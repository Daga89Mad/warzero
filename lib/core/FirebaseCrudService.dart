// lib/core/firebaseCrudService.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseCrudService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─────────────────────────────────────────────────────────────
  // Configuración del perfil inicial de un jugador nuevo
  // ─────────────────────────────────────────────────────────────

  /// Cartas iniciales que recibe el jugador en su colección personal.
  /// Cantidad por defecto: 2 de cada una.
  static const List<String> _cartasInicialesIds = [
    '8KZtDtblcypCtFfDSF08',
    'k1ExDeLkxEvUtDPUUJvt',
    'kKJl1PyTsfIytyfOkfiS',
    'piqdzNbXTy1xt2ibg8Oi',
    'xPcw2Adpdfdb8TMp4Uiy',
  ];

  /// Cartas que componen el mazo inicial de Ejército 1 (Humanos).
  /// Cantidad por defecto: 2 de cada una.
  static const List<String> _cartasMazoHumanosIds = [
    '8KZtDtblcypCtFfDSF08',
    'xPcw2Adpdfdb8TMp4Uiy',
    'k1ExDeLkxEvUtDPUUJvt',
    'kKJl1PyTsfIytyfOkfiS',
    'piqdzNbXTy1xt2ibg8Oi',
  ];

  static const int _cantidadInicialPorCarta = 2;

  /// Constructor por defecto, sin parámetros
  FirebaseCrudService();

  // Helper que convierte cualquier raw a double
  double _parseDouble(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  /// Registra un usuario con email y contraseña, y crea su perfil
  /// inicial en Firestore (documento + cartas iniciales + mazo humano).
  ///
  /// Lanza Exception con mensaje legible si hay error.
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user?.uid;
      if (uid != null) {
        await _crearPerfilInicialJugador(uid);
      }

      return cred;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  /// Crea de forma atómica todo el perfil inicial de un jugador:
  /// - `Jugadores/{uid}` con los valores por defecto.
  /// - `Jugadores/{uid}/Cartas/*` con las cartas iniciales (Cantidad = 2).
  /// - `Jugadores/{uid}/Mazos/{autoId}` con un mazo de Humanos
  ///   y su subcolección `Cartas/*` (Cantidad = 2).
  Future<void> _crearPerfilInicialJugador(String uid) async {
    final batch = _db.batch();

    // 1. Documento principal del jugador
    //    Campos en minúscula/camelCase según captura de Firestore
    final jugadorRef = _db.collection('Jugadores').doc(uid);
    batch.set(jugadorRef, {
      'alias': 'Jugador Zero',
      'dinero': 500,
      'experiencia': 0,
      'imagenPerfil': '',
      'nivel': 1,
    });

    // 2. Subcolección Cartas del jugador
    for (final cartaId in _cartasInicialesIds) {
      final cartaRef = jugadorRef.collection('Cartas').doc(cartaId);
      batch.set(cartaRef, {'Cantidad': _cantidadInicialPorCarta});
    }

    // 3. Mazo inicial del Ejército 1 (Humanos)
    final mazoRef = jugadorRef.collection('Mazos').doc();
    batch.set(mazoRef, {
      'ejercito': 1,
      'nombre': 'Mazo Humanos',
    });

    // 4. Subcolección Cartas del mazo
    for (final cartaId in _cartasMazoHumanosIds) {
      final cartaMazoRef = mazoRef.collection('Cartas').doc(cartaId);
      batch.set(cartaMazoRef, {'Cantidad': _cantidadInicialPorCarta});
    }

    await batch.commit();
  }

  /// Inicia sesión con email y contraseña
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

  /// Mapea los códigos de FirebaseAuthException a mensajes legibles
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
      default:
        return e.message ?? 'Ocurrió un error de autenticación.';
    }
  }

  /// Traduce códigos de FirebaseAuthException a mensajes legibles
  String _translateErrorCode(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo.';
      case 'weak-password':
        return 'La contraseña es demasiado débil.';
      case 'operation-not-allowed':
        return 'Operación no permitida. Contacta al soporte.';
      default:
        return e.message ?? 'Error desconocido de autenticación.';
    }
  }
}
