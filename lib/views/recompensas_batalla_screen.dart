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
/// Además, en el cierre DEFINITIVO de la partida (no en el anticipo por
/// eliminación) muestra la EXPERIENCIA y el ORO ganados por la posición final,
/// que el servidor acredita con la misma tabla ([RecompensaPorPosicion] en
/// WarZeroRecompensas). El crédito REAL lo hace el servidor; esta pantalla solo
/// MUESTRA el desglose con la misma fórmula, así que ambas piezas deben
/// mantenerse sincronizadas.
///
/// Se abre en DOS momentos:
///   · Al terminar la partida (todos los jugadores).
///   · Al quedar ELIMINADO ([eliminado] = true), aunque la batalla siga. En ese
///     caso el servidor ya ha acreditado estos Zero por adelantado
///     (RepartirAnticiposEliminadosAsync): el PC del eliminado está congelado,
///     así que la cifra es definitiva. Lo único que puede subir al final es la
///     experiencia/dinero por posición, y esa diferencia la liquida el servidor.
class RecompensasBatallaScreen extends StatelessWidget {
  /// PC (puntos de combate) del jugador local en la partida.
  final int pc;

  /// Ejército con el que jugó (define la moneda donde se acredita el Zero).
  final int? ejercitoId;

  /// True si el jugador local ganó la partida (solo afecta al encabezado).
  final bool esGanador;

  /// True cuando la pantalla se abre por ELIMINACIÓN del jugador local y la
  /// batalla continúa entre los demás. Cambia los textos (anticipo) y la
  /// etiqueta del botón de cierre.
  final bool eliminado;

  /// Jugadores que siguen en pie (solo informativo, para el caso [eliminado]).
  final int jugadoresRestantes;

  /// Experiencia ganada por la posición final (0 = desconocida/no aplicable).
  /// Solo se muestra en el cierre definitivo (no en el anticipo por eliminación).
  final int experiencia;

  /// Oro (dinero) ganado por la posición final (0 = desconocido/no aplicable).
  final int oro;

  /// Cuántos PC equivalen a 1 Zero del ejército.
  static const int pcPorZero = 20;

  /// Zero de regalo por participar y no abandonar la batalla.
  static const int bonusParticipacion = 1;

  const RecompensasBatallaScreen({
    super.key,
    required this.pc,
    required this.ejercitoId,
    this.esGanador = false,
    this.eliminado = false,
    this.jugadoresRestantes = 0,
    this.experiencia = 0,
    this.oro = 0,
  });

  /// Zero ganado por combate: PC ÷ [pcPorZero] (redondeo hacia abajo).
  int get zeroCombate => pc ~/ pcPorZero;

  /// Zero total acreditado = combate + bono de participación.
  int get zeroTotal => zeroCombate + bonusParticipacion;

  /// ¿Hay progreso (XP/oro) definitivo que mostrar?
  bool get _muestraProgreso => !eliminado && (experiencia > 0 || oro > 0);

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final moneda = MonedaZeroExt.fromEjercito(ejercitoId ?? 0);
    final acento = moneda.color;
    const oroColor = Color(0xFFC8A860);

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          eliminado ? 'TU RECOMPENSA' : 'RECOMPENSAS DE BATALLA',
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
                      eliminado
                          ? '💀 CUARTEL DESTRUIDO'
                          : (esGanador
                              ? '🏆 ¡VICTORIA!'
                              : 'BATALLA FINALIZADA'),
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.5,
                        fontFamily: 'Cinzel',
                        fontWeight: FontWeight.bold,
                        color: eliminado
                            ? const Color(0xFFCC3030)
                            : (esGanador ? oroColor : war.textoTenue),
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
                    if (eliminado) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A0505),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFCC3030).withOpacity(0.35)),
                        ),
                        child: Text(
                          jugadoresRestantes > 0
                              ? 'La batalla continúa entre $jugadoresRestantes '
                                  'comandantes, pero tu recompensa ya es tuya: '
                                  'tus PC están cerrados y se te ha acreditado ya.'
                              : 'Tu recompensa ya es tuya: tus PC están cerrados '
                                  'y se te ha acreditado sin esperar al final.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            height: 1.6,
                            fontFamily: 'Cinzel',
                            color: Color(0xFF8A6060),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Tarjeta de desglose de Cristales Zero.
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

                    // Tarjeta de EXPERIENCIA / ORO por posición final (solo en el
                    // cierre definitivo de la partida).
                    if (_muestraProgreso) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: war.superficie,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: oroColor.withOpacity(0.30)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text('✨', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'PROGRESO DE COMANDANTE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1.5,
                                      fontFamily: 'Cinzel',
                                      fontWeight: FontWeight.bold,
                                      color: war.texto,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _filaDesglose(
                              war,
                              etiqueta: 'Experiencia ganada',
                              detalle: 'Según tu posición final',
                              valor: '+$experiencia XP',
                              valorColor: oroColor,
                            ),
                            if (oro > 0) ...[
                              _sep(war),
                              _filaDesglose(
                                war,
                                etiqueta: 'Oro ganado',
                                valor: '+$oro',
                                valorColor: const Color(0xFFD4A800),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    Text(
                      eliminado
                          ? 'Los $zeroTotal ${moneda.label} se han sumado ya a tu '
                              'saldo del ejército. Cuando la partida termine, si '
                              'quedas 1º o 2º por PC recibirás además la '
                              'experiencia y el dinero extra de esa posición.'
                          : 'Los $zeroTotal ${moneda.label} se han sumado a tu saldo '
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
                    eliminado ? 'CONTINUAR' : 'SALIR AL MENÚ',
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
