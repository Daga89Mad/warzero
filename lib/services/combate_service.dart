// lib/services/combate_service.dart

/// ─────────────────────────────────────────────────────────────────────────
/// Sistema de combate de WarZero
///
/// REGLAS:
///   Al final de cada turno (antes de empezar el siguiente) se comprueba si
///   hay cartas de distintos jugadores en la misma celda.
///
///   Si las hay, se resuelve el combate por celda:
///     • poderNeto(X) = Σfuerza(X) − Σdefensa(todos los enemigos de X)
///     • El grupo con mayor poderNeto gana.
///     • Las cartas de los grupos perdedores se destruyen.
///     • En empate exacto entre dos o más grupos → todos destruidos.
///
///   Recompensas para el ganador (por cada grupo derrotado):
///     • Energies += Σcoste de las cartas destruidas del grupo derrotado.
///     • PC       += 3 × número de cartas destruidas del grupo derrotado.
/// ─────────────────────────────────────────────────────────────────────────

/// Datos de un grupo de cartas que pertenecen al mismo jugador en una celda.
class _GrupoJugador {
  final String ownerUid;
  final String ownerZone;
  final List<Map<String, dynamic>> cartas;

  _GrupoJugador({
    required this.ownerUid,
    required this.ownerZone,
    required this.cartas,
  });

  int get totalFuerza =>
      cartas.fold(0, (s, c) => s + ((c['fuerza'] as num?)?.toInt() ?? 0));

  int get totalDefensa =>
      cartas.fold(0, (s, c) => s + ((c['defensa'] as num?)?.toInt() ?? 0));

  int get totalCoste =>
      cartas.fold(0, (s, c) => s + ((c['coste'] as num?)?.toInt() ?? 0));

  int get numCartas => cartas.length;
}

// ─────────────────────────────────────────────────────────────────────────

/// Resultado del combate en una celda concreta.
class ResultadoCombate {
  /// Coordenada de la celda donde ocurrió el combate (e.g. "B5").
  final String coord;

  /// UID del jugador ganador. Null si fue un empate total (todos destruidos).
  final String? ganadorUid;

  /// Zone del ganador (para UI).
  final String? ganadorZone;

  /// UIDs de los jugadores cuyos grupos fueron derrotados.
  final List<String> derrotadosUid;

  /// Energies ganadas por jugador: uid → cantidad.
  final Map<String, int> energiesGanadas;

  /// PC ganados por jugador: uid → cantidad.
  final Map<String, int> pcGanados;

  /// Cartas que sobreviven en la celda tras el combate.
  final List<Map<String, dynamic>> cartasSupervivientes;

  /// Detalle para mostrar en el log de la partida.
  final List<Map<String, dynamic>> detalle;

  const ResultadoCombate({
    required this.coord,
    required this.ganadorUid,
    required this.ganadorZone,
    required this.derrotadosUid,
    required this.energiesGanadas,
    required this.pcGanados,
    required this.cartasSupervivientes,
    required this.detalle,
  });

  /// Serializa para guardar en Firestore como log del último combate.
  Map<String, dynamic> toLogMap() => {
        'coord': coord,
        'ganadorUid': ganadorUid,
        'ganadorZone': ganadorZone,
        'derrotadosUid': derrotadosUid,
        'energiesGanadas': energiesGanadas,
        'pcGanados': pcGanados,
        'detalle': detalle,
      };
}

// ─────────────────────────────────────────────────────────────────────────

/// Resultado global de la fase de combates para un turno completo.
class ResolucionCombates {
  /// Tablero con las cartas destruidas ya eliminadas.
  final Map<String, List<Map<String, dynamic>>> tableroResultante;

  /// Lista de todos los combates resueltos (uno por celda con conflicto).
  final List<ResultadoCombate> resultados;

  /// Energies acumuladas por jugador en este turno: uid → total ganado.
  final Map<String, int> energiesPorJugador;

  /// PC acumulados por jugador en este turno: uid → total ganado.
  final Map<String, int> pcPorJugador;

  const ResolucionCombates({
    required this.tableroResultante,
    required this.resultados,
    required this.energiesPorJugador,
    required this.pcPorJugador,
  });
}

// ─────────────────────────────────────────────────────────────────────────

class CombateService {
  /// Resuelve todos los combates del tablero y devuelve el tablero resultante
  /// junto con las recompensas por jugador.
  ///
  /// [tablero] es el mapa coord → lista de cartas (cada carta es un Map que
  /// incluye 'ownerUid', 'ownerZone', 'fuerza', 'defensa', 'coste', etc.)
  static ResolucionCombates resolverCombates(
    Map<String, List<Map<String, dynamic>>> tablero,
  ) {
    final tableroResultante = <String, List<Map<String, dynamic>>>{};
    final resultados = <ResultadoCombate>[];
    final energiesPorJugador = <String, int>{};
    final pcPorJugador = <String, int>{};

    for (final entry in tablero.entries) {
      final coord = entry.key;
      final cartas = entry.value;

      // Agrupar cartas por ownerUid
      final grupos = _agruparPorJugador(cartas);

      // Sin combate → copiar tal cual
      if (grupos.length <= 1) {
        tableroResultante[coord] = cartas;
        continue;
      }

      // ── Calcular poder neto de cada grupo ────────────────────
      // poderNeto(X) = Σfuerza(X) − Σdefensa(todos los grupos enemigos de X)
      final poderNeto = <String, int>{};
      for (final uid in grupos.keys) {
        final defensaEnemigos = grupos.entries
            .where((e) => e.key != uid)
            .fold(0, (s, e) => s + e.value.totalDefensa);
        poderNeto[uid] = grupos[uid]!.totalFuerza - defensaEnemigos;
      }

      // ── Determinar ganador/es ─────────────────────────────────
      final maxPoder = poderNeto.values.reduce((a, b) => a > b ? a : b);
      final ganadoresUid = poderNeto.entries
          .where((e) => e.value == maxPoder)
          .map((e) => e.key)
          .toList();

      // ── Construir log de detalle ──────────────────────────────
      final detalle = grupos.entries.map((e) {
        return {
          'ownerUid': e.key,
          'ownerZone': e.value.ownerZone,
          'totalFuerza': e.value.totalFuerza,
          'totalDefensa': e.value.totalDefensa,
          'poderNeto': poderNeto[e.key],
          'numCartas': e.value.numCartas,
          // Lista de cartas individuales con sus stats
          'cartas': e.value.cartas
              .map((c) => {
                    'nombre': c['Nombre'] ?? c['nombre'] ?? 'Carta',
                    'fuerza': (c['Fuerza'] ?? c['fuerza'] ?? 0),
                    'defensa': (c['Defensa'] ?? c['defensa'] ?? 0),
                    'coste': (c['Coste'] ?? c['coste'] ?? 0),
                  })
              .toList(),
        };
      }).toList();

      String? ganadorUid;
      String? ganadorZone;
      List<String> derrotadosUid;
      List<Map<String, dynamic>> supervivientes;

      if (ganadoresUid.length == 1) {
        // ── Victoria clara ────────────────────────────────────
        ganadorUid = ganadoresUid.first;
        ganadorZone = grupos[ganadorUid]!.ownerZone;
        derrotadosUid = grupos.keys.where((uid) => uid != ganadorUid).toList();
        supervivientes = grupos[ganadorUid]!.cartas;

        // Recompensas: por cada grupo derrotado
        for (final derrotadoUid in derrotadosUid) {
          final grupo = grupos[derrotadoUid]!;
          final energies = grupo.totalCoste;
          final pc = 3 * grupo.numCartas;

          energiesPorJugador[ganadorUid!] =
              (energiesPorJugador[ganadorUid] ?? 0) + energies;
          pcPorJugador[ganadorUid] = (pcPorJugador[ganadorUid] ?? 0) + pc;
        }
      } else {
        // ── Empate total: todos los grupos empatados se destruyen ─
        // Los grupos con poder inferior también se destruyen.
        ganadorUid = null;
        ganadorZone = null;
        derrotadosUid = grupos.keys.toList();
        supervivientes = [];
      }

      // Actualizar tablero resultante
      if (supervivientes.isNotEmpty) {
        tableroResultante[coord] = supervivientes;
      }
      // Si no quedan supervivientes, la celda queda vacía (no se añade al mapa)

      resultados.add(ResultadoCombate(
        coord: coord,
        ganadorUid: ganadorUid,
        ganadorZone: ganadorZone,
        derrotadosUid: derrotadosUid,
        energiesGanadas: ganadorUid != null
            ? {ganadorUid: energiesPorJugador[ganadorUid] ?? 0}
            : {},
        pcGanados: ganadorUid != null
            ? {ganadorUid: pcPorJugador[ganadorUid] ?? 0}
            : {},
        cartasSupervivientes: supervivientes,
        detalle: detalle,
      ));
    }

    return ResolucionCombates(
      tableroResultante: tableroResultante,
      resultados: resultados,
      energiesPorJugador: energiesPorJugador,
      pcPorJugador: pcPorJugador,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  static Map<String, _GrupoJugador> _agruparPorJugador(
    List<Map<String, dynamic>> cartas,
  ) {
    final grupos = <String, _GrupoJugador>{};
    for (final carta in cartas) {
      final uid = carta['ownerUid'] as String? ?? '';
      final zone = carta['ownerZone'] as String? ?? '';
      if (grupos.containsKey(uid)) {
        grupos[uid]!.cartas.add(carta);
      } else {
        grupos[uid] = _GrupoJugador(
          ownerUid: uid,
          ownerZone: zone,
          cartas: [carta],
        );
      }
    }
    return grupos;
  }

  /// Texto legible del resultado (para debug o notificaciones simples).
  static String resumirResultado(ResultadoCombate r) {
    if (r.ganadorUid == null) {
      return '[${r.coord}] Empate — todas las cartas destruidas';
    }
    final energies = r.energiesGanadas[r.ganadorUid] ?? 0;
    final pc = r.pcGanados[r.ganadorUid] ?? 0;
    return '[${r.coord}] Gana ${r.ganadorZone} (+$energies Energies, +$pc PC)';
  }
}
