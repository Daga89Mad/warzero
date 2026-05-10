// lib/views/seleccionar_carta_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart'; // kEjercitos

/// Pantalla que muestra todas las cartas de la colección global `Cartas`
/// con búsqueda por nombre y filtro por ejército.
///
/// Devuelve `pop(CartaModel)` cuando el usuario selecciona una carta,
/// o `pop(null)` si cancela.
class SeleccionarCartaScreen extends StatefulWidget {
  /// Si no es null, esta carta se excluye de la lista (para no elegirse a sí
  /// misma como evolución).
  final String? excluirId;

  const SeleccionarCartaScreen({super.key, this.excluirId});

  @override
  State<SeleccionarCartaScreen> createState() => _SeleccionarCartaScreenState();
}

class _SeleccionarCartaScreenState extends State<SeleccionarCartaScreen> {
  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<CartaModel> _todas = [];
  List<CartaModel> _filtradas = [];
  int? _ejercitoFiltro; // null = todos

  @override
  void initState() {
    super.initState();
    _loadCartas();
    _searchCtrl.addListener(_aplicarFiltros);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCartas() async {
    try {
      final snap = await _db.collection('Cartas').get();
      final cartas = snap.docs
          .map(CartaModel.fromFirestore)
          .where((c) => c.id != widget.excluirId)
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      if (!mounted) return;
      setState(() {
        _todas = cartas;
        _filtradas = cartas;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _aplicarFiltros() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtradas = _todas.where((c) {
        if (_ejercitoFiltro != null && c.ejercito != _ejercitoFiltro) {
          return false;
        }
        if (query.isNotEmpty && !c.nombre.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  void _setEjercito(int? id) {
    _ejercitoFiltro = id;
    _aplicarFiltros();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: Color(0xFFC8A860)),
        title: const Text(
          'ELEGIR CARTA',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Cinzel',
            letterSpacing: 3,
            color: Color(0xFFC8A860),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Búsqueda ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(
                color: Color(0xFFE0D8C0),
                fontFamily: 'Cinzel',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre…',
                hintStyle: const TextStyle(
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                ),
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF506070), size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                        },
                        child: const Icon(Icons.close,
                            color: Color(0xFF506070), size: 18),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0A1220),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: const Color(0xFFC8A860).withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: const Color(0xFFC8A860).withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFC8A860), width: 1),
                ),
              ),
            ),
          ),

          // ── Filtros ejército ───────────────────────────────
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChip(
                  label: 'TODOS',
                  selected: _ejercitoFiltro == null,
                  onTap: () => _setEjercito(null),
                ),
                ...kEjercitos.map((e) => _FilterChip(
                      label: '${e.icono} ${e.nombre.toUpperCase()}',
                      selected: _ejercitoFiltro == e.id,
                      onTap: () => _setEjercito(e.id),
                    )),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Lista ─────────────────────────────────────────
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFC8A860)),
              ),
            )
          else if (_filtradas.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'SIN RESULTADOS',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF506070),
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _filtradas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final c = _filtradas[i];
                  final ej = kEjercitos.firstWhere(
                    (e) => e.id == c.ejercito,
                    orElse: () => kEjercitos.first,
                  );
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(c),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1220),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFC8A860).withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Mini imagen
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: const Color(0xFF050C14),
                              border: Border.all(
                                color: const Color(0xFFC8A860).withOpacity(0.3),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: c.imagen.isNotEmpty
                                  ? Image.network(c.imagen,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.shield_outlined,
                                          size: 18,
                                          color: Color(0xFF2A3A4A)))
                                  : const Icon(Icons.shield_outlined,
                                      size: 18, color: Color(0xFF2A3A4A)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.nombre,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFC8A860),
                                    fontFamily: 'Cinzel',
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${ej.icono} ${ej.nombre}  ·  ⚔${c.fuerza}  🛡${c.defensa}  ↗${c.movimiento}',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Color(0xFF506070),
                                    fontFamily: 'Cinzel',
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: Color(0xFF506070)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

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
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFC8A860).withOpacity(0.18)
                : const Color(0xFF0A1220),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFC8A860)
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
                  selected ? const Color(0xFFC8A860) : const Color(0xFF506070),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
