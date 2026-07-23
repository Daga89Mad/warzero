// lib/models/jugador_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Lee un campo aceptando tanto la clave en lowercase (nueva)
/// como en PascalCase (legado), para mantener retrocompatibilidad.
T? _pickField<T>(Map<String, dynamic> d, List<String> keys) {
  for (final k in keys) {
    final v = d[k];
    if (v != null) return v as T?;
  }
  return null;
}

class JugadorDatos {
  final String uid;
  final String alias;
  final int dinero;
  final String imagenPerfil;
  final int nivel;
  final int experiencia;

  const JugadorDatos({
    required this.uid,
    required this.alias,
    required this.dinero,
    required this.imagenPerfil,
    this.nivel = 1,
    this.experiencia = 0,
  });

  factory JugadorDatos.fromFirestore(String uid, DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return JugadorDatos(
      uid: uid,
      alias: _pickField<String>(d, ['alias', 'Alias']) ?? 'Jugador',
      dinero: (_pickField<num>(d, ['dinero', 'Dinero']))?.toInt() ?? 0,
      imagenPerfil:
          _pickField<String>(d, ['imagenPerfil', 'ImagenPerfil']) ?? '',
      nivel: (_pickField<num>(d, ['nivel', 'Nivel']))?.toInt() ?? 1,
      experiencia:
          (_pickField<num>(d, ['experiencia', 'Experiencia']))?.toInt() ?? 0,
    );
  }
}

class JugadorEstadisticas {
  final int victorias;
  final int derrotas;
  final int retiradas;

  const JugadorEstadisticas({
    required this.victorias,
    required this.derrotas,
    required this.retiradas,
  });

  factory JugadorEstadisticas.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return JugadorEstadisticas(
      victorias: (d['Victorias'] as num?)?.toInt() ??
          (d['victorias'] as num?)?.toInt() ??
          0,
      derrotas: (d['Derrotas'] as num?)?.toInt() ??
          (d['derrotas'] as num?)?.toInt() ??
          0,
      retiradas: (d['Retiradas'] as num?)?.toInt() ??
          (d['retiradas'] as num?)?.toInt() ??
          0,
    );
  }
}

/// Jugador activo en una partida.
/// [energies] acumula el coste de las cartas enemigas destruidas.
/// [pc]       acumula 3 puntos por cada carta enemiga destruida.
class PlayerSession {
  final JugadorDatos datos;
  final String zona; // 'north', 'south', 'west', 'east'
  final int colorIndex; // 0-3, para asignar color en tablero
  int vida;
  int puntos;
  int energies;
  int pc;

  PlayerSession({
    required this.datos,
    required this.zona,
    required this.colorIndex,
    this.vida = 20,
    this.puntos = 0,
    this.energies = 0,
    this.pc = 0,
  });

  String get alias => datos.alias;
  String get uid => datos.uid;

  /// Aplica las recompensas obtenidas tras un combate.
  void aplicarRecompensas(
      {required int energiesGanadas, required int pcGanados}) {
    energies += energiesGanadas;
    pc += pcGanados;
  }

  PlayerSession copyWith({
    JugadorDatos? datos,
    String? zona,
    int? colorIndex,
    int? vida,
    int? puntos,
    int? energies,
    int? pc,
  }) =>
      PlayerSession(
        datos: datos ?? this.datos,
        zona: zona ?? this.zona,
        colorIndex: colorIndex ?? this.colorIndex,
        vida: vida ?? this.vida,
        puntos: puntos ?? this.puntos,
        energies: energies ?? this.energies,
        pc: pc ?? this.pc,
      );

  Map<String, dynamic> toStatsMap() => {
        'energies': energies,
        'pc': pc,
        'vida': vida,
        'puntos': puntos,
      };
}

// ── Stats de partida por jugador (energies, PC, victorias/derrotas) ──
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
