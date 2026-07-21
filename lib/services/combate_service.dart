// lib/services/combate_service.dart

/// ─────────────────────────────────────────────────────────────────────────
/// Sistema de combate de WarZero
///
/// REGLAS NORMALES:
///   Al final de cada turno se comprueba si hay cartas de distintos jugadores
///   en la misma celda.
///   • poderNeto(X) = Σfuerza(X) − Σdefensa(todos los enemigos de X)
///   • El grupo con mayor poderNeto gana.
///   • Las cartas de los grupos perdedores se destruyen.
///   • En empate exacto → no se resuelve
///
/// REGLA CUARTEL GENERAL (OBELISCO):
///   Si se produce combate en la celda obelisco de un jugador, ese jugador
///   recibe una defensa extra de 80 puntos (la fortaleza del cuartel).
///   Si el defensor pierde → conquista: el atacante gana +100 Zero y
///   +100 PC, y el defensor queda ELIMINADO de la partida.
///   Si no hay cartas defensoras pero sí atacantes, se compara la fuerza
///   atacante contra 80 (defensa base del cuartel vacío).
///
/// EFECTOS PERSISTENTES (VENENO):
///   Cada carta puede llevar en su Map un campo `Efectos: [...]` con efectos
///   activos. La defensa efectiva de una carta es:
///       defensaEfectiva = max(0, Defensa - Σ veneno.magnitud)
///   considerando solo efectos con turnosRestantes > 0. La defensa que se
///   usa en `totalDefensa` (y en la fórmula del combate) es la efectiva.
///
/// RECOMPENSAS NORMALES (por grupo derrotado):
///   • Zero += Σcoste de las cartas destruidas del grupo derrotado.
///   • PC       += 3 × número de cartas destruidas del grupo derrotado.
/// ─────────────────────────────────────────────────────────────────────────

/// Calcula la reducción de defensa que sufre una carta por sus efectos
/// activos (suma de magnitudes de los venenos con turnosRestantes > 0).
///
/// Se mantiene como función top-level y no depende del servicio de
/// habilidades para evitar acoplamiento circular: `combate_service` no
/// importa `habilidad_service`.
int _defensaReducidaPorEfectos(Map<String, dynamic> carta) {
  final raw = carta['Efectos'] as List?;
  if (raw == null) return 0;
  int total = 0;
  for (final m in raw) {
    final mm = Map<String, dynamic>.from(m as Map);
    final turnos = (mm['turnosRestantes'] as num?)?.toInt() ?? 0;
    if (turnos <= 0) continue;
    final tipo = mm['tipo'] as String?;
    // Solo el veneno reduce defensa por ahora. Si en el futuro hay más
    // efectos que la reduzcan, basta con añadirlos aquí.
    if (tipo == 'veneno') {
      total += (mm['magnitud'] as num?)?.toInt() ?? 0;
    }
  }
  return total;
}

/// Defensa efectiva de una sola carta (no negativa).
int _defensaEfectivaDeCarta(Map<String, dynamic> c) {
  final base = ((c['Defensa'] ?? c['defensa'] as num? ?? 0) as num).toInt();
  final reducida = _defensaReducidaPorEfectos(c);
  final efectiva = base - reducida;
  return efectiva > 0 ? efectiva : 0;
}

/// Resultado de la conquista de un cuartel general.
class ObeliscoConquista {
  final String coord;
  final String conquistadorUid;
  final String perdedorUid;

  const ObeliscoConquista({
    required this.coord,
    required this.conquistadorUid,
    required this.perdedorUid,
  });

  Map<String, dynamic> toLogMap() => {
        'coord': coord,
        'conquistadorUid': conquistadorUid,
        'perdedorUid': perdedorUid,
        'tipo': 'conquista_cuartel',
      };
}

// ─────────────────────────────────────────────────────────────────────────
class _GrupoJugador {
  final String ownerUid;
  final String ownerZone;
  final List<Map<String, dynamic>> cartas;

  /// Defensa adicional (solo usada en obeliscos).
  final int defensaBonus;

  _GrupoJugador({
    required this.ownerUid,
    required this.ownerZone,
    required this.cartas,
    this.defensaBonus = 0,
  });

  int get totalFuerza => cartas.fold(0,
      (s, c) => s + ((c['Fuerza'] ?? c['fuerza'] as num? ?? 0) as num).toInt());

  /// Defensa total efectiva: suma defensa efectiva por carta (base − venenos)
  /// y añade el bonus de obelisco si aplica.
  int get totalDefensa {
    int suma = 0;
    for (final c in cartas) {
      suma += _defensaEfectivaDeCarta(c);
    }
    return suma + defensaBonus;
  }

  /// Defensa total base, sin restar efectos. Útil para logs y depuración.
  int get totalDefensaBase {
    int suma = 0;
    for (final c in cartas) {
      suma += ((c['Defensa'] ?? c['defensa'] as num? ?? 0) as num).toInt();
    }
    return suma + defensaBonus;
  }

  /// Suma de la reducción por venenos en este grupo.
  int get totalReduccionVeneno =>
      cartas.fold(0, (s, c) => s + _defensaReducidaPorEfectos(c));

  int get totalCoste => cartas.fold(0,
      (s, c) => s + ((c['Coste'] ?? c['coste'] as num? ?? 0) as num).toInt());

  int get numCartas => cartas.length;
}

// ─────────────────────────────────────────────────────────────────────────

/// Resultado del combate en una celda concreta.
class ResultadoCombate {
  final String coord;
  final String? ganadorUid;
  final String? ganadorZone;
  final List<String> derrotadosUid;
  final Map<String, int> energiesGanadas;
  final Map<String, int> pcGanados;
  final List<Map<String, dynamic>> cartasSupervivientes;
  final List<Map<String, dynamic>> detalle;

  /// True si este combate resultó en la conquista de un cuartel general.
  final bool esConquistaObelisco;

  const ResultadoCombate({
    required this.coord,
    required this.ganadorUid,
    required this.ganadorZone,
    required this.derrotadosUid,
    required this.energiesGanadas,
    required this.pcGanados,
    required this.cartasSupervivientes,
    required this.detalle,
    this.esConquistaObelisco = false,
  });

  Map<String, dynamic> toLogMap() => {
        'coord': coord,
        'ganadorUid': ganadorUid,
        'ganadorZone': ganadorZone,
        'derrotadosUid': derrotadosUid,
        'energiesGanadas': energiesGanadas,
        'pcGanados': pcGanados,
        'detalle': detalle,
        'esConquistaObelisco': esConquistaObelisco,
      };
}

// ─────────────────────────────────────────────────────────────────────────

/// Resultado global de la fase de combates para un turno completo.
class ResolucionCombates {
  final Map<String, List<Map<String, dynamic>>> tableroResultante;
  final List<ResultadoCombate> resultados;
  final Map<String, int> energiesPorJugador;
  final Map<String, int> pcPorJugador;

  /// Lista de conquistas de cuarteles generales ocurridas en este turno.
  final List<ObeliscoConquista> obeliscosConquistados;

  const ResolucionCombates({
    required this.tableroResultante,
    required this.resultados,
    required this.energiesPorJugador,
    required this.pcPorJugador,
    this.obeliscosConquistados = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────

class CombateService {
  /// Defensa base del cuartel general (obelisco).
  static const int defensaObelisco = 40;

  /// Bonificación de Zero por conquistar un cuartel.
  static const int energiesConquista = 100;

  /// Bonificación de PC por conquistar un cuartel.
  static const int pcConquista = 100;

  /// Resuelve todos los combates del tablero y devuelve el tablero resultante
  /// junto con las recompensas por jugador.
  ///
  /// [tablero]             coord → lista de cartas (PascalCase o snake_case).
  ///                       Cada carta puede llevar un campo 'Efectos' (lista
  ///                       de efectos activos) que se consulta para calcular
  ///                       defensa efectiva por veneno.
  /// [obeliscosPorJugador] uid → coord del cuartel de ese jugador.
  ///                        Si se pasa, los combates en cuarteles aplican
  ///                        la defensa extra de [defensaObelisco].
  static ResolucionCombates resolverCombates(
    Map<String, List<Map<String, dynamic>>> tablero, {
    Map<String, String>? obeliscosPorJugador,
  }) {
    // Invertir: coord → uid propietario del obelisco en esa coord.
    final obeliscoOwnerByCoord = <String, String>{};
    if (obeliscosPorJugador != null) {
      obeliscosPorJugador.forEach((uid, coord) {
        obeliscoOwnerByCoord[coord] = uid;
      });
    }

    final tableroResultante = <String, List<Map<String, dynamic>>>{};
    final resultados = <ResultadoCombate>[];
    final energiesPorJugador = <String, int>{};
    final pcPorJugador = <String, int>{};
    final conquistas = <ObeliscoConquista>[];

    // ── Celdas que son cuarteles pero aparecen vacías (sin cartas atacantes) ──
    // Solo procesar celdas que tengan cartas.
    final coordsAProcesar = {
      ...tablero.keys,
      // También incluir coords de obeliscos vacíos que tengan atacantes →
      // ya cubiertos por tablero.keys si los atacantes movieron ahí.
    };

    for (final coord in coordsAProcesar) {
      final cartas = tablero[coord] ?? [];
      if (cartas.isEmpty) continue;

      final esObeliscoCoord = obeliscoOwnerByCoord.containsKey(coord);
      final obeliscoPropietarioUid =
          esObeliscoCoord ? obeliscoOwnerByCoord[coord]! : null;

      // Agrupar cartas por propietario.
      final grupos = _agruparPorJugador(cartas);

      // ── Caso especial: obelisco sin defensor (solo atacantes) ─────────────
      if (esObeliscoCoord &&
          obeliscoPropietarioUid != null &&
          !grupos.containsKey(obeliscoPropietarioUid)) {
        // Solo hay cartas enemigas en el cuartel.
        // La conquista ocurre si la fuerza total del atacante > 80.
        // Puede haber más de un atacante (se toman todos como aliados vs el cuartel).
        final fuerzaTotal = grupos.values.fold(0, (s, g) => s + g.totalFuerza);
        if (fuerzaTotal > defensaObelisco) {
          // Conquista: el obelisco no tiene cartas que soporten.
          // ¿Quién conquista? Si hay un solo atacante es claro.
          // Con varios, el que más fuerza tiene lleva el logro.
          final conquistadorUid = grupos.entries
              .reduce(
                  (a, b) => a.value.totalFuerza >= b.value.totalFuerza ? a : b)
              .key;
          conquistas.add(ObeliscoConquista(
            coord: coord,
            conquistadorUid: conquistadorUid,
            perdedorUid: obeliscoPropietarioUid,
          ));
          energiesPorJugador[conquistadorUid] =
              (energiesPorJugador[conquistadorUid] ?? 0) + energiesConquista;
          pcPorJugador[conquistadorUid] =
              (pcPorJugador[conquistadorUid] ?? 0) + pcConquista;

          // Las cartas atacantes permanecen en la celda.
          tableroResultante[coord] = cartas;
          resultados.add(ResultadoCombate(
            coord: coord,
            ganadorUid: conquistadorUid,
            ganadorZone: grupos[conquistadorUid]!.ownerZone,
            derrotadosUid: [obeliscoPropietarioUid],
            energiesGanadas: {conquistadorUid: energiesConquista},
            pcGanados: {conquistadorUid: pcConquista},
            cartasSupervivientes: cartas,
            detalle: [],
            esConquistaObelisco: true,
          ));
        } else {
          // Fuerza insuficiente para conquistar: cartas permanecen (no hay combate real).
          tableroResultante[coord] = cartas;
        }
        continue;
      }

      // ── Sin combate (1 solo propietario) ─────────────────────────────────
      if (grupos.length <= 1) {
        tableroResultante[coord] = cartas;
        continue;
      }

      // ── Combate: varios propietarios en la misma celda ───────────────────
      // Si es un obelisco, el propietario recibe +80 de defensa.
      if (esObeliscoCoord && obeliscoPropietarioUid != null) {
        if (grupos.containsKey(obeliscoPropietarioUid)) {
          final g = grupos[obeliscoPropietarioUid]!;
          grupos[obeliscoPropietarioUid] = _GrupoJugador(
            ownerUid: g.ownerUid,
            ownerZone: g.ownerZone,
            cartas: g.cartas,
            defensaBonus: defensaObelisco,
          );
        }
      }

      // ── Calcular poder neto ───────────────────────────────────────────────
      final poderNeto = <String, int>{};
      for (final uid in grupos.keys) {
        final defensaEnemigos = grupos.entries
            .where((e) => e.key != uid)
            .fold(0, (s, e) => s + e.value.totalDefensa);
        poderNeto[uid] = grupos[uid]!.totalFuerza - defensaEnemigos;
      }

      // ── Determinar ganador/es ─────────────────────────────────────────────
      final maxPoder = poderNeto.values.reduce((a, b) => a > b ? a : b);
      final ganadoresUid = poderNeto.entries
          .where((e) => e.value == maxPoder)
          .map((e) => e.key)
          .toList();

      // ── Log de detalle ────────────────────────────────────────────────────
      final detalle = grupos.entries.map((e) {
        return {
          'ownerUid': e.key,
          'ownerZone': e.value.ownerZone,
          'totalFuerza': e.value.totalFuerza,
          'totalDefensa': e.value.totalDefensa,
          'totalDefensaBase': e.value.totalDefensaBase,
          'reduccionVeneno': e.value.totalReduccionVeneno,
          'defensaBonus': e.value.defensaBonus,
          'poderNeto': poderNeto[e.key],
          'numCartas': e.value.numCartas,
          'cartas': e.value.cartas.map((c) {
            final base =
                ((c['Defensa'] ?? c['defensa'] as num? ?? 0) as num).toInt();
            final reducida = _defensaReducidaPorEfectos(c);
            return {
              'nombre': c['Nombre'] ?? c['nombre'] ?? 'Carta',
              'fuerza': (c['Fuerza'] ?? c['fuerza'] ?? 0),
              'defensa': base,
              'defensaEfectiva': base - reducida > 0 ? base - reducida : 0,
              'reduccionVeneno': reducida,
              'coste': (c['Coste'] ?? c['coste'] ?? 0),
            };
          }).toList(),
        };
      }).toList();

      String? ganadorUid;
      String? ganadorZone;
      List<String> derrotadosUid;
      List<Map<String, dynamic>> supervivientes;
      bool esConquista = false;

      if (ganadoresUid.length == 1) {
        ganadorUid = ganadoresUid.first;
        ganadorZone = grupos[ganadorUid]!.ownerZone;
        derrotadosUid = grupos.keys.where((uid) => uid != ganadorUid).toList();
        supervivientes = grupos[ganadorUid]!.cartas;

        // Recompensas normales por grupos derrotados.
        for (final derrotadoUid in derrotadosUid) {
          final grupo = grupos[derrotadoUid]!;
          final energies = grupo.totalCoste;
          final pc = 3 * grupo.numCartas;
          energiesPorJugador[ganadorUid!] =
              (energiesPorJugador[ganadorUid] ?? 0) + energies;
          pcPorJugador[ganadorUid] = (pcPorJugador[ganadorUid] ?? 0) + pc;
        }

        // ── Conquista de cuartel ──────────────────────────────────────────
        if (esObeliscoCoord &&
            obeliscoPropietarioUid != null &&
            derrotadosUid.contains(obeliscoPropietarioUid)) {
          esConquista = true;
          conquistas.add(ObeliscoConquista(
            coord: coord,
            conquistadorUid: ganadorUid!,
            perdedorUid: obeliscoPropietarioUid,
          ));
          // Recompensas adicionales por conquista.
          energiesPorJugador[ganadorUid] =
              (energiesPorJugador[ganadorUid] ?? 0) + energiesConquista;
          pcPorJugador[ganadorUid] =
              (pcPorJugador[ganadorUid] ?? 0) + pcConquista;
        }
      } else {
        // Empate EN CABEZA: solo permanecen los grupos empatados al máximo
        // poderNeto (standoff). Los de menos poder (perdedores claros) caen.
        ganadorUid = null;
        ganadorZone = null;
        final empatados = ganadoresUid.toSet();
        derrotadosUid =
            grupos.keys.where((uid) => !empatados.contains(uid)).toList();
        supervivientes = grupos.entries
            .where((e) => empatados.contains(e.key))
            .expand((e) => e.value.cartas)
            .toList();
      }

      if (supervivientes.isNotEmpty) {
        tableroResultante[coord] = supervivientes;
      }

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
        esConquistaObelisco: esConquista,
      ));
    }

    return ResolucionCombates(
      tableroResultante: tableroResultante,
      resultados: resultados,
      energiesPorJugador: energiesPorJugador,
      pcPorJugador: pcPorJugador,
      obeliscosConquistados: conquistas,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

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

  static String resumirResultado(ResultadoCombate r) {
    if (r.esConquistaObelisco) {
      return '[${r.coord}] 🏰 CUARTEL CONQUISTADO por ${r.ganadorZone} '
          '(+$energiesConquista Zero, +$pcConquista PC)';
    }
    if (r.ganadorUid == null) {
      return '[${r.coord}] Empate — las cartas se mantienen hasta el desempate';
    }
    final energies = r.energiesGanadas[r.ganadorUid] ?? 0;
    final pc = r.pcGanados[r.ganadorUid] ?? 0;
    return '[${r.coord}] Gana ${r.ganadorZone} (+$energies Zero, +$pc PC)';
  }
}
