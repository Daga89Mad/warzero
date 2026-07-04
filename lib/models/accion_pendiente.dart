// lib/models/accion_pendiente.dart

/// Una acción declarada por un jugador durante su turno. Se serializa con los
/// movimientos del turno y se resuelve cuando el turno se cierra.
///
/// CICLO DE VIDA
///   1. Jugador pulsa carta de acción (mano) o "LANZAR HABILIDAD" (carta en
///      tablero) → entra en modo selección.
///   2. Tras seleccionar destino(s) (y carta origen si aplica), se crea una
///      `AccionPendiente` en estado local y se descuentan energías.
///   3. Al cerrar turno, las acciones se envían junto con los movimientos:
///         movimientosTurno.{uid}.acciones = [AccionPendiente.toMap(), ...]
///   4. Al resolver turno: `HabilidadService.aplicarAcciones` consume estas
///      acciones antes de combates.
class AccionPendiente {
  /// Id de la habilidad en `CatalogoHabilidades`.
  final int habilidadId;

  /// Uid del jugador que lanza.
  final String uid;

  /// Zona del jugador ('north', 'south'…). Útil para colorear en el Informe.
  final String zona;

  /// Celda origen desde la que se calculó el rango.
  ///   - Carta de acción jugada desde la mano  → obelisco del jugador.
  ///   - Habilidad de carta en el tablero      → coord de esa carta.
  final String origen;

  /// Celdas objetivo seleccionadas. Su tamaño debe coincidir con
  /// `Habilidad.numObjetivos` del id correspondiente.
  final List<String> objetivos;

  /// Solo para teletransporte: coord de la carta propia a mover.
  final String? cartaOrigenCoord;

  /// Solo para teletransporte: índice de la carta dentro de la celda origen
  /// (puede haber varias cartas apiladas).
  final int? cartaOrigenIndice;

  /// Solo para teletransporte: id de la `CartaModel` a mover. Permite al
  /// servidor localizar la carta exacta aunque los índices hayan cambiado
  /// (p. ej. al colocar otra carta en la misma celda antes de resolver).
  final String? cartaOrigenId;

  /// Solo para carta de acción jugada desde la mano: id de la `CartaModel`
  /// que se debe descartar de la mano después de aplicar el efecto.
  /// Si es null → es una habilidad de carta del tablero (no se descarta nada).
  final String? cartaAccionId;

  /// Turno en que se declaró la acción.
  final int turno;

  /// Coste en energías pagado al declarar la acción (se descuenta localmente
  /// y se sincroniza al cerrar turno).
  final int costePagado;

  const AccionPendiente({
    required this.habilidadId,
    required this.uid,
    required this.zona,
    required this.origen,
    required this.objetivos,
    required this.turno,
    this.cartaOrigenCoord,
    this.cartaOrigenIndice,
    this.cartaOrigenId,
    this.cartaAccionId,
    this.costePagado = 0,
  });

  // ── Serialización ─────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'habilidadId': habilidadId,
        'uid': uid,
        'zona': zona,
        'origen': origen,
        'objetivos': objetivos,
        'turno': turno,
        'costePagado': costePagado,
        if (cartaOrigenCoord != null) 'cartaOrigenCoord': cartaOrigenCoord,
        if (cartaOrigenIndice != null) 'cartaOrigenIndice': cartaOrigenIndice,
        if (cartaOrigenId != null) 'cartaOrigenId': cartaOrigenId,
        if (cartaAccionId != null) 'cartaAccionId': cartaAccionId,
      };

  factory AccionPendiente.fromMap(Map<String, dynamic> d) => AccionPendiente(
        habilidadId: (d['habilidadId'] as num?)?.toInt() ?? 0,
        uid: d['uid'] as String? ?? '',
        zona: d['zona'] as String? ?? '',
        origen: d['origen'] as String? ?? '',
        objetivos: (d['objetivos'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const [],
        turno: (d['turno'] as num?)?.toInt() ?? 0,
        costePagado: (d['costePagado'] as num?)?.toInt() ?? 0,
        cartaOrigenCoord: d['cartaOrigenCoord'] as String?,
        cartaOrigenIndice: (d['cartaOrigenIndice'] as num?)?.toInt(),
        cartaOrigenId: d['cartaOrigenId'] as String?,
        cartaAccionId: d['cartaAccionId'] as String?,
      );

  AccionPendiente copyWith({
    int? habilidadId,
    String? uid,
    String? zona,
    String? origen,
    List<String>? objetivos,
    String? cartaOrigenCoord,
    int? cartaOrigenIndice,
    String? cartaOrigenId,
    String? cartaAccionId,
    int? turno,
    int? costePagado,
  }) =>
      AccionPendiente(
        habilidadId: habilidadId ?? this.habilidadId,
        uid: uid ?? this.uid,
        zona: zona ?? this.zona,
        origen: origen ?? this.origen,
        objetivos: objetivos ?? this.objetivos,
        cartaOrigenCoord: cartaOrigenCoord ?? this.cartaOrigenCoord,
        cartaOrigenIndice: cartaOrigenIndice ?? this.cartaOrigenIndice,
        cartaOrigenId: cartaOrigenId ?? this.cartaOrigenId,
        cartaAccionId: cartaAccionId ?? this.cartaAccionId,
        turno: turno ?? this.turno,
        costePagado: costePagado ?? this.costePagado,
      );
}
