// lib/widgets/player_hud.dart

import 'package:flutter/material.dart';
import '../models/jugador_model.dart';

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

          // ── Stats: PUNTOS + ENERGIES ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatColumn(
                label: 'PUNTOS',
                value: player.puntos,
                color: color,
              ),
              const SizedBox(width: 10),
              const _StatColumn(
                label: 'ENERGIES',
                value: 0, // Placeholder — se activará más adelante
                color: Color(0xFF3A7ABA),
              ),
            ],
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

// ── Columna de stat (PUNTOS / ENERGIES) ──────────────────────
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
