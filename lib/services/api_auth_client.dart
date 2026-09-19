// lib/services/api_auth_client.dart
//
// Cliente HTTP global de la app. Se instala en main.dart con
// `http.runWithClient`, así que TODAS las llamadas `http.get/post(...)` del
// proyecto (WarZeroApi, TrofeosService, RetoService…) pasan por aquí sin tener
// que tocar cada servicio.
//
// Qué hace:
//   1. Añade `Authorization: Bearer <ID token de Firebase>` a las peticiones
//      dirigidas a NUESTRO backend (y solo a él: el token nunca sale hacia
//      terceros). Si la petición ya trae Authorization (AdminCuentasService),
//      no la toca.
//   2. Si el servidor responde 401, renueva el token una vez y reintenta
//      (caso típico: el token caducó justo entre medias).
//   3. En iOS usa la pila de red del SISTEMA (NSURLSession vía cupertino_http)
//      en lugar del TLS propio de Dart. Así el tráfico HTTPS de la app usa el
//      cifrado del sistema operativo, respeta ATS y la configuración de red
//      del dispositivo (ver nota de cumplimiento de cifrado en la revisión).

import 'dart:io' show Platform;

import 'package:cupertino_http/cupertino_http.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class ApiAuthClient extends http.BaseClient {
  ApiAuthClient._(this._interno);

  /// Hosts propios que reciben el ID token. Añade aquí el dominio si cambias
  /// de proveedor o pones un dominio propio.
  static const Set<String> hostsPropios = {'fenrirv2.onrender.com'};

  /// Cliente de red real, COMPARTIDO. Las funciones top-level `http.get` crean
  /// un cliente por llamada y lo cierran al terminar; por eso el envoltorio se
  /// crea cada vez pero el cliente interno (y su pool de conexiones) se
  /// reutiliza y nunca se cierra.
  static final http.Client _compartido = _crearInterno();

  final http.Client _interno;

  /// Fábrica para `http.runWithClient(..., ApiAuthClient.fabrica)`.
  static http.Client fabrica() => ApiAuthClient._(_compartido);

  static http.Client _crearInterno() {
    if (!kIsWeb && Platform.isIOS) {
      return CupertinoClient.defaultSessionConfiguration();
    }
    // IOClient explícito: dentro de runWithClient, `http.Client()` volvería a
    // llamar a la fábrica y entraría en bucle.
    return IOClient();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final esPropio = request.url.scheme == 'https' &&
        hostsPropios.contains(request.url.host);

    if (!esPropio || request.headers.containsKey('Authorization')) {
      return _interno.send(request);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _interno.send(request);

    // Copia previa: una petición ya enviada no se puede reenviar.
    final copia = request is http.Request ? _copiar(request) : null;

    final token = await _token(user, forzar: false);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final respuesta = await _interno.send(request);
    if (respuesta.statusCode != 401 || copia == null) return respuesta;

    // 401: token caducado o revocado → renovar una vez y reintentar.
    await respuesta.stream.drain<void>();
    final nuevo = await _token(user, forzar: true);
    if (nuevo == null) {
      return http.StreamedResponse(const Stream.empty(), 401,
          request: request, reasonPhrase: 'Unauthorized');
    }
    copia.headers['Authorization'] = 'Bearer $nuevo';
    return _interno.send(copia);
  }

  static Future<String?> _token(User user, {required bool forzar}) async {
    try {
      return await user.getIdToken(forzar);
    } catch (e) {
      debugPrint('[WZ][auth] no se pudo obtener el ID token: $e');
      return null;
    }
  }

  static http.Request _copiar(http.Request original) {
    return http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..bodyBytes = original.bodyBytes
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
  }

  /// El cliente compartido vive toda la app: no se cierra con cada petición.
  @override
  void close() {}
}
