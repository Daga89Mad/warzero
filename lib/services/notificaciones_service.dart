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

    // Renovación del token → re-registrar.
    _fm.onTokenRefresh.listen((token) {
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
    if (nuevoUid != null) {
      await _registrarTokenActual(nuevoUid);
    }
  }

  Future<void> _registrarTokenActual(String uid) async {
    try {
      // En iOS conviene asegurar el token APNs antes de pedir el de FCM.
      if (!kIsWeb && Platform.isIOS) {
        await _fm.getAPNSToken();
      }
      final token = await _fm.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[WZ][push] token FCM nulo');
        return;
      }
      _ultimoToken = token;
      await _api.registrarFcmToken(
        uid: uid,
        token: token,
        platform: _plataforma(),
      );
      debugPrint('[WZ][push] token registrado para uid=$uid');
    } catch (e) {
      debugPrint('[WZ][push] registrar token falló: $e');
    }
  }

  String _plataforma() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'desconocida';
  }
}
