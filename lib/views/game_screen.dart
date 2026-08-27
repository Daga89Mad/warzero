// lib/views/game_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/game_config.dart';
import '../models/board_state.dart';
import '../models/jugador_model.dart';
import '../services/turn_service.dart';
import '../services/warzero_api.dart';
import '../models/alianza_estado.dart';
import 'alianza_screen.dart';
import '../services/combate_service.dart';
import 'informe_batalla_screen.dart';
import 'revision_turno_screen.dart';
import '../models/lobby_model.dart';
import '../widgets/board_widget.dart';
import '../widgets/card_detail_overlay.dart';
import '../widgets/cell_sidebar.dart';
import '../widgets/cell_widget.dart' show ownerColor;
import '../widgets/hand_widget.dart';
import '../widgets/player_hud.dart';
import '../models/accion_pendiente.dart';
import '../models/efecto_estado.dart';
import '../models/habilidad_model.dart';
import '../services/accion_controller.dart';
import '../services/habilidad_service.dart';
import '../services/pending_revert_store.dart';
import 'cuartel_screen.dart';
import 'puntuaciones_screen.dart';

/// Silueta fantasma de una carta en su celda de origen (revisión post-cierre).
/// Es estructuralmente idéntico a `RevisionFantasma` de board_widget.dart (los
/// records de Dart son de tipado estructural), así que se puede pasar tal cual
/// al parámetro `fantasmasRevision` del BoardWidget sin depender de aquel nombre.
typedef _Fantasma = ({
  String origen,
  String destino,
  Color color,
  IconData icon,
  Color iconColor,
  int movimiento,
  String nombre,
});

class GameScreen extends StatefulWidget {
  final String localPlayerUid;
  final int playerCount;

  /// ID del documento Partidas en Firestore.
  /// Null en partidas locales/test (se asigna obelisco aleatorio sin persistir).
  final String? lobbyId;

  const GameScreen({
    super.key,
    required this.localPlayerUid,
    this.playerCount = 4,
    this.lobbyId,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late GameConfig _config;
  BoardState _boardState = const BoardState();

  late PlayerSession _localPlayer;
  late PlayerSession _opponentPlayer;

  String? _obeliscoLocal;
  String? _obeliscoOponente;

  /// Imagen de fondo del mapa de ESTA partida (ruta de asset o URL). Se carga en
  /// _aplicarTerreno desde el documento del mapa. Null → BoardWidget usa la
  /// imagen por defecto.
  String? _imagenMapa;

  /// Lee las coords de los rayos de farmeo del doc/estado. Soporta el formato
  /// nuevo (`rayos`: lista de {coord,...} o `rayoCoords`: lista de coords) y el
  /// antiguo (`rayo`: {coord} único / `rayoCoord`: coord única).
  Set<String> _rayoCoordsFromData(Map<String, dynamic> data) {
    final out = <String>{};
    final rayos = data['rayos'];
    if (rayos is List) {
      for (final r in rayos) {
        if (r is Map && r['coord'] is String) out.add(r['coord'] as String);
        if (r is String) out.add(r);
      }
    }
    final rcs = data['rayoCoords'];
    if (rcs is List) {
      for (final c in rcs) {
        if (c is String) out.add(c);
      }
    }
    // Retrocompatibilidad con el formato antiguo de rayo único.
    final r = data['rayo'];
    if (r is Map && r['coord'] is String) out.add(r['coord'] as String);
    final rc = data['rayoCoord'];
    if (rc is String) out.add(rc);
    return out;
  }

  /// Coords de cuarteles destruidos (conquistados) leídos del doc.
  Set<String> _cuartelesDestruidosFromData(Map<String, dynamic> data) {
    final raw = data['cuartelesDestruidos'] as List? ?? const [];
    final res = <String>{};
    for (final e in raw) {
      if (e is Map) {
        final c = e['coord'];
        if (c is String && c.isNotEmpty) res.add(c);
      } else if (e is String && e.isNotEmpty) {
        res.add(e);
      }
    }
    return res;
  }

  /// uid → color del obelisco asignado (se carga desde Firestore)
  Map<String, Color> _playerColors = {};

  /// uid → coord del obelisco asignado (para lógica de conquista)
  Map<String, String> _obeliscosPorJugador = {};

  // ── Modo turno ────────────────────────────────────────────
  ModoTurno _modoTurno = ModoTurno.rapida;
  List<String> _cerradoPor = [];
  int _jugadoresEnPartida = 2;

  /// Duración (segundos) de cada turno en PARTIDA RÁPIDA.
  static const int _duracionTurnoRapidoSeg = 90;
  int _segundosRestantes = _duracionTurnoRapidoSeg;
  bool _timerActivo = false;

  bool _resolviendo = false;
  bool _isSendingTurn = false;
  bool _sondeoActivo = false;
  final WarZeroApi _api = WarZeroApi();

  /// Estado `alianzas` de la partida (para la pantalla y los avisos).
  Map<String, dynamic> _alianzas = {};

  /// uids aliados del jugador local (incluye su propio uid). Se recalcula en
  /// [_revisarAlianzas] y se pasa al tablero para que una casilla compartida
  /// SOLO con aliados se pinte como pila amistosa y no como combate.
  Set<String> _aliadosLocal = {};

  /// Claves de propuestas/avisos ya mostrados (para no repetir en cada sondeo).
  final Set<String> _alianzaVistos = {};

  /// Nº de propuestas de alianza ENTRANTES pendientes de responder (para el
  /// badge del menú). Se recalcula en cada _revisarAlianzas desde el estado.
  int _propuestasPendientes = 0;

  /// Jugadores eliminados (cuartel conquistado).
  List<String> _jugadoresEliminados = [];

  /// True si el jugador local fue eliminado.
  bool _estoyEliminado = false;

  /// True si la partida ha terminado (solo queda 1 jugador).
  bool _juegoTerminado = false;
  String? _ganadorUid;

  List<Map<String, dynamic>> _lastCombateLog = [];
  List<Map<String, dynamic>> _lastMovimientosLog = [];
  List<Map<String, dynamic>> _lastFarmeoLog = []; // ← nuevo
  List<Map<String, dynamic>> _lastAccionesLog = []; // ← nuevo (disparos, etc.)
  Set<String> _lastRayoCoords = {}; // coords de rayos del último informe
  /// Fecha límite de resolución obligatoria (epoch millis UTC, 00:00) que envía
  /// el servidor en `fechaResolucion`. Null si aún no se conoce.
  int? _fechaResolucionMs;
  LobbyModel? _currentLobby;
  List<Map<String, dynamic>> _historialCombates = [];

  int _informeMostradoTurno = 0;
  bool _informeAbierto = false;
  String _hostUid = '';

  bool _cargaCompletada = false;
  int _turnoConfirmadoStream = 0;

  bool get _yoCerreElTurno => _cerradoPor.contains(widget.localPlayerUid);

  /// Número de jugadores activos (no eliminados).
  int get _jugadoresActivos =>
      math.max(1, _jugadoresEnPartida - _jugadoresEliminados.length);

  bool get _esperandoOtros =>
      _yoCerreElTurno && _cerradoPor.length < _jugadoresActivos;
  bool get _todosCerraronTurno => _cerradoPor.length >= _jugadoresActivos;

  // ── Mano y mazo ───────────────────────────────────────────
  List<CartaModel> _hand = [];
  List<CartaModel> _mazoRestante = [];

  /// Mazo completo del jugador (pool de hasta 8 cartas). Cada turno, salvo el
  /// primero, se roba una de estas al azar (con repetición).
  List<CartaModel> _mazoCompleto = [];

  /// IDs de las cartas de EVOLUCIÓN que el jugador local POSEE en su colección.
  /// Regla: una carta base solo puede evolucionar si su evolución está aquí
  /// (poseer la base NO implica poseer la evolución). Se rellena en initState.
  final Set<String> _evolucionesPoseidas = {};
  bool _evolucionesPoseidasCargadas = false;

  /// Última carta robada (para mostrarla en el informe del turno).
  CartaModel? _ultimaCartaRepartida;
  int? _selectedHandIndex;

  /// Ejército del jugador local (para filtrar especiales en el cuartel).
  int? _miEjercitoId;

  /// IDs de cartas especiales ya compradas por el jugador esta partida
  /// (deshabilitadas para futuras compras suyas).
  final Set<String> _especialesCompradas = {};

  /// IDs de especiales compradas EN ESTE TURNO (subconjunto de las anteriores).
  /// Se usan para desmarcarlas en el servidor si el jugador deshace o sale a
  /// mitad de turno (bug QAS #2). Se limpia al empezar cada turno.
  final Set<String> _especialesCompradasEsteTurno = {};

  /// Nº de cartas robadas en el CUARTEL esta partida. Define el precio del
  /// próximo robo (100 · 2^n → 100, 200, 400…). Es permanente: se persiste en
  /// statsPartida.{uid}.robosComprados para que el precio no se reinicie al
  /// reentrar a la partida.
  int _robosComprados = 0;

  /// Precio del PRÓXIMO robo de carta en el cuartel.
  int get _precioRoboActual => 100 * (1 << _robosComprados);

  // ── Sidebar ───────────────────────────────────────────────
  String? _sidebarCoord;
  int? _sidebarRi;
  int? _sidebarCi;
  bool _sidebarOpen = false;

  /// Key estable del tablero: preserva su State (incluido el nivel de zoom) aunque
  /// el árbol de widgets se reorganice al abrir/cerrar capas superpuestas.
  final GlobalKey _boardKey = GlobalKey();

  // ── Modo movimiento ───────────────────────────────────────
  String? _moveFromCoord;
  List<int> _moveCardIndices = [];
  Set<String> _movableCoords = {};
  bool get _inMoveMode => _moveFromCoord != null;
// ── Modo acción / habilidad ─────────────────────────────────
  late AccionController _accionController;

  /// Acciones declaradas en este turno (se envían al cerrar turno).
  final List<AccionPendiente> _accionesPendientes = [];

  /// Marcadores puramente visuales y locales: carta(s) de acción colocadas
  /// en una celda mientras la acción está pendiente de resolverse al cerrar
  /// turno. Solo las ve el jugador que las lanzó; no se sincronizan con el
  /// servidor ni afectan al cálculo de combate (no viven en `_boardState`).
  final Map<String, List<CartaModel>> _fantasmasAccion = {};

  /// Efectos de celda activos (leídos de Firestore y mantenidos en memoria).
  Map<String, List<EfectoActivo>> _efectosCelda = {};

  bool get _inActionMode => _accionController.activo;

  /// Coords resaltables en el tablero: depende del modo activo.
  ///   - Modo movimiento → _movableCoords
  ///   - Modo acción     → objetivos válidos del controlador
  Set<String> get _highlightCoords =>
      _inActionMode ? _accionController.objetivosValidos : _movableCoords;
  // ── Snapshot inicial del turno ─────────────────────────────
  BoardState _boardStateInicial = const BoardState();
  List<CartaModel> _handInicial = [];

  /// instanceId (identidad por-instancia, NO carta.id) de las cartas del
  /// jugador que ya se movieron / desplegaron-estáticas / se compraron este
  /// turno y por tanto no pueden volver a moverse. Usar carta.id aquí era el
  /// bug de "dos Tiburón de combate": mover una copia bloqueaba a la otra.
  final Set<String> _cartasMovidasEsteTurno = {};

  /// Cartas robadas este turno cuyo gasto/carta aún NO se han consolidado
  /// (se consolidan al cerrar turno). Se usa para: (a) impedir sacrificarlas
  /// el mismo turno y (b) identificarlas por referencia al revertir.
  final List<CartaModel> _cartasRobadasEsteTurno = [];

  /// Exclusión mutua POR CARTA (no por turno): una carta que se movió este turno
  /// no puede evolucionar, y una que evolucionó no puede moverse. Se rastrea por
  /// instanceId (identidad por-instancia), IGUAL que la exclusión mover/habilidad.
  /// Así mover una carta NO bloquea evolucionar OTRA distinta (bug QAS #3).
  /// (El despliegue desde la mano no cuenta como movimiento a estos efectos.)
  final Set<String> _cartasQueEvolucionaron = {};

  /// Exclusión mutua por CARTA: una carta que se mueve no puede usar habilidad
  /// ese turno, y una que usa habilidad no puede moverse. Indexado por
  /// instanceId (identidad por-instancia), por el mismo motivo que arriba.
  final Set<String> _cartasQueSeMovieron = {};
  final Set<String> _cartasQueUsaronHabilidad = {};

  /// instanceId → celda de ORIGEN del movimiento de este turno (la primera celda
  /// desde la que se movió la carta este turno). Se registra en el momento del
  /// movimiento, por lo que es fiable incluso para cartas desplegadas o
  /// recolocadas este turno; no depende de emparejar por instanceId con el
  /// tablero inicial (que puede reasignar instanceId al reconstruirse).
  final Map<String, String> _origenTurnoPorId = {};

  /// REVISIÓN POST-CIERRE: instantánea de lo que hice este turno, tomada al
  /// cerrar el turno. Se dibuja sobre el tablero (flechas origen→destino de mis
  /// movimientos y resaltado de las celdas objetivo de mis acciones) hasta que
  /// el turno se resuelve. Sobrevive a los refrescos de espera y se limpia
  /// cuando el turno avanza. Así el jugador ve "de dónde a dónde se movió y
  /// dónde puso cada acción" mientras espera.
  List<_Fantasma> _revisionFantasmas = const [];
  Set<String> _revisionAcciones = const {};

  bool get _hayCambiosPendientes =>
      _cartasMovidasEsteTurno.isNotEmpty || _accionesPendientes.isNotEmpty;

  // ── Energía snapshot al inicio de cada turno ──────────────
  /// Energías del jugador al comenzar el turno (para restaurar en undo).
  int _puntosInicial = 0;

  /// Energía total gastada en despliegues este turno (para restaurar en Firestore).
  int _energiaGastadaDespliegue = 0;

  /// Marca que, al pausar la app, quedó una reversión de turno pendiente de
  /// reembolsar en el servidor. Al reanudar se consume para reintentar el
  /// reembolso (ver _reembolsarPendienteAlReanudar).
  bool _reembolsoPendienteTrasPausa = false;

  /// Persiste en disco la deuda de energía/especiales NO consolidada del turno
  /// en curso. Se llama tras CADA gasto y tras cada reversión local, con la app
  /// activa (fiable frente a suspensiones y cierres forzados). Así, si el móvil
  /// se bloquea sin cerrar turno, el reembolso puede reintentarse al reentrar.
  void _persistirDeudaPendiente() {
    final id = widget.lobbyId;
    if (id == null) return;
    PendingRevertStore.guardar(
      id,
      DeudaRevert(
        turno: _boardState.turnoActual,
        energia: _energiaGastadaDespliegue,
        especiales: _especialesCompradasEsteTurno.toList(),
      ),
    );
  }

  /// Borra la deuda persistida (tras consolidar el gasto: cerrar turno, deshacer
  /// manual o salir con reembolso inmediato ya aplicado).
  void _limpiarDeudaPendiente() {
    final id = widget.lobbyId;
    if (id == null) return;
    PendingRevertStore.limpiar(id);
  }

  /// Reembolsa en el SERVIDOR la energía NO consolidada que quedó pendiente de un
  /// turno en curso al salir/bloquear el móvil sin cerrar turno, leyéndola del
  /// almacén persistente. Idempotente y con guardas para NO reembolsar de más:
  /// solo actúa si la deuda pertenece al turno abierto ACTUAL y el jugador aún no
  /// lo ha cerrado. Devuelve la energía reembolsada (0 si no procede). Desmarca
  /// localmente las especiales revertidas.
  Future<int> _reconciliarReembolsoPendiente({
    required int turnoServidor,
    required bool cerradoPorMi,
  }) async {
    final id = widget.lobbyId;
    if (id == null) return 0;

    final deuda = await PendingRevertStore.leer(id);
    if (deuda == null || deuda.vacia) {
      await PendingRevertStore.limpiar(id);
      return 0;
    }

    // Guardas anti doble-reembolso: si el turno ya avanzó (deuda de un turno
    // anterior) o si YO cerré este turno (el gasto se consolidó al cerrar), la
    // deuda no debe reembolsarse: se descarta.
    if (deuda.turno != turnoServidor || cerradoPorMi) {
      await PendingRevertStore.limpiar(id);
      return 0;
    }

    // Reembolsar en el servidor la energía revertible y desmarcar especiales.
    await _api.deshacerTurno(
      lobbyId: id,
      uid: widget.localPlayerUid,
      turno: deuda.turno,
      energiesDelta: deuda.energia,
      especialesQuitar: deuda.especiales,
    );
    await PendingRevertStore.limpiar(id);

    // Reflejar localmente el desmarcado de especiales (el estado cargado del
    // servidor aún las traía marcadas).
    if (deuda.especiales.isNotEmpty && mounted) {
      setState(() => _especialesCompradas.removeAll(deuda.especiales));
    }
    debugPrint('[WZ][deuda] reembolso reconciliado turno=${deuda.turno} '
        'energia=${deuda.energia} especiales=${deuda.especiales.length}');
    return deuda.energia;
  }

  /// Al reanudar la app tras haber revertido el turno en la pausa: reintenta el
  /// reembolso ahora que hay red. No ajusta la energía local porque al pausar ya
  /// se restauró al snapshot de inicio de turno (_puntosInicial), que coincide
  /// con la energía del servidor una vez aplicado el reembolso.
  Future<void> _reembolsarPendienteAlReanudar() async {
    if (widget.lobbyId == null || _estoyEliminado || _juegoTerminado) return;
    await _reconciliarReembolsoPendiente(
      turnoServidor: _boardState.turnoActual,
      cerradoPorMi: _yoCerreElTurno,
    );
  }

  bool _loading = true;
  String? _error;

  // ── Tamaño inicial de la mano al arrancar la partida ───────
  static const int _initialHandSize = 5;

  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Observa el ciclo de vida para revertir en el servidor la energía gastada
    // este turno si la app pasa a segundo plano / se cierra sin cerrar el turno
    // (los movimientos no se persisten a mitad de turno; ver incidencia #1).
    WidgetsBinding.instance.addObserver(this);
    _config = GameConfig.forPlayerCount(widget.playerCount);
    _accionController = AccionController(config: _config);
    _setupPlayers();
    // Despierta el servidor de Render (free tier duerme tras inactividad) en
    // paralelo, para que esté listo cuando _loadGame llame a entrar().
    if (widget.lobbyId != null) {
      _api.despertar();
    }
    _cargarEvolucionesPoseidas();
    _loadGame();
    _loadGame();
  }

  void _setupPlayers() {
    _localPlayer = PlayerSession(
      datos: JugadorDatos(
          uid: widget.localPlayerUid,
          alias: 'Jugador',
          dinero: 0,
          imagenPerfil: ''),
      zona: 'south',
      colorIndex: 1,
      vida: 20,
      puntos: 0,
    );
    _opponentPlayer = PlayerSession(
      datos: JugadorDatos(
          uid: 'opponent_1', alias: 'Enemigo', dinero: 0, imagenPerfil: ''),
      zona: 'north',
      colorIndex: 0,
      vida: 20,
      puntos: 0,
    );
  }

  /// Best-effort: ¿ya intentamos cargar el perfil real del jugador local?
  bool _perfilLocalCargado = false;

  /// Actualiza el alias del jugador local con el REAL del lobby. El alias
  /// inicial es un placeholder ("Jugador"); sin esto el banner inferior mostraba
  /// "JUGADOR" en lugar del alias de la cuenta. No hace setState (se llama desde
  /// dentro de uno).
  void _sincronizarAliasLocalDesdeLobby(LobbyModel? lobby) {
    if (lobby == null) return;
    for (final j in lobby.jugadores) {
      if (j.uid == widget.localPlayerUid) {
        if (j.alias.isNotEmpty && j.alias != _localPlayer.datos.alias) {
          _localPlayer = _localPlayer.copyWith(
            datos: JugadorDatos(
              uid: _localPlayer.datos.uid,
              alias: j.alias,
              dinero: _localPlayer.datos.dinero,
              imagenPerfil: _localPlayer.datos.imagenPerfil,
              nivel: _localPlayer.datos.nivel,
              experiencia: _localPlayer.datos.experiencia,
            ),
          );
        }
        return;
      }
    }
  }

  /// Carga (best-effort, sin bloquear) el alias e imagen de perfil reales del
  /// jugador local desde el servidor, para el avatar del HUD inferior. Si falla
  /// (p. ej. arranque en frío), se puede reintentar en la siguiente carga.
  Future<void> _cargarPerfilLocal() async {
    if (_perfilLocalCargado || widget.lobbyId == null) return;
    _perfilLocalCargado = true;
    try {
      final data = await _api.obtenerColeccion(widget.localPlayerUid);
      final jug = data?['jugador'];
      if (jug is Map && mounted) {
        final alias = (jug['alias'] as String?)?.trim() ?? '';
        final img = (jug['imagenPerfil'] as String?)?.trim() ?? '';
        setState(() {
          _localPlayer = _localPlayer.copyWith(
            datos: JugadorDatos(
              uid: _localPlayer.datos.uid,
              alias: alias.isNotEmpty ? alias : _localPlayer.datos.alias,
              dinero: _localPlayer.datos.dinero,
              imagenPerfil: img,
              nivel: _localPlayer.datos.nivel,
              experiencia: _localPlayer.datos.experiencia,
            ),
          );
        });
      }
    } catch (_) {
      _perfilLocalCargado = false; // permitir reintento
    }
  }

  /// Paleta de 8 colores distintos para cuarteles/jugadores. El color por coord
  /// (_obeliscoColor) solo conocía las 4 posiciones clásicas y devolvía gris
  /// para el resto; en mapas de 8 hay que dar un color propio a cada jugador.
  static const List<Color> _paletaJugadores = [
    Color(0xFFFF3030), // rojo
    Color(0xFF3080FF), // azul
    Color(0xFFFFCC00), // amarillo
    Color(0xFF30FF70), // verde
    Color(0xFFC060FF), // morado
    Color(0xFFFF8C1A), // naranja
    Color(0xFF20D0D0), // cian
    Color(0xFFFF66AA), // rosa
  ];

  static Color _colorJugadorPorIndice(int i) =>
      _paletaJugadores[i % _paletaJugadores.length];

  static Color _obeliscoColor(String coord) {
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
        return const Color(0xFF888888);
    }
  }

  // ── Evoluciones que el jugador POSEE (regla de evolución) ──
  /// Carga desde el servidor las evoluciones que el jugador tiene en su
  /// colección. Se usa para permitir/impedir evolucionar en el tablero: tener
  /// la carta base NO implica tener su evolución. Hace setState para refrescar
  /// los botones de evolución del sidebar.
  Future<void> _cargarEvolucionesPoseidas() async {
    try {
      final data = await _api.obtenerColeccion(widget.localPlayerUid);
      final ids = ((data?['evolucionesPoseidas'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _evolucionesPoseidas
          ..clear()
          ..addAll(ids);
        _evolucionesPoseidasCargadas = true;
      });
    } catch (_) {
      // Sin bloqueo permanente ante fallos de red: se reintenta de forma
      // perezosa la primera vez que se intente evolucionar.
      _evolucionesPoseidasCargadas = false;
    }
  }

  // ── Resolver carta de evolución desde el catálogo vía API ─
  Future<CartaModel?> _resolveEvolucion(String idEvolucion) async {
    if (idEvolucion.isEmpty) return null;
    try {
      final cartas = await _api.obtenerCartas([idEvolucion]);
      return cartas.isEmpty ? null : cartas.first;
    } catch (_) {
      return null;
    }
  }

  // ── Evolucionar una carta en una celda ────────────────────
  Future<void> _evolucionarCarta(
      String coord, int indice, CartaModel evolucion) async {
    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }
    // ── Regla de colección: solo puedes evolucionar si POSEES la evolución.
    //    Tener la carta base no implica tenerla. Si aún no se cargó la lista
    //    (p. ej. fallo de red al entrar), se pide ahora antes de decidir.
    if (!_evolucionesPoseidasCargadas) {
      await _cargarEvolucionesPoseidas();
    }
    if (!mounted) return;
    if (_evolucionesPoseidasCargadas &&
        !_evolucionesPoseidas.contains(evolucion.id)) {
      _toast('No posees la evolución de esta carta.', error: true);
      return;
    }
    final celda = _boardState.getCelda(coord);
    if (indice < 0 || indice >= celda.cartas.length) return;

    final original = celda.cartas[indice];
    if (original.ownerUid != _localPlayer.datos.uid) {
      _toast('No puedes evolucionar cartas ajenas', error: true);
      return;
    }
    // Exclusión POR CARTA: solo esta carta queda bloqueada si YA se movió este
    // turno. Mover otras cartas NO impide evolucionar esta (bug QAS #3).
    if (_cartasQueSeMovieron.contains(original.instanceId)) {
      _toast('Esta carta ya se movió este turno: no puede evolucionar.',
          error: true);
      return;
    }

    // ── Terreno: la carta EVOLUCIONADA debe poder estar en el terreno de la
    //    celda actual. P. ej. una terrestre que evoluciona a marina no puede
    //    hacerlo en una celda de tierra; debe estar en agua/anfibio (y al revés).
    if (!_config.canLand(coord, evolucion.tipo)) {
      _toast(
          '🌊 Terreno incompatible: ${evolucion.nombre} no puede estar en esta celda',
          error: true);
      return;
    }

    final coste = original.carta.evolucion;
    if (_localPlayer.puntos < coste) {
      _toast('Energías insuficientes (${_localPlayer.puntos} / $coste)',
          error: true);
      return;
    }

    final nuevaCarta = CartaEnCelda(
      carta: evolucion,
      ownerUid: original.ownerUid,
      ownerZone: original.ownerZone,
    );
    final nuevasCartas = [...celda.cartas];
    nuevasCartas[indice] = nuevaCarta;
    final nuevaCelda = celda.withCartas(nuevasCartas);

    setState(() {
      _boardState = _boardState.setCelda(coord, nuevaCelda);
      _localPlayer.puntos -= coste;
      // Energía revertible de este turno (para deshacer / salir).
      _energiaGastadaDespliegue += coste;
      // La carta evolucionada (esta instancia concreta) no puede moverse este
      // turno. Se rastrea por instanceId, no por plantilla.
      _cartasMovidasEsteTurno.add(nuevaCarta.instanceId);
      _cartasQueEvolucionaron.add(nuevaCarta.instanceId);
    });

    if (widget.lobbyId != null) {
      try {
        await _api.actualizarStats(
          lobbyId: widget.lobbyId!,
          uid: widget.localPlayerUid,
          energiesDelta: -coste,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _boardState = _boardState.setCelda(coord, celda);
          _localPlayer.puntos += coste;
          _energiaGastadaDespliegue -= coste;
          _cartasMovidasEsteTurno.remove(nuevaCarta.instanceId);
          _cartasQueEvolucionaron.remove(nuevaCarta.instanceId);
        });
        _toast('Error al evolucionar. Inténtalo de nuevo.', error: true);
        return;
      }
    }

    _toast('${original.carta.nombre} → ${evolucion.nombre}  (-${coste}Ø)');
    _persistirDeudaPendiente();
  }

  // ── Helper para reconstruir un CartaModel desde un mapa ───
  CartaModel _cartaFromMap(Map<String, dynamic> c, {String? fallbackId}) {
    final carta = CartaModel.fromMap(c);
    if (fallbackId != null && fallbackId.isNotEmpty && carta.id.isEmpty) {
      return carta.copyWith(id: fallbackId);
    }
    return carta;
  }

  // ── Restaurar lista de cartas desde IDs (respeta duplicados) ──
  /// Dado una lista de IDs (puede tener repetidos), extrae del [pool] las
  /// cartas correspondientes en orden, consumiendo cada instancia una vez.
  List<CartaModel> _restoreCartasFromIds(
      List<String> ids, List<CartaModel> pool) {
    final disponibles = List<CartaModel>.from(pool);
    final result = <CartaModel>[];
    for (final id in ids) {
      final idx = disponibles.indexWhere((c) => c.id == id);
      if (idx != -1) {
        result.add(disponibles[idx]);
        disponibles.removeAt(idx);
      }
    }
    return result;
  }

  /// Resuelve una lista de IDs de carta (con duplicados) a modelos. Busca
  /// primero en [pool] (el mazo ya resuelto) y, para los IDs que no estén ahí
  /// (p. ej. cuando el servidor repartió de un mazo por defecto), los carga del
  /// catálogo `Cartas`. Permite repetir un mismo ID varias veces.
  Future<List<CartaModel>> _resolverCartasPorIds(
      List<String> ids, List<CartaModel> pool) async {
    final porId = <String, CartaModel>{};
    for (final c in pool) {
      porId.putIfAbsent(c.id, () => c);
    }

    final faltantes =
        ids.toSet().where((id) => !porId.containsKey(id)).toList();
    if (faltantes.isNotEmpty) {
      try {
        final extra = await _api.obtenerCartas(faltantes);
        for (final c in extra) {
          porId[c.id] = c;
        }
      } catch (_) {}
    }

    final result = <CartaModel>[];
    for (final id in ids) {
      final c = porId[id];
      // copyWith() por cada aparición: cada carta de la mano es una INSTANCIA
      // propia aunque varias compartan id (p. ej. 4 parálisis divina). Así el
      // rastreo por referencia (robada/sacrificio) distingue copias en vez de
      // compartir un único objeto entre todas.
      if (c != null) result.add(c.copyWith());
    }
    return result;
  }

  // ── Persistir mano y mazo restante vía API (sin Firestore) ─
  void _saveHandAndDeck() {
    if (widget.lobbyId == null) return;
    _api
        .actualizarStats(
          lobbyId: widget.lobbyId!,
          uid: widget.localPlayerUid,
          mano: _hand.map((c) => c.id).toList(),
          mazoRestante: _mazoRestante.map((c) => c.id).toList(),
        )
        .catchError((_) => null); // fire-and-forget
  }

  /// ¿Puede el jugador volver a repartir ahora? Solo en el PRIMER turno, en su
  /// turno y SIN haber jugado nada (para no dejar cartas desplegadas sin
  /// consolidar fuera de la mano). Un sacrificio no lo impide (no deja cartas en
  /// el tablero), pero un despliegue sí (haría _hand ≠ _handInicial en tamaño).
  bool get _puedeVolverARepartir =>
      _boardState.turnoActual == 1 &&
      !_yoCerreElTurno &&
      !_estoyEliminado &&
      !_hayCambiosPendientes &&
      _energiaGastadaDespliegue == 0 &&
      _hand.length == _handInicial.length;

  /// Descarta la mano del primer turno y reparte una nueva, barajando la mano
  /// actual junto al mazo restante. Solo disponible en el primer turno.
  void _volverARepartir() {
    if (_boardState.turnoActual != 1 || _yoCerreElTurno || _estoyEliminado) {
      return;
    }
    if (!_puedeVolverARepartir) {
      _toast('Deshaz tus jugadas de este turno para volver a repartir.',
          error: true);
      return;
    }
    final pool = <CartaModel>[..._hand, ..._mazoRestante]
      ..shuffle(math.Random());
    final nuevaMano = pool.take(_initialHandSize).toList();
    final nuevoMazo = pool.skip(_initialHandSize).toList();
    setState(() {
      _hand = nuevaMano;
      _mazoRestante = nuevoMazo;
      _handInicial = List.from(nuevaMano);
      _selectedHandIndex = null;
    });
    _saveHandAndDeck();
    _toast('Se ha repartido tu mano de nuevo.');
  }

  /// Muestra un panel deslizante con el MAZO del jugador: el pool completo del
  /// que se roba 1 carta al azar cada turno (con repetición; el pool no se
  /// agota). Se abre al pulsar "MAZO DISPONIBLE" en el HUD inferior.
  void _mostrarMazoDisponible() {
    // El pool real de robo por turno es el mazo completo (server: mazoPool),
    // NO _mazoRestante (que es solo el sobrante tras la mano inicial).
    final mazo = List<CartaModel>.from(_mazoCompleto);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.style, size: 16, color: Color(0xFFC8A860)),
                  const SizedBox(width: 8),
                  const Text('MAZO DISPONIBLE',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE0D8C0))),
                  const SizedBox(width: 8),
                  Text('${mazo.length} carta${mazo.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 10,
                          color: Color(0xFF6A7A8A))),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Tu mazo completo. Cada turno recibes 1 carta al azar de aquí '
                '(puede repetirse).',
                style: TextStyle(fontSize: 9, color: Color(0xFF6A7A8A)),
              ),
              const SizedBox(height: 12),
              if (mazo.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No quedan cartas en el mazo.',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 11,
                            color: Color(0xFF506070))),
                  ),
                )
              else
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: mazo.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _MazoCard(
                      carta: mazo[i],
                      onTap: () => showCardDetail(
                        ctx,
                        mazo[i],
                        resolveEvolucion: _resolveEvolucion,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reparto de fin de turno (autoritativo del servidor, bug QAS #2) ───────
  /// cartaId que el servidor repartió a [uid] en el último turno resuelto
  /// (data['ultimoRepartoLog']), o null si no le tocó carta.
  String? _cartaIdRepartidaPara(Map<String, dynamic> data, String uid) {
    final raw = data['ultimoRepartoLog'];
    if (raw is! List) return null;
    for (final e in raw) {
      if (e is Map && e['uid'] == uid) {
        final id = e['cartaId']?.toString();
        return (id == null || id.isEmpty) ? null : id;
      }
    }
    return null;
  }

  /// True si al jugador local le repartieron carta en el último turno resuelto.
  bool _meRepartieronCarta(Map<String, dynamic> data) =>
      _cartaIdRepartidaPara(data, widget.localPlayerUid) != null;

  /// Sincroniza mano y mazo restante desde el estado autoritativo del servidor
  /// (statsPartida.{uid}.mano/.mazoRestante), que YA incluye la carta de fin de
  /// turno repartida en el servidor. Sustituye al antiguo robo local: así la
  /// carta no se pierde aunque el jugador no esté presente al resolver el turno.
  Future<void> _sincronizarManoDesdeEstado(Map<String, dynamic> data) async {
    final rawStats = data['statsPartida'] as Map<String, dynamic>? ?? {};
    if (!rawStats.containsKey(widget.localPlayerUid)) return;
    final myS =
        Map<String, dynamic>.from(rawStats[widget.localPlayerUid] as Map);
    final manoIds =
        (myS['mano'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final mazoIds =
        (myS['mazoRestante'] as List?)?.map((e) => e.toString()).toList() ??
            const [];
    final mano = manoIds.isEmpty
        ? <CartaModel>[]
        : await _resolverCartasPorIds(manoIds, _mazoCompleto);
    final mazo = mazoIds.isEmpty
        ? <CartaModel>[]
        : await _resolverCartasPorIds(mazoIds, _mazoCompleto);
    if (!mounted) return;
    final manoFiltrada =
        mano.where((c) => !c.esEvolucion && !c.esEspecial).toList();
    setState(() {
      _hand = manoFiltrada;
      _mazoRestante = mazo;
      _handInicial = List.from(manoFiltrada);
    });
  }

  /// Revierte en el SERVIDOR los gastos NO consolidados del turno en curso:
  /// devuelve la energía revertible gastada este turno (despliegues + compras +
  /// evoluciones) y desmarca las especiales compradas este turno. Se usa al SALIR
  /// a mitad de turno y al pulsar DESHACER, para que no se pierdan los Zeros ni
  /// quede el general comprado sin poder recomprarse. El tablero revierte solo
  /// (no se persiste a mitad de turno). Fire-and-forget.
  void _revertirGastosServidor() {
    if (widget.lobbyId == null) return;
    final energia = _energiaGastadaDespliegue;
    final especiales = _especialesCompradasEsteTurno.toList();
    if (energia <= 0 && especiales.isEmpty) return;
    _api.deshacerTurno(
      lobbyId: widget.lobbyId!,
      uid: widget.localPlayerUid,
      turno: _boardState.turnoActual,
      energiesDelta: energia,
      especialesQuitar: especiales,
    );
    // El reembolso ya se lanzó aquí (app activa): borrar la deuda persistida para
    // que _loadGame no la reembolse otra vez al reentrar.
    _limpiarDeudaPendiente();
  }

  // ── Cargar terreno del mapa vía API (sin Firestore) ──────
  Future<void> _aplicarTerreno(String mapaId) async {
    try {
      final data = await _api.obtenerMapa(mapaId);
      if (data == null || !mounted) return;

      final raw = (data['terreno'] as Map?) ?? {};
      final terreno = <String, TerrainType>{};
      raw.forEach((coord, valor) {
        terreno[coord.toString()] = switch (valor?.toString() ?? 'land') {
          'sea' => TerrainType.sea,
          'deepSea' => TerrainType.deepSea,
          'amphibious' => TerrainType.amphibious,
          _ => TerrainType.land,
        };
      });

      // Rejilla REAL del mapa. Un mapa puede tener más celdas que el preset del
      // nº de jugadores (p. ej. 12×20 en una partida de 8, cuyo preset es 12×18).
      // Sin aplicar filas/columnas del mapa, esas columnas/filas extra no existen
      // en juego y los obeliscos o continentes que caen ahí (p. ej. col 19-20) se
      // salen del tablero. Requiere que el endpoint /warzero/mapa devuelva
      // filas/columnas (WarZeroService.MapaTerrenoAsync + WarZeroExtensions).
      var filas = (data['filas'] as num?)?.toInt();
      var columnas = (data['columnas'] as num?)?.toInt();

      // Robustez: si el doc del mapa NO trae filas/columnas (o vienen a 0), las
      // inferimos de las coordenadas del propio terreno (máx. letra de fila y
      // máx. número de columna). Así un mapa 12×20 se dibuja completo aunque el
      // documento no declare sus dimensiones, en vez de quedarse con el preset.
      if (filas == null || columnas == null || filas <= 0 || columnas <= 0) {
        final d = _dimsDesdeCoords(terreno.keys);
        if (filas == null || filas <= 0) filas = d.rows > 0 ? d.rows : null;
        if (columnas == null || columnas <= 0) {
          columnas = d.cols > 0 ? d.cols : null;
        }
      }

      // Imagen de fondo del mapa (ruta de asset o URL). Si viene vacía, se deja
      // null para que BoardWidget use la imagen por defecto.
      final imagen = (data['imagen'] as String?)?.trim();

      setState(() {
        var cfg = _config;
        if (filas != null && columnas != null && filas > 0 && columnas > 0) {
          cfg = cfg.withGrid(filas: filas, columnas: columnas);
        }
        _config = cfg.withTerrain(terreno);
        // IMPORTANTE: el AccionController se creó con el _config del preset. Si
        // no le propagamos la rejilla real, calcularObjetivosValidos usa un grid
        // equivocado y, p. ej., el "escudo lejano" (rango = cualquiera) marca
        // celdas de un tablero distinto al que se ve → no deja seleccionar.
        _accionController.actualizarConfig(_config);
        if (imagen != null && imagen.isNotEmpty) _imagenMapa = imagen;
      });
    } catch (_) {}
  }

  /// Dimensiones (filas, columnas) mínimas que contienen todas las [coords]
  /// tipo "A1".."T20": fila = letra inicial (A→1), columna = número. Devuelve
  /// (0,0) si no hay coordenadas válidas. Se usa para dibujar/expandir la
  /// rejilla al tamaño REAL del mapa aunque el documento no declare filas y
  /// columnas.
  static ({int rows, int cols}) _dimsDesdeCoords(Iterable<String> coords) {
    int rows = 0, cols = 0;
    for (final c in coords) {
      if (c.isEmpty) continue;
      final code = c.codeUnitAt(0);
      if (code < 65 || code > 90) continue; // debe empezar por A..Z
      final r = code - 64; // 'A' → 1
      final col = int.tryParse(c.substring(1));
      if (col == null || col <= 0) continue;
      if (r > rows) rows = r;
      if (col > cols) cols = col;
    }
    return (rows: rows, cols: cols);
  }

  /// Expande (nunca encoge) la rejilla de [_config] para que contenga todas las
  /// coordenadas reales del juego —obeliscos y cartas del tablero— y propaga la
  /// nueva config al AccionController. Red de seguridad para mapas cuyo grid no
  /// llegó a aplicarse (obeliscos/celdas en columnas/filas fuera del preset):
  /// sin esto, el cuartel puede caer fuera del tablero y "no aparece ninguna
  /// casilla" al desplegar.
  /// Expande (nunca encoge) la rejilla de [_config] para que contenga [coords]
  /// y propaga la nueva config al AccionController. Red de seguridad usada tanto
  /// al recibir estado por el stream (obeliscos que llegan tarde en partidas de
  /// 8 jugadores) como al iniciar un movimiento (garantiza que la celda de
  /// ORIGEN está en la rejilla; si no lo está, el BFS no encuentra la casilla y
  /// no se pintan las casillas verdes de destino). Devuelve true si expandió.
  bool _expandirGridSiHaceFalta(Iterable<String> coords) {
    final d = _dimsDesdeCoords(coords);
    if (d.rows > _config.rows || d.cols > _config.cols) {
      setState(() {
        _config = _config.withGrid(
          filas: d.rows > _config.rows ? d.rows : _config.rows,
          columnas: d.cols > _config.cols ? d.cols : _config.cols,
        );
        _accionController.actualizarConfig(_config);
      });
      return true;
    }
    return false;
  }

  void _ajustarGridAContenido(
      Map<String, dynamic> data, Map<String, String> obeliscos) {
    final coords = <String>{}
      ..addAll(obeliscos.values.where((c) => c.isNotEmpty));
    final tablero = data['tablero'];
    if (tablero is Map) {
      coords.addAll(tablero.keys.map((k) => k.toString()));
    }
    if (coords.isEmpty) return;
    final d = _dimsDesdeCoords(coords);
    if (d.rows > _config.rows || d.cols > _config.cols) {
      setState(() {
        _config = _config.withGrid(
          filas: d.rows > _config.rows ? d.rows : _config.rows,
          columnas: d.cols > _config.cols ? d.cols : _config.cols,
        );
        _accionController.actualizarConfig(_config);
      });
    }
  }

  /// Ejército mayoritario entre [cartas] (el id que más se repite), o null si
  /// la lista está vacía. Se usa para que el cuartel siga el ejército del mazo
  /// que realmente se juega, aunque el lobby tenga otro `ejercitoId`.
  int? _ejercitoDominante(List<CartaModel> cartas) {
    if (cartas.isEmpty) return null;
    final conteo = <int, int>{};
    for (final c in cartas) {
      conteo[c.ejercito] = (conteo[c.ejercito] ?? 0) + 1;
    }
    return conteo.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<void> _loadGame() async {
    try {
      // ── 1. Entrar a la partida vía API (init atómica energías + obelisco) ──
      int? ejercitoId;
      LobbyModel? lobby;
      Map<String, dynamic> data = {};
      String? obeliscoAsignadoServer;

      if (widget.lobbyId != null) {
        EntrarResult? entrada;
        try {
          entrada = await _api.entrar(
            lobbyId: widget.lobbyId!,
            uid: widget.localPlayerUid,
          );
          debugPrint('[WZ][entrar] turno=${entrada?.turnoActual} '
              'energias=${entrada?.energiasAsignadas} '
              'obelisco=${entrada?.obeliscoAsignado}');
          obeliscoAsignadoServer = entrada?.obeliscoAsignado;
        } catch (e) {
          debugPrint('[WZ][entrar] error API entrar: $e');
        }
        if (!mounted) return;

        if (entrada?.estado != null) {
          data = entrada!.estado!;
          lobby = LobbyModel.fromMap(widget.lobbyId!, data);
        } else {
          // Fallback API (sin Firestore): si entrar() no devolvió estado,
          // pedimos el estado por HTTP. Mantiene todo el flujo sobre la API.
          try {
            final est = await _api.obtenerEstado(widget.lobbyId!);
            if (!mounted) return;
            if (est != null) {
              data = est;
              lobby = LobbyModel.fromMap(widget.lobbyId!, data);
            }
          } catch (e) {
            debugPrint('[WZ][entrar] fallback obtenerEstado falló: $e');
          }
        }

        if (lobby != null) {
          final myJugador = lobby.jugadores.cast<LobbyJugador?>().firstWhere(
              (j) => j?.uid == widget.localPlayerUid,
              orElse: () => null);
          ejercitoId = myJugador?.ejercitoId;
        }
      }
      _miEjercitoId = ejercitoId;

      // ── 3. Cargar mazo filtrado por ejército (vía API, sin Firestore) ──
      final mazoCartas = await _api.obtenerMazo(
        widget.localPlayerUid,
        ejercitoId: ejercitoId,
      );
      if (!mounted) return;

      // Pool de robo por turno: el mazo completo sin evoluciones ni especiales.
      _mazoCompleto =
          mazoCartas.where((c) => !c.esEvolucion && !c.esEspecial).toList();

      // FIX (cuartel de otro ejército): el `ejercitoId` del lobby puede NO
      // coincidir con el ejército del mazo que realmente se juega. Ocurre si el
      // jugador quedó asignado a un ejército (p. ej. Demonios) del que NO tiene
      // mazo: el servidor, al no encontrar mazo de ese ejército, cae a su mazo
      // principal (p. ej. Humanos) y, al vaciarse el filtro, lo PRESERVA
      // (MazoDelJugadorAsync → Construir(false)). Resultado: se juega Humanos
      // pero el cuartel, que usaba el id del lobby, mostraba especiales de
      // Demonios. La fuente de verdad para el cuartel debe ser el ejército de
      // las cartas que de verdad despliegas, así que lo derivamos del mazo.
      final ejercitoDeMazo = _ejercitoDominante(_mazoCompleto);
      if (ejercitoDeMazo != null &&
          ejercitoDeMazo != 0 &&
          ejercitoDeMazo != _miEjercitoId) {
        debugPrint('[WZ][ejercito] lobby=$_miEjercitoId difiere del mazo real '
            '=$ejercitoDeMazo → el cuartel usa el del mazo');
        _miEjercitoId = ejercitoDeMazo;
      }

      debugPrint('[WZ][ejercito] seleccionado=$_miEjercitoId '
          'cartasMazo=${_mazoCompleto.length} '
          'ejercitosEnMazo=${_mazoCompleto.map((c) => c.ejercito).toSet()}');

      if (lobby != null) {
        // ── 4. Configurar estado del lobby ────────────────────────
        setState(() {
          _modoTurno = lobby!.modoTurno;
          _jugadoresEnPartida = lobby.jugadores.length;
          _cerradoPor = List<String>.from(lobby.cerradoPor);
        });
        _revisarAlianzas(data);

        if (lobby.mapaId != null) {
          await _aplicarTerreno(lobby.mapaId!);
          if (!mounted) return;
        }

        // Logs y stats
        final loadedCombateLog =
            (data['ultimoCombateLog'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        final loadedMovLog =
            (data['ultimosMovimientos'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        final rawStats = data['statsPartida'] as Map<String, dynamic>? ?? {};
        // ── Energías iniciales ────────────────────────────────
        // Si el jugador no tiene entrada en statsPartida (primera vez que
        // entra al juego), se le asignan 15 energías y se persisten.
        const int _energiasIniciales = 15;
        int puntosRestaurados;

        if (rawStats.containsKey(widget.localPlayerUid)) {
          final myS =
              Map<String, dynamic>.from(rawStats[widget.localPlayerUid] as Map);
          puntosRestaurados = (myS['energies'] as num?)?.toInt() ?? 0;
          // Especiales ya compradas por el jugador esta partida.
          final compradas = myS['especialesCompradas'] as List?;
          if (compradas != null) {
            _especialesCompradas
              ..clear()
              ..addAll(compradas.map((e) => e.toString()));
          }
          // Robos de cuartel ya realizados (precio creciente del robo).
          _robosComprados = (myS['robosComprados'] as num?)?.toInt() ?? 0;
        } else {
          // Primera vez: el servidor ya asigna energías en POST /warzero/entrar,
          // pero por robustez las fijamos también vía API (increment sobre campo
          // ausente lo crea = _energiasIniciales). Sin Firestore.
          puntosRestaurados = _energiasIniciales;
          _api
              .actualizarStats(
                lobbyId: widget.lobbyId!,
                uid: widget.localPlayerUid,
                energiesDelta: _energiasIniciales,
              )
              .catchError((_) => null);
        }
        final loadedFarmeoLog =
            (data['ultimoFarmeoLog'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        final loadedAccionesLog =
            (data['ultimoAccionesLog'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        // Reembolsar energía pendiente de un turno anterior que quedó sin cerrar
        // al bloquear el móvil / matar la app (ver PendingRevertStore). Va ANTES
        // de fijar _puntosInicial para que el snapshot de inicio de turno ya
        // incluya el reembolso.
        final int turnoServidorCarga =
            (data['turnoActual'] as num?)?.toInt() ?? 0;
        final bool cerradoPorMiCarga =
            _cerradoPor.contains(widget.localPlayerUid);
        final int reembolso = await _reconciliarReembolsoPendiente(
          turnoServidor: turnoServidorCarga,
          cerradoPorMi: cerradoPorMiCarga,
        );
        if (!mounted) return;
        if (reembolso > 0) puntosRestaurados += reembolso;

        _puntosInicial = puntosRestaurados;
        final loadedHistorial =
            (data['historialCombates'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        // Jugadores eliminados
        final rawElim = data['jugadoresEliminados'] as List? ?? [];
        final eliminados = List<String>.from(rawElim);

        // Obeliscos
        final obeliscosData = data['obeliscos'] as Map<String, dynamic>? ?? {};
        final colors = <String, Color>{};
        final obeliscosMap = <String, String>{};
        // Color por jugador con paleta de 8 (antes _obeliscoColor solo conocía
        // las 4 coords clásicas y devolvía gris para el resto). Orden estable por
        // coord para que el color sea consistente entre clientes.
        final entradasObel = obeliscosData.entries.toList()
          ..sort((a, b) => a.value.toString().compareTo(b.value.toString()));
        for (var i = 0; i < entradasObel.length; i++) {
          final uid = entradasObel[i].key;
          final coord = entradasObel[i].value as String;
          colors[uid] = _colorJugadorPorIndice(i);
          obeliscosMap[uid] = coord;
        }
        // Extraer el cuartel del jugador local y del oponente directamente
        // del doc. Respaldo: el obelisco que el servidor dice haber asignado.
        final obeliscoLocalDoc =
            obeliscosMap[widget.localPlayerUid] ?? obeliscoAsignadoServer;
        debugPrint('[WZ][entrar] obeliscos=$obeliscosMap '
            'localUid=${widget.localPlayerUid} '
            'cuartelLocal=$obeliscoLocalDoc '
            'asignadoServer=$obeliscoAsignadoServer');
        final obeliscoOponenteDoc = obeliscosMap.entries
            .firstWhere((e) => e.key != widget.localPlayerUid,
                orElse: () => const MapEntry('', ''))
            .value
            .nullIfEmpty;

        // Estado del juego
        final juegoTerminado = lobby.estado == LobbyEstado.finalizada;

        setState(() {
          _currentLobby = lobby;
          _sincronizarAliasLocalDesdeLobby(lobby);
          _lastCombateLog = loadedCombateLog;
          _lastMovimientosLog = loadedMovLog;
          _lastFarmeoLog = loadedFarmeoLog; // ← nuevo
          _lastAccionesLog = loadedAccionesLog; // ← nuevo
          _lastRayoCoords = _rayoCoordsFromData(data); // ← nuevo
          _historialCombates = loadedHistorial;
          _localPlayer.puntos = puntosRestaurados;
          _playerColors = colors;
          _obeliscosPorJugador = obeliscosMap;
          if (obeliscoLocalDoc != null) _obeliscoLocal = obeliscoLocalDoc;
          if (obeliscoOponenteDoc != null) {
            _obeliscoOponente = obeliscoOponenteDoc;
          }
          _jugadoresEliminados = eliminados;
          _estoyEliminado = eliminados.contains(widget.localPlayerUid);
          _juegoTerminado = juegoTerminado;
          _ganadorUid = lobby!.ganadorUid;
        });

        // Red de seguridad de rejilla: garantiza que el tablero contiene todas
        // las coordenadas reales (obeliscos + cartas). Si el grid del mapa no se
        // aplicó (doc sin filas/columnas) y el cuartel cae en una columna/fila
        // fuera del preset, sin esto "no aparece ninguna casilla" al desplegar.
        _ajustarGridAContenido(data, obeliscosMap);

        // ── 5. Restaurar tablero ──────────────────────────────────
        // `serverStartBoard` = tablero autoritativo (inicio del turno en curso).
        // OJO: el estado puede NO traer `tablero` (p. ej. turno 1, donde aún no
        // se ha resuelto nada y solo hay despliegues). Por eso reconstruimos
        // SIEMPRE la vista con MIS movimientos comprometidos (movimientosTurno),
        // así al reentrar se ven mis unidades donde las dejé y las flechas/acciones.
        BoardState serverStartBoard = const BoardState();
        if (data.containsKey('tablero')) {
          final tableroRaw = TurnService.parseTablero(data);
          var restoredBoard = const BoardState();
          tableroRaw.forEach((coord, cartas) {
            for (final c in cartas) {
              // IMPORTANTE: `CartaEnCelda.fromMap` preserva el campo `Efectos`
              // de la carta (veneno arrastrado, potenciaciones, etc.). El
              // constructor pelado los descartaba, por eso al reentrar
              // desaparecían los buffs/venenos aunque el servidor sí los
              // persiste. Debe hacerse EXACTAMENTE igual que en _aplicarEstado.
              restoredBoard = restoredBoard.placeCarta(
                coord,
                CartaEnCelda.fromMap(c),
              );
            }
          });
          serverStartBoard = restoredBoard;
        }
        // Efectos de CELDA (veneno de celda, escudo, parálisis…). También se
        // descartaban en esta ruta: sin ellos el tablero no marca las celdas
        // afectadas ni el sidebar muestra su estado.
        final efectosCeldaEntrar = TurnService.parseEfectosCelda(data);
        // Rayos / cuarteles / turno / efectosCelda se aplican SIEMPRE.
        serverStartBoard = serverStartBoard
            .copyWith(
              turnoActual: lobby!.turnoActual,
              efectosCelda: efectosCeldaEntrar,
            )
            .withRayos(_rayoCoordsFromData(data))
            .withCuarteles(_cuartelesDestruidosFromData(data));
        final displayBoard =
            _reconstruirBoardConMisMovimientos(data, serverStartBoard);
        setState(() {
          _boardState = displayBoard;
          _actualizarOverlayRevision(data);
        });

        // ── 6. Restaurar mano y mazo (con soporte de duplicados) ──
        // El servidor reparte la mano (POST /warzero/entrar) y guarda los IDs en
        // statsPartida.{uid}.mano/.mazoRestante. Resolvemos esos IDs a modelos
        // contra el mazo y, si falta alguno (p. ej. mazo por defecto del
        // servidor), contra el catálogo de Cartas.
        List<CartaModel> manoFinal = [];
        List<CartaModel> mazoRestanteFinal = [];

        if (rawStats.containsKey(widget.localPlayerUid)) {
          final myS =
              Map<String, dynamic>.from(rawStats[widget.localPlayerUid] as Map);
          final manoIds = myS['mano'] as List?;
          final mazoIds = myS['mazoRestante'] as List?;

          if (manoIds != null && manoIds.isNotEmpty) {
            manoFinal = await _resolverCartasPorIds(
                manoIds.map((e) => e.toString()).toList(), mazoCartas);
            if (!mounted) return;
          }
          if (mazoIds != null && mazoIds.isNotEmpty) {
            mazoRestanteFinal = await _resolverCartasPorIds(
                mazoIds.map((e) => e.toString()).toList(), mazoCartas);
            if (!mounted) return;
          }
        }

        // Fallback: si el servidor no repartió (mano vacía) → repartir en cliente.
        if (manoFinal.isEmpty && !_estoyEliminado) {
          final cartasEnTablero = _boardState.celdas.values
              .expand((c) => c.cartas)
              .where((c) => c.ownerUid == _localPlayer.datos.uid)
              .map((c) => c.carta.id)
              .toSet();

          final pool = List<CartaModel>.from(mazoCartas.where((c) =>
              !cartasEnTablero.contains(c.id) &&
              !c.esEvolucion &&
              !c.esEspecial))
            ..shuffle(math.Random());

          manoFinal = pool.take(_initialHandSize).toList();
          mazoRestanteFinal = pool.skip(_initialHandSize).toList();

          // Guardar inmediatamente (fallback)
          setState(() {
            _hand = manoFinal;
            _mazoRestante = mazoRestanteFinal;
          });
          _saveHandAndDeck();
        } else {
          // Filtrar evoluciones y especiales de la mano restaurada.
          manoFinal =
              manoFinal.where((c) => !c.esEvolucion && !c.esEspecial).toList();
        }

        setState(() {
          _hand = manoFinal;
          _mazoRestante = mazoRestanteFinal;
          _loading = false;
          // El "inicial" del turno es el tablero autoritativo del servidor (sin
          // mis movimientos aplicados encima), para diffs/reversiones correctos.
          _boardStateInicial = serverStartBoard;
          _handInicial = List.from(manoFinal);
          _cartasMovidasEsteTurno.clear();
          _cartasRobadasEsteTurno.clear();
          _cartasQueEvolucionaron.clear();
          _cartasQueSeMovieron.clear();
          _origenTurnoPorId.clear();
          _cartasQueUsaronHabilidad.clear();
          _energiaGastadaDespliegue = 0;
          _especialesCompradasEsteTurno.clear();
          // NOTA: NO se limpia aquí la capa de revisión: ya se calculó desde el
          // servidor en el paso 5 y debe persistir al reentrar mientras el turno
          // cerrado se resuelve.
        });
        _turnoConfirmadoStream = lobby.turnoActual;
        _fechaResolucionMs = (data['fechaResolucion'] as num?)?.toInt();
        // Al (re)entrar se muestra el informe del ÚLTIMO turno resuelto
        // (turnoActual - 1) una vez; los anteriores ya no se repiten. Por eso la
        // guarda se deja en turnoActual - 2 y se llama a _maybeMostrarInforme.
        _informeMostradoTurno = lobby.turnoActual - 2;
        _cargaCompletada = true;

        // Cargar alias e imagen de perfil reales para el avatar del HUD
        // inferior (best-effort, no bloquea).
        _cargarPerfilLocal();

        if (lobby.modoTurno == ModoTurno.rapida && lobby.cerradoPor.isEmpty) {
          _startTimer();
        }
        _iniciarPolling();
        // El obelisco lo asigna el servidor en POST /warzero/entrar; los datos
        // ya vienen en `data['obeliscos']` y se aplicaron arriba.

        // Abrir por defecto el informe del último turno resuelto al reentrar
        // (resuelve además _ultimaCartaRepartida desde ultimoRepartoLog, para que
        // la carta de fin de turno aparezca aunque no estuviéramos presentes).
        _maybeMostrarInforme(lobby.turnoActual, data);

        // La resolución del turno la hace el servidor; el stream avanza solo.
        // (Antes aquí se disparaba la resolución en cliente.)

        // Mostrar pantallas de fin de juego si procede
        if (_juegoTerminado || _estoyEliminado) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_estoyEliminado && !_juegoTerminado) {
              _showEliminadoDialog();
            } else if (_juegoTerminado) {
              _showFinPartidaDialog();
            }
          });
        }
        return;
      }

      // ── Modo offline (sin lobby) ──────────────────────────────
      final fullHand = List<CartaModel>.from(
          mazoCartas.where((c) => !c.esEvolucion && !c.esEspecial).toList())
        ..shuffle();
      final manoInicial = fullHand.take(_initialHandSize).toList();
      final mazoOff = fullHand.skip(_initialHandSize).toList();
      setState(() {
        _hand = manoInicial;
        _mazoRestante = mazoOff;
        _loading = false;
        _boardStateInicial = _boardState;
        _handInicial = List.from(manoInicial);
        _cartasMovidasEsteTurno.clear();
        _cartasRobadasEsteTurno.clear();
        _cartasQueEvolucionaron.clear();
        _cartasQueSeMovieron.clear();
        _origenTurnoPorId.clear();
        _cartasQueUsaronHabilidad.clear();
        _puntosInicial = 0;
        _energiaGastadaDespliegue = 0;
        _especialesCompradasEsteTurno.clear();
        _revisionFantasmas = const [];
        _revisionAcciones = const {};
      });
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(() {
          _error = 'La conexión tardó demasiado.\nPulsa Reintentar.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  Timer? _pollTimer;
  bool _polling = false;

  /// Intervalo con el que está armado ahora mismo el sondeo. Se usa para
  /// re-armar el timer cuando cambia el modo de turno (al conocer que la
  /// partida es diaria/12h pasamos de un sondeo rápido a uno mucho más lento).
  Duration? _pollIntervaloActual;

  /// Cadencia del sondeo del estado según el modo de turno. En `rápida` los
  /// turnos duran segundos y conviene ver pronto el movimiento del rival; en
  /// `diario`/`turno12h` el turno tarda HORAS en resolverse, así que sondear a
  /// menudo solo malgasta lecturas de Firestore.
  Duration _intervaloPoll() {
    switch (_modoTurno) {
      case ModoTurno.diario:
      case ModoTurno.turno12h:
        return const Duration(seconds: 45);
      case ModoTurno.rapida:
        return const Duration(seconds: 8);
    }
  }

  /// Abre el informe de batalla del último turno resuelto, si aún no se mostró.
  /// Es idempotente: usa `_informeMostradoTurno` como guarda, así puede llamarse
  /// en cada snapshot sin abrir el informe dos veces. Independiente del avance
  /// del tablero, para que no se lo "coma" otra ruta que suba el turno antes.
  Future<void> _maybeMostrarInforme(
      int turnoActual, Map<String, dynamic> data) async {
    if (!mounted) return;
    if (turnoActual <= 1) return;
    final turnoInforme = turnoActual - 1;
    if (turnoInforme <= _informeMostradoTurno) {
      debugPrint('[WZ][informe] skip: turnoInforme=$turnoInforme <= '
          'mostrado=$_informeMostradoTurno');
      return;
    }
    if (_informeAbierto || _estoyEliminado || _juegoTerminado) {
      debugPrint('[WZ][informe] skip: abierto=$_informeAbierto '
          'eliminado=$_estoyEliminado terminado=$_juegoTerminado');
      return;
    }
    debugPrint('[WZ][informe] ABRIENDO informe turno=$turnoInforme');

    List<Map<String, dynamic>> parseLista(dynamic raw) {
      final out = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          try {
            if (e is Map) out.add(Map<String, dynamic>.from(e));
          } catch (_) {}
        }
      }
      return out;
    }

    final combateLog = parseLista(data['ultimoCombateLog']);
    final movLog = parseLista(data['ultimosMovimientos']);
    final farmeoLog = parseLista(data['ultimoFarmeoLog']); // ← nuevo
    final accionesLog = parseLista(data['ultimoAccionesLog']); // ← nuevo
    final rayoCoords = _rayoCoordsFromData(data); // ← nuevo
    final historialData = parseLista(data['historialCombates']);

    _lastCombateLog = combateLog;
    _lastMovimientosLog = movLog;
    _lastFarmeoLog = farmeoLog; // ← nuevo
    _lastAccionesLog = accionesLog; // ← nuevo
    _lastRayoCoords = rayoCoords; // ← nuevo
    _historialCombates = historialData;
    _informeMostradoTurno = turnoInforme;
    _informeAbierto = true;

    // BUG QAS #2: la carta de fin de turno la reparte el SERVIDOR y viaja en
    // data['ultimoRepartoLog']. La resolvemos aquí para mostrarla SIEMPRE en el
    // informe, aunque el jugador no estuviera presente cuando el turno resolvió.
    _ultimaCartaRepartida = null;
    final miRepartoId = _cartaIdRepartidaPara(data, widget.localPlayerUid);
    if (miRepartoId != null) {
      try {
        final resueltas =
            await _resolverCartasPorIds([miRepartoId], _mazoCompleto);
        if (resueltas.isNotEmpty) _ultimaCartaRepartida = resueltas.first;
      } catch (_) {}
    }
    if (!mounted) {
      _informeAbierto = false;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _informeAbierto = false;
        return;
      }
      Navigator.of(context)
          .push(MaterialPageRoute(
        builder: (_) => InformeBatallaScreen(
          combateLog: combateLog,
          movimientosLog: movLog,
          historial: historialData,
          localUid: widget.localPlayerUid,
          jugadores: _currentLobby?.jugadores ?? [],
          turno: turnoInforme,
          farmeoLog: farmeoLog, // ← nuevo
          accionesLog: accionesLog, // ← nuevo
          rayoCoords: rayoCoords.toList(),
          ultimaCartaRepartida: _ultimaCartaRepartida,
        ),
      ))
          .whenComplete(() {
        _informeAbierto = false;
        _abrirRevisionTurno(turnoRevisar: turnoInforme);
      });
    });
  }

  /// Procesa un estado de partida recibido por la API (mismo shape que el doc
  /// de Firestore). Antes era el listener del stream en tiempo real; ahora se
  /// alimenta del sondeo HTTP periódico (_pollEstado), eliminando la dependencia
  /// del realtime de Firestore que causaba cuelgues en Android.
  void _procesarEstado(Map<String, dynamic> data, LobbyModel lobby) {
    if (!mounted) return;

    _fechaResolucionMs = (data['fechaResolucion'] as num?)?.toInt();
    _revisarAlianzas(data);

    debugPrint('[WZ][poll] turnoActual=${lobby.turnoActual} '
        'turnoConfirmado=$_turnoConfirmadoStream '
        'cerradoPor=${lobby.cerradoPor} '
        'activos=$_jugadoresActivos '
        'informeMostrado=$_informeMostradoTurno '
        'informeAbierto=$_informeAbierto '
        'hasTablero=${data.containsKey('tablero')} '
        'estado=${lobby.estado}');

    try {
      // ── Actualizar obeliscos ──────────────────────────────────
      final obelData = data['obeliscos'] as Map<String, dynamic>? ?? {};
      final streamColors = <String, Color>{};
      final streamObeliscos = <String, String>{};
      // Color por jugador con paleta de 8 (orden estable por coord), igual que
      // en _loadGame, para que coincida entre carga inicial y sondeo.
      final entradasObelStream = obelData.entries.toList()
        ..sort((a, b) => a.value.toString().compareTo(b.value.toString()));
      for (var i = 0; i < entradasObelStream.length; i++) {
        final uid = entradasObelStream[i].key;
        final coord = entradasObelStream[i].value as String;
        streamColors[uid] = _colorJugadorPorIndice(i);
        streamObeliscos[uid] = coord;
      }

      // ── Actualizar eliminados ─────────────────────────────────
      final rawElim = data['jugadoresEliminados'] as List? ?? [];
      final nuevosEliminados = List<String>.from(rawElim);
      final yaEliminadoAntes = _estoyEliminado;
      final ahoraEliminado = nuevosEliminados.contains(widget.localPlayerUid);

      // ── Estado fin de partida ─────────────────────────────────
      final juegoTerminado = lobby.estado == LobbyEstado.finalizada;

      setState(() {
        _cerradoPor = List<String>.from(lobby.cerradoPor);
        _jugadoresEnPartida = lobby.jugadores.length;
        _modoTurno = lobby.modoTurno;
        if (streamColors.isNotEmpty) _playerColors = streamColors;
        if (streamObeliscos.isNotEmpty) _obeliscosPorJugador = streamObeliscos;
        _currentLobby = lobby;
        _sincronizarAliasLocalDesdeLobby(lobby);
        _hostUid = lobby.hostUid;
        _jugadoresEliminados = nuevosEliminados;
        _estoyEliminado = ahoraEliminado;
        _juegoTerminado = juegoTerminado;
        if (juegoTerminado) _ganadorUid = lobby.ganadorUid;
      });

      // Red de seguridad de rejilla EN TIEMPO REAL (bug 8 jugadores): si algún
      // obelisco llega o cambia por el stream —en partidas de 8 jugadores los
      // cuarteles se asignan de forma escalonada y caen en los bordes del
      // tablero (fila L / columna 18)— re-expandimos la rejilla para que los
      // contenga. En _loadGame ya se hacía (via _ajustarGridAContenido), pero
      // aquí faltaba: un cuartel que no estaba en _config al cargar quedaba
      // FUERA de la rejilla y luego no se podía mover desde él (el BFS no
      // encuentra la casilla de origen y no aparecen los recuadros verdes),
      // aunque sí se pudiera desplegar en él.
      if (streamObeliscos.isNotEmpty) {
        _ajustarGridAContenido(data, streamObeliscos);
      }

      // Mostrar diálogo de eliminación si acaba de ocurrir
      if (!yaEliminadoAntes && ahoraEliminado) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEliminadoDialog();
        });
      }
      // Mostrar fin de partida
      if (juegoTerminado && !_informeAbierto) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showFinPartidaDialog();
        });
      }

      // ── Informe de batalla (independiente del avance de tablero) ──
      // Se evalúa en CADA snapshot: si el turno resuelto (turnoActual-1) es
      // mayor que el último informe mostrado, lo abrimos. Así no depende de
      // qué ruta avanzó `_turnoConfirmadoStream`.
      _maybeMostrarInforme(lobby.turnoActual, data);

      // ── Nuevo turno: aplicar tablero y robar 1 carta ──────────
      if (lobby.turnoActual > _turnoConfirmadoStream &&
          data.containsKey('tablero')) {
        final tableroRaw = TurnService.parseTablero(data);
        // Efectos de CELDA persistidos por el servidor (veneno de celda, escudo,
        // parálisis…). Esta ruta la usan los jugadores que NO resolvieron el
        // turno (la actualización llega por el stream de Firestore). Antes se
        // descartaban aquí, de modo que el que resolvía veía los efectos
        // (_aplicarEstado) y el resto no. Ahora se preservan igual.
        final efectosCeldaStream = TurnService.parseEfectosCelda(data);
        var restoredState = const BoardState();
        tableroRaw.forEach((coord, cartas) {
          for (final c in cartas) {
            try {
              // `CartaEnCelda.fromMap` conserva el campo `Efectos` de la carta
              // (potenciaciones y veneno arrastrado). El constructor pelado los
              // perdía, por eso los buffs/venenos no se veían tras resolver.
              restoredState = restoredState.placeCarta(
                coord,
                CartaEnCelda.fromMap(c),
              );
            } catch (e) {
              debugPrint('[WZ][stream][ERROR] carta mal formada en $coord: '
                  '$e\n  carta=$c');
            }
          }
        });
        _turnoConfirmadoStream = lobby.turnoActual;

        setState(() {
          _boardState = restoredState
              .copyWith(
                turnoActual: lobby.turnoActual,
                efectosCelda: efectosCeldaStream,
              )
              .withRayos(_rayoCoordsFromData(data))
              .withCuarteles(_cuartelesDestruidosFromData(data));
          _cerradoPor = [];
          _resolviendo = false;
          _isSendingTurn = false;
          _cargaCompletada = true;
          _boardStateInicial = restoredState
              .copyWith(
                turnoActual: lobby.turnoActual,
                efectosCelda: efectosCeldaStream,
              )
              .withRayos(_rayoCoordsFromData(data))
              .withCuarteles(_cuartelesDestruidosFromData(data));
          _cartasMovidasEsteTurno.clear();
          _cartasRobadasEsteTurno.clear();
          _cartasQueEvolucionaron.clear();
          _cartasQueSeMovieron.clear();
          _origenTurnoPorId.clear();
          _cartasQueUsaronHabilidad.clear();
          // FALTABA en la ruta del stream (sí estaba en _aplicarEstado): las
          // acciones y fantasmas del turno que acaba de resolverse deben limpiarse
          // aquí también. Si no, el jugador que NO resolvió el turno se queda con
          // los marcadores locales de sus disparos/escudos pegados varios turnos.
          _accionesPendientes.clear();
          _accionController.cancelar();
          _fantasmasAccion.clear();
          _energiaGastadaDespliegue = 0;
          _especialesCompradasEsteTurno.clear();
          _revisionFantasmas = const [];
          _revisionAcciones = const {};
        });

        // BUG QAS #2: la mano y el mazo restante ya vienen del servidor con la
        // carta de fin de turno YA repartida (statsPartida.{uid}). El cliente ya
        // NO roba ni persiste aquí: solo sincroniza desde el estado autoritativo.
        _sincronizarManoDesdeEstado(data);

        // Actualizar puntos locales
        final rawSt = data['statsPartida'] as Map<String, dynamic>? ?? {};
        if (rawSt.containsKey(widget.localPlayerUid)) {
          final myS =
              Map<String, dynamic>.from(rawSt[widget.localPlayerUid] as Map);
          final pts = (myS['energies'] as num?)?.toInt() ?? 0;
          if (pts != _localPlayer.puntos) {
            setState(() {
              _localPlayer.puntos = pts;
              _puntosInicial = pts; // sincronizar snapshot de inicio de turno
            });
          }
        }
        if (_modoTurno == ModoTurno.rapida) _startTimer();

        if (_meRepartieronCarta(data)) {
          _toast('🃏 +1 carta para el nuevo turno');
        }

        // El informe lo gestiona _maybeMostrarInforme (llamado antes en este
        // mismo listener), de forma independiente al avance del tablero.
        return;
      }

      // La resolución la hace el servidor cuando cierra el último jugador; el
      // stream entregará el turno avanzado y este listener lo aplicará arriba.
      // (Antes aquí se llamaba a _resolverTurno en el cliente.)

      // Revisión post-cierre: si ya cerré y el turno todavía no se ha resuelto,
      // recalculo desde el servidor las flechas de mis movimientos y las celdas
      // de mis acciones. Al basarse en `movimientosTurno`, se mantiene aunque
      // salga y vuelva a entrar.
      if (mounted && _yoCerreElTurno) {
        setState(() => _actualizarOverlayRevision(data));
      }
    } catch (e, st) {
      debugPrint('[WZ][poll][ERROR] $e');
      debugPrint('[WZ][poll][ERROR] $st');
    }
  }

  /// Arranca el sondeo periódico del estado por HTTP (sustituye al stream de
  /// Firestore). Hace una primera lectura inmediata y luego cada pocos segundos.
  /// Como efecto colateral, mantiene "despierto" el backend de Render.
  void _iniciarPolling() {
    if (widget.lobbyId == null) return;
    _pollTimer?.cancel();
    _pollIntervaloActual = _intervaloPoll();
    _pollEstado(); // primera lectura inmediata
    _pollTimer = Timer.periodic(
      _pollIntervaloActual!,
      (_) => _pollEstado(),
    );
  }

  /// Una iteración del sondeo: pide el estado a la API y lo procesa. Reentrante-
  /// seguro mediante [_polling]. No muestra toasts en error para no spamear.
  Future<void> _pollEstado() async {
    if (_polling || !mounted || widget.lobbyId == null) return;
    _polling = true;
    try {
      final estado = await _api.obtenerEstado(widget.lobbyId!);
      if (!mounted || estado == null) return;
      final lobby = LobbyModel.fromMap(widget.lobbyId!, estado);
      _procesarEstado(estado, lobby);
      // Si la partida terminó, dejamos de sondear.
      if (lobby.estado == LobbyEstado.finalizada) {
        _pollTimer?.cancel();
        _pollTimer = null;
      } else if (_pollTimer != null &&
          _intervaloPoll() != _pollIntervaloActual) {
        // Al procesar el estado se ha actualizado `_modoTurno`; si eso cambia la
        // cadencia (p. ej. descubrimos que la partida es diaria y pasamos de 8 s
        // a 45 s), re-armamos el sondeo con el nuevo intervalo. La llamada
        // inmediata a `_pollEstado` dentro de `_iniciarPolling` es un no-op
        // porque `_polling` sigue en true durante esta iteración.
        _iniciarPolling();
      }
    } catch (e) {
      debugPrint('[WZ][poll] obtenerEstado falló (seguimos): $e');
    } finally {
      _polling = false;
    }
  }

  void _startTimer() {
    if (_timerActivo) return;
    _timerActivo = true;
    _segundosRestantes = _duracionTurnoRapidoSeg;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_timerActivo) return false;
      if (mounted) setState(() => _segundosRestantes--);
      if (_segundosRestantes <= 0) {
        _timerActivo = false;
        if (mounted) _cerrarTurno();
        return false;
      }
      return true;
    });
  }

  @override
  void dispose() {
    // Último intento de revertir la energía del turno en curso si el jugador
    // abandona la pantalla sin cerrar el turno (además del hook de ciclo de
    // vida, por si el pop ocurre sin pasar por `paused`). En dispose NO se puede
    // llamar a setState, así que se pide la variante sin reconstruir la UI.
    _revertirCambiosPorSalidaSiProcede(permitirSetState: false);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _timerActivo = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // La app pasa a segundo plano o se cierra: revertir energía revertible.
      _revertirCambiosPorSalidaSiProcede();
      // Detener el sondeo mientras la app no está visible: no tiene sentido
      // gastar lecturas de Firestore si el jugador no está mirando. Al volver
      // (resumed) se reanuda con una lectura inmediata para ponerse al día.
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      // Al volver, permitir una nueva reversión si el jugador vuelve a gastar.
      _revirtiendoPorSalida = false;
      // Reanudar el sondeo (se detuvo al pasar a segundo plano) si la partida
      // sigue viva. `_iniciarPolling` hace una primera lectura inmediata.
      if (!_juegoTerminado && widget.lobbyId != null && _pollTimer == null) {
        _iniciarPolling();
      }
      // Si al pausar quedó una reversión pendiente de reembolsar (el reembolso
      // fire-and-forget no llegó porque el SO suspendió el proceso), reintentarlo
      // ahora que hay red.
      if (_reembolsoPendienteTrasPausa) {
        _reembolsoPendienteTrasPausa = false;
        _reembolsarPendienteAlReanudar();
      }
    }
  }

  /// Guarda contra reversiones duplicadas (paused + detached + dispose).
  bool _revirtiendoPorSalida = false;

  /// Incidencia #1: al cerrar la app (o abandonar la pantalla) después de mover
  /// cartas SIN cerrar el turno, los movimientos NO se persisten y al reentrar
  /// el tablero vuelve a su estado inicial; pero la energía SÍ se persiste de
  /// forma incremental (despliegues, compras, evoluciones), así que sin esto se
  /// perdería ("las cartas vuelven a su ser pero la energía se pierde").
  ///
  /// Para dejar cliente y servidor coherentes hacemos lo mismo que "deshacer":
  /// devolvemos en el servidor la energía revertible del turno y desmarcamos las
  /// especiales compradas este turno, y reseteamos el estado local al inicio del
  /// turno (así, si la app vuelve al mismo instante, no queda energía ya devuelta
  /// pendiente de un futuro cierre de turno, evitando un exploit).
  void _revertirCambiosPorSalidaSiProcede({bool permitirSetState = true}) {
    if (_revirtiendoPorSalida) return;
    if (widget.lobbyId == null) return;
    if (_yoCerreElTurno || _estoyEliminado || _juegoTerminado) return;

    final energiaADevolver = _energiaGastadaDespliegue;
    final especialesADesmarcar = _especialesCompradasEsteTurno.toList();
    if (energiaADevolver <= 0 && especialesADesmarcar.isEmpty) return;

    _revirtiendoPorSalida = true;

    // NO se lanza aquí `deshacerTurno`: al bloquear el móvil el SO suspende el
    // proceso antes de que la petición HTTP termine y el reembolso se perdía (el
    // jugador reentraba sin la energía). La deuda ya está persistida en disco
    // (se escribió en el momento del gasto), así que el reembolso se REINTENTA
    // de forma fiable al reanudar la app (didChangeAppLifecycleState.resumed) o
    // al reentrar a la partida (_loadGame), cuando hay red disponible.
    _reembolsoPendienteTrasPausa = true;

    // Resetear estado local al snapshot de inicio de turno (coherente con el
    // tablero que se recargará del servidor al reentrar).
    void reset() {
      _boardState = _boardStateInicial;
      _hand = List.from(_handInicial);
      _cartasMovidasEsteTurno.clear();
      _cartasRobadasEsteTurno.clear();
      _cartasQueEvolucionaron.clear();
      _cartasQueSeMovieron.clear();
      _origenTurnoPorId.clear();
      _cartasQueUsaronHabilidad.clear();
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
      _selectedHandIndex = null;
      _sidebarOpen = false;
      _sidebarCoord = null;
      _accionController.cancelar();
      _accionesPendientes.clear();
      _fantasmasAccion.clear();
      _localPlayer.puntos = _puntosInicial;
      _energiaGastadaDespliegue = 0;
      _especialesCompradas.removeAll(especialesADesmarcar);
      _especialesCompradasEsteTurno.clear();
      _revisionFantasmas = const [];
      _revisionAcciones = const {};
    }

    if (permitirSetState && mounted) {
      setState(reset);
    } else {
      reset();
    }
  }

  // ─────────────────────────────────────────────────────────
  // COORD HELPERS
  // ─────────────────────────────────────────────────────────
  (int, int)? _coordToPos(String coord) {
    if (coord.length < 2) return null;
    final ri = _config.rowLabels.indexOf(coord[0]);
    final colNum = int.tryParse(coord.substring(1));
    if (colNum == null) return null;
    final ci = _config.colLabels.indexOf(colNum);
    if (ri == -1 || ci == -1) return null;
    return (ri, ci);
  }

  int _distance(String a, String b) {
    final pa = _coordToPos(a);
    final pb = _coordToPos(b);
    if (pa == null || pb == null) return 999;
    return (pa.$1 - pb.$1).abs() + (pa.$2 - pb.$2).abs();
  }

  Set<String> _computeMovableBFS(String from, int mov, int tipo) {
    if (mov <= 0) return {};
    final visited = <String, int>{from: 0};
    final queue = [_MoveNode(from, 0)];
    int head = 0;
    final result = <String>{};

    while (head < queue.length) {
      final node = queue[head++];
      if (node.steps >= mov) continue;
      final pos = _coordToPos(node.coord);
      if (pos == null) continue;
      final (ri, ci) = pos;

      const deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)];
      for (final (dr, dc) in deltas) {
        final nr = ri + dr;
        final nc = ci + dc;
        if (nr < 0 || nr >= _config.rows || nc < 0 || nc >= _config.cols) {
          continue;
        }
        final nCoord = _config.coordLabel(nr, nc);
        final newSteps = node.steps + 1;
        if ((visited[nCoord] ?? 999) <= newSteps) continue;
        if (!_config.canTraverse(nCoord, tipo)) continue;
        visited[nCoord] = newSteps;
        if (nCoord != from &&
            _config.canLand(nCoord, tipo) &&
            !_boardState.celdaProtegidaPorRival(
                nCoord, _localPlayer.datos.uid)) {
          result.add(nCoord);
        }
        if (newSteps < mov) {
          queue.add(_MoveNode(nCoord, newSteps));
        }
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────
  // LÓGICA DE INTERACCIÓN
  // ─────────────────────────────────────────────────────────

  /// Celdas donde se puede desplegar la carta seleccionada de la mano, para
  /// resaltarlas en verde. Debe coincidir EXACTAMENTE con la validación de
  /// [_tryPlaceFromHand]:
  ///   • Cartas normales → solo el cuartel.
  ///   • Cartas estáticas → cualquier celda (que no sea el cuartel) donde el
  ///     jugador ya tenía una carta al inicio del turno, que no se haya movido
  ///     este turno, con terreno compatible y sin escudo rival.
  Set<String> get _deployCoords {
    final idx = _selectedHandIndex;
    if (idx == null || idx >= _hand.length) return const {};
    final carta = _hand[idx];
    final miUid = _localPlayer.datos.uid;

    if (!carta.esEstatica) {
      final o = _obeliscoLocal;
      if (o == null) return const {};
      if (_boardState.celdaProtegidaPorRival(o, miUid)) return const {};
      return {o};
    }

    final res = <String>{};
    for (final entry in _boardStateInicial.celdas.entries) {
      final coord = entry.key;
      if (coord == _obeliscoLocal) continue;
      final propias =
          entry.value.cartas.where((c) => c.ownerUid == miUid).toList();
      if (propias.isEmpty) continue;
      if (propias.any((c) => _cartasMovidasEsteTurno.contains(c.instanceId))) {
        continue;
      }
      if (!_config.canLand(coord, carta.tipo)) continue;
      if (_boardState.celdaProtegidaPorRival(coord, miUid)) continue;
      res.add(coord);
    }
    return res;
  }

  void _onCellTap(String coord, int ri, int ci) {
    // ── Modo acción: selección de objetivos ────────────────
    if (_inActionMode) {
      _handleCellTapEnAccion(coord);
      return;
    }
    if (_selectedHandIndex != null) {
      _tryPlaceFromHand(coord, ri, ci);
      return;
    }
    if (_inMoveMode) {
      if (coord == _moveFromCoord) {
        _cancelMoveMode();
      } else if (_movableCoords.contains(coord)) {
        _executeMove(coord, ri, ci);
      } else {
        _cancelMoveMode();
      }
      return;
    }
    setState(() {
      _sidebarCoord = coord;
      _sidebarRi = ri;
      _sidebarCi = ci;
      _sidebarOpen = true;
    });
  }

  void _tryPlaceFromHand(String coord, int ri, int ci) {
    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }
    final carta = _hand[_selectedHandIndex!];

    // ── Validación de la celda de colocación ──────────────────
    if (carta.esEstatica) {
      // Estáticas: NUNCA en el cuartel; solo donde ya tenías una carta el turno
      // anterior (que no se haya movido este turno) y con terreno compatible.
      if (coord == _obeliscoLocal) {
        _toast('🏰 Las estáticas no pueden desplegarse en el cuartel general',
            error: true);
        return;
      }
      final celdaInicial = _boardStateInicial.getCelda(coord);
      final propiasAnteriores = celdaInicial.cartas
          .where((c) => c.ownerUid == _localPlayer.datos.uid)
          .toList();
      if (propiasAnteriores.isEmpty) {
        _toast(
            '🏰 Estática: solo puedes colocarla donde ya tenías una carta el turno anterior',
            error: true);
        return;
      }
      final algunaMovida = propiasAnteriores
          .any((c) => _cartasMovidasEsteTurno.contains(c.instanceId));
      if (algunaMovida) {
        _toast(
            '🏰 Esa carta ya se ha movido este turno: no puedes desplegar en esa celda',
            error: true);
        return;
      }
      // Terreno: la estática debe poder estar en el terreno de la celda
      // (tipo 1 terrestre, 2 volador → tierra/anfibio; tipo 3 marino → agua/anfibio).
      if (!_config.canLand(coord, carta.tipo)) {
        _toast(
            '🌊 Terreno incompatible: esta carta no puede desplegarse en esta celda',
            error: true);
        return;
      }
    } else {
      // Cartas normales: solo en el cuartel.
      if (coord != _obeliscoLocal) {
        _toast('⚔  Solo puedes desplegar en tu cuartel: $_obeliscoLocal',
            error: true);
        return;
      }
    }

    // ── Celda protegida por un escudo rival ───────────────────
    if (_boardState.celdaProtegidaPorRival(coord, _localPlayer.datos.uid)) {
      _toast('🛡 Celda escudada por un rival: no puedes desplegar aquí',
          error: true);
      return;
    }

    // ── Comprobar coste de energía ────────────────────────────
    final coste = carta.coste;
    if (_localPlayer.puntos < coste) {
      _toast(
        'Ø Zero insuficiente: necesitas $coste, tienes ${_localPlayer.puntos}',
        error: true,
      );
      return;
    }

    setState(() {
      final nueva = CartaEnCelda(
        carta: carta,
        ownerUid: _localPlayer.datos.uid,
        ownerZone: _localPlayer.zona,
      );
      _boardState = _boardState.placeCarta(coord, nueva);
      _hand = List.from(_hand)..removeAt(_selectedHandIndex!);
      _selectedHandIndex = null;
      if (carta.esEstatica) {
        // Estática: esta instancia no se mueve. Por instanceId, para no
        // bloquear otras copias de la misma carta.
        _cartasMovidasEsteTurno.add(nueva.instanceId);
      }
      // ── Descontar energía localmente ──────────────────────
      _localPlayer.puntos -= coste;
      _energiaGastadaDespliegue += coste;
      _sidebarCoord = coord;
      _sidebarRi = ri;
      _sidebarCi = ci;
      _sidebarOpen = true;
    });

    // ── Persistir gasto vía API (sin Firestore) ───────────────
    if (widget.lobbyId != null && coste > 0) {
      _api
          .actualizarStats(
            lobbyId: widget.lobbyId!,
            uid: widget.localPlayerUid,
            energiesDelta: -coste,
          )
          .catchError((_) => null); // fire-and-forget; undo restaura si cancela
    }

    if (coste > 0) {
      _toast('${carta.nombre} desplegada  (-$coste Ø)');
    }
    _persistirDeudaPendiente();
  }

  // ── CUARTEL: compra de cartas especiales ──────────────────
  /// Abre la pantalla del cuartel para comprar cartas especiales.
  void _abrirCuartel() {
    final puedeComprar = !_yoCerreElTurno && !_estoyEliminado;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CuartelScreen(
        ejercitoId: _miEjercitoId,
        energiasIniciales: _localPlayer.puntos,
        puedeComprar: puedeComprar,
        compradasIniciales: _especialesCompradas,
        onComprar: _comprarEspecial,
        robosCompradosIniciales: _robosComprados,
        onRobarCarta: _robarCartaCuartel,
      ),
    ));
  }

  /// Abre el informe de batalla del turno anterior. Antes vivía como
  /// closure inline del extinto menú flotante; ahora lo llama el menú
  /// único de PartidaTopBar.
  void _abrirInformeBatalla() {
    _informeAbierto = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => InformeBatallaScreen(
        combateLog: _lastCombateLog,
        movimientosLog: _lastMovimientosLog,
        historial: _historialCombates,
        localUid: widget.localPlayerUid,
        jugadores: _currentLobby?.jugadores ?? [],
        turno: _boardState.turnoActual - 1,
        farmeoLog: _lastFarmeoLog,
        accionesLog: _lastAccionesLog,
        rayoCoords: _lastRayoCoords.toList(),
        // BUG QAS #2: al reabrir el informe del último turno también hay que
        // mostrar la carta repartida (antes solo la pasaba el informe en vivo).
        ultimaCartaRepartida: _ultimaCartaRepartida,
      ),
    ))
        .whenComplete(() {
      _informeAbierto = false;
      _abrirRevisionTurno(turnoRevisar: _boardState.turnoActual - 1);
    });
  }

  void _revisarAlianzas(Map<String, dynamic> data) {
    final raw = data['alianzas'];
    _alianzas = raw is Map ? Map<String, dynamic>.from(raw) : {};
    if (!mounted) return;
    final est = EstadoAlianzas.fromMap(_alianzas);
    final miUid = widget.localPlayerUid;

    // Aliados del jugador local (para el render del tablero).
    final aliadoActivo = est.aliadoDe(miUid);
    final nuevosAliados = <String>{
      miUid,
      if (aliadoActivo != null && aliadoActivo.isNotEmpty) aliadoActivo,
    };
    final aliadosCambiaron = nuevosAliados.length != _aliadosLocal.length ||
        !nuevosAliados.containsAll(_aliadosLocal);
    if (aliadosCambiaron) {
      setState(() => _aliadosLocal = nuevosAliados);
    }

    // BANDEJA: nº de propuestas entrantes pendientes → badge del menú. Persiste
    // hasta que respondas (aceptar/rechazar), aunque cierres el aviso.
    final recibidas = est.propuestasEntrantesParaLista(miUid);
    if (recibidas.length != _propuestasPendientes) {
      setState(() => _propuestasPendientes = recibidas.length);
    }

    // Aviso AL ENTRAR / al llegar una nueva propuesta: diálogo de la primera no
    // vista aún. Cerrar el aviso NO responde: la propuesta sigue en la bandeja.
    final prop = recibidas.isNotEmpty ? recibidas.first : null;
    if (prop != null && !_alianzaVistos.contains(prop.clave)) {
      _alianzaVistos.add(prop.clave);
      _mostrarPropuestaAlianza(prop);
    }

    // Avisos para mí no vistos → toast + limpiar en el servidor.
    final mis = est
        .avisosPara(miUid)
        .where((a) => !_alianzaVistos.contains(a.clave))
        .toList();
    if (mis.isNotEmpty) {
      for (final a in mis) {
        _alianzaVistos.add(a.clave);
        _toast(_mensajeAviso(a));
      }
      if (widget.lobbyId != null) {
        _api.limpiarAvisosAlianza(lobbyId: widget.lobbyId!, uid: miUid);
      }
    }
  }

  String _aliasDeUidAlianza(String uid) {
    for (final j in (_currentLobby?.jugadores ?? const [])) {
      if (j.uid == uid) return j.alias;
    }
    return 'Un jugador';
  }

  String _mensajeAviso(AvisoAlianza a) {
    switch (a.tipo) {
      case 'traicionado':
        return '${_aliasDeUidAlianza(a.deUid)} te ha traicionado. Ya sois enemigos.';
      case 'alianza_terminada':
        return 'Tu alianza con ${_aliasDeUidAlianza(a.deUid)} ha terminado.';
      case 'aceptada':
        return '${_aliasDeUidAlianza(a.deUid)} ha aceptado tu alianza.';
      case 'rechazada':
        return '${_aliasDeUidAlianza(a.deUid)} ha rechazado tu alianza.';
      default:
        return 'Novedad en tus alianzas.';
    }
  }

  void _mostrarPropuestaAlianza(PropuestaAlianza p) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        var armado = false; // los botones se activan tras 700 ms
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            if (!armado) {
              Future.delayed(const Duration(milliseconds: 700), () {
                if (ctx.mounted) setLocal(() => armado = true);
              });
            }
            Color c(Color base) => armado ? base : base.withOpacity(0.35);
            return AlertDialog(
              backgroundColor: const Color(0xFF0C1828),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0x66C8A860)),
              ),
              title: const Text('Propuesta de alianza',
                  style: TextStyle(
                      color: Color(0xFFE0D8C0),
                      fontFamily: 'Cinzel',
                      fontSize: 16)),
              content: Text(
                '${_aliasDeUidAlianza(p.deUid)} te propone una alianza durante '
                '${p.turnos} turnos. Puedes responder ahora o más tarde desde '
                'el menú → ALIANZA.',
                style: const TextStyle(color: Color(0xFFB0C0D0), fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(), // queda en bandeja
                  child: const Text('MÁS TARDE',
                      style: TextStyle(color: Color(0xFF9AB0C0))),
                ),
                TextButton(
                  onPressed: armado
                      ? () {
                          Navigator.of(ctx).pop();
                          _responderPropuesta(p, false);
                        }
                      : null,
                  child: Text('RECHAZAR',
                      style: TextStyle(color: c(const Color(0xFFE06060)))),
                ),
                TextButton(
                  onPressed: armado
                      ? () {
                          Navigator.of(ctx).pop();
                          _confirmarAceptarAlianza(p);
                        }
                      : null,
                  child: Text('ACEPTAR',
                      style: TextStyle(
                          color: c(const Color(0xFF9AD06A)),
                          fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Confirmación explícita antes de sellar la alianza (evita aceptados
  /// accidentales por un toque perdido).
  Future<void> _confirmarAceptarAlianza(PropuestaAlianza p) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1828),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0x669AD06A)),
        ),
        title: const Text('Confirmar alianza',
            style: TextStyle(
                color: Color(0xFFE0D8C0), fontFamily: 'Cinzel', fontSize: 16)),
        content: Text(
          '¿Aliarte con ${_aliasDeUidAlianza(p.deUid)} durante ${p.turnos} '
          'turnos?',
          style: const TextStyle(color: Color(0xFFB0C0D0), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF9AB0C0))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ALIARME',
                style: TextStyle(
                    color: Color(0xFF9AD06A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) _responderPropuesta(p, true);
  }

  Future<void> _responderPropuesta(PropuestaAlianza p, bool aceptar) async {
    if (widget.lobbyId == null) return;
    try {
      final r = await _api.responderAlianza(
        lobbyId: widget.lobbyId!,
        uid: widget.localPlayerUid,
        proponenteUid: p.deUid,
        aceptar: aceptar,
      );
      if (r.estado != null && r.estado!['alianzas'] is Map) {
        _alianzas = Map<String, dynamic>.from(r.estado!['alianzas'] as Map);
        // Actualiza el badge al momento (sin esperar al siguiente sondeo).
        final pend = EstadoAlianzas.fromMap(_alianzas)
            .propuestasPendientesPara(widget.localPlayerUid);
        if (mounted) setState(() => _propuestasPendientes = pend);
      }
      _toast(r.mensaje.isEmpty
          ? (aceptar ? 'Alianza aceptada.' : 'Propuesta rechazada.')
          : r.mensaje);
    } catch (e) {
      _toast('No se pudo responder la alianza', error: true);
    }
  }

  void _abrirAlianza() {
    if (widget.lobbyId == null) return;
    final jugadores = <Map<String, dynamic>>[];
    for (final j in (_currentLobby?.jugadores ?? const [])) {
      if (j.uid == widget.localPlayerUid) continue;
      if (_jugadoresEliminados.contains(j.uid)) continue;
      jugadores.add({
        'uid': j.uid,
        'alias': j.alias,
        'color': _colorDeUid(j.uid),
      });
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlianzaScreen(
        api: _api,
        lobbyId: widget.lobbyId!,
        miUid: widget.localPlayerUid,
        jugadores: jugadores,
        alianzasIniciales: _alianzas,
      ),
    ));
  }

  void _abrirPuntuaciones() {
    final lobby = _currentLobby;
    final localUid = _localPlayer.datos.uid;
    final filas = (lobby?.jugadores ?? const []).map((j) {
      final s = lobby!.statsDeJugador(j.uid);
      return PuntuacionJugador(
        alias: j.alias,
        color: _colorDeUid(j.uid),
        victorias: s.victorias,
        derrotas: s.derrotas,
        pc: s.pc,
        eliminado: lobby.jugadoresEliminados.contains(j.uid),
        esLocal: j.uid == localUid,
      );
    }).toList();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PuntuacionesScreen(
        nombrePartida: lobby?.nombre ?? 'Partida',
        jugadores: filas,
      ),
    ));
  }

  /// Pide confirmación antes de deshacer los cambios del turno. Antes vivía
  /// dentro del extinto _GameActionsMenu; ahora lo llama el menú único de
  /// PartidaTopBar.
  void _pedirDeshacer() {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1E30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('¿Deshacer cambios?',
            style: TextStyle(
                fontFamily: 'Cinzel', color: Color(0xFFC8A860), fontSize: 14)),
        content: const Text(
          'Se revertirán todos los movimientos de este turno.\n'
          'El tablero volverá al estado guardado en el servidor.',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: Color(0xFF8A9AAA),
              fontSize: 10,
              height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: Color(0xFF506070),
                    fontSize: 10)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DESHACER',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: Color(0xFFFF5050),
                    fontSize: 10)),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) _undoCambios();
    });
  }

  /// Compra una carta especial: descuenta Zero, la coloca en el cuartel y
  /// la marca como comprada (deshabilitada para futuras compras).
  Future<CompraResult> _comprarEspecial(CartaModel carta) async {
    CompraResult fallo(String m) => CompraResult(
        ok: false, mensaje: m, energiasRestantes: _localPlayer.puntos);

    if (_yoCerreElTurno) {
      return fallo('Ya cerraste el turno. No puedes comprar.');
    }
    if (_estoyEliminado) return fallo('Estás eliminado.');
    if (_especialesCompradas.contains(carta.id)) {
      return fallo('Ya compraste esta carta esta partida.');
    }
    final cuartel = _obeliscoLocal;
    if (cuartel == null || cuartel.isEmpty) {
      return fallo('No tienes cuartel asignado.');
    }
    final coste = carta.coste;
    if (_localPlayer.puntos < coste) {
      return fallo('Energía insuficiente: necesitas $coste.');
    }

    // Aplicar localmente: colocar en el cuartel, descontar energía y marcar.
    final nueva = CartaEnCelda(
      carta: carta,
      ownerUid: _localPlayer.datos.uid,
      ownerZone: _localPlayer.zona,
    );
    setState(() {
      _boardState = _boardState.placeCarta(cuartel, nueva);
      _localPlayer.puntos -= coste;
      _especialesCompradas.add(carta.id);
      // Energía y especial revertibles de este turno (para deshacer / salir).
      _energiaGastadaDespliegue += coste;
      _especialesCompradasEsteTurno.add(carta.id);
      // Recién comprada: esta instancia no puede moverse este turno.
      _cartasMovidasEsteTurno.add(nueva.instanceId);
    });

    // Persistir energía y compra vía API (la posición en el tablero viaja al
    // cerrar turno). Sin Firestore.
    if (widget.lobbyId != null) {
      try {
        await _api.actualizarStats(
          lobbyId: widget.lobbyId!,
          uid: widget.localPlayerUid,
          energiesDelta: -coste,
          especialComprada: carta.id,
        );
      } catch (e) {
        // Revertir si falla la persistencia.
        if (mounted) {
          setState(() {
            _localPlayer.puntos += coste;
            _especialesCompradas.remove(carta.id);
            _energiaGastadaDespliegue -= coste;
            _especialesCompradasEsteTurno.remove(carta.id);
            _cartasMovidasEsteTurno.remove(nueva.instanceId);
            final celda = _boardState.getCelda(cuartel);
            final idx = celda.cartas
                .lastIndexWhere((c) => c.instanceId == nueva.instanceId);
            if (idx != -1) {
              final nuevas = [...celda.cartas]..removeAt(idx);
              _boardState =
                  _boardState.setCelda(cuartel, celda.withCartas(nuevas));
            }
          });
        }
        return fallo('Error al comprar. Inténtalo de nuevo.');
      }
    }

    _persistirDeudaPendiente();
    return CompraResult(
      ok: true,
      mensaje: '${carta.nombre} comprada y desplegada en tu cuartel.',
      energiasRestantes: _localPlayer.puntos,
    );
  }

  /// Roba una carta al azar del mazo del jugador y la añade a la mano, a cambio
  /// de un precio creciente (100 · 2^robosComprados).
  ///
  /// REVERTIBLE dentro del turno:
  ///   • Si CIERRAS el turno, carta y gasto se consolidan (_cerrarTurno sube
  ///     _hand con la carta incluida).
  ///   • Si SALES o pulsas «Deshacer» SIN cerrar, la carta desaparece y la
  ///     energía se devuelve — coherente con "tu progreso de este turno se
  ///     perderá si no cerraste el turno".
  ///
  /// Detalles:
  ///   • La carta va a _hand pero NO a _handInicial → al revertir se restaura
  ///     _hand = _handInicial sin ella.
  ///   • El coste entra en el pool REVERTIBLE (_energiaGastadaDespliegue), NO
  ///     se consolida en _puntosInicial.
  ///   • NO se persiste la mano aquí (solo el gasto y el contador de robos); la
  ///     mano definitiva se sube al cerrar turno.
  ///   • _robosComprados (precio) sube PERMANENTE aunque salgas: evita farmear
  ///     robos baratos saliendo cada vez.
  Future<CompraResult> _robarCartaCuartel() async {
    CompraResult fallo(String m) => CompraResult(
        ok: false, mensaje: m, energiasRestantes: _localPlayer.puntos);

    if (_yoCerreElTurno) return fallo('Ya cerraste el turno. No puedes robar.');
    if (_estoyEliminado) return fallo('Estás eliminado.');

    final precio = _precioRoboActual;
    if (_localPlayer.puntos < precio) {
      return fallo('Energía insuficiente: necesitas $precio.');
    }

    // Elegir una carta al azar del mazo del jugador (sin evoluciones/especiales).
    final pool =
        _mazoCompleto.where((c) => !c.esEvolucion && !c.esEspecial).toList();
    if (pool.isEmpty) return fallo('No hay cartas disponibles para robar.');
    // Clonar la robada a una INSTANCIA propia. Las copias del mismo tipo comparten
    // el mismo objeto en el mazo, así que sin clonar identical() marcaría como
    // "robada este turno" a TODAS las copias (tus 4 parálisis divina) y no dejaría
    // sacrificar ninguna. Con el clon, solo la robada queda bloqueada.
    final carta = pool[math.Random().nextInt(pool.length)].copyWith();

    setState(() {
      // Carta REVERTIBLE: solo en _hand (no en _handInicial).
      _hand = [..._hand, carta];
      _cartasRobadasEsteTurno.add(carta);
      // Gasto REVERTIBLE: lo reembolsan "deshacer"/"salir".
      _localPlayer.puntos -= precio;
      _energiaGastadaDespliegue += precio;
      // El precio del próximo robo sube de forma permanente.
      _robosComprados += 1;
    });

    if (widget.lobbyId != null) {
      try {
        // Solo se persiste el gasto y el contador de robos. La mano NO se sube
        // aquí: si el jugador sale sin cerrar, la carta no debe sobrevivir. Al
        // cerrar turno, _cerrarTurno sube _hand completa (con la carta robada).
        await _api.actualizarStats(
          lobbyId: widget.lobbyId!,
          uid: widget.localPlayerUid,
          energiesDelta: -precio,
          robosDelta: 1,
        );
      } catch (_) {
        // Revertir si falla la persistencia.
        if (mounted) {
          setState(() {
            final idx = _hand.lastIndexWhere((c) => identical(c, carta));
            if (idx != -1) _hand = [..._hand]..removeAt(idx);
            _cartasRobadasEsteTurno.removeWhere((c) => identical(c, carta));
            _localPlayer.puntos += precio;
            _energiaGastadaDespliegue -= precio;
            _robosComprados -= 1;
          });
        }
        return fallo('Error al robar. Inténtalo de nuevo.');
      }
    }

    // Persistir la deuda revertible (energía) por si se bloquea el móvil / se
    // mata la app sin cerrar el turno.
    _persistirDeudaPendiente();

    return CompraResult(
      ok: true,
      mensaje: 'Has robado ${carta.nombre}.',
      energiasRestantes: _localPlayer.puntos,
    );
  }

  void _onMoveSelected(List<int> indices) {
    if (_sidebarCoord == null || indices.isEmpty) return;
    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }
    final celda = _boardState.getCelda(_sidebarCoord!);
    // Exclusión POR CARTA: se descartan solo las cartas que evolucionaron este
    // turno; el resto puede moverse aunque otra haya evolucionado (bug QAS #3).
    final validIndices = indices
        .where((i) =>
            i < celda.cartas.length &&
            celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
            !_cartasMovidasEsteTurno.contains(celda.cartas[i].instanceId) &&
            !_cartasQueEvolucionaron.contains(celda.cartas[i].instanceId) &&
            !_cartasQueUsaronHabilidad.contains(celda.cartas[i].instanceId) &&
            !celda.cartas[i].carta.esEstatica &&
            !celda.cartas[i].paralizado)
        .toList();

    if (validIndices.isEmpty) {
      final algunaUsoHabilidad = indices.any((i) =>
          i < celda.cartas.length &&
          celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
          _cartasQueUsaronHabilidad.contains(celda.cartas[i].instanceId));
      if (algunaUsoHabilidad) {
        _toast('Esa carta usó habilidad este turno: no puede moverse.',
            error: true);
        return;
      }
    }

    if (validIndices.isEmpty) {
      final algunaEvoluciono = indices.any((i) =>
          i < celda.cartas.length &&
          celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
          _cartasQueEvolucionaron.contains(celda.cartas[i].instanceId));
      if (algunaEvoluciono) {
        _toast('Esa carta evolucionó este turno: no puede moverse.',
            error: true);
        return;
      }
    }

    if (validIndices.isEmpty) {
      final algunaParalizada = indices.any((i) =>
          i < celda.cartas.length &&
          celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
          celda.cartas[i].paralizado);
      if (algunaParalizada) {
        _toast('⏱ Cartas paralizadas: no pueden moverse este turno',
            error: true);
        return;
      }
    }

    if (validIndices.isEmpty) {
      final todasEstaticas = indices.every(
          (i) => i < celda.cartas.length && celda.cartas[i].carta.esEstatica);
      if (todasEstaticas) {
        _toast('🏰 Las cartas estáticas no pueden moverse', error: true);
        return;
      }
    }
    if (validIndices.isEmpty) {
      final alreadyMoved = indices.any((i) =>
          i < celda.cartas.length &&
          _cartasMovidasEsteTurno.contains(celda.cartas[i].instanceId));
      if (alreadyMoved) {
        _toast('Estas cartas ya se movieron este turno', error: true);
      } else {
        _toast('No puedes mover cartas de otros jugadores', error: true);
      }
      return;
    }

    // ── Aviso: cartas con TELETRANSPORTE pendiente ───────────
    // Si alguna carta seleccionada ya tiene un teletransporte declarado este
    // turno, moverla manualmente entra en conflicto con esa acción (el servidor
    // la teletransporta al resolver). Avisamos y solo movemos las que NO tengan
    // acción pendiente.
    final conTeleport = validIndices
        .where((i) =>
            _teleportPendienteDeCarta(_sidebarCoord!, celda.cartas[i]) != null)
        .toList();
    if (conTeleport.isNotEmpty) {
      final restantes =
          validIndices.where((i) => !conTeleport.contains(i)).toList();
      _avisarTeleportPendiente(celda, conTeleport, restantes);
      return;
    }

    _entrarModoMovimiento(celda, validIndices);
  }

  /// Entra en modo movimiento con las cartas [validIndices] de [celda]: calcula
  /// el alcance (BFS) y resalta las celdas destino válidas. Extraído de
  /// [_onMoveSelected] para poder reutilizarlo tras confirmar un aviso.
  /// Entra en modo movimiento con las cartas [validIndices] de [celda]: calcula
  /// el alcance (BFS) y resalta las celdas destino válidas. Extraído de
  /// [_onMoveSelected] para poder reutilizarlo tras confirmar un aviso.
  void _entrarModoMovimiento(CeldaState celda, List<int> validIndices) {
    if (validIndices.isEmpty || _sidebarCoord == null) return;

    // Red de seguridad (bug 8 jugadores): garantiza que la rejilla contiene la
    // celda de ORIGEN antes de calcular el alcance. En partidas grandes el
    // cuartel puede quedar fuera de _config (grid encogido por el terreno del
    // mapa, o no re-expandido cuando el obelisco llegó por el stream). Si el
    // origen no está en la rejilla, _coordToPos(from) devuelve null, el BFS sale
    // vacío y NO se pintan las casillas verdes de destino. Al expandir aquí, el
    // movimiento desde el cuartel vuelve a funcionar siempre.
    _expandirGridSiHaceFalta([_sidebarCoord!]);

    final minMov = validIndices
        .map((i) => celda.cartas[i].movimientoEfectivo)
        .reduce((a, b) => a < b ? a : b);

    // Tipos distintos presentes en la selección (1=tierra, 2=aire, 3=mar).
    final tipos = validIndices.map((i) => celda.cartas[i].carta.tipo).toSet();

    // Regla de diseño: terrestres y marinas nunca se mueven juntas.
    if (tipos.contains(1) && tipos.contains(3)) {
      _toast('No puedes mover unidades terrestres y marinas juntas',
          error: true);
      return;
    }

    // Destinos válidos = INTERSECCIÓN del alcance de cada tipo seleccionado.
    // Como todas las cartas del grupo acaban en la MISMA celda, el destino solo
    // es válido si TODAS pueden atravesar el camino y aterrizar allí. Así, al
    // mezclar mar (tipo 3) + aire (tipo 2) solo se permiten casillas anfibias:
    // una unidad de aire no puede quedarse en agua aunque viaje junto a una
    // marina (antes se colaba porque el grupo tomaba el tipo de la marina).
    Set<String>? destinos;
    for (final t in tipos) {
      final alcance = _computeMovableBFS(_sidebarCoord!, minMov, t);
      destinos = destinos == null ? alcance : destinos.intersection(alcance);
    }
    destinos ??= <String>{};

    if (destinos.isEmpty && tipos.length > 1) {
      _toast(
          '🌊 Esas cartas no comparten ninguna casilla de destino compatible',
          error: true);
      return;
    }

    setState(() {
      _moveFromCoord = _sidebarCoord;
      _moveCardIndices = validIndices;
      _movableCoords = destinos!;
      _sidebarOpen = false;
    });
  }

  /// Acción de teletransporte pendiente cuyo origen es [carta] situada en
  /// [coord], o null si no hay ninguna. Solo el teletransporte fija
  /// `cartaOrigen*`; se identifica por la celda de origen y el id de catálogo de
  /// la carta (robusto ante cambios de índice dentro de la celda).
  AccionPendiente? _teleportPendienteDeCarta(String coord, CartaEnCelda carta) {
    for (final a in _accionesPendientes) {
      final oc = a.cartaOrigenCoord;
      if (oc == null || oc != coord) continue;
      if (a.cartaOrigenId != null && a.cartaOrigenId != carta.carta.id) {
        continue;
      }
      return a;
    }
    return null;
  }

  /// Informa de que las cartas [conTeleport] (índices en [celda]) tienen un
  /// teletransporte pendiente. Si el jugador lo acepta y hay cartas libres,
  /// mueve solo las [restantes]. Si no quedan libres, es solo informativo.
  Future<void> _avisarTeleportPendiente(
    CeldaState celda,
    List<int> conTeleport,
    List<int> restantes,
  ) async {
    final nombres =
        conTeleport.map((i) => celda.cartas[i].carta.nombre).toSet().join(', ');
    final hayRestantes = restantes.isNotEmpty;

    final proceder = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1220),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x40C8A860), width: 1),
        ),
        title: const Row(children: [
          Icon(Icons.swap_horiz, size: 18, color: Color(0xFFC8A860)),
          SizedBox(width: 8),
          Text('ACCIÓN PENDIENTE',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                  letterSpacing: 1,
                  color: Color(0xFFC8A860))),
        ]),
        content: Text(
          hayRestantes
              ? '↔ «$nombres» tiene un teletransporte declarado este turno y se '
                  'moverá al resolver. No puede moverse manualmente.\n\n'
                  '¿Mover el resto de la selección?'
              : '↔ «$nombres» tiene un teletransporte declarado este turno: se '
                  'moverá al resolver el turno. No puede moverse manualmente.\n\n'
                  'Si quieres reasignarla, usa «Deshacer cambios».',
          style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 11,
              height: 1.6,
              color: Color(0xFFBFC8D0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(hayRestantes ? 'CANCELAR' : 'ENTENDIDO',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    color: Color(0xFF506070))),
          ),
          if (hayRestantes)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('MOVER EL RESTO',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      color: Color(0xFF40B0FF))),
            ),
        ],
      ),
    );

    if (!mounted) return;
    if (proceder == true && restantes.isNotEmpty) {
      _entrarModoMovimiento(celda, restantes);
    }
  }

  void _executeMove(String dest, int ri, int ci) {
    final from = _moveFromCoord!;
    final celda = _boardState.getCelda(from);
    final moving = _moveCardIndices
        .where((i) =>
            i < celda.cartas.length &&
            celda.cartas[i].ownerUid == _localPlayer.datos.uid)
        .map((i) => celda.cartas[i])
        .toList();

    if (moving.isEmpty) {
      _cancelMoveMode();
      return;
    }
    final movingSet = moving.toSet();
    final staying = celda.cartas.where((c) => !movingSet.contains(c)).toList();

    setState(() {
      var st =
          _boardState.setCelda(from, CeldaState(coord: from, cartas: staying));
      for (final c in moving) {
        st = st.placeCarta(dest, c);
        _cartasMovidasEsteTurno.add(c.instanceId);
        _cartasQueSeMovieron.add(c.instanceId);
        // Origen del movimiento (solo la primera vez este turno): permite
        // dibujar la silueta fantasma origen→destino de forma fiable.
        _origenTurnoPorId.putIfAbsent(c.instanceId, () => from);
      }
      _boardState = st;
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
      // Al completar el movimiento NO abrimos el menú lateral del destino:
      // el jugador solo quería mover. Lo cerramos; un toque posterior sobre
      // cualquier celda (ya fuera de modo movimiento) lo abrirá con normalidad.
      _sidebarOpen = false;
      _sidebarCoord = null;
    });
  }

  void _cancelMoveMode() {
    setState(() {
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
    });
  }

  /// Deshace el movimiento de las cartas seleccionadas en el menú lateral,
  /// devolviéndolas a la posición que ocupaban al inicio de este turno.
  ///
  /// Solo actúa sobre cartas propias que se movieron ESTE turno (las que están
  /// en [_cartasQueSeMovieron]); su origen se lee de [_origenTurnoPorId], que se
  /// rellenó en [_executeMove]. Tras deshacer, la carta vuelve a poder moverse
  /// (se limpian los rastreos por-instancia), de modo que el estado queda igual
  /// que si nunca la hubieras movido.
  void _undoMoveSelected(List<int> indices) {
    if (_sidebarCoord == null || indices.isEmpty) return;
    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }
    final coord = _sidebarCoord!;
    final celda = _boardState.getCelda(coord);

    // Cartas válidas para deshacer: propias, movidas este turno y con un origen
    // registrado distinto de la celda actual.
    final aDeshacer = <CartaEnCelda>[];
    for (final i in indices) {
      if (i < 0 || i >= celda.cartas.length) continue;
      final c = celda.cartas[i];
      if (c.ownerUid != _localPlayer.datos.uid) continue;
      if (!_cartasQueSeMovieron.contains(c.instanceId)) continue;
      final origen = _origenTurnoPorId[c.instanceId];
      if (origen == null || origen == coord) continue;
      aDeshacer.add(c);
    }

    if (aDeshacer.isEmpty) {
      _toast('No hay movimientos que deshacer en estas cartas.', error: true);
      return;
    }

    final deshacerSet = aDeshacer.toSet();

    setState(() {
      // 1) Quitar las cartas a deshacer de la celda actual.
      final quedan =
          celda.cartas.where((c) => !deshacerSet.contains(c)).toList();
      var st =
          _boardState.setCelda(coord, CeldaState(coord: coord, cartas: quedan));

      // 2) Devolver cada carta a su celda de origen y limpiar su rastreo, para
      //    que vuelva a estar disponible para moverse este turno.
      for (final c in aDeshacer) {
        final origen = _origenTurnoPorId[c.instanceId]!;
        st = st.placeCarta(origen, c);
        _cartasMovidasEsteTurno.remove(c.instanceId);
        _cartasQueSeMovieron.remove(c.instanceId);
        _origenTurnoPorId.remove(c.instanceId);
      }
      _boardState = st;

      // La celda pudo quedar vacía o cambiar de contenido: cerramos el menú
      // lateral para evitar índices obsoletos (un nuevo toque lo reabre).
      _sidebarOpen = false;
      _sidebarCoord = null;
      _cancelMoveMode();
    });

    final n = aDeshacer.length;
    _toast(n == 1
        ? 'Movimiento deshecho: la carta volvió a su posición.'
        : 'Movimientos deshechos: $n cartas volvieron a su posición.');
  }
// ─────────────────────────────────────────────────────────
  // FLUJO DE ACCIONES / HABILIDADES
  // ─────────────────────────────────────────────────────────

  /// Lanza una carta de acción desde la mano. El origen es el cuartel local.
  void _iniciarAccionDesdeMano(int handIndex) {
    if (_yoCerreElTurno || _estoyEliminado) {
      _toast('No puedes lanzar acciones ahora.', error: true);
      return;
    }
    if (handIndex < 0 || handIndex >= _hand.length) return;
    final carta = _hand[handIndex];
    if (!carta.tieneHabilidad) {
      _toast('Esta carta no tiene habilidad asignada.', error: true);
      return;
    }
    if (_obeliscoLocal == null || _obeliscoLocal!.isEmpty) {
      _toast('Necesitas un cuartel asignado.', error: true);
      return;
    }
    // Carta de acción jugada desde la mano → se paga con el campo `coste`
    // normal de la carta (el mismo que se ve en la mano y en el detalle),
    // no con `costeHabilidad` (ese es para habilidades de cartas normales
    // ya desplegadas en el tablero).
    if (_localPlayer.puntos < carta.coste) {
      _toast(
          'Energías insuficientes (${_localPlayer.puntos} / ${carta.coste}).',
          error: true);
      return;
    }

    setState(() {
      _selectedHandIndex = null;
      _cancelMoveMode();
      _sidebarOpen = false;
      _accionController.iniciarDesdeCartaDeMano(
        carta: carta,
        indiceMano: handIndex,
        obeliscoLocal: _obeliscoLocal!,
        obeliscosPorJugador: _obeliscosPorJugador,
        coordsPropias: _coordsConCartaPropia(),
      );
    });
    _toast(
        'Selecciona ${_accionController.habilidad!.numObjetivos == 1 ? 'una celda' : '${_accionController.habilidad!.numObjetivos} celdas'} objetivo.');
  }

  /// Lanza la habilidad de una carta del tablero (carta normal con
  /// idHabilidad > 0). Se llama desde el botón "LANZAR HABILIDAD" del
  /// overlay de detalle.
  Future<void> _iniciarAccionDesdeTablero(
    CartaEnCelda carta,
    String coord,
    int indiceCelda,
  ) async {
    if (_yoCerreElTurno || _estoyEliminado) {
      _toast('No puedes lanzar habilidades ahora.', error: true);
      return;
    }
    if (!carta.habilidadDisponible(_boardState.turnoActual)) {
      _toast('La habilidad está en enfriamiento.', error: true);
      return;
    }
    if (_localPlayer.puntos < carta.carta.costeHabilidad) {
      _toast(
          'Energías insuficientes (${_localPlayer.puntos} / ${carta.carta.costeHabilidad}).',
          error: true);
      return;
    }
    if (_cartasQueSeMovieron.contains(carta.instanceId)) {
      _toast('Esta carta ya se movió este turno: no puede usar habilidad.',
          error: true);
      return;
    }

    setState(() {
      _selectedHandIndex = null;
      _cancelMoveMode();
      _sidebarOpen = false;
      _accionController.iniciarDesdeCartaDeTablero(
        cartaEnCelda: carta,
        coord: coord,
        indiceCelda: indiceCelda,
        obeliscosPorJugador: _obeliscosPorJugador,
        coordsPropias: _coordsConCartaPropia(),
      );
    });
    _toast(
        'Selecciona ${_accionController.habilidad!.numObjetivos == 1 ? 'una celda' : '${_accionController.habilidad!.numObjetivos} celdas'} objetivo.');
  }

  /// Maneja un tap en el tablero cuando estamos en modo acción.
  void _handleCellTapEnAccion(String coord) {
    final controller = _accionController;
    if (controller.fase == FaseAccion.seleccionandoObjetivos) {
      final aceptado = controller.seleccionarObjetivo(coord);
      if (!aceptado) {
        _toast('Esa celda no es un objetivo válido.', error: true);
        return;
      }
      setState(() {}); // refresca highlight

      // Si requiere carta propia → mostrar modal
      if (controller.fase == FaseAccion.seleccionandoCartaTeleport) {
        _showCartaPropiaModal();
        return;
      }

      if (controller.lista) {
        _completarAccion();
      }
    }
  }

  /// Modal para elegir qué carta propia teletransportar.
  Future<void> _showCartaPropiaModal() async {
    // Destino/objetivo ya elegido en la fase anterior.
    //   - Teletransporte: es la celda DESTINO donde caerá la carta.
    //   - Invisibilidad: es la celda que CONTIENE la carta propia a ocultar.
    final destino = _accionController.objetivos.isNotEmpty
        ? _accionController.objetivos.first
        : null;

    final esInvisibilidad =
        _accionController.habilidad?.efecto.tipo == EfectoTipo.invisibilidad;

    final candidatos = <_CartaPropiaRef>[];
    if (esInvisibilidad) {
      // Invisibilidad: solo las cartas PROPIAS de la celda objetivo. No hay
      // restricción de terreno (la carta no se mueve).
      if (destino != null) {
        final celda = _boardState.getCelda(destino);
        for (int i = 0; i < celda.cartas.length; i++) {
          final c = celda.cartas[i];
          if (c.ownerUid != _localPlayer.datos.uid) continue;
          candidatos.add(_CartaPropiaRef(coord: destino, indice: i, carta: c));
        }
      }
    } else {
      // Teletransporte: cartas propias del tablero que puedan ATERRIZAR en el
      // destino (una unidad de aire no puede ir a una celda de agua, etc.).
      _boardState.celdas.forEach((coord, celda) {
        for (int i = 0; i < celda.cartas.length; i++) {
          final c = celda.cartas[i];
          // Las cartas estáticas no pueden teletransportarse (mov 0).
          if (c.carta.esEstatica) continue;
          if (c.ownerUid != _localPlayer.datos.uid) continue;
          // Terreno: descartar las que no pueden aterrizar en el destino.
          if (destino != null && !_config.canLand(destino, c.carta.tipo))
            continue;
          candidatos.add(_CartaPropiaRef(coord: coord, indice: i, carta: c));
        }
      });
    }

    if (candidatos.isEmpty) {
      _toast(
          esInvisibilidad
              ? 'No tienes ninguna carta propia en esa celda.'
              : (destino != null
                  ? 'Ninguna de tus cartas puede aterrizar en $destino.'
                  : 'No tienes cartas en el tablero para teletransportar.'),
          error: true);
      _cancelarAccion();
      return;
    }

    final ref = await showDialog<_CartaPropiaRef>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1525),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x4040C0FF), width: 1),
        ),
        title: const Text('ELIGE UNA CARTA',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 12,
                color: Color(0xFF40C0FF),
                letterSpacing: 1.5)),
        content: SizedBox(
          width: 280,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidatos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final r = candidatos[i];
              return InkWell(
                onTap: () => Navigator.of(ctx).pop(r),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06101C),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: const Color(0x4040C0FF), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Text(r.coord,
                          style: const TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 12,
                              color: Color(0xFFC8A860),
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(r.carta.carta.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: 10,
                                color: Color(0xFFB0A090))),
                      ),
                      Text('${r.carta.carta.fuerza}⚔',
                          style: const TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 10,
                              color: Color(0xFFC04040))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('CANCELAR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: Color(0xFF506070),
                    fontSize: 10)),
          ),
        ],
      ),
    );

    if (ref == null) {
      _cancelarAccion();
      return;
    }
    _accionController.setCartaTeleport(ref.coord, ref.indice,
        cartaId: ref.carta.carta.id);
    _completarAccion();
  }

  /// Arma o cancela la DESCARGA sobre el cuartel propio [coord]. Es un toggle:
  /// si ya estaba armada, se cancela y se reembolsa el coste. La descarga se
  /// declara como una AccionPendiente (esDescarga) y se resuelve en el servidor
  /// ANTES del combate: mata todo lo que haya en el cuartel (amigos y enemigos)
  /// y deja la defensa a 0, recuperándose +25%/turno.
  void _toggleDescarga(String coord) {
    if (_yoCerreElTurno || _estoyEliminado) {
      _toast('No puedes usar la descarga ahora.', error: true);
      return;
    }
    if (_obeliscoLocal != coord) {
      _toast('La descarga solo se usa en tu cuartel.', error: true);
      return;
    }
    final idx = _accionesPendientes
        .indexWhere((a) => a.esDescarga && a.origen == coord);
    if (idx >= 0) {
      // Cancelar: reembolsar el coste.
      setState(() {
        final a = _accionesPendientes.removeAt(idx);
        _localPlayer.puntos += a.costePagado;
      });
      _toast('Descarga cancelada.');
      return;
    }
    if (_localPlayer.puntos < kDescargaCoste) {
      _toast(
          'Energías insuficientes (${_localPlayer.puntos} / $kDescargaCoste).',
          error: true);
      return;
    }
    setState(() {
      _accionesPendientes.add(AccionPendiente(
        habilidadId: 0,
        uid: _localPlayer.datos.uid,
        zona: _localPlayer.zona,
        origen: coord,
        objetivos: [coord],
        turno: _boardState.turnoActual,
        esDescarga: true,
        costePagado: kDescargaCoste,
      ));
      _localPlayer.puntos -= kDescargaCoste;
    });
    _toast(
        'Descarga armada: al resolver morirá todo lo que haya en tu cuartel.');
  }

  /// Construye la AccionPendiente final, descuenta energías y la añade a
  /// la lista pendiente. Si es carta de acción, se descarta de la mano.
  void _completarAccion() {
    final controller = _accionController;
    final accion = controller.construir(
      uid: _localPlayer.datos.uid,
      zona: _localPlayer.zona,
      turno: _boardState.turnoActual,
    );
    if (accion == null) return;

    // ── Revalidación defensiva de energía ──────────────────────
    // El coste se comprobó al iniciar la acción, pero puede haber pasado
    // tiempo (selección de objetivos, modal de teletransporte) durante el
    // cual la energía disponible cambió. Sin esta comprobación era posible
    // completar una acción cuyo coste ya no se podía pagar.
    if (_localPlayer.puntos < accion.costePagado) {
      _toast(
        'Energías insuficientes (${_localPlayer.puntos} / ${accion.costePagado}).',
        error: true,
      );
      _cancelarAccion();
      return;
    }

    setState(() {
      _accionesPendientes.add(accion);
      _localPlayer.puntos -= accion.costePagado;

      // Si es carta de acción: descartar de la mano.
      if (controller.esCartaDeAccion && controller.indiceMano != null) {
        final idx = controller.indiceMano!;
        if (idx >= 0 && idx < _hand.length) {
          // ── Marcador fantasma (solo local) ──────────────────
          // Guardamos la carta en las celdas objetivo únicamente para que
          // el jugador que la lanzó recuerde dónde la puso hasta que se
          // resuelva el turno. No es una CartaEnCelda real: no se envía al
          // servidor, no participa en el cálculo de combate y desaparece
          // en cuanto el turno se resuelve (o se deshacen los cambios).
          final cartaUsada = _hand[idx];
          for (final coord in accion.objetivos) {
            (_fantasmasAccion[coord] ??= []).add(cartaUsada);
          }
          _hand = List.from(_hand)..removeAt(idx);
        }
      }
      // Si es habilidad de carta en tablero: marcar ultimoUsoHabilidad.
      if (controller.esHabilidadDeTablero &&
          controller.cartaTableroCoord != null &&
          controller.cartaTableroIndice != null) {
        final coord = controller.cartaTableroCoord!;
        final indice = controller.cartaTableroIndice!;
        final celda = _boardState.getCelda(coord);
        if (indice >= 0 && indice < celda.cartas.length) {
          _cartasQueUsaronHabilidad.add(celda.cartas[indice].instanceId);
          final actualizada = celda.cartas[indice]
              .copyWith(ultimoUsoHabilidad: _boardState.turnoActual);
          final nuevasCartas = [...celda.cartas];
          nuevasCartas[indice] = actualizada;
          _boardState =
              _boardState.setCelda(coord, celda.withCartas(nuevasCartas));
        }
      }
      _accionController.cancelar();
    });
    _toast('Acción declarada. Se resolverá al cerrar el turno.');
  }

  void _cancelarAccion() {
    setState(() => _accionController.cancelar());
  }

  /// Celdas del tablero que contienen alguna carta del jugador local. Se usa
  /// para impedir que veneno / parálisis apunten a las propias unidades
  /// (incidencia #2: "veneno y parálisis no puede afectar al propio jugador que
  /// lo lanzó"). Incluye también los fantasmas de acción propios pendientes.
  Set<String> _coordsConCartaPropia() {
    final uid = _localPlayer.datos.uid;
    final res = <String>{};
    _boardState.celdas.forEach((coord, celda) {
      if (celda.cartas.any((c) => c.ownerUid == uid)) res.add(coord);
    });
    // Fantasmas de acción (cartas propias colocadas visualmente este turno).
    res.addAll(_fantasmasAccion.keys);
    return res;
  }

  void _undoCambios() {
    // Gastos revertibles persistidos en el servidor este turno (despliegues +
    // compras + evoluciones) y especiales compradas este turno. El estado del
    // servidor trae la energía ya reducida y las especiales marcadas, así que
    // hay que devolver la energía y desmarcarlas explícitamente o se quedarían
    // gastadas / bloqueadas tras deshacer (bug QAS #2).
    final energiaADevolver = _energiaGastadaDespliegue;
    final especialesADesmarcar = _especialesCompradasEsteTurno.toList();

    setState(() {
      _boardState = _boardStateInicial;
      _hand = List.from(_handInicial);
      _cartasMovidasEsteTurno.clear();
      _cartasRobadasEsteTurno.clear();
      _cartasQueEvolucionaron.clear();
      _cartasQueSeMovieron.clear();
      _origenTurnoPorId.clear();
      _cartasQueUsaronHabilidad.clear();
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
      _selectedHandIndex = null;
      _sidebarOpen = false;
      _sidebarCoord = null;
      _accionController.cancelar();
      _accionesPendientes.clear();
      _fantasmasAccion.clear();
      // Restaurar energías locales al snapshot de inicio de turno (incluye el
      // coste de acciones, que no se persiste hasta cerrar el turno).
      _localPlayer.puntos = _puntosInicial;
      _energiaGastadaDespliegue = 0;
      // Desmarcar localmente las especiales compradas este turno (para poder
      // recomprarlas) y limpiar el rastreo del turno.
      _especialesCompradas.removeAll(especialesADesmarcar);
      _especialesCompradasEsteTurno.clear();
      _revisionFantasmas = const [];
      _revisionAcciones = const {};
    });

    // Revertir en el servidor: devolver la energía revertible y desmarcar las
    // especiales compradas este turno.
    if (widget.lobbyId != null &&
        (energiaADevolver > 0 || especialesADesmarcar.isNotEmpty)) {
      _api.deshacerTurno(
        lobbyId: widget.lobbyId!,
        uid: widget.localPlayerUid,
        turno: _boardState.turnoActual,
        energiesDelta: energiaADevolver,
        especialesQuitar: especialesADesmarcar,
      );
    }
    // Deshacer manual: el gasto queda revertido, así que borramos la deuda
    // persistida (evita un doble reembolso al reentrar).
    _limpiarDeudaPendiente();

    _toast('Cambios revertidos al estado inicial del turno.');
  }

  /// Sacrifica una carta de la mano a cambio de la mitad de su coste en
  /// energías (redondeo hacia abajo). El sacrificio es DEFINITIVO: la carta se
  /// pierde y no se revierte con "deshacer", por lo que también se elimina del
  /// snapshot de inicio de turno y la energía recibida se consolida.
  Future<void> _sacrificarCarta(int index) async {
    if (_yoCerreElTurno || _estoyEliminado) {
      _toast('No puedes sacrificar cartas ahora.', error: true);
      return;
    }
    if (index < 0 || index >= _hand.length) return;
    final carta = _hand[index];

    // No se puede sacrificar una carta robada este MISMO turno (aún sin
    // consolidar): evitaría el combo robar→sacrificar→salir para quedarse la
    // recompensa (permanente) y recuperar el precio del robo (revertible).
    if (_cartasRobadasEsteTurno.any((c) => identical(c, carta))) {
      _toast(
          'No puedes sacrificar una carta robada este turno. '
          'Cierra el turno primero para consolidarla.',
          error: true);
      return;
    }

    final recompensa = carta.coste ~/ 2;

    setState(() {
      _hand = List<CartaModel>.from(_hand)..removeAt(index);
      _handInicial = List<CartaModel>.from(_handInicial)..remove(carta);
      _localPlayer.puntos += recompensa;
      _puntosInicial += recompensa;
      if (_selectedHandIndex == index) {
        _selectedHandIndex = null;
      } else if (_selectedHandIndex != null && _selectedHandIndex! > index) {
        _selectedHandIndex = _selectedHandIndex! - 1;
      }
    });

    if (widget.lobbyId != null) {
      try {
        // IMPORTANTE: persistir la mano REVERTIBLE (_handInicial), no _hand.
        // _hand ya está vaciada por las cartas desplegadas este turno (que aún
        // NO se han consolidado en el tablero: este solo se guarda al cerrar el
        // turno). Si persistiéramos _hand, el servidor perdería esas cartas
        // desplegadas: al salir a mitad de turno el tablero revierte (nunca se
        // guardó) y la mano quedaría sin ellas → cartas desaparecidas.
        // _handInicial = mano de inicio de turno menos las sacrificadas (ya se
        // le quitó la carta arriba) e incluye las desplegadas revertibles, que
        // es justo lo que el jugador debe recuperar si abandona sin cerrar.
        await _api.actualizarStats(
          lobbyId: widget.lobbyId!,
          uid: widget.localPlayerUid,
          energiesDelta: recompensa,
          mano: _handInicial.map((c) => c.id).toList(),
          mazoRestante: _mazoRestante.map((c) => c.id).toList(),
        );
      } catch (_) {
        // Revertir si falla la persistencia.
        if (mounted) {
          setState(() {
            _hand = List<CartaModel>.from(_hand)..insert(index, carta);
            _handInicial = List<CartaModel>.from(_handInicial)..add(carta);
            _localPlayer.puntos -= recompensa;
            _puntosInicial -= recompensa;
          });
        }
        _toast('No se pudo sacrificar. Inténtalo de nuevo.', error: true);
        return;
      }
    }

    _toast('${carta.nombre} sacrificada  (+$recompensa Ø)');
  }

  void _onHandCardTap(int index) {
    if (index < 0 || index >= _hand.length) return;
    final carta = _hand[index];

    // ── Carta de acción: entra en modo selección de objetivos ──
    if (carta.esAccion) {
      _iniciarAccionDesdeMano(index);
      return;
    }

    // Comportamiento clásico para cartas no-acción
    setState(() {
      _accionController.cancelar();
      _selectedHandIndex = _selectedHandIndex == index ? null : index;
      _cancelMoveMode();
      if (_selectedHandIndex != null) _sidebarOpen = false;
    });
  }

  void _closeSidebar() => setState(() {
        _sidebarOpen = false;
        _sidebarCoord = null;
      });

  Map<String, List<Map<String, dynamic>>> _serializarTablero() {
    // Origen (celda de inicio de turno) de cada carta propia, por instanceId.
    // Sirve para etiquetar de DÓNDE viene una carta que se movió este turno, de
    // modo que la flecha origen→destino se pueda dibujar incluso tras salir y
    // volver a entrar (el estado del servidor no reenvía el tablero de inicio).
    final origenPorId = <String, String>{};
    _boardStateInicial.celdas.forEach((coord, celda) {
      for (final c in celda.cartas) {
        if (c.ownerUid == _localPlayer.datos.uid) {
          origenPorId[c.instanceId] = coord;
        }
      }
    });

    final result = <String, List<Map<String, dynamic>>>{};
    _boardState.celdas.forEach((coord, celda) {
      final misCartas = celda.cartas
          .where((c) => c.ownerUid == _localPlayer.datos.uid)
          .map((c) {
        final carta = c.carta;
        final map = <String, dynamic>{
          'id': carta.id,
          'Nombre': carta.nombre,
          'Descripcion': carta.descripcion,
          'Ejercito': carta.ejercito,
          'Fuerza': carta.fuerza,
          'Defensa': carta.defensa,
          'Coste': carta.coste,
          'IdHabilidad': carta.idHabilidad,
          'CosteHabilidad': carta.costeHabilidad,
          'EnfriamientoHabilidad': carta.enfriamientoHabilidad,
          // Imagen (skin resuelto): sin ella la carta en el tablero se queda sin
          // imagen al recomponer el tablero desde el servidor (bug del menú
          // lateral). El combate del servidor conserva los campos tal cual.
          'Imagen': carta.imagen,
          'Movimiento': carta.movimiento,
          'Tipo': carta.tipo,
          'IdEvolucion': carta.idEvolucion,
          'Evolucion': carta.evolucion,
          'Condicion': carta.condicion.value,
          'PorDefecto': carta.porDefecto,
          'ownerUid': c.ownerUid,
          'ownerZone': c.ownerZone,
          // Conservar los efectos persistentes (veneno, parálisis…) y el
          // enfriamiento de habilidad: si no se reenvían, el servidor los
          // pierde al recomponer el tablero cada turno.
          if (c.efectos.isNotEmpty)
            'Efectos': c.efectos.map((e) => e.toMap()).toList(),
          if (c.ultimoUsoHabilidad != null)
            'UltimoUsoHabilidad': c.ultimoUsoHabilidad,
        };
        // Etiqueta de revisión: celda de origen si esta carta se movió este
        // turno. El servidor la guarda tal cual en movimientosTurno (M.FromJson
        // conserva campos extra) y la ignora en el combate.
        final origen =
            _origenTurnoPorId[c.instanceId] ?? origenPorId[c.instanceId];
        if (_cartasQueSeMovieron.contains(c.instanceId) &&
            origen != null &&
            origen != coord) {
          map['origenTurno'] = origen;
        }
        return map;
      }).toList();
      if (misCartas.isNotEmpty) result[coord] = misCartas;
    });
    return result;
  }

  /// Toma la instantánea de revisión (siluetas de origen y acciones de este
  /// turno) para mostrarla sobre el tablero mientras el turno cerrado se resuelve.
  void _capturarRevisionTurno() {
    final uid = widget.localPlayerUid;

    // instanceId → coord al inicio del turno (solo mis cartas).
    final iniPorId = <String, String>{};
    _boardStateInicial.celdas.forEach((coord, celda) {
      for (final c in celda.cartas) {
        if (c.ownerUid == uid) iniPorId[c.instanceId] = coord;
      }
    });

    // Silueta fantasma en la celda de ORIGEN de cada carta que moví (una por
    // celda de origen).
    final fantasmas = <_Fantasma>[];
    final vistos = <String>{};
    _boardState.celdas.forEach((coord, celda) {
      for (final c in celda.cartas) {
        if (c.ownerUid != uid) continue;
        if (!_cartasQueSeMovieron.contains(c.instanceId)) continue;
        final from = _origenTurnoPorId[c.instanceId] ?? iniPorId[c.instanceId];
        if (from == null || from == coord) continue;
        if (!vistos.add(from)) continue;
        fantasmas.add(_ghostDeCarta(from, coord, c.carta));
      }
    });

    // Celdas objetivo de acciones/habilidades declaradas + fantasmas de acción.
    final acciones = <String>{};
    for (final a in _accionesPendientes) {
      acciones.addAll(a.objetivos);
      final origenCarta = a.cartaOrigenCoord;
      if (origenCarta != null && origenCarta.isNotEmpty) {
        acciones.add(origenCarta);
      }
    }
    acciones.addAll(_fantasmasAccion.keys);

    _revisionFantasmas = fantasmas;
    _revisionAcciones = acciones;
  }

  /// Construye la silueta fantasma de [carta] que se movió de [origen] a
  /// [destino] (mismo lenguaje visual que su token: color del jugador, icono de
  /// tipo, movimiento y nombre).
  _Fantasma _ghostDeCarta(String origen, String destino, CartaModel carta) {
    final color = _playerColors[widget.localPlayerUid] ?? ownerColor('');
    return (
      origen: origen,
      destino: destino,
      color: color,
      icon: carta.tipoIconData,
      iconColor: Color(carta.tipoColorValue),
      movimiento: carta.movimiento,
      nombre: carta.nombre,
    );
  }

  /// Mi movimiento comprometido (celdas + acciones) para el turno actual, tal y
  /// como lo guardó el servidor al cerrar. Es la fuente PERSISTENTE de la
  /// revisión: sobrevive a refrescos y a salir/entrar de la pantalla. `null` si
  /// aún no he cerrado (o no hay entrada para el turno en curso).
  MovimientoTurno? _miMovimientoComprometido(Map<String, dynamic> estado) {
    final turnoActual =
        (estado['turnoActual'] as num?)?.toInt() ?? _boardState.turnoActual;
    final rawMov =
        estado['movimientosTurno'] as Map<String, dynamic>? ?? const {};
    final mine = rawMov[widget.localPlayerUid];
    if (mine == null) return null;
    try {
      final mov =
          MovimientoTurno.fromMap(Map<String, dynamic>.from(mine as Map));
      return mov.turno == turnoActual ? mov : null;
    } catch (_) {
      return null;
    }
  }

  /// Recalcula la capa de revisión (flechas origen→destino de mis movimientos y
  /// celdas objetivo de mis acciones) a partir del estado AUTORITATIVO del
  /// servidor: compara mis posiciones de inicio de turno (`estado['tablero']`)
  /// con mis celdas ya comprometidas (`movimientosTurno.{uid}.celdas`). Como se
  /// basa en el servidor, funciona igual tras salir y volver a entrar.
  /// Debe llamarse dentro de un setState.
  void _actualizarOverlayRevision(Map<String, dynamic> estado) {
    final mov = _miMovimientoComprometido(estado);
    if (mov == null) {
      _revisionFantasmas = const [];
      _revisionAcciones = const {};
      return;
    }
    // Celdas objetivo de mis acciones/habilidades: SIEMPRE disponibles desde
    // `movimientosTurno.acciones` (no necesitan el tablero).
    final uid = widget.localPlayerUid;
    final acciones = <String>{};
    for (final a in mov.acciones) {
      acciones.addAll(a.objetivos);
      final oc = a.cartaOrigenCoord;
      if (oc != null && oc.isNotEmpty) acciones.add(oc);
    }
    _revisionAcciones = acciones;

    // Siluetas fantasma en el ORIGEN. Fuente PRINCIPAL: el campo `origenTurno`
    // que viaja con cada carta movida (se escribe en _serializarTablero al
    // cerrar), así que funciona aunque el estado no traiga `tablero` (p. ej.
    // tras reentrar).
    final fantasmas = <_Fantasma>[];
    final vistos = <String>{};
    var huboOrigenTurno = false;
    mov.celdas.forEach((coord, cartas) {
      for (final c in cartas) {
        final origen = (c['origenTurno'] as String?) ?? '';
        if (origen.isEmpty) continue;
        huboOrigenTurno = true;
        if (origen == coord) continue;
        if (!vistos.add(origen)) continue;
        fantasmas.add(_ghostDeCarta(origen, coord, _cartaFromMap(c)));
      }
    });

    if (huboOrigenTurno) {
      _revisionFantasmas = fantasmas;
      return;
    }

    // Respaldo (datos sin `origenTurno`): diff contra el tablero de inicio, si
    // el estado lo trae. Si no lo trae, conservamos lo que hubiera (no lo
    // borramos). En el turno 1 solo hay despliegues, así que no hay siluetas.
    if (!estado.containsKey('tablero')) return;

    final startById = <String, List<String>>{};
    TurnService.parseTablero(estado).forEach((coord, cartas) {
      for (final c in cartas) {
        if ((c['ownerUid'] as String? ?? '') != uid) continue;
        final id = (c['id'] ?? c['Id'] ?? '').toString();
        (startById[id] ??= <String>[]).add(coord);
      }
    });

    final fantasmas2 = <_Fantasma>[];
    final vistos2 = <String>{};
    mov.celdas.forEach((coord, cartas) {
      for (final c in cartas) {
        final id = (c['id'] ?? c['Id'] ?? '').toString();
        final cola = startById[id];
        if (cola == null || cola.isEmpty) continue; // desplegada este turno
        if (cola.remove(coord)) continue; // seguía en la misma celda
        final from = cola.removeAt(0);
        if (from == coord) continue;
        if (!vistos2.add(from)) continue;
        fantasmas2.add(_ghostDeCarta(from, coord, _cartaFromMap(c)));
      }
    });

    _revisionFantasmas = fantasmas2;
  }

  /// Devuelve el tablero de inicio [startBoard] con MIS cartas recolocadas en
  /// las posiciones que ya comprometí este turno (`movimientosTurno.{uid}`), de
  /// modo que, al reentrar mientras el turno se resuelve, se vean mis unidades
  /// donde las moví (no en su posición de inicio). Las cartas ajenas y los
  /// efectos/rayos/cuarteles del tablero se conservan intactos.
  BoardState _reconstruirBoardConMisMovimientos(
      Map<String, dynamic> estado, BoardState startBoard) {
    final mov = _miMovimientoComprometido(estado);
    if (mov == null) return startBoard;
    final uid = widget.localPlayerUid;

    var b = startBoard;
    // Quitar mis cartas de todas las celdas donde aparezcan.
    final coordsConMias = <String>[];
    startBoard.celdas.forEach((coord, celda) {
      if (celda.cartas.any((c) => c.ownerUid == uid)) coordsConMias.add(coord);
    });
    for (final coord in coordsConMias) {
      final ajenas =
          b.getCelda(coord).cartas.where((c) => c.ownerUid != uid).toList();
      b = b.setCelda(coord, CeldaState(coord: coord, cartas: ajenas));
    }
    // Colocar mis cartas comprometidas en su celda de destino. Se usa
    // `CartaEnCelda.fromMap` para preservar el campo `Efectos` que
    // `_serializarTablero` ya escribe en `movimientosTurno` (así mis cartas
    // conservan sus venenos/potenciaciones al reentrar mientras el turno se
    // resuelve). Si el map no trajera ownerUid, caemos al uid local.
    mov.celdas.forEach((coord, cartas) {
      for (final c in cartas) {
        final base = CartaEnCelda.fromMap(c);
        b = b.placeCarta(
          coord,
          base.ownerUid.isEmpty ? base.copyWith(ownerUid: uid) : base,
        );
      }
    });
    return b;
  }

  Future<void> _cerrarTurno() async {
    if (_yoCerreElTurno || _isSendingTurn || _estoyEliminado) return;
    // Instantánea de revisión ANTES de tocar nada: se mostrará sobre el tablero
    // hasta que el turno se resuelva.
    _capturarRevisionTurno();
    setState(() {
      _isSendingTurn = true;
      _selectedHandIndex = null;
      _cancelMoveMode();
      _sidebarOpen = false;
      _timerActivo = false;
      // Marcar mi cierre de forma optimista: así el banner de espera y la capa
      // de revisión (flechas/acciones) aparecen al instante, sin esperar a que
      // el servidor confirme en el siguiente sondeo. El poll lo reconcilia.
      if (!_cerradoPor.contains(widget.localPlayerUid)) {
        _cerradoPor = [..._cerradoPor, widget.localPlayerUid];
      }
    });

    if (widget.lobbyId != null) {
      final turnService = TurnService();
      // BUG QAS #2: persistir la mano y el mazo ANTES de cerrar (bloqueante),
      // para que el servidor reparta la carta de fin de turno sobre la mano
      // correcta (ya sin las cartas desplegadas este turno). Ya NO se persiste
      // DESPUÉS de cerrar, porque machacaría la carta que el servidor repartió.
      try {
        await _api
            .actualizarStats(
              lobbyId: widget.lobbyId!,
              uid: widget.localPlayerUid,
              mano: _hand.map((c) => c.id).toList(),
              mazoRestante: _mazoRestante.map((c) => c.id).toList(),
            )
            .timeout(const Duration(seconds: 15));
      } catch (_) {/* el cierre puede continuar; el servidor usa lo último */}
      try {
        await turnService
            .cerrarTurno(
              lobbyId: widget.lobbyId!,
              uid: widget.localPlayerUid,
              turno: _boardState.turnoActual,
              celdas: _serializarTablero(),
              acciones: _accionesPendientes,
            )
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        bool reintentado = false;
        for (int intento = 1; intento <= 2; intento++) {
          await Future.delayed(Duration(seconds: intento * 2));
          if (!mounted) return;
          try {
            await turnService
                .cerrarTurno(
                  lobbyId: widget.lobbyId!,
                  uid: widget.localPlayerUid,
                  turno: _boardState.turnoActual,
                  celdas: _serializarTablero(),
                  acciones: _accionesPendientes,
                )
                .timeout(const Duration(seconds: 30));
            reintentado = true;
            break;
          } catch (_) {}
        }
        if (!mounted) return;
        if (!reintentado) {
          setState(() => _isSendingTurn = false);
          _toast('Error: ${e.toString().split(']').last.trim()}', error: true);
          return;
        }
      }
      if (!mounted) return;
      // Turno cerrado: el gasto queda consolidado, no hay nada que reembolsar.
      _limpiarDeudaPendiente();
      // BUG QAS #2: NO se vuelve a persistir la mano aquí. El servidor ya
      // repartió la carta de fin de turno sobre la mano que subimos ANTES de
      // cerrar; reescribirla ahora la machacaría. La mano se resincroniza desde
      // el estado autoritativo en _sincronizarManoDesdeEstado.

      // Si el servidor resolvió el turno con ESTA llamada (yo era el último en
      // cerrar), no dependemos del stream: forzamos un refresco autoritativo
      // que aplica el tablero nuevo y abre el informe de inmediato.
      final cierre = turnService.ultimoCierre;
      debugPrint('[WZ][cerrar] ultimoCierre.resuelto=${cierre?.resuelto} '
          'turnoActual=${cierre?.turnoActual}');
      if (cierre != null && cierre.resuelto) {
        if (mounted) setState(() => _isSendingTurn = false);
        // Camino HTTP puro: el estado viene en la propia respuesta del cierre.
        if (cierre.estado != null) {
          _aplicarEstado(cierre.estado!);
        } else {
          await _checkRefresh(turnoEsperado: cierre.turnoActual);
        }
        return;
      }

      // No resolví yo (soy el que espera al resto). El stream debería avanzar
      // solo, pero en redes/emuladores lentos puede no llegar: arranco un
      // sondeo ligero como red de seguridad hasta que el turno avance.
      _iniciarSondeoEspera(_boardState.turnoActual);
    } else {
      // Modo offline: avanzar turno y robar 1 carta al azar del mazo (pool 8).
      setState(() {
        _boardState = _boardState.nextTurn(_opponentPlayer.datos.uid);
      });
      final robo = _calcularRoboNuevoTurno();
      _ultimaCartaRepartida = robo.carta;
      if (robo.carta != null) {
        setState(() {
          _hand = robo.mano;
          _mazoRestante = robo.mazo;
        });
        _toast('🃏 +1 carta para el nuevo turno');
      }
    }

    if (mounted) setState(() => _isSendingTurn = false);
    _toast('Turno cerrado. Esperando a los demás…');
  }

  void _endTurn() => _cerrarTurno();

  /// Color asignado a un uid: el de `_playerColors` (obelisco), o el de su zona
  /// como respaldo.
  Color _colorDeUid(String uid, {String? zonaFallback}) {
    final c = _playerColors[uid];
    if (c != null) return c;
    if (zonaFallback != null) return ownerColor(zonaFallback);
    return const Color(0xFF888888);
  }

  /// Construye la lista de jugadores para el menú desplegable de la barra de
  /// partida: alias, color asignado y total de Zeros. Para el jugador local se
  /// usan sus Zeros en vivo (`_localPlayer.puntos`); para el resto, los de
  /// statsPartida del lobby.
  List<HudJugadorInfo> _infoJugadoresHud() {
    final lobby = _currentLobby;
    final localUid = _localPlayer.datos.uid;
    if (lobby == null) {
      return [
        HudJugadorInfo(
          alias: _localPlayer.alias,
          color: _colorDeUid(localUid, zonaFallback: _localPlayer.zona),
          zeros: _localPlayer.puntos,
          esLocal: true,
        ),
      ];
    }
    return [
      for (final j in lobby.jugadores)
        HudJugadorInfo(
          alias: j.alias,
          color: _colorDeUid(j.uid),
          zeros: j.uid == localUid
              ? _localPlayer.puntos
              : lobby.statsDeJugador(j.uid).energies,
          esLocal: j.uid == localUid,
        ),
    ];
  }

  Future<void> _confirmExit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1525),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x40C8A860), width: 1),
        ),
        title: const Text('SALIR DE LA PARTIDA',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 12,
                color: Color(0xFFC8A860),
                letterSpacing: 1.5)),
        content: const Text(
            'Tu progreso de este turno se perderá si no cerraste el turno. ¿Salir al menú?',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 10,
                color: Color(0xFF8A9AAA),
                height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    color: Color(0xFF506070))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('SALIR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    color: Color(0xFFC04040),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      // BUG QAS #2: al salir a mitad de turno se DESHACEN los gastos no
      // consolidados (se devuelven los Zeros de despliegues/compras/evoluciones
      // y se desmarcan las especiales compradas este turno). El tablero revierte
      // solo al reentrar porque no se persiste a mitad de turno.
      _revertirGastosServidor();
      _pollTimer?.cancel();
      Navigator.of(context).pop();
    }
  }

  /// Calcula el robo de 1 carta AL AZAR del mazo completo (pool de hasta 8,
  /// CON repetición: la misma carta puede salir otro turno). Excluye nada extra
  /// (el pool ya viene sin evoluciones). No muta el estado: devuelve la carta
  /// robada (o null) y la nueva mano para que el llamador la aplique.
  ({CartaModel? carta, List<CartaModel> mazo, List<CartaModel> mano})
      _calcularRoboNuevoTurno() {
    CartaModel? carta;
    if (_mazoCompleto.isNotEmpty && !_estoyEliminado) {
      carta = _mazoCompleto[math.Random().nextInt(_mazoCompleto.length)];
    }
    final nuevaMano =
        carta != null ? [..._hand, carta] : List<CartaModel>.from(_hand);
    // El pool no se agota: _mazoRestante se mantiene igual.
    return (carta: carta, mazo: _mazoRestante, mano: nuevaMano);
  }

  /// Aplica un estado de partida recibido por HTTP (sin Firestore): tablero,
  /// efectos, informe y avance de turno. [estado] tiene el mismo shape que el
  /// doc de Firestore. Devuelve true si avanzó el turno.
  bool _aplicarEstado(Map<String, dynamic> estado) {
    if (!mounted) return false;
    _fechaResolucionMs = (estado['fechaResolucion'] as num?)?.toInt();
    _revisarAlianzas(estado);
    final turnoActual = (estado['turnoActual'] as num?)?.toInt() ?? 0;
    final cerradoPor = ((estado['cerradoPor'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final jugadores = (estado['jugadores'] as List?) ?? [];
    debugPrint('[WZ][estado] aplicar turnoActual=$turnoActual '
        'confirmado=$_turnoConfirmadoStream cerradoPor=$cerradoPor');

    try {
      setState(() {
        _cerradoPor = cerradoPor;
        if (jugadores.isNotEmpty) _jugadoresEnPartida = jugadores.length;
      });
      _maybeMostrarInforme(turnoActual, estado);

      if (turnoActual > _turnoConfirmadoStream &&
          estado.containsKey('tablero')) {
        debugPrint('[WZ][estado] avanzando tablero a $turnoActual');
        final tableroRaw = TurnService.parseTablero(estado);
        final efectos = TurnService.parseEfectosCelda(estado);
        var restored = const BoardState();
        tableroRaw.forEach((coord, cartas) {
          for (final c in cartas) {
            try {
              restored = restored.placeCarta(coord, CartaEnCelda.fromMap(c));
            } catch (e) {
              debugPrint('[WZ][estado][ERROR] carta mal formada en $coord: $e');
            }
          }
        });
        restored = restored.copyWith(efectosCelda: efectos);
        _turnoConfirmadoStream = turnoActual;

        setState(() {
          _boardState = restored
              .copyWith(turnoActual: turnoActual)
              .withRayos(_rayoCoordsFromData(estado))
              .withCuarteles(_cuartelesDestruidosFromData(estado));
          _cerradoPor = [];
          _isSendingTurn = false;
          _cargaCompletada = true;
          _boardStateInicial = restored
              .copyWith(turnoActual: turnoActual)
              .withRayos(_rayoCoordsFromData(estado))
              .withCuarteles(_cuartelesDestruidosFromData(estado));
          _cartasMovidasEsteTurno.clear();
          _cartasRobadasEsteTurno.clear();
          _cartasQueEvolucionaron.clear();
          _cartasQueSeMovieron.clear();
          _origenTurnoPorId.clear();
          _cartasQueUsaronHabilidad.clear();
          // Las acciones (veneno, disparo, teletransporte…) pertenecían al
          // turno que acaba de resolverse; hay que descartarlas o se
          // reenviarían cada turno (p. ej. el veneno se refrescaría a 3
          // indefinidamente y nunca desaparecería de la celda).
          _accionesPendientes.clear();
          _accionController.cancelar();
          _fantasmasAccion.clear();
          _energiaGastadaDespliegue = 0;
          _robosComprados =
              0; // el precio de robar vuelve a 100 al empezar el turno
          _especialesCompradasEsteTurno.clear();
          _revisionFantasmas = const [];
          _revisionAcciones = const {};
        });
        // Turno nuevo: sin deuda pendiente que reembolsar.
        _limpiarDeudaPendiente();

        // BUG QAS #2: mano/mazo llegan del servidor con la carta ya repartida.
        _sincronizarManoDesdeEstado(estado);

        // Refrescar energías del nuevo turno desde el estado.
        final rawSt = estado['statsPartida'] as Map<String, dynamic>? ?? {};
        if (rawSt.containsKey(widget.localPlayerUid)) {
          final myS =
              Map<String, dynamic>.from(rawSt[widget.localPlayerUid] as Map);
          final pts = (myS['energies'] as num?)?.toInt() ?? _localPlayer.puntos;
          setState(() {
            _localPlayer.puntos = pts;
            _puntosInicial = pts;
          });
        } else {
          _puntosInicial = _localPlayer.puntos;
        }

        if (_modoTurno == ModoTurno.rapida) _startTimer();
        if (_meRepartieronCarta(estado)) {
          _toast('🃏 +1 carta para el nuevo turno');
        }

        debugPrint('[WZ][estado] tablero aplicado, turno=$turnoActual '
            'reparto=${_meRepartieronCarta(estado) ? 'sí' : 'no'}');
        return true;
      }

      // Revisión post-cierre (sin avance de turno): recalcular desde el servidor
      // las flechas de mis movimientos y las celdas de mis acciones.
      if (mounted && _yoCerreElTurno) {
        setState(() => _actualizarOverlayRevision(estado));
      }
    } catch (e, st) {
      debugPrint('[WZ][estado][ERROR] $e');
      debugPrint('[WZ][estado][ERROR] $st');
    }
    return false;
  }

  /// Sondeo de seguridad para el jugador que ya cerró y espera la resolución.
  /// Refresca periódicamente hasta que el turno avance (o se agote el margen),
  /// por si el stream de Firestore no entrega el cambio en vivo.
  Future<void> _iniciarSondeoEspera(int turnoAntes) async {
    if (_sondeoActivo) return;
    if (widget.lobbyId == null) return;
    _sondeoActivo = true;
    debugPrint('[WZ][sondeo] inicio (HTTP), turnoAntes=$turnoAntes');
    try {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        if (_turnoConfirmadoStream > turnoAntes) {
          debugPrint('[WZ][sondeo] turno avanzó, fin');
          return;
        }
        try {
          final estado = await _api.obtenerEstado(widget.lobbyId!);
          if (!mounted) return;
          if (estado != null) {
            final avanzo = _aplicarEstado(estado);
            if (avanzo || _turnoConfirmadoStream > turnoAntes) {
              debugPrint('[WZ][sondeo] turno avanzó tras estado HTTP, fin');
              return;
            }
          }
        } catch (e) {
          debugPrint('[WZ][sondeo] obtenerEstado falló: $e');
        }
      }
      debugPrint('[WZ][sondeo] agotado sin avance');
    } finally {
      _sondeoActivo = false;
    }
  }

  /// Refresca el estado por HTTP (sin Firestore). Si se pasa [turnoEsperado],
  /// reintenta hasta que el estado refleje ese turno (o se agoten los intentos).
  Future<void> _checkRefresh({int? turnoEsperado}) async {
    if (widget.lobbyId == null) return;
    debugPrint('[WZ][refresh] inicio HTTP (confirmado=$_turnoConfirmadoStream '
        'esperado=${turnoEsperado ?? '-'})');

    Map<String, dynamic>? estado;
    for (int i = 0; i < 6; i++) {
      try {
        estado = await _api.obtenerEstado(widget.lobbyId!);
      } catch (e) {
        debugPrint('[WZ][refresh] intento ${i + 1} HTTP falló: $e');
      }
      if (estado != null) {
        final t = (estado['turnoActual'] as num?)?.toInt() ?? 0;
        debugPrint('[WZ][refresh] intento ${i + 1} turno=$t '
            '(esperado=${turnoEsperado ?? '-'})');
        if (turnoEsperado == null || t >= turnoEsperado) break;
      }
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
    }

    if (estado == null || !mounted) {
      if (mounted) _toast('No se pudo actualizar. Inténtalo de nuevo.');
      return;
    }

    final avanzo = _aplicarEstado(estado);

    // Turno no avanzado y yo ya cerré: informar cuántos faltan.
    if (!avanzo && _yoCerreElTurno) {
      final faltan = _jugadoresActivos - _cerradoPor.length;
      if (faltan > 0) {
        _toast('Faltan $faltan jugador${faltan == 1 ? '' : 'es'} por cerrar.');
      } else {
        _toast('Esperando a que el servidor resuelva el turno…');
      }
    }
  }

  /// Abre la pantalla de revisión del turno con los eventos del último
  /// turno resuelto. Se llama tras cerrar el informe de batalla.
  void _abrirRevisionTurno({required int turnoRevisar}) {
    if (!mounted) return;
    Map<String, dynamic>? entry;
    for (final h in _historialCombates.reversed) {
      final t = (h['turno'] as num?)?.toInt() ?? 0;
      if (t == turnoRevisar) {
        entry = h;
        break;
      }
    }
    entry ??= {
      'turno': turnoRevisar,
      'combateLog': _lastCombateLog,
      'movimientosLog': _lastMovimientosLog,
      'accionesLog': _lastAccionesLog,
      'conquistasLog': const [],
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RevisionTurnoScreen(
          config: _config,
          boardState: _boardState,
          historialEntry: entry!,
          localUid: widget.localPlayerUid,
          playerColors: _playerColors,
          obeliscoLocal: _obeliscoLocal,
          obeliscosPorJugador: _obeliscosPorJugador,
        ),
      ),
    );
  }

  // ── Diálogo de eliminación ────────────────────────────────
  void _showEliminadoDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A0505),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('💀 CUARTEL DESTRUIDO',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 14,
                color: Color(0xFFCC3030),
                letterSpacing: 1.5)),
        content: const Text(
            'Tu cuartel general ha sido conquistado.\n'
            'Has sido eliminado de la partida.\n'
            'Puedes seguir observando la batalla.',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 10,
                color: Color(0xFF8A6060),
                height: 1.7)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OBSERVAR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    color: Color(0xFFCC3030))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // salir al menú
            },
            child: const Text('SALIR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    color: Color(0xFF506070))),
          ),
        ],
      ),
    );
  }

  // ── Diálogo de fin de partida ─────────────────────────────
  void _showFinPartidaDialog() {
    if (!mounted) return;
    final somoGanador = _ganadorUid == widget.localPlayerUid;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor:
            somoGanador ? const Color(0xFF0A1A05) : const Color(0xFF0A0A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(somoGanador ? '🏆 ¡VICTORIA!' : '⚔  PARTIDA FINALIZADA',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 14,
                color: somoGanador
                    ? const Color(0xFFC8A860)
                    : const Color(0xFF506070),
                letterSpacing: 1.5)),
        content: Text(
            somoGanador
                ? 'Eres el último comandante en pie.\n¡El campo de batalla es tuyo!'
                : 'La partida ha terminado.\nUn rival ha conquistado todos los cuarteles.',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 10,
                color: somoGanador
                    ? const Color(0xFF6A8A50)
                    : const Color(0xFF506070),
                height: 1.7)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text('SALIR AL MENÚ',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    color: somoGanador
                        ? const Color(0xFFC8A860)
                        : const Color(0xFF506070))),
          ),
        ],
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 10,
              color: Colors.white,
              letterSpacing: 0.5)),
      backgroundColor:
          error ? const Color(0xFF7A1010) : const Color(0xFF1C3020),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();
    if (_error != null) {
      return _ErrorScreen(
        message: _error!,
        onRetry: () {
          setState(() {
            _error = null;
            _loading = true;
          });
          _loadGame();
        },
      );
    }

    // Celda visible para el jugador local: oculta las cartas invisibles del
    // rival también en el sidebar (las propias se conservan).
    final sidebarCelda = _sidebarCoord != null
        ? _boardState.celdaVisiblePara(_sidebarCoord!, _localPlayer.datos.uid)
        : null;
    final sidebarTerrain = (_sidebarRi != null && _sidebarCi != null)
        ? _config.terrain(_sidebarRi!, _sidebarCi!)
        : null;
    final destruidoAqui =
        _sidebarCoord != null && _boardState.esCuartelDestruido(_sidebarCoord!);
    // Obeliscos REALES asignados por el servidor (uid → coord). Antes se usaba
    // kObeliscoCoords (4 esquinas hardcodeadas de un 6×10), que en cualquier mapa
    // que no fuera el clásico marcaba celdas equivocadas como cuartel.
    final obeliscoCoordsReales = _obeliscosPorJugador.values.toSet();
    final isEnemySidebar = _sidebarCoord != null &&
        obeliscoCoordsReales.contains(_sidebarCoord) &&
        _sidebarCoord != _obeliscoLocal &&
        !destruidoAqui;
    final isObeliscoSidebar = _sidebarCoord != null &&
        obeliscoCoordsReales.contains(_sidebarCoord) &&
        !destruidoAqui;
    final String? selectedCoord =
        _inMoveMode ? _moveFromCoord : (_sidebarOpen ? _sidebarCoord : null);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1F35),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Deseleccionar carta / cancelar acción al tocar fuera ────
            // Esta capa va DETRÁS de todo (primer hijo del Stack). IMPORTANTE:
            // se mantiene SIEMPRE presente (aunque inactiva con IgnorePointer),
            // no de forma condicional. Si apareciera/desapareciera, cambiaría el
            // número de hijos del Stack y desplazaría la Column del tablero, con
            // lo que Flutter recrearía el BoardWidget y se perdería el zoom (bug:
            // al desplegar una carta o mover, el zoom saltaba al 100%). Con
            // IgnorePointer sólo intercepta toques cuando hay algo que cancelar:
            //   - Carta normal seleccionada en la mano → se deselecciona.
            //   - Carta/habilidad de acción en curso (esperando objetivo)
            //     → se cancela, igual que si no se hubiera pulsado nunca.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !(_selectedHandIndex != null || _inActionMode),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_inActionMode) {
                      _cancelarAccion();
                    } else {
                      setState(() => _selectedHandIndex = null);
                    }
                  },
                ),
              ),
            ),
            Column(
              children: [
                // ── Barra de partida: nombre + color asignado + menú ──
                // Único menú de la pantalla: jugadores, Cuartel/Informe/
                // Deshacer, y "Salir de la partida" siempre al final.
                PartidaTopBar(
                  nombrePartida: _currentLobby?.nombre ?? 'Partida',
                  colorAsignado: _colorDeUid(_localPlayer.datos.uid,
                      zonaFallback: _localPlayer.zona),
                  jugadores: _infoJugadoresHud(),
                  onSalir: _confirmExit,
                  puedeCuartel: !_estoyEliminado,
                  onCuartel: _abrirCuartel,
                  puedeInforme: _boardState.turnoActual > 1,
                  onInforme: _abrirInformeBatalla,
                  puedePuntuaciones: true,
                  onPuntuaciones: _abrirPuntuaciones,
                  puedeAlianza: _jugadoresEnPartida >= 4 && !_estoyEliminado,
                  onAlianza: _abrirAlianza,
                  propuestasAlianzaPendientes: _propuestasPendientes,
                  puedeDeshacer: _hayCambiosPendientes &&
                      !_yoCerreElTurno &&
                      !_estoyEliminado,
                  onDeshacer: _pedirDeshacer,
                ),
                // ── Volver a repartir (SOLO primer turno) ──
                if (_boardState.turnoActual == 1 &&
                    !_yoCerreElTurno &&
                    !_estoyEliminado)
                  Container(
                    color: const Color(0xF202050D),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Center(
                      child: GestureDetector(
                        onTap: _volverARepartir,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8A860).withOpacity(
                                _puedeVolverARepartir ? 0.15 : 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFC8A860).withOpacity(
                                  _puedeVolverARepartir ? 0.5 : 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh,
                                  size: 14,
                                  color: const Color(0xFFC8A860).withOpacity(
                                      _puedeVolverARepartir ? 1 : 0.4)),
                              const SizedBox(width: 8),
                              Text(
                                'VOLVER A REPARTIR',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'Cinzel',
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFC8A860).withOpacity(
                                      _puedeVolverARepartir ? 1 : 0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                _PhaseBanner(
                  handSelected: _selectedHandIndex != null,
                  inMoveMode: _inMoveMode,
                  obeliscoLocal: _obeliscoLocal,
                  moveCount: _moveCardIndices.length,
                ),
                Expanded(
                  child: BoardWidget(
                    key: _boardKey,
                    config: _config,
                    boardState: _boardState,
                    imagenMapa: _imagenMapa,
                    selectedCellCoord: selectedCoord,
                    highlightEmpty: _selectedHandIndex != null,
                    movableCoords: _highlightCoords,
                    deployCoords: _deployCoords,
                    obeliscoLocal: _obeliscoLocal,
                    obeliscoCoords: _obeliscosPorJugador.values.toSet(),
                    obeliscoColores: {
                      for (final e in _obeliscosPorJugador.entries)
                        e.value: (_playerColors[e.key] ?? Colors.white),
                    },
                    playerColors: _playerColors,
                    localPlayerUid: widget.localPlayerUid,
                    aliadosLocal: _aliadosLocal,
                    fantasmasAccion: _fantasmasAccion,
                    fantasmasRevision:
                        _yoCerreElTurno ? _revisionFantasmas : const [],
                    accionesRevision:
                        _yoCerreElTurno ? _revisionAcciones : const {},
                    onCellTap: _onCellTap,
                  ),
                ),
                if (_yoCerreElTurno)
                  _TurnWaitBanner(
                    modoTurno: _modoTurno,
                    cerradoPor: _cerradoPor.length,
                    totalJugadores: _jugadoresActivos,
                    fechaResolucionMs: _fechaResolucionMs,
                    onRefresh: () => _checkRefresh(),
                  ),
                // Banner eliminado (modo observador)
                if (_estoyEliminado)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    color: const Color(0xFF2A0505),
                    child: const Text('💀 ELIMINADO — Modo Observador',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 9,
                            color: Color(0xFFAA3030),
                            letterSpacing: 1)),
                  ),
                if (!_estoyEliminado)
                  BottomHudBar(
                    player: _localPlayer,
                    isMyTurn: !_yoCerreElTurno,
                    isSending: _isSendingTurn,
                    colorOverride: _colorDeUid(_localPlayer.datos.uid,
                        zonaFallback: _localPlayer.zona),
                    imagenPerfil: _localPlayer.datos.imagenPerfil,
                    // El pool de robo real es el mazo completo (8), no el
                    // sobrante tras la mano inicial.
                    mazoCount: _mazoCompleto.length,
                    onVerMazo: _mostrarMazoDisponible,
                    endTurnLabel: _isSendingTurn
                        ? 'ENVIANDO'
                        : _yoCerreElTurno
                            ? 'TURNO CERRADO'
                            : _modoTurno == ModoTurno.rapida
                                ? 'FIN TURNO (${_segundosRestantes}s)'
                                : 'FIN TURNO',
                    onEndTurn:
                        (_yoCerreElTurno || _isSendingTurn) ? null : _endTurn,
                  ),
                if (!_estoyEliminado)
                  HandWidget(
                    cartas: _hand,
                    selectedIndex: _selectedHandIndex,
                    onCardTap: _onHandCardTap,
                    energiesDisponibles: _localPlayer.puntos,
                    resolveEvolucion: _resolveEvolucion,
                    onSacrificar: _sacrificarCarta,
                    permiteSacrificio: !_yoCerreElTurno && !_estoyEliminado,
                  ),
              ],
            ),
            if (_sidebarOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeSidebar,
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned(
              top: 58,
              right: 0,
              bottom: _estoyEliminado ? 0 : 58 + 105,
              width: CellSidebar.width,
              child: CellSidebar(
                celda: sidebarCelda,
                coord: _sidebarCoord,
                terrain: sidebarTerrain,
                isOpen: _sidebarOpen,
                isEnemyObelisco: isEnemySidebar,
                isObelisco: isObeliscoSidebar,
                localUid: _localPlayer.datos.uid,
                playerColors: _playerColors,
                efectosCelda: _sidebarCoord != null
                    ? _boardState.getEfectosCelda(_sidebarCoord!)
                    : const [],
                onMoveSelected: _estoyEliminado ? (_) {} : _onMoveSelected,
                movedInstanceIds: _cartasQueSeMovieron,
                onUndoSelected: _estoyEliminado ? (_) {} : _undoMoveSelected,
                onClose: _closeSidebar,
                energiasDisponibles: _localPlayer.puntos,
                resolveEvolucion: _resolveEvolucion,
                onEvolucionar:
                    _estoyEliminado ? (_, __, ___) async {} : _evolucionarCarta,
                evolucionesPoseidas: _evolucionesPoseidas,
                turnoActual: _boardState.turnoActual, // NUEVO
                onLanzarHabilidad: // NUEVO
                    _estoyEliminado ? null : _iniciarAccionDesdeTablero,
                // Descarga: solo en el cuartel propio (sidebar lo restringe con
                // isObelisco && !isEnemyObelisco).
                onDescarga: (_estoyEliminado || _sidebarCoord == null)
                    ? null
                    : () => _toggleDescarga(_sidebarCoord!),
                descargaArmada: _sidebarCoord != null &&
                    _accionesPendientes
                        .any((a) => a.esDescarga && a.origen == _sidebarCoord),
                descargaCoste: kDescargaCoste,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PHASE BANNER
// ─────────────────────────────────────────────────────────────
class _PhaseBanner extends StatelessWidget {
  final bool handSelected;
  final bool inMoveMode;
  final String? obeliscoLocal;
  final int moveCount;

  const _PhaseBanner({
    required this.handSelected,
    required this.inMoveMode,
    required this.obeliscoLocal,
    required this.moveCount,
  });

  @override
  Widget build(BuildContext context) {
    String? msg;
    Color accent = const Color(0xFF506070);

    if (handSelected) {
      msg = '⚔  Desplegando en cuartel $obeliscoLocal';
      accent = const Color(0xFF4ABB58);
    } else if (inMoveMode) {
      msg =
          '↗  $moveCount ${moveCount == 1 ? 'carta' : 'cartas'} — elige destino (azul)';
      accent = const Color(0xFF40B0FF);
    }

    if (msg == null) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5),
      color: accent.withOpacity(0.10),
      child: Text(msg,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 9,
              color: accent,
              fontFamily: 'Cinzel',
              letterSpacing: 1.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BANNER: ESPERANDO A QUE OTROS CIERREN EL TURNO
// ─────────────────────────────────────────────────────────────
class _TurnWaitBanner extends StatefulWidget {
  final ModoTurno modoTurno;
  final int cerradoPor;
  final int totalJugadores;
  final int? fechaResolucionMs;
  final Future<void> Function()? onRefresh;

  const _TurnWaitBanner({
    required this.modoTurno,
    required this.cerradoPor,
    required this.totalJugadores,
    this.fechaResolucionMs,
    this.onRefresh,
  });

  @override
  State<_TurnWaitBanner> createState() => _TurnWaitBannerState();
}

class _TurnWaitBannerState extends State<_TurnWaitBanner> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing || widget.onRefresh == null) return;
    setState(() => _refreshing = true);
    await widget.onRefresh!();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.totalJugadores - widget.cerradoPor;
    final String msg;
    if (widget.modoTurno == ModoTurno.diario ||
        widget.modoTurno == ModoTurno.turno12h) {
      // Cierre real = fechaResolucion del servidor. En diario es 00:00 UTC; en
      // turno12h es la hora de resolución + 12 h (la calcula el servidor, así
      // que sin ese dato no hay fallback local fiable).
      final esDiario = widget.modoTurno == ModoTurno.diario;
      final ref = esDiario ? '(00:00 UTC)' : '(UTC +12 h)';
      final cierreMs = widget.fechaResolucionMs;
      final DateTime? cierre = cierreMs != null
          ? DateTime.fromMillisecondsSinceEpoch(cierreMs, isUtc: true)
          : (esDiario ? TurnService.proximoCierreUTC() : null);
      if (cierre == null) {
        msg = 'Esperando cierre del turno…';
      } else {
        final diff = cierre.difference(DateTime.now().toUtc());
        if (diff.isNegative) {
          msg = 'Cierre vencido $ref. Resolviendo…';
        } else {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          msg = 'Esperando. Cierre en ${h}h ${m}m $ref';
        }
      }
    } else {
      final suf = pending == 1 ? '' : 'es';
      msg = '$pending jugador$suf sin cerrar.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF0A2A0A),
      child: Row(children: [
        const Icon(Icons.hourglass_top, size: 12, color: Color(0xFF55FF70)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(msg,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFFCCFFCC),
                fontFamily: 'Cinzel',
                height: 1.5,
                letterSpacing: 0.3,
              )),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _refreshing ? null : _handleRefresh,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _refreshing
                  ? const Color(0xFF0A2A0A)
                  : const Color(0xFF0D3A1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _refreshing
                    ? const Color(0xFF1A4A2A)
                    : const Color(0xFF2A8040),
                width: 1,
              ),
            ),
            child: _refreshing
                ? const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF55FF70)),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 11, color: Color(0xFF55FF70)),
                      SizedBox(width: 4),
                      Text('ACTUALIZAR',
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 7,
                            letterSpacing: 1,
                            color: Color(0xFF55FF70),
                          )),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF0A1F35),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: Color(0xFFC8A860)),
          SizedBox(height: 16),
          Text('CARGANDO MAZO...',
              style: TextStyle(
                  color: Color(0xFF7A6040),
                  fontSize: 12,
                  letterSpacing: 3,
                  fontFamily: 'Cinzel')),
        ])),
      );
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorScreen({required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A1F35),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: Color(0xFFC04040)),
                const SizedBox(height: 18),
                Text(
                  message,
                  style: const TextStyle(
                      color: Color(0xFFC04040),
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      height: 1.7),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (onRetry != null)
                  GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC8A860).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFFC8A860).withOpacity(0.6),
                            width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 14, color: Color(0xFFC8A860)),
                          SizedBox(width: 8),
                          Text('REINTENTAR',
                              style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 11,
                                  letterSpacing: 2,
                                  color: Color(0xFFC8A860),
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('VOLVER',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 9,
                            letterSpacing: 2,
                            color: Color(0xFF506070))),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// NODO AUXILIAR PARA EL BFS DE MOVIMIENTO
// ─────────────────────────────────────────────────────────────
class _MoveNode {
  final String coord;
  final int steps;
  const _MoveNode(this.coord, this.steps);
}

// ─────────────────────────────────────────────────────────────
extension _StringExt on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

// ─────────────────────────────────────────────────────────────
// REFERENCIA A UNA CARTA PROPIA EN EL TABLERO
// Usado por _showCartaPropiaModal para elegir qué carta teletransportar.
// ─────────────────────────────────────────────────────────────
class _CartaPropiaRef {
  final String coord;
  final int indice;
  final CartaEnCelda carta;
  const _CartaPropiaRef({
    required this.coord,
    required this.indice,
    required this.carta,
  });
}

// ─────────────────────────────────────────────────────────────
// TARJETA DEL MAZO DISPONIBLE (slider del HUD inferior)
// ─────────────────────────────────────────────────────────────
class _MazoCard extends StatelessWidget {
  final CartaModel carta;
  final VoidCallback onTap;
  const _MazoCard({required this.carta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: const Color(0xFF0C1A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF78591E).withOpacity(0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: carta.imagen.trim().isNotEmpty
                  ? Image.network(
                      carta.imagen,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFF081019),
                        child: Icon(Icons.shield_outlined,
                            size: 26, color: Color(0xFF2A3A4A)),
                      ),
                    )
                  : const ColoredBox(
                      color: Color(0xFF081019),
                      child: Icon(Icons.shield_outlined,
                          size: 26, color: Color(0xFF2A3A4A)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    carta.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'Cinzel',
                      color: Color(0xFFE0D8C0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '⚔${carta.fuerza}  🛡${carta.defensa}  Ø${carta.coste}',
                    style: const TextStyle(
                      fontSize: 8,
                      fontFamily: 'Cinzel',
                      color: Color(0xFF6A7A8A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
