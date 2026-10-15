// lib/services/torneos_service.dart
//
// Cliente HTTP del MODO TORNEO (Fenrir · WarZeroTorneos.cs).
// Todas las peticiones van con el ID token de Firebase. Las rutas /admin/*
// exigen además el claim editor=true en el servidor; si llega un 403 se
// renueva el token una vez (por si el claim se acaba de asignar).

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:warzero/models/torneo_model.dart';

class TorneosService {
  TorneosService({this.baseUrl = _defaultBaseUrl});

  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';

  /// Render puede tardar en despertar el servicio: margen amplio.
  static const Duration _timeout = Duration(seconds: 60);

  final String baseUrl;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ───────────────────────────────────────────────────────────
  // JUGADOR
  // ───────────────────────────────────────────────────────────

  /// Torneo vigente (o [TorneoVigente.ninguno]). Nunca lanza: si falla la red
  /// devuelve "ninguno" para que el botón quede deshabilitado.
  Future<TorneoVigente> vigente() async {
    try {
      final res = await _enviar(
        (h) => http.get(Uri.parse('$baseUrl/warzero/torneos/vigente'), headers: h),
        etiqueta: 'vigente',
      );
      return TorneoVigente.fromJson(_jsonOk(res));
    } catch (e) {
      debugPrint('[WZ][torneos] vigente error: $e');
      return TorneoVigente.ninguno;
    }
  }

  Future<int> inscribir(String torneoId) async {
    final res = await _enviar(
      (h) => http.post(Uri.parse('$baseUrl/warzero/torneos/$torneoId/inscribir'),
          headers: h),
      etiqueta: 'inscribir',
    );
    return (_jsonOk(res)['inscritos'] as num?)?.toInt() ?? 0;
  }

  Future<int> desinscribir(String torneoId) async {
    final res = await _enviar(
      (h) => http.post(
          Uri.parse('$baseUrl/warzero/torneos/$torneoId/desinscribir'),
          headers: h),
      etiqueta: 'desinscribir',
    );
    return (_jsonOk(res)['inscritos'] as num?)?.toInt() ?? 0;
  }

  Future<List<GrupoTorneo>> grupos(String torneoId, {int? ronda}) async {
    final q = ronda != null ? '?ronda=$ronda' : '';
    final res = await _enviar(
      (h) => http.get(Uri.parse('$baseUrl/warzero/torneos/$torneoId/grupos$q'),
          headers: h),
      etiqueta: 'grupos',
    );
    return _grupos(_jsonOk(res));
  }

  // ───────────────────────────────────────────────────────────
  // EDITOR
  // ───────────────────────────────────────────────────────────

  Future<List<TorneoVigente>> listarAdmin() async {
    final res = await _enviar(
      (h) => http.get(Uri.parse('$baseUrl/admin/torneos'), headers: h),
      etiqueta: 'admin/listar',
    );
    final lista = ((_jsonOk(res)['torneos'] as List?) ?? [])
        .map((e) => TorneoVigente.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    lista.sort((a, b) => (b.torneo?.inicioTorneo ?? DateTime(0))
        .compareTo(a.torneo?.inicioTorneo ?? DateTime(0)));
    return lista;
  }

  Future<TorneoModel> guardar(TorneoModel t) async {
    final res = await _enviar(
      (h) => http.post(Uri.parse('$baseUrl/admin/torneos'),
          headers: h, body: jsonEncode(t.toJson())),
      etiqueta: 'admin/guardar',
    );
    return TorneoModel.fromJson(
        Map<String, dynamic>.from(_jsonOk(res)['torneo'] as Map));
  }

  Future<void> borrar(String id) async {
    final res = await _enviar(
      (h) => http.delete(Uri.parse('$baseUrl/admin/torneos/$id'), headers: h),
      etiqueta: 'admin/borrar',
    );
    _jsonOk(res);
  }

  Future<List<InscritoTorneo>> inscritos(String id) async {
    final res = await _enviar(
      (h) => http.get(Uri.parse('$baseUrl/admin/torneos/$id/inscritos'),
          headers: h),
      etiqueta: 'admin/inscritos',
    );
    return ((_jsonOk(res)['inscritos'] as List?) ?? [])
        .map((e) => InscritoTorneo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Sortea grupos aleatorios para [ronda]. Con [forzar] se permite aunque la
  /// inscripción siga abierta.
  Future<List<GrupoTorneo>> sortear(String id,
      {int ronda = 1, bool forzar = false}) async {
    final res = await _enviar(
      (h) => http.post(Uri.parse('$baseUrl/admin/torneos/$id/sortear'),
          headers: h, body: jsonEncode({'ronda': ronda, 'forzar': forzar})),
      etiqueta: 'admin/sortear',
    );
    return _grupos(_jsonOk(res));
  }

  /// Premios ya repartidos (tras finalizar el torneo).
  Future<List<PremiadoTorneo>> premiados(String id) async {
    final res = await _enviar(
      (h) => http.get(Uri.parse('$baseUrl/admin/torneos/$id/premiados'),
          headers: h),
      etiqueta: 'admin/premiados',
    );
    return ((_jsonOk(res)['premiados'] as List?) ?? [])
        .map((e) => PremiadoTorneo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Marca como entregado (o no) el premio de fuera de la app de [uid].
  Future<void> marcarExterno(String id, String uid, bool entregado) async {
    final res = await _enviar(
      (h) => http.post(
          Uri.parse('$baseUrl/admin/torneos/$id/premiados/$uid/externo'),
          headers: h,
          body: jsonEncode({'entregado': entregado})),
      etiqueta: 'admin/externo',
    );
    _jsonOk(res);
  }

  // ───────────────────────────────────────────────────────────
  // INTERNOS
  // ───────────────────────────────────────────────────────────

  List<GrupoTorneo> _grupos(Map<String, dynamic> j) =>
      ((j['grupos'] as List?) ?? [])
          .map((e) => GrupoTorneo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

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

  Future<http.Response> _enviar(
    Future<http.Response> Function(Map<String, String> headers) peticion, {
    required String etiqueta,
  }) async {
    try {
      var res = await peticion(await _headers()).timeout(_timeout);
      if (res.statusCode == 403) {
        res = await peticion(await _headers(forzarToken: true)).timeout(_timeout);
      }
      debugPrint('[WZ][torneos] $etiqueta status=${res.statusCode}');
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
        throw Exception('Sesión no válida. Vuelve a iniciar sesión.');
      case 403:
        throw Exception('Tu cuenta no tiene permisos de editor en el servidor.');
      case 404:
        throw Exception(j?['error']?.toString() ?? 'No encontrado.');
      default:
        throw Exception(j?['error']?.toString() ??
            j?['detail']?.toString() ??
            'Error del servidor (${res.statusCode}).');
    }
  }
}
