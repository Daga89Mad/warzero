// lib/main.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/firebaseCrudService.dart';
import 'firebase_options.dart'; // ← generado por: flutterfire configure
import 'services/api_auth_client.dart';
import 'services/notificaciones_service.dart';
import 'package:warzero/services/settings_controller.dart';
import 'views/loginBody.dart';
import 'views/menu.dart';

/// Clave global del navegador: permite navegar desde fuera del árbol de widgets
/// (p. ej. al pulsar una notificación push).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // En RELEASE no se escribe nada en la consola del dispositivo: los logs
  // incluyen uids, ids de partida y respuestas del servidor, y en iOS/Android
  // cualquiera con el móvil conectado a un ordenador puede leerlos. El panel
  // interno de DebugLog (appLog) sigue funcionando porque guarda en memoria.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Todas las llamadas http.get/post de la app pasan por ApiAuthClient, que
  // añade el ID token de Firebase a las peticiones de nuestro backend. Todo el
  // arranque va DENTRO de la zona para que runApp y ensureInitialized
  // compartan zona (Flutter avisa si no).
  http.runWithClient(_arrancar, ApiAuthClient.fabrica);
}

Future<void> _arrancar() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    runApp(_ErrorApp(message: 'Error al inicializar Firebase:\n$e'));
    return;
  }

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 20 * 1024 * 1024, // 20 MB. NUNCA CACHE_SIZE_UNLIMITED.
  );

  // ── Notificaciones push (turno resuelto → "ya puedes jugar") ──────────────
  // Handler de mensajes en background/app terminada (debe registrarse antes de
  // runApp y ser una función top-level).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Qué hacer al pulsar la notificación. Llevamos al jugador a la pantalla
  // principal (lista de partidas), desde donde entra a la que toca. Si más
  // adelante se quiere deep-link directo a la sala concreta, aquí está el
  // lobbyId disponible para construir RoomScreen/GameScreen.
  NotificacionesService.instance.onAbrirPartida = (lobbyId) {
    debugPrint('[WZ][push] abrir partida $lobbyId');
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
  };

  // Se inicializa en segundo plano para no bloquear el arranque de la UI.
  // (Pide permisos, obtiene el token FCM y lo registra en el backend.)
  NotificacionesService.instance.iniciar();

  // Cargar ajustes persistidos (tema + escala de texto) antes de arrancar la UI.
  await settingsController.cargar();

  runApp(const WarZeroApp());
}

// ─── App principal ──────────────────────────────────────────
class WarZeroApp extends StatelessWidget {
  const WarZeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Se reconstruye cuando cambian el tema o la escala de texto.
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'WarZero',
          debugShowCheckedModeBanner: false,
          theme: settingsController.tema.construir(),
          // Escala de texto GLOBAL: afecta a todos los Text de la app.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(settingsController.escala),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const _AuthGate(),
        );
      },
    );
  }
}

// ─── Auth gate ───────────────────────────────────────────────
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final FirebaseCrudService _svc = FirebaseCrudService();
  StreamSubscription<User?>? _sub;

  bool _cargando = true;
  bool _reconectando = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  /// 1) Espera el PRIMER estado real de Firebase Auth (la restauración de la
  ///    sesión guardada en el dispositivo). Antes se usaba Stream.timeout,
  ///    que en arranques lentos emitía `null` y mandaba al login aunque la
  ///    sesión fuese válida.
  /// 2) Si no hay sesión, intenta la reconexión silenciosa con "Recuérdame".
  /// 3) Después escucha cambios para reaccionar a revocaciones en caliente.
  Future<void> _arrancar() async {
    User? user;
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }

    user ??= await _svc.reloginSilencioso();

    if (!mounted) return;
    setState(() {
      _user = user;
      _cargando = false;
    });

    _sub = FirebaseAuth.instance.authStateChanges().listen(_onAuthCambio);
  }

  Future<void> _onAuthCambio(User? u) async {
    if (!mounted) return;

    if (u != null) {
      if (u.uid != _user?.uid) setState(() => _user = u);
      return;
    }

    // u == null: la sesión se ha perdido estando dentro.
    if (_user == null || _reconectando) return;
    _reconectando = true;
    // Si fue cierre manual, reloginSilencioso devuelve null al instante.
    final recuperado = await _svc.reloginSilencioso();
    _reconectando = false;
    if (!mounted) return;
    setState(() => _user = recuperado);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const _SplashScreen();
    if (_user == null) return const LoginBody();
    return const MenuScreen();
  }
}

// ─── Splash ──────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'WARZERO',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                fontFamily: 'Cinzel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pantalla de error de inicio ─────────────────────────────
class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF030810),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFC04040), size: 48),
                const SizedBox(height: 20),
                const Text(
                  'ERROR DE INICIO',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 16,
                    color: Color(0xFFC04040),
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A6060),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
