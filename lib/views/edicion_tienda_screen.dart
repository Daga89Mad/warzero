// lib/views/edicion_tienda_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/tienda_model.dart';
import '../services/settings_controller.dart';

/// EDITAR TIENDA (solo editores)
///
/// Gestiona los artículos de la tienda (colección Firestore `Tienda`). Permite
/// crear, editar y borrar artículos, dando a cada uno: categoría (pestaña),
/// nombre, descripción, imagen (URL), coste, moneda, si está activo y su orden.
///
/// Escribe directamente en Firestore, igual que el resto de editores del juego.
class EdicionTiendaScreen extends StatefulWidget {
  const EdicionTiendaScreen({super.key});

  @override
  State<EdicionTiendaScreen> createState() => _EdicionTiendaScreenState();
}

class _EdicionTiendaScreenState extends State<EdicionTiendaScreen> {
  static const _accent = Color(0xFFE0B040);

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
      final snap = await _col.get();
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

  /// Abre el formulario para crear o editar. Si [base] es null, crea uno nuevo
  /// en la categoría [categoria].
  Future<void> _abrirEditor(
      {ArticuloTienda? base, required TiendaCategoria categoria}) async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ArticuloEditor(
          col: _col,
          base: base,
          categoriaInicial: base?.categoria ?? categoria,
          accent: _accent,
        ),
      ),
    );
    if (cambiado == true) _cargar();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor:
            error ? const Color(0xFF7A1010) : const Color(0xFF1C3020),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const cats = TiendaCategoria.values;

    return DefaultTabController(
      length: cats.length,
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: war.fondo,
          appBar: AppBar(
            backgroundColor: war.superficie,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 16, color: _accent),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('EDITAR TIENDA',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 13,
                    letterSpacing: 3,
                    color: _accent)),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: war.textoTenue),
                onPressed: _loading ? null : _cargar,
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              indicatorColor: _accent,
              labelColor: _accent,
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
          floatingActionButton: Builder(builder: (context) {
            return FloatingActionButton.extended(
              backgroundColor: _accent,
              onPressed: () {
                final idx = DefaultTabController.of(context).index;
                _abrirEditor(categoria: cats[idx]);
              },
              icon: const Icon(Icons.add, color: Colors.black87),
              label: const Text('NUEVO',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.black87)),
            );
          }),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: _accent))
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
                          _ListaCategoria(
                            articulos: _deCategoria(c),
                            accent: _accent,
                            onEditar: (a) =>
                                _abrirEditor(base: a, categoria: c),
                          ),
                      ],
                    ),
        );
      }),
    );
  }
}

class _ListaCategoria extends StatelessWidget {
  final List<ArticuloTienda> articulos;
  final Color accent;
  final void Function(ArticuloTienda) onEditar;

  const _ListaCategoria({
    required this.articulos,
    required this.accent,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    if (articulos.isEmpty) {
      return Center(
        child: Text('Sin artículos. Pulsa NUEVO para añadir uno.',
            style: TextStyle(
                fontFamily: 'Cinzel', fontSize: 10, color: war.textoTenue)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: articulos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = articulos[i];
        return GestureDetector(
          onTap: () => onEditar(a),
          child: Container(
            decoration: BoxDecoration(
              color: war.superficie,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: a.activo
                      ? accent.withOpacity(0.30)
                      : war.borde.withOpacity(0.30)),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: war.fondo,
                    child: a.imagen.isNotEmpty
                        ? Image.network(a.imagen,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.image_outlined,
                                size: 22,
                                color: war.textoTenue.withOpacity(0.5)))
                        : Icon(Icons.image_outlined,
                            size: 22, color: war.textoTenue.withOpacity(0.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(a.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: war.texto)),
                          ),
                          if (!a.activo)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: war.error.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text('OCULTO',
                                  style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      fontSize: 7,
                                      letterSpacing: 1,
                                      color: war.error)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text('${a.coste} ${a.moneda}  ·  orden ${a.orden}',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 9,
                              color: war.textoTenue)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: war.textoTenue, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FORMULARIO DE ARTÍCULO (crear / editar / borrar)
// ─────────────────────────────────────────────────────────────
class _ArticuloEditor extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final ArticuloTienda? base; // null = nuevo
  final TiendaCategoria categoriaInicial;
  final Color accent;

  const _ArticuloEditor({
    required this.col,
    required this.base,
    required this.categoriaInicial,
    required this.accent,
  });

  @override
  State<_ArticuloEditor> createState() => _ArticuloEditorState();
}

class _ArticuloEditorState extends State<_ArticuloEditor> {
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _imagen;
  late final TextEditingController _coste;
  late final TextEditingController _moneda;
  late final TextEditingController _orden;

  late TiendaCategoria _categoria;
  late bool _activo;
  bool _guardando = false;

  bool get _esNuevo => widget.base == null;

  @override
  void initState() {
    super.initState();
    final b = widget.base;
    _nombre = TextEditingController(text: b?.nombre ?? '');
    _descripcion = TextEditingController(text: b?.descripcion ?? '');
    _imagen = TextEditingController(text: b?.imagen ?? '');
    _coste = TextEditingController(text: '${b?.coste ?? 0}');
    _moneda = TextEditingController(text: b?.moneda ?? 'Zero Puro');
    _orden = TextEditingController(text: '${b?.orden ?? 0}');
    _categoria = widget.categoriaInicial;
    _activo = b?.activo ?? true;
    // Refresca la vista previa de la imagen al escribir la URL.
    _imagen.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _imagen.dispose();
    _coste.dispose();
    _moneda.dispose();
    _orden.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _toast('El nombre no puede estar vacío', error: true);
      return;
    }
    setState(() => _guardando = true);
    final data = {
      'categoria': _categoria.key,
      'nombre': nombre,
      'descripcion': _descripcion.text.trim(),
      'imagen': _imagen.text.trim(),
      'coste': int.tryParse(_coste.text.trim()) ?? 0,
      'moneda': _moneda.text.trim().isEmpty ? 'Zero Puro' : _moneda.text.trim(),
      'activo': _activo,
      'orden': int.tryParse(_orden.text.trim()) ?? 0,
    };
    try {
      if (_esNuevo) {
        await widget.col.add(data);
      } else {
        await widget.col
            .doc(widget.base!.id)
            .set(data, SetOptions(merge: true));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _toast('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _borrar() async {
    if (_esNuevo) return;
    final war = context.war;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: war.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('¿Borrar artículo?',
            style: TextStyle(
                fontFamily: 'Cinzel', fontSize: 13, color: war.error)),
        content: Text('Se eliminará "${widget.base!.nombre}" de la tienda.',
            style: TextStyle(
                fontFamily: 'Cinzel', fontSize: 10, color: war.textoTenue)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCELAR',
                style: TextStyle(
                    fontFamily: 'Cinzel', fontSize: 10, color: war.textoTenue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('BORRAR',
                style: TextStyle(
                    fontFamily: 'Cinzel', fontSize: 10, color: war.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await widget.col.doc(widget.base!.id).delete();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _toast('No se pudo borrar: $e', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor:
            error ? const Color(0xFF7A1010) : const Color(0xFF1C3020),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = widget.accent;

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 16, color: accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_esNuevo ? 'NUEVO ARTÍCULO' : 'EDITAR ARTÍCULO',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 2,
                color: accent)),
        actions: [
          if (!_esNuevo)
            IconButton(
              icon: Icon(Icons.delete_outline, color: war.error, size: 20),
              onPressed: _guardando ? null : _borrar,
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _guardando,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Vista previa de la imagen.
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 120,
                  height: 120,
                  color: war.superficie,
                  child: _imagen.text.trim().isNotEmpty
                      ? Image.network(
                          _imagen.text.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                              Icons.broken_image_outlined,
                              size: 34,
                              color: war.textoTenue.withOpacity(0.5)),
                        )
                      : Icon(Icons.image_outlined,
                          size: 34, color: war.textoTenue.withOpacity(0.5)),
                ),
              ),
            ),
            const SizedBox(height: 18),

            _campoLabel('CATEGORÍA', war),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in TiendaCategoria.values)
                  GestureDetector(
                    onTap: () => setState(() => _categoria = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _categoria == c
                            ? accent.withOpacity(0.18)
                            : war.superficie,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _categoria == c
                                ? accent.withOpacity(0.8)
                                : war.borde.withOpacity(0.4),
                            width: _categoria == c ? 1.4 : 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon,
                              size: 14,
                              color: _categoria == c ? accent : war.textoTenue),
                          const SizedBox(width: 6),
                          Text(c.label,
                              style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 10,
                                  color: _categoria == c
                                      ? accent
                                      : war.textoTenue)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            _campo('NOMBRE', _nombre, war, accent),
            _campo('DESCRIPCIÓN', _descripcion, war, accent, maxLines: 3),
            _campo('IMAGEN (URL)', _imagen, war, accent),
            Row(
              children: [
                Expanded(
                  child: _campo('COSTE', _coste, war, accent,
                      teclado: TextInputType.number),
                ),
                const SizedBox(width: 12),
                Expanded(child: _campo('MONEDA', _moneda, war, accent)),
              ],
            ),
            _campo('ORDEN', _orden, war, accent, teclado: TextInputType.number),
            const SizedBox(height: 8),

            // Activo.
            Row(
              children: [
                Text('VISIBLE EN LA TIENDA',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        letterSpacing: 1,
                        color: war.textoTenue)),
                const Spacer(),
                Switch(
                  value: _activo,
                  activeColor: accent,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Guardar.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent.withOpacity(0.18),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: accent.withOpacity(0.6)),
                  ),
                ),
                child: _guardando
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: accent),
                      )
                    : Text(_esNuevo ? 'CREAR' : 'GUARDAR',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 12,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            color: accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoLabel(String label, WarColors war) => Text(
        label,
        style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 9,
            letterSpacing: 1.5,
            color: war.textoTenue),
      );

  Widget _campo(
    String label,
    TextEditingController ctrl,
    WarColors war,
    Color accent, {
    int maxLines = 1,
    TextInputType? teclado,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _campoLabel(label, war),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: teclado,
            style:
                TextStyle(fontFamily: 'Cinzel', fontSize: 12, color: war.texto),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: war.superficie,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: war.borde.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: accent.withOpacity(0.7)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
