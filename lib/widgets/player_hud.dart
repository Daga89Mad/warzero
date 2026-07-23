// lib/widgets/player_hud.dart

import 'package:flutter/material.dart';
import '../models/jugador_model.dart';

/// Datos de un jugador para el menú desplegable de la barra de partida.
class HudJugadorInfo {
  final String alias;
  final Color color;
  final int zeros;
  final bool esLocal;

  const HudJugadorInfo({
    required this.alias,
    required this.color,
    required this.zeros,
    this.esLocal = false,
  });
}

/// Barra superior de la partida: a la izquierda un botón con menú desplegable
/// (alias de cada jugador con su color y total de Zeros, y "Salir de la
/// partida"), y en el centro el nombre de la partida con un punto del color
/// asignado al jugador local.
/// Barra superior de la partida: a la izquierda un botón con menú desplegable
/// (alias de cada jugador con su color y total de Zeros, y "Salir de la
/// partida"), y en el centro el nombre de la partida con un punto del color
/// asignado al jugador local.
class PartidaTopBar extends StatelessWidget {
  final String nombrePartida;
  final Color colorAsignado;
  final List<HudJugadorInfo> jugadores;
  final VoidCallback onSalir;

  /// Acciones del desplegable, en este orden, ANTES de "Salir de la partida"
  /// (que se mantiene siempre al final). `enabled: false` deja el ítem atenuado
  /// y sin poder pulsarse.
  final bool puedeCuartel;
  final VoidCallback onCuartel;
  final bool puedeInforme;
  final VoidCallback onInforme;
  final bool puedePuntuaciones;
  final VoidCallback onPuntuaciones;
  final bool puedeDeshacer;
  final VoidCallback onDeshacer;

  const PartidaTopBar({
    super.key,
    required this.nombrePartida,
    required this.colorAsignado,
    required this.jugadores,
    required this.onSalir,
    required this.puedeCuartel,
    required this.onCuartel,
    required this.puedeInforme,
    required this.onInforme,
    required this.puedePuntuaciones,
    required this.onPuntuaciones,
    required this.puedeDeshacer,
    required this.onDeshacer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xF202050D),
        border: Border(bottom: BorderSide(color: Color(0x22C8A860), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // ── Botón + menú desplegable de jugadores ──
          PopupMenuButton<String>(
            tooltip: 'Jugadores',
            color: const Color(0xFF0C1828),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: const Color(0xFFC8A860).withOpacity(0.3)),
            ),
            offset: const Offset(0, 44),
            onSelected: (v) {
              if (v == '__salir__') onSalir();
              if (v == '__cuartel__' && puedeCuartel) onCuartel();
              if (v == '__informe__' && puedeInforme) onInforme();
              if (v == '__puntuaciones__' && puedePuntuaciones)
                onPuntuaciones();
              if (v == '__deshacer__' && puedeDeshacer) onDeshacer();
            },
            itemBuilder: (context) => [
              for (int i = 0; i < jugadores.length; i++)
                PopupMenuItem<String>(
                  value: 'jugador_$i',
                  enabled: false,
                  height: 40,
                  child: _FilaJugador(info: jugadores[i]),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: '__cuartel__',
                enabled: puedeCuartel,
                height: 40,
                child: _FilaAccion(
                  icon: Icons.castle,
                  label: 'CUARTEL',
                  color: const Color(0xFFC8A860),
                  enabled: puedeCuartel,
                ),
              ),
              PopupMenuItem<String>(
                value: '__informe__',
                enabled: puedeInforme,
                height: 40,
                child: _FilaAccion(
                  icon: Icons.history,
                  label: 'INFORME',
                  color: const Color(0xFF6AAAD0),
                  enabled: puedeInforme,
                ),
              ),
              PopupMenuItem<String>(
                value: '__puntuaciones__',
                enabled: puedePuntuaciones,
                height: 40,
                child: _FilaAccion(
                  icon: Icons.leaderboard,
                  label: 'PUNTUACIONES',
                  color: const Color(0xFF9AD06A),
                  enabled: puedePuntuaciones,
                ),
              ),
              PopupMenuItem<String>(
                value: '__deshacer__',
                enabled: puedeDeshacer,
                height: 40,
                child: _FilaAccion(
                  icon: Icons.undo,
                  label: 'DESHACER CAMBIOS',
                  color: const Color(0xFFFF8080),
                  enabled: puedeDeshacer,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: '__salir__',
                height: 40,
                child: Row(
                  children: const [
                    Icon(Icons.logout, size: 16, color: Color(0xFFE06060)),
                    SizedBox(width: 10),
                    Text(
                      'Salir de la partida',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cinzel',
                        color: Color(0xFFE06060),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 34,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF0A1525),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x40C8A860), width: 1),
              ),
              child: const Icon(Icons.menu, size: 18, color: Color(0xFFC8A860)),
            ),
          ),

          // ── Nombre de la partida + color asignado ──
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorAsignado,
                    border: Border.all(
                        color: colorAsignado.withOpacity(0.6), width: 1),
                    boxShadow: [
                      BoxShadow(
                          color: colorAsignado.withOpacity(0.5), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    nombrePartida.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Cinzel',
                      letterSpacing: 2,
                      color: Color(0xFFE0D8C0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Espaciador simétrico al botón de la izquierda para centrar el título.
          const SizedBox(width: 34),
        ],
      ),
    );
  }
}

// ── Fila de una acción (Cuartel/Informe/Deshacer) dentro del desplegable ──
/// Misma dinámica visual que tenían los botones del antiguo menú flotante:
/// atenuada y sin interacción cuando `enabled` es false (el propio
/// `PopupMenuItem.enabled` ya bloquea el toque; esto solo replica el estilo).
class _FilaAccion extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;

  const _FilaAccion({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : const Color(0xFF3A4A5A);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Cinzel',
              letterSpacing: 0.5,
              color: c,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un jugador dentro del menú: punto de color · alias · Ø total.
class _FilaJugador extends StatelessWidget {
  final HudJugadorInfo info;
  const _FilaJugador({required this.info});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: info.color,
            border: Border.all(color: info.color.withOpacity(0.7), width: 1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            info.esLocal ? '${info.alias} (tú)' : info.alias,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Cinzel',
              color: info.esLocal
                  ? const Color(0xFFE0D8C0)
                  : const Color(0xFFB0C0D0),
              fontWeight: info.esLocal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${info.zeros} Ø',
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
            color: Color(0xFF2EA6FF),
          ),
        ),
      ],
    );
  }
}

// ── Top HUD (opponent info) ───────────────────────────────────
class TopHudBar extends StatelessWidget {
  final PlayerSession player;
  final int turno;
  final VoidCallback? onBack;

  const TopHudBar({
    super.key,
    required this.player,
    required this.turno,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _HudBar(
      player: player,
      isEnemy: true,
      turno: turno,
      onBack: onBack,
      borderSide:
          const Border(bottom: BorderSide(color: Color(0x3C503214), width: 1)),
    );
  }
}

// ── Bottom HUD (local player info) ────────────────────────────
class BottomHudBar extends StatelessWidget {
  final PlayerSession player;
  final bool isMyTurn;
  final VoidCallback? onEndTurn;
  final String endTurnLabel;

  /// Si es true, el botón fin de turno muestra un spinner "ENVIANDO…".
  final bool isSending;

  const BottomHudBar({
    super.key,
    required this.player,
    required this.isMyTurn,
    this.onEndTurn,
    this.endTurnLabel = 'FIN\nTURNO',
    this.isSending = false,
  });

  @override
  Widget build(BuildContext context) {
    return _HudBar(
      player: player,
      isEnemy: false,
      isMyTurn: isMyTurn,
      onEndTurn: onEndTurn,
      endTurnLabel: endTurnLabel,
      isSending: isSending,
      borderSide:
          const Border(top: BorderSide(color: Color(0x3C283C20), width: 1)),
    );
  }
}

// ── Shared HUD bar ────────────────────────────────────────────
class _HudBar extends StatelessWidget {
  final PlayerSession player;
  final bool isEnemy;
  final bool isMyTurn;
  final int turno;
  final Border borderSide;
  final VoidCallback? onEndTurn;
  final String endTurnLabel;
  final bool isSending;
  final VoidCallback? onBack;

  const _HudBar({
    required this.player,
    required this.isEnemy,
    this.isMyTurn = false,
    this.turno = 0,
    required this.borderSide,
    this.onEndTurn,
    this.endTurnLabel = 'FIN\nTURNO',
    this.isSending = false,
    this.onBack,
  });

  Color get _zoneColor {
    switch (player.zona) {
      case 'north':
        return const Color(0xFFC04040);
      case 'south':
        return const Color(0xFF4ABB58);
      case 'west':
        return const Color(0xFF4060D0);
      case 'east':
        return const Color(0xFFC0A820);
      default:
        return const Color(0xFF888888);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor;
    const maxVida = 20;

    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xEB02050D),
        border: borderSide,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // ── Back button (solo en el HUD del enemigo = parte superior) ──
          if (isEnemy && onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0A1525),
                  border: Border.all(color: const Color(0x40506070), width: 1),
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    size: 13, color: Color(0xFF506070)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // ── Avatar ──
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
              border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            ),
            child: Center(
              child: Text(
                player.alias.isNotEmpty ? player.alias[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'Cinzel',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ── Name + HP bar ──
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.alias.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: Color(0xFFC8A860),
                        fontFamily: 'Cinzel',
                      ),
                    ),
                    if (!isEnemy && isMyTurn) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF50C860).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: const Color(0xFF205A28), width: 0.5),
                        ),
                        child: const Text(
                          'TU TURNO',
                          style: TextStyle(
                              fontSize: 7,
                              color: Color(0xFF50C860),
                              letterSpacing: 1,
                              fontFamily: 'Cinzel'),
                        ),
                      ),
                    ],
                    if (isEnemy && turno > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        'TURNO $turno',
                        style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xFF7A6040),
                            letterSpacing: 1,
                            fontFamily: 'Cinzel'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: player.vida / maxVida,
                          backgroundColor: Colors.white.withOpacity(0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isEnemy
                                ? const Color(0xFFC04040)
                                : const Color(0xFF50C860),
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${player.vida}/$maxVida',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF506070),
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── Stats: ZERO ──
          // player.puntos contiene las energías actuales (leídas de
          // statsPartida.{uid}.energies en Firestore).
          _StatColumn(
            label: 'Ø ZERO',
            value: player.puntos,
            color: const Color(0xFF2EA6FF),
          ),

          // ── End turn button (player only) ──
          if (!isEnemy) ...[
            const SizedBox(width: 8),
            _EndTurnButton(
              label: endTurnLabel,
              onTap: onEndTurn,
              isSending: isSending,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Columna de stat ───────────────────────────────────────────
class _StatColumn extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 6,
            color: Color(0xFF506070),
            letterSpacing: 1.2,
            fontFamily: 'Cinzel',
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'Cinzel',
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

// ── Botón fin de turno con spinner ───────────────────────────
class _EndTurnButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isSending;

  const _EndTurnButton({
    required this.label,
    required this.onTap,
    required this.isSending,
  });

  @override
  Widget build(BuildContext context) {
    if (isSending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0A2010),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF205030), width: 1.2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF50C860),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'ENVIANDO',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7,
                letterSpacing: 1.2,
                color: Color(0xFF50C860),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: onTap != null
              ? const Color(0xFF64460A).withOpacity(0.15)
              : const Color(0xFF5A1A00),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: onTap != null
                ? const Color(0xFF64460A).withOpacity(0.5)
                : const Color(0xFFDD6600),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 8,
            letterSpacing: 1.5,
            color: onTap != null
                ? const Color(0xFFC8A860)
                : const Color(0xFFFFAA55),
            fontFamily: 'Cinzel',
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
