// lib/services/notificaciones_service.dart
//
// Notificaciones push (Firebase Cloud Messaging) para iOS y Android.
//
// Responsabilidades:
//   • Pedir permiso de notificaciones (iOS y Android 13+).
//   • Obtener el token FCM del dispositivo y registrarlo en el backend
//     (POST /warzero/fcm/registrar) asociado al uid del jugador logueado.
//   • Reaccionar a la renovación de token (onTokenRefresh) re-registrándolo.
//   • Mostrar la notificación cuando llega con la app en PRIMER PLANO (en
//     Android, FCM no la muestra sola: la pintamos con flutter_local_notifications).
//   • Navegar a la partida cuando el usuario PULSA la notificación (vía el
//     callback [onAbrirPartida], que la app decide cómo resolver).
//
// El backend envía el push cuando un turno se resuelve (cerró el último jugador
// o venció la hora límite). El payload de datos incluye:
//   { tipo: "turno_resuelto"|"partida_finalizada", lobbyId, turno }
//
// Uso desde main():
//   1. Registrar el handler de background ANTES de runApp (top-level).
//   2. Llamar a NotificacionesService.instance.iniciar() tras Firebase.initializeApp().
//   3. (Opcional) asignar NotificacionesService.instance.onAbrirPartida.
//
// NOTA iOS (importante): en iOS el token FCM NO se puede obtener hasta que el
// dispositivo ha terminado de registrarse en APNs. Ese registro es asíncrono y
// justo al arrancar `getAPNSToken()` puede devolver null durante un instante;
// si en ese momento se llama a `getToken()`, el plugin lanza "apns-token-not-set"
// y, sin reintento, el token nunca se registra (síntoma: en Firestore el token
// no se actualiza). Por eso aquí:
//   • Se reintenta obtener el token APNs con backoff antes de pedir el FCM.
//   • Si aun así falla, se re-programa el registro unos segundos después.
//   • Se registran en log el APNs y el FCM para poder diagnosticar.
// Si tras los reintentos el APNs sigue null, el problema NO es de carrera sino
// de configuración del build: falta la capability "Push Notifications" / el
// entitlement `aps-environment`, el provisioning no incluye push, o la clave
// APNs (.p8) no está subida en Firebase.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'warzero_api.dart';

/// Handler de mensajes en BACKGROUND / app terminada. DEBE ser una función
/// top-level (o estática) anotada con @pragma('vm:entry-point'). Se ejecuta en
/// un isolate aparte, por eso apenas hace nada: el sistema ya muestra la
/// notificación (viene con bloque `notification`); aquí solo se podría procesar
/// el payload de datos si hiciera falta.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nota: no reinicializamos Firebase aquí porque el plugin ya lo gestiona en
  // el isolate de background para los mensajes con `notification`. Si en el
  // futuro se procesan mensajes SOLO de datos, habría que llamar a
  // Firebase.initializeApp() antes de tocar otros servicios de Firebase.
  debugPrint(
      '[WZ][push][bg] mensaje: ${message.messageId} data=${message.data}');
}

class NotificacionesService {
  NotificacionesService._();
  static final NotificacionesService instance = NotificacionesService._();

  final WarZeroApi _api = WarZeroApi();
  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // Debe coincidir con el channelId del backend (WarZeroNotificaciones.cs).
  static const String _canalId = 'turnos_warzero';
  static const String _canalNombre = 'Turnos de partida';
  static const String _canalDesc =
      'Avisos cuando se resuelve un turno y ya puedes jugar.';

  bool _iniciado = false;
  String? _uidActual;
  String? _ultimoToken;

  // Control de reintentos del registro (para cubrir la carrera de arranque en
  // iOS con el token APNs, o un fallo transitorio de red al registrar).
  static const int _maxReintentos = 5;
  int _reintentos = 0;
  Timer? _timerReintento;

  /// La app decide cómo abrir una partida al pulsar una notificación. Recibe el
  /// lobbyId. Se invoca tanto para el mensaje que abrió la app (app terminada)
  /// como para pulsaciones con la app en segundo plano.
  void Function(String lobbyId)? onAbrirPartida;

  /// Inicializa el servicio. Idempotente. Llamar una vez tras Firebase.initializeApp().
  Future<void> iniciar() async {
    if (_iniciado) return;
    _iniciado = true;

    try {
      await _pedirPermisos();
      await _configurarNotificacionesLocales();
      await _configurarPresentacionPrimerPlano();
      _registrarListeners();

      // Registrar el token del usuario ya logueado (si lo hay) y reaccionar a
      // logins/logouts posteriores.
      _uidActual = FirebaseAuth.instance.currentUser?.uid;
      if (_uidActual != null) {
        await _registrarTokenActual(_uidActual!);
      } else {
        debugPrint('[WZ][push] sin usuario logueado aún; se registrará al '
            'restaurarse la sesión (authStateChanges).');
      }
      FirebaseAuth.instance.authStateChanges().listen(_onAuthCambio);

      // Comprobar si la app se ABRIÓ pulsando una notificación (estaba terminada).
      final inicial = await _fm.getInitialMessage();
      if (inicial != null) _abrirDesdeMensaje(inicial);
    } catch (e) {
      debugPrint('[WZ][push] iniciar falló (seguimos sin push): $e');
    }
  }

  // ── Permisos ──────────────────────────────────────────────────────────────
  Future<void> _pedirPermisos() async {
    // iOS + Android 13+. En Android <13 se concede automáticamente.
    final settings = await _fm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[WZ][push] permiso: ${settings.authorizationStatus}');
  }

  // ── Notificaciones locales (para mostrar en primer plano en Android) ───────
  Future<void> _configurarNotificacionesLocales() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // Ya pedimos permisos vía FirebaseMessaging; no re-solicitar aquí.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final lobbyId = resp.payload;
        if (lobbyId != null && lobbyId.isNotEmpty) {
          onAbrirPartida?.call(lobbyId);
        }
      },
    );

    // Crear el canal de Android (necesario en Android 8+). Debe coincidir con el
    // channelId que envía el backend.
    const canal = AndroidNotificationChannel(
      _canalId,
      _canalNombre,
      description: _canalDesc,
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canal);
  }

  /// En iOS, por defecto las notificaciones NO se muestran con la app en primer
  /// plano. Esto las muestra igualmente (banner + sonido).
  Future<void> _configurarPresentacionPrimerPlano() async {
    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ── Listeners de mensajes ──────────────────────────────────────────────────
  void _registrarListeners() {
    // Mensaje recibido con la app en PRIMER PLANO.
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[WZ][push][fg] ${msg.notification?.title} data=${msg.data}');
      _mostrarLocal(msg);
    });

    // Usuario PULSA la notificación con la app en segundo plano (no terminada).
    FirebaseMessaging.onMessageOpenedApp.listen(_abrirDesdeMensaje);

    // Renovación del token → re-registrar. Este listener es clave en iOS: si el
    // token APNs no estaba listo al arrancar, cuando por fin se resuelve, FCM
    // emite un token nuevo por aquí y lo registramos.
    _fm.onTokenRefresh.listen((token) {
      debugPrint('[WZ][push] onTokenRefresh → $token');
      _ultimoToken = token;
      final uid = _uidActual;
      if (uid != null) {
        _api.registrarFcmToken(uid: uid, token: token, platform: _plataforma());
      }
    });
  }

  Future<void> _mostrarLocal(RemoteMessage msg) async {
    final n = msg.notification;
    // Solo mostramos manualmente si trae bloque de notificación (título/cuerpo).
    if (n == null) return;

    const androidDetails = AndroidNotificationDetails(
      _canalId,
      _canalNombre,
      channelDescription: _canalDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _local.show(
      msg.hashCode,
      n.title ?? 'WarZero',
      n.body ?? '',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: msg.data['lobbyId'] as String?,
    );
  }

  void _abrirDesdeMensaje(RemoteMessage msg) {
    final lobbyId = msg.data['lobbyId'] as String?;
    if (lobbyId != null && lobbyId.isNotEmpty) {
      onAbrirPartida?.call(lobbyId);
    }
  }

  // ── Registro del token contra el backend ───────────────────────────────────
  Future<void> _onAuthCambio(User? user) async {
    final nuevoUid = user?.uid;
    if (nuevoUid == _uidActual) return;

    // Logout: dar de baja el token del usuario anterior.
    final anterior = _uidActual;
    if (anterior != null && _ultimoToken != null) {
      await _api.eliminarFcmToken(uid: anterior, token: _ultimoToken!);
    }

    _uidActual = nuevoUid;
    // Nuevo usuario → reiniciar el contador de reintentos y registrar.
    _reintentos = 0;
    _timerReintento?.cancel();
    if (nuevoUid != null) {
      await _registrarTokenActual(nuevoUid);
    }
  }

  Future<void> _registrarTokenActual(String uid) async {
    try {
      // En iOS hay que asegurar el token APNs ANTES de pedir el de FCM. Puede
      // no estar listo justo al arrancar → reintentar con backoff.
      if (!kIsWeb && Platform.isIOS) {
        final apns = await _obtenerApnsTokenConReintentos();
        if (apns == null || apns.isEmpty) {
          debugPrint(
              '[WZ][push] APNs token NULL tras reintentos. iOS no se ha '
              'registrado en APNs → no habrá token FCM. Revisa en Xcode la '
              'capability "Push Notifications" y el entitlement aps-environment, '
              'el provisioning con push, y la clave APNs (.p8) en Firebase. '
              'Reintentando en segundo plano…');
          _programarReintento(uid);
          return;
        }
        debugPrint('[WZ][push] APNs token OK: $apns');
      }

      final token = await _fm.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[WZ][push] token FCM nulo (reprogramando reintento)');
        _programarReintento(uid);
        return;
      }

      _ultimoToken = token;
      debugPrint('[WZ][push] FCM token=$token'); // ← para pruebas de consola
      await _api.registrarFcmToken(
        uid: uid,
        token: token,
        platform: _plataforma(),
      );
      debugPrint('[WZ][push] token registrado para uid=$uid');

      // Éxito: limpiar reintentos pendientes.
      _reintentos = 0;
      _timerReintento?.cancel();
    } catch (e) {
      debugPrint('[WZ][push] registrar token falló: $e');
      _programarReintento(uid);
    }
  }

  /// Pide el token APNs varias veces con backoff creciente. Devuelve el token o
  /// null si sigue sin estar disponible tras los intentos.
  Future<String?> _obtenerApnsTokenConReintentos({int intentos = 5}) async {
    for (var i = 0; i < intentos; i++) {
      try {
        final apns = await _fm.getAPNSToken();
        if (apns != null && apns.isNotEmpty) return apns;
      } catch (e) {
        debugPrint('[WZ][push] getAPNSToken lanzó (intento ${i + 1}): $e');
      }
      debugPrint('[WZ][push] APNs aún no listo (intento ${i + 1}/$intentos)…');
      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    return null;
  }

  /// Reprograma un intento de registro más adelante (fallo transitorio o token
  /// APNs que aún no estaba listo). Limitado a [_maxReintentos] para no insistir
  /// indefinidamente si el problema es de configuración.
  void _programarReintento(String uid) {
    if (_reintentos >= _maxReintentos) {
      debugPrint('[WZ][push] agotados los reintentos de registro para uid=$uid. '
          'Si es iOS, casi seguro falta config de APNs (capability/entitlement '
          'o clave APNs en Firebase).');
      return;
    }
    _reintentos++;
    final segundos = 3 * _reintentos;
    _timerReintento?.cancel();
    _timerReintento = Timer(Duration(seconds: segundos), () {
      // El usuario podría haber cambiado entretanto.
      if (_uidActual == uid) {
        debugPrint('[WZ][push] reintento $_reintentos de registro (uid=$uid)…');
        _registrarTokenActual(uid);
      }
    });
  }

  String _plataforma() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'desconocida';
  }
}