// lib/widgets/board_widget.dart

import 'package:flutter/material.dart';
import '../models/game_config.dart';
import '../models/board_state.dart';
import '../models/carta_model.dart';
import 'cell_widget.dart';
import '../services/settings_controller.dart';

/// Silueta fantasma de una carta que se movió este turno: recorre el camino de
/// su celda de ORIGEN a su celda de DESTINO (animación de revisión post-cierre).
typedef RevisionFantasma = ({
  String origen,
  String destino,
  Color color,
  IconData icon,
  Color iconColor,
  int movimiento,
  String nombre,
});

/// Imagen usada cuando el mapa no define una propia (campo `imagen` vacío).
const String kImagenTableroPorDefecto = 'assets/images/map_background.png';

/// Pinta la imagen de fondo del tablero a partir de la referencia del mapa.
/// Acepta URL http(s) (Image.network) o ruta de asset (Image.asset), y cae a
/// [kImagenTableroPorDefecto] si la referencia está vacía o falla la carga.
/// Se reutiliza en el preview del editor de mapas.
/// Pinta la imagen de fondo del tablero a partir de la referencia del mapa.
/// Acepta URL http(s) (Image.network) o ruta de asset (Image.asset), y cae a
/// [kImagenTableroPorDefecto] si la referencia está vacía o falla la carga.
/// Se reutiliza en el preview del editor de mapas.
class BoardBackgroundImage extends StatelessWidget {
  final String? imagen;
  final BoxFit fit;

  /// Calidad de muestreo al escalar la imagen.
  ///
  /// `medium` activa el filtrado trilineal (mipmaps), que es lo que elimina el
  /// "borroso" del lado lejano del tablero cuando la imagen se ve muy reducida
  /// por el zoom bajo (40 % en mapas de 8) + la perspectiva 3D. El valor por
  /// defecto de Flutter, `low`, usa bilineal sin mipmaps y produce ese
  /// aliasing/emborronamiento al minificar mucho.
  final FilterQuality filterQuality;

  const BoardBackgroundImage({
    super.key,
    required this.imagen,
    this.fit = BoxFit.fill,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  Widget build(BuildContext context) {
    final ref = (imagen ?? '').trim();

    if (ref.isEmpty) return _asset(kImagenTableroPorDefecto);

    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return Image.network(
        ref,
        fit: fit,
        filterQuality: filterQuality,
        // Si la URL falla (404, sin red…) no dejamos el tablero en blanco.
        errorBuilder: (_, __, ___) => _asset(kImagenTableroPorDefecto),
      );
    }
    return _asset(ref);
  }

  Widget _asset(String path) => Image.asset(
        path,
        fit: fit,
        filterQuality: filterQuality,
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

  /// Celdas donde el jugador puede desplegar la carta seleccionada de la
  /// mano (el cuartel para cartas normales; las celdas asentadas para las
  /// estáticas). Se resaltan en verde mientras haya carta seleccionada.
  final Set<String> deployCoords;

  /// Coordenadas de TODOS los obeliscos (de cualquier jugador), del servidor.
  final Set<String> obeliscoCoords;

  /// coord → color del dueño del obelisco. Colorea el cristal del cuartel
  /// (SpawnMarker) con el color de su jugador en vez de blanco.
  final Map<String, Color> obeliscoColores;

  /// uid → color del obelisco para colorear cartas
  final Map<String, Color> playerColors;

  /// uid del jugador local (para el +80 de defensa del cuartel en el preview).
  final String? localPlayerUid;

  /// uids aliados del jugador local (incluye su propio uid). Sirve para
  /// que una casilla compartida SOLO con aliados se pinte como pila
  /// amistosa y no como combate.
  final Set<String> aliadosLocal;

  /// Imagen de fondo del tablero para ESTE mapa. Puede ser:
  ///   - una URL http(s)  → se carga con Image.network
  ///   - una ruta de asset → se carga con Image.asset
  ///   - null / vacío      → se usa [kImagenTableroPorDefecto]
  /// Viene del campo `imagen` del documento del mapa en Firestore.
  final String? imagenMapa;

  /// coord → cartas de acción declaradas ahí, pendientes de resolverse al
  /// cerrar turno. Solo visión local (ver doc en CellWidget.fantasmas).
  final Map<String, List<CartaModel>> fantasmasAccion;

  /// REVISIÓN POST-CIERRE: mientras el turno cerrado se resuelve, se dibuja una
  /// SILUETA FANTASMA (copia tenue de la carta) en la celda de ORIGEN de cada
  /// unidad que moví, y un resaltado en las celdas objetivo de mis acciones.
  /// Vacío = no se pinta nada.
  final List<RevisionFantasma> fantasmasRevision;
  final Set<String> accionesRevision;

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
    this.deployCoords = const {},
    this.obeliscoCoords = const {},
    this.obeliscoColores = const {},
    this.playerColors = const {},
    this.localPlayerUid,
    this.aliadosLocal = const {},
    this.imagenMapa,
    this.onBackgroundTap,
    this.fantasmasAccion = const {},
    this.fantasmasRevision = const [],
    this.accionesRevision = const {},
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

  // Zoom mínimo ADAPTATIVO al tamaño del tablero: los mapas grandes (muchas
  // columnas, p. ej. 12×20) necesitan poder alejarse más para verse enteros.
  //   · 16+ columnas (6/8 jugadores, mapas anchos) → 0.20 (20%)
  //   · resto (2/4 jugadores)                      → 0.40 (40%)
  double get _minScale => widget.config.cols >= 16 ? 0.15 : 0.4;
  static const double _maxScale = 2.0;

  double get _logicalW => kLabelW + widget.config.cols * kCellW + 80;
  double get _logicalH => kLabelH + widget.config.rows * kCellH + 120;

  @override
  void initState() {
    super.initState();
    // Zoom INICIAL adaptativo: los mapas grandes (16+ columnas, p. ej. 12×20)
    // arrancan algo alejados (80%) para ver más tablero de un vistazo; el resto
    // arranca a 100%. Mismo umbral que _minScale.
    _scale = widget.config.cols >= 16 ? 0.4 : 1.0;
    _momentumCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_applyMomentum);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerBoard());
  }

  @override
  void didUpdateWidget(BoardWidget old) {
    super.didUpdateWidget(old);
    // Si cambian las dimensiones lógicas del tablero —al cargar el terreno del
    // mapa o al EXPANDIR la rejilla para que quepan los cuarteles/obeliscos que
    // llegan del servidor tras el primer render— el centrado calculado en
    // initState ya no sirve y los cuarteles quedan descolocados. Reaccionamos
    // SOLO al cambio de tamaño (no a otros rebuilds) para no pelear con el
    // paneo del usuario, y recolocamos.
    if (old.config.cols != widget.config.cols ||
        old.config.rows != widget.config.rows) {
      _centered = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerBoard());
    }
  }

  @override
  void dispose() {
    _momentumCtrl.dispose();
    super.dispose();
  }

  void _centerBoard() {
    if (_centered) return;
    final size = context.size;
    if (size == null) {
      // El tablero aún no tiene tamaño en este frame. En vez de abandonar el
      // centrado para siempre (lo que dejaba los cuarteles descolocados hasta
      // salir y reentrar), lo reintentamos en el siguiente frame.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _centerBoard());
      }
      return;
    }
    _centered = true;
    setState(() {
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
                    deployCoords: widget.deployCoords,
                    obeliscoCoords: widget.obeliscoCoords,
                    obeliscoColores: widget.obeliscoColores,
                    playerColors: widget.playerColors,
                    localPlayerUid: widget.localPlayerUid,
                    aliadosLocal: widget.aliadosLocal,
                    imagenMapa: widget.imagenMapa,
                    fantasmasAccion: widget.fantasmasAccion,
                    fantasmasRevision: widget.fantasmasRevision,
                    accionesRevision: widget.accionesRevision,
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

  /// Celdas donde el jugador puede desplegar la carta seleccionada de la
  /// mano (el cuartel para cartas normales; las celdas asentadas para las
  /// estáticas). Se resaltan en verde mientras haya carta seleccionada.
  final Set<String> deployCoords;
  final Set<String> obeliscoCoords;
  final Map<String, Color> obeliscoColores;
  final Map<String, Color> playerColors;
  final String? localPlayerUid;

  /// uids aliados del jugador local (incluye su propio uid). Sirve para
  /// que una casilla compartida SOLO con aliados se pinte como pila
  /// amistosa y no como combate.
  final Set<String> aliadosLocal;
  final String? imagenMapa;
  final Map<String, List<CartaModel>> fantasmasAccion;
  final List<RevisionFantasma> fantasmasRevision;
  final Set<String> accionesRevision;
  final Function(String, int, int) onCellTap;

  const _PerspectiveBoard({
    required this.config,
    required this.boardState,
    required this.selectedCoord,
    required this.highlightEmpty,
    this.movableCoords = const {},
    this.obeliscoLocal,
    this.deployCoords = const {},
    this.obeliscoCoords = const {},
    this.obeliscoColores = const {},
    this.playerColors = const {},
    this.localPlayerUid,
    this.aliadosLocal = const {},
    this.imagenMapa,
    this.fantasmasAccion = const {},
    this.fantasmasRevision = const [],
    this.accionesRevision = const {},
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    // El contenido real del tablero (marco de roca + rejilla + fichas).
    final Widget contenido = _RockFrame(
      child: _GridContent(
        config: config,
        boardState: boardState,
        selectedCoord: selectedCoord,
        highlightEmpty: highlightEmpty,
        movableCoords: movableCoords,
        obeliscoLocal: obeliscoLocal,
        deployCoords: deployCoords,
        obeliscoCoords: obeliscoCoords,
        obeliscoColores: obeliscoColores,
        playerColors: playerColors,
        localPlayerUid: localPlayerUid,
        aliadosLocal: aliadosLocal,
        imagenMapa: imagenMapa,
        fantasmasAccion: fantasmasAccion,
        fantasmasRevision: fantasmasRevision,
        accionesRevision: accionesRevision,
        onCellTap: onCellTap,
      ),
    );

    // El modo (3D vs plano) se lee del ajuste persistente y se actualiza en
    // vivo al cambiarlo desde Ajustes (settingsController es un ChangeNotifier).
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        // Ajuste desactivado -> tablero PLANO (cenital, de frente).
        if (!settingsController.tablero3D) return contenido;

        // Ajuste activado -> perspectiva 3D original.
        return Transform(
          alignment: Alignment.topCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0010)
            ..rotateX(-0.58),
          child: contenido,
        );
      },
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

  /// Celdas donde el jugador puede desplegar la carta seleccionada de la
  /// mano (el cuartel para cartas normales; las celdas asentadas para las
  /// estáticas). Se resaltan en verde mientras haya carta seleccionada.
  final Set<String> deployCoords;
  final Set<String> obeliscoCoords;
  final Map<String, Color> obeliscoColores;
  final Map<String, Color> playerColors;
  final String? localPlayerUid;

  /// uids aliados del jugador local (incluye su propio uid). Sirve para
  /// que una casilla compartida SOLO con aliados se pinte como pila
  /// amistosa y no como combate.
  final Set<String> aliadosLocal;
  final String? imagenMapa;
  final Map<String, List<CartaModel>> fantasmasAccion;
  final List<RevisionFantasma> fantasmasRevision;
  final Set<String> accionesRevision;
  final Function(String, int, int) onCellTap;

  const _GridContent({
    required this.config,
    required this.boardState,
    required this.selectedCoord,
    required this.highlightEmpty,
    this.movableCoords = const {},
    this.obeliscoLocal,
    this.deployCoords = const {},
    this.obeliscoCoords = const {},
    this.obeliscoColores = const {},
    this.playerColors = const {},
    this.localPlayerUid,
    this.aliadosLocal = const {},
    this.imagenMapa,
    this.fantasmasAccion = const {},
    this.fantasmasRevision = const [],
    this.accionesRevision = const {},
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
                  // Celda tal y como la ve el jugador local: las cartas
                  // invisibles del rival se ocultan (las propias se conservan y
                  // el CellWidget las pinta translúcidas).
                  final celda =
                      boardState.celdaVisiblePara(coord, localPlayerUid);
                  return CellWidget(
                    ri: ri,
                    ci: ci,
                    config: config,
                    celda: celda,
                    isSelected: coord == selectedCoord,
                    isHighlighted:
                        highlightEmpty && deployCoords.contains(coord),
                    isMovable: movableCoords.contains(coord),
                    isObelisco: coord == obeliscoLocal,
                    obeliscoCoords: obeliscoCoords,
                    obeliscoColores: obeliscoColores,
                    isConquistado: boardState.esCuartelDestruido(coord),
                    isRayo: boardState.esRayo(coord), // ← nuevo
                    isEnvenenada: boardState.celdaTieneVeneno(coord),
                    isParalizada: boardState.celdaTieneParalisis(coord),
                    isEscudada: boardState.celdaTieneEscudo(coord),
                    turnosVeneno: boardState.turnosVenenoCelda(coord),
                    turnosParalisis: boardState.turnosParalisisCelda(coord),
                    turnosEscudo: boardState.turnosEscudoCelda(coord),
                    venenosCelda: boardState.venenosCelda(coord),
                    escudosCelda: boardState.escudosCelda(coord),
                    playerColors: playerColors,
                    localPlayerUid: localPlayerUid,
                    aliadosLocal: aliadosLocal,
                    fantasmas: fantasmasAccion[coord] ?? const [],
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
              // Capa de REVISIÓN post-cierre: silueta fantasma de cada carta en
              // su celda de origen + resaltado de celdas objetivo de acciones.
              // Va encima de las celdas (hereda la misma perspectiva 3D). No
              // intercepta toques.
              if (fantasmasRevision.isNotEmpty || accionesRevision.isNotEmpty)
                Positioned.fill(
                  child: _RevisionLayer(
                    config: config,
                    fantasmas: fantasmasRevision,
                    acciones: accionesRevision,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CAPA DE REVISIÓN (post-cierre de turno)
// ─────────────────────────────────────────────────────────────

/// Capa que se superpone a la rejilla mientras el turno cerrado se resuelve:
///   · Una SILUETA FANTASMA (copia tenue de la carta) en la celda de ORIGEN de
///     cada unidad que moví este turno -así se ve "de dónde viene".
///   · Un anillo luminoso en las celdas objetivo de mis acciones/habilidades.
/// Va DENTRO del Stack de la rejilla, por lo que hereda la misma perspectiva 3D
/// que las celdas y queda perfectamente alineada. No intercepta toques.
class _RevisionLayer extends StatefulWidget {
  final GameConfig config;
  final List<RevisionFantasma> fantasmas;
  final Set<String> acciones;

  const _RevisionLayer({
    required this.config,
    required this.fantasmas,
    required this.acciones,
  });

  @override
  State<_RevisionLayer> createState() => _RevisionLayerState();
}

class _RevisionLayerState extends State<_RevisionLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Bucle continuo: cada ciclo la silueta aparece en el origen, se desliza al
    // destino y se desvanece al llegar a la carta real.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Rectángulo (en el espacio de la rejilla) de la celda [coord].
  Rect? _rectFor(String coord) {
    for (int ri = 0; ri < widget.config.rows; ri++) {
      for (int ci = 0; ci < widget.config.cols; ci++) {
        if (widget.config.coordLabel(ri, ci) == coord) {
          return Rect.fromLTWH(
            kLabelW + ci * kCellW,
            ri * kCellH,
            kCellW,
            kCellH,
          );
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // Anillos de acción (estáticos, debajo de las siluetas).
    for (final coord in widget.acciones) {
      final r = _rectFor(coord);
      if (r == null) continue;
      children.add(Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height,
        child: const Center(child: _AccionRing()),
      ));
    }

    // Marcador tenue fijo en la celda de ORIGEN, para que el punto de partida
    // siga visible aunque la silueta esté a medio camino.
    for (final f in widget.fantasmas) {
      final r = _rectFor(f.origen);
      if (r == null) continue;
      children.add(Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height,
        child: Center(child: _GhostOrigenMarker(color: f.color)),
      ));
    }

    // Siluetas ANIMADAS recorriendo origen→destino.
    children.add(Positioned.fill(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final movers = <Widget>[];
          final raw = _ctrl.value;
          // Posición: reposa un poco en el origen, se desliza, y reposa en el
          // destino. Opacidad: entra al principio y se desvanece al final.
          final posT = const Interval(0.12, 0.86, curve: Curves.easeInOutCubic)
              .transform(raw);
          double op;
          if (raw < 0.14) {
            op = raw / 0.14;
          } else if (raw > 0.80) {
            op = (1 - raw) / 0.20;
          } else {
            op = 1;
          }
          op = op.clamp(0.0, 1.0);

          for (final f in widget.fantasmas) {
            final ro = _rectFor(f.origen);
            final rd = _rectFor(f.destino);
            if (ro == null || rd == null) continue;
            final pos = Offset.lerp(ro.center, rd.center, posT)!;
            movers.add(Positioned(
              left: pos.dx - kCellW / 2,
              top: pos.dy - kCellH / 2,
              width: kCellW,
              height: kCellH,
              child: Center(child: _GhostToken(fantasma: f, opacityFactor: op)),
            ));
          }
          return Stack(children: movers);
        },
      ),
    ));

    return IgnorePointer(child: Stack(children: children));
  }
}

/// Pequeño marcador tenue en la celda de origen (aro hueco), para anclar el
/// punto de partida mientras la silueta viaja.
class _GhostOrigenMarker extends StatelessWidget {
  final Color color;
  const _GhostOrigenMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    final d = (kCellW < kCellH ? kCellW : kCellH) * 0.34;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.55), width: 1.5),
      ),
    );
  }
}

/// Copia tenue del token de la carta en su celda de origen. Reproduce el mismo
/// lenguaje visual que el token real (icono de tipo + movimiento + nombre) pero
/// atenuado y con borde punteado, para que se lea claramente como "fantasma".
class _GhostToken extends StatelessWidget {
  final RevisionFantasma fantasma;

  /// Factor de opacidad (0..1) que aplica la animación al recorrer el camino.
  final double opacityFactor;
  const _GhostToken({required this.fantasma, this.opacityFactor = 1.0});

  @override
  Widget build(BuildContext context) {
    final color = fantasma.color;
    return Opacity(
      opacity: (0.82 * opacityFactor).clamp(0.0, 1.0),
      child: SizedBox(
        width: kCellW * 0.70,
        child: Stack(
          children: [
            // Borde punteado + fondo translúcido.
            Positioned.fill(
              child: CustomPaint(
                painter: _GhostBorderPainter(color.withOpacity(0.85)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(fantasma.icon,
                          size: 10, color: fantasma.iconColor.withOpacity(0.9)),
                      const SizedBox(width: 3),
                      Text(
                        '${fantasma.movimiento}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontFamily: 'Cinzel',
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    fantasma.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 6,
                      color: color.withOpacity(0.85),
                      fontFamily: 'Cinzel',
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anillo luminoso para las celdas objetivo de una acción/habilidad.
class _AccionRing extends StatelessWidget {
  const _AccionRing();

  static const Color _c = Color(0xFF40C0FF);

  @override
  Widget build(BuildContext context) {
    final d = (kCellW < kCellH ? kCellW : kCellH) * 0.52;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _c.withOpacity(0.12),
        border: Border.all(color: _c, width: 2),
        boxShadow: [
          BoxShadow(color: _c.withOpacity(0.40), blurRadius: 8),
        ],
      ),
      child: const Icon(Icons.flash_on, size: 15, color: _c),
    );
  }
}

/// Borde punteado redondeado + relleno translúcido para la silueta fantasma.
class _GhostBorderPainter extends CustomPainter {
  final Color color;
  const _GhostBorderPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));

    // Fondo translúcido oscuro.
    canvas.drawRRect(rrect, Paint()..color = const Color(0xCC060C14));

    // Borde punteado.
    final path = Path()..addRRect(rrect);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    const dashLen = 4.0, gapLen = 3.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final end = (dist + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), dash);
        dist += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_GhostBorderPainter old) => old.color != color;
}
