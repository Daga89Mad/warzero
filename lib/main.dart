// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'views/loginBody.dart';
import 'views/menu.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Activar persistencia offline de Firestore:
  // los documentos se cachean localmente y la app funciona
  // aunque la conexión inicial tarde (emuladores lentos).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const WarZeroApp());
}

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
      // ── Auth gate: show login or game depending on session ──
      home: const _AuthGate(),
    );
  }
}

/// Listens to Firebase auth state and routes accordingly.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still checking
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        final user = snapshot.data;

        // Not logged in → show login
        if (user == null) {
          return const LoginBody();
        }

        // Logged in → go to menu
        return const MenuScreen();
      },
    );
  }
}

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
