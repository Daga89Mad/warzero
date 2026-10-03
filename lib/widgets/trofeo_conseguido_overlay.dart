// lib/widgets/trofeo_conseguido_overlay.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/trofeo_model.dart';

/// Muestra el pop-up "¡TROFEO CONSEGUIDO!" para cada trofeo de [trofeos], uno
/// detrás de otro (se pueden ganar varios en la misma resolución de turno).
///
/// Espera a que el jugador cierre cada uno antes de abrir el siguiente, así que
/// el `await` no vuelve hasta que se han visto todos. Si el widget que lo llamó
/// se desmonta a medias, se corta sin más.
///
/// Es seguro llamarlo con una lista vacía: no hace nada.
Future<void> mostrarTrofeosConseguidos(
  BuildContext context,
  List<TrofeoModel> trofeos,
) async {
  if (trofeos.isEmpty) return;
  for (int i = 0; i < trofeos.length; i++) {
    if (!context.mounted) return;
    await _mostrarUno(context, trofeos[i], i + 1, trofeos.length);
  }
}

Future<void> _mostrarUno(
  BuildContext context,
  TrofeoModel trofeo,
  int indice,
  int total,
) {
  return showGeneralDialog<void>(
    context: context,
    // A propósito NO se puede cerrar tocando fuera: es un logro, no un aviso de
    // paso. Se cierra con su botón, y así no se descarta por un toque perdido.
    barrierDismissible: false,
    barrierLabel: 'trofeo conseguido',
    barrierColor: Colors.black.withOpacity(0.86),
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: (ctx, anim, _, child) {
      final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1.0).animate(curva),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, __) => _TrofeoConseguidoPage(
      trofeo: trofeo,
      indice: indice,
      total: total,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
class _TrofeoConseguidoPage extends StatefulWidget {
  final TrofeoModel trofeo;
  final int indice;
  final int total;

  const _TrofeoConseguidoPage({
    required this.trofeo,
    required this.indice,
    required this.total,
  });

  @override
  State<_TrofeoConseguidoPage> createState() => _TrofeoConseguidoPageState();
}

class _TrofeoConseguidoPageState extends State<_TrofeoConseguidoPage>
    with SingleTickerProviderStateMixin {
  /// Latido del halo dorado tras el icono. Se repite mientras el pop-up vive.
  late final AnimationController _pulso;

  @override
  void initState() {
    super.initState();
    _pulso = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const oro = Color(0xFFE8C870);
    const oroTenue = Color(0xFFC8A860);
    final pantalla = MediaQuery.of(context).size;
    final ancho = math.min(pantalla.width - 40.0, 380.0);

    // Techo de alto del diálogo. Sin él (y sin el SingleChildScrollView de más
    // abajo) un trofeo con nombre y descripción largos desborda en vertical en
    // pantallas pequeñas — y más aún con la escala de texto de
    // settingsController subida, que es GLOBAL y multiplica todos los tamaños
    // de fuente de la app. Se reservan 40 px arriba y abajo para que el borde
    // dorado no quede pegado al marco del móvil; nunca menos de 200 px, para
    // que en horizontal siga quedando algo visible.
    final altoMax = math.max(pantalla.height - 80.0, 200.0);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: altoMax),
          child: SizedBox(
            width: ancho,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF11213A),
                    Color(0xFF0A1525),
                    Color(0xFF060E18),
                  ],
                ),
                border:
                    Border.all(color: oroTenue.withOpacity(0.75), width: 1.6),
                boxShadow: [
                  BoxShadow(
                      color: oro.withOpacity(0.28),
                      blurRadius: 34,
                      spreadRadius: 2),
                  const BoxShadow(
                      color: Color(0xAA000000),
                      blurRadius: 26,
                      offset: Offset(0, 10)),
                ],
              ),
              // El scroll va DENTRO del recuadro: el marco dorado y su sombra no
              // se mueven, y solo se desplaza el contenido cuando no cabe. Con
              // contenido corto el SingleChildScrollView se ajusta al alto del
              // hijo, así que el diálogo sigue viéndose igual que antes.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Contador, solo si llegan varios de golpe ──
                    if (widget.total > 1) ...[
                      Text(
                        '${widget.indice} / ${widget.total}',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 10,
                          letterSpacing: 2,
                          color: oroTenue.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Titular ──
                    const Text(
                      '¡TROFEO CONSEGUIDO!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.2,
                        color: oro,
                        decoration: TextDecoration.none,
                        shadows: [
                          Shadow(color: Color(0x88E8C870), blurRadius: 14)
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ── Icono con halo latiente ──
                    AnimatedBuilder(
                      animation: _pulso,
                      builder: (ctx, child) {
                        final t = Curves.easeInOut.transform(_pulso.value);
                        return Container(
                          width: 108,
                          height: 108,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: oro.withOpacity(0.06 + 0.06 * t),
                            border: Border.all(
                              color: oro.withOpacity(0.30 + 0.35 * t),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: oro.withOpacity(0.16 + 0.22 * t),
                                blurRadius: 24 + 20 * t,
                                spreadRadius: 1 + 3 * t,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: Text(
                        widget.trofeo.icono,
                        style: const TextStyle(
                          fontSize: 52,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Nombre del trofeo ──
                    Text(
                      widget.trofeo.nombre.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white,
                        height: 1.25,
                        decoration: TextDecoration.none,
                      ),
                    ),

                    // ── Descripción (si el editor puso alguna) ──
                    if (widget.trofeo.descripcion.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.trofeo.descripcion,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 12.5,
                          height: 1.45,
                          color: Color(0xFFB0A090),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],

                    const SizedBox(height: 22),
                    Container(height: 1, color: oroTenue.withOpacity(0.22)),
                    const SizedBox(height: 14),

                    // ── Botón de cierre ──
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: double.infinity,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: oro.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: oro.withOpacity(0.60), width: 1.2),
                        ),
                        child: Text(
                          widget.indice < widget.total
                              ? 'SIGUIENTE'
                              : 'CONTINUAR',
                          style: const TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: oro,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
