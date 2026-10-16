// lib/services/admin_bots_service.dart
//
// Cliente de los endpoints de ADMINISTRACIÓN DE BOTS del backend
// (WarZeroBotsAdmin.cs). Solo lo usan los editores desde EdicionBotsScreen.
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

/// Resultado de mandar un bot a una partida pública.
class EnvioBotResult {
  final String alias;

  /// Partidas en las que está el bot tras el envío (incluida la nueva).
  final int partidasActivas;
  final int maxPartidas;

  const EnvioBotResult({
    required this.alias,
    required this.partidasActivas,
    required this.maxPartidas,
  });

  factory EnvioBotResult.fromJson(Map<String, dynamic> j) => EnvioBotResult(
        alias: j['alias']?.toString() ?? '',
        partidasActivas: (j['partidasActivas'] as num?)?.toInt() ?? 0,
        maxPartidas: (j['maxPartidas'] as num?)?.toInt() ?? 0,
      );
}

class AdminBotsService {
  AdminBotsService({this.baseUrl = _defaultBaseUrl});

  /// Mismo backend que WarZeroApi.
  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';

  /// Render puede tardar en despertar el servicio: margen amplio.
  static const Duration _timeout = Duration(seconds: 60);

  final String baseUrl;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ───────────────────────────────────────────────────────────
  // API PÚBLICA
  // ───────────────────────────────────────────────────────────

  /// Manda el bot [botUid] a la partida pública [lobbyId] para que ocupe un
  /// hueco. El servidor valida que la sala siga en espera, sea pública, tenga
  /// hueco y algún humano, y que el bot no esté ya dentro. Lanza una
  /// excepción con el motivo si no se puede.
  Future<EnvioBotResult> enviarBotAPartida({
    required String botUid,
    required String lobbyId,
  }) async {
    final res = await _enviar(
      (headers) => http.post(
        Uri.parse('$baseUrl/admin/bots/enviar'),
        headers: headers,
        body: jsonEncode({'botUid': botUid, 'lobbyId': lobbyId}),
      ),
      etiqueta: 'bots/enviar',
    );
    return EnvioBotResult.fromJson(_jsonOk(res));
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
        debugPrint('[WZ][admin-bots] $etiqueta 403 → renovando token');
        res =
            await peticion(await _headers(forzarToken: true)).timeout(_timeout);
      }
      debugPrint('[WZ][admin-bots] $etiqueta status=${res.statusCode}');
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
