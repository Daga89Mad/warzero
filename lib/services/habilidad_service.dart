// lib/services/habilidad_service.dart

import '../models/accion_pendiente.dart';
import '../models/efecto_estado.dart';
import '../models/game_config.dart';
import '../models/habilidad_model.dart';

// ─────────────────────────────────────────────────────────────────────────
// RESULTADOS
// ─────────────────────────────────────────────────────────────────────────

/// Resultado de aplicar acciones al tablero antes de combates.
class ResultadoAplicarAcciones {
  /// Tablero tras teletransportes, disparos y aplicación de venenos.
  final Map<String, List<Map<String, dynamic>>> tableroResultante;

  /// Efectos activos en celdas (nuevos venenos añadidos).
  final Map<String, List<EfectoActivo>> efectosCeldaResultante;

  /// Log de acciones aplicadas, para el Informe de Batalla.
  final List<Map<String, dynamic>> log;

  const ResultadoAplicarAcciones({
    required this.tableroResultante,
    required this.efectosCeldaResultante,
    required this.log,
  });
}

/// Resultado de avanzar un turno los efectos persistentes (decrementar).
class ResultadoTickEfectos {
  final Map<String, List<Map<String, dynamic>>> tableroResultante;
  final Map<String, List<EfectoActivo>> efectosCeldaResultante;

  const ResultadoTickEfectos({
    required this.tableroResultante,
    required this.efectosCeldaResultante,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// SERVICIO
// ─────────────────────────────────────────────────────────────────────────

class HabilidadService {
  HabilidadService._();

  static const List<(int, int)> _deltas = [
    (-1, 0),
    (1, 0),
    (0, -1),
    (0, 1),
  ];

  // ── Conversión de coordenadas ────────────────────────────────────────────

  static (int, int)? _coordToPos(String coord, GameConfig config) {
    if (coord.length < 2) return null;
    final ri = config.rowLabels.indexOf(coord[0]);
    final colNum = int.tryParse(coord.substring(1));
    if (colNum == null) return null;
    final ci = config.colLabels.indexOf(colNum);
    if (ri == -1 || ci == -1) return null;
    return (ri, ci);
  }

  // ── Cálculo de objetivos válidos ─────────────────────────────────────────

  /// Devuelve el conjunto de celdas elegibles como objetivo de [habilidad]
  /// desde la celda [origen]. NO consulta el terreno (las habilidades son
  /// efectos a distancia/mágicos; el rango es Manhattan ortogonal).
  ///
  /// [obeliscosPorJugador] es necesario para aplicar `excluyeCG`.
  static Set<String> calcularObjetivosValidos({
    required String origen,
    required Habilidad habilidad,
    required GameConfig config,
    required Map<String, String> obeliscosPorJugador,
  }) {
    final candidatos = <String>{};

    switch (habilidad.rango.tipo) {
      case RangoTipo.frontera:
        candidatos.addAll(_frontera(origen, config));
        break;
      case RangoTipo.radio:
        candidatos.addAll(_radio(origen, habilidad.rango.distancia, config));
        break;
      case RangoTipo.cualquiera:
        candidatos.addAll(_todasLasCeldas(config));
        break;
    }

    // El origen nunca es objetivo válido (no te lanzas a ti mismo).
    candidatos.remove(origen);

    // Filtrar cuarteles generales si la habilidad lo requiere.
    if (habilidad.excluyeCG && obeliscosPorJugador.isNotEmpty) {
      final cgs = obeliscosPorJugador.values.toSet();
      candidatos.removeWhere((c) => cgs.contains(c));
    }

    return candidatos;
  }

  static Set<String> _frontera(String origen, GameConfig config) {
    final pos = _coordToPos(origen, config);
    if (pos == null) return {};
    final result = <String>{};
    for (final (dr, dc) in _deltas) {
      final nr = pos.$1 + dr;
      final nc = pos.$2 + dc;
      if (nr < 0 || nr >= config.rows || nc < 0 || nc >= config.cols) continue;
      result.add(config.coordLabel(nr, nc));
    }
    return result;
  }

  static Set<String> _radio(String origen, int radio, GameConfig config) {
    if (radio <= 0) return {};
    final pos = _coordToPos(origen, config);
    if (pos == null) return {};

    final visited = <String, int>{origen: 0};
    // (coord, steps, ri, ci)
    final queue = <(String, int, int, int)>[(origen, 0, pos.$1, pos.$2)];
    int head = 0;
    final result = <String>{};

    while (head < queue.length) {
      final (coord, steps, ri, ci) = queue[head++];
      if (steps >= radio) continue;
      for (final (dr, dc) in _deltas) {
        final nr = ri + dr;
        final nc = ci + dc;
        if (nr < 0 || nr >= config.rows || nc < 0 || nc >= config.cols) {
          continue;
        }
        final nCoord = config.coordLabel(nr, nc);
        final newSteps = steps + 1;
        if ((visited[nCoord] ?? 999) <= newSteps) continue;
        visited[nCoord] = newSteps;
        result.add(nCoord);
        if (newSteps < radio) {
          queue.add((nCoord, newSteps, nr, nc));
        }
      }
    }
    return result;
  }

  static List<String> _todasLasCeldas(GameConfig config) {
    final result = <String>[];
    for (int ri = 0; ri < config.rows; ri++) {
      for (int ci = 0; ci < config.cols; ci++) {
        result.add(config.coordLabel(ri, ci));
      }
    }
    return result;
  }

  // ── Aplicar acciones ─────────────────────────────────────────────────────

  /// Aplica todas las acciones pendientes al tablero, en este orden:
  ///   1. Teletransportes (las cartas movidas pueden esquivar disparos).
  ///   2. Disparos (eliminan cartas en la celda objetivo).
  ///   3. Venenos (marcan celdas y cartas).
  ///
  /// Tras aplicar nuevos venenos, propaga también el veneno de celdas que ya
  /// estaban envenenadas de turnos anteriores a las cartas que ahora están
  /// allí (cumpliendo "si una carta entra, también queda envenenada").
  ///
  /// El tablero y efectos de entrada NO se mutan; se devuelven copias.
  static ResultadoAplicarAcciones aplicarAcciones({
    required Map<String, List<Map<String, dynamic>>> tablero,
    required List<AccionPendiente> acciones,
    required Map<String, List<EfectoActivo>> efectosCelda,
    required Map<String, String> obeliscosPorJugador,
  }) {
    final t = _copiarTablero(tablero);
    final e = _copiarEfectos(efectosCelda);
    final log = <Map<String, dynamic>>[];

    // Segmentar por tipo de efecto.
    final teles = <AccionPendiente>[];
    final disparos = <AccionPendiente>[];
    final venenos = <AccionPendiente>[];

    for (final a in acciones) {
      final h = CatalogoHabilidades.get(a.habilidadId);
      if (h == null) continue;
      switch (h.efecto.tipo) {
        case EfectoTipo.teletransporte:
          teles.add(a);
          break;
        case EfectoTipo.disparo:
          disparos.add(a);
          break;
        case EfectoTipo.veneno:
          venenos.add(a);
          break;
      }
    }

    for (final a in teles) {
      _aplicarTeletransporte(a, t, log, obeliscosPorJugador);
    }
    for (final a in disparos) {
      _aplicarDisparo(a, t, log, obeliscosPorJugador);
    }
    for (final a in venenos) {
      _aplicarVeneno(a, t, e, log, obeliscosPorJugador);
    }

    // Propagar veneno preexistente a cartas que estén actualmente en la celda.
    _propagarVenenoACeldas(t, e);

    return ResultadoAplicarAcciones(
      tableroResultante: t,
      efectosCeldaResultante: e,
      log: log,
    );
  }

  static void _aplicarTeletransporte(
    AccionPendiente a,
    Map<String, List<Map<String, dynamic>>> t,
    List<Map<String, dynamic>> log,
    Map<String, String> obeliscosPorJugador,
  ) {
    final h = CatalogoHabilidades.get(a.habilidadId);
    if (h == null) return;

    if (a.cartaOrigenCoord == null ||
        a.cartaOrigenIndice == null ||
        a.objetivos.isEmpty) {
      log.add(_logFallo(a, h, 'Datos de teletransporte incompletos'));
      return;
    }
    final fromCoord = a.cartaOrigenCoord!;
    final fromIdx = a.cartaOrigenIndice!;
    final destino = a.objetivos.first;

    if (h.excluyeCG && obeliscosPorJugador.values.contains(destino)) {
      log.add(_logFallo(a, h, 'No se puede teletransportar a un cuartel'));
      return;
    }

    final cartasOrigen = t[fromCoord];
    if (cartasOrigen == null || fromIdx < 0 || fromIdx >= cartasOrigen.length) {
      log.add(_logFallo(a, h, 'La carta origen ya no existe'));
      return;
    }

    // Solo se pueden mover cartas propias del jugador.
    final carta = cartasOrigen[fromIdx];
    final ownerUid = carta['ownerUid'] as String? ?? '';
    if (ownerUid != a.uid) {
      log.add(_logFallo(a, h, 'La carta origen no pertenece al jugador'));
      return;
    }

    cartasOrigen.removeAt(fromIdx);
    if (cartasOrigen.isEmpty) t.remove(fromCoord);
    t.putIfAbsent(destino, () => []).add(carta);

    log.add({
      'tipo': 'teletransporte',
      'habilidadId': h.id,
      'habilidadNombre': h.nombre,
      'uid': a.uid,
      'zona': a.zona,
      'origen': a.origen,
      'cartaOrigenCoord': fromCoord,
      'destino': destino,
      'cartaNombre': carta['Nombre'] ?? carta['nombre'] ?? '',
    });
  }

  static void _aplicarDisparo(
    AccionPendiente a,
    Map<String, List<Map<String, dynamic>>> t,
    List<Map<String, dynamic>> log,
    Map<String, String> obeliscosPorJugador,
  ) {
    final h = CatalogoHabilidades.get(a.habilidadId);
    if (h == null) return;

    for (final obj in a.objetivos) {
      if (h.excluyeCG && obeliscosPorJugador.values.contains(obj)) {
        continue;
      }
      final cartas = t[obj];
      final destruidas = (cartas ?? const [])
          .map((c) => {
                'id': c['id'] ?? c['Id'] ?? '',
                'Nombre': c['Nombre'] ?? c['nombre'] ?? '',
                'ownerUid': c['ownerUid'] ?? '',
                'ownerZone': c['ownerZone'] ?? '',
              })
          .toList();
      t.remove(obj);
      log.add({
        'tipo': 'disparo',
        'habilidadId': h.id,
        'habilidadNombre': h.nombre,
        'uid': a.uid,
        'zona': a.zona,
        'origen': a.origen,
        'objetivo': obj,
        'cartasDestruidas': destruidas,
      });
    }
  }

  static void _aplicarVeneno(
    AccionPendiente a,
    Map<String, List<Map<String, dynamic>>> t,
    Map<String, List<EfectoActivo>> e,
    List<Map<String, dynamic>> log,
    Map<String, String> obeliscosPorJugador,
  ) {
    final h = CatalogoHabilidades.get(a.habilidadId);
    if (h == null) return;

    for (final obj in a.objetivos) {
      if (h.excluyeCG && obeliscosPorJugador.values.contains(obj)) {
        continue;
      }
      final efecto = EfectoActivo(
        tipo: EfectoTipoEstado.veneno,
        turnosRestantes: h.efecto.duracionTurnos,
        magnitud: h.efecto.defensaReducida,
        origenUid: a.uid,
      );
      _agregarOFusionarEfectoCelda(e, obj, efecto);

      // Aplicar también a las cartas que estén ahora mismo en la celda.
      final cartas = t[obj] ?? const [];
      for (final c in cartas) {
        _agregarOFusionarEfectoCarta(c, efecto);
      }

      log.add({
        'tipo': 'veneno',
        'habilidadId': h.id,
        'habilidadNombre': h.nombre,
        'uid': a.uid,
        'zona': a.zona,
        'origen': a.origen,
        'objetivo': obj,
        'turnosRestantes': efecto.turnosRestantes,
        'magnitud': efecto.magnitud,
      });
    }
  }

  /// Para cada celda con efectos activos, garantiza que las cartas
  /// actualmente en la celda tienen el efecto registrado.
  /// Cumple: "si una carta entra en una celda envenenada, también queda
  /// envenenada".
  static void _propagarVenenoACeldas(
    Map<String, List<Map<String, dynamic>>> t,
    Map<String, List<EfectoActivo>> e,
  ) {
    e.forEach((coord, lista) {
      final cartas = t[coord];
      if (cartas == null || cartas.isEmpty) return;
      for (final ef in lista) {
        if (ef.tipo != EfectoTipoEstado.veneno) continue;
        for (final c in cartas) {
          _agregarOFusionarEfectoCarta(c, ef);
        }
      }
    });
  }

  // ── Tick: decrementar duración de todos los efectos ──────────────────────

  /// Decrementa en 1 los `turnosRestantes` de todos los efectos en celdas y
  /// cartas. Elimina los efectos expirados. Se llama tras resolver combates.
  static ResultadoTickEfectos tickEfectos({
    required Map<String, List<Map<String, dynamic>>> tablero,
    required Map<String, List<EfectoActivo>> efectosCelda,
  }) {
    final t = _copiarTablero(tablero);
    final e = <String, List<EfectoActivo>>{};

    // Celdas.
    efectosCelda.forEach((coord, lista) {
      final nuevos = lista
          .map((ef) => ef.decrementar())
          .where((ef) => !ef.expirado)
          .toList();
      if (nuevos.isNotEmpty) e[coord] = nuevos;
    });

    // Cartas: el campo 'Efectos' es una lista de mapas serializados.
    t.forEach((coord, cartas) {
      for (final c in cartas) {
        final raw = c['Efectos'] as List?;
        if (raw == null || raw.isEmpty) continue;
        final nuevos = raw
            .map((m) =>
                EfectoActivo.fromMap(Map<String, dynamic>.from(m as Map)))
            .map((ef) => ef.decrementar())
            .where((ef) => !ef.expirado)
            .map((ef) => ef.toMap())
            .toList();
        if (nuevos.isEmpty) {
          c.remove('Efectos');
        } else {
          c['Efectos'] = nuevos;
        }
      }
    });

    return ResultadoTickEfectos(
      tableroResultante: t,
      efectosCeldaResultante: e,
    );
  }

  // ── Helper para combate: reducción de defensa por efectos activos ────────

  /// Suma la magnitud total de efectos de tipo veneno activos en [carta].
  /// El servicio de combate usa esto para reducir la defensa efectiva.
  static int defensaReducidaPorEfectos(Map<String, dynamic> carta) {
    final raw = carta['Efectos'] as List?;
    if (raw == null) return 0;
    int total = 0;
    for (final m in raw) {
      final mm = Map<String, dynamic>.from(m as Map);
      final turnos = (mm['turnosRestantes'] as num?)?.toInt() ?? 0;
      if (turnos <= 0) continue;
      final tipo = mm['tipo'] as String?;
      if (tipo == EfectoTipoEstado.veneno.name) {
        total += (mm['magnitud'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  // ── Serialización de efectosCelda (para Firestore) ───────────────────────

  static Map<String, dynamic> efectosCeldaToMap(
          Map<String, List<EfectoActivo>> efectosCelda) =>
      efectosCelda
          .map((k, v) => MapEntry(k, v.map((ef) => ef.toMap()).toList()));

  static Map<String, List<EfectoActivo>> efectosCeldaFromMap(
      Map<String, dynamic>? raw) {
    final result = <String, List<EfectoActivo>>{};
    if (raw == null) return result;
    raw.forEach((k, v) {
      final lista = (v as List?)
              ?.map((m) =>
                  EfectoActivo.fromMap(Map<String, dynamic>.from(m as Map)))
              .toList() ??
          [];
      if (lista.isNotEmpty) result[k] = lista;
    });
    return result;
  }

  // ── Internos: copias y fusión ────────────────────────────────────────────

  static Map<String, List<Map<String, dynamic>>> _copiarTablero(
      Map<String, List<Map<String, dynamic>>> src) {
    final out = <String, List<Map<String, dynamic>>>{};
    src.forEach((k, v) {
      out[k] = v.map((c) {
        // copia profunda de Efectos también.
        final copy = Map<String, dynamic>.from(c);
        final ef = c['Efectos'] as List?;
        if (ef != null) {
          copy['Efectos'] =
              ef.map((m) => Map<String, dynamic>.from(m as Map)).toList();
        }
        return copy;
      }).toList();
    });
    return out;
  }

  static Map<String, List<EfectoActivo>> _copiarEfectos(
      Map<String, List<EfectoActivo>> src) {
    final out = <String, List<EfectoActivo>>{};
    src.forEach((k, v) {
      out[k] = List<EfectoActivo>.from(v);
    });
    return out;
  }

  /// Añade un efecto a la celda. Si ya hay uno del mismo tipo + origen,
  /// se queda con el de mayor `turnosRestantes` (refresca, no apila).
  static void _agregarOFusionarEfectoCelda(
    Map<String, List<EfectoActivo>> efectos,
    String coord,
    EfectoActivo nuevo,
  ) {
    final lista = efectos.putIfAbsent(coord, () => []);
    final idx = lista.indexWhere(
      (ef) => ef.tipo == nuevo.tipo && ef.origenUid == nuevo.origenUid,
    );
    if (idx == -1) {
      lista.add(nuevo);
    } else if (nuevo.turnosRestantes > lista[idx].turnosRestantes) {
      lista[idx] = nuevo;
    }
  }

  /// Como [_agregarOFusionarEfectoCelda] pero sobre el campo 'Efectos' de una
  /// carta en formato Map (la representación dentro del tablero serializado).
  static void _agregarOFusionarEfectoCarta(
    Map<String, dynamic> carta,
    EfectoActivo nuevo,
  ) {
    final raw = (carta['Efectos'] as List?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .toList() ??
        <Map<String, dynamic>>[];
    final idx = raw.indexWhere((m) =>
        (m['tipo'] as String?) == nuevo.tipo.name &&
        (m['origenUid'] as String?) == nuevo.origenUid);
    if (idx == -1) {
      raw.add(nuevo.toMap());
    } else {
      final actuales = (raw[idx]['turnosRestantes'] as num?)?.toInt() ?? 0;
      if (nuevo.turnosRestantes > actuales) {
        raw[idx] = nuevo.toMap();
      }
    }
    carta['Efectos'] = raw;
  }

  static Map<String, dynamic> _logFallo(
          AccionPendiente a, Habilidad h, String motivo) =>
      {
        'tipo': 'fallida',
        'habilidadId': h.id,
        'habilidadNombre': h.nombre,
        'uid': a.uid,
        'zona': a.zona,
        'origen': a.origen,
        'motivo': motivo,
      };
}
