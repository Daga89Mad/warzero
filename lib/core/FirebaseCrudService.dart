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
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

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
