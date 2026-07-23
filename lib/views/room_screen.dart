// lib/views/room_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:warzero/services/settings_controller.dart';
import '../models/lobby_model.dart';
import '../services/ejercito_service.dart';
import '../services/lobby_service.dart';
import '../services/warzero_api.dart';
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
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WarZeroApi().despertar();
  }

  Future<void> _selectEjercito(int ejercitoId) async {
    setState(() => _selectedEjercitoId = ejercitoId);
    await _service.seleccionarEjercito(
      lobbyId: widget.lobbyId,
      uid: widget.localUid,
      ejercitoId: ejercitoId,
    );
  }

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

  Future<void> _iniciarPartida(LobbyModel lobby) async {
    await _service.iniciarPartida(widget.lobbyId);
    _goToGame(lobby);
  }

  Future<void> _salir() async {
    await _service.salirDeLobby(lobbyId: widget.lobbyId, uid: widget.localUid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return WillPopScope(
      onWillPop: () async {
        await _salir();
        return false;
      },
      child: Scaffold(
        backgroundColor: war.fondo,
        body: StreamBuilder<LobbyModel?>(
          stream: _service.lobbyStream(widget.lobbyId),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(color: war.primario));
            }
            final lobby = snap.data;
            if (lobby == null) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => Navigator.of(context).pop());
              return const SizedBox();
            }

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
                  _RoomHeader(
                    lobby: lobby,
                    isHost: isHost,
                    onLeave: _salir,
                  ),
                  Divider(color: war.primario.withOpacity(0.12), height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _PlayerList(
                            lobby: lobby,
                            localUid: widget.localUid,
                          ),
                        ),
                        Container(
                            width: 1, color: war.primario.withOpacity(0.12)),
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
    final war = context.war;
    return Container(
      color: war.superficie,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onLeave,
            child: Icon(Icons.arrow_back_ios, size: 16, color: war.textoTenue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lobby.nombre.toUpperCase(),
                  style: TextStyle(
                    fontSize: 15,
                    color: war.primario,
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (lobby.esPrivada) ...[
                      Icon(Icons.lock, size: 9, color: war.textoTenue),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      'SALA · ${lobby.jugadores.length}/${lobby.maxJugadores}',
                      style: TextStyle(
                        fontSize: 9,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: lobby.id));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('ID copiado al portapapeles',
                    style: TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
                backgroundColor: war.superficie,
                duration: const Duration(seconds: 2),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: war.fondo,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: war.borde.withOpacity(0.3), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.copy, size: 11, color: war.textoTenue),
                  const SizedBox(width: 5),
                  Text(
                    lobby.id.length > 8
                        ? '${lobby.id.substring(0, 8)}…'
                        : lobby.id,
                    style: TextStyle(
                      fontSize: 8,
                      color: war.textoTenue,
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
    final war = context.war;
    final slots = List<LobbyJugador?>.from(lobby.jugadores);
    while (slots.length < lobby.maxJugadores) {
      slots.add(null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text(
            'COMANDANTES',
            style: TextStyle(
              fontSize: 9,
              color: war.textoTenue,
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
    final war = context.war;
    final isEmpty = jugador == null;
    final accent = isEmpty
        ? war.borde
        : jugador!.listo
            ? war.secundario
            : isLocal
                ? war.primario
                : const Color(0xFF4060D0); // azul remoto: semántico

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isEmpty ? war.fondo : war.superficie,
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
                      size: 14, color: accent.withOpacity(0.5))
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
                ? Text(
                    'ESPERANDO…',
                    style: TextStyle(
                      fontSize: 8,
                      color: war.borde,
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
                            style: TextStyle(
                              fontSize: 9,
                              color: war.primario,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1,
                            ),
                          ),
                          if (isHost) ...[
                            const SizedBox(width: 5),
                            Icon(Icons.star, size: 9, color: war.primario),
                          ],
                          if (isLocal) ...[
                            const SizedBox(width: 5),
                            Text(
                              'TÚ',
                              style: TextStyle(
                                fontSize: 7,
                                color: war.secundario,
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
                          style: TextStyle(
                            fontSize: 7,
                            color: war.textoTenue,
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
                color: jugador!.listo ? war.secundario : war.textoTenue,
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
class _ArmySelector extends StatelessWidget {
  final int? selectedId;
  final void Function(int) onSelect;

  const _ArmySelector({required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text(
            'ELIGE TU EJÉRCITO',
            style: TextStyle(
              fontSize: 9,
              color: war.textoTenue,
              fontFamily: 'Cinzel',
              letterSpacing: 2,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<EjercitoInfo>>(
            stream: EjercitoService().ejercitosStream(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: war.primario),
                );
              }
              if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                return Center(
                  child: Text('Sin ejércitos disponibles',
                      style: TextStyle(
                          fontSize: 9,
                          color: war.textoTenue,
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
    final war = context.war;
    final accent = isSelected ? war.primario : war.borde;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? war.primario.withOpacity(0.08) : war.superficie,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withOpacity(isSelected ? 0.60 : 0.20),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: war.primario.withOpacity(0.08),
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
                      color: isSelected ? war.primario : war.texto,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ejercito.descripcion,
                    style: TextStyle(
                      fontSize: 8,
                      color: war.textoTenue,
                      fontFamily: 'Cinzel',
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 18, color: war.primario),
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
    final war = context.war;
    final me = lobby.jugadores.firstWhere((j) => j.uid == localUid,
        orElse: () => LobbyJugador(uid: localUid, alias: 'Jugador'));
    final mismoEjercito = selectedEjercito ?? me.ejercitoId;
    final canStart = isHost && lobby.todosListos && lobby.jugadores.length >= 2;
    final hasEjercito = mismoEjercito != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: war.superficie,
        border: Border(
            top: BorderSide(color: war.primario.withOpacity(0.12), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${lobby.jugadores.where((j) => j.listo).length}/${lobby.jugadores.length} LISTOS',
                  style: TextStyle(
                    fontSize: 9,
                    color: war.textoTenue,
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
                    backgroundColor: war.fondo,
                    valueColor: AlwaysStoppedAnimation<Color>(war.secundario),
                    minHeight: 4,
                  ),
                ),
                if (!hasEjercito) ...[
                  const SizedBox(height: 6),
                  Text(
                    '← Elige un ejército para estar listo',
                    style: TextStyle(
                        fontSize: 8,
                        color: war.error,
                        fontFamily: 'Cinzel',
                        letterSpacing: 0.5),
                  ),
                ] else if (isHost && !lobby.todosListos) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Esperando a que todos elijan ejército',
                    style: TextStyle(
                        fontSize: 8,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        letterSpacing: 0.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (isHost)
            GestureDetector(
              onTap: canStart ? onStart : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: canStart ? war.primario.withOpacity(0.18) : war.fondo,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: canStart
                        ? war.primario.withOpacity(0.6)
                        : war.borde.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  'INICIAR BATALLA',
                  style: TextStyle(
                    fontSize: 11,
                    color: canStart ? war.primario : war.textoTenue,
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
                color: me.listo ? war.secundario.withOpacity(0.10) : war.fondo,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: me.listo
                      ? war.secundario.withOpacity(0.4)
                      : war.borde.withOpacity(0.3),
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
                      ? war.secundario
                      : me.ejercitoId == null
                          ? war.error
                          : war.textoTenue,
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
