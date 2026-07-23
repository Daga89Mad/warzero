// lib/views/puntuaciones_screen.dart

import 'package:flutter/material.dart';
import '../services/settings_controller.dart';

/// Fila de puntuación de un jugador en la partida actual.
class PuntuacionJugador {
  final String alias;
  final Color color;
  final int victorias;
  final int derrotas;
  final int pc;
  final bool eliminado;
  final bool esLocal;

  const PuntuacionJugador({
    required this.alias,
    required this.color,
    required this.victorias,
    required this.derrotas,
    required this.pc,
    this.eliminado = false,
    this.esLocal = false,
  });
}

/// PUNTUACIONES de la partida en curso:
///   · V / D: se cuentan POR COMBATE (ganar un combate = +1 V; cada grupo
///     destruido = +1 D). No son "partidas ganadas".
///   · PC: 3 por cada carta enemiga destruida + 100 por conquistar un cuartel.
class PuntuacionesScreen extends StatelessWidget {
  final String nombrePartida;
  final List<PuntuacionJugador> jugadores;

  const PuntuacionesScreen({
    super.key,
    required this.nombrePartida,
    required this.jugadores,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    // Orden: más PC primero; a igualdad, más victorias.
    final filas = [...jugadores]..sort((a, b) {
        final c = b.pc.compareTo(a.pc);
        return c != 0 ? c : b.victorias.compareTo(a.victorias);
      });

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        title: Text(
          'PUNTUACIONES',
          style: TextStyle(
            fontSize: 15,
            letterSpacing: 3,
            color: war.primario,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                nombrePartida.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: war.textoTenue,
                  fontFamily: 'Cinzel',
                ),
              ),
            ),
          ),
          // Cabecera de columnas.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 24),
                Expanded(child: _colHeader('JUGADOR', war, alignStart: true)),
                SizedBox(width: 44, child: _colHeader('V', war)),
                SizedBox(width: 44, child: _colHeader('D', war)),
                SizedBox(width: 60, child: _colHeader('PC', war)),
              ],
            ),
          ),
          Divider(height: 1, color: war.borde.withOpacity(0.3)),
          Expanded(
            child: filas.isEmpty
                ? Center(
                    child: Text('Sin datos de puntuación todavía.',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 10,
                            color: war.textoTenue)),
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _FilaPuntuacion(
                      posicion: i + 1,
                      jugador: filas[i],
                    ),
                  ),
          ),
          const _LeyendaPC(),
        ],
      ),
    );
  }

  Widget _colHeader(String t, WarColors war, {bool alignStart = false}) => Text(
        t,
        textAlign: alignStart ? TextAlign.start : TextAlign.center,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1.5,
          color: war.textoTenue,
          fontFamily: 'Cinzel',
          fontWeight: FontWeight.bold,
        ),
      );
}

class _FilaPuntuacion extends StatelessWidget {
  final int posicion;
  final PuntuacionJugador jugador;
  const _FilaPuntuacion({required this.posicion, required this.jugador});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final acento = jugador.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: jugador.esLocal
              ? war.primario.withOpacity(0.5)
              : acento.withOpacity(0.25),
          width: jugador.esLocal ? 1.2 : 1,
        ),
      ),
      child: Opacity(
        opacity: jugador.eliminado ? 0.55 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$posicion',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold,
                  color: war.textoTenue,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: acento,
                      boxShadow: [
                        BoxShadow(
                            color: acento.withOpacity(0.5), blurRadius: 5),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      jugador.alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cinzel',
                        fontWeight: FontWeight.bold,
                        color: war.texto,
                      ),
                    ),
                  ),
                  if (jugador.esLocal) ...[
                    const SizedBox(width: 6),
                    _tag('TÚ', war.primario),
                  ],
                  if (jugador.eliminado) ...[
                    const SizedBox(width: 6),
                    _tag('ELIMINADO', war.error),
                  ],
                ],
              ),
            ),
            SizedBox(
                width: 44,
                child: _num('${jugador.victorias}', const Color(0xFF4ABB58))),
            SizedBox(width: 44, child: _num('${jugador.derrotas}', war.error)),
            SizedBox(
                width: 60,
                child: _num('${jugador.pc}', war.primario, bold: true)),
          ],
        ),
      ),
    );
  }

  Widget _num(String t, Color c, {bool bold = false}) => Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'Cinzel',
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: c,
        ),
      );

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: c.withOpacity(0.5), width: 0.8),
        ),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 7,
            letterSpacing: 1,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
            color: c,
          ),
        ),
      );
}

class _LeyendaPC extends StatelessWidget {
  const _LeyendaPC();

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: war.superficie.withOpacity(0.5),
        border: Border(top: BorderSide(color: war.borde.withOpacity(0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CÓMO SE PUNTÚA',
              style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.5,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold,
                  color: war.primario)),
          const SizedBox(height: 6),
          Text(
            'V / D: victorias y derrotas por COMBATE (no partidas). Ganar un '
            'combate suma 1 V; cada grupo destruido suma 1 D.\n'
            'PC: 3 por cada carta enemiga destruida + 100 por conquistar un '
            'cuartel. No depende de ganar, sino de cuánto destruyes.',
            style: TextStyle(
                fontSize: 9,
                height: 1.6,
                fontFamily: 'Cinzel',
                color: war.textoTenue),
          ),
        ],
      ),
    );
  }
}
