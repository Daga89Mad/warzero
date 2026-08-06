// lib/services/permisos.dart
//
// Permisos por correo. FUENTE ÚNICA de la lista de cuentas con acceso a
// herramientas internas (edición de contenido, diagnóstico de notificaciones,
// etc.). Antes la lista vivía embebida en menu.dart; centralizarla aquí evita
// que se desincronice cuando se usa en varias pantallas.
//
// Para dar/quitar acceso a alguien, edita ÚNICAMENTE el conjunto [kEditores].

import 'package:firebase_auth/firebase_auth.dart';

/// Correos con permisos de editor/QA (edición de contenido y diagnóstico).
const Set<String> kEditores = {
  'dagahh89@gmail.com',
  'qa104@daga.com',
  'qa106@daga.com',
  'qa107@daga.com',
};

/// ¿El correo [email] tiene permisos de editor/QA? Normaliza espacios y
/// mayúsculas para comparar de forma robusta.
bool esEditorEmail(String? email) =>
    kEditores.contains((email ?? '').trim().toLowerCase());

/// ¿El usuario [user] (por defecto, el que hay logueado) tiene permisos de
/// editor/QA?
bool esEditor([User? user]) =>
    esEditorEmail((user ?? FirebaseAuth.instance.currentUser)?.email);
