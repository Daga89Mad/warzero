// lib/views/historia_detalle_screen.dart

import 'package:flutter/material.dart';
import '../models/historia_model.dart';
import '../services/settings_controller.dart';

/// Visor de una historia: imagen grande arriba con flechas a los lados y la
/// descripción de esa página debajo.
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
    final war = context.war;
    final total = _paginas.length;
    final pagina = total > 0 ? _paginas[_index] : null;
    final puedeAtras = _index > 0;
    final puedeAdelante = _index < total - 1;

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text(
          widget.historia.titulo.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: war.primario,
          ),
        ),
      ),
      body: pagina == null
          ? Center(
              child: Text(
                'SIN CONTENIDO',
                style: TextStyle(
                  fontSize: 11,
                  color: war.textoTenue,
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
                                color: war.superficie,
                                width: double.infinity,
                                child: pagina.imagen.isEmpty
                                    ? Center(
                                        child: Icon(Icons.image_outlined,
                                            size: 48, color: war.borde),
                                      )
                                    : GestureDetector(
                                        onTap: () => _abrirImagenCompleta(
                                            context, pagina.imagen),
                                        child: Image.network(
                                          pagina.imagen,
                                          fit: BoxFit.contain,
                                          loadingBuilder: (c, child, p) =>
                                              p == null
                                                  ? child
                                                  : Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                        color: war.primario,
                                                      ),
                                                    ),
                                          errorBuilder: (c, e, s) => Center(
                                            child: Icon(
                                                Icons.broken_image_outlined,
                                                size: 48,
                                                color: war.borde),
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
                    style: TextStyle(
                      fontSize: 11,
                      color: war.primario,
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
                      color: war.superficie,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: war.primario.withOpacity(0.20)),
                    ),
                    child: SingleChildScrollView(
                      key: ValueKey(_index),
                      child: Text(
                        pagina.descripcion,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: war.texto,
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

/// Visor de la imagen a pantalla completa (siempre sobre negro).
class _ImagenCompletaScreen extends StatelessWidget {
  final String url;
  const _ImagenCompletaScreen({required this.url});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
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
                        : Center(
                            child: CircularProgressIndicator(
                              color: war.primario,
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
                    color: Colors.black.withOpacity(0.8),
                    border: Border.all(
                        color: war.primario.withOpacity(0.5), width: 1),
                  ),
                  child: Icon(Icons.close, size: 20, color: war.primario),
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
    final war = context.war;
    return Opacity(
      opacity: enabled ? 1 : 0.25,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 56,
          decoration: BoxDecoration(
            color: war.superficie.withOpacity(0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: war.primario.withOpacity(0.5), width: 1),
          ),
          child: Icon(icon, color: war.primario, size: 30),
        ),
      ),
    );
  }
}
