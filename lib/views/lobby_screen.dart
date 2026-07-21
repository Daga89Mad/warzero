// lib/views/lobby_screen.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lobby_model.dart';
import '../services/lobby_service.dart';
import '../services/warzero_api.dart';
import 'game_screen.dart';
import '../services/mapa_service.dart';
import 'room_screen.dart';

// ─────────────────────────────────────────────────────────────
// LOBBY SCREEN
// ─────────────────────────────────────────────────────────────
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with SingleTickerProviderStateMixin {
  final _service = LobbyService();
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _alias {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final emailPart = user?.email?.split('@').first?.trim() ?? '';
    if (emailPart.isNotEmpty) return emailPart;
    return 'Jugador';
  }

  void _goToRoom(String lobbyId) {
    // Buscar el lobby en los datos actuales para saber si está en curso
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoomScreen(
        lobbyId: lobbyId,
        localUid: _uid,
        localAlias: _alias,
      ),
    ));
  }

  /// Navega directamente al GameScreen (para partidas ya en curso).
  void _goDirectlyToGame(String lobbyId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(
        localPlayerUid: _uid,
        playerCount: 2,
        lobbyId: lobbyId,
      ),
    ));
  }

  void _showCrearDialog() {
    showDialog(
      context: context,
      builder: (_) => _CrearSalaDialog(
        onCreate: ({
          required nombre,
          required esPrivada,
          required contrasena,
          required maxJugadores,
          required modoTurno,
          required mapaId,
        }) async {
          final id = await _service.crearLobby(
            nombre: nombre,
            hostUid: _uid,
            hostAlias: _alias,
            esPrivada: esPrivada,
            contrasena: contrasena,
            maxJugadores: maxJugadores,
            modoTurno: modoTurno,
            mapaId: mapaId,
          );
          if (mounted) {
            Navigator.of(context).pop();
            _goToRoom(id);
          }
        },
      ),
    );
  }

  void _showUnirsePrivadoDialog() {
    showDialog(
      context: context,
      builder: (_) => _UnirsePrivadoDialog(
        onJoin: ({required lobbyId, required contrasena}) async {
          try {
            await _service.unirseALobby(
              lobbyId: lobbyId,
              uid: _uid,
              alias: _alias,
              contrasena: contrasena,
            );
            if (mounted) {
              Navigator.of(context).pop();
              _goToRoom(lobbyId);
            }
          } catch (e) {
            if (mounted) {
              _showError(e.toString().replaceFirst('Exception: ', ''));
            }
          }
        },
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontFamily: 'Cinzel', fontSize: 11)),
      backgroundColor: const Color(0xFF3A0A08),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'SALA DE GUERRA',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: 4,
            color: Color(0xFFC8A860),
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFC8A860),
          indicatorWeight: 1.5,
          labelStyle: const TextStyle(
              fontSize: 10, letterSpacing: 2, fontFamily: 'Cinzel'),
          unselectedLabelColor: const Color(0xFF506070),
          labelColor: const Color(0xFFC8A860),
          tabs: const [
            Tab(text: 'EN CURSO'),
            Tab(text: 'PÚBLICAS'),
            Tab(text: 'PRIVADA'),
          ],
        ),
        actions: [
          _GoldButton(
            label: 'CREAR SALA',
            icon: Icons.add,
            onTap: _showCrearDialog,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MisPartidasList(
              service: _service,
              uid: _uid,
              onJoin: _goToRoom,
              onDirectGame: _goDirectlyToGame),
          _PublicLobbiesList(
            service: _service,
            uid: _uid,
            alias: _alias,
            onJoin: _goToRoom,
            onError: _showError,
          ),
          _PrivateTab(onJoin: _showUnirsePrivadoDialog),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA DE PARTIDAS PÚBLICAS
// ─────────────────────────────────────────────────────────────
class _PublicLobbiesList extends StatefulWidget {
  final LobbyService service;
  final String uid;
  final String alias;
  final void Function(String) onJoin;
  final void Function(String) onError;

  const _PublicLobbiesList({
    required this.service,
    required this.uid,
    required this.alias,
    required this.onJoin,
    required this.onError,
  });

  @override
  State<_PublicLobbiesList> createState() => _PublicLobbiesListState();
}

class _PublicLobbiesListState extends State<_PublicLobbiesList> {
  // Vía API (sin Firestore realtime, que se cuelga en Android). El future se
  // recrea al recargar.
  final WarZeroApi _api = WarZeroApi();
  Future<List<LobbyModel>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<LobbyModel>> _cargar() async {
    final docs = await _api.obtenerPublicas();
    final list = docs
        .map((d) => LobbyModel.fromMap(d['id'] as String? ?? '', d))
        .toList();
    list.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return list;
  }

  Future<void> _recargar() async {
    setState(() {
      _future = _cargar();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final uid = widget.uid;
    final alias = widget.alias;
    final onJoin = widget.onJoin;
    final onError = widget.onError;
    return FutureBuilder<List<LobbyModel>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return _RetryState(
            message: 'No se pudieron cargar las partidas públicas.',
            onRetry: _recargar,
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return _LoadingWithRetry(onRetry: _recargar);
        }
        final lobbies = snap.data ?? [];
        if (lobbies.isEmpty) {
          return _EmptyState(
            icon: Icons.public_off,
            message: 'No hay partidas públicas.\n¡Crea la primera!',
          );
        }
        return RefreshIndicator(
          color: const Color(0xFFC8A860),
          backgroundColor: const Color(0xFF0A1220),
          onRefresh: _recargar,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lobbies.length,
            itemBuilder: (_, i) => _LobbyCard(
              lobby: lobbies[i],
              isMyLobby: lobbies[i].jugadores.any((j) => j.uid == uid),
              onTap: () async {
                try {
                  if (!lobbies[i].jugadores.any((j) => j.uid == uid)) {
                    await service.unirseALobby(
                        lobbyId: lobbies[i].id, uid: uid, alias: alias);
                  }
                  onJoin(lobbies[i].id);
                } catch (e) {
                  onError(e.toString().replaceFirst('Exception: ', ''));
                }
              },
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TARJETA DE LOBBY
// ─────────────────────────────────────────────────────────────
class _LobbyCard extends StatelessWidget {
  final LobbyModel lobby;
  final bool isMyLobby;
  final VoidCallback onTap;

  const _LobbyCard({
    required this.lobby,
    required this.isMyLobby,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = lobby.estaLleno;
    final accent = isMyLobby
        ? const Color(0xFFC8A860)
        : isFull
            ? const Color(0xFF506070)
            : const Color(0xFF4ABB58);

    return GestureDetector(
      onTap: isFull && !isMyLobby ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF080D18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withOpacity(0.30), width: 1),
          boxShadow: [
            BoxShadow(
                color: accent.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withOpacity(0.30), width: 1),
              ),
              child: Icon(
                isMyLobby ? Icons.sensor_door : Icons.groups,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lobby.nombre,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFD0B870),
                          fontFamily: 'Cinzel',
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.person, size: 10, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      '${lobby.jugadores.length}/${lobby.maxJugadores} jugadores',
                      style: TextStyle(
                          fontSize: 9,
                          color: accent.withOpacity(0.8),
                          fontFamily: 'Cinzel',
                          letterSpacing: 1),
                    ),
                  ]),
                ],
              ),
            ),
            _StatusChip(
              label: isMyLobby
                  ? 'CONTINUAR'
                  : isFull
                      ? 'LLENA'
                      : 'ENTRAR',
              color: accent,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAB SALA PRIVADA
// ─────────────────────────────────────────────────────────────
class _PrivateTab extends StatelessWidget {
  final VoidCallback onJoin;
  const _PrivateTab({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: Color(0xFF3A4050)),
          const SizedBox(height: 16),
          const Text('SALA PRIVADA',
              style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFC8A860),
                  letterSpacing: 4,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Introduce el ID de sala y la contraseña\npara unirte a una partida privada.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                color: Color(0xFF506070),
                fontFamily: 'Cinzel',
                height: 1.8,
                letterSpacing: 1),
          ),
          const SizedBox(height: 32),
          _GoldButton(
              label: 'UNIRSE CON CÓDIGO',
              icon: Icons.vpn_key,
              onTap: onJoin,
              width: 200),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO: CREAR SALA  (con selector de mapa)
// ─────────────────────────────────────────────────────────────
class _CrearSalaDialog extends StatefulWidget {
  final Future<void> Function({
    required String nombre,
    required bool esPrivada,
    required String contrasena,
    required int maxJugadores,
    required ModoTurno modoTurno,
    required String? mapaId,
  }) onCreate;

  const _CrearSalaDialog({required this.onCreate});

  @override
  State<_CrearSalaDialog> createState() => _CrearSalaDialogState();
}

class _CrearSalaDialogState extends State<_CrearSalaDialog> {
  final _nombreCtrl = TextEditingController(text: 'Mi Sala');
  final _passCtrl = TextEditingController();
  bool _esPrivada = false;
  int _maxJugadores = 4;
  ModoTurno _modoTurno = ModoTurno.rapida;
  bool _loading = false;

  // ── Mapa ──────────────────────────────────────────────────
  List<MapaInfo> _mapas = [];
  String? _mapaId;
  bool _loadingMapas = false;
  String? _errorMapas;

  @override
  void initState() {
    super.initState();
    _cargarMapas();
  }

  Future<void> _cargarMapas() async {
    if (!mounted) return;
    setState(() {
      _loadingMapas = true;
      _errorMapas = null;
    });
    try {
      final lista = await MapaService().obtenerMapas(jugadores: _maxJugadores);
      if (!mounted) return;
      setState(() {
        _mapas = lista;
        if (lista.length == 1) _mapaId = lista.first.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMapas = e.toString());
    } finally {
      if (mounted) setState(() => _loadingMapas = false);
    }
  }

  /// Recarga mapas cuando cambia el número de jugadores
  Future<void> _onJugadoresChanged(int n) async {
    if (!mounted) return;
    setState(() {
      _maxJugadores = n;
      _mapaId = null;
      _mapas = [];
      _loadingMapas = true;
      _errorMapas = null;
    });
    try {
      final lista = await MapaService().obtenerMapas(jugadores: n);
      if (!mounted) return;
      setState(() {
        _mapas = lista;
        if (lista.length == 1) _mapaId = lista.first.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMapas = e.toString());
    } finally {
      if (mounted) setState(() => _loadingMapas = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nombreCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.onCreate(
        nombre: _nombreCtrl.text.trim(),
        esPrivada: _esPrivada,
        contrasena: _esPrivada ? _passCtrl.text : '',
        maxJugadores: _maxJugadores,
        modoTurno: _modoTurno,
        mapaId: _mapaId,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF080D18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0x405A4820), width: 1),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CREAR SALA',
                style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFC8A860),
                    fontFamily: 'Cinzel',
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Divider(color: Color(0x30C8A860)),
            const SizedBox(height: 16),

            // ── Nombre ──────────────────────────────────────
            _FieldLabel('NOMBRE DE SALA'),
            _DarkTextField(controller: _nombreCtrl, hint: 'Mi Sala'),
            const SizedBox(height: 16),

            // ── Jugadores ────────────────────────────────────
            _FieldLabel('JUGADORES'),
            Row(
              children: [2, 4, 6, 8].map((n) {
                final sel = n == _maxJugadores;
                return GestureDetector(
                  onTap: () => _onJugadoresChanged(n),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 48,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFFC8A860).withOpacity(0.15)
                          : const Color(0xFF0A1220),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFFC8A860)
                            : const Color(0x30506070),
                        width: 1,
                      ),
                    ),
                    child: Text('$n',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: sel
                                ? const Color(0xFFC8A860)
                                : const Color(0xFF506070),
                            fontFamily: 'Cinzel')),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Selector de mapa ─────────────────────────────
            _FieldLabel('MAPA'),
            _MapaSelector(
              mapas: _mapas,
              selectedId: _mapaId,
              loading: _loadingMapas,
              error: _errorMapas,
              onSelected: (id) => setState(() => _mapaId = id),
            ),
            const SizedBox(height: 16),

            // ── Modo turno ───────────────────────────────────
            _FieldLabel('FIN DE TURNO'),
            _ModoTurnoSelector(
              selected: _modoTurno,
              onChanged: (m) => setState(() => _modoTurno = m),
            ),
            const SizedBox(height: 16),

            // ── Sala privada ─────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _esPrivada = !_esPrivada),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _esPrivada
                          ? const Color(0xFFC8A860)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: const Color(0xFF7A5A18), width: 1),
                    ),
                    child: _esPrivada
                        ? const Icon(Icons.check,
                            size: 14, color: Color(0xFF030810))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  const Text('SALA PRIVADA',
                      style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9A8060),
                          fontFamily: 'Cinzel',
                          letterSpacing: 1.5)),
                ],
              ),
            ),

            if (_esPrivada) ...[
              const SizedBox(height: 16),
              _FieldLabel('CONTRASEÑA'),
              _DarkTextField(
                  controller: _passCtrl, hint: '••••••', obscure: true),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0x30506070), width: 1),
                      ),
                      child: const Text('CANCELAR',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF506070),
                              fontFamily: 'Cinzel',
                              letterSpacing: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _loading ? null : _submit,
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC8A860).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFFC8A860).withOpacity(0.5),
                            width: 1),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Color(0xFFC8A860), strokeWidth: 2))
                          : const Text('CREAR',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFC8A860),
                                  fontFamily: 'Cinzel',
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SELECTOR DE MAPA
// ─────────────────────────────────────────────────────────────
class _MapaSelector extends StatelessWidget {
  final List<MapaInfo> mapas;
  final String? selectedId;
  final bool loading;
  final String? error;
  final void Function(String?) onSelected;

  const _MapaSelector({
    required this.mapas,
    required this.selectedId,
    required this.loading,
    required this.onSelected,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: Color(0xFF506070), strokeWidth: 1.5),
          ),
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF200808),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0x60C04040), width: 1),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 13, color: Color(0xFFC04040)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Error cargando mapas: $error',
              style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xFFC04040),
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.3),
            ),
          ),
        ]),
      );
    }

    if (mapas.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF050A14),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0x30506070), width: 1),
        ),
        child: const Text(
          'Sin mapas para esta configuración — terreno estándar',
          style: TextStyle(
              fontSize: 9,
              color: Color(0xFF506070),
              fontFamily: 'Cinzel',
              letterSpacing: 0.5),
        ),
      );
    }

    // Opción "Sin mapa" + lista de mapas
    final opciones = <MapaInfo?>[null, ...mapas];

    return Column(
      children: opciones.map((mapa) {
        final isSelected =
            mapa == null ? selectedId == null : mapa.id == selectedId;
        final label = mapa == null
            ? 'SIN MAPA  (todo terrestre)'
            : mapa.nombre.toUpperCase();
        final accent =
            isSelected ? const Color(0xFF4090E0) : const Color(0xFF304050);

        return GestureDetector(
          onTap: () => onSelected(mapa?.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF4090E0).withOpacity(0.08)
                  : const Color(0xFF050A14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF4090E0).withOpacity(0.60)
                    : const Color(0x25506070),
                width: isSelected ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  mapa == null ? Icons.crop_square : Icons.map_outlined,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? const Color(0xFF80C0FF)
                            : const Color(0xFF506070),
                        fontFamily: 'Cinzel',
                        letterSpacing: 1,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFF4090E0)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4090E0)
                          : const Color(0xFF506070),
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          size: 9, color: Color(0xFF030810))
                      : null,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO: UNIRSE PRIVADA
// ─────────────────────────────────────────────────────────────
class _UnirsePrivadoDialog extends StatefulWidget {
  final Future<void> Function({
    required String lobbyId,
    required String contrasena,
  }) onJoin;

  const _UnirsePrivadoDialog({required this.onJoin});

  @override
  State<_UnirsePrivadoDialog> createState() => _UnirsePrivadoDialogState();
}

class _UnirsePrivadoDialogState extends State<_UnirsePrivadoDialog> {
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_idCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.onJoin(
          lobbyId: _idCtrl.text.trim(), contrasena: _passCtrl.text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF080D18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0x405A4820), width: 1),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('UNIRSE A SALA PRIVADA',
                style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFC8A860),
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            const Divider(color: Color(0x30C8A860)),
            const SizedBox(height: 16),
            _FieldLabel('ID DE SALA'),
            _DarkTextField(controller: _idCtrl, hint: 'Código de sala...'),
            const SizedBox(height: 16),
            _FieldLabel('CONTRASEÑA'),
            _DarkTextField(
                controller: _passCtrl, hint: '••••••', obscure: true),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _loading ? null : _submit,
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC8A860).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFFC8A860).withOpacity(0.5),
                        width: 1),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Color(0xFFC8A860), strokeWidth: 2))
                      : const Text('ENTRAR',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC8A860),
                              fontFamily: 'Cinzel',
                              letterSpacing: 3,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WIDGETS COMPARTIDOS
// ─────────────────────────────────────────────────────────────
class _GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double? width;

  const _GoldButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFC8A860).withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: const Color(0xFFC8A860).withOpacity(0.40), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFC8A860)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFFC8A860),
                    fontFamily: 'Cinzel',
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 8,
              color: Color(0xFF506070),
              fontFamily: 'Cinzel',
              letterSpacing: 2)),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
          color: Color(0xFFD0B870), fontFamily: 'Cinzel', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0x60506070), fontFamily: 'Cinzel', fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0x40503214), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFC8A860), width: 1.2),
          borderRadius: BorderRadius.circular(4),
        ),
        fillColor: const Color(0xFF050A14),
        filled: true,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.40), width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 8,
              color: color,
              fontFamily: 'Cinzel',
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: const Color(0xFF2A3040)),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  height: 1.8,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARGANDO CON OPCIÓN DE REINTENTO
// Muestra un spinner; si la carga se prolonga, ofrece un botón para
// reintentar, de modo que el jugador nunca quede atrapado indefinidamente.
// ─────────────────────────────────────────────────────────────
class _LoadingWithRetry extends StatefulWidget {
  final VoidCallback onRetry;
  const _LoadingWithRetry({required this.onRetry});

  @override
  State<_LoadingWithRetry> createState() => _LoadingWithRetryState();
}

class _LoadingWithRetryState extends State<_LoadingWithRetry> {
  bool _mostrarReintento = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _mostrarReintento = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFC8A860)),
          if (_mostrarReintento) ...[
            const SizedBox(height: 20),
            const Text('La carga está tardando más de lo normal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF506070),
                    fontFamily: 'Cinzel',
                    height: 1.6,
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            _RetryButton(onRetry: widget.onRetry),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ESTADO DE ERROR CON REINTENTO
// ─────────────────────────────────────────────────────────────
class _RetryState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RetryState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Color(0xFF2A3040)),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  height: 1.8,
                  letterSpacing: 1)),
          const SizedBox(height: 16),
          _RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFC8A860).withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: const Color(0xFFC8A860).withOpacity(0.6), width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 13, color: Color(0xFFC8A860)),
            SizedBox(width: 8),
            Text('REINTENTAR',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Color(0xFFC8A860),
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MIS PARTIDAS
// ─────────────────────────────────────────────────────────────
class _MisPartidasList extends StatefulWidget {
  final LobbyService service;
  final String uid;
  final void Function(String) onJoin;
  final void Function(String) onDirectGame;

  const _MisPartidasList({
    required this.service,
    required this.uid,
    required this.onJoin,
    required this.onDirectGame,
  });

  @override
  State<_MisPartidasList> createState() => _MisPartidasListState();
}

class _MisPartidasListState extends State<_MisPartidasList> {
  // Vía API (sin Firestore realtime, que se cuelga en Android tras la partida).
  // El future se recrea al recargar.
  final WarZeroApi _api = WarZeroApi();
  Future<List<LobbyModel>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<LobbyModel>> _cargar() async {
    final docs = await _api.obtenerMisPartidas(widget.uid);
    final list = docs
        .map((d) => LobbyModel.fromMap(d['id'] as String? ?? '', d))
        .where((l) => l.estado != LobbyEstado.finalizada)
        .toList();
    list.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return list;
  }

  /// Recarga (botón "reintentar").
  Future<void> _recargar() async {
    setState(() {
      _future = _cargar();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LobbyModel>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return _RetryState(
            message: 'No se pudieron cargar las partidas.',
            onRetry: _recargar,
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          // Spinner con opción de reintentar por si la carga se atasca, para no
          // dejar al jugador atrapado en un spinner indefinido.
          return _LoadingWithRetry(onRetry: _recargar);
        }

        final lobbies = snap.data ?? [];
        if (lobbies.isEmpty) {
          return const _EmptyState(
              icon: Icons.inbox_outlined,
              message:
                  'No tienes partidas activas.\nCrea una sala o únete a una.');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: lobbies.length,
          itemBuilder: (_, i) {
            final lobby = lobbies[i];
            final estado = lobby.estado == LobbyEstado.enCurso
                ? 'EN BATALLA'
                : 'ESPERANDO';
            final accentColor = lobby.estado == LobbyEstado.enCurso
                ? const Color(0xFFC04040)
                : const Color(0xFFC8A860);

            return GestureDetector(
              onTap: () {
                if (lobby.estado == LobbyEstado.enCurso) {
                  widget.onDirectGame(lobby.id);
                } else {
                  widget.onJoin(lobby.id);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF080D18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: accentColor.withOpacity(0.30), width: 1),
                  boxShadow: [
                    BoxShadow(
                        color: accentColor.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: accentColor.withOpacity(0.30), width: 1),
                      ),
                      child: Icon(
                        lobby.estado == LobbyEstado.enCurso
                            ? Icons.bolt
                            : Icons.hourglass_top,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lobby.nombre,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD0B870),
                                  fontFamily: 'Cinzel',
                                  letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.person, size: 10, color: accentColor),
                            const SizedBox(width: 4),
                            Text(
                              '${lobby.jugadores.length}/${lobby.maxJugadores}',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: accentColor.withOpacity(0.8),
                                  fontFamily: 'Cinzel',
                                  letterSpacing: 1),
                            ),
                            const SizedBox(width: 10),
                            if (lobby.esPrivada)
                              Icon(Icons.lock,
                                  size: 9, color: accentColor.withOpacity(0.6)),
                          ]),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: accentColor.withOpacity(0.40), width: 1),
                      ),
                      child: Text(estado,
                          style: TextStyle(
                              fontSize: 8,
                              color: accentColor,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SELECTOR MODO TURNO
// ─────────────────────────────────────────────────────────────
class _ModoTurnoSelector extends StatelessWidget {
  final ModoTurno selected;
  final void Function(ModoTurno) onChanged;

  const _ModoTurnoSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModoOption(
          label: 'PARTIDA RÁPIDA',
          icon: Icons.bolt,
          accent: const Color(0xFF4ABB58),
          isSelected: selected == ModoTurno.rapida,
          onTap: () => onChanged(ModoTurno.rapida),
          info: selected == ModoTurno.rapida
              ? 'Los turnos durarán 30 segundos. Para pausar la partida '
                  'todos los miembros deben salir; cuando uno entre se '
                  'resolverá el turno y empezará el siguiente.'
              : null,
        ),
        const SizedBox(height: 8),
        _ModoOption(
          label: 'TURNO DIARIO',
          icon: Icons.schedule,
          accent: const Color(0xFF4080C0),
          isSelected: selected == ModoTurno.diario,
          onTap: () => onChanged(ModoTurno.diario),
          info: selected == ModoTurno.diario
              ? 'Los turnos se resolverán a las 00:00 UTC. '
                  'Si todos los miembros han finalizado el turno en el mismo '
                  'día se podrá jugar otro turno. '
                  'Hora UTC actual: ${_horaUTC()}'
              : null,
        ),
      ],
    );
  }

  static String _horaUTC() {
    final now = DateTime.now().toUtc();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')} UTC';
  }
}

class _ModoOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool isSelected;
  final VoidCallback onTap;
  final String? info;

  const _ModoOption({
    required this.label,
    required this.icon,
    required this.accent,
    required this.isSelected,
    required this.onTap,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              isSelected ? accent.withOpacity(0.08) : const Color(0xFF050A14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                isSelected ? accent.withOpacity(0.60) : const Color(0x25506070),
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon,
                  size: 13,
                  color: isSelected ? accent : const Color(0xFF506070)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? accent : const Color(0xFF506070),
                      fontFamily: 'Cinzel',
                      letterSpacing: 1.5)),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? accent : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? accent : const Color(0xFF506070),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 9, color: Color(0xFF030810))
                    : null,
              ),
            ]),
            if (info != null) ...[
              const SizedBox(height: 8),
              Text(info!,
                  style: TextStyle(
                      fontSize: 8,
                      color: accent.withOpacity(0.75),
                      fontFamily: 'Cinzel',
                      height: 1.7,
                      letterSpacing: 0.3)),
            ],
          ],
        ),
      ),
    );
  }
}
