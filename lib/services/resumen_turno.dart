// lib/services/resumen_turno.dart
//
// RESUMEN EN TEXTO de un turno resuelto, a partir de una entrada de
// `historialCombates` (la misma que pinta el Informe de batalla). Genera
// secciones legibles tipo "crónica" (movimientos, acciones, combates,
// conquistas, energía) para la pestaña RESUMEN del informe y para poder
// copiarlo y compartirlo.
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

  ResumenTurno({
    required this.entrada,
    required this.localUid,
    required this.alias,
  });

  int get turno => (entrada['turno'] as num?)?.toInt() ?? 0;

  // ── utilidades ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _lista(String k) => (entrada[k] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  String _quien(String uid) => uid == localUid ? 'Tú' : alias(uid);

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

  // ── secciones ────────────────────────────────────────────────────────────
  List<SeccionResumen> generar() {
    final secciones = <SeccionResumen>[
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
        partes.add('${_cartas(cartas)} → $coord');
      }
      if (partes.isEmpty) continue;
      out.add('${_quien(uid)}: ${partes.join('; ')}.');
    }
    return SeccionResumen('Movimientos', out);
  }

  SeccionResumen _acciones() {
    final out = <String>[];
    for (final a in _lista('accionesLog')) {
      final uid = (a['uid'] ?? '').toString();
      final quien = _quien(uid);
      final tipo = (a['tipo'] ?? '').toString();
      final hab = (a['habilidadNombre'] ?? '').toString();
      final obj = (a['objetivo'] ?? a['destino'] ?? a['coord'] ?? '?').toString();
      final origen = (a['origen'] ?? a['cartaOrigenCoord'] ?? '').toString();
      final turnos = _int(a['turnosRestantes']);
      final dura = turnos > 0 ? ' durante $turnos turno(s)' : '';
      final conHab = hab.isNotEmpty ? ' ($hab)' : '';
      final destruidas = (a['cartasDestruidas'] as List? ?? const [])
          .whereType<Map>()
          .toList();

      switch (tipo) {
        case 'disparo':
          final desde = origen.isNotEmpty ? ' desde $origen' : '';
          if (destruidas.isEmpty) {
            out.add('$quien disparó$conHab$desde contra $obj sin causar bajas.');
          } else {
            final victimas = destruidas
                .map((c) => (c['ownerUid'] ?? '').toString())
                .where((u) => u.isNotEmpty)
                .toSet()
                .map(_quien)
                .toList();
            final pc = _int(a['pc']);
            out.add('$quien disparó$conHab$desde contra $obj y destruyó '
                '${_cartas(destruidas)}'
                '${victimas.isNotEmpty ? ' de ${_enumerar(victimas)}' : ''}'
                '${pc > 0 ? ' (+$pc PC)' : ''}.');
          }
          break;
        case 'teletransporte':
          out.add('$quien teletransportó ${a['cartaNombre'] ?? 'una carta'} '
              'de ${a['cartaOrigenCoord'] ?? '?'} a ${a['destino'] ?? '?'}.');
          break;
        case 'veneno':
          final mag = _int(a['magnitud']);
          out.add('$quien envenenó $obj$conHab'
              '${mag > 0 ? ' (−$mag defensa a los rivales)' : ''}$dura.');
          break;
        case 'paralisis':
          out.add('$quien paralizó las cartas rivales de $obj$conHab$dura.');
          break;
        case 'escudo':
          out.add('$quien levantó un escudo en $obj$conHab$dura: '
              'la celda queda protegida frente a habilidades.');
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
          out.add('$quien potenció la $que en $obj$conHab'
              '${mag != 0 ? ' (+$mag)' : ''}$dura.');
          break;
        case 'descarga':
          final coord = (a['coord'] ?? '?').toString();
          final propias = uid == localUid
              ? destruidas
              : destruidas
                  .where((c) => (c['ownerUid'] ?? '').toString() == localUid)
                  .toList();
          final ocultas = destruidas.length - propias.length;
          var txt = '$quien descargó su cuartel en $coord: ';
          if (destruidas.isEmpty) {
            txt += 'estaba vacío, sin bajas.';
          } else {
            txt += 'murieron ${destruidas.length} carta(s)';
            if (propias.isNotEmpty) txt += ' (${_cartas(propias)})';
            if (ocultas > 0 && uid != localUid) {
              txt += ', $ocultas de ellas de su guarnición (ocultas)';
            }
            txt += '.';
          }
          out.add(txt);
          break;
        case 'fallida':
        case 'descarga_fallida':
          final motivo = (a['motivo'] ?? 'no se pudo resolver').toString();
          out.add('La acción de $quien$conHab sobre $obj falló: $motivo.');
          break;
        default:
          out.add('$quien usó ${hab.isNotEmpty ? hab : tipo} sobre $obj.');
      }
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
      var txt = 'Combate en $coord${esObelisco ? ' (obelisco)' : ''}: '
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
      final perd = _quien((q['perdedorUid'] ?? '').toString());
      final coord = (q['coord'] ?? '?').toString();
      final tipo = (q['tipo'] ?? '').toString();
      if (tipo == 'conquista_cuartel') {
        out.add('$conq conquistó el cuartel de $perd en $coord: '
            '$perd queda eliminado.');
      } else {
        out.add('$conq conquistó $coord a $perd.');
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
