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
import '../services/combate_service.dart';
import 'informe_batalla_screen.dart';
import 'revision_turno_screen.dart';
import '../models/lobby_model.dart';
import '../widgets/board_widget.dart';
import '../widgets/cell_sidebar.dart';
import '../widgets/cell_widget.dart' show kObeliscoCoords;
import '../widgets/hand_widget.dart';
import '../widgets/player_hud.dart';
import '../models/accion_pendiente.dart';
import '../models/efecto_estado.dart';
import '../models/habilidad_model.dart';
import '../services/accion_controller.dart';
import '../services/habilidad_service.dart';
import 'cuartel_screen.dart';

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

class _GameScreenState extends State<GameScreen> {
  late GameConfig _config;
  BoardState _boardState = const BoardState();

  late PlayerSession _localPlayer;
  late PlayerSession _opponentPlayer;

  String? _obeliscoLocal;
  String? _obeliscoOponente;

  /// Lee la coord del rayo de farmeo del doc/estado de la partida.
  String? _rayoCoordFromData(Map<String, dynamic> data) {
    final r = data['rayo'];
    if (r is Map && r['coord'] is String) return r['coord'] as String;
    final rc = data['rayoCoord'];
    return rc is String ? rc : null;
  }

  /// uid → color del obelisco asignado (se carga desde Firestore)
  Map<String, Color> _playerColors = {};

  /// uid → coord del obelisco asignado (para lógica de conquista)
  Map<String, String> _obeliscosPorJugador = {};

  // ── Modo turno ────────────────────────────────────────────
  ModoTurno _modoTurno = ModoTurno.rapida;
  List<String> _cerradoPor = [];
  int _jugadoresEnPartida = 2;
  int _segundosRestantes = 30;
  bool _timerActivo = false;

  bool _resolviendo = false;
  bool _isSendingTurn = false;
  bool _sondeoActivo = false;
  final WarZeroApi _api = WarZeroApi();

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
  String? _lastRayoCoord; // ← nuevo
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

  /// Última carta robada (para mostrarla en el informe del turno).
  CartaModel? _ultimaCartaRepartida;
  int? _selectedHandIndex;

  /// Ejército del jugador local (para filtrar especiales en el cuartel).
  int? _miEjercitoId;

  /// IDs de cartas especiales ya compradas por el jugador esta partida
  /// (deshabilitadas para futuras compras suyas).
  final Set<String> _especialesCompradas = {};

  // ── Sidebar ───────────────────────────────────────────────
  String? _sidebarCoord;
  int? _sidebarRi;
  int? _sidebarCi;
  bool _sidebarOpen = false;

  // ── Modo movimiento ───────────────────────────────────────
  String? _moveFromCoord;
  List<int> _moveCardIndices = [];
  Set<String> _movableCoords = {};
  bool get _inMoveMode => _moveFromCoord != null;
// ── Modo acción / habilidad ─────────────────────────────────
  late AccionController _accionController;

  /// Acciones declaradas en este turno (se envían al cerrar turno).
  final List<AccionPendiente> _accionesPendientes = [];

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
  final Set<String> _cartasMovidasEsteTurno = {};

  /// Exclusión mutua por turno: si mueves una carta no puedes evolucionar, y si
  /// evolucionas no puedes mover. (El despliegue desde la mano no cuenta como
  /// movimiento a estos efectos.)
  bool _haMovidoEsteTurno = false;
  final Set<String> _cartasEvolucionadasEsteTurno = {};
  bool get _haEvolucionadoEsteTurno => _cartasEvolucionadasEsteTurno.isNotEmpty;

  bool get _hayCambiosPendientes =>
      _cartasMovidasEsteTurno.isNotEmpty || _accionesPendientes.isNotEmpty;

  // ── Energía snapshot al inicio de cada turno ──────────────
  /// Energías del jugador al comenzar el turno (para restaurar en undo).
  int _puntosInicial = 0;

  /// Energía total gastada en despliegues este turno (para restaurar en Firestore).
  int _energiaGastadaDespliegue = 0;

  bool _loading = true;
  String? _error;

  // ── Tamaño inicial de la mano al arrancar la partida ───────
  static const int _initialHandSize = 5;

  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _config = GameConfig.forPlayerCount(widget.playerCount);
    _accionController = AccionController(config: _config);
    _setupPlayers();
    // Despierta el servidor de Render (free tier duerme tras inactividad) en
    // paralelo, para que esté listo cuando _loadGame llame a entrar().
    if (widget.lobbyId != null) {
      _api.despertar();
    }
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
    if (_haMovidoEsteTurno) {
      _toast('Este turno ya has movido: no puedes evolucionar.', error: true);
      return;
    }

    final celda = _boardState.getCelda(coord);
    if (indice < 0 || indice >= celda.cartas.length) return;

    final original = celda.cartas[indice];
    if (original.ownerUid != _localPlayer.datos.uid) {
      _toast('No puedes evolucionar cartas ajenas', error: true);
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
      _cartasMovidasEsteTurno.add(evolucion.id);
      _cartasEvolucionadasEsteTurno.add(evolucion.id);
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
          _cartasMovidasEsteTurno.remove(evolucion.id);
          _cartasEvolucionadasEsteTurno.remove(evolucion.id);
        });
        _toast('Error al evolucionar. Inténtalo de nuevo.', error: true);
        return;
      }
    }

    _toast('${original.carta.nombre} → ${evolucion.nombre}  (-$coste⚡)');
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
      if (c != null) result.add(c);
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

      setState(() => _config = _config.withTerrain(terreno));
    } catch (_) {}
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

      debugPrint('[WZ][ejercito] seleccionado=$ejercitoId '
          'cartasMazo=${_mazoCompleto.length} '
          'ejercitosEnMazo=${_mazoCompleto.map((c) => c.ejercito).toSet()}');

      if (lobby != null) {
        // ── 4. Configurar estado del lobby ────────────────────────
        setState(() {
          _modoTurno = lobby!.modoTurno;
          _jugadoresEnPartida = lobby.jugadores.length;
          _cerradoPor = List<String>.from(lobby.cerradoPor);
        });

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
        obeliscosData.forEach((uid, coord) {
          colors[uid] = _obeliscoColor(coord as String);
          obeliscosMap[uid] = coord;
        });
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
          _lastCombateLog = loadedCombateLog;
          _lastMovimientosLog = loadedMovLog;
          _lastFarmeoLog = loadedFarmeoLog; // ← nuevo
          _lastAccionesLog = loadedAccionesLog; // ← nuevo
          _lastRayoCoord = _rayoCoordFromData(data); // ← nuevo
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

        // ── 5. Restaurar tablero ──────────────────────────────────
        if (data.containsKey('tablero')) {
          final tableroRaw = TurnService.parseTablero(data);
          var restoredBoard = const BoardState();
          tableroRaw.forEach((coord, cartas) {
            for (final c in cartas) {
              restoredBoard = restoredBoard.placeCarta(
                coord,
                CartaEnCelda(
                  carta: _cartaFromMap(c),
                  ownerUid: c['ownerUid'] as String? ?? '',
                  ownerZone: c['ownerZone'] as String? ?? '',
                ),
              );
            }
          });
          setState(() {
            _boardState = restoredBoard
                .copyWith(turnoActual: lobby!.turnoActual)
                .withRayo(_rayoCoordFromData(data));
          });
        }

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
          _boardStateInicial = _boardState;
          _handInicial = List.from(manoFinal);
          _cartasMovidasEsteTurno.clear();
          _haMovidoEsteTurno = false;
          _cartasEvolucionadasEsteTurno.clear();
          _energiaGastadaDespliegue = 0;
        });
        _turnoConfirmadoStream = lobby.turnoActual;
        // No repetir informes de turnos ya resueltos al (re)entrar: solo se
        // mostrará el informe de la PRÓXIMA resolución en adelante.
        _informeMostradoTurno = lobby.turnoActual - 1;
        _cargaCompletada = true;

        if (lobby.modoTurno == ModoTurno.rapida && lobby.cerradoPor.isEmpty) {
          _startTimer();
        }
        _iniciarPolling();
        // El obelisco lo asigna el servidor en POST /warzero/entrar; los datos
        // ya vienen en `data['obeliscos']` y se aplicaron arriba.

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
        _haMovidoEsteTurno = false;
        _cartasEvolucionadasEsteTurno.clear();
        _puntosInicial = 0;
        _energiaGastadaDespliegue = 0;
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

  /// Abre el informe de batalla del último turno resuelto, si aún no se mostró.
  /// Es idempotente: usa `_informeMostradoTurno` como guarda, así puede llamarse
  /// en cada snapshot sin abrir el informe dos veces. Independiente del avance
  /// del tablero, para que no se lo "coma" otra ruta que suba el turno antes.
  void _maybeMostrarInforme(int turnoActual, Map<String, dynamic> data) {
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
    final rayoCoord = _rayoCoordFromData(data); // ← nuevo
    final historialData = parseLista(data['historialCombates']);

    _lastCombateLog = combateLog;
    _lastMovimientosLog = movLog;
    _lastFarmeoLog = farmeoLog; // ← nuevo
    _lastAccionesLog = accionesLog; // ← nuevo
    _lastRayoCoord = rayoCoord; // ← nuevo
    _historialCombates = historialData;
    _informeMostradoTurno = turnoInforme;
    _informeAbierto = true;

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
          rayoCoord: rayoCoord, // ← nuevo
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
      obelData.forEach((uid, coord) {
        streamColors[uid] = _obeliscoColor(coord as String);
        streamObeliscos[uid] = coord;
      });

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
        _hostUid = lobby.hostUid;
        _jugadoresEliminados = nuevosEliminados;
        _estoyEliminado = ahoraEliminado;
        _juegoTerminado = juegoTerminado;
        if (juegoTerminado) _ganadorUid = lobby.ganadorUid;
      });

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
        var restoredState = const BoardState();
        tableroRaw.forEach((coord, cartas) {
          for (final c in cartas) {
            try {
              restoredState = restoredState.placeCarta(
                coord,
                CartaEnCelda(
                  carta: _cartaFromMap(c),
                  ownerUid: c['ownerUid'] as String? ?? '',
                  ownerZone: c['ownerZone'] as String? ?? '',
                ),
              );
            } catch (e) {
              debugPrint('[WZ][stream][ERROR] carta mal formada en $coord: '
                  '$e\n  carta=$c');
            }
          }
        });
        _turnoConfirmadoStream = lobby.turnoActual;

        // Robar 1 carta al azar del mazo restante (si no está eliminado)
        final robo = _calcularRoboNuevoTurno();
        final cartaRobada = robo.carta;
        final nuevoMazo = robo.mazo;
        final nuevaMano = robo.mano;
        _ultimaCartaRepartida = cartaRobada;

        setState(() {
          _boardState = restoredState
              .copyWith(turnoActual: lobby.turnoActual)
              .withRayo(_rayoCoordFromData(data));
          _cerradoPor = [];
          _resolviendo = false;
          _isSendingTurn = false;
          _cargaCompletada = true;
          _boardStateInicial = restoredState
              .copyWith(turnoActual: lobby.turnoActual)
              .withRayo(_rayoCoordFromData(data));
          _hand = nuevaMano;
          _mazoRestante = nuevoMazo;
          _handInicial = List.from(nuevaMano);
          _cartasMovidasEsteTurno.clear();
          _haMovidoEsteTurno = false;
          _cartasEvolucionadasEsteTurno.clear();
          _energiaGastadaDespliegue = 0;
        });

        // Persistir mano + mazo tras robar la carta
        _saveHandAndDeck();

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

        if (cartaRobada != null) {
          _toast('🃏 +1 carta para el nuevo turno');
        }

        // El informe lo gestiona _maybeMostrarInforme (llamado antes en este
        // mismo listener), de forma independiente al avance del tablero.
        return;
      }

      // La resolución la hace el servidor cuando cierra el último jugador; el
      // stream entregará el turno avanzado y este listener lo aplicará arriba.
      // (Antes aquí se llamaba a _resolverTurno en el cliente.)
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
    _pollEstado(); // primera lectura inmediata
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
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
    _segundosRestantes = 30;
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
    _pollTimer?.cancel();
    _timerActivo = false;
    super.dispose();
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
        if (nCoord != from && _config.canLand(nCoord, tipo)) {
          result.add(nCoord);
        }
        if (newSteps < mov) {
          queue.add(_MoveNode(nCoord, newSteps));
        }
      }
    }
    return result;
  }

  int _tipoEfectivo(List<int> validIndices, CeldaState celda) {
    final tipos = validIndices.map((i) => celda.cartas[i].carta.tipo).toSet();
    if (tipos.length == 1) return tipos.first;
    if (tipos.contains(1) && tipos.contains(3)) return -1;
    if (tipos.contains(1)) return 1;
    if (tipos.contains(3)) return 3;
    return 2;
  }

  // ─────────────────────────────────────────────────────────
  // LÓGICA DE INTERACCIÓN
  // ─────────────────────────────────────────────────────────

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
          .any((c) => _cartasMovidasEsteTurno.contains(c.carta.id));
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

    // ── Comprobar coste de energía ────────────────────────────
    final coste = carta.coste;
    if (_localPlayer.puntos < coste) {
      _toast(
        '⚡ Energía insuficiente: necesitas $coste, tienes ${_localPlayer.puntos}',
        error: true,
      );
      return;
    }

    setState(() {
      _boardState = _boardState.placeCarta(
        coord,
        CartaEnCelda(
            carta: carta,
            ownerUid: _localPlayer.datos.uid,
            ownerZone: _localPlayer.zona),
      );
      _hand = List.from(_hand)..removeAt(_selectedHandIndex!);
      _selectedHandIndex = null;
      if (carta.esEstatica) {
        _cartasMovidasEsteTurno.add(carta.id);
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
      _toast('${carta.nombre} desplegada  (-$coste ⚡)');
    }
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
      ),
    ));
  }

  /// Compra una carta especial: descuenta Energies, la coloca en el cuartel y
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
    setState(() {
      _boardState = _boardState.placeCarta(
        cuartel,
        CartaEnCelda(
          carta: carta,
          ownerUid: _localPlayer.datos.uid,
          ownerZone: _localPlayer.zona,
        ),
      );
      _localPlayer.puntos -= coste;
      _especialesCompradas.add(carta.id);
      // Recién comprada: no puede moverse este turno.
      _cartasMovidasEsteTurno.add(carta.id);
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
            _cartasMovidasEsteTurno.remove(carta.id);
            final celda = _boardState.getCelda(cuartel);
            final idx = celda.cartas.lastIndexWhere((c) =>
                c.carta.id == carta.id && c.ownerUid == _localPlayer.datos.uid);
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

    return CompraResult(
      ok: true,
      mensaje: '${carta.nombre} comprada y desplegada en tu cuartel.',
      energiasRestantes: _localPlayer.puntos,
    );
  }

  void _onMoveSelected(List<int> indices) {
    if (_sidebarCoord == null || indices.isEmpty) return;
    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }
    if (_haEvolucionadoEsteTurno) {
      _toast('Este turno ya has evolucionado: no puedes mover.', error: true);
      return;
    }
    final celda = _boardState.getCelda(_sidebarCoord!);
    final validIndices = indices
        .where((i) =>
            i < celda.cartas.length &&
            celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
            !_cartasMovidasEsteTurno.contains(celda.cartas[i].carta.id) &&
            !celda.cartas[i].carta.esEstatica &&
            !celda.cartas[i].paralizado)
        .toList();

    if (validIndices.isEmpty) {
      final algunaParalizada = indices.any((i) =>
          i < celda.cartas.length &&
          celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
          celda.cartas[i].paralizado);
      if (algunaParalizada) {
        _toast('❄ Cartas paralizadas: no pueden moverse este turno',
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
          _cartasMovidasEsteTurno.contains(celda.cartas[i].carta.id));
      if (alreadyMoved) {
        _toast('Estas cartas ya se movieron este turno', error: true);
      } else {
        _toast('No puedes mover cartas de otros jugadores', error: true);
      }
      return;
    }

    final minMov = validIndices
        .map((i) => celda.cartas[i].carta.movimiento)
        .reduce((a, b) => a < b ? a : b);
    final tipo = _tipoEfectivo(validIndices, celda);
    if (tipo == -1) {
      _toast('No puedes mover unidades terrestres y marinas juntas',
          error: true);
      return;
    }
    setState(() {
      _moveFromCoord = _sidebarCoord;
      _moveCardIndices = validIndices;
      _movableCoords = _computeMovableBFS(_sidebarCoord!, minMov, tipo);
      _sidebarOpen = false;
    });
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
        _cartasMovidasEsteTurno.add(c.carta.id);
      }
      _haMovidoEsteTurno = true;
      _boardState = st;
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
      _sidebarCoord = dest;
      _sidebarRi = ri;
      _sidebarCi = ci;
      _sidebarOpen = true;
    });
  }

  void _cancelMoveMode() {
    setState(() {
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
    });
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
    if (_localPlayer.puntos < carta.costeHabilidad) {
      _toast(
          'Energías insuficientes (${_localPlayer.puntos} / ${carta.costeHabilidad}).',
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

    setState(() {
      _selectedHandIndex = null;
      _cancelMoveMode();
      _sidebarOpen = false;
      _accionController.iniciarDesdeCartaDeTablero(
        cartaEnCelda: carta,
        coord: coord,
        indiceCelda: indiceCelda,
        obeliscosPorJugador: _obeliscosPorJugador,
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
    // Lista de candidatos: todas las cartas propias del jugador local
    // en el tablero. Se identifican por (coord, indice).
    final candidatos = <_CartaPropiaRef>[];
    _boardState.celdas.forEach((coord, celda) {
      for (int i = 0; i < celda.cartas.length; i++) {
        final c = celda.cartas[i];
        // Las cartas estáticas no pueden teletransportarse (mov 0).
        if (c.carta.esEstatica) continue;
        if (c.ownerUid == _localPlayer.datos.uid) {
          candidatos.add(_CartaPropiaRef(coord: coord, indice: i, carta: c));
        }
      }
    });

    if (candidatos.isEmpty) {
      _toast('No tienes cartas en el tablero para teletransportar.',
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

    setState(() {
      _accionesPendientes.add(accion);
      _localPlayer.puntos -= accion.costePagado;

      // Si es carta de acción: descartar de la mano.
      if (controller.esCartaDeAccion && controller.indiceMano != null) {
        final idx = controller.indiceMano!;
        if (idx >= 0 && idx < _hand.length) {
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

  void _undoCambios() {
    // Energía persistida en el servidor este turno (despliegues). El stream
    // trae el valor ya reducido, así que hay que devolverla explícitamente o
    // las energías se quedarían gastadas tras deshacer.
    final energiaADevolver = _energiaGastadaDespliegue;

    setState(() {
      _boardState = _boardStateInicial;
      _hand = List.from(_handInicial);
      _cartasMovidasEsteTurno.clear();
      _haMovidoEsteTurno = false;
      _cartasEvolucionadasEsteTurno.clear();
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
      _selectedHandIndex = null;
      _sidebarOpen = false;
      _sidebarCoord = null;
      _accionController.cancelar();
      _accionesPendientes.clear();
      // Restaurar energías locales al snapshot de inicio de turno (incluye el
      // coste de acciones, que no se persiste hasta cerrar el turno).
      _localPlayer.puntos = _puntosInicial;
      _energiaGastadaDespliegue = 0;
    });

    // Revertir en el servidor el gasto de despliegues persistido este turno.
    if (widget.lobbyId != null && energiaADevolver > 0) {
      _api
          .actualizarStats(
            lobbyId: widget.lobbyId!,
            uid: widget.localPlayerUid,
            energiesDelta: energiaADevolver,
          )
          .catchError((_) => null);
    }

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
        await _api.actualizarStats(
          lobbyId: widget.lobbyId!,
          uid: widget.localPlayerUid,
          energiesDelta: recompensa,
          mano: _hand.map((c) => c.id).toList(),
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

    _toast('${carta.nombre} sacrificada  (+$recompensa ⚡)');
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
    final result = <String, List<Map<String, dynamic>>>{};
    _boardState.celdas.forEach((coord, celda) {
      final misCartas = celda.cartas
          .where((c) => c.ownerUid == _localPlayer.datos.uid)
          .map((c) {
        final carta = c.carta;
        return <String, dynamic>{
          'id': carta.id,
          'Nombre': carta.nombre,
          'Ejercito': carta.ejercito,
          'Fuerza': carta.fuerza,
          'Defensa': carta.defensa,
          'Coste': carta.coste,
          'IdHabilidad': carta.idHabilidad,
          'Movimiento': carta.movimiento,
          'Tipo': carta.tipo,
          'IdEvolucion': carta.idEvolucion,
          'Evolucion': carta.evolucion,
          'Condicion': carta.condicion.value,
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
      }).toList();
      if (misCartas.isNotEmpty) result[coord] = misCartas;
    });
    return result;
  }

  Future<void> _cerrarTurno() async {
    if (_yoCerreElTurno || _isSendingTurn || _estoyEliminado) return;
    setState(() {
      _isSendingTurn = true;
      _selectedHandIndex = null;
      _cancelMoveMode();
      _sidebarOpen = false;
      _timerActivo = false;
    });

    if (widget.lobbyId != null) {
      final turnService = TurnService();
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
      // Persistir mano + mazo al cerrar turno
      _saveHandAndDeck();

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

        // Robar 1 carta al azar para el nuevo turno.
        final robo = _calcularRoboNuevoTurno();
        _ultimaCartaRepartida = robo.carta;

        setState(() {
          _boardState = restored
              .copyWith(turnoActual: turnoActual)
              .withRayo(_rayoCoordFromData(estado));
          _cerradoPor = [];
          _isSendingTurn = false;
          _cargaCompletada = true;
          _boardStateInicial = restored
              .copyWith(turnoActual: turnoActual)
              .withRayo(_rayoCoordFromData(estado));
          _hand = robo.mano;
          _mazoRestante = robo.mazo;
          _handInicial = List.from(robo.mano);
          _cartasMovidasEsteTurno.clear();
          _haMovidoEsteTurno = false;
          _cartasEvolucionadasEsteTurno.clear();
          // Las acciones (veneno, disparo, teletransporte…) pertenecían al
          // turno que acaba de resolverse; hay que descartarlas o se
          // reenviarían cada turno (p. ej. el veneno se refrescaría a 3
          // indefinidamente y nunca desaparecería de la celda).
          _accionesPendientes.clear();
          _accionController.cancelar();
          _energiaGastadaDespliegue = 0;
        });

        // Persistir mano + mazo tras robar.
        if (robo.carta != null) _saveHandAndDeck();

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
        if (robo.carta != null) {
          _toast('🃏 +1 carta para el nuevo turno');
        }

        debugPrint('[WZ][estado] tablero aplicado, turno=$turnoActual '
            'robo=${robo.carta?.nombre ?? 'sin carta'}');
        return true;
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

    final sidebarCelda =
        _sidebarCoord != null ? _boardState.getCelda(_sidebarCoord!) : null;
    final sidebarTerrain = (_sidebarRi != null && _sidebarCi != null)
        ? _config.terrain(_sidebarRi!, _sidebarCi!)
        : null;
    final isEnemySidebar = _sidebarCoord != null &&
        kObeliscoCoords.contains(_sidebarCoord) &&
        _sidebarCoord != _obeliscoLocal;
    final isObeliscoSidebar =
        _sidebarCoord != null && kObeliscoCoords.contains(_sidebarCoord);
    final String? selectedCoord =
        _inMoveMode ? _moveFromCoord : (_sidebarOpen ? _sidebarCoord : null);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1F35),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                TopHudBar(
                    player: _opponentPlayer,
                    turno: _boardState.turnoActual,
                    onBack: _confirmExit),
                _PhaseBanner(
                  handSelected: _selectedHandIndex != null,
                  inMoveMode: _inMoveMode,
                  obeliscoLocal: _obeliscoLocal,
                  moveCount: _moveCardIndices.length,
                ),
                Expanded(
                  child: BoardWidget(
                    config: _config,
                    boardState: _boardState,
                    selectedCellCoord: selectedCoord,
                    highlightEmpty: _selectedHandIndex != null,
                    movableCoords: _highlightCoords,
                    obeliscoLocal: _obeliscoLocal,
                    playerColors: _playerColors,
                    localPlayerUid: widget.localPlayerUid,
                    onCellTap: _onCellTap,
                  ),
                ),
                if (_yoCerreElTurno)
                  _TurnWaitBanner(
                    modoTurno: _modoTurno,
                    cerradoPor: _cerradoPor.length,
                    totalJugadores: _jugadoresActivos,
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
            // ── Menú de acciones (Cuartel / Informe / Deshacer) ──
            // Un único botón desplegable que sustituye a los antiguos botones
            // sueltos (que se pisaban entre sí). El contador del mazo
            // (_DeckCounter) se elimina: ya no hay número fijo de cartas.
            Positioned(
              left: 10,
              bottom: _estoyEliminado ? 8 : 58 + 105 + 6,
              child: _GameActionsMenu(
                puedeCuartel: !_estoyEliminado,
                onCuartel: _abrirCuartel,
                puedeInforme: _boardState.turnoActual > 1,
                onInforme: () {
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
                      farmeoLog: _lastFarmeoLog, // ← nuevo
                      accionesLog: _lastAccionesLog, // ← nuevo
                      rayoCoord: _lastRayoCoord, // ← nuevo
                    ),
                  ))
                      .whenComplete(() {
                    _informeAbierto = false;
                    _abrirRevisionTurno(
                        turnoRevisar: _boardState.turnoActual - 1);
                  });
                },
                puedeDeshacer: _hayCambiosPendientes &&
                    !_yoCerreElTurno &&
                    !_estoyEliminado,
                onDeshacer: _undoCambios,
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
                onMoveSelected: _estoyEliminado ? (_) {} : _onMoveSelected,
                onClose: _closeSidebar,
                energiasDisponibles: _localPlayer.puntos,
                resolveEvolucion: _resolveEvolucion,
                onEvolucionar:
                    _estoyEliminado ? (_, __, ___) async {} : _evolucionarCarta,
                turnoActual: _boardState.turnoActual, // NUEVO
                onLanzarHabilidad: // NUEVO
                    _estoyEliminado ? null : _iniciarAccionDesdeTablero,
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
  final Future<void> Function()? onRefresh;

  const _TurnWaitBanner({
    required this.modoTurno,
    required this.cerradoPor,
    required this.totalJugadores,
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
    if (widget.modoTurno == ModoTurno.diario) {
      final cierre = TurnService.proximoCierreUTC();
      final diff = cierre.difference(DateTime.now().toUtc());
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      msg = 'Esperando. Cierre: ${h}h ${m}m (12:00 UTC)';
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
// MENÚ DE ACCIONES (Cuartel / Informe / Deshacer cambios)
// Un único disparador que despliega los 3, habilitados o no.
// ─────────────────────────────────────────────────────────────
class _GameActionsMenu extends StatefulWidget {
  final bool puedeCuartel;
  final VoidCallback onCuartel;

  final bool puedeInforme;
  final VoidCallback onInforme;

  final bool puedeDeshacer;
  final VoidCallback onDeshacer; // se llama TRAS confirmar

  const _GameActionsMenu({
    required this.puedeCuartel,
    required this.onCuartel,
    required this.puedeInforme,
    required this.onInforme,
    required this.puedeDeshacer,
    required this.onDeshacer,
  });

  @override
  State<_GameActionsMenu> createState() => _GameActionsMenuState();
}

class _GameActionsMenuState extends State<_GameActionsMenu> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);
  void _close() => setState(() => _open = false);

  void _pedirDeshacer() {
    _close();
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
      if (ok == true) widget.onDeshacer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_open) ...[
          _MenuItem(
            icon: Icons.castle,
            label: 'CUARTEL',
            color: const Color(0xFFC8A860),
            enabled: widget.puedeCuartel,
            onTap: () {
              _close();
              widget.onCuartel();
            },
          ),
          const SizedBox(height: 6),
          _MenuItem(
            icon: Icons.history,
            label: 'INFORME',
            color: const Color(0xFF6AAAD0),
            enabled: widget.puedeInforme,
            onTap: () {
              _close();
              widget.onInforme();
            },
          ),
          const SizedBox(height: 6),
          _MenuItem(
            icon: Icons.undo,
            label: 'DESHACER CAMBIOS',
            color: const Color(0xFFFF8080),
            enabled: widget.puedeDeshacer,
            onTap: _pedirDeshacer,
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xCC0D1E30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A5A7A), width: 1.2),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_open ? Icons.close : Icons.menu,
                    size: 14, color: const Color(0xFFC8A860)),
                const SizedBox(width: 6),
                const Text('ACCIONES',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 9,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC8A860))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : const Color(0xFF3A4A5A);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 168,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xEE0A1626),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.withOpacity(0.7), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: c),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: c)),
            ],
          ),
        ),
      ),
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
