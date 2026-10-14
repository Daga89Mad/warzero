// lib/widgets/modo_partida_widgets.dart
//
// Widgets del MODO DE PARTIDA (normal · lluvia de meteoritos · apocalipsis):
//   • ModoPartidaDropdown: desplegable de CREAR SALA con la descripción del
//     modo elegido debajo.
//   • ModoPartidaChip: chip pequeño para listas de salas y la sala de espera.
// Ver models/modo_partida.dart (cliente) y ModosCatastrofe.cs (servidor).

import 'package:flutter/material.dart';
import 'package:warzero/services/settings_controller.dart';

import '../models/modo_partida.dart';

// ─────────────────────────────────────────────────────────────
// DESPLEGABLE MODO DE PARTIDA (normal · lluvia de meteoritos · apocalipsis)
// Debajo del desplegable se muestra la descripción del modo elegido. Ver
// modo_partida.dart (cliente) y ModosCatastrofe.cs (servidor).
// ─────────────────────────────────────────────────────────────
Color modoPartidaColor(ModoPartida m) {
  switch (m) {
    case ModoPartida.meteoritos:
      return const Color(0xFFFF8A3A);
    case ModoPartida.apocalipsis:
      return const Color(0xFFD04A6A);
    case ModoPartida.normal:
      return const Color(0xFF9AA0A6);
  }
}

class ModoPartidaDropdown extends StatelessWidget {
  final ModoPartida selected;
  final void Function(ModoPartida) onChanged;

  const ModoPartidaDropdown({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = modoPartidaColor(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: war.fondo,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected.tieneCatastrofes
                  ? accent.withOpacity(0.6)
                  : war.borde.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ModoPartida>(
              value: selected,
              isExpanded: true,
              dropdownColor: war.superficie,
              iconEnabledColor: war.primario,
              style: TextStyle(
                fontSize: 10,
                color: war.texto,
                fontFamily: 'Cinzel',
                letterSpacing: 1.5,
              ),
              items: ModoPartida.values.map((m) {
                final c = modoPartidaColor(m);
                return DropdownMenuItem<ModoPartida>(
                  value: m,
                  child: Row(
                    children: [
                      Text(m.icono,
                          style: TextStyle(fontSize: 13, color: c)),
                      const SizedBox(width: 8),
                      Text(m.nombre,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: m == selected ? c : war.texto,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1.5)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (m) {
                if (m != null) onChanged(m);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accent.withOpacity(selected.tieneCatastrofes ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withOpacity(0.35), width: 1),
          ),
          child: Text(
            selected.descripcion,
            style: TextStyle(
                fontSize: 8,
                color: accent.withOpacity(0.9),
                fontFamily: 'Cinzel',
                height: 1.7,
                letterSpacing: 0.3),
          ),
        ),
      ],
    );
  }
}

/// Chip pequeño con el modo de partida (listas de salas y sala de espera).
class ModoPartidaChip extends StatelessWidget {
  final ModoPartida modo;
  final double fontSize;

  const ModoPartidaChip({super.key, required this.modo, this.fontSize = 8});

  @override
  Widget build(BuildContext context) {
    final c = modoPartidaColor(modo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.55), width: 1),
      ),
      child: Text(
        '${modo.icono} ${modo.etiqueta}',
        style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: c,
            fontFamily: 'Cinzel',
            letterSpacing: 1),
      ),
    );
  }
}
