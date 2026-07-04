// lib/services/lobby_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lobby_model.dart';
import '../models/mazo_model.dart';
import '../services/mazo_service.dart';

class LobbyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Stream de lobbies públicos en espera ──────────────────
  /// Filtra SOLO por estado en el servidor (índice de campo único, siempre
  /// disponible) y descarta las privadas en cliente. Antes combinaba dos
  /// `where` (esPrivada + estado), lo que exige un índice COMPUESTO en
  /// Firestore: si no está desplegado, el stream lanza error y la lista deja de
  /// mostrar partidas ("dejó de buscar partidas"). Mismo criterio que en
  /// [misPartidasStream].
  Stream<List<LobbyModel>> lobbiesPublicosStream() {
    return _db
        .collection('Partidas')
        .where('estado', isEqualTo: 'esperando')
        .limit(50)
        .snapshots()
        .map((s) {
      final list = <LobbyModel>[];
      for (final d in s.docs) {
        try {
          final l = LobbyModel.fromFirestore(d);
          if (!l.esPrivada) list.add(l); // privadas fuera, en cliente
        } catch (_) {
          // Ignorar documentos malformados.
        }
      }
      list.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
      return list;
    });
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

  // ── Seleccionar ejército y marcar listo ───────────────────
  Future<void> seleccionarEjercito({
    required String lobbyId,
    required String uid,
    required int ejercitoId,
  }) async {
    final doc = await _db.collection('Partidas').doc(lobbyId).get();
    if (!doc.exists) return;

    final lobby = LobbyModel.fromFirestore(doc);
    final jugadores = lobby.jugadores.map((j) {
      if (j.uid == uid) return j.copyWith(ejercitoId: ejercitoId, listo: true);
      return j;
    }).toList();

    await _db.collection('Partidas').doc(lobbyId).update({
      'jugadores': jugadores.map((j) => j.toMap()).toList(),
    });
  }

  // ── Iniciar partida (solo host) ───────────────────────────
  Future<void> iniciarPartida(String lobbyId) async {
    await _db.collection('Partidas').doc(lobbyId).update({
      'estado': 'en_curso',
    });
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
    return _db
        .collection('Partidas')
        .where('participantes', arrayContains: uid)
        .snapshots()
        .map((s) {
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
    });
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
