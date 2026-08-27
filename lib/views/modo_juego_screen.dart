// lib/views/modo_juego_screen.dart

import 'package:flutter/material.dart';

import 'package:warzero/services/settings_controller.dart';
import 'package:warzero/views/lobby_screen.dart';
import 'package:warzero/views/modo_historia_screen.dart';
import 'package:warzero/views/retos_screen.dart';

/// Pantalla intermedia tras pulsar JUGAR.
class ModoJuegoScreen extends StatelessWidget {
  const ModoJuegoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text(
          'JUGAR',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Cinzel',
            letterSpacing: 3,
            color: war.primario,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,

            // Espacio horizontal entre botones
            crossAxisSpacing: 12,

            // Espacio vertical entre botones
            mainAxisSpacing: 12,

            // 1 = botones cuadrados
            childAspectRatio: 1,

            children: [
              _ModoTile(
                icon: Icons.auto_stories_outlined,
                label: 'MODO HISTORIA',
                sublabel: 'Campañas por ejército y retos',
                accent: const Color(0xFFE0A030),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ModoHistoriaScreen(),
                    ),
                  );
                },
              ),
              _ModoTile(
                icon: Icons.public,
                label: 'MODO PARTIDA',
                sublabel: 'Unirse o crear una partida',
                accent: const Color(0xFF4ABB58),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LobbyScreen(),
                    ),
                  );
                },
              ),
              _ModoTile(
                icon: Icons.flag_outlined,
                label: 'RETOS',
                sublabel: 'Completa desafíos especiales',
                accent: const Color(0xFF3F8CFF),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RetosScreen(),
                    ),
                  );
                },
              ),
              _ModoTile(
                icon: Icons.emoji_events_outlined,
                label: 'TORNEOS',
                sublabel: 'Compite contra otros jugadores',
                accent: const Color(0xFFE04444),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LobbyScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color accent;
  final VoidCallback onTap;

  const _ModoTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent.withOpacity(0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: accent.withOpacity(0.30),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 25,
                  color: accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: accent,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sublabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: war.textoTenue,
                  fontFamily: 'Cinzel',
                  height: 1.4,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
