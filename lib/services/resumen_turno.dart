// lib/services/resumen_turno.dart
//
// RESUMEN EN TEXTO de un turno resuelto, a partir de una entrada de
// `historialCombates` (la misma que pinta el Informe de batalla). Genera
// secciones legibles tipo "crónica" (movimientos, acciones, combates,
// conquistas, energía) para la pestaña RESUMEN del informe y para poder
// copiarlo y compartirlo.
//
// · Las celdas que son CUARTEL se nombran como "Cuartel de X" (o "tu Cuartel")
//   en vez de por su coordenada.
// · Cada acción indica si tuvo efecto sobre cartas ENEMIGAS o no.
//
// Solo usa lo que el servidor ya publica en el informe (no revela nada nuevo):
// los movimientos invisibles ya vienen filtrados y la guarnición de una
// descarga rival se cuenta sin nombrarla, igual que en la pestaña ACCIONES.

class SeccionResumen {
  final String titulo;
  final List<String> lineas;
  const SeccionResumen(this.titulo, this.lineas);
}

class ResumenTurno {
  final Map<String, dynamic> entrada;
  final String localUid;
  final String Function(String uid) alias;

  /// Cuarteles de la partida: uid → coordenada.
  final Map<String, String> cuarteles;

  ResumenTurno({
    required this.entrada,
    required this.localUid,
    required this.alias,
    this.cuarteles = const {},
  });

  int get turno => (entrada['turno'] as num?)?.toInt() ?? 0;

  // ── utilidades ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _lista(String k) => (entrada[k] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  String _quien(String uid) => uid == localUid ? 'Tú' : alias(uid);

  /// coord → uid del dueño del cuartel. Incluye los cuarteles conquistados
  /// este turno (su dueño puede haber desaparecido ya de `obeliscos`).
  late final Map<String, String> _duenoCuartel = () {
    final m = <String, String>{};
    for (final kv in cuarteles.entries) {
      if (kv.value.isNotEmpty) m[kv.value] = kv.key;
    }
    for (final q in _lista('conquistasLog')) {
      if ((q['tipo'] ?? '') != 'conquista_cuartel') continue;
      final coord = (q['coord'] ?? '').toString();
      final perd = (q['perdedorUid'] ?? '').toString();
      if (coord.isNotEmpty && perd.isNotEmpty) m[coord] = perd;
    }
    return m;
  }();

  /// Nombre legible de una celda: "Cuartel de X" / "tu Cuartel" o la coord.
  String _celda(String coord) {
    final dueno = _duenoCuartel[coord];
    if (dueno == null) return coord;
    return dueno == localUid ? 'tu Cuartel' : 'el Cuartel de ${alias(dueno)}';
  }

  String _nombre(Map c) =>
      (c['Nombre'] ?? c['nombre'] ?? c['cartaNombre'] ?? 'una carta').toString();

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  String _enumerar(List<String> xs) {
    if (xs.isEmpty) return '';
    if (xs.length == 1) return xs.first;
    return '${xs.sublist(0, xs.length - 1).join(', ')} y ${xs.last}';
  }

  /// "Soldado ×2, Capitán" a partir de una lista de cartas.
  String _cartas(Iterable<Map> cartas) {
    final cuenta = <String, int>{};
    for (final c in cartas) {
      final n = _nombre(c);
      cuenta[n] = (cuenta[n] ?? 0) + 1;
    }
    return cuenta.entries
        .map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key)
        .join(', ');
  }

  /// "de Itachi y Madara" con los dueños de [cartas].
  String _duenos(Iterable<Map> cartas) {
    final us = cartas
        .map((c) => (c['ownerUid'] ?? '').toString())
        .where((u) => u.isNotEmpty)
        .toSet()
        .map(_quien)
        .toList();
    return us.isEmpty ? '' : ' de ${_enumerar(us)}';
  }

  // ── secciones ────────────────────────────────────────────────────────────
  List<SeccionResumen> generar() {
    final secciones = <SeccionResumen>[
      _comprasRobosSacrificios(),
      _movimientos(),
      _acciones(),
      _combates(),
      _conquistasYExpulsiones(),
      _energia(),
    ].where((s) => s.lineas.isNotEmpty).toList();

    if (secciones.isEmpty) {
      secciones.add(const SeccionResumen(
          'Turno tranquilo', ['No hubo movimientos, acciones ni combates.']));
    }
    return secciones;
  }

  /// Compras de GENERALES, ROBOS de carta y SACRIFICIOS del turno, sacados
  /// del libro de economía (`economiaLog`; solo partidas con el servidor
  /// nuevo). Las cartas que roba un RIVAL no se nombran (su mano es privada);
  /// las tuyas sí. Generales y sacrificios se nombran siempre: el general sale
  /// al tablero y la carta sacrificada ya no está en ninguna mano.
  SeccionResumen _comprasRobosSacrificios() {
    final out = <String>[];
    final eco =
        Map<String, dynamic>.from(entrada['economiaLog'] as Map? ?? const {});
    for (final kv in eco.entries) {
      final uid = kv.key;
      final esYo = uid == localUid;
      final quien = _quien(uid);
      final e = Map<String, dynamic>.from(kv.value as Map? ?? const {});
      final movs = (e['movimientos'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      // Generales devueltos con "deshacer": no cuentan como comprados.
      final deshechos = movs
          .where((m) => m['concepto'] == 'deshacer')
          .expand((m) => (m['especialesQuitadas'] as List? ?? const []))
          .map((x) => x.toString())
          .toSet();

      int robos = 0, precioRobos = 0, energiaSacrificio = 0;
      final robadas = <String>[];
      final sacrificadas = <String>[];
      for (final m in movs) {
        // Generales.
        final esp = (m['especial'] ?? '').toString();
        if (esp.isNotEmpty && !deshechos.contains(esp)) {
          final nombre = (m['especialNombre'] ?? '').toString();
          final coste = _int(m['especialCoste']);
          out.add('$quien ${esYo ? 'compraste' : 'compró'} el general '
              '${nombre.isNotEmpty ? nombre : '(sin nombre)'}'
              '${coste > 0 ? ' por $coste de energía' : ''}.');
        }
        // Robos.
        final r = _int(m['robos']);
        if (r > 0) {
          robos += r;
          precioRobos += _int(m['precioRobos']);
          robadas.addAll((m['cartasRobadasNombres'] as List? ?? const [])
              .map((x) => x.toString())
              .where((x) => x.isNotEmpty));
        }
        // Sacrificios.
        final sac = (m['sacrificadas'] as List? ?? const []);
        if (sac.isNotEmpty) {
          final nombres = (m['sacrificadasNombres'] as List? ?? const [])
              .map((x) => x.toString())
              .where((x) => x.isNotEmpty)
              .toList();
          if (nombres.length == sac.length) {
            sacrificadas.addAll(nombres);
          } else {
            sacrificadas.addAll(List.filled(sac.length, 'una carta'));
          }
          energiaSacrificio += _int(m['energiaSacrificio']);
        }
      }

      if (robos > 0) {
        final precio = precioRobos > 0 ? ' por $precioRobos de energía' : '';
        if (esYo && robadas.isNotEmpty) {
          out.add('Robaste ${_enumerar(_contarNombres(robadas))}$precio.');
        } else {
          out.add('$quien ${esYo ? 'robaste' : 'robó'} '
              '${robos == 1 ? 'una carta' : '$robos cartas'}$precio.');
        }
      }
      if (sacrificadas.isNotEmpty) {
        out.add('$quien ${esYo ? 'sacrificaste' : 'sacrificó'} '
            '${_enumerar(_contarNombres(sacrificadas))}'
            '${energiaSacrificio > 0 ? ' y ${esYo ? 'recuperaste' : 'recuperó'} '
                '$energiaSacrificio de energía' : ''}.');
      }
    }
    return SeccionResumen('Compras, robos y sacrificios', out);
  }

  /// ["Misil", "Misil", "Escudo"] → ["Misil ×2", "Escudo"].
  List<String> _contarNombres(List<String> nombres) {
    final cuenta = <String, int>{};
    for (final n in nombres) {
      cuenta[n] = (cuenta[n] ?? 0) + 1;
    }
    return cuenta.entries
        .map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key)
        .toList();
  }

  SeccionResumen _movimientos() {
    final out = <String>[];
    for (final m in _lista('movimientosLog')) {
      final uid = (m['uid'] ?? '').toString();
      final celdas = Map<String, dynamic>.from(m['celdas'] as Map? ?? const {});
      if (celdas.isEmpty) continue;
      final partes = <String>[];
      final coords = celdas.keys.toList()..sort();
      for (final coord in coords) {
        final cartas = (celdas[coord] as List? ?? const []).whereType<Map>();
        if (cartas.isEmpty) continue;
        partes.add('${_cartas(cartas)} → ${_celda(coord)}');
      }
      if (partes.isEmpty) continue;
      out.add('${_quien(uid)}: ${partes.join('; ')}.');
    }
    return SeccionResumen('Movimientos', out);
  }

  SeccionResumen _acciones() {
    final out = <String>[];
    final acciones = _lista('accionesLog');

    // Rechazos de escudo: el servidor anota UNA entrada por carta rebotada;
    // se agrupan por (jugador, celda escudada, celda de vuelta).
    final rebotes = <String, List<Map<String, dynamic>>>{};

    for (final a in acciones) {
      final uid = (a['uid'] ?? '').toString();
      final quien = _quien(uid);
      final tipo = (a['tipo'] ?? '').toString();
      final hab = (a['habilidadNombre'] ?? '').toString();
      final objCoord =
          (a['objetivo'] ?? a['destino'] ?? a['coord'] ?? '').toString();
      final obj = objCoord.isEmpty ? '?' : _celda(objCoord);
      final origenCoord = (a['origen'] ?? a['cartaOrigenCoord'] ?? '').toString();
      final turnos = _int(a['turnosRestantes']);
      final dura = turnos > 0 ? ' durante $turnos turno(s)' : '';
      final conHab = hab.isNotEmpty ? ' ($hab)' : '';
      final destruidas = (a['cartasDestruidas'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final enemigasDestruidas = destruidas
          .where((c) => (c['ownerUid'] ?? '').toString() != uid)
          .toList();
      final propiasDestruidas = destruidas
          .where((c) => (c['ownerUid'] ?? '').toString() == uid)
          .toList();

      // Cartas enemigas alcanzadas por veneno/parálisis (servidor nuevo). Si el
      // campo no está (partidas antiguas) no se puede afirmar nada.
      final afectadasRaw = a['cartasAfectadas'];
      final afectadas = afectadasRaw is List
          ? afectadasRaw.whereType<Map>().toList()
          : null;
      String efectoAfectadas() {
        if (afectadas == null) return '';
        if (afectadas.isEmpty) {
          return ' Sin efecto: no había cartas enemigas en la celda al resolver.';
        }
        return ' Afectó a ${_cartas(afectadas)}${_duenos(afectadas)}.';
      }

      switch (tipo) {
        case 'disparo':
          final desde = origenCoord.isNotEmpty ? ' desde ${_celda(origenCoord)}' : '';
          var txt = '$quien disparó$conHab$desde contra $obj.';
          if (enemigasDestruidas.isEmpty) {
            txt += ' Sin efecto sobre cartas enemigas';
            txt += destruidas.isEmpty ? ' (la celda estaba vacía).' : '.';
          } else {
            final pc = _int(a['pc']);
            txt += ' Destruyó ${_cartas(enemigasDestruidas)}'
                '${_duenos(enemigasDestruidas)}'
                '${pc > 0 ? ' (+$pc PC)' : ''}.';
          }
          if (propiasDestruidas.isNotEmpty) {
            txt += ' También cayeron cartas propias: '
                '${_cartas(propiasDestruidas)}.';
          }
          out.add(txt);
          break;
        case 'teletransporte':
          out.add('$quien teletransportó ${a['cartaNombre'] ?? 'una carta'} '
              'de ${_celda((a['cartaOrigenCoord'] ?? '?').toString())} '
              'a ${_celda((a['destino'] ?? '?').toString())}. '
              'Sin efecto directo sobre cartas enemigas.');
          break;
        case 'veneno':
          final mag = _int(a['magnitud']);
          out.add('$quien envenenó $obj$conHab'
              '${mag > 0 ? ' (−$mag defensa a los rivales)' : ''}$dura.'
              '${efectoAfectadas()}');
          break;
        case 'paralisis':
          out.add('$quien lanzó una parálisis sobre $obj$conHab$dura.'
              '${efectoAfectadas()}');
          break;
        case 'escudo':
          out.add('$quien levantó un escudo en $obj$conHab$dura. '
              'No afecta a cartas: protege la celda frente a habilidades y '
              'movimientos rivales.');
          break;
        case 'escudoBloqueoMovimiento':
          final clave = '$uid|$objCoord|$origenCoord';
          (rebotes[clave] ??= []).add(a);
          break;
        case 'potFuerza':
        case 'potDefensa':
        case 'potMovimiento':
          final que = tipo == 'potFuerza'
              ? 'fuerza'
              : tipo == 'potDefensa'
                  ? 'defensa'
                  : 'movimiento';
          final mag = _int(a['magnitud']);
          out.add('$quien potenció la $que de sus cartas en $obj$conHab'
              '${mag != 0 ? ' (+$mag)' : ''}$dura. '
              'Efecto sobre cartas propias, no sobre enemigas.');
          break;
        case 'descarga':
          final coord = (a['coord'] ?? objCoord).toString();
          final enemigasVisibles = uid == localUid
              ? enemigasDestruidas
              : enemigasDestruidas
                  .where((c) => (c['ownerUid'] ?? '').toString() == localUid)
                  .toList();
          var txt = '$quien descargó ${_celda(coord)}: ';
          if (destruidas.isEmpty) {
            txt += 'estaba vacío, sin bajas.';
          } else if (enemigasDestruidas.isEmpty) {
            txt += 'murieron ${destruidas.length} carta(s), todas propias; '
                'sin efecto sobre cartas enemigas.';
          } else {
            txt += 'destruyó ${enemigasDestruidas.length} carta(s) enemiga(s)';
            if (enemigasVisibles.isNotEmpty) {
              txt += ' (${_cartas(enemigasVisibles)}'
                  '${_duenos(enemigasVisibles)})';
            }
            final propias = propiasDestruidas.length;
            if (propias > 0) {
              txt += uid == localUid
                  ? ' y $propias tuya(s) (${_cartas(propiasDestruidas)})'
                  : ' y $propias de su guarnición (ocultas)';
            }
            txt += '.';
          }
          out.add(txt);
          break;
        case 'fallida':
        case 'descarga_fallida':
          final motivo = (a['motivo'] ?? 'no se pudo resolver').toString();
          final sobre = objCoord.isNotEmpty ? ' sobre $obj' : '';
          out.add('La acción de $quien$conHab$sobre falló: $motivo. '
              'Sin efecto sobre cartas enemigas.');
          break;
        default:
          out.add('$quien usó ${hab.isNotEmpty ? hab : tipo}'
              '${objCoord.isNotEmpty ? ' sobre $obj' : ''}.');
      }
    }

    for (final grupo in rebotes.values) {
      final a = grupo.first;
      final quien = _quien((a['uid'] ?? '').toString());
      final destino = _celda((a['objetivo'] ?? '?').toString());
      final vuelta = _celda((a['origen'] ?? '?').toString());
      final nombres = grupo
          .map((e) => (e['cartaNombre'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList();
      final que = nombres.isNotEmpty
          ? _cartas(nombres.map((n) => {'Nombre': n}))
          : '${grupo.length} carta(s)';
      out.add('Un escudo en $destino rechazó el movimiento de $quien: '
          '$que vuelve(n) a $vuelta.');
    }
    return SeccionResumen('Acciones', out);
  }

  SeccionResumen _combates() {
    final out = <String>[];
    for (final c in _lista('combateLog')) {
      final coord = (c['coord'] ?? '?').toString();
      final ganador = (c['ganadorUid'] ?? '').toString();
      final derrotados = (c['derrotadosUid'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      final detalle = (c['detalle'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Bandos con su poder y sus cartas.
      final bandos = detalle.map((d) {
        final u = (d['ownerUid'] ?? '').toString();
        final cartas = (d['cartas'] as List? ?? const []).whereType<Map>();
        final f = _int(d['totalFuerza']);
        final def = _int(d['totalDefensa']);
        final extras = <String>[];
        if (_int(d['bonusEscudo']) > 0) extras.add('escudo +${_int(d['bonusEscudo'])}');
        if (_int(d['reduccionVeneno']) > 0) {
          extras.add('veneno −${_int(d['reduccionVeneno'])}');
        }
        if (d['confuso'] == true) extras.add('confuso');
        return '${_quien(u)} con ${_cartas(cartas)} '
            '(F $f / D $def${extras.isNotEmpty ? ', ${extras.join(', ')}' : ''})';
      }).toList();

      final esObelisco = c['esConquistaObelisco'] == true;
      final lugar = _celda(coord);
      var txt = 'Combate en $lugar'
          '${esObelisco && lugar == coord ? ' (obelisco)' : ''}: '
          '${_enumerar(bandos)}. ';
      if (ganador.isEmpty) {
        txt += 'Sin vencedor: todos los bandos cayeron o empataron.';
      } else {
        final energias = _int((c['energiesGanadas'] as Map? ?? const {})[ganador]);
        final pc = _int((c['pcGanados'] as Map? ?? const {})[ganador]);
        final premio = <String>[
          if (energias > 0) '+$energias de energía',
          if (pc > 0) '+$pc PC',
        ];
        txt += 'Gana ${_quien(ganador)}';
        if (derrotados.isNotEmpty) {
          txt += ' frente a ${_enumerar(derrotados.map(_quien).toList())}';
        }
        if (premio.isNotEmpty) txt += ' (${premio.join(', ')})';
        txt += '.';
      }
      out.add(txt);
    }
    return SeccionResumen('Combates', out);
  }

  SeccionResumen _conquistasYExpulsiones() {
    final out = <String>[];
    for (final q in _lista('conquistasLog')) {
      final conq = _quien((q['conquistadorUid'] ?? '').toString());
      final perdUid = (q['perdedorUid'] ?? '').toString();
      final perd = _quien(perdUid);
      final coord = (q['coord'] ?? '?').toString();
      final tipo = (q['tipo'] ?? '').toString();
      if (tipo == 'conquista_cuartel') {
        final cuartel = perdUid == localUid ? 'tu Cuartel' : 'el Cuartel de $perd';
        out.add('$conq conquistó $cuartel: '
            '${perdUid == localUid ? 'quedas eliminado' : '$perd queda eliminado'}.');
      } else {
        out.add('$conq conquistó ${_celda(coord)} a $perd.');
      }
    }
    for (final e in _lista('expulsionesLog')) {
      final quien = _quien((e['uid'] ?? '').toString());
      final n = _int(e['turnosSinCerrar']);
      out.add('$quien fue expulsado por inactividad'
          '${n > 0 ? ' ($n turnos sin cerrar)' : ''}; '
          'su energía y PC se repartieron entre los rivales.');
    }
    return SeccionResumen('Conquistas y eliminaciones', out);
  }

  static const _fuentes = {
    'islaCentral': 'isla central',
    'continenteEnemigo': 'continente enemigo',
    'rayo': 'rayo',
    'suerteDelPerdedor': 'suerte del perdedor',
    'expulsion': 'reparto por expulsión',
  };

  SeccionResumen _energia() {
    final out = <String>[];
    for (final f in _lista('farmeoLog')) {
      final quien = _quien((f['uid'] ?? '').toString());
      final total = _int(f['totalEnergies']);
      if (total == 0) continue;
      final det = Map<String, dynamic>.from(f['detalle'] as Map? ?? const {});
      final partes = det.entries
          .where((e) => _int(e.value) != 0)
          .map((e) => '${_fuentes[e.key] ?? e.key} +${_int(e.value)}')
          .toList();
      out.add('$quien farmeó +$total'
          '${partes.isNotEmpty ? ' (${partes.join(', ')})' : ''}.');
    }
    final rayos = (entrada['rayoCoords'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    if (rayos.isNotEmpty) {
      out.add('Rayos activos para el siguiente turno: ${rayos.join(', ')}.');
    }

    // Libro de economía (solo partidas con el servidor nuevo): saldo de cada
    // jugador antes y después de resolver.
    final eco = Map<String, dynamic>.from(entrada['economiaLog'] as Map? ?? const {});
    for (final kv in eco.entries) {
      final e = Map<String, dynamic>.from(kv.value as Map? ?? const {});
      final antes = _int(e['saldoAntesResolucion']);
      final tras = _int(e['saldoTrasResolucion']);
      final gasto = _int(e['gastoRegistrado']);
      if (antes == 0 && tras == 0 && gasto == 0) continue;
      final movs = (e['movimientos'] as List? ?? const []).whereType<Map>();
      final sacrificios = movs
          .expand((m) => (m['sacrificadas'] as List? ?? const []))
          .length;
      out.add('${_quien(kv.key)}: '
          '${gasto != 0 ? 'movimientos del turno ${gasto > 0 ? '+' : ''}$gasto, ' : ''}'
          '${sacrificios > 0 ? '$sacrificios carta(s) sacrificada(s), ' : ''}'
          'saldo al cerrar $antes → tras resolver $tras.');
    }
    return SeccionResumen('Energía', out);
  }

  /// Texto plano completo (para copiar).
  String comoTexto() {
    final b = StringBuffer('TURNO $turno\n');
    for (final s in generar()) {
      b.writeln('\n${s.titulo.toUpperCase()}');
      for (final l in s.lineas) {
        b.writeln('• $l');
      }
    }
    return b.toString();
  }
}
