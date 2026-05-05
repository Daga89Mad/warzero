// lib/services/mazo_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/carta_model.dart';
import '../models/mazo_model.dart';

class MazoService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Cargar todas las cartas del juego ──────────────────────
  Future<List<CartaModel>> fetchTodasLasCartas() async {
    final snap = await _db.collection('Cartas').get();
    return snap.docs.map(CartaModel.fromFirestore).toList();
  }

  // ── Cargar mazos de un jugador ─────────────────────────────
  Future<List<MazoModel>> fetchMazosDelJugador(String uid) async {
    final snap = await _db
        .collection('Jugadores')
        .doc(uid)
        .collection('Mazos')
        .get();

    final mazos = <MazoModel>[];
    for (final mazoDoc in snap.docs) {
      final cartasSnap = await mazoDoc.reference.collection('Cartas').get();
      final entradas = cartasSnap.docs.map(MazoEntrada.fromFirestore).toList();
      mazos.add(MazoModel(id: mazoDoc.id, entradas: entradas));
    }
    return mazos;
  }

  // ── Resolver un mazo: expandir cartas con Cantidad ─────────
  Future<MazoResuelto> resolverMazo(MazoModel mazo) async {
    // Cargar solo las cartas necesarias del mazo
    final cartasIds = mazo.entradas.map((e) => e.idCarta).toList();
    final snaps = await Future.wait(
      cartasIds.map((id) => _db.collection('Cartas').doc(id).get()),
    );

    final cartas = <CartaModel>[];
    for (int i = 0; i < mazo.entradas.length; i++) {
      final doc = snaps[i];
      if (!doc.exists) continue;
      final carta = CartaModel.fromFirestore(doc);
      final cantidad = mazo.entradas[i].cantidad;
      for (int q = 0; q < cantidad; q++) {
        cartas.add(carta);
      }
    }
    return MazoResuelto(id: mazo.id, cartas: cartas);
  }

  // ── Mazo por defecto si el jugador no tiene ninguno ────────
  /// Crea un mazo aleatorio con las primeras N cartas disponibles
  Future<MazoResuelto> crearMazoPorDefecto({int tamanio = 20}) async {
    final todasLasCartas = await fetchTodasLasCartas();
    todasLasCartas.shuffle();
    final seleccion = todasLasCartas.take(tamanio).toList();
    return MazoResuelto(id: 'default', cartas: seleccion);
  }

  // ── Punto de entrada principal: obtener mazo listo ─────────
  /// Devuelve el primer mazo del jugador, o uno por defecto si no tiene.
  Future<MazoResuelto> obtenerMazoParaJuego(String uid) async {
    try {
      final mazos = await fetchMazosDelJugador(uid);
      if (mazos.isEmpty) {
        return crearMazoPorDefecto();
      }
      return resolverMazo(mazos.first);
    } catch (e) {
      // Fallback: mazo por defecto en caso de error
      return crearMazoPorDefecto();
    }
  }

  // ── Guardar mazo ───────────────────────────────────────────
  Future<void> guardarMazo(String uid, MazoResuelto mazo) async {
    // Agrupa por carta y cuenta
    final conteo = <String, int>{};
    for (final carta in mazo.cartas) {
      conteo[carta.id] = (conteo[carta.id] ?? 0) + 1;
    }

    final mazoRef = _db
        .collection('Jugadores')
        .doc(uid)
        .collection('Mazos')
        .doc(mazo.id == 'default' ? null : mazo.id);

    final batch = _db.batch();
    for (final entry in conteo.entries) {
      batch.set(
        mazoRef.collection('Cartas').doc(entry.key),
        {'Cantidad': entry.value},
      );
    }
    await batch.commit();
  }
}
