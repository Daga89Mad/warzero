// lib/services/lobby_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lobby_model.dart';
import '../models/mazo_model.dart';
import '../services/mazo_service.dart';
import 'warzero_api.dart';

class LobbyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final WarZeroApi _api = WarZeroApi();

  // ── Stream de lobbies públicos en espera ──────────────────
  /// La lista pública se sirve ahora por HTTP desde el backend, que la cachea
  /// con TTL corto y COMPARTIDO entre todos los clientes. Así N clientes
  /// sondeando = 1 ciclo de lectura de Firestore en el servidor, en lugar de N
  /// lecturas independientes (una por cliente). El sondeo del cliente se relaja
  /// a 30 s: una lista pública tolera perfectamente esa latencia.
  Stream<List<LobbyModel>> lobbiesPublicosStream() {
    return _sondeoPeriodico(const Duration(seconds: 30), _leerLobbiesPublicos);
  }

  Future<List<LobbyModel>> _leerLobbiesPublicos() async {
    // Lectura vía backend (cacheada y compartida). Ya no toca Firestore desde
    // el cliente. El backend devuelve mapas planos con `id` inyectado.
    final raw = await _api.obtenerPublicas();
    final list = <LobbyModel>[];
    for (final d in raw) {
      try {
        final id = d['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final l = LobbyModel.fromMap(id, d);
        if (!l.esPrivada) list.add(l); // defensa extra: privadas fuera
      } catch (_) {
        // Ignorar documentos malformados.
      }
    }
    list.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return list;
  }

  /// Emite el resultado de [leer] inmediatamente y luego lo re-emite cada
  /// [cada]. Sustituye a los listeners en tiempo real sobre CONSULTAS
  /// multi-documento (que re-leían en cada cambio de cualquier partida). El
  /// StreamBuilder cancela la suscripción al salir de pantalla, así que solo
  /// consume mientras la lista está visible. Reutilizable para varias listas.
  Stream<List<LobbyModel>> _sondeoPeriodico(
    Duration cada,
    Future<List<LobbyModel>> Function() leer,
  ) async* {
    // Primera emisión inmediata (sin esperar al primer tick).
    yield await leer();
    // Emisiones sucesivas. asyncMap serializa: no se solapan lecturas aunque
    // una tarde más que el intervalo.
    yield* Stream.periodic(cada).asyncMap((_) => leer());
  }

  // ── Stream de un lobby concreto ───────────────────────────
  Stream<LobbyModel?> lobbyStream(String lobbyId) {
    return _db
        .collection('Partidas')
        .doc(lobbyId)
        .snapshots()
        .map((s) => s.exists ? LobbyModel.fromFirestore(s) : null);
  }

  // ── Crear lobby ───────────────────────────────────────────
  /// [mapaId] es opcional: si se pasa, se guarda en la partida para
  /// que todos los jugadores carguen el mismo terreno al entrar en juego.
  Future<String> crearLobby({
    required String nombre,
    required String hostUid,
    required String hostAlias,
    required bool esPrivada,
    required String contrasena,
    required int maxJugadores,
    ModoTurno modoTurno = ModoTurno.rapida,
    String? mapaId,
  }) async {
    final data = LobbyModel(
      id: '',
      nombre: nombre,
      hostUid: hostUid,
      esPrivada: esPrivada,
      contrasena: contrasena,
      maxJugadores: maxJugadores,
      jugadores: [
        LobbyJugador(uid: hostUid, alias: hostAlias, listo: false),
      ],
      estado: LobbyEstado.esperando,
      creadoEn: DateTime.now(),
      modoTurno: modoTurno,
      turnoActual: 1,
      cerradoPor: const [],
      mapaId: mapaId,
    ).toMap();

    data['participantes'] = [hostUid];

    final ref = await _db.collection('Partidas').add(data);
    return ref.id;
  }

  // ── Unirse a un lobby ─────────────────────────────────────
  Future<void> unirseALobby({
    required String lobbyId,
    required String uid,
    required String alias,
    String? contrasena,
  }) async {
    final doc = await _db.collection('Partidas').doc(lobbyId).get();
    if (!doc.exists) throw Exception('La sala no existe.');

    final lobby = LobbyModel.fromFirestore(doc);
    if (lobby.estado != LobbyEstado.esperando) {
      throw Exception('La partida ya ha comenzado.');
    }
    if (lobby.estaLleno) throw Exception('La sala está llena.');
    if (lobby.esPrivada && lobby.contrasena != contrasena) {
      throw Exception('Contraseña incorrecta.');
    }
    if (lobby.jugadores.any((j) => j.uid == uid)) return;

    final nuevo = LobbyJugador(uid: uid, alias: alias).toMap();
    await _db.collection('Partidas').doc(lobbyId).update({
      'jugadores': FieldValue.arrayUnion([nuevo]),
      'participantes': FieldValue.arrayUnion([uid]),
    });
  }

  // ── Salir del lobby ───────────────────────────────────────
  Future<void> salirDeLobby({
    required String lobbyId,
    required String uid,
  }) async {
    final doc = await _db.collection('Partidas').doc(lobbyId).get();
    if (!doc.exists) return;

    final lobby = LobbyModel.fromFirestore(doc);
    final nuevosJugadores = lobby.jugadores.where((j) => j.uid != uid).toList();

    if (nuevosJugadores.isEmpty) {
      await _db.collection('Partidas').doc(lobbyId).delete();
      return;
    }

    final updates = <String, dynamic>{
      'jugadores': nuevosJugadores.map((j) => j.toMap()).toList(),
    };
    if (lobby.hostUid == uid) {
      updates['hostUid'] = nuevosJugadores.first.uid;
    }
    await _db.collection('Partidas').doc(lobbyId).update(updates);
  }

  // ── Cancelar (eliminar) una sala ──────────────────────────
  /// Borra la sala por completo. Pensado para que SOLO el host cancele
  /// explícitamente una sala que ya no quiere. A diferencia de [salirDeLobby],
  /// no depende de que la sala quede vacía: elimina el documento directamente.
  Future<void> cancelarLobby(String lobbyId) async {
    await _db.collection('Partidas').doc(lobbyId).delete();
  }

  /// Fija el ejército del jugador [uid] en la sala y lo marca como listo.
  ///
  /// IMPORTANTE — por qué es una TRANSACCIÓN y no un get+update:
  /// El mazo/mano (`mazoPool`, `mano`) se reparte UNA sola vez al arrancar la
  /// partida con el `ejercitoId` de ese momento y luego se preserva turno a
  /// turno. Si se pudiera cambiar el ejército después (o si dos escrituras del
  /// array `jugadores` se pisaran por no ser atómicas), el `ejercitoId` del
  /// lobby quedaría desincronizado del mazo realmente repartido: se juega un
  /// ejército pero el cuartel muestra otro (incidencia real: jugador con mazo
  /// de Humanos y cuartel de Demonios). Para evitarlo:
  ///   1) Solo se permite elegir/cambiar ejército mientras la sala está en
  ///      `esperando` (una vez `en_curso` el mazo ya está repartido y fijado).
  ///   2) Se hace dentro de una transacción, modificando SOLO la entrada de
  ///      este `uid`, para no perder ni cruzar selecciones de otros jugadores
  ///      o bots que entren a la vez.
  Future<void> seleccionarEjercito({
    required String lobbyId,
    required String uid,
    required int ejercitoId,
  }) async {
    final ref = _db.collection('Partidas').doc(lobbyId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) return;

      final lobby = LobbyModel.fromFirestore(doc);

      // Una vez la partida arrancó (o terminó), el ejército queda fijado: el
      // mazo ya se repartió con él y cambiarlo ahora lo desincronizaría.
      if (lobby.estado != LobbyEstado.esperando) return;

      final jugadores = lobby.jugadores.map((j) {
        if (j.uid == uid) {
          return j.copyWith(ejercitoId: ejercitoId, listo: true);
        }
        return j;
      }).toList();

      tx.update(ref, {
        'jugadores': jugadores.map((j) => j.toMap()).toList(),
      });
    });
  }

  // ── Iniciar partida (solo host) ───────────────────────────
  /// El botón "Iniciar batalla" solo está activo cuando TODOS los jugadores
  /// presentes han elegido ejército (canStart = todosListos), así que aquí nunca
  /// hay humanos sin ejército: solo huecos vacíos.
  ///   • Si faltan jugadores → marca `rellenarBots` para que el servidor
  ///     (orquestador) rellene los huecos con bots; al quedar llena y todos
  ///     listos, arranca sola y envía la notificación push.
  ///   • Si la sala ya está completa → arranca directamente.
  /// La navegación al juego la dispara el stream cuando `estado` = `en_curso`.
  Future<void> iniciarPartida(String lobbyId) async {
    final doc = await _db.collection('Partidas').doc(lobbyId).get();
    if (!doc.exists) return;
    final lobby = LobbyModel.fromFirestore(doc);
    final huecos = lobby.maxJugadores - lobby.jugadores.length;

    if (huecos > 0) {
      await _db.collection('Partidas').doc(lobbyId).update({
        'rellenarBots': true,
      });
    } else {
      await _db.collection('Partidas').doc(lobbyId).update({
        'estado': 'en_curso',
      });
    }
  }

  /// Garantiza que el campo `participantes` contiene a todos los jugadores
  /// actuales. Idempotente y barato: solo escribe si falta alguien. Sirve para
  /// auto-reparar partidas creadas antes de que existiera el campo (de lo
  /// contrario no aparecerían en "mis partidas", que ahora filtra por
  /// `participantes`). Es fire-and-forget: cualquier error se ignora.
  Future<void> asegurarParticipantes(String lobbyId) async {
    try {
      final doc = await _db.collection('Partidas').doc(lobbyId).get();
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      final jugadores = (data['jugadores'] as List? ?? [])
          .map((j) => (j as Map)['uid'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toSet();
      final participantes = (data['participantes'] as List? ?? [])
          .map((e) => e.toString())
          .toSet();
      final faltan = jugadores.difference(participantes);
      if (faltan.isNotEmpty) {
        await _db.collection('Partidas').doc(lobbyId).update({
          'participantes': FieldValue.arrayUnion(faltan.toList()),
        });
      }
    } catch (_) {
      // No crítico: si falla, la lista simplemente no se auto-repara.
    }
  }

  // ── Stream de mis partidas ────────────────────────────────
  /// Devuelve las partidas (en espera o en curso) en las que el usuario es
  /// participante.
  ///
  /// Filtra EN EL SERVIDOR por el campo `participantes` con `arrayContains`,
  /// en lugar de escanear toda la colección y filtrar en cliente. Esto evita:
  ///   - Que reglas de seguridad basadas en participantes rechacen la consulta
  ///     (lo que dejaba el StreamBuilder cargando indefinidamente).
  ///   - Leer documentos de otros usuarios (rendimiento y coste).
  /// Un único `arrayContains` no requiere índice compuesto. El estado se filtra
  /// en cliente (excluir finalizadas) para no necesitar un índice combinado.
  Stream<List<LobbyModel>> misPartidasStream(String uid) {
    // OPTIMIZACIÓN DE LECTURAS: es una consulta por-usuario (no compartible),
    // así que se mantiene en el cliente pero con la cadencia relajada a 30 s
    // (antes 15 s). En tiempo real este listener re-leía la partida completa en
    // cada escritura (cada resolución de turno, cada movimiento), incluidas las
    // partidas EN CURSO, que son las que más cambian; el sondeo acota el coste.
    return _sondeoPeriodico(
      const Duration(seconds: 30),
      () => _leerMisPartidas(uid),
    );
  }

  Future<List<LobbyModel>> _leerMisPartidas(String uid) async {
    final s = await _db
        .collection('Partidas')
        .where('participantes', arrayContains: uid)
        .get();
    final list = <LobbyModel>[];
    for (final d in s.docs) {
      try {
        final l = LobbyModel.fromFirestore(d);
        // Mostrar solo partidas activas (esperando o en curso) en las que el
        // jugador sigue presente.
        final sigueEnPartida = l.jugadores.any((j) => j.uid == uid);
        if (l.estado != LobbyEstado.finalizada && sigueEnPartida) {
          list.add(l);
        }
      } catch (_) {
        // Documento malformado: lo ignoramos para no tumbar la lista entera.
      }
    }
    list.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return list;
  }

  // ── Buscar lobby privado por ID ───────────────────────────
  Future<LobbyModel?> buscarLobbyPorId(String lobbyId) async {
    final doc = await _db.collection('Partidas').doc(lobbyId).get();
    if (!doc.exists) return null;
    return LobbyModel.fromFirestore(doc);
  }

  // ── Obeliscos / cuarteles ─────────────────────────────────
  Future<Map<String, String>> getObeliscos(String lobbyId) async {
    final doc = await _db.collection('Partidas').doc(lobbyId).get();
    if (!doc.exists) return {};
    final data = doc.data() as Map<String, dynamic>;
    final raw = data['obeliscos'] as Map<String, dynamic>? ?? {};
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  Future<String?> assignObeliscoIfNeeded({
    required String lobbyId,
    required String uid,
    required List<String> allCoords,
  }) async {
    final obeliscos = await getObeliscos(lobbyId);
    if (obeliscos.containsKey(uid)) return obeliscos[uid];

    final taken = obeliscos.values.toSet();
    final available = allCoords.where((c) => !taken.contains(c)).toList();
    if (available.isEmpty) return null;

    available.shuffle();
    final assigned = available.first;

    await _db.collection('Partidas').doc(lobbyId).update({
      'obeliscos.$uid': assigned,
    });
    return assigned;
  }

  // ── Mazo ──────────────────────────────────────────────────
  Future<MazoResuelto> obtenerMazoParaEjercito({
    required String uid,
    required int ejercitoId,
  }) async {
    return MazoService().obtenerMazoParaJuego(uid);
  }
}
