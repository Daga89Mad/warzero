// lib/views/edicion_skins_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/carta_model.dart';

/// Rarezas disponibles (id interno → etiqueta visible), de menor a mayor.
const List<({String id, String label, Color color})> kRarezas = [
  (id: 'comun', label: 'Común', color: Color(0xFF9AA5B0)),
  (id: 'rara', label: 'Rara', color: Color(0xFF4A9DE0)),
  (id: 'epica', label: 'Épica', color: Color(0xFFB060D0)),
  (id: 'legendaria', label: 'Legendaria', color: Color(0xFFE0A020)),
];

Color _colorRareza(String r) =>
    kRarezas.firstWhere((x) => x.id == r, orElse: () => kRarezas.first).color;
String _labelRareza(String r) =>
    kRarezas.firstWhere((x) => x.id == r, orElse: () => kRarezas.first).label;

/// Administración de SKINS (solo editores). Permite crear una skin, asociarla a
/// una carta, rellenar su URL y rareza, y guardarla o modificarla. Escribe
/// directamente en la colección Firestore `Skins` (docs con cartaId, imagen,
/// rareza), que es lo que el servidor sirve a los jugadores.
class EdicionSkinsScreen extends StatefulWidget {
  const EdicionSkinsScreen({super.key});

  @override
  State<EdicionSkinsScreen> createState() => _EdicionSkinsScreenState();
}

class _EdicionSkinsScreenState extends State<EdicionSkinsScreen> {
  static const _accent = Color(0xFF30B0A0);
  final _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  List<CartaModel> _cartas = [];
  Map<String, CartaModel> _cartaPorId = {};
  List<_SkinItem> _skins = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cartasSnap = await _db.collection('Cartas').get();
      final cartas = cartasSnap.docs.map(CartaModel.fromFirestore).toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));

      final skinsSnap = await _db.collection('Skins').get();
      final skins = skinsSnap.docs.map((doc) {
        final d = doc.data();
        return _SkinItem(
          docId: doc.id,
          cartaId: (d['cartaId'] ?? d['CartaId'] ?? '').toString(),
          imagen: (d['imagen'] ?? d['Imagen'] ?? '').toString(),
          rareza: (d['rareza'] ?? d['Rareza'] ?? 'comun').toString(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _cartas = cartas;
        _cartaPorId = {for (final c in cartas) c.id: c};
        _skins = skins;
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

  Future<void> _abrirEditor({_SkinItem? skin}) async {
    if (_cartas.isEmpty) return;
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EditorSkin(cartas: _cartas, skin: skin),
      ),
    );
    if (cambiado == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: _accent),
        title: const Text(
          'EDICIÓN · SKINS',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: _accent,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _accent,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('NUEVA SKIN',
                  style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      letterSpacing: 1)),
              onPressed: () => _abrirEditor(),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudieron cargar las skins.\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF506070),
                            fontFamily: 'Cinzel',
                            height: 1.4)),
                  ),
                )
              : _skins.isEmpty
                  ? const Center(
                      child: Text('No hay skins todavía.\nPulsa "NUEVA SKIN".',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF506070),
                              fontFamily: 'Cinzel',
                              height: 1.4)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _skins.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final s = _skins[i];
                        final carta = _cartaPorId[s.cartaId];
                        return _SkinTile(
                          skin: s,
                          nombreCarta: carta?.nombre ?? '(carta desconocida)',
                          onTap: () => _abrirEditor(skin: s),
                        );
                      },
                    ),
    );
  }
}

class _SkinItem {
  final String docId;
  final String cartaId;
  final String imagen;
  final String rareza;
  const _SkinItem({
    required this.docId,
    required this.cartaId,
    required this.imagen,
    required this.rareza,
  });
}

// ─────────────────────────────────────────────────────────────
// Fila de skin en la lista
// ─────────────────────────────────────────────────────────────
class _SkinTile extends StatelessWidget {
  final _SkinItem skin;
  final String nombreCarta;
  final VoidCallback onTap;

  const _SkinTile({
    required this.skin,
    required this.nombreCarta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = _colorRareza(skin.rareza);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: col.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            _preview(skin.imagen, col),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombreCarta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'Cinzel',
                          letterSpacing: 0.5,
                          color: Color(0xFFE0D8C0))),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: col.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: col.withOpacity(0.6)),
                    ),
                    child: Text(_labelRareza(skin.rareza).toUpperCase(),
                        style: TextStyle(
                            fontSize: 8,
                            letterSpacing: 1,
                            fontFamily: 'Cinzel',
                            color: col)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF30B0A0)),
          ],
        ),
      ),
    );
  }

  Widget _preview(String url, Color col) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF060C16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.startsWith('http')
          ? Image.network(url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: Color(0xFF405060)))
          : const Icon(Icons.image_outlined,
              size: 18, color: Color(0xFF405060)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Editor de una skin (carta + URL + rareza)
// ─────────────────────────────────────────────────────────────
class _EditorSkin extends StatefulWidget {
  final List<CartaModel> cartas;
  final _SkinItem? skin; // null → nueva

  const _EditorSkin({required this.cartas, this.skin});

  @override
  State<_EditorSkin> createState() => _EditorSkinState();
}

class _EditorSkinState extends State<_EditorSkin> {
  static const _accent = Color(0xFF30B0A0);
  final _col = FirebaseFirestore.instance.collection('Skins');
  final _urlCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  String? _cartaId;
  String _rareza = 'comun';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.skin != null) {
      _cartaId = widget.skin!.cartaId;
      _urlCtrl.text = widget.skin!.imagen;
      _rareza = widget.skin!.rareza;
    }
    _urlCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cinzel')),
      backgroundColor:
          error ? const Color(0xFF3A0E0E) : const Color(0xFF0E2A24),
    ));
  }

  Future<void> _guardar() async {
    if (_cartaId == null || _cartaId!.isEmpty) {
      _toast('Selecciona una carta para asociar la skin.', error: true);
      return;
    }
    if (_urlCtrl.text.trim().isEmpty) {
      _toast('La URL de la imagen no puede estar vacía.', error: true);
      return;
    }
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'cartaId': _cartaId,
      'imagen': _urlCtrl.text.trim(),
      'rareza': _rareza,
    };
    try {
      if (widget.skin != null) {
        await _col.doc(widget.skin!.docId).set(data, SetOptions(merge: true));
      } else {
        await _col.add(data); // id automático (una carta puede tener varias)
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
    if (widget.skin == null) {
      Navigator.of(context).pop(false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1828),
        title: const Text('Eliminar skin',
            style: TextStyle(color: Color(0xFFE06060), fontFamily: 'Cinzel')),
        content: const Text('Esta skin se borrará permanentemente.',
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
      await _col.doc(widget.skin!.docId).delete();
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
    final url = _urlCtrl.text.trim();
    final query = _searchCtrl.text.trim().toLowerCase();
    final cartasFiltradas = query.isEmpty
        ? widget.cartas
        : widget.cartas
            .where((c) => c.nombre.toLowerCase().contains(query))
            .toList();
    final cartaSel = _cartaId == null
        ? null
        : widget.cartas.cast<CartaModel?>().firstWhere(
              (c) => c!.id == _cartaId,
              orElse: () => null,
            );

    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: _accent),
        title: Text(widget.skin == null ? 'NUEVA SKIN' : 'EDITAR SKIN',
            style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Cinzel',
                letterSpacing: 1.5,
                color: _accent)),
        actions: [
          if (widget.skin != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFE06060)),
              onPressed: _saving ? null : _eliminar,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── Preview de la imagen ──
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF060C16),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: _colorRareza(_rareza).withOpacity(0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: url.startsWith('http')
                  ? Image.network(url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          size: 32,
                          color: Color(0xFF405060)))
                  : const Icon(Icons.image_outlined,
                      size: 32, color: Color(0xFF405060)),
            ),
          ),
          const SizedBox(height: 20),

          _label('CARTA ASOCIADA'),
          const SizedBox(height: 6),
          if (cartaSel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1220),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _accent.withOpacity(0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.style, size: 16, color: _accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cartaSel.nombre,
                        style: const TextStyle(
                            color: Color(0xFFE0D8C0),
                            fontFamily: 'Cinzel',
                            fontSize: 13)),
                  ),
                  const Text('cambiar',
                      style: TextStyle(color: Color(0xFF607080), fontSize: 10)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // Buscador + lista de cartas
          _campo(_searchCtrl,
              hint: 'Buscar carta…', onChanged: () => setState(() {})),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF080D18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF203040)),
            ),
            child: cartasFiltradas.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Sin resultados.',
                        style:
                            TextStyle(color: Color(0xFF506070), fontSize: 11)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: cartasFiltradas.length,
                    itemBuilder: (_, i) {
                      final c = cartasFiltradas[i];
                      final sel = c.id == _cartaId;
                      return InkWell(
                        onTap: () => setState(() => _cartaId = c.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          color: sel
                              ? _accent.withOpacity(0.12)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              Icon(
                                sel
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 14,
                                color: sel ? _accent : const Color(0xFF405060),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(c.nombre,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: sel
                                            ? const Color(0xFFCFEFE8)
                                            : const Color(0xFFB0BCC8),
                                        fontSize: 12,
                                        fontFamily: 'Cinzel')),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 20),

          _label('URL DE LA IMAGEN'),
          const SizedBox(height: 6),
          _campo(_urlCtrl, hint: 'https://…'),
          const SizedBox(height: 20),

          _label('RAREZA'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in kRarezas)
                GestureDetector(
                  onTap: () => setState(() => _rareza = r.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _rareza == r.id
                          ? r.color.withOpacity(0.18)
                          : const Color(0xFF0A1220),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            _rareza == r.id ? r.color : const Color(0xFF304050),
                        width: _rareza == r.id ? 1.4 : 0.8,
                      ),
                    ),
                    child: Text(r.label.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontFamily: 'Cinzel',
                            fontWeight: _rareza == r.id
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _rareza == r.id
                                ? r.color
                                : const Color(0xFF607080))),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GestureDetector(
            onTap: _saving ? null : _guardar,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0E2A24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withOpacity(0.8), width: 1.5),
              ),
              child: Text(_saving ? 'GUARDANDO…' : 'GUARDAR SKIN',
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: _accent)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 9,
          letterSpacing: 2,
          color: Color(0xFF506070),
          fontFamily: 'Cinzel'));

  Widget _campo(TextEditingController c,
      {String hint = '', VoidCallback? onChanged}) {
    return TextField(
      controller: c,
      onChanged: onChanged == null ? null : (_) => onChanged(),
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
          borderSide: const BorderSide(color: _accent),
        ),
      ),
    );
  }
}
