// lib/widgets/bombardeo_overlay.dart
//
// BOMBARDEO de las batallas de historia (p. ej. humanos_1 · Los hermanos del
// alba) y de los MODOS DE PARTIDA con catástrofes (lluvia de meteoritos /
// apocalipsis, ver modo_partida.dart). El servidor publica en la partida el
// plan del turno en curso (campo `bombardeo`, ver HistoriaBombardeo.cs y
// ModosCatastrofe.cs):
//
//   {
//     turno: 3, disparosPorFila: 4, disparos: 48,   // 4 en CADA fila (12 filas)
//     disparosBase: 5, reduccion: 1,
//     prob: { "C3": 29, "C4": 17, … },              // % de que caiga un disparo
//     desactivadoras: [ { coord: "G8", hastaTurno: 4, centro: true }, … ],
//     filas: { … },                                 // solo lo usa el servidor
//     modo: "meteoritos" | "apocalipsis",           // solo modos catástrofe
//     paralisisPorFila: 1, paralisis: 8,            // solo apocalipsis
//   }
//
// Aquí se pinta:
//   • BombardeoLayer: sobre la rejilla, el % de cada celda en una pequeña
//     etiqueta en su esquina (sin tintar la celda, para no tapar el tablero
//     ni las casillas de movimiento); y las
//     casillas DESACTIVADORAS con un anillo cian, el icono ⛨ y los turnos que
//     les quedan en esa posición.
//   • BombardeoLeyenda: chip fijo en la esquina del tablero con los disparos
//     que caerán este turno (por fila en historia/apocalipsis; totales en la
//     lluvia de meteoritos).
//   • CatastrofeAvisoChip: en los modos catástrofe, cuando NO hay plan activo,
//     avisa de en qué turno cae la próxima lluvia/apocalipsis.
//
// Es puramente informativo: no intercepta toques.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_config.dart';
import '../models/modo_partida.dart';
import 'cell_widget.dart' show kCellW, kCellH, kLabelW;

/// Una casilla desactivadora del turno.
class DesactivadoraVista {
  final String coord;

  /// Último turno (inclusive) en que sigue en esta posición.
  final int hastaTurno;

  /// True si es la del centro del tablero.
  final bool centro;

  const DesactivadoraVista({
    required this.coord,
    required this.hastaTurno,
    required this.centro,
  });
}

/// Plan de bombardeo del turno tal y como lo publica el servidor.
class BombardeoVista {
  final int turno;

  /// Disparos que caerán este turno EN CADA FILA (ya descontadas las
  /// desactivadoras). En la lluvia de meteoritos, disparos TOTALES.
  final int disparosPorFila;

  /// Disparos totales del turno (suma de todas las filas).
  final int disparos;
  final int disparosBase;

  /// Disparos que se han quitado EN CADA FILA por las desactivadoras ocupadas.
  final int reduccion;

  /// coord → % (1..100) de que caiga al menos un impacto en la celda.
  final Map<String, int> prob;
  final List<DesactivadoraVista> desactivadoras;

  /// Modo de partida que origina el plan. `normal` = bombardeo de historia.
  final ModoPartida modo;

  /// Parálisis por fila / totales (solo apocalipsis; 0 en el resto).
  final int paralisisPorFila;
  final int paralisis;

  const BombardeoVista({
    required this.turno,
    required this.disparosPorFila,
    required this.disparos,
    required this.disparosBase,
    required this.reduccion,
    required this.prob,
    required this.desactivadoras,
    this.modo = ModoPartida.normal,
    this.paralisisPorFila = 0,
    this.paralisis = 0,
  });

  /// True si el plan viene de un modo catástrofe (no de una historia).
  bool get esCatastrofe => modo.tieneCatastrofes;

  /// Lee el campo `bombardeo` del estado de la partida. null si no lo hay
  /// (partidas sin bombardeo).
  static BombardeoVista? fromEstado(Map<String, dynamic> estado) {
    final raw = estado['bombardeo'];
    if (raw is! Map) return null;
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;

    final prob = <String, int>{};
    final rawProb = raw['prob'];
    if (rawProb is Map) {
      rawProb.forEach((k, v) {
        final p = n(v);
        if (p > 0) prob[k.toString()] = p.clamp(1, 100);
      });
    }

    final desact = <DesactivadoraVista>[];
    final rawDes = raw['desactivadoras'];
    if (rawDes is List) {
      for (final d in rawDes) {
        if (d is! Map) continue;
        final coord = (d['coord'] ?? '').toString();
        if (coord.isEmpty) continue;
        desact.add(DesactivadoraVista(
          coord: coord,
          hastaTurno: n(d['hastaTurno']),
          centro: d['centro'] == true,
        ));
      }
    }

    final base = n(raw['disparosBase']);
    final reduccion = n(raw['reduccion']);
    return BombardeoVista(
      turno: n(raw['turno']),
      disparosPorFila: raw['disparosPorFila'] is num
          ? n(raw['disparosPorFila'])
          : math.max(0, base - reduccion),
      disparos: n(raw['disparos']),
      disparosBase: base,
      reduccion: reduccion,
      prob: prob,
      desactivadoras: desact,
      modo: modoPartidaFromString(raw['modo']?.toString()),
      paralisisPorFila: n(raw['paralisisPorFila']),
      paralisis: n(raw['paralisis']),
    );
  }
}

const Color _rojo = Color(0xFFFF4A3A);
const Color _cian = Color(0xFF3AD8FF);
const Color _naranja = Color(0xFFFF8A3A);
const Color _granate = Color(0xFFD04A6A);

/// Color de acento de la capa según el origen del plan.
Color _acento(ModoPartida modo) {
  switch (modo) {
    case ModoPartida.meteoritos:
      return _naranja;
    case ModoPartida.apocalipsis:
      return _granate;
    case ModoPartida.normal:
      return _rojo;
  }
}

/// Icono de la etiqueta de % de cada celda.
String _iconoCelda(ModoPartida modo) {
  switch (modo) {
    case ModoPartida.meteoritos:
      return '☄';
    case ModoPartida.apocalipsis:
      return '☠';
    case ModoPartida.normal:
      return '💥';
  }
}

/// Capa que se superpone a la rejilla (va dentro del Stack de la rejilla, así
/// que hereda la perspectiva 3D y queda alineada con las celdas).
class BombardeoLayer extends StatelessWidget {
  final GameConfig config;
  final BombardeoVista vista;

  const BombardeoLayer({super.key, required this.config, required this.vista});

  @override
  Widget build(BuildContext context) {
    // coord → (fila, columna) de la rejilla, una sola pasada.
    final pos = <String, (int, int)>{};
    for (int ri = 0; ri < config.rows; ri++) {
      for (int ci = 0; ci < config.cols; ci++) {
        pos[config.coordLabel(ri, ci)] = (ri, ci);
      }
    }

    Rect? rect(String coord) {
      final p = pos[coord];
      if (p == null) return null;
      return Rect.fromLTWH(
          kLabelW + p.$2 * kCellW, p.$1 * kCellH, kCellW, kCellH);
    }

    final hijos = <Widget>[];
    final acento = _acento(vista.modo);
    final icono = _iconoCelda(vista.modo);

    // Probabilidades.
    vista.prob.forEach((coord, pct) {
      final r = rect(coord);
      if (r == null) return;
      hijos.add(Positioned.fromRect(
        rect: r,
        child: _CeldaProbabilidad(pct: pct, acento: acento, icono: icono),
      ));
    });

    // Desactivadoras (encima de las probabilidades).
    for (final d in vista.desactivadoras) {
      final r = rect(d.coord);
      if (r == null) continue;
      final turnos = (d.hastaTurno - vista.turno + 1).clamp(1, 99);
      hijos.add(Positioned.fromRect(
        rect: r,
        child: _CeldaDesactivadora(turnos: turnos, centro: d.centro),
      ));
    }

    return IgnorePointer(child: Stack(children: hijos));
  }
}

class _CeldaProbabilidad extends StatelessWidget {
  final int pct;
  final Color acento;
  final String icono;
  const _CeldaProbabilidad({
    required this.pct,
    this.acento = _rojo,
    this.icono = '💥',
  });

  @override
  Widget build(BuildContext context) {
    // Solo la etiqueta con el %: SIN tinte ni borde en la celda. Con el
    // bombardeo por filas casi todas las casillas tienen %, y un fondo de
    // color tapaba el tablero y las casillas de movimiento resaltadas.
    return Stack(
      children: [
        Positioned(
          left: 3,
          bottom: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xE6140606),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: acento.withOpacity(0.8), width: 1),
            ),
            child: Text(
              '$icono $pct%',
              style: const TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFD0C8),
                fontFamily: 'Cinzel',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CeldaDesactivadora extends StatelessWidget {
  final int turnos;
  final bool centro;
  const _CeldaDesactivadora({required this.turnos, required this.centro});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _cian, width: 2),
              boxShadow: [
                BoxShadow(color: _cian.withOpacity(0.45), blurRadius: 10),
              ],
              color: _cian.withOpacity(0.08),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xE6061418),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _cian, width: 1),
            ),
            child: Text(
              '⛨ −1💥/fila · ${turnos}T',
              style: const TextStyle(
                fontSize: 8,
                height: 1.1,
                fontWeight: FontWeight.bold,
                color: Color(0xFFCFF6FF),
                fontFamily: 'Cinzel',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "💥 4 disparos por fila este turno" o, si solo llueve en algunas filas
/// (duelo de humanos_3), "💥 3 disparos este turno · 1 por fila en 3 filas".
/// En los modos catástrofe, el texto propio del modo.
String _textoDisparos(BombardeoVista vista, String quitados) {
  switch (vista.modo) {
    case ModoPartida.meteoritos:
      final total = vista.disparos > 0 ? vista.disparos : vista.disparosPorFila;
      return '☄ LLUVIA DE METEORITOS · caen $total disparo'
          '${total == 1 ? '' : 's'} lejano${total == 1 ? '' : 's'} en el '
          'centro al cerrar el turno';
    case ModoPartida.apocalipsis:
      final d = vista.disparosPorFila;
      final p = vista.paralisisPorFila;
      return '☠ APOCALIPSIS · por fila: $d disparo${d == 1 ? '' : 's'} '
          'lejano${d == 1 ? '' : 's'} + $p parálisis al cerrar el turno';
    case ModoPartida.normal:
      break;
  }
  final filas = vista.prob.keys
      .where((c) => c.isNotEmpty)
      .map((c) => c[0])
      .toSet()
      .length;
  final porFila = vista.disparosPorFila;
  final total = vista.disparos > 0 ? vista.disparos : porFila * filas;
  if (filas > 0 &&
      porFila > 0 &&
      total < porFila * 6 &&
      total == porFila * filas) {
    return '💥 $total disparo${total == 1 ? '' : 's'} este turno · '
        '$porFila por fila en $filas fila${filas == 1 ? '' : 's'} (0 % = a salvo)$quitados';
  }
  return '💥 $porFila disparo${porFila == 1 ? '' : 's'} por fila este turno$quitados';
}

/// Chip con los disparos del turno (por fila), para la esquina del tablero.
class BombardeoLeyenda extends StatelessWidget {
  final BombardeoVista vista;
  const BombardeoLeyenda({super.key, required this.vista});

  @override
  Widget build(BuildContext context) {
    final quitados =
        vista.reduccion > 0 ? '  (−${vista.reduccion} por desactivadoras)' : '';
    final acento = _acento(vista.modo);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xDD0A0A14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: acento.withOpacity(0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _textoDisparos(vista, quitados),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFD0C8),
                fontFamily: 'Cinzel',
              ),
            ),
            if (vista.esCatastrofe) ...[
              const SizedBox(height: 2),
              Text(
                '% = probabilidad de impacto en la casilla · un escudo propio lo bloquea',
                style: TextStyle(
                  fontSize: 8,
                  color: acento.withOpacity(0.85),
                  fontFamily: 'Cinzel',
                ),
              ),
            ],
            if (vista.desactivadoras.isNotEmpty) ...[
              const SizedBox(height: 2),
              const Text(
                '⛨ Ocupa una desactivadora: −1 disparo por fila y escudo 3T',
                style: TextStyle(
                  fontSize: 8,
                  color: Color(0xFFCFF6FF),
                  fontFamily: 'Cinzel',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso de la PRÓXIMA catástrofe (modos meteoritos/apocalipsis) para los
/// turnos en los que no hay plan publicado: "☄ próxima lluvia en el turno 15
/// (faltan 3)". Se pinta en la misma esquina que la leyenda del bombardeo.
class CatastrofeAvisoChip extends StatelessWidget {
  final ModoPartida modo;
  final int turnoActual;

  const CatastrofeAvisoChip({
    super.key,
    required this.modo,
    required this.turnoActual,
  });

  @override
  Widget build(BuildContext context) {
    if (!modo.tieneCatastrofes) return const SizedBox.shrink();
    final proximo = proximoTurnoDeImpacto(turnoActual);
    final faltan = proximo - turnoActual;
    final acento = _acento(modo);
    final que = modo == ModoPartida.meteoritos
        ? 'próxima lluvia'
        : 'próximo apocalipsis';
    final cuando = faltan <= 0
        ? 'este turno'
        : 'turno $proximo (falta${faltan == 1 ? '' : 'n'} $faltan)';
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xCC0A0A14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: acento.withOpacity(0.45)),
        ),
        child: Text(
          '${modo.icono} ${modo.etiqueta} · $que: $cuando',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: acento.withOpacity(0.95),
            fontFamily: 'Cinzel',
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
