// lib/services/warzero_api.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/accion_pendiente.dart';
import '../models/carta_model.dart';
import '../models/historia_model.dart';

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

  /// Estado completo de la partida tras la operación (mismo shape que el doc de
  /// Firestore). Permite avanzar el turno SIN leer Firestore.
  final Map<String, dynamic>? estado;

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
    this.estado,
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
      estado: j['estado'] is Map
          ? Map<String, dynamic>.from(j['estado'] as Map)
          : null,
    );
  }
}

/// Resultado de entrar a una partida.
class EntrarResult {
  final int turnoActual;
  final int? energiasAsignadas;
  final String? obeliscoAsignado;
  final Map<String, dynamic>? estado;

  const EntrarResult({
    required this.turnoActual,
    this.energiasAsignadas,
    this.obeliscoAsignado,
    this.estado,
  });

  factory EntrarResult.fromJson(Map<String, dynamic> j) => EntrarResult(
        turnoActual: (j['turnoActual'] as num?)?.toInt() ?? 0,
        energiasAsignadas: (j['energiasAsignadas'] as num?)?.toInt(),
        obeliscoAsignado: j['obeliscoAsignado'] as String?,
        estado: j['estado'] is Map
            ? Map<String, dynamic>.from(j['estado'] as Map)
            : null,
      );
}

/// Cliente de la API Fenrir / WarZero.
///
/// IMPORTANTE: el backend corre en Render con plan gratuito, que DUERME el
/// servicio tras un rato de inactividad. La primera petición tras el "sueño"
/// puede tardar 30-60s en despertarlo. Por eso este cliente:
///  - expone [despertar] (warm-up) para arrancar el despertar cuanto antes,
///  - usa timeouts generosos y reintentos en las llamadas clave,
/// de modo que un arranque en frío no rompa la entrada ni el cierre de turno.
class WarZeroApi {
  WarZeroApi({this.baseUrl = _defaultBaseUrl, this.token});

  static const String _defaultBaseUrl = 'https://fenrirv2.onrender.com';

  final String baseUrl;

  /// JWT opcional (Bearer). Si la API exige autenticación, asígnalo.
  final String? token;

  // Timeouts. Generosos para absorber el arranque en frío de Render.
  static const Duration _wakeTimeout = Duration(seconds: 60);
  static const Duration _postTimeout = Duration(seconds: 45);
  static const Duration _getTimeout = Duration(seconds: 30);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

  /// Warm-up: despierta el servidor de Render (best-effort). Conviene llamarlo
  /// lo antes posible (p. ej. al abrir la sala o la pantalla de juego) para que
  /// el servidor ya esté despierto cuando se llame a [entrar].
  Future<void> despertar() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/warzero/status'), headers: _headers)
          .timeout(_wakeTimeout);
      debugPrint('[WZ][api] despertar status=${res.statusCode}');
    } catch (e) {
      // No es crítico: si falla, los reintentos de las llamadas reales cubren.
      debugPrint('[WZ][api] despertar falló (seguimos): $e');
    }
  }

  /// Envía una petición reintentando ante errores de red / timeout (arranque en
  /// frío de Render). No reintenta ante respuestas HTTP con código (eso lo
  /// decide el llamador). Lanza si se agotan los intentos.
  Future<http.Response> _enviarConReintentos(
    Future<http.Response> Function() enviar, {
    required String etiqueta,
    int intentos = 3,
    required Duration timeout,
  }) async {
    Object? ultimoError;
    for (int i = 1; i <= intentos; i++) {
      try {
        return await enviar().timeout(timeout);
      } on TimeoutException catch (e) {
        ultimoError = e;
        debugPrint('[WZ][api] $etiqueta intento $i: timeout');
      } catch (e) {
        ultimoError = e;
        debugPrint('[WZ][api] $etiqueta intento $i falló: $e');
      }
      if (i < intentos) {
        await Future.delayed(Duration(seconds: 2 * i));
      }
    }
    throw Exception(
        '$etiqueta sin respuesta tras $intentos intentos: $ultimoError');
  }

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

    debugPrint('[WZ][api] POST cerrar lobby=$lobbyId uid=$uid turno=$turno');

    final res = await _enviarConReintentos(
      () => http.post(
        Uri.parse('$baseUrl/warzero/turno/cerrar'),
        headers: _headers,
        body: body,
      ),
      etiqueta: 'cerrar',
      intentos: 3,
      timeout: _postTimeout,
    );

    debugPrint('[WZ][api] resp status=${res.statusCode} body=${res.body}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return CerrarTurnoResult.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('cerrarTurno HTTP ${res.statusCode}: ${res.body}');
  }

  /// Deshace los gastos NO consolidados del turno en curso: devuelve la energía
  /// revertible ([energiesDelta] positivo) y desmarca las especiales compradas
  /// este turno ([especialesQuitar]). Fire-and-forget: nunca lanza. BUG QAS #2.
  Future<void> deshacerTurno({
    required String lobbyId,
    required String uid,
    required int turno,
    required int energiesDelta,
    List<String> especialesQuitar = const [],
  }) async {
    if (energiesDelta == 0 && especialesQuitar.isEmpty) return;
    try {
      final body = jsonEncode({
        'lobbyId': lobbyId,
        'uid': uid,
        'turno': turno,
        'energiesDelta': energiesDelta,
        'especialesQuitar': especialesQuitar,
      });
      await http
          .post(
            Uri.parse('$baseUrl/warzero/turno/deshacer'),
            headers: _headers,
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[WZ][api] turno deshecho lobby=$lobbyId turno=$turno '
          'devuelto=$energiesDelta especiales=${especialesQuitar.length}');
    } catch (e) {
      debugPrint('[WZ][api] deshacerTurno falló (ignorado): $e');
    }
  }

  /// Entrada a la partida: inicializa energías/obelisco/mano si hace falta
  /// (atómico en el servidor) y devuelve el estado completo. Devuelve null si no
  /// existe. Reintenta para absorber el arranque en frío de Render.
  Future<EntrarResult?> entrar({
    required String lobbyId,
    required String uid,
  }) async {
    final res = await _enviarConReintentos(
      () => http.post(
        Uri.parse('$baseUrl/warzero/entrar'),
        headers: _headers,
        body: jsonEncode({'lobbyId': lobbyId, 'uid': uid}),
      ),
      etiqueta: 'entrar',
      intentos: 3,
      timeout: _postTimeout,
    );
    debugPrint('[WZ][api] POST entrar status=${res.statusCode}');
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['existe'] != true) return null;
      return EntrarResult.fromJson(j);
    }
    throw Exception('entrar HTTP ${res.statusCode}: ${res.body}');
  }

  /// Obtiene el estado completo de la partida por HTTP (sin Firestore).
  /// Devuelve el mapa `estado` (mismo shape que el doc) o null si no existe.
  Future<Map<String, dynamic>?> obtenerEstado(String lobbyId) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/estado?lobbyId=$lobbyId'),
        headers: _headers,
      ),
      etiqueta: 'estado',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET estado status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['existe'] != true) return null;
      return j['estado'] is Map
          ? Map<String, dynamic>.from(j['estado'] as Map)
          : null;
    }
    throw Exception('obtenerEstado HTTP ${res.statusCode}: ${res.body}');
  }

  /// Colección personal del jugador por HTTP (sin Firestore). Devuelve el mapa
  /// con claves `jugador`, `cartas` y `evoluciones`, o null si no existe.
  Future<Map<String, dynamic>?> obtenerColeccion(String uid) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/coleccion?uid=$uid'),
        headers: _headers,
      ),
      etiqueta: 'coleccion',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET coleccion status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['existe'] != true) return null;
      return j;
    }
    throw Exception('obtenerColeccion HTTP ${res.statusCode}: ${res.body}');
  }

  /// Skins desbloqueadas del jugador para una carta. Devuelve la lista de skins
  /// (cada una con id/nombre/imagen/rareza), o lista vacía si no hay.
  Future<List<Map<String, dynamic>>> obtenerSkins(
      String uid, String cartaId) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/skins?uid=$uid&cartaId=$cartaId'),
        headers: _headers,
      ),
      etiqueta: 'skins',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET skins status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (j['skins'] as List?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('obtenerSkins HTTP ${res.statusCode}: ${res.body}');
  }

  /// Fija (o limpia, pasando skinId null) la skin elegida del jugador para una
  /// carta. Devuelve {ok, skinId, imagen} con la URL resuelta por el servidor.
  Future<Map<String, dynamic>> seleccionarSkin({
    required String uid,
    required String cartaId,
    String? skinId,
  }) async {
    final res = await _enviarConReintentos(
      () => http.post(
        Uri.parse('$baseUrl/warzero/skin/seleccionar'),
        headers: _headers,
        body: jsonEncode({
          'uid': uid,
          'cartaId': cartaId,
          'skinId': skinId,
        }),
      ),
      etiqueta: 'skin/seleccionar',
      intentos: 2,
      timeout: _postTimeout,
    );
    debugPrint('[WZ][api] POST skin/seleccionar status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('seleccionarSkin HTTP ${res.statusCode}: ${res.body}');
  }

  /// Actualiza los stats de partida del jugador (energías, mano/mazo, compras)
  /// vía API, sin escribir en Firestore desde el cliente. Todos los campos son
  /// opcionales; solo se aplican los que se envían. `energiesDelta` se aplica
  /// como incremento (negativo = gasto). Devuelve las energías resultantes.
  Future<int?> actualizarStats({
    required String lobbyId,
    required String uid,
    int? energiesDelta,
    String? especialComprada,
    List<String>? mano,
    List<String>? mazoRestante,
  }) async {
    final res = await _enviarConReintentos(
      () => http.post(
        Uri.parse('$baseUrl/warzero/stats'),
        headers: _headers,
        body: jsonEncode({
          'lobbyId': lobbyId,
          'uid': uid,
          if (energiesDelta != null) 'energiesDelta': energiesDelta,
          if (especialComprada != null) 'especialComprada': especialComprada,
          if (mano != null) 'mano': mano,
          if (mazoRestante != null) 'mazoRestante': mazoRestante,
        }),
      ),
      etiqueta: 'stats',
      intentos: 2,
      timeout: _postTimeout,
    );
    debugPrint('[WZ][api] POST stats status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return (j['energies'] as num?)?.toInt();
    }
    throw Exception('actualizarStats HTTP ${res.statusCode}: ${res.body}');
  }

  /// Cartas del catálogo por sus IDs (resolver evoluciones y mano/mazo) sin
  /// Firestore. Devuelve solo las que existen.
  Future<List<CartaModel>> obtenerCartas(List<String> ids) async {
    final query = ids.where((s) => s.isNotEmpty).join(',');
    if (query.isEmpty) return [];
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse(
            '$baseUrl/warzero/cartas?ids=${Uri.encodeQueryComponent(query)}'),
        headers: _headers,
      ),
      etiqueta: 'cartas',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET cartas status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (j['cartas'] as List?) ?? [];
      return list
          .map((e) => CartaModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception('obtenerCartas HTTP ${res.statusCode}: ${res.body}');
  }

  /// Mazo del jugador (expandido por cantidad, filtrado por ejército) vía API,
  /// sin Firestore. Mismo resultado que MazoService.obtenerMazoParaJuego.
  Future<List<CartaModel>> obtenerMazo(String uid, {int? ejercitoId}) async {
    final ej = ejercitoId != null ? '&ejercitoId=$ejercitoId' : '';
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/mazo?uid=$uid$ej'),
        headers: _headers,
      ),
      etiqueta: 'mazo',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET mazo status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (j['cartas'] as List?) ?? [];
      return list
          .map((e) => CartaModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception('obtenerMazo HTTP ${res.statusCode}: ${res.body}');
  }

  /// Partidas en las que el jugador participa (en curso o esperando), vía API
  /// (sin Firestore realtime, que se cuelga en Android). Devuelve la lista de
  /// docs de partida (mismo shape que Firestore); el cliente los convierte con
  /// LobbyModel.fromMap.
  Future<List<Map<String, dynamic>>> obtenerMisPartidas(String uid) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/mispartidas?uid=$uid'),
        headers: _headers,
      ),
      etiqueta: 'mispartidas',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET mispartidas status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (j['partidas'] as List?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('obtenerMisPartidas HTTP ${res.statusCode}: ${res.body}');
  }

  /// Partidas públicas en espera (lista de la pestaña PÚBLICAS) vía API.
  Future<List<Map<String, dynamic>>> obtenerPublicas() async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/publicas'),
        headers: _headers,
      ),
      etiqueta: 'publicas',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET publicas status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (j['partidas'] as List?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('obtenerPublicas HTTP ${res.statusCode}: ${res.body}');
  }

  /// Datos de la pantalla MIS MAZOS vía API (sin Firestore): ejércitos, catálogo
  /// de cartas y perfiles de mazo del jugador. Devuelve el mapa con claves
  /// `ejercitos`, `cartas` y `mazos` (cada una una lista).
  Future<Map<String, dynamic>> obtenerMisMazos(String uid) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/mismazos?uid=$uid'),
        headers: _headers,
      ),
      etiqueta: 'mismazos',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET mismazos status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('obtenerMisMazos HTTP ${res.statusCode}: ${res.body}');
  }

  /// Terreno de un mapa por HTTP (sin Firestore). Devuelve el mapa con la clave
  /// `terreno` { coord: "sea"|"deepSea"|"amphibious"|"land" }, o null si no existe.
  Future<Map<String, dynamic>?> obtenerMapa(String mapaId) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/mapa?mapaId=$mapaId'),
        headers: _headers,
      ),
      etiqueta: 'mapa',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET mapa status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['existe'] != true) return null;
      return j;
    }
    throw Exception('obtenerMapa HTTP ${res.statusCode}: ${res.body}');
  }

  /// Historias del jugador (catálogo + estado desbloqueada) vía API. Devuelve la
  /// lista completa; el cliente la agrupa por ejército. Las bloqueadas vienen sin
  /// título ni páginas.
  Future<List<HistoriaModel>> obtenerHistorias(String uid) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/historias?uid=$uid'),
        headers: _headers,
      ),
      etiqueta: 'historias',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET historias status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (j['historias'] as List?) ?? [];
      return list
          .map(
              (e) => HistoriaModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception('obtenerHistorias HTTP ${res.statusCode}: ${res.body}');
  }

  /// Desbloquea una historia para el jugador (la consigue "a lo largo del juego").
  /// Llamar cuando se cumpla la condición de obtención. Devuelve true si fue ok.
  Future<bool> desbloquearHistoria({
    required String uid,
    required String historiaId,
  }) async {
    final res = await _enviarConReintentos(
      () => http.post(
        Uri.parse('$baseUrl/warzero/historia/desbloquear'),
        headers: _headers,
        body: jsonEncode({'uid': uid, 'historiaId': historiaId}),
      ),
      etiqueta: 'historia/desbloquear',
      intentos: 2,
      timeout: _postTimeout,
    );
    debugPrint('[WZ][api] POST historia/desbloquear status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return j['ok'] == true;
    }
    throw Exception('desbloquearHistoria HTTP ${res.statusCode}: ${res.body}');
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

  Future<Map<String, dynamic>?> obtenerRanking(String uid,
      {String orden = 'experiencia'}) async {
    final res = await _enviarConReintentos(
      () => http.get(
        Uri.parse('$baseUrl/warzero/ranking?uid=$uid&orden=$orden'),
        headers: _headers,
      ),
      etiqueta: 'ranking',
      intentos: 2,
      timeout: _getTimeout,
    );
    debugPrint('[WZ][api] GET ranking status=${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return null;
      return j;
    }
    throw Exception('obtenerRanking HTTP ${res.statusCode}: ${res.body}');
  }
}
