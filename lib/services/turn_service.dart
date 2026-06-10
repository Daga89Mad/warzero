// lib/services/turn_service.dart
//
// Cierre de turno migrado a la API (Fenrir / WarZero).
//
// A partir de esta versión el cliente NO resuelve el turno: solo sube sus
// movimientos + acciones al endpoint `POST /warzero/turno/cerrar`. El servidor,
// dentro de una transacción Firestore, registra el cierre y —cuando han cerrado
// todos los jugadores activos— AUTO-RESUELVE el turno completo
// (habilidades → combate → tick de efectos → farmeo → stats → historial →
// avance de turno → eliminaciones / fin de partida).
//
// El cliente se entera del resultado escuchando `lobbyStream`: cuando el doc
// del lobby cambia (turno avanzado, tablero nuevo, etc.) la UI se reconstruye.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/accion_pendiente.dart';
import '../models/board_state.dart';
import '../models/efecto_estado.dart';
import '../models/lobby_model.dart';
import 'combate_service.dart';
import 'warzero_api.dart';

// ── Movimiento serializado ────────────────────────────────────
class MovimientoTurno {
  final String uid;
  final int turno;
  final Map<String, List<Map<String, dynamic>>> celdas;
  final DateTime timestamp;

  /// Acciones declaradas por el jugador durante este turno (carta de acción
  /// o habilidad de carta). Se resuelven en el servidor al cerrar el turno.
  final List<AccionPendiente> acciones;

  const MovimientoTurno({
    required this.uid,
    required this.turno,
    required this.celdas,
    required this.timestamp,
    this.acciones = const [],
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'turno': turno,
        'celdas': celdas,
        'timestamp': Timestamp.fromDate(timestamp),
        if (acciones.isNotEmpty)
          'acciones': acciones.map((a) => a.toMap()).toList(),
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
        acciones: ((d['acciones'] as List?) ?? [])
            .map((m) =>
                AccionPendiente.fromMap(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────
class TurnService {
  TurnService({WarZeroApi? api}) : _api = api ?? WarZeroApi();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final WarZeroApi _api;

  /// Resultado de la última llamada a [cerrarTurno] (útil para la UI:
  /// saber si esta llamada resolvió el turno, si la partida terminó, etc.).
  CerrarTurnoResult? ultimoCierre;

  // ── Stream del lobby ──────────────────────────────────────
  Stream<LobbyModel?> lobbyStream(String lobbyId) {
    return _db
        .collection('Partidas')
        .doc(lobbyId)
        .snapshots()
        .map((s) => s.exists ? LobbyModel.fromFirestore(s) : null);
  }

  // ── Cerrar turno (vía API) ────────────────────────────────
  /// Sube los movimientos y las acciones del jugador a la API. El servidor
  /// marca el cierre y resuelve el turno automáticamente cuando han cerrado
  /// todos los jugadores activos.
  ///
  /// Mantiene la misma firma que la versión anterior para no romper a los
  /// llamadores; el resultado detallado queda en [ultimoCierre].
  Future<void> cerrarTurno({
    required String lobbyId,
    required String uid,
    required int turno,
    required Map<String, List<Map<String, dynamic>>> celdas,
    List<AccionPendiente> acciones = const [],
  }) async {
    Exception? lastError;
    for (int i = 0; i < 3; i++) {
      try {
        ultimoCierre = await _api.cerrarTurno(
          lobbyId: lobbyId,
          uid: uid,
          turno: turno,
          celdas: celdas,
          acciones: acciones,
        );
        return;
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < 2) await Future.delayed(Duration(seconds: i + 1));
      }
    }
    throw lastError!;
  }

  // ── Obtener movimientos de todos (lectura auxiliar) ───────
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
        if (mov.turno == turno) result.add(mov);
      } catch (_) {}
    }
    return result;
  }

  // ── Resolución de turno (DEPRECATED) ──────────────────────
  /// La resolución del turno ahora ocurre EN EL SERVIDOR durante el cierre.
  /// Este método se conserva como no-op para no romper código antiguo: ya no
  /// lee, calcula ni escribe nada. Devuelve una resolución vacía.
  ///
  /// El cliente debe limitarse a escuchar [lobbyStream] y reaccionar a los
  /// cambios del lobby (turno avanzado, tablero nuevo, etc.).
  @Deprecated(
      'La resolución del turno la hace el servidor en cerrarTurno. Escucha lobbyStream.')
  Future<ResolucionCombates> resolverCombatesYAvanzar({
    required String lobbyId,
    required int turnoActual,
    required Map<String, List<Map<String, dynamic>>> tablero,
    required Map<String, Map<String, int>> statsActuales,
    List<Map<String, dynamic>>? movimientosLog,
    Map<String, String>? obeliscosPorJugador,
    List<AccionPendiente> acciones = const [],
    Map<String, List<EfectoActivo>> efectosCeldaActual = const {},
    Map<String, List<String>>? continentes,
    List<String>? islaCentral,
    Map<String, dynamic>? rayoActual,
    List<String>? todasLasCeldas,
  }) async {
    return ResolucionCombates(
      tableroResultante: tablero,
      resultados: const [],
      energiesPorJugador: const {},
      pcPorJugador: const {},
      obeliscosConquistados: const [],
    );
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

  /// Parsea el campo `efectosCelda` del doc del lobby.
  static Map<String, List<EfectoActivo>> parseEfectosCelda(
          Map<String, dynamic> data) =>
      BoardState.efectosCeldaFromFirestore(
        data['efectosCelda'] as Map<String, dynamic>?,
      );

  /// Parsea el campo `acciones` flat de todos los movimientos de un turno.
  static List<AccionPendiente> parseAccionesDeMovimientos(
    Map<String, dynamic> data,
    int turno,
  ) {
    final rawMov = data['movimientosTurno'] as Map<String, dynamic>? ?? {};
    final result = <AccionPendiente>[];
    for (final entry in rawMov.entries) {
      try {
        final mov = MovimientoTurno.fromMap(
            Map<String, dynamic>.from(entry.value as Map));
        if (mov.turno == turno) result.addAll(mov.acciones);
      } catch (_) {}
    }
    return result;
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
