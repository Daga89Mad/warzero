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
  //
  // Estas cartas se dan a cada jugador nuevo:
  //   - Se crean en Jugadores/{uid}/Coleccion/{cartaId}
  //   - Se añaden a Jugadores/{uid}/Mazos/{mazoId}/Cartas/{cartaId}
  //     con { Cantidad: 1 } para que el mazo inicial sea jugable.
  //
  // Formato: { cartaId → skins desbloqueadas }
  // La primera skin de la lista es la seleccionada por defecto.
  // ───────────────────────────────────────────────────────────
  static const Map<String, List<String>> _cartasIniciales = {
    '0ahUhgSb6oOIaqe1yxIt': ['default'],
    '0qGtiuXP9aqAmxEwVzhc': ['default'],
    '0vL229Dy0qkJxFTv5f7O': ['default'],
    '1YpvMjECo464Dx9jvTVK': ['default'],
    '2DjgWWSU7Q5F6dFAv8wQ': ['default'],
    '2nSmuTkVPutvQV9B9CO3': ['default'],
    '2zKQOGmsL72jl4vveJOC': ['default'],
    '4OSJYbsRbWkiNiJCmrPM': ['default'],
    '5FIrpVqO890nhRg1atDB': ['default'],
    '8KZtDtblcypCtFfDSF08': ['default'],
    '8ROTbPT4Msl5Sf4MkSdG': ['default'],
    '8WxyKRLvqWf6kFMcVHSw': ['default'],
    '9Uxi9KSJmsZIN8SNQ1hD': ['default'],
    '9Vb3p8MPmxlC0fiaZX6B': ['default'],
    'AGk9YFtmaOe99ZKUiEHz': ['default'],
    'AWfj1Y7ibCw7nkAUlUUE': ['default'],
    'BPzSAviOhq9P5OlTlyoU': ['default'],
    'HCSN6Oy5zpVz59uXhKGN': ['default'],
    'IV8OBgpNjDTwYV8PAILP': ['default'],
    'JFyZ4iYEA9BfsFSh3VLa': ['default'],
    'JJ9rVGVtdaSLOImXV2j2': ['default'],
    'JeI4EaJKLQrQlBiblNLp': ['default'],
    'LpAM8celKg1gvQsp5okR': ['default'],
    'LyGg5ElbrcFgvrJjbNqP': ['default'],
    'MJOdFy1NhGnmvPGIlm7i': ['default'],
    'MRBiWOXxtxs7fqlJrfd0': ['default'],
    'OgkbAd8qpHAwiDiiTUNn': ['default'],
    'SgxMTCB6knJe8SUrQh5F': ['default'],
    'VKM1uUkqO9GqDI6tTr47': ['default'],
    'VmhD1AghdOBjmRfpSzk4': ['default'],
    'WXnsascHJzcddkDXVUQu': ['default'],
    'Xh0qnUlyvCvLBFYGJseH': ['default'],
    'YorhPHxb4D1CffkVeHxQ': ['default'],
    'aYqrD9mNBO7adaPHWp6i': ['default'],
    'akw6SDq7YhWRpGLDl77e': ['default'],
    'cPgRW24Te3ic6sN8EPoR': ['default'],
    'cShsMi3IB8Pd2gu42T4O': ['default'],
    'ca0XZNWXTUMvjvzoBqu0': ['default'],
    'ch5IVwiwxaFjsaASAJVH': ['default'],
    'cluh1nY12v6yxichmdex': ['default'],
    'dJGMcvXCCNdhLFpTms1F': ['default'],
    'emeeFFwdvz3RKHyYTxaI': ['default'],
    'h4AzHTBz0PRwjBBTxhHf': ['default'],
    'hlwsYwP3e4hyrjG5i9ZY': ['default'],
    'iGUutQJ6O071IZ1tAYYl': ['default'],
    'iju32O3HHqU27hmoVhhn': ['default'],
    'jFpE0EY9dJQdME2iM2y9': ['default'],
    'jI9Tu5falVBBqLozHU2d': ['default'],
    'k1ExDeLkxEvUtDPUUJvt': ['default'],
    'kKJl1PyTsfIytyfOkfiS': ['default'],
    'lKG5rzUbmslpf9fb65Cz': ['default'],
    'lQVO1N9Xi3Fe6BP7cNyw': ['default'],
    'nE3AAMcX0H7oWTVMydsZ': ['default'],
    'nKvmAoQLLynP0L91SqV3': ['default'],
    'oVcsugdOXwTaVrpBaoEO': ['default'],
    'piqdzNbXTy1xt2ibg8Oi': ['default'],
    'qeygP8oT7WYKqmq1kvHI': ['default'],
    'qrc2GYYSEhjLoISdxQch': ['default'],
    'rDnEsagFisLO8TbSzeHb': ['default'],
    'rpZC7bELsrHFfn4YsCbY': ['default'],
    'stF3jOzQyQvVJguGblKj': ['default'],
    'tSWupmUokszJJfLRJaFC': ['default'],
    'tTxkzVeFYLUXxMOg03y8': ['default'],
    'tkw9wEklsteYfmGclaNe': ['default'],
    'uOfCRljbVXoRNWXwv6gL': ['default'],
    'uoxviGggKKUDlkEwHn6O': ['default'],
    'vy3wCVMYaQUcYw768Mnf': ['default'],
    'wU6paai60pEqfYnAx2cE': ['default'],
    'wWGvqQWEjZRZZcyab6yU': ['default'],
    'xi9ys2LqcHNVfFPNRsef': ['default'],
    'zDMmUICWuTmfsAAk6JbV': ['default'],
    'zj2P2KoF31Hw24KQWiBu': ['default'],
    'zqIDNsAb8dHtKf7EMISq': ['default'],
    'YbgK01QuTY3nGT6ZTwui': ['default'],
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

        // Crear subcolecciones: cada bloque en su propio try-catch para
        // que un fallo en uno no bloquee los demás.
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
  // INICIALIZACIÓN DE SUBCOLECCIONES (registro)
  // ───────────────────────────────────────────────────────────

  /// Crea las tres subcolecciones del jugador con su contenido inicial.
  ///
  /// ESTRUCTURA RESULTANTE EN FIRESTORE:
  ///   Jugadores/{uid}/Estadisticas/Resultados      → {Victorias:0, Derrotas:0}
  ///   Jugadores/{uid}/Coleccion/{cartaId}           → {cantidad, fechaObtenida,
  ///                                                    skinSeleccionada,
  ///                                                    skinsDesbloqueadas}
  ///   Jugadores/{uid}/Mazos/{mazoId}               → metadata del mazo
  ///   Jugadores/{uid}/Mazos/{mazoId}/Cartas/{id}   → {Cantidad: 1}
  ///                                                 ← CLAVE: sin esto el mazo
  ///                                                   se lee como vacío y el
  ///                                                   jugador no recibe mano.
  ///
  /// REGLA DE FIRESTORE NECESARIA (añadir si no existe):
  ///   match /Estadisticas/{docId} {
  ///     allow read, write: if request.auth != null
  ///                        && request.auth.uid == uid;
  ///   }
  Future<void> _initSubcolecciones(String uid) async {
    final jugadorRef = _db.collection('Jugadores').doc(uid);

    // ── 1. Estadisticas ──────────────────────────────────────
    try {
      await jugadorRef.collection('Estadisticas').doc('Resultados').set({
        'Victorias': 0,
        'Derrotas': 0,
      });
    } catch (e) {
      print('[FirebaseCrudService] _initSubcolecciones Estadisticas: $e');
    }

    // ── 2. Coleccion (cartas que posee el jugador) ────────────
    // Doc ID = ID de la carta global. Campos: cantidad (String),
    // fechaObtenida, skinSeleccionada, skinsDesbloqueadas.
    try {
      final colRef = jugadorRef.collection('Coleccion');
      final batch = _db.batch();
      final ahora = Timestamp.now();
      for (final entry in _cartasIniciales.entries) {
        batch.set(colRef.doc(entry.key), {
          'cantidad': '1',
          'fechaObtenida': ahora,
          'skinSeleccionada': entry.value.first,
          'skinsDesbloqueadas': entry.value,
        });
      }
      await batch.commit();
    } catch (e) {
      print('[FirebaseCrudService] _initSubcolecciones Coleccion: $e');
    }

    // ── 3. Mazos + su subcolección Cartas ────────────────────
    //
    // RAÍZ DEL BUG: el código anterior solo creaba el doc del mazo
    // pero NO las entradas en Mazos/{id}/Cartas. fetchMazosDelJugador
    // lee esa subcolección → vacía → resolverMazo devuelve [] → mano vacía.
    //
    // Ahora se crean ambas cosas en el mismo batch para garantizar
    // que el mazo sea jugable desde el primer turno.
    try {
      final mazosRef = jugadorRef.collection('Mazos');
      final mazoDoc = mazosRef.doc(); // ID auto-generado

      final batch = _db.batch();

      // Doc raíz del mazo
      batch.set(mazoDoc, {
        'nombre': 'Mazo 1',
        'ejercitoId': 1,
        'esPrincipal': true,
        'cartaIds': _cartasIniciales.keys.toList(),
        'total': _cartasIniciales.length,
        'creadoEn': FieldValue.serverTimestamp(),
      });

      // Subcolección Cartas: una entrada por carta inicial.
      // MazoEntrada.fromFirestore espera doc.id = cartaId y campo 'Cantidad'.
      final cartasRef = mazoDoc.collection('Cartas');
      for (final cartaId in _cartasIniciales.keys) {
        batch.set(cartasRef.doc(cartaId), {'Cantidad': 1});
      }

      await batch.commit();
    } catch (e) {
      print('[FirebaseCrudService] _initSubcolecciones Mazos: $e');
    }
  }

  // ───────────────────────────────────────────────────────────
  // IDEMPOTENTE PARA CUENTAS ANTIGUAS (login)
  // ───────────────────────────────────────────────────────────

  /// Se llama en cada login. Solo crea lo que falta; no toca lo que existe.
  Future<void> _ensureSubcolecciones(String uid) async {
    final jugadorRef = _db.collection('Jugadores').doc(uid);

    // Estadisticas
    try {
      final snap =
          await jugadorRef.collection('Estadisticas').doc('Resultados').get();
      if (!snap.exists) {
        await jugadorRef.collection('Estadisticas').doc('Resultados').set({
          'Victorias': 0,
          'Derrotas': 0,
        });
      }
    } catch (e) {
      print('[FirebaseCrudService] _ensureSubcolecciones Estadisticas: $e');
    }

    // Coleccion: si vacía, sembrar cartas iniciales
    try {
      final colSnap = await jugadorRef.collection('Coleccion').limit(1).get();
      if (colSnap.docs.isEmpty) {
        final colRef = jugadorRef.collection('Coleccion');
        final batch = _db.batch();
        final ahora = Timestamp.now();
        for (final entry in _cartasIniciales.entries) {
          batch.set(colRef.doc(entry.key), {
            'cantidad': '1',
            'fechaObtenida': ahora,
            'skinSeleccionada': entry.value.first,
            'skinsDesbloqueadas': entry.value,
          });
        }
        await batch.commit();
      }
    } catch (e) {
      print('[FirebaseCrudService] _ensureSubcolecciones Coleccion: $e');
    }

    // Mazos: si vacío, crear el mazo inicial CON su subcolección Cartas
    try {
      final mazosSnap = await jugadorRef.collection('Mazos').limit(1).get();
      if (mazosSnap.docs.isEmpty) {
        // Sin ningún mazo → crear mazo inicial completo
        final mazosRef = jugadorRef.collection('Mazos');
        final mazoDoc = mazosRef.doc();
        final batch = _db.batch();
        batch.set(mazoDoc, {
          'nombre': 'Mazo 1',
          'ejercitoId': 1,
          'esPrincipal': true,
          'cartaIds': _cartasIniciales.keys.toList(),
          'total': _cartasIniciales.length,
          'creadoEn': FieldValue.serverTimestamp(),
        });
        final cartasRef = mazoDoc.collection('Cartas');
        for (final cartaId in _cartasIniciales.keys) {
          batch.set(cartasRef.doc(cartaId), {'Cantidad': 1});
        }
        await batch.commit();
      } else {
        // Hay al menos un mazo: verificar que tenga cartas en su subcolección.
        // Cuentas antiguas pueden tener el doc del mazo pero sin Cartas.
        final primerMazo = mazosSnap.docs.first;
        final cartasSnap =
            await primerMazo.reference.collection('Cartas').limit(1).get();
        if (cartasSnap.docs.isEmpty) {
          // El mazo existe pero su subcolección Cartas está vacía → poblarla
          final batch = _db.batch();
          final cartasRef = primerMazo.reference.collection('Cartas');
          for (final cartaId in _cartasIniciales.keys) {
            batch.set(cartasRef.doc(cartaId), {'Cantidad': 1});
          }
          await batch.commit();
        }
      }
    } catch (e) {
      print('[FirebaseCrudService] _ensureSubcolecciones Mazos: $e');
    }
  }

  // ───────────────────────────────────────────────────────────
  // COLECCION DE CARTAS DEL JUGADOR
  // ───────────────────────────────────────────────────────────

  /// Añade una carta a la Coleccion del jugador o incrementa su cantidad.
  Future<void> agregarCartaAColeccion({
    required String uid,
    required String cartaId,
    String skinInicial = 'default',
  }) async {
    final colRef = _db.collection('Jugadores').doc(uid).collection('Coleccion');
    final cartaRef = colRef.doc(cartaId);
    final snap = await cartaRef.get();

    if (snap.exists && snap.data()?['placeholder'] != true) {
      final cantidadActual =
          int.tryParse(snap.data()?['cantidad']?.toString() ?? '1') ?? 1;
      await cartaRef.update({'cantidad': '${cantidadActual + 1}'});
    } else {
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
