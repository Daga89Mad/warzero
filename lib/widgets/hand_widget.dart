// lib/widgets/hand_widget.dart

import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import 'card_detail_overlay.dart';

class HandWidget extends StatelessWidget {
  final List<CartaModel> cartas;
  final int? selectedIndex;
  final Function(int) onCardTap;

  const HandWidget({
    super.key,
    required this.cartas,
    required this.selectedIndex,
    required this.onCardTap,
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
        itemBuilder: (context, i) => _HandCard(
          carta: cartas[i],
          isActive: i == selectedIndex,
          onTap: () => onCardTap(i),
          onLongPress: () => showCardDetail(context, cartas[i]),
        ),
      ),
    );
  }
}

// ── Single card in hand ───────────────────────────────────────
class _HandCard extends StatelessWidget {
  final CartaModel carta;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HandCard({
    required this.carta,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        transform: Matrix4.translationValues(0, isActive ? -11 : 0, 0),
        width: 64,
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF0C1A2A),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isActive
                ? const Color(0xFFE0C060)
                : const Color(0xFF78591E).withOpacity(0.45),
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
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE0C060),
                      fontFamily: 'Cinzel',
                      height: 1,
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB08040),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${carta.coste}',
                        style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF040C14),
                            fontFamily: 'Cinzel'),
                      ),
                    ),
                  ),
                ],
              ),
              // ── Art area ──
              Expanded(
                child: Center(
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
              // ── Nombre ──
              Text(
                carta.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 6,
                  color: Color(0xFF506878),
                  letterSpacing: 0.5,
                  fontFamily: 'Cinzel',
                ),
              ),
              // ── Ejército ──
              Text(
                'EJÉRCITO ${carta.ejercito}',
                style: const TextStyle(
                  fontSize: 5,
                  color: Color(0x7F506878),
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
