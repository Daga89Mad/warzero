// lib/views/cartas_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart';
import '../services/warzero_api.dart';
import '../services/settings_controller.dart';
import '../widgets/card_detail_overlay.dart';
import 'card_skin_selector_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CartasScreen — Colección personal del jugador organizada por ejército.
// ─────────────────────────────────────────────────────────────────────────────

class CartasScreen extends StatefulWidget {
  const CartasScreen({super.key});

  @override
  State<CartasScreen> createState() => _CartasScreenState();
}

class _CartasScreenState extends State<CartasScreen>
    with SingleTickerProviderStateMixin {
  final _api = WarZeroApi();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  String? _error;

  Map<String, CartaModel> _catalogoGlobal = {};
  Map<String, _ColeccionEntry> _coleccion = {};
  Map<int, List<CartaModel>> _cartasPorEjercito = {};
  final Map<String, String> _skinImageCache = {};

  late TabController _tabController;
  List<EjercitoInfo> _ejercitosConCartas = [];

  _JugadorStats? _jugadorStats;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await _api.obtenerColeccion(_uid);

      if (res == null) {
        if (!mounted) return;
        _tabController = TabController(length: 1, vsync: this);
        setState(() {
          _catalogoGlobal = {};
          _coleccion = {};
          _cartasPorEjercito = {};
          _ejercitosConCartas = [];
          _jugadorStats = null;
          _loading = false;
        });
        return;
      }

      final catalogo = <String, CartaModel>{};
      final coleccion = <String, _ColeccionEntry>{};
      final skinCache = <String, String>{};

      for (final raw in (res['cartas'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final carta = CartaModel.fromMap(m);
        if (carta.id.isEmpty) continue;
        catalogo[carta.id] = carta;
        coleccion[carta.id] = _ColeccionEntry(
          cartaId: carta.id,
          cantidad: (m['cantidad'] as num?)?.toInt() ?? 1,
          skinSeleccionada: m['skinSeleccionada'] as String?,
          skinsDesbloqueadas:
              List<String>.from(m['skinsDesbloqueadas'] as List? ?? []),
          fechaObtenida: m['fechaObtenida'] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (m['fechaObtenida'] as num).toInt())
              : null,
        );
        final skinImg = m['skinImagen'] as String?;
        if (skinImg != null && skinImg.isNotEmpty)
          skinCache[carta.id] = skinImg;
      }

      for (final raw in (res['evoluciones'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final carta = CartaModel.fromMap(m);
        if (carta.id.isNotEmpty) catalogo[carta.id] = carta;
      }

      _JugadorStats? stats;
      final jug = res['jugador'];
      if (jug is Map) {
        final d = Map<String, dynamic>.from(jug);
        stats = _JugadorStats(
          alias: d['alias']?.toString() ?? 'Comandante',
          nivel: (d['nivel'] as num?)?.toInt() ?? 1,
          experiencia: (d['experiencia'] as num?)?.toInt() ?? 0,
          dinero: (d['dinero'] as num?)?.toInt() ?? 0,
          imagenPerfil: d['imagenPerfil']?.toString() ?? '',
        );
      }

      final agrupadas = <int, List<CartaModel>>{};
      for (final entry in coleccion.entries) {
        final carta = catalogo[entry.key];
        if (carta == null) continue;
        if (carta.esEvolucion) continue;
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
        _skinImageCache
          ..clear()
          ..addAll(skinCache);
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

  String _imagenEfectiva(CartaModel carta) =>
      _skinImageCache[carta.id] ?? carta.imagen;

  Future<CartaModel?> _resolveEvolucion(String idEvolucion) async =>
      _catalogoGlobal[idEvolucion];

  Future<void> _abrirDetalle(CartaModel carta) async {
    final imgUrl = _imagenEfectiva(carta);
    if (imgUrl.isNotEmpty) {
      try {
        await precacheImage(
          NetworkImage(imgUrl),
          context,
        ).timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
    }
    if (!mounted) return;
    final cartaConSkin = imgUrl.isNotEmpty && imgUrl != carta.imagen
        ? carta.copyWith(imagen: imgUrl)
        : carta;
    showCardDetail(
      context,
      cartaConSkin,
      resolveEvolucion: carta.puedeEvolucionar ? _resolveEvolucion : null,
      energiasDisponibles: null,
      onEvolucionar: null,
      onCambiarDiseno: () => _abrirSelectorSkin(carta),
    );
  }

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
    final war = context.war;
    if (_loading) return const _LoadingView();

    if (_error != null) {
      return Scaffold(
        backgroundColor: war.fondo,
        appBar: _appBar(),
        body: Center(
          child: Text(_error!,
              style: TextStyle(color: war.error, fontFamily: 'Cinzel')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: _appBar(),
      body: Column(
        children: [
          if (_jugadorStats != null) _JugadorStatsBar(stats: _jugadorStats!),
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
                    onCardTap: _abrirDetalle,
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  AppBar _appBar() {
    final war = context.war;
    return AppBar(
      backgroundColor: war.superficie,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MI COLECCIÓN',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                  letterSpacing: 2,
                  color: war.primario)),
          Text('${_coleccion.length} cartas desbloqueadas',
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 8, color: war.textoTenue)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final war = context.war;
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      indicatorColor: war.primario,
      indicatorWeight: 1.5,
      labelColor: war.primario,
      unselectedLabelColor: war.textoTenue,
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
                        color: war.borde.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_cartasPorEjercito[e.id]?.length ?? 0}',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 7,
                            color: war.textoTenue),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BARRA DE STATS DEL JUGADOR  (con la fórmula de nivel corregida)
// ─────────────────────────────────────────────────────────────
class _JugadorStatsBar extends StatelessWidget {
  final _JugadorStats stats;
  const _JugadorStatsBar({required this.stats});

  // XP total acumulada para ALCANZAR un nivel: 1000 * (2^(n-1) - 1).
  static int _xpParaAlcanzar(int n) => 1000 * ((1 << (n - 1)) - 1);

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final xpBase = _xpParaAlcanzar(stats.nivel);
    final xpTecho = _xpParaAlcanzar(stats.nivel + 1);
    final costeNivel = (xpTecho - xpBase).clamp(1, 1 << 30);
    final xpEnNivel = (stats.experiencia - xpBase).clamp(0, costeNivel);
    final progreso = (xpEnNivel / costeNivel).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: war.superficie,
        border: Border(bottom: BorderSide(color: war.borde.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: war.fondo,
              border:
                  Border.all(color: war.primario.withOpacity(0.5), width: 1.5),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('NV',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 6,
                          color: war.textoTenue,
                          letterSpacing: 1)),
                  Text('${stats.nivel}',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 14,
                          color: war.primario,
                          fontWeight: FontWeight.bold,
                          height: 1)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stats.alias.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        color: war.primario,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 4,
                    backgroundColor: war.borde.withOpacity(0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(war.primario),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$xpEnNivel / $costeNivel XP',
                  style: TextStyle(
                      fontFamily: 'Cinzel', fontSize: 7, color: war.textoTenue),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
// GRID 3 COLUMNAS
// ─────────────────────────────────────────────────────────────
class _CartasGrid extends StatefulWidget {
  final List<CartaModel> cartas;
  final Map<String, _ColeccionEntry> coleccion;
  final String Function(CartaModel) imagenEfectiva;
  final void Function(CartaModel) onCardTap;

  const _CartasGrid({
    required this.cartas,
    required this.coleccion,
    required this.imagenEfectiva,
    required this.onCardTap,
  });

  @override
  State<_CartasGrid> createState() => _CartasGridState();
}

class _CartasGridState extends State<_CartasGrid> {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: widget.cartas.length,
      itemBuilder: (_, i) {
        final carta = widget.cartas[i];
        final entry = widget.coleccion[carta.id];
        return _MiniCarta(
          carta: carta,
          imagen: widget.imagenEfectiva(carta),
          cantidad: entry?.cantidad ?? 1,
          tieneSkin: entry?.skinSeleccionada != null,
          onTap: () => widget.onCardTap(carta),
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
  final VoidCallback onTap;

  const _MiniCarta({
    required this.carta,
    required this.imagen,
    required this.cantidad,
    required this.tieneSkin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    // Morado de skin: semántico (se mantiene fijo).
    const skinPurple = Color(0xFFA040FF);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: tieneSkin
                ? skinPurple.withOpacity(0.7)
                : war.borde.withOpacity(0.5),
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
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: war.primario,
                          height: 1)),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        color: war.primario, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${carta.coste}',
                          style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                              color: war.fondo,
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
                    if (carta.puedeEvolucionar)
                      const Positioned(
                        top: 2,
                        right: 2,
                        child: Icon(Icons.arrow_forward_ios,
                            size: 8, color: Color(0xFFC060E0)),
                      ),
                    if (tieneSkin)
                      const Positioned(
                        bottom: 2,
                        right: 2,
                        child:
                            Icon(Icons.color_lens, size: 10, color: skinPurple),
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
                              style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 6,
                                  color: war.primario)),
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
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 6,
                    color: war.textoTenue,
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
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      color: war.fondo,
      child: Icon(Icons.shield_outlined, size: 28, color: war.borde),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// VISTAS DE ESTADO
// ─────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: war.primario),
            const SizedBox(height: 16),
            Text('CARGANDO COLECCIÓN…',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    letterSpacing: 2,
                    color: war.textoTenue)),
          ],
        ),
      ),
    );
  }
}

class _ColeccionVaciaView extends StatelessWidget {
  const _ColeccionVaciaView();
  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined, size: 48, color: war.borde),
          const SizedBox(height: 16),
          Text('Aún no tienes cartas.',
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 12, color: war.textoTenue)),
          const SizedBox(height: 8),
          Text('Juega partidas para ganar\ncartas y diseños nuevos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 9,
                  color: war.textoTenue.withOpacity(0.7),
                  height: 1.6)),
        ],
      ),
    );
  }
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
