// lib/services/pending_revert_store.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deuda de energía / especiales NO consolidada de un turno en curso, persistida
/// en disco para sobrevivir a que la app pase a segundo plano o el sistema
/// operativo la mate mientras el jugador tenía cartas desplegadas SIN cerrar el
/// turno.
///
/// ── Por qué existe ──────────────────────────────────────────────────────────
/// La energía se descuenta en el SERVIDOR de forma incremental al desplegar,
/// evolucionar o comprar (cada acción envía `energiesDelta: -coste`), pero el
/// tablero SOLO se persiste al cerrar el turno. Al salir a mitad de turno hay que
/// DEVOLVER esa energía al servidor con `deshacerTurno(...)`.
///
/// El bug que resuelve: ese reembolso se lanzaba como fire-and-forget justo
/// cuando el móvil se bloqueaba (`AppLifecycleState.paused`). El SO suspendía el
/// proceso antes de que la petición HTTP terminara, así que el reembolso se
/// perdía: el jugador reentraba con las cartas revertidas (nunca se persistieron)
/// PERO sin la energía ("bloqueé el móvil sin cerrar turno y perdí la energía y
/// las cartas no estaban en el tablero").
///
/// ── Cómo lo resuelve ────────────────────────────────────────────────────────
/// Se escribe la deuda en disco EN EL MOMENTO del gasto (con la app activa: es
/// fiable frente a suspensiones y cierres forzados) y se REINTENTA el reembolso
/// (`deshacerTurno`) al reentrar a la partida o al reanudar la app, cuando hay
/// red disponible. Guardas por `turno` + `cerradoPor` evitan reembolsar de más.
@immutable
class DeudaRevert {
  /// Turno en el que se contrajo la deuda (el turno abierto que se estaba
  /// jugando). Se usa como guarda: si al reentrar el turno del servidor ya no
  /// coincide, la deuda es de un turno pasado y no debe reembolsarse.
  final int turno;

  /// Energía revertible acumulada este turno (despliegues + compras +
  /// evoluciones ya descontados en el servidor).
  final int energia;

  /// IDs de cartas especiales compradas este turno (para desmarcarlas y poder
  /// recomprarlas tras el reembolso).
  final List<String> especiales;

  const DeudaRevert({
    required this.turno,
    required this.energia,
    this.especiales = const [],
  });

  /// True si no hay nada que reembolsar (ni energía ni especiales).
  bool get vacia => energia <= 0 && especiales.isEmpty;

  Map<String, dynamic> toJson() => {
        'turno': turno,
        'energia': energia,
        'especiales': especiales,
      };

  factory DeudaRevert.fromJson(Map<String, dynamic> j) => DeudaRevert(
        turno: (j['turno'] as num?)?.toInt() ?? 0,
        energia: (j['energia'] as num?)?.toInt() ?? 0,
        especiales:
            (j['especiales'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      );

  @override
  String toString() =>
      'DeudaRevert(turno: $turno, energia: $energia, especiales: $especiales)';
}

/// Almacén de deudas de reembolso pendientes, indexado por lobby (partida). Usa
/// SharedPreferences. Todas las operaciones son best-effort y NUNCA lanzan: un
/// fallo de almacenamiento no debe romper la partida.
class PendingRevertStore {
  const PendingRevertStore._();

  static const String _prefix = 'wz_deuda_revert_';

  static String _key(String lobbyId) => '$_prefix$lobbyId';

  /// Guarda la deuda del turno en curso para [lobbyId]. Si la deuda está vacía,
  /// borra cualquier registro previo (equivale a limpiar).
  static Future<void> guardar(String lobbyId, DeudaRevert deuda) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (deuda.vacia) {
        await p.remove(_key(lobbyId));
      } else {
        await p.setString(_key(lobbyId), jsonEncode(deuda.toJson()));
      }
    } catch (e) {
      debugPrint('[WZ][deuda] guardar falló (ignorado): $e');
    }
  }

  /// Lee la deuda pendiente para [lobbyId], o null si no hay ninguna.
  static Future<DeudaRevert?> leer(String lobbyId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(lobbyId));
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return DeudaRevert.fromJson(j);
    } catch (e) {
      debugPrint('[WZ][deuda] leer falló (ignorado): $e');
      return null;
    }
  }

  /// Borra la deuda pendiente para [lobbyId].
  static Future<void> limpiar(String lobbyId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(lobbyId));
    } catch (e) {
      debugPrint('[WZ][deuda] limpiar falló (ignorado): $e');
    }
  }
}
