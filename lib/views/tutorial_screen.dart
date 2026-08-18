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
import '../widgets/board_widget.dart';
import '../models/jugador_model.dart';
import '../widgets/player_hud.dart';
import '../widgets/hand_widget.dart';
import '../widgets/carta_rota_animation.dart';
import '../widgets/card_detail_overlay.dart';

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
      _recalcTargets();
    });
  }

  void _onCellTap(String coord) {
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
        if (placed?.owner == 'yo' && placed!.card.movimiento > 0) {
          setState(() {
            _selBoard = coord;
            _recalcTargets();
          });
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

  void _atacar(String coordEnemigo) {
    final origen = _selBoard ?? _friendlyCoords().first;
    final enemigo = _board[coordEnemigo];
    final yo = _board[origen];
    setState(() {
      final movida = _board.remove(origen)!;
      _board[coordEnemigo] = movida;
      _zero += enemigo?.card.coste ?? 0;
    });
    _mostrarResultadoCombate(yo?.card ?? _soldado, enemigo?.card ?? _dron,
        enemigo?.card.coste ?? 0, coordEnemigo);
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
    return BoardState(celdas: celdas, rayoCoords: const {_rayo});
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final resaltarEnergia = _step == _Step.energiaZero;
    return Scaffold(
      backgroundColor: war.fondo,
      body: SafeArea(
        child: Column(
          children: [
            // ── Menú superior REAL de la partida (jugadores + salir) ──
            PartidaTopBar(
              nombrePartida: 'TUTORIAL',
              colorAsignado: _cYo,
              jugadores: _hudJugadores,
              onSalir: () => Navigator.of(context).maybePop(),
              // En el tutorial estas acciones se muestran atenuadas (inertes).
              puedeCuartel: false,
              onCuartel: () {},
              puedeInforme: false,
              onInforme: () {},
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
                boardState: _buildBoardState(),
                selectedCellCoord: _selBoard,
                highlightEmpty: _usaDeploy,
                deployCoords: _usaDeploy ? _targets : const {},
                movableCoords: _usaDeploy ? const {} : _targets,
                obeliscoLocal: _hqYo,
                obeliscoCoords: _obeliscoCoords,
                obeliscoColores: _obeliscoColores,
                playerColors: _playerColors,
                localPlayerUid: 'yo',
                onBackgroundTap: () {
                  if (_selBoard != null) {
                    setState(() {
                      _selBoard = null;
                      _recalcTargets();
                    });
                  }
                },
                onCellTap: (coord, ri, ci) => _onCellTap(coord),
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
                // Inertes en el tutorial: se avanza con el panel de abajo.
                onEndTurn: null,
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

  // ── Resultado de combate (igual que en el juego) ────────────
  /// Presenta el combate con la MISMA animación de carta rota que usa el
  /// informe de batalla del juego (`CartaRotaStrip`), más el desglose de
  /// fuerza/defensa/poder neto y la recompensa.
  void _mostrarResultadoCombate(
      _TCard atacante, _TCard defensor, int premio, String coord) {
    final war = context.war;
    const verde = Color(0xFF4ABB58);
    final poderNeto = atacante.fuerza - defensor.defensa;
    final pnTxt = poderNeto >= 0 ? '+$poderNeto' : '$poderNeto';

    Widget stat(String icon, String value, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.35), width: 0.6),
          ),
          child: Text('$icon $value',
              style:
                  TextStyle(fontFamily: 'Cinzel', fontSize: 10, color: color)),
        );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: war.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera ⚔ CELDA — como el informe de batalla del juego.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: verde.withOpacity(0.10),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(children: [
                  Text('⚔  COMBATE EN $coord',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 11,
                          letterSpacing: 1.5,
                          color: war.primario)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: verde.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('TU COMBATE',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            letterSpacing: 1,
                            color: verde)),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.emoji_events, size: 15, color: verde),
                        const SizedBox(width: 6),
                        const Text('VICTORIA: TÚ',
                            style: TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: 10,
                                letterSpacing: 1,
                                color: verde)),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 21),
                        child: Text('+$premio Ø  ·  +3 PC',
                            style: TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: 9,
                                color: war.textoTenue)),
                      ),
                      const SizedBox(height: 10),
                      // Desglose fuerza (tú) vs defensa (rival) y poder neto.
                      Row(children: [
                        stat('⚔', '${atacante.fuerza}', _cYo),
                        const SizedBox(width: 8),
                        Text('vs',
                            style: TextStyle(
                                color: war.textoTenue,
                                fontFamily: 'Cinzel',
                                fontSize: 9)),
                        const SizedBox(width: 8),
                        stat('🛡', '${defensor.defensa}', _cRojo),
                        const Spacer(),
                        stat('⚡', pnTxt, verde),
                      ]),
                      const SizedBox(height: 16),
                      // Animación de carta rota — EXACTAMENTE la del juego.
                      Center(
                        child: CartaRotaStrip(
                          cartas: [
                            {
                              'Nombre': defensor.nombre,
                              'Fuerza': defensor.fuerza,
                              'Defensa': defensor.defensa,
                              'Imagen': '',
                              'ownerUid': 'rojo',
                              'ownerZone': 'nw',
                            }
                          ],
                          localUid: 'yo',
                          colorZona: (z) =>
                              (z == 'se' || z == 'yo') ? _cYo : _cRojo,
                          titulo: 'CARTA ENEMIGA DESTRUIDA',
                          cardWidth: 116,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tu fuerza (${atacante.fuerza}) supera la defensa '
                        'enemiga (${defensor.defensa}): la unidad rival es '
                        'destruida y conquistas la celda.',
                        style: TextStyle(
                            fontSize: 11, height: 1.4, color: war.textoTenue),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _advance();
                          },
                          child: const Text('CONTINUAR',
                              style: TextStyle(
                                  fontFamily: 'Cinzel', letterSpacing: 1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
        return _Coach(
          titulo: '5 · Mover la carta',
          cuerpo:
              'Las unidades avanzan según su Movimiento. Toca tu Soldado en el '
              'tablero para seleccionarlo y luego una de las celdas resaltadas '
              'a las que puede llegar.',
          hint: _selBoard == null
              ? 'Toca tu Soldado en el tablero'
              : 'Toca una celda resaltada',
        );
      case _Step.evolucion:
        return _Coach(
          titulo: '6 · Evolución',
          cuerpo: 'Algunas cartas pueden EVOLUCIONAR a una versión más potente '
              'pagando Energía Zero. Toca tu Soldado en el tablero para abrir su '
              'ficha: pulsa la FLECHA de evolución para ver en qué se convierte y '
              'luego EVOLUCIONAR (−${_soldado.evolucion}Ø). Una carta recién '
              'evolucionada no puede moverse ese turno.',
          hint: 'Toca tu Soldado y pulsa la flecha de evolución',
        );
      case _Step.batalla:
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
      case _Step.estatica:
        final tieneSel = _selHand?.id == 'torreta';
        return _Coach(
          titulo: '8 · Cartas estáticas',
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
          titulo: '9 · Acción: Teletransporte',
          cuerpo: 'Las cartas de ACCIÓN lanzan efectos y se descartan. El '
              'Teletransporte mueve una carta tuya a cualquier celda libre: '
              'selecciona la acción, elige tu carta y luego el destino.',
          hint: hint,
        );
      case _Step.misil:
        final tieneSel = _selHand?.id == 'misil';
        return _Coach(
          titulo: '10 · Acción: Misil',
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
