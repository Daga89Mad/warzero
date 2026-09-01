// lib/views/apertura_sobre_screen.dart

import 'package:flutter/material.dart';
import '../services/settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AperturaSobreScreen
//
// Muestra un sobre; el jugador MANTIENE PULSADO el centro y el brillo va
// subiendo. Al cargarse del todo, el sobre estalla y aparecen todas las cartas
// en pantalla con una animación escalonada.
//
// Recibe las cartas ya resueltas por el backend (cada una es un mapa con
// {cartaId, nombre, imagen, nueva, vecesObtenida, skinLegendaria}).
//
// Optimizaciones de rendimiento:
//   • Las miniaturas se decodifican al tamaño REAL de la celda (ResizeImage)
//     en lugar de a la resolución original del arte → mucho menos tiempo de
//     decodificado y memoria.
//   • Las imágenes se PRECARGAN mientras el jugador mantiene pulsado, así al
//     revelar aparecen al instante y sin tirones.
//   • El sobre animado va dentro de un RepaintBoundary para no repintar el
//     fondo a pantalla completa en cada frame del brillo.
//   • Las animaciones de aparición se calculan una sola vez (no se crean
//     CurvedAnimation nuevas por celda en cada build).
// ─────────────────────────────────────────────────────────────────────────────
class AperturaSobreScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartas;
  final Color acento;
  final String titulo;

  /// Ruta del asset del sobre (p. ej. 'assets/images/SobreCeleste.png').
  final String imagenSobre;

  /// Ruta del asset del fondo del ejército (p. ej. 'assets/images/FondoCeleste.png').
  final String fondo;

  const AperturaSobreScreen({
    super.key,
    required this.cartas,
    required this.acento,
    required this.imagenSobre,
    required this.fondo,
    this.titulo = 'SOBRE',
  });

  @override
  State<AperturaSobreScreen> createState() => _AperturaSobreScreenState();
}

class _AperturaSobreScreenState extends State<AperturaSobreScreen>
    with TickerProviderStateMixin {
  late final AnimationController _carga; // 0→1 mientras se mantiene pulsado
  late final AnimationController _reveal; // animación de aparición de cartas

  // Animaciones de aparición precalculadas (una por carta) para no crear
  // CurvedAnimation nuevas en cada frame dentro del itemBuilder.
  late final List<Animation<double>> _revealAnims;

  bool _abierto = false;

  // Ancho de decodificación de las miniaturas, en píxeles físicos. Se calcula
  // una sola vez, cuando ya tenemos MediaQuery disponible.
  int? _thumbW;
  bool _precargado = false;

  @override
  void initState() {
    super.initState();
    _carga = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _abrir();
      });
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // Se calculan una sola vez; el itemBuilder solo las lee.
    final n = widget.cartas.length;
    _revealAnims = List<Animation<double>>.generate(n, (i) {
      final start = n <= 1 ? 0.0 : (i / n) * 0.55;
      return CurvedAnimation(
        parent: _reveal,
        curve: Interval(
          start,
          (start + 0.45).clamp(0.0, 1.0),
          curve: Curves.easeOutBack,
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precargado) return;
    _precargado = true;

    final mq = MediaQuery.of(context);
    // Cada celda ocupa ~1/3 del ancho de pantalla. Decodificamos a esa
    // resolución real en vez de al tamaño original del arte (evita decodificar
    // imágenes de 1000px+ para mostrarlas en ~110px lógicos).
    _thumbW = (mq.size.width / 3 * mq.devicePixelRatio).round();

    // Precargamos las imágenes YA redimensionadas, con la misma "key" que usará
    // cada tarjeta, para que al revelar aparezcan al instante y sin volver a
    // decodificar.
    for (final c in widget.cartas) {
      final url = c['imagen']?.toString() ?? '';
      if (url.isEmpty) continue;
      precacheImage(ResizeImage(NetworkImage(url), width: _thumbW), context);
    }
  }

  @override
  void dispose() {
    _carga.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _mantener(_) {
    if (_abierto) return;
    _carga.forward();
  }

  void _soltar([_]) {
    if (_abierto) return;
    if (!_carga.isCompleted) _carga.reverse();
  }

  void _abrir() {
    setState(() => _abierto = true);
    _reveal.forward();
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: const Color(0xFF04070E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo del ejército.
          Image.asset(
            widget.fondo,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF04070E)),
          ),
          // Scrim para contraste (más oscuro al revelar las cartas).
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            color: Colors.black.withOpacity(_abierto ? 0.72 : 0.45),
          ),
          SafeArea(
            child: _abierto ? _buildCartas(war) : _buildSobre(war),
          ),
        ],
      ),
    );
  }

  // ── Sobre con brillo creciente ───────────────────────────────
  Widget _buildSobre(dynamic war) {
    return Stack(
      children: [
        // Sobre encajado sobre la plataforma del fondo (algo por encima del
        // centro). Ajusta el segundo valor del Alignment (-1 arriba, 1 abajo)
        // si quieres subirlo o bajarlo respecto a la plataforma.
        Align(
          alignment: const Alignment(0, -0.22),
          // RepaintBoundary aísla el repintado del sobre (que se anima en cada
          // frame por el brillo) del fondo a pantalla completa y del scrim.
          child: RepaintBoundary(
            child: GestureDetector(
              onTapDown: _mantener,
              onTapUp: _soltar,
              onTapCancel: _soltar,
              child: AnimatedBuilder(
                animation: _carga,
                builder: (_, __) {
                  final t = Curves.easeIn.transform(_carga.value);
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: widget.acento.withOpacity(0.18 + t * 0.6),
                          // Blur más contenido (24→~74 en vez de 24→114). Las
                          // sombras difuminadas grandes animadas son de lo más
                          // caro de pintar por frame; con RepaintBoundary +
                          // este ajuste va notablemente más fino.
                          blurRadius: 24 + t * 50,
                          spreadRadius: t * 12,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 240,
                          height: 330,
                          child: Image.asset(
                            widget.imagenSobre,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _PaqueteSobre(
                                t: _carga.value, color: widget.acento),
                          ),
                        ),
                        IgnorePointer(
                          child: Container(
                            width: 240,
                            height: 330,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                radius: 0.5,
                                colors: [
                                  Colors.white.withOpacity(t * 0.55),
                                  widget.acento.withOpacity(t * 0.30),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.35, 0.75],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Título arriba.
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Text(widget.titulo.toUpperCase(),
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 13,
                    letterSpacing: 4,
                    color: widget.acento)),
          ),
        ),
        // Pista abajo.
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _carga,
              builder: (_, __) => Opacity(
                opacity: (1 - _carga.value).clamp(0.3, 1.0),
                child: Text(
                  _carga.value > 0.02
                      ? 'SIGUE PULSANDO…'
                      : 'MANTÉN PULSADO EL CENTRO',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      letterSpacing: 2,
                      color: war.textoTenue),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Cartas reveladas ─────────────────────────────────────────
  Widget _buildCartas(dynamic war) {
    final n = widget.cartas.length;
    return Column(
      children: [
        const SizedBox(height: 16),
        Text('¡$n CARTAS!',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 14,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
                color: widget.acento)),
        const SizedBox(height: 4),
        Text('TU BOTÍN',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 8,
                letterSpacing: 3,
                color: war.textoTenue)),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemCount: n,
            itemBuilder: (_, i) {
              final anim = _revealAnims[i];
              return AnimatedBuilder(
                animation: anim,
                builder: (_, child) {
                  final v = anim.value.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: v,
                    child: Transform.scale(scale: v, child: child),
                  );
                },
                // El contenido va como `child`: NO se reconstruye en cada frame
                // de la animación (solo se reaplica Opacity/scale). Además cada
                // carta en su RepaintBoundary para no propagar repintados.
                child: RepaintBoundary(
                  child: _CartaRevelada(
                    carta: widget.cartas[i],
                    acento: widget.acento,
                    thumbW: _thumbW,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.acento.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.acento.withOpacity(0.7)),
              ),
              child: Text('CONTINUAR',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                      color: widget.acento)),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SOBRE (paquete) con brillo creciente según t (0..1)
// ─────────────────────────────────────────────────────────────
class _PaqueteSobre extends StatelessWidget {
  final double t; // 0 = apagado, 1 = a punto de estallar
  final Color color;
  const _PaqueteSobre({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    final glow = Curves.easeIn.transform(t);
    return Container(
      width: 210,
      height: 290,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B1526),
            Color.lerp(const Color(0xFF10203A), color.withOpacity(0.5), glow)!,
            const Color(0xFF07101E),
          ],
        ),
        border: Border.all(
          color: Color.lerp(color.withOpacity(0.4), color, glow)!,
          width: 1.5 + glow * 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15 + glow * 0.6),
            blurRadius: 20 + glow * 70,
            spreadRadius: glow * 12,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Núcleo hexagonal que brilla.
          Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: RadialGradient(colors: [
                  Color.lerp(color.withOpacity(0.5), Colors.white, glow * 0.7)!,
                  color.withOpacity(0.15 + glow * 0.5),
                ]),
                boxShadow: [
                  BoxShadow(
                      color: color.withOpacity(0.3 + glow * 0.6),
                      blurRadius: 10 + glow * 40),
                ],
              ),
            ),
          ),
          Icon(Icons.brightness_7,
              size: 30 + glow * 10,
              color: Color.lerp(color, Colors.white, glow)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARTA REVELADA
// ─────────────────────────────────────────────────────────────
class _CartaRevelada extends StatelessWidget {
  final Map<String, dynamic> carta;
  final Color acento;

  /// Ancho de decodificación en píxeles físicos (tamaño real de la celda).
  final int? thumbW;

  const _CartaRevelada({
    required this.carta,
    required this.acento,
    this.thumbW,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final nombre = carta['nombre']?.toString() ?? '';
    final imagen = carta['imagen']?.toString() ?? '';
    final nueva = carta['nueva'] == true;
    final legendaria = (carta['skinLegendaria']?.toString() ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (legendaria ? const Color(0xFFFF9500) : acento)
                            .withOpacity(0.6),
                        width: 1.2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: imagen.isNotEmpty ? _imagen(war, imagen) : _ph(war),
                  ),
                ),
              ),
              if (nueva)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A0A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF4ABB58)),
                    ),
                    child: const Text('NUEVA',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 6,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7BE08A))),
                  ),
                ),
              if (legendaria)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.workspace_premium,
                      size: 14, color: Color(0xFFFF9500)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(nombre.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontFamily: 'Cinzel', fontSize: 7, color: war.texto)),
      ],
    );
  }

  // Imagen decodificada al tamaño real de la celda (ResizeImage) y con un
  // fundido suave al aparecer. La "key" coincide con la de precacheImage, así
  // que si ya está precargada se pinta de inmediato.
  Widget _imagen(dynamic war, String url) {
    // Cada rama se asigna por separado para que se suba a ImageProvider de
    // forma individual (un ternario mezclaría ResizeImage y NetworkImage y el
    // tipo común inferido sería Object, que no es asignable a ImageProvider).
    final int? w = thumbW;
    final ImageProvider provider;
    if (w != null) {
      provider = ResizeImage(NetworkImage(url), width: w);
    } else {
      provider = NetworkImage(url);
    }

    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (_, __, ___) => _ph(war),
    );
  }

  Widget _ph(dynamic war) => Container(
        color: war.fondo,
        child: Icon(Icons.image_outlined, size: 24, color: war.borde),
      );
}
