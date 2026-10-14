// lib/views/duelos/duelos_partida_screen.dart
//
// MODO DUELOS — campo de batalla.
//
// Reutiliza el tablero de las partidas normales (BoardWidget: terreno e imagen
// del mapa, cartas, efectos de casilla, casillas resaltadas y la silueta que
// recorre el camino de cada carta que se mueve) y el mismo flujo de órdenes:
//   · Toca una casilla → panel con sus cartas → MOVER / HABILIDAD → toca la
//     casilla destino u objetivo resaltada.
//   · Barra inferior: habilidad del EJÉRCITO (una vez por partida), DISPARO
//     lejano y FIN DE TURNO (con la cuenta atrás en modo rápida).
//
// Todo lo que se ofrece sale de la vista del servidor (`alcanzables`,
// `alcanzablesExtra`, objetivos de cada habilidad…), que es quien valida la
// jugada, así que la app no repite las reglas del motor. El Comandante rival
// nunca viene en la vista.
//
// Tiempo de turno: igual que las partidas normales (rápida 30 s, diario a las
// 00:00 UTC o cada 12 h). Si no pulsas FIN DE TURNO a tiempo, el turno se
// cierra SIN MOVER; con 3 seguidos pierdes el duelo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:warzero/services/settings_controller.dart';

import '../../models/board_state.dart';
import '../../models/carta_model.dart';
import '../../models/efecto_estado.dart';
import '../../models/game_config.dart';
import '../../models/lobby_model.dart' show ModoTurno;
import '../../services/duelos_service.dart';
import '../../services/mapa_service.dart';
import '../../widgets/board_widget.dart';
import 'duelos_lobby_screen.dart';

/// Color del rival en el tablero.
const Color _kRival = Color(0xFFD05050);

/// Qué está esperando el tablero al tocar una casilla.
enum _Modo { ninguno, mover, habCelda, habCartaCelda, muro, disparo }

/// Orden de habilidad de un general para este turno.
class _OrdenHab {
  final List<String> celdas;
  final int cartaId;
  const _OrdenHab({this.celdas = const [], this.cartaId = -1});
}

class DuelosPartidaScreen extends StatefulWidget {
  final String salaId;
  final String uid;

  const DuelosPartidaScreen({
    super.key,
    required this.salaId,
    required this.uid,
  });

  @override
  State<DuelosPartidaScreen> createState() => _DuelosPartidaScreenState();
}

class _DuelosPartidaScreenState extends State<DuelosPartidaScreen> {
  final _service = DuelosService();

  DuelosSala? _sala;
  _VistaPartida? _vista;
  String? _error;
  bool _cargando = false;
  bool _enviando = false;
  bool _rindiendo = false;

  Timer? _sondeo;
  Duration? _intervaloSondeo;
  Timer? _reloj;
  DateTime _ultimoSondeoForzado = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Mapa y catálogo ──
  bool _mapaPedido = false;
  Map<String, TerrainType> _terrenoMapa = const {};
  String? _imagenMapa;
  Map<String, String> _imagenes = const {}; // cartaId → imagen

  // ── Órdenes del turno [_turnoOrdenes] ──
  int _turnoOrdenes = 0;
  final Map<int, String> _movs = {}; // carta → destino
  final Map<int, _OrdenHab> _habs = {}; // general → habilidad
  final List<String> _disparos = [];
  bool _usarEjercito = false;
  int _ejercitoCarta = -1;

  // ── Interacción ──
  _Modo _modo = _Modo.ninguno;
  int? _cartaActiva; // carta que se mueve o general que lanza
  int? _cartaObjetivo; // carta elegida (teletransporte / clon)
  final List<String> _muro = [];
  String? _celdaSel;

  int _informeVisto = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCatalogo();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // CARGA
  // ═══════════════════════════════════════════════════════════

  Future<void> _cargar() async {
    if (_cargando) return;
    _cargando = true;
    try {
      final sala = await _service.partida(widget.salaId, widget.uid);
      if (!mounted) return;
      _aplicar(sala);
    } on DuelosError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      // Fallo de red puntual: el siguiente sondeo lo reintenta.
    } finally {
      _cargando = false;
    }
  }

  void _aplicar(DuelosSala sala) {
    final p = sala.partida;
    final vista = p == null ? null : _VistaPartida.fromMap(p);
    setState(() {
      _sala = sala;
      _vista = vista;
      _error = null;
      if (vista != null && vista.turno != _turnoOrdenes) {
        _limpiarOrdenes();
        _turnoOrdenes = vista.turno;
      }
      if (!_puedoOrdenar) _cancelarModo();
    });
    if (!_mapaPedido) _cargarMapa(sala.mapaId);
    _programarSondeo(sala);
    if (vista != null) _quizaInforme(vista, sala);
  }

  Future<void> _cargarMapa(String? mapaId) async {
    _mapaPedido = true;
    if (mapaId == null || mapaId.isEmpty) return;
    try {
      final mapa = await MapaService().obtenerMapa(mapaId);
      if (!mounted || mapa == null) return;
      setState(() {
        _terrenoMapa = mapa.terreno;
        _imagenMapa = mapa.imagen.isEmpty ? null : mapa.imagen;
      });
    } catch (_) {
      // Sin mapa: el tablero se pinta con las casillas bloqueadas de la vista.
    }
  }

  Future<void> _cargarCatalogo() async {
    try {
      final cat = await _service.catalogo();
      if (!mounted) return;
      final m = <String, String>{};
      for (final e in cat.ejercitos) {
        for (final g in e.generales) {
          m[g.cartaId] = g.imagen;
        }
        for (final s in e.guarnicion) {
          m[s.cartaId] = s.imagen;
        }
      }
      setState(() => _imagenes = m);
    } catch (_) {}
  }

  /// Sondeo: a menudo en rápida (turnos de 30 s), poco en diario / 12 h.
  void _programarSondeo(DuelosSala sala) {
    if (sala.finalizada) {
      _sondeo?.cancel();
      _sondeo = null;
      _intervaloSondeo = null;
      return;
    }
    final intervalo = sala.modoTurno == ModoTurno.rapida
        ? const Duration(seconds: 3)
        : const Duration(seconds: 20);
    if (_sondeo != null && _intervaloSondeo == intervalo) return;
    _sondeo?.cancel();
    _intervaloSondeo = intervalo;
    _sondeo = Timer.periodic(intervalo, (_) => _cargar());
  }

  /// Reloj de 1 s: repinta la cuenta atrás y, al llegar a 0, pide el estado
  /// (el servidor cierra el turno por tiempo al leerlo).
  void _tic() {
    final sala = _sala;
    if (!mounted || sala == null || !sala.enCurso) return;
    setState(() {});
    final r = sala.restante;
    if (r != null &&
        r == Duration.zero &&
        DateTime.now().difference(_ultimoSondeoForzado) >
            const Duration(seconds: 3)) {
      _ultimoSondeoForzado = DateTime.now();
      _cargar();
    }
  }

  /// Informe del último turno resuelto (una vez por turno).
  void _quizaInforme(_VistaPartida v, DuelosSala sala) {
    final turnoInforme = sala.finalizada ? v.turno : v.turno - 1;
    if (turnoInforme < 1 || turnoInforme <= _informeVisto) return;
    _informeVisto = turnoInforme;
    if (v.eventos.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => _InformeDialog(turno: turnoInforme, eventos: v.eventos),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════
  // ÓRDENES
  // ═══════════════════════════════════════════════════════════

  bool get _puedoOrdenar {
    final s = _sala;
    return s != null && s.enCurso && !s.yaJugue && !_enviando && _vista != null;
  }

  void _limpiarOrdenes() {
    _movs.clear();
    _habs.clear();
    _disparos.clear();
    _usarEjercito = false;
    _ejercitoCarta = -1;
    _cancelarModo();
    _celdaSel = null;
  }

  void _cancelarModo() {
    _modo = _Modo.ninguno;
    _cartaActiva = null;
    _cartaObjetivo = null;
    _muro.clear();
  }

  int get _numOrdenes =>
      _movs.length +
      _habs.length +
      _disparos.length +
      (_usarEjercito ? 1 : 0);

  _CartaVista? _carta(int? id) {
    if (id == null) return null;
    for (final c in _vista?.cartas ?? const <_CartaVista>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  _JugadorVista? get _yo {
    for (final j in _vista?.jugadores ?? const <_JugadorVista>[]) {
      if (j.propio) return j;
    }
    return null;
  }

  _JugadorVista? get _rival {
    for (final j in _vista?.jugadores ?? const <_JugadorVista>[]) {
      if (!j.propio) return j;
    }
    return null;
  }

  String get _rivalUid {
    for (final j in _sala?.jugadores ?? const <DuelosJugadorSala>[]) {
      if (j.uid != widget.uid) return j.uid;
    }
    return 'rival';
  }

  /// Carta que un general va a teletransportar este turno → destino.
  String? _destinoTeletransporte(int cartaId) {
    for (final e in _habs.entries) {
      final g = _carta(e.key);
      if (g?.hab?.tipo == 'Teletransporte' &&
          e.value.cartaId == cartaId &&
          e.value.celdas.isNotEmpty) {
        return e.value.celdas.first;
      }
    }
    return null;
  }

  /// La Reparación deja quieto al general reparado.
  bool _inmovilizada(int cartaId) =>
      _usarEjercito &&
      _yo?.habilidadEjercito.tipo == 'Reparacion' &&
      _ejercitoCarta == cartaId;

  /// Casilla donde se verá la carta con las órdenes actuales.
  String _celdaPrevista(_CartaVista c) {
    if (!c.propia) return c.celda;
    return _destinoTeletransporte(c.id) ?? _movs[c.id] ?? c.celda;
  }

  /// Casillas a las que puede mover [c] con las órdenes actuales (Movilización
  /// y Más movimiento se aplican antes de mover, así que amplían el alcance).
  Set<String> _destinosDe(_CartaVista c) {
    final movil = _usarEjercito &&
        _yo?.habilidadEjercito.tipo == 'Movilizacion' &&
        c.alcanzablesExtra.containsKey('movilizacion');
    final mas = c.masMovimientoDe != null && _habs.containsKey(c.masMovimientoDe);
    if (movil && mas && c.alcanzablesExtra.containsKey('ambos')) {
      return c.alcanzablesExtra['ambos']!.toSet();
    }
    if (movil) return c.alcanzablesExtra['movilizacion']!.toSet();
    if (mas && c.alcanzablesExtra.containsKey('masMovimiento')) {
      return c.alcanzablesExtra['masMovimiento']!.toSet();
    }
    return c.alcanzables.toSet();
  }

  /// Casillas válidas para un disparo lejano.
  Set<String> get _celdasDisparo {
    final v = _vista;
    if (v == null) return const {};
    final r = <String>{};
    for (int f = 0; f < v.filas; f++) {
      for (int c = 0; c < v.columnas; c++) {
        final coord = '${String.fromCharCode(65 + f)}${c + 1}';
        if (!v.hundidas.contains(coord) && !v.bloqueadas.contains(coord)) {
          r.add(coord);
        }
      }
    }
    return r;
  }

  static (int, int) _rc(String coord) =>
      (coord.codeUnitAt(0) - 65, int.tryParse(coord.substring(1)) ?? 0);

  static int _distancia(String a, String b) {
    final (fa, ca) = _rc(a);
    final (fb, cb) = _rc(b);
    return (fa - fb).abs() + (ca - cb).abs();
  }

  /// Casillas resaltadas según lo que se esté eligiendo.
  Set<String> get _resaltadas {
    switch (_modo) {
      case _Modo.ninguno:
        return const {};
      case _Modo.mover:
        {
          final c = _carta(_cartaActiva);
          return c == null ? const {} : _destinosDe(c);
        }
      case _Modo.habCelda:
        return _carta(_cartaActiva)?.hab?.objetivos.toSet() ?? const {};
      case _Modo.habCartaCelda:
        {
          final h = _carta(_cartaActiva)?.hab;
          return h?.cartas[_cartaObjetivo]?.toSet() ?? const {};
        }
      case _Modo.muro:
        {
          final h = _carta(_cartaActiva)?.hab;
          if (h == null) return const {};
          if (_muro.isEmpty) return h.objetivos.toSet();
          return h.libres
              .where((l) =>
                  !_muro.contains(l) &&
                  _muro.any((m) => _distancia(m, l) == 1))
              .toSet();
        }
      case _Modo.disparo:
        return _celdasDisparo;
    }
  }

  void _onCellTap(String coord, int ri, int ci) {
    if (_vista == null) return;
    if (_modo == _Modo.ninguno || !_puedoOrdenar) {
      setState(() => _celdaSel = _celdaSel == coord ? null : coord);
      return;
    }
    final validas = _resaltadas;
    final id = _cartaActiva;
    setState(() {
      switch (_modo) {
        case _Modo.ninguno:
          break;
        case _Modo.mover:
          {
            final c = _carta(id);
            if (c != null && coord == c.celda) {
              _movs.remove(c.id); // tocar su casilla = quedarse quieta
            } else if (c != null && validas.contains(coord)) {
              _movs[c.id] = coord;
            } else {
              return; // fuera del alcance: sigue eligiendo
            }
            _celdaSel = coord;
            _cancelarModo();
          }
          break;
        case _Modo.habCelda:
          if (id == null || !validas.contains(coord)) return;
          _habs[id] = _OrdenHab(celdas: [coord]);
          _cancelarModo();
          break;
        case _Modo.habCartaCelda:
          if (id == null || _cartaObjetivo == null || !validas.contains(coord)) {
            return;
          }
          _habs[id] = _OrdenHab(celdas: [coord], cartaId: _cartaObjetivo!);
          // Teletransporte: la carta va por el aire, no por su pie.
          if (_carta(id)?.hab?.tipo == 'Teletransporte') {
            _movs.remove(_cartaObjetivo);
          }
          _cancelarModo();
          break;
        case _Modo.muro:
          {
            final h = _carta(id)?.hab;
            if (id == null || h == null) return;
            if (_muro.isNotEmpty && _muro.last == coord) {
              _muro.removeLast(); // deshacer la última casilla
              return;
            }
            if (!validas.contains(coord)) return;
            _muro.add(coord);
            if (_muro.length >= h.numCeldas) {
              _habs[id] = _OrdenHab(celdas: List.of(_muro));
              _cancelarModo();
            }
          }
          break;
        case _Modo.disparo:
          if (!validas.contains(coord)) return;
          _disparos.add(coord);
          _cancelarModo();
          break;
      }
    });
  }

  void _empezarMover(_CartaVista c) {
    setState(() {
      _cancelarModo();
      _modo = _Modo.mover;
      _cartaActiva = c.id;
    });
  }

  Future<void> _empezarHabilidad(_CartaVista g) async {
    final h = g.hab;
    if (h == null || h.modo.isEmpty) return;
    switch (h.modo) {
      case 'inmediata':
        setState(() => _habs[g.id] = const _OrdenHab());
        break;
      case 'celda':
        setState(() {
          _cancelarModo();
          _modo = _Modo.habCelda;
          _cartaActiva = g.id;
        });
        break;
      case 'carta':
        {
          final id = await _elegirCarta(
              '${h.nombre.toUpperCase()}: ELIGE CARTA', h.cartas.keys.toList());
          if (id != null && mounted) {
            setState(() => _habs[g.id] = _OrdenHab(cartaId: id));
          }
        }
        break;
      case 'carta_celda':
        {
          final titulo = h.tipo == 'Clon'
              ? 'CLON: ¿A QUÉ GENERAL COPIA?'
              : '${h.nombre.toUpperCase()}: ¿QUÉ CARTA?';
          final id = await _elegirCarta(titulo, h.cartas.keys.toList());
          if (id != null && mounted) {
            setState(() {
              _cancelarModo();
              _modo = _Modo.habCartaCelda;
              _cartaActiva = g.id;
              _cartaObjetivo = id;
            });
          }
        }
        break;
      case 'muro':
        setState(() {
          _cancelarModo();
          _modo = _Modo.muro;
          _cartaActiva = g.id;
        });
        break;
    }
  }

  Future<void> _pulsarEjercito() async {
    final yo = _yo;
    if (yo == null || !_puedoOrdenar) return;
    if (_usarEjercito) {
      setState(() {
        _usarEjercito = false;
        _ejercitoCarta = -1;
      });
      return;
    }
    final h = yo.habilidadEjercito;
    if (h.requiereCarta) {
      if (h.objetivos.isEmpty) {
        _aviso('${h.nombre}: no tienes ningún general herido.');
        return;
      }
      final id = await _elegirCarta(
          '${h.nombre.toUpperCase()}: ¿QUÉ GENERAL?', h.objetivos);
      if (id == null || !mounted) return;
      setState(() {
        _usarEjercito = true;
        _ejercitoCarta = id;
        _movs.remove(id); // el general reparado no se mueve este turno
      });
    } else {
      setState(() => _usarEjercito = true);
    }
  }

  void _pulsarDisparo() {
    if (!_puedoOrdenar) return;
    setState(() {
      if (_modo == _Modo.disparo) {
        _cancelarModo();
      } else {
        _cancelarModo();
        _modo = _Modo.disparo;
      }
    });
  }

  Future<int?> _elegirCarta(String titulo, List<int> ids) {
    final cartas = ids.map(_carta).whereType<_CartaVista>().toList();
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        final war = ctx.war;
        return SimpleDialog(
          backgroundColor: war.superficie,
          title: Text(titulo,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                  letterSpacing: 1.5,
                  color: war.primario)),
          children: [
            for (final c in cartas)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(c.id),
                child: Row(children: [
                  SizedBox(
                    width: 28,
                    child: Text(c.celda,
                        style: TextStyle(
                            fontSize: 9,
                            color: war.textoTenue,
                            fontFamily: 'Cinzel')),
                  ),
                  Expanded(
                    child: Text(
                        '${c.esComandante ? '★ ' : ''}${c.nombre}'
                        '${c.esGeneral ? '   ♥ ${c.vidas}/${c.vidasMax}' : ''}',
                        style: TextStyle(
                            fontSize: 11,
                            color: war.texto,
                            fontFamily: 'Cinzel')),
                  ),
                ]),
              ),
          ],
        );
      },
    );
  }

  Map<String, dynamic> _jugada() => {
        'movimientos': {
          for (final e in _movs.entries) '${e.key}': e.value,
        },
        'habilidades': [
          for (final e in _habs.entries)
            {
              'generalId': e.key,
              'celdas': e.value.celdas,
              'cartaId': e.value.cartaId,
            }
        ],
        'disparos': List.of(_disparos),
        'usarHabilidadEjercito': _usarEjercito,
        'habilidadEjercitoCartaId': _ejercitoCarta,
      };

  Future<void> _finTurno() async {
    final v = _vista;
    if (v == null || !_puedoOrdenar) return;
    setState(() {
      _enviando = true;
      _cancelarModo();
    });
    try {
      final sala = await _service.turno(
        id: widget.salaId,
        uid: widget.uid,
        turno: v.turno,
        jugada: _jugada(),
      );
      if (!mounted) return;
      _aplicar(sala);
    } on DuelosError catch (e) {
      _aviso(e.mensaje);
      await _cargar();
    } catch (e) {
      _aviso('No se pudo enviar el turno. Revisa la conexión.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontFamily: 'Cinzel', fontSize: 11)),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _rendirse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final war = ctx.war;
        return AlertDialog(
          backgroundColor: war.superficie,
          title: Text('¿RENDIRSE?',
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 13, color: war.primario)),
          content: Text('Perderás el duelo y la victoria será de tu rival.',
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 10, color: war.texto)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('SEGUIR LUCHANDO',
                    style: TextStyle(
                        fontFamily: 'Cinzel', color: war.textoTenue))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('RENDIRSE',
                    style:
                        TextStyle(fontFamily: 'Cinzel', color: war.error))),
          ],
        );
      },
    );
    if (ok != true) return;
    setState(() => _rindiendo = true);
    try {
      await _service.salir(id: widget.salaId, uid: widget.uid);
      await _cargar();
    } catch (e) {
      _aviso(e.toString());
    } finally {
      if (mounted) setState(() => _rindiendo = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TABLERO (BoardWidget de las partidas normales)
  // ═══════════════════════════════════════════════════════════

  GameConfig _config(_VistaPartida v) {
    final terreno = Map<String, TerrainType>.of(_terrenoMapa);
    for (final b in v.bloqueadas) {
      final t = terreno[b];
      if (t == null || t == TerrainType.land) terreno[b] = TerrainType.deepSea;
    }
    for (final h in v.hundidas) {
      terreno[h] = TerrainType.deepSea;
    }
    return GameConfig.forPlayerCount(2)
        .withTerrain(terreno)
        .withGrid(filas: v.filas, columnas: v.columnas);
  }

  static EfectoActivo _efecto(EfectoTipoEstado t,
          {int turnos = 1, String origen = '', String icono = ''}) =>
      EfectoActivo(
        tipo: t,
        turnosRestantes: turnos < 1 ? 1 : turnos,
        magnitud: 0, // solo indicador: el ataque ya viene calculado
        origenUid: origen,
        tipoRaw: t.name,
        icono: icono,
      );

  CartaEnCelda _cartaEnCelda(_CartaVista c) {
    final efectos = <EfectoActivo>[
      if (c.efectos.contains('paralizada'))
        _efecto(EfectoTipoEstado.paralisis),
      if (c.efectos.contains('confusa')) _efecto(EfectoTipoEstado.confusion),
      if (c.efectos.contains('veneno')) _efecto(EfectoTipoEstado.veneno),
      if (c.efectos.contains('masAtaque')) _efecto(EfectoTipoEstado.potFuerza),
      if (c.efectos.contains('masMovimiento'))
        _efecto(EfectoTipoEstado.potMovimiento),
      if (c.efectos.contains('supervivencia'))
        _efecto(EfectoTipoEstado.supervivencia),
    ];
    final vidas = c.esGeneral ? ' ${'♥' * c.vidas}' : '';
    return CartaEnCelda(
      carta: CartaModel(
        id: c.cartaId,
        nombre: '${c.esComandante ? '★ ' : ''}${c.nombre}$vidas',
        descripcion: c.hab?.descripcion ?? '',
        ejercito: 0,
        fuerza: c.ataque,
        idHabilidad: 0,
        imagen: _imagenes[c.cartaId] ?? '',
        movimiento: c.movimiento,
      ),
      ownerUid: c.propia ? widget.uid : _rivalUid,
      ownerZone: c.propia ? 'south' : 'north',
      efectos: efectos,
      instanceId: 'duelo_${c.id}',
      esClon: c.esClon,
    );
  }

  BoardState _tablero(_VistaPartida v) {
    final celdas = <String, List<CartaEnCelda>>{};
    for (final c in v.cartas) {
      celdas.putIfAbsent(_celdaPrevista(c), () => []).add(_cartaEnCelda(c));
    }
    final efectosCelda = <String, List<EfectoActivo>>{};
    void anadir(String coord, EfectoActivo e) =>
        efectosCelda.putIfAbsent(coord, () => []).add(e);
    for (final m in v.muros) {
      anadir(m.celda,
          _efecto(EfectoTipoEstado.muro, turnos: m.hasta - v.turno + 1));
    }
    for (final e in v.escudos) {
      anadir(
          e.celda,
          _efecto(EfectoTipoEstado.escudo,
              turnos: e.hasta - v.turno + 1,
              origen: e.propio ? widget.uid : _rivalUid));
    }
    // Casillas que se hunden al final de este turno.
    for (final h in v.hundimientos) {
      anadir(h, _efecto(EfectoTipoEstado.trampa, icono: '🌊'));
    }
    return BoardState(
      celdas: {
        for (final e in celdas.entries)
          e.key: CeldaState(coord: e.key, cartas: e.value),
      },
      turnoActual: v.turno,
      efectosCelda: efectosCelda,
    );
  }

  /// Siluetas que recorren el camino de cada carta con orden de moverse.
  List<RevisionFantasma> _fantasmas(_VistaPartida v) {
    final r = <RevisionFantasma>[];
    for (final c in v.cartas.where((c) => c.propia)) {
      final destino = _celdaPrevista(c);
      if (destino == c.celda) continue;
      r.add((
        origen: c.celda,
        destino: destino,
        color: kDuelosAcento,
        icon: _destinoTeletransporte(c.id) != null
            ? Icons.auto_awesome
            : Icons.directions_walk,
        iconColor: Colors.white,
        movimiento: c.movimiento,
        nombre: c.nombre,
      ));
    }
    return r;
  }

  /// Anillos en las casillas objetivo de habilidades y disparos ordenados.
  Set<String> get _objetivosOrdenados => {
        for (final h in _habs.values) ...h.celdas,
        ..._disparos,
        ..._muro,
      };

  // ═══════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final sala = _sala;
    final v = _vista;
    return Scaffold(
      backgroundColor: const Color(0xFF0A1F35),
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        titleSpacing: 0,
        title: Text(
          sala?.nombre.toUpperCase() ?? 'DUELO',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 2,
            color: war.primario,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (v != null && v.eventos.isNotEmpty)
            IconButton(
              tooltip: 'Informe del último turno',
              icon: Icon(Icons.article_outlined, color: war.primario),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _InformeDialog(
                    turno: sala?.finalizada == true ? v.turno : v.turno - 1,
                    eventos: v.eventos),
              ),
            ),
          IconButton(
            tooltip: 'Reglas',
            icon: Icon(Icons.help_outline, color: war.primario),
            onPressed: () => showDialog<void>(
                context: context, builder: (_) => const _AyudaDialog()),
          ),
          if (sala != null && sala.enCurso)
            IconButton(
              tooltip: 'Rendirse',
              icon: Icon(Icons.flag_outlined, color: war.error),
              onPressed: _rindiendo ? null : _rendirse,
            ),
        ],
      ),
      body: SafeArea(
        child: sala == null
            ? (_error != null
                ? DuelosMensaje(
                    icono: Icons.error_outline,
                    texto: _error!,
                    accion: 'REINTENTAR',
                    onAccion: _cargar)
                : Center(
                    child: CircularProgressIndicator(color: war.primario)))
            : v == null
                ? const DuelosMensaje(
                    icono: Icons.hourglass_top,
                    texto: 'El duelo todavía no ha empezado.')
                : _cuerpo(sala, v),
      ),
    );
  }

  Widget _cuerpo(DuelosSala sala, _VistaPartida v) {
    final celdaSel = _modo == _Modo.ninguno ? _celdaSel : null;
    return Column(
      children: [
        _Cabecera(sala: sala, vista: v, yo: _yo, rival: _rival),
        if (sala.finalizada)
          _BannerResultado(
              vista: v, motivo: sala.motivo, recompensa: sala.recompensa),
        if (_modo != _Modo.ninguno) _bannerModo(),
        // Con clave: los avisos de arriba y los paneles de abajo aparecen y
        // desaparecen, y sin ella Flutter recrearía el tablero (perdiendo el
        // zoom y el desplazamiento) cada vez.
        Expanded(
          key: const ValueKey('duelos_tablero'),
          child: BoardWidget(
            config: _config(v),
            boardState: _tablero(v),
            imagenMapa: _imagenMapa,
            selectedCellCoord: celdaSel,
            highlightEmpty: false,
            movableCoords: _resaltadas,
            playerColors: {widget.uid: kDuelosAcento, _rivalUid: _kRival},
            localPlayerUid: widget.uid,
            fantasmasRevision: sala.enCurso ? _fantasmas(v) : const [],
            accionesRevision: sala.enCurso ? _objetivosOrdenados : const {},
            onCellTap: _onCellTap,
          ),
        ),
        if (celdaSel != null) _panelCelda(v, celdaSel),
        if (sala.enCurso && _numOrdenes > 0) _listaOrdenes(),
        if (sala.enCurso) _barra(sala, v),
      ],
    );
  }

  Widget _bannerModo() {
    final war = context.war;
    final a = _carta(_cartaActiva);
    final texto = switch (_modo) {
      _Modo.mover => 'Elige el destino de ${a?.nombre ?? 'la carta'} '
          '(toca su casilla para que no se mueva)',
      _Modo.habCelda => '${a?.hab?.nombre ?? 'Habilidad'}: elige la casilla',
      _Modo.habCartaCelda => a?.hab?.tipo == 'Clon'
          ? 'Clon: elige la casilla donde aparece'
          : '${a?.hab?.nombre ?? 'Habilidad'}: elige el destino de '
              '${_carta(_cartaObjetivo)?.nombre ?? 'la carta'}',
      _Modo.muro => 'Muro: casilla ${_muro.length + 1} de '
          '${a?.hab?.numCeldas ?? 3} (encadenadas; toca la última para '
          'quitarla)',
      _Modo.disparo => 'Disparo lejano: elige la casilla',
      _Modo.ninguno => '',
    };
    return Container(
      width: double.infinity,
      color: kDuelosAcento.withOpacity(0.14),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(children: [
        Expanded(
          child: Text(texto,
              style: TextStyle(
                  fontSize: 9,
                  color: war.texto,
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.5)),
        ),
        TextButton(
          onPressed: () => setState(_cancelarModo),
          child: Text('CANCELAR',
              style: TextStyle(
                  fontSize: 9,
                  color: war.error,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1)),
        ),
      ]),
    );
  }

  /// Panel con las cartas de la casilla tocada (como el menú lateral de las
  /// partidas normales): MOVER / DESHACER / HABILIDAD.
  Widget _panelCelda(_VistaPartida v, String coord) {
    final war = context.war;
    final cartas =
        v.cartas.where((c) => _celdaPrevista(c) == coord).toList()
          ..sort((a, b) => (b.propia ? 1 : 0) - (a.propia ? 1 : 0));
    final notas = <String>[
      if (v.hundimientos.contains(coord)) '🌊 Se hunde al final del turno',
      if (v.hundidas.contains(coord)) 'Casilla hundida',
      if (v.bloqueadas.contains(coord)) 'Casilla bloqueada',
      for (final m in v.muros)
        if (m.celda == coord) '🧱 Muro hasta el turno ${m.hasta}',
      for (final e in v.escudos)
        if (e.celda == coord)
          '🛡 Escudo ${e.propio ? 'propio' : 'rival'} hasta el turno ${e.hasta}',
    ];
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: BoxDecoration(
        color: war.superficie,
        border: Border(top: BorderSide(color: war.borde.withOpacity(0.4))),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        children: [
          Row(children: [
            Text('CASILLA $coord',
                style: TextStyle(
                    fontSize: 10,
                    color: war.primario,
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _celdaSel = null),
              child: Icon(Icons.close, size: 16, color: war.textoTenue),
            ),
          ]),
          for (final n in notas)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(n,
                  style: TextStyle(
                      fontSize: 8,
                      color: war.textoTenue,
                      fontFamily: 'Cinzel')),
            ),
          if (cartas.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Sin cartas.',
                  style: TextStyle(
                      fontSize: 9,
                      color: war.textoTenue,
                      fontFamily: 'Cinzel')),
            ),
          for (final c in cartas) _filaCarta(c),
        ],
      ),
    );
  }

  Widget _filaCarta(_CartaVista c) {
    final war = context.war;
    final color = c.propia ? kDuelosAcento : _kRival;
    final movida = _movs.containsKey(c.id);
    final tele = _destinoTeletransporte(c.id) != null;
    final quieta = _inmovilizada(c.id);
    final ordenHab = _habs.containsKey(c.id);
    final h = c.hab;

    final detalles = <String>[
      '⚔ ${c.ataque}',
      if (c.esGeneral) '♥ ${c.vidas}/${c.vidasMax}',
      for (final e in c.efectos) _textoEfecto(e),
      if (c.esClon) 'clon',
      if (h != null)
        c.propia && !c.esClon
            ? '${h.nombre} · ${h.lista ? 'lista' : 'turno ${h.recargaLista}'}'
            : h.nombre,
    ];

    final botones = <Widget>[];
    if (c.propia && _puedoOrdenar) {
      if (movida) {
        botones.add(_BotonMini(
            label: 'DESHACER',
            icon: Icons.undo,
            onTap: () => setState(() => _movs.remove(c.id))));
      } else if (!tele && !quieta && _destinosDe(c).isNotEmpty) {
        botones.add(_BotonMini(
            label: 'MOVER',
            icon: Icons.open_with,
            onTap: () => _empezarMover(c)));
      }
      if (h != null && !c.esClon) {
        if (ordenHab) {
          botones.add(_BotonMini(
              label: 'QUITAR ${h.nombre.toUpperCase()}',
              icon: Icons.close,
              color: war.error,
              onTap: () => setState(() => _habs.remove(c.id))));
        } else if (h.modo.isNotEmpty) {
          botones.add(_BotonMini(
              label: h.nombre.toUpperCase(),
              icon: Icons.auto_awesome,
              color: war.secundario,
              onTap: () => _empezarHabilidad(c)));
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (c.esComandante)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.shield, size: 12, color: war.primario),
              ),
            Expanded(
              child: Text(
                  '${c.nombre}${c.esComandante ? '  ·  $kDuelosTerminoComandante' : ''}',
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontFamily: 'Cinzel',
                      fontWeight: FontWeight.bold)),
            ),
            if (h != null)
              GestureDetector(
                onTap: () => _verHabilidad(h),
                child: Icon(Icons.info_outline,
                    size: 14, color: war.textoTenue),
              ),
          ]),
          const SizedBox(height: 3),
          Text(detalles.join('  ·  '),
              style: TextStyle(
                  fontSize: 8, color: war.texto, fontFamily: 'Cinzel')),
          if (c.propia && (movida || tele || quieta))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                  tele
                      ? 'Se teletransporta a ${_destinoTeletransporte(c.id)}'
                      : quieta
                          ? 'No se mueve este turno (reparación)'
                          : 'Sale de ${c.celda} hacia ${_movs[c.id]}',
                  style: const TextStyle(
                      fontSize: 8,
                      color: kDuelosAcento,
                      fontFamily: 'Cinzel')),
            ),
          if (botones.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: botones),
          ],
        ],
      ),
    );
  }

  void _verHabilidad(_HabilidadVista h) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final war = ctx.war;
        return AlertDialog(
          backgroundColor: war.superficie,
          title: Text(h.nombre.toUpperCase(),
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 13, color: war.primario)),
          content: Text(h.descripcion,
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 10, color: war.texto)),
        );
      },
    );
  }

  static String _textoEfecto(String e) => switch (e) {
        'paralizada' => 'paralizada',
        'confusa' => 'confusa',
        'veneno' => 'envenenada',
        'masAtaque' => 'más ataque',
        'masMovimiento' => 'más movimiento',
        'supervivencia' => 'supervivencia',
        _ => e,
      };

  /// Órdenes de este turno, cada una con su ✕ para quitarla.
  Widget _listaOrdenes() {
    final war = context.war;
    final chips = <Widget>[];
    for (final e in _movs.entries) {
      final c = _carta(e.key);
      chips.add(_ChipOrden(
          texto: '${c?.nombre ?? '?'} → ${e.value}',
          onQuitar: () => setState(() => _movs.remove(e.key))));
    }
    for (final e in _habs.entries) {
      final g = _carta(e.key);
      final obj = _carta(e.value.cartaId);
      final partes = [
        if (obj != null) obj.nombre,
        if (e.value.celdas.isNotEmpty) e.value.celdas.join(','),
      ];
      chips.add(_ChipOrden(
          texto: '${g?.hab?.nombre ?? 'Habilidad'}'
              '${partes.isEmpty ? '' : ': ${partes.join(' → ')}'}',
          color: war.secundario,
          onQuitar: () => setState(() => _habs.remove(e.key))));
    }
    for (int i = 0; i < _disparos.length; i++) {
      final idx = i;
      chips.add(_ChipOrden(
          texto: '🎯 Disparo ${_disparos[i]}',
          color: war.error,
          onQuitar: () => setState(() => _disparos.removeAt(idx))));
    }
    if (_usarEjercito) {
      final h = _yo?.habilidadEjercito;
      final obj = _carta(_ejercitoCarta);
      chips.add(_ChipOrden(
          texto: '${h?.nombre ?? 'Habilidad de ejército'}'
              '${obj != null ? ': ${obj.nombre}' : ''}',
          color: war.primario,
          onQuitar: () => setState(() {
                _usarEjercito = false;
                _ejercitoCarta = -1;
              })));
    }
    return Container(
      width: double.infinity,
      color: war.fondo,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: chips),
      ),
    );
  }

  /// Barra inferior: habilidad del ejército, disparo lejano y FIN DE TURNO.
  Widget _barra(DuelosSala sala, _VistaPartida v) {
    final war = context.war;
    final yo = _yo;
    final hEj = yo?.habilidadEjercito;
    final puedo = _puedoOrdenar;

    String etiquetaEj;
    VoidCallback? accionEj;
    if (hEj == null) {
      etiquetaEj = 'EJÉRCITO';
    } else if (hEj.usada) {
      etiquetaEj = '${hEj.nombre.toUpperCase()} · USADA';
    } else if (!hEj.lista) {
      etiquetaEj = '${hEj.nombre.toUpperCase()} · TURNO 2';
    } else {
      etiquetaEj = _usarEjercito
          ? '${hEj.nombre.toUpperCase()} ✓'
          : hEj.nombre.toUpperCase();
      accionEj = puedo ? _pulsarEjercito : null;
    }

    final disparosLibres = (yo?.disparosRestantes ?? 0) - _disparos.length;
    final puedeDisparar =
        puedo && (yo?.puedeDisparar ?? false) && disparosLibres > 0;

    final restante = sala.restante;
    String etiquetaFin;
    if (_enviando) {
      etiquetaFin = 'ENVIANDO';
    } else if (sala.yaJugue) {
      etiquetaFin = 'TURNO CERRADO';
    } else if (sala.modoTurno == ModoTurno.rapida && restante != null) {
      etiquetaFin = 'FIN DE TURNO (${restante.inSeconds}s)';
    } else {
      etiquetaFin = 'FIN DE TURNO';
    }

    return Container(
      color: war.superficie,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sala.yaJugue)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                  sala.rivalJugo
                      ? 'Resolviendo el turno…'
                      : 'Turno cerrado. Esperando a tu rival…',
                  style: TextStyle(
                      fontSize: 9,
                      color: war.textoTenue,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1)),
            ),
          Row(children: [
            Expanded(
              flex: 5,
              child: GestureDetector(
                onLongPress: hEj == null
                    ? null
                    : () => _verHabilidad(_HabilidadVista.soloTexto(
                        hEj.nombre, hEj.descripcion)),
                child: DuelosBoton(
                  label: etiquetaEj,
                  icon: Icons.military_tech,
                  color: _usarEjercito ? kDuelosAcento : war.primario,
                  onTap: accionEj,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: DuelosBoton(
                label: _modo == _Modo.disparo
                    ? 'CANCELAR'
                    : '🎯 ${yo?.disparosRestantes ?? 0}',
                icon: Icons.gps_fixed,
                color: war.error,
                onTap: (puedeDisparar || _modo == _Modo.disparo)
                    ? _pulsarDisparo
                    : null,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: DuelosBoton(
              label: etiquetaFin,
              icon: sala.yaJugue ? Icons.hourglass_top : Icons.check,
              color: kDuelosAcento,
              cargando: _enviando,
              onTap: puedo ? _finTurno : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODELO DE LA VISTA (lo que manda el servidor en `partida`)
// ─────────────────────────────────────────────────────────────

List<String> _strs(Object? o) =>
    (o as List? ?? const []).map((e) => e.toString()).toList();

List<Map<String, dynamic>> _maps(Object? o) => (o as List? ?? const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

int _int(Object? o, [int def = 0]) => o is num ? o.toInt() : def;

class _MarcaCelda {
  final String celda;
  final int hasta;
  final bool propio;
  const _MarcaCelda(this.celda, this.hasta, this.propio);
}

class _VistaPartida {
  final int turno;
  final int turnoLimite;
  final int filas;
  final int columnas;
  final String resultado;
  final Set<String> bloqueadas;
  final Set<String> hundidas;
  final Set<String> hundimientos;
  final List<_MarcaCelda> muros;
  final List<_MarcaCelda> escudos;
  final List<_JugadorVista> jugadores;
  final List<_CartaVista> cartas;
  final List<_EventoVista> eventos;

  const _VistaPartida({
    required this.turno,
    required this.turnoLimite,
    required this.filas,
    required this.columnas,
    required this.resultado,
    required this.bloqueadas,
    required this.hundidas,
    required this.hundimientos,
    required this.muros,
    required this.escudos,
    required this.jugadores,
    required this.cartas,
    required this.eventos,
  });

  factory _VistaPartida.fromMap(Map<String, dynamic> p) => _VistaPartida(
        turno: _int(p['turno'], 1),
        turnoLimite: _int(p['turnoLimite'], 35),
        filas: _int(p['filas'], 7),
        columnas: _int(p['columnas'], 7),
        resultado: p['resultado'] as String? ?? '',
        bloqueadas: _strs(p['bloqueadas']).toSet(),
        hundidas: _strs(p['hundidas']).toSet(),
        hundimientos: _strs(p['hundimientos']).toSet(),
        muros: _maps(p['muros'])
            .map((m) => _MarcaCelda('${m['celda']}', _int(m['hasta']), false))
            .toList(),
        escudos: _maps(p['escudos'])
            .map((m) => _MarcaCelda(
                '${m['celda']}', _int(m['hasta']), m['propio'] == true))
            .toList(),
        jugadores: _maps(p['jugadores']).map(_JugadorVista.fromMap).toList(),
        cartas: _maps(p['cartas']).map(_CartaVista.fromMap).toList(),
        eventos: _maps(p['eventos']).map(_EventoVista.fromMap).toList(),
      );
}

class _HabilidadEjercitoVista {
  final String tipo;
  final String nombre;
  final String descripcion;
  final bool usada;
  final bool lista;
  final bool requiereCarta;
  final List<int> objetivos;

  const _HabilidadEjercitoVista({
    required this.tipo,
    required this.nombre,
    required this.descripcion,
    required this.usada,
    required this.lista,
    required this.requiereCarta,
    required this.objetivos,
  });

  factory _HabilidadEjercitoVista.fromMap(Map<String, dynamic> h) =>
      _HabilidadEjercitoVista(
        tipo: h['tipo'] as String? ?? '',
        nombre: h['nombre'] as String? ?? '',
        descripcion: h['descripcion'] as String? ?? '',
        usada: h['usada'] == true,
        lista: h['lista'] == true,
        requiereCarta: h['requiereCarta'] == true,
        objetivos: (h['objetivos'] as List? ?? const [])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList(),
      );
}

class _JugadorVista {
  final bool propio;
  final String ejercito;
  final int pc;
  final int disparosRestantes;
  final bool puedeDisparar;
  final _HabilidadEjercitoVista habilidadEjercito;
  final bool fortalezaActiva;
  final bool furiaActiva;
  final bool movilizacionActiva;

  const _JugadorVista({
    required this.propio,
    required this.ejercito,
    required this.pc,
    required this.disparosRestantes,
    required this.puedeDisparar,
    required this.habilidadEjercito,
    required this.fortalezaActiva,
    required this.furiaActiva,
    required this.movilizacionActiva,
  });

  factory _JugadorVista.fromMap(Map<String, dynamic> m) => _JugadorVista(
        propio: m['propio'] == true,
        ejercito: m['ejercito'] as String? ?? '',
        pc: _int(m['pc']),
        disparosRestantes: _int(m['disparosRestantes']),
        puedeDisparar: m['puedeDisparar'] == true,
        habilidadEjercito: _HabilidadEjercitoVista.fromMap(
            Map<String, dynamic>.from(m['habilidadEjercito'] as Map? ?? {})),
        fortalezaActiva: m['fortalezaActiva'] == true,
        furiaActiva: m['furiaActiva'] == true,
        movilizacionActiva: m['movilizacionActiva'] == true,
      );

  /// Efectos de ejército activos este turno (para la cabecera).
  List<String> get activos => [
        if (fortalezaActiva) 'Fortaleza',
        if (furiaActiva) 'Furia',
        if (movilizacionActiva) 'Movilización',
      ];
}

/// Habilidad de un general. Para los propios trae sus objetivos válidos:
///   modo "" (no disponible), "inmediata", "celda" ([objetivos]), "carta"
///   ([cartas]), "carta_celda" ([cartas] → destinos) o "muro" ([numCeldas]
///   casillas de [libres] encadenadas, la primera de [objetivos]).
class _HabilidadVista {
  final String tipo;
  final String nombre;
  final String descripcion;
  final bool lista;
  final int recargaLista;
  final String modo;
  final List<String> objetivos;
  final Map<int, List<String>> cartas;
  final List<String> libres;
  final int numCeldas;

  const _HabilidadVista({
    required this.tipo,
    required this.nombre,
    required this.descripcion,
    required this.lista,
    required this.recargaLista,
    this.modo = '',
    this.objetivos = const [],
    this.cartas = const {},
    this.libres = const [],
    this.numCeldas = 1,
  });

  factory _HabilidadVista.soloTexto(String nombre, String descripcion) =>
      _HabilidadVista(
          tipo: '',
          nombre: nombre,
          descripcion: descripcion,
          lista: false,
          recargaLista: 0);

  factory _HabilidadVista.fromMap(Map<String, dynamic> h) {
    final cartas = <int, List<String>>{};
    final raw = h['cartas'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id != null) cartas[id] = _strs(v);
      });
    }
    return _HabilidadVista(
      tipo: h['tipo'] as String? ?? '',
      nombre: h['nombre'] as String? ?? '',
      descripcion: h['descripcion'] as String? ?? '',
      lista: h['lista'] == true,
      recargaLista: _int(h['recargaLista']),
      modo: h['modo'] as String? ?? '',
      objetivos: _strs(h['objetivos']),
      cartas: cartas,
      libres: _strs(h['libres']),
      numCeldas: _int(h['numCeldas'], 1),
    );
  }
}

class _CartaVista {
  final int id;
  final bool propia;
  final String nombre;
  final String cartaId;
  final String papel;
  final String celda;
  final int ataque;
  final int movimiento;
  final bool esGeneral;
  final int vidas;
  final int vidasMax;
  final bool esComandante;
  final bool esClon;
  final _HabilidadVista? hab;
  final List<String> efectos;
  final List<String> alcanzables;
  final Map<String, List<String>> alcanzablesExtra;
  final int? masMovimientoDe;

  const _CartaVista({
    required this.id,
    required this.propia,
    required this.nombre,
    required this.cartaId,
    required this.papel,
    required this.celda,
    required this.ataque,
    required this.movimiento,
    required this.esGeneral,
    required this.vidas,
    required this.vidasMax,
    required this.esComandante,
    required this.esClon,
    required this.hab,
    required this.efectos,
    required this.alcanzables,
    required this.alcanzablesExtra,
    required this.masMovimientoDe,
  });

  factory _CartaVista.fromMap(Map<String, dynamic> m) {
    final ef = Map<String, dynamic>.from(m['efectos'] as Map? ?? {});
    final extra = <String, List<String>>{};
    final rawExtra = m['alcanzablesExtra'];
    if (rawExtra is Map) {
      rawExtra.forEach((k, v) => extra[k.toString()] = _strs(v));
    }
    final h = m['habilidad'];
    return _CartaVista(
      id: _int(m['id']),
      propia: m['propia'] == true,
      nombre: m['nombre'] as String? ?? '',
      cartaId: m['cartaId'] as String? ?? '',
      papel: m['papel'] as String? ?? '',
      celda: m['celda'] as String? ?? '',
      ataque: _int(m['ataque']),
      movimiento: _int(m['movimiento'], 2),
      esGeneral: m['esGeneral'] == true,
      vidas: _int(m['vidas']),
      vidasMax: _int(m['vidasMax']),
      esComandante: m['esComandante'] == true,
      esClon: m['esClon'] == true,
      hab: h is Map
          ? _HabilidadVista.fromMap(Map<String, dynamic>.from(h))
          : null,
      efectos: [
        for (final e in ef.entries)
          if (e.value == true) e.key
      ],
      alcanzables: _strs(m['alcanzables']),
      alcanzablesExtra: extra,
      masMovimientoDe:
          m['masMovimientoDe'] is num ? (m['masMovimientoDe'] as num).toInt() : null,
    );
  }
}

class _EventoVista {
  final String tipo;
  final String celda;
  final String texto;
  final bool propio;
  final bool rival;

  const _EventoVista({
    required this.tipo,
    required this.celda,
    required this.texto,
    required this.propio,
    required this.rival,
  });

  factory _EventoVista.fromMap(Map<String, dynamic> m) => _EventoVista(
        tipo: m['tipo'] as String? ?? '',
        celda: m['celda'] as String? ?? '',
        texto: m['texto'] as String? ?? '',
        propio: m['propio'] == true,
        rival: m['rival'] == true,
      );
}

// ─────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────

/// Cabecera: turno, tiempo para cerrar, y estado de cada bando.
class _Cabecera extends StatelessWidget {
  final DuelosSala sala;
  final _VistaPartida vista;
  final _JugadorVista? yo;
  final _JugadorVista? rival;

  const _Cabecera({
    required this.sala,
    required this.vista,
    required this.yo,
    required this.rival,
  });

  static String _tiempo(DuelosSala s) {
    final r = s.restante;
    if (r == null) return '';
    if (s.modoTurno == ModoTurno.rapida) return '${r.inSeconds} s';
    final h = r.inHours;
    final m = r.inMinutes % 60;
    final limite = DateTime.fromMillisecondsSinceEpoch(s.fechaLimiteMs,
        isUtc: true);
    final hora = '${limite.hour.toString().padLeft(2, '0')}:'
        '${limite.minute.toString().padLeft(2, '0')} UTC';
    return h > 0 ? 'cierra en $h h $m min ($hora)' : 'cierra en $m min ($hora)';
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final estilo = TextStyle(
        fontSize: 8, color: war.textoTenue, fontFamily: 'Cinzel');
    final rivales = sala.jugadores.where((j) => !j.propio).toList();
    final alias = rivales.isEmpty ? 'Rival' : rivales.first.alias;

    Widget bando(_JugadorVista? j, String nombre, Color color, bool cerro) {
      if (j == null) return const SizedBox.shrink();
      final partes = <String>[
        j.ejercito.toUpperCase(),
        '${j.pc} PC',
        '🎯 ${j.disparosRestantes}',
        '${j.habilidadEjercito.nombre}: '
            '${j.habilidadEjercito.usada ? 'usada' : 'disponible'}',
        ...j.activos,
      ];
      return Row(children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(nombre,
            style: TextStyle(
                fontSize: 8,
                color: color,
                fontFamily: 'Cinzel',
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(partes.join('  ·  '),
              overflow: TextOverflow.ellipsis, style: estilo),
        ),
        if (cerro)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.check_circle, size: 11, color: kDuelosAcento),
          ),
      ]);
    }

    final tiempo = sala.enCurso ? _tiempo(sala) : '';
    return Container(
      color: war.superficie.withOpacity(0.9),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('TURNO ${vista.turno}/${vista.turnoLimite}',
                style: TextStyle(
                    fontSize: 10,
                    color: war.primario,
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(textoModoDuelo(sala.modoTurno), style: estilo),
            const Spacer(),
            if (tiempo.isNotEmpty)
              Text(tiempo,
                  style: TextStyle(
                      fontSize: 9,
                      color: sala.modoTurno == ModoTurno.rapida &&
                              (sala.restante?.inSeconds ?? 99) <= 10
                          ? war.error
                          : war.texto,
                      fontFamily: 'Cinzel')),
          ]),
          const SizedBox(height: 4),
          bando(yo, 'TÚ', kDuelosAcento, sala.yaJugue),
          const SizedBox(height: 2),
          bando(rival, alias.toUpperCase(), _kRival, sala.rivalJugo),
          if (sala.enCurso && sala.inactividad > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '⚠ Llevas ${sala.inactividad} '
                  '${sala.inactividad == 1 ? 'turno' : 'turnos'} sin pulsar '
                  'FIN DE TURNO. Con ${sala.turnosInactividadDerrota} pierdes '
                  'el duelo.',
                  style: TextStyle(
                      fontSize: 8, color: war.error, fontFamily: 'Cinzel')),
            ),
        ],
      ),
    );
  }
}

class _BannerResultado extends StatelessWidget {
  final _VistaPartida vista;
  final String motivo;
  final DuelosRecompensa? recompensa;
  const _BannerResultado(
      {required this.vista, required this.motivo, this.recompensa});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final (texto, color) = switch (vista.resultado) {
      'victoria' => ('¡VICTORIA!', const Color(0xFFFFCC00)),
      'derrota' => ('DERROTA', war.error),
      _ => ('TABLAS', war.textoTenue),
    };
    final explicacion = switch (motivo) {
      'abandono' => 'Un jugador se ha rendido.',
      'inactividad' => '3 turnos seguidos sin pulsar FIN DE TURNO.',
      'limite' => 'Se alcanzó el límite de turnos.',
      'ambos reyes' =>
        'Los dos ${kDuelosTerminoComandante}s cayeron a la vez.',
      '' => '',
      _ => 'El $kDuelosTerminoComandante cayó por: $motivo.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: color.withOpacity(0.12),
      child: Column(children: [
        Text(texto,
            style: TextStyle(
                fontSize: 16,
                color: color,
                fontFamily: 'Cinzel',
                letterSpacing: 4,
                fontWeight: FontWeight.bold)),
        if (explicacion.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(explicacion,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9, color: war.texto, fontFamily: 'Cinzel')),
        ],
        if (recompensa != null) ...[
          const SizedBox(height: 6),
          Text(
              '${recompensa!.pc} PC   ·   +${recompensa!.xp} XP   ·   '
              '+${recompensa!.dinero} dinero   ·   '
              '+${recompensa!.zero} Cristales Zero',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9,
                  color: color,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold)),
        ],
      ]),
    );
  }
}

class _BotonMini extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _BotonMini({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? kDuelosAcento;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withOpacity(0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 8,
                  color: c,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _ChipOrden extends StatelessWidget {
  final String texto;
  final VoidCallback onQuitar;
  final Color? color;

  const _ChipOrden({required this.texto, required this.onQuitar, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kDuelosAcento;
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(texto,
            style: TextStyle(fontSize: 8, color: c, fontFamily: 'Cinzel')),
        GestureDetector(
          onTap: onQuitar,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.close, size: 11, color: c),
          ),
        ),
      ]),
    );
  }
}

class _InformeDialog extends StatelessWidget {
  final int turno;
  final List<_EventoVista> eventos;
  const _InformeDialog({required this.turno, required this.eventos});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return AlertDialog(
      backgroundColor: war.superficie,
      title: Text('INFORME DEL TURNO $turno',
          style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 13,
              letterSpacing: 2,
              color: war.primario)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in eventos)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(e.celda,
                          style: TextStyle(
                              fontSize: 9,
                              color: war.textoTenue,
                              fontFamily: 'Cinzel')),
                    ),
                    Expanded(
                      child: Text(e.texto,
                          style: TextStyle(
                              fontSize: 9,
                              color: e.propio
                                  ? kDuelosAcento
                                  : e.rival
                                      ? _kRival
                                      : war.texto,
                              fontFamily: 'Cinzel')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CERRAR',
              style: TextStyle(fontFamily: 'Cinzel', color: war.primario)),
        ),
      ],
    );
  }
}

class _AyudaDialog extends StatelessWidget {
  const _AyudaDialog();

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final estilo = TextStyle(
        fontSize: 9, color: war.texto, fontFamily: 'Cinzel', height: 1.5);
    const lineas = [
      '★ Tu $kDuelosTerminoComandante: si cae, pierdes. El rival no sabe '
          'cuál de tus dos generales es.',
      'Toca una casilla para ver sus cartas y darles órdenes: MOVER o '
          'lanzar la habilidad del general.',
      'Las órdenes se resuelven a la vez para los dos jugadores al pulsar '
          'FIN DE TURNO.',
      'Combate: gana la casilla quien sume más ataque. Los soldados del '
          'perdedor mueren; sus generales pierden 1 vida y retroceden.',
      'Habilidad de ejército: una vez por partida, desde el turno 2.',
      'PC: +3 por cada soldado enemigo destruido y +50 por cada general '
          'enemigo derrotado, en combate, con disparos o con habilidades.',
      'Al terminar: el ganador recibe 500 XP y 100 de dinero; el perdedor, '
          '250 XP y 50. Además, 1 Cristal Zero por cada 20 PC y 1 por '
          'participar (no si te rindes o pierdes por inactividad).',
      '🎯 Disparo lejano: 2 por partida, desde el turno 3, a cualquier '
          'casilla.',
      '🌊 Desde el turno 3 se hunden casillas cada turno (más desde el 10 '
          'y el 20).',
      'Si no pulsas FIN DE TURNO a tiempo, tu turno se cierra sin mover. '
          'Con 3 seguidos pierdes el duelo.',
    ];
    return AlertDialog(
      backgroundColor: war.superficie,
      title: Text('CÓMO SE JUEGA',
          style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 13,
              letterSpacing: 2,
              color: war.primario)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in lineas)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l, style: estilo),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('ENTENDIDO',
              style: TextStyle(fontFamily: 'Cinzel', color: war.primario)),
        ),
      ],
    );
  }
}
