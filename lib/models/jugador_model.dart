// lib/models/jugador_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class JugadorDatos {
  final String uid;
  final String alias;
  final int dinero;
  final String imagenPerfil;

  const JugadorDatos({
    required this.uid,
    required this.alias,
    required this.dinero,
    required this.imagenPerfil,
  });

  factory JugadorDatos.fromFirestore(String uid, DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return JugadorDatos(
      uid: uid,
      alias: d['Alias'] as String? ?? 'Jugador',
      dinero: (d['Dinero'] as num?)?.toInt() ?? 0,
      imagenPerfil: d['ImagenPerfil'] as String? ?? '',
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
      victorias: (d['Victorias'] as num?)?.toInt() ?? 0,
      derrotas: (d['Derrotas'] as num?)?.toInt() ?? 0,
      retiradas: (d['Retiradas'] as num?)?.toInt() ?? 0,
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
