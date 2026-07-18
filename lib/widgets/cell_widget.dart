// lib/widgets/cell_widget.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'terrain_overlay.dart';
import '../models/game_config.dart';
import '../models/board_state.dart';
import '../models/carta_model.dart';

const double kCellW = 88;
const double kCellH = 80;
const double kLabelW = 22;
const double kLabelH = 18;

Color ownerColor(String zone) {
  switch (zone) {
    case 'north':
      return const Color(0xFFC04040);
    case 'south':
      return const Color(0xFF4ABB58);
    case 'west':
      return const Color(0xFF4060D0);
    case 'east':
      return const Color(0xFFC0A820);
    case 'ne':
      return const Color(0xFFA040C0);
    case 'nw':
      return const Color(0xFF40A0C0);
    case 'se':
      return const Color(0xFFD06040);
    case 'sw':
      return const Color(0xFF60C080);
    default:
      return const Color(0xFF888888);
  }
}

Border _reliefBorder({required Color lit, required Color shadow}) => Border(
      top: BorderSide(color: lit, width: 1.0),
      left: BorderSide(color: lit, width: 1.0),
      bottom: BorderSide(color: shadow, width: 1.0),
      right: BorderSide(color: shadow, width: 1.0),
    );

/// Todas las celdas comparten la misma decoración base sin color de terreno.
/// La información de terreno se comunica únicamente mediante el badge (icono).
BoxDecoration _cellDecoration(bool isDark) => BoxDecoration(
      color: isDark ? const Color(0x18000000) : const Color(0x12FFFFFF),
      border: _reliefBorder(
        lit: const Color(0x55FFFFFF),
        shadow: const Color(0x44000000),
      ),
    );

class CellWidget extends StatelessWidget {
  final int ri;
  final int ci;
  final GameConfig config;
  final CeldaState celda;
  final bool isSelected;
  final bool isHighlighted;
  final bool isMovable;
  final bool isObelisco;
  final bool isRayo;

  /// True si la celda tiene un veneno activo (se marca con calavera ☠).
  final bool isEnvenenada;

  /// True si la celda tiene una parálisis activa (se marca con reloj ⏱).
  final bool isParalizada;

  /// True si la celda tiene un escudo activo (se marca con 🛡).
  final bool isEscudada;

  /// Venenos activos en la celda (origen + magnitud). El preview de combate
  /// resta defensa solo a las cartas enemigas del veneno. Vacío = sin veneno.
  final List<({String origen, int magnitud})> venenosCelda;

  /// Escudos activos en la celda (origen + magnitud). Suman defensa solo a las
  /// cartas del lanzador. Vacío = sin escudo.
  final List<({String origen, int magnitud})> escudosCelda;

  /// uid → color del obelisco asignado (para colorear cartas por jugador)
  final Map<String, Color> playerColors;

  /// uid del jugador local (lo pasa el tablero; reservado para futuros previews
  /// de combate que necesiten distinguir al defensor del cuartel).
  final String? localPlayerUid;

  /// Cartas de acción declaradas por el jugador local sobre esta celda,
  /// pendientes de resolverse al cerrar turno. Es un marcador puramente
  /// visual (solo lo ve quien las lanzó): no participa en el combate ni
  /// existe en `celda`, así que no afecta a `_CardStack`.
  final List<CartaModel> fantasmas;
  final VoidCallback onTap;

  const CellWidget({
    super.key,
    required this.ri,
    required this.ci,
    required this.config,
    required this.celda,
    required this.isSelected,
    required this.isHighlighted,
    this.isMovable = false,
    this.isObelisco = false,
    this.isRayo = false,
    this.isEnvenenada = false,
    this.isParalizada = false,
    this.isEscudada = false,
    this.venenosCelda = const [],
    this.escudosCelda = const [],
    this.playerColors = const {},
    this.localPlayerUid,
    this.fantasmas = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final terrain = config.terrain(ri, ci);
    final isDark = (ri + ci) % 2 == 0;
    final zone = config.zoneFor(ri, ci);
    final coord = config.coordLabel(ri, ci);
    final overlay = terrainAt(coord);
    final painter = terrainPainter(overlay);
    final isSpawn = kSpawnCoords.contains(coord);

    // Todas las celdas usan la misma decoración — el terreno se indica solo con el badge.
    final cellDeco = _cellDecoration(isDark);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: kCellW,
        height: kCellH,
        decoration: cellDeco,
        foregroundDecoration: _foregroundDeco(
            isSelected, isHighlighted, isMovable, isObelisco, isRayo),
        child: Stack(
          children: [
            if (painter != null)
              Positioned.fill(child: CustomPaint(painter: painter)),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BevelHighlightPainter(isDark: isDark),
                ),
              ),
            ),
            if (zone != null) _ZoneTriangle(color: zone.color),

            // Resplandor dorado de la celda del rayo de farmeo (+10 Zero).
            if (isRayo)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.9,
                        colors: [Color(0x55D4A800), Color(0x00D4A800)],
                      ),
                    ),
                  ),
                ),
              ),

            // Badge de terreno — esquina inferior derecha, visible solo si no es tierra pura
            if (terrain != TerrainType.land)
              Positioned(
                right: 3,
                bottom: 3,
                child: _TerrainBadge(terrain: terrain),
              ),

            // Badge del rayo — esquina superior izquierda.
            if (isRayo) const Positioned(left: 3, top: 3, child: _RayoBadge()),

            // Tinte verde tóxico de la celda envenenada.
            if (isEnvenenada)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.95,
                        colors: [Color(0x3331C04A), Color(0x0031C04A)],
                      ),
                    ),
                  ),
                ),
              ),

            // Badge de veneno (calavera) — esquina superior derecha.
            if (isEnvenenada)
              const Positioned(right: 3, top: 3, child: _VenenoBadge()),

            // Tinte gélido de la celda paralizada.
            if (isParalizada)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.95,
                        colors: [Color(0x3340C0E0), Color(0x0040C0E0)],
                      ),
                    ),
                  ),
                ),
              ),

            // Badge de parálisis (reloj) — esquina inferior izquierda.
            if (isParalizada)
              const Positioned(left: 3, bottom: 3, child: _ParalisisBadge()),

            // Tinte azulado de la celda escudada.
            if (isEscudada)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.95,
                        colors: [Color(0x333A78C8), Color(0x003A78C8)],
                      ),
                    ),
                  ),
                ),
              ),

            // Badge de escudo — esquina inferior derecha.
            if (isEscudada)
              const Positioned(right: 3, bottom: 3, child: _EscudoBadge()),

            if (isSpawn && celda.isEmpty) SpawnMarker(coord: coord),
            if (!celda.isEmpty)
              Center(
                child: _CardStack(
                  celda: celda,
                  isEnemyObelisco:
                      kObeliscoCoords.contains(coord) && !isObelisco,
                  playerColors: playerColors,
                  venenosCelda: venenosCelda,
                  escudosCelda: escudosCelda,
                ),
              ),

            // Marcador fantasma de acción pendiente (solo visión local).
            if (fantasmas.isNotEmpty)
              Positioned(
                left: 2,
                top: 2,
                child: _AccionFantasmaBadge(cartas: fantasmas),
              ),
          ],
        ),
      ),
    );
  }

  BoxDecoration? _foregroundDeco(bool selected, bool highlighted, bool movable,
      bool isObelisco, bool isRayo) {
    if (selected) {
      return BoxDecoration(
        border: Border.all(color: const Color(0xFFDCBE30), width: 2),
      );
    }
    if (highlighted && isObelisco) {
      return BoxDecoration(
        border: Border.all(color: const Color(0xFF50E070), width: 2.5),
        color: const Color(0xFF28A040).withOpacity(0.20),
      );
    }
    if (highlighted) {
      return BoxDecoration(
        border: Border.all(color: const Color(0xFF28A040), width: 1.5),
        color: const Color(0xFF28A040).withOpacity(0.10),
      );
    }
    if (movable) {
      // Verde (antes azul): destino disponible al mover una carta.
      return BoxDecoration(
        border: Border.all(color: const Color(0xFF3AC65A), width: 1.5),
        color: const Color(0xFF3AC65A).withOpacity(0.14),
      );
    }
    if (isRayo) {
      return BoxDecoration(
        border: Border.all(color: const Color(0xFFD4A800), width: 1.5),
      );
    }
    return null;
  }
}

/// Marcador visual de una (o varias) carta(s) de acción declarada(s) sobre
/// esta celda, pendiente de resolverse al cerrar turno. Solo el jugador que
/// las lanzó las ve (viven en un mapa local de `GameScreen`, no en
/// `BoardState`), y no se enfrenta en combate: es solo una "chincheta" para
/// recordar dónde se apuntó.
class _AccionFantasmaBadge extends StatelessWidget {
  final List<CartaModel> cartas;
  const _AccionFantasmaBadge({required this.cartas});

  @override
  Widget build(BuildContext context) {
    final carta = cartas.last; // la más reciente, si hay varias apiladas
    return IgnorePointer(
      child: Opacity(
        opacity: 0.72,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1220),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF40C0FF),
              width: 1.2,
              style: BorderStyle.solid,
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x8040C0FF), blurRadius: 6, spreadRadius: 0.5),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (carta.imagen.trim().isNotEmpty)
                Image.network(
                  carta.imagen,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.bolt,
                      size: 14, color: Color(0xFF40C0FF)),
                )
              else
                const Center(
                  child: Icon(Icons.bolt, size: 14, color: Color(0xFF40C0FF)),
                ),
              // Velo azulado para que se note que es un marcador, no la carta real.
              Container(color: const Color(0x5006101C)),
              if (cartas.length > 1)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1220),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF40C0FF), width: 0.8),
                    ),
                    child: Text('${cartas.length}',
                        style: const TextStyle(
                            fontSize: 7,
                            color: Color(0xFF40C0FF),
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de la celda del rayo de farmeo (+10 Zero).
class _RayoBadge extends StatelessWidget {
  const _RayoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFFD4A800).withOpacity(0.92),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4A800).withOpacity(0.6),
            blurRadius: 6,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('Ø',
          style: TextStyle(
              fontSize: 11,
              height: 1.0,
              fontWeight: FontWeight.bold,
              color: Color(0xFF201400))),
    );
  }
}

/// Indicador de celda envenenada (calavera ☠). Las cartas que estén o entren
/// en la celda pierden defensa mientras el veneno siga activo.
class _VenenoBadge extends StatelessWidget {
  const _VenenoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFF2BA046).withOpacity(0.92),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2BA046).withOpacity(0.6),
            blurRadius: 6,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('☠', style: TextStyle(fontSize: 11, height: 1.0)),
    );
  }
}

/// Indicador de celda paralizada (reloj ⏱). Las cartas que estén o entren en
/// la celda no pueden moverse mientras la parálisis siga activa.
class _ParalisisBadge extends StatelessWidget {
  const _ParalisisBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFF2C90C8).withOpacity(0.92),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C90C8).withOpacity(0.6),
            blurRadius: 6,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('⏱', style: TextStyle(fontSize: 11, height: 1.0)),
    );
  }
}

/// Indicador de celda escudada (🛡). Las cartas del lanzador que estén o entren
/// en la celda ganan defensa mientras el escudo siga activo.
class _EscudoBadge extends StatelessWidget {
  const _EscudoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFF3A78C8).withOpacity(0.92),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3A78C8).withOpacity(0.6),
            blurRadius: 6,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('🛡', style: TextStyle(fontSize: 10, height: 1.0)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BADGE DE TERRENO
// ─────────────────────────────────────────────────────────────

/// Badge de terreno — solo icono, sin texto.
/// La descripción completa aparece en el sidebar al pulsar la celda.
class _TerrainBadge extends StatelessWidget {
  final TerrainType terrain;
  const _TerrainBadge({required this.terrain});

  @override
  Widget build(BuildContext context) {
    final (String icon, Color color) = switch (terrain) {
      TerrainType.sea => ('〰', const Color(0xFF4090E0)),
      TerrainType.deepSea => ('〰', const Color(0xFF2060C0)),
      TerrainType.amphibious => ('⚓', const Color(0xFF50A878)),
      TerrainType.land => ('', Colors.transparent),
    };

    if (icon.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color.withOpacity(0.82),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(icon, style: const TextStyle(fontSize: 9, height: 1.1)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _BevelHighlightPainter extends CustomPainter {
  final bool isDark;
  const _BevelHighlightPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final litPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: [const Color(0x1AFFFFFF), const Color(0x00FFFFFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.55, 0)
        ..lineTo(0, size.height * 0.55)
        ..close(),
      litPaint,
    );

    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.center,
        colors: [const Color(0x18000000), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height)
        ..lineTo(size.width * 0.45, size.height)
        ..lineTo(size.width, size.height * 0.45)
        ..close(),
      shadowPaint,
    );
  }

  @override
  bool shouldRepaint(_BevelHighlightPainter old) => old.isDark != isDark;
}

class _CardStack extends StatelessWidget {
  final CeldaState celda;
  final bool isEnemyObelisco;
  final Map<String, Color> playerColors;
  final List<({String origen, int magnitud})> venenosCelda;
  final List<({String origen, int magnitud})> escudosCelda;
  const _CardStack({
    required this.celda,
    this.isEnemyObelisco = false,
    this.playerColors = const {},
    this.venenosCelda = const [],
    this.escudosCelda = const [],
  });

  Color _colorFor(CartaEnCelda c) {
    if (playerColors.containsKey(c.ownerUid)) return playerColors[c.ownerUid]!;
    return ownerColor(c.ownerZone);
  }

  /// Defensa efectiva de una carta: resta el veneno de la celda (de un rival)
  /// y suma el escudo de la celda (del propio dueño), además de los efectos que
  /// ya lleva encima. Refleja lo que la propagación del servidor aplicará.
  int _defEfectiva(CartaEnCelda c) {
    int venenoCelda = 0;
    for (final v in venenosCelda) {
      if (v.origen == c.ownerUid) continue; // el veneno propio no le afecta
      if (v.magnitud > venenoCelda) venenoCelda = v.magnitud;
    }
    int escudoCelda = 0;
    for (final s in escudosCelda) {
      if (s.origen != c.ownerUid) continue; // el escudo solo protege a su dueño
      if (s.magnitud > escudoCelda) escudoCelda = s.magnitud;
    }
    final reduccion = c.defensaReducidaPorEfectos > venenoCelda
        ? c.defensaReducidaPorEfectos
        : venenoCelda;
    final extra = c.defensaExtraPorEfectos > escudoCelda
        ? c.defensaExtraPorEfectos
        : escudoCelda;
    final r = c.carta.defensa - reduccion + extra;
    return r > 0 ? r : 0;
  }

  @override
  Widget build(BuildContext context) {
    final primary = celda.cartas.first;
    final color = _colorFor(primary);
    final isMulti = celda.cartas.length > 1;
    final count = celda.cartas.length;

    if (isEnemyObelisco) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xDD060C14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.50), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.25), blurRadius: 8, spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 16, color: color.withOpacity(0.70)),
            const SizedBox(height: 2),
            Text(
              '$count ${count == 1 ? 'carta' : 'cartas'}',
              style: TextStyle(
                fontSize: 8,
                color: color.withOpacity(0.80),
                fontFamily: 'Cinzel',
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    // ── Combate pendiente: cartas de distintos jugadores en la misma celda ──
    // En vez de la fuerza bruta se muestra el RESULTADO del ataque contra la
    // defensa (poder neto), igual que el informe de combate, con el icono ⚡.
    //   poderNeto(X) = Σfuerza(X) − ΣdefensaEfectiva(enemigos de X)
    // Nota: el +80 de defensa del cuartel se aplica en la resolución del
    // servidor; este preview usa la fórmula base (válida fuera de obeliscos).
    if (celda.hayCombate) {
      // Construir grupos: uid → (fuerza, defensa efectiva, numCartas, color)
      final grupos =
          <String, ({int fuerza, int defensa, int numCartas, Color color})>{};
      for (final c in celda.cartas) {
        final uid = c.ownerUid;
        final prev = grupos[uid];
        grupos[uid] = (
          fuerza: (prev?.fuerza ?? 0) + c.fuerzaEfectiva,
          defensa: (prev?.defensa ?? 0) + _defEfectiva(c),
          numCartas: (prev?.numCartas ?? 0) + 1,
          color: _colorFor(c),
        );
      }
      final entries = grupos.entries.toList();
      final defensaTotal = entries.fold<int>(0, (s, e) => s + e.value.defensa);

      // Poder neto de un grupo = su fuerza − defensa efectiva de los rivales.
      int netoDe(int fuerza, int defensaPropia) =>
          fuerza - (defensaTotal - defensaPropia);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xEE060C14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: const Color(0xFFCC3030).withOpacity(0.80), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFCC3030).withOpacity(0.30),
                blurRadius: 10,
                spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ⚡ resultado del ataque contra la defensa
            const Text('⚡', style: TextStyle(fontSize: 10, height: 1)),
            const SizedBox(height: 2),
            // Poder neto de cada jugador separado por ⚡. FittedBox escala el
            // contenido para que no desborde en celdas estrechas.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (int i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          '⚡',
                          style: TextStyle(fontSize: 8, height: 1),
                        ),
                      ),
                    Builder(
                      builder: (_) {
                        final v = entries[i].value;
                        final neto = netoDe(v.fuerza, v.defensa);
                        final txt = neto >= 0 ? '+$neto' : '$neto';
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              txt,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: v.color,
                                fontFamily: 'Cinzel',
                                height: 1,
                                shadows: [
                                  Shadow(
                                    color: v.color.withOpacity(0.6),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${v.fuerza}/${v.defensa} · ${v.numCartas}u',
                              style: TextStyle(
                                fontSize: 6.5,
                                color: v.color.withOpacity(0.70),
                                fontFamily: 'Cinzel',
                                height: 1.1,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Un solo jugador (comportamiento original) ─────────────
    // En la miniatura se muestra el MOVIMIENTO de la carta principal (antes se
    // mostraba la fuerza), y un icono que indica su tipo: Tierra / Mar / Aire.
    final movimientoPrimary = primary.movimientoEfectivo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xDD060C14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.70), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35), blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icono de tipo (Tierra/Mar/Aire) + valor de movimiento.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                primary.carta.tipoIconData,
                size: 11,
                color: Color(primary.carta.tipoColorValue),
              ),
              const SizedBox(width: 3),
              Text(
                '$movimientoPrimary',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'Cinzel',
                  height: 1,
                  shadows: [
                    Shadow(color: color.withOpacity(0.6), blurRadius: 6)
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (isMulti)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withOpacity(0.20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withOpacity(0.50), width: 0.5),
              ),
              child: Text(
                '${celda.cartas.length} u.',
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'Cinzel'),
              ),
            )
          else
            Text(
              celda.cartas.first.carta.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 7,
                  color: color.withOpacity(0.85),
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.3),
            ),
        ],
      ),
    );
  }
}

class _ZoneTriangle extends StatelessWidget {
  final Color color;
  const _ZoneTriangle({required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: CustomPaint(
        size: const Size(14, 14),
        painter: _TrianglePainter(color: color.withOpacity(0.55)),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

class _WavePattern extends StatelessWidget {
  final bool deep;
  const _WavePattern({required this.deep});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(kCellW, kCellH),
      painter: _WavePainter(deep: deep),
    );
  }
}

class _WavePainter extends CustomPainter {
  final bool deep;
  const _WavePainter({required this.deep});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A4060).withOpacity(deep ? 0.15 : 0.22)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (double y = 10; y < size.height; y += 14) {
      final path = Path()..moveTo(0, y);
      for (double x = 0; x < size.width; x += 10) {
        path.relativeCubicTo(2.5, -4, 7.5, -4, 10, 0);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.deep != deep;
}

Widget colLabelCell(String text) => Container(
      width: kCellW,
      height: kLabelH,
      color: const Color(0xFF061525),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF9A8060),
              letterSpacing: 1,
              fontFamily: 'Cinzel')),
    );

Widget rowLabelCell(String text) => Container(
      width: kLabelW,
      height: kCellH,
      color: const Color(0xFF061525),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF9A8060),
              letterSpacing: 1,
              fontFamily: 'Cinzel')),
    );

Widget cornerCell() =>
    Container(width: kLabelW, height: kLabelH, color: const Color(0xFF061525));

// ─────────────────────────────────────────────────────────────
// SPAWN MARKER – Portal de cristal mágico 3D
// ─────────────────────────────────────────────────────────────

const Set<String> kObeliscoCoords = {'F1', 'A1', 'A10', 'F10'};
const Set<String> kSpawnCoords = kObeliscoCoords;

Color _spawnColor(String coord) {
  switch (coord) {
    case 'F1':
      return const Color(0xFF3080FF);
    case 'A1':
      return const Color(0xFFFF3030);
    case 'A10':
      return const Color(0xFFFFCC00);
    case 'F10':
      return const Color(0xFF30FF70);
    default:
      return const Color(0xFFFFFFFF);
  }
}

class SpawnMarker extends StatelessWidget {
  final String coord;
  const SpawnMarker({super.key, required this.coord});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: RepaintBoundary(
          // no repintar con cada rebuild del tablero
          child: SizedBox(
            width: kCellW * 0.88,
            height: kCellH * 0.92,
            child: CustomPaint(
              painter: _PortalCrystalPainter(color: _spawnColor(coord)),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalCrystalPainter extends CustomPainter {
  final Color color;
  const _PortalCrystalPainter({required this.color});

  Color _face(double brightness) {
    final t = brightness.clamp(0.0, 1.0);
    return Color.lerp(
      Color.lerp(color, Colors.black, 0.65)!,
      Color.lerp(color, Colors.white, 0.60)!,
      t,
    )!;
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    _drawShadow(canvas, w, h);
    _drawPedestal(canvas, w, h);
    _drawRuneRing(canvas, w, h);
    _drawCrystal(canvas, w, h);
    _drawBeamGlow(canvas, w, h);
    _drawSparkles(canvas, w, h);
  }

  void _drawShadow(Canvas canvas, double w, double h) {
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.52, h * 0.90),
          width: w * 0.75,
          height: h * 0.09),
      Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  void _drawPedestal(Canvas canvas, double w, double h) {
    final tl = Offset(w * 0.18, h * 0.74);
    final tr = Offset(w * 0.82, h * 0.74);
    final bl = Offset(w * 0.18, h * 0.87);
    final br = Offset(w * 0.82, h * 0.87);
    final tc = Offset(w * 0.50, h * 0.66);

    canvas.drawPath(
        Path()..addPolygon([tc, tl, tr], true),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_face(1.0), _face(0.72)],
          ).createShader(Rect.fromLTWH(0, h * 0.64, w, h * 0.12)));

    canvas.drawPath(
        Path()
          ..addPolygon(
              [tl, Offset(w * 0.50, h * 0.74), Offset(w * 0.50, h * 0.87), bl],
              true),
        Paint()..color = _face(0.38));

    canvas.drawPath(
        Path()
          ..addPolygon(
              [Offset(w * 0.50, h * 0.74), tr, br, Offset(w * 0.50, h * 0.87)],
              true),
        Paint()..color = _face(0.55));

    canvas.drawLine(
        tl,
        tr,
        Paint()
          ..color = Colors.white.withOpacity(0.72)
          ..strokeWidth = 1.4);
    canvas.drawLine(
        tl,
        tc,
        Paint()
          ..color = Colors.white.withOpacity(0.50)
          ..strokeWidth = 0.8);
    canvas.drawLine(
        tr,
        tc,
        Paint()
          ..color = Colors.white.withOpacity(0.35)
          ..strokeWidth = 0.8);

    canvas.drawLine(
        bl,
        br,
        Paint()
          ..color = Colors.black.withOpacity(0.60)
          ..strokeWidth = 1.2);

    final rune = Paint()
      ..color = color.withOpacity(0.85)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    for (final xf in [0.34, 0.50, 0.66]) {
      canvas.drawLine(Offset(w * xf, h * 0.76), Offset(w * xf, h * 0.85), rune);
    }
    canvas.drawLine(
        Offset(w * 0.22, h * 0.80), Offset(w * 0.78, h * 0.80), rune);

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.70),
          width: w * 0.50,
          height: h * 0.05),
      Paint()
        ..color = color.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  void _drawRuneRing(Canvas canvas, double w, double h) {
    final cy = h * 0.82;
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * 0.50, cy), width: w * 0.88, height: h * 0.090),
        Paint()
          ..color = color.withOpacity(0.55)
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * 0.50, cy), width: w * 0.62, height: h * 0.062),
        Paint()
          ..color = color.withOpacity(0.30)
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke);
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawCircle(
          Offset(
              w * 0.50 + w * 0.41 * math.cos(a), cy + h * 0.040 * math.sin(a)),
          1.8,
          Paint()
            ..color = Color.lerp(color, Colors.white, 0.5)!.withOpacity(0.88));
    }
  }

  void _drawCrystal(Canvas canvas, double w, double h) {
    final apex = Offset(w * 0.50, h * 0.03);
    final base = h * 0.68;

    final bL = Offset(w * 0.14, base);
    final bCL = Offset(w * 0.36, base);
    final bCR = Offset(w * 0.64, base);
    final bR = Offset(w * 0.86, base);
    final sL = Offset(w * 0.21, h * 0.29);
    final sCL = Offset(w * 0.39, h * 0.25);
    final sCR = Offset(w * 0.61, h * 0.25);
    final sR = Offset(w * 0.79, h * 0.29);

    canvas.drawPath(
        Path()..addPolygon([apex, sL, bL], true), Paint()..color = _face(0.10));

    canvas.drawPath(
        Path()..addPolygon([apex, sL, bL, bCL, sCL], true),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_face(0.20), _face(0.40)],
          ).createShader(Rect.fromLTWH(0, 0, w, h)));

    canvas.drawPath(
        Path()..addPolygon([apex, sCL, bCL, bCR, sCR], true),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(color, Colors.white, 0.78)!,
              Color.lerp(color, Colors.white, 0.38)!,
              color
            ],
            stops: const [0.0, 0.38, 1.0],
          ).createShader(Rect.fromLTWH(0, 0, w, h)));

    for (final xf in [0.44, 0.53]) {
      canvas.drawLine(
          Offset(w * xf, h * 0.10),
          Offset(w * xf, base),
          Paint()
            ..color = Colors.white.withOpacity(0.16)
            ..strokeWidth = 0.7);
    }

    canvas.drawPath(
        Path()..addPolygon([apex, sCR, bCR, bR, sR], true),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_face(0.65), _face(0.48)],
          ).createShader(Rect.fromLTWH(0, 0, w, h)));

    canvas.drawPath(
        Path()..addPolygon([apex, sR, bR], true), Paint()..color = _face(0.28));

    final ep = Paint()
      ..color = Colors.white.withOpacity(0.28)
      ..strokeWidth = 0.6;
    for (final pair in [
      [apex, sL],
      [apex, sCL],
      [apex, sCR],
      [apex, sR],
      [sL, bL],
      [sCL, bCL],
      [bCL, bCR],
      [sCR, bCR],
      [sR, bR]
    ]) {
      canvas.drawLine(pair[0], pair[1], ep);
    }
    canvas.drawLine(
        apex,
        bL,
        Paint()
          ..color = Colors.white.withOpacity(0.55)
          ..strokeWidth = 1.3);

    canvas.drawPath(
        Path()..addPolygon([apex, sCL, bCL, bCR, sCR], true),
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, 0.1),
            radius: 0.55,
            colors: [color.withOpacity(0.48), color.withOpacity(0.0)],
          ).createShader(
              Rect.fromLTWH(w * 0.28, h * 0.08, w * 0.44, h * 0.62)));

    for (final pair in [
      [apex, bL, 0.45],
      [apex, bR, 0.28]
    ]) {
      canvas.drawLine(
          pair[0] as Offset,
          pair[1] as Offset,
          Paint()
            ..color = color.withOpacity(pair[2] as double)
            ..strokeWidth = 2.8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }

    canvas.drawCircle(
        Offset(w * 0.46, h * 0.11),
        5,
        Paint()
          ..color = Colors.white.withOpacity(0.92)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(
        Offset(w * 0.46, h * 0.11), 2.2, Paint()..color = Colors.white);
  }

  void _drawBeamGlow(Canvas canvas, double w, double h) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * 0.50, h * 0.40),
            width: w * 1.05,
            height: h * 0.70),
        Paint()
          ..color = color.withOpacity(0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * 0.50, h * 0.30),
            width: w * 0.52,
            height: h * 0.42),
        Paint()
          ..color = color.withOpacity(0.38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    final br = Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.30), width: w * 0.18, height: h * 0.56);
    canvas.drawRect(
        br,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withOpacity(0.0),
              color.withOpacity(0.50),
              Colors.white.withOpacity(0.15)
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(br)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  }

  void _drawSparkles(Canvas canvas, double w, double h) {
    final pts = [
      (w * 0.10, h * 0.22, 2.0),
      (w * 0.90, h * 0.18, 1.7),
      (w * 0.06, h * 0.50, 1.5),
      (w * 0.94, h * 0.44, 1.8),
      (w * 0.18, h * 0.60, 1.3),
      (w * 0.84, h * 0.58, 1.4),
      (w * 0.50, h * 0.05, 2.3),
      (w * 0.28, h * 0.13, 1.6),
      (w * 0.74, h * 0.11, 1.5),
    ];
    for (final p in pts) {
      final ox = p.$1;
      final oy = p.$2;
      final r = p.$3;
      canvas.drawCircle(
          Offset(ox, oy),
          r * 2.8,
          Paint()
            ..color = color.withOpacity(0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      canvas.drawCircle(
          Offset(ox, oy), r, Paint()..color = Colors.white.withOpacity(0.92));
      final sp = Paint()
        ..color = Colors.white.withOpacity(0.50)
        ..strokeWidth = 0.6;
      canvas.drawLine(Offset(ox - r * 2.2, oy), Offset(ox + r * 2.2, oy), sp);
      canvas.drawLine(Offset(ox, oy - r * 2.2), Offset(ox, oy + r * 2.2), sp);
    }
  }

  @override
  bool shouldRepaint(_PortalCrystalPainter old) => old.color != color;
}
