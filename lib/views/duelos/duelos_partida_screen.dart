// lib/views/duelos/duelos_partida_screen.dart
//
// MODO DUELOS — partida. De momento muestra el campo de batalla tal como lo ve
// el jugador (vista del servidor: el Comandante rival nunca viene en ella), el
// estado de cada carta y el resultado. Las órdenes del turno (mover, usar
// habilidades, disparar) se añaden en el siguiente paso; el servidor ya las
// acepta en POST /warzero/duelos/turno.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:warzero/services/settings_controller.dart';

import '../../services/duelos_service.dart';
import 'duelos_lobby_screen.dart';

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
  String? _error;
  Timer? _sondeo;
  bool _rindiendo = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _sondeo = Timer.periodic(const Duration(seconds: 5), (_) => _cargar());
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final sala = await _service.partida(widget.salaId, widget.uid);
      if (!mounted) return;
      setState(() {
        _sala = sala;
        _error = null;
      });
      if (sala.finalizada) _sondeo?.cancel();
    } on DuelosError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      // Fallo de red puntual: el siguiente sondeo lo reintenta.
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _rindiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final sala = _sala;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text(
          sala?.nombre.toUpperCase() ?? 'DUELO',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 3,
            color: war.primario,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (sala != null && sala.enCurso)
            IconButton(
              tooltip: 'Rendirse',
              icon: Icon(Icons.flag_outlined, color: war.error),
              onPressed: _rindiendo ? null : _rendirse,
            ),
        ],
      ),
      body: sala == null
          ? (_error != null
              ? DuelosMensaje(
                  icono: Icons.error_outline,
                  texto: _error!,
                  accion: 'REINTENTAR',
                  onAccion: _cargar)
              : Center(child: CircularProgressIndicator(color: war.primario)))
          : sala.partida == null
              ? const DuelosMensaje(
                  icono: Icons.hourglass_top,
                  texto: 'El duelo todavía no ha empezado.')
              : _cuerpo(sala, sala.partida!),
    );
  }

  Widget _cuerpo(DuelosSala sala, Map<String, dynamic> p) {
    final war = context.war;
    final vista = _VistaPartida.fromMap(p);
    final rival = sala.jugadores.where((j) => j.uid != widget.uid).toList();
    final aliasRival = rival.isEmpty ? 'Rival' : rival.first.alias;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (sala.finalizada) _BannerResultado(vista: vista, motivo: sala.motivo),
        // ── Cabecera ──
        Row(children: [
          Text('TURNO ${vista.turno}/${vista.turnoLimite}',
              style: TextStyle(
                  fontSize: 11,
                  color: war.primario,
                  fontFamily: 'Cinzel',
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('contra $aliasRival',
              style: TextStyle(
                  fontSize: 9, color: war.textoTenue, fontFamily: 'Cinzel')),
        ]),
        const SizedBox(height: 8),
        for (final j in vista.jugadores) _FilaRecursos(jugador: j),
        const SizedBox(height: 10),

        // ── Tablero ──
        _Tablero(vista: vista),
        const SizedBox(height: 8),
        _Leyenda(),
        const SizedBox(height: 12),

        if (sala.enCurso)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: war.primario.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: war.primario.withOpacity(0.3)),
            ),
            child: Text(
              'Las órdenes de batalla (mover, usar habilidades y disparar) '
              'llegan en la próxima actualización de la app.',
              style: TextStyle(
                  fontSize: 9,
                  color: war.texto,
                  fontFamily: 'Cinzel',
                  height: 1.5),
            ),
          ),
        const SizedBox(height: 12),

        // ── Cartas ──
        const DuelosEtiqueta('TUS CARTAS'),
        for (final c in vista.cartas.where((c) => c.propia)) _FilaCarta(carta: c),
        const SizedBox(height: 10),
        const DuelosEtiqueta('CARTAS RIVALES'),
        for (final c in vista.cartas.where((c) => !c.propia)) _FilaCarta(carta: c),

        if (vista.eventos.isNotEmpty) ...[
          const SizedBox(height: 10),
          const DuelosEtiqueta('ÚLTIMO TURNO'),
          for (final e in vista.eventos)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                  '${e.celda.isEmpty ? '' : '${e.celda} · '}${e.texto}',
                  style: TextStyle(
                      fontSize: 8,
                      color: e.propio ? kDuelosAcento : war.textoTenue,
                      fontFamily: 'Cinzel')),
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODELO DE LA VISTA (lo que manda el servidor en `partida`)
// ─────────────────────────────────────────────────────────────

class _VistaPartida {
  final int turno;
  final int turnoLimite;
  final int filas;
  final int columnas;
  final String resultado;
  final Set<String> bloqueadas;
  final Set<String> hundidas;
  final Set<String> hundimientos;
  final Set<String> muros;
  final Map<String, bool> escudos; // celda → propio
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

  static Set<String> _celdas(Object? o) =>
      (o as List? ?? const []).map((e) => e.toString()).toSet();

  static List<Map<String, dynamic>> _maps(Object? o) => (o as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  factory _VistaPartida.fromMap(Map<String, dynamic> p) => _VistaPartida(
        turno: (p['turno'] as num?)?.toInt() ?? 1,
        turnoLimite: (p['turnoLimite'] as num?)?.toInt() ?? 35,
        filas: (p['filas'] as num?)?.toInt() ?? 7,
        columnas: (p['columnas'] as num?)?.toInt() ?? 7,
        resultado: p['resultado'] as String? ?? '',
        bloqueadas: _celdas(p['bloqueadas']),
        hundidas: _celdas(p['hundidas']),
        hundimientos: _celdas(p['hundimientos']),
        muros: _maps(p['muros']).map((m) => m['celda'].toString()).toSet(),
        escudos: {
          for (final m in _maps(p['escudos']))
            m['celda'].toString(): m['propio'] == true
        },
        jugadores: _maps(p['jugadores']).map(_JugadorVista.fromMap).toList(),
        cartas: _maps(p['cartas']).map(_CartaVista.fromMap).toList(),
        eventos: _maps(p['eventos']).map(_EventoVista.fromMap).toList(),
      );
}

class _JugadorVista {
  final bool propio;
  final String ejercito;
  final int disparosRestantes;
  final String habilidadEjercito;
  final bool habilidadEjercitoUsada;

  const _JugadorVista({
    required this.propio,
    required this.ejercito,
    required this.disparosRestantes,
    required this.habilidadEjercito,
    required this.habilidadEjercitoUsada,
  });

  factory _JugadorVista.fromMap(Map<String, dynamic> m) {
    final h = Map<String, dynamic>.from(m['habilidadEjercito'] as Map? ?? {});
    return _JugadorVista(
      propio: m['propio'] == true,
      ejercito: m['ejercito'] as String? ?? '',
      disparosRestantes: (m['disparosRestantes'] as num?)?.toInt() ?? 0,
      habilidadEjercito: h['nombre'] as String? ?? '',
      habilidadEjercitoUsada: h['usada'] == true,
    );
  }
}

class _CartaVista {
  final int id;
  final bool propia;
  final String nombre;
  final String papel;
  final String celda;
  final int ataque;
  final bool esGeneral;
  final int vidas;
  final int vidasMax;
  final bool esComandante;
  final bool esClon;
  final String habilidad;
  final bool habilidadLista;
  final int recargaLista;
  final List<String> efectos;

  const _CartaVista({
    required this.id,
    required this.propia,
    required this.nombre,
    required this.papel,
    required this.celda,
    required this.ataque,
    required this.esGeneral,
    required this.vidas,
    required this.vidasMax,
    required this.esComandante,
    required this.esClon,
    required this.habilidad,
    required this.habilidadLista,
    required this.recargaLista,
    required this.efectos,
  });

  factory _CartaVista.fromMap(Map<String, dynamic> m) {
    final h = Map<String, dynamic>.from(m['habilidad'] as Map? ?? {});
    final ef = Map<String, dynamic>.from(m['efectos'] as Map? ?? {});
    const nombresEfecto = {
      'paralizada': 'paralizada',
      'confusa': 'confusa',
      'veneno': 'envenenada',
      'masAtaque': 'furia',
      'masMovimiento': 'marcha',
      'supervivencia': 'supervivencia',
    };
    return _CartaVista(
      id: (m['id'] as num?)?.toInt() ?? 0,
      propia: m['propia'] == true,
      nombre: m['nombre'] as String? ?? '',
      papel: m['papel'] as String? ?? '',
      celda: m['celda'] as String? ?? '',
      ataque: (m['ataque'] as num?)?.toInt() ?? 0,
      esGeneral: m['esGeneral'] == true,
      vidas: (m['vidas'] as num?)?.toInt() ?? 0,
      vidasMax: (m['vidasMax'] as num?)?.toInt() ?? 0,
      esComandante: m['esComandante'] == true,
      esClon: m['esClon'] == true,
      habilidad: h['nombre'] as String? ?? '',
      habilidadLista: h['lista'] == true,
      recargaLista: (h['recargaLista'] as num?)?.toInt() ?? 0,
      efectos: [
        for (final e in nombresEfecto.entries)
          if (ef[e.key] == true) e.value
      ],
    );
  }

  /// Letra corta para el tablero.
  String get sigla => esGeneral
      ? (esComandante ? '★' : 'G')
      : switch (papel) {
          'Alta' => 'A',
          'Media' => 'M',
          _ => 'B',
        };
}

class _EventoVista {
  final String celda;
  final String texto;
  final bool propio;

  const _EventoVista(
      {required this.celda, required this.texto, required this.propio});

  factory _EventoVista.fromMap(Map<String, dynamic> m) => _EventoVista(
        celda: m['celda'] as String? ?? '',
        texto: m['texto'] as String? ?? '',
        propio: m['propio'] == true,
      );
}

// ─────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────

class _BannerResultado extends StatelessWidget {
  final _VistaPartida vista;
  final String motivo;
  const _BannerResultado({required this.vista, required this.motivo});

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
      'limite' => 'Se alcanzó el límite de turnos.',
      'ambos reyes' => 'Los dos Comandantes cayeron a la vez.',
      '' => '',
      _ => 'El Comandante cayó por: $motivo.',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Column(children: [
        Text(texto,
            style: TextStyle(
                fontSize: 18,
                color: color,
                fontFamily: 'Cinzel',
                letterSpacing: 4,
                fontWeight: FontWeight.bold)),
        if (explicacion.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(explicacion,
              style: TextStyle(
                  fontSize: 9, color: war.texto, fontFamily: 'Cinzel')),
        ],
      ]),
    );
  }
}

class _FilaRecursos extends StatelessWidget {
  final _JugadorVista jugador;
  const _FilaRecursos({required this.jugador});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final color = jugador.propio ? kDuelosAcento : war.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
            '${jugador.propio ? 'TÚ' : 'RIVAL'} · ${jugador.ejercito.toUpperCase()}',
            style: TextStyle(
                fontSize: 9,
                color: color,
                fontFamily: 'Cinzel',
                letterSpacing: 1,
                fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(
            '🎯 ${jugador.disparosRestantes}   '
            '${jugador.habilidadEjercito}: ${jugador.habilidadEjercitoUsada ? 'usada' : 'disponible'}',
            style: TextStyle(
                fontSize: 8, color: war.textoTenue, fontFamily: 'Cinzel')),
      ]),
    );
  }
}

class _Tablero extends StatelessWidget {
  final _VistaPartida vista;
  const _Tablero({required this.vista});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return AspectRatio(
      aspectRatio: vista.columnas / vista.filas,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: war.borde.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            for (int f = 0; f < vista.filas; f++)
              Expanded(
                child: Row(
                  children: [
                    for (int c = 0; c < vista.columnas; c++)
                      Expanded(
                          child: _Casilla(
                              vista: vista,
                              coord:
                                  '${String.fromCharCode(65 + f)}${c + 1}')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Casilla extends StatelessWidget {
  final _VistaPartida vista;
  final String coord;
  const _Casilla({required this.vista, required this.coord});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final bloqueada = vista.bloqueadas.contains(coord);
    final hundida = vista.hundidas.contains(coord);
    final seHunde = vista.hundimientos.contains(coord);
    final muro = vista.muros.contains(coord);
    final escudo = vista.escudos[coord];
    final cartas = vista.cartas.where((c) => c.celda == coord).toList();

    Color fondo = war.superficie;
    if (bloqueada) fondo = war.borde.withOpacity(0.55);
    if (hundida) fondo = Colors.black;
    if (muro) fondo = const Color(0xFF6B4F2A);

    Color borde = war.borde.withOpacity(0.25);
    double grosor = 0.5;
    if (seHunde) {
      borde = war.error;
      grosor = 1.5;
    } else if (escudo != null) {
      borde = escudo ? kDuelosAcento : const Color(0xFF4090E0);
      grosor = 1.5;
    }

    return Container(
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: borde, width: grosor),
      ),
      child: Stack(children: [
        Positioned(
          left: 2,
          top: 1,
          child: Text(coord,
              style: TextStyle(
                  fontSize: 6,
                  color: war.textoTenue.withOpacity(0.6),
                  fontFamily: 'Cinzel')),
        ),
        if (hundida)
          Center(
              child: Text('≈',
                  style: TextStyle(color: war.textoTenue, fontSize: 14))),
        if (cartas.isNotEmpty)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 1,
              runSpacing: 1,
              children: [
                for (final c in cartas)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: (c.propia ? kDuelosAcento : war.error)
                          .withOpacity(0.85),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      c.esGeneral ? '${c.sigla}${c.vidas}' : c.sigla,
                      style: const TextStyle(
                          fontSize: 7,
                          color: Colors.black,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
      ]),
    );
  }
}

class _Leyenda extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final estilo =
        TextStyle(fontSize: 7, color: war.textoTenue, fontFamily: 'Cinzel');
    return Wrap(spacing: 10, runSpacing: 4, children: [
      Text('G2 = general con 2 vidas', style: estilo),
      Text('★ = tu Comandante', style: estilo),
      Text('A / M / B = soldado alto, medio, básico', style: estilo),
      Text('borde rojo = se hunde este turno', style: estilo),
    ]);
  }
}

class _FilaCarta extends StatelessWidget {
  final _CartaVista carta;
  const _FilaCarta({required this.carta});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final c = carta;
    final detalles = <String>[
      '⚔ ${c.ataque}',
      if (c.esGeneral) '❤ ${c.vidas}/${c.vidasMax}',
      if (c.habilidad.isNotEmpty)
        c.propia
            ? '${c.habilidad}${c.habilidadLista ? ' (lista)' : ' (turno ${c.recargaLista})'}'
            : c.habilidad,
      ...c.efectos,
      if (c.esClon) 'clon',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 26,
          child: Text(c.celda,
              style: TextStyle(
                  fontSize: 8,
                  color: war.textoTenue,
                  fontFamily: 'Cinzel')),
        ),
        if (c.esComandante)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.shield, size: 11, color: war.primario),
          ),
        Expanded(
          child: Text('${c.nombre}  ·  ${detalles.join('  ·  ')}',
              style: TextStyle(
                  fontSize: 8,
                  color: c.propia ? war.texto : war.texto.withOpacity(0.8),
                  fontFamily: 'Cinzel')),
        ),
      ]),
    );
  }
}
