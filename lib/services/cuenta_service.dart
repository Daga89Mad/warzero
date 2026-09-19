// lib/services/cuenta_service.dart
//
// Operaciones sobre la PROPIA cuenta del jugador:
//
//   · Enlace a la política de privacidad (obligatorio en App Store Connect y
//     accesible dentro de la app: Guideline 5.1.1(i)).
//   · Borrado de la cuenta desde la app (Guideline 5.1.1(v) y derecho de
//     supresión del RGPD).
//
// El borrado:
//   1. Reautentica con la contraseña (Firebase y el servidor exigen un
//      inicio de sesión reciente para una operación irreversible).
//   2. Llama a POST /warzero/cuenta/eliminar, que borra los datos de Firestore
//      y el usuario de Authentication. El ID token lo añade ApiAuthClient.
//   3. Limpia TODO lo guardado en el dispositivo ("Recuérdame", contraseña en
//      el llavero, token FCM) y cierra la sesión local.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CuentaService {
  CuentaService({this.baseUrl = _defaultBaseUrl});

  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';
  final String baseUrl;

  /// TODO: sustituir por la URL pública real de la política de privacidad
  /// (la misma que se indica en App Store Connect). Recomendado tenerla en
  /// español y en francés si se distribuye en Francia.
  static const String urlPoliticaPrivacidad =
      'https://example.com/warzero/privacidad';

  /// TODO: correo de contacto para ejercer derechos RGPD.
  static const String emailPrivacidad = 'privacidad@example.com';

  // Mismas claves que FirebaseCrudService y LoginBody.
  static const String _kRememberMe = 'remember_me';
  static const String _kSavedEmail = 'saved_email';
  static const String _kSavedPass = 'saved_pass';
  static const String _kLogoutManual = 'logout_manual';
  static const String _kEmailPendiente = 'email_pendiente';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ── Política de privacidad ──────────────────────────────────────────────
  Future<bool> abrirPoliticaPrivacidad() async {
    try {
      return await launchUrl(
        Uri.parse(urlPoliticaPrivacidad),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[WZ][cuenta] no se pudo abrir la política: $e');
      return false;
    }
  }

  // ── Borrado de cuenta ───────────────────────────────────────────────────
  /// Lanza [Exception] con un mensaje apto para mostrar al usuario.
  Future<void> eliminarCuenta({required String password}) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw Exception('No hay ninguna sesión iniciada.');
    }
    if (password.isEmpty) {
      throw Exception('Introduce tu contraseña para confirmar.');
    }

    // 1) Reautenticación.
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      // Token nuevo con auth_time actualizado (el servidor lo comprueba).
      await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('La contraseña no es correcta.');
        case 'too-many-requests':
          throw Exception('Demasiados intentos. Espera unos minutos.');
        case 'network-request-failed':
          throw Exception('Sin conexión. Revisa tu red.');
        default:
          throw Exception('No se pudo verificar tu identidad.');
      }
    }

    // 2) Borrado en el servidor.
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$baseUrl/warzero/cuenta/eliminar'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'confirmacion': 'ELIMINAR'}),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw Exception('El servidor no responde. Inténtalo de nuevo.');
    } catch (_) {
      throw Exception('Sin conexión con el servidor.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String mensaje = 'No se pudo eliminar la cuenta (${res.statusCode}).';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['error'] is String) mensaje = j['error'] as String;
        if (j is Map && j['title'] is String) mensaje = j['title'] as String;
      } catch (_) {}
      throw Exception(mensaje);
    }

    // 3) Limpieza local (la cuenta ya no existe: nada de esto debe fallar
    //    hacia el usuario).
    await limpiarDatosLocales();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  /// Borra credenciales y preferencias de sesión guardadas en el dispositivo.
  /// Importante en iOS: los elementos del llavero SOBREVIVEN a la
  /// desinstalación de la app.
  Future<void> limpiarDatosLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLogoutManual, true);
      await prefs.remove(_kRememberMe);
      await prefs.remove(_kSavedEmail);
      await prefs.remove(_kEmailPendiente);
    } catch (e) {
      debugPrint('[WZ][cuenta] limpiar prefs: $e');
    }
    try {
      await _secureStorage.delete(key: _kSavedPass);
    } catch (e) {
      debugPrint('[WZ][cuenta] limpiar llavero: $e');
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[WZ][cuenta] borrar token FCM: $e');
    }
  }
}
