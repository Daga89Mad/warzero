// lib/widgets/card_detail_overlay.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import 'cell_widget.dart' show ZeroChip;

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
  bool esLegendaria = false,
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
      esLegendaria: esLegendaria,
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
  final bool esLegendaria;

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
    this.esLegendaria = false,
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
    // Margen lateral mínimo: la carta ocupa casi todo el ancho de pantalla.
    const double totalSideSpace = 12.0;
    final double usableWidth = mq.width - totalSideSpace;

    final double maxW = usableWidth.clamp(0.0, 720.0);
    // Usamos más alto de pantalla. En la mayoría de móviles la carta sigue
    // limitada por el ancho, pero en pantallas altas gana tamaño.
    final double maxH = (mq.height * 0.88).clamp(0.0, 980.0);

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
                // Envuelta en _PinchZoomCard: se puede ampliar con dos dedos
                // (pellizco) y, al soltar, vuelve animada a su tamaño original.
                _PinchZoomCard(
                  child: _FlippingCard(
                    controller: _flipCtrl,
                    front: widget.carta,
                    back: _evolucion,
                    cardWidth: sz.width,
                    cardHeight: sz.height,
                    esLegendaria: widget.esLegendaria,
                  ),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              busy ? 'SACRIFICANDO…' : 'SACRIFICAR  —  +$recompensa',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: accent,
                fontFamily: 'Cinzel',
                letterSpacing: 1,
              ),
            ),
            if (!busy) ...[
              const SizedBox(width: 6),
              const ZeroChip(size: 15),
            ],
          ],
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
    bool mostrarCoste = false;
    if (busy) {
      label = 'LANZANDO…';
    } else if (enfriamientoRestante > 0) {
      label = 'ENFRIAMIENTO  ${enfriamientoRestante}t';
    } else if (energiasDisponibles < coste) {
      label = 'ENERGÍAS INSUFICIENTES  ($energiasDisponibles / $coste)';
    } else {
      label = 'LANZAR HABILIDAD  —  $coste';
      mostrarCoste = true;
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
            if (mostrarCoste) ...[
              const SizedBox(width: 6),
              const ZeroChip(size: 15),
            ],
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

  /// La skin legendaria pertenece a la carta frontal; solo se aplica a la cara
  /// delantera (la evolución del reverso es otra carta distinta).
  final bool esLegendaria;

  const _FlippingCard({
    required this.controller,
    required this.front,
    required this.cardWidth,
    required this.cardHeight,
    this.back,
    this.esLegendaria = false,
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
                    esLegendaria: false,
                  ),
                )
              : _CardFace(
                  carta: front,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                  esLegendaria: esLegendaria,
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
    // El coste se muestra aparte con ZeroChip (disco amarillo, Ø negro) para que
    // no se pegue al número (antes "3Ø" parecía "30").
    final mostrarCoste = enabled && !busy;
    final label = !enabled
        ? 'ENERGÍAS INSUFICIENTES  ($energiasDisponibles / $cost)'
        : busy
            ? 'EVOLUCIONANDO…'
            : 'EVOLUCIONAR  —  $cost';

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
            if (mostrarCoste) ...[
              const SizedBox(width: 6),
              const ZeroChip(size: 15),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MARCOS DECORATIVOS (assets transparentes en assets/images/)
//   Mapeo por ejército: 1 Humanos · 2 Biónicos · 3 Demonios · 4 Nefilim.
//   - Legendaria: envuelve la ILUSTRACIÓN (marco horizontal).
//   - Especial:   envuelve TODA la carta (marco vertical).
// ─────────────────────────────────────────────────────────────
String _marcoLegendaria(int ejercito) =>
    'assets/images/marco_legendaria_$ejercito.png';
String _marcoEspecial(int ejercito) =>
    'assets/images/marco_especial_$ejercito.png';

// Cuánto sobresale cada marco respecto a su área base (fracción del ANCHO de la
// carta). Ajusta finamente si los adornos quedan demasiado dentro/fuera.
const double _kSangradoEspecial = 0.02; // marco de toda la carta (sangrado)
const double _kSangradoLegendariaX = 0.06; // marco de la ilustración (lados)
const double _kSangradoLegendariaY =
    0.10; // marco de la ilustración (arriba/abajo)

// Ventanas internas del marco ESPECIAL, medidas sobre el PNG (1046x1504) como
// fracciones del propio marco. El contenido de la carta se coloca EXACTAMENTE
// en estos huecos para que encaje con el marco. Si mañana cambias el arte del
// marco y las ventanas se mueven, basta reajustar estos números.
const double _kEspImgL = 0.070,
    _kEspImgT = 0.156,
    _kEspImgR = 0.929,
    _kEspImgB = 0.628; // ventana de la ilustración
const double _kEspTxtL = 0.070,
    _kEspTxtT = 0.658,
    _kEspTxtR = 0.928,
    _kEspTxtB = 0.893; // ventana de texto
const double _kEspTitL = 0.203,
    _kEspTitT = 0.048,
    _kEspTitR = 0.795,
    _kEspTitB = 0.130; // barra de título
// Centros de los huecos de esquina (coste, fuerza, mov, defensa).
const double _kEspSlotTLx = 0.084, _kEspSlotTLy = 0.068;
const double _kEspSlotTRx = 0.914, _kEspSlotTRy = 0.068;
const double _kEspSlotBLx = 0.084, _kEspSlotBLy = 0.938;
const double _kEspSlotBRx = 0.914, _kEspSlotBRy = 0.938;
// Tamaño de cada hueco de esquina (fracción del marco).
const double _kEspSlotW = 0.070, _kEspSlotH = 0.050;
// true  -> la ilustración se ve ENTERA (BoxFit.contain, puede dejar bandas).
// false -> la ilustración RELLENA la ventana (BoxFit.cover, recorta bordes).
const bool _kEspImagenCompleta = false;

// ─────────────────────────────────────────────────────────────
// CARTA FÍSICA (RESPONSIVE — tamaño recibido del padre)
// ─────────────────────────────────────────────────────────────
class _CardFace extends StatelessWidget {
  final CartaModel carta;
  final double cardWidth;
  final double cardHeight;

  /// True si la skin aplicada a esta carta es legendaria (marco en la imagen).
  final bool esLegendaria;

  const _CardFace({
    required this.carta,
    required this.cardWidth,
    required this.cardHeight,
    this.esLegendaria = false,
  });

  @override
  Widget build(BuildContext context) {
    // Las cartas Especiales llevan marco de ejército alrededor de TODA la carta.
    final bool especial = carta.esEspecial;

    final Widget nucleo = Container(
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
        // Con marco especial, el borde dorado propio estorba (el marco ya lo
        // aporta): lo hacemos transparente para evitar el doble borde.
        border: Border.all(
          color: const Color(0xFFC8A860).withOpacity(especial ? 0.0 : 1.0),
          width: 1.8,
        ),
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      const Color(0xFFC8A860).withOpacity(0.40),
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
                                        frameBuilder:
                                            (ctx, child, frame, sync) {
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
                                                opacity:
                                                    frame == null ? 0.0 : 1.0,
                                                duration: const Duration(
                                                    milliseconds: 250),
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
                        // ── MARCO LEGENDARIO (envuelve la ilustración) ──
                        if (esLegendaria)
                          Positioned(
                            left: -cardWidth * _kSangradoLegendariaX,
                            right: -cardWidth * _kSangradoLegendariaX,
                            top: -cardWidth * _kSangradoLegendariaY,
                            bottom: -cardWidth * _kSangradoLegendariaY,
                            child: IgnorePointer(
                              child: Image.asset(
                                _marcoLegendaria(carta.ejercito),
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                      ],
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
                                  fontSize: 12,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (especial) return _buildEspecial(context);
    return nucleo;
  }

  // ── Layout dedicado a cartas ESPECIALES ────────────────────────────
  // El marco de ejército es una plantilla completa (título, ilustración, texto
  // y huecos de esquina). En vez de superponerlo sobre la carta normal (que no
  // cuadraba), aquí colocamos cada elemento dentro de su ventana del marco.
  Widget _buildEspecial(BuildContext context) {
    final double w = cardWidth, h = cardHeight;
    final double pad =
        w * _kSangradoEspecial; // sangrado del marco hacia afuera
    final double fW = w + 2 * pad, fH = h + 2 * pad; // rect completo del marco

    // Inset (izq./sup.) desde el borde de la carta para una fracción del marco.
    double fx(double f) => -pad + f * fW;
    double fy(double f) => -pad + f * fH;

    // Coloca [child] exactamente en la ventana [l,t,r,b] (fracciones del marco).
    Widget ventana(double l, double t, double r, double b, Widget child) =>
        Positioned(
          left: fx(l),
          top: fy(t),
          width: (r - l) * fW,
          height: (b - t) * fH,
          child: child,
        );

    // Coloca un badge centrado en el hueco de esquina (cx,cy), escalado al hueco.
    Widget hueco(double cx, double cy, Widget badge) {
      // Tamaño legible (independiente del hueco decorativo, que puede ser
      // diminuto). El badge se centra sobre el hueco; si es mayor, desborda un
      // poco sobre el marco, que es justo el aspecto de carta con stats.
      final double bw = 0.105 * fW, bh = 0.082 * fH;
      return Positioned(
        left: fx(cx) - bw / 2,
        top: fy(cy) - bh / 2,
        width: bw,
        height: bh,
        child: FittedBox(fit: BoxFit.contain, child: badge),
      );
    }

    // Sangrado del marco legendario respecto a la ventana de ilustración.
    final double legIx = (_kEspImgR - _kEspImgL) * fW * _kSangradoLegendariaX;
    final double legIy = (_kEspImgB - _kEspImgT) * fH * _kSangradoLegendariaY;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cuerpo oscuro de la carta (el marco no rellena; aporta legibilidad).
          Positioned.fill(
            child: Container(
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
              ),
            ),
          ),

          // Ilustración (con marco legendario encima si la skin es legendaria).
          ventana(
            _kEspImgL,
            _kEspImgT,
            _kEspImgR,
            _kEspImgB,
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: _ilustracion()),
                if (esLegendaria)
                  Positioned(
                    left: -legIx,
                    right: -legIx,
                    top: -legIy,
                    bottom: -legIy,
                    child: IgnorePointer(
                      child: Image.asset(
                        _marcoLegendaria(carta.ejercito),
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Texto (descripción + evolución).
          ventana(_kEspTxtL, _kEspTxtT, _kEspTxtR, _kEspTxtB, _textoPanel()),

          // Título (nombre + chips) en la barra superior del marco.
          ventana(
            _kEspTitL,
            _kEspTitT,
            _kEspTitR,
            _kEspTitB,
            Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: _tituloWidget()),
            ),
          ),

          // Badges en los huecos de esquina.
          hueco(_kEspSlotTLx, _kEspSlotTLy, _badgeCoste()),
          hueco(_kEspSlotTRx, _kEspSlotTRy, _badgeFuerza()),
          hueco(_kEspSlotBLx, _kEspSlotBLy, _badgeMov()),
          hueco(_kEspSlotBRx, _kEspSlotBRy, _badgeDefensa()),

          // Marco de ejército POR ENCIMA (define bordes; ventanas transparentes).
          Positioned(
            left: -pad,
            top: -pad,
            width: fW,
            height: fH,
            child: IgnorePointer(
              child: Image.asset(
                _marcoEspecial(carta.ejercito),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Piezas reutilizadas por el layout especial ─────────────────────
  Widget _ilustracion() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: const Color(0xFF060E14), // fondo por si contain deja bandas
        child: SizedBox.expand(
          child: carta.imagen.isNotEmpty
              ? Image.network(
                  carta.imagen,
                  fit: _kEspImagenCompleta ? BoxFit.contain : BoxFit.cover,
                  errorBuilder: (_, __, ___) => _ImagePlaceholder(),
                )
              : _ImagePlaceholder(),
        ),
      ),
    );
  }

  Widget _textoPanel() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF060E14),
        borderRadius: BorderRadius.circular(6),
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
                  fontSize: 12,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFA040C0).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFFA040C0).withOpacity(0.40),
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
    );
  }

  Widget _tituloWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Color(carta.tipoColorValue).withOpacity(0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: Color(carta.tipoColorValue).withOpacity(0.45),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(carta.condicion.colorValue).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color:
                          Color(carta.condicion.colorValue).withOpacity(0.40),
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
    );
  }

  Widget _badgeCoste() => _Badge(
        value: '${carta.coste}',
        label: 'COSTE',
        icon: Icons.monetization_on_outlined,
        color: const Color(0xFFB08040),
      );
  Widget _badgeFuerza() => _Badge(
        value: '${carta.fuerza}',
        label: 'FUERZA',
        icon: Icons.bolt,
        color: const Color(0xFFC04040),
      );
  Widget _badgeMov() => _Badge(
        value: '${carta.movimiento}',
        label: 'MOV',
        icon: Icons.open_with,
        color: const Color(0xFF4080C0),
      );
  Widget _badgeDefensa() => _Badge(
        value: '${carta.defensa}',
        label: 'DEFENSA',
        icon: Icons.shield_outlined,
        color: const Color(0xFF40B070),
      );
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

// ─────────────────────────────────────────────────────────────
// ZOOM POR PELLIZCO (pinch-to-zoom con retorno al soltar)
// ─────────────────────────────────────────────────────────────
/// Permite ampliar [child] con dos dedos (gesto de pellizco). Mientras se
/// mantienen los dedos sobre la carta, esta escala en tiempo real siguiendo el
/// pellizco (y se desplaza con el punto focal). Al soltar los dedos, vuelve
/// animada a su tamaño y posición originales.
///
/// Solo reacciona a gestos de 2+ dedos, de modo que un toque simple sigue sin
/// hacer nada (no interfiere con el cierre del overlay al tocar fuera).
class _PinchZoomCard extends StatefulWidget {
  final Widget child;

  /// Escala máxima alcanzable con el pellizco.
  final double maxScale;

  const _PinchZoomCard({
    required this.child,
    this.maxScale = 3.0,
  });

  @override
  State<_PinchZoomCard> createState() => _PinchZoomCardState();
}

class _PinchZoomCardState extends State<_PinchZoomCard>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  late final AnimationController _resetCtrl;
  Animation<double>? _scaleAnim;
  Animation<Offset>? _offsetAnim;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        setState(() {
          if (_scaleAnim != null) _scale = _scaleAnim!.value;
          if (_offsetAnim != null) _offset = _offsetAnim!.value;
        });
      });
  }

  @override
  void dispose() {
    _resetCtrl.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _resetCtrl.stop();
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Solo pellizco real: ignoramos arrastres de un solo dedo.
    if (d.pointerCount < 2) return;
    setState(() {
      _scale = (_baseScale * d.scale).clamp(1.0, widget.maxScale);
      _offset = _baseOffset + (d.localFocalPoint - _startFocal);
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Al soltar los dedos → volver al tamaño y posición originales.
    if (_scale == 1.0 && _offset == Offset.zero) return;
    _scaleAnim = Tween<double>(begin: _scale, end: 1.0).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOut),
    );
    _offsetAnim = Tween<Offset>(begin: _offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _resetCtrl, curve: Curves.easeOut),
    );
    _resetCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(_offset.dx, _offset.dy)
          ..scale(_scale),
        child: widget.child,
      ),
    );
  }
}
