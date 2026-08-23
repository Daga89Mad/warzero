// lib/models/jugador_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Lee un campo aceptando tanto la clave en lowercase (nueva)
/// como en PascalCase (legado), para mantener retrocompatibilidad.
T? _pickField<T>(Map<String, dynamic> d, List<String> keys) {
  for (final k in keys) {
    final v = d[k];
    if (v != null) return v as T?;
  }
  return null;
}

int _pickInt(Map<String, dynamic> d, List<String> keys, {int fallback = 0}) =>
    (_pickField<num>(d, keys))?.toInt() ?? fallback;

// ─────────────────────────────────────────────────────────────
// MONEDAS ZERO
// ─────────────────────────────────────────────────────────────
/// Las 5 monedas "Zero" del jugador. Cada ejército tiene la suya; `puro` es
/// transversal (sirve para comprar cosas de cualquier ejército).
///
/// Mapeo con `kEjercitos`:
///   Ejército 1 (Humanos)  → Zero Celeste
///   Ejército 2 (Biónicos) → Zero Escarlata
///   Ejército 3 (Demonios) → Zero Fuego
///   Ejército 4 (Nefilim)  → Zero Natural
///   (transversal)         → Zero Puro
enum MonedaZero { celeste, escarlata, fuego, natural, puro }

extension MonedaZeroExt on MonedaZero {
  /// Clave lowercase usada en Firestore dentro del doc del jugador.
  String get firestoreKey {
    switch (this) {
      case MonedaZero.celeste:
        return 'zeroCeleste';
      case MonedaZero.escarlata:
        return 'zeroEscarlata';
      case MonedaZero.fuego:
        return 'zeroFuego';
      case MonedaZero.natural:
        return 'zeroNatural';
      case MonedaZero.puro:
        return 'zeroPuro';
    }
  }

  /// Clave legado en PascalCase, por retrocompatibilidad de lectura.
  String get firestoreKeyLegacy {
    switch (this) {
      case MonedaZero.celeste:
        return 'ZeroCeleste';
      case MonedaZero.escarlata:
        return 'ZeroEscarlata';
      case MonedaZero.fuego:
        return 'ZeroFuego';
      case MonedaZero.natural:
        return 'ZeroNatural';
      case MonedaZero.puro:
        return 'ZeroPuro';
    }
  }

  /// Nombre visible en la UI.
  /// Nombre corto del color de cristal ('Celeste', 'Escarlata', ...).
  String get colorNombre {
    switch (this) {
      case MonedaZero.celeste:
        return 'Celeste';
      case MonedaZero.escarlata:
        return 'Escarlata';
      case MonedaZero.fuego:
        return 'Fuego';
      case MonedaZero.natural:
        return 'Natural';
      case MonedaZero.puro:
        return 'Puro';
    }
  }

  /// Nombre completo de la moneda para la UI: "Cristales Zero <color>".
  String get label => 'Cristales Zero $colorNombre';

  /// Color temático de la moneda.
  Color get color {
    switch (this) {
      case MonedaZero.celeste:
        return const Color(0xFF5AB6E8); // azul celeste (Humanos)
      case MonedaZero.escarlata:
        return const Color(0xFFE0453A); // rojo escarlata (Biónicos)
      case MonedaZero.fuego:
        return const Color(0xFFF08A2E); // naranja fuego (Demonios)
      case MonedaZero.natural:
        return const Color(0xFF4CC26A); // verde (Nefilim)
      case MonedaZero.puro:
        return const Color(0xFFE0C040); // amarillo (transversal)
    }
  }

  /// Id del ejército al que pertenece esta moneda (null para `puro`).
  int? get ejercitoId {
    switch (this) {
      case MonedaZero.celeste:
        return 1;
      case MonedaZero.escarlata:
        return 2;
      case MonedaZero.fuego:
        return 3;
      case MonedaZero.natural:
        return 4;
      case MonedaZero.puro:
        return null;
    }
  }

  /// Moneda asociada a un ejército (por su id). Desconocido → puro.
  static MonedaZero fromEjercito(int ejercitoId) {
    switch (ejercitoId) {
      case 1:
        return MonedaZero.celeste;
      case 2:
        return MonedaZero.escarlata;
      case 3:
        return MonedaZero.fuego;
      case 4:
        return MonedaZero.natural;
      default:
        return MonedaZero.puro;
    }
  }
}

class JugadorDatos {
  final String uid;
  final String alias;
  final int dinero;
  final String imagenPerfil;
  final int nivel;
  final int experiencia;

  // ── Monedas Zero (coleccionismo / tiendas por ejército) ──
  final int zeroCeleste; // Humanos
  final int zeroEscarlata; // Biónicos
  final int zeroFuego; // Demonios
  final int zeroNatural; // Nefilim (verde)
  final int zeroPuro; // transversal (amarillo)

  const JugadorDatos({
    required this.uid,
    required this.alias,
    required this.dinero,
    required this.imagenPerfil,
    this.nivel = 1,
    this.experiencia = 0,
    this.zeroCeleste = 0,
    this.zeroEscarlata = 0,
    this.zeroFuego = 0,
    this.zeroNatural = 0,
    this.zeroPuro = 0,
  });

  factory JugadorDatos.fromFirestore(String uid, DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return JugadorDatos(
      uid: uid,
      alias: _pickField<String>(d, ['alias', 'Alias']) ?? 'Jugador',
      dinero: _pickInt(d, ['dinero', 'Dinero']),
      imagenPerfil:
          _pickField<String>(d, ['imagenPerfil', 'ImagenPerfil']) ?? '',
      nivel: _pickInt(d, ['nivel', 'Nivel'], fallback: 1),
      experiencia: _pickInt(d, ['experiencia', 'Experiencia']),
      zeroCeleste: _pickInt(d, ['zeroCeleste', 'ZeroCeleste']),
      zeroEscarlata: _pickInt(d, ['zeroEscarlata', 'ZeroEscarlata']),
      zeroFuego: _pickInt(d, ['zeroFuego', 'ZeroFuego']),
      zeroNatural: _pickInt(d, ['zeroNatural', 'ZeroNatural']),
      zeroPuro: _pickInt(d, ['zeroPuro', 'ZeroPuro']),
    );
  }

  factory JugadorDatos.fromMap(String uid, Map<String, dynamic> d) =>
      JugadorDatos(
        uid: uid,
        alias: _pickField<String>(d, ['alias', 'Alias']) ?? 'Jugador',
        dinero: _pickInt(d, ['dinero', 'Dinero']),
        imagenPerfil:
            _pickField<String>(d, ['imagenPerfil', 'ImagenPerfil']) ?? '',
        nivel: _pickInt(d, ['nivel', 'Nivel'], fallback: 1),
        experiencia: _pickInt(d, ['experiencia', 'Experiencia']),
        zeroCeleste: _pickInt(d, ['zeroCeleste', 'ZeroCeleste']),
        zeroEscarlata: _pickInt(d, ['zeroEscarlata', 'ZeroEscarlata']),
        zeroFuego: _pickInt(d, ['zeroFuego', 'ZeroFuego']),
        zeroNatural: _pickInt(d, ['zeroNatural', 'ZeroNatural']),
        zeroPuro: _pickInt(d, ['zeroPuro', 'ZeroPuro']),
      );

  /// Devuelve el saldo de una moneda concreta.
  int zeroDe(MonedaZero moneda) {
    switch (moneda) {
      case MonedaZero.celeste:
        return zeroCeleste;
      case MonedaZero.escarlata:
        return zeroEscarlata;
      case MonedaZero.fuego:
        return zeroFuego;
      case MonedaZero.natural:
        return zeroNatural;
      case MonedaZero.puro:
        return zeroPuro;
    }
  }

  /// Devuelve la moneda propia de un ejército (por su id).
  int zeroDeEjercito(int ejercitoId) =>
      zeroDe(MonedaZeroExt.fromEjercito(ejercitoId));

  /// Mapa moneda → saldo, útil para pintar la fila de monedas en el perfil.
  Map<MonedaZero, int> get zerosPorMoneda => {
        for (final m in MonedaZero.values) m: zeroDe(m),
      };

  JugadorDatos copyWith({
    String? uid,
    String? alias,
    int? dinero,
    String? imagenPerfil,
    int? nivel,
    int? experiencia,
    int? zeroCeleste,
    int? zeroEscarlata,
    int? zeroFuego,
    int? zeroNatural,
    int? zeroPuro,
  }) =>
      JugadorDatos(
        uid: uid ?? this.uid,
        alias: alias ?? this.alias,
        dinero: dinero ?? this.dinero,
        imagenPerfil: imagenPerfil ?? this.imagenPerfil,
        nivel: nivel ?? this.nivel,
        experiencia: experiencia ?? this.experiencia,
        zeroCeleste: zeroCeleste ?? this.zeroCeleste,
        zeroEscarlata: zeroEscarlata ?? this.zeroEscarlata,
        zeroFuego: zeroFuego ?? this.zeroFuego,
        zeroNatural: zeroNatural ?? this.zeroNatural,
        zeroPuro: zeroPuro ?? this.zeroPuro,
      );
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
