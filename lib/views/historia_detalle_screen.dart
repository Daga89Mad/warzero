// lib/views/historia_detalle_screen.dart

import 'package:flutter/material.dart';
import '../models/historia_model.dart';

/// Visor de una historia: imagen grande arriba con flechas a los lados para
/// avanzar/retroceder, y la descripción de esa página debajo. Las páginas se
/// recorren en orden cronológico (ya vienen ordenadas en el modelo).
class HistoriaDetalleScreen extends StatefulWidget {
  final HistoriaModel historia;
  const HistoriaDetalleScreen({super.key, required this.historia});

  @override
  State<HistoriaDetalleScreen> createState() => _HistoriaDetalleScreenState();
}

class _HistoriaDetalleScreenState extends State<HistoriaDetalleScreen> {
  int _index = 0;

  List<HistoriaPagina> get _paginas => widget.historia.paginas;

  void _prev() {
    if (_index > 0) setState(() => _index--);
  }

  void _next() {
    if (_index < _paginas.length - 1) setState(() => _index++);
  }

  void _abrirImagenCompleta(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _ImagenCompletaScreen(url: url),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _paginas.length;
    final pagina = total > 0 ? _paginas[_index] : null;
    final puedeAtras = _index > 0;
    final puedeAdelante = _index < total - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: Color(0xFFC8A860)),
        title: Text(
          widget.historia.titulo.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: Color(0xFFC8A860),
          ),
        ),
      ),
      body: pagina == null
          ? const Center(
              child: Text(
                'SIN CONTENIDO',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  letterSpacing: 2,
                ),
              ),
            )
          : Column(
              children: [
                // ── Imagen grande + flechas laterales ─────────────
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    // Permitir también deslizar para pasar de página.
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -120) {
                        _next();
                      } else if (v > 120) {
                        _prev();
                      }
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                color: const Color(0xFF050C14),
                                width: double.infinity,
                                child: pagina.imagen.isEmpty
                                    ? const Center(
                                        child: Icon(Icons.image_outlined,
                                            size: 48, color: Color(0xFF334050)),
                                      )
                                    : GestureDetector(
                                        onTap: () => _abrirImagenCompleta(
                                            context, pagina.imagen),
                                        child: Image.network(
                                          pagina.imagen,
                                          fit: BoxFit.contain,
                                          loadingBuilder: (c, child, p) => p ==
                                                  null
                                              ? child
                                              : const Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                    color: Color(0xFFC8A860),
                                                  ),
                                                ),
                                          errorBuilder: (c, e, s) =>
                                              const Center(
                                            child: Icon(
                                                Icons.broken_image_outlined,
                                                size: 48,
                                                color: Color(0xFF334050)),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 2,
                          child: _NavArrow(
                            icon: Icons.chevron_left,
                            enabled: puedeAtras,
                            onTap: _prev,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          child: _NavArrow(
                            icon: Icons.chevron_right,
                            enabled: puedeAdelante,
                            onTap: _next,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Indicador de página ───────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${_index + 1} / $total',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFC8A860),
                      fontFamily: 'Cinzel',
                      letterSpacing: 2,
                    ),
                  ),
                ),

                // ── Descripción de la página ──────────────────────
                Expanded(
                  flex: 2,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1220),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFC8A860).withOpacity(0.20)),
                    ),
                    child: SingleChildScrollView(
                      // Sin esta key, al cambiar de página (_next/_prev) el
                      // scroll de la descripción conservaba el desplazamiento
                      // de la página anterior en vez de empezar arriba: si
                      // habías bajado leyendo una página larga, la siguiente
                      // entraba ya desplazada y había que subir a mano. La
                      // key fuerza a Flutter a tratarlo como un scroll nuevo
                      // (offset 0) cada vez que cambia `_index`.
                      key: ValueKey(_index),
                      child: Text(
                        pagina.descripcion,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFFD8D0BC),
                          fontFamily: 'Cinzel',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Visor de la imagen ocupando toda la pantalla. Permite hacer zoom/pan
/// (InteractiveViewer) y se cierra tocando la imagen o el botón de cerrar.
class _ImagenCompletaScreen extends StatelessWidget {
  final String url;
  const _ImagenCompletaScreen({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFC8A860),
                            ),
                          ),
                    errorBuilder: (c, e, s) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 64, color: Color(0xFF334050)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xCC02050D),
                    border: Border.all(
                        color: const Color(0xFFC8A860).withOpacity(0.5),
                        width: 1),
                  ),
                  child: const Icon(Icons.close,
                      size: 20, color: Color(0xFFC8A860)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flecha de navegación semitransparente; se atenúa cuando no se puede avanzar.
class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.25,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xCC02050D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFC8A860).withOpacity(0.5), width: 1),
          ),
          child: Icon(icon, color: const Color(0xFFC8A860), size: 30),
        ),
      ),
    );
  }
}
