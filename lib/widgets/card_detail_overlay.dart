// lib/widgets/card_detail_overlay.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/carta_model.dart';

/// Muestra la carta en grande al centro de la pantalla.
///
/// Parámetros opcionales:
/// - [resolveEvolucion]: dado un `idEvolucion`, devuelve la `CartaModel`.
/// - [energiasDisponibles]: energías del jugador. `null` → sin botones de coste.
/// - [onEvolucionar]: callback al confirmar evolución. `null` → sin botón.
/// - [onCambiarDiseno]: callback para cambiar skin. `null` → sin botón.
/// - [onLanzarHabilidad]: callback al pulsar LANZAR HABILIDAD. `null` → sin
///   botón. Si la carta tiene `idHabilidad>0` y este callback está presente,
///   se muestra el botón.
/// - [enfriamientoRestante]: turnos restantes de enfriamiento (informativo).
///   Si > 0 el botón LANZAR HABILIDAD se muestra deshabilitado con el motivo.
Future<void> showCardDetail(
  BuildContext context,
  CartaModel carta, {
  Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion,
  int? energiasDisponibles,
  Future<void> Function(CartaModel evolucion)? onEvolucionar,
  VoidCallback? onCambiarDiseno,
  Future<void> Function()? onLanzarHabilidad,
  int enfriamientoRestante = 0,
  Future<void> Function()? onSacrificar,
  int recompensaSacrificio = 0,
  int defensaReducida = 0,
  int defensaExtra = 0,
  int fuerzaExtra = 0,
  int movimientoExtra = 0,
  bool paralizada = false,
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
      onLanzarHabilidad: onLanzarHabilidad,
      enfriamientoRestante: enfriamientoRestante,
      onSacrificar: onSacrificar,
      recompensaSacrificio: recompensaSacrificio,
      defensaReducida: defensaReducida,
      defensaExtra: defensaExtra,
      fuerzaExtra: fuerzaExtra,
      movimientoExtra: movimientoExtra,
      paralizada: paralizada,
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
  final Future<void> Function()? onLanzarHabilidad;
  final int enfriamientoRestante;
  final Future<void> Function()? onSacrificar;
  final int recompensaSacrificio;
  final int defensaReducida;
  final int defensaExtra;
  final int fuerzaExtra;
  final int movimientoExtra;
  final bool paralizada;

  const _CardDetailPage({
    required this.carta,
    this.resolveEvolucion,
    this.energiasDisponibles,
    this.onEvolucionar,
    this.onCambiarDiseno,
    this.onLanzarHabilidad,
    this.enfriamientoRestante = 0,
    this.onSacrificar,
    this.recompensaSacrificio = 0,
    this.defensaReducida = 0,
    this.defensaExtra = 0,
    this.fuerzaExtra = 0,
    this.movimientoExtra = 0,
    this.paralizada = false,
  });

  @override
  State<_CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<_CardDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipCtrl;
  CartaModel? _evolucion;
  late bool _loadingEvol;
  bool _showingEvolution = false;
  bool _evolucionando = false;
  bool _lanzandoHabilidad = false;
  bool _sacrificando = false;

  bool get _tieneEvolucion =>
      widget.carta.puedeEvolucionar && widget.resolveEvolucion != null;

  bool get _puedeEvolucionar =>
      _evolucion != null &&
      widget.onEvolucionar != null &&
      widget.energiasDisponibles != null &&
      widget.energiasDisponibles! >= widget.carta.evolucion;

  bool get _muestraHabilidad =>
      widget.onLanzarHabilidad != null && widget.carta.tieneHabilidad;

  bool get _energiasSuficientesHabilidad =>
      widget.energiasDisponibles == null ||
      widget.energiasDisponibles! >= widget.carta.costeHabilidad;

  bool get _puedeLanzarHabilidad =>
      _muestraHabilidad &&
      widget.enfriamientoRestante <= 0 &&
      _energiasSuficientesHabilidad &&
      !_lanzandoHabilidad;

  @override
  void initState() {
    super.initState();
    _loadingEvol = _tieneEvolucion;
    _flipCtrl = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    if (_tieneEvolucion) {
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

  Future<void> _confirmarLanzarHabilidad() async {
    if (!_puedeLanzarHabilidad) return;
    setState(() => _lanzandoHabilidad = true);
    try {
      // Cerrar el overlay primero para devolver el control al tablero,
      // donde se hará el targeting de las celdas objetivo.
      Navigator.of(context).pop();
      await widget.onLanzarHabilidad!();
    } catch (_) {
      if (mounted) setState(() => _lanzandoHabilidad = false);
    }
  }

  Future<void> _confirmarSacrificio() async {
    if (widget.onSacrificar == null || _sacrificando) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1828),
        title: const Text(
          'Sacrificar carta',
          style: TextStyle(color: Color(0xFFE0C060), fontFamily: 'Cinzel'),
        ),
        content: Text(
          'Sacrificar "${widget.carta.nombre}" a cambio de '
          '+${widget.recompensaSacrificio}Ø.\nLa carta se perderá y no podrás '
          'deshacerlo.',
          style: const TextStyle(color: Color(0xFFB0C0D0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF90A0B0))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Sacrificar',
                style: TextStyle(color: Color(0xFFE06060))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sacrificando = true);
    try {
      Navigator.of(context).pop(); // cerrar el detalle
      await widget.onSacrificar!();
    } catch (_) {
      if (mounted) setState(() => _sacrificando = false);
    }
  }

  Size _cardSize(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    const double aspect = 1.5;
    // No hay flecha lateral: solo un mini-padding para que la carta no
    // toque los bordes laterales de la pantalla.
    const double totalSideSpace = 20.0;
    final double usableWidth = mq.width - totalSideSpace;

    final double maxW = (usableWidth * 0.98).clamp(0.0, 560.0);
    // Dejar espacio vertical para la flecha de evolución que ahora va
    // debajo (64dp + spacer) y para los botones de habilidad/evolucionar.
    final double maxH = (mq.height * 0.78).clamp(0.0, 820.0);

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
                // ── BOTÓN LANZAR HABILIDAD (encima de la carta) ──
                if (_muestraHabilidad) ...[
                  _HabilidadButton(
                    coste: widget.carta.costeHabilidad,
                    energiasDisponibles: widget.energiasDisponibles ?? 0,
                    enfriamientoRestante: widget.enfriamientoRestante,
                    enabled: _puedeLanzarHabilidad,
                    busy: _lanzandoHabilidad,
                    onTap: _confirmarLanzarHabilidad,
                  ),
                  const SizedBox(height: 14),
                ],

                // ── CARTA ─────────────────────────────────────
                _FlippingCard(
                  controller: _flipCtrl,
                  front: widget.carta,
                  back: _evolucion,
                  cardWidth: sz.width,
                  cardHeight: sz.height,
                ),

                // ── CHIP DE VENENO (defensa reducida) ──
                if (widget.defensaReducida > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11331C),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF2BA046).withOpacity(0.7),
                          width: 1),
                    ),
                    child: Text(
                      '☠  Envenenada · Defensa '
                      '${widget.carta.defensa} → '
                      '${(widget.carta.defensa - widget.defensaReducida).clamp(0, 99999)}'
                      '  (-${widget.defensaReducida})',
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        color: Color(0xFF5AD07A),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],

                // ── CHIP DE DEFENSA (+escudo / potenciar defensa) ──
                if (widget.defensaExtra > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E2440),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF3A78C8).withOpacity(0.7),
                          width: 1),
                    ),
                    child: Text(
                      '🛡  Defensa '
                      '${widget.carta.defensa} → '
                      '${widget.carta.defensa + widget.defensaExtra}'
                      '  (+${widget.defensaExtra})',
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        color: Color(0xFF9AD0FF),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],

                // ── CHIP DE FUERZA (potenciar fuerza) ──
                if (widget.fuerzaExtra > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A2408),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFFFFB84D).withOpacity(0.7),
                          width: 1),
                    ),
                    child: Text(
                      '💪  Fuerza '
                      '${widget.carta.fuerza} → '
                      '${widget.carta.fuerza + widget.fuerzaExtra}'
                      '  (+${widget.fuerzaExtra})',
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        color: Color(0xFFFFCC80),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],

                // ── CHIP DE MOVIMIENTO (potenciar movimiento) ──
                if (widget.movimientoExtra > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E2E36),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF40C0D0).withOpacity(0.7),
                          width: 1),
                    ),
                    child: Text(
                      '💨  Movimiento '
                      '${widget.carta.movimiento} → '
                      '${widget.carta.movimiento + widget.movimientoExtra}'
                      '  (+${widget.movimientoExtra})',
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        color: Color(0xFF80E0E8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],

                // ── CHIP DE PARÁLISIS ──
                if (widget.paralizada) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E2836),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF2C90C8).withOpacity(0.7),
                          width: 1),
                    ),
                    child: const Text(
                      '⏱  Paralizada · no puede moverse',
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        color: Color(0xFF7AC8E8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],

                // ── FLECHA EVOLUCIÓN (debajo, alineada a la derecha) ──
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

                // ── BOTÓN SACRIFICAR ────────────────────────────
                if (widget.onSacrificar != null) ...[
                  const SizedBox(height: 14),
                  _SacrificarButton(
                    recompensa: widget.recompensaSacrificio,
                    busy: _sacrificando,
                    onTap: _confirmarSacrificio,
                  ),
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
// BOTÓN SACRIFICAR
// ─────────────────────────────────────────────────────────────
class _SacrificarButton extends StatelessWidget {
  final int recompensa;
  final bool busy;
  final VoidCallback onTap;

  const _SacrificarButton({
    required this.recompensa,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE06060);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1A0E12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.7), width: 1.5),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(0.20), blurRadius: 12),
          ],
        ),
        child: Text(
          busy ? 'SACRIFICANDO…' : 'SACRIFICAR  —  +$recompensaØ',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: accent,
            fontFamily: 'Cinzel',
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTÓN LANZAR HABILIDAD
// ─────────────────────────────────────────────────────────────
class _HabilidadButton extends StatelessWidget {
  final int coste;
  final int energiasDisponibles;
  final int enfriamientoRestante;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _HabilidadButton({
    required this.coste,
    required this.energiasDisponibles,
    required this.enfriamientoRestante,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF40C0FF);
    final color = enabled ? accent : const Color(0xFF506070);

    final String label;
    if (busy) {
      label = 'LANZANDO…';
    } else if (enfriamientoRestante > 0) {
      label = 'ENFRIAMIENTO  ${enfriamientoRestante}t';
    } else if (energiasDisponibles < coste) {
      label = 'ENERGÍAS INSUFICIENTES  ($energiasDisponibles / $coste)';
    } else {
      label = 'LANZAR HABILIDAD  —  $costeØ';
    }

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
              Icon(Icons.flash_on, size: 14, color: color),
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
    final color = enabled ? accent : const Color(0xFF354050);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.55), width: 1.2),
          boxShadow: enabled
              ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 14)]
              : const [],
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              : AnimatedSwitcher(
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
            : 'EVOLUCIONAR  —  ${cost}Ø';

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

  @override
  Widget build(BuildContext context) {
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

            // Nombre + Condición (chip justo debajo del nombre)
            Positioned(
              top: 0,
              left: 68,
              right: 68,
              height: 78,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                  const SizedBox(height: 4),
                  // Chips: tipo de terreno (siempre) + condición (si no básica).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(carta.tipoColorValue).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color:
                                  Color(carta.tipoColorValue).withOpacity(0.45),
                              width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(carta.tipoIconData,
                                size: 11, color: Color(carta.tipoColorValue)),
                            const SizedBox(width: 4),
                            Text(
                              carta.tipoNombre,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(carta.tipoColorValue),
                                fontFamily: 'Cinzel',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (carta.condicion != CondicionCarta.basica) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Color(carta.condicion.colorValue)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Color(carta.condicion.colorValue)
                                    .withOpacity(0.40),
                                width: 0.8),
                          ),
                          child: Text(
                            '${carta.condicion.icon} ${carta.condicion.label}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(carta.condicion.colorValue),
                              fontFamily: 'Cinzel',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Contenido
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 78, 14, 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 6,
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
                                  frameBuilder: (ctx, child, frame, sync) {
                                    if (sync || frame != null) {
                                      return AnimatedOpacity(
                                        opacity: 1.0,
                                        duration: Duration.zero,
                                        child: child,
                                      );
                                    }
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
                  Expanded(
                    flex: 4,
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(carta.tipoIconData,
                            size: 9, color: Color(carta.tipoColorValue)),
                        const SizedBox(width: 4),
                        Text(
                          carta.tipoNombre.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            color: Color(carta.tipoColorValue),
                            fontFamily: 'Cinzel',
                            letterSpacing: 2,
                          ),
                        ),
                      ],
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
