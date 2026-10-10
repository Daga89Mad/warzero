// lib/services/reto_service.dart
//
// Cliente del modo RETOS. Hay dos clases de reto (RetoCatalogo.cs):
//   • Reto de PARTIDA NORMAL: el servidor monta la partida (mapa, ejército y
//     bots fijos) y arranca EN CURSO. El reparto de energías, cuarteles y
//     manos lo hace el servidor en `entrar`, igual que en cualquier partida; y
//     los bots rivales son los mismos runners que rellenan salas públicas.
//   • Reto sobre el MOTOR DE HISTORIA (p. ej. «El duelo de Alexander»): el
//     servidor devuelve una batalla de historia (`estado.esHistoria`), y se
//     entra a la pantalla de juego con su config `historia`, igual que desde
//     el modo historia.
// En los dos casos aquí solo hay que pedirla (POST /warzero/reto/crear) y
// entrar a la pantalla de juego con el lobbyId devuelto.
//
// SALIR = ABANDONAR: igual que en el modo historia, salir de un reto lo da por
// perdido. La pantalla de juego llama a `abandonarReto` (POST
// /warzero/reto/abandonar): el servidor para los bots y borra la partida, así
// que un reto nunca queda "en curso" en la Sala de Guerra y cada intento
// empieza de cero. (Los retos sobre el motor de historia usan
// `HistoriaService.abandonarHistoria`, con el mismo efecto.)
//
// NOTA: se usa `http` directamente (con la baseUrl de WarZeroApi) para no tener
// que tocar warzero_api.dart. Si algún día hay más llamadas de retos, conviene
// moverlas allí junto al resto de la API.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../views/game_screen.dart';
import 'warzero_api.dart';

/// Un reto del catálogo, tal y como lo pinta la pantalla de retos. Los ids
/// tienen que coincidir con los de `RetoCatalogo` en el servidor.
class RetoInfo {
  /// Posición en la lista (1..N).
  final int numero;

  /// Id que viaja al servidor.
  final String id;

  final String titulo;
  final String descripcion;

  /// Etiquetas cortas para la ficha del reto (ejército, mapa, rivales…).
  final List<String> etiquetas;

  const RetoInfo({
    required this.numero,
    required this.id,
    required this.titulo,
    required this.descripcion,
    this.etiquetas = const [],
  });
}

/// Retos disponibles. El resto de huecos de la pantalla salen bloqueados.
const List<RetoInfo> kRetosDisponibles = [
  RetoInfo(
    numero: 1,
    id: 'resistencia_demoniaca',
    titulo: 'Resistencia demoníaca',
    descripcion: 'Tres ejércitos, un solo objetivo: tú.',
    etiquetas: ['⚓ Demonios', '🗺 Clásica 4J', '🤖 3 bots'],
  ),
  RetoInfo(
    numero: 2,
    id: 'resistencia_humana_8',
    titulo: 'Resistencia humana',
    descripcion: 'Siete ejércitos, un solo objetivo: tú.',
    etiquetas: ['🛡 Humanos', '🗺 Mapa 8J', '🤖 7 bots'],
  ),
  RetoInfo(
    numero: 3,
    id: 'duelo_alexander',
    titulo: 'El duelo de Alexander',
    descripcion: 'Eres Alexander. Alvaroth y Albariel vienen a por ti.',
    etiquetas: ['👁 Nefilim', '🗺 Monolito', '⚔ Duelo de generales'],
  ),
];

class RetoService {
  RetoService({WarZeroApi? api}) : _api = api ?? WarZeroApi();

  final WarZeroApi _api;

  static const _oro = Color(0xFFC8A860);

  static const Duration _timeout = Duration(seconds: 45);
  static const int _intentos = 3;

  /// Crea el reto [retoId] (siempre de cero) y entra a la partida.
  Future<void> lanzarReto(
    BuildContext context, {
    required String uid,
    required String retoId,
  }) async {
    if (uid.isEmpty) {
      _toast(context, 'Debes iniciar sesión para jugar.');
      return;
    }

    _mostrarLoader(context);

    Map<String, dynamic>? res;
    Object? error;
    try {
      await _api.despertar();
      res = await _crear(uid: uid, retoId: retoId);
    } catch (e) {
      error = e;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // cierra el loader

    final ok = res != null && res['ok'] == true;
    final lobbyId = res?['lobbyId'] as String?;
    if (!ok || lobbyId == null || lobbyId.isEmpty) {
      final msg =
          (res?['error'] ?? error ?? 'No se pudo iniciar el reto.').toString();
      _toast(context, msg);
      return;
    }

    final jugadores = (res!['maxJugadores'] as num?)?.toInt() ?? 4;

    // Reto sobre el motor de historia: se entra como a una batalla de
    // historia (2 jugadores y su config `historia`).
    final estado = (res['estado'] as Map?)?.cast<String, dynamic>();
    final historia = estado?['esHistoria'] == true || estado?['historia'] is Map
        ? (estado?['historia'] as Map?)?.cast<String, dynamic>()
        : null;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          localPlayerUid: uid,
          playerCount: historia != null ? 2 : jugadores,
          lobbyId: lobbyId,
          historia: historia,
          esReto: historia == null,
        ),
      ),
    );
  }

  // ── HTTP ──────────────────────────────────────────────────────────────────
  /// POST /warzero/reto/crear → { ok, lobbyId, maxJugadores, estado } (o
  /// { error } con 400, que se devuelve igual para poder mostrarlo).
  Future<Map<String, dynamic>?> _crear({
    required String uid,
    required String retoId,
  }) async {
    Object? ultimoError;
    for (int i = 1; i <= _intentos; i++) {
      try {
        final res = await http
            .post(
              Uri.parse('${_api.baseUrl}/warzero/reto/crear'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'uid': uid, 'retoId': retoId}),
            )
            .timeout(_timeout);
        debugPrint('[WZ][api] POST reto/crear status=${res.statusCode}');
        try {
          return jsonDecode(res.body) as Map<String, dynamic>;
        } catch (_) {
          throw Exception('reto/crear HTTP ${res.statusCode}: ${res.body}');
        }
      } on TimeoutException catch (e) {
        // Arranque en frío del servidor: se reintenta.
        ultimoError = e;
        debugPrint('[WZ][api] reto/crear intento $i: timeout');
      } catch (e) {
        ultimoError = e;
        debugPrint('[WZ][api] reto/crear intento $i falló: $e');
      }
      if (i < _intentos) {
        await Future.delayed(Duration(seconds: 2 * i));
      }
    }
    throw Exception('reto/crear sin respuesta tras $_intentos intentos: '
        '$ultimoError');
  }

  /// Abandona el reto [lobbyId] (salir por el menú, botón atrás, cerrar la
  /// app…): el servidor para sus bots y BORRA la partida (POST
  /// /warzero/reto/abandonar). Es "dispara y olvida": nunca lanza, para no
  /// bloquear la salida.
  Future<void> abandonarReto({
    required String uid,
    required String lobbyId,
  }) async {
    if (uid.isEmpty || lobbyId.isEmpty) return;
    try {
      final res = await http
          .post(
            Uri.parse('${_api.baseUrl}/warzero/reto/abandonar'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'uid': uid, 'lobbyId': lobbyId}),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[WZ][api] POST reto/abandonar status=${res.statusCode}');
    } catch (e) {
      debugPrint('[WZ][api] abandonarReto falló (ignorado): $e');
    }
  }

  // ── UI auxiliar ───────────────────────────────────────────────────────────
  void _mostrarLoader(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _oro),
              SizedBox(height: 16),
              Text(
                'PREPARANDO EL RETO…',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: _oro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}
