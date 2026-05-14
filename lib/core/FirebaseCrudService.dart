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
  // CARTAS INICIALES DEL CATÁLOGO
  // Cada jugador nuevo recibe estas cartas al registrarse.
  // Formato: { cartaId → lista de skins desbloqueadas }
  // La primera skin de cada lista es la seleccionada por defecto.
  // ───────────────────────────────────────────────────────────
  static const Map<String, List<String>> _cartasIniciales = {
    '2nSmuTkVPutvQV9B9CO3': ['default'],
    '4OSJYbsRbWkiNiJCmrPM': ['default'],
    '5FIrpVq0890nhRg1atDB': ['default'],
    '8KZtDtblcypCtFfDSF08': ['default'],
    'BPzSAviOhq9P5OlTlyoU': ['default'],
    'MJOdFy1NhGnmvPGIlm7i': ['default'],
    'OgkbAd8qpHAwiDiiTUNn': ['default'],
    'Xh0qnULyvCvLBFYGJseH': ['default'],
    'YorhPHxb4D1CffkVeHxQ': ['default'],
    'ch5IVwiwxaFjsaASAJVH': ['default'],
    'emeeFFwdvz3RKHyYTxaI': ['default'],
    'h4AzHTBz0PRwjBBTxhHf': ['default'],
    'k1ExDeLkxEvUtDPUUJvt': ['default'],
    'kKJl1PyTsfIytyfOkfiS': ['default'],
    'lKG5rzUbmslpf9fb65Cz': ['default'],
    'piqdZNbXTy1xt2ibg8Oi': ['default'],
    'rDnEsagFisLO8TbSzeHb': ['default'],
    'rpZC7bELsrHFfn4YsCbY': ['default'],
    'tkw9wEklsteYfmGclaNe': ['default'],
    // Carta con 1 skin extra desbloqueada
    'xPcw2Adpdfdb8TMp4Uiy': ['default', 'XIm1pgv67us9IPZq39sV'],
    // Carta con 2 skins extra desbloqueadas
    'xYGGl9sWoZfYQwnlaNwu': [
      'default',
      'ZCQ4azbUkHO6WsBCtXib',
      'EfZhU2Fqc7gsCp8Et0mr'
    ],
  };

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

        // Crear las subcolecciones iniciales (cada una en su try-catch
        // para que un fallo en una no bloquee las demás)
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

  /// Crea las subcolecciones con su contenido inicial.
  /// Cada bloque va en su propio try-catch: si uno falla (p. ej. por
  /// reglas de Firestore incompletas) los demás se crean igualmente.
  ///
  /// IMPORTANTE: las reglas de Firestore deben incluir:
  ///   match /Estadisticas/{docId} {
  ///     allow read, write: if request.auth != null
  ///                        && request.auth.uid == uid;
  ///   }
  Future<void> _initSubcolecciones(String uid) async {
    final jugadorRef = _db.collection('Jugadores').doc(uid);

    // ── Estadisticas → doc 'Resultados' ──────────────────────
    try {
      await jugadorRef.collection('Estadisticas').doc('Resultados').set({
        'Victorias': 0,
        'Derrotas': 0,
      });
    } catch (e) {
      print('[FirebaseCrudService] _initSubcolecciones Estadisticas: $e');
    }

    // ── Coleccion → 21 cartas iniciales del catálogo ─────────
    // Cada documento usa el ID de la carta global como ID del doc y tiene:
    //   cantidad (String), fechaObtenida, skinSeleccionada, skinsDesbloqueadas
    try {
      final colRef = jugadorRef.collection('Coleccion');
      final batch = _db.batch();
      final ahora = Timestamp.now();

      for (final entry in _cartasIniciales.entries) {
        final cartaId = entry.key;
        final skins = entry.value;
        batch.set(colRef.doc(cartaId), {
          'cantidad': '1',
          'fechaObtenida': ahora,
          'skinSeleccionada': skins.first,
          'skinsDesbloqueadas': skins,
        });
      }
      await batch.commit();
    } catch (e) {
      print('[FirebaseCrudService] _initSubcolecciones Coleccion: $e');
    }

    // ── Mazos → mazo vacío inicial ────────────────────────────
    try {
      await jugadorRef.collection('Mazos').add({
        'nombre': 'Mazo 1',
        'ejercitoId': 1,
        'esPrincipal': true,
        'cartaIds': <String>[],
        'total': 0,
        'creadoEn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('[FirebaseCrudService] _initSubcolecciones Mazos: $e');
    }
  }

  /// Versión idempotente para cuentas antiguas: solo crea lo que falta.
  /// Se llama en cada login; no toca nada que ya exista.
  Future<void> _ensureSubcolecciones(String uid) async {
    final jugadorRef = _db.collection('Jugadores').doc(uid);

    // Estadisticas/Resultados
    try {
      final estSnap =
          await jugadorRef.collection('Estadisticas').doc('Resultados').get();
      if (!estSnap.exists) {
        await jugadorRef.collection('Estadisticas').doc('Resultados').set({
          'Victorias': 0,
          'Derrotas': 0,
        });
      }
    } catch (e) {
      print('[FirebaseCrudService] _ensureSubcolecciones Estadisticas: $e');
    }

    // Coleccion: si está completamente vacía, sembrar las cartas iniciales
    try {
      final colSnap = await jugadorRef.collection('Coleccion').limit(1).get();
      if (colSnap.docs.isEmpty) {
        final colRef = jugadorRef.collection('Coleccion');
        final batch = _db.batch();
        final ahora = Timestamp.now();

        for (final entry in _cartasIniciales.entries) {
          final cartaId = entry.key;
          final skins = entry.value;
          batch.set(colRef.doc(cartaId), {
            'cantidad': '1',
            'fechaObtenida': ahora,
            'skinSeleccionada': skins.first,
            'skinsDesbloqueadas': skins,
          });
        }
        await batch.commit();
      }
    } catch (e) {
      print('[FirebaseCrudService] _ensureSubcolecciones Coleccion: $e');
    }

    // Mazos: si no tiene ninguno, crear el mazo inicial
    try {
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
    } catch (e) {
      print('[FirebaseCrudService] _ensureSubcolecciones Mazos: $e');
    }
  }

  // ───────────────────────────────────────────────────────────
  // COLECCION DE CARTAS DEL JUGADOR
  // ───────────────────────────────────────────────────────────

  /// Añade una carta a la Coleccion del jugador o incrementa su cantidad.
  ///
  /// [cartaId] es el ID del doc en la colección global 'Cartas'.
  /// [skinInicial] es la skin que se asigna la primera vez.
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
      // Primera copia (o placeholder residual de versiones antiguas)
      await cartaRef.set({
        'cantidad': '1',
        'fechaObtenida': FieldValue.serverTimestamp(),
        'skinSeleccionada': skinInicial,
        'skinsDesbloqueadas': [skinInicial],
      });
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
