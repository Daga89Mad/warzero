// lib/widgets/bombardeo_overlay.dart
//
// BOMBARDEO de las batallas de historia (p. ej. humanos_1 · Los hermanos del
// alba). El servidor publica en la partida el plan del turno en curso (campo
// `bombardeo`, ver HistoriaBombardeo.cs):
//
//   {
//     turno: 3, disparosPorFila: 4, disparos: 48,   // 4 en CADA fila (12 filas)
//     disparosBase: 5, reduccion: 1,
//     prob: { "C3": 29, "C4": 17, … },              // % de que caiga un disparo
//     desactivadoras: [ { coord: "G8", hastaTurno: 4, centro: true }, … ],
//     filas: { … }                                  // solo lo usa el servidor
//   }
//
// Aquí se pinta:
//   • BombardeoLayer: sobre la rejilla, el % de cada celda en una pequeña
//     etiqueta en su esquina (sin tintar la celda, para no tapar el tablero
//     ni las casillas de movimiento); y las
//     casillas DESACTIVADORAS con un anillo cian, el icono ⛨ y los turnos que
//     les quedan en esa posición.
//   • BombardeoLeyenda: chip fijo en la esquina del tablero con los disparos
//     que caerán este turno EN CADA FILA (y cuántos se han quitado por las
//     desactivadoras).
//
// Es puramente informativo: no intercepta toques.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_config.dart';
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
  /// desactivadoras).
  final int disparosPorFila;

  /// Disparos totales del turno (suma de todas las filas).
  final int disparos;
  final int disparosBase;

  /// Disparos que se han quitado EN CADA FILA por las desactivadoras ocupadas.
  final int reduccion;

  /// coord → % (1..100) de que caiga al menos un disparo en la celda.
  final Map<String, int> prob;
  final List<DesactivadoraVista> desactivadoras;

  const BombardeoVista({
    required this.turno,
    required this.disparosPorFila,
    required this.disparos,
    required this.disparosBase,
    required this.reduccion,
    required this.prob,
    required this.desactivadoras,
  });

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
    );
  }
}

const Color _rojo = Color(0xFFFF4A3A);
const Color _cian = Color(0xFF3AD8FF);

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

    // Probabilidades.
    vista.prob.forEach((coord, pct) {
      final r = rect(coord);
      if (r == null) return;
      hijos.add(Positioned.fromRect(
        rect: r,
        child: _CeldaProbabilidad(pct: pct),
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
  const _CeldaProbabilidad({required this.pct});

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
              border: Border.all(color: _rojo.withOpacity(0.8), width: 1),
            ),
            child: Text(
              '💥 $pct%',
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
String _textoDisparos(BombardeoVista vista, String quitados) {
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
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xDD0A0A14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _rojo.withOpacity(0.6)),
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
