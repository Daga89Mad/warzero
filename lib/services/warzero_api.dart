// lib/services/warzero_api.dart

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/accion_pendiente.dart';

/// Resultado de cerrar un turno a través de la API.
class CerrarTurnoResult {
  /// True si esta llamada cerró al último jugador y el servidor resolvió el turno.
  final bool resuelto;

  /// Turno vigente tras la operación (incrementado si [resuelto] es true).
  final int turnoActual;

  final int cerradoPor;
  final int jugadoresActivos;
  final int faltan;

  final bool finalizada;
  final String? ganadorUid;

  /// Conquistas de cuartel ocurridas en esta resolución.
  final List<Map<String, dynamic>> conquistas;

  /// Energies ganadas por jugador (combate + farmeo).
  final Map<String, int> energiesPorJugador;

  final String mensaje;

  const CerrarTurnoResult({
    required this.resuelto,
    required this.turnoActual,
    required this.cerradoPor,
    required this.jugadoresActivos,
    required this.faltan,
    required this.finalizada,
    required this.ganadorUid,
    required this.conquistas,
    required this.energiesPorJugador,
    required this.mensaje,
  });

  factory CerrarTurnoResult.fromJson(Map<String, dynamic> j) {
    final energiesRaw = (j['energiesPorJugador'] as Map?) ?? {};
    return CerrarTurnoResult(
      resuelto: j['resuelto'] == true,
      turnoActual: (j['turnoActual'] as num?)?.toInt() ?? 0,
      cerradoPor: (j['cerradoPor'] as num?)?.toInt() ?? 0,
      jugadoresActivos: (j['jugadoresActivos'] as num?)?.toInt() ?? 0,
      faltan: (j['faltan'] as num?)?.toInt() ?? 0,
      finalizada: j['finalizada'] == true,
      ganadorUid: j['ganadorUid'] as String?,
      conquistas: ((j['conquistas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      energiesPorJugador: energiesRaw.map(
        (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
      ),
      mensaje: j['mensaje'] as String? ?? '',
    );
  }
}

/// Cliente de la API Fenrir / WarZero.
class WarZeroApi {
  WarZeroApi({this.baseUrl = _defaultBaseUrl, this.token});

  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';

  final String baseUrl;

  /// JWT opcional (Bearer). Si la API exige autenticación, asígnalo.
  final String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

  /// Cierra el turno del jugador. El servidor resuelve el turno cuando han
  /// cerrado todos los jugadores activos.
  Future<CerrarTurnoResult> cerrarTurno({
    required String lobbyId,
    required String uid,
    required int turno,
    required Map<String, List<Map<String, dynamic>>> celdas,
    List<AccionPendiente> acciones = const [],
  }) async {
    final body = jsonEncode({
      'lobbyId': lobbyId,
      'uid': uid,
      'turno': turno,
      'celdas': _jsonSafe(celdas),
      'acciones': acciones.map((a) => _jsonSafe(a.toMap())).toList(),
    });

    final res = await http
        .post(
          Uri.parse('$baseUrl/warzero/turno/cerrar'),
          headers: _headers,
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return CerrarTurnoResult.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('cerrarTurno HTTP ${res.statusCode}: ${res.body}');
  }

  /// Convierte recursivamente valores no serializables a JSON (Timestamp →
  /// epoch millis, DateTime → ISO 8601) para poder enviarlos por HTTP.
  static dynamic _jsonSafe(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _jsonSafe(v)));
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList();
    }
    return value;
  }
}
