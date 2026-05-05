// lib/models/game_config.dart

import 'package:flutter/material.dart';

/// Zona de jugador dentro del tablero
class PlayerZone {
  final String zoneId; // 'north','south','west','east','ne','nw','se','sw'
  final String label;
  final Color color;

  const PlayerZone({
    required this.zoneId,
    required this.label,
    required this.color,
  });
}

/// Tipo de terreno de una celda.
///
///  [land]       → Tierra pura.  Tipo 1 y 2 pueden detenerse. Tipo 3 no puede cruzar.
///  [sea]        → Mar.          Tipo 3 y 2 (paso) pueden cruzar. Tipo 1 no puede cruzar.
///  [deepSea]    → Mar profundo. Igual que [sea], renderizado más oscuro.
///  [amphibious] → Anfibio.      Cualquier tipo puede cruzar y detenerse.
enum TerrainType { land, sea, deepSea, amphibious }

/// Configuración completa de un tablero
class GameConfig {
  final int playerCount;
  final List<String> rowLabels; // e.g. ['A','B',...,'H']
  final List<int> colLabels; // e.g. [1,2,...,14]
  final List<PlayerZone> zones;

  /// Mapa de terrenos: coord (e.g. "B5") → TerrainType.
  /// Las celdas ausentes se consideran [TerrainType.land].
  final Map<String, TerrainType> terrainMap;

  const GameConfig({
    required this.playerCount,
    required this.rowLabels,
    required this.colLabels,
    required this.zones,
    this.terrainMap = const {},
  });

  int get rows => rowLabels.length;
  int get cols => colLabels.length;

  String coordLabel(int ri, int ci) => '${rowLabels[ri]}${colLabels[ci]}';

  // ── Terreno ───────────────────────────────────────────────

  /// Terreno de una celda por coordenada (e.g. "B5").
  TerrainType terrainAt(String coord) => terrainMap[coord] ?? TerrainType.land;

  /// Terreno de una celda por índices de fila/columna.
  TerrainType terrain(int ri, int ci) => terrainAt(coordLabel(ri, ci));

  /// True si la celda es acuática (sea o deepSea).
  bool isSea(int ri, int ci) {
    final t = terrain(ri, ci);
    return t == TerrainType.sea || t == TerrainType.deepSea;
  }

  // ── Reglas de movimiento por terreno ─────────────────────

  /// ¿Puede una unidad de [tipo] **atravesar** (pasar por) esta celda?
  ///
  ///  tipo 1 (terrestre) → solo land y amphibious
  ///  tipo 2 (volador)   → cualquier celda
  ///  tipo 3 (marino)    → solo sea, deepSea y amphibious
  bool canTraverse(String coord, int tipo) {
    final t = terrainAt(coord);
    switch (tipo) {
      case 1:
        return t == TerrainType.land || t == TerrainType.amphibious;
      case 3:
        return t == TerrainType.sea ||
            t == TerrainType.deepSea ||
            t == TerrainType.amphibious;
      default: // tipo 2: vuela sobre todo
        return true;
    }
  }

  /// ¿Puede una unidad de [tipo] **detenerse/aterrizar** en esta celda?
  ///
  ///  tipo 1 (terrestre) → solo land y amphibious
  ///  tipo 2 (volador)   → solo land y amphibious (no puede aterrizar en agua)
  ///  tipo 3 (marino)    → solo sea, deepSea y amphibious
  bool canLand(String coord, int tipo) {
    final t = terrainAt(coord);
    switch (tipo) {
      case 1:
      case 2:
        return t == TerrainType.land || t == TerrainType.amphibious;
      case 3:
        return t == TerrainType.sea ||
            t == TerrainType.deepSea ||
            t == TerrainType.amphibious;
      default:
        return true;
    }
  }

  // ── Zona ─────────────────────────────────────────────────
  PlayerZone? zoneFor(int ri, int ci) {
    for (final z in zones) {
      if (_cellInZone(ri, ci, z.zoneId)) return z;
    }
    return null;
  }

  bool _cellInZone(int ri, int ci, String zoneId) {
    switch (zoneId) {
      case 'north':
        return ri <= 2;
      case 'south':
        return ri >= rows - 3;
      case 'west':
        return ci <= 2;
      case 'east':
        return ci >= cols - 3;
      case 'ne':
        return ri <= 2 && ci >= cols - 3;
      case 'nw':
        return ri <= 2 && ci <= 2;
      case 'se':
        return ri >= rows - 3 && ci >= cols - 3;
      case 'sw':
        return ri >= rows - 3 && ci <= 2;
      default:
        return false;
    }
  }

  /// Devuelve una copia de esta configuración con un mapa de terreno distinto.
  /// Útil para cargar el terreno desde Firestore en tiempo de ejecución:
  ///   _config = GameConfig.forPlayerCount(n).withTerrain(mapFromFirestore);
  GameConfig withTerrain(Map<String, TerrainType> newTerrainMap) => GameConfig(
        playerCount: playerCount,
        rowLabels: rowLabels,
        colLabels: colLabels,
        zones: zones,
        terrainMap: newTerrainMap,
      );

  // ─────────────────────────────────────────────────────────
  // Presets
  // ─────────────────────────────────────────────────────────

  /// 4 jugadores: Norte, Sur, Este, Oeste  |  14×8
  static const GameConfig fourPlayers = GameConfig(
    playerCount: 4,
    rowLabels: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
    colLabels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
    zones: [
      PlayerZone(zoneId: 'north', label: 'NORTE', color: Color(0xFFC04040)),
      PlayerZone(zoneId: 'south', label: 'SUR', color: Color(0xFF4ABB58)),
      PlayerZone(zoneId: 'west', label: 'OESTE', color: Color(0xFF4060D0)),
      PlayerZone(zoneId: 'east', label: 'ESTE', color: Color(0xFFC0A820)),
    ],
  );

  /// 2 jugadores: Norte y Sur  |  10×6
  static const GameConfig twoPlayers = GameConfig(
    playerCount: 2,
    rowLabels: ['A', 'B', 'C', 'D', 'E', 'F'],
    colLabels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    zones: [
      PlayerZone(zoneId: 'north', label: 'NORTE', color: Color(0xFFC04040)),
      PlayerZone(zoneId: 'south', label: 'SUR', color: Color(0xFF4ABB58)),
    ],
  );

  /// 6 jugadores: Norte, Sur, Este, Oeste, NE, SW  |  16×10
  static const GameConfig sixPlayers = GameConfig(
    playerCount: 6,
    rowLabels: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'],
    colLabels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
    zones: [
      PlayerZone(zoneId: 'north', label: 'NORTE', color: Color(0xFFC04040)),
      PlayerZone(zoneId: 'south', label: 'SUR', color: Color(0xFF4ABB58)),
      PlayerZone(zoneId: 'west', label: 'OESTE', color: Color(0xFF4060D0)),
      PlayerZone(zoneId: 'east', label: 'ESTE', color: Color(0xFFC0A820)),
      PlayerZone(zoneId: 'ne', label: 'NE', color: Color(0xFFA040C0)),
      PlayerZone(zoneId: 'sw', label: 'SO', color: Color(0xFF40A0C0)),
    ],
  );

  /// 8 jugadores: Norte, Sur, Este, Oeste, NE, NW, SE, SW  |  18×12
  static const GameConfig eightPlayers = GameConfig(
    playerCount: 8,
    rowLabels: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'],
    colLabels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
    zones: [
      PlayerZone(zoneId: 'north', label: 'NORTE', color: Color(0xFFC04040)),
      PlayerZone(zoneId: 'south', label: 'SUR', color: Color(0xFF4ABB58)),
      PlayerZone(zoneId: 'west', label: 'OESTE', color: Color(0xFF4060D0)),
      PlayerZone(zoneId: 'east', label: 'ESTE', color: Color(0xFFC0A820)),
      PlayerZone(zoneId: 'ne', label: 'NE', color: Color(0xFFA040C0)),
      PlayerZone(zoneId: 'nw', label: 'NO', color: Color(0xFF40A0C0)),
      PlayerZone(zoneId: 'se', label: 'SE', color: Color(0xFFD06040)),
      PlayerZone(zoneId: 'sw', label: 'SO', color: Color(0xFF60C080)),
    ],
  );

  static GameConfig forPlayerCount(int count) {
    switch (count) {
      case 2:
        return twoPlayers;
      case 6:
        return sixPlayers;
      case 8:
        return eightPlayers;
      default:
        return fourPlayers;
    }
  }
}
