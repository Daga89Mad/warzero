// lib/widgets/card_detail_overlay.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/carta_model.dart';

/// Muestra la carta en grande al centro de la pantalla.
///
/// Parámetros opcionales para el sistema de evoluciones:
/// - [resolveEvolucion]: dado un `idEvolucion`, devuelve la `CartaModel`
///   correspondiente. Si la carta tiene evolución (`carta.puedeEvolucionar`)
///   aparece una FLECHA fuera de la carta a la derecha.
/// - [energiasDisponibles]: energías del jugador. `null` → sin botón.
/// - [onEvolucionar]: callback al confirmar evolución. `null` → sin botón.
Future<void> showCardDetail(
  BuildContext context,
  CartaModel carta, {
  Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion,
  int? energiasDisponibles,
  Future<void> Function(CartaModel evolucion)? onEvolucionar,
}) {
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
    pageBuilder: (ctx, _, __) => _CardDetailPage(
      carta: carta,
      resolveEvolucion: resolveEvolucion,
      energiasDisponibles: energiasDisponibles,
      onEvolucionar: onEvolucionar,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
class _CardDetailPage extends StatefulWidget {
  final CartaModel carta;
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;
  final int? energiasDisponibles;
  final Future<void> Function(CartaModel evolucion)? onEvolucionar;

  const _CardDetailPage({
    required this.carta,
    this.resolveEvolucion,
    this.energiasDisponibles,
    this.onEvolucionar,
  });

  @override
  State<_CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<_CardDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipCtrl;
  CartaModel? _evolucion;
  bool _loadingEvol = false;
  bool _showingEvolution = false;
  bool _evolucionando = false;

  bool get _tieneEvolucion =>
      widget.carta.puedeEvolucionar && widget.resolveEvolucion != null;

  bool get _puedeEvolucionar =>
      _evolucion != null &&
      widget.onEvolucionar != null &&
      widget.energiasDisponibles != null &&
      widget.energiasDisponibles! >= widget.carta.evolucion;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    if (_tieneEvolucion) _loadEvolucion();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEvolucion() async {
    setState(() => _loadingEvol = true);
    try {
      final c = await widget.resolveEvolucion!(widget.carta.idEvolucion);
      if (!mounted) return;
      setState(() {
        _evolucion = c;
        _loadingEvol = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEvol = false);
    }
  }

  void _toggleFlip() {
    if (_flipCtrl.isAnimating) return;
    if (_loadingEvol || _evolucion == null) return;
    setState(() => _showingEvolution = !_showingEvolution);
    if (_showingEvolution) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
  }

  Future<void> _confirmarEvolucion() async {
    if (!_puedeEvolucionar || _evolucionando) return;
    setState(() => _evolucionando = true);
    try {
      await widget.onEvolucionar!(_evolucion!);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _evolucionando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── CARTA + FLECHA ─────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FlippingCard(
                    controller: _flipCtrl,
                    front: widget.carta,
                    back: _evolucion,
                  ),
                  if (_tieneEvolucion) ...[
                    const SizedBox(width: 12),
                    _EvolutionArrow(
                      enabled: !_loadingEvol && _evolucion != null,
                      loading: _loadingEvol,
                      showingEvolution: _showingEvolution,
                      onTap: _toggleFlip,
                      evolucionCost: widget.carta.evolucion,
                    ),
                  ],
                ],
              ),

              // ── BOTÓN EVOLUCIONAR ──────────────────────────
              if (_showingEvolution && widget.onEvolucionar != null) ...[
                const SizedBox(height: 18),
                _EvolveButton(
                  cost: widget.carta.evolucion,
                  energiasDisponibles: widget.energiasDisponibles ?? 0,
                  enabled: _puedeEvolucionar,
                  busy: _evolucionando,
                  onTap: _confirmarEvolucion,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FLIPPING CARD — rotación 3D en eje Y. A los 90° se intercambia
// la cara visible (front → back).
// ─────────────────────────────────────────────────────────────
class _FlippingCard extends StatelessWidget {
  final AnimationController controller;
  final CartaModel front;
  final CartaModel? back;

  const _FlippingCard({
    required this.controller,
    required this.front,
    required this.back,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final t = controller.value;
        final angle = t * math.pi;
        final isBack = t > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: isBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: back != null
                      ? _CardFace(carta: back!)
                      : _CardFace(carta: front),
                )
              : _CardFace(carta: front),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FLECHA DE EVOLUCIÓN (fuera de la carta, lado derecho)
// ─────────────────────────────────────────────────────────────
class _EvolutionArrow extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final bool showingEvolution;
  final VoidCallback onTap;
  final int evolucionCost;

  const _EvolutionArrow({
    required this.enabled,
    required this.loading,
    required this.showingEvolution,
    required this.onTap,
    required this.evolucionCost,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFA040C0);
    final color = enabled ? accent : const Color(0xFF354050);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 110,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.55), width: 1.2),
          boxShadow: enabled
              ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 14)]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: Icon(
                  showingEvolution
                      ? Icons.arrow_back_ios_new
                      : Icons.arrow_forward_ios,
                  key: ValueKey(showingEvolution),
                  size: 20,
                  color: color,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'EVOL',
              style: TextStyle(
                fontSize: 8,
                color: color,
                fontFamily: 'Cinzel',
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$evolucionCost⚡',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'Cinzel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTÓN EVOLUCIONAR (debajo de la carta)
// ─────────────────────────────────────────────────────────────
class _EvolveButton extends StatelessWidget {
  final int cost;
  final int energiasDisponibles;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _EvolveButton({
    required this.cost,
    required this.energiasDisponibles,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFC060E0);
    final color = enabled ? accent : const Color(0xFF506070);
    final label = !enabled
        ? 'ENERGÍAS INSUFICIENTES  ($energiasDisponibles / $cost)'
        : busy
            ? 'EVOLUCIONANDO…'
            : 'EVOLUCIONAR  —  $cost⚡';

    return GestureDetector(
      onTap: enabled && !busy ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? accent.withOpacity(0.18) : const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.6), width: 1.2),
          boxShadow: enabled
              ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 14)]
              : const [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              Icon(Icons.auto_awesome, size: 14, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'Cinzel',
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARTA FÍSICA (RESPONSIVE)
// ─────────────────────────────────────────────────────────────
class _CardFace extends StatelessWidget {
  final CartaModel carta;
  const _CardFace({required this.carta});

  @override
  Widget build(BuildContext context) {
    // Tamaño dinámico: manteniendo aspecto ~2:3.
    // Ancho reducido ligeramente para dejar sitio a la flecha EVOL.
    final mq = MediaQuery.of(context).size;
    const double aspect = 1.5;

    final double maxW = (mq.width * 0.78).clamp(260.0, 340.0);
    final double maxH = (mq.height * 0.86).clamp(440.0, 600.0);

    double cardW = maxW;
    double cardH = cardW * aspect;
    if (cardH > maxH) {
      cardH = maxH;
      cardW = cardH / aspect;
    }

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
                value: '${carta.coste}',
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
            // Inf-izquierda: MOVIMIENTO
            Positioned(
              bottom: 8,
              left: 8,
              child: _Badge(
                value: '${carta.movimiento}',
                label: 'MOV',
                icon: Icons.open_with,
                color: const Color(0xFF4080C0),
              ),
            ),
            // Inf-derecha: DEFENSA
            Positioned(
              bottom: 8,
              right: 8,
              child: _Badge(
                value: '${carta.defensa}',
                label: 'DEFENSA',
                icon: Icons.shield_outlined,
                color: const Color(0xFF4090D0),
              ),
            ),

            // ── Nombre centrado entre COSTE y FUERZA ──────────
            Positioned(
              top: 0,
              left: 68,
              right: 68,
              height: 52,
              child: Center(
                child: Text(
                  carta.nombre.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
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
              padding: const EdgeInsets.fromLTRB(14, 52, 14, 56),
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
                        child: SizedBox.expand(
                          child: carta.imagen.isNotEmpty
                              ? Image.network(
                                  carta.imagen,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  loadingBuilder: (ctx, child, progress) {
                                    if (progress == null) return child;
                                    return _ImagePlaceholder();
                                  },
                                  errorBuilder: (_, __, ___) =>
                                      _ImagePlaceholder(),
                                )
                              : _ImagePlaceholder(),
                        ),
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
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFB0A090),
                            height: 1.5,
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
                                '${carta.evolucion}',
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
// BADGE (stat en esquina de la carta)
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

    canvas.drawLine(
      Offset(20, 40),
      Offset(size.width - 20, 40),
      paint,
    );
    canvas.drawLine(
      Offset(20, size.height - 40),
      Offset(size.width - 20, size.height - 40),
      paint,
    );

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
