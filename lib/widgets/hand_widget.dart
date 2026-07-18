// lib/widgets/hand_widget.dart

import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import 'card_detail_overlay.dart';

class HandWidget extends StatelessWidget {
  final List<CartaModel> cartas;
  final int? selectedIndex;
  final Function(int) onCardTap;

  /// Energías disponibles del jugador local.
  /// Las cartas con coste > energiesDisponibles se muestran bloqueadas.
  final int energiesDisponibles;

  /// Resolver carta de evolución (para preview al hacer long press).
  final Future<CartaModel?> Function(String idEvolucion)? resolveEvolucion;

  /// Sacrificar la carta de índice [i] a cambio de la mitad de su coste.
  /// `null` o [permiteSacrificio] = false → no se muestra el botón.
  final Future<void> Function(int index)? onSacrificar;
  final bool permiteSacrificio;

  const HandWidget({
    super.key,
    required this.cartas,
    required this.selectedIndex,
    required this.onCardTap,
    this.energiesDisponibles = 0,
    this.resolveEvolucion,
    this.onSacrificar,
    this.permiteSacrificio = false,
  });

  @override
  Widget build(BuildContext context) {
    if (cartas.isEmpty) {
      return const SizedBox(
        height: 105,
        child: Center(
          child: Text(
            'SIN CARTAS',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF354050),
              letterSpacing: 2,
              fontFamily: 'Cinzel',
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 105,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 13),
        itemCount: cartas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final carta = cartas[i];
          // Las cartas de acción se pagan con `costeHabilidad`, no con
          // `coste` (ese campo es el de despliegue normal). Usar el campo
          // equivocado aquí hacía que una carta se mostrara "asequible"
          // (y se pudiera pulsar) aunque el coste real que se cobra al
          // jugarla fuese mayor que la energía disponible.
          final costeReal = carta.esAccion ? carta.costeHabilidad : carta.coste;
          final affordable = costeReal <= energiesDisponibles;
          return _HandCard(
            carta: carta,
            costeMostrado: costeReal,
            isActive: i == selectedIndex,
            affordable: affordable,
            onTap: affordable ? () => onCardTap(i) : null,
            onLongPress: () => showCardDetail(
              context,
              carta,
              resolveEvolucion: resolveEvolucion,
              onSacrificar: (onSacrificar != null && permiteSacrificio)
                  ? () async => onSacrificar!(i)
                  : null,
              recompensaSacrificio: carta.coste ~/ 2,
            ),
          );
        },
      ),
    );
  }
}

// ── Single card in hand ───────────────────────────────────────
class _HandCard extends StatelessWidget {
  final CartaModel carta;
  final bool isActive;

  /// False si el jugador no tiene energía suficiente para desplegarla.
  final bool affordable;

  /// Coste real que se cobrará al jugar la carta (costeHabilidad para
  /// cartas de acción, coste normal para el resto). Es lo que se muestra
  /// en el círculo de coste, para que coincida con lo que de verdad se
  /// va a descontar.
  final int costeMostrado;

  /// Null cuando la carta no es asequible: así el círculo/tap queda
  /// deshabilitado en vez de solo "verse" bloqueado.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _HandCard({
    required this.carta,
    required this.isActive,
    required this.affordable,
    required this.costeMostrado,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Color del borde del círculo de coste: rojo si no puede pagar, dorado si sí.
    final costCircleColor =
        affordable ? const Color(0xFFB08040) : const Color(0xFF8B2020);
    final costTextColor =
        affordable ? const Color(0xFF040C14) : const Color(0xFFFFAAAA);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        transform: Matrix4.translationValues(0, isActive ? -11 : 0, 0),
        width: 64,
        height: 88,
        decoration: BoxDecoration(
          color: affordable
              ? const Color(0xFF0C1A2A)
              : const Color(0xFF0C0E14), // fondo más oscuro si no puede pagar
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isActive
                ? const Color(0xFFE0C060)
                : affordable
                    ? const Color(0xFF78591E).withOpacity(0.45)
                    : const Color(0xFF5A2020).withOpacity(0.7),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFE0C060).withOpacity(0.25),
                    offset: const Offset(0, -6),
                    blurRadius: 18,
                  ),
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
          child: Column(
            children: [
              // ── Top row: fuerza + coste ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${carta.fuerza}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: affordable
                          ? const Color(0xFFE0C060)
                          : const Color(0xFF806040),
                      fontFamily: 'Cinzel',
                      height: 1,
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: costCircleColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$costeMostrado',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: costTextColor,
                            fontFamily: 'Cinzel'),
                      ),
                    ),
                  ),
                ],
              ),
              // ── Art area ──
              Expanded(
                child: Center(
                  child: Opacity(
                    opacity: affordable ? 1.0 : 0.45,
                    child: carta.imagen.isNotEmpty
                        ? Image.network(
                            carta.imagen,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const _PlaceholderIcon(),
                          )
                        : const _PlaceholderIcon(),
                  ),
                ),
              ),
              // ── Nombre ──
              Text(
                carta.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 6,
                  color: affordable
                      ? const Color(0xFF506878)
                      : const Color(0xFF3A3040),
                  letterSpacing: 0.5,
                  fontFamily: 'Cinzel',
                ),
              ),
              // ── Ejército ──
              Text(
                'EJÉRCITO ${carta.ejercito}',
                style: TextStyle(
                  fontSize: 5,
                  color: affordable
                      ? const Color(0x7F506878)
                      : const Color(0x4F3A3040),
                  fontFamily: 'Cinzel',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.shield_outlined,
        size: 24, color: Color(0xFFB08040));
  }
}
