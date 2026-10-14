// lib/services/duelos_service.dart
//
// MODO DUELOS — cliente de la API (/warzero/duelos/*) y modelos.
//
// Las salas de duelo viven en la colección `Duelos`, pero la app NUNCA la lee
// de Firestore: todo pasa por la API, que solo devuelve vistas saneadas. Así el
// Comandante del rival (el general que hay que proteger) y sus jugadas del
// turno nunca llegan a este dispositivo.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'warzero_api.dart';

/// Nombre que ve el jugador para el general que hay que proteger. El servidor
/// lo devuelve también en el catálogo (`comandante`).
const String kDuelosTerminoComandante = 'Comandante';

/// Error devuelto por la API de duelos (mensaje listo para mostrar).
class DuelosError implements Exception {
  final String mensaje;
  const DuelosError(this.mensaje);
  @override
  String toString() => mensaje;
}

// ─────────────────────────────────────────────────────────────
// CATÁLOGO
// ─────────────────────────────────────────────────────────────

class DuelosHabilidadInfo {
  final String tipo;
  final String nombre;
  final String descripcion;

  const DuelosHabilidadInfo({
    required this.tipo,
    required this.nombre,
    required this.descripcion,
  });

  factory DuelosHabilidadInfo.fromMap(Map<String, dynamic>? m) =>
      DuelosHabilidadInfo(
        tipo: m?['tipo'] as String? ?? '',
        nombre: m?['nombre'] as String? ?? '',
        descripcion: m?['descripcion'] as String? ?? '',
      );
}

class DuelosGeneralInfo {
  final String nombre;
  final String cartaId;
  final String imagen;
  final int ataque;
  final int vidas;
  final DuelosHabilidadInfo habilidad;

  const DuelosGeneralInfo({
    required this.nombre,
    required this.cartaId,
    required this.imagen,
    required this.ataque,
    required this.vidas,
    required this.habilidad,
  });

  factory DuelosGeneralInfo.fromMap(Map<String, dynamic> m) =>
      DuelosGeneralInfo(
        nombre: m['nombre'] as String? ?? '',
        cartaId: m['cartaId'] as String? ?? '',
        imagen: m['imagen'] as String? ?? '',
        ataque: (m['ataque'] as num?)?.toInt() ?? 0,
        vidas: (m['vidas'] as num?)?.toInt() ?? 0,
        habilidad: DuelosHabilidadInfo.fromMap(_mapa(m['habilidad'])),
      );
}

class DuelosSoldadoInfo {
  final String nombre;
  final String cartaId;
  final String imagen;
  final String papel;
  final int ataque;

  const DuelosSoldadoInfo({
    required this.nombre,
    required this.cartaId,
    required this.imagen,
    required this.papel,
    required this.ataque,
  });

  factory DuelosSoldadoInfo.fromMap(Map<String, dynamic> m) =>
      DuelosSoldadoInfo(
        nombre: m['nombre'] as String? ?? '',
        cartaId: m['cartaId'] as String? ?? '',
        imagen: m['imagen'] as String? ?? '',
        papel: m['papel'] as String? ?? '',
        ataque: (m['ataque'] as num?)?.toInt() ?? 0,
      );
}

class DuelosEjercitoInfo {
  final int id;
  final String nombre;
  final DuelosHabilidadInfo habilidadEjercito;
  final List<DuelosGeneralInfo> generales;
  final List<DuelosSoldadoInfo> guarnicion;

  const DuelosEjercitoInfo({
    required this.id,
    required this.nombre,
    required this.habilidadEjercito,
    required this.generales,
    required this.guarnicion,
  });

  factory DuelosEjercitoInfo.fromMap(Map<String, dynamic> m) =>
      DuelosEjercitoInfo(
        id: (m['id'] as num?)?.toInt() ?? 0,
        nombre: m['nombre'] as String? ?? '',
        habilidadEjercito:
            DuelosHabilidadInfo.fromMap(_mapa(m['habilidadEjercito'])),
        generales: _lista(m['generales'])
            .map(DuelosGeneralInfo.fromMap)
            .toList(growable: false),
        guarnicion: _lista(m['guarnicion'])
            .map(DuelosSoldadoInfo.fromMap)
            .toList(growable: false),
      );
}

class DuelosCatalogo {
  final String comandante;
  final List<DuelosEjercitoInfo> ejercitos;
  final Map<String, dynamic> reglas;

  const DuelosCatalogo({
    required this.comandante,
    required this.ejercitos,
    required this.reglas,
  });

  factory DuelosCatalogo.fromMap(Map<String, dynamic> m) => DuelosCatalogo(
        comandante: m['comandante'] as String? ?? kDuelosTerminoComandante,
        ejercitos: _lista(m['ejercitos'])
            .map(DuelosEjercitoInfo.fromMap)
            .toList(growable: false),
        reglas: _mapa(m['reglas']) ?? const {},
      );

  DuelosEjercitoInfo? ejercito(int? id) {
    for (final e in ejercitos) {
      if (e.id == id) return e;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// SALAS
// ─────────────────────────────────────────────────────────────

class DuelosJugadorSala {
  final String uid;
  final String alias;
  final bool listo;
  final bool esHost;
  final bool propio;

  /// Solo se conocen los propios mientras la sala está en espera.
  final int? ejercitoId;
  final List<String> generales;

  /// Índice (0/1) del Comandante dentro de [generales]. Solo el propio.
  final int? comandante;

  const DuelosJugadorSala({
    required this.uid,
    required this.alias,
    required this.listo,
    this.esHost = false,
    this.propio = false,
    this.ejercitoId,
    this.generales = const [],
    this.comandante,
  });

  factory DuelosJugadorSala.fromMap(Map<String, dynamic> m) =>
      DuelosJugadorSala(
        uid: m['uid'] as String? ?? '',
        alias: m['alias'] as String? ?? 'Jugador',
        listo: m['listo'] == true,
        esHost: m['esHost'] == true,
        propio: m['propio'] == true,
        ejercitoId: (m['ejercitoId'] as num?)?.toInt(),
        generales: (m['generales'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        comandante: (m['comandante'] as num?)?.toInt(),
      );
}

/// Sala de duelo tal como la devuelve la API (listas, sala y partida).
class DuelosSala {
  final String id;
  final String nombre;

  /// "esperando" | "en_curso" | "finalizada".
  final String estado;
  final bool esPrivada;
  final String? mapaId;
  final String mapaNombre;
  final String hostUid;
  final DateTime creadoEn;
  final int turno;
  final int numJugadores;
  final int maxJugadores;
  final List<DuelosJugadorSala> jugadores;
  final bool soyParticipante;

  /// En curso: true si ya mandaste tu jugada de este turno.
  final bool yaJugue;

  /// Terminada: "victoria" | "derrota" | "tablas" (desde tu punto de vista).
  final String resultado;
  final String motivo;

  /// Vista de la partida (solo en GET partida, con el duelo empezado).
  final Map<String, dynamic>? partida;

  const DuelosSala({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.esPrivada,
    required this.mapaId,
    required this.mapaNombre,
    required this.hostUid,
    required this.creadoEn,
    required this.turno,
    required this.numJugadores,
    required this.maxJugadores,
    required this.jugadores,
    required this.soyParticipante,
    required this.yaJugue,
    required this.resultado,
    required this.motivo,
    this.partida,
  });

  bool get esperando => estado == 'esperando';
  bool get enCurso => estado == 'en_curso';
  bool get finalizada => estado == 'finalizada';
  bool get llena => numJugadores >= maxJugadores;

  DuelosJugadorSala? jugador(String uid) {
    for (final j in jugadores) {
      if (j.uid == uid) return j;
    }
    return null;
  }

  factory DuelosSala.fromMap(Map<String, dynamic> m) => DuelosSala(
        id: m['id'] as String? ?? '',
        nombre: m['nombre'] as String? ?? 'Duelo',
        estado: m['estado'] as String? ?? 'esperando',
        esPrivada: m['esPrivada'] == true,
        mapaId: m['mapaId'] as String?,
        mapaNombre: m['mapaNombre'] as String? ?? '',
        hostUid: m['hostUid'] as String? ?? '',
        creadoEn: DateTime.fromMillisecondsSinceEpoch(
            (m['creadoEn'] as num?)?.toInt() ?? 0),
        turno: (m['turno'] as num?)?.toInt() ?? 0,
        numJugadores: (m['numJugadores'] as num?)?.toInt() ?? 0,
        maxJugadores: (m['maxJugadores'] as num?)?.toInt() ?? 2,
        jugadores: _lista(m['jugadores'])
            .map(DuelosJugadorSala.fromMap)
            .toList(growable: false),
        soyParticipante: m['soyParticipante'] == true,
        yaJugue: m['yaJugue'] == true,
        resultado: m['resultado'] as String? ?? '',
        motivo: m['motivo'] as String? ?? '',
        partida: _mapa(m['partida']),
      );
}

// ─────────────────────────────────────────────────────────────
// SERVICIO
// ─────────────────────────────────────────────────────────────

class DuelosService {
  DuelosService({WarZeroApi? api}) : _base = (api ?? WarZeroApi()).baseUrl;

  final String _base;

  static const Duration _timeout = Duration(seconds: 45);
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  /// El catálogo no cambia durante la sesión: se pide una vez.
  static DuelosCatalogo? _catalogo;

  Future<DuelosCatalogo> catalogo({bool forzar = false}) async {
    if (_catalogo != null && !forzar) return _catalogo!;
    final j = await _get('/warzero/duelos/catalogo');
    _catalogo = DuelosCatalogo.fromMap(j);
    return _catalogo!;
  }

  Future<List<DuelosSala>> publicas(String uid) async {
    final j = await _get('/warzero/duelos/publicas?uid=${_q(uid)}');
    return _lista(j['duelos']).map(DuelosSala.fromMap).toList();
  }

  Future<List<DuelosSala>> misDuelos(String uid) async {
    final j = await _get('/warzero/duelos/mispartidas?uid=${_q(uid)}');
    return _lista(j['duelos']).map(DuelosSala.fromMap).toList();
  }

  Future<DuelosSala> sala(String id, String uid) async => DuelosSala.fromMap(
      await _get('/warzero/duelos/sala?id=${_q(id)}&uid=${_q(uid)}'));

  Future<DuelosSala> partida(String id, String uid) async => DuelosSala.fromMap(
      await _get('/warzero/duelos/partida?id=${_q(id)}&uid=${_q(uid)}'));

  Future<DuelosSala> crear({
    required String uid,
    required String alias,
    required String nombre,
    required bool esPrivada,
    required String contrasena,
    String? mapaId,
  }) async =>
      DuelosSala.fromMap(await _post('/warzero/duelos/crear', {
        'uid': uid,
        'alias': alias,
        'nombre': nombre,
        'esPrivada': esPrivada,
        'contrasena': contrasena,
        'mapaId': mapaId,
      }));

  Future<DuelosSala> unirse({
    required String id,
    required String uid,
    required String alias,
    String? contrasena,
  }) async =>
      DuelosSala.fromMap(await _post('/warzero/duelos/unirse', {
        'id': id,
        'uid': uid,
        'alias': alias,
        'contrasena': contrasena,
      }));

  /// En espera: sale de la sala. En curso: se rinde (gana el rival).
  Future<void> salir({required String id, required String uid}) async {
    await _post('/warzero/duelos/salir', {'id': id, 'uid': uid});
  }

  Future<DuelosSala> elegir({
    required String id,
    required String uid,
    required int ejercitoId,
    required List<String> generales,
    required int comandante,
  }) async =>
      DuelosSala.fromMap(await _post('/warzero/duelos/elegir', {
        'id': id,
        'uid': uid,
        'ejercitoId': ejercitoId,
        'generales': generales,
        'comandante': comandante,
      }));

  Future<DuelosSala> iniciar({required String id, required String uid}) async =>
      DuelosSala.fromMap(
          await _post('/warzero/duelos/iniciar', {'id': id, 'uid': uid}));

  /// Manda la jugada del turno. El servidor resuelve cuando están las dos.
  Future<DuelosSala> turno({
    required String id,
    required String uid,
    required int turno,
    required Map<String, dynamic> jugada,
  }) async =>
      DuelosSala.fromMap(await _post('/warzero/duelos/turno', {
        'id': id,
        'uid': uid,
        'turno': turno,
        'jugada': jugada,
      }));

  // ── HTTP ──────────────────────────────────────────────────

  static String _q(String s) => Uri.encodeQueryComponent(s);

  Future<Map<String, dynamic>> _get(String ruta) async {
    final res = await http
        .get(Uri.parse('$_base$ruta'), headers: _headers)
        .timeout(_timeout);
    return _leer(res, ruta);
  }

  Future<Map<String, dynamic>> _post(
      String ruta, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$_base$ruta'),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return _leer(res, ruta);
  }

  Map<String, dynamic> _leer(http.Response res, String ruta) {
    Map<String, dynamic>? j;
    try {
      final d = jsonDecode(res.body);
      if (d is Map) j = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300 && j != null) return j;
    final msg = (j?['error'] ?? j?['detail'] ?? j?['title'])?.toString();
    debugPrint('[WZ][duelos] $ruta HTTP ${res.statusCode}: ${res.body}');
    throw DuelosError(msg?.isNotEmpty == true
        ? _capitalizar(msg!)
        : 'No se pudo conectar con el servidor (${res.statusCode}).');
  }

  static String _capitalizar(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Ayudas de parseo ─────────────────────────────────────────

Map<String, dynamic>? _mapa(Object? o) =>
    o is Map ? Map<String, dynamic>.from(o) : null;

List<Map<String, dynamic>> _lista(Object? o) => o is List
    ? o.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];
