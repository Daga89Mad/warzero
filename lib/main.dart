// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:warzero/services/settings_controller.dart';
import 'firebase_options.dart'; // ← generado por: flutterfire configure
import 'views/loginBody.dart';
import 'views/menu.dart';
import 'services/settings_controller.dart';

void main() async {
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        if (snapshot.hasError) {
          return const LoginBody();
        }
        if (snapshot.data == null) {
          return const LoginBody();
        }
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
