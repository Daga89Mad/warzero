// lib/widgets/card_detail_overlay.dart

import 'package:flutter/material.dart';
import '../models/carta_model.dart';

/// Muestra la carta en grande al centro de la pantalla.
/// Llamar con [showCardDetail(context, carta)].
Future<void> showCardDetail(BuildContext context, CartaModel carta) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withOpacity(0.82),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, anim, _, child) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
    pageBuilder: (ctx, _, __) => _CardDetailPage(carta: carta),
  );
}

// ─────────────────────────────────────────────────────────────
class _CardDetailPage extends StatelessWidget {
  final CartaModel carta;
  const _CardDetailPage({required this.carta});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        // Tap en cualquier parte fuera cierra
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            // Absorber taps sobre la carta para no cerrar
            onTap: () {},
            child: _CardFace(carta: carta),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARTA FÍSICA
// ─────────────────────────────────────────────────────────────
class _CardFace extends StatelessWidget {
  final CartaModel carta;
  const _CardFace({required this.carta});

  @override
  Widget build(BuildContext context) {
    const cardW = 280.0;
    const cardH = 420.0;

    // coste y evolución aún no están en CartaModel → placeholder
    const int coste = 0; // TODO: carta.coste
    const int evolucion = 0; // TODO: carta.evolucion

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Fondo pergamino oscuro con degradado
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0E1824),
            Color(0xFF0A1218),
            Color(0xFF060E14),
          ],
        ),
        border: Border.all(color: const Color(0xFFC8A860), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC8A860).withOpacity(0.30),
            blurRadius: 32,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // ── Fondo decorativo ──────────────────────────────
            Positioned.fill(child: _CardBackground()),

            // ── Badges en esquinas de la CARTA ────────────────
            // Sup-izquierda: COSTE
            Positioned(
              top: 8,
              left: 8,
              child: _Badge(
                value: '$coste',
                label: 'COSTE',
                icon: Icons.monetization_on_outlined,
                color: const Color(0xFFB08040),
              ),
            ),
            // Sup-derecha: FUERZA
            Positioned(
              top: 8,
              right: 8,
              child: _Badge(
                value: '${carta.fuerza}',
                label: 'FUERZA',
                icon: Icons.bolt,
                color: const Color(0xFFC04040),
              ),
            ),
            // Inf-derecha: MOVIMIENTO
            Positioned(
              bottom: 8,
              right: 8,
              child: _Badge(
                value: '${carta.movimiento}',
                label: 'MOV',
                icon: Icons.open_with,
                color: const Color(0xFF4080C0),
              ),
            ),

            // ── Nombre centrado entre COSTE y FUERZA ──────────
            Positioned(
              top: 0,
              left: 64,
              right: 64,
              height: 52,
              child: Center(
                child: Text(
                  carta.nombre.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE8C870),
                    fontFamily: 'Cinzel',
                    letterSpacing: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),

            // ── Contenido principal ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 52, 14, 52),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Imagen ────────────────────────────────
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFC8A860).withOpacity(0.40),
                            width: 1),
                        color: const Color(0xFF050C14),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: carta.imagen.isNotEmpty
                            ? Image.network(
                                carta.imagen,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _ImagePlaceholder(),
                              )
                            : _ImagePlaceholder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Descripción + Evolución ───────────────
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          carta.descripcion.isNotEmpty
                              ? carta.descripcion
                              : 'Sin descripción.',
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFB0A090),
                            height: 1.7,
                            fontFamily: 'Georgia',
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'EVOLUCIÓN',
                              style: TextStyle(
                                fontSize: 8,
                                color: Color(0xFF7A6A40),
                                fontFamily: 'Cinzel',
                                letterSpacing: 1.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFA040C0).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFFA040C0)
                                        .withOpacity(0.40),
                                    width: 0.8),
                              ),
                              child: Text(
                                '$evolucion',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC060E0),
                                  fontFamily: 'Cinzel',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Ejército ──────────────────────────────
                  Center(
                    child: Text(
                      'EJÉRCITO ${carta.ejercito}',
                      style: const TextStyle(
                        fontSize: 7,
                        color: Color(0xFF506070),
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BADGE (stat en esquina de la imagen)
// ─────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _Badge({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.80),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.60), width: 1),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.25), blurRadius: 6),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Cinzel',
              height: 1,
              shadows: [Shadow(color: color.withOpacity(0.5), blurRadius: 6)],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 6,
              color: color.withOpacity(0.75),
              fontFamily: 'Cinzel',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FONDO DECORATIVO
// ─────────────────────────────────────────────────────────────
class _CardBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CardBgPainter());
  }
}

class _CardBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x10C8A860)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Línea horizontal decorativa superior
    canvas.drawLine(
      Offset(20, 40),
      Offset(size.width - 20, 40),
      paint,
    );
    // Línea horizontal decorativa inferior
    canvas.drawLine(
      Offset(20, size.height - 40),
      Offset(size.width - 20, size.height - 40),
      paint,
    );

    // Ornamentos en las 4 esquinas
    final cornerPaint = Paint()
      ..color = const Color(0x25C8A860)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final (cx, cy, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      canvas.drawLine(
        Offset(cx + sx * 10, cy),
        Offset(cx + sx * 28, cy),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(cx, cy + sy * 10),
        Offset(cx, cy + sy * 28),
        cornerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CardBgPainter _) => false;
}

// ─────────────────────────────────────────────────────────────
// PLACEHOLDER DE IMAGEN
// ─────────────────────────────────────────────────────────────
class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080E16),
      child: const Center(
        child: Icon(Icons.shield_outlined, size: 56, color: Color(0xFF2A3A4A)),
      ),
    );
  }
}
