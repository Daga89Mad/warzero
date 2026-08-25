// lib/views/tutorial_screen.dart
//
// TUTORIAL GUIADO — VARIANTE LIBRE · usa el BoardWidget REAL.
// -----------------------------------------------------------------------------
// Partida SCRIPTED de demostración sobre el MISMO tablero que la partida real
// (BoardWidget): marco de madera, imagen del mapa Clásico (6×10), cuarteles en
// las esquinas y fichas idénticas. Respeta el ajuste 3D/plano de Ajustes.
// NO usa Firestore, ni TurnService, ni el motor real: es una simulación
// controlada pensada solo para enseñar los conceptos del juego.
//
// Modo LIBRE: nada se selecciona solo.
//   · Toca una carta de la MANO para seleccionarla antes de desplegar o lanzar
//     una acción (icono 🔍 en la carta para verla en grande).
//   · Toca tu UNIDAD del tablero para seleccionarla antes de mover, atacar o
//     teletransportar. Las celdas válidas solo se iluminan tras la selección.
//
// Los rivales aparecen solo cuando toca su paso (Dron en la batalla, Tanque en
// el misil), para que el mapa se vea limpio al inicio.
//
// Se abre desde Ajustes → "Ver tutorial".
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../services/settings_controller.dart';
import '../models/game_config.dart';
import '../models/board_state.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart';
import '../widgets/board_widget.dart';
import '../widgets/cell_sidebar.dart';
import '../models/jugador_model.dart';
import '../widgets/player_hud.dart';
import '../widgets/hand_widget.dart';
import '../widgets/card_detail_overlay.dart';
import 'informe_batalla_screen.dart';

// ─────────────────────────────────────────────────────────────
// COLORES DE JUGADOR (fijos).
// ─────────────────────────────────────────────────────────────
const Color _cYo = Color(0xFFE0B84A); // tú (amarillo/dorado, abajo-derecha)
const Color _cRojo = Color(0xFFC04040); // arriba-izquierda
const Color _cAzul = Color(0xFF4A90D9); // arriba-derecha
const Color _cVerde = Color(0xFF4ABB58); // abajo-izquierda
const Color _cRayo = Color(0xFF55C0FF); // energía Zero

// ─────────────────────────────────────────────────────────────
// MODELO DE CARTA (ligero, solo para el tutorial)
// ─────────────────────────────────────────────────────────────
enum _Cond { basica, estatica, accion }

class _TCard {
  final String id;
  final String nombre;
  final String desc;
  final int fuerza;
  final int defensa;
  final int coste;
  final int movimiento;
  final int tipo; // 1 Tierra · 2 Aire · 3 Mar
  final _Cond cond;
  final IconData icon;

  /// Evolución: id de la carta resultante y coste en energía. Si ambos están
  /// definidos (id no vacío y coste > 0), la carta "puede evolucionar" y en su
  /// detalle aparece la flecha de evolución (igual que en el juego).
  final String idEvolucion;
  final int evolucion;

  const _TCard({
    required this.id,
    required this.nombre,
    required this.desc,
    this.fuerza = 0,
    this.defensa = 0,
    this.coste = 0,
    this.movimiento = 0,
    this.tipo = 1,
    this.cond = _Cond.basica,
    required this.icon,
    this.idEvolucion = '',
    this.evolucion = 0,
  });

  String get tipoNombre => tipo == 2 ? 'Aire' : (tipo == 3 ? 'Mar' : 'Tierra');
  IconData get tipoIcon =>
      tipo == 2 ? Icons.air : (tipo == 3 ? Icons.waves : Icons.terrain);
  Color get tipoColor => tipo == 2
      ? const Color(0xFF8AB4E8)
      : (tipo == 3 ? const Color(0xFF2E88C8) : const Color(0xFF8A9A5B));

  String get condLabel {
    switch (cond) {
      case _Cond.estatica:
        return 'Estática';
      case _Cond.accion:
        return 'Acción';
      case _Cond.basica:
        return 'Básica';
    }
  }

  Color get condColor {
    switch (cond) {
      case _Cond.estatica:
        return const Color(0xFFE0A030);
      case _Cond.accion:
        return const Color(0xFF40C0FF);
      case _Cond.basica:
        return const Color(0xFF7FB4D6);
    }
  }

  CondicionCarta get condicion {
    switch (cond) {
      case _Cond.estatica:
        return CondicionCarta.estatica;
      case _Cond.accion:
        return CondicionCarta.accion;
      case _Cond.basica:
        return CondicionCarta.basica;
    }
  }

  /// Convierte esta carta ligera a un CartaModel real (para el BoardWidget).
  CartaModel aModelo() => CartaModel(
        id: id,
        nombre: nombre,
        descripcion: desc,
        ejercito: 0,
        fuerza: fuerza,
        defensa: defensa,
        coste: coste,
        idHabilidad: 0,
        imagen: '',
        movimiento: movimiento,
        tipo: tipo,
        condicion: condicion,
        idEvolucion: idEvolucion,
        evolucion: evolucion,
      );
}

class _Placed {
  final _TCard card;
  final String owner; // 'yo' | 'rojo'
  const _Placed(this.card, this.owner);
}

/// Combate pendiente de resolver: tu carta ha entrado en la celda [coord] que
/// ocupa la carta enemiga. Ambas conviven en la celda (mostrando el poder neto)
/// hasta que se cierra el turno; entonces la enemiga se destruye y tú conquistas
/// la celda ganando [premio] Ø.
class _CombatePendiente {
  final String coord; // celda enemiga donde entra tu carta
  final String origen; // de dónde vino tu carta
  final _TCard aliada; // tu carta
  final _TCard enemiga; // carta enemiga
  final int premio; // Ø que ganas al resolver
  const _CombatePendiente({
    required this.coord,
    required this.origen,
    required this.aliada,
    required this.enemiga,
    required this.premio,
  });
}

// ─────────────────────────────────────────────────────────────
// PASOS DEL TUTORIAL
// ─────────────────────────────────────────────────────────────
enum _Step {
  intro,
  energiaZero,
  atributos,
  cartaGrande,
  sacarCuartel,
  mover,
  evolucion,
  batalla,
  informe,
  estatica,
  teletransporte,
  misil,
  fin,
}

const List<_Step> _orden = [
  _Step.intro,
  _Step.energiaZero,
  _Step.atributos,
  _Step.cartaGrande,
  _Step.sacarCuartel,
  _Step.mover,
  _Step.evolucion,
  _Step.batalla,
  _Step.informe,
  _Step.estatica,
  _Step.teletransporte,
  _Step.misil,
  _Step.fin,
];

// Nodo auxiliar para el BFS de movimiento.
class _QN {
  final String coord;
  final int d;
  const _QN(this.coord, this.d);
}

// ─────────────────────────────────────────────────────────────
// PANTALLA
// ─────────────────────────────────────────────────────────────
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with SingleTickerProviderStateMixin {
  // MAPA CLÁSICO: 6 filas (A–F) × 10 columnas (1–10).
  static const int _cols = 10;
  static const int _rows = 6;

  // Config del tablero real (6×10, 4 zonas).
  final GameConfig _config = GameConfig(
    playerCount: 4,
    rowLabels: GameConfig.generarRowLabels(_rows), // A..F
    colLabels: GameConfig.generarColLabels(_cols), // 1..10
    zones: const [
      PlayerZone(zoneId: 'nw', label: 'ROJO', color: _cRojo),
      PlayerZone(zoneId: 'ne', label: 'AZUL', color: _cAzul),
      PlayerZone(zoneId: 'sw', label: 'VERDE', color: _cVerde),
      PlayerZone(zoneId: 'se', label: 'TÚ', color: _cYo),
    ],
  );

  // Cuarteles (esquinas). Coord → color del cristal.
  static const String _hqYo = 'F10'; // tú (abajo-derecha)
  static const Set<String> _obeliscoCoords = {'A1', 'A10', 'F1', 'F10'};
  static const Map<String, Color> _obeliscoColores = {
    'A1': _cRojo,
    'A10': _cAzul,
    'F1': _cVerde,
    'F10': _cYo,
  };
  static const Map<String, Color> _playerColors = {
    'yo': _cYo,
    'rojo': _cRojo,
  };

  // Isla central (obelisco del arte): intransitable en el tutorial.
  static const Set<String> _centro = {'C5', 'C6', 'D5', 'D6'};

  // Rayo de energía Zero (posición fija).
  static const String _rayo = 'C8';

  // ── Cartas del tutorial ─────────────────────────────────────
  static const _soldado = _TCard(
    id: 'soldado',
    nombre: 'Soldado Zero',
    desc:
        'Infantería básica. Se despliega en tu cuartel y avanza por el tablero '
        'para conquistar celdas y luchar.',
    fuerza: 3,
    defensa: 3,
    coste: 2,
    movimiento: 2,
    tipo: 1,
    cond: _Cond.basica,
    icon: Icons.person,
    idEvolucion: 'soldado_elite',
    evolucion: 3,
  );
  // Evolución del Soldado Zero: más fuerza, defensa y movimiento.
  static const _soldadoElite = _TCard(
    id: 'soldado_elite',
    nombre: 'Soldado Élite',
    desc: 'Versión evolucionada del Soldado Zero: más fuerza, defensa y '
        'movimiento. Una carta evolucionada no puede moverse el turno en que '
        'evoluciona.',
    fuerza: 5,
    defensa: 5,
    coste: 4,
    movimiento: 3,
    tipo: 1,
    cond: _Cond.basica,
    icon: Icons.shield_moon,
  );
  static const _torreta = _TCard(
    id: 'torreta',
    nombre: 'Torreta Búnker',
    desc:
        'Estructura defensiva. Movimiento 0: no se mueve una vez colocada, pero '
        'aporta mucha defensa a la celda que ocupa.',
    fuerza: 4,
    defensa: 5,
    coste: 3,
    movimiento: 0,
    tipo: 1,
    cond: _Cond.estatica,
    icon: Icons.security,
  );
  static const _tele = _TCard(
    id: 'tele',
    nombre: 'Teletransporte',
    desc:
        'Carta de acción. Mueve al instante una de tus cartas a cualquier celda '
        'libre del tablero. Se descarta tras usarse.',
    coste: 2,
    cond: _Cond.accion,
    icon: Icons.flash_on,
  );
  static const _misil = _TCard(
    id: 'misil',
    nombre: 'Misil Zero',
    desc: 'Carta de acción ofensiva. Destruye la carta enemiga de una celda a '
        'distancia. Se descarta tras usarse.',
    fuerza: 5,
    coste: 3,
    cond: _Cond.accion,
    icon: Icons.rocket_launch,
  );

  static const _dron = _TCard(
    id: 'dron',
    nombre: 'Dron Rival',
    desc: 'Unidad enemiga.',
    fuerza: 2,
    defensa: 2,
    coste: 2,
    tipo: 2,
    icon: Icons.adb,
  );
  static const _tanque = _TCard(
    id: 'tanque',
    nombre: 'Tanque Rival',
    desc: 'Unidad enemiga acorazada.',
    fuerza: 3,
    defensa: 4,
    coste: 3,
    tipo: 1,
    icon: Icons.directions_car,
  );

  List<_TCard> get _mano => const [_soldado, _torreta, _tele, _misil];

  // ── Estado ──────────────────────────────────────────────────
  int _paso = 0;
  int _zero = 12;

  final Map<String, _Placed> _board = {};

  _TCard? _selHand;
  String? _selBoard;
  Set<String> _targets = {};

  // ── Menú lateral (igual que en la partida real) ──────────────
  // En el paso "mover" tocar tu unidad abre el CellSidebar; desde ahí se
  // selecciona la carta y se pulsa MOVER para resaltar las celdas alcanzables.
  bool _sidebarOpen = false;
  String? _sidebarCoord;

  // ── Cierre de turno + informe de fin de turno ────────────────
  // Tras mover tu carta sobre la enemiga (paso "batalla") ambas quedan en la
  // MISMA celda y esta muestra el poder neto (⚡ = fuerza − defensa del rival),
  // igual que en el juego. La carta enemiga NO desaparece hasta que pulses FIN
  // TURNO: en ese momento se resuelve el combate y se abre el informe.
  bool _batallaResuelta = false;
  Map<String, dynamic>? _combateInforme;
  _CombatePendiente? _combatePendiente;

  late final AnimationController _pulse;

  _Step get _step => _orden[_paso];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _resetPartida();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _resetPartida() {
    _board.clear(); // el mapa arranca VACÍO
    _zero = 12;
    _onEnterStep();
  }

  // Al entrar en un paso NO se selecciona nada (modo libre). Los rivales
  // aparecen solo en el paso que los necesita.
  void _onEnterStep() {
    _selHand = null;
    _selBoard = null;
    _targets = {};
    _sidebarOpen = false;
    _sidebarCoord = null;
    if (_step != _Step.batalla && _step != _Step.informe) {
      // El resultado del combate y el flag de "batalla resuelta" solo viven
      // durante los pasos de batalla e informe.
      _batallaResuelta = false;
      _combatePendiente = null;
    }
    if (_step == _Step.batalla) {
      _spawnDron();
    } else if (_step == _Step.misil) {
      _spawnTanque();
    } else if (_step == _Step.evolucion) {
      // Resaltar la unidad propia para que se vea qué tocar y evolucionar.
      final fc = _friendlyCoords();
      if (fc.isNotEmpty) _selBoard = fc.first;
    }
  }

  void _spawnDron() {
    if (_coordDe('dron', 'rojo') != null) return;
    final fc = _friendlyCoords();
    final s = fc.isNotEmpty ? fc.first : null;
    String? cell = s != null ? _celdaLibreVecina(s) : null;
    cell ??= _primeraLibrePref(const ['D8', 'C8', 'D7', 'C7', 'E8']);
    if (cell != null) _board[cell] = const _Placed(_dron, 'rojo');
  }

  void _spawnTanque() {
    if (_coordDe('tanque', 'rojo') != null) return;
    final cell = _primeraLibrePref(const ['C7', 'B7', 'C8', 'B6', 'D7', 'D8']);
    if (cell != null) _board[cell] = const _Placed(_tanque, 'rojo');
  }

  void _advance() {
    if (_paso < _orden.length - 1) {
      setState(() {
        _paso++;
        _onEnterStep();
      });
    }
  }

  // ── Coordenadas (label A1..F10 ↔ ri/ci) ─────────────────────
  int _ri(String c) => c.codeUnitAt(0) - 65;
  int _ci(String c) => int.parse(c.substring(1)) - 1;
  String _mk(int ri, int ci) => '${String.fromCharCode(65 + ri)}${ci + 1}';

  List<String> _vecinos(String coord) {
    final r = _ri(coord);
    final c = _ci(coord);
    final res = <String>[];
    void add(int rr, int cc) {
      if (rr >= 0 && rr < _rows && cc >= 0 && cc < _cols) res.add(_mk(rr, cc));
    }

    add(r - 1, c);
    add(r + 1, c);
    add(r, c - 1);
    add(r, c + 1);
    return res;
  }

  // ── Consultas de tablero ────────────────────────────────────
  Set<String> _friendlyCoords() => _board.entries
      .where((e) => e.value.owner == 'yo')
      .map((e) => e.key)
      .toSet();

  Set<String> _enemyCoords() => _board.entries
      .where((e) => e.value.owner != 'yo')
      .map((e) => e.key)
      .toSet();

  bool _esHqEnemigo(String coord) =>
      _obeliscoCoords.contains(coord) && coord != _hqYo;

  bool _libreYPermitida(String coord) =>
      !_board.containsKey(coord) &&
      !_obeliscoCoords.contains(coord) &&
      !_centro.contains(coord);

  String? _celdaLibreVecina(String ancla) {
    for (final v in _vecinos(ancla)) {
      if (_libreYPermitida(v)) return v;
    }
    return null;
  }

  String? _primeraLibrePref(List<String> pref) {
    for (final c in pref) {
      if (_libreYPermitida(c)) return c;
    }
    // Cualquier celda libre como último recurso.
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final coord = _mk(r, c);
        if (_libreYPermitida(coord)) return coord;
      }
    }
    return null;
  }

  Set<String> _celdasLibres() {
    final res = <String>{};
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final coord = _mk(r, c);
        if (_libreYPermitida(coord)) res.add(coord);
      }
    }
    return res;
  }

  /// Celdas vacías alcanzables desde [origen] en ≤ [pasos] pasos ortogonales,
  /// sin atravesar ocupadas ni el obelisco central.
  Set<String> _alcanzablesMov(String origen, int pasos) {
    final res = <String>{};
    final visitado = <String>{origen};
    final cola = <_QN>[_QN(origen, 0)];
    while (cola.isNotEmpty) {
      final n = cola.removeAt(0);
      if (n.d >= pasos) continue;
      for (final v in _vecinos(n.coord)) {
        if (visitado.contains(v)) continue;
        if (_board.containsKey(v)) continue;
        if (_centro.contains(v)) continue;
        visitado.add(v);
        res.add(v);
        cola.add(_QN(v, n.d + 1));
      }
    }
    return res;
  }

  /// Celdas donde colocar una ESTÁTICA: tu cuartel (si libre) o vacía adyacente
  /// a una unidad tuya.
  Set<String> _celdasEstaticaValidas() {
    final candidatos = <String>{_hqYo};
    for (final m in _friendlyCoords()) {
      candidatos.addAll(_vecinos(m));
    }
    final res = <String>{};
    for (final c in candidatos) {
      if (_board.containsKey(c)) continue;
      if (_esHqEnemigo(c)) continue;
      if (_centro.contains(c)) continue;
      res.add(c);
    }
    return res;
  }

  String? _coordDe(String cardId, String owner) {
    for (final e in _board.entries) {
      if (e.value.owner == owner && e.value.card.id == cardId) return e.key;
    }
    return null;
  }

  bool get _pasoSeleccionaUnidad =>
      _step == _Step.mover ||
      _step == _Step.batalla ||
      (_step == _Step.teletransporte && _selHand?.id == 'tele');

  bool get _usaDeploy => _step == _Step.sacarCuartel || _step == _Step.estatica;

  // ── Recalcula objetivos según selección ─────────────────────
  void _recalcTargets() {
    var t = <String>{};
    switch (_step) {
      case _Step.sacarCuartel:
        if (_selHand?.id == 'soldado' && !_board.containsKey(_hqYo)) {
          t = {_hqYo};
        }
        break;
      case _Step.estatica:
        if (_selHand?.id == 'torreta') t = _celdasEstaticaValidas();
        break;
      case _Step.mover:
        final sel = _selBoard;
        if (sel != null) {
          final u = _board[sel];
          if (u != null && u.card.movimiento > 0) {
            t = _alcanzablesMov(sel, u.card.movimiento);
          }
        }
        break;
      case _Step.batalla:
        if (_selBoard != null) {
          t = _enemyCoords().where((c) => _board[c]?.card.id == 'dron').toSet();
        }
        break;
      case _Step.teletransporte:
        if (_selHand?.id == 'tele' && _selBoard != null) t = _celdasLibres();
        break;
      case _Step.misil:
        if (_selHand?.id == 'misil') t = _enemyCoords();
        break;
      default:
        break;
    }
    _targets = t;
  }

  // ── Toques ──────────────────────────────────────────────────
  void _onHandTap(_TCard c) {
    setState(() {
      _selHand = c;
      _selBoard = null;
      _sidebarOpen = false;
      _sidebarCoord = null;
      _recalcTargets();
    });
  }

  // ── Menú lateral (CellSidebar real) ─────────────────────────
  /// Abre el menú lateral sobre [coord] mostrando la ficha de la unidad, tal y
  /// como ocurre en la partida real al tocar una celda propia.
  void _abrirSidebar(String coord) {
    setState(() {
      _sidebarCoord = coord;
      _sidebarOpen = true;
      _selBoard = null;
      _targets = {};
    });
  }

  void _cerrarSidebar() {
    if (!_sidebarOpen) return;
    setState(() {
      _sidebarOpen = false;
      _sidebarCoord = null;
    });
  }

  /// Callback del botón MOVER del menú lateral: con la carta seleccionada,
  /// calcula el alcance (BFS) y resalta las celdas destino válidas, cerrando el
  /// menú. Reproduce el flujo real "selecciona la carta → marca MOVER".
  void _onSidebarMove(List<int> indices) {
    final coord = _sidebarCoord;
    if (coord == null || indices.isEmpty) return;
    final placed = _board[coord];
    if (placed == null || placed.card.movimiento <= 0) return;
    setState(() {
      _selBoard = coord;
      _targets = _alcanzablesMov(coord, placed.card.movimiento);
      _sidebarOpen = false;
    });
  }

  void _onCellTap(String coord, int ri, int ci) {
    final placed = _board[coord];
    switch (_step) {
      case _Step.sacarCuartel:
        if (_selHand?.id == 'soldado' && _targets.contains(coord)) {
          _desplegarSoldado(coord);
        }
        break;
      case _Step.estatica:
        if (_selHand?.id == 'torreta' && _targets.contains(coord)) {
          _desplegarTorreta(coord);
        }
        break;
      case _Step.mover:
        // Igual que en la partida real: tocar tu unidad abre el MENÚ LATERAL
        // con su ficha. Allí seleccionas la carta y pulsas MOVER; solo entonces
        // se iluminan las celdas alcanzables. Después tocas la celda destino.
        if (_selBoard == null &&
            placed?.owner == 'yo' &&
            placed!.card.movimiento > 0) {
          _abrirSidebar(coord);
        } else if (_selBoard != null && _targets.contains(coord)) {
          _moverSoldado(coord);
        }
        break;
      case _Step.evolucion:
        // Tocar tu unidad abre el detalle REAL con la flecha de evolución.
        if (placed?.owner == 'yo') {
          _abrirEvolucion(coord);
        }
        break;
      case _Step.batalla:
        // Con el combate ya pendiente (esperando cierre de turno) el tablero
        // queda bloqueado: solo falta pulsar FIN TURNO.
        if (_batallaResuelta) break;
        if (placed?.owner == 'yo') {
          setState(() {
            _selBoard = coord;
            _recalcTargets();
          });
        } else if (_selBoard != null && _targets.contains(coord)) {
          _atacar(coord);
        }
        break;
      case _Step.teletransporte:
        if (_selHand?.id != 'tele') break;
        if (_selBoard == null) {
          if (placed?.owner == 'yo') {
            setState(() {
              _selBoard = coord;
              _recalcTargets();
            });
          }
        } else if (_targets.contains(coord)) {
          _teletransportar(_selBoard!, coord);
        } else if (placed?.owner == 'yo') {
          setState(() {
            _selBoard = coord;
            _recalcTargets();
          });
        }
        break;
      case _Step.misil:
        if (_selHand?.id == 'misil' && _targets.contains(coord)) {
          _lanzarMisil(coord);
        }
        break;
      default:
        if (placed != null) _verCarta(placed.card);
        break;
    }
  }

  // ── Acciones ────────────────────────────────────────────────
  void _desplegarSoldado(String coord) {
    setState(() {
      _board[coord] = const _Placed(_soldado, 'yo');
      _zero = (_zero - _soldado.coste).clamp(0, 999);
    });
    _toast('¡Soldado desplegado! −${_soldado.coste} Ø');
    _advance();
  }

  void _moverSoldado(String destino) {
    final origen = _selBoard ?? _coordDe('soldado', 'yo');
    if (origen == null) return;
    setState(() {
      final p = _board.remove(origen)!;
      _board[destino] = p;
    });
    _toast('Carta movida a $destino');
    _advance();
  }

  // ── Evolución (usa el detalle REAL del juego, con su flecha) ──
  /// Abre el detalle real de la carta en [coord] con la flecha de evolución.
  /// El coste se descuenta de la Energía Zero, igual que en la partida.
  Future<void> _abrirEvolucion(String coord) async {
    final placed = _board[coord];
    if (placed == null) return;
    await showCardDetail(
      context,
      placed.card.aModelo(),
      energiasDisponibles: _zero,
      resolveEvolucion: (id) async =>
          id == _soldadoElite.id ? _soldadoElite.aModelo() : null,
      onEvolucionar: (evolucion) async => _evolucionarUnidad(coord),
    );
  }

  void _evolucionarUnidad(String coord) {
    final placed = _board[coord];
    if (placed == null) return;
    final coste = placed.card.evolucion;
    setState(() {
      _board[coord] = _Placed(_soldadoElite, placed.owner);
      _zero = (_zero - coste).clamp(0, 999);
    });
    _toast('${placed.card.nombre} → ${_soldadoElite.nombre}  (-${coste}Ø)');
    _advance();
  }

  /// Tu carta entra en la celda enemiga. NO se resuelve el combate todavía:
  /// ambas cartas quedan en la misma celda (la celda muestra el poder neto ⚡) y
  /// solo al pulsar FIN TURNO se destruye la enemiga y conquistas la celda.
  void _atacar(String coordEnemigo) {
    final origen = _selBoard ?? _friendlyCoords().first;
    final enemigo = _board[coordEnemigo];
    final yo = _board[origen];
    final atacante = yo?.card ?? _soldado;
    final defensor = enemigo?.card ?? _dron;
    final premio = defensor.coste;
    setState(() {
      // Saca tu carta de su celda de origen, pero deja la enemiga en la suya:
      // el combate queda PENDIENTE y ambas conviven en la celda enemiga.
      _board.remove(origen);
      _combatePendiente = _CombatePendiente(
        coord: coordEnemigo,
        origen: origen,
        aliada: atacante,
        enemiga: defensor,
        premio: premio,
      );
      // Prepara la entrada del INFORME DE BATALLA con este combate, para poder
      // mostrarla al cerrar el turno (mismo formato que el informe real).
      _combateInforme =
          _construirEntradaCombate(atacante, defensor, premio, coordEnemigo);
      // Ahora toca CERRAR TURNO para resolver el combate y ver el informe.
      _batallaResuelta = true;
      _selBoard = null;
      _targets = {};
    });
    _toast('Tu carta entra en $coordEnemigo. Cierra el turno para resolver.');
  }

  /// Construye una entrada de `combateLog` con el formato que consume
  /// [InformeBatallaScreen] (ganador, derrotados, recompensa y desglose por
  /// ejército con sus cartas).
  Map<String, dynamic> _construirEntradaCombate(
      _TCard atacante, _TCard defensor, int premio, String coord) {
    Map<String, dynamic> carta(_TCard c, String uid, String zone) => {
          'nombre': c.nombre,
          'fuerza': c.fuerza,
          'defensa': c.defensa,
          // Claves en mayúscula que usa la animación de carta rota.
          'Nombre': c.nombre,
          'Fuerza': c.fuerza,
          'Defensa': c.defensa,
          'Imagen': '',
          'ownerUid': uid,
          'ownerZone': zone,
        };
    return {
      'coord': coord,
      'ganadorUid': 'yo',
      'ganadorZone': 'south',
      'derrotadosUid': const ['rojo'],
      'energiesGanadas': {'yo': premio},
      'pcGanados': const {'yo': 3},
      'detalle': [
        {
          'ownerUid': 'yo',
          'ownerZone': 'south',
          'totalFuerza': atacante.fuerza,
          'totalDefensa': atacante.defensa,
          'poderNeto': atacante.fuerza - defensor.defensa,
          'numCartas': 1,
          'cartas': [carta(atacante, 'yo', 'south')],
        },
        {
          'ownerUid': 'rojo',
          'ownerZone': 'north',
          'totalFuerza': defensor.fuerza,
          'totalDefensa': defensor.defensa,
          'poderNeto': defensor.fuerza - atacante.defensa,
          'numCartas': 1,
          'cartas': [carta(defensor, 'rojo', 'north')],
        },
      ],
    };
  }

  // ── Cierre de turno + informe de fin de turno ───────────────
  /// Cierra el turno del tutorial: RESUELVE el combate pendiente (la carta
  /// enemiga se destruye y conquistas la celda ganando su premio), abre el
  /// INFORME DE BATALLA con el resultado y, al volver, avanza a la explicación.
  Future<void> _cerrarTurnoTutorial() async {
    final p = _combatePendiente;
    if (p != null) {
      setState(() {
        // La enemiga desaparece; tu carta ocupa la celda en solitario.
        _board[p.coord] = _Placed(p.aliada, 'yo');
        _zero += p.premio;
        _combatePendiente = null;
      });
    }
    await _abrirInforme();
    if (!mounted) return;
    _advance();
  }

  /// Abre el informe de batalla real (misma pantalla que en la partida),
  /// posicionado en la pestaña ZERO y con una nota explicativa del tutorial
  /// para explicar cómo se farmea energía.
  Future<void> _abrirInforme() async {
    final combate = _combateInforme;
    // Entrada de farmeo de ejemplo: +10 Zero del cristal (rayo) de C8, para que
    // la pestaña ZERO muestre un ingreso real que explicar.
    const farmeo = <Map<String, dynamic>>[
      {
        'uid': 'yo',
        'zona': 'south',
        'totalEnergies': 10,
        'detalle': {'rayo': 10},
      },
    ];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InformeBatallaScreen(
          combateLog: combate != null ? [combate] : const [],
          movimientosLog: const [],
          farmeoLog: farmeo,
          accionesLog: const [],
          rayoCoords: const [_rayo],
          historial: const [],
          localUid: 'yo',
          jugadores: const [
            LobbyJugador(uid: 'yo', alias: 'TÚ'),
            LobbyJugador(uid: 'rojo', alias: 'Rojo'),
          ],
          turno: 1,
          // La carta nueva del turno: la Torreta que usarás en el paso siguiente.
          ultimaCartaRepartida: _torreta.aModelo(),
          // Abre en COMBATES (índice 0) y muestra la nota guía del tutorial.
          initialTabIndex: 0,
          notaTutorial:
              'Este es el informe de fin de turno. Aquí ves el COMBATE que acabas '
              'de ganar. Ahora toca la pestaña ZERO (arriba) para ver cómo se '
              'farmea la ENERGÍA ZERO (Ø): cada CRISTAL ZERO (celdas con el icono '
              'Ø, como C8) da +10 Ø por turno a quien tenga una carta encima, y '
              'también ganas Ø al vencer combates.',
        ),
      ),
    );
  }

  void _desplegarTorreta(String coord) {
    setState(() {
      _board[coord] = const _Placed(_torreta, 'yo');
      _zero = (_zero - _torreta.coste).clamp(0, 999);
    });
    _toast('Torreta colocada. −${_torreta.coste} Ø');
    _advance();
  }

  void _teletransportar(String src, String dst) {
    setState(() {
      final p = _board.remove(src)!;
      _board[dst] = p;
      _zero = (_zero - _tele.coste).clamp(0, 999);
    });
    _toast('¡Teletransporte! −${_tele.coste} Ø');
    _advance();
  }

  void _lanzarMisil(String coord) {
    setState(() {
      _board.remove(coord);
      _zero = (_zero - _misil.coste).clamp(0, 999);
    });
    _toast('¡Impacto directo! Objetivo destruido. −${_misil.coste} Ø');
    _advance();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cinzel')),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Construye el BoardState real desde _board ───────────────
  BoardState _buildBoardState() {
    final celdas = <String, CeldaState>{};
    _board.forEach((coord, p) {
      final ec = CartaEnCelda(
        carta: p.card.aModelo(),
        ownerUid: p.owner,
        ownerZone: p.owner == 'yo' ? 'se' : 'nw',
      );
      celdas[coord] = CeldaState(coord: coord, cartas: [ec]);
    });

    // Combate pendiente: tu carta convive con la enemiga en la misma celda. Al
    // haber dos dueños distintos, la celda pinta el poder neto (⚡ = fuerza −
    // defensa del rival) automáticamente, igual que en la partida real.
    final p = _combatePendiente;
    if (p != null) {
      final aliada = CartaEnCelda(
        carta: p.aliada.aModelo(),
        ownerUid: 'yo',
        ownerZone: 'se',
      );
      final existentes = celdas[p.coord]?.cartas ?? const <CartaEnCelda>[];
      celdas[p.coord] =
          CeldaState(coord: p.coord, cartas: [...existentes, aliada]);
    }

    return BoardState(celdas: celdas, rayoCoords: const {_rayo});
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final resaltarEnergia = _step == _Step.energiaZero;
    // BoardState construido una sola vez por frame: lo comparten el tablero y el
    // menú lateral, para que la ficha del sidebar coincida con la del tablero.
    final board = _buildBoardState();

    // ── Estado de fin de turno ──
    // El botón FIN TURNO solo se activa cuando el combate del paso "batalla" ya
    // se ha resuelto: al pulsarlo se abre el informe de fin de turno.
    final puedeCerrarTurno = _step == _Step.batalla && _batallaResuelta;
    // El botón de informe (📜) del menú superior se habilita en el paso de
    // explicación para poder reabrir el informe cuando se quiera.
    final puedeVerInforme = _step == _Step.informe;

    return Scaffold(
      backgroundColor: war.fondo,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── Menú superior REAL de la partida (jugadores + salir) ──
                PartidaTopBar(
                  nombrePartida: 'TUTORIAL',
                  colorAsignado: _cYo,
                  jugadores: _hudJugadores,
                  onSalir: () => Navigator.of(context).maybePop(),
                  // En el tutorial el resto de acciones se muestran atenuadas.
                  puedeCuartel: false,
                  onCuartel: () {},
                  puedeInforme: puedeVerInforme,
                  onInforme: puedeVerInforme ? () => _abrirInforme() : () {},
                  puedePuntuaciones: false,
                  onPuntuaciones: () {},
                  puedeAlianza: false,
                  onAlianza: () {},
                  puedeDeshacer: false,
                  onDeshacer: () {},
                ),
                // Tablero REAL (respeta el ajuste 3D/plano de Ajustes).
                Expanded(
                  child: BoardWidget(
                    config: _config,
                    boardState: board,
                    selectedCellCoord: _sidebarOpen ? _sidebarCoord : _selBoard,
                    highlightEmpty: _usaDeploy,
                    deployCoords: _usaDeploy ? _targets : const {},
                    movableCoords: _usaDeploy ? const {} : _targets,
                    obeliscoLocal: _hqYo,
                    obeliscoCoords: _obeliscoCoords,
                    obeliscoColores: _obeliscoColores,
                    playerColors: _playerColors,
                    localPlayerUid: 'yo',
                    onBackgroundTap: () {
                      if (_sidebarOpen) {
                        _cerrarSidebar();
                      } else if (_selBoard != null) {
                        setState(() {
                          _selBoard = null;
                          _recalcTargets();
                        });
                      }
                    },
                    onCellTap: (coord, ri, ci) => _onCellTap(coord, ri, ci),
                  ),
                ),
                // ── Barra de jugador REAL: inicial + Energía Zero + FIN TURNO ──
                // En el paso de Energía se resalta con un glow para guiar la vista.
                Container(
                  decoration: resaltarEnergia
                      ? BoxDecoration(
                          border: Border.all(color: _cRayo, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: _cRayo.withOpacity(0.4), blurRadius: 14),
                          ],
                        )
                      : null,
                  child: BottomHudBar(
                    player: _sesionYo,
                    isMyTurn: true,
                    colorOverride: _cYo,
                    mazoCount: _mano.length,
                    endTurnLabel: 'FIN TURNO',
                    // Solo activo cuando toca cerrar el turno tras el combate.
                    onEndTurn: puedeCerrarTurno ? _cerrarTurnoTutorial : null,
                    onVerMazo: null,
                  ),
                ),
                // ── Mano inferior REAL ──
                HandWidget(
                  cartas: _mano.map((c) => c.aModelo()).toList(),
                  selectedIndex: _selHand == null
                      ? null
                      : _mano.indexWhere((c) => c.id == _selHand!.id),
                  onCardTap: (i) => _onHandTap(_mano[i]),
                  energiesDisponibles: _zero,
                ),
                _panelCoach(war),
              ],
            ),

            // ── Scrim para cerrar el menú lateral tocando fuera ──
            if (_sidebarOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _cerrarSidebar,
                ),
              ),

            // ── MENÚ LATERAL REAL (CellSidebar) ──
            // Se desliza desde la derecha en el paso "mover": muestra la ficha
            // de la unidad y el botón MOVER, igual que en la partida.
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: CellSidebar(
                celda: _sidebarCoord != null
                    ? board.getCelda(_sidebarCoord!)
                    : null,
                coord: _sidebarCoord,
                terrain: TerrainType.land,
                isOpen: _sidebarOpen,
                onClose: _cerrarSidebar,
                localUid: 'yo',
                playerColors: _playerColors,
                onMoveSelected: _onSidebarMove,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sesión del jugador local para la barra inferior real (inicial + Zero).
  PlayerSession get _sesionYo => PlayerSession(
        datos: const JugadorDatos(
            uid: 'yo', alias: 'TÚ', dinero: 0, imagenPerfil: ''),
        zona: 'south',
        colorIndex: 3,
        puntos: _zero,
      );

  /// Jugadores para el desplegable del menú superior real (inicial + Zero).
  List<HudJugadorInfo> get _hudJugadores => [
        HudJugadorInfo(alias: 'TÚ', color: _cYo, zeros: _zero, esLocal: true),
        const HudJugadorInfo(alias: 'Rojo', color: _cRojo, zeros: 0),
        const HudJugadorInfo(alias: 'Azul', color: _cAzul, zeros: 0),
        const HudJugadorInfo(alias: 'Verde', color: _cVerde, zeros: 0),
      ];

  // ── Carta en grande (overlay) ───────────────────────────────
  Future<void> _verCarta(_TCard c, {bool avanzarAlCerrar = false}) async {
    final war = context.war;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          decoration: BoxDecoration(
            color: war.superficie,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.condColor.withOpacity(0.7), width: 2),
            boxShadow: [
              BoxShadow(color: c.condColor.withOpacity(0.35), blurRadius: 24)
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: c.condColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.condColor.withOpacity(0.6)),
                ),
                child: Icon(c.icon, size: 44, color: c.condColor),
              ),
              const SizedBox(height: 14),
              Text(c.nombre,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: war.texto)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: c.condColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(c.condLabel,
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        color: c.condColor,
                        fontFamily: 'Cinzel')),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statGrande('⚔', 'FUERZA', '${c.fuerza}', war),
                  _statGrande('🛡', 'DEFENSA', '${c.defensa}', war),
                  _statGrande('Ø', 'COSTE', '${c.coste}', war, color: _cRayo),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _chipInfo(c.tipoIcon, c.tipoNombre, c.tipoColor, war),
                  _chipInfo(Icons.directions_run, 'Mov ${c.movimiento}',
                      war.primario, war),
                ],
              ),
              const SizedBox(height: 16),
              Text(c.desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: war.textoTenue)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(avanzarAlCerrar ? 'CONTINUAR' : 'CERRAR',
                      style: const TextStyle(
                          fontFamily: 'Cinzel', letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (avanzarAlCerrar) _advance();
  }

  Widget _statGrande(String glifo, String label, String valor, WarColors war,
      {Color? color}) {
    return Column(
      children: [
        Text(glifo, style: TextStyle(fontSize: 20, color: color ?? war.texto)),
        const SizedBox(height: 2),
        Text(valor,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color ?? war.texto)),
        Text(label,
            style: TextStyle(
                fontSize: 9, letterSpacing: 1, color: war.textoTenue)),
      ],
    );
  }

  Widget _chipInfo(IconData icon, String txt, Color color, WarColors war) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(txt,
              style: TextStyle(
                  fontSize: 12, color: war.texto, fontFamily: 'Cinzel')),
        ],
      ),
    );
  }

  // ── Panel guía inferior (coach) ─────────────────────────────
  _Coach get _coach {
    switch (_step) {
      case _Step.intro:
        return const _Coach(
          titulo: 'Bienvenido a WarZero',
          cuerpo:
              'Jugaremos una partida guiada en el mapa Clásico (6 filas × 10 '
              'columnas), con 4 cuarteles en las esquinas y el obelisco central. '
              'Tu cuartel es el amarillo, abajo a la derecha (F10). Puedes hacer '
              'zoom y arrastrar el tablero.',
          boton: 'COMENZAR',
        );
      case _Step.energiaZero:
        return const _Coach(
          titulo: '1 · Energía Zero (Ø)',
          cuerpo: 'Abajo, en tu barra de jugador, ves tu Energía Zero (Ø): '
              'la moneda del juego. Con ella '
              'despliegas cartas , lanzas acciones, y compras generales. La consigues ganando '
              'combates y minando en casillas con el icono (Ø) en amarillo del tablero.',
          boton: 'SIGUIENTE',
        );
      case _Step.atributos:
        return const _Coach(
          titulo: '2 · Atributos de una carta',
          cuerpo:
              ' Las cartas que aparecen abajo son tu mano en ese momento, las miniaturas te muestran los 4 atributos que tienen las cartas '
              ' Arriba izquierda Ø Coste (lo que pagas para desplegarla), ariba derecha ⚔ Fuerza (ataque), abajo izquierda movimiento, abajo derecha 🛡 Defensa (aguante)',
          boton: 'SIGUIENTE',
        );
      case _Step.cartaGrande:
        return const _Coach(
          titulo: '3 · Ver una carta en grande',
          cuerpo:
              'Mantén pulsada la carta "Soldado Celeste" de tu mano para ver '
              'todos sus datos en detalle, de esta forma podremos ver el tipo de terreno donde puede moverse esta carta tierra/mar/aire o el tipo de carta si es básica, estática o de acción, '
              'o descripción de la carta, o detalles de su historia y habilidades especiales. '
              'Cuando termines, pulsa SIGUIENTE.',
          boton: 'SIGUIENTE',
        );
      case _Step.sacarCuartel:
        final tieneSel = _selHand?.id == 'soldado';
        return _Coach(
          titulo: '4 · Sacar la carta al cuartel',
          cuerpo:
              'Para entrar en juego, primero SELECCIONA una carta tocándola en '
              'tu mano luego tócala sobre TU cuartel (amarillo, F10, esquina inferior derecha) '
              ' La mayoría de cartas deben pasar por el cuartel excepto estáticas '
              'que se colocan en cualquier celda donde tengas una carta que lleve mas de un turno, y las de acción que lanzan una habilidad sobre alguna celda',
          hint: tieneSel
              ? 'Ahora toca tu cuartel resaltado (F10)'
              : 'Selecciona el Soldado en tu mano',
        );
      case _Step.mover:
        String hint;
        if (_sidebarOpen) {
          hint = 'Selecciona el Soldado y pulsa MOVER';
        } else if (_selBoard == null) {
          hint = 'Toca tu Soldado para abrir su menú';
        } else {
          hint = 'Toca una celda resaltada';
        }
        return _Coach(
          titulo: '5 · Mover la carta',
          cuerpo:
              'Las unidades avanzan según su Movimiento. Toca tu Soldado en el '
              'tablero: se abrirá el MENÚ LATERAL con su ficha. Marca la carta '
              'y pulsa MOVER; entonces se iluminan las celdas a las que puede '
              'llegar. Toca una para desplazarte.',
          hint: hint,
        );
      case _Step.evolucion:
        return _Coach(
          titulo: '6 · Evolución',
          cuerpo: 'Algunas cartas pueden EVOLUCIONAR a una versión más potente '
              'pagando Energía Zero. Toca tu Soldado en el tablero para abrir su '
              'ficha: pulsa la FLECHA de evolución para ver en qué se convierte y '
              'luego EVOLUCIONAR (−${_soldado.evolucion}Ø). En una partida real, '
              'si EVOLUCIONAS una carta no puedes MOVERLA ese turno, y si ya la '
              'has movido no puedes evolucionarla. Para agilizar el tutorial nos '
              'saltamos esa condición.',
          hint: 'Toca tu Soldado y pulsa la flecha de evolución',
        );
      case _Step.batalla:
        if (_batallaResuelta) {
          // Segunda fase del paso: cerrar el turno para ver el informe.
          return const _Coach(
            titulo: '7 · Cierra el turno',
            cuerpo:
                'Tu carta ha entrado en la celda del Dron: ahora la celda muestra '
                'el ⚡ de cada bando (tu fuerza menos la defensa rival, y al revés). '
                'El combate NO se resuelve todavía y el Dron sigue ahí. Pulsa FIN '
                'TURNO (abajo a la derecha): al cerrar el turno se resuelven los '
                'combates, la carta enemiga es destruida y se genera el INFORME '
                'DE FIN DE TURNO.',
            hint: 'Pulsa FIN TURNO para resolver y ver el informe',
          );
        }
        return _Coach(
          titulo: '7 · ¡Batalla!',
          cuerpo:
              'Ha aparecido un Dron Rival junto a ti. Al entrar en una celda '
              'enemiga se combate: gana quien supere la defensa rival. '
              'Selecciona tu unidad y ataca al Dron.',
          hint: _selBoard == null
              ? 'Toca tu unidad para seleccionarla'
              : 'Toca la celda del Dron Rival',
        );
      case _Step.informe:
        return const _Coach(
          titulo: '8 · Informe de fin de turno',
          cuerpo:
              'El informe se abre en COMBATES con el combate que ganaste. Cambia '
              'a la pestaña ZERO para ver cómo se farmea la energía: los CRISTALES '
              'ZERO (celdas con el icono Ø, como C8) dan +10 Ø por turno a quien '
              'tenga una carta encima, y también ganas Ø al vencer combates. El '
              'informe reúne además ACCIONES, CARTA (la nueva carta del turno) y '
              'MOVIMIENTOS. Puedes reabrirlo con el botón 📜 de la barra superior.',
          boton: 'SIGUIENTE',
        );
      case _Step.estatica:
        final tieneSel = _selHand?.id == 'torreta';
        return _Coach(
          titulo: '9 · Cartas estáticas',
          cuerpo: 'La "Torreta Búnker" es ESTÁTICA: no se mueve (Mov 0). '
              'Selecciónala en tu mano y colócala sobre una '
              'celda que controlas.',
          hint: tieneSel
              ? 'Toca una celda resaltada para colocarla'
              : 'Selecciona la Torreta en tu mano',
        );
      case _Step.teletransporte:
        String hint;
        if (_selHand?.id != 'tele') {
          hint = 'Selecciona la carta Teletransporte en tu mano';
        } else if (_selBoard == null) {
          hint = 'Toca una carta TUYA del tablero';
        } else {
          hint = 'Toca la celda de destino';
        }
        return _Coach(
          titulo: '10 · Acción: Teletransporte',
          cuerpo: 'Las cartas de ACCIÓN lanzan efectos y se descartan. El '
              'Teletransporte mueve una carta tuya a cualquier celda libre: '
              'selecciona la acción, elige tu carta y luego el destino.',
          hint: hint,
        );
      case _Step.misil:
        final tieneSel = _selHand?.id == 'misil';
        return _Coach(
          titulo: '11 · Acción: Misil',
          cuerpo: 'Ha aparecido un Tanque Rival. El Misil Zero es una acción '
              'ofensiva: destruye una carta enemiga a distancia. Selecciónalo '
              'en tu mano y apunta al Tanque.',
          hint: tieneSel
              ? 'Toca la celda del Tanque Rival'
              : 'Selecciona el Misil en tu mano',
        );
      case _Step.fin:
        return const _Coach(
          titulo: '¡Tutorial completado!',
          cuerpo:
              'Ya conoces la Energía Zero, los atributos, el despliegue, el '
              'movimiento, la evolución, el combate y las cartas estáticas y de '
              'acción. ¡Estás listo para tu primera partida real!',
          boton: 'TERMINAR',
        );
    }
  }

  Widget _panelCoach(WarColors war) {
    final coach = _coach;
    final total = _orden.length - 1; // sin contar "fin"
    final actual = _paso.clamp(0, total);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: war.primario.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(coach.titulo,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: war.primario)),
              ),
              if (_step != _Step.intro && _step != _Step.fin)
                Text('Paso $actual/${total - 1}',
                    style: TextStyle(
                        fontSize: 11,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel')),
            ],
          ),
          const SizedBox(height: 8),
          Text(coach.cuerpo,
              style: TextStyle(fontSize: 13, height: 1.4, color: war.texto)),
          const SizedBox(height: 12),
          if (coach.boton != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_step == _Step.fin) {
                    Navigator.of(context).maybePop();
                  } else {
                    _advance();
                  }
                },
                child: Text(coach.boton!,
                    style: const TextStyle(
                        fontFamily: 'Cinzel', letterSpacing: 1)),
              ),
            )
          else if (coach.hint != null)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Row(
                children: [
                  Icon(Icons.touch_app,
                      size: 18,
                      color:
                          war.primario.withOpacity(0.5 + 0.5 * _pulse.value)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(coach.hint!,
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: war.primario
                                .withOpacity(0.7 + 0.3 * _pulse.value))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _Coach {
  final String titulo;
  final String cuerpo;
  final String? boton;
  final String? hint;
  const _Coach({
    required this.titulo,
    required this.cuerpo,
    this.boton,
    this.hint,
  });
}
