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
  ///
  /// El diálogo BLOQUEA la pantalla (no se cierra tocando fuera ni con el botón
  /// atrás) y, al aceptarlo, CIERRA la partida actual por completo antes de
  /// seguir: se retiran el diálogo, cualquier pantalla que hubiera encima de la
  /// partida (informe, revisión, cuartel…) y la propia partida. Después:
  ///   · victoria con parte siguiente → se crea y abre la siguiente parte
  ///     (1 → 2, 2 → 3);
  ///   · victoria en la última parte → se vuelve a la pantalla de la historia;
  ///   · derrota → REINTENTAR (vuelve a la parte 1) o SALIR.
  ///
  /// Antes se usaba `pushReplacement` desde el contexto de la partida: si el
  /// diálogo salía con el informe o la revisión del turno abiertos, se
  /// sustituía ESA pantalla y la partida anterior se quedaba viva por debajo.
  ///
  /// [context] debe ser el de la pantalla de juego (GameScreen).
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
    final turnosSup = (historia['turnosSupervivencia'] as num?)?.toInt() ?? 0;

    // Navigator y ruta de la PARTIDA, capturados ahora: tras cerrar la partida
    // su contexto deja de existir, pero el del Navigator sigue montado y sirve
    // para lanzar la siguiente parte.
    final nav = Navigator.of(context);
    final rutaPartida = ModalRoute.of(context);

    final Color fondo =
        gano ? const Color(0xFF0A1A05) : const Color(0xFF0A0A1A);
    final Color acento = gano ? _oro : _tenue;

    String titulo;
    String cuerpo;
    if (gano && esUltima) {
      titulo = '🏆 ¡ENHORABUENA!';
      cuerpo = 'Has completado las $partes partes.\n¡La historia es tuya!';
    } else if (gano) {
      titulo = '🎉 ¡ENHORABUENA!';
      final resistido = turnosSup > 0
          ? 'Has resistido los $turnosSup turnos del asedio.'
          : 'Has vencido esta batalla.';
      cuerpo = '$resistido\nParte $parte de $partes superada.\n'
          'Al aceptar comenzará la parte ${parte + 1}.';
    } else {
      titulo = '⚔ DERROTA';
      cuerpo =
          'Han conquistado tu cuartel.\nDebes empezar la historia de nuevo.';
    }

    // Cierra el diálogo, todo lo que haya encima de la partida y la partida.
    void cerrarPartida() {
      if (rutaPartida != null && rutaPartida.isActive) {
        nav.popUntil((r) => r == rutaPartida);
        if (nav.canPop()) nav.pop();
      } else if (nav.canPop()) {
        nav.pop(); // solo el diálogo
      }
    }

    // Cierra la partida y abre [id] en limpio desde la pantalla anterior.
    void cerrarYLanzar(String id) {
      cerrarPartida();
      final ctxNav = nav.context;
      if (!ctxNav.mounted) return;
      lanzarHistoria(ctxNav, uid: uid, historiaId: id);
    }

    final acciones = <Widget>[];
    if (gano && !esUltima && siguienteId.isNotEmpty) {
      acciones.add(_boton(context, 'ACEPTAR', acento, () {
        cerrarYLanzar(siguienteId);
      }));
    } else if (gano) {
      acciones.add(_boton(context, 'ACEPTAR', acento, cerrarPartida));
    } else {
      // Derrota: reiniciar desde la parte 1 de la historia. Como perder obliga a
      // empezar de cero, se reintenta la PRIMERA parte si la conocemos; si no,
      // esta misma batalla.
      final reinicioId = (historia['primeraParteId'] ?? historiaId).toString();
      acciones.add(_boton(context, 'REINTENTAR', const Color(0xFFC86050), () {
        cerrarYLanzar(reinicioId);
      }));
      acciones.add(_boton(context, 'SALIR', _tenue, cerrarPartida));
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => PopScope(
        // Bloqueante: ni tocando fuera ni con el botón atrás del sistema.
        canPop: false,
        child: AlertDialog(
          backgroundColor: fondo,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 16,
              color: acento,
              letterSpacing: 1.5,
            ),
          ),
          content: Text(
            cuerpo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 11,
              color: acento.withOpacity(0.85),
              height: 1.7,
            ),
          ),
          actionsAlignment: acciones.length > 1
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.center,
          actions: acciones,
        ),
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
