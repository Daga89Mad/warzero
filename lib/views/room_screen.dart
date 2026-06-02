// lib/views/room_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lobby_model.dart';
import '../services/ejercito_service.dart';
import '../services/lobby_service.dart';
import 'game_screen.dart';

// ─────────────────────────────────────────────────────────────
// ROOM SCREEN  (sala de espera con jugadores + selección ejército)
// ─────────────────────────────────────────────────────────────
class RoomScreen extends StatefulWidget {
  final String lobbyId;
  final String localUid;
  final String localAlias;

  const RoomScreen({
    super.key,
    required this.lobbyId,
    required this.localUid,
    required this.localAlias,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final _service = LobbyService();

  int? _selectedEjercitoId;
  bool _navigating = false; // evita doble push

  // Stream cacheado: se crea UNA sola vez. Si se crea en build(), cada
  // reconstrucción del widget abriría una conexión nueva a Firestore, lo que
  // satura el canal y degrada toda la conectividad (incluido el login).
  late final Stream<LobbyModel?> _lobbyStream =
      _service.lobbyStream(widget.lobbyId);

  // ── Seleccionar ejército ──────────────────────────────────
  Future<void> _selectEjercito(int ejercitoId) async {
    setState(() => _selectedEjercitoId = ejercitoId);
    await _service.seleccionarEjercito(
      lobbyId: widget.lobbyId,
      uid: widget.localUid,
      ejercitoId: ejercitoId,
    );
  }

  // ── Navegar al juego (con guard anti-doble-push) ─────────
  void _goToGame(LobbyModel lobby) {
    if (_navigating) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => GameScreen(
          localPlayerUid: widget.localUid,
          playerCount: lobby.maxJugadores,
          lobbyId: widget.lobbyId,
        ),
      ));
    });
  }

  // ── Iniciar partida (solo host) ───────────────────────────
  Future<void> _iniciarPartida(LobbyModel lobby) async {
    await _service.iniciarPartida(widget.lobbyId);
    _goToGame(lobby);
  }

  // ── Salir ─────────────────────────────────────────────────
  Future<void> _salir() async {
    await _service.salirDeLobby(lobbyId: widget.lobbyId, uid: widget.localUid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _salir();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF030810),
        body: StreamBuilder<LobbyModel?>(
          stream: _lobbyStream,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFC8A860)));
            }
            final lobby = snap.data;
            if (lobby == null) {
              // Sala eliminada
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => Navigator.of(context).pop());
              return const SizedBox();
            }

            // ── Auto-navegar ─────────────────────────────────────
            // Cuando el host inicia la partida, Firestore propaga
            // estado='en_curso' a todos los jugadores vía stream.
            if (lobby.estado == LobbyEstado.enCurso) {
              _goToGame(lobby);
            }

            final isHost = lobby.hostUid == widget.localUid;
            final me = lobby.jugadores.firstWhere(
                (j) => j.uid == widget.localUid,
                orElse: () => LobbyJugador(
                    uid: widget.localUid, alias: widget.localAlias));

            return SafeArea(
              child: Column(
                children: [
                  // ── AppBar ──
                  _RoomHeader(
                    lobby: lobby,
                    isHost: isHost,
                    onLeave: _salir,
                  ),

                  const Divider(color: Color(0x20C8A860), height: 1),

                  // ── Contenido ──
                  Expanded(
                    child: Row(
                      children: [
                        // Izquierda: jugadores
                        Expanded(
                          flex: 2,
                          child: _PlayerList(
                            lobby: lobby,
                            localUid: widget.localUid,
                          ),
                        ),

                        Container(width: 1, color: const Color(0x20C8A860)),

                        // Derecha: ejércitos
                        Expanded(
                          flex: 3,
                          child: _ArmySelector(
                            selectedId: _selectedEjercitoId ?? me.ejercitoId,
                            onSelect: _selectEjercito,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Footer ──
                  _RoomFooter(
                    lobby: lobby,
                    isHost: isHost,
                    localUid: widget.localUid,
                    selectedEjercito: _selectedEjercitoId,
                    onStart: () => _iniciarPartida(lobby),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────
class _RoomHeader extends StatelessWidget {
  final LobbyModel lobby;
  final bool isHost;
  final VoidCallback onLeave;

  const _RoomHeader({
    required this.lobby,
    required this.isHost,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF02050D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onLeave,
            child: const Icon(Icons.arrow_back_ios,
                size: 16, color: Color(0xFF506070)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lobby.nombre.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFC8A860),
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (lobby.esPrivada) ...[
                      const Icon(Icons.lock, size: 9, color: Color(0xFF506070)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      'SALA · ${lobby.jugadores.length}/${lobby.maxJugadores}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF506070),
                        fontFamily: 'Cinzel',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Copiar ID
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: lobby.id));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('ID copiado al portapapeles',
                    style: TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
                backgroundColor: Color(0xFF1A1408),
                duration: Duration(seconds: 2),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1220),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0x30506070), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.copy, size: 11, color: Color(0xFF506070)),
                  const SizedBox(width: 5),
                  Text(
                    lobby.id.length > 8
                        ? '${lobby.id.substring(0, 8)}…'
                        : lobby.id,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF506070),
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA DE JUGADORES
// ─────────────────────────────────────────────────────────────
class _PlayerList extends StatelessWidget {
  final LobbyModel lobby;
  final String localUid;

  const _PlayerList({required this.lobby, required this.localUid});

  @override
  Widget build(BuildContext context) {
    // Rellenar con slots vacíos
    final slots = List<LobbyJugador?>.from(lobby.jugadores);
    while (slots.length < lobby.maxJugadores) {
      slots.add(null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text(
            'COMANDANTES',
            style: TextStyle(
              fontSize: 9,
              color: Color(0xFF506070),
              fontFamily: 'Cinzel',
              letterSpacing: 2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: slots.length,
            itemBuilder: (_, i) {
              final j = slots[i];
              return _PlayerSlot(
                jugador: j,
                isLocal: j?.uid == localUid,
                isHost: j?.uid == lobby.hostUid,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  final LobbyJugador? jugador;
  final bool isLocal;
  final bool isHost;

  const _PlayerSlot({
    required this.jugador,
    required this.isLocal,
    required this.isHost,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = jugador == null;
    final accent = isEmpty
        ? const Color(0xFF1A2030)
        : jugador!.listo
            ? const Color(0xFF4ABB58)
            : isLocal
                ? const Color(0xFFC8A860)
                : const Color(0xFF4060D0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isEmpty ? const Color(0x080A1220) : const Color(0xFF080D18),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: accent.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.10),
              border: Border.all(color: accent.withOpacity(0.30), width: 1),
            ),
            child: Center(
              child: isEmpty
                  ? Icon(Icons.person_outline,
                      size: 14, color: accent.withOpacity(0.3))
                  : Text(
                      jugador!.alias.isNotEmpty
                          ? jugador!.alias[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: accent,
                        fontFamily: 'Cinzel',
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEmpty
                ? const Text(
                    'ESPERANDO…',
                    style: TextStyle(
                      fontSize: 8,
                      color: Color(0xFF2A3040),
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            jugador!.alias.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFFC8A860),
                              fontFamily: 'Cinzel',
                              letterSpacing: 1,
                            ),
                          ),
                          if (isHost) ...[
                            const SizedBox(width: 5),
                            const Icon(Icons.star,
                                size: 9, color: Color(0xFFC8A860)),
                          ],
                          if (isLocal) ...[
                            const SizedBox(width: 5),
                            const Text(
                              'TÚ',
                              style: TextStyle(
                                fontSize: 7,
                                color: Color(0xFF4ABB58),
                                fontFamily: 'Cinzel',
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (jugador!.ejercitoId != null)
                        Text(
                          _getEjercitoNombre(jugador!.ejercitoId!),
                          style: const TextStyle(
                            fontSize: 7,
                            color: Color(0xFF506070),
                            fontFamily: 'Cinzel',
                          ),
                        ),
                    ],
                  ),
          ),
          if (!isEmpty)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: jugador!.listo
                    ? const Color(0xFF4ABB58)
                    : const Color(0xFF506070),
              ),
            ),
        ],
      ),
    );
  }

  String _getEjercitoNombre(int id) {
    return 'Ejército $id';
  }
}

// ─────────────────────────────────────────────────────────────
// SELECTOR DE EJÉRCITO
// ─────────────────────────────────────────────────────────────
class _ArmySelector extends StatefulWidget {
  final int? selectedId;
  final void Function(int) onSelect;

  const _ArmySelector({required this.selectedId, required this.onSelect});

  @override
  State<_ArmySelector> createState() => _ArmySelectorState();
}

class _ArmySelectorState extends State<_ArmySelector> {
  // Catálogo estático: una sola lectura, cacheada. (Antes se abría un stream
  // en tiempo real en cada build, una fuga de conexiones.)
  late final Future<List<EjercitoInfo>> _ejercitosFuture =
      EjercitoService().fetchEjercitos();

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    final onSelect = widget.onSelect;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text(
            'ELIGE TU EJÉRCITO',
            style: TextStyle(
              fontSize: 9,
              color: Color(0xFF506070),
              fontFamily: 'Cinzel',
              letterSpacing: 2,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<EjercitoInfo>>(
            future: _ejercitosFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFC8A860)),
                );
              }
              if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                return const Center(
                  child: Text('Sin ejércitos disponibles',
                      style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel')),
                );
              }
              final ejercitos = snap.data!;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: ejercitos.length,
                itemBuilder: (_, i) {
                  final ej = ejercitos[i];
                  return _ArmyCard(
                    ejercito: ej,
                    isSelected: ej.id == selectedId,
                    onTap: () => onSelect(ej.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArmyCard extends StatelessWidget {
  final EjercitoInfo ejercito;
  final bool isSelected;
  final VoidCallback onTap;

  const _ArmyCard({
    required this.ejercito,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isSelected ? const Color(0xFFC8A860) : const Color(0xFF2A3040);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFC8A860).withOpacity(0.08)
              : const Color(0xFF080D18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withOpacity(isSelected ? 0.60 : 0.20),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFC8A860).withOpacity(0.08),
                    blurRadius: 10,
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Text(ejercito.icono, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ejercito.nombre,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? const Color(0xFFC8A860)
                          : const Color(0xFF8A7858),
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ejercito.descripcion,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF506070),
                      fontFamily: 'Cinzel',
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  size: 18, color: Color(0xFFC8A860)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FOOTER
// ─────────────────────────────────────────────────────────────
class _RoomFooter extends StatelessWidget {
  final LobbyModel lobby;
  final bool isHost;
  final String localUid;
  final int? selectedEjercito;
  final VoidCallback onStart;

  const _RoomFooter({
    required this.lobby,
    required this.isHost,
    required this.localUid,
    required this.selectedEjercito,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final me = lobby.jugadores.firstWhere((j) => j.uid == localUid,
        orElse: () => LobbyJugador(uid: localUid, alias: 'Jugador'));
    final mismoEjercito = selectedEjercito ?? me.ejercitoId;
    final canStart = isHost && lobby.todosListos && lobby.jugadores.length >= 2;
    final hasEjercito = mismoEjercito != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF02050D),
        border: Border(top: BorderSide(color: Color(0x20C8A860), width: 1)),
      ),
      child: Row(
        children: [
          // Progreso de listos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${lobby.jugadores.where((j) => j.listo).length}/${lobby.jugadores.length} LISTOS',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF506070),
                    fontFamily: 'Cinzel',
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: lobby.jugadores.isEmpty
                        ? 0
                        : lobby.jugadores.where((j) => j.listo).length /
                            lobby.jugadores.length,
                    backgroundColor: const Color(0xFF0A1220),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF4ABB58)),
                    minHeight: 4,
                  ),
                ),
                if (!hasEjercito) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '← Elige un ejército para estar listo',
                    style: TextStyle(
                        fontSize: 8,
                        color: Color(0xFFC04040),
                        fontFamily: 'Cinzel',
                        letterSpacing: 0.5),
                  ),
                ] else if (isHost && !lobby.todosListos) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Esperando a que todos elijan ejército',
                    style: TextStyle(
                        fontSize: 8,
                        color: Color(0xFF506070),
                        fontFamily: 'Cinzel',
                        letterSpacing: 0.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Botón
          if (isHost)
            GestureDetector(
              onTap: canStart ? onStart : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: canStart
                      ? const Color(0xFFC8A860).withOpacity(0.18)
                      : const Color(0xFF0A1220),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: canStart
                        ? const Color(0xFFC8A860).withOpacity(0.6)
                        : const Color(0x30506070),
                    width: 1,
                  ),
                ),
                child: Text(
                  'INICIAR BATALLA',
                  style: TextStyle(
                    fontSize: 11,
                    color: canStart
                        ? const Color(0xFFC8A860)
                        : const Color(0xFF354050),
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: me.listo
                    ? const Color(0xFF4ABB58).withOpacity(0.10)
                    : const Color(0xFF0A1220),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: me.listo
                      ? const Color(0xFF4ABB58).withOpacity(0.4)
                      : const Color(0x30506070),
                  width: 1,
                ),
              ),
              child: Text(
                me.listo
                    ? '✓ LISTO'
                    : me.ejercitoId == null
                        ? '← ELIGE EJÉRCITO'
                        : 'ESPERANDO A OTROS',
                style: TextStyle(
                  fontSize: 11,
                  color: me.listo
                      ? const Color(0xFF4ABB58)
                      : me.ejercitoId == null
                          ? const Color(0xFFC04040)
                          : const Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  letterSpacing: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
