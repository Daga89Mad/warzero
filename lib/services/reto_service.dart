// lib/services/reto_service.dart
//
// Cliente del modo RETOS. Un reto es una partida normal que el servidor monta ya
// hecha (mapa, ejército y bots fijos) y que arranca EN CURSO, así que aquí solo
// hay que:
//   • pedirla (POST /warzero/reto/crear),
//   • y entrar a la pantalla de juego de siempre con el lobbyId devuelto.
//
// El reparto de energías, cuarteles y manos lo hace el servidor en `entrar`,
// igual que en cualquier partida; y los bots rivales son los mismos runners que
// rellenan salas públicas, con su dificultad y su estilo.
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
];

class RetoService {
  RetoService({WarZeroApi? api}) : _api = api ?? WarZeroApi();

  final WarZeroApi _api;

  static const _oro = Color(0xFFC8A860);

  static const Duration _timeout = Duration(seconds: 45);
  static const int _intentos = 3;

  /// Crea (o reanuda) el reto [retoId] y entra a la partida.
  ///
  /// Si el jugador dejó un intento a medias, el servidor devuelve ESA partida en
  /// vez de reiniciarla: se vuelve justo donde lo dejó.
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

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          localPlayerUid: uid,
          playerCount: jugadores,
          lobbyId: lobbyId,
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
