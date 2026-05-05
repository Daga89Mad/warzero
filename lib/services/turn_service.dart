// lib/services/turn_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lobby_model.dart';
import 'combate_service.dart';
import 'farmeo_service.dart';

// ── Movimiento serializado ────────────────────────────────────
/// Representa el estado del tablero del jugador al cerrar turno.
/// Se guarda en el campo [movimientosTurno] del documento Partidas/{id},
/// evitando subcolecciones que pueden quedar fuera de las reglas de seguridad.
class MovimientoTurno {
  final String uid;
  final int turno;
  final Map<String, List<Map<String, dynamic>>> celdas;
  final DateTime timestamp;

  const MovimientoTurno({
    required this.uid,
    required this.turno,
    required this.celdas,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'turno': turno,
        'celdas': celdas,
        'timestamp': Timestamp.fromDate(timestamp),
      };

  factory MovimientoTurno.fromMap(Map<String, dynamic> d) => MovimientoTurno(
        uid: d['uid'] as String? ?? '',
        turno: (d['turno'] as num?)?.toInt() ?? 0,
        celdas: (d['celdas'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(
            k,
            (v as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        ),
        timestamp: d['timestamp'] is Timestamp
            ? (d['timestamp'] as Timestamp).toDate()
            : DateTime.now(),
      );
}

// ─────────────────────────────────────────────────────────────
class TurnService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Stream del lobby ──────────────────────────────────────
  Stream<LobbyModel?> lobbyStream(String lobbyId) {
    return _db
        .collection('Partidas')
        .doc(lobbyId)
        .snapshots()
        .map((s) => s.exists ? LobbyModel.fromFirestore(s) : null);
  }

  // ── Cerrar turno ──────────────────────────────────────────
  /// Guarda los movimientos del jugador en el campo [movimientosTurno]
  /// del documento principal y añade el uid a [cerradoPor].
  /// Todo en un único update sobre Partidas/{id} — sin subcolecciones.
  Future<void> cerrarTurno({
    required String lobbyId,
    required String uid,
    required int turno,
    required Map<String, List<Map<String, dynamic>>> celdas,
  }) async {
    final lobbyRef = _db.collection('Partidas').doc(lobbyId);

    final movData = MovimientoTurno(
      uid: uid,
      turno: turno,
      celdas: celdas,
      timestamp: DateTime.now().toUtc(),
    ).toMap();

    // Un único update: guarda movimientos + marca cerradoPor
    // movimientosTurno.{uid} = movData  →  solo escribe la clave del jugador
    Exception? lastError;
    for (int i = 0; i < 3; i++) {
      try {
        await lobbyRef.update({
          'movimientosTurno.$uid': movData,
          'cerradoPor': FieldValue.arrayUnion([uid]),
        });
        return; // éxito
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < 2) await Future.delayed(Duration(seconds: i + 1));
      }
    }
    throw lastError!;
  }

  // ── Obtener movimientos de todos ──────────────────────────
  /// Lee el campo [movimientosTurno] del documento principal
  /// y devuelve solo los movimientos del turno actual.
  Future<List<MovimientoTurno>> getMovimientosTurno({
    required String lobbyId,
    required int turno,
  }) async {
    final snap = await _db.collection('Partidas').doc(lobbyId).get();
    if (!snap.exists) return [];

    final data = snap.data() as Map<String, dynamic>;
    final rawMov = data['movimientosTurno'] as Map<String, dynamic>? ?? {};

    final result = <MovimientoTurno>[];
    for (final entry in rawMov.entries) {
      try {
        final mov = MovimientoTurno.fromMap(
            Map<String, dynamic>.from(entry.value as Map));
        // Filtrar por turno actual para ignorar datos de turnos anteriores
        if (mov.turno == turno) result.add(mov);
      } catch (_) {}
    }
    return result;
  }

  // ── Resolver combates, farmeo y avanzar turno ─────────────
  /// Resuelve combates + farmeo de posición + rayo, persiste en Firestore
  /// y retorna la resolución de combates.
  ///
  /// Parámetros de farmeo (opcionales — si no se pasan, el farmeo se omite):
  ///   [obeliscosPorJugador]  uid → coord del obelisco asignado.
  ///   [continentes]          obeliscoCoord → lista de celdas del continente.
  ///   [islaCentral]          Lista de coords de la isla central.
  ///   [rayoActual]           Estado del rayo en BD: {coord, turnosRestantes}.
  ///   [todasLasCeldas]       Todas las coords válidas del tablero.
  Future<ResolucionCombates> resolverCombatesYAvanzar({
    required String lobbyId,
    required int turnoActual,
    required Map<String, List<Map<String, dynamic>>> tablero,
    required Map<String, Map<String, int>> statsActuales,
    List<Map<String, dynamic>>? movimientosLog,
    // ── Farmeo ────────────────────────────────────────────────
    Map<String, String>? obeliscosPorJugador,
    Map<String, List<String>>? continentes,
    List<String>? islaCentral,
    Map<String, dynamic>? rayoActual,
    List<String>? todasLasCeldas,
  }) async {
    // 1. Resolver combates (puro CPU, sin red)
    final resolucion = CombateService.resolverCombates(tablero);

    // 2. Calcular farmeo (sobre el tablero RESULTANTE tras combates)
    FarmeoResultado? farmeoResultado;
    final farmeoActivo =
        continentes != null && islaCentral != null && todasLasCeldas != null;
    if (farmeoActivo) {
      farmeoResultado = FarmeoService.calcularFarmeo(
        tablero: resolucion.tableroResultante,
        obeliscosPorJugador: obeliscosPorJugador ?? {},
        continentes: continentes!,
        islaCentral: islaCentral!,
        rayoActual: rayoActual,
        todasLasCeldas: todasLasCeldas!,
      );
    }

    // 3. Acumular stats (combate + farmeo)
    final statsActualizadas = <String, Map<String, dynamic>>{};
    for (final entry in statsActuales.entries) {
      statsActualizadas[entry.key] = Map<String, dynamic>.from(entry.value);
    }

    // Energies de COMBATE
    resolucion.energiesPorJugador.forEach((uid, energiesC) {
      statsActualizadas.putIfAbsent(uid, () => {'energies': 0, 'pc': 0});
      statsActualizadas[uid]!['energies'] =
          ((statsActualizadas[uid]!['energies'] as int?) ?? 0) + energiesC;
    });
    resolucion.pcPorJugador.forEach((uid, pc) {
      statsActualizadas.putIfAbsent(uid, () => {'energies': 0, 'pc': 0});
      statsActualizadas[uid]!['pc'] =
          ((statsActualizadas[uid]!['pc'] as int?) ?? 0) + pc;
    });

    // Energies de FARMEO
    farmeoResultado?.energiesPorJugador.forEach((uid, energiesF) {
      statsActualizadas.putIfAbsent(uid, () => {'energies': 0, 'pc': 0});
      statsActualizadas[uid]!['energies'] =
          ((statsActualizadas[uid]!['energies'] as int?) ?? 0) + energiesF;
    });

    // 4. Construir log de combates y entrada de historial
    final combateLog = resolucion.resultados.map((r) => r.toLogMap()).toList();
    final entradaHistorial = <String, dynamic>{
      'turno': turnoActual,
      'combateLog': combateLog,
      'movimientosLog': movimientosLog ?? [],
      // Farmeo del turno
      'farmeoLog': farmeoResultado?.farmeoLog ?? [],
      'rayoCoord': farmeoResultado?.nuevoRayo?['coord'],
      'rayoTurnosRestantes': farmeoResultado?.nuevoRayo?['turnosRestantes'],
    };

    // 5. Transacción: solo escribe si el turno no ha avanzado ya
    final lobbyRef = _db.collection('Partidas').doc(lobbyId);
    final updateData = <String, dynamic>{
      'turnoActual': turnoActual + 1,
      'cerradoPor': [],
      'movimientosTurno': {},
      'tablero': resolucion.tableroResultante,
      'statsPartida': statsActualizadas,
      'ultimoCombateLog': combateLog,
      'ultimoFarmeoLog': farmeoResultado?.farmeoLog ?? [],
      if (movimientosLog != null) 'ultimosMovimientos': movimientosLog,
      // Rayo persistido para el próximo turno
      if (farmeoActivo)
        'rayo': farmeoResultado?.nuevoRayo ?? FieldValue.delete(),
    };

    await _db.runTransaction((tx) async {
      final snap = await tx.get(lobbyRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final turnoEnDB = (data['turnoActual'] as num?)?.toInt() ?? 0;
      if (turnoEnDB != turnoActual) return; // ya resuelto por otro jugador

      // Leer historial actual y mantener solo los últimos 3 turnos
      final existingHistorial =
          List<dynamic>.from((data['historialCombates'] as List?) ?? []);
      existingHistorial.add(entradaHistorial);
      if (existingHistorial.length > 3) {
        existingHistorial.removeRange(0, existingHistorial.length - 3);
      }
      final finalData = Map<String, dynamic>.from(updateData);
      finalData['historialCombates'] = existingHistorial;
      tx.update(lobbyRef, finalData);
    });

    return resolucion;
  }

  // ── Avanzar turno sin combate (fallback) ─────────────────
  Future<void> avanzarTurno({
    required String lobbyId,
    required int turnoActual,
    required Map<String, dynamic> tablero,
  }) async {
    await _db.collection('Partidas').doc(lobbyId).update({
      'turnoActual': turnoActual + 1,
      'cerradoPor': [],
      'movimientosTurno': {},
      'tablero': tablero,
    });
  }

  // ── Parsear tablero del doc ───────────────────────────────
  static Map<String, List<Map<String, dynamic>>> parseTablero(
      Map<String, dynamic> data) {
    final raw = data['tablero'] as Map<String, dynamic>? ?? {};
    return raw.map((coord, celdaRaw) {
      final cartas = (celdaRaw as List<dynamic>)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
      return MapEntry(coord, cartas);
    });
  }

  // ── Cierre diario ─────────────────────────────────────────
  static DateTime proximoCierreUTC() {
    final now = DateTime.now().toUtc();
    var target = DateTime.utc(now.year, now.month, now.day, 12);
    if (now.isAfter(target)) target = target.add(const Duration(days: 1));
    return target;
  }

  static String formatDuracionHastaCierre() {
    final diff = proximoCierreUTC().difference(DateTime.now().toUtc());
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  static String horaUTCActual() {
    final now = DateTime.now().toUtc();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')} UTC';
  }
}
