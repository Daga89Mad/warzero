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

  const CellSidebar({
    super.key,
    required this.celda,
    required this.coord,
    required this.terrain,
    required this.isOpen,
    required this.onClose,
    this.isEnemyObelisco = false,
    this.localUid,
    this.onMoveSelected,
    this.playerColors = const {},
    this.energiasDisponibles,
    this.resolveEvolucion,
    this.onEvolucionar,
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

    // Movimiento mínimo entre cartas seleccionadas
    int? minMov;
    if (_selected.isNotEmpty) {
      minMov = _selected
          .map((i) => cards[i].carta.movimiento)
          .reduce((a, b) => a < b ? a : b);
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
              onClose: widget.onClose),
          const Divider(color: Color(0x30503214), height: 1),

          Expanded(
            child: _Body(
              celda: widget.celda,
              coord: widget.coord,
              terrain: widget.terrain,
              isEnemyObelisco: widget.isEnemyObelisco,
              localUid: widget.localUid,
              selected: _selected,
              onToggle: _toggle,
              playerColors: widget.playerColors,
              energiasDisponibles: widget.energiasDisponibles,
              resolveEvolucion: widget.resolveEvolucion,
              onEvolucionar: widget.onEvolucionar,
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
  final VoidCallback onClose;
  const _Header(
      {required this.coord,
      required this.terrain,
      required this.total,
      required this.onClose});

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
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (total != null && total! > 0) ...[
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
              const SizedBox(height: 4),
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
// BODY
// ─────────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  final CeldaState? celda;
  final String? coord;
  final TerrainType? terrain;
  final bool isEnemyObelisco;
  final String? localUid;
  final Set<int> selected;
  final void Function(int) onToggle;
  final Map<String, Color> playerColors;

  // Evolución
  final int? energiasDisponibles;
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;
  final Future<void> Function(String coord, int indice, CartaModel evolucion)?
      onEvolucionar;

  const _Body({
    required this.celda,
    required this.coord,
    required this.terrain,
    required this.isEnemyObelisco,
    required this.localUid,
    required this.selected,
    required this.onToggle,
    this.playerColors = const {},
    this.energiasDisponibles,
    this.resolveEvolucion,
    this.onEvolucionar,
  });

  @override
  Widget build(BuildContext context) {
    final cards = celda?.cartas ?? [];
    // ── Cuartel enemigo ──────────────────────────────────────
    if (isEnemyObelisco && cards.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CUARTEL ENEMIGO',
              style: TextStyle(
                  fontSize: 8,
                  color: Color(0xFFC04040),
                  fontFamily: 'Cinzel',
                  letterSpacing: 2)),
          const SizedBox(height: 12),
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
    // Solo evolucionar cartas propias con evolución configurada
    final puedeEvolucionar = isLocal &&
        onEvolucionar != null &&
        coord != null &&
        entry.carta.puedeEvolucionar;

    showCardDetail(
      ctx,
      entry.carta,
      resolveEvolucion: resolveEvolucion,
      energiasDisponibles: puedeEvolucionar ? energiasDisponibles : null,
      onEvolucionar: puedeEvolucionar
          ? (evolucion) => onEvolucionar!(coord!, indice, evolucion)
          : null,
    );
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
                        _Chip(label: 'MOV ${carta.movimiento}', color: color),
                        const SizedBox(width: 4),
                        _Chip(
                            label: _ownerLabel(entry.ownerZone), color: color),
                        if (carta.puedeEvolucionar) ...[
                          const SizedBox(width: 4),
                          _Chip(
                              label: 'EVOL ${carta.evolucion}⚡',
                              color: const Color(0xFFC060E0)),
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
