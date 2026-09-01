// lib/views/card_skin_selector_screen.dart

import 'package:flutter/material.dart';
import '../models/carta_model.dart';
import '../models/jugador_model.dart';
import '../services/warzero_api.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CardSkinSelectorScreen
//
// Muestra todas las skins DESBLOQUEADAS para una carta concreta.
// El jugador elige una y se guarda en:
//   Jugadores/{uid}/Coleccion/{cartaId}  →  skinSeleccionada: skinId
//
// Skins disponibles se cargan de:
//   Skins/{skinId}  filtrado por  cartaId == carta.id
//   + filtro adicional: solo las que están en skinsDesbloqueadas del jugador
// ─────────────────────────────────────────────────────────────────────────────

/// Una skin del inventario de la carta tal como la conoce el servidor en este
/// momento (id + imagen + rareza + si el jugador la tiene desbloqueada).
class SkinInventarioItem {
  final String id;
  final String imagen;
  final String rareza;
  final bool desbloqueada;

  const SkinInventarioItem({
    required this.id,
    required this.imagen,
    required this.rareza,
    this.desbloqueada = false,
  });
}

/// Resultado devuelto a CartasScreen al hacer pop.
class SkinSelectorResult {
  /// null → diseño original (sin skin)
  final String? skinId;
  final String? imagen;

  /// Rareza de la skin aplicada ('comun' | 'rara' | 'epica' | 'legendaria').
  /// null cuando se vuelve al diseño original.
  final String? rareza;

  /// Inventario COMPLETO de skins de la carta tal como lo acaba de leer el
  /// servidor en este selector. Es la FUENTE DE VERDAD con la que la colección
  /// reconcilia tanto la tira de números como el modo "Ver todo" (que pinta
  /// cada skin como una celda). null cuando no se pudo determinar el inventario.
  final List<SkinInventarioItem>? skinsInventario;

  const SkinSelectorResult({
    this.skinId,
    this.imagen,
    this.rareza,
    this.skinsInventario,
  });
}

class CardSkinSelectorScreen extends StatefulWidget {
  final CartaModel carta;
  final String uid;
  final String? skinActualId;

  /// IDs de skins que el jugador ya ha desbloqueado para esta carta.
  final List<String> skinsDesbloqueadas;

  const CardSkinSelectorScreen({
    super.key,
    required this.carta,
    required this.uid,
    required this.skinsDesbloqueadas,
    this.skinActualId,
  });

  @override
  State<CardSkinSelectorScreen> createState() => _CardSkinSelectorScreenState();
}

class _CardSkinSelectorScreenState extends State<CardSkinSelectorScreen> {
  final _api = WarZeroApi();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<_SkinItem> _skins = [];
  String? _selectedSkinId;

  // Datos para la compra de skins bloqueadas.
  int _vecesObtenida = 0;
  String? _comprandoId;

  @override
  void initState() {
    super.initState();
    _selectedSkinId = widget.skinActualId;
    _loadSkins();
  }

  Future<void> _loadSkins() async {
    try {
      // El servidor devuelve TODAS las skins de la carta con su estado
      // (desbloqueada o no) + el contador de veces obtenidas y el saldo Zero,
      // para poder mostrar el botón de compra en las bloqueadas.
      final data = await _api.obtenerSkinsCarta(widget.uid, widget.carta.id);

      final skins = ((data['skins'] as List?) ?? []).map((raw) {
        final d = Map<String, dynamic>.from(raw as Map);
        return _SkinItem(
          id: d['id']?.toString() ?? '',
          nombre: d['nombre']?.toString() ?? 'Sin nombre',
          imagen: d['imagen']?.toString() ?? '',
          rareza: d['rareza']?.toString() ?? 'comun',
          numeroCompra: (d['numeroCompra'] as num?)?.toInt() ?? 0,
          desbloqueada: d['desbloqueada'] == true,
        );
      }).toList();

      skins.sort(
          (a, b) => _rarezaOrder(b.rareza).compareTo(_rarezaOrder(a.rareza)));

      if (mounted) {
        setState(() {
          _skins = skins;
          _vecesObtenida = (data['vecesObtenida'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _comprar(_SkinItem skin) async {
    if (_comprandoId != null) return;
    setState(() => _comprandoId = skin.id);
    try {
      final res = await _api.comprarSkin(widget.uid, skin.id);
      final restantes =
          (res['vecesRestantes'] as num?)?.toInt() ?? _vecesObtenida;
      if (!mounted) return;
      setState(() {
        _vecesObtenida = restantes; // se consumieron las copias
        _skins = _skins
            .map((s) => s.id == skin.id ? s.comoDesbloqueada() : s)
            .toList();
        _selectedSkinId = skin.id; // auto-selecciona la recién canjeada
        _comprandoId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('¡Skin desbloqueada!',
            style: TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor: Color(0xFF1A3A0A),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _comprandoId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor: const Color(0xFF7A1010),
      ));
    }
  }

  int _rarezaOrder(String r) {
    switch (r) {
      case 'legendaria':
        return 4;
      case 'epica':
        return 3;
      case 'rara':
        return 2;
      default:
        return 1;
    }
  }

  Color _rarezaColor(String r) {
    switch (r) {
      case 'legendaria':
        return const Color(0xFFFF9500);
      case 'epica':
        return const Color(0xFFA040FF);
      case 'rara':
        return const Color(0xFF3090FF);
      default:
        return const Color(0xFF506070);
    }
  }

  String _rarezaLabel(String r) {
    switch (r) {
      case 'legendaria':
        return '★★★★ LEGENDARIA';
      case 'epica':
        return '★★★  ÉPICA';
      case 'rara':
        return '★★   RARA';
      default:
        return '★    COMÚN';
    }
  }

  Future<void> _confirmarSeleccion() async {
    setState(() => _saving = true);
    try {
      // El servidor escribe skinSeleccionada (o lo borra si es null) en la
      // colección del jugador. El cliente ya no toca Firestore.
      await _api.seleccionarSkin(
        uid: widget.uid,
        cartaId: widget.carta.id,
        skinId: _selectedSkinId,
      );

      if (!mounted) return;

      String? imagenSeleccionada;
      String? rarezaSeleccionada;
      if (_selectedSkinId != null) {
        try {
          final skin = _skins.firstWhere((s) => s.id == _selectedSkinId);
          imagenSeleccionada = skin.imagen.isNotEmpty ? skin.imagen : null;
          rarezaSeleccionada = skin.rareza;
        } catch (_) {}
      }

      Navigator.of(context).pop(SkinSelectorResult(
        skinId: _selectedSkinId,
        imagen: imagenSeleccionada,
        rareza: rarezaSeleccionada,
        // Inventario real y fresco de la carta para reconciliar la colección
        // (tira de números y modo "Ver todo"), que pudo cargarse desfasada.
        skinsInventario: _skins
            .map((s) => SkinInventarioItem(
                  id: s.id,
                  imagen: s.imagen,
                  rareza: s.rareza,
                  desbloqueada: s.desbloqueada,
                ))
            .toList(),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar: $e',
              style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
          backgroundColor: const Color(0xFF7A1010),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
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
            const Text('CAMBIAR DISEÑO',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 11,
                    letterSpacing: 2,
                    color: Color(0xFFC8A860))),
            Text(widget.carta.nombre.toUpperCase(),
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF506070),
                    letterSpacing: 1.5)),
          ],
        ),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _saving ? null : _confirmarSeleccion,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _saving
                        ? const Color(0xFF1A2A0A)
                        : const Color(0xFF1A3A0A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF4ABB58).withOpacity(0.6),
                        width: 1),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Color(0xFF4ABB58)))
                      : const Text('APLICAR',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 9,
                              letterSpacing: 1.5,
                              color: Color(0xFF4ABB58),
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A860)))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFC04040), fontFamily: 'Cinzel')))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    // Imagen de preview: skin seleccionada o imagen original
    final skinSeleccionada = _selectedSkinId != null
        ? _skins.firstWhere(
            (s) => s.id == _selectedSkinId,
            orElse: () => _SkinItem(id: '', nombre: '', imagen: '', rareza: ''),
          )
        : null;

    final desbloqueadas = _skins.where((s) => s.desbloqueada).toList();
    final enVenta = _skins.where((s) => !s.desbloqueada).toList();
    final monedaColor = MonedaZeroExt.fromEjercito(widget.carta.ejercito).color;

    return Column(
      children: [
        // ── Vista previa ─────────────────────────────────────
        _PreviewBar(
          carta: widget.carta,
          skinActiva: skinSeleccionada,
        ),

        const Divider(color: Color(0xFF1A2A3A), height: 1),

        // ── Lista de opciones ────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Opción por defecto
              _OpcionDefault(
                imagenDefault: widget.carta.imagen,
                isSelected: _selectedSkinId == null,
                onTap: () => setState(() => _selectedSkinId = null),
              ),

              const SizedBox(height: 16),

              if (desbloqueadas.isEmpty && enVenta.isEmpty)
                const _SinSkinsView()
              else ...[
                if (desbloqueadas.isNotEmpty) ...[
                  const Text('DISEÑOS DESBLOQUEADOS',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 8,
                          letterSpacing: 2,
                          color: Color(0xFF506070))),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.60,
                    ),
                    itemCount: desbloqueadas.length,
                    itemBuilder: (_, i) => _SkinCard(
                      skin: desbloqueadas[i],
                      isSelected: _selectedSkinId == desbloqueadas[i].id,
                      rarezaColor: _rarezaColor(desbloqueadas[i].rareza),
                      rarezaLabel: _rarezaLabel(desbloqueadas[i].rareza),
                      onTap: () =>
                          setState(() => _selectedSkinId = desbloqueadas[i].id),
                    ),
                  ),
                ],
                if (enVenta.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    const Text('CANJEAR POR COPIAS',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            letterSpacing: 2,
                            color: Color(0xFF506070))),
                    const Spacer(),
                    Text('$_vecesObtenida copias',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            color: monedaColor)),
                  ]),
                  const SizedBox(height: 10),
                  for (final skin in enVenta)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SkinCompraCard(
                        skin: skin,
                        rarezaColor: _rarezaColor(skin.rareza),
                        rarezaLabel: _rarezaLabel(skin.rareza),
                        acento: monedaColor,
                        vecesObtenida: _vecesObtenida,
                        comprando: _comprandoId == skin.id,
                        bloqueadoPorOtraCompra:
                            _comprandoId != null && _comprandoId != skin.id,
                        onComprar: () => _comprar(skin),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PREVIEW BAR
// ─────────────────────────────────────────────────────────────
class _PreviewBar extends StatelessWidget {
  final CartaModel carta;
  final _SkinItem? skinActiva;

  const _PreviewBar({required this.carta, required this.skinActiva});

  @override
  Widget build(BuildContext context) {
    final imagenMostrada = (skinActiva != null && skinActiva!.imagen.isNotEmpty)
        ? skinActiva!.imagen
        : carta.imagen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFF080F1A),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 95,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: skinActiva != null
                      ? const Color(0xFFA040FF).withOpacity(0.5)
                      : const Color(0xFFC8A860).withOpacity(0.4),
                  width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: imagenMostrada.isNotEmpty
                  ? Image.network(imagenMostrada,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _PlaceholderSmall())
                  : const _PlaceholderSmall(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VISTA PREVIA',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 7,
                        letterSpacing: 2,
                        color: Color(0xFF506070))),
                const SizedBox(height: 4),
                Text(carta.nombre.toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        color: Color(0xFFC8A860),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  skinActiva != null
                      ? '🎨 ${skinActiva!.nombre}'
                      : '🖼 Diseño original',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      color: skinActiva != null
                          ? const Color(0xFFA040FF)
                          : const Color(0xFF506070)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// OPCIÓN POR DEFECTO
// ─────────────────────────────────────────────────────────────
class _OpcionDefault extends StatelessWidget {
  final String imagenDefault;
  final bool isSelected;
  final VoidCallback onTap;

  const _OpcionDefault({
    required this.imagenDefault,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0A2A0A) : const Color(0xFF0A1525),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF4ABB58) : const Color(0xFF1A2A3A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2A3A4A), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: imagenDefault.isNotEmpty
                    ? Image.network(imagenDefault,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _PlaceholderSmall())
                    : const _PlaceholderSmall(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DISEÑO ORIGINAL',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 11,
                          color: Color(0xFFC8A860),
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  const Text('Imagen base de la carta',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 8,
                          color: Color(0xFF506070))),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  size: 20, color: Color(0xFF4ABB58)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SKIN CARD
// ─────────────────────────────────────────────────────────────
class _SkinCard extends StatelessWidget {
  final _SkinItem skin;
  final bool isSelected;
  final Color rarezaColor;
  final String rarezaLabel;
  final VoidCallback onTap;

  const _SkinCard({
    required this.skin,
    required this.isSelected,
    required this.rarezaColor,
    required this.rarezaLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1525),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? rarezaColor : rarezaColor.withOpacity(0.25),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: rarezaColor.withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 1)
                ]
              : [],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(7)),
                    child: skin.imagen.isNotEmpty
                        ? Image.network(skin.imagen,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _PlaceholderSmall())
                        : const _PlaceholderSmall(),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rarezaLabel,
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 5.5,
                              color: rarezaColor,
                              letterSpacing: 0.3)),
                      const SizedBox(height: 2),
                      Text(
                        skin.nombre.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 7.5,
                            color: Color(0xFFC8A860),
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration:
                      BoxDecoration(color: rarezaColor, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 13, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// VISTA SIN SKINS
// ─────────────────────────────────────────────────────────────
class _SinSkinsView extends StatelessWidget {
  const _SinSkinsView();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_search, size: 40, color: Color(0xFF2A3A4A)),
              SizedBox(height: 14),
              Text('Sin diseños desbloqueados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      color: Color(0xFF506070))),
              SizedBox(height: 6),
              Text(
                'Consigue nuevos diseños jugando\npartidas y subiendo de nivel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF3A4A5A),
                    height: 1.6),
              ),
            ],
          ),
        ),
      );
}

class _PlaceholderSmall extends StatelessWidget {
  const _PlaceholderSmall();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0A1525),
        child: const Icon(Icons.image_outlined,
            size: 20, color: Color(0xFF2A3A4A)),
      );
}

// ─────────────────────────────────────────────────────────────
// MODELO LOCAL
// ─────────────────────────────────────────────────────────────
class _SkinItem {
  final String id;
  final String nombre;
  final String imagen;
  final String rareza;

  /// Veces que debe tocarte la carta para poder comprarla (0 = no comprable).
  final int numeroCompra;

  /// True si el jugador ya la tiene desbloqueada.
  final bool desbloqueada;

  const _SkinItem({
    required this.id,
    required this.nombre,
    required this.imagen,
    required this.rareza,
    this.numeroCompra = 0,
    this.desbloqueada = true,
  });

  bool get esLegendaria => rareza == 'legendaria';

  _SkinItem comoDesbloqueada() => _SkinItem(
        id: id,
        nombre: nombre,
        imagen: imagen,
        rareza: rareza,
        numeroCompra: numeroCompra,
        desbloqueada: true,
      );
}

// ─────────────────────────────────────────────────────────────
// SKIN BLOQUEADA — canje por copias de la carta
// ─────────────────────────────────────────────────────────────
class _SkinCompraCard extends StatelessWidget {
  final _SkinItem skin;
  final Color rarezaColor;
  final String rarezaLabel;
  final Color acento;
  final int vecesObtenida;
  final bool comprando;
  final bool bloqueadoPorOtraCompra;
  final VoidCallback onComprar;

  const _SkinCompraCard({
    required this.skin,
    required this.rarezaColor,
    required this.rarezaLabel,
    required this.acento,
    required this.vecesObtenida,
    required this.comprando,
    required this.bloqueadoPorOtraCompra,
    required this.onComprar,
  });

  @override
  Widget build(BuildContext context) {
    final cumple = skin.numeroCompra > 0 && vecesObtenida >= skin.numeroCompra;
    final faltan = (skin.numeroCompra - vecesObtenida).clamp(0, 9999);
    final puedeCanjear = !skin.esLegendaria &&
        skin.numeroCompra > 0 &&
        cumple &&
        !comprando &&
        !bloqueadoPorOtraCompra;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rarezaColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          // Miniatura bloqueada (imagen atenuada + candado).
          SizedBox(
            width: 46,
            height: 62,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        Colors.black54, BlendMode.darken),
                    child: skin.imagen.isNotEmpty
                        ? Image.network(skin.imagen,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _PlaceholderSmall())
                        : const _PlaceholderSmall(),
                  ),
                ),
                const Center(
                    child: Icon(Icons.lock, size: 18, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rarezaLabel,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 6,
                        color: rarezaColor,
                        letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(skin.nombre.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 9,
                        color: Color(0xFFC8A860),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (skin.esLegendaria)
                  const Text('Solo se consigue en sobres',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 7,
                          color: Color(0xFFFF9500)))
                else
                  Text(
                    'Copias: $vecesObtenida/${skin.numeroCompra}'
                    '${cumple ? "  \u00b7  \u00a1listo!" : "  \u00b7  faltan $faltan"}',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 7,
                        color: cumple
                            ? const Color(0xFF4ABB58)
                            : const Color(0xFF607080)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!skin.esLegendaria)
            GestureDetector(
              onTap: puedeCanjear ? onComprar : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: puedeCanjear
                      ? acento.withOpacity(0.18)
                      : const Color(0xFF10202E),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: puedeCanjear
                          ? acento.withOpacity(0.7)
                          : const Color(0xFF203040),
                      width: 1),
                ),
                child: comprando
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: acento))
                    : Text(
                        cumple ? 'CANJEAR' : 'FALTAN $faltan',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.bold,
                            color: puedeCanjear
                                ? acento
                                : const Color(0xFF506070)),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
