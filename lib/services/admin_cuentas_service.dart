// lib/services/admin_cuentas_service.dart
//
// Cliente de los endpoints de ADMINISTRACIÓN DE CUENTAS del backend
// (WarZeroAdminCuentas.cs). Solo lo usan los editores.
//
// Cada petición envía el ID token de Firebase del editor en
//   Authorization: Bearer <token>
// y el servidor exige el custom claim editor=true. Si el servidor responde 403,
// se fuerza la renovación del token una vez (por si el claim se asignó después
// de iniciar sesión) y se reintenta.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cuenta devuelta por la búsqueda de administración.
class CuentaAdmin {
  final String uid;
  final String email;
  final String alias;
  final bool emailVerificado;
  final bool deshabilitada;
  final bool esEditor;
  final DateTime? creada;
  final DateTime? ultimoAcceso;

  const CuentaAdmin({
    required this.uid,
    required this.email,
    required this.alias,
    required this.emailVerificado,
    required this.deshabilitada,
    required this.esEditor,
    this.creada,
    this.ultimoAcceso,
  });

  factory CuentaAdmin.fromJson(Map<String, dynamic> j) => CuentaAdmin(
        uid: j['uid']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        alias: j['alias']?.toString() ?? '',
        emailVerificado: j['emailVerificado'] == true,
        deshabilitada: j['deshabilitada'] == true,
        esEditor: j['esEditor'] == true,
        creada: DateTime.tryParse(j['creada']?.toString() ?? '')?.toLocal(),
        ultimoAcceso:
            DateTime.tryParse(j['ultimoAcceso']?.toString() ?? '')?.toLocal(),
      );
}

/// Resultado de un cambio de correo hecho por un editor.
class CambioEmailAdminResult {
  final String uid;
  final String emailAnterior;
  final String emailNuevo;
  final bool sesionesCerradas;

  const CambioEmailAdminResult({
    required this.uid,
    required this.emailAnterior,
    required this.emailNuevo,
    required this.sesionesCerradas,
  });

  factory CambioEmailAdminResult.fromJson(Map<String, dynamic> j) =>
      CambioEmailAdminResult(
        uid: j['uid']?.toString() ?? '',
        emailAnterior: j['emailAnterior']?.toString() ?? '',
        emailNuevo: j['emailNuevo']?.toString() ?? '',
        sesionesCerradas: j['sesionesCerradas'] == true,
      );
}

/// Resultado de enviar una carta a un jugador.
class EnvioCartaResult {
  final String uid;
  final String email;
  final String alias;
  final String nombreCarta;

  /// true si el jugador no tenía la carta.
  final bool nueva;
  final int cantidadAnterior;
  final int cantidadNueva;

  const EnvioCartaResult({
    required this.uid,
    required this.email,
    required this.alias,
    required this.nombreCarta,
    required this.nueva,
    required this.cantidadAnterior,
    required this.cantidadNueva,
  });

  factory EnvioCartaResult.fromJson(Map<String, dynamic> j) => EnvioCartaResult(
        uid: j['uid']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        alias: j['alias']?.toString() ?? '',
        nombreCarta: j['nombreCarta']?.toString() ?? '',
        nueva: j['nueva'] == true,
        cantidadAnterior: (j['cantidadAnterior'] as num?)?.toInt() ?? 0,
        cantidadNueva: (j['cantidadNueva'] as num?)?.toInt() ?? 0,
      );
}

class AdminCuentasService {
  AdminCuentasService({this.baseUrl = _defaultBaseUrl});

  /// Mismo backend que WarZeroApi.
  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';

  /// Render puede tardar en despertar el servicio: margen amplio.
  static const Duration _timeout = Duration(seconds: 60);

  final String baseUrl;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ───────────────────────────────────────────────────────────
  // API PÚBLICA
  // ───────────────────────────────────────────────────────────

  /// Busca cuentas por correo exacto, UID o alias exacto.
  Future<List<CuentaAdmin>> buscar(String texto) async {
    final q = Uri.encodeQueryComponent(texto.trim());
    final res = await _enviar(
      (headers) => http.get(
        Uri.parse('$baseUrl/admin/cuentas/buscar?q=$q'),
        headers: headers,
      ),
      etiqueta: 'buscar',
    );
    final j = _jsonOk(res);
    return ((j['cuentas'] as List?) ?? [])
        .map((e) => CuentaAdmin.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Cambia el correo de login de otra cuenta. Es inmediato y sin
  /// verificación: por eso exige [motivo] y queda auditado en el servidor.
  Future<CambioEmailAdminResult> cambiarEmail({
    required String uid,
    required String nuevoEmail,
    required String motivo,
    bool cerrarSesiones = true,
  }) async {
    final res = await _enviar(
      (headers) => http.post(
        Uri.parse('$baseUrl/admin/cuentas/cambiar-email'),
        headers: headers,
        body: jsonEncode({
          'uid': uid,
          'nuevoEmail': nuevoEmail.trim(),
          'motivo': motivo.trim(),
          'cerrarSesiones': cerrarSesiones,
        }),
      ),
      etiqueta: 'cambiar-email',
    );
    return CambioEmailAdminResult.fromJson(_jsonOk(res));
  }

  /// Envía [cantidad] copias de la carta [cartaId] al jugador cuyo correo de
  /// login es [email]. Si ya la tenía, se suman a las que tuviera.
  Future<EnvioCartaResult> enviarCarta({
    required String email,
    required String cartaId,
    int cantidad = 1,
    String? motivo,
  }) async {
    final res = await _enviar(
      (headers) => http.post(
        Uri.parse('$baseUrl/admin/cartas/enviar'),
        headers: headers,
        body: jsonEncode({
          'email': email.trim(),
          'cartaId': cartaId,
          'cantidad': cantidad,
          'motivo': motivo?.trim() ?? '',
        }),
      ),
      etiqueta: 'cartas/enviar',
    );
    return EnvioCartaResult.fromJson(_jsonOk(res));
  }

  // ───────────────────────────────────────────────────────────
  // INTERNOS
  // ───────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers({bool forzarToken = false}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay un usuario autenticado.');
    final token = await user.getIdToken(forzarToken);
    if (token == null || token.isEmpty) {
      throw Exception('No se pudo obtener el token de sesión.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Envía la petición; si recibe 403, renueva el token (para recoger un
  /// claim recién asignado) y reintenta una sola vez.
  Future<http.Response> _enviar(
    Future<http.Response> Function(Map<String, String> headers) peticion, {
    required String etiqueta,
  }) async {
    try {
      var res = await peticion(await _headers()).timeout(_timeout);
      if (res.statusCode == 403) {
        debugPrint('[WZ][admin] $etiqueta 403 → renovando token');
        res =
            await peticion(await _headers(forzarToken: true)).timeout(_timeout);
      }
      debugPrint('[WZ][admin] $etiqueta status=${res.statusCode}');
      return res;
    } on TimeoutException {
      throw Exception(
          'El servidor no responde. Puede estar arrancando: prueba de nuevo en un momento.');
    }
  }

  Map<String, dynamic> _jsonOk(http.Response res) {
    Map<String, dynamic>? j;
    try {
      final d = jsonDecode(res.body);
      if (d is Map) j = Map<String, dynamic>.from(d);
    } catch (_) {}

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return j ?? <String, dynamic>{};
    }

    switch (res.statusCode) {
      case 401:
        throw Exception('Sesión no válida. Cierra sesión y vuelve a entrar.');
      case 403:
        throw Exception(
            'Tu cuenta no tiene permiso de editor en el servidor (falta el claim "editor").');
      default:
        final msg = j?['error'] ?? j?['detail'] ?? j?['title'];
        throw Exception(
            msg?.toString() ?? 'Error del servidor (${res.statusCode}).');
    }
  }
}
