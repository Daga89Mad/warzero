// lib/widgets/board_widget.dart

import 'package:flutter/material.dart';
import '../models/game_config.dart';
import '../models/board_state.dart';
import 'cell_widget.dart';

/// Imagen usada cuando el mapa no define una propia (campo `imagen` vacío).
const String kImagenTableroPorDefecto = 'assets/images/map_background.png';

/// Pinta la imagen de fondo del tablero a partir de la referencia del mapa.
/// Acepta URL http(s) (Image.network) o ruta de asset (Image.asset), y cae a
/// [kImagenTableroPorDefecto] si la referencia está vacía o falla la carga.
/// Se reutiliza en el preview del editor de mapas.
class BoardBackgroundImage extends StatelessWidget {
  final String? imagen;
  final BoxFit fit;

  const BoardBackgroundImage({
    super.key,
    required this.imagen,
    this.fit = BoxFit.fill,
  });

  @override
  Widget build(BuildContext context) {
    final ref = (imagen ?? '').trim();

    if (ref.isEmpty) return _asset(kImagenTableroPorDefecto);

    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return Image.network(
        ref,
        fit: fit,
        // Si la URL falla (404, sin red…) no dejamos el tablero en blanco.
        errorBuilder: (_, __, ___) => _asset(kImagenTableroPorDefecto),
      );
    }
    return _asset(ref);
  }

  Widget _asset(String path) => Image.asset(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0A1828)),
      );
}

class BoardWidget extends StatefulWidget {
  final GameConfig config;
  final BoardState boardState;
  final String? selectedCellCoord;
  final bool highlightEmpty;
  final Set<String> movableCoords;
  final String? obeliscoLocal;

  /// uid → color del obelisco para colorear cartas
  final Map<String, Color> playerColors;

  /// uid del jugador local (para el +80 de defensa del cuartel en el preview).
  final String? localPlayerUid;

  /// Imagen de fondo del tablero para ESTE mapa. Puede ser:
  ///   - una URL http(s)  → se carga con Image.network
  ///   - una ruta de asset → se carga con Image.asset
  ///   - null / vacío      → se usa [kImagenTableroPorDefecto]
  /// Viene del campo `imagen` del documento del mapa en Firestore.
  final String? imagenMapa;

  final Function(String coord, int ri, int ci) onCellTap;

  /// Toque dentro del área del tablero pero FUERA de cualquier celda (el marco
  /// de roca, el océano alrededor de la rejilla, el canto de madera…). Las
  /// celdas consumen su propio tap, así que esto solo salta en el "vacío".
  /// game_screen lo usa para deseleccionar la carta/acción en curso.
  final VoidCallback? onBackgroundTap;

  const BoardWidget({
    super.key,
    required this.config,
    required this.boardState,
    required this.selectedCellCoord,
    required this.highlightEmpty,
    this.movableCoords = const {},
    this.obeliscoLocal,
    this.playerColors = const {},
    this.localPlayerUid,
    this.imagenMapa,
    this.onBackgroundTap,
    required this.onCellTap,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _momentumCtrl;

  // ── Pan ───────────────────────────────────────────────────
  Offset _panOffset = Offset.zero;
  Offset _velocity = Offset.zero;
  bool _centered = false;

  // ── Zoom ─────────────────────────────────────────────────
  double _scale = 1.0;
  double _scaleStart = 1.0;
  Offset _focalPoint = Offset.zero;
  Offset _panAtScale = Offset.zero; // pan snapshot when pinch started

  static const double _minScale = 0.4;
  static const double _maxScale = 2.0;

  double get _logicalW => kLabelW + widget.config.cols * kCellW + 80;
  double get _logicalH => kLabelH + widget.config.rows * kCellH + 120;

  @override
  void initState() {
    super.initState();
    _momentumCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_applyMomentum);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerBoard());
  }

  @override
  void dispose() {
    _momentumCtrl.dispose();
    super.dispose();
  }

  void _centerBoard() {
    if (_centered) return;
    final size = context.size;
    if (size == null) return;
    _centered = true;
    setState(() {
      final targetY = _logicalW * _scale - size.height * 0.3;
      _panOffset = Offset(
        -((_logicalW * _scale) - size.width).clamp(0.0, double.infinity) / 2,
        -((_logicalH * _scale) - size.height * 0.75)
            .clamp(0.0, double.infinity),
      );
    });
  }

  Offset _clamp(Offset o, Size vs) {
    final sw = _logicalW * _scale;
    final sh = _logicalH * _scale;
    return Offset(
      o.dx.clamp(-((sw - vs.width + 300).clamp(0.0, double.infinity)), 300.0),
      o.dy.clamp(-((sh - vs.height + 500).clamp(0.0, double.infinity)), 300.0),
    );
  }

  // ── Scale gesture callbacks ───────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _momentumCtrl.stop();
    _scaleStart = _scale;
    _focalPoint = d.localFocalPoint;
    _panAtScale = _panOffset;
    _velocity = Offset.zero;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final size = context.size ?? const Size(400, 400);

    if (d.pointerCount >= 2) {
      // ── Pinch zoom ──────────────────────────────────────
      final newScale = (_scaleStart * d.scale).clamp(_minScale, _maxScale);

      // Zoom centrado en el punto focal: mantener el punto del mapa
      // bajo el dedo estático mientras se hace zoom
      final focalInBoard = (_focalPoint - _panAtScale) / _scaleStart;
      final newPan = _focalPoint - focalInBoard * newScale;

      setState(() {
        _scale = newScale;
        _panOffset = _clamp(newPan, size);
      });
    } else {
      // ── Pan ─────────────────────────────────────────────
      final delta = d.focalPoint - _focalPoint;
      _focalPoint = d.focalPoint;
      setState(() {
        _panOffset = _clamp(_panOffset + delta, size);
        _velocity = delta;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount < 2) {
      // Momentum solo en pan
      _velocity = d.velocity.pixelsPerSecond / 60.0;
      _momentumCtrl.value = 1.0;
      _momentumCtrl.animateTo(0.0,
          duration: const Duration(milliseconds: 900),
          curve: Curves.decelerate);
    }
  }

  void _applyMomentum() {
    final size = context.size;
    if (size == null) return;
    setState(() {
      _panOffset = _clamp(_panOffset + _velocity, size);
      _velocity *= 0.91;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          // Un toque limpio (sin arrastre) sobre el tablero que NO haya sido
          // consumido por una celda cae aquí: es "fuera del mapa".
          onTap: widget.onBackgroundTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: _panOffset,
                child: Transform.scale(
                  scale: _scale,
                  alignment: Alignment.topLeft,
                  child: _PerspectiveBoard(
                    config: widget.config,
                    boardState: widget.boardState,
                    selectedCoord: widget.selectedCellCoord,
                    highlightEmpty: widget.highlightEmpty,
                    movableCoords: widget.movableCoords,
                    obeliscoLocal: widget.obeliscoLocal,
                    playerColors: widget.playerColors,
                    localPlayerUid: widget.localPlayerUid,
                    imagenMapa: widget.imagenMapa,
                    onCellTap: widget.onCellTap,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Controles de zoom ─────────────────────────────
        Positioned(
          right: 12,
          bottom: 12,
          child: _ZoomControls(
            scale: _scale,
            onZoomIn: () => _zoomBy(1.25),
            onZoomOut: () => _zoomBy(0.80),
            onReset: () => _resetZoom(),
          ),
        ),
      ],
    );
  }

  void _zoomBy(double factor) {
    final size = context.size ?? const Size(400, 400);
    final center = Offset(size.width / 2, size.height / 2);
    final newScale = (_scale * factor).clamp(_minScale, _maxScale);
    final focalInBoard = (center - _panOffset) / _scale;
    setState(() {
      _scale = newScale;
      _panOffset = _clamp(center - focalInBoard * newScale, size);
    });
  }

  void _resetZoom() {
    final size = context.size ?? const Size(400, 400);
    setState(() {
      _scale = 1.0;
      _panOffset = _clamp(
          Offset(
            -((_logicalW) - size.width).clamp(0.0, double.infinity) / 2,
            -((_logicalH) - size.height * 0.75).clamp(0.0, double.infinity),
          ),
          size);
    });
  }
}

// ── Botones de zoom ────────────────────────────────────────────
class _ZoomControls extends StatelessWidget {
  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC060F1C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x405A4820), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomBtn(icon: Icons.add, onTap: onZoomIn),
          Container(height: 0.5, color: const Color(0x30C8A860)),
          _ZoomBtn(
            onTap: onReset,
            child: Text(
              '${(scale * 100).round()}%',
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFFC8A860),
                fontFamily: 'Cinzel',
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(height: 0.5, color: const Color(0x30C8A860)),
          _ZoomBtn(icon: Icons.remove, onTap: onZoomOut),
        ],
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;

  const _ZoomBtn({required this.onTap, this.icon, this.child})
      : assert(icon != null || child != null);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, size: 18, color: const Color(0xFFC8A860))
            : child,
      ),
    );
  }
}

class _PerspectiveBoard extends StatelessWidget {
  final GameConfig config;
  final BoardState boardState;
  final String? selectedCoord;
  final bool highlightEmpty;
  final Set<String> movableCoords;
  final String? obeliscoLocal;
  final Map<String, Color> playerColors;
  final String? localPlayerUid;
  final String? imagenMapa;
  final Function(String, int, int) onCellTap;

  const _PerspectiveBoard({
    required this.config,
    required this.boardState,
    required this.selectedCoord,
    required this.highlightEmpty,
    this.movableCoords = const {},
    this.obeliscoLocal,
    this.playerColors = const {},
    this.localPlayerUid,
    this.imagenMapa,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.topCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0010)
        ..rotateX(-0.58),
      child: _RockFrame(
        child: _GridContent(
          config: config,
          boardState: boardState,
          selectedCoord: selectedCoord,
          highlightEmpty: highlightEmpty,
          movableCoords: movableCoords,
          obeliscoLocal: obeliscoLocal,
          playerColors: playerColors,
          localPlayerUid: localPlayerUid,
          imagenMapa: imagenMapa,
          onCellTap: onCellTap,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOARD FRAME – Mesa de mando militar: madera oscura + metal
// ─────────────────────────────────────────────────────────────
class _RockFrame extends StatelessWidget {
  final Widget child;
  const _RockFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Superficie del tablero ────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
            // Madera oscura: veta horizontal suave
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1E1608), // madera oscura superficial
                Color(0xFF271C0C), // veta media
                Color(0xFF1A1208), // madera profunda
                Color(0xFF221A0E), // veta cálida
                Color(0xFF1C1208), // base
              ],
              stops: [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
            border: Border.all(color: const Color(0xFF5A4820), width: 1.5),
            boxShadow: const [
              // Borde metálico superior-izquierdo (acero bruñido)
              BoxShadow(
                  color: Color(0xFFD0B870),
                  offset: Offset(-8, -6),
                  blurRadius: 0),
              BoxShadow(
                  color: Color(0xFFAA9050),
                  offset: Offset(-6, -4),
                  blurRadius: 0,
                  spreadRadius: 1),
              BoxShadow(
                  color: Color(0xFF8C7848),
                  offset: Offset(-4, -3),
                  blurRadius: 0,
                  spreadRadius: 2),
              BoxShadow(
                  color: Color(0xFF6A5A30),
                  offset: Offset(-2, -1),
                  blurRadius: 0,
                  spreadRadius: 3),
              // Sombra inferior-derecha
              BoxShadow(
                  color: Color(0xFF060402),
                  offset: Offset(8, 8),
                  blurRadius: 0),
              BoxShadow(
                  color: Color(0xFF0A0804),
                  offset: Offset(6, 6),
                  blurRadius: 0,
                  spreadRadius: 1),
              BoxShadow(
                  color: Color(0xFF14100A),
                  offset: Offset(4, 4),
                  blurRadius: 0,
                  spreadRadius: 2),
              BoxShadow(
                  color: Color(0xFF1E1810),
                  offset: Offset(2, 2),
                  blurRadius: 0,
                  spreadRadius: 3),
              // Contorno exterior
              BoxShadow(
                  color: Color(0xFF100C06),
                  offset: Offset.zero,
                  blurRadius: 0,
                  spreadRadius: 5),
              BoxShadow(
                  color: Color(0xFF080604),
                  offset: Offset.zero,
                  blurRadius: 0,
                  spreadRadius: 8),
              // Sombra de profundidad
              BoxShadow(
                  color: Color(0xAA0A1420),
                  offset: Offset(0, 16),
                  blurRadius: 32),
              BoxShadow(
                  color: Color(0x550A1828),
                  offset: Offset(0, 28),
                  blurRadius: 48),
            ],
          ),
          child: Stack(
            children: [
              // Grid del tablero
              Padding(
                padding: const EdgeInsets.all(18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: child,
                ),
              ),
              // ── Ribete metálico superior (acero pulido)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 7,
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF3A2E14),
                        Color(0xFFB09050),
                        Color(0xFFE8D090),
                        Color(0xFFB09050),
                        Color(0xFF3A2E14),
                      ],
                      stops: [0.0, 0.2, 0.5, 0.8, 1.0],
                    ),
                  ),
                ),
              ),
              // ── Ribete metálico izquierdo
              Positioned(
                top: 7,
                left: 0,
                bottom: 0,
                width: 7,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFB09050),
                        Color(0xFF786030),
                        Color(0xFF3A2E14),
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // ── Ribete derecho (sombra)
              Positioned(
                top: 7,
                right: 0,
                bottom: 0,
                width: 7,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2A2010), Color(0xFF0A0806)],
                    ),
                  ),
                ),
              ),
              // ── Remaches metálicos en esquinas
              ..._rivets(),
              // ── Vignette interior (da profundidad)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const RadialGradient(
                        center: Alignment(0, 0),
                        radius: 1.4,
                        colors: [Color(0x00000000), Color(0x30000000)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Cara frontal del tablero (canto de madera/metal) ─
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          height: 64,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(3),
              bottomRight: Radius.circular(3),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF4A3818), // canto superior: madera expuesta, iluminada
                Color(0xFF2E2010), // cuerpo: madera en sombra
                Color(0xFF1A1208), // base: oscuro
                Color(0xFF0C0A06), // pie: casi negro
              ],
              stops: [0.0, 0.28, 0.65, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                  color: Color(0xBB061018),
                  offset: Offset(0, 14),
                  blurRadius: 28,
                  spreadRadius: 4),
              BoxShadow(
                  color: Color(0x770A1828),
                  offset: Offset(0, 28),
                  blurRadius: 48,
                  spreadRadius: 2),
              BoxShadow(
                  color: Color(0x440D2030),
                  offset: Offset(0, 42),
                  blurRadius: 60),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(3),
              bottomRight: Radius.circular(3),
            ),
            child: CustomPaint(painter: _WoodEdgePainter()),
          ),
        ),

        // ── Sombra proyectada en el océano ───────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          height: 26,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x550A1828), Color(0x00061525)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  // Pequeños remaches en las 4 esquinas
  static List<Widget> _rivets() {
    const positions = [
      (6.0, 6.0),
      (6.0, -6.0),
      (-6.0, 6.0),
      (-6.0, -6.0),
    ];
    return positions.map((pos) {
      final (dx, dy) = pos;
      final isTop = dy > 0;
      final isLeft = dx > 0;
      return Positioned(
        top: isTop ? 6 : null,
        bottom: !isTop ? 6 : null,
        left: isLeft ? 6 : null,
        right: !isLeft ? 6 : null,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.4, -0.4),
              radius: 0.8,
              colors: const [Color(0xFFD0A840), Color(0xFF806020)],
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x88000000),
                  offset: Offset(1, 1),
                  blurRadius: 2),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class _WoodEdgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;

    // Línea de ribete metálico en la cima del canto
    paint
      ..strokeWidth = 1.0
      ..color = const Color(0x70C8A040);
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), paint);

    // Vetas de madera horizontales
    final grains = [
      (0.20, const Color(0x30805028)),
      (0.38, const Color(0x25603818)),
      (0.55, const Color(0x1C502810)),
      (0.72, const Color(0x14402010)),
      (0.86, const Color(0x0E301808)),
    ];
    paint.strokeWidth = 0.6;
    for (final (frac, color) in grains) {
      paint.color = color;
      final y = size.height * frac;
      final path = Path()..moveTo(0, y);
      // Veta ligeramente ondulada
      for (double x = 0; x < size.width; x += 40) {
        path.cubicTo(x + 10, y - 0.8, x + 30, y + 0.8, x + 40, y);
      }
      canvas.drawPath(path, paint);
    }

    // Líneas verticales de unión de tablones
    paint
      ..strokeWidth = 0.7
      ..color = const Color(0x20100800);
    for (final xf in [0.20, 0.40, 0.60, 0.80]) {
      final x = size.width * xf;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      // Highlight del tablón
      paint.color = const Color(0x10806030);
      canvas.drawLine(Offset(x + 1, 0), Offset(x + 1, size.height), paint);
      paint.color = const Color(0x20100800);
    }
  }

  @override
  bool shouldRepaint(_WoodEdgePainter o) => false;
}

class _GridContent extends StatelessWidget {
  final GameConfig config;
  final BoardState boardState;
  final String? selectedCoord;
  final bool highlightEmpty;
  final Set<String> movableCoords;
  final String? obeliscoLocal;
  final Map<String, Color> playerColors;
  final String? localPlayerUid;
  final String? imagenMapa;
  final Function(String, int, int) onCellTap;

  const _GridContent({
    required this.config,
    required this.boardState,
    required this.selectedCoord,
    required this.highlightEmpty,
    this.movableCoords = const {},
    this.obeliscoLocal,
    this.playerColors = const {},
    this.localPlayerUid,
    this.imagenMapa,
    required this.onCellTap,
  });

  double get _gridW => config.cols * kCellW;
  double get _gridH => config.rows * kCellH;

  @override
  Widget build(BuildContext context) {
    // Filas de celdas transparentes
    final cellRows = List.generate(
        config.rows,
        (ri) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                rowLabelCell(config.rowLabels[ri]),
                ...List.generate(config.cols, (ci) {
                  final coord = config.coordLabel(ri, ci);
                  final celda = boardState.getCelda(coord);
                  return CellWidget(
                    ri: ri,
                    ci: ci,
                    config: config,
                    celda: celda,
                    isSelected: coord == selectedCoord,
                    isHighlighted: highlightEmpty && coord == obeliscoLocal,
                    isMovable: movableCoords.contains(coord),
                    isObelisco: coord == obeliscoLocal,
                    isRayo: boardState.esRayo(coord), // ← nuevo
                    isEnvenenada: boardState.celdaTieneVeneno(coord),
                    isParalizada: boardState.celdaTieneParalisis(coord),
                    isEscudada: boardState.celdaTieneEscudo(coord),
                    venenosCelda: boardState.venenosCelda(coord),
                    escudosCelda: boardState.escudosCelda(coord),
                    playerColors: playerColors,
                    localPlayerUid: localPlayerUid,
                    onTap: () => onCellTap(coord, ri, ci),
                  );
                }),
              ],
            ));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Etiquetas de columna
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            cornerCell(),
            ...List.generate(
                config.cols, (ci) => colLabelCell('${config.colLabels[ci]}')),
          ],
        ),
        // Grid: imagen única de fondo + celdas encima en un Stack
        SizedBox(
          width: kLabelW + _gridW,
          height: _gridH,
          child: Stack(
            children: [
              Positioned(
                left: kLabelW,
                top: 0,
                width: _gridW,
                height: _gridH,
                child: BoardBackgroundImage(imagen: imagenMapa),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: cellRows,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
