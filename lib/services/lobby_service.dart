// lib/services/lobby_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lobby_model.dart';
import '../models/mazo_model.dart';
import '../services/mazo_service.dart';

class LobbyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Stream de lobbies públicos en espera ──────────────────
  Stream<List<LobbyModel>> lobbiesPublicosStream() {
    return _db
        .collection('Partidas')
        .where('esPrivada', isEqualTo: false)
        .where('estado', isEqualTo: 'esperando')
        .limit(30)
        .snapshots()
        .map((s) {
      final list = s.docs.map(LobbyModel.fromFirestore).toList();
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

  // ── Stream de mis partidas ────────────────────────────────
  Stream<List<LobbyModel>> misPartidasStream(String uid) {
    return _db
        .collection('Partidas')
        .where('estado', whereIn: ['esperando', 'en_curso'])
        .snapshots()
        .map((s) {
          final list = s.docs
              .map(LobbyModel.fromFirestore)
              .where((l) => l.jugadores.any((j) => j.uid == uid))
              .toList();
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
