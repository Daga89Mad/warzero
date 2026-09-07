// lib/views/historia_hud.dart
//
// Banner de OBJETIVO del modo historia, sobrepuesto en la parte superior del
// tablero durante la partida. Muestra el objetivo del jugador y, si es de
// supervivencia, el progreso de turnos ("AGUANTA · TURNO 3/6").
//
// Se alimenta de la config `historia` que GameScreen recibe por constructor y
// del turno actual del tablero. Es puramente informativo (IgnorePointer en el
// punto de inserción), así que no interfiere con los toques del tablero.

import 'package:flutter/material.dart';

class HistoriaObjetivoHud extends StatelessWidget {
  /// Config de historia (campo `historia` del estado de la partida).
  final Map<String, dynamic> historia;

  /// Turno actual de la partida (1..N).
  final int turnoActual;

  const HistoriaObjetivoHud({
    super.key,
    required this.historia,
    required this.turnoActual,
  });

  @override
  Widget build(BuildContext context) {
    final objetivo = (historia['jugadorObjetivo'] ?? 'sobrevivir').toString();
    final total = (historia['turnosSupervivencia'] as num?)?.toInt() ?? 0;

    final IconData icono;
    final String texto;
    if (objetivo == 'conquistar') {
      icono = Icons.local_fire_department_rounded;
      texto = 'CONQUISTA EL CUARTEL';
    } else {
      icono = Icons.shield_rounded;
      final actual = total > 0 ? turnoActual.clamp(1, total) : turnoActual;
      texto =
          total > 0 ? 'AGUANTA · TURNO $actual/$total' : 'AGUANTA EL ASEDIO';
    }

    const oro = Color(0xFFC8A860);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A).withOpacity(0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: oro.withOpacity(0.55)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: oro),
          const SizedBox(width: 8),
          Text(
            texto,
            style: const TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: oro,
            ),
          ),
        ],
      ),
    );
  }
}
