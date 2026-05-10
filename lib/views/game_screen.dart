// lib/views/game_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:warzero/models/mazo_model.dart';
import '../models/carta_model.dart';
import '../models/game_config.dart';
import '../models/board_state.dart';
import '../models/jugador_model.dart';
import '../services/mazo_service.dart';
import '../services/lobby_service.dart';
import '../services/mapa_service.dart';
import '../services/turn_service.dart';
import '../services/combate_service.dart';
import 'informe_batalla_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lobby_model.dart';
import '../widgets/board_widget.dart';
import '../widgets/cell_sidebar.dart';
import '../widgets/cell_widget.dart' show kObeliscoCoords;
import '../widgets/hand_widget.dart';
import '../widgets/player_hud.dart';

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

  /// uid → color del obelisco asignado (se carga desde Firestore)
  Map<String, Color> _playerColors = {};

  // ── Modo turno ────────────────────────────────────────────
  ModoTurno _modoTurno = ModoTurno.rapida;
  List<String> _cerradoPor = [];
  int _jugadoresEnPartida = 2;
  int _segundosRestantes = 30;
  bool _timerActivo = false;

  /// Guard para evitar llamar _resolverTurno más de una vez por turno.
  /// Se resetea cuando llega el nuevo turno desde Firestore.
  bool _resolviendo = false;

  /// True mientras se envía el turno.
  bool _isSendingTurn = false;

  /// Último informe de batalla (combates y movimientos del turno anterior)
  List<Map<String, dynamic>> _lastCombateLog = [];
  List<Map<String, dynamic>> _lastMovimientosLog = [];
  LobbyModel? _currentLobby;
  List<Map<String, dynamic>> _historialCombates = [];

  /// Último turno cuyo informe ya se ha auto-mostrado al jugador local.
  /// Evita que cada nuevo snapshot de Firestore vuelva a apilar el mismo
  /// informe encima del que ya está abierto.
  int _informeMostradoTurno = 0;

  /// True mientras el InformeBatallaScreen está abierto en la pila local.
  /// Si está abierto y llega un turno nuevo, NO se auto-pushea el siguiente
  /// informe (para no pisar lo que el usuario está leyendo). Los datos sí se
  /// actualizan en _lastCombateLog/_lastMovimientosLog para que el botón
  /// del tablero muestre el último al cerrar el actual.
  bool _informeAbierto = false;
  String _hostUid =
      ''; // guardado del stream para no necesitar red en checkRefresh

  /// True solo después de que _loadGame termina completamente.
  /// Evita que el stream de lobby dispare lógica antes de que el estado
  /// inicial esté listo (problema en Pixel 9 con caché de Firestore).
  bool _cargaCompletada = false;

  /// Último número de turno que el STREAM de Firestore confirmó y aplicó.
  /// Independiente de _boardState.turnoActual para que el host (que actualiza
  /// _boardState localmente en _resolverTurno) también reciba la sincronización
  /// del tablero definitivo cuando llega el snapshot de Firestore.
  int _turnoConfirmadoStream = 0;

  bool get _yoCerreElTurno => _cerradoPor.contains(widget.localPlayerUid);
  bool get _esperandoOtros =>
      _yoCerreElTurno && _cerradoPor.length < _jugadoresEnPartida;
  bool get _todosCerraronTurno => _cerradoPor.length >= _jugadoresEnPartida;

  // ── Mano ──────────────────────────────────────────────────
  List<CartaModel> _hand = [];
  int? _selectedHandIndex;

  // ── Sidebar ───────────────────────────────────────────────
  String? _sidebarCoord;
  int? _sidebarRi;
  int? _sidebarCi;
  bool _sidebarOpen = false;

  // ── Modo movimiento ───────────────────────────────────────
  /// Celda de origen desde la que se van a mover cartas
  String? _moveFromCoord;

  /// Índices de las cartas seleccionadas en _moveFromCoord
  List<int> _moveCardIndices = [];

  /// Celdas alcanzables (azul) basadas en min(movimiento) + terreno
  Set<String> _movableCoords = {};

  bool get _inMoveMode => _moveFromCoord != null;

  // ── Snapshot inicial del turno (estado Firebase) ──────────
  BoardState _boardStateInicial = const BoardState();
  List<CartaModel> _handInicial = [];

  /// IDs de cartas que ya se han movido o colocado este turno.
  final Set<String> _cartasMovidasEsteTurno = {};

  bool get _hayCambiosPendientes => _cartasMovidasEsteTurno.isNotEmpty;

  bool _loading = true;
  String? _error;

  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _config = GameConfig.forPlayerCount(widget.playerCount);
    _setupPlayers();
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

  Future<void> _assignObeliscos() async {
    final coords = kObeliscoCoords.toList();

    if (widget.lobbyId != null) {
      final service = LobbyService();
      final assigned = await service.assignObeliscoIfNeeded(
        lobbyId: widget.lobbyId!,
        uid: widget.localPlayerUid,
        allCoords: coords,
      );
      final all = await service.getObeliscos(widget.lobbyId!);
      if (!mounted) return;
      setState(() {
        _obeliscoLocal = assigned;
        _obeliscoOponente = all.entries
            .firstWhere((e) => e.key != widget.localPlayerUid,
                orElse: () => const MapEntry('', ''))
            .value
            .nullIfEmpty;
      });
    } else {
      coords.shuffle(math.Random());
      setState(() {
        _obeliscoLocal = coords[0];
        _obeliscoOponente = coords[1];
      });
    }
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

// ── Resolver carta de evolución desde Cartas/{id} ─────────
  Future<CartaModel?> _resolveEvolucion(String idEvolucion) async {
    if (idEvolucion.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Cartas')
          .doc(idEvolucion)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!doc.exists) return null;
      return CartaModel.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  // ── Evolucionar una carta en una celda ────────────────────
  /// Sustituye la carta en [coord][indice] por [evolucion], descuenta el
  /// coste de las energías del jugador local (statsPartida.{uid}.energies)
  /// y persiste la deducción en Firestore. La carta evolucionada viaja
  /// como parte del tablero en `cerrarTurno()`, igual que un movimiento.
  Future<void> _evolucionarCarta(
      String coord, int indice, CartaModel evolucion) async {
    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }

    final celda = _boardState.getCelda(coord);
    if (indice < 0 || indice >= celda.cartas.length) return;

    final original = celda.cartas[indice];
    if (original.ownerUid != _localPlayer.datos.uid) {
      _toast('No puedes evolucionar cartas ajenas', error: true);
      return;
    }

    final coste = original.carta.evolucion;
    if (_localPlayer.puntos < coste) {
      _toast('Energías insuficientes (${_localPlayer.puntos} / $coste)',
          error: true);
      return;
    }

    // 1. Reemplazo local en la misma posición (manteniendo owner)
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
      // La carta evolucionada cuenta como acción del turno: la marcamos
      // como movida para que no pueda volver a moverse este turno.
      _cartasMovidasEsteTurno.add(evolucion.id);
    });

    // 2. Persistir descuento de energías en Firestore (atómico)
    if (widget.lobbyId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('Partidas')
            .doc(widget.lobbyId)
            .update({
          'statsPartida.${widget.localPlayerUid}.energies':
              FieldValue.increment(-coste),
        }).timeout(const Duration(seconds: 8));
      } catch (e) {
        // Si falla, revertir el cambio local.
        if (!mounted) return;
        setState(() {
          _boardState = _boardState.setCelda(coord, celda);
          _localPlayer.puntos += coste;
          _cartasMovidasEsteTurno.remove(evolucion.id);
        });
        _toast('Error al evolucionar. Inténtalo de nuevo.', error: true);
        return;
      }
    }

    _toast('${original.carta.nombre} → ${evolucion.nombre}  (-$coste⚡)');
  }

  // ── Helper para reconstruir un CartaModel desde un mapa Firestore ──
  // CartaModel.fromMap acepta PascalCase y snake_case (compatibilidad Firestore)
  CartaModel _cartaFromMap(Map<String, dynamic> c, {String? fallbackId}) {
    final carta = CartaModel.fromMap(c);
    if (fallbackId != null && fallbackId.isNotEmpty && carta.id.isEmpty) {
      return carta.copyWith(id: fallbackId);
    }
    return carta;
  }

  // ── Cargar terreno desde la coleccion Mapas ──────────────
  Future<void> _aplicarTerreno(String mapaId) async {
    try {
      final config = await MapaService()
          .aplicarTerrenoAConfig(mapaId, _config)
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _config = config);
    } catch (_) {
      // Si la carga del terreno falla o tarda demasiado, continuar
      // con el terreno por defecto (todo land) para no bloquear la carga.
    }
  }

  Future<void> _loadGame() async {
    try {
      // Carga crítica en paralelo: mazo + datos del lobby.
      // Los obeliscos se cargan en background tras mostrar el juego.
      final futures = <Future>[
        MazoService().obtenerMazoParaJuego(widget.localPlayerUid),
        if (widget.lobbyId != null)
          FirebaseFirestore.instance
              .collection('Partidas')
              .doc(widget.lobbyId)
              .get(),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      final mazo = results[0] as MazoResuelto;

      if (widget.lobbyId != null && results.length > 1) {
        final doc = results[1] as DocumentSnapshot;
        if (doc.exists) {
          final lobby = LobbyModel.fromFirestore(doc);
          final data = doc.data() as Map<String, dynamic>;

          setState(() {
            _modoTurno = lobby.modoTurno;
            _jugadoresEnPartida = lobby.jugadores.length;
            _cerradoPor = List<String>.from(lobby.cerradoPor);
          });

          // ── Cargar terreno desde Mapas/{mapaId} ──────────────
          if (lobby.mapaId != null) {
            await _aplicarTerreno(lobby.mapaId!);
            if (!mounted) return;
          }

          // Restaurar logs + puntos — dentro de setState para que el botón
          // INFORME aparezca inmediatamente al cargar la partida.
          final loadedCombateLog =
              (data['ultimoCombateLog'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          final loadedMovLog =
              (data['ultimosMovimientos'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          final rawStats = data['statsPartida'] as Map<String, dynamic>? ?? {};
          int puntosRestaurados = _localPlayer.puntos;
          if (rawStats.containsKey(widget.localPlayerUid)) {
            final myS = Map<String, dynamic>.from(
                rawStats[widget.localPlayerUid] as Map);
            puntosRestaurados = (myS['energies'] as num?)?.toInt() ?? 0;
          }
          final loadedHistorial =
              (data['historialCombates'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          setState(() {
            _currentLobby = lobby;
            _lastCombateLog = loadedCombateLog;
            _lastMovimientosLog = loadedMovLog;
            _historialCombates = loadedHistorial;
            _localPlayer.puntos = puntosRestaurados;
          });

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
              _boardState =
                  restoredBoard.copyWith(turnoActual: lobby.turnoActual);
            });
          }

          final cartasEnTablero = _boardState.celdas.values
              .expand((c) => c.cartas)
              .where((c) => c.ownerUid == _localPlayer.datos.uid)
              .map((c) => c.carta.id)
              .toSet();

          final manoRestante = mazo.cartas
              .where((c) => !cartasEnTablero.contains(c.id))
              .toList();

          final obeliscosData =
              data['obeliscos'] as Map<String, dynamic>? ?? {};
          final colors = <String, Color>{};
          obeliscosData.forEach((uid, coord) {
            colors[uid] = _obeliscoColor(coord as String);
          });
          setState(() => _playerColors = colors);

          if (lobby.modoTurno == ModoTurno.rapida && lobby.cerradoPor.isEmpty) {
            _startTimer();
          }
          _subscribeToLobby();

          // Cargar obeliscos en background — no bloquea la carga del juego
          _assignObeliscos().catchError((_) {});

          setState(() {
            _hand = manoRestante;
            _loading = false;
            _boardStateInicial = _boardState;
            _handInicial = List.from(manoRestante);
            _cartasMovidasEsteTurno.clear();
          });
          _turnoConfirmadoStream = lobby.turnoActual;
          _cargaCompletada = true;
          // Si todos ya cerraron antes de que cargara _loadGame,
          // el stream ya disparó pero _cargaCompletada era false.
          // Comprobamos aquí para no perder el turno.
          // Cualquier jugador puede resolver al volver a entrar a la partida
          if (_todosCerraronTurno && !_resolviendo) {
            _resolviendo = true;
            _resolverTurno();
          }
          return;
        }
      }

      final fullHand = List<CartaModel>.from(mazo.cartas)..shuffle();
      setState(() {
        _hand = fullHand;
        _loading = false;
        _boardStateInicial = _boardState;
        _handInicial = List.from(fullHand);
        _cartasMovidasEsteTurno.clear();
      });
    } on TimeoutException catch (_) {
      if (mounted)
        setState(() {
          _error = 'La conexión tardó demasiado.\nPulsa Reintentar.';
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Error: ${e.toString()}';
          _loading = false;
        });
    }
  }

  StreamSubscription<DocumentSnapshot>? _lobbySub;

  void _subscribeToLobby() {
    if (widget.lobbyId == null) return;
    _lobbySub = FirebaseFirestore.instance
        .collection('Partidas')
        .doc(widget.lobbyId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final lobby = LobbyModel.fromFirestore(doc);
      final data = doc.data() as Map<String, dynamic>;

      final obelData = data['obeliscos'] as Map<String, dynamic>? ?? {};
      final streamColors = <String, Color>{};
      obelData.forEach((uid, coord) {
        streamColors[uid] = _obeliscoColor(coord as String);
      });
      setState(() {
        _cerradoPor = List<String>.from(lobby.cerradoPor);
        _jugadoresEnPartida = lobby.jugadores.length;
        _modoTurno = lobby.modoTurno;
        if (streamColors.isNotEmpty) _playerColors = streamColors;
        _currentLobby = lobby;
        _hostUid = lobby.hostUid;
      });

      // Aplicar el tablero de Firestore si el stream trae un turno que aún
      // no hemos confirmado. Usamos _turnoConfirmadoStream en lugar de
      // _boardState.turnoActual para que el HOST (que ya actualiza
      // _boardState localmente en _resolverTurno) también sincronice.
      if (lobby.turnoActual > _turnoConfirmadoStream &&
          data.containsKey('tablero')) {
        final tableroRaw = TurnService.parseTablero(data);
        var restoredState = const BoardState();
        tableroRaw.forEach((coord, cartas) {
          for (final c in cartas) {
            restoredState = restoredState.placeCarta(
              coord,
              CartaEnCelda(
                carta: _cartaFromMap(c),
                ownerUid: c['ownerUid'] as String? ?? '',
                ownerZone: c['ownerZone'] as String? ?? '',
              ),
            );
          }
        });
        _turnoConfirmadoStream = lobby.turnoActual;
        setState(() {
          _boardState = restoredState.copyWith(turnoActual: lobby.turnoActual);
          _cerradoPor = [];
          _resolviendo = false;
          _isSendingTurn = false; // siempre resetear al llegar nuevo turno
          _cargaCompletada = true;
          _boardStateInicial =
              restoredState.copyWith(turnoActual: lobby.turnoActual);
          _handInicial = List.from(_hand);
          _cartasMovidasEsteTurno.clear();
        });
        // Actualizar puntos locales desde statsPartida
        final rawSt = data['statsPartida'] as Map<String, dynamic>? ?? {};
        if (rawSt.containsKey(widget.localPlayerUid)) {
          final myS =
              Map<String, dynamic>.from(rawSt[widget.localPlayerUid] as Map);
          final pts = (myS['energies'] as num?)?.toInt() ?? 0;
          if (pts != _localPlayer.puntos)
            setState(() => _localPlayer.puntos = pts);
        }
        if (_modoTurno == ModoTurno.rapida) _startTimer();

        // Mostrar informe de batalla a partir del turno 2.
        // Solo se auto-mostrará si:
        //   (1) no hemos mostrado ya el informe de este mismo turno
        //   (2) no hay un informe abierto pisable (evitar que un nuevo turno
        //       cubra el informe que el usuario todavía está leyendo).
        // En ambos casos, _lastCombateLog / _lastMovimientosLog quedan
        // actualizados para que el botón del tablero abra siempre el último.
        if (lobby.turnoActual > 1 && mounted) {
          final combateLog = (data['ultimoCombateLog'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final movLog = (data['ultimosMovimientos'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          // Guardar para acceso posterior desde el botón del tablero
          _lastCombateLog = combateLog;
          _lastMovimientosLog = movLog;
          final historialData =
              (data['historialCombates'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          _historialCombates = historialData;

          final turnoInforme = lobby.turnoActual - 1;
          if (turnoInforme > _informeMostradoTurno && !_informeAbierto) {
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
                      historial: _historialCombates,
                      localUid: widget.localPlayerUid,
                      jugadores: _currentLobby?.jugadores ?? [],
                      turno: turnoInforme,
                    ),
                  ))
                  .whenComplete(() => _informeAbierto = false);
            });
          }
        }
        return;
      }

      // ── El host resuelve cuando todos cierran ─────────────────
      // _cargaCompletada evita que el primer snapshot de caché (Pixel 9)
      // dispare la resolución antes de que _loadGame haya terminado.
      // _resolviendo evita llamadas dobles si llegan varios snapshots seguidos.
      // Cualquier jugador puede disparar la resolución.
      // La transacción Firestore garantiza que solo se aplique una vez.
      if (_cargaCompletada &&
          !_resolviendo &&
          _cerradoPor.length >= _jugadoresEnPartida) {
        _resolviendo = true;
        _resolverTurno();
      }
    }, onError: (e) {
      // Errores del stream Firestore (conexión, permisos, etc.)
      if (mounted) _toast('Conexión perdida con el servidor', error: true);
    });
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
    _lobbySub?.cancel();
    _timerActivo =
        false; // detener el timer para que Future.doWhile no llame setState
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

  // ── BFS de movimiento con restricciones de terreno ────────
  //
  // Reglas según el campo `tipo` de la carta:
  //   tipo 1 (terrestre) → solo traversa/aterriza en land y amphibious.
  //                         Una celda de agua bloquea el paso completamente.
  //   tipo 2 (volador)   → traversa cualquier celda, pero solo puede
  //                         detenerse en land y amphibious.
  //   tipo 3 (marino)    → inverso al tipo 1: solo traversa/aterriza en
  //                         sea, deepSea y amphibious.
  Set<String> _computeMovableBFS(String from, int mov, int tipo) {
    if (mov <= 0) return {};

    // visited[coord] = mínimo de pasos gastados para llegar
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

        // Ya visitado con igual o menor coste
        if ((visited[nCoord] ?? 999) <= newSteps) continue;

        // ¿Puede la unidad atravesar esta celda?
        if (!_config.canTraverse(nCoord, tipo)) continue;

        visited[nCoord] = newSteps;

        // ¿Puede la unidad detenerse aquí?
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

  /// Calcula el tipo efectivo de un grupo de cartas.
  /// Devuelve -1 si la mezcla es incompatible (terrestre + marino).
  int _tipoEfectivo(List<int> validIndices, CeldaState celda) {
    final tipos = validIndices.map((i) => celda.cartas[i].carta.tipo).toSet();
    if (tipos.length == 1) return tipos.first;
    if (tipos.contains(1) && tipos.contains(3)) return -1; // incompatible
    if (tipos.contains(1)) return 1; // terrestre + volador → terrestre gana
    if (tipos.contains(3)) return 3; // marino + volador → marino gana
    return 2;
  }

  // ─────────────────────────────────────────────────────────
  // LÓGICA DE INTERACCIÓN
  // ─────────────────────────────────────────────────────────

  void _onCellTap(String coord, int ri, int ci) {
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
    if (coord != _obeliscoLocal) {
      _toast('⚔  Solo puedes desplegar en tu cuartel: $_obeliscoLocal',
          error: true);
      return;
    }
    final carta = _hand[_selectedHandIndex!];
    setState(() {
      _boardState = _boardState.placeCarta(
        coord,
        CartaEnCelda(
            carta: carta,
            ownerUid: _localPlayer.datos.uid,
            ownerZone: _localPlayer.zona),
      );
      _hand = List.from(_hand)..removeAt(_selectedHandIndex!);
      // No añadir a _cartasMovidasEsteTurno: desplegar desde la mano
      // no consume el movimiento de la carta; podrá moverse este mismo turno.
      _selectedHandIndex = null;
      _sidebarCoord = coord;
      _sidebarRi = ri;
      _sidebarCi = ci;
      _sidebarOpen = true;
    });
  }

  // ── Activar modo movimiento desde sidebar ─────────────────
  void _onMoveSelected(List<int> indices) {
    if (_sidebarCoord == null || indices.isEmpty) return;

    if (_yoCerreElTurno) {
      _toast('Ya has cerrado el turno. Espera al siguiente.', error: true);
      return;
    }

    final celda = _boardState.getCelda(_sidebarCoord!);

    final validIndices = indices
        .where((i) =>
            i < celda.cartas.length &&
            celda.cartas[i].ownerUid == _localPlayer.datos.uid &&
            !_cartasMovidasEsteTurno.contains(celda.cartas[i].carta.id))
        .toList();

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

    // ── Resolver tipo efectivo del grupo ──────────────────
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

  // ── Ejecutar movimiento ───────────────────────────────────
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

  void _undoCambios() {
    setState(() {
      _boardState = _boardStateInicial;
      _hand = List.from(_handInicial);
      _cartasMovidasEsteTurno.clear();
      _moveFromCoord = null;
      _moveCardIndices = [];
      _movableCoords = {};
      _selectedHandIndex = null;
      _sidebarOpen = false;
      _sidebarCoord = null;
    });
    _toast('Cambios revertidos al estado inicial del turno.');
  }

  void _onHandCardTap(int index) {
    setState(() {
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
        // Solo campos necesarios para combate — sin Imagen ni Descripcion
        // para mantener el payload pequeño y evitar timeouts en red lenta.
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
          'ownerUid': c.ownerUid,
          'ownerZone': c.ownerZone,
        };
      }).toList();
      if (misCartas.isNotEmpty) result[coord] = misCartas;
    });
    return result;
  }

  Future<void> _cerrarTurno() async {
    if (_yoCerreElTurno || _isSendingTurn) return;
    setState(() {
      _isSendingTurn = true;
      _selectedHandIndex = null;
      _cancelMoveMode();
      _sidebarOpen = false;
      _timerActivo = false;
    });

    if (widget.lobbyId != null) {
      try {
        await TurnService()
            .cerrarTurno(
              lobbyId: widget.lobbyId!,
              uid: widget.localPlayerUid,
              turno: _boardState.turnoActual,
              celdas: _serializarTablero(),
            )
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        // Reintentar automáticamente hasta 2 veces en errores transitorios
        bool reintentado = false;
        for (int intento = 1; intento <= 2; intento++) {
          await Future.delayed(Duration(seconds: intento * 2));
          if (!mounted) return;
          try {
            await TurnService()
                .cerrarTurno(
                  lobbyId: widget.lobbyId!,
                  uid: widget.localPlayerUid,
                  turno: _boardState.turnoActual,
                  celdas: _serializarTablero(),
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
    } else {
      setState(
          () => _boardState = _boardState.nextTurn(_opponentPlayer.datos.uid));
    }

    if (mounted) setState(() => _isSendingTurn = false);
    _toast('Turno cerrado. Esperando a los demás…');
  }

  Future<void> _resolverTurno() async {
    if (widget.lobbyId == null) return;
    final turnoAResolver = _boardState.turnoActual;
    try {
      // 1. Leer movimientos y stats en PARALELO con timeout
      final fetchMovimientos = TurnService()
          .getMovimientosTurno(
            lobbyId: widget.lobbyId!,
            turno: turnoAResolver,
          )
          .timeout(const Duration(seconds: 30));
      final fetchDoc = FirebaseFirestore.instance
          .collection('Partidas')
          .doc(widget.lobbyId)
          .get()
          .timeout(const Duration(seconds: 60));
      final movimientos = await fetchMovimientos;
      final lobbyDoc = await fetchDoc;
      if (!mounted) return;

      // 2. Fusionar tableros
      final tableroFusionado = <String, List<Map<String, dynamic>>>{};
      for (final mov in movimientos) {
        mov.celdas.forEach((coord, cartas) {
          tableroFusionado.putIfAbsent(coord, () => []).addAll(cartas);
        });
      }

      // 3. Resolver combates (CPU, sin red)
      final resolucion = CombateService.resolverCombates(tableroFusionado);

      // 4. Reconstruir BoardState limpio (sin cartas derrotadas)
      var newState = const BoardState();
      resolucion.tableroResultante.forEach((coord, cartas) {
        for (final c in cartas) {
          newState = newState.placeCarta(
            coord,
            CartaEnCelda(
              carta: _cartaFromMap(c),
              ownerUid: c['ownerUid'] as String? ?? '',
              ownerZone: c['ownerZone'] as String? ?? '',
            ),
          );
        }
      });

      // 5. Extraer stats del doc ya leído en paralelo
      final statsActuales = <String, Map<String, int>>{};
      if (lobbyDoc.exists) {
        final rawS =
            ((lobbyDoc.data() as Map<String, dynamic>?)?['statsPartida']
                    as Map<String, dynamic>?) ??
                {};
        rawS.forEach((uid, v) {
          final m = Map<String, dynamic>.from(v as Map);
          statsActuales[uid] = {
            'energies': (m['energies'] as num?)?.toInt() ?? 0,
            'pc': (m['pc'] as num?)?.toInt() ?? 0,
          };
        });
      }

      // 6. Log de movimientos
      final movimientosLog = movimientos.map((m) {
        String zona = '';
        for (final cs in m.celdas.values) {
          if (cs.isNotEmpty) {
            zona = cs.first['ownerZone'] as String? ?? '';
            if (zona.isNotEmpty) break;
          }
        }
        return {'uid': m.uid, 'zona': zona, 'celdas': m.celdas};
      }).toList();

      // 7. Persistir en Firestore (el outer try-catch captura fallos)
      await TurnService()
          .resolverCombatesYAvanzar(
            lobbyId: widget.lobbyId!,
            turnoActual: turnoAResolver,
            tablero: tableroFusionado,
            statsActuales: statsActuales,
            movimientosLog: movimientosLog,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      // 8. Actualizar estado local
      final ptsGanados =
          resolucion.energiesPorJugador[widget.localPlayerUid] ?? 0;
      setState(() {
        _boardState = newState.copyWith(turnoActual: turnoAResolver + 1);
        _cerradoPor = [];
        _resolviendo = false;
        _isSendingTurn = false;
        _boardStateInicial = _boardState;
        _handInicial = List.from(_hand);
        _cartasMovidasEsteTurno.clear();
        if (ptsGanados > 0) _localPlayer.puntos += ptsGanados;
      });
      if (_modoTurno == ModoTurno.rapida && mounted) _startTimer();
    } catch (e) {
      // Cualquier excepción en el flujo de resolución resetea el estado
      // para que el jugador pueda reintentar.
      if (mounted) {
        setState(() {
          _resolviendo = false;
          _isSendingTurn = false;
        });
        _toast('Error al resolver turno. Pulsa Actualizar.', error: true);
      }
    }
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
      _lobbySub?.cancel();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _checkRefresh() async {
    if (!_yoCerreElTurno) return;

    // ── Paso 1: estado en memoria (sin red) ──────────────────
    // Resetear _resolviendo para desbloquear si quedó atascado
    setState(() => _resolviendo = false);

    if (_todosCerraronTurno) {
      _resolviendo = true;
      _toast('Resolviendo turno…');
      _resolverTurno();
      return;
    }

    // ── Paso 2: comprobar si el turno ya avanzó en Firestore ─
    // Solo caché local — sin esperar red. Si falla, mostrar estado en memoria.
    if (widget.lobbyId == null) {
      final faltan = _jugadoresEnPartida - _cerradoPor.length;
      _toast('Faltan $faltan jugador${faltan == 1 ? '' : 'es'} por cerrar.');
      return;
    }

    DocumentSnapshot? doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('Partidas')
          .doc(widget.lobbyId)
          .get(const GetOptions(source: Source.cache));
    } catch (_) {
      // Sin caché: mostrar estado en memoria sin error
      final faltan = _jugadoresEnPartida - _cerradoPor.length;
      _toast('Faltan $faltan jugador${faltan == 1 ? '' : 'es'} por cerrar.');
      return;
    }
    if (doc == null || !doc.exists || !mounted) return;
    final lobby = LobbyModel.fromFirestore(doc);
    final data = doc.data() as Map<String, dynamic>;

    // Si ya avanzó el turno en Firestore, sincronizar el tablero
    if (lobby.turnoActual > _turnoConfirmadoStream &&
        data.containsKey('tablero')) {
      final tableroRaw = TurnService.parseTablero(data);
      var restoredState = const BoardState();
      tableroRaw.forEach((coord, cartas) {
        for (final c in cartas) {
          restoredState = restoredState.placeCarta(
            coord,
            CartaEnCelda(
              carta: _cartaFromMap(c),
              ownerUid: c['ownerUid'] as String? ?? '',
              ownerZone: c['ownerZone'] as String? ?? '',
            ),
          );
        }
      });
      _turnoConfirmadoStream = lobby.turnoActual;
      setState(() {
        _boardState = restoredState.copyWith(turnoActual: lobby.turnoActual);
        _cerradoPor = [];
        _resolviendo = false;
        _isSendingTurn = false;
        _cargaCompletada = true;
        _boardStateInicial =
            restoredState.copyWith(turnoActual: lobby.turnoActual);
        _handInicial = List.from(_hand);
        _cartasMovidasEsteTurno.clear();
      });
      return;
    }

    // Turno no avanzado: actualizar cerradoPor y disparar resolución si somos host
    setState(() {
      _cerradoPor = List<String>.from(lobby.cerradoPor);
      _jugadoresEnPartida = lobby.jugadores.length;
      // Resetear _resolviendo para recuperarse de cualquier estado bloqueado
      _resolviendo = false;
    });
    if (_todosCerraronTurno) {
      _resolviendo = true;
      _toast('Resolviendo turno…');
      _resolverTurno();
    } else {
      final faltan = _jugadoresEnPartida - _cerradoPor.length;
      _toast(
          'Faltan $faltan jugador${faltan == 1 ? '' : 'es'} por cerrar turno.');
    }
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
                    movableCoords: _movableCoords,
                    obeliscoLocal: _obeliscoLocal,
                    playerColors: _playerColors,
                    onCellTap: _onCellTap,
                  ),
                ),
                if (_yoCerreElTurno)
                  _TurnWaitBanner(
                    modoTurno: _modoTurno,
                    cerradoPor: _cerradoPor.length,
                    totalJugadores: _jugadoresEnPartida,
                    onRefresh: _checkRefresh,
                  ),
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
                HandWidget(
                  cartas: _hand,
                  selectedIndex: _selectedHandIndex,
                  onCardTap: _onHandCardTap,
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
            if (_hayCambiosPendientes && !_yoCerreElTurno)
              Positioned(
                left: 10,
                bottom: 58 + 105 + 8,
                child: _UndoChangesButton(onUndo: _undoCambios),
              ),
            // Botón INFORME — entre tablero y HUD inferior
            if (_boardState.turnoActual > 1)
              Positioned(
                left: 10,
                bottom: 58 + 105 + 6,
                child: _InformeButton(
                  onTap: () {
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
                          ),
                        ))
                        .whenComplete(() => _informeAbierto = false);
                  },
                ),
              ),
            Positioned(
              top: 58,
              right: 0,
              bottom: 58 + 105,
              width: CellSidebar.width,
              child: CellSidebar(
                celda: sidebarCelda,
                coord: _sidebarCoord,
                terrain: sidebarTerrain,
                isOpen: _sidebarOpen,
                isEnemyObelisco: isEnemySidebar,
                localUid: _localPlayer.datos.uid,
                playerColors: _playerColors,
                onMoveSelected: _onMoveSelected,
                onClose: _closeSidebar,
                energiasDisponibles: _localPlayer.puntos,
                resolveEvolucion: _resolveEvolucion,
                onEvolucionar: _evolucionarCarta,
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
// BOTÓN DESHACER CAMBIOS
// ─────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────
// BOTÓN INFORME DE BATALLA
// ─────────────────────────────────────────────────────────────
class _InformeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InformeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xCC060E1A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A5A7A), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2A4A6A).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 13, color: Color(0xFF6AAAD0)),
            SizedBox(width: 5),
            Text('INFORME',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  letterSpacing: 1.2,
                  color: Color(0xFF6AAAD0),
                )),
          ],
        ),
      ),
    );
  }
}

class _UndoChangesButton extends StatelessWidget {
  final VoidCallback onUndo;
  const _UndoChangesButton({required this.onUndo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0D1E30),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text(
              '¿Deshacer cambios?',
              style: TextStyle(
                  fontFamily: 'Cinzel', color: Color(0xFFC8A860), fontSize: 14),
            ),
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
        ).then((confirmed) {
          if (confirmed == true) onUndo();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A0808),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCC3030), width: 1.2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.undo, size: 12, color: Color(0xFFFF8080)),
            SizedBox(width: 5),
            Text(
              'DESHACER CAMBIOS',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  color: Color(0xFFFF8080),
                  letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
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
