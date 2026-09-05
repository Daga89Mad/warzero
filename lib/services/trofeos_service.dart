// lib/services/trofeos_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trofeo_model.dart';

/// Resultado de consultar los trofeos de un jugador.
class TrofeosResult {
  final List<TrofeoModel> trofeos;
  final int total;
  final int conseguidos;
  final int porcentaje; // 0-100

  /// Id del trofeo que el jugador ha elegido destacar junto a su alias
  /// (vacío = ninguno). El servidor ya valida que esté conseguido y activo.
  final String destacadoId;

  const TrofeosResult({
    required this.trofeos,
    required this.total,
    required this.conseguidos,
    required this.porcentaje,
    this.destacadoId = '',
  });

  static const empty = TrofeosResult(
      trofeos: [], total: 0, conseguidos: 0, porcentaje: 0, destacadoId: '');

  /// Trofeo destacado resuelto (icono + nombre) o null si no hay o no es válido.
  TrofeoModel? get destacado {
    if (destacadoId.isEmpty) return null;
    for (final t in trofeos) {
      if (t.id == destacadoId && t.conseguido) return t;
    }
    return null;
  }

  /// Copia con un nuevo id destacado (para actualizar el estado tras elegir).
  TrofeosResult copyWith({String? destacadoId}) => TrofeosResult(
        trofeos: trofeos,
        total: total,
        conseguidos: conseguidos,
        porcentaje: porcentaje,
        destacadoId: destacadoId ?? this.destacadoId,
      );

  /// Trofeos conseguidos (para el selector de destacado).
  List<TrofeoModel> get logrados =>
      trofeos.where((t) => t.conseguido).toList(growable: false);
}

/// Cliente HTTP mínimo para el sistema de trofeos. Es independiente de
/// `WarZeroApi` (mismo backend/base URL) para no acoplar esta feature al cliente
/// grande. Best-effort: en caso de error devuelve un resultado vacío en lugar de
/// romper el perfil.
class TrofeosService {
  TrofeosService({this.baseUrl = _defaultBaseUrl});

  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';
  final String baseUrl;

  static const Duration _timeout = Duration(seconds: 30);
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  /// Devuelve los trofeos de [uid] (catálogo activo + estado conseguido + %).
  /// Vale para el perfil propio y para el PÚBLICO: el servidor lee con
  /// credenciales de admin, así que puede resolver el doc de cualquier jugador.
  Future<TrofeosResult> obtener(String uid) async {
    if (uid.isEmpty) return TrofeosResult.empty;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/warzero/trofeos?uid=$uid'),
              headers: _headers)
          .timeout(_timeout);
      debugPrint('[WZ][trofeos] GET status=${res.statusCode}');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return TrofeosResult.empty;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['existe'] != true) return TrofeosResult.empty;

      final lista = (j['trofeos'] as List? ?? const [])
          .map((e) => TrofeoModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) {
          final o = a.orden.compareTo(b.orden);
          return o != 0 ? o : a.nombre.compareTo(b.nombre);
        });

      return TrofeosResult(
        trofeos: lista,
        total: (j['total'] as num?)?.toInt() ?? lista.length,
        conseguidos: (j['conseguidos'] as num?)?.toInt() ??
            lista.where((t) => t.conseguido).length,
        porcentaje: (j['porcentaje'] as num?)?.toInt() ?? 0,
        destacadoId: (j['destacado'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[WZ][trofeos] obtener falló: $e');
      return TrofeosResult.empty;
    }
  }

  /// Trofeo destacado (icono + nombre) de VARIOS jugadores de una vez. Para la
  /// sala de espera / listados: una sola petición para todos los uids. Devuelve
  /// un mapa uid → TrofeoModel (solo los que tengan un destacado válido).
  Future<Map<String, TrofeoModel>> obtenerDestacados(List<String> uids) async {
    final ids = uids.where((s) => s.isNotEmpty).toSet().join(',');
    if (ids.isEmpty) return {};
    try {
      final res = await http
          .get(
              Uri.parse(
                  '$baseUrl/warzero/trofeos-destacados?uids=${Uri.encodeQueryComponent(ids)}'),
              headers: _headers)
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return {};
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final map = (j['destacados'] as Map?) ?? const {};
      final out = <String, TrofeoModel>{};
      map.forEach((k, v) {
        final m = Map<String, dynamic>.from(v as Map);
        if ((m['id'] ?? '').toString().isNotEmpty) {
          m['conseguido'] = true; // ya viene validado por el servidor
          out[k.toString()] = TrofeoModel.fromMap(m);
        }
      });
      return out;
    } catch (e) {
      debugPrint('[WZ][trofeos] obtenerDestacados falló: $e');
      return {};
    }
  }
}
