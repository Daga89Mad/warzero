// lib/views/menu.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:warzero/views/loginBody.dart';
import 'package:warzero/views/settingsScreen.dart';
import 'package:warzero/views/lobby_screen.dart';
import 'package:warzero/views/mazo_screen.dart';
import 'package:warzero/views/cartas_screen.dart';
import 'package:warzero/views/perfil_screen.dart';
import 'package:warzero/views/crear_carta_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({Key? key}) : super(key: key);

  Future<void> _signOutAndGoToLogin(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginBody()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final alias =
        user?.displayName ?? user?.email?.split('@').first ?? 'Comandante';

    return Scaffold(
      backgroundColor: const Color(0xFF030810),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: const BoxDecoration(
                color: Color(0xFF02050D),
                border: Border(
                    bottom: BorderSide(color: Color(0x20C8A860), width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WARZERO',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFC8A860),
                            fontFamily: 'Cinzel',
                            letterSpacing: 8,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'BIENVENIDO, ${alias.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF506070),
                            fontFamily: 'Cinzel',
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botón de acceso rápido al perfil
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PerfilScreen())),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF080D18),
                        border: Border.all(
                            color: const Color(0xFFC8A860).withOpacity(0.3),
                            width: 1),
                      ),
                      child: const Icon(Icons.person_outline,
                          size: 20, color: Color(0xFFC8A860)),
                    ),
                  ),
                ],
              ),
            ),

            // ── Grid de opciones ─────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
                    _MenuTile(
                      icon: Icons.public,
                      label: 'JUGAR',
                      sublabel: 'Unirse o crear\nuna partida',
                      accent: const Color(0xFF4ABB58),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LobbyScreen()),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.style,
                      label: 'MAZOS',
                      sublabel: 'Gestiona tus\nmazos por ejército',
                      accent: const Color(0xFFC8A860),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MazoScreen()),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.collections_bookmark_outlined,
                      label: 'CARTAS',
                      sublabel: 'Colección y\npersonalización',
                      accent: const Color(0xFFA040FF),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CartasScreen()),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.person_outline,
                      label: 'PERFIL',
                      sublabel: 'Tu alias e\nimagen de perfil',
                      accent: const Color(0xFF40C0D0),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PerfilScreen()),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.add_card,
                      label: 'CREAR CARTA',
                      sublabel: 'Diseña nuevas\ncartas para el juego',
                      accent: const Color(0xFFA040C0),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CrearCartaScreen()),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.emoji_events_outlined,
                      label: 'RANKINGS',
                      sublabel: 'Clasificaciones\nglobales',
                      accent: const Color(0xFFD06040),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Próximamente',
                                style: TextStyle(fontFamily: 'Cinzel')),
                            backgroundColor: Color(0xFF1A1408),
                          ),
                        );
                      },
                    ),
                    _MenuTile(
                      icon: Icons.settings_outlined,
                      label: 'AJUSTES',
                      sublabel: 'Configuración\ny cuenta',
                      accent: const Color(0xFF4060D0),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Logout ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: GestureDetector(
                onTap: () => _signOutAndGoToLogin(context),
                child: Container(
                  width: double.infinity,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border:
                        Border.all(color: const Color(0x30C04040), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, size: 14, color: Color(0xFF7A4040)),
                      SizedBox(width: 8),
                      Text(
                        'CERRAR SESIÓN',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF7A4040),
                          fontFamily: 'Cinzel',
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
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
// TILE DEL MENÚ
// ─────────────────────────────────────────────────────────────
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color accent;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.accent,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF080D18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.25), width: 1),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withOpacity(0.30), width: 1),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: accent,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sublabel,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  height: 1.6,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
