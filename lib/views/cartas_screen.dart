// lib/views/cartas_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart';
import 'card_skin_selector_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CartasScreen — Colección personal del jugador organizada por ejército.
//
// Firestore leído:
//   Cartas/{cartaId}                         → catálogo global (read-only)
//   Jugadores/{uid}                          → alias, nivel, exp, dinero
//   Jugadores/{uid}/Coleccion/{cartaId}      → cartas que el jugador posee
//   Skins/{skinId}                           → URL de skins (carga lazy)
// ─────────────────────────────────────────────────────────────────────────────

class CartasScreen extends StatefulWidget {
  const CartasScreen({super.key});

  @override
  State<CartasScreen> createState() => _CartasScreenState();
}

class _CartasScreenState extends State<CartasScreen>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  String? _error;

  Map<String, CartaModel> _catalogoGlobal = {};
  Map<String, _ColeccionEntry> _coleccion = {};
  Map<int, List<CartaModel>> _cartasPorEjercito = {};
  final Map<String, String> _skinImageCache = {};

  late TabController _tabController;
  List<EjercitoInfo> _ejercitosConCartas = [];

  CartaModel? _detalleCarta;
  _JugadorStats? _jugadorStats;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _db.collection('Cartas').get(),
        _db.collection('Jugadores').doc(_uid).collection('Coleccion').get(),
        _db.collection('Jugadores').doc(_uid).get(),
      ]);

      final cartasSnap = results[0] as QuerySnapshot;
      final coleccionSnap = results[1] as QuerySnapshot;
      final jugadorSnap = results[2] as DocumentSnapshot;

      // Catálogo global
      final catalogo = <String, CartaModel>{
        for (final doc in cartasSnap.docs) doc.id: CartaModel.fromFirestore(doc)
      };

      // Subcolección Coleccion
      final coleccion = <String, _ColeccionEntry>{};
      for (final doc in coleccionSnap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        coleccion[doc.id] = _ColeccionEntry(
          cartaId: doc.id,
          cantidad: (d['cantidad'] as num?)?.toInt() ?? 1,
          skinSeleccionada: d['skinSeleccionada'] as String?,
          skinsDesbloqueadas:
              List<String>.from(d['skinsDesbloqueadas'] as List? ?? []),
          fechaObtenida: (d['fechaObtenida'] as Timestamp?)?.toDate(),
        );
      }

      // Stats del jugador
      _JugadorStats? stats;
      if (jugadorSnap.exists) {
        final d = jugadorSnap.data() as Map<String, dynamic>;
        stats = _JugadorStats(
          alias: d['alias']?.toString() ?? 'Comandante',
          nivel: (d['nivel'] as num?)?.toInt() ?? 1,
          experiencia: (d['experiencia'] as num?)?.toInt() ?? 0,
          dinero: (d['dinero'] as num?)?.toInt() ?? 0,
          imagenPerfil: d['imagenPerfil']?.toString() ?? '',
        );
      }

      // Agrupar por ejército (solo cartas que posee el jugador)
      final agrupadas = <int, List<CartaModel>>{};
      for (final entry in coleccion.entries) {
        final carta = catalogo[entry.key];
        if (carta == null) continue;
        agrupadas.putIfAbsent(carta.ejercito, () => []).add(carta);
      }
      agrupadas.forEach((_, list) {
        list.sort((a, b) => a.nombre.compareTo(b.nombre));
      });

      final ejercitosConCartas =
          kEjercitos.where((e) => agrupadas.containsKey(e.id)).toList();

      if (!mounted) return;

      _tabController = TabController(
        length: ejercitosConCartas.isEmpty ? 1 : ejercitosConCartas.length,
        vsync: this,
      );

      setState(() {
        _catalogoGlobal = catalogo;
        _coleccion = coleccion;
        _cartasPorEjercito = agrupadas;
        _ejercitosConCartas = ejercitosConCartas;
        _jugadorStats = stats;
        _loading = false;
      });

      _resolverImagenesSkins(coleccion);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _resolverImagenesSkins(
      Map<String, _ColeccionEntry> coleccion) async {
    for (final entry in coleccion.entries) {
      final skinId = entry.value.skinSeleccionada;
      if (skinId == null || skinId.isEmpty) continue;
      try {
        final doc = await _db.collection('Skins').doc(skinId).get();
        if (!doc.exists || !mounted) continue;
        final url = (doc.data() as Map<String, dynamic>)['imagen'] as String?;
        if (url != null && url.isNotEmpty && mounted) {
          setState(() => _skinImageCache[entry.key] = url);
        }
      } catch (_) {}
    }
  }

  String _imagenEfectiva(CartaModel carta) =>
      _skinImageCache[carta.id] ?? carta.imagen;

  Future<void> _abrirSelectorSkin(CartaModel carta) async {
    final entry = _coleccion[carta.id];
    final result =
        await Navigator.of(context).push<SkinSelectorResult>(MaterialPageRoute(
      builder: (_) => CardSkinSelectorScreen(
        carta: carta,
        uid: _uid,
        skinActualId: entry?.skinSeleccionada,
        skinsDesbloqueadas: entry?.skinsDesbloqueadas ?? [],
      ),
    ));
    if (result == null || !mounted) return;

    setState(() {
      final prev = _coleccion[carta.id] ?? _ColeccionEntry(cartaId: carta.id);
      _coleccion[carta.id] = _ColeccionEntry(
        cartaId: carta.id,
        cantidad: prev.cantidad,
        skinSeleccionada: result.skinId,
        skinsDesbloqueadas: prev.skinsDesbloqueadas,
        fechaObtenida: prev.fechaObtenida,
      );
      if (result.skinId == null) {
        _skinImageCache.remove(carta.id);
      } else if (result.imagen != null) {
        _skinImageCache[carta.id] = result.imagen!;
      }
    });
  }

  @override
  void dispose() {
    if (!_loading && _ejercitosConCartas.isNotEmpty) _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingView();

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF060E1A),
        appBar: _appBar(),
        body: Center(
          child: Text(_error!,
              style: const TextStyle(
                  color: Color(0xFFC04040), fontFamily: 'Cinzel')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: _appBar(),
      body: Stack(
        children: [
          Column(
            children: [
              if (_jugadorStats != null)
                _JugadorStatsBar(stats: _jugadorStats!),
              if (_ejercitosConCartas.isEmpty)
                const Expanded(child: _ColeccionVaciaView())
              else ...[
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: _ejercitosConCartas.map((e) {
                      final cartas = _cartasPorEjercito[e.id] ?? [];
                      return _CartasGrid(
                        cartas: cartas,
                        coleccion: _coleccion,
                        imagenEfectiva: _imagenEfectiva,
                        onLongPress: (c) => setState(() => _detalleCarta = c),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),

          // Overlay detalle
          if (_detalleCarta != null) ...[
            GestureDetector(
              onTap: () => setState(() => _detalleCarta = null),
              child: Container(color: Colors.black87),
            ),
            Center(
              child: _CartaDetalleOverlay(
                carta: _detalleCarta!,
                imagen: _imagenEfectiva(_detalleCarta!),
                cantidad: _coleccion[_detalleCarta!.id]?.cantidad ?? 1,
                tieneSkinActiva:
                    _coleccion[_detalleCarta!.id]?.skinSeleccionada != null,
                onClose: () => setState(() => _detalleCarta = null),
                onCambiarDiseno: () {
                  final carta = _detalleCarta!;
                  setState(() => _detalleCarta = null);
                  _abrirSelectorSkin(carta);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  AppBar _appBar() => AppBar(
        backgroundColor: const Color(0xFF060E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              size: 16, color: Color(0xFFC8A860)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MI COLECCIÓN',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    letterSpacing: 2,
                    color: Color(0xFFC8A860))),
            Text('${_coleccion.length} cartas desbloqueadas',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF506070))),
          ],
        ),
      );

  Widget _buildTabBar() => TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: const Color(0xFFC8A860),
        indicatorWeight: 1.5,
        labelColor: const Color(0xFFC8A860),
        unselectedLabelColor: const Color(0xFF506070),
        labelStyle: const TextStyle(
            fontFamily: 'Cinzel', fontSize: 9, letterSpacing: 1.5),
        tabs: _ejercitosConCartas
            .map((e) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.icono, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 5),
                      Text(e.nombre.toUpperCase()),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2A3A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_cartasPorEjercito[e.id]?.length ?? 0}',
                          style: const TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 7,
                              color: Color(0xFF8A9AAA)),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────
// BARRA DE STATS DEL JUGADOR
// ─────────────────────────────────────────────────────────────
class _JugadorStatsBar extends StatelessWidget {
  final _JugadorStats stats;
  const _JugadorStatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final xpSiguienteNivel = stats.nivel * 1000;
    final progreso = ((stats.experiencia % xpSiguienteNivel) / xpSiguienteNivel)
        .clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF080F1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1A2A3A))),
      ),
      child: Row(
        children: [
          // Avatar circular con nivel
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A1525),
              border: Border.all(
                  color: const Color(0xFFC8A860).withOpacity(0.5), width: 1.5),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('NV',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 6,
                          color: Color(0xFF506070),
                          letterSpacing: 1)),
                  Text('${stats.nivel}',
                      style: const TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 14,
                          color: Color(0xFFC8A860),
                          fontWeight: FontWeight.bold,
                          height: 1)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Alias + barra XP
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stats.alias.toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        color: Color(0xFFC8A860),
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF1A2A3A),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFC8A860)),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${stats.experiencia % xpSiguienteNivel} / $xpSiguienteNivel XP',
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 7,
                      color: Color(0xFF506070)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Dinero
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('💰', style: TextStyle(fontSize: 18)),
              Text(
                '${stats.dinero}',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    color: Color(0xFFD4A800),
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GRID 4 COLUMNAS
// ─────────────────────────────────────────────────────────────
class _CartasGrid extends StatelessWidget {
  final List<CartaModel> cartas;
  final Map<String, _ColeccionEntry> coleccion;
  final String Function(CartaModel) imagenEfectiva;
  final void Function(CartaModel) onLongPress;

  const _CartasGrid({
    required this.cartas,
    required this.coleccion,
    required this.imagenEfectiva,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.60,
      ),
      itemCount: cartas.length,
      itemBuilder: (_, i) {
        final carta = cartas[i];
        final entry = coleccion[carta.id];
        return _MiniCarta(
          carta: carta,
          imagen: imagenEfectiva(carta),
          cantidad: entry?.cantidad ?? 1,
          tieneSkin: entry?.skinSeleccionada != null,
          onLongPress: () => onLongPress(carta),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MINIATURA
// ─────────────────────────────────────────────────────────────
class _MiniCarta extends StatelessWidget {
  final CartaModel carta;
  final String imagen;
  final int cantidad;
  final bool tieneSkin;
  final VoidCallback onLongPress;

  const _MiniCarta({
    required this.carta,
    required this.imagen,
    required this.cantidad,
    required this.tieneSkin,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: tieneSkin
                ? const Color(0xFFA040FF).withOpacity(0.7)
                : const Color(0xFF78591E).withOpacity(0.5),
            width: tieneSkin ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${carta.fuerza}',
                      style: const TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE0C060),
                          height: 1)),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                        color: Color(0xFFB08040), shape: BoxShape.circle),
                    child: Center(
                      child: Text('${carta.coste}',
                          style: const TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF040C14),
                              fontFamily: 'Cinzel')),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: imagen.isNotEmpty
                          ? Image.network(imagen,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _PlaceholderArt())
                          : const _PlaceholderArt(),
                    ),
                    if (tieneSkin)
                      const Positioned(
                        bottom: 2,
                        right: 2,
                        child: Icon(Icons.color_lens,
                            size: 10, color: Color(0xFFA040FF)),
                      ),
                    if (cantidad > 1)
                      Positioned(
                        bottom: 2,
                        left: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('x$cantidad',
                              style: const TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 6,
                                  color: Color(0xFFC8A860))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 3, 3, 4),
              child: Text(
                carta.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 6,
                    color: Color(0xFF8A9AAA),
                    height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderArt extends StatelessWidget {
  const _PlaceholderArt();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0A1525),
        child: const Icon(Icons.shield_outlined,
            size: 28, color: Color(0xFF2A3A4A)),
      );
}

// ─────────────────────────────────────────────────────────────
// OVERLAY DETALLE
// ─────────────────────────────────────────────────────────────
class _CartaDetalleOverlay extends StatelessWidget {
  final CartaModel carta;
  final String imagen;
  final int cantidad;
  final bool tieneSkinActiva;
  final VoidCallback onClose;
  final VoidCallback onCambiarDiseno;

  const _CartaDetalleOverlay({
    required this.carta,
    required this.imagen,
    required this.cantidad,
    required this.tieneSkinActiva,
    required this.onClose,
    required this.onCambiarDiseno,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.82,
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1525),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFC8A860).withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFC8A860).withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 2)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon:
                    const Icon(Icons.close, size: 18, color: Color(0xFF506070)),
                onPressed: onClose,
              ),
            ),

            // Imagen
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  width: 150,
                  height: 200,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: tieneSkinActiva
                            ? const Color(0xFFA040FF).withOpacity(0.7)
                            : const Color(0xFFE0C060).withOpacity(0.5),
                        width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: imagen.isNotEmpty
                        ? Image.network(imagen,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _PlaceholderArt())
                        : const _PlaceholderArt(),
                  ),
                ),
                if (tieneSkinActiva)
                  const Positioned(
                    top: 6,
                    right: 26,
                    child: Icon(Icons.color_lens,
                        size: 16, color: Color(0xFFA040FF)),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(carta.nombre.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 13,
                      letterSpacing: 1.5,
                      color: Color(0xFFC8A860),
                      fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 4),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                    '${carta.tipoIcon} ${carta.tipoLabel.toUpperCase()}  ·  EJ.${carta.ejercito}',
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        color: Color(0xFF506070),
                        letterSpacing: 1)),
                if (cantidad > 1) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2A3A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('x$cantidad',
                        style: const TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            color: Color(0xFFC8A860))),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 14),

            // Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatChip(
                      '⚔', '${carta.fuerza}', 'FZA', const Color(0xFFE08040)),
                  _StatChip(
                      '🛡', '${carta.defensa}', 'DEF', const Color(0xFF4090D0)),
                  _StatChip(
                      '⚡', '${carta.coste}', 'CST', const Color(0xFFD4A800)),
                  _StatChip('↗', '${carta.movimiento}', 'MOV',
                      const Color(0xFF4ABB58)),
                ],
              ),
            ),

            if (carta.descripcion.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  carta.descripcion,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 8,
                      color: Color(0xFF506070),
                      height: 1.6),
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Botón CAMBIAR DISEÑO
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GestureDetector(
                onTap: onCambiarDiseno,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFFA040FF).withOpacity(0.25),
                      const Color(0xFFA040FF).withOpacity(0.08),
                    ]),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFA040FF).withOpacity(0.6),
                        width: 1),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.color_lens_outlined,
                          size: 16, color: Color(0xFFA040FF)),
                      SizedBox(width: 8),
                      Text('CAMBIAR DISEÑO',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 11,
                              letterSpacing: 2,
                              color: Color(0xFFA040FF),
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  final Color color;
  const _StatChip(this.icon, this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 6,
                  color: Color(0xFF506070),
                  letterSpacing: 1)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────
// VISTAS DE ESTADO
// ─────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF060E1A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFC8A860)),
              SizedBox(height: 16),
              Text('CARGANDO COLECCIÓN…',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      letterSpacing: 2,
                      color: Color(0xFF506070))),
            ],
          ),
        ),
      );
}

class _ColeccionVaciaView extends StatelessWidget {
  const _ColeccionVaciaView();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined, size: 48, color: Color(0xFF2A3A4A)),
            SizedBox(height: 16),
            Text('Aún no tienes cartas.',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    color: Color(0xFF506070))),
            SizedBox(height: 8),
            Text('Juega partidas para ganar\ncartas y diseños nuevos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    color: Color(0xFF3A4A5A),
                    height: 1.6)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// MODELOS LOCALES
// ─────────────────────────────────────────────────────────────
class _ColeccionEntry {
  final String cartaId;
  final int cantidad;
  final String? skinSeleccionada;
  final List<String> skinsDesbloqueadas;
  final DateTime? fechaObtenida;

  const _ColeccionEntry({
    required this.cartaId,
    this.cantidad = 1,
    this.skinSeleccionada,
    this.skinsDesbloqueadas = const [],
    this.fechaObtenida,
  });
}

class _JugadorStats {
  final String alias;
  final int nivel;
  final int experiencia;
  final int dinero;
  final String imagenPerfil;

  const _JugadorStats({
    required this.alias,
    required this.nivel,
    required this.experiencia,
    required this.dinero,
    required this.imagenPerfil,
  });
}
