// lib/core/firebaseCrudService.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseCrudService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  FirebaseCrudService();

  // ─────────────────────────────────────────────────────────
  // AUTENTICACIÓN
  // ─────────────────────────────────────────────────────────

  /// Registra un usuario con email/password y crea su perfil en Firestore.
  /// Devuelve el UserCredential creado.
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String alias,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Actualizar displayName en Firebase Auth
      await credential.user?.updateDisplayName(alias);

      // Crear toda la estructura en Firestore
      await crearEstructuraJugador(
        uid: credential.user!.uid,
        alias: alias,
        email: email,
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  /// Inicia sesión con email y contraseña.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // CREACIÓN DE ESTRUCTURA DEL JUGADOR
  // ─────────────────────────────────────────────────────────

  /// Crea el documento raíz del jugador y todos los documentos
  /// iniciales de sus subcolecciones.
  ///
  /// Llama con SetOptions(merge: true) para que sea idempotente:
  /// si el jugador ya existe (re-instalación) no machaca sus datos.
  Future<void> crearEstructuraJugador({
    required String uid,
    required String alias,
    required String email,
  }) async {
    final batch = _db.batch();
    final jugadorRef = _db.collection('Jugadores').doc(uid);
    final ahora = FieldValue.serverTimestamp();

    // ── 1. Documento raíz ─────────────────────────────────
    batch.set(
      jugadorRef,
      {
        'alias': alias,
        'email': email,
        'imagenPerfil': '',
        'nivel': 1,
        'experiencia': 0,
        'dinero': 0,
        'fechaRegistro': ahora,
        'ultimaConexion': ahora,
      },
      SetOptions(merge: true), // idempotente
    );

    // ── 2. Estadísticas iniciales ──────────────────────────
    // Subcolección Estadisticas / resumen
    // Al tener un documento inicial, la subcolección ya es visible
    // en la consola aunque el jugador no haya jugado ninguna partida.
    final statsRef = jugadorRef.collection('Estadisticas').doc('resumen');
    batch.set(
      statsRef,
      {
        'partidasJugadas': 0,
        'partidasGanadas': 0,
        'cartasDestruidas': 0,
        'energiesTotales': 0,
        'turnosJugados': 0,
        'ultimaActualizacion': ahora,
      },
      SetOptions(merge: true),
    );

    // ── 3. Mazos y Colección ───────────────────────────────
    // No se crean documentos iniciales: los mazos y las cartas
    // se añaden en el flujo normal del juego. Firestore no permite
    // subcolecciones vacías, así que se crearán solas al primer uso.

    await batch.commit();
  }

  /// Actualiza los campos editables del perfil (alias e imagenPerfil).
  Future<void> actualizarPerfil({
    required String uid,
    required String alias,
    required String imagenPerfil,
  }) async {
    await _db.collection('Jugadores').doc(uid).update({
      'alias': alias,
      'imagenPerfil': imagenPerfil,
      'ultimaConexion': FieldValue.serverTimestamp(),
    });

    // Sync con Firebase Auth displayName
    await _auth.currentUser?.updateDisplayName(alias);
  }

  /// Verifica si el documento de perfil ya existe (para el flujo
  /// de login: si el jugador borra la app y vuelve a entrar,
  /// no se re-crea el perfil con datos por defecto).
  Future<bool> perfilExiste(String uid) async {
    final doc = await _db.collection('Jugadores').doc(uid).get();
    return doc.exists;
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  double _parseDouble(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

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
      case 'operation-not-allowed':
        return 'Operación no permitida. Contacta al soporte.';
      default:
        return e.message ?? 'Ocurrió un error de autenticación.';
    }
  }
}
