// lib/screens/cuartel_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/carta_model.dart';
import '../widgets/card_detail_overlay.dart';

/// Resultado de un intento de compra de carta especial.
class CompraResult {
  final bool ok;
  final String mensaje;

  /// Energies restantes del jugador tras la operación.
  final int energiasRestantes;

  const CompraResult({
    required this.ok,
    required this.mensaje,
    required this.energiasRestantes,
  });
}

/// Pantalla del CUARTEL: muestra las cartas ESPECIALES del ejército del jugador
/// y permite comprarlas con Energies. Al comprar, la carta va directa al cuartel
/// (lo gestiona [onComprar]) y queda deshabilitada para futuras compras del
/// jugador durante el resto de la partida.
class CuartelScreen extends StatefulWidget {
  final int? ejercitoId;
  final int energiasIniciales;

  /// True si el jugador puede comprar ahora (es su turno y no lo ha cerrado).
  final bool puedeComprar;

  /// IDs de especiales ya compradas por el jugador (deshabilitadas).
  final Set<String> compradasIniciales;

  /// Ejecuta la compra. Devuelve el resultado (incluye energías restantes).
  final Future<CompraResult> Function(CartaModel carta) onComprar;

  const CuartelScreen({
    super.key,
    required this.ejercitoId,
    required this.energiasIniciales,
    required this.puedeComprar,
    required this.compradasIniciales,
    required this.onComprar,
  });

  @override
  State<CuartelScreen> createState() => _CuartelScreenState();
}

class _CuartelScreenState extends State<CuartelScreen> {
  late int _energias;
  late Set<String> _compradas;
  String? _comprandoId; // id en curso (evita doble compra)

  static const _bg = Color(0xFF0A1018);
  static const _panel = Color(0xFF0F1A28);
  static const _gold = Color(0xFFC8A860);
  static const _energy = Color(0xFFD4A800); // ← rayo dorado de energies
  static const _border = Color(0x33C8A860);

  @override
  void initState() {
    super.initState();
    _energias = widget.energiasIniciales;
    _compradas = {...widget.compradasIniciales};
  }

  Future<void> _comprar(CartaModel carta) async {
    if (_comprandoId != null) return;
    setState(() => _comprandoId = carta.id);
    final res = await widget.onComprar(carta);
    if (!mounted) return;
    setState(() {
      _comprandoId = null;
      _energias = res.energiasRestantes;
      if (res.ok) _compradas.add(carta.id);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(res.mensaje),
        backgroundColor:
            res.ok ? const Color(0xFF1E5631) : const Color(0xFF6B2020),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _gold),
        title: const Text('CUARTEL',
            style: TextStyle(
                color: _gold,
                fontFamily: 'Cinzel',
                fontSize: 16,
                letterSpacing: 2)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              const Icon(Icons.flash_on, color: _energy, size: 16),
              const SizedBox(width: 4),
              Text('$_energias',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.puedeComprar)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: const Color(0xFF2A1A0A),
              child: const Text(
                'Solo puedes comprar durante tu turno (antes de cerrarlo).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFE0A030), fontSize: 12),
              ),
            ),
          Expanded(child: _buildLista()),
        ],
      ),
    );
  }

  Widget _buildLista() {
    if (widget.ejercitoId == null) {
      return const Center(
        child: Text('Sin ejército asignado.',
            style: TextStyle(color: Color(0xFF607080))),
      );
    }

    // Filtramos por Condicion en la query y por ejército en cliente para evitar
    // requerir un índice compuesto en Firestore.
    final query = FirebaseFirestore.instance
        .collection('Cartas')
        .where('Condicion', isEqualTo: CondicionCarta.especial.value);

    return FutureBuilder<QuerySnapshot>(
      future: query.get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _gold));
        }
        if (snap.hasError) {
          return Center(
            child: Text('Error al cargar especiales:\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9A5050))),
          );
        }

        final especiales = (snap.data?.docs ?? [])
            .map((d) => CartaModel.fromFirestore(d))
            .where((c) => c.ejercito == widget.ejercitoId)
            .toList()
          ..sort((a, b) => a.coste.compareTo(b.coste));

        if (especiales.isEmpty) {
          return const Center(
            child: Text('No hay cartas especiales para tu ejército.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF607080))),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: especiales.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _buildTile(especiales[i]),
        );
      },
    );
  }

  Widget _buildTile(CartaModel carta) {
    final yaComprada = _compradas.contains(carta.id);
    final sinEnergia = _energias < carta.coste;
    final enCurso = _comprandoId == carta.id;
    final habilitado = widget.puedeComprar &&
        !yaComprada &&
        !sinEnergia &&
        _comprandoId == null;

    return GestureDetector(
      // Mantener pulsado → ver la carta en grande.
      onLongPress: () => showCardDetail(context, carta),
      child: Container(
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2838),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.star, color: _gold, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(carta.nombre,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '⚔ ${carta.fuerza}   🛡 ${carta.defensa}   ➤ ${carta.movimiento}',
                    style:
                        const TextStyle(color: Color(0xFF8898A8), fontSize: 11),
                  ),
                  if (carta.descripcion.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(carta.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF607080), fontSize: 10)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildBoton(carta, yaComprada, sinEnergia, enCurso, habilitado),
          ],
        ),
      ),
    );
  }

  Widget _buildBoton(CartaModel carta, bool yaComprada, bool sinEnergia,
      bool enCurso, bool habilitado) {
    if (yaComprada) {
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: Color(0xFF4ABB58), size: 22),
        Text('Comprada',
            style: TextStyle(color: Color(0xFF4ABB58), fontSize: 9)),
      ]);
    }
    return SizedBox(
      width: 80,
      child: ElevatedButton(
        onPressed: habilitado ? () => _comprar(carta) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E5631),
          disabledBackgroundColor: const Color(0xFF1A2230),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: enCurso
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flash_on, size: 12, color: _energy),
                  Text('${carta.coste}',
                      style: TextStyle(
                          color: sinEnergia
                              ? const Color(0xFF9A5050)
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
                Text(sinEnergia ? 'Sin energía' : 'Comprar',
                    style: TextStyle(
                        color: sinEnergia
                            ? const Color(0xFF9A5050)
                            : Colors.white70,
                        fontSize: 9)),
              ]),
      ),
    );
  }
}
