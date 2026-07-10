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
  // El editor de mazos (mazo_screen.dart) guarda las cartas del mazo como un
  // array plano `cartaIds` en el propio documento del mazo (sin duplicados:
  // cada id aparece como máximo una vez), NO como una subcolección `Cartas`
  // con campo `Cantidad` (ese esquema antiguo ya no lo escribe la app).
  Future<List<MazoModel>> fetchMazosDelJugador(String uid) async {
    final snap =
        await _db.collection('Jugadores').doc(uid).collection('Mazos').get();

    final mazos = <MazoModel>[];
    for (final mazoDoc in snap.docs) {
      final d = mazoDoc.data();
      final cartaIds = List<String>.from(d['cartaIds'] as List? ?? []);
      final entradas =
          cartaIds.map((id) => MazoEntrada(idCarta: id, cantidad: 1)).toList();
      mazos.add(MazoModel(
        id: mazoDoc.id,
        entradas: entradas,
        esPrincipal: d['esPrincipal'] as bool? ?? false,
        ejercitoId: (d['ejercitoId'] as num?)?.toInt(),
      ));
    }
    // El mazo principal primero (si hay varios y ninguno está marcado, se
    // conserva el orden de Firestore).
    mazos.sort((a, b) => (b.esPrincipal ? 1 : 0) - (a.esPrincipal ? 1 : 0));
    return mazos;
  }

  // ── Resolver un mazo: expandir cartas con Cantidad ─────────
  Future<MazoResuelto> resolverMazo(MazoModel mazo) async {
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
  /// Construye el mazo por defecto del ejército. Usa las cartas marcadas con el
  /// check "Mazo por defecto" (campo `PorDefecto`) de ese ejército. Si no hay
  /// ninguna marcada, cae a una selección aleatoria (comportamiento anterior).
  Future<MazoResuelto> crearMazoPorDefecto({
    int tamanio = 8,
    int? ejercitoId,
  }) async {
    final todasLasCartas = await fetchTodasLasCartas();
    // Nunca incluir cartas de Evolución ni Especiales en mazos (no se reparten).
    todasLasCartas.removeWhere((c) => c.esEvolucion || c.esEspecial);

    // Pool del ejército (o todas si no se especifica o no hay de ese ejército).
    List<CartaModel> pool = todasLasCartas;
    if (ejercitoId != null) {
      final filtradas =
          todasLasCartas.where((c) => c.ejercito == ejercitoId).toList();
      if (filtradas.isNotEmpty) pool = filtradas;
    }

    // Preferimos las cartas marcadas como "mazo por defecto".
    final marcadas = pool.where((c) => c.porDefecto).toList();
    if (marcadas.isNotEmpty) {
      marcadas.shuffle();
      return MazoResuelto(
          id: 'default', cartas: marcadas.take(tamanio).toList());
    }

    // Fallback: selección aleatoria del ejército.
    pool.shuffle();
    final seleccion = pool.take(tamanio).toList();
    return MazoResuelto(id: 'default', cartas: seleccion);
  }

  // ── Punto de entrada principal: obtener mazo listo ─────────
  /// Devuelve el primer mazo del jugador filtrado por [ejercitoId], o uno
  /// por defecto si no tiene mazos guardados.
  ///
  /// [ejercitoId] El ID del ejército seleccionado por el jugador en la sala
  ///              de espera. Si es null no se filtra.
  Future<MazoResuelto> obtenerMazoParaJuego(
    String uid, {
    int? ejercitoId,
  }) async {
    try {
      final mazos = await fetchMazosDelJugador(uid);
      if (mazos.isEmpty) {
        return crearMazoPorDefecto(ejercitoId: ejercitoId);
      }
      // `esPrincipal` es por ejército: elegir el mazo del ejército en juego
      // (principal de ese ejército → cualquiera de ese ejército → el primero).
      final elegido = _elegirMazo(mazos, ejercitoId);
      final resuelto = await resolverMazo(elegido);
      // Filtrar por ejército preservando el mazo original si queda vacío.
      return resuelto.filtrarPorEjercito(ejercitoId);
    } catch (e) {
      return crearMazoPorDefecto(ejercitoId: ejercitoId);
    }
  }

  /// Elige el mazo a usar. `esPrincipal` es por ejército, así que se prioriza
  /// el mazo del [ejercitoId] indicado:
  ///   1) principal del ejército  2) cualquiera del ejército
  ///   3) principal global        4) el primero
  MazoModel _elegirMazo(List<MazoModel> mazos, int? ejercitoId) {
    if (ejercitoId != null) {
      final delEjercito =
          mazos.where((m) => m.ejercitoId == ejercitoId).toList();
      if (delEjercito.isNotEmpty) {
        return delEjercito.firstWhere((m) => m.esPrincipal,
            orElse: () => delEjercito.first);
      }
    }
    return mazos.firstWhere((m) => m.esPrincipal, orElse: () => mazos.first);
  }

  // ── Guardar mazo ───────────────────────────────────────────
  // Mismo esquema que escribe el editor de mazos (mazo_screen.dart): un
  // array plano `cartaIds` (sin duplicados) en el propio documento del mazo.
  Future<void> guardarMazo(String uid, MazoResuelto mazo) async {
    final cartaIds = mazo.cartas.map((c) => c.id).toSet().toList();

    final coleccion = _db.collection('Jugadores').doc(uid).collection('Mazos');
    final mazoRef =
        mazo.id == 'default' ? coleccion.doc() : coleccion.doc(mazo.id);

    await mazoRef.set({
      'cartaIds': cartaIds,
      'total': cartaIds.length,
    }, SetOptions(merge: true));
  }
}
