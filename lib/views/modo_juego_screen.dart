// lib/views/modo_juego_screen.dart

import 'package:flutter/material.dart';

import 'package:warzero/models/torneo_model.dart';
import 'package:warzero/services/settings_controller.dart';
import 'package:warzero/services/torneos_service.dart';
import 'package:warzero/views/duelos/duelos_lobby_screen.dart';
import 'package:warzero/views/lobby_screen.dart';
import 'package:warzero/views/modo_historia_screen.dart';
import 'package:warzero/views/retos_screen.dart';
import 'package:warzero/views/torneos_screen.dart';

/// Pantalla intermedia tras pulsar JUGAR.
class ModoJuegoScreen extends StatefulWidget {
  const ModoJuegoScreen({super.key});

  @override
  State<ModoJuegoScreen> createState() => _ModoJuegoScreenState();
}

class _ModoJuegoScreenState extends State<ModoJuegoScreen> {
  final _torneos = TorneosService();

  /// null = cargando.
  TorneoVigente? _torneo;

  @override
  void initState() {
    super.initState();
    _cargarTorneo();
  }

  Future<void> _cargarTorneo() async {
    final v = await _torneos.vigente();
    if (mounted) setState(() => _torneo = v);
  }

  /// Texto bajo el botón TORNEOS, si está habilitado y texto del candado.
  ({String sublabel, bool enabled, String lock}) _estadoTorneo() {
    final v = _torneo;
    if (v == null) {
      return (sublabel: 'Consultando torneos…', enabled: false, lock: 'CARGANDO');
    }
    final t = v.torneo;
    if (t == null) {
      return (sublabel: 'No hay torneos', enabled: false, lock: 'NO HAY TORNEOS');
    }
    final fechas = 'Inscripción ${fechaCortaTorneo(t.inicioInscripcion)}'
        ' – ${fechaCortaTorneo(t.finInscripcion)}';
    if (v.inscripcionPendiente) {
      return (
        sublabel: '${t.nombre}\n$fechas',
        enabled: false,
        lock: 'ABRE EL ${fechaCortaTorneo(t.inicioInscripcion)}',
      );
    }
    if (v.inscripcionAbierta) {
      return (
        sublabel: v.inscrito ? '${t.nombre}\nYa estás inscrito' : '${t.nombre}\n$fechas',
        enabled: true,
        lock: '',
      );
    }
    // Inscripción cerrada: solo entra quien participa (para ver sus grupos).
    if (v.inscrito) {
      return (
        sublabel: v.gruposSorteados
            ? '${t.nombre}\nGrupos sorteados'
            : '${t.nombre}\nEmpieza ${fechaCortaTorneo(t.inicioTorneo)}',
        enabled: true,
        lock: '',
      );
    }
    return (sublabel: '${t.nombre}\n$fechas', enabled: false, lock: 'INSCRIPCIÓN CERRADA');
  }

  @override
  Widget build(BuildContext context) {
    final torneo = _estadoTorneo();
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
                sublabel: torneo.sublabel,
                accent: const Color(0xFFE04444),
                enabled: torneo.enabled,
                lockText: torneo.lock,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TorneosScreen(inicial: _torneo),
                    ),
                  );
                  _cargarTorneo();
                },
              ),
              _ModoTile(
                icon: Icons.hexagon_outlined,
                label: 'BATALLAS',
                sublabel: 'Batallas de Nexos',
                accent: const Color(0xFF9B5CFF),
                enabled: false,
              ),
              _ModoTile(
                icon: Icons.sports_kabaddi_outlined,
                label: 'DUELOS',
                sublabel: 'Dos generales y un Comandante que proteger',
                accent: const Color(0xFF40C08A),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DuelosLobbyScreen(),
                    ),
                  );
                },
              ),
              _ModoTile(
                icon: Icons.groups_outlined,
                label: 'COOPERATIVO',
                sublabel: 'Juega en equipo con tus amigos',
                accent: const Color(0xFF30B8C8),
                enabled: false,
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
  final VoidCallback? onTap;
  final bool enabled;

  /// Texto del candado cuando está deshabilitado.
  final String lockText;

  const _ModoTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.accent,
    this.onTap,
    this.enabled = true,
    this.lockText = 'PRÓXIMAMENTE',
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    final contenido = Container(
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
    );

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: enabled
          ? contenido
          : Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: 0.45, child: contenido),
                Positioned.fill(
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: war.superficie,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: accent.withOpacity(0.7), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 12, color: accent),
                          const SizedBox(width: 5),
                          Flexible(
                           child: Text(
                            lockText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 8,
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                           ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
