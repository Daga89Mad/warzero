// lib/services/farmeo_service.dart

import 'dart:math';

/// ─────────────────────────────────────────────────────────────────────────────
/// FarmeoService — Calcula las energies de farmeo al resolver cada turno.
///
/// REGLAS:
///   1. Carta en continente ENEMIGO → +5 Energies por carta.
///   2. Carta en isla CENTRAL       → +7 Energies por carta.
///   3. Carta en posición del RAYO  → +10 Energies por carta (en esa celda).
///
/// RAYO:
///   - Al resolver el turno se elige una celda vacía aleatoria (sin cartas ni
///     obelisco) donde aparece un rayo que permanece 3 turnos.
///   - Si ya hay un rayo activo, se decrementa su contador. Si llega a 0 se
///     sustituye por uno nuevo en otra celda vacía.
///   - Las energies del rayo se calculan ANTES de decrementar el contador,
///     es decir, el jugador cobra si estaba en la celda cuando se resolvió.
///
/// CONTINENTES (configurable en BD por mapa):
///   El campo `continentes` es un mapa { obeliscoCoord → [lista de celdas] }.
///   Se carga desde la colección Mapas/{id} en Firestore.
/// ─────────────────────────────────────────────────────────────────────────────

/// Resultado del cálculo de farmeo para un turno.
class FarmeoResultado {
  /// Energies ganadas por farmeo: uid → cantidad total.
  final Map<String, int> energiesPorJugador;

  /// Detalle por jugador para mostrar en el Informe de Batalla.
  /// Cada entrada: { uid, zona, totalEnergies, detalle: {continenteEnemigo, islaCentral, rayo} }
  final List<Map<String, dynamic>> farmeoLog;

  /// Estado del rayo TRAS resolver el turno (null si no hay celdas vacías disponibles).
  final Map<String, dynamic>? nuevoRayo;

  const FarmeoResultado({
    required this.energiesPorJugador,
    required this.farmeoLog,
    required this.nuevoRayo,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class FarmeoService {
  /// Calcula las energies de farmeo y actualiza el rayo.
  ///
  /// [tablero]              Tablero RESULTANTE tras combates: coord → cartas.
  /// [obeliscosPorJugador]  uid → coordenada del obelisco del jugador.
  /// [continentes]          obeliscoCoord → lista de coords del continente.
  ///                        Si un obelisco no tiene propietario asignado aún,
  ///                        ese continente no genera farmeo enemigo.
  /// [islaCentral]          Lista de coords de la isla central.
  /// [rayoActual]           Estado actual del rayo: {coord, turnosRestantes} o null.
  /// [todasLasCeldas]       Todas las coords válidas del tablero (para colocar rayo).
  /// [random]               Semilla opcional para tests deterministas.
  static FarmeoResultado calcularFarmeo({
    required Map<String, List<Map<String, dynamic>>> tablero,
    required Map<String, String> obeliscosPorJugador,
    required Map<String, List<String>> continentes,
    required List<String> islaCentral,
    required Map<String, dynamic>? rayoActual,
    required List<String> todasLasCeldas,
    Random? random,
  }) {
    final rng = random ?? Random();

    // Invertir: obeliscoCoord → uid propietario
    final propietarioDeObelisco = <String, String>{};
    obeliscosPorJugador.forEach((uid, coord) {
      propietarioDeObelisco[coord] = uid;
    });

    // Coord del rayo activo (ANTES de decrementarlo)
    final rayoCoord = rayoActual?['coord'] as String?;

    // ─── 1. Acumular energies por celda ──────────────────────────────────────
    final energies = <String, int>{};
    final detalleMap = <String,
        Map<String, int>>{}; // uid → {continenteEnemigo, islaCentral, rayo}
    final zonaMap = <String, String>{};

    tablero.forEach((coord, cartas) {
      for (final carta in cartas) {
        final uid = carta['ownerUid'] as String? ?? '';
        final zona = carta['ownerZone'] as String? ?? '';
        if (uid.isEmpty) continue;

        zonaMap[uid] = zona;
        detalleMap.putIfAbsent(
            uid,
            () => {
                  'continenteEnemigo': 0,
                  'islaCentral': 0,
                  'rayo': 0,
                });

        // BUG QAS #1: una carta sobre CUALQUIER celda de cuartel/obelisco no
        // farmea nada (ni continente, ni isla central, ni rayo). El cuartel es
        // una base, no una zona de extracción. (Paridad con WarZeroLogic.cs.)
        if (propietarioDeObelisco.containsKey(coord)) continue;

        // ¿Carta en continente ENEMIGO?
        for (final entry in continentes.entries) {
          final obeliscoCoord = entry.key;
          final positions = entry.value;
          if (!positions.contains(coord)) continue;

          final propietarioUid = propietarioDeObelisco[obeliscoCoord];
          // Solo cuenta si el continente tiene propietario y es diferente al portador de la carta
          if (propietarioUid != null &&
              propietarioUid.isNotEmpty &&
              propietarioUid != uid) {
            energies[uid] = (energies[uid] ?? 0) + 5;
            detalleMap[uid]!['continenteEnemigo'] =
                (detalleMap[uid]!['continenteEnemigo'] ?? 0) + 5;
          }
        }

        // ¿Carta en isla CENTRAL?
        if (islaCentral.contains(coord)) {
          energies[uid] = (energies[uid] ?? 0) + 7;
          detalleMap[uid]!['islaCentral'] =
              (detalleMap[uid]!['islaCentral'] ?? 0) + 7;
        }

        // ¿Carta en celda del RAYO?
        if (rayoCoord != null && coord == rayoCoord) {
          energies[uid] = (energies[uid] ?? 0) + 10;
          detalleMap[uid]!['rayo'] = (detalleMap[uid]!['rayo'] ?? 0) + 10;
        }
      }
    });

    // ─── 2. Construir farmeoLog ───────────────────────────────────────────────
    final farmeoLog = detalleMap.entries
        .where((e) => (energies[e.key] ?? 0) > 0)
        .map((e) => <String, dynamic>{
              'uid': e.key,
              'zona': zonaMap[e.key] ?? '',
              'totalEnergies': energies[e.key] ?? 0,
              'detalle': Map<String, dynamic>.from(e.value),
            })
        .toList();

    // ─── 3. Actualizar rayo ───────────────────────────────────────────────────
    Map<String, dynamic>? nuevoRayo;

    if (rayoActual != null) {
      final turnosRestantes =
          ((rayoActual['turnosRestantes'] as num?)?.toInt() ?? 0) - 1;
      if (turnosRestantes > 0) {
        // El rayo sigue en la misma celda con un turno menos
        nuevoRayo = {
          'coord': rayoActual['coord'],
          'turnosRestantes': turnosRestantes,
        };
      }
      // Si turnosRestantes <= 0, el rayo expira y colocaremos uno nuevo
    }

    // Si no hay rayo activo (o acaba de expirar), colocar uno nuevo en celda vacía
    if (nuevoRayo == null) {
      final celdaConCartas = tablero.keys.toSet();
      final obeliscos = obeliscosPorJugador.values.toSet();

      final celdasDisponibles = todasLasCeldas
          .where((c) =>
              !celdaConCartas.contains(c) && // sin cartas
              !obeliscos.contains(c)) // no es obelisco
          .toList();

      if (celdasDisponibles.isNotEmpty) {
        celdasDisponibles.shuffle(rng);
        nuevoRayo = {
          'coord': celdasDisponibles.first,
          'turnosRestantes': 3,
        };
      }
    }

    return FarmeoResultado(
      energiesPorJugador: energies,
      farmeoLog: farmeoLog,
      nuevoRayo: nuevoRayo,
    );
  }
}
