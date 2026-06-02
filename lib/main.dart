// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // ← generado por: flutterfire configure
import 'views/loginBody.dart';
import 'views/menu.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase con opciones explícitas para cada plataforma.
  // Esto evita que iOS falle silenciosamente si el GoogleService-Info.plist
  // no está correctamente embebido en el target de Xcode.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Si Firebase no arranca, mostramos una pantalla de error
    // en lugar de quedarnos en blanco.
    runApp(_ErrorApp(message: 'Error al inicializar Firebase:\n$e'));
    return;
  }

  // ── Configuración de Firestore ─────────────────────────────
  //
  // Persistencia ACTIVADA (las escrituras se confirman en local al instante, lo
  // que hace que cerrar turno sea rápido aunque la red esté lenta), pero con la
  // caché LIMITADA a 20 MB. La clave del problema anterior era
  // cacheSizeBytes:UNLIMITED, que desactiva la limpieza y deja crecer la caché
  // hasta degradar las lecturas. Con un límite, el recolector de basura mantiene
  // la caché pequeña y no se degrada. Este es el equilibrio recomendado:
  // escrituras rápidas (offline-tolerant) + lecturas que no se ralentizan.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 20 * 1024 * 1024, // 20 MB. NUNCA CACHE_SIZE_UNLIMITED.
  );

  runApp(const WarZeroApp());
}

// ─── App principal ──────────────────────────────────────────
class WarZeroApp extends StatelessWidget {
  const WarZeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WarZero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030810),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC8A860),
          secondary: Color(0xFF4ABB58),
          surface: Color(0xFF0A1220),
          error: Color(0xFFC04040),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFC8C0A8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(color: Color(0xFF7A6040)),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0x503A2800)),
            borderRadius: BorderRadius.circular(6),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xFFC8A860), width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          filled: true,
          fillColor: const Color(0xFF0A1220),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1208),
            foregroundColor: const Color(0xFFC8A860),
            side: const BorderSide(color: Color(0xFF7A5A18), width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFFC8A860)
                : Colors.transparent,
          ),
          checkColor: WidgetStateProperty.all(const Color(0xFF030810)),
          side: const BorderSide(color: Color(0xFF7A5A18)),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

// ─── Auth gate ───────────────────────────────────────────────
/// Escucha el estado de autenticación con un timeout de 8 segundos.
/// Si Firebase tarda más (o se cuelga), redirige al login directamente.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  // Stream cacheado: se crea UNA sola vez. Si se crea en build() (como antes),
  // cada reconstrucción abre una suscripción nueva a authStateChanges, lo que
  // contribuye a saturar la conexión a Firebase.
  late final Stream<User?> _authStream =
      FirebaseAuth.instance.authStateChanges().timeout(
            const Duration(seconds: 8),
            onTimeout: (sink) => sink.add(FirebaseAuth.instance.currentUser),
          );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        // Cargando → splash
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        // Error de stream → ir al login igualmente
        if (snapshot.hasError) {
          return const LoginBody();
        }

        // No logueado → login
        if (snapshot.data == null) {
          return const LoginBody();
        }

        // Logueado → menú
        return const MenuScreen();
      },
    );
  }
}

// ─── Splash ──────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF030810),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFC8A860)),
            SizedBox(height: 20),
            Text(
              'WARZERO',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC8A860),
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
/// Solo aparece si Firebase.initializeApp() lanza una excepción.
/// Muestra el mensaje en lugar de dejar la pantalla en blanco.
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
