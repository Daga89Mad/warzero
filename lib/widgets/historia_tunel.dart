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
//     muralla: {                              (solo modo "muralla", nefilim_2)
//       orientacion, fase, escudoDoble, giraYCarga, alcanceCarga, anchoCarga,
//       plan: {turno, accion: avanzar|giraYCarga|girar|barrido|aturdida,
//              dir, carril: [...], laterales: [...], fin, hundira},
//       linea: {fila, letra, proximoAvance, cada},
//       grietas: {coord: pisadas}, grietaPisadas, huecos: [...], hundida,
//       odio: {puntos, max, coste}
//     }, odioTurno
//   }
//   carcel: {                                 (HistoriaCarcel.cs · nefilim_1)
//     turno, alexanderId, salaActual, fin,
//     salas: [{nombre, puerta, celdas, final, pistas, huye, intercambios,
//              slots: [{nombre, icono, duracion}]}],
//     puertas: [{coord, sala, abierta, abrible, final, requiere: [icono]}],
//     salida: [...], guardias: {instanceId: {sala, slot, nombre, prob, coord}},
//     nucleos: [{sala, slot, nombre, icono, caduca, restantes}],
//     pistas: [{turno, sala, slot, texto}],
//     alarma: {valor, max, proximoUmbral, proximoNombre},
//     odio: {usado, turno, turnoUsado, fuerza},
//     ultimo: {turno, eventos: [{tipo, texto, coord, malo}],
//              intercambios: [{a, b, desde, hacia}], huidas: [{desde, hacia}]}
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
//   • CarcelVista: la cárcel biónica (nefilim_1): puertas que solo se abren
//     con su núcleo, % de cada guardia, núcleos de Alexander, pistas, alarma
//     y odio. La capa pinta puertas, salida, % sobre los guardias, núcleos
//     sobre Alexander e intercambios/huidas del último turno.

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

/// Estado del DUELO DE LA MURALLA (bloque `duelo.muralla`, nefilim_2).
class MurallaVista {
  /// Hacia dónde mira Izanami: "N" | "S" | "E" | "O".
  final String orientacion;
  final int fase;
  final bool escudoDoble;
  final bool giraYCarga;
  final int alcanceCarga;
  final int anchoCarga;

  /// Plan publicado para [planTurno].
  final int planTurno;
  final String planAccion;
  final String planDir;
  final Set<String> planCarril;
  final Set<String> planLaterales;
  final String planFin;
  final bool planHundira;

  /// Fila (0 = A) de la línea biónica y turno de su próximo avance.
  final int lineaFila;
  final String lineaLetra;
  final int lineaProximoAvance;
  final int lineaCada;

  /// Grietas (coord → veces pisada), pisadas para que sea profunda, huecos y
  /// la casilla hundida bajo Izanami.
  final Map<String, int> grietas;
  final int grietaPisadas;
  final Set<String> huecos;
  final String hundida;

  final int odioPuntos;
  final int odioMax;
  final int odioCoste;

  /// Turno para el que el jugador ha declarado la embestida del odio.
  final int odioTurno;

  const MurallaVista({
    required this.orientacion,
    required this.fase,
    required this.escudoDoble,
    required this.giraYCarga,
    required this.alcanceCarga,
    required this.anchoCarga,
    required this.planTurno,
    required this.planAccion,
    required this.planDir,
    required this.planCarril,
    required this.planLaterales,
    required this.planFin,
    required this.planHundira,
    required this.lineaFila,
    required this.lineaLetra,
    required this.lineaProximoAvance,
    required this.lineaCada,
    required this.grietas,
    required this.grietaPisadas,
    required this.huecos,
    required this.hundida,
    required this.odioPuntos,
    required this.odioMax,
    required this.odioCoste,
    required this.odioTurno,
  });

  static MurallaVista? fromDuelo(Map raw) {
    final m = raw['muralla'];
    if (m is! Map) return null;
    final plan = m['plan'] is Map ? m['plan'] as Map : const {};
    final linea = m['linea'] is Map ? m['linea'] as Map : const {};
    final odio = m['odio'] is Map ? m['odio'] as Map : const {};
    final grietas = <String, int>{};
    if (m['grietas'] is Map) {
      (m['grietas'] as Map).forEach((k, v) => grietas[k.toString()] = _n(v));
    }
    final pisadas = _n(m['grietaPisadas']);
    return MurallaVista(
      orientacion: (m['orientacion'] ?? 'S').toString(),
      fase: _n(m['fase']) <= 0 ? 1 : _n(m['fase']),
      escudoDoble: m['escudoDoble'] == true,
      giraYCarga: m['giraYCarga'] == true,
      alcanceCarga: _n(m['alcanceCarga']),
      anchoCarga: _n(m['anchoCarga']) <= 0 ? 1 : _n(m['anchoCarga']),
      planTurno: _n(plan['turno']),
      planAccion: (plan['accion'] ?? '').toString(),
      planDir: (plan['dir'] ?? '').toString(),
      planCarril: _strs(plan['carril']).toSet(),
      planLaterales: _strs(plan['laterales']).toSet(),
      planFin: (plan['fin'] ?? '').toString(),
      planHundira: plan['hundira'] == true,
      lineaFila: _n(linea['fila']),
      lineaLetra: (linea['letra'] ?? 'A').toString(),
      lineaProximoAvance: _n(linea['proximoAvance']),
      lineaCada: _n(linea['cada']),
      grietas: grietas,
      grietaPisadas: pisadas <= 0 ? 2 : pisadas,
      huecos: _strs(m['huecos']).toSet(),
      hundida: (m['hundida'] ?? '').toString(),
      odioPuntos: _n(odio['puntos']),
      odioMax: _n(odio['max']),
      odioCoste: _n(odio['coste']) <= 0 ? 2 : _n(odio['coste']),
      odioTurno: _n(raw['odioTurno']),
    );
  }

  /// Plan vigente en [turnoActual] (si no, la acción es '').
  String accionEn(int turnoActual) => planTurno == turnoActual ? planAccion : '';

  bool esCarga(String accion) => accion == 'avanzar' || accion == 'giraYCarga';

  /// True si [coord] es una grieta profunda (Izanami se hunde si acaba ahí).
  bool profunda(String coord) => (grietas[coord] ?? 0) >= grietaPisadas;

  /// El jugador puede lanzar la embestida del odio.
  bool get odioListo => odioPuntos >= odioCoste;

  /// El jugador la ha declarado para [turnoActual].
  bool odioDeclaradoEn(int turnoActual) => odioTurno > 0 && odioTurno == turnoActual;
}

/// Flecha de una dirección.
String flechaDir(String dir) => switch (dir) {
      'N' => '▲',
      'S' => '▼',
      'E' => '▶',
      'O' => '◀',
      _ => '•',
    };

String nombreDir(String dir) => switch (dir) {
      'N' => 'norte',
      'S' => 'sur',
      'E' => 'este',
      'O' => 'oeste',
      _ => dir,
    };

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

  /// Modo MURALLA (nefilim_2): null en el resto de duelos.
  final MurallaVista? muralla;

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
    this.muralla,
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
      muralla: raw['modo'] == 'muralla' ? MurallaVista.fromDuelo(raw) : null,
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

/// Una puerta de la cárcel.
class PuertaCarcel {
  final String coord;
  final int sala;
  final bool abierta;

  /// Alexander lleva sus núcleos: puede ENTRAR (no atravesarla) este turno.
  final bool abrible;
  final bool esFinal;

  /// Iconos de los núcleos que pide (🔑, 🪶…).
  final List<String> requiere;

  const PuertaCarcel({
    required this.coord,
    required this.sala,
    required this.abierta,
    required this.abrible,
    required this.esFinal,
    required this.requiere,
  });
}

/// Un slot de núcleo de una sala.
class SlotCarcel {
  final String nombre;
  final String icono;
  final int duracion;
  const SlotCarcel(
      {required this.nombre, required this.icono, required this.duracion});
}

/// Una sala de la cárcel.
class SalaCarcelVista {
  final String nombre;
  final String puerta;
  final bool esFinal;
  final bool pistas;
  final bool huye;
  final int intercambios;
  final List<SlotCarcel> slots;
  const SalaCarcelVista({
    required this.nombre,
    required this.puerta,
    required this.esFinal,
    required this.pistas,
    required this.huye,
    required this.intercambios,
    required this.slots,
  });
}

/// Un guardia vivo de la cárcel con su % de llevar el núcleo de su slot.
class GuardiaCarcelVista {
  final String id;
  final int sala;
  final int slot;
  final String nombre;
  final double prob;
  final String coord;
  const GuardiaCarcelVista({
    required this.id,
    required this.sala,
    required this.slot,
    required this.nombre,
    required this.prob,
    required this.coord,
  });
}

/// Núcleo que lleva Alexander.
class NucleoCarcel {
  final int sala;
  final int slot;
  final String nombre;
  final String icono;

  /// Turnos que le quedan contando el actual (0 = sin límite).
  final int restantes;
  const NucleoCarcel({
    required this.sala,
    required this.slot,
    required this.nombre,
    required this.icono,
    required this.restantes,
  });
}

/// Estado público de la CÁRCEL BIÓNICA (campo `carcel`, nefilim_1).
class CarcelVista {
  /// Turno para el que vale este estado.
  final int turno;
  final String alexanderId;
  final int salaActual;

  /// "" | "escape" | "alarma".
  final String fin;
  final List<SalaCarcelVista> salas;
  final Map<String, PuertaCarcel> puertas;
  final Set<String> salida;
  final Map<String, GuardiaCarcelVista> guardias;
  final List<NucleoCarcel> nucleos;

  /// Pistas reveladas: (turno, sala, slot, texto).
  final List<({int turno, int sala, int slot, String texto})> pistas;
  final int alarma;
  final int alarmaMax;
  final int proximoUmbral;
  final String proximoNombre;
  final bool odioUsado;
  final int odioTurno;
  final int odioTurnoUsado;
  final int odioFuerza;

  /// Lo que pasó al resolver el último turno.
  final int ultimoTurno;
  final List<({String tipo, String texto, String coord, bool malo})> eventos;
  final List<({String desde, String hacia})> intercambios;
  final List<({String desde, String hacia})> huidas;

  const CarcelVista({
    required this.turno,
    required this.alexanderId,
    required this.salaActual,
    required this.fin,
    required this.salas,
    required this.puertas,
    required this.salida,
    required this.guardias,
    required this.nucleos,
    required this.pistas,
    required this.alarma,
    required this.alarmaMax,
    required this.proximoUmbral,
    required this.proximoNombre,
    required this.odioUsado,
    required this.odioTurno,
    required this.odioTurnoUsado,
    required this.odioFuerza,
    required this.ultimoTurno,
    required this.eventos,
    required this.intercambios,
    required this.huidas,
  });

  /// Lee el campo `carcel` del estado. null si la batalla no es una cárcel.
  static CarcelVista? fromEstado(Map<String, dynamic> estado) {
    final raw = estado['carcel'];
    if (raw is! Map) return null;

    final salas = <SalaCarcelVista>[];
    for (final x in (raw['salas'] as List? ?? const [])) {
      if (x is! Map) continue;
      salas.add(SalaCarcelVista(
        nombre: (x['nombre'] ?? '').toString(),
        puerta: (x['puerta'] ?? '').toString(),
        esFinal: x['final'] == true,
        pistas: x['pistas'] == true,
        huye: x['huye'] == true,
        intercambios: _n(x['intercambios']),
        slots: [
          for (final sl in (x['slots'] as List? ?? const []))
            if (sl is Map)
              SlotCarcel(
                nombre: (sl['nombre'] ?? '').toString(),
                icono: (sl['icono'] ?? '🔑').toString(),
                duracion: _n(sl['duracion']),
              ),
        ],
      ));
    }

    final puertas = <String, PuertaCarcel>{};
    for (final x in (raw['puertas'] as List? ?? const [])) {
      if (x is! Map) continue;
      final coord = (x['coord'] ?? '').toString();
      if (coord.isEmpty) continue;
      puertas[coord] = PuertaCarcel(
        coord: coord,
        sala: _n(x['sala']),
        abierta: x['abierta'] == true,
        abrible: x['abrible'] == true,
        esFinal: x['final'] == true,
        requiere: _strs(x['requiere']),
      );
    }

    final guardias = <String, GuardiaCarcelVista>{};
    final rawG = raw['guardias'];
    if (rawG is Map) {
      rawG.forEach((k, v) {
        if (v is! Map) return;
        guardias[k.toString()] = GuardiaCarcelVista(
          id: k.toString(),
          sala: _n(v['sala']),
          slot: _n(v['slot']),
          nombre: (v['nombre'] ?? '').toString(),
          prob: (v['prob'] as num?)?.toDouble() ?? 0,
          coord: (v['coord'] ?? '').toString(),
        );
      });
    }

    final nucleos = <NucleoCarcel>[
      for (final x in (raw['nucleos'] as List? ?? const []))
        if (x is Map)
          NucleoCarcel(
            sala: _n(x['sala']),
            slot: _n(x['slot']),
            nombre: (x['nombre'] ?? '').toString(),
            icono: (x['icono'] ?? '🔑').toString(),
            restantes: _n(x['restantes']),
          ),
    ];

    final pistas = <({int turno, int sala, int slot, String texto})>[
      for (final x in (raw['pistas'] as List? ?? const []))
        if (x is Map)
          (
            turno: _n(x['turno']),
            sala: _n(x['sala']),
            slot: _n(x['slot']),
            texto: (x['texto'] ?? '').toString(),
          ),
    ];

    final alarma = raw['alarma'] is Map ? raw['alarma'] as Map : const {};
    final odio = raw['odio'] is Map ? raw['odio'] as Map : const {};
    final ult = raw['ultimo'] is Map ? raw['ultimo'] as Map : const {};

    List<({String desde, String hacia})> pares(dynamic v) => [
          for (final x in (v as List? ?? const []))
            if (x is Map)
              (
                desde: (x['desde'] ?? '').toString(),
                hacia: (x['hacia'] ?? '').toString(),
              ),
        ];

    return CarcelVista(
      turno: _n(raw['turno']),
      alexanderId: (raw['alexanderId'] ?? '').toString(),
      salaActual: _n(raw['salaActual']),
      fin: (raw['fin'] ?? '').toString(),
      salas: salas,
      puertas: puertas,
      salida: _strs(raw['salida']).toSet(),
      guardias: guardias,
      nucleos: nucleos,
      pistas: pistas,
      alarma: _n(alarma['valor']),
      alarmaMax: _n(alarma['max']),
      proximoUmbral: _n(alarma['proximoUmbral']),
      proximoNombre: (alarma['proximoNombre'] ?? '').toString(),
      odioUsado: odio['usado'] == true,
      odioTurno: _n(odio['turno']),
      odioTurnoUsado: _n(odio['turnoUsado']),
      odioFuerza: _n(odio['fuerza']),
      ultimoTurno: _n(ult['turno']),
      eventos: [
        for (final e in (ult['eventos'] as List? ?? const []))
          if (e is Map)
            (
              tipo: (e['tipo'] ?? '').toString(),
              texto: (e['texto'] ?? '').toString(),
              coord: (e['coord'] ?? '').toString(),
              malo: e['malo'] == true,
            ),
      ],
      intercambios: pares(ult['intercambios']),
      huidas: pares(ult['huidas']),
    );
  }

  /// Sala activa (null si ya se ha escapado).
  SalaCarcelVista? get sala =>
      salaActual >= 0 && salaActual < salas.length ? salas[salaActual] : null;

  /// Puertas cerradas (paredes para todos salvo las abribles).
  Set<String> get puertasCerradas =>
      {for (final p in puertas.values) if (!p.abierta) p.coord};

  /// Puertas cerradas en las que Alexander puede ENTRAR este turno.
  Set<String> get puertasAbribles =>
      {for (final p in puertas.values) if (!p.abierta && p.abrible) p.coord};

  /// El jugador puede desatar el odio (aún no lo ha usado).
  bool get odioDisponible => !odioUsado && fin.isEmpty;

  /// El jugador ha declarado el odio para [turnoActual].
  bool odioDeclaradoEn(int turnoActual) =>
      !odioUsado && odioTurno > 0 && odioTurno == turnoActual;

  /// Icono del núcleo que buscaría un guardia de [sala]/[slot].
  String iconoDe(int sala, int slot) {
    if (sala < 0 || sala >= salas.length) return '🔑';
    final sl = salas[sala].slots;
    return slot >= 0 && slot < sl.length ? sl[slot].icono : '🔑';
  }

  /// True si Alexander ya lleva el núcleo de [sala]/[slot].
  bool llevaNucleo(int sala, int slot) =>
      nucleos.any((n) => n.sala == sala && n.slot == slot);

  /// Pistas de la sala activa, la más reciente primero.
  List<String> get pistasSalaActual => [
        for (final p in pistas.reversed)
          if (p.sala == salaActual) p.texto,
      ];
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

  /// Cárcel biónica (null si la batalla no lo es).
  final CarcelVista? carcel;

  /// Casilla actual de Alexander en la cárcel (para pintar sus núcleos).
  final String? celdaAlexander;

  /// El jugador ha desatado el odio este turno (pendiente de resolver).
  final bool odioActivo;

  const CapaHistoriaVista({
    this.tunel,
    this.marcas,
    this.celdasVip = const {},
    required this.turno,
    this.duelo,
    this.posiciones = const {},
    this.lluviaCeldas = const {},
    this.lluviaEligiendo = false,
    this.carcel,
    this.celdaAlexander,
    this.odioActivo = false,
  });

  bool get vacia =>
      tunel == null && marcas == null && duelo == null && carcel == null;
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
      // Muralla: línea, huecos, grietas y el plan de Izanami.
      final mu = d.muralla;
      if (mu != null) {
        for (var ci = 0; ci < config.cols; ci++) {
          final fila = mu.lineaFila < 0
              ? 0
              : (mu.lineaFila >= config.rows ? config.rows - 1 : mu.lineaFila);
          final coord = config.coordLabel(fila, ci);
          final r = rect(coord);
          if (r == null) continue;
          hijos.add(Positioned.fromRect(rect: r, child: const _CeldaLinea()));
        }
        for (final coord in mu.huecos) {
          final r = rect(coord);
          if (r == null) continue;
          hijos.add(Positioned.fromRect(rect: r, child: const _CeldaHueco()));
        }
        mu.grietas.forEach((coord, n) {
          final r = rect(coord);
          if (r == null) return;
          hijos.add(Positioned.fromRect(
              rect: r, child: _CeldaGrieta(profunda: mu.profunda(coord))));
        });
        final accion = mu.accionEn(vista.turno);
        if (mu.esCarga(accion)) {
          for (final coord in mu.planLaterales) {
            final r = rect(coord);
            if (r == null) continue;
            hijos.add(Positioned.fromRect(
                rect: r, child: const _CeldaLateralCarga()));
          }
          for (final coord in mu.planCarril) {
            final r = rect(coord);
            if (r == null) continue;
            hijos.add(Positioned.fromRect(
              rect: r,
              child: _CeldaCarril(
                  dir: mu.planDir,
                  fin: coord == mu.planFin,
                  icono: coord == mu.planFin && mu.planHundira ? '🕳' : '🛡'),
            ));
          }
        }
        // Izanami: hacia dónde mira y qué hará (giro, barrido, aturdida).
        final idJ = d.idDe('jefe');
        final cj = idJ == null ? null : vista.posiciones[idJ];
        if (cj != null) {
          if (accion == 'barrido') {
            final p = _pos(config, cj);
            if (p != null) {
              for (var dr = -1; dr <= 1; dr++) {
                for (var dc = -1; dc <= 1; dc++) {
                  if (dr == 0 && dc == 0) continue;
                  final fr = p.$1 + dr, fc = p.$2 + dc;
                  if (fr < 0 || fr >= config.rows || fc < 0 || fc >= config.cols) {
                    continue;
                  }
                  final r = rect(config.coordLabel(fr, fc));
                  if (r == null) continue;
                  hijos.add(Positioned.fromRect(
                      rect: r, child: const _CeldaLateralCarga(barrido: true)));
                }
              }
            }
          }
          final r = rect(cj);
          if (r != null) {
            hijos.add(Positioned.fromRect(
              rect: r,
              child: _InsigniaOrientacion(
                dir: mu.orientacion,
                gira: accion == 'girar' || accion == 'giraYCarga'
                    ? mu.planDir
                    : '',
                aturdida: accion == 'aturdida',
                escudoDoble: mu.escudoDoble,
              ),
            ));
          }
        }
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
              nucleos: rol == 'jefe' && d.muralla != null,
              odio: rol == 'cazador' && d.muralla != null
                  ? d.muralla!.odioPuntos
                  : 0,
            ));
      });
      porCelda.forEach((coord, fichas) {
        final r = rect(coord);
        if (r == null) return;
        hijos.add(Positioned.fromRect(
            rect: r, child: _InsigniasVida(fichas: fichas)));
      });
    }

    // ── Cárcel: salida, puertas, % de los guardias, núcleos ─
    final cc = vista.carcel;
    if (cc != null) {
      for (final coord in cc.salida) {
        final r = rect(coord);
        if (r == null) continue;
        hijos.add(Positioned.fromRect(rect: r, child: const _CeldaSalida()));
      }
      for (final p in cc.puertas.values) {
        final r = rect(p.coord);
        if (r == null) continue;
        hijos.add(Positioned.fromRect(rect: r, child: _CeldaPuerta(puerta: p)));
      }
      // % por casilla (solo la sala activa), agrupado por núcleo.
      final porCelda = <String, Map<String, double>>{};
      for (final g in cc.guardias.values) {
        if (g.sala != cc.salaActual || g.prob <= 0 || g.coord.isEmpty) continue;
        if (cc.llevaNucleo(g.sala, g.slot)) continue;
        final icono = cc.iconoDe(g.sala, g.slot);
        final m = porCelda.putIfAbsent(g.coord, () => {});
        m[icono] = (m[icono] ?? 0.0) + g.prob;
      }
      porCelda.forEach((coord, probs) {
        final r = rect(coord);
        if (r == null) return;
        hijos.add(
            Positioned.fromRect(rect: r, child: _InsigniaProb(probs: probs)));
      });
      // Intercambios y huidas del turno que se acaba de resolver.
      if (cc.ultimoTurno > 0 && cc.ultimoTurno == vista.turno - 1) {
        var n = 0;
        for (final x in cc.intercambios) {
          n++;
          for (final coord in [x.desde, x.hacia]) {
            final r = rect(coord);
            if (r == null) continue;
            hijos.add(Positioned.fromRect(
                rect: r, child: _MarcaUltimo(texto: '🔀$n')));
          }
        }
        for (final h in cc.huidas) {
          final r = rect(h.hacia);
          if (r == null) continue;
          hijos.add(Positioned.fromRect(
              rect: r, child: const _MarcaUltimo(texto: '💨')));
        }
      }
      // Núcleos que lleva Alexander (y el odio desatado).
      final ca = vista.celdaAlexander;
      if (ca != null && (cc.nucleos.isNotEmpty || vista.odioActivo)) {
        final r = rect(ca);
        if (r != null) {
          hijos.add(Positioned.fromRect(
            rect: r,
            child: _InsigniaNucleos(
                nucleos: cc.nucleos, odio: vista.odioActivo),
          ));
        }
      }
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

const Color _acero = Color(0xFF8FA3B8);
const Color _cian = Color(0xFF6FE0E0);

/// Casilla del EXTERIOR de la cárcel (la fuga).
class _CeldaSalida extends StatelessWidget {
  const _CeldaSalida();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE6A8).withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFFE6A8).withOpacity(0.35)),
      ),
      child: const Center(
          child: Text('🌄', style: TextStyle(fontSize: 14, height: 1))),
    );
  }
}

/// Puerta de la cárcel: cerrada (acero, con los núcleos que pide), abrible
/// (verde: Alexander ya puede entrar) o abierta (solo un borde fino).
class _CeldaPuerta extends StatelessWidget {
  final PuertaCarcel puerta;
  const _CeldaPuerta({required this.puerta});

  @override
  Widget build(BuildContext context) {
    if (puerta.abierta) {
      return Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _verde.withOpacity(0.45)),
        ),
        child: const Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(right: 3, top: 2),
            child: Text('🚪✓',
                style: TextStyle(fontSize: 9, color: _verde, height: 1)),
          ),
        ),
      );
    }
    final color = puerta.abrible ? _verde : _acero;
    return Container(
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2028).withOpacity(0.86),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: puerta.abrible ? 2.2 : 1.4),
        boxShadow: puerta.abrible
            ? [BoxShadow(color: _verde.withOpacity(0.45), blurRadius: 8)]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(puerta.esFinal ? '🏯' : '🚪',
              style: const TextStyle(fontSize: 16, height: 1.1)),
          Text(
            puerta.requiere.join(),
            style: TextStyle(
                fontSize: 9,
                height: 1.1,
                color: puerta.abrible ? _verde : Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// % de llevar el núcleo sobre una casilla con guardias.
class _InsigniaProb extends StatelessWidget {
  /// icono del núcleo → probabilidad (0..1) sumada de la casilla.
  final Map<String, double> probs;
  const _InsigniaProb({required this.probs});

  @override
  Widget build(BuildContext context) {
    final entradas = probs.entries.toList();
    return Stack(children: [
      Positioned(
        left: 2,
        top: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in entradas)
              Container(
                margin: const EdgeInsets.only(bottom: 1),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xE60A0A10),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: e.value >= 0.5 ? _oro : _cian.withOpacity(0.8),
                      width: 1),
                ),
                child: Text(
                  '${e.key}${(e.value * 100).round()}%',
                  style: TextStyle(
                      fontSize: 8.5,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                      color: e.value >= 0.5 ? _oro : const Color(0xFFCFF6F6),
                      fontFamily: 'Cinzel'),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// Núcleos que lleva Alexander (con los turnos que les quedan) y el odio.
class _InsigniaNucleos extends StatelessWidget {
  final List<NucleoCarcel> nucleos;
  final bool odio;
  const _InsigniaNucleos({required this.nucleos, required this.odio});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        left: 2,
        bottom: 2,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final n in nucleos)
            Container(
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xE60A0A10),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: n.restantes == 1 ? _rojoCaza : _verde, width: 1),
              ),
              child: Text(
                n.restantes > 0 ? '${n.icono}${n.restantes}' : n.icono,
                style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.bold,
                    color: n.restantes == 1 ? _rojoCaza : _verde),
              ),
            ),
          if (odio)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xE6200806),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _rojoCaza, width: 1),
              ),
              child: const Text('🔥',
                  style: TextStyle(fontSize: 9, height: 1.1)),
            ),
        ]),
      ),
    ]);
  }
}

/// Marca del último turno (🔀 intercambio, 💨 huida).
class _MarcaUltimo extends StatelessWidget {
  final String texto;
  const _MarcaUltimo({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        right: 2,
        bottom: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xE60A0A10),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _naranja, width: 1),
          ),
          child: Text(texto,
              style: const TextStyle(
                  fontSize: 8.5,
                  height: 1.1,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD9A8))),
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

  /// Icono de la casilla final (🐂 por defecto).
  final String icono;
  const _CeldaCarril({required this.dir, required this.fin, this.icono = '🐂'});

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
          child: Text(fin ? icono : flecha,
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
const Color _acero2 = Color(0xFF9FB4C8);

(int, int)? _pos(GameConfig config, String coord) {
  for (int ri = 0; ri < config.rows; ri++) {
    for (int ci = 0; ci < config.cols; ci++) {
      if (config.coordLabel(ri, ci) == coord) return (ri, ci);
    }
  }
  return null;
}

/// Fila de la LÍNEA BIÓNICA (encima del negro de la casilla bloqueada).
class _CeldaLinea extends StatelessWidget {
  const _CeldaLinea();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151C24),
        border: Border(
            bottom: BorderSide(color: _acero2.withOpacity(0.9), width: 2)),
      ),
      child: const Center(
          child: Text('🛡', style: TextStyle(fontSize: 16, height: 1))),
    );
  }
}

/// HUECO: casilla hundida, impracticable.
class _CeldaHueco extends StatelessWidget {
  const _CeldaHueco();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
          child: Text('🕳', style: TextStyle(fontSize: 18, height: 1))),
    );
  }
}

/// GRIETA (⚡) o GRIETA PROFUNDA (⚡⚡, Izanami se hunde si acaba ahí).
class _CeldaGrieta extends StatelessWidget {
  final bool profunda;
  const _CeldaGrieta({required this.profunda});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        left: 3,
        bottom: 2,
        child: Text(
          profunda ? '⚡⚡' : '⚡',
          style: TextStyle(
              fontSize: profunda ? 11 : 10,
              height: 1,
              color: profunda ? _naranja : const Color(0xFFE8D8B0)),
        ),
      ),
    ]);
  }
}

/// Lateral de una carga de 3 de ancho, o casilla del BARRIDO del escudo.
class _CeldaLateralCarga extends StatelessWidget {
  final bool barrido;
  const _CeldaLateralCarga({this.barrido = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: _rojoCaza.withOpacity(barrido ? 0.20 : 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _rojoCaza.withOpacity(0.5)),
      ),
      child: barrido
          ? const Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(right: 3, top: 2),
                child: Text('🛡', style: TextStyle(fontSize: 9, height: 1)),
              ),
            )
          : null,
    );
  }
}

/// Hacia dónde mira Izanami (su escudo) y si este turno gira o está aturdida.
class _InsigniaOrientacion extends StatelessWidget {
  final String dir;

  /// Dirección a la que gira este turno ('' = no gira).
  final String gira;
  final bool aturdida;
  final bool escudoDoble;
  const _InsigniaOrientacion({
    required this.dir,
    required this.gira,
    required this.aturdida,
    required this.escudoDoble,
  });

  @override
  Widget build(BuildContext context) {
    // La flecha va pegada al borde hacia el que mira.
    final align = switch (dir) {
      'N' => Alignment.topCenter,
      'S' => Alignment.bottomCenter,
      'E' => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    return Stack(children: [
      Align(
        alignment: align,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
          decoration: BoxDecoration(
            color: const Color(0xE60A0A10),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: escudoDoble ? _oro : _acero2, width: escudoDoble ? 1.5 : 1),
          ),
          child: Text(flechaDir(dir),
              style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: escudoDoble ? _oro : const Color(0xFFDDE8F2))),
        ),
      ),
      if (gira.isNotEmpty || aturdida)
        Positioned(
          right: 2,
          top: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xE60A0A10),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: aturdida ? _verde : _naranja, width: 1),
            ),
            child: Text(aturdida ? '😵' : '↻${flechaDir(gira)}',
                style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.bold,
                    color: aturdida ? _verde : _naranja)),
          ),
        ),
    ]);
  }
}

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

  /// Muralla: las vidas de Izanami son núcleos (◆) y Alexander lleva odio.
  final bool nucleos;
  final int odio;
  const _FichaVida({
    required this.rol,
    required this.vidas,
    required this.max,
    required this.paralizado,
    required this.sinEscudo,
    this.nucleos = false,
    this.odio = 0,
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
                  f.nucleos
                      ? '${_rep('◆', f.vidas)}${_rep('◇', f.max - f.vidas)}'
                          '${f.paralizado ? ' 🕳' : ''}'
                      : '${_rep('❤', f.vidas)}${_rep('♡', f.max - f.vidas)}'
                          '${f.paralizado ? ' 🔗' : ''}${f.sinEscudo ? ' 🛡✖' : ''}'
                          '${f.odio > 0 ? ' ${_rep('🔥', f.odio)}' : ''}',
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
        d.muralla != null
            ? '⚔ Duelo · turno ${vista.turno} · ${d.nombreDe('jefe')} '
                '${_rep('◆', d.vidasDe('jefe'))}${_rep('◇', (d.vidasMax[d.idDe('jefe')] ?? 0) - d.vidasDe('jefe'))}'
                ' · ${vidas('cazador')}'
            : '⚔ Duelo · turno ${vista.turno}${d.turnoLimite > 0 ? '/${d.turnoLimite}' : ''} · '
                '${vidas('jefe')} · ${vidas('cazador')}'
                '${d.embestida ? '' : ' · ${vidas('verdugo')}'}',
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFD9A8),
            fontFamily: 'Cinzel'),
      ));
      final avisos = <String>[];
      final mu = d.muralla;
      if (mu != null) {
        // Duelo de la muralla (nefilim_2).
        final jefe = d.nombreDe('jefe');
        final accion = mu.accionEn(vista.turno);
        switch (accion) {
          case 'avanzar':
          case 'giraYCarga':
            avisos.add(
                '${accion == 'giraYCarga' ? '↻${flechaDir(mu.planDir)} Se gira y ' : '🐂 '}'
                '${accion == 'giraYCarga' ? 'carga' : 'Carga'} hasta ${mu.planFin}: sal del carril rojo'
                '${mu.planLaterales.isNotEmpty ? ' (3 de ancho)' : ''}');
            if (mu.planHundira) {
              avisos.add('🕳 ¡Terminará sobre una grieta profunda y se hundirá!');
            }
          case 'girar':
            avisos.add(
                '↻ $jefe se gira hacia el ${nombreDir(mu.planDir)} sin moverse: '
                '¡si llegas a su casilla, golpéala!');
          case 'barrido':
            avisos.add('🛡 BARRIDO: aléjate de las 8 casillas que la rodean');
          case 'aturdida':
            avisos.add('😵 $jefe está hundida: ¡entra en su casilla!');
        }
        avisos.add(mu.escudoDoble
            ? '🛡 Escudo doble: solo la espalda la hiere'
            : '🛡 Escudo frontal ${flechaDir(mu.orientacion)}: golpéala por el flanco o la espalda');
        final faltan = mu.lineaProximoAvance - vista.turno;
        avisos.add(faltan <= 0
            ? '🛡 La línea (fila ${mu.lineaLetra}) avanza al cerrar este turno'
            : '🛡 La línea (fila ${mu.lineaLetra}) avanza en $faltan turno${faltan == 1 ? '' : 's'}');
        if (mu.odioDeclaradoEn(vista.turno) || vista.odioActivo) {
          avisos.add('🔥 EMBESTIDA DEL ODIO lista: choca con ella de frente');
        } else if (mu.odioListo) {
          avisos.add('🔥 Odio ${mu.odioPuntos}/${mu.odioMax}: lanza la embestida desde la ficha de Alexander');
        } else if (mu.odioPuntos > 0) {
          avisos.add('🔥 Odio ${mu.odioPuntos}/${mu.odioMax}');
        }
      } else if (d.embestida) {
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

    final cc = vista.carcel;
    if (cc != null) {
      if (lineas.isNotEmpty) lineas.add(const SizedBox(height: 2));
      final sala = cc.sala;
      if (sala != null) {
        lineas.add(Text(
          '🏛 Sala ${cc.salaActual + 1}/${cc.salas.length} · ${sala.nombre} · '
          'puerta ${sala.puerta}',
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD9A8),
              fontFamily: 'Cinzel'),
        ));
      }
      final avisos = <(String, Color)>[];
      final alarmaColor = cc.alarmaMax > 0 && cc.alarma * 4 >= cc.alarmaMax * 3
          ? const Color(0xFFFF8A80)
          : const Color(0xFFE8E0D0);
      avisos.add((
        '🚨 Alarma ${cc.alarma}/${cc.alarmaMax}'
            '${cc.proximoUmbral > 0 ? ' · a ${cc.proximoUmbral} llega un ${cc.proximoNombre} a la puerta' : ''}',
        alarmaColor,
      ));
      if (sala != null) {
        for (var i = 0; i < sala.slots.length; i++) {
          final sl = sala.slots[i];
          NucleoCarcel? lleva;
          for (final n in cc.nucleos) {
            if (n.sala == cc.salaActual && n.slot == i) lleva = n;
          }
          if (lleva == null) {
            avisos.add((
              '${sl.icono} Busca el ${sl.nombre}'
                  '${sl.duracion > 0 ? ' (luego tendrás ${sl.duracion} turnos)' : ''}',
              const Color(0xFFCFF6F6),
            ));
          } else if (lleva.restantes > 0) {
            avisos.add((
              '${sl.icono} ¡Lo tienes! Se apaga en ${lleva.restantes} '
                  '${lleva.restantes == 1 ? 'turno: entra YA en ${sala.puerta}' : 'turnos'}',
              lleva.restantes == 1
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFFB8F5C4),
            ));
          } else {
            avisos.add((
              '${sl.icono} ¡Lo tienes! Llévalo a ${sala.puerta}',
              const Color(0xFFB8F5C4),
            ));
          }
        }
        final extras = <String>[
          if (sala.huye) '💨 el portador huye',
          if (sala.intercambios > 0) '🔀 se pasan el núcleo',
        ];
        if (extras.isNotEmpty) {
          avisos.add((extras.join(' · '), const Color(0xFFE8E0D0)));
        }
      }
      for (final p in cc.pistasSalaActual.take(2)) {
        avisos.add(('🔎 $p', const Color(0xFFE8E0D0)));
      }
      if (vista.odioActivo) {
        avisos.add((
          '🔥 ODIO desatado este turno: +${cc.odioFuerza} de fuerza',
          const Color(0xFFFF8A80),
        ));
      } else if (cc.odioDisponible) {
        avisos.add((
          '🔥 Odio disponible (1 uso): desde la ficha de Alexander',
          const Color(0xFFE8E0D0),
        ));
      } else {
        avisos.add(('🔥 Odio ya desatado', const Color(0xFF9A9080)));
      }
      for (final (texto, color) in avisos) {
        lineas.add(Text(texto,
            style: TextStyle(
                fontSize: 8.5, color: color, fontFamily: 'Cinzel')));
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
