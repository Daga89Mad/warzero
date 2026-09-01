// lib/views/recompensas_batalla_screen.dart

import 'package:flutter/material.dart';
import '../models/jugador_model.dart' show MonedaZero, MonedaZeroExt;
import '../services/settings_controller.dart';

/// RECOMPENSAS DE BATALLA
///
/// Desglose de la Energía Zero del ejército que gana el jugador al terminar la
/// partida. Se muestra tras cerrar la tabla de puntuaciones.
///
///   · Combate: los PC se convierten a razón de [pcPorZero] PC = 1 Zero.
///   · Participación: +[bonusParticipacion] Zero por no abandonar la batalla.
///
/// El total se acredita en la moneda (Cristales Zero) del ejército con el que
/// se ha jugado. El crédito REAL lo hace el servidor al finalizar la partida
/// (WarZeroRecompensas); esta pantalla solo MUESTRA el desglose con la misma
/// fórmula, así que ambas piezas deben mantenerse sincronizadas.
class RecompensasBatallaScreen extends StatelessWidget {
  /// PC (puntos de combate) del jugador local en la partida.
  final int pc;

  /// Ejército con el que jugó (define la moneda donde se acredita el Zero).
  final int? ejercitoId;

  /// True si el jugador local ganó la partida (solo afecta al encabezado).
  final bool esGanador;

  /// Cuántos PC equivalen a 1 Zero del ejército.
  static const int pcPorZero = 20;

  /// Zero de regalo por participar y no abandonar la batalla.
  static const int bonusParticipacion = 1;

  const RecompensasBatallaScreen({
    super.key,
    required this.pc,
    required this.ejercitoId,
    this.esGanador = false,
  });

  /// Zero ganado por combate: PC ÷ [pcPorZero] (redondeo hacia abajo).
  int get zeroCombate => pc ~/ pcPorZero;

  /// Zero total acreditado = combate + bono de participación.
  int get zeroTotal => zeroCombate + bonusParticipacion;

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final moneda = MonedaZeroExt.fromEjercito(ejercitoId ?? 0);
    final acento = moneda.color;

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'RECOMPENSAS DE BATALLA',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 2.5,
            color: war.primario,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  children: [
                    // Cristal grande del ejército.
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          acento.withOpacity(0.35),
                          acento.withOpacity(0.05),
                        ]),
                        border: Border.all(
                            color: acento.withOpacity(0.6), width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: acento.withOpacity(0.35), blurRadius: 24),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.diamond, size: 44, color: acento),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      esGanador ? '🏆 ¡VICTORIA!' : 'BATALLA FINALIZADA',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.5,
                        fontFamily: 'Cinzel',
                        fontWeight: FontWeight.bold,
                        color: esGanador
                            ? const Color(0xFFC8A860)
                            : war.textoTenue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Energía acreditada en ${moneda.label}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'Cinzel',
                        color: war.textoTenue,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tarjeta de desglose.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: war.superficie,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: acento.withOpacity(0.30)),
                      ),
                      child: Column(
                        children: [
                          _filaDesglose(
                            war,
                            etiqueta: 'Puntos de combate',
                            valor: '$pc PC',
                            valorColor: war.texto,
                          ),
                          _sep(war),
                          _filaDesglose(
                            war,
                            etiqueta: 'Conversión de combate',
                            detalle: '$pcPorZero PC = 1 Zero',
                            valor: '+$zeroCombate',
                            valorColor: acento,
                          ),
                          _sep(war),
                          _filaDesglose(
                            war,
                            etiqueta: 'Bono por no abandonar',
                            detalle: 'Participación completa',
                            valor: '+$bonusParticipacion',
                            valorColor: acento,
                          ),
                          _sep(war, fuerte: true),
                          // Total.
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1.5,
                                    fontFamily: 'Cinzel',
                                    fontWeight: FontWeight.bold,
                                    color: war.texto,
                                  ),
                                ),
                              ),
                              Icon(Icons.diamond, size: 16, color: acento),
                              const SizedBox(width: 6),
                              Text(
                                '+$zeroTotal',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontFamily: 'Cinzel',
                                  fontWeight: FontWeight.bold,
                                  color: acento,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Los $zeroTotal ${moneda.label} se han sumado a tu saldo '
                      'del ejército. Úsalos para abrir sobres y ampliar tu '
                      'colección.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.6,
                        fontFamily: 'Cinzel',
                        color: war.textoTenue,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Botón salir al menú.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: war.primario.withOpacity(0.16),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: war.primario.withOpacity(0.5)),
                    ),
                  ),
                  child: Text(
                    'SALIR AL MENÚ',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      fontFamily: 'Cinzel',
                      fontWeight: FontWeight.bold,
                      color: war.primario,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaDesglose(
    WarColors war, {
    required String etiqueta,
    String? detalle,
    required String valor,
    required Color valorColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.w600,
                  color: war.texto,
                ),
              ),
              if (detalle != null) ...[
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontFamily: 'Cinzel',
                    color: war.textoTenue,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 15,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
            color: valorColor,
          ),
        ),
      ],
    );
  }

  Widget _sep(WarColors war, {bool fuerte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(
          height: 1,
          color: war.borde.withOpacity(fuerte ? 0.55 : 0.25),
        ),
      );
}
