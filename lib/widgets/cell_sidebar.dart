// lib/widgets/cell_sidebar.dart

import 'package:flutter/material.dart';
import '../models/board_state.dart';
import '../models/carta_model.dart';
import '../models/efecto_estado.dart';
import '../models/game_config.dart';
import 'cell_widget.dart' show ownerColor, ZeroChip;
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

  /// `instanceId` de las cartas que YA se movieron este turno. Para esas cartas
  /// el botón inferior pasa a ser DESHACER (en vez de MOVER) y la selección no
  /// puede mezclar cartas movidas con cartas sin mover.
  final Set<String> movedInstanceIds;

  /// Callback con los índices seleccionados cuando el jugador pulsa DESHACER.
  /// Devuelve cada carta movida a su posición anterior a este turno.
  final void Function(List<int> indices)? onUndoSelected;

  /// uid → color para colorear cartas por jugador
  final Map<String, Color> playerColors;

  /// Efectos de ACCIÓN activos sobre ESTA celda (veneno de celda, escudo,
  /// parálisis, potenciaciones…), tal y como los persiste el servidor en
  /// `efectosCelda[coord]`. Se combinan con los efectos que arrastran las
  /// cartas para pintar el indicador de acciones activas de la cabecera.
  final List<EfectoActivo> efectosCelda;

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
  static const int defensaBase = 40;

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
    this.movedInstanceIds = const {},
    this.onUndoSelected,
    this.playerColors = const {},
    this.efectosCelda = const [], // NUEVO
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

  /// True si la carta [i] ya se movió este turno (candidata a DESHACER).
  bool _isMoved(int i) {
    final cards = widget.celda?.cartas ?? const [];
    if (i < 0 || i >= cards.length) return false;
    return widget.movedInstanceIds.contains(cards[i].instanceId);
  }

  /// Categoría de la selección actual:
  ///   true  → todas las seleccionadas se han movido (modo DESHACER)
  ///   false → todas las seleccionadas están sin mover (modo MOVER)
  ///   null  → no hay nada seleccionado
  ///
  /// La selección es homogénea: al elegir la primera carta se fija la categoría
  /// y solo se pueden seleccionar más cartas de esa misma categoría.
  bool? get _selectionUndo {
    if (_selected.isEmpty) return null;
    return _isMoved(_selected.first);
  }

  /// ¿Se puede marcar/desmarcar la carta [i]? Siempre se permite desmarcar una
  /// ya seleccionada; para marcar una nueva debe coincidir con la categoría de
  /// la selección (movida vs. sin mover). Si no hay selección, todo vale.
  bool _puedeToggle(int i) {
    if (_selected.contains(i)) return true;
    final cat = _selectionUndo;
    if (cat == null) return true;
    return _isMoved(i) == cat;
  }

  void _toggle(int i) {
    if (!_puedeToggle(i)) return; // check deshabilitado por exclusión mutua
    setState(
        () => _selected.contains(i) ? _selected.remove(i) : _selected.add(i));
  }

  void _confirmMove() {
    if (_selected.isEmpty) return;
    widget.onMoveSelected?.call(List<int>.from(_selected)..sort());
    setState(() => _selected.clear());
  }

  void _confirmUndo() {
    if (_selected.isEmpty) return;
    widget.onUndoSelected?.call(List<int>.from(_selected)..sort());
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.celda?.cartas ?? [];
    final hasLocal = cards.any((c) => c.ownerUid == widget.localUid);
    final localCount = cards.where((c) => c.ownerUid == widget.localUid).length;
    final total =
        widget.isEnemyObelisco ? null : widget.celda?.fuerzaTotalEfectiva;
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
          fuerza: (prev?.fuerza ?? 0) + c.fuerzaEfectiva,
          defensa: (prev?.defensa ?? 0) + c.defensaEfectiva,
          reduccion: (prev?.reduccion ?? 0) + c.defensaReducidaPorEfectos,
          color: widget.playerColors[c.ownerUid] ?? ownerColor(c.ownerZone),
          tipos: {...(prev?.tipos ?? const <int>{}), c.carta.tipo},
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
              movedInstanceIds: widget.movedInstanceIds,
              isEnabled: _puedeToggle,
              playerColors: widget.playerColors,
              efectosCelda: widget.efectosCelda, // NUEVO
              energiasDisponibles: widget.energiasDisponibles,
              resolveEvolucion: widget.resolveEvolucion,
              onEvolucionar: widget.onEvolucionar,
              turnoActual: widget.turnoActual, // NUEVO
              onLanzarHabilidad: widget.onLanzarHabilidad, // NUEVO
            ),
          ),

          // Botón inferior: DESHACER si la selección son cartas ya movidas;
          // MOVER en cualquier otro caso. Solo con cartas propias en la celda.
          if (!widget.isEnemyObelisco &&
              hasLocal &&
              (widget.onMoveSelected != null || widget.onUndoSelected != null))
            (_selectionUndo == true)
                ? _UndoButton(
                    selected: _selected.length,
                    onTap: _selected.isEmpty ? null : _confirmUndo,
                  )
                : _MoveButton(
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
        Text(a.esLocal ? 'TÚ' : _tipoArmyLabel(a.tipos),
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

  /// Tipos de las cartas de este ejército en la celda (1=tierra, 2=aire, 3=mar).
  /// Se usa para etiquetar el bloque con TIERRA/AIRE/MAR (o MIXTO si hay varios).
  final Set<int> tipos;

  const _ArmyTotal({
    required this.uid,
    required this.zone,
    required this.esLocal,
    required this.fuerza,
    required this.defensa,
    required this.reduccion,
    required this.color,
    this.tipos = const {},
  });
}

/// Etiqueta del TIPO de una carta: 1=TIERRA, 2=AIRE, 3=MAR. Sustituye a la
/// antigua etiqueta de zona (SUR/SE…) en el menú lateral.
String _tipoLabel(int tipo) {
  switch (tipo) {
    case 1:
      return 'TIERRA';
    case 2:
      return 'AIRE';
    case 3:
      return 'MAR';
    default:
      return '—';
  }
}

/// Etiqueta de tipo para un conjunto de cartas (un ejército en la celda): el
/// tipo si todas comparten uno, o MIXTO si hay varios.
String _tipoArmyLabel(Set<int> tipos) {
  if (tipos.isEmpty) return '—';
  if (tipos.length == 1) return _tipoLabel(tipos.first);
  return 'MIXTO';
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

  /// `instanceId` de las cartas ya movidas este turno (candidatas a DESHACER).
  final Set<String> movedInstanceIds;

  /// ¿Se puede marcar/desmarcar la carta [i]? (exclusión mutua movida/sin mover)
  final bool Function(int index) isEnabled;

  final Map<String, Color> playerColors;

  /// Efectos de acción activos sobre la celda (fuente: `efectosCelda[coord]`).
  final List<EfectoActivo> efectosCelda;

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
    required this.movedInstanceIds,
    required this.isEnabled,
    this.playerColors = const {},
    this.efectosCelda = const [],
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
                'El cuartel resiste con\ndefensa propia (40).',
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

    // ── Indicador de ACCIONES ACTIVAS sobre la celda ─────────
    // Combina los efectos de celda (efectosCelda) con los que arrastran las
    // cartas presentes. Cada chip muestra icono + turnos restantes; al pulsar,
    // si el efecto afecta a una carta concreta, abre su detalle.
    final efectosActivos = _EfectoCeldaEntry.recolectar(efectosCelda, cards);
    final Widget actionsBar = efectosActivos.isEmpty
        ? const SizedBox.shrink()
        : _CellActionsBar(entries: efectosActivos);

    // ── Celda vacía (no obelisco) ────────────────────────────
    if (cards.isEmpty) {
      // Aun sin unidades puede haber efectos de celda (p. ej. veneno lejano
      // colocado sobre una casilla vacía): mostramos el indicador arriba.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          actionsBar,
          const Expanded(
            child: Center(
              child: Text('CELDA VACÍA',
                  style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF354050),
                      letterSpacing: 1,
                      fontFamily: 'Cinzel')),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        actionsBar,
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final isLocal = cards[i].ownerUid == localUid;
              final moved = movedInstanceIds.contains(cards[i].instanceId);
              final enabled = isLocal && isEnabled(i);
              return _CardTile(
                entry: cards[i],
                indice: i,
                coord: coord,
                isLocal: isLocal,
                isChecked: selected.contains(i),
                moved: moved,
                enabled: enabled,
                // El check solo responde si la carta es propia y está habilitada
                // por la exclusión mutua (movidas vs. sin mover). El detalle
                // (pulsación larga) sigue disponible aunque el check lo esté.
                onToggle: enabled ? () => onToggle(i) : null,
                playerColors: playerColors,
                energiasDisponibles: energiasDisponibles,
                resolveEvolucion: resolveEvolucion,
                onEvolucionar: onEvolucionar,
                turnoActual: turnoActual,
                onLanzarHabilidad: onLanzarHabilidad,
              );
            },
          ),
        ),
      ],
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

  /// True si esta carta ya se movió este turno (candidata a DESHACER).
  final bool moved;

  /// True si el check puede pulsarse (exclusión mutua movida/sin mover). Cuando
  /// es false, la carta se atenúa para indicar que su check está deshabilitado.
  final bool enabled;

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
    this.moved = false,
    this.enabled = true,
    this.playerColors = const {},
    this.energiasDisponibles,
    this.resolveEvolucion,
    this.onEvolucionar,
    this.turnoActual = 1,
    this.onLanzarHabilidad,
  });

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
      fuerzaExtra: entry.fuerzaExtraPorEfectos,
      movimientoExtra: entry.movimientoExtraPorEfectos,
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
    // Carta propia cuyo check está deshabilitado por la exclusión mutua (no se
    // pueden mezclar cartas movidas con cartas sin mover): se atenúa para que
    // se vea que su check no está disponible en esta selección.
    final checkDeshabilitado = isLocal && !enabled;

    return Builder(
      builder: (ctx) => Opacity(
        opacity: checkDeshabilitado ? 0.42 : 1.0,
        child: GestureDetector(
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
                      border: Border.all(
                          color: color.withOpacity(0.25), width: 0.5),
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
                                        fontSize: 11,
                                        color: Color(0xFF2BA046))),
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
                                        fontSize: 11,
                                        color: Color(0xFF2C90C8))),
                                const SizedBox(width: 6),
                              ],
                              if (entry.defensaExtraPorEfectos > 0) ...[
                                const Text('🛡',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF6AB0FF))),
                                const SizedBox(width: 2),
                                Text('${entry.defensaEfectiva}',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF9AD0FF),
                                        fontFamily: 'Cinzel')),
                                const SizedBox(width: 6),
                              ],
                              if (entry.movimientoExtraPorEfectos > 0) ...[
                                const Text('💨',
                                    style: TextStyle(fontSize: 10)),
                                Text('${entry.movimientoEfectivo}',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF9AD0FF),
                                        fontFamily: 'Cinzel')),
                                const SizedBox(width: 6),
                              ],
                              if (entry.fuerzaExtraPorEfectos > 0)
                                const Text('💪',
                                    style: TextStyle(fontSize: 10)),
                              Text('${entry.fuerzaEfectiva}',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: entry.fuerzaExtraPorEfectos > 0
                                          ? const Color(0xFFFFB84D)
                                          : color,
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
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          if (moved)
                            const _Chip(
                                label: '↩ MOVIDA', color: Color(0xFF40B0FF)),
                          _Chip(
                              label: 'MOV ${carta.movimientoEfectivo}',
                              color: color),
                          _Chip(label: _tipoLabel(carta.tipo), color: color),
                          if (carta.condicion != CondicionCarta.basica)
                            _Chip(
                                label:
                                    '${carta.condicion.icon} ${carta.condicion.label.toUpperCase()}',
                                color: Color(carta.condicion.colorValue)),
                          if (carta.puedeEvolucionar)
                            _EvolChip(coste: carta.evolucion),
                        ]),
                      ]),
                ),
              ],
            ),
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
// BOTÓN DESHACER — aparece en lugar de MOVER cuando la selección son cartas
// que ya se movieron este turno. Devuelve cada carta a su posición anterior.
// ─────────────────────────────────────────────────────────────
class _UndoButton extends StatelessWidget {
  final int selected;
  final VoidCallback? onTap;

  const _UndoButton({
    required this.selected,
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
                active
                    ? '$selected MOVIDA(S) SELECCIONADA(S)'
                    : 'TOCA UNA CARTA',
                style: TextStyle(
                    fontSize: 8,
                    color: accent,
                    fontFamily: 'Cinzel',
                    letterSpacing: 1),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF40B0FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: const Color(0xFF40B0FF).withOpacity(0.4),
                      width: 0.5),
                ),
                child: const Text('↩ VOLVER',
                    style: TextStyle(
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
                Icon(Icons.undo, size: 13, color: accent),
                const SizedBox(width: 7),
                Text(
                  active ? 'DESHACER MOVIMIENTO' : 'DESHACER',
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
          Text('$coste',
              style: const TextStyle(
                  fontSize: 7,
                  color: color,
                  letterSpacing: 0.5,
                  fontFamily: 'Cinzel')),
          const SizedBox(width: 2),
          const ZeroChip(size: 9),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INDICADOR DE ACCIONES ACTIVAS SOBRE LA CELDA
// ─────────────────────────────────────────────────────────────

/// Acumulador mutable interno para fusionar efectos por (tipo, origen).
class _MutEfecto {
  EfectoTipoEstado tipo;
  int turnos;
  int magnitud;
  String origen;
  CartaEnCelda? carta;
  _MutEfecto(this.tipo, this.turnos, this.magnitud, this.origen, this.carta);
}

/// Una acción activa sobre la celda, lista para mostrarse: tipo de efecto,
/// turnos restantes (máximo), magnitud, origen y —si procede— la carta concreta
/// a la que está afectando (para abrir su detalle al pulsar).
class _EfectoCeldaEntry {
  final EfectoTipoEstado tipo;
  final int turnos;
  final int magnitud;
  final String origenUid;
  final CartaEnCelda? cartaAfectada;

  const _EfectoCeldaEntry({
    required this.tipo,
    required this.turnos,
    required this.magnitud,
    required this.origenUid,
    required this.cartaAfectada,
  });

  /// Combina los efectos de CELDA (`efectosCelda`) con los que arrastran las
  /// cartas presentes, deduplicando por (tipo, origen) y quedándose con el
  /// máximo de turnos restantes. Asocia a cada efecto la primera carta que lo
  /// arrastra (si la hay), para poder abrir su detalle al pulsar. Así funciona
  /// tanto para un veneno recién colocado sobre la celda como para un efecto que
  /// una carta arrastra tras moverse a otra casilla.
  static List<_EfectoCeldaEntry> recolectar(
      List<EfectoActivo> efectosCelda, List<CartaEnCelda> cards) {
    final acc = <String, _MutEfecto>{};

    void upsert(EfectoActivo e, CartaEnCelda? carta) {
      if (e.turnosRestantes <= 0) return;
      final key = '${e.tipo.name}|${e.origenUid}';
      final prev = acc[key];
      if (prev == null) {
        acc[key] = _MutEfecto(
            e.tipo, e.turnosRestantes, e.magnitud, e.origenUid, carta);
      } else {
        if (e.turnosRestantes > prev.turnos) prev.turnos = e.turnosRestantes;
        if (e.magnitud > prev.magnitud) prev.magnitud = e.magnitud;
        prev.carta ??= carta;
      }
    }

    for (final e in efectosCelda) {
      upsert(e, null);
    }
    for (final c in cards) {
      for (final e in c.efectos) {
        upsert(e, c);
      }
    }

    int rank(EfectoTipoEstado t) {
      switch (t) {
        case EfectoTipoEstado.veneno:
          return 0;
        case EfectoTipoEstado.paralisis:
          return 1;
        case EfectoTipoEstado.escudo:
          return 2;
        case EfectoTipoEstado.potFuerza:
          return 3;
        case EfectoTipoEstado.potDefensa:
          return 4;
        case EfectoTipoEstado.potMovimiento:
          return 5;
      }
    }

    final list = acc.values
        .map((m) => _EfectoCeldaEntry(
              tipo: m.tipo,
              turnos: m.turnos,
              magnitud: m.magnitud,
              origenUid: m.origen,
              cartaAfectada: m.carta,
            ))
        .toList()
      ..sort((a, b) => rank(a.tipo).compareTo(rank(b.tipo)));
    return list;
  }
}

/// Cabecera con las acciones activas sobre la celda. Cada chip muestra el icono
/// del efecto, su magnitud (si aplica) y los turnos que le quedan; si el efecto
/// está afectando a una carta concreta, al pulsarlo se abre el detalle de esa
/// carta con sus estadísticas ya modificadas por el efecto.
class _CellActionsBar extends StatelessWidget {
  final List<_EfectoCeldaEntry> entries;
  const _CellActionsBar({required this.entries});

  Color _colorDe(EfectoTipoEstado t) {
    switch (t) {
      case EfectoTipoEstado.veneno:
        return const Color(0xFF2BA046);
      case EfectoTipoEstado.paralisis:
        return const Color(0xFF2C90C8);
      case EfectoTipoEstado.escudo:
        return const Color(0xFF6AB0FF);
      case EfectoTipoEstado.potFuerza:
        return const Color(0xFFFFB84D);
      case EfectoTipoEstado.potDefensa:
        return const Color(0xFF9AD0FF);
      case EfectoTipoEstado.potMovimiento:
        return const Color(0xFF9AD0FF);
    }
  }

  /// Texto de magnitud con signo (veneno resta defensa, potenciaciones suman).
  String _signo(EfectoTipoEstado t, int mag) {
    if (mag <= 0) return '';
    switch (t) {
      case EfectoTipoEstado.veneno:
        return '-$mag';
      case EfectoTipoEstado.potFuerza:
      case EfectoTipoEstado.potDefensa:
      case EfectoTipoEstado.potMovimiento:
        return '+$mag';
      default:
        return '';
    }
  }

  void _abrirCarta(BuildContext ctx, CartaEnCelda entry) {
    showCardDetail(
      ctx,
      entry.carta,
      defensaReducida: entry.defensaReducidaPorEfectos,
      defensaExtra: entry.defensaExtraPorEfectos,
      fuerzaExtra: entry.fuerzaExtraPorEfectos,
      movimientoExtra: entry.movimientoExtraPorEfectos,
      paralizada: entry.paralizado,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0x14000000),
        border: Border(bottom: BorderSide(color: Color(0x20503214), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ACCIONES ACTIVAS',
              style: TextStyle(
                  fontSize: 7,
                  color: Color(0xFF7A6040),
                  letterSpacing: 1.5,
                  fontFamily: 'Cinzel')),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entries.map((e) {
              final color = _colorDe(e.tipo);
              final carta = e.cartaAfectada;
              final tappable = carta != null;
              final signo = _signo(e.tipo, e.magnitud);
              return Builder(builder: (ctx) {
                return GestureDetector(
                  onTap: tappable ? () => _abrirCarta(ctx, carta) : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: color.withOpacity(tappable ? 0.55 : 0.28),
                          width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.tipo.icon, style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 3),
                        Text(e.tipo.nombre.toUpperCase(),
                            style: TextStyle(
                                fontSize: 7,
                                color: color,
                                letterSpacing: 0.5,
                                fontFamily: 'Cinzel')),
                        if (signo.isNotEmpty) ...[
                          const SizedBox(width: 3),
                          Text(signo,
                              style: TextStyle(
                                  fontSize: 8,
                                  color: color,
                                  fontFamily: 'Cinzel',
                                  fontWeight: FontWeight.bold)),
                        ],
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('${e.turnos}t',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: color,
                                  fontFamily: 'Cinzel',
                                  fontWeight: FontWeight.bold)),
                        ),
                        if (tappable) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.open_in_new,
                              size: 9, color: color.withOpacity(0.8)),
                        ],
                      ],
                    ),
                  ),
                );
              });
            }).toList(),
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
