// lib/widgets/card_detail_overlay.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/carta_model.dart';

/// Muestra la carta en grande al centro de la pantalla.
///
/// Parámetros opcionales para el sistema de evoluciones:
/// - [resolveEvolucion]: dado un `idEvolucion`, devuelve la `CartaModel`.
/// - [energiasDisponibles]: energías del jugador. `null` → sin botón.
/// - [onEvolucionar]: callback al confirmar evolución. `null` → sin botón.
Future<void> showCardDetail(
  BuildContext context,
  CartaModel carta, {
  Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion,
  int? energiasDisponibles,
  Future<void> Function(CartaModel evolucion)? onEvolucionar,

  /// Callback para cambiar el skin/diseño. Solo se muestra el botón si
  /// se proporciona (colección sí, juego no).
  VoidCallback? onCambiarDiseno,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'cerrar',
    barrierColor: Colors.black.withOpacity(0.82),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOut),
          ),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, __) => _CardDetailPage(
      carta: carta,
      resolveEvolucion: resolveEvolucion,
      energiasDisponibles: energiasDisponibles,
      onEvolucionar: onEvolucionar,
      onCambiarDiseno: onCambiarDiseno,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
class _CardDetailPage extends StatefulWidget {
  final CartaModel carta;
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;
  final int? energiasDisponibles;
  final Future<void> Function(CartaModel evolucion)? onEvolucionar;
  final VoidCallback? onCambiarDiseno;

  const _CardDetailPage({
    required this.carta,
    this.resolveEvolucion,
    this.energiasDisponibles,
    this.onEvolucionar,
    this.onCambiarDiseno,
  });

  @override
  State<_CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<_CardDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipCtrl;
  CartaModel? _evolucion;
  // Se inicializa a true si hay evolución para evitar setState durante
  // la animación de apertura (causaba el parpadeo visible).
  late bool _loadingEvol;
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
    _loadingEvol =
        _tieneEvolucion; // sin setState — evita rebuild mid-animation
    _flipCtrl = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    if (_tieneEvolucion) {
      // Retrasar la carga hasta que la animación de apertura termine
      // (transitionDuration = 220ms). Si setState ocurre durante la
      // animación causa un parpadeo visible.
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _loadEvolucion();
      });
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEvolucion() async {
    try {
      final c = await widget.resolveEvolucion!(widget.carta.idEvolucion);
      if (!mounted) return;
      // Precachear la imagen de la evolución antes de mostrar la flecha
      // activa para que al hacer flip no haya parpadeo de placeholder.
      if (c != null && c.imagen.isNotEmpty) {
        try {
          await precacheImage(NetworkImage(c.imagen), context)
              .timeout(const Duration(milliseconds: 1500));
        } catch (_) {}
        if (!mounted) return;
      }
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

  // ── Calcular dimensiones de la carta ──────────────────────────
  Size _cardSize(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    const double aspect = 1.5;
    const double hPad = 24.0; // padding horizontal total (12 cada lado)
    final double maxW = (mq.width - hPad).clamp(0.0, 520.0);
    final double maxH = (mq.height * 0.80).clamp(0.0, 820.0);

    double cardW = maxW;
    double cardH = cardW * aspect;
    if (cardH > maxH) {
      cardH = maxH;
      cardW = cardH / aspect;
    }
    return Size(cardW, cardH);
  }

  @override
  Widget build(BuildContext context) {
    final sz = _cardSize(context);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── CARTA ─────────────────────────────────────
                _FlippingCard(
                  controller: _flipCtrl,
                  front: widget.carta,
                  back: _evolucion,
                  cardWidth: sz.width,
                  cardHeight: sz.height,
                ),

                // ── FILA INFERIOR: flecha evolución (derecha) ──
                if (_tieneEvolucion) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: sz.width,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _EvolutionArrow(
                          enabled: !_loadingEvol && _evolucion != null,
                          loading: _loadingEvol,
                          showingEvolution: _showingEvolution,
                          onTap: _toggleFlip,
                          evolucionCost: widget.carta.evolucion,
                        ),
                      ],
                    ),
                  ),
                ],

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

                // ── BOTÓN CAMBIAR DISEÑO ────────────────────────
                if (widget.onCambiarDiseno != null) ...[
                  const SizedBox(height: 14),
                  _SkinButton(onTap: () {
                    Navigator.of(context).pop();
                    widget.onCambiarDiseno!();
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FLIPPING CARD
// ─────────────────────────────────────────────────────────────
class _FlippingCard extends StatelessWidget {
  final AnimationController controller;
  final CartaModel front;
  final CartaModel? back;
  final double cardWidth;
  final double cardHeight;

  const _FlippingCard({
    required this.controller,
    required this.front,
    required this.cardWidth,
    required this.cardHeight,
    this.back,
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
                  child: _CardFace(
                    carta: back ?? front,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                  ),
                )
              : _CardFace(
                  carta: front,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FLECHA DE EVOLUCIÓN
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
    final color = enabled ? accent : const Color(0xFF506070);
    final label = loading
        ? '…'
        : showingEvolution
            ? 'Original'
            : 'Evolución  ⚡$evolucionCost';

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.60),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.65), width: 1.2),
          boxShadow: enabled
              ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12)]
              : const [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Cinzel',
              letterSpacing: 1.0,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTÓN CAMBIAR DISEÑO (skin)
// ─────────────────────────────────────────────────────────────
class _SkinButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SkinButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFA040FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withOpacity(0.22),
            color.withOpacity(0.07),
          ]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.55), width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.color_lens_outlined, size: 16, color: color),
            SizedBox(width: 8),
            Text(
              'CAMBIAR DISEÑO',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 11,
                letterSpacing: 2,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// BOTÓN EVOLUCIONAR
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
// CARTA FÍSICA (RESPONSIVE — tamaño recibido del padre)
// ─────────────────────────────────────────────────────────────
class _CardFace extends StatelessWidget {
  final CartaModel carta;
  final double cardWidth;
  final double cardHeight;

  const _CardFace({
    required this.carta,
    required this.cardWidth,
    required this.cardHeight,
  });

  // CAMBIO: la cabecera crece si la carta tiene condición especial,
  // para alojar el chip de condición debajo del nombre.
  double get _headerHeight =>
      carta.condicion != CondicionCarta.basica ? 68.0 : 52.0;

  @override
  Widget build(BuildContext context) {
    final headerH = _headerHeight;

    return Container(
      width: cardWidth,
      height: cardHeight,
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
            Positioned.fill(child: _CardBackground()),

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
                color: const Color(0xFF40B070),
              ),
            ),

            // ── CABECERA: Nombre + Condición (si aplica) ──
            // CAMBIO: altura dinámica según si hay condición
            Positioned(
              top: 0,
              left: 68,
              right: 68,
              height: headerH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Nombre
                  Text(
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
                  // CAMBIO: condición debajo del nombre en pequeño
                  if (carta.condicion != CondicionCarta.basica) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            Color(carta.condicion.colorValue).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Color(carta.condicion.colorValue)
                              .withOpacity(0.45),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${carta.condicion.icon} ${carta.condicion.label.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Color(carta.condicion.colorValue),
                          fontFamily: 'Cinzel',
                          letterSpacing: 0.8,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Contenido (imagen + descripción)
            // CAMBIO: padding superior usa headerH dinámico
            Padding(
              padding: EdgeInsets.fromLTRB(14, headerH, 14, 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Imagen (flex:7 — ~65 % del espacio)
                  Expanded(
                    flex: 7,
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
                                  // frameBuilder evita el hard-switch
                                  // placeholder→imagen que causaba el
                                  // parpadeo al abrir la carta.
                                  frameBuilder: (ctx, child, frame, sync) {
                                    if (sync || frame != null) {
                                      return AnimatedOpacity(
                                        opacity: 1.0,
                                        duration: Duration.zero,
                                        child: child,
                                      );
                                    }
                                    // Imagen aún cargando — fondo plano
                                    // sin switch brusco
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _ImagePlaceholder(),
                                        AnimatedOpacity(
                                          opacity: frame == null ? 0.0 : 1.0,
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.easeIn,
                                          child: child,
                                        ),
                                      ],
                                    );
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

                  // Descripción + Evolución (flex:3 — ~35 % del espacio)
                  // CAMBIO: eliminada la fila de Condición de aquí
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF060E14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFC8A860).withOpacity(0.10),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                carta.descripcion.isNotEmpty
                                    ? carta.descripcion
                                    : 'Sin descripción.',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFB0A090),
                                  height: 1.5,
                                  fontFamily: 'Georgia',
                                  decoration: TextDecoration.none,
                                ),
                              ),
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
                  ),

                  const SizedBox(height: 8),

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

    canvas.drawLine(Offset(20, 40), Offset(size.width - 20, 40), paint);
    canvas.drawLine(Offset(20, size.height - 40),
        Offset(size.width - 20, size.height - 40), paint);

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
          Offset(cx + sx * 10, cy), Offset(cx + sx * 28, cy), cornerPaint);
      canvas.drawLine(
          Offset(cx, cy + sy * 10), Offset(cx, cy + sy * 28), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(_CardBgPainter _) => false;
}

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
