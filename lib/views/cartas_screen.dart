// lib/views/cartas_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart';
import '../services/warzero_api.dart';
import '../services/settings_controller.dart';
import '../widgets/card_detail_overlay.dart';
import 'card_skin_selector_screen.dart';
import 'centro_mando_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CartasScreen — Colección personal del jugador organizada por ejército.
// ─────────────────────────────────────────────────────────────────────────────

class CartasScreen extends StatefulWidget {
  const CartasScreen({super.key});

  @override
  State<CartasScreen> createState() => _CartasScreenState();
}

class _CartasScreenState extends State<CartasScreen>
    with TickerProviderStateMixin {
  final _api = WarZeroApi();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  String? _error;

  Map<String, CartaModel> _catalogoGlobal = {};
  Map<String, _ColeccionEntry> _coleccion = {};
  Map<int, List<CartaModel>> _cartasPorEjercito = {};
  final Map<String, String> _skinImageCache = {};
  final Map<String, String> _skinRarezaCache = {};

  // Coleccionismo:
  //   _porcentajes        → ejercitoId → {conseguidas, total, porcentaje}
  //   _numeradoPorEjercito → ejercitoId → slots numerados (poseídos o no)
  Map<int, _EjercitoPct> _porcentajes = {};
  Map<int, List<_SlotNumerado>> _numeradoPorEjercito = {};

  late TabController _tabController;
  bool _hasTabController = false;

  /// Crea (o recrea) el TabController liberando el anterior si existía. Evita el
  /// error de "multiple tickers" al recargar la colección (p. ej. al volver de
  /// la pantalla de sobres).
  void _setTabController(int length) {
    if (_hasTabController) _tabController.dispose();
    _tabController = TabController(length: length, vsync: this);
    _hasTabController = true;
  }

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
        _setTabController(1);
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
      final rarezaCache = <String, String>{};

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
          skinsExtraIds: List<String>.from(m['skinsExtraIds'] as List? ?? []),
          fechaObtenida: m['fechaObtenida'] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (m['fechaObtenida'] as num).toInt())
              : null,
        );
        final skinImg = m['skinImagen'] as String?;
        if (skinImg != null && skinImg.isNotEmpty)
          skinCache[carta.id] = skinImg;
        final skinRar = m['skinRareza'] as String?;
        if (skinRar != null && skinRar.isNotEmpty)
          rarezaCache[carta.id] = skinRar;
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

      // Porcentajes de completado por ejército.
      final porcentajes = <int, _EjercitoPct>{};
      for (final raw in (res['porcentajes'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final ej = (m['ejercito'] as num?)?.toInt() ?? 0;
        if (ej == 0) continue;
        porcentajes[ej] = _EjercitoPct(
          conseguidas: (m['conseguidas'] as num?)?.toInt() ?? 0,
          total: (m['total'] as num?)?.toInt() ?? 0,
          porcentaje: (m['porcentaje'] as num?)?.toInt() ?? 0,
        );
      }

      // Catálogo NUMERADO por ejército (para pintar huecos bloqueados).
      final numerado = <int, List<_SlotNumerado>>{};
      for (final raw in (res['catalogoNumerado'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final ej = (m['ejercito'] as num?)?.toInt() ?? 0;
        if (ej == 0) continue;
        numerado.putIfAbsent(ej, () => []).add(_SlotNumerado(
              cartaId: m['cartaId']?.toString() ?? '',
              numero: (m['numero'] as num?)?.toInt() ?? 0,
              poseida: m['poseida'] == true,
              idEvolucion: m['idEvolucion']?.toString() ?? '',
            ));
      }
      numerado.forEach((_, list) {
        list.sort((a, b) => a.numero.compareTo(b.numero));
      });

      // Tabs = ejércitos con cartas poseídas O con catálogo numerado (para que
      // se muestren las bloqueadas aunque aún no tengas ninguna de ese ejército).
      final idsConContenido = <int>{
        ...agrupadas.keys,
        ...numerado.keys,
      };
      final ejercitosConCartas =
          kEjercitos.where((e) => idsConContenido.contains(e.id)).toList();

      if (!mounted) return;

      _setTabController(
          ejercitosConCartas.isEmpty ? 1 : ejercitosConCartas.length);

      setState(() {
        _catalogoGlobal = catalogo;
        _coleccion = coleccion;
        _cartasPorEjercito = agrupadas;
        _ejercitosConCartas = ejercitosConCartas;
        _porcentajes = porcentajes;
        _numeradoPorEjercito = numerado;
        _jugadorStats = stats;
        _skinImageCache
          ..clear()
          ..addAll(skinCache);
        _skinRarezaCache
          ..clear()
          ..addAll(rarezaCache);
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

  /// True si la skin actualmente aplicada a la carta es de rareza legendaria.
  bool _esLegendaria(CartaModel carta) =>
      (_skinRarezaCache[carta.id] ?? '') == 'legendaria';

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
      esLegendaria: _esLegendaria(carta),
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
        skinsExtraIds: prev.skinsExtraIds,
        fechaObtenida: prev.fechaObtenida,
      );
      if (result.skinId == null) {
        _skinImageCache.remove(carta.id);
        _skinRarezaCache.remove(carta.id);
      } else {
        if (result.imagen != null) {
          _skinImageCache[carta.id] = result.imagen!;
        }
        if (result.rareza != null && result.rareza!.isNotEmpty) {
          _skinRarezaCache[carta.id] = result.rareza!;
        } else {
          _skinRarezaCache.remove(carta.id);
        }
      }
    });
  }

  @override
  void dispose() {
    if (_hasTabController) _tabController.dispose();
    super.dispose();
  }

  /// Construye la lista ordenada de celdas para un ejército: cada carta
  /// numerada aparece en su posición (poseída → carta real; no poseída →
  /// bloqueada) y, JUSTO DETRÁS, su evolución si la tiene. Las evoluciones se
  /// muestran como celda propia SIN duplicar: si dos básicas evolucionan a la
  /// misma, o si ya aparece con su propio número, solo se pinta una vez.
  ///
  /// La evolución se revela (con imagen/datos) solo cuando su base es poseída
  /// —su definición llega en `evoluciones` y por tanto está en el catálogo—; en
  /// caso contrario se pinta como celda de evolución BLOQUEADA (igual que una
  /// básica bloqueada, sin revelar nada).
  List<_GridItem> _itemsDeEjercito(int ejercitoId) {
    final items = <_GridItem>[];
    final usados = <String>{};

    // Cartas que YA tienen su propia celda (con su número): huecos numerados
    // (poseídos o bloqueados) + poseídas sin numerar. Una evolución que sea una
    // de estas NO se repite como preview.
    final propios = <String>{
      for (final slot in (_numeradoPorEjercito[ejercitoId] ?? const []))
        slot.cartaId,
      for (final carta in (_cartasPorEjercito[ejercitoId] ?? const []))
        if (carta.numero == 0) carta.id,
    };

    // Evoluciones ya colocadas (reveladas o bloqueadas): evita duplicar cuando
    // varias básicas comparten la misma evolución.
    final evosPuestas = <String>{};

    void agregarEvolucion(String idEvo) {
      if (idEvo.isEmpty) return;
      if (propios.contains(idEvo)) return; // ya aparece con su propio número
      if (!evosPuestas.add(idEvo)) return; // ya la puso otra básica
      final evo = _catalogoGlobal[idEvo];
      items.add(
          evo != null ? _GridItem.evolucion(evo) : _GridItem.evolucionLocked());
    }

    for (final slot in (_numeradoPorEjercito[ejercitoId] ?? const [])) {
      final carta = _catalogoGlobal[slot.cartaId];
      final poseida =
          slot.poseida && carta != null && _coleccion.containsKey(slot.cartaId);
      if (poseida) {
        items.add(_GridItem.owned(carta!, slot.numero));
        usados.add(slot.cartaId);
        agregarEvolucion(carta.idEvolucion);
      } else {
        items.add(_GridItem.locked(slot.numero));
        // Aunque la base esté bloqueada, si el catálogo indica que tiene
        // evolución la mostramos como celda de evolución bloqueada a su lado.
        agregarEvolucion(slot.idEvolucion);
      }
    }

    // Poseídas sin número (no vienen en el catálogo numerado).
    for (final carta in (_cartasPorEjercito[ejercitoId] ?? const [])) {
      if (usados.contains(carta.id) || carta.numero > 0) continue;
      items.add(_GridItem.owned(carta, 0));
      agregarEvolucion(carta.idEvolucion);
    }
    return items;
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
                  return _CartasGrid(
                    items: _itemsDeEjercito(e.id),
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
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Sobres',
            icon: Icon(Icons.card_giftcard, size: 20, color: war.primario),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CentroMandoScreen(),
              ));
              if (mounted) _loadData(); // refresca colección/monedas al volver
            },
          ),
        ),
      ],
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
                        color: war.primario.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: war.primario.withOpacity(0.4), width: 0.6),
                      ),
                      child: Text(
                        '${_porcentajes[e.id]?.porcentaje ?? 0}%',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            color: war.primario),
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
class _CartasGrid extends StatelessWidget {
  final List<_GridItem> items;
  final Map<String, _ColeccionEntry> coleccion;
  final String Function(CartaModel) imagenEfectiva;
  final void Function(CartaModel) onCardTap;

  const _CartasGrid({
    required this.items,
    required this.coleccion,
    required this.imagenEfectiva,
    required this.onCardTap,
  });

  List<bool> _flagsDe(CartaModel carta) {
    final entry = coleccion[carta.id];
    final extraIds = entry?.skinsExtraIds ?? const <String>[];
    final unlocked = (entry?.skinsDesbloqueadas ?? const <String>[]).toSet();
    // nº 1 = diseño por defecto (poseído al tener la carta); 2..X = extra.
    return <bool>[true, for (final id in extraIds) unlocked.contains(id)];
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _ColeccionVaciaView();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.54,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.bloqueada) {
          return _LockedCarta(
              numero: item.numero, esEvolucion: item.esEvolucion);
        }

        final carta = item.carta!;
        final entry = coleccion[carta.id];
        // Las evoluciones de preview se muestran sin tira de skins.
        final flags = item.esEvolucion ? null : _flagsDe(carta);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MiniCarta(
                carta: carta,
                imagen: imagenEfectiva(carta),
                cantidad: entry?.cantidad ?? 1,
                tieneSkin: entry?.skinSeleccionada != null,
                onTap: () => onCardTap(carta),
              ),
            ),
            const SizedBox(height: 4),
            flags != null
                ? _SkinNumeros(flags: flags)
                : const SizedBox(height: 13),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TIRA DE NÚMEROS DE SKIN (debajo de cada carta)
//   nº 1 = diseño por defecto; 2..X = skins extra. Resaltado = desbloqueada.
// ─────────────────────────────────────────────────────────────
class _SkinNumeros extends StatelessWidget {
  final List<bool> flags;
  const _SkinNumeros({required this.flags});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const skinPurple = Color(0xFFA040FF);
    if (flags.isEmpty) return const SizedBox(height: 14);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < flags.length; i++)
          Container(
            width: 13,
            height: 13,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: flags[i] ? skinPurple.withOpacity(0.9) : war.superficie,
              shape: BoxShape.circle,
              border: Border.all(
                color: flags[i] ? skinPurple : war.borde.withOpacity(0.6),
                width: 0.8,
              ),
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 6.5,
                fontWeight: FontWeight.bold,
                color: flags[i] ? Colors.white : war.textoTenue,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARTA BLOQUEADA (no poseída): sin imagen ni información
// ─────────────────────────────────────────────────────────────
class _LockedCarta extends StatelessWidget {
  final int numero;

  /// True si esta celda representa una EVOLUCIÓN bloqueada (aún no revelada).
  /// Se pinta con el acento morado de evolución y sin número de colección.
  final bool esEvolucion;

  const _LockedCarta({required this.numero, this.esEvolucion = false});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const evoPurple = Color(0xFFC060E0);
    final acento = esEvolucion ? evoPurple : war.borde;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: war.fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: esEvolucion
              ? evoPurple.withOpacity(0.4)
              : war.borde.withOpacity(0.4),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(esEvolucion ? Icons.auto_awesome : Icons.lock_outline,
              size: 26, color: acento),
          const SizedBox(height: 8),
          Text(
            esEvolucion ? 'EVOLUCIÓN' : 'Nº $numero',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: esEvolucion ? 8 : 9,
                letterSpacing: 1,
                fontWeight: esEvolucion ? FontWeight.bold : FontWeight.normal,
                color: esEvolucion ? evoPurple : war.textoTenue),
          ),
          const SizedBox(height: 2),
          Text(
            'BLOQUEADA',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 6,
                letterSpacing: 1.5,
                color: war.textoTenue.withOpacity(0.6)),
          ),
        ],
      ),
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

  /// Ids (en orden) de las skins EXTRA existentes para esta carta. Sirve para
  /// pintar los números 1..X bajo la carta y saber cuáles están desbloqueadas.
  final List<String> skinsExtraIds;
  final DateTime? fechaObtenida;

  const _ColeccionEntry({
    required this.cartaId,
    this.cantidad = 1,
    this.skinSeleccionada,
    this.skinsDesbloqueadas = const [],
    this.skinsExtraIds = const [],
    this.fechaObtenida,
  });
}

/// Un slot del catálogo numerado de un ejército (poseído o bloqueado).
class _SlotNumerado {
  final String cartaId;
  final int numero;
  final bool poseida;

  /// Id de la evolución de esta carta (vacío si no tiene). Permite pintar una
  /// celda de "evolución bloqueada" junto a las básicas que aún no posees.
  final String idEvolucion;

  const _SlotNumerado({
    required this.cartaId,
    required this.numero,
    required this.poseida,
    this.idEvolucion = '',
  });
}

/// Porcentaje de completado de un ejército.
class _EjercitoPct {
  final int conseguidas;
  final int total;
  final int porcentaje;
  const _EjercitoPct({
    required this.conseguidas,
    required this.total,
    required this.porcentaje,
  });
}

/// Celda de la rejilla: carta poseída, hueco bloqueado o evolución (preview).
class _GridItem {
  final CartaModel? carta; // null → bloqueada
  final int numero;

  /// True si es la evolución de otra carta (se muestra como celda propia, sin
  /// tira de skins).
  final bool esEvolucion;

  const _GridItem._(this.carta, this.numero, this.esEvolucion);
  factory _GridItem.owned(CartaModel c, int numero) =>
      _GridItem._(c, numero, false);
  factory _GridItem.locked(int numero) => _GridItem._(null, numero, false);
  factory _GridItem.evolucion(CartaModel c) => _GridItem._(c, 0, true);

  /// Evolución de una base bloqueada: se sabe que existe pero no se revela.
  factory _GridItem.evolucionLocked() => _GridItem._(null, 0, true);
  bool get bloqueada => carta == null;
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
