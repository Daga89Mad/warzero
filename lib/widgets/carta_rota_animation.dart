// lib/widgets/carta_rota_animation.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CARTA ROTA — ANIMACIÓN DE DESTRUCCIÓN
//
// Muestra una carta (arte o frontal estilizado) que se fractura EN DIAGONAL:
// una grieta de luz recorre la carta de esquina a esquina, las dos mitades se
// separan girando y cayendo por gravedad mientras se desvanecen, y salen
// esquirlas. Reproduce una vez al aparecer; se puede repetir tocándola.
//
// Uso individual:
//   CartaRotaAnimation(
//     nombre: 'Dragón', imagen: url, fuerza: 5, defensa: 3,
//     width: 64, zoneColor: Color(0xFFC04040), esLocal: true,
//   )
//
// Uso en grupo (tira de bajas), a partir de una lista de mapas de carta:
//   CartaRotaStrip(
//     cartas: bajas, localUid: localUid, colorZona: colorZona,
//     titulo: 'BAJAS EN ESTA CELDA',
//   )
// ─────────────────────────────────────────────────────────────────────────────

class CartaRotaAnimation extends StatefulWidget {
  final String nombre;

  /// URL del arte de la carta. Si va vacía, se pinta un frontal estilizado.
  final String imagen;
  final int fuerza;
  final int defensa;

  /// Ancho del frontal en px. El alto se calcula con proporción de carta.
  final double width;

  /// Retardo antes de arrancar (para escalonar varias cartas en una tira).
  final Duration delay;

  /// Color de acento del borde (color de la zona del dueño).
  final Color zoneColor;

  /// Si es una carta del jugador local, añade un halo rojo de peligro.
  final bool esLocal;

  /// Arranca sola al construirse. Si es false, solo se anima al tocar.
  final bool autoPlay;

  const CartaRotaAnimation({
    super.key,
    required this.nombre,
    this.imagen = '',
    this.fuerza = 0,
    this.defensa = 0,
    this.width = 128,
    this.delay = Duration.zero,
    this.zoneColor = const Color(0xFFC04040),
    this.esLocal = false,
    this.autoPlay = true,
  });

  @override
  State<CartaRotaAnimation> createState() => _CartaRotaAnimationState();
}

class _CartaRotaAnimationState extends State<CartaRotaAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Shard> _shards;

  double get _h => widget.width * 1.34;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _shards = _buildShards(widget.nombre.hashCode);
    if (widget.autoPlay) {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _replay() {
    _c
      ..reset()
      ..forward();
  }

  /// Genera esquirlas deterministas (misma carta → mismo patrón).
  List<_Shard> _buildShards(int seed) {
    final r = math.Random(seed);
    return List.generate(9, (_) {
      // Ángulos concentrados alrededor de la perpendicular a la diagonal.
      final ang = (r.nextDouble() * 2 - 1) * math.pi;
      final speed = 0.5 + r.nextDouble() * 0.9;
      final size = 2.5 + r.nextDouble() * 4.5;
      final spin = (r.nextDouble() * 2 - 1) * 6;
      return _Shard(ang, speed, size, spin);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = _h;

    // Vector diagonal (0,0)→(w,h). Normal unitaria perpendicular = (h,-w)/len.
    final len = math.sqrt(w * w + h * h);
    final nx = h / len; // hacia arriba-derecha
    final ny = -w / len;

    return GestureDetector(
      onTap: _replay,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;

                // Antes de 0.14 la carta está entera (impacto + grieta).
                final s = t <= 0.14
                    ? 0.0
                    : Curves.easeOut
                        .transform(((t - 0.14) / 0.86).clamp(0.0, 1.0));

                // Separación perpendicular a la diagonal + gravedad + rotación.
                final sep = s * w * 0.55;
                final grav = s * s * h * 0.85;
                final rot = s * 0.42;
                final op = (1.0 - s * 0.9).clamp(0.0, 1.0);

                final offTopRight = Offset(nx * sep, ny * sep + grav);
                final offBotLeft = Offset(-nx * sep, -ny * sep + grav);

                // Grieta: entra rápido y se desvanece.
                final crackA =
                    (t < 0.1 ? t / 0.1 : 1 - (t - 0.1) / 0.8).clamp(0.0, 1.0);

                // Fogonazo de impacto.
                final flashA = t < 0.18 ? (1 - t / 0.18) * 0.7 : 0.0;

                // Temblor breve en el impacto.
                final shake = t < 0.14
                    ? math.sin(t * math.pi * 9) * (1 - t / 0.14) * 3.0
                    : 0.0;

                return Transform.translate(
                  offset: Offset(shake, 0),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // ── Mitad inferior-izquierda ──
                        Transform.translate(
                          offset: offBotLeft,
                          child: Transform.rotate(
                            angle: -rot,
                            child: Opacity(
                              opacity: op,
                              child: ClipPath(
                                clipper: _DiagonalHalfClipper(topRight: false),
                                child: _CartaFace(
                                  nombre: widget.nombre,
                                  imagen: widget.imagen,
                                  fuerza: widget.fuerza,
                                  defensa: widget.defensa,
                                  width: w,
                                  height: h,
                                  zoneColor: widget.zoneColor,
                                  esLocal: widget.esLocal,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── Mitad superior-derecha ──
                        Transform.translate(
                          offset: offTopRight,
                          child: Transform.rotate(
                            angle: rot,
                            child: Opacity(
                              opacity: op,
                              child: ClipPath(
                                clipper: _DiagonalHalfClipper(topRight: true),
                                child: _CartaFace(
                                  nombre: widget.nombre,
                                  imagen: widget.imagen,
                                  fuerza: widget.fuerza,
                                  defensa: widget.defensa,
                                  width: w,
                                  height: h,
                                  zoneColor: widget.zoneColor,
                                  esLocal: widget.esLocal,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── Esquirlas ──
                        if (s > 0 && op > 0.02)
                          ..._shards.map((sh) {
                            final dist = s * w * 0.9 * sh.speed;
                            final px = w / 2 +
                                nx * (sh.ang.isNegative ? -1 : 1) * dist +
                                math.cos(sh.ang) * dist * 0.4;
                            final py = h / 2 +
                                ny * (sh.ang.isNegative ? -1 : 1) * dist +
                                math.sin(sh.ang) * dist * 0.4 +
                                grav * 0.5;
                            return Positioned(
                              left: px - sh.size / 2,
                              top: py - sh.size / 2,
                              child: Transform.rotate(
                                angle: s * sh.spin,
                                child: Opacity(
                                  opacity: (1 - s).clamp(0.0, 1.0),
                                  child: Container(
                                    width: sh.size,
                                    height: sh.size,
                                    color: widget.zoneColor.withOpacity(0.9),
                                  ),
                                ),
                              ),
                            );
                          }),
                        // ── Grieta de luz sobre la diagonal ──
                        if (crackA > 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _CrackPainter(
                                  progress: crackA,
                                  reveal: t.clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        // ── Fogonazo ──
                        if (flashA > 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white.withOpacity(flashA),
                                ),
                              ),
                            ),
                          ),
                        // ── Pista de repetición cuando ya está rota ──
                        if (t >= 0.999)
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 2,
                            child: Center(
                              child: Icon(Icons.refresh,
                                  size: 12, color: Color(0xFF3A4A5A)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: w + 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.esLocal ? '☠ ' : '✖ ',
                      style: TextStyle(
                          fontSize: 8,
                          color: widget.esLocal
                              ? const Color(0xFFC04040)
                              : const Color(0xFF6A7A8A))),
                  Flexible(
                    child: Text(
                      widget.nombre.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        letterSpacing: 0.5,
                        color: Color(0xFF8A9AAA),
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

// ─────────────────────────────────────────────────────────────────────────────
// FRONTAL DE CARTA (compartido por las dos mitades)
// ─────────────────────────────────────────────────────────────────────────────
class _CartaFace extends StatelessWidget {
  final String nombre;
  final String imagen;
  final int fuerza;
  final int defensa;
  final double width;
  final double height;
  final Color zoneColor;
  final bool esLocal;

  const _CartaFace({
    required this.nombre,
    required this.imagen,
    required this.fuerza,
    required this.defensa,
    required this.width,
    required this.height,
    required this.zoneColor,
    required this.esLocal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (esLocal ? const Color(0xFFC04040) : zoneColor)
                .withOpacity(0.75),
            width: 1.5),
        boxShadow: esLocal
            ? [
                BoxShadow(
                    color: const Color(0xFFC04040).withOpacity(0.35),
                    blurRadius: 8,
                    spreadRadius: 0.5),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Arte o fondo estilizado.
            if (imagen.isNotEmpty)
              Image.network(
                imagen,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fondo(),
              )
            else
              _fondo(),
            // Velo inferior para legibilidad del nombre.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height * 0.42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF060E1A).withOpacity(0.85),
                    ],
                  ),
                ),
              ),
            ),
            // Stats en las esquinas superiores.
            Positioned(top: 3, left: 3, child: _stat('⚔', fuerza)),
            Positioned(top: 3, right: 3, child: _stat('🛡', defensa)),
            // Nombre.
            Positioned(
              left: 3,
              right: 3,
              bottom: 3,
              child: Text(
                nombre.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 7,
                  height: 1.1,
                  letterSpacing: 0.3,
                  color: Color(0xFFE8D8A8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fondo() => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF12233A), Color(0xFF0A1525)],
          ),
        ),
        child: Center(
          child: Icon(Icons.shield_outlined,
              size: width * 0.5, color: const Color(0xFF2A3A4A)),
        ),
      );

  Widget _stat(String icon, int value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF060E1A).withOpacity(0.7),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text('$icon$value',
            style: const TextStyle(
                fontFamily: 'Cinzel', fontSize: 7, color: Color(0xFFC8A860))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLIPPER DIAGONAL — parte la carta en dos triángulos complementarios
// ─────────────────────────────────────────────────────────────────────────────
class _DiagonalHalfClipper extends CustomClipper<Path> {
  /// true → triángulo superior-derecha; false → inferior-izquierda.
  final bool topRight;
  const _DiagonalHalfClipper({required this.topRight});

  @override
  Path getClip(Size s) {
    final p = Path();
    if (topRight) {
      p.moveTo(0, 0);
      p.lineTo(s.width, 0);
      p.lineTo(s.width, s.height);
      p.close();
    } else {
      p.moveTo(0, 0);
      p.lineTo(s.width, s.height);
      p.lineTo(0, s.height);
      p.close();
    }
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// GRIETA DE LUZ — línea quebrada a lo largo de la diagonal
// ─────────────────────────────────────────────────────────────────────────────
class _CrackPainter extends CustomPainter {
  final double progress; // opacidad de la grieta [0..1]
  final double reveal; // cuánto de la grieta se ha "dibujado" [0..1]

  _CrackPainter({required this.progress, required this.reveal});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Puntos quebrados alrededor de la diagonal (0,0)→(w,h).
    final pts = <Offset>[
      Offset(0, 0),
      Offset(w * 0.28, h * 0.22),
      Offset(w * 0.42, h * 0.5),
      Offset(w * 0.6, h * 0.56),
      Offset(w * 0.74, h * 0.8),
      Offset(w, h),
    ];

    final drawUntil =
        (reveal / 0.14).clamp(0.0, 1.0); // termina de trazarse pronto
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final f = i / (pts.length - 1);
      if (f > drawUntil) {
        final prev = pts[i - 1];
        final seg =
            ((drawUntil - (i - 1) / (pts.length - 1)) * (pts.length - 1))
                .clamp(0.0, 1.0);
        path.lineTo(
          prev.dx + (pts[i].dx - prev.dx) * seg,
          prev.dy + (pts[i].dy - prev.dy) * seg,
        );
        break;
      }
      path.lineTo(pts[i].dx, pts[i].dy);
    }

    // Resplandor exterior.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE0C060).withOpacity(0.35 * progress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Núcleo brillante.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
                const Color(0xFFFFF4D0), const Color(0xFFFFB84D), 1 - progress)!
            .withOpacity(progress),
    );
  }

  @override
  bool shouldRepaint(covariant _CrackPainter old) =>
      old.progress != progress || old.reveal != reveal;
}

// ─────────────────────────────────────────────────────────────────────────────
// ESQUIRLA
// ─────────────────────────────────────────────────────────────────────────────
class _Shard {
  final double ang;
  final double speed;
  final double size;
  final double spin;
  const _Shard(this.ang, this.speed, this.size, this.spin);
}

// ─────────────────────────────────────────────────────────────────────────────
// TIRA DE BAJAS — varias cartas rotas en fila con arranque escalonado
// ─────────────────────────────────────────────────────────────────────────────
class CartaRotaStrip extends StatelessWidget {
  /// Cada mapa admite: nombre/Nombre, fuerza/Fuerza, defensa/Defensa,
  /// imagen/Imagen, ownerUid, ownerZone.
  final List<Map<String, dynamic>> cartas;
  final String localUid;
  final Color Function(String?) colorZona;
  final String? titulo;
  final double cardWidth;

  const CartaRotaStrip({
    super.key,
    required this.cartas,
    required this.localUid,
    required this.colorZona,
    this.titulo,
    this.cardWidth = 128,
  });

  @override
  Widget build(BuildContext context) {
    if (cartas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titulo != null) ...[
          Row(children: [
            const Text('☠', style: TextStyle(fontSize: 10)),
            const SizedBox(width: 6),
            Text(titulo!,
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    letterSpacing: 1,
                    color: Color(0xFF506070))),
          ]),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(cartas.length, (i) {
            final c = cartas[i];
            final nombre = (c['nombre'] ?? c['Nombre'] ?? 'Carta').toString();
            final fuerza = ((c['fuerza'] ?? c['Fuerza'] ?? 0) as num).toInt();
            final defensa =
                ((c['defensa'] ?? c['Defensa'] ?? 0) as num).toInt();
            final imagen = (c['imagen'] ?? c['Imagen'] ?? '').toString();
            final ownerUid = (c['ownerUid'] ?? '').toString();
            final ownerZone = c['ownerZone'] as String?;
            final esLocal = ownerUid.isNotEmpty && ownerUid == localUid;

            return CartaRotaAnimation(
              nombre: nombre,
              imagen: imagen,
              fuerza: fuerza,
              defensa: defensa,
              width: cardWidth,
              delay: Duration(milliseconds: 280 * i),
              zoneColor: colorZona(ownerZone),
              esLocal: esLocal,
            );
          }),
        ),
      ],
    );
  }
}
