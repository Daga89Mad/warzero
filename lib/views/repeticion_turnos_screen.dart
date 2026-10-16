// lib/views/repeticion_turnos_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/game_config.dart';
import '../services/settings_controller.dart';
import '../widgets/cell_widget.dart' show ownerColor;

// Colores de RESULTADO de combate (lenguaje del juego, fijos en cualquier tema).
const _cGanado = Color(0xFF4ABB58);
const _cPerdido = Color(0xFFC04040);
const _cOtros = Color(0xFFE0C040);

// Fases de la animación (fracción del controlador 0..1).
const double _finMovimiento = 0.55; // las fichas llegan a su destino
const double _inicioCombate = 0.50; // se encienden las casillas de combate
const double _finCombate = 0.75;
const double _inicioBajas = 0.70; // se apagan las fichas derrotadas
const double _finBajas = 0.95;

/// Repetición animada de uno de los últimos turnos resueltos (los que guarda el
/// servidor en `historialCombates`, hasta 5).
///
/// Muestra las cartas de TODOS los jugadores desplazándose de su celda de
/// origen a la de destino y, a continuación, colorea las casillas donde hubo
/// combate:
///   - verde    → combate que gané,
///   - rojo     → combate que perdí,
///   - amarillo → combate entre otros jugadores.
///
/// Respeta lo que ya oculta el servidor en `movimientosLog`: las cartas dentro
/// del cuartel de su dueño y las cartas invisibles no aparecen.
///
/// Rendimiento: no hace ninguna lectura extra (usa el historial que ya llega
/// por el stream de la partida) y todo el tablero se pinta en un único
/// CustomPainter que repinta con el AnimationController, sin reconstruir
/// widgets en cada frame.
class RepeticionTurnosScreen extends StatefulWidget {
  final GameConfig config;

  /// Entradas de `historialCombates` (orden indiferente).
  final List<Map<String, dynamic>> historial;
  final String localUid;
  final Map<String, Color> playerColors;

  /// uid → coord del cuartel de cada jugador.
  final Map<String, String> obeliscosPorJugador;

  /// uid → alias, para el detalle de celda.
  final Map<String, String> aliasPorUid;

  /// Turno que se abre al entrar (por defecto, el más reciente).
  final int? turnoInicial;

  const RepeticionTurnosScreen({
    super.key,
    required this.config,
    required this.historial,
    required this.localUid,
    this.playerColors = const {},
    this.obeliscosPorJugador = const {},
    this.aliasPorUid = const {},
    this.turnoInicial,
  });

  @override
  State<RepeticionTurnosScreen> createState() => _RepeticionTurnosScreenState();
}

class _RepeticionTurnosScreenState extends State<RepeticionTurnosScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_TurnoRepeticion> _turnos;
  late final Map<String, (int, int)> _posPorCoord;
  int _indice = 0;

  @override
  void initState() {
    super.initState();
    _posPorCoord = {
      for (int r = 0; r < widget.config.rows; r++)
        for (int c = 0; c < widget.config.cols; c++)
          widget.config.coordLabel(r, c): (r, c),
    };
    _turnos = widget.historial
        .map((h) => _TurnoRepeticion.fromEntry(h, widget.localUid))
        .where((t) => t.turno > 0)
        .toList()
      ..sort((a, b) => a.turno.compareTo(b.turno));

    _indice = _turnos.isEmpty ? 0 : _turnos.length - 1;
    final ini = widget.turnoInicial;
    if (ini != null) {
      final i = _turnos.indexWhere((t) => t.turno == ini);
      if (i >= 0) _indice = i;
    }

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener((_) {
        if (mounted) setState(() {}); // icono play/pausa
      });
    if (_turnos.isNotEmpty) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _seleccionarTurno(int i) {
    if (i == _indice) {
      _ctrl.forward(from: 0);
      return;
    }
    setState(() => _indice = i);
    _ctrl.forward(from: 0);
  }

  void _playPausa() {
    if (_ctrl.isAnimating) {
      _ctrl.stop();
    } else if (_ctrl.value >= 1.0) {
      _ctrl.forward(from: 0);
    } else {
      _ctrl.forward();
    }
    setState(() {});
  }

  String _alias(String uid) {
    if (uid == widget.localUid) return 'Tú';
    final a = widget.aliasPorUid[uid];
    return (a == null || a.isEmpty) ? 'Rival' : a;
  }

  Color _colorJugador(String uid, String zona) =>
      widget.playerColors[uid] ?? ownerColor(zona);

  // ── Detalle de celda ─────────────────────────────────────────

  void _mostrarDetalle(String coord) {
    if (_turnos.isEmpty) return;
    final t = _turnos[_indice];
    final combate = t.combates[coord];
    final llegadas = t.fichas.where((f) => f.hasta == coord).toList();
    final salidas =
        t.fichas.where((f) => f.desde == coord && f.hasta != coord).toList();
    if (combate == null && llegadas.isEmpty && salidas.isEmpty) return;

    final war = context.war;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: war.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        final filas = <Widget>[];
        if (combate != null) {
          final color = combate.color;
          final titulo = switch (combate.resultado) {
            _Resultado.ganado => 'Combate ganado',
            _Resultado.perdido => 'Combate perdido',
            _Resultado.otros => 'Combate entre otros jugadores',
          };
          final ganador = combate.ganadorUid == null
              ? 'Sin ganador'
              : 'Gana ${_alias(combate.ganadorUid!)}';
          final derrotados = combate.derrotados.isEmpty
              ? ''
              : ' · Caen: ${combate.derrotados.map(_alias).join(', ')}';
          filas.add(_FilaDetalle(
            icono: Icons.flash_on,
            color: color,
            titulo: titulo,
            detalle: '$ganador$derrotados'
                '${combate.conquista ? '\nEl cuartel cambió de manos.' : ''}',
          ));
        }
        for (final f in llegadas) {
          final origen = f.desdeMano
              ? 'jugada desde la mano'
              : (f.desde != null ? 'desde ${f.desde}' : 'se mantuvo aquí');
          filas.add(_FilaDetalle(
            icono: Icons.style,
            color: _colorJugador(f.uid, f.zona),
            titulo: f.nombre.isEmpty ? 'Carta' : f.nombre,
            detalle: '${_alias(f.uid)} · $origen',
          ));
        }
        for (final f in salidas) {
          filas.add(_FilaDetalle(
            icono: Icons.north_east,
            color: _colorJugador(f.uid, f.zona),
            titulo: f.nombre.isEmpty ? 'Carta' : f.nombre,
            detalle: '${_alias(f.uid)} · salió hacia ${f.hasta}',
          ));
        }
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.55,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                Text(
                  'CASILLA $coord · TURNO ${t.turno}',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: war.primario,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                ...filas,
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      body: SafeArea(
        child: Column(
          children: [
            _Cabecera(onCerrar: () => Navigator.of(context).pop()),
            if (_turnos.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Aún no hay turnos resueltos que repetir',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      color: war.textoTenue,
                    ),
                  ),
                ),
              )
            else ...[
              _SelectorTurnos(
                turnos: _turnos.map((t) => t.turno).toList(),
                seleccionado: _indice,
                onSeleccionar: _seleccionarTurno,
              ),
              const _Leyenda(),
              Expanded(child: _tablero()),
              _Controles(
                ctrl: _ctrl,
                onPlayPausa: _playPausa,
                onRepetir: () => _ctrl.forward(from: 0),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tablero() {
    final war = context.war;
    final config = widget.config;
    final turno = _turnos[_indice];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          const gutter = 18.0;
          final cellW = (constraints.maxWidth - gutter) / config.cols;
          final cellH = (constraints.maxHeight - gutter) / config.rows;
          final cell = math.max(4.0, math.min(cellW, cellH));
          final size = Size(
            gutter + cell * config.cols,
            gutter + cell * config.rows,
          );
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 6.0,
            boundaryMargin: const EdgeInsets.all(120),
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final p = d.localPosition - const Offset(gutter, gutter);
                  if (p.dx < 0 || p.dy < 0) return;
                  final c = p.dx ~/ cell;
                  final r = p.dy ~/ cell;
                  if (r >= config.rows || c >= config.cols) return;
                  _mostrarDetalle(config.coordLabel(r, c));
                },
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: _RepeticionPainter(
                      progreso: _ctrl,
                      config: config,
                      turno: turno,
                      posPorCoord: _posPorCoord,
                      cell: cell,
                      gutter: gutter,
                      localUid: widget.localUid,
                      colorDe: _colorJugador,
                      obeliscosPorJugador: widget.obeliscosPorJugador,
                      superficie: war.superficie,
                      borde: war.borde,
                      textoTenue: war.textoTenue,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODELO DE LA REPETICIÓN (parseo de una entrada del historial)
// ─────────────────────────────────────────────────────────────

enum _Resultado { ganado, perdido, otros }

class _Ficha {
  final String uid;
  final String zona;
  final String nombre;

  /// Celda de origen si la carta se movió este turno; null si no se movió o
  /// si el dato no existe (turnos resueltos antes de sellar `origenTurno`).
  final String? desde;
  final String hasta;
  final bool desdeMano;

  /// Posición de la ficha dentro de su celda de destino (para no solaparlas).
  int slot = 0;
  int slotsEnCelda = 1;

  _Ficha({
    required this.uid,
    required this.zona,
    required this.nombre,
    required this.desde,
    required this.hasta,
    required this.desdeMano,
  });
}

class _Combate {
  final String coord;
  final String? ganadorUid;
  final List<String> derrotados;
  final _Resultado resultado;
  final bool conquista;

  _Combate({
    required this.coord,
    required this.ganadorUid,
    required this.derrotados,
    required this.resultado,
    required this.conquista,
  });

  Color get color => switch (resultado) {
        _Resultado.ganado => _cGanado,
        _Resultado.perdido => _cPerdido,
        _Resultado.otros => _cOtros,
      };
}

class _TurnoRepeticion {
  final int turno;
  final List<_Ficha> fichas;
  final Map<String, _Combate> combates;

  _TurnoRepeticion(this.turno, this.fichas, this.combates);

  factory _TurnoRepeticion.fromEntry(Map<String, dynamic> e, String localUid) {
    final turno = (e['turno'] as num?)?.toInt() ?? 0;

    // ── Fichas (movimientosLog: uid → celdas{coord: [cartas]}) ──
    final fichas = <_Ficha>[];
    for (final raw in (e['movimientosLog'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final mov = Map<String, dynamic>.from(raw);
      final uid = mov['uid'] as String? ?? '';
      final zonaMov = mov['zona'] as String? ?? '';
      final celdas = mov['celdas'];
      if (celdas is! Map) continue;
      celdas.forEach((coord, cartas) {
        if (coord is! String || cartas is! List) return;
        for (final c in cartas) {
          if (c is! Map) continue;
          final origen = c['origenTurno'];
          final desde =
              (origen is String && origen.isNotEmpty && origen != coord)
                  ? origen
                  : null;
          fichas.add(_Ficha(
            uid: (c['ownerUid'] as String?)?.isNotEmpty == true
                ? c['ownerUid'] as String
                : uid,
            zona: (c['ownerZone'] as String?)?.isNotEmpty == true
                ? c['ownerZone'] as String
                : zonaMov,
            nombre: (c['Nombre'] ?? c['nombre'] ?? '').toString(),
            desde: desde,
            hasta: coord,
            desdeMano: c['desdeMano'] == true,
          ));
        }
      });
    }
    // Reparto de huecos dentro de cada celda de destino.
    final porCelda = <String, List<_Ficha>>{};
    for (final f in fichas) {
      porCelda.putIfAbsent(f.hasta, () => []).add(f);
    }
    for (final lista in porCelda.values) {
      for (int i = 0; i < lista.length; i++) {
        lista[i]
          ..slot = i
          ..slotsEnCelda = lista.length;
      }
    }

    // ── Combates (combateLog) ──
    final conquistas = <String>{};
    for (final raw in (e['conquistasLog'] as List? ?? const [])) {
      if (raw is Map && raw['coord'] is String) {
        conquistas.add(raw['coord'] as String);
      }
    }
    final combates = <String, _Combate>{};
    for (final raw in (e['combateLog'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final coord = raw['coord'] as String? ?? '';
      if (coord.isEmpty) continue;
      final ganador = raw['ganadorUid'] as String?;
      final derrotados = (raw['derrotadosUid'] as List? ?? const [])
          .whereType<String>()
          .toList();
      final _Resultado res;
      if (ganador != null && ganador == localUid) {
        res = _Resultado.ganado;
      } else if (derrotados.contains(localUid)) {
        res = _Resultado.perdido;
      } else {
        res = _Resultado.otros;
      }
      combates[coord] = _Combate(
        coord: coord,
        ganadorUid: (ganador == null || ganador.isEmpty) ? null : ganador,
        derrotados: derrotados,
        resultado: res,
        conquista: raw['esConquistaObelisco'] == true ||
            conquistas.contains(coord),
      );
    }
    // Conquistas sin entrada en combateLog (por si acaso).
    for (final c in conquistas) {
      combates.putIfAbsent(
        c,
        () => _Combate(
          coord: c,
          ganadorUid: null,
          derrotados: const [],
          resultado: _Resultado.otros,
          conquista: true,
        ),
      );
    }

    return _TurnoRepeticion(turno, fichas, combates);
  }
}

// ─────────────────────────────────────────────────────────────
// PAINTER (todo el tablero en una sola pasada por frame)
// ─────────────────────────────────────────────────────────────

class _RepeticionPainter extends CustomPainter {
  final Animation<double> progreso;
  final GameConfig config;
  final _TurnoRepeticion turno;
  final Map<String, (int, int)> posPorCoord;
  final double cell;
  final double gutter;
  final String localUid;
  final Color Function(String uid, String zona) colorDe;
  final Map<String, String> obeliscosPorJugador;
  final Color superficie;
  final Color borde;
  final Color textoTenue;

  // Etiquetas de filas/columnas: se maquetan una vez y se reutilizan.
  List<TextPainter>? _etiquetasCol;
  List<TextPainter>? _etiquetasFila;

  _RepeticionPainter({
    required this.progreso,
    required this.config,
    required this.turno,
    required this.posPorCoord,
    required this.cell,
    required this.gutter,
    required this.localUid,
    required this.colorDe,
    required this.obeliscosPorJugador,
    required this.superficie,
    required this.borde,
    required this.textoTenue,
  }) : super(repaint: progreso);

  Offset? _centro(String coord) {
    final p = posPorCoord[coord];
    if (p == null) return null;
    return Offset(
      gutter + (p.$2 + 0.5) * cell,
      gutter + (p.$1 + 0.5) * cell,
    );
  }

  /// Desplazamiento de un hueco dentro de la celda (rejilla k×k, máx 3×3).
  Offset _offsetSlot(int slot, int total) {
    if (total <= 1) return Offset.zero;
    final k = math.min(3, (math.sqrt(total)).ceil());
    final s = slot % (k * k);
    final fila = s ~/ k;
    final col = s % k;
    final paso = cell / (k + 0.6);
    final mitad = (k - 1) / 2;
    return Offset((col - mitad) * paso, (fila - mitad) * paso);
  }

  double _tramo(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  TextPainter _texto(String s) => TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 8,
            color: textoTenue,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final t = progreso.value;

    // ── Etiquetas ──
    _etiquetasCol ??= [for (final c in config.colLabels) _texto('$c')];
    _etiquetasFila ??= [for (final r in config.rowLabels) _texto(r)];
    for (int c = 0; c < config.cols; c++) {
      final tp = _etiquetasCol![c];
      tp.paint(
        canvas,
        Offset(gutter + (c + 0.5) * cell - tp.width / 2,
            (gutter - tp.height) / 2),
      );
    }
    for (int r = 0; r < config.rows; r++) {
      final tp = _etiquetasFila![r];
      tp.paint(
        canvas,
        Offset((gutter - tp.width) / 2,
            gutter + (r + 0.5) * cell - tp.height / 2),
      );
    }

    // ── Celdas base ──
    final fondo = Paint()..color = superficie;
    final linea = Paint()
      ..color = borde.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int r = 0; r < config.rows; r++) {
      for (int c = 0; c < config.cols; c++) {
        final rect = Rect.fromLTWH(
            gutter + c * cell, gutter + r * cell, cell, cell).deflate(0.5);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2));
        canvas.drawRRect(rr, fondo);
        canvas.drawRRect(rr, linea);
      }
    }

    // ── Cuarteles (tinte del color de su dueño) ──
    obeliscosPorJugador.forEach((uid, coord) {
      final centro = _centro(coord);
      if (centro == null) return;
      final color = colorDe(uid, '');
      final rect = Rect.fromCenter(
              center: centro, width: cell, height: cell)
          .deflate(1);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rr, Paint()..color = color.withOpacity(0.16));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = color.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      _dibujarCastillo(canvas, centro, cell * 0.22, color.withOpacity(0.7));
    });

    // ── Combates (aparecen tras el movimiento) ──
    final aCombate = Curves.easeOut.transform(
        _tramo(t, _inicioCombate, _finCombate));
    if (aCombate > 0) {
      for (final cb in turno.combates.values) {
        final centro = _centro(cb.coord);
        if (centro == null) continue;
        final rect = Rect.fromCenter(
                center: centro, width: cell, height: cell)
            .deflate(1);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        // Destello al encenderse que se asienta en un tinte fijo.
        final destello = math.sin(aCombate * math.pi) * 0.25;
        canvas.drawRRect(
          rr,
          Paint()..color = cb.color.withOpacity((0.28 + destello) * aCombate),
        );
        canvas.drawRRect(
          rr.inflate(1.5 * aCombate),
          Paint()
            ..color = cb.color.withOpacity(0.45 * aCombate)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawRRect(
          rr,
          Paint()
            ..color = cb.color.withOpacity(aCombate)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        if (cb.conquista) {
          _dibujarCastillo(
              canvas, centro, cell * 0.26, cb.color.withOpacity(aCombate));
        }
      }
    }

    // ── Fichas ──
    final aMov = Curves.easeInOutCubic
        .transform(_tramo(t, 0.0, _finMovimiento));
    final aBajas = _tramo(t, _inicioBajas, _finBajas);
    final radioBase = cell * 0.13;

    // Estelas primero, para que queden por debajo de las fichas.
    for (final f in turno.fichas) {
      if (f.desde == null) continue;
      final ori = _centro(f.desde!);
      final dst = _centro(f.hasta);
      if (ori == null || dst == null) continue;
      final off = _offsetSlot(f.slot, f.slotsEnCelda);
      final a = ori + off;
      final b = dst + off;
      final actual = Offset.lerp(a, b, aMov)!;
      final color = colorDe(f.uid, f.zona);
      canvas.drawLine(
        a,
        actual,
        Paint()
          ..color = color.withOpacity(0.45)
          ..strokeWidth = math.max(1.0, cell * 0.04)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(a, radioBase * 0.45, Paint()..color = color.withOpacity(0.5));
    }

    for (final f in turno.fichas) {
      final dst = _centro(f.hasta);
      if (dst == null) continue;
      final off = _offsetSlot(f.slot, f.slotsEnCelda);
      final k = math.min(3, math.sqrt(f.slotsEnCelda).ceil());
      final radio = k <= 1 ? radioBase * 1.3 : (k == 2 ? radioBase : radioBase * 0.8);

      Offset pos = dst + off;
      double opacidad = 1.0;
      double escala = 1.0;
      if (f.desde != null) {
        final ori = _centro(f.desde!);
        if (ori != null) pos = Offset.lerp(ori + off, dst + off, aMov)!;
      } else if (f.desdeMano) {
        // Cartas recién jugadas: aparecen con un fundido en su destino.
        final aparicion = Curves.easeOutBack
            .transform(_tramo(t, _finMovimiento * 0.5, _finMovimiento));
        escala = aparicion;
        opacidad = aparicion.clamp(0.0, 1.0);
      }

      // Derrotadas en el combate de su celda: se apagan al final.
      final cb = turno.combates[f.hasta];
      final caida = cb != null && cb.derrotados.contains(f.uid);
      if (caida) opacidad *= 1.0 - 0.8 * aBajas;
      if (opacidad <= 0.01 || escala <= 0.01) continue;

      final color = colorDe(f.uid, f.zona);
      final r = radio * escala;
      canvas.drawCircle(pos, r, Paint()..color = color.withOpacity(opacidad));
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = (f.uid == localUid ? Colors.white : Colors.black)
              .withOpacity(0.6 * opacidad)
          ..style = PaintingStyle.stroke
          ..strokeWidth = f.uid == localUid ? 1.2 : 0.6,
      );
      if (caida && aBajas > 0) {
        final x = Paint()
          ..color = Colors.white.withOpacity(0.85 * aBajas)
          ..strokeWidth = math.max(1.0, r * 0.25)
          ..strokeCap = StrokeCap.round;
        final d = r * 0.55;
        canvas.drawLine(pos + Offset(-d, -d), pos + Offset(d, d), x);
        canvas.drawLine(pos + Offset(d, -d), pos + Offset(-d, d), x);
      }
    }
  }

  void _dibujarCastillo(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()..color = color;
    final base = Rect.fromCenter(
        center: c + Offset(0, s * 0.25), width: s * 1.6, height: s);
    canvas.drawRect(base, p);
    final almena = s * 0.4;
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(base.left + i * (base.width - almena) / 2,
            base.top - almena, almena, almena),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_RepeticionPainter old) =>
      old.turno != turno ||
      old.cell != cell ||
      old.superficie != superficie ||
      old.borde != borde;
}

// ─────────────────────────────────────────────────────────────
// CABECERA
// ─────────────────────────────────────────────────────────────

class _Cabecera extends StatelessWidget {
  final VoidCallback onCerrar;
  const _Cabecera({required this.onCerrar});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: war.borde.withOpacity(0.5), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TURNOS ANTERIORES',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: war.primario,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Movimientos de todos los jugadores',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: war.textoTenue,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onCerrar,
            icon: Icon(Icons.close, color: war.primario, size: 20),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SELECTOR DE TURNO
// ─────────────────────────────────────────────────────────────

class _SelectorTurnos extends StatelessWidget {
  final List<int> turnos;
  final int seleccionado;
  final ValueChanged<int> onSeleccionar;

  const _SelectorTurnos({
    required this.turnos,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return SizedBox(
      height: 44,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (int i = 0; i < turnos.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => onSeleccionar(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: i == seleccionado
                            ? war.primario.withOpacity(0.18)
                            : war.superficie,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: i == seleccionado
                              ? war.primario
                              : war.borde.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'TURNO ${turnos[i]}',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: i == seleccionado
                              ? war.primario
                              : war.textoTenue,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LEYENDA
// ─────────────────────────────────────────────────────────────

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    Widget chip(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color.withOpacity(0.35),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: color, width: 1.4),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7.5,
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Column(
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              chip(_cGanado, 'GANADO'),
              chip(_cPerdido, 'PERDIDO'),
              chip(_cOtros, 'OTROS JUGADORES'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Toca una casilla para ver el detalle · pellizca para ampliar',
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 7.5,
              color: war.textoTenue,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CONTROLES (play/pausa, repetir, barra de progreso)
// ─────────────────────────────────────────────────────────────

class _Controles extends StatelessWidget {
  final AnimationController ctrl;
  final VoidCallback onPlayPausa;
  final VoidCallback onRepetir;

  const _Controles({
    required this.ctrl,
    required this.onPlayPausa,
    required this.onRepetir,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: war.borde.withOpacity(0.5), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: ctrl.isAnimating ? 'Pausa' : 'Reproducir',
            onPressed: onPlayPausa,
            icon: Icon(
              ctrl.isAnimating ? Icons.pause : Icons.play_arrow,
              color: war.primario,
            ),
          ),
          IconButton(
            tooltip: 'Repetir',
            onPressed: onRepetir,
            icon: Icon(Icons.replay, color: war.primario),
          ),
          Expanded(
            // Solo la barra escucha al controlador: el resto de la pantalla no
            // se reconstruye durante la animación.
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (_, __) => SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: ctrl.value,
                  activeColor: war.primario,
                  inactiveColor: war.borde.withOpacity(0.4),
                  onChangeStart: (_) => ctrl.stop(),
                  onChanged: (v) => ctrl.value = v,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FILA DEL DETALLE DE CELDA
// ─────────────────────────────────────────────────────────────

class _FilaDetalle extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String detalle;

  const _FilaDetalle({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withOpacity(0.7), width: 1),
            ),
            child: Icon(icono, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: war.texto,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 11, color: war.textoTenue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
