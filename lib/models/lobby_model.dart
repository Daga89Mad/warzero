// lib/models/lobby_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Estado de un jugador dentro del lobby ─────────────────────
class LobbyJugador {
  final String uid;
  final String alias;
  final int? ejercitoId;
  final bool listo;

  const LobbyJugador({
    required this.uid,
    required this.alias,
    this.ejercitoId,
    this.listo = false,
  });

  factory LobbyJugador.fromMap(Map<String, dynamic> d) => LobbyJugador(
        uid: d['uid'] as String? ?? '',
        alias: d['alias'] as String? ?? 'Jugador',
        ejercitoId: (d['ejercitoId'] as num?)?.toInt(),
        listo: d['listo'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'alias': alias,
        'ejercitoId': ejercitoId,
        'listo': listo,
      };

  LobbyJugador copyWith({
    String? uid,
    String? alias,
    int? ejercitoId,
    bool? listo,
  }) =>
      LobbyJugador(
        uid: uid ?? this.uid,
        alias: alias ?? this.alias,
        ejercitoId: ejercitoId ?? this.ejercitoId,
        listo: listo ?? this.listo,
      );
}

/// ── Stats de partida por jugador (energies, PC, victorias/derrotas) ──
class StatsPartidaJugador {
  final int energies;
  final int pc;
  final int victorias; // victorias POR COMBATE en esta partida
  final int derrotas; // derrotas POR COMBATE en esta partida

  const StatsPartidaJugador({
    this.energies = 0,
    this.pc = 0,
    this.victorias = 0,
    this.derrotas = 0,
  });

  factory StatsPartidaJugador.fromMap(Map<String, dynamic> d) =>
      StatsPartidaJugador(
        energies: (d['energies'] as num?)?.toInt() ?? 0,
        pc: (d['pc'] as num?)?.toInt() ?? 0,
        victorias: (d['victorias'] as num?)?.toInt() ?? 0,
        derrotas: (d['derrotas'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'energies': energies,
        'pc': pc,
        'victorias': victorias,
        'derrotas': derrotas,
      };

  StatsPartidaJugador sumar({
    int energies = 0,
    int pc = 0,
    int victorias = 0,
    int derrotas = 0,
  }) =>
      StatsPartidaJugador(
        energies: this.energies + energies,
        pc: this.pc + pc,
        victorias: this.victorias + victorias,
        derrotas: this.derrotas + derrotas,
      );
}

// ── Modo de fin de turno ─────────────────────────────────────
enum ModoTurno { rapida, diario }

// ── Estado general del lobby ──────────────────────────────────
enum LobbyEstado { esperando, enCurso, finalizada }

class LobbyModel {
  final String id;
  final String nombre;
  final String hostUid;
  final bool esPrivada;
  final String contrasena;
  final int maxJugadores;
  final List<LobbyJugador> jugadores;
  final LobbyEstado estado;
  final DateTime creadoEn;
  final ModoTurno modoTurno;
  final int turnoActual;
  final List<String> cerradoPor;
  final Map<String, StatsPartidaJugador> statsPartida;
  final List<Map<String, dynamic>> ultimoCombateLog;
  final String? mapaId;

  /// UIDs de jugadores cuyo cuartel general fue conquistado (eliminados).
  final List<String> jugadoresEliminados;

  /// UID del jugador ganador (disponible cuando estado == finalizada).
  final String? ganadorUid;

  const LobbyModel({
    required this.id,
    required this.nombre,
    required this.hostUid,
    required this.esPrivada,
    required this.contrasena,
    required this.maxJugadores,
    required this.jugadores,
    required this.estado,
    required this.creadoEn,
    this.modoTurno = ModoTurno.rapida,
    this.turnoActual = 1,
    this.cerradoPor = const [],
    this.statsPartida = const {},
    this.ultimoCombateLog = const [],
    this.mapaId,
    this.jugadoresEliminados = const [],
    this.ganadorUid,
  });

  bool get estaLleno => jugadores.length >= maxJugadores;
  bool get todosListos =>
      jugadores.isNotEmpty && jugadores.every((j) => j.listo);

  /// Número de jugadores aún activos (no eliminados).
  int get jugadoresActivos =>
      jugadores.where((j) => !jugadoresEliminados.contains(j.uid)).length;

  /// True si todos los jugadores ACTIVOS han cerrado el turno.
  bool get todosCerraronTurno {
    final activos =
        jugadores.where((j) => !jugadoresEliminados.contains(j.uid));
    return activos.isNotEmpty &&
        activos.every((j) => cerradoPor.contains(j.uid));
  }

  StatsPartidaJugador statsDeJugador(String uid) =>
      statsPartida[uid] ?? const StatsPartidaJugador();

  factory LobbyModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return LobbyModel.fromMap(doc.id, d);
  }

  /// Construye un LobbyModel desde un mapa plano (p. ej. el estado que devuelve
  /// la API por HTTP). `creadoEn` puede venir como Timestamp o como epoch millis.
  factory LobbyModel.fromMap(String id, Map<String, dynamic> d) {
    final rawStats = d['statsPartida'] as Map<String, dynamic>? ?? {};
    final stats = rawStats.map(
      (uid, v) => MapEntry(
        uid,
        StatsPartidaJugador.fromMap(Map<String, dynamic>.from(v as Map)),
      ),
    );

    final rawLog = d['ultimoCombateLog'] as List<dynamic>? ?? [];
    final combateLog =
        rawLog.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final rawElim = d['jugadoresEliminados'] as List<dynamic>? ?? [];
    final eliminados = rawElim.map((e) => e.toString()).toList();

    DateTime creadoEn;
    final rawCreado = d['creadoEn'];
    if (rawCreado is Timestamp) {
      creadoEn = rawCreado.toDate();
    } else if (rawCreado is num) {
      creadoEn = DateTime.fromMillisecondsSinceEpoch(rawCreado.toInt());
    } else {
      creadoEn = DateTime.now();
    }

    return LobbyModel(
      id: id,
      nombre: d['nombre'] as String? ?? 'Partida',
      hostUid: d['hostUid'] as String? ?? '',
      esPrivada: d['esPrivada'] as bool? ?? false,
      contrasena: d['contrasena'] as String? ?? '',
      maxJugadores: (d['maxJugadores'] as num?)?.toInt() ?? 4,
      jugadores: ((d['jugadores'] as List<dynamic>?) ?? [])
          .map((j) => LobbyJugador.fromMap(Map<String, dynamic>.from(j as Map)))
          .toList(),
      estado: _parseEstado(d['estado'] as String?),
      creadoEn: creadoEn,
      modoTurno: _parseModoTurno(d['modoTurno'] as String?),
      turnoActual: (d['turnoActual'] as num?)?.toInt() ?? 1,
      cerradoPor: List<String>.from(d['cerradoPor'] as List? ?? []),
      statsPartida: stats,
      ultimoCombateLog: combateLog,
      mapaId: d['mapaId'] as String?,
      jugadoresEliminados: eliminados,
      ganadorUid: d['ganadorUid'] as String?,
    );
  }

  static LobbyEstado _parseEstado(String? s) {
    switch (s) {
      case 'en_curso':
        return LobbyEstado.enCurso;
      case 'finalizada':
        return LobbyEstado.finalizada;
      default:
        return LobbyEstado.esperando;
    }
  }

  static ModoTurno _parseModoTurno(String? s) =>
      s == 'diario' ? ModoTurno.diario : ModoTurno.rapida;

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'hostUid': hostUid,
        'esPrivada': esPrivada,
        'contrasena': contrasena,
        'maxJugadores': maxJugadores,
        'jugadores': jugadores.map((j) => j.toMap()).toList(),
        'estado': _estadoStr(estado),
        'creadoEn': Timestamp.fromDate(creadoEn),
        'modoTurno': modoTurno == ModoTurno.diario ? 'diario' : 'rapida',
        'turnoActual': turnoActual,
        'cerradoPor': cerradoPor,
        'statsPartida': statsPartida.map((uid, s) => MapEntry(uid, s.toMap())),
        'ultimoCombateLog': ultimoCombateLog,
        'jugadoresEliminados': jugadoresEliminados,
        if (ganadorUid != null) 'ganadorUid': ganadorUid,
        if (mapaId != null) 'mapaId': mapaId,
      };

  static String _estadoStr(LobbyEstado e) {
    switch (e) {
      case LobbyEstado.enCurso:
        return 'en_curso';
      case LobbyEstado.finalizada:
        return 'finalizada';
      default:
        return 'esperando';
    }
  }
}

// ── Modelo de ejército disponible ─────────────────────────────
class EjercitoInfo {
  final int id;
  final String nombre;
  final String descripcion;
  final String icono;

  const EjercitoInfo({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
  });
}

const List<EjercitoInfo> kEjercitos = [
  EjercitoInfo(id: 1, nombre: 'Humanos', descripcion: '', icono: '⚔️'),
  EjercitoInfo(id: 2, nombre: 'Biónicos', descripcion: '', icono: '🛡️'),
  EjercitoInfo(id: 3, nombre: 'Demonios', descripcion: '', icono: '⚓'),
  EjercitoInfo(id: 4, nombre: 'Nefilim', descripcion: '', icono: '🌒'),
];
