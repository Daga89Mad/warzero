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
import 'services/trofeos_service.dart';
import 'widgets/trofeo_conseguido_overlay.dart';

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

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  final FirebaseCrudService _svc = FirebaseCrudService();
  final TrofeosService _trofeos = TrofeosService();
  StreamSubscription<User?>? _sub;

  bool _cargando = true;
  bool _reconectando = false;
  User? _user;

  /// Evita que dos drenajes se solapen (p. ej. un `resumed` que llega mientras
  /// el pop-up del arranque está abierto). La cola vive en el servidor y la
  /// petición la CONSUME, así que dos llamadas simultáneas podrían perder avisos.
  bool _drenandoTrofeos = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

    // TROFEOS: repesca de los avisos que quedaron pendientes desde la última
    // sesión (turnos que resolvió OTRO jugador, resoluciones forzosas por fecha
    // límite, o la red de seguridad del perfil).
    //
    // Va en un post-frame callback porque en este punto el menú todavía no está
    // montado: el pop-up necesita un Navigator vivo debajo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drenarTrofeosPendientes();
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Al volver del fondo: puede que mientras la app estaba dormida otro jugador
    // haya resuelto un turno en el que ganamos un trofeo.
    if (state == AppLifecycleState.resumed) _drenarTrofeosPendientes();
  }

  /// Pide al servidor los avisos de trofeo pendientes y los muestra.
  ///
  /// Solo se ejecuta cuando el jugador está EN EL MENÚ (`canPop() == false`): si
  /// está dentro de una partida o de cualquier pantalla más profunda, el pop-up
  /// caería encima de lo que esté haciendo, y además los trofeos de SU propia
  /// jugada ya le llegan por la respuesta de cerrar turno. Lo que quede en la
  /// cola esperará al siguiente arranque o al siguiente regreso del fondo.
  ///
  /// Best-effort: si falla, ni molesta ni rompe el arranque.
  Future<void> _drenarTrofeosPendientes() async {
    if (!mounted || _drenandoTrofeos) return;
    final uid = _user?.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final nav = navigatorKey.currentState;
    if (nav == null || nav.canPop()) {
      debugPrint('[WZ][trofeos] repesca aplazada: no estamos en el menú');
      return;
    }

    _drenandoTrofeos = true;
    try {
      final pendientes = await _trofeos.pendientes(uid);
      if (pendientes.isEmpty) return;

      // El contexto del propio Navigator raíz: sirve aunque _AuthGate se haya
      // reconstruido entre la petición y la respuesta.
      final ctx = navigatorKey.currentContext;
      if (!mounted || ctx == null) {
        debugPrint('[WZ][trofeos] ${pendientes.length} aviso(s) descartado(s): '
            'sin contexto para mostrarlos');
        return;
      }
      await mostrarTrofeosConseguidos(ctx, pendientes);
    } catch (e) {
      debugPrint('[WZ][trofeos] repesca falló: $e');
    } finally {
      _drenandoTrofeos = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
