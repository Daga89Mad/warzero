// lib/views/edicion_cartas_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart'; // kEjercitos
import 'crear_carta_screen.dart';

class EdicionCartasScreen extends StatefulWidget {
  const EdicionCartasScreen({super.key});

  @override
  State<EdicionCartasScreen> createState() => _EdicionCartasScreenState();
}

class _EdicionCartasScreenState extends State<EdicionCartasScreen> {
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
    setState(() => _loading = true);
    try {
      final snap = await _db.collection('Cartas').get();
      final cartas = snap.docs.map(CartaModel.fromFirestore).toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      if (!mounted) return;
      setState(() {
        _todas = cartas;
        _loading = false;
      });
      _aplicarFiltros();
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

  Future<void> _abrirCrear() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CrearCartaScreen()),
    );
    if (result == true) _loadCartas(); // Recargar tras crear
  }

  Future<void> _abrirEditar(CartaModel carta) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CrearCartaScreen(cartaEditar: carta)),
    );
    if (result == true) _loadCartas(); // Recargar tras editar
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: Color(0xFFC8A860)),
        title: const Text(
          'EDICIÓN DE CARTAS',
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
          // ── Botón NUEVA CARTA ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: GestureDetector(
              onTap: _abrirCrear,
              child: Container(
                width: double.infinity,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFF4ABB58).withOpacity(0.20),
                    const Color(0xFF4ABB58).withOpacity(0.06),
                  ]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4ABB58).withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 16, color: Color(0xFF4ABB58)),
                    SizedBox(width: 8),
                    Text(
                      'NUEVA CARTA',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                        color: Color(0xFF4ABB58),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

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
                        onTap: () => _searchCtrl.clear(),
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

          const SizedBox(height: 4),

          // ── Contador ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filtradas.length} carta${_filtradas.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

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
                  return _CartaTile(
                    carta: c,
                    onTap: () => _abrirEditar(c),
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
// TILE DE CARTA
// ─────────────────────────────────────────────────────────────
class _CartaTile extends StatelessWidget {
  final CartaModel carta;
  final VoidCallback onTap;

  const _CartaTile({required this.carta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ej = kEjercitos.firstWhere(
      (e) => e.id == carta.ejercito,
      orElse: () => kEjercitos.first,
    );
    final condColor = Color(carta.condicion.colorValue);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFC8A860).withOpacity(0.15)),
        ),
        child: Row(
          children: [
            // Mini imagen
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF050C14),
                border: Border.all(
                    color: const Color(0xFFC8A860).withOpacity(0.25)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: carta.imagen.isNotEmpty
                    ? Image.network(carta.imagen,
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
                    carta.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFC8A860),
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${ej.icono} ${ej.nombre}',
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '⚔${carta.fuerza}  🛡${carta.defensa}  ↗${carta.movimientoEfectivo}',
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel',
                        ),
                      ),
                    ],
                  ),
                  if (carta.condicion != CondicionCarta.basica) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: condColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: condColor.withOpacity(0.30), width: 0.5),
                      ),
                      child: Text(
                        '${carta.condicion.icon} ${carta.condicion.label}',
                        style: TextStyle(
                          fontSize: 7,
                          color: condColor,
                          fontFamily: 'Cinzel',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF506070)),
          ],
        ),
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
