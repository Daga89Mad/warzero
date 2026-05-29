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
import 'revision_turno_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Jugadores eliminados (cuartel conquistado).
  List<String> _jugadoresEliminados = [];

  /// True si el jugador local fue eliminado.
  bool _estoyEliminado = false;

  /// True si la partida ha terminado (solo queda 1 jugador).
  bool _juegoTerminado = false;
  String? _ganadorUid;

  List<Map<String, dynamic>> _lastCombateLog = [];
  List<Map<String, dynamic>> _lastMovimientosLog = [];
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

  /// UID del cliente encargado de RESOLVER el turno cuando todos han cerrado.
  ///
  /// Solo UN cliente debe ejecutar la resolución para evitar condiciones de
  /// carrera entre dispositivos (la transacción de servidor protege la
  /// escritura, pero no el estado local del resto). Se elige al host si sigue
  /// activo; en caso contrario, el menor uid activo (orden lexicográfico) para
  /// que la elección sea idéntica y determinista en todos los dispositivos.
  String? get _resolvedorUid {
    final lobby = _currentLobby;
    if (lobby == null) return null;
    final activos = lobby.jugadores
        .map((j) => j.uid)
        .where((u) => u.isNotEmpty && !_jugadoresEliminados.contains(u))
        .toList()
      ..sort();
    if (activos.isEmpty) return null;
    if (lobby.hostUid.isNotEmpty && activos.contains(lobby.hostUid)) {
      return lobby.hostUid;
    }
    return activos.first;
  }

  bool get _soyResolvedor => _resolvedorUid == widget.localPlayerUid;

  /// Timer de respaldo: si el resolvedor designado no avanza el turno en este
  /// tiempo (p. ej. se ha desconectado), cualquier cliente que ya cerró fuerza
  /// la resolución. La transacción de servidor impide resoluciones duplicadas.
  Timer? _fallbackTimer;

  // ── Mano y mazo ───────────────────────────────────────────
  List<CartaModel> _hand = [];
  List<CartaModel> _mazoRestante = [];
  int? _selectedHandIndex;

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
      final colors = <String, Color>{};
      final obeliscos = <String, String>{};
      all.forEach((uid, coord) {
        colors[uid] = _obeliscoColor(coord);
        obeliscos[uid] = coord;
      });
      setState(() {
        // No sobrescribir con null si ya teníamos un cuartel válido.
        if (assigned != null && assigned.isNotEmpty) {
          _obeliscoLocal = assigned;
        }
        final oponente = all.entries
            .firstWhere((e) => e.key != widget.localPlayerUid,
                orElse: () => const MapEntry('', ''))
            .value
            .nullIfEmpty;
        if (oponente != null) _obeliscoOponente = oponente;
        if (colors.isNotEmpty) _playerColors = colors;
        if (obeliscos.isNotEmpty) _obeliscosPorJugador = obeliscos;
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
    });

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

  // ── Persistir mano y mazo restante en Firestore ───────────
  void _saveHandAndDeck() {
    if (widget.lobbyId == null) return;
    FirebaseFirestore.instance
        .collection('Partidas')
        .doc(widget.lobbyId)
        .update({
      'statsPartida.${widget.localPlayerUid}.mano':
          _hand.map((c) => c.id).toList(),
      'statsPartida.${widget.localPlayerUid}.mazoRestante':
          _mazoRestante.map((c) => c.id).toList(),
    }).catchError((_) {}); // fire-and-forget
  }

  // ── Cargar terreno desde la coleccion Mapas ──────────────
  Future<void> _aplicarTerreno(String mapaId) async {
    try {
      final config = await MapaService()
          .aplicarTerrenoAConfig(mapaId, _config)
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _config = config);
    } catch (_) {}
  }

  Future<void> _loadGame() async {
    try {
      // ── 1. Cargar datos del lobby en paralelo con el mazo base ──
      final lobbyFuture = widget.lobbyId != null
          ? FirebaseFirestore.instance
              .collection('Partidas')
              .doc(widget.lobbyId)
              .get()
          : null;
      final lobbyDoc = lobbyFuture != null ? await lobbyFuture : null;
      if (!mounted) return;

      // ── 2. Extraer ejercitoId del lobby para filtrar el mazo ──
      int? ejercitoId;
      LobbyModel? lobby;
      Map<String, dynamic> data = {};

      if (lobbyDoc != null && lobbyDoc.exists) {
        lobby = LobbyModel.fromFirestore(lobbyDoc);
        data = lobbyDoc.data() as Map<String, dynamic>;
        final myJugador = lobby.jugadores.cast<LobbyJugador?>().firstWhere(
            (j) => j?.uid == widget.localPlayerUid,
            orElse: () => null);
        ejercitoId = myJugador?.ejercitoId;
      }

      // ── 3. Cargar mazo filtrado por ejército ──────────────────
      final mazo = await MazoService()
          .obtenerMazoParaJuego(widget.localPlayerUid, ejercitoId: ejercitoId);
      if (!mounted) return;

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
        } else {
          // Primera vez: asignar energías de inicio
          puntosRestaurados = _energiasIniciales;
          FirebaseFirestore.instance
              .collection('Partidas')
              .doc(widget.lobbyId)
              .update({
            'statsPartida.${widget.localPlayerUid}.energies':
                _energiasIniciales,
          }).catchError((_) {});
        }
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
        // del doc, para no depender de la llamada de red de _assignObeliscos.
        final obeliscoLocalDoc = obeliscosMap[widget.localPlayerUid];
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
            _boardState =
                restoredBoard.copyWith(turnoActual: lobby!.turnoActual);
          });
        }

        // ── 6. Restaurar mano y mazo (con soporte de duplicados) ──
        List<CartaModel> manoFinal = [];
        List<CartaModel> mazoRestanteFinal = [];

        if (rawStats.containsKey(widget.localPlayerUid)) {
          final myS =
              Map<String, dynamic>.from(rawStats[widget.localPlayerUid] as Map);
          final manoIds = myS['mano'] as List?;
          final mazoIds = myS['mazoRestante'] as List?;

          if (manoIds != null && manoIds.isNotEmpty) {
            manoFinal = _restoreCartasFromIds(
                manoIds.map((e) => e.toString()).toList(), mazo.cartas);
          }
          if (mazoIds != null && mazoIds.isNotEmpty) {
            mazoRestanteFinal = _restoreCartasFromIds(
                mazoIds.map((e) => e.toString()).toList(), mazo.cartas);
          }
        }

        // Si no hay mano guardada → repartir mano inicial
        if (manoFinal.isEmpty && !_estoyEliminado) {
          final cartasEnTablero = _boardState.celdas.values
              .expand((c) => c.cartas)
              .where((c) => c.ownerUid == _localPlayer.datos.uid)
              .map((c) => c.carta.id)
              .toSet();

          final pool = List<CartaModel>.from(mazo.cartas
              .where((c) => !cartasEnTablero.contains(c.id) && !c.esEvolucion))
            ..shuffle(math.Random());

          manoFinal = pool.take(_initialHandSize).toList();
          mazoRestanteFinal = pool.skip(_initialHandSize).toList();

          // Guardar inmediatamente
          setState(() {
            _hand = manoFinal;
            _mazoRestante = mazoRestanteFinal;
          });
          _saveHandAndDeck();
        } else {
          // Filtrar evoluciones de la mano restaurada
          manoFinal = manoFinal.where((c) => !c.esEvolucion).toList();
        }

        setState(() {
          _hand = manoFinal;
          _mazoRestante = mazoRestanteFinal;
          _loading = false;
          _boardStateInicial = _boardState;
          _handInicial = List.from(manoFinal);
          _cartasMovidasEsteTurno.clear();
          _energiaGastadaDespliegue = 0;
        });
        _turnoConfirmadoStream = lobby.turnoActual;
        _cargaCompletada = true;

        if (lobby.modoTurno == ModoTurno.rapida && lobby.cerradoPor.isEmpty) {
          _startTimer();
        }
        _subscribeToLobby();
        _assignObeliscos().catchError((_) {});
        // Auto-reparar el índice `participantes` para que esta partida aparezca
        // siempre en "mis partidas" (fire-and-forget, no bloquea la carga).
        LobbyService()
            .asegurarParticipantes(widget.lobbyId!)
            .catchError((_) {});

        _intentarResolverSiProcede();

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
          mazo.cartas.where((c) => !c.esEvolucion).toList())
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

      // ── Nuevo turno: aplicar tablero y robar 1 carta ──────────
      if (lobby.turnoActual > _turnoConfirmadoStream &&
          data.containsKey('tablero')) {
        final tableroRaw = TurnService.parseTablero(data);
        final efectosCeldaStream = TurnService.parseEfectosCelda(data);
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
        restoredState =
            restoredState.copyWith(efectosCelda: efectosCeldaStream);
        _turnoConfirmadoStream = lobby.turnoActual;
        _fallbackTimer?.cancel();

        // Robar 1 carta del mazo restante (si no está eliminado)
        CartaModel? cartaRobada;
        final nuevoMazo = List<CartaModel>.from(_mazoRestante);
        if (nuevoMazo.isNotEmpty && !_estoyEliminado) {
          final idx = nuevoMazo.indexWhere((c) => !c.esEvolucion);
          if (idx != -1) {
            cartaRobada = nuevoMazo[idx];
            nuevoMazo.removeAt(idx);
          }
        }
        final nuevaMano = cartaRobada != null
            ? [..._hand, cartaRobada]
            : List<CartaModel>.from(_hand);

        setState(() {
          _boardState = restoredState.copyWith(turnoActual: lobby.turnoActual);
          _cerradoPor = [];
          _resolviendo = false;
          _isSendingTurn = false;
          _cargaCompletada = true;
          _boardStateInicial =
              restoredState.copyWith(turnoActual: lobby.turnoActual);
          _hand = nuevaMano;
          _mazoRestante = nuevoMazo;
          _handInicial = List.from(nuevaMano);
          _cartasMovidasEsteTurno.clear();
          _accionesPendientes.clear();
          _accionController.cancelar();
          _efectosCelda = efectosCeldaStream;
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

        // Informe de batalla (a partir del turno 2)
        if (lobby.turnoActual > 1 && mounted) {
          final combateLog = (data['ultimoCombateLog'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final movLog = (data['ultimosMovimientos'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
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
                  .whenComplete(() {
                _informeAbierto = false;
                _abrirRevisionTurno(turnoRevisar: turnoInforme);
              });
            });
          }
        }
        return;
      }

      // ── Resolver turno cuando todos cierran ───────────────────
      // Delegado al resolvedor único (con fallback temporizado) para evitar
      // que varios dispositivos resuelvan en paralelo.
      _intentarResolverSiProcede();
    }, onError: (e) {
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
    _fallbackTimer?.cancel();
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
    if (coord != _obeliscoLocal) {
      _toast('⚔  Solo puedes desplegar en tu cuartel: $_obeliscoLocal',
          error: true);
      return;
    }
    final carta = _hand[_selectedHandIndex!];

    // ── Comprobar coste de energía ────────────────────────────
    final coste = carta.coste;
    if (_localPlayer.puntos < coste) {
      _toast(
        '⚡ Energía insuficiente: necesitas $coste, tienes ${_localPlayer.puntos}',
        error: true,
      );
      return;
    }

    if (carta.esEstatica) {
      final celdaInicial = _boardStateInicial.getCelda(coord);
      final tieneCartaPropiaAnterior =
          celdaInicial.cartas.any((c) => c.ownerUid == _localPlayer.datos.uid);
      if (!tieneCartaPropiaAnterior) {
        _toast(
            '🏰 Estática: solo puedes colocarla donde ya tenías una carta del turno anterior',
            error: true);
        return;
      }
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

    // ── Persistir gasto en Firestore ──────────────────────────
    if (widget.lobbyId != null && coste > 0) {
      FirebaseFirestore.instance
          .collection('Partidas')
          .doc(widget.lobbyId)
          .update({
        'statsPartida.${widget.localPlayerUid}.energies':
            FieldValue.increment(-coste),
      }).catchError((_) {}); // fire-and-forget; undo restaura si cancela
    }

    if (coste > 0) {
      _toast('${carta.nombre} desplegada  (-$coste ⚡)');
    }
  }

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
            !_cartasMovidasEsteTurno.contains(celda.cartas[i].carta.id) &&
            !celda.cartas[i].carta.esEstatica)
        .toList();

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
    _accionController.setCartaTeleport(ref.coord, ref.indice);
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
      _accionController.cancelar();
      _accionesPendientes.clear();
      // Las energías se restauran cuando llega el nuevo estado por el stream.
    });
    _toast('Cambios revertidos al estado inicial del turno.');
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
      try {
        await TurnService()
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
            await TurnService()
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
    } else {
      // Modo offline: avanzar turno y robar 1 carta
      setState(() {
        _boardState = _boardState.nextTurn(_opponentPlayer.datos.uid);
      });
      // Robar 1 carta del mazo en modo offline
      if (_mazoRestante.isNotEmpty) {
        final idx = _mazoRestante.indexWhere((c) => !c.esEvolucion);
        if (idx != -1) {
          final carta = _mazoRestante[idx];
          setState(() {
            _mazoRestante = List.from(_mazoRestante)..removeAt(idx);
            _hand = [..._hand, carta];
          });
          _toast('🃏 +1 carta para el nuevo turno');
        }
      }
    }

    if (mounted) setState(() => _isSendingTurn = false);
    _toast('Turno cerrado. Esperando a los demás…');
  }

  /// Punto único de entrada para la resolución del turno.
  ///
  /// Se invoca desde la carga inicial, el stream del lobby y "Actualizar".
  /// Solo el resolvedor designado resuelve de inmediato; el resto programa un
  /// fallback temporizado por si el resolvedor no completa la resolución.
  /// Con [forzar] = true cualquier cliente resuelve (usado por "Actualizar").
  void _intentarResolverSiProcede({bool forzar = false}) {
    if (widget.lobbyId == null) return;
    if (_resolviendo || !_cargaCompletada) return;
    if (_cerradoPor.length < _jugadoresActivos) return;

    if (forzar || _soyResolvedor) {
      _fallbackTimer?.cancel();
      _resolviendo = true;
      _resolverTurno();
    } else {
      _programarFallbackResolucion();
    }
  }

  void _programarFallbackResolucion() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (!_resolviendo &&
          _cargaCompletada &&
          _cerradoPor.length >= _jugadoresActivos) {
        _resolviendo = true;
        _resolverTurno();
      }
    });
  }

  Future<void> _resolverTurno() async {
    if (widget.lobbyId == null) return;
    final turnoAResolver = _boardState.turnoActual;
    try {
      // 1. Leer movimientos y stats en paralelo
      final movimientos = await TurnService()
          .getMovimientosTurno(
            lobbyId: widget.lobbyId!,
            turno: turnoAResolver,
          )
          .timeout(const Duration(seconds: 30));
      final lobbyDoc = await FirebaseFirestore.instance
          .collection('Partidas')
          .doc(widget.lobbyId)
          .get()
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;

      final dataLobby = lobbyDoc.exists
          ? (lobbyDoc.data() as Map<String, dynamic>)
          : <String, dynamic>{};

      // 1b. Idempotencia: si el turno YA avanzó en el servidor (otro cliente lo
      // resolvió), no es un error. Bajamos flags y dejamos que el stream aplique
      // el nuevo estado de forma uniforme en todos los dispositivos.
      final turnoEnDB =
          (dataLobby['turnoActual'] as num?)?.toInt() ?? turnoAResolver;
      if (turnoEnDB != turnoAResolver || movimientos.isEmpty) {
        _fallbackTimer?.cancel();
        if (mounted) {
          setState(() {
            _resolviendo = false;
            _isSendingTurn = false;
          });
        }
        return;
      }

      // 1c. Obeliscos LEÍDOS DEL DOCUMENTO (no del estado local, que se carga de
      // forma asíncrona y puede diferir entre dispositivos → resultados de
      // conquista no deterministas). Fallback al estado local si faltan.
      final obelDataResolver =
          dataLobby['obeliscos'] as Map<String, dynamic>? ?? {};
      final obeliscosResolver = <String, String>{};
      obelDataResolver.forEach((uid, coord) {
        if (coord is String && coord.isNotEmpty) obeliscosResolver[uid] = coord;
      });
      final obeliscosEfectivos = obeliscosResolver.isNotEmpty
          ? obeliscosResolver
          : (_obeliscosPorJugador.isNotEmpty ? _obeliscosPorJugador : null);

      // 2. Fusionar tableros
      final tableroFusionado = <String, List<Map<String, dynamic>>>{};
      for (final mov in movimientos) {
        mov.celdas.forEach((coord, cartas) {
          tableroFusionado.putIfAbsent(coord, () => []).addAll(cartas);
        });
      }

      // 3. Recopilar acciones de todos los jugadores y efectos previos
      final acciones = <AccionPendiente>[];
      for (final mov in movimientos) {
        acciones.addAll(mov.acciones);
      }
      final efectosCeldaPrevios = lobbyDoc.exists
          ? TurnService.parseEfectosCelda(
              lobbyDoc.data() as Map<String, dynamic>)
          : <String, List<EfectoActivo>>{};

      // 4. Aplicar acciones (tele → disparo → veneno) ANTES de combates
      final accResult = HabilidadService.aplicarAcciones(
        tablero: tableroFusionado,
        acciones: acciones,
        efectosCelda: efectosCeldaPrevios,
        obeliscosPorJugador: obeliscosEfectivos ?? const {},
      );

      // 5. Resolver combates sobre el tablero tras acciones.
      // (Se usa solo para mostrar avisos de conquista al resolvedor; el estado
      // definitivo lo recalcula y persiste resolverCombatesYAvanzar.)
      final resolucion = CombateService.resolverCombates(
        accResult.tableroResultante,
        obeliscosPorJugador: obeliscosEfectivos,
      );

      // 6. Extraer stats actuales
      final statsActuales = <String, Map<String, int>>{};
      final rawS = dataLobby['statsPartida'] as Map<String, dynamic>? ?? {};
      rawS.forEach((uid, v) {
        final m = Map<String, dynamic>.from(v as Map);
        statsActuales[uid] = {
          'energies': (m['energies'] as num?)?.toInt() ?? 0,
          'pc': (m['pc'] as num?)?.toInt() ?? 0,
        };
      });

      // 7. Log de movimientos
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

      // 10. Persistir en Firestore (incluyendo efectosCelda)
      await TurnService()
          .resolverCombatesYAvanzar(
            lobbyId: widget.lobbyId!,
            turnoActual: turnoAResolver,
            tablero: tableroFusionado,
            statsActuales: statsActuales,
            movimientosLog: movimientosLog,
            obeliscosPorJugador: obeliscosEfectivos,
            acciones: acciones,
            efectosCeldaActual: efectosCeldaPrevios,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      // 11. Notificar conquistas
      for (final conquista in resolucion.obeliscosConquistados) {
        if (conquista.conquistadorUid == widget.localPlayerUid) {
          _toast(
              '🏰 ¡Cuartel conquistado en ${conquista.coord}! +${CombateService.energiesConquista}E +${CombateService.pcConquista}PC');
        } else if (conquista.perdedorUid == widget.localPlayerUid) {
          _toast('💀 Tu cuartel en ${conquista.coord} fue conquistado',
              error: true);
        }
      }

      // 12. NO avanzamos el estado del turno localmente. El stream del lobby
      // (bloque "nuevo turno") es la ÚNICA fuente de verdad y aplicará el
      // tablero, la mano, el robo de carta, los efectos y el informe de batalla
      // de forma idéntica en TODOS los dispositivos. Aquí solo bajamos las
      // banderas de "resolviendo" para desbloquear la UI.
      _fallbackTimer?.cancel();
      if (mounted) {
        setState(() {
          _resolviendo = false;
          _isSendingTurn = false;
        });
      }

      // El temporizador del nuevo turno lo arranca el stream al recibir el
      // turno avanzado (evita arrancar dos timers en paralelo).
    } catch (_) {
      // Un fallo aquí NO debe dejar al jugador atascado. Bajamos las banderas
      // para que el botón "Actualizar" pueda reintentar leyendo del servidor.
      _fallbackTimer?.cancel();
      if (mounted) {
        setState(() {
          _resolviendo = false;
          _isSendingTurn = false;
        });
        _toast(
            'No se pudo resolver el turno. Pulsa Actualizar para reintentar.',
            error: true);
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
      Navigator.of(context).pop();
    }
  }

  Future<void> _checkRefresh() async {
    if (!_yoCerreElTurno) return;

    if (widget.lobbyId == null) {
      final faltan = _jugadoresActivos - _cerradoPor.length;
      _toast('Faltan $faltan jugador${faltan == 1 ? '' : 'es'} por cerrar.');
      return;
    }

    setState(() => _resolviendo = false);

    // Lectura desde el SERVIDOR (no caché): "Actualizar" debe traer el estado
    // real, no una copia local potencialmente obsoleta.
    DocumentSnapshot? doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('Partidas')
          .doc(widget.lobbyId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) {
        _toast('No se pudo contactar con el servidor. Reintenta.', error: true);
      }
      return;
    }
    if (doc == null || !doc.exists || !mounted) return;
    final lobby = LobbyModel.fromFirestore(doc);
    final data = doc.data() as Map<String, dynamic>;

    // ── Caso 1: el turno YA avanzó en el servidor ─────────────────
    // Aplicamos el nuevo turno manualmente (red de seguridad por si el stream
    // se retrasó) y mostramos el informe de batalla para no perdérnoslo.
    if (lobby.turnoActual > _turnoConfirmadoStream &&
        data.containsKey('tablero')) {
      final tableroRaw = TurnService.parseTablero(data);
      final efectosCeldaStream = TurnService.parseEfectosCelda(data);
      var restoredState = const BoardState();
      tableroRaw.forEach((coord, cartas) {
        for (final c in cartas) {
          restoredState = restoredState.placeCarta(
            coord,
            CartaEnCelda.fromMap(c),
          );
        }
      });
      restoredState = restoredState.copyWith(efectosCelda: efectosCeldaStream);

      final turnoInforme = lobby.turnoActual - 1;
      final combateLog = (data['ultimoCombateLog'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final movLog = (data['ultimosMovimientos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final historialData = (data['historialCombates'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      _turnoConfirmadoStream = lobby.turnoActual;
      _fallbackTimer?.cancel();
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
        _accionesPendientes.clear();
        _accionController.cancelar();
        _efectosCelda = efectosCeldaStream;
        _puntosInicial = _localPlayer.puntos;
        _energiaGastadaDespliegue = 0;
        _lastCombateLog = combateLog;
        _lastMovimientosLog = movLog;
        _historialCombates = historialData;
      });

      // Sincronizar puntos desde stats del servidor.
      final rawSt = data['statsPartida'] as Map<String, dynamic>? ?? {};
      if (rawSt.containsKey(widget.localPlayerUid)) {
        final myS =
            Map<String, dynamic>.from(rawSt[widget.localPlayerUid] as Map);
        final pts = (myS['energies'] as num?)?.toInt() ?? 0;
        if (mounted && pts != _localPlayer.puntos) {
          setState(() {
            _localPlayer.puntos = pts;
            _puntosInicial = pts;
          });
        }
      }

      // Mostrar informe de batalla (si procede y no se mostró ya).
      if (turnoInforme >= 1 &&
          turnoInforme > _informeMostradoTurno &&
          !_informeAbierto &&
          mounted) {
        _informeMostradoTurno = turnoInforme;
        _informeAbierto = true;
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
            .whenComplete(() {
          _informeAbierto = false;
          _abrirRevisionTurno(turnoRevisar: turnoInforme);
        });
      }
      return;
    }

    // ── Caso 2: el turno NO ha avanzado ───────────────────────────
    // Sincronizamos el estado de cierre desde el servidor.
    final elimServidor =
        List<String>.from(data['jugadoresEliminados'] as List? ?? []);
    setState(() {
      _cerradoPor = List<String>.from(lobby.cerradoPor);
      _jugadoresEnPartida = lobby.jugadores.length;
      _jugadoresEliminados = elimServidor;
      _estoyEliminado = elimServidor.contains(widget.localPlayerUid);
      _resolviendo = false;
    });

    if (_todosCerraronTurno) {
      // Todos han cerrado pero el turno sigue sin avanzar: forzamos la
      // resolución desde este cliente (idempotente; la transacción de servidor
      // impide duplicados). Cubre el caso de que el resolvedor designado se
      // haya desconectado.
      _toast('Resolviendo turno…');
      _intentarResolverSiProcede(forzar: true);
    } else {
      final faltan = _jugadoresActivos - _cerradoPor.length;
      _toast(
          'Faltan $faltan jugador${faltan == 1 ? '' : 'es'} por cerrar turno.');
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
      'accionesLog': const [],
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
                    onCellTap: _onCellTap,
                  ),
                ),
                if (_yoCerreElTurno)
                  _TurnWaitBanner(
                    modoTurno: _modoTurno,
                    cerradoPor: _cerradoPor.length,
                    totalJugadores: _jugadoresActivos,
                    onRefresh: _checkRefresh,
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
            if (_hayCambiosPendientes && !_yoCerreElTurno && !_estoyEliminado)
              Positioned(
                left: 10,
                bottom: 58 + 105 + 8,
                child: _UndoChangesButton(onUndo: _undoCambios),
              ),
            if (_boardState.turnoActual > 1)
              Positioned(
                left: 10,
                bottom: _estoyEliminado ? 8 : 58 + 105 + 6,
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
                        .whenComplete(() {
                      _informeAbierto = false;
                      _abrirRevisionTurno(
                          turnoRevisar: _boardState.turnoActual - 1);
                    });
                  },
                ),
              ),
            // Mazo restante counter
            if (!_estoyEliminado && _mazoRestante.isNotEmpty)
              Positioned(
                right: 10,
                bottom: 58 + 105 + 6,
                child: _DeckCounter(remaining: _mazoRestante.length),
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
// CONTADOR DE MAZO RESTANTE
// ─────────────────────────────────────────────────────────────
class _DeckCounter extends StatelessWidget {
  final int remaining;
  const _DeckCounter({required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xCC060E1A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A4060), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.style, size: 11, color: Color(0xFF5080A0)),
          const SizedBox(width: 4),
          Text('$remaining',
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 9,
                  color: Color(0xFF5080A0),
                  letterSpacing: 1)),
        ],
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
