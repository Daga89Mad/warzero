// lib/services/turn_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/debug_log.dart';
import '../models/accion_pendiente.dart';
import '../models/board_state.dart';
import '../models/efecto_estado.dart';
import '../models/lobby_model.dart';
import 'combate_service.dart';
import 'farmeo_service.dart';
import 'habilidad_service.dart';

// ── Movimiento serializado ────────────────────────────────────
class MovimientoTurno {
  final String uid;
  final int turno;
  final Map<String, List<Map<String, dynamic>>> celdas;
  final DateTime timestamp;

  /// Acciones declaradas por el jugador durante este turno (carta de acción
  /// o habilidad de carta). Se resuelven al cerrar el turno.
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
  /// Sube los movimientos y las acciones declaradas por el jugador, y marca
  /// que ha cerrado el turno.
  Future<void> cerrarTurno({
    required String lobbyId,
    required String uid,
    required int turno,
    required Map<String, List<Map<String, dynamic>>> celdas,
    List<AccionPendiente> acciones = const [],
  }) async {
    final lobbyRef = _db.collection('Partidas').doc(lobbyId);

    final movData = MovimientoTurno(
      uid: uid,
      turno: turno,
      celdas: celdas,
      timestamp: DateTime.now().toUtc(),
      acciones: acciones,
    ).toMap();

    final sw = Stopwatch()..start();
    try {
      // Dos escrituras al documento de la partida (ya ligero):
      //   Paso 1: marcar el cierre (arrayUnion de cerradoPor).
      //   Paso 2: subir los movimientos del turno.
      await lobbyRef.update({
        'cerradoPor': FieldValue.arrayUnion([uid]),
      }).timeout(const Duration(seconds: 12));

      await lobbyRef.update({
        'movimientosTurno.$uid': movData,
      }).timeout(const Duration(seconds: 12));
      appLog('🟦 [SVC] cierre escrito en ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      appLog('🟥 [SVC] cierre LANZÓ/timeout tras ${sw.elapsedMilliseconds} ms: '
          '${e.runtimeType}');
      rethrow;
    }
  }

  // ── Leer historial de combates desde la subcolección ──────
  /// Lee los últimos turnos del historial desde Partidas/{id}/historial.
  /// Devuelve las entradas ordenadas por turno ascendente. Mantiene el
  /// documento principal ligero (el historial ya no vive dentro de él).
  Future<List<Map<String, dynamic>>> getHistorialCombates({
    required String lobbyId,
    int ultimosN = 5,
  }) async {
    try {
      final snap = await _db
          .collection('Partidas')
          .doc(lobbyId)
          .collection('historial')
          .get()
          .timeout(const Duration(seconds: 15));
      final entradas = snap.docs.map((d) => d.data()).toList();
      // Ordenar por turno ascendente.
      entradas.sort((a, b) =>
          ((a['turno'] as num?) ?? 0).compareTo((b['turno'] as num?) ?? 0));
      if (entradas.length > ultimosN) {
        return entradas.sublist(entradas.length - ultimosN);
      }
      return entradas;
    } catch (e) {
      appLog('🟡 [SVC] no se pudo leer historial: ${e.runtimeType}');
      return [];
    }
  }

  // ── Obtener movimientos de todos ──────────────────────────
  Future<List<MovimientoTurno>> getMovimientosTurno({
    required String lobbyId,
    required int turno,
  }) async {
    // Intentamos SERVIDOR con timeout corto (los movimientos de los demás
    // jugadores los escriben otros dispositivos y podrían no estar aún en la
    // caché local). Si no responde rápido, caemos a la lectura normal para no
    // colgar en entornos donde el canal seguro no se establece.
    final ref = _db.collection('Partidas').doc(lobbyId);
    DocumentSnapshot snap;
    try {
      snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      snap = await ref.get().timeout(const Duration(seconds: 15));
    }
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

  // ── Resolver acciones + combates + farmeo y avanzar turno ─
  /// Resuelve, en este orden:
  ///   1. Acciones declaradas (disparo / teletransporte / veneno) sobre el
  ///      tablero ya fusionado.
  ///   2. Combates con defensa reducida por venenos activos en cartas.
  ///   3. Farmeo de posición + rayo, sobre el tablero post-combates.
  ///   4. `tickEfectos` para decrementar duración de todos los efectos
  ///      persistentes (celdas y cartas).
  ///
  /// Persiste en Firestore el tablero resultante, las stats acumuladas y el
  /// estado actualizado de `efectosCelda`.
  ///
  /// [obeliscosPorJugador]   uid → coord del cuartel de ese jugador.
  /// [acciones]              Lista PLANA de acciones pendientes de todos los
  ///                          jugadores (orden de declaración no importa).
  /// [efectosCeldaActual]    Estado de efectos en celdas leído del lobby.
  Future<ResolucionCombates> resolverCombatesYAvanzar({
    required String lobbyId,
    required int turnoActual,
    required Map<String, List<Map<String, dynamic>>> tablero,
    required Map<String, Map<String, int>> statsActuales,
    List<Map<String, dynamic>>? movimientosLog,
    // ── Cuarteles ────────────────────────────────────────────
    Map<String, String>? obeliscosPorJugador,
    // ── Acciones / efectos persistentes ─────────────────────
    List<AccionPendiente> acciones = const [],
    Map<String, List<EfectoActivo>> efectosCeldaActual = const {},
    // ── Farmeo ────────────────────────────────────────────────
    Map<String, List<String>>? continentes,
    List<String>? islaCentral,
    Map<String, dynamic>? rayoActual,
    List<String>? todasLasCeldas,
  }) async {
    // 1. Aplicar acciones (tele → disparo → veneno) y propagar venenos.
    final accResultado = HabilidadService.aplicarAcciones(
      tablero: tablero,
      acciones: acciones,
      efectosCelda: efectosCeldaActual,
      obeliscosPorJugador: obeliscosPorJugador ?? const {},
    );

    // 2. Resolver combates sobre el tablero ya modificado.
    final resolucion = CombateService.resolverCombates(
      accResultado.tableroResultante,
      obeliscosPorJugador: obeliscosPorJugador,
    );

    // 3. Tick de efectos sobre el tablero post-combate (decrementa duraciones).
    final tick = HabilidadService.tickEfectos(
      tablero: resolucion.tableroResultante,
      efectosCelda: accResultado.efectosCeldaResultante,
    );

    final tableroFinal = tick.tableroResultante;
    final efectosCeldaFinal = tick.efectosCeldaResultante;

    // 4. Calcular farmeo (sobre el tablero FINAL tras combates y tick).
    FarmeoResultado? farmeoResultado;
    final farmeoActivo =
        continentes != null && islaCentral != null && todasLasCeldas != null;
    if (farmeoActivo) {
      farmeoResultado = FarmeoService.calcularFarmeo(
        tablero: tableroFinal,
        obeliscosPorJugador: obeliscosPorJugador ?? {},
        continentes: continentes!,
        islaCentral: islaCentral!,
        rayoActual: rayoActual,
        todasLasCeldas: todasLasCeldas!,
      );
    }

    // 5. Acumular stats (combate + farmeo + conquistas)
    final statsActualizadas = <String, Map<String, dynamic>>{};
    for (final entry in statsActuales.entries) {
      statsActualizadas[entry.key] = Map<String, dynamic>.from(entry.value);
    }

    // Energies de COMBATE (incluye recompensas normales y de conquista)
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

    // 6. Construir log de combates y entrada de historial
    final combateLog = resolucion.resultados.map((r) => r.toLogMap()).toList();
    final conquistasLog =
        resolucion.obeliscosConquistados.map((c) => c.toLogMap()).toList();
    final entradaHistorial = <String, dynamic>{
      'turno': turnoActual,
      'combateLog': combateLog,
      'conquistasLog': conquistasLog,
      'movimientosLog': movimientosLog ?? [],
      'farmeoLog': farmeoResultado?.farmeoLog ?? [],
      'accionesLog': accResultado.log,
      'rayoCoord': farmeoResultado?.nuevoRayo?['coord'],
      'rayoTurnosRestantes': farmeoResultado?.nuevoRayo?['turnosRestantes'],
    };

    // 7. Preparar lista de jugadores recién eliminados
    final nuevosEliminados =
        resolucion.obeliscosConquistados.map((c) => c.perdedorUid).toList();

    // 8. Transacción: solo escribe si el turno no ha avanzado ya
    final lobbyRef = _db.collection('Partidas').doc(lobbyId);
    final updateData = <String, dynamic>{
      'turnoActual': turnoActual + 1,
      'cerradoPor': [],
      'movimientosTurno': {},
      // CRÍTICO: el tablero se persiste ALIGERADO (solo campos mutables). Para
      // calcular combates se había enriquecido con todos los stats del catálogo,
      // pero guardarlo así engordaba el documento y leerlo se colgaba. Aquí lo
      // reducimos de nuevo a id + estado mutable; los stats se reconstruyen
      // desde el catálogo al leer.
      'tablero': aligerarTablero(tableroFinal),
      'statsPartida': statsActualizadas,
      'ultimoCombateLog': combateLog,
      'ultimoFarmeoLog': farmeoResultado?.farmeoLog ?? [],
      'ultimoAccionesLog': accResultado.log,
      if (movimientosLog != null) 'ultimosMovimientos': movimientosLog,
      if (farmeoActivo)
        'rayo': farmeoResultado?.nuevoRayo ?? FieldValue.delete(),
      // Persistir efectos de celda (o borrar el campo si queda vacío).
      'efectosCelda': efectosCeldaFinal.isEmpty
          ? FieldValue.delete()
          : BoardState.efectosCeldaToFirestore(efectosCeldaFinal),
    };

    await _db.runTransaction((tx) async {
      final snap = await tx.get(lobbyRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final turnoEnDB = (data['turnoActual'] as num?)?.toInt() ?? 0;
      if (turnoEnDB != turnoActual) return; // ya resuelto por otro jugador

      final finalData = Map<String, dynamic>.from(updateData);
      // El historial YA NO se guarda como campo del documento principal (eso
      // hacía crecer y anidar el documento hasta que leerlo del servidor se
      // colgaba en Android). Se borra el campo viejo si existe y el historial
      // del turno se guarda aparte, en la subcolección 'historial' (fuera de la
      // transacción, ver más abajo).
      finalData['historialCombates'] = FieldValue.delete();

      // ── Manejar eliminaciones ────────────────────────────────
      if (nuevosEliminados.isNotEmpty) {
        finalData['jugadoresEliminados'] =
            FieldValue.arrayUnion(nuevosEliminados);

        // Calcular jugadores aún activos para detectar fin de partida.
        final existingElim =
            List<String>.from((data['jugadoresEliminados'] as List?) ?? []);
        final totalElim = {...existingElim, ...nuevosEliminados};
        final jugadoresList = (data['jugadores'] as List? ?? []);
        final allUids = jugadoresList
            .map((j) => (j as Map)['uid'] as String? ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        final activos =
            allUids.where((uid) => !totalElim.contains(uid)).toList();

        if (activos.length <= 1) {
          finalData['estado'] = 'finalizada';
          if (activos.isNotEmpty) finalData['ganadorUid'] = activos.first;
        }
      }

      tx.update(lobbyRef, finalData);
    });

    // ── Guardar el historial del turno en la SUBCOLECCIÓN (fuera de la
    // transacción). Documento: Partidas/{id}/historial/{turno}. Así el
    // documento principal queda pequeño y plano, y leerlo es instantáneo.
    // El informe de batalla lee esta subcolección bajo demanda.
    try {
      await lobbyRef
          .collection('historial')
          .doc(turnoActual.toString())
          .set(entradaHistorial)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      appLog('🟡 [SVC] no se pudo guardar historial del turno $turnoActual '
          '(no crítico): ${e.runtimeType}');
    }

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

  /// Reduce un tablero crudo a solo los campos que cambian en partida, para que
  /// el documento de Firestore quede ligero. Los stats base (nombre, fuerza,
  /// defensa, etc.) se reconstruyen desde el catálogo al leer, así que no hace
  /// falta persistirlos. Mantiene id, Condicion, owner*, y la evolución.
  static Map<String, List<Map<String, dynamic>>> aligerarTablero(
      Map<String, List<Map<String, dynamic>>> tablero) {
    const mutables = {
      'id',
      'Id',
      'Condicion',
      'condicion',
      'ownerUid',
      'ownerZone',
      'Evolucion',
      'evolucion',
      'IdEvolucion',
      'idEvolucion',
      'Efectos',
      'efectos',
      'UltimoUsoHabilidad',
      'ultimoUsoHabilidad',
    };
    final result = <String, List<Map<String, dynamic>>>{};
    tablero.forEach((coord, cartas) {
      result[coord] = cartas.map((m) {
        final ligera = <String, dynamic>{};
        for (final k in mutables) {
          if (m.containsKey(k)) ligera[k] = m[k];
        }
        // Garantizar que siempre va el id (clave para reconstruir).
        if (!ligera.containsKey('id') && m.containsKey('Id')) {
          ligera['id'] = m['Id'];
        }
        return ligera;
      }).toList();
    });
    return result;
  }

  /// Parsea el campo `efectosCelda` del doc del lobby.
  static Map<String, List<EfectoActivo>> parseEfectosCelda(
          Map<String, dynamic> data) =>
      BoardState.efectosCeldaFromFirestore(
        data['efectosCelda'] as Map<String, dynamic>?,
      );

  /// Parsea el campo `acciones` flat de todos los movimientos de un turno.
  /// Útil para reconstruir la lista de acciones a resolver.
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
