// lib/views/amigos_screen.dart

import 'package:flutter/material.dart';
import '../services/settings_controller.dart';

/// AMIGOS — placeholder "Próximamente".
///
/// Pantalla temporal para el botón de Amigos del menú. Cuando se implemente la
/// funcionalidad (lista de amigos, invitaciones, etc.) se sustituye el cuerpo.
class AmigosScreen extends StatelessWidget {
  const AmigosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('AMIGOS',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: war.primario)),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: war.superficie,
                border: Border.all(color: war.primario.withOpacity(0.3)),
              ),
              child: Icon(Icons.group_outlined, size: 40, color: war.primario),
            ),
            const SizedBox(height: 20),
            Text(
              'PRÓXIMAMENTE',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 16,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
                color: war.primario,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'La sección de amigos estará disponible muy pronto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                  height: 1.6,
                  color: war.textoTenue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
