// lib/views/edicion_historias_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/lobby_model.dart'; // kEjercitos

/// Pantalla de administración de HISTORIAS (solo editores). Mismo patrón que la
/// pantalla de Historias del jugador: selector por ejército arriba y 10 slots
/// debajo. Aquí, en cambio, cada slot se puede crear/editar: título y páginas
/// (imagen + descripción). Escribe directamente en la colección Firestore
/// `Historias` (docs con Ejercito, Orden, Titulo, Paginas[]).
class EdicionHistoriasScreen extends StatefulWidget {
  const EdicionHistoriasScreen({super.key});

  @override
  State<EdicionHistoriasScreen> createState() => _EdicionHistoriasScreenState();
}

class _EdicionHistoriasScreenState extends State<EdicionHistoriasScreen> {
  static const int _slots = 10;
  final _col = FirebaseFirestore.instance.collection('Historias');

  bool _loading = true;
  String? _error;
  int _ejercitoSel = kEjercitos.first.id;

  /// ejercito → orden → resumen
  final Map<int, Map<int, _HistoriaResumen>> _porEjercito = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _col.get();
      final map = <int, Map<int, _HistoriaResumen>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final ej = _int(d['Ejercito'] ?? d['ejercito']);
        final orden = _int(d['Orden'] ?? d['orden']);
        final titulo = (d['Titulo'] ?? d['titulo'] ?? '').toString();
        final paginas = (d['Paginas'] ?? d['paginas']) as List? ?? const [];
        map.putIfAbsent(ej, () => {})[orden] = _HistoriaResumen(
          docId: doc.id,
          titulo: titulo,
          numPaginas: paginas.length,
        );
      }
      if (!mounted) return;
      setState(() {
        _porEjercito
          ..clear()
          ..addAll(map);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _editar(int orden) async {
    final existente = _porEjercito[_ejercitoSel]?[orden];
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EditorHistoria(
          ejercito: _ejercitoSel,
          orden: orden,
          docId: existente?.docId,
        ),
      ),
    );
    if (cambiado == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final delEjercito = _porEjercito[_ejercitoSel] ?? const {};

    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: Color(0xFFA040C0)),
        title: const Text(
          'EDICIÓN · HISTORIAS',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: Color(0xFFA040C0),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFA040C0)),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Selector de ejército ───────────────────────────
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in kEjercitos)
                  _FilterChip(
                    label: '${e.icono} ${e.nombre.toUpperCase()}',
                    selected: _ejercitoSel == e.id,
                    onTap: () => setState(() => _ejercitoSel = e.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFA040C0)),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No se pudieron cargar las historias.\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF506070),
                      fontFamily: 'Cinzel',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _slots,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final orden = i + 1;
                  final r = delEjercito[orden];
                  return _SlotTile(
                    numero: orden,
                    titulo: r?.titulo ?? '',
                    numPaginas: r?.numPaginas ?? 0,
                    existe: r != null,
                    onTap: () => _editar(orden),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoriaResumen {
  final String docId;
  final String titulo;
  final int numPaginas;
  const _HistoriaResumen({
    required this.docId,
    required this.titulo,
    required this.numPaginas,
  });
}

// ─────────────────────────────────────────────────────────────
// SLOT (fila) de la lista de administración
// ─────────────────────────────────────────────────────────────
class _SlotTile extends StatelessWidget {
  final int numero;
  final String titulo;
  final int numPaginas;
  final bool existe;
  final VoidCallback onTap;

  const _SlotTile({
    required this.numero,
    required this.titulo,
    required this.numPaginas,
    required this.existe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = existe ? const Color(0xFFC8A860) : const Color(0xFF506070);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(existe ? 0.35 : 0.15)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$numero.',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Cinzel',
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existe && titulo.isNotEmpty ? titulo : 'Vacía',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'Cinzel',
                      letterSpacing: 0.5,
                      color: existe
                          ? const Color(0xFFE0D8C0)
                          : const Color(0xFF506070),
                      fontStyle: existe ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  if (existe)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$numPaginas página${numPaginas == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'Cinzel',
                          color: Color(0xFF506070),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              existe ? Icons.edit_outlined : Icons.add,
              size: 18,
              color: accent.withOpacity(0.9),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EDITOR de una historia (título + páginas)
// ─────────────────────────────────────────────────────────────
class _EditorHistoria extends StatefulWidget {
  final int ejercito;
  final int orden;
  final String? docId; // null → crear

  const _EditorHistoria({
    required this.ejercito,
    required this.orden,
    this.docId,
  });

  @override
  State<_EditorHistoria> createState() => _EditorHistoriaState();
}

class _EditorHistoriaState extends State<_EditorHistoria> {
  final _col = FirebaseFirestore.instance.collection('Historias');
  final _tituloCtrl = TextEditingController();
  final List<_PaginaEdit> _paginas = [];

  bool _loading = true;
  bool _saving = false;
  String? _docId;

  @override
  void initState() {
    super.initState();
    _docId = widget.docId;
    _load();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    for (final p in _paginas) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.docId != null) {
        final doc = await _col.doc(widget.docId!).get();
        final d = doc.data() ?? const {};
        _tituloCtrl.text = (d['Titulo'] ?? d['titulo'] ?? '').toString();
        final paginas = (d['Paginas'] ?? d['paginas']) as List? ?? const [];
        for (final p in paginas) {
          final pm = Map<String, dynamic>.from(p as Map);
          _paginas.add(_PaginaEdit(
            imagen: (pm['Imagen'] ?? pm['imagen'] ?? '').toString(),
            descripcion:
                (pm['Descripcion'] ?? pm['descripcion'] ?? '').toString(),
          ));
        }
      }
    } catch (_) {
      // Si falla la carga se empieza en blanco.
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cinzel')),
      backgroundColor:
          error ? const Color(0xFF3A0E0E) : const Color(0xFF0E2A14),
    ));
  }

  void _addPagina() {
    setState(() => _paginas.add(_PaginaEdit(imagen: '', descripcion: '')));
  }

  void _removePagina(int i) {
    setState(() {
      _paginas.removeAt(i).dispose();
    });
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _paginas.length) return;
    setState(() {
      final tmp = _paginas[i];
      _paginas[i] = _paginas[j];
      _paginas[j] = tmp;
    });
  }

  Future<void> _guardar() async {
    if (_tituloCtrl.text.trim().isEmpty) {
      _toast('El título no puede estar vacío.', error: true);
      return;
    }
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'Ejercito': widget.ejercito,
      'Orden': widget.orden,
      'Titulo': _tituloCtrl.text.trim(),
      'Paginas': [
        for (int i = 0; i < _paginas.length; i++)
          {
            'Imagen': _paginas[i].imagenCtrl.text.trim(),
            'Descripcion': _paginas[i].descCtrl.text.trim(),
            'Orden': i + 1,
          },
      ],
    };

    try {
      if (_docId != null) {
        await _col.doc(_docId!).set(data, SetOptions(merge: true));
      } else {
        // ID determinista para evitar duplicados por (ejército, orden).
        final id = 'e${widget.ejercito}_${widget.orden}';
        await _col.doc(id).set(data);
        _docId = id;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('No se pudo guardar: $e', error: true);
      }
    }
  }

  Future<void> _eliminar() async {
    if (_docId == null) {
      Navigator.of(context).pop(false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1828),
        title: const Text('Eliminar historia',
            style: TextStyle(color: Color(0xFFE06060), fontFamily: 'Cinzel')),
        content: const Text('Esta historia se borrará permanentemente.',
            style: TextStyle(color: Color(0xFFB0C0D0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF90A0B0))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(color: Color(0xFFE06060))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _col.doc(_docId!).delete();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('No se pudo eliminar: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ejercito = kEjercitos.firstWhere(
      (e) => e.id == widget.ejercito,
      orElse: () => kEjercitos.first,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: Color(0xFFA040C0)),
        title: Text(
          '${ejercito.icono} ${ejercito.nombre.toUpperCase()} · Nº ${widget.orden}',
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'Cinzel',
            letterSpacing: 1.5,
            color: Color(0xFFA040C0),
          ),
        ),
        actions: [
          if (_docId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFE06060)),
              onPressed: _saving ? null : _eliminar,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFA040C0)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const Text('TÍTULO',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2,
                        color: Color(0xFF506070),
                        fontFamily: 'Cinzel')),
                const SizedBox(height: 6),
                _campo(_tituloCtrl, hint: 'Título de la historia'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('PÁGINAS',
                        style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 2,
                            color: Color(0xFF506070),
                            fontFamily: 'Cinzel')),
                    const Spacer(),
                    Text('${_paginas.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFC8A860),
                            fontFamily: 'Cinzel')),
                  ],
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < _paginas.length; i++)
                  _PaginaCard(
                    key: ValueKey(_paginas[i]),
                    numero: i + 1,
                    pagina: _paginas[i],
                    onRemove: () => _removePagina(i),
                    onUp: i > 0 ? () => _move(i, -1) : null,
                    onDown: i < _paginas.length - 1 ? () => _move(i, 1) : null,
                  ),
                const SizedBox(height: 8),
                _botonSecundario(
                  icon: Icons.add,
                  label: 'AÑADIR PÁGINA',
                  onTap: _addPagina,
                ),
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: _saving ? null : _guardar,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF14241A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF4ABB58).withOpacity(0.7),
                          width: 1.5),
                    ),
                    child: Text(
                      _saving ? 'GUARDANDO…' : 'GUARDAR HISTORIA',
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Color(0xFF6AD078),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _campo(TextEditingController c, {String hint = '', int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(
          color: Color(0xFFE0D8C0), fontSize: 13, fontFamily: 'Cinzel'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF405060), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0A1220),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:
              BorderSide(color: const Color(0xFF506070).withOpacity(0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFC8A860)),
        ),
      ),
    );
  }

  Widget _botonSecundario(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: const Color(0xFFA040C0).withOpacity(0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFA040C0)),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cinzel',
                    letterSpacing: 1.5,
                    color: Color(0xFFA040C0))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Estado editable de una página (dos controllers)
// ─────────────────────────────────────────────────────────────
class _PaginaEdit {
  final TextEditingController imagenCtrl;
  final TextEditingController descCtrl;

  _PaginaEdit({required String imagen, required String descripcion})
      : imagenCtrl = TextEditingController(text: imagen),
        descCtrl = TextEditingController(text: descripcion);

  void dispose() {
    imagenCtrl.dispose();
    descCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// Tarjeta de edición de una página
// ─────────────────────────────────────────────────────────────
class _PaginaCard extends StatefulWidget {
  final int numero;
  final _PaginaEdit pagina;
  final VoidCallback onRemove;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _PaginaCard({
    super.key,
    required this.numero,
    required this.pagina,
    required this.onRemove,
    this.onUp,
    this.onDown,
  });

  @override
  State<_PaginaCard> createState() => _PaginaCardState();
}

class _PaginaCardState extends State<_PaginaCard> {
  @override
  Widget build(BuildContext context) {
    final url = widget.pagina.imagenCtrl.text.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF080D18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF203040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PÁGINA ${widget.numero}',
                  style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: Color(0xFFC8A860),
                      fontFamily: 'Cinzel')),
              const Spacer(),
              _iconBtn(Icons.arrow_upward, widget.onUp),
              _iconBtn(Icons.arrow_downward, widget.onDown),
              _iconBtn(Icons.close, widget.onRemove,
                  color: const Color(0xFFE06060)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview de la imagen (si es una URL válida).
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1220),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF203040)),
                ),
                clipBehavior: Clip.antiAlias,
                child: url.startsWith('http')
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: Color(0xFF405060)),
                      )
                    : const Icon(Icons.image_outlined,
                        size: 20, color: Color(0xFF405060)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _mini(
                  widget.pagina.imagenCtrl,
                  hint: 'URL de la imagen',
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _mini(
            widget.pagina.descCtrl,
            hint: 'Descripción de la página',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {Color? color}) {
    final enabled = onTap != null;
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      icon: Icon(icon,
          size: 16,
          color: (color ?? const Color(0xFF90A0B0))
              .withOpacity(enabled ? 1 : 0.25)),
      onPressed: onTap,
    );
  }

  Widget _mini(TextEditingController c,
      {String hint = '', int maxLines = 1, VoidCallback? onChanged}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      style: const TextStyle(color: Color(0xFFE0D8C0), fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF405060), fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF0A1220),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide:
              BorderSide(color: const Color(0xFF506070).withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFFC8A860)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHIP DE EJÉRCITO (mismo estilo que Historias / Edición)
// ─────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFA040C0).withOpacity(0.18)
                : const Color(0xFF0A1220),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFA040C0)
                  : const Color(0xFF506070).withOpacity(0.4),
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
              color:
                  selected ? const Color(0xFFA040C0) : const Color(0xFF506070),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
