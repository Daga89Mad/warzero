// lib/views/tienda_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/tienda_model.dart';
import '../services/settings_controller.dart';

/// TIENDA
///
/// Muestra los artículos a la venta agrupados en cuatro pestañas: Marcos,
/// Iconos, Ofertas y Packs. Los artículos los crean/editan los editores desde
/// la pantalla "Editar Tienda" (colección Firestore `Tienda`).
///
/// La COMPRA todavía no está conectada a la economía del juego: al pulsar
/// COMPRAR se pide confirmación y se deja el punto donde enganchar el cobro y la
/// entrega (ver [_comprar]).
class TiendaScreen extends StatefulWidget {
  const TiendaScreen({super.key});

  @override
  State<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends State<TiendaScreen> {
  final _col = FirebaseFirestore.instance.collection('Tienda');

  bool _loading = true;
  String? _error;
  List<ArticuloTienda> _articulos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Solo artículos activos. El orden se aplica en cliente (así no hace falta
      // índice compuesto en Firestore).
      final snap = await _col.where('activo', isEqualTo: true).get();
      final lista = snap.docs.map(ArticuloTienda.fromDoc).toList()
        ..sort((a, b) {
          final c = a.orden.compareTo(b.orden);
          return c != 0 ? c : a.nombre.compareTo(b.nombre);
        });
      if (!mounted) return;
      setState(() {
        _articulos = lista;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<ArticuloTienda> _deCategoria(TiendaCategoria c) =>
      _articulos.where((a) => a.categoria == c).toList();

  /// Punto de enganche de la compra. De momento solo confirma y avisa: aquí es
  /// donde habría que descontar la moneda correspondiente y entregar el artículo
  /// (marco/icono/pack) al jugador, seguramente vía un endpoint del backend.
  Future<void> _comprar(ArticuloTienda a) async {
    final war = context.war;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: war.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Comprar ${a.nombre}',
            style: TextStyle(
                fontFamily: 'Cinzel', fontSize: 13, color: war.primario)),
        content: Text(
          '${a.descripcion}\n\nCoste: ${a.coste} ${a.moneda}',
          style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 10,
              height: 1.6,
              color: war.textoTenue),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCELAR',
                style: TextStyle(
                    fontFamily: 'Cinzel', fontSize: 10, color: war.textoTenue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('COMPRAR',
                style: TextStyle(
                    fontFamily: 'Cinzel', fontSize: 10, color: war.primario)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // TODO(economía): cobrar la moneda y entregar el artículo al jugador.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Compra de "${a.nombre}" pendiente de conectar',
            style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor: const Color(0xFF1C3020),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const cats = TiendaCategoria.values;

    return DefaultTabController(
      length: cats.length,
      child: Scaffold(
        backgroundColor: war.fondo,
        appBar: AppBar(
          backgroundColor: war.superficie,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('TIENDA',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 13,
                  letterSpacing: 3,
                  color: war.primario)),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, size: 18, color: war.textoTenue),
              onPressed: _loading ? null : _cargar,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: war.primario,
            labelColor: war.primario,
            unselectedLabelColor: war.textoTenue,
            labelStyle: const TextStyle(
                fontFamily: 'Cinzel', fontSize: 11, letterSpacing: 1),
            tabs: [
              for (final c in cats)
                Tab(
                  height: 42,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(c.icon, size: 15),
                      const SizedBox(width: 6),
                      Text(c.label.toUpperCase()),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: war.primario))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 11,
                              color: war.textoTenue)),
                    ),
                  )
                : TabBarView(
                    children: [
                      for (final c in cats)
                        _CategoriaTab(
                          articulos: _deCategoria(c),
                          onComprar: _comprar,
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _CategoriaTab extends StatelessWidget {
  final List<ArticuloTienda> articulos;
  final void Function(ArticuloTienda) onComprar;

  const _CategoriaTab({required this.articulos, required this.onComprar});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    if (articulos.isEmpty) {
      return Center(
        child: Text('No hay artículos en esta sección todavía.',
            style: TextStyle(
                fontFamily: 'Cinzel', fontSize: 10, color: war.textoTenue)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: articulos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) =>
          _ArticuloCard(articulo: articulos[i], onComprar: onComprar),
    );
  }
}

class _ArticuloCard extends StatelessWidget {
  final ArticuloTienda articulo;
  final void Function(ArticuloTienda) onComprar;

  const _ArticuloCard({required this.articulo, required this.onComprar});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final a = articulo;

    return Container(
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: war.primario.withOpacity(0.18)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen del artículo.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 74,
              height: 74,
              color: war.fondo,
              child: a.imagen.isNotEmpty
                  ? Image.network(
                      a.imagen,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.image_outlined,
                          color: war.textoTenue.withOpacity(0.5), size: 28),
                    )
                  : Icon(Icons.image_outlined,
                      color: war.textoTenue.withOpacity(0.5), size: 28),
            ),
          ),
          const SizedBox(width: 12),
          // Nombre, descripción, coste + botón.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: war.texto,
                  ),
                ),
                if (a.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    a.descripcion,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      height: 1.5,
                      color: war.textoTenue,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.diamond, size: 13, color: war.primario),
                    const SizedBox(width: 4),
                    Text(
                      '${a.coste} ${a.moneda}',
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: war.primario,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => onComprar(a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: war.primario.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: war.primario.withOpacity(0.5)),
                        ),
                        child: Text(
                          'COMPRAR',
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 9,
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold,
                            color: war.primario,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
