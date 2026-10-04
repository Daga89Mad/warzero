// lib/widgets/historia_tunel.dart
//
// Capa del MODO HISTORIA con el TÚNEL INUNDABLE y las MARCAS del tablero
// (p. ej. humanos_2 · El túnel de Soren). El servidor publica en la partida:
//
//   tunel: {                                  (HistoriaTuneles.cs)
//     celdas: [...],            // todas las casillas del túnel
//     bocas: { "E13": ["E14"], ... },   // casilla de boca → celdas exteriores
//     movimiento: 2,            // movimiento de TODAS las cartas dentro
//     sinExplorar: [...],       // casillas de tramos con agua aún sin pisar
//     limpias: [...],           // pasos seguros ya encontrados
//     inundadas: [...],         // casillas inundadas (impracticables)
//     ultimo: { turno, inundadas, limpias, ahogadas: [{coord, nombre}],
//               revertidas: [{desde, hacia, nombre}] }
//   }
//   marcasHistoria: {                         (WarZeroHistoriaReglas.cs)
//     rolesBot: { "A9": {cazadores: 3, asalto: 0}, ... },
//     vip: [instanceId...],     // cartas clave del jugador (👑)
//     guarnicion: [instanceId...], // guarnición del jugador (no se mueve)
//     prohibidas: ["J16"],      // celdas donde el jugador no puede entrar
//     turnoAsalto: 8, asaltoGeneral: false, reunion: "C2",
//     bloqueadas: ["C3", ...]   // nadie las pisa ni las atraviesa (duelo)
//   }
//   duelo: {                                  (HistoriaDuelo.cs · humanos_3)
//     modo: "generales" | "embestida",
//     roles: {instanceId: "jefe"|"cazador"|"verdugo"}, vidas, vidasMax, nombres,
//     paralizadoHasta, sinEscudoHasta, rompe: {turno, prob}, turno,
//     turnoLimite, lluviaEsteTurno, rompeEsteTurno, canaliza,
//     ultimo: {turno, eventos: [{tipo, texto, coord}]},
//     embestida: {                            (solo modo "embestida", bionicos_3)
//       pilares: [...], escombros: [...],
//       carga: {turno, dir, origen, fin, choque, carril: [...]},
//       cargaEsteTurno, proximaCarga, onda, enL, bordeAturde
//     }
//   }
//
// Aquí está:
//   • TunelVista.destinos: el movimiento con las reglas del túnel (mismo
//     algoritmo que HistoriaTuneles.Destinos en el servidor, que es quien
//     manda: lo que no cumpla las reglas vuelve a su casilla).
//   • HistoriaCapaLayer: pinta el túnel (oscuro = sin explorar, ✓ = limpia,
//     azul con 💧 = inundada), los papeles del bot (🎯 cazadores, ⚔ asalto) y
//     tus cartas clave (👑). No intercepta toques.
//   • HistoriaCapaLeyenda: chip con el asalto general y el estado del túnel.

import 'package:flutter/material.dart';

import '../models/game_config.dart';
import 'cell_widget.dart' show kCellW, kCellH, kLabelW;

List<String> _strs(dynamic v) => v is List
    ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
    : <String>[];

int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

/// [s] repetido [n] veces (entre 0 y 9).
String _rep(String s, int n) => n <= 0 ? '' : s * (n > 9 ? 9 : n);

/// Estado público del túnel.
class TunelVista {
  final Set<String> celdas;
  final Map<String, Set<String>> bocas;
  final int movimiento;
  final Set<String> sinExplorar;
  final Set<String> limpias;
  final Set<String> inundadas;

  /// Lo que pasó al resolver el último turno.
  final int ultimoTurno;
  final List<String> ultimoInundadas;
  final List<String> ultimoLimpias;
  final List<({String coord, String nombre})> ultimoAhogadas;
  final List<({String desde, String hacia, String nombre})> ultimoRevertidas;

  const TunelVista({
    required this.celdas,
    required this.bocas,
    required this.movimiento,
    required this.sinExplorar,
    required this.limpias,
    required this.inundadas,
    required this.ultimoTurno,
    required this.ultimoInundadas,
    required this.ultimoLimpias,
    required this.ultimoAhogadas,
    required this.ultimoRevertidas,
  });

  /// Lee el campo `tunel` del estado. null si la batalla no tiene túnel.
  static TunelVista? fromEstado(Map<String, dynamic> estado) {
    final raw = estado['tunel'];
    if (raw is! Map) return null;
    final celdas = _strs(raw['celdas']).toSet();
    if (celdas.isEmpty) return null;

    final bocas = <String, Set<String>>{};
    final rawBocas = raw['bocas'];
    if (rawBocas is Map) {
      rawBocas.forEach((k, v) => bocas[k.toString()] = _strs(v).toSet());
    }

    final ult = raw['ultimo'] is Map ? raw['ultimo'] as Map : const {};
    final ahogadas = <({String coord, String nombre})>[];
    if (ult['ahogadas'] is List) {
      for (final a in ult['ahogadas'] as List) {
        if (a is! Map) continue;
        ahogadas.add((
          coord: (a['coord'] ?? '').toString(),
          nombre: (a['nombre'] ?? 'Carta').toString(),
        ));
      }
    }
    final revertidas = <({String desde, String hacia, String nombre})>[];
    if (ult['revertidas'] is List) {
      for (final a in ult['revertidas'] as List) {
        if (a is! Map) continue;
        revertidas.add((
          desde: (a['desde'] ?? '').toString(),
          hacia: (a['hacia'] ?? '').toString(),
          nombre: (a['nombre'] ?? 'Carta').toString(),
        ));
      }
    }

    final mov = _n(raw['movimiento']);
    return TunelVista(
      celdas: celdas,
      bocas: bocas,
      movimiento: mov > 0 ? mov : 2,
      sinExplorar: _strs(raw['sinExplorar']).toSet(),
      limpias: _strs(raw['limpias']).toSet(),
      inundadas: _strs(raw['inundadas']).toSet(),
      ultimoTurno: _n(ult['turno']),
      ultimoInundadas: _strs(ult['inundadas']),
      ultimoLimpias: _strs(ult['limpias']),
      ultimoAhogadas: ahogadas,
      ultimoRevertidas: revertidas,
    );
  }

  bool contiene(String coord) => celdas.contains(coord);

  bool _esBocaDe(String interior, String exterior) =>
      bocas[interior]?.contains(exterior) ?? false;

  /// Casillas a las que puede ir una carta que empieza en [origen] con las
  /// reglas del túnel (sin incluir el origen):
  ///   • empezando FUERA: [movPropio] pasos por el exterior; el túnel es pared
  ///     salvo entrar por una BOCA desde su celda exterior, y entrar termina el
  ///     movimiento;
  ///   • empezando DENTRO: [movimiento] pasos por casillas del túnel no
  ///     inundadas, o saliendo por una boca (y siguiendo fuera con los pasos que
  ///     queden). Entrar en una casilla sin explorar termina el movimiento.
  /// [vecinos] da las 4 vecinas ortogonales que existen en la rejilla;
  /// [transitable] si una celda EXTERIOR se puede pisar; [aterriza] si se
  /// puede terminar en ella.
  Set<String> destinos({
    required String origen,
    required int movPropio,
    required List<String> Function(String) vecinos,
    required bool Function(String) transitable,
    required bool Function(String) aterriza,
  }) {
    final res = <String>{};
    final empiezaDentro = celdas.contains(origen);
    final mov = empiezaDentro ? movimiento : movPropio;
    if (mov <= 0) return res;

    final visto = <String, int>{origen: 0};
    final cola = <(String, int)>[(origen, 0)];
    var head = 0;
    while (head < cola.length) {
      final (cur, d) = cola[head++];
      if (d >= mov) continue;
      final curDentro = celdas.contains(cur);
      for (final n in vecinos(cur)) {
        final nd = d + 1;
        if ((visto[n] ?? 999) <= nd) continue;
        final nDentro = celdas.contains(n);
        if (nDentro) {
          if (inundadas.contains(n)) continue;
          if (!curDentro) {
            // Entrar desde fuera: solo por la boca, y se acaba el paso.
            if (!_esBocaDe(n, cur)) continue;
            visto[n] = nd;
            if (n != origen) res.add(n);
            continue;
          }
          visto[n] = nd;
          if (n != origen) res.add(n);
          if (sinExplorar.contains(n)) continue; // termina aquí
          if (nd < mov) cola.add((n, nd));
        } else {
          if (curDentro && !_esBocaDe(cur, n)) continue; // pared del túnel
          if (!transitable(n)) continue;
          visto[n] = nd;
          if (n != origen && aterriza(n)) res.add(n);
          if (nd < mov) cola.add((n, nd));
        }
      }
    }
    return res;
  }
}

/// Marcas de la batalla para el tablero.
class MarcasHistoriaVista {
  final Map<String, ({int cazadores, int asalto})> rolesBot;
  final Set<String> vip;
  final Set<String> guarnicion;
  final Set<String> prohibidas;
  final int turnoAsalto;
  final bool asaltoGeneral;
  final String reunion;

  /// Casillas que nadie puede pisar ni atravesar (pilares del duelo).
  final Set<String> bloqueadas;

  const MarcasHistoriaVista({
    required this.rolesBot,
    required this.vip,
    required this.guarnicion,
    required this.prohibidas,
    required this.turnoAsalto,
    required this.asaltoGeneral,
    required this.reunion,
    this.bloqueadas = const {},
  });

  static MarcasHistoriaVista? fromEstado(Map<String, dynamic> estado) {
    final raw = estado['marcasHistoria'];
    if (raw is! Map) return null;
    final roles = <String, ({int cazadores, int asalto})>{};
    final rawRoles = raw['rolesBot'];
    if (rawRoles is Map) {
      rawRoles.forEach((k, v) {
        if (v is! Map) return;
        roles[k.toString()] =
            (cazadores: _n(v['cazadores']), asalto: _n(v['asalto']));
      });
    }
    return MarcasHistoriaVista(
      rolesBot: roles,
      vip: _strs(raw['vip']).toSet(),
      guarnicion: _strs(raw['guarnicion']).toSet(),
      prohibidas: _strs(raw['prohibidas']).toSet(),
      turnoAsalto: _n(raw['turnoAsalto']),
      asaltoGeneral: raw['asaltoGeneral'] == true,
      reunion: (raw['reunion'] ?? '').toString(),
      bloqueadas: _strs(raw['bloqueadas']).toSet(),
    );
  }
}

/// Estado del DUELO de generales (campo `duelo`, humanos_3).
class DueloVista {
  /// instanceId → rol ("jefe" | "cazador" | "verdugo").
  final Map<String, String> roles;
  final Map<String, int> vidas;
  final Map<String, int> vidasMax;
  final Map<String, String> nombres;
  final int paralizadoHasta;
  final int sinEscudoHasta;
  final int rompeTurno;
  final Map<String, int> rompeProb;
  final int turno;
  final int turnoLimite;
  final bool lluviaEsteTurno;
  final bool rompeEsteTurno;
  final bool canaliza;
  final int ultimoTurno;

  /// Sucesos de la última resolución. `malo` = le perjudica al jugador.
  final List<({String tipo, String texto, String coord, bool malo})> eventos;

  /// Dueños del jefe y de los generales. En el duelo INVERTIDO
  /// (`jugadorEsJefe`) el jugador lleva al jefe.
  final String jefeUid;
  final String generalesUid;
  final bool jugadorEsJefe;
  final int movimientoJefe;

  /// Lluvia de rocas MANUAL (duelo invertido): la lanza el jugador desde la
  /// carta del jefe cuando no está recargando (`lluviaDisponible`, válido para
  /// el turno `turno`). Elige las casillas: como mucho `lluviaPorFila` por fila
  /// y `lluviaMaxFilas` filas (0 = todas). El turno en que la lanza no se mueve.
  final bool lluviaManual;
  final bool lluviaDisponible;
  final int lluviaRecarga;
  final int lluviaUltimoTurno;
  final int lluviaMaxFilas;
  final int lluviaPorFila;

  /// Modo EMBESTIDA (bionicos_3): un solo general contra un jefe que carga.
  /// Pilares en pie (aturden), escombros (bloquean pero ya no aturden), la
  /// carga publicada para `cargaTurno` (carril que barre, ancho 3) y las
  /// fases activas (onda de choque, giro en L).
  final bool embestida;
  final Set<String> pilares;
  final Set<String> escombros;
  final int cargaTurno;
  final String cargaDir;
  final String cargaFin;
  final String cargaChoque;
  final Set<String> cargaCarril;
  final int proximaCarga;
  final bool onda;
  final bool enL;
  final bool bordeAturde;

  const DueloVista({
    required this.roles,
    required this.vidas,
    required this.vidasMax,
    required this.nombres,
    required this.paralizadoHasta,
    required this.sinEscudoHasta,
    required this.rompeTurno,
    required this.rompeProb,
    required this.turno,
    required this.turnoLimite,
    required this.lluviaEsteTurno,
    required this.rompeEsteTurno,
    required this.canaliza,
    required this.ultimoTurno,
    required this.eventos,
    this.jefeUid = '',
    this.generalesUid = '',
    this.jugadorEsJefe = false,
    this.movimientoJefe = 2,
    this.lluviaManual = false,
    this.lluviaDisponible = false,
    this.lluviaRecarga = 0,
    this.lluviaUltimoTurno = 0,
    this.lluviaMaxFilas = 0,
    this.lluviaPorFila = 1,
    this.embestida = false,
    this.pilares = const {},
    this.escombros = const {},
    this.cargaTurno = 0,
    this.cargaDir = '',
    this.cargaFin = '',
    this.cargaChoque = '',
    this.cargaCarril = const {},
    this.proximaCarga = 0,
    this.onda = false,
    this.enL = false,
    this.bordeAturde = false,
  });

  static DueloVista? fromEstado(Map<String, dynamic> estado) {
    final raw = estado['duelo'];
    if (raw is! Map) return null;
    Map<String, int> ints(dynamic v) {
      final res = <String, int>{};
      if (v is Map) v.forEach((k, x) => res[k.toString()] = _n(x));
      return res;
    }

    final roles = <String, String>{};
    if (raw['roles'] is Map) {
      (raw['roles'] as Map)
          .forEach((k, v) => roles[k.toString()] = v.toString());
    }
    final nombres = <String, String>{};
    if (raw['nombres'] is Map) {
      (raw['nombres'] as Map)
          .forEach((k, v) => nombres[k.toString()] = v.toString());
    }
    final rompe = raw['rompe'] is Map ? raw['rompe'] as Map : const {};
    final lluvia = raw['lluvia'] is Map ? raw['lluvia'] as Map : const {};
    final ult = raw['ultimo'] is Map ? raw['ultimo'] as Map : const {};
    final emb = raw['embestida'] is Map ? raw['embestida'] as Map : const {};
    final carga = emb['carga'] is Map ? emb['carga'] as Map : const {};
    final eventos = <({String tipo, String texto, String coord, bool malo})>[];
    if (ult['eventos'] is List) {
      for (final e in ult['eventos'] as List) {
        if (e is! Map) continue;
        eventos.add((
          tipo: (e['tipo'] ?? '').toString(),
          texto: (e['texto'] ?? '').toString(),
          coord: (e['coord'] ?? '').toString(),
          malo: e['malo'] == true,
        ));
      }
    }
    return DueloVista(
      roles: roles,
      vidas: ints(raw['vidas']),
      vidasMax: ints(raw['vidasMax']),
      nombres: nombres,
      paralizadoHasta: _n(raw['paralizadoHasta']),
      sinEscudoHasta: _n(raw['sinEscudoHasta']),
      rompeTurno: _n(rompe['turno']),
      rompeProb: ints(rompe['prob']),
      turno: _n(raw['turno']),
      turnoLimite: _n(raw['turnoLimite']),
      lluviaEsteTurno: raw['lluviaEsteTurno'] == true,
      rompeEsteTurno: raw['rompeEsteTurno'] == true,
      canaliza: raw['canaliza'] == true,
      ultimoTurno: _n(ult['turno']),
      eventos: eventos,
      jefeUid: (raw['jefeUid'] ?? '').toString(),
      generalesUid: (raw['generalesUid'] ?? '').toString(),
      jugadorEsJefe: raw['jugadorEsJefe'] == true,
      movimientoJefe:
          raw['movimientoJefe'] == null ? 2 : _n(raw['movimientoJefe']),
      lluviaManual: lluvia['manual'] == true,
      lluviaDisponible: lluvia['disponible'] == true,
      lluviaRecarga: _n(lluvia['recarga']),
      lluviaUltimoTurno: _n(lluvia['ultimoTurno']),
      lluviaMaxFilas: _n(lluvia['maxFilas']),
      lluviaPorFila: lluvia['porFila'] == null ? 1 : _n(lluvia['porFila']),
      embestida: raw['modo'] == 'embestida',
      pilares: _strs(emb['pilares']).toSet(),
      escombros: _strs(emb['escombros']).toSet(),
      cargaTurno: _n(carga['turno']),
      cargaDir: (carga['dir'] ?? '').toString(),
      cargaFin: (carga['fin'] ?? '').toString(),
      cargaChoque: (carga['choque'] ?? '').toString(),
      cargaCarril: _strs(carga['carril']).toSet(),
      proximaCarga: _n(emb['proximaCarga']),
      onda: emb['onda'] == true,
      enL: emb['enL'] == true,
      bordeAturde: emb['bordeAturde'] == true,
    );
  }

  /// True si en [turnoActual] el jefe embiste (hay carril publicado).
  bool cargaEn(int turnoActual) =>
      embestida &&
      cargaTurno == turnoActual &&
      cargaDir.isNotEmpty &&
      cargaCarril.isNotEmpty;

  /// True si el jefe NO puede moverse en [turnoActual] por las reglas del
  /// duelo (paralizado o canalizando la lluvia del calendario). La lluvia
  /// MANUAL la controla la pantalla de juego (solo si el jugador la lanza).
  bool jefeInmovil(int turnoActual) =>
      paralizado(turnoActual) ||
      (!lluviaManual && canaliza && turno == turnoActual);

  /// True si en [turnoActual] el jugador puede lanzar la lluvia manual.
  bool lluviaLista(int turnoActual) =>
      lluviaManual && lluviaDisponible && turno == turnoActual;

  /// Turno en que la lluvia manual vuelve a estar lista.
  int get lluviaListaEnTurno =>
      lluviaUltimoTurno <= 0 ? 1 : lluviaUltimoTurno + lluviaRecarga + 1;

  String? idDe(String rol) {
    for (final e in roles.entries) {
      if (e.value == rol) return e.key;
    }
    return null;
  }

  String nombreDe(String rol) {
    final id = idDe(rol);
    final n = id == null ? '' : (nombres[id] ?? '');
    return n.replaceFirst('General ', '');
  }

  int vidasDe(String rol) {
    final id = idDe(rol);
    return id == null ? 0 : (vidas[id] ?? 0);
  }

  bool paralizado(int turno) => turno <= paralizadoHasta;
  bool sinEscudo(int turno) => turno <= sinEscudoHasta;
}

/// Todo lo que pinta la capa de historia en un turno.
class CapaHistoriaVista {
  final TunelVista? tunel;
  final MarcasHistoriaVista? marcas;

  /// Celdas con alguna carta clave del jugador local (👑).
  final Set<String> celdasVip;

  /// Turno en curso (para la cuenta atrás del asalto general).
  final int turno;

  /// Duelo de generales (null si la batalla no lo es).
  final DueloVista? duelo;

  /// instanceId → celda actual de las cartas del duelo (para pintar vidas).
  final Map<String, String> posiciones;

  /// Lluvia de rocas MANUAL que el jugador ha elegido este turno (casillas
  /// donde caerá una roca) y si sigue eligiéndolas.
  final Set<String> lluviaCeldas;
  final bool lluviaEligiendo;

  const CapaHistoriaVista({
    this.tunel,
    this.marcas,
    this.celdasVip = const {},
    required this.turno,
    this.duelo,
    this.posiciones = const {},
    this.lluviaCeldas = const {},
    this.lluviaEligiendo = false,
  });

  bool get vacia => tunel == null && marcas == null && duelo == null;
}

const Color _agua = Color(0xFF2F7BD8);
const Color _aguaOscura = Color(0xFF071526);
const Color _paredTunel = Color(0xFF6FA8C8);
const Color _verde = Color(0xFF6FE08A);
const Color _rojoCaza = Color(0xFFFF5A48);
const Color _naranja = Color(0xFFFFB040);
const Color _oro = Color(0xFFFFD86A);

/// Capa sobre la rejilla (va dentro del Stack de la rejilla, como la del
/// bombardeo, así que hereda la perspectiva 3D y queda alineada).
class HistoriaCapaLayer extends StatelessWidget {
  final GameConfig config;
  final CapaHistoriaVista vista;

  const HistoriaCapaLayer(
      {super.key, required this.config, required this.vista});

  @override
  Widget build(BuildContext context) {
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

    // ── Túnel ─────────────────────────────────────────────
    final t = vista.tunel;
    if (t != null) {
      for (final coord in t.celdas) {
        final r = rect(coord);
        if (r == null) continue;
        final _EstadoCelda estado = t.inundadas.contains(coord)
            ? _EstadoCelda.inundada
            : t.sinExplorar.contains(coord)
                ? _EstadoCelda.sinExplorar
                : t.limpias.contains(coord)
                    ? _EstadoCelda.limpia
                    : _EstadoCelda.seca;
        hijos.add(Positioned.fromRect(
          rect: r,
          child: _CeldaTunel(
            estado: estado,
            boca: t.bocas.containsKey(coord),
            reciente: t.ultimoInundadas.contains(coord) ||
                t.ultimoLimpias.contains(coord),
          ),
        ));
      }
    }

    // ── Papeles del bot ───────────────────────────────────
    final m = vista.marcas;
    if (m != null) {
      m.rolesBot.forEach((coord, roles) {
        final r = rect(coord);
        if (r == null) return;
        hijos.add(Positioned.fromRect(
          rect: r,
          child:
              _InsigniasRol(cazadores: roles.cazadores, asalto: roles.asalto),
        ));
      });
      for (final coord in m.prohibidas) {
        final r = rect(coord);
        if (r == null) continue;
        hijos.add(Positioned.fromRect(rect: r, child: const _CeldaProhibida()));
      }
    }

    // ── Duelo: casillas bloqueadas, rompe escudos y vidas ──
    if (m != null) {
      for (final coord in m.bloqueadas) {
        final r = rect(coord);
        if (r == null) continue;
        hijos.add(Positioned.fromRect(rect: r, child: const _CeldaBloqueada()));
      }
    }
    final d = vista.duelo;
    if (d != null) {
      // Embestida: pilares en pie / escombros (sobre el negro de la casilla
      // bloqueada) y el carril de la carga de este turno.
      if (d.embestida) {
        for (final coord in d.pilares) {
          final r = rect(coord);
          if (r == null) continue;
          hijos.add(Positioned.fromRect(
              rect: r, child: const _CeldaPilar(enPie: true)));
        }
        for (final coord in d.escombros) {
          final r = rect(coord);
          if (r == null) continue;
          hijos.add(Positioned.fromRect(
              rect: r, child: const _CeldaPilar(enPie: false)));
        }
        if (d.cargaEn(vista.turno)) {
          for (final coord in d.cargaCarril) {
            final r = rect(coord);
            if (r == null) continue;
            hijos.add(Positioned.fromRect(
              rect: r,
              child: _CeldaCarril(dir: d.cargaDir, fin: coord == d.cargaFin),
            ));
          }
        }
      }
      if (d.rompeTurno == vista.turno) {
        d.rompeProb.forEach((coord, pct) {
          final r = rect(coord);
          if (r == null) return;
          hijos.add(Positioned.fromRect(rect: r, child: _CeldaRompe(pct: pct)));
        });
      }
      // Lluvia de rocas que ha elegido el jugador (solo la ve él).
      for (final coord in vista.lluviaCeldas) {
        final r = rect(coord);
        if (r == null) continue;
        hijos.add(Positioned.fromRect(
            rect: r,
            child: _CeldaLluviaElegida(eligiendo: vista.lluviaEligiendo)));
      }
      // Agrupar por celda las fichas de vida (puede haber 2 generales juntos).
      final porCelda = <String, List<_FichaVida>>{};
      d.roles.forEach((iid, rol) {
        final coord = vista.posiciones[iid];
        if (coord == null) return;
        porCelda.putIfAbsent(coord, () => []).add(_FichaVida(
              rol: rol,
              vidas: d.vidas[iid] ?? 0,
              max: d.vidasMax[iid] ?? (d.vidas[iid] ?? 0),
              paralizado: rol == 'jefe' && d.paralizado(vista.turno),
              sinEscudo: rol == 'cazador' && d.sinEscudo(vista.turno),
            ));
      });
      porCelda.forEach((coord, fichas) {
        final r = rect(coord);
        if (r == null) return;
        hijos.add(Positioned.fromRect(
            rect: r, child: _InsigniasVida(fichas: fichas)));
      });
    }

    // ── Cartas clave del jugador ──────────────────────────
    for (final coord in vista.celdasVip) {
      final r = rect(coord);
      if (r == null) continue;
      hijos.add(Positioned.fromRect(rect: r, child: const _InsigniaVip()));
    }

    return IgnorePointer(child: Stack(children: hijos));
  }
}

enum _EstadoCelda { seca, sinExplorar, limpia, inundada }

class _CeldaTunel extends StatelessWidget {
  final _EstadoCelda estado;
  final bool boca;
  final bool reciente;
  const _CeldaTunel(
      {required this.estado, required this.boca, required this.reciente});

  @override
  Widget build(BuildContext context) {
    // Seca: solo un borde fino (no tapa el tablero ni las casillas de
    // movimiento). Sin explorar: velo oscuro. Inundada: agua azul con 💧.
    final Color? relleno = switch (estado) {
      _EstadoCelda.inundada => _agua.withOpacity(0.72),
      _EstadoCelda.sinExplorar => _aguaOscura.withOpacity(0.42),
      _ => null,
    };
    final borde = estado == _EstadoCelda.inundada
        ? _agua
        : estado == _EstadoCelda.sinExplorar
            ? _paredTunel.withOpacity(0.75)
            : _paredTunel.withOpacity(0.45);
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: relleno,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: reciente ? Colors.white.withOpacity(0.9) : borde,
                width: reciente ? 2 : 1,
              ),
            ),
          ),
        ),
        if (estado == _EstadoCelda.inundada)
          const Center(child: Text('💧', style: TextStyle(fontSize: 20))),
        if (estado == _EstadoCelda.sinExplorar)
          const Positioned(
            right: 4,
            top: 3,
            child: Text('≈',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9CCBEA))),
          ),
        if (estado == _EstadoCelda.limpia)
          const Positioned(
            right: 4,
            top: 2,
            child: Text('✓',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: _verde)),
          ),
        if (boca)
          const Positioned(
            left: 4,
            bottom: 2,
            child: Text('⛰',
                style: TextStyle(fontSize: 10, color: Color(0xFFCFE6F2))),
          ),
      ],
    );
  }
}

class _InsigniasRol extends StatelessWidget {
  final int cazadores;
  final int asalto;
  const _InsigniasRol({required this.cazadores, required this.asalto});

  Widget _pill(String texto, Color color) => Container(
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xE60A0A10),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 8.5,
                height: 1.1,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'Cinzel')),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        left: 2,
        top: 2,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (cazadores > 0) _pill('🎯$cazadores', _rojoCaza),
          if (asalto > 0) _pill('⚔$asalto', _naranja),
        ]),
      ),
    ]);
  }
}

class _InsigniaVip extends StatelessWidget {
  const _InsigniaVip();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        right: 2,
        bottom: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xE6140F02),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _oro, width: 1),
          ),
          child: const Text('👑', style: TextStyle(fontSize: 10, height: 1.1)),
        ),
      ),
    ]);
  }
}

class _CeldaProhibida extends StatelessWidget {
  const _CeldaProhibida();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        right: 3,
        top: 3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xE6100808),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white38, width: 1),
          ),
          child: const Text('⛔', style: TextStyle(fontSize: 9, height: 1.1)),
        ),
      ),
    ]);
  }
}

class _CeldaBloqueada extends StatelessWidget {
  const _CeldaBloqueada();

  /// Casilla bloqueada: negro opaco, tapa por completo la imagen del mapa.
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.black),
      ),
    );
  }
}

/// Pilar del duelo de la embestida: en pie (⛰, aturde al jefe) o derrumbado
/// (✖, sigue bloqueado pero ya no aturde). Va encima del negro de la casilla
/// bloqueada.
class _CeldaPilar extends StatelessWidget {
  final bool enPie;
  const _CeldaPilar({required this.enPie});

  @override
  Widget build(BuildContext context) {
    final color = enPie ? _oro : Colors.white38;
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(enPie ? 0.85 : 0.5)),
      ),
      child: Center(
        child: Text(
          enPie ? '⛰' : '✖',
          style: TextStyle(
              fontSize: enPie ? 20 : 16,
              color: enPie ? null : Colors.white38,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Casilla del CARRIL de la embestida de este turno: roja, con la flecha de
/// la dirección. [fin] = casilla donde se detendrá si no alcanza a nadie.
class _CeldaCarril extends StatelessWidget {
  final String dir;
  final bool fin;
  const _CeldaCarril({required this.dir, required this.fin});

  @override
  Widget build(BuildContext context) {
    final flecha = switch (dir) {
      'N' => '↑',
      'S' => '↓',
      'E' => '→',
      'O' => '←',
      _ => '•',
    };
    return Container(
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: _rojoCaza.withOpacity(0.28),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: _rojoCaza.withOpacity(fin ? 0.95 : 0.6), width: fin ? 2 : 1),
      ),
      child: Stack(children: [
        Positioned(
          right: 3,
          top: 2,
          child: Text(fin ? '🐂' : flecha,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFC2BA))),
        ),
      ]),
    );
  }
}

const Color _morado = Color(0xFFB57BFF);

/// Casilla elegida por el jugador para su lluvia de rocas.
class _CeldaLluviaElegida extends StatelessWidget {
  final bool eligiendo;
  const _CeldaLluviaElegida({required this.eligiendo});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _naranja.withOpacity(0.22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: _naranja.withOpacity(eligiendo ? 0.95 : 0.7),
            width: eligiendo ? 2 : 1.2),
      ),
      child: const Center(child: Text('🪨', style: TextStyle(fontSize: 18))),
    );
  }
}

class _CeldaRompe extends StatelessWidget {
  final int pct;
  const _CeldaRompe({required this.pct});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        right: 3,
        bottom: 3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xE6120818),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _morado.withOpacity(0.9), width: 1),
          ),
          child: Text('🛡 $pct%',
              style: const TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE6D2FF),
                  fontFamily: 'Cinzel')),
        ),
      ),
    ]);
  }
}

class _FichaVida {
  final String rol;
  final int vidas;
  final int max;
  final bool paralizado;
  final bool sinEscudo;
  const _FichaVida({
    required this.rol,
    required this.vidas,
    required this.max,
    required this.paralizado,
    required this.sinEscudo,
  });
}

class _InsigniasVida extends StatelessWidget {
  final List<_FichaVida> fichas;
  const _InsigniasVida({required this.fichas});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        left: 2,
        top: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in fichas)
              Container(
                margin: const EdgeInsets.only(bottom: 1),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xE60A0A10),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: f.rol == 'jefe' ? _rojoCaza : _oro, width: 1),
                ),
                child: Text(
                  '${_rep('❤', f.vidas)}${_rep('♡', f.max - f.vidas)}'
                  '${f.paralizado ? ' 🔗' : ''}${f.sinEscudo ? ' 🛡✖' : ''}',
                  style: TextStyle(
                      fontSize: 8,
                      height: 1.1,
                      color: f.rol == 'jefe'
                          ? const Color(0xFFFF8A80)
                          : const Color(0xFFFFE08A)),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// Chip para la esquina del tablero: asalto general y estado del túnel.
class HistoriaCapaLeyenda extends StatelessWidget {
  final CapaHistoriaVista vista;
  const HistoriaCapaLeyenda({super.key, required this.vista});

  @override
  Widget build(BuildContext context) {
    final lineas = <Widget>[];
    final m = vista.marcas;
    if (m != null && m.turnoAsalto > 0) {
      final faltan = m.turnoAsalto - vista.turno;
      final texto = m.asaltoGeneral || faltan <= 0
          ? '⚔ ¡ASALTO GENERAL! Se reúnen${m.reunion.isNotEmpty ? ' en ${m.reunion}' : ''} y van a por tu cuartel'
          : '⚔ Asalto general en el turno ${m.turnoAsalto} '
              '(${faltan == 1 ? 'falta 1 turno' : 'faltan $faltan turnos'})';
      lineas.add(Text(texto,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD9A8),
              fontFamily: 'Cinzel')));
    }
    final d = vista.duelo;
    if (d != null) {
      String vidas(String rol) {
        final id = d.idDe(rol);
        final v = d.vidasDe(rol);
        final max = id == null ? v : (d.vidasMax[id] ?? v);
        return '${d.nombreDe(rol)} ${_rep('❤', v)}${_rep('♡', max - v)}';
      }

      lineas.add(Text(
        '⚔ Duelo · turno ${vista.turno}${d.turnoLimite > 0 ? '/${d.turnoLimite}' : ''} · '
        '${vidas('jefe')} · ${vidas('cazador')}'
        '${d.embestida ? '' : ' · ${vidas('verdugo')}'}',
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFD9A8),
            fontFamily: 'Cinzel'),
      ));
      final avisos = <String>[];
      if (d.embestida) {
        // Duelo de la embestida (bionicos_3).
        final jefe = d.nombreDe('jefe');
        if (d.paralizado(vista.turno)) {
          avisos.add('🔗 $jefe está ATURDIDO: ¡entra en su casilla!');
        } else if (d.cargaEn(vista.turno)) {
          final contra = switch (d.cargaChoque) {
            'pilar' => 'se estrellará contra un pilar',
            'muro' => 'se detendrá en los escombros',
            _ => 'llegará hasta el borde',
          };
          avisos
              .add('🐂 ¡EMBESTIDA! Sal del carril rojo (3 de ancho): $contra');
          if (d.enL && d.cargaChoque != 'pilar') {
            avisos.add('🔥 Furia: si no choca con un pilar, girará hacia ti');
          }
        } else {
          final faltan = d.proximaCarga - vista.turno;
          avisos.add(d.proximaCarga <= 0
              ? '💨 $jefe te acecha'
              : faltan == 1
                  ? '💨 $jefe te acecha · embiste el turno que viene: colócate con un pilar a tu espalda'
                  : '💨 $jefe te acecha · próxima embestida en el turno ${d.proximaCarga}');
        }
        avisos.add('⛰ Pilares en pie: ${d.pilares.length}'
            '${d.bordeAturde ? ' · el borde también le aturde' : ''}'
            '${d.onda ? ' · 💥 onda de choque activa' : ''}');
      } else if (d.jugadorEsJefe) {
        // Duelo invertido: el jugador es el jefe.
        final lanzada = vista.lluviaCeldas.isNotEmpty;
        if (d.paralizado(vista.turno)) {
          avisos.add(
              '🔗 Estás paralizado: no puedes moverte y ${d.nombreDe('verdugo')} puede herirte');
        } else if (lanzada || (d.canaliza && d.turno == vista.turno)) {
          avisos.add('🪨 Canalizas la lluvia: este turno NO te mueves');
        } else {
          avisos.add('💨 Te mueves este turno');
        }
        if (d.lluviaManual) {
          final filas = d.lluviaMaxFilas > 0
              ? '${d.lluviaMaxFilas} fila${d.lluviaMaxFilas == 1 ? '' : 's'}'
              : 'todas las filas';
          if (lanzada) {
            final celdas = vista.lluviaCeldas.toList()..sort();
            avisos.add('🪨 Lluvia sobre ${celdas.join(', ')}'
                '${vista.lluviaEligiendo ? ' · toca a Alexander para terminar' : ''}');
          } else if (d.lluviaLista(vista.turno)) {
            avisos.add(
                '🪨 Lluvia lista: lánzala desde la ficha de ${d.nombreDe('jefe')} '
                '(${d.lluviaPorFila} por fila, $filas)');
          } else {
            avisos.add(
                '🪨 Lluvia recargando: lista en el turno ${d.lluviaListaEnTurno}');
          }
        }
        if (d.rompeTurno == vista.turno) {
          avisos.add(
              '🛡 Rompe escudos sobre ${d.nombreDe('cazador')}: mira los % morados');
        }
        if (d.sinEscudo(vista.turno)) {
          avisos.add(
              '🛡✖ ${d.nombreDe('cazador')} sin escudo: si coincidís, pierde una vida');
        }
      } else {
        if (d.paralizado(vista.turno)) {
          avisos.add(
              '🔗 ${d.nombreDe('jefe')} está paralizado: ¡que entre ${d.nombreDe('verdugo')}!');
        } else if (d.canaliza && d.turno == vista.turno) {
          avisos.add(
              '🪨 ${d.nombreDe('jefe')} canaliza la lluvia: este turno NO se mueve');
        } else {
          avisos.add('💨 ${d.nombreDe('jefe')} se mueve este turno');
        }
        if (d.rompeTurno == vista.turno) {
          avisos.add(
              '🛡 Rompe escudos sobre ${d.nombreDe('cazador')}: mira los % morados');
        }
        if (d.sinEscudo(vista.turno)) {
          avisos.add(
              '🛡✖ ${d.nombreDe('cazador')} sin escudo hasta el turno ${d.sinEscudoHasta}: ¡huye!');
        }
      }
      for (final a in avisos) {
        lineas.add(Text(a,
            style: const TextStyle(
                fontSize: 8.5,
                color: Color(0xFFE8E0D0),
                fontFamily: 'Cinzel')));
      }
    }

    final t = vista.tunel;
    if (t != null) {
      if (lineas.isNotEmpty) lineas.add(const SizedBox(height: 2));
      lineas.add(Text(
        '🕳 Túnel: mov ${t.movimiento} dentro · '
        '${t.sinExplorar.length} casilla${t.sinExplorar.length == 1 ? '' : 's'} sin explorar · '
        '${t.inundadas.length} inundada${t.inundadas.length == 1 ? '' : 's'}',
        style: const TextStyle(
            fontSize: 8.5, color: Color(0xFFCFE6F2), fontFamily: 'Cinzel'),
      ));
    }
    if (lineas.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xDD0A0A14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _naranja.withOpacity(0.55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lineas,
        ),
      ),
    );
  }
}
