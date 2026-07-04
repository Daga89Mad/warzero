// lib/views/revision_turno_screen.dart

import 'package:flutter/material.dart';
import '../models/board_state.dart';
import '../models/game_config.dart';
import '../widgets/cell_widget.dart' show kObeliscoCoords, ownerColor;

/// Pantalla intermedia que se muestra tras cerrar el informe de batalla.
///
/// Reconstruye visualmente lo que ha ocurrido en el turno recién resuelto:
///   - Celdas donde hubo combate (borde rojo + glow).
///   - Celdas origen/objetivo de acciones o habilidades (borde cyan + ⚡),
///     hayan impactado o no.
///   - Celdas con presencia de cartas rivales (fondo amarillo translúcido).
///   - Cuarteles conquistados (borde dorado + corona).
///
/// La pantalla es solo visual: contiene un botón "EMPEZAR TURNO" arriba que
/// la cierra. Al volver, el flujo del juego continúa con el turno ya
/// resuelto.
class RevisionTurnoScreen extends StatelessWidget {
  final GameConfig config;
  final BoardState boardState;
  final Map<String, dynamic> historialEntry;
  final String localUid;
  final Map<String, Color> playerColors;

  /// Coord del cuartel local para distinguirlo visualmente.
  final String? obeliscoLocal;

  /// uid → coord del cuartel de cada jugador (para distinguir cuarteles).
  final Map<String, String> obeliscosPorJugador;

  const RevisionTurnoScreen({
    super.key,
    required this.config,
    required this.boardState,
    required this.historialEntry,
    required this.localUid,
    this.playerColors = const {},
    this.obeliscoLocal,
    this.obeliscosPorJugador = const {},
  });

  // ── Extracción de eventos ───────────────────────────────────

  /// Coords donde se produjo combate (no necesariamente conquista).
  Set<String> _combateCoords() {
    final result = <String>{};
    final log = historialEntry['combateLog'] as List? ?? [];
    for (final e in log) {
      final m = Map<String, dynamic>.from(e as Map);
      final coord = m['coord'] as String?;
      if (coord != null && coord.isNotEmpty) result.add(coord);
    }
    return result;
  }

  /// Coords donde un cuartel cambió de manos.
  Set<String> _conquistaCoords() {
    final result = <String>{};
    final log = historialEntry['conquistasLog'] as List? ?? [];
    for (final e in log) {
      final m = Map<String, dynamic>.from(e as Map);
      final coord = m['coord'] as String?;
      if (coord != null && coord.isNotEmpty) result.add(coord);
    }
    // También se marcan conquistas registradas dentro del combateLog
    // (esConquistaObelisco == true).
    final cl = historialEntry['combateLog'] as List? ?? [];
    for (final e in cl) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['esConquistaObelisco'] == true) {
        final coord = m['coord'] as String?;
        if (coord != null && coord.isNotEmpty) result.add(coord);
      }
    }
    return result;
  }

  /// Coords origen + objetivos de acciones/habilidades del turno.
  /// Se incluyen aunque no hayan impactado (es lo que el jugador pidió).
  Set<String> _accionCoords() {
    final result = <String>{};
    final log = historialEntry['accionesLog'] as List? ?? [];
    for (final e in log) {
      final m = Map<String, dynamic>.from(e as Map);
      final origen = m['origen'] as String?;
      if (origen != null && origen.isNotEmpty) result.add(origen);
      // El servidor escribe `objetivo` (singular) por acción; se mantiene el
      // soporte de `objetivos` (lista) por compatibilidad, y `destino` para el
      // teletransporte. Esto marca la celda DONDE cayó la habilidad.
      final objetivo = m['objetivo'] as String?;
      if (objetivo != null && objetivo.isNotEmpty) result.add(objetivo);
      final destino = m['destino'] as String?;
      if (destino != null && destino.isNotEmpty) result.add(destino);
      final objetivos = m['objetivos'] as List? ?? [];
      for (final o in objetivos) {
        if (o is String && o.isNotEmpty) result.add(o);
      }
    }
    return result;
  }

  /// Coords donde aparecen cartas rivales en el `movimientosLog`.
  /// Es la "huella" de las cartas enemigas tras cerrar el turno.
  Set<String> _movimientoRivalCoords() {
    final result = <String>{};
    final log = historialEntry['movimientosLog'] as List? ?? [];
    for (final e in log) {
      final m = Map<String, dynamic>.from(e as Map);
      final uid = m['uid'] as String?;
      if (uid == null || uid == localUid) continue;
      final celdas = m['celdas'] as Map?;
      if (celdas == null) continue;
      celdas.forEach((coord, cartas) {
        final lista = cartas as List? ?? [];
        if (lista.isEmpty) return;
        if (coord is String && coord.isNotEmpty) result.add(coord);
      });
    }
    return result;
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final combate = _combateCoords();
    final conquista = _conquistaCoords();
    final accion = _accionCoords();
    final movRival = _movimientoRivalCoords();
    final turno = (historialEntry['turno'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF050D18),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              turno: turno,
              onEmpezarTurno: () => Navigator.of(context).pop(),
            ),
            _Legend(
              combate: combate.isNotEmpty,
              accion: accion.isNotEmpty,
              movRival: movRival.isNotEmpty,
              conquista: conquista.isNotEmpty,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final maxW = constraints.maxWidth;
                    final maxH = constraints.maxHeight;
                    // Cada celda es cuadrada. Calcular el tamaño que cabe en
                    // ambas dimensiones, respetando un mini-margen para labels.
                    const labelGutter = 18.0;
                    // Cada _MiniCell añade margin EdgeInsets.all(0.5) → 1px de
                    // ancho/alto extra por celda. Hay que descontarlo o la fila
                    // desborda (p. ej. 10 columnas = 10px de overflow).
                    const cellMargin = 1.0;
                    final cellW =
                        (maxW - labelGutter - config.cols * cellMargin) /
                            config.cols;
                    final cellH =
                        (maxH - labelGutter - config.rows * cellMargin) /
                            config.rows;
                    final cellSize = cellW < cellH ? cellW : cellH; // cuadrada
                    final gridW = cellSize * config.cols +
                        config.cols * cellMargin +
                        labelGutter;
                    final gridH = cellSize * config.rows +
                        config.rows * cellMargin +
                        labelGutter;

                    return Center(
                      child: SizedBox(
                        width: gridW,
                        height: gridH,
                        child: _MiniBoard(
                          config: config,
                          boardState: boardState,
                          cellSize: cellSize,
                          labelGutter: labelGutter,
                          combateCoords: combate,
                          accionCoords: accion,
                          movimientoRivalCoords: movRival,
                          conquistaCoords: conquista,
                          localUid: localUid,
                          playerColors: playerColors,
                          obeliscoLocal: obeliscoLocal,
                          obeliscosPorJugador: obeliscosPorJugador,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final int turno;
  final VoidCallback onEmpezarTurno;
  const _TopBar({required this.turno, required this.onEmpezarTurno});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x40503214), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REVISIÓN DEL TURNO',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC8A860),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Turno $turno • Eventos del campo de batalla',
                  style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF506070),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEmpezarTurno,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFC8A860).withOpacity(0.14),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: const Color(0xFFC8A860).withOpacity(0.55), width: 1),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFC8A860).withOpacity(0.25),
                      blurRadius: 10),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 13, color: Color(0xFFC8A860)),
                  SizedBox(width: 5),
                  Text(
                    'EMPEZAR TURNO',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      color: Color(0xFFC8A860),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LEYENDA
// ─────────────────────────────────────────────────────────────
class _Legend extends StatelessWidget {
  final bool combate;
  final bool accion;
  final bool movRival;
  final bool conquista;

  const _Legend({
    required this.combate,
    required this.accion,
    required this.movRival,
    required this.conquista,
  });

  @override
  Widget build(BuildContext context) {
    if (!combate && !accion && !movRival && !conquista) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Sin eventos relevantes este turno',
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 8,
            color: Color(0xFF506070),
            letterSpacing: 1,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          if (movRival)
            const _LegendChip(
              color: Color(0xFFE0C040),
              label: 'MOV. RIVAL',
              filled: true,
            ),
          if (combate)
            const _LegendChip(
              color: Color(0xFFC04040),
              label: 'COMBATE',
            ),
          if (accion)
            const _LegendChip(
              color: Color(0xFF40C0FF),
              label: 'ACCIÓN / HABILIDAD',
              icon: Icons.flash_on,
            ),
          if (conquista)
            const _LegendChip(
              color: Color(0xFFE8C870),
              label: 'CONQUISTA',
              icon: Icons.castle,
            ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final IconData? icon;
  final bool filled;
  const _LegendChip({
    required this.color,
    required this.label,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.20) : color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
          ] else
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.65),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 7,
              color: color,
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MINI BOARD
// ─────────────────────────────────────────────────────────────
class _MiniBoard extends StatelessWidget {
  final GameConfig config;
  final BoardState boardState;
  final double cellSize;
  final double labelGutter;
  final Set<String> combateCoords;
  final Set<String> accionCoords;
  final Set<String> movimientoRivalCoords;
  final Set<String> conquistaCoords;
  final String localUid;
  final Map<String, Color> playerColors;
  final String? obeliscoLocal;
  final Map<String, String> obeliscosPorJugador;

  const _MiniBoard({
    required this.config,
    required this.boardState,
    required this.cellSize,
    required this.labelGutter,
    required this.combateCoords,
    required this.accionCoords,
    required this.movimientoRivalCoords,
    required this.conquistaCoords,
    required this.localUid,
    required this.playerColors,
    required this.obeliscoLocal,
    required this.obeliscosPorJugador,
  });

  bool _esObelisco(String coord) =>
      kObeliscoCoords.contains(coord) ||
      obeliscosPorJugador.values.contains(coord);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header: etiquetas de columna ──
        SizedBox(
          height: labelGutter,
          child: Row(
            children: [
              SizedBox(width: labelGutter),
              for (int c = 0; c < config.cols; c++)
                SizedBox(
                  width: cellSize,
                  child: Center(
                    child: Text(
                      '${config.colLabels[c]}',
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        color: Color(0xFF506070),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ── Filas ──
        for (int r = 0; r < config.rows; r++)
          SizedBox(
            height: cellSize,
            child: Row(
              children: [
                SizedBox(
                  width: labelGutter,
                  child: Center(
                    child: Text(
                      config.rowLabels[r],
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        color: Color(0xFF506070),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                for (int c = 0; c < config.cols; c++)
                  _MiniCell(
                    coord: config.coordLabel(r, c),
                    size: cellSize,
                    boardState: boardState,
                    isCombate: false,
                    isAccion: false,
                    isMovRival: false,
                    isConquista: false,
                    isObelisco: false,
                    isLocalObelisco: false,
                    localUid: localUid,
                    playerColors: playerColors,
                  )._withFlags(
                    isCombate: combateCoords.contains(config.coordLabel(r, c)),
                    isAccion: accionCoords.contains(config.coordLabel(r, c)),
                    isMovRival:
                        movimientoRivalCoords.contains(config.coordLabel(r, c)),
                    isConquista:
                        conquistaCoords.contains(config.coordLabel(r, c)),
                    isObelisco: _esObelisco(config.coordLabel(r, c)),
                    isLocalObelisco: config.coordLabel(r, c) == obeliscoLocal,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MINI CELL
// ─────────────────────────────────────────────────────────────
class _MiniCell extends StatelessWidget {
  final String coord;
  final double size;
  final BoardState boardState;
  final bool isCombate;
  final bool isAccion;
  final bool isMovRival;
  final bool isConquista;
  final bool isObelisco;
  final bool isLocalObelisco;
  final String localUid;
  final Map<String, Color> playerColors;

  const _MiniCell({
    required this.coord,
    required this.size,
    required this.boardState,
    required this.isCombate,
    required this.isAccion,
    required this.isMovRival,
    required this.isConquista,
    required this.isObelisco,
    required this.isLocalObelisco,
    required this.localUid,
    required this.playerColors,
  });

  /// Crea una copia con flags actualizadas (usado por el builder anterior).
  _MiniCell _withFlags({
    required bool isCombate,
    required bool isAccion,
    required bool isMovRival,
    required bool isConquista,
    required bool isObelisco,
    required bool isLocalObelisco,
  }) {
    return _MiniCell(
      coord: coord,
      size: size,
      boardState: boardState,
      isCombate: isCombate,
      isAccion: isAccion,
      isMovRival: isMovRival,
      isConquista: isConquista,
      isObelisco: isObelisco,
      isLocalObelisco: isLocalObelisco,
      localUid: localUid,
      playerColors: playerColors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartas = boardState.getCelda(coord).cartas;
    final tieneCartas = cartas.isNotEmpty;
    final isRayo = boardState.esRayo(coord); // ← rayo de farmeo

    // ── Color de fondo base ──────────────────────────────────
    Color bgColor = const Color(0xFF0A1525);
    if (isObelisco) {
      bgColor = isLocalObelisco
          ? const Color(0xFF1A1A0A) // dorado oscuro
          : const Color(0xFF1A0A0A); // rojo oscuro
    }
    if (isRayo && !isObelisco && !isMovRival) {
      bgColor = const Color(0xFFD4A800).withOpacity(0.14); // tinte dorado rayo
    }
    if (isMovRival) {
      // Amarillo translúcido (prioritario sobre el fondo de obelisco).
      bgColor = const Color(0xFFE0C040).withOpacity(0.22);
    }

    // ── Borde principal por prioridad ────────────────────────
    Color borderColor = const Color(0x20503214);
    double borderWidth = 0.5;
    List<BoxShadow> shadows = const [];

    if (isConquista) {
      borderColor = const Color(0xFFE8C870);
      borderWidth = 2.0;
      shadows = [
        BoxShadow(
            color: const Color(0xFFE8C870).withOpacity(0.55), blurRadius: 10),
      ];
    } else if (isCombate) {
      borderColor = const Color(0xFFC04040);
      borderWidth = 1.8;
      shadows = [
        BoxShadow(
            color: const Color(0xFFC04040).withOpacity(0.50), blurRadius: 8),
      ];
    } else if (isAccion) {
      borderColor = const Color(0xFF40C0FF);
      borderWidth = 1.4;
      shadows = [
        BoxShadow(
            color: const Color(0xFF40C0FF).withOpacity(0.35), blurRadius: 6),
      ];
    } else if (isRayo) {
      borderColor = const Color(0xFFD4A800);
      borderWidth = 1.6;
      shadows = [
        BoxShadow(
            color: const Color(0xFFD4A800).withOpacity(0.45), blurRadius: 8),
      ];
    } else if (isObelisco) {
      borderColor = isLocalObelisco
          ? const Color(0xFFC8A860).withOpacity(0.45)
          : const Color(0xFFC04040).withOpacity(0.45);
      borderWidth = 1.0;
    }

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadows,
      ),
      child: Stack(
        children: [
          // Coord en esquina superior izquierda
          Positioned(
            top: 1,
            left: 2,
            child: Text(
              coord,
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 6,
                color: Color.lerp(borderColor, const Color(0xFF506070), 0.4)!,
                letterSpacing: 0.3,
              ),
            ),
          ),
          // Icono de conquista
          if (isConquista)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.castle, size: 10, color: Color(0xFFE8C870)),
            ),
          // Icono de acción (si no hay conquista para no chocar)
          if (isAccion && !isConquista)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.flash_on, size: 9, color: Color(0xFF40C0FF)),
            ),
          // Icono del rayo de farmeo (abajo-derecha, para no chocar con los de arriba)
          if (isRayo)
            const Positioned(
              bottom: 2,
              right: 2,
              child: Icon(Icons.bolt, size: 10, color: Color(0xFFFFE066)),
            ),
          // Fichas de cartas en el centro (puntos coloreados por jugador)
          if (tieneCartas)
            Center(
              child: _CardDots(
                cartas: cartas,
                localUid: localUid,
                playerColors: playerColors,
                maxDots: 4,
                dotSize: (size * 0.13).clamp(3.0, 7.0),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PUNTOS DE CARTA (representación mini)
// ─────────────────────────────────────────────────────────────
class _CardDots extends StatelessWidget {
  final List<CartaEnCelda> cartas;
  final String localUid;
  final Map<String, Color> playerColors;
  final int maxDots;
  final double dotSize;

  const _CardDots({
    required this.cartas,
    required this.localUid,
    required this.playerColors,
    required this.maxDots,
    required this.dotSize,
  });

  @override
  Widget build(BuildContext context) {
    final visibles = cartas.take(maxDots).toList();
    final extras = cartas.length - visibles.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final c in visibles)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.6),
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: playerColors[c.ownerUid] ?? ownerColor(c.ownerZone),
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.ownerUid == localUid
                      ? Colors.white.withOpacity(0.55)
                      : Colors.transparent,
                  width: 0.5,
                ),
              ),
            ),
          ),
        if (extras > 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              '+$extras',
              style: const TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 6,
                color: Color(0xFFB0A090),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
