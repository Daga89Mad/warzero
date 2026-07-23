// lib/screens/cuartel_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/carta_model.dart';
import '../services/settings_controller.dart';
import '../widgets/card_detail_overlay.dart';

/// Resultado de un intento de compra de carta especial.
class CompraResult {
  final bool ok;
  final String mensaje;

  /// Zero restantes del jugador tras la operación.
  final int energiasRestantes;

  const CompraResult({
    required this.ok,
    required this.mensaje,
    required this.energiasRestantes,
  });
}

/// Pantalla del CUARTEL: muestra las cartas ESPECIALES del ejército del jugador
/// y permite comprarlas con Zero. Al comprar, la carta va directa al cuartel
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

  // Colores semánticos que se mantienen fijos en cualquier tema.
  static const _energy = Color(0xFF2EA6FF); // Zero / energía
  static const _verde = Color(0xFF4ABB58); // comprado / disponible
  static const _rojo = Color(0xFF9A5050); // sin energía / error

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
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        iconTheme: IconThemeData(color: war.primario),
        title: Text('CUARTEL',
            style: TextStyle(
                color: war.primario,
                fontFamily: 'Cinzel',
                fontSize: 16,
                letterSpacing: 2)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              const Text('Ø',
                  style: TextStyle(
                      color: _energy,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text('$_energias',
                  style: TextStyle(
                      color: war.texto,
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
              color: war.primario.withOpacity(0.12),
              child: Text(
                'Solo puedes comprar durante tu turno (antes de cerrarlo).',
                textAlign: TextAlign.center,
                style: TextStyle(color: war.primario, fontSize: 12),
              ),
            ),
          Expanded(child: _buildLista()),
        ],
      ),
    );
  }

  Widget _buildLista() {
    final war = context.war;
    if (widget.ejercitoId == null) {
      return Center(
        child: Text('Sin ejército asignado.',
            style: TextStyle(color: war.textoTenue)),
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
          return Center(child: CircularProgressIndicator(color: war.primario));
        }
        if (snap.hasError) {
          return Center(
            child: Text('Error al cargar especiales:\n${snap.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: war.error)),
          );
        }

        final especiales = (snap.data?.docs ?? [])
            .map((d) => CartaModel.fromFirestore(d))
            .where((c) => c.ejercito == widget.ejercitoId)
            .toList()
          ..sort((a, b) => a.coste.compareTo(b.coste));

        if (especiales.isEmpty) {
          return Center(
            child: Text('No hay cartas especiales para tu ejército.',
                textAlign: TextAlign.center,
                style: TextStyle(color: war.textoTenue)),
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
    final war = context.war;
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
          color: war.superficie,
          border: Border.all(color: war.primario.withOpacity(0.20)),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: war.fondo,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: war.primario.withOpacity(0.20)),
              ),
              alignment: Alignment.center,
              child: carta.imagen.trim().isEmpty
                  ? Icon(Icons.star, color: war.primario, size: 22)
                  : Image.network(
                      carta.imagen,
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: war.primario),
                              ),
                            ),
                      errorBuilder: (c, e, s) =>
                          Icon(Icons.star, color: war.primario, size: 22),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(carta.nombre,
                      style: TextStyle(
                          color: war.texto,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '⚔ ${carta.fuerza}   🛡 ${carta.defensa}   ➤ ${carta.movimiento}',
                    style: TextStyle(color: war.textoTenue, fontSize: 11),
                  ),
                  if (carta.descripcion.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(carta.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: war.textoTenue.withOpacity(0.8),
                              fontSize: 10)),
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
    final war = context.war;
    if (yaComprada) {
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: _verde, size: 22),
        Text('Comprada', style: TextStyle(color: _verde, fontSize: 9)),
      ]);
    }
    return SizedBox(
      width: 80,
      child: ElevatedButton(
        onPressed: habilitado ? () => _comprar(carta) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E5631),
          disabledBackgroundColor: war.fondo,
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
                  const Text('Ø ',
                      style: TextStyle(
                          color: _energy,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  Text('${carta.coste}',
                      style: TextStyle(
                          color: sinEnergia ? _rojo : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
                Text(sinEnergia ? 'Sin energía' : 'Comprar',
                    style: TextStyle(
                        color: sinEnergia ? _rojo : Colors.white70,
                        fontSize: 9)),
              ]),
      ),
    );
  }
}
