// lib/widgets/cell_sidebar.dart

import 'package:flutter/material.dart';
import '../models/board_state.dart';
import '../models/carta_model.dart';
import '../models/game_config.dart';
import 'cell_widget.dart' show ownerColor;
import 'card_detail_overlay.dart';

// ─────────────────────────────────────────────────────────────
// CELL SIDEBAR
// ─────────────────────────────────────────────────────────────
class CellSidebar extends StatefulWidget {
  final CeldaState? celda;
  final String? coord;
  final TerrainType? terrain;
  final bool isOpen;
  final VoidCallback onClose;

  /// True → cuartel enemigo, ocultar detalles
  final bool isEnemyObelisco;

  /// True → esta celda es cualquier cuartel general (propio o enemigo)
  final bool isObelisco;

  /// UID del jugador local — determina qué cartas son movibles
  final String? localUid;

  /// Callback con los índices seleccionados cuando el jugador pulsa MOVER
  final void Function(List<int> indices)? onMoveSelected;

  /// uid → color para colorear cartas por jugador
  final Map<String, Color> playerColors;

  // ── Sistema de evoluciones ───────────────────────────────
  final int? energiasDisponibles;
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;
  final Future<void> Function(String coord, int indice, CartaModel evolucion)?
      onEvolucionar;

  static const double width = 220;

  /// Turno actual de la partida (para calcular enfriamiento de habilidades).
  final int turnoActual;

  /// Callback al pulsar LANZAR HABILIDAD en una carta del tablero.
  /// Recibe (carta, coord, indiceDentroDeLaCelda).
  final Future<void> Function(CartaEnCelda carta, String coord, int indice)?
      onLanzarHabilidad;

  /// Defensa base de cualquier cuartel general.
  static const int defensaBase = 80;

  const CellSidebar({
    super.key,
    required this.celda,
    required this.coord,
    required this.terrain,
    required this.isOpen,
    required this.onClose,
    this.isEnemyObelisco = false,
    this.isObelisco = false,
    this.localUid,
    this.onMoveSelected,
    this.playerColors = const {},
    this.energiasDisponibles,
    this.resolveEvolucion,
    this.onEvolucionar,
    this.turnoActual = 1, // NUEVO
    this.onLanzarHabilidad, // NUEVO
  });

  @override
  State<CellSidebar> createState() => _CellSidebarState();
}

class _CellSidebarState extends State<CellSidebar> {
  final Set<int> _selected = {};

  @override
  void didUpdateWidget(CellSidebar old) {
    super.didUpdateWidget(old);
    // Limpiar al cambiar de celda o al cerrar
    if (old.coord != widget.coord || (!widget.isOpen && old.isOpen)) {
      setState(() => _selected.clear());
    }
  }

  void _toggle(int i) => setState(
      () => _selected.contains(i) ? _selected.remove(i) : _selected.add(i));

  void _confirmMove() {
    if (_selected.isEmpty) return;
    widget.onMoveSelected?.call(List<int>.from(_selected)..sort());
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.celda?.cartas ?? [];
    final hasLocal = cards.any((c) => c.ownerUid == widget.localUid);
    final localCount = cards.where((c) => c.ownerUid == widget.localUid).length;
    final total = widget.isEnemyObelisco ? null : widget.celda?.fuerzaTotal;
    // Para obeliscos: siempre incluir los 80 de defensa base.
    // Cuartel enemigo → solo base (no revelamos las cartas enemigas).
    // Cuartel propio  → base + defensa de las cartas.
    // Celda normal    → solo defensa de las cartas (null si no hay cartas).
    final int? defensa;
    int defensaReducida = 0;
    if (widget.isEnemyObelisco) {
      defensa = CellSidebar.defensaBase;
    } else if (widget.isObelisco) {
      defensa =
          CellSidebar.defensaBase + (widget.celda?.defensaTotalEfectiva ?? 0);
      defensaReducida = (widget.celda?.defensaTotal ?? 0) -
          (widget.celda?.defensaTotalEfectiva ?? 0);
    } else {
      final d = widget.celda?.defensaTotalEfectiva;
      defensa = (d != null && d > 0) ? d : null;
      defensaReducida = (widget.celda?.defensaTotal ?? 0) -
          (widget.celda?.defensaTotalEfectiva ?? 0);
    }

    // Movimiento mínimo entre cartas seleccionadas
    int? minMov;
    if (_selected.isNotEmpty) {
      minMov = _selected
          .map((i) => cards[i].carta.movimiento)
          .reduce((a, b) => a < b ? a : b);
    }

    // Totales por ejército: en celdas en disputa (varios dueños) se muestran
    // por separado en vez de sumar fuerza/defensa de ambos.
    final ejercitos = <_ArmyTotal>[];
    if (!widget.isEnemyObelisco && !widget.isObelisco) {
      final byUid = <String, _ArmyTotal>{};
      for (final c in cards) {
        final prev = byUid[c.ownerUid];
        byUid[c.ownerUid] = _ArmyTotal(
          uid: c.ownerUid,
          zone: c.ownerZone,
          esLocal: c.ownerUid == widget.localUid,
          fuerza: (prev?.fuerza ?? 0) + c.carta.fuerza,
          defensa: (prev?.defensa ?? 0) + c.defensaEfectiva,
          reduccion: (prev?.reduccion ?? 0) + c.defensaReducidaPorEfectos,
          color: widget.playerColors[c.ownerUid] ?? ownerColor(c.ownerZone),
        );
      }
      ejercitos.addAll(byUid.values);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      width: CellSidebar.width,
      transform: Matrix4.translationValues(
          widget.isOpen ? 0 : CellSidebar.width, 0, 0),
      decoration: const BoxDecoration(
        color: Color(0xF7030812),
        border: Border(left: BorderSide(color: Color(0x40503214), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            coord: widget.coord,
            terrain: widget.terrain,
            total: total,
            defensa: defensa,
            defensaReducida: defensaReducida,
            ejercitos: ejercitos,
            isObelisco: widget.isObelisco,
            isEnemyObelisco: widget.isEnemyObelisco,
            onClose: widget.onClose,
          ),
          const Divider(color: Color(0x30503214), height: 1),

          Expanded(
            child: _Body(
              celda: widget.celda,
              coord: widget.coord,
              terrain: widget.terrain,
              isEnemyObelisco: widget.isEnemyObelisco,
              isObelisco: widget.isObelisco,
              localUid: widget.localUid,
              selected: _selected,
              onToggle: _toggle,
              playerColors: widget.playerColors,
              energiasDisponibles: widget.energiasDisponibles,
              resolveEvolucion: widget.resolveEvolucion,
              onEvolucionar: widget.onEvolucionar,
              turnoActual: widget.turnoActual, // NUEVO
              onLanzarHabilidad: widget.onLanzarHabilidad, // NUEVO
            ),
          ),

          // Botón MOVER solo cuando hay cartas propias y onMoveSelected definido
          if (!widget.isEnemyObelisco &&
              hasLocal &&
              widget.onMoveSelected != null)
            _MoveButton(
              selected: _selected.length,
              total: localCount,
              minMov: minMov,
              onTap: _selected.isEmpty ? null : _confirmMove,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String? coord;
  final TerrainType? terrain;
  final int? total;
  final int? defensa;
  final int defensaReducida;
  final List<_ArmyTotal> ejercitos;
  final bool isObelisco;
  final bool isEnemyObelisco;
  final VoidCallback onClose;

  const _Header({
    required this.coord,
    required this.terrain,
    required this.total,
    required this.defensa,
    this.defensaReducida = 0,
    this.ejercitos = const [],
    required this.isObelisco,
    required this.isEnemyObelisco,
    required this.onClose,
  });

  Widget _armyBlock(_ArmyTotal a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(a.esLocal ? 'TÚ' : _ownerZoneLabel(a.zone),
            style: TextStyle(
                fontSize: 7,
                color: a.color,
                letterSpacing: 1.5,
                fontFamily: 'Cinzel')),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('⚔ ',
              style: TextStyle(fontSize: 9, color: Color(0xFFE0C060))),
          Text('${a.fuerza}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE0C060),
                  fontFamily: 'Cinzel',
                  height: 1)),
          const SizedBox(width: 8),
          Text(a.reduccion > 0 ? '☠ ' : '🛡 ',
              style: const TextStyle(fontSize: 9)),
          Text('${a.defensa}',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: a.reduccion > 0
                      ? const Color(0xFF5AD07A)
                      : const Color(0xFF60A0D0),
                  fontFamily: 'Cinzel',
                  height: 1)),
          if (a.reduccion > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text('-${a.reduccion}',
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2BA046),
                      fontFamily: 'Cinzel',
                      height: 1)),
            ),
        ]),
      ]),
    );
  }

  static String _ownerZoneLabel(String zone) {
    const m = {
      'north': 'NORTE',
      'south': 'SUR',
      'west': 'OESTE',
      'east': 'ESTE',
      'ne': 'NE',
      'nw': 'NO',
      'se': 'SE',
      'sw': 'SO'
    };
    return m[zone] ?? zone.toUpperCase();
  }

  String _label(TerrainType? t) {
    switch (t) {
      case TerrainType.deepSea:
        return 'MAR PROFUNDO';
      case TerrainType.sea:
        return 'AGUAS COSTERAS';
      case TerrainType.amphibious:
        return 'TIERRA / AGUA';
      default:
        return 'TIERRA FIRME';
    }
  }

  String _terrainIcon(TerrainType? t) {
    switch (t) {
      case TerrainType.deepSea:
      case TerrainType.sea:
        return '〰';
      case TerrainType.amphibious:
        return '⚓';
      default:
        return '';
    }
  }

  String _terrainDesc(TerrainType? t) {
    switch (t) {
      case TerrainType.deepSea:
        return 'Mar profundo. Solo unidades marinas pueden moverse y detenerse aquí. Las unidades voladoras pueden sobrevolarlo pero no aterrizar.';
      case TerrainType.sea:
        return 'Aguas costeras. Solo unidades marinas pueden moverse y detenerse aquí. Las unidades voladoras pueden sobrevolarlo pero no aterrizar.';
      case TerrainType.amphibious:
        return 'Tierra y agua. Cualquier tipo de unidad puede moverse y detenerse aquí: terrestres, marinas y voladoras.';
      default:
        return 'Tierra firme. Las unidades terrestres y voladoras pueden moverse y detenerse aquí. Las unidades marinas no pueden acceder.';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Color del cuartel: rojo para enemigo, dorado para propio
    const ownColor = Color(0xFFC8A860);
    const enemyColor = Color(0xFFC04040);
    final hqColor = isEnemyObelisco ? enemyColor : ownColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(coord ?? '—',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC8A860),
                      fontFamily: 'Cinzel',
                      height: 1)),
              const SizedBox(height: 4),
              // Etiqueta de cuartel general — sustituye etiqueta de terreno
              if (isObelisco) ...[
                Text(
                  isEnemyObelisco
                      ? '🏚  CUARTEL ENEMIGO'
                      : '🏰  CUARTEL GENERAL',
                  style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.5,
                      color: hqColor,
                      fontFamily: 'Cinzel'),
                ),
                const SizedBox(height: 6),
                // Badge de defensa base
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: hqColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: hqColor.withOpacity(0.35), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield, size: 11, color: hqColor),
                      const SizedBox(width: 4),
                      Text(
                        'DEFENSA BASE  ${CellSidebar.defensaBase}',
                        style: TextStyle(
                            fontSize: 8,
                            color: hqColor,
                            fontFamily: 'Cinzel',
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(children: [
                  if (_terrainIcon(terrain).isNotEmpty) ...[
                    Text(_terrainIcon(terrain),
                        style: const TextStyle(fontSize: 11, height: 1)),
                    const SizedBox(width: 5),
                  ],
                  Text(_label(terrain),
                      style: const TextStyle(
                          fontSize: 8,
                          letterSpacing: 2,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel')),
                ]),
                const SizedBox(height: 6),
                Text(_terrainDesc(terrain),
                    style: const TextStyle(
                        fontSize: 8,
                        color: Color(0xFF304555),
                        height: 1.6,
                        fontFamily: 'Cinzel',
                        letterSpacing: 0.2)),
              ],
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Celda en disputa: un bloque por ejército (no se suman entre sí).
            if (ejercitos.length > 1) ...ejercitos.map(_armyBlock),
            if (ejercitos.length <= 1 && defensa != null) ...[
              Text(defensaReducida > 0 ? '☠ DEFENSA' : 'DEFENSA',
                  style: TextStyle(
                      fontSize: 7,
                      color: defensaReducida > 0
                          ? const Color(0xFF2BA046)
                          : const Color(0xFF506070),
                      letterSpacing: 1.5,
                      fontFamily: 'Cinzel')),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$defensa',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: defensaReducida > 0
                            ? const Color(0xFF5AD07A)
                            : const Color(0xFF60A0D0),
                        fontFamily: 'Cinzel',
                        height: 1)),
                if (defensaReducida > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Text('-$defensaReducida',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2BA046),
                            fontFamily: 'Cinzel',
                            height: 1)),
                  ),
              ]),
              const SizedBox(height: 6),
            ],
            if (ejercitos.length <= 1 && total != null && total! > 0) ...[
              const Text('FUERZA',
                  style: TextStyle(
                      fontSize: 7,
                      color: Color(0xFF506070),
                      letterSpacing: 1.5,
                      fontFamily: 'Cinzel')),
              Text('$total',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE0C060),
                      fontFamily: 'Cinzel',
                      height: 1)),
              const SizedBox(height: 6),
            ],
            GestureDetector(
              onTap: onClose,
              child:
                  const Icon(Icons.close, size: 18, color: Color(0xFF506070)),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Totales de un ejército dentro de una celda en disputa.
// ─────────────────────────────────────────────────────────────
class _ArmyTotal {
  final String uid;
  final String zone;
  final bool esLocal;
  final int fuerza;
  final int defensa;
  final int reduccion;
  final Color color;
  const _ArmyTotal({
    required this.uid,
    required this.zone,
    required this.esLocal,
    required this.fuerza,
    required this.defensa,
    required this.reduccion,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────
// BODY
// ─────────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  final CeldaState? celda;
  final String? coord;
  final TerrainType? terrain;
  final bool isEnemyObelisco;
  final bool isObelisco;
  final String? localUid;
  final Set<int> selected;
  final void Function(int) onToggle;
  final Map<String, Color> playerColors;

  // Evolución
  final int? energiasDisponibles;
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;
  final Future<void> Function(String coord, int indice, CartaModel evolucion)?
      onEvolucionar;

  // Habilidad
  final int turnoActual;
  final Future<void> Function(CartaEnCelda carta, String coord, int indice)?
      onLanzarHabilidad;

  const _Body({
    required this.celda,
    required this.coord,
    required this.terrain,
    required this.isEnemyObelisco,
    required this.isObelisco,
    required this.localUid,
    required this.selected,
    required this.onToggle,
    this.playerColors = const {},
    this.energiasDisponibles,
    this.resolveEvolucion,
    this.onEvolucionar,
    this.turnoActual = 1,
    this.onLanzarHabilidad,
  });

  @override
  Widget build(BuildContext context) {
    final cards = celda?.cartas ?? [];

    // ── Cuartel enemigo con cartas ───────────────────────────
    if (isEnemyObelisco && cards.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x30C04040), width: 1),
            ),
            child: Column(children: [
              const Icon(Icons.lock, size: 22, color: Color(0xFF506070)),
              const SizedBox(height: 8),
              Text(
                  '${cards.length} ${cards.length == 1 ? 'unidad' : 'unidades'}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC04040),
                      fontFamily: 'Cinzel',
                      height: 1)),
              const SizedBox(height: 4),
              const Text('INFORMACIÓN\nCLASIFICADA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 7,
                      color: Color(0xFF506070),
                      fontFamily: 'Cinzel',
                      letterSpacing: 2,
                      height: 1.6)),
            ]),
          ),
        ]),
      );
    }

    // ── Cuartel enemigo vacío ────────────────────────────────
    if (isEnemyObelisco && cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x30C04040), width: 1),
            ),
            child: Column(children: [
              const Icon(Icons.shield_outlined,
                  size: 22, color: Color(0xFFC04040)),
              const SizedBox(height: 8),
              const Text('SIN DEFENSORES',
                  style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFFC04040),
                      fontFamily: 'Cinzel',
                      letterSpacing: 1.5)),
              const SizedBox(height: 4),
              const Text(
                'El cuartel resiste con\ndefensa propia (80).',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 7,
                    color: Color(0xFF506070),
                    fontFamily: 'Cinzel',
                    letterSpacing: 1,
                    height: 1.6),
              ),
            ]),
          ),
        ]),
      );
    }

    // ── Celda vacía (no obelisco) ────────────────────────────
    if (cards.isEmpty) {
      return const Center(
        child: Text('CELDA VACÍA',
            style: TextStyle(
                fontSize: 10,
                color: Color(0xFF354050),
                letterSpacing: 1,
                fontFamily: 'Cinzel')),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      itemCount: cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _CardTile(
        entry: cards[i],
        indice: i,
        coord: coord,
        isLocal: cards[i].ownerUid == localUid,
        isChecked: selected.contains(i),
        onToggle: cards[i].ownerUid == localUid ? () => onToggle(i) : null,
        playerColors: playerColors,
        energiasDisponibles: energiasDisponibles,
        resolveEvolucion: resolveEvolucion,
        onEvolucionar: onEvolucionar,
        turnoActual: turnoActual,
        onLanzarHabilidad: onLanzarHabilidad,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARD TILE
// ─────────────────────────────────────────────────────────────
class _CardTile extends StatelessWidget {
  final CartaEnCelda entry;
  final int indice;
  final String? coord;
  final bool isLocal;
  final bool isChecked;
  final VoidCallback? onToggle;
  final Map<String, Color> playerColors;
  final int turnoActual;
  final Future<void> Function(CartaEnCelda carta, String coord, int indice)?
      onLanzarHabilidad;
  // Evolución
  final int? energiasDisponibles;
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;
  final Future<void> Function(String coord, int indice, CartaModel evolucion)?
      onEvolucionar;

  const _CardTile({
    required this.entry,
    required this.indice,
    required this.coord,
    required this.isLocal,
    required this.isChecked,
    required this.onToggle,
    this.playerColors = const {},
    this.energiasDisponibles,
    this.resolveEvolucion,
    this.onEvolucionar,
    this.turnoActual = 1,
    this.onLanzarHabilidad,
  });

  String _ownerLabel(String zone) {
    const m = {
      'north': 'NORTE',
      'south': 'SUR',
      'west': 'OESTE',
      'east': 'ESTE',
      'ne': 'NE',
      'nw': 'NO',
      'se': 'SE',
      'sw': 'SO'
    };
    return m[zone] ?? zone.toUpperCase();
  }

  void _abrirDetalle(BuildContext ctx) {
    final puedeEvolucionar = isLocal &&
        onEvolucionar != null &&
        coord != null &&
        entry.carta.puedeEvolucionar;

    // ── Habilidad: visible solo si la carta es propia, tiene habilidad
    //     en el catálogo y se ha pasado un callback. El cooldown se
    //     calcula desde ultimoUsoHabilidad y enfriamientoHabilidad.
    final puedeLanzar = isLocal &&
        coord != null &&
        onLanzarHabilidad != null &&
        entry.carta.tieneHabilidad;

    final enfriamientoRestante =
        puedeLanzar ? _calcularEnfriamientoRestante(entry, turnoActual) : 0;

    showCardDetail(
      ctx,
      entry.carta,
      resolveEvolucion: resolveEvolucion,
      energiasDisponibles:
          (puedeEvolucionar || puedeLanzar) ? energiasDisponibles : null,
      onEvolucionar: puedeEvolucionar
          ? (evolucion) => onEvolucionar!(coord!, indice, evolucion)
          : null,
      onLanzarHabilidad:
          puedeLanzar ? () => onLanzarHabilidad!(entry, coord!, indice) : null,
      enfriamientoRestante: enfriamientoRestante,
      defensaReducida: entry.defensaReducidaPorEfectos,
      defensaExtra: entry.defensaExtraPorEfectos,
      paralizada: entry.paralizado,
    );
  }

  static int _calcularEnfriamientoRestante(
      CartaEnCelda entry, int turnoActual) {
    if (entry.ultimoUsoHabilidad == null) return 0;
    final transcurridos = turnoActual - entry.ultimoUsoHabilidad!;
    final restante = entry.carta.enfriamientoHabilidad - transcurridos + 1;
    return restante > 0 ? restante : 0;
  }

  @override
  Widget build(BuildContext context) {
    final carta = entry.carta;
    final color = playerColors.containsKey(entry.ownerUid)
        ? playerColors[entry.ownerUid]!
        : ownerColor(entry.ownerZone);
    final border =
        isChecked ? const Color(0xFF40B0FF) : const Color(0x40322814);

    return Builder(
      builder: (ctx) => GestureDetector(
        onTap: onToggle,
        onLongPress: () => _abrirDetalle(ctx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: isChecked
                ? const Color(0xFF40B0FF).withOpacity(0.08)
                : const Color(0xFF0A1220),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: border, width: isChecked ? 1.2 : 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox (solo cartas locales)
              if (isLocal)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isChecked
                          ? const Color(0xFF40B0FF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isChecked
                            ? const Color(0xFF40B0FF)
                            : const Color(0xFF506070),
                        width: 1.2,
                      ),
                    ),
                    child: isChecked
                        ? const Icon(Icons.check,
                            size: 11, color: Color(0xFF030810))
                        : null,
                  ),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: color.withOpacity(0.25), width: 0.5),
                  ),
                  child: Icon(Icons.shield, size: 13, color: color),
                ),

              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(carta.nombre,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: isChecked
                                          ? const Color(0xFF80D0FF)
                                          : const Color(0xFFC8A860),
                                      letterSpacing: 1,
                                      fontFamily: 'Cinzel')),
                            ),
                            if (entry.envenenada) ...[
                              const Text('☠',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF2BA046))),
                              const SizedBox(width: 4),
                              Text('🛡${entry.defensaEfectiva}',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF5AD07A),
                                      fontFamily: 'Cinzel')),
                              const SizedBox(width: 6),
                            ],
                            if (entry.paralizado) ...[
                              const Text('⏱',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF2C90C8))),
                              const SizedBox(width: 6),
                            ],
                            if (entry.escudada) ...[
                              const Text('🛡',
                                  style: TextStyle(
                                      fontSize: 10, color: Color(0xFF6AB0FF))),
                              const SizedBox(width: 2),
                              Text('${entry.defensaEfectiva}',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF9AD0FF),
                                      fontFamily: 'Cinzel')),
                              const SizedBox(width: 6),
                            ],
                            Text('${carta.fuerza}',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                    fontFamily: 'Cinzel')),
                          ]),
                      const SizedBox(height: 4),
                      Text(carta.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 8,
                              color: Color(0xFF3D5060),
                              height: 1.5,
                              fontFamily: 'Georgia')),
                      const SizedBox(height: 5),
                      Row(children: [
                        _Chip(
                            label: 'MOV ${carta.movimientoEfectivo}',
                            color: color),
                        const SizedBox(width: 4),
                        _Chip(
                            label: _ownerLabel(entry.ownerZone), color: color),
                        if (carta.condicion != CondicionCarta.basica) ...[
                          const SizedBox(width: 4),
                          _Chip(
                              label:
                                  '${carta.condicion.icon} ${carta.condicion.label.toUpperCase()}',
                              color: Color(carta.condicion.colorValue)),
                        ],
                        if (carta.puedeEvolucionar) ...[
                          const SizedBox(width: 4),
                          _EvolChip(coste: carta.evolucion),
                        ],
                      ]),
                    ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTÓN MOVER
// ─────────────────────────────────────────────────────────────
class _MoveButton extends StatelessWidget {
  final int selected;
  final int total;
  final int? minMov;
  final VoidCallback? onTap;

  const _MoveButton({
    required this.selected,
    required this.total,
    required this.minMov,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final accent = active ? const Color(0xFF40B0FF) : const Color(0xFF354050);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x20506070), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                active ? '$selected/$total SELECCIONADAS' : 'TOCA UNA CARTA',
                style: TextStyle(
                    fontSize: 8,
                    color: accent,
                    fontFamily: 'Cinzel',
                    letterSpacing: 1),
              ),
              if (active && minMov != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF40B0FF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                        color: const Color(0xFF40B0FF).withOpacity(0.4),
                        width: 0.5),
                  ),
                  child: Text('MOV $minMov',
                      style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF40B0FF),
                          fontFamily: 'Cinzel',
                          letterSpacing: 1)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF40B0FF).withOpacity(0.14)
                    : const Color(0xFF0A1220),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: active
                      ? const Color(0xFF40B0FF).withOpacity(0.55)
                      : const Color(0x25506070),
                  width: 1,
                ),
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.open_with, size: 13, color: accent),
                const SizedBox(width: 7),
                Text(
                  active ? 'MOVER SELECCIÓN' : 'MOVER',
                  style: TextStyle(
                      fontSize: 9,
                      color: accent,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHIP EVOLUCIÓN — solo icono + coste, sin texto "EVOL"
// ─────────────────────────────────────────────────────────────
class _EvolChip extends StatelessWidget {
  final int coste;
  const _EvolChip({required this.coste});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFC060E0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward, size: 8, color: color),
          const SizedBox(width: 2),
          Text('$coste⚡',
              style: const TextStyle(
                  fontSize: 7,
                  color: color,
                  letterSpacing: 0.5,
                  fontFamily: 'Cinzel')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 7,
              color: color,
              letterSpacing: 1,
              fontFamily: 'Cinzel')),
    );
  }
}
