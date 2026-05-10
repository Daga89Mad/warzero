// lib/core/firebaseCrudService.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseCrudService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  FirebaseCrudService();

  String? get currentUid => _auth.currentUser?.uid;

  double _parseDouble(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  // ───────────────────────────────────────────────────────────
  // REGISTRO
  // ───────────────────────────────────────────────────────────

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String alias,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user?.uid;
      final aliasFinal = alias.trim().isEmpty ? 'Jugador' : alias.trim();
      if (uid != null) {
        // Crear el doc principal del jugador
        await _db.collection('Jugadores').doc(uid).set({
          'alias': aliasFinal,
          'dinero': 0,
          'imagenPerfil': '',
          'nivel': 1,
          'experiencia': 0,
          'fechaRegistro': FieldValue.serverTimestamp(),
        });
        try {
          await cred.user?.updateDisplayName(aliasFinal);
        } catch (_) {}

        // Crear las subcolecciones iniciales
        await _initSubcolecciones(uid);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  // ───────────────────────────────────────────────────────────
  // LOGIN
  // ───────────────────────────────────────────────────────────

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Asegurar que cuentas antiguas (sin subcolecciones) las tengan
      final uid = cred.user?.uid;
      if (uid != null) {
        try {
          await _ensureSubcolecciones(uid);
        } catch (_) {
          // No bloqueamos el login si falla
        }
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  // ───────────────────────────────────────────────────────────
  // ESTRUCTURA INICIAL DE SUBCOLECCIONES
  // ───────────────────────────────────────────────────────────

  /// Crea las 3 subcolecciones con su documento inicial.
  /// Usado en el registro (usuario nuevo, no hay nada aún).
  Future<void> _initSubcolecciones(String uid) async {
    final jugadorRef = _db.collection('Jugadores').doc(uid);

    // ── Estadisticas → doc 'Resultados' ──────────────────────
    // Estructura vista en Firestore: { Victorias: 0, Derrotas: 0 }
    await jugadorRef.collection('Estadisticas').doc('Resultados').set({
      'Victorias': 0,
      'Derrotas': 0,
    });

    // ── Coleccion → placeholder hasta que el jugador obtenga cartas ──
    // Cada doc real tiene: { cantidad, fechaObtenida,
    //   skinSeleccionada, skinsDesbloqueadas[] }
    // El ID del doc es el mismo ID de la carta en la colección global Cartas.
    // Al registrarse no hay cartas todavía; el placeholder hace que la
    // subcolección sea visible en la consola de Firestore.
    await jugadorRef.collection('Coleccion').doc('_init').set({
      'placeholder': true,
      'creadoEn': FieldValue.serverTimestamp(),
    });

    // ── Mazos → mazo vacío inicial ────────────────────────────
    // Estructura del doc mazo: { nombre, ejercitoId, esPrincipal,
    //   cartaIds, total, creadoEn }
    // Cada mazo tiene una sub-subcolección 'Cartas' donde el ID de
    // cada doc es el ID de la carta y el campo es { Cantidad: int }.
    // Al registrarse el mazo empieza sin cartas.
    await jugadorRef.collection('Mazos').add({
      'nombre': 'Mazo 1',
      'ejercitoId': 1,
      'esPrincipal': true,
      'cartaIds': <String>[],
      'total': 0,
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Versión idempotente para cuentas antiguas: solo crea lo que falta.
  /// Se llama en cada login; no toca nada que ya exista.
  Future<void> _ensureSubcolecciones(String uid) async {
    final jugadorRef = _db.collection('Jugadores').doc(uid);

    // Estadisticas/Resultados
    final estSnap =
        await jugadorRef.collection('Estadisticas').doc('Resultados').get();
    if (!estSnap.exists) {
      await jugadorRef.collection('Estadisticas').doc('Resultados').set({
        'Victorias': 0,
        'Derrotas': 0,
      });
    }

    // Coleccion: si está completamente vacía, sembrar placeholder
    final colSnap = await jugadorRef.collection('Coleccion').limit(1).get();
    if (colSnap.docs.isEmpty) {
      await jugadorRef.collection('Coleccion').doc('_init').set({
        'placeholder': true,
        'creadoEn': FieldValue.serverTimestamp(),
      });
    }

    // Mazos: si no tiene ninguno, crear el mazo inicial
    final mazosSnap = await jugadorRef.collection('Mazos').limit(1).get();
    if (mazosSnap.docs.isEmpty) {
      await jugadorRef.collection('Mazos').add({
        'nombre': 'Mazo 1',
        'ejercitoId': 1,
        'esPrincipal': true,
        'cartaIds': <String>[],
        'total': 0,
        'creadoEn': FieldValue.serverTimestamp(),
      });
    }
  }

  // ───────────────────────────────────────────────────────────
  // COLECCION DE CARTAS DEL JUGADOR
  // ───────────────────────────────────────────────────────────

  /// Añade una carta a la Coleccion del jugador o incrementa su cantidad.
  ///
  /// [cartaId] es el ID del doc en la colección global 'Cartas'.
  /// [skinInicial] es la skin que se asigna la primera vez.
  ///
  /// Al añadir la primera carta real se elimina automáticamente el
  /// placeholder '_init' si sigue ahí.
  Future<void> agregarCartaAColeccion({
    required String uid,
    required String cartaId,
    String skinInicial = 'default',
  }) async {
    final colRef = _db.collection('Jugadores').doc(uid).collection('Coleccion');
    final cartaRef = colRef.doc(cartaId);
    final snap = await cartaRef.get();

    if (snap.exists && snap.data()?['placeholder'] != true) {
      // El jugador ya tiene la carta: sumar una copia
      final cantidadActual =
          int.tryParse(snap.data()?['cantidad']?.toString() ?? '1') ?? 1;
      await cartaRef.update({'cantidad': '${cantidadActual + 1}'});
    } else {
      // Primera copia
      await cartaRef.set({
        'cantidad': '1',
        'fechaObtenida': FieldValue.serverTimestamp(),
        'skinSeleccionada': skinInicial,
        'skinsDesbloqueadas': [skinInicial],
      });

      // Borrar placeholder _init si todavía existe
      try {
        final initRef = colRef.doc('_init');
        final initSnap = await initRef.get();
        if (initSnap.exists && initSnap.data()?['placeholder'] == true) {
          await initRef.delete();
        }
      } catch (_) {}
    }
  }

  // ───────────────────────────────────────────────────────────
  // PERFIL
  // ───────────────────────────────────────────────────────────

  Future<void> signOut() => _auth.signOut();

  Future<void> actualizarPerfil({
    String? uid,
    String? alias,
    String? imagenPerfil,
    int? dinero,
    int? nivel,
    int? experiencia,
  }) async {
    final targetUid = uid ?? currentUid;
    if (targetUid == null || targetUid.isEmpty) {
      throw Exception('No hay un usuario autenticado.');
    }
    final updates = <String, dynamic>{};
    if (alias != null && alias.trim().isNotEmpty)
      updates['alias'] = alias.trim();
    if (imagenPerfil != null) updates['imagenPerfil'] = imagenPerfil;
    if (dinero != null) updates['dinero'] = dinero;
    if (nivel != null) updates['nivel'] = nivel;
    if (experiencia != null) updates['experiencia'] = experiencia;
    if (updates.isEmpty) return;
    try {
      await _db.collection('Jugadores').doc(targetUid).set(
            updates,
            SetOptions(merge: true),
          );
      if (updates.containsKey('alias') && targetUid == currentUid) {
        try {
          await _auth.currentUser
              ?.updateDisplayName(updates['alias'] as String);
        } catch (_) {}
      }
    } on FirebaseException catch (e) {
      throw Exception('No se pudo actualizar el perfil: ${e.message}');
    }
  }

  Future<void> cambiarPassword(String nuevaPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay un usuario autenticado.');
    try {
      await user.updatePassword(nuevaPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  // ───────────────────────────────────────────────────────────
  // HELPERS
  // ───────────────────────────────────────────────────────────

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no tiene un formato válido.';
      case 'user-not-found':
        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':
        return 'La contraseña es incorrecta.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta registrada con ese correo.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'requires-recent-login':
        return 'Por seguridad, vuelve a iniciar sesión para realizar este cambio.';
      default:
        return e.message ?? 'Ocurrió un error de autenticación.';
    }
  }
}
