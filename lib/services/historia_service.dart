// lib/services/historia_service.dart
//
// Cliente del MODO HISTORIA (Opción B). Se encarga de:
//   • lanzarHistoria(): crear (o reiniciar) una batalla en el servidor
//     (POST /warzero/historia/crear) y navegar a la partida ya montada.
//   • mostrarFinHistoria(): diálogo de fin de una batalla de historia, con
//     victoria (→ parte siguiente / historia completada) o derrota
//     (→ reintentar / salir). Sustituye al flujo PvP de puntuaciones/recompensas.
//
// La partida es una `Partidas/{id}` real (misma pantalla de juego que el PvP);
// lo único distinto es la config de historia, que viaja a GameScreen por el
// parámetro `historia` y decide el HUD de objetivo y este diálogo de fin.

import 'package:flutter/material.dart';

import '../views/game_screen.dart';
import 'warzero_api.dart';

class HistoriaService {
  HistoriaService({WarZeroApi? api}) : _api = api ?? WarZeroApi();

  final WarZeroApi _api;

  static const _oro = Color(0xFFC8A860);
  static const _tenue = Color(0xFF506070);

  /// Crea (o reinicia) la batalla [historiaId] y entra a la partida.
  ///
  /// Muestra un loader mientras el servidor la monta. Si [reemplazar] es true,
  /// sustituye la pantalla actual (se usa al encadenar a la siguiente parte o al
  /// reintentar tras perder, para no apilar partidas); si es false, la apila
  /// (entrada normal desde la lista de historias).
  Future<void> lanzarHistoria(
    BuildContext context, {
    required String uid,
    required String historiaId,
    bool reemplazar = false,
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
      res = await _api.crearHistoria(uid: uid, historiaId: historiaId);
    } catch (e) {
      error = e;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // cierra el loader

    final ok = res != null && res['ok'] == true;
    final lobbyId = res?['lobbyId'] as String?;
    if (!ok || lobbyId == null || lobbyId.isEmpty) {
      final msg = (res?['error'] ?? error ?? 'No se pudo iniciar la batalla.')
          .toString();
      _toast(context, msg);
      return;
    }

    final estado = (res!['estado'] as Map?)?.cast<String, dynamic>();
    final historia = (estado?['historia'] as Map?)?.cast<String, dynamic>();

    final route = MaterialPageRoute<void>(
      builder: (_) => GameScreen(
        localPlayerUid: uid,
        playerCount: 2,
        lobbyId: lobbyId,
        historia: historia,
      ),
    );
    if (reemplazar) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  /// Diálogo de fin de una batalla de historia.
  ///
  /// [gano] = el jugador ganó (sobrevivió los turnos o conquistó al bot).
  /// Según sea victoria/derrota y si quedan partes, ofrece continuar, reintentar
  /// o salir. Debe llamarse con `barrierDismissible: false` implícito (lo es).
  void mostrarFinHistoria(
    BuildContext context, {
    required Map<String, dynamic> historia,
    required bool gano,
    required String uid,
  }) {
    final historiaId = (historia['id'] ?? '').toString();
    final siguienteId = (historia['siguienteId'] ?? '').toString();
    final esUltima = historia['esUltimaParte'] == true;
    final parte = (historia['parte'] as num?)?.toInt() ?? 1;
    final partes = (historia['partes'] as num?)?.toInt() ?? 1;

    final Color fondo =
        gano ? const Color(0xFF0A1A05) : const Color(0xFF0A0A1A);
    final Color acento = gano ? _oro : _tenue;

    String titulo;
    String cuerpo;
    if (gano && esUltima) {
      titulo = '🏆 ¡HISTORIA COMPLETADA!';
      cuerpo = 'Has superado las $partes partes.\n¡La historia es tuya!';
    } else if (gano) {
      titulo = '🛡 ¡PARTE $parte SUPERADA!';
      cuerpo =
          'Has aguantado el asedio.\nTe espera la parte ${parte + 1} de $partes.';
    } else {
      titulo = '⚔ DERROTA';
      cuerpo =
          'Han conquistado tu cuartel.\nDebes empezar la historia de nuevo.';
    }

    // Acciones según el resultado.
    final acciones = <Widget>[];
    void volverAlMenu() => Navigator.of(context).popUntil((r) => r.isFirst);

    if (gano && !esUltima && siguienteId.isNotEmpty) {
      acciones.add(_boton(context, 'SIGUIENTE PARTE', acento, () {
        Navigator.of(context).pop();
        lanzarHistoria(context,
            uid: uid, historiaId: siguienteId, reemplazar: true);
      }));
      acciones.add(_boton(context, 'SALIR', _tenue, () {
        Navigator.of(context).pop();
        volverAlMenu();
      }));
    } else if (gano) {
      acciones.add(_boton(context, 'VOLVER', acento, () {
        Navigator.of(context).pop();
        volverAlMenu();
      }));
    } else {
      // Derrota: reiniciar desde la parte 1 de la historia. Como perder obliga a
      // empezar de cero, se reintenta la PRIMERA parte si la conocemos; si no,
      // esta misma batalla.
      final reinicioId = (historia['primeraParteId'] ?? historiaId).toString();
      acciones.add(_boton(context, 'REINTENTAR', const Color(0xFFC86050), () {
        Navigator.of(context).pop();
        lanzarHistoria(context,
            uid: uid, historiaId: reinicioId, reemplazar: true);
      }));
      acciones.add(_boton(context, 'SALIR', _tenue, () {
        Navigator.of(context).pop();
        volverAlMenu();
      }));
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: fondo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          titulo,
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 14,
            color: acento,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          cuerpo,
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 10,
            color: acento.withOpacity(0.85),
            height: 1.7,
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: acciones,
      ),
    );
  }

  // ── UI auxiliar ──────────────────────────────────────────────────────────
  Widget _boton(
      BuildContext context, String texto, Color color, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: 10,
          letterSpacing: 1,
          color: color,
        ),
      ),
    );
  }

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
                'PREPARANDO BATALLA…',
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
