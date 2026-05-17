// lib/models/efecto_estado.dart

/// Tipos de efecto persistente que pueden estar activos sobre una celda o
/// sobre una carta.
enum EfectoTipoEstado {
  veneno,
  // futuro: paralisis, regeneracion, escudo...
}

extension EfectoTipoEstadoExt on EfectoTipoEstado {
  String get nombre {
    switch (this) {
      case EfectoTipoEstado.veneno:
        return 'Veneno';
    }
  }

  String get icon {
    switch (this) {
      case EfectoTipoEstado.veneno:
        return '☠';
    }
  }

  static EfectoTipoEstado fromName(String? name) {
    for (final t in EfectoTipoEstado.values) {
      if (t.name == name) return t;
    }
    return EfectoTipoEstado.veneno;
  }
}

/// Un efecto persistente activo sobre una celda o una carta.
///
/// USO EN CELDAS
///   Se guarda en `Map<String, List<EfectoActivo>> efectosCelda` dentro del
///   estado de la partida. Mientras la celda tenga un veneno con
///   `turnosRestantes > 0`, cualquier carta que esté o entre recibe el efecto.
///
/// USO EN CARTAS
///   Se guarda en el campo `Efectos: [...]` del Map de la carta dentro del
///   tablero. La carta arrastra el efecto aunque se mueva. El servicio de
///   combate consulta estos efectos para reducir la defensa de la carta.
class EfectoActivo {
  final EfectoTipoEstado tipo;
  final int turnosRestantes;

  /// Magnitud del efecto. Para veneno: defensa que resta.
  final int magnitud;

  /// Uid del jugador que originó el efecto. Útil para logs y para evitar
  /// stackear infinitos venenos del mismo origen (se refresca duración).
  final String origenUid;

  const EfectoActivo({
    required this.tipo,
    required this.turnosRestantes,
    required this.magnitud,
    required this.origenUid,
  });

  bool get expirado => turnosRestantes <= 0;

  EfectoActivo copyWith({
    EfectoTipoEstado? tipo,
    int? turnosRestantes,
    int? magnitud,
    String? origenUid,
  }) =>
      EfectoActivo(
        tipo: tipo ?? this.tipo,
        turnosRestantes: turnosRestantes ?? this.turnosRestantes,
        magnitud: magnitud ?? this.magnitud,
        origenUid: origenUid ?? this.origenUid,
      );

  /// Devuelve una copia con `turnosRestantes - 1`. Usado al cerrar cada turno.
  EfectoActivo decrementar() => copyWith(turnosRestantes: turnosRestantes - 1);

  Map<String, dynamic> toMap() => {
        'tipo': tipo.name,
        'turnosRestantes': turnosRestantes,
        'magnitud': magnitud,
        'origenUid': origenUid,
      };

  factory EfectoActivo.fromMap(Map<String, dynamic> d) => EfectoActivo(
        tipo: EfectoTipoEstadoExt.fromName(d['tipo'] as String?),
        turnosRestantes: (d['turnosRestantes'] as num?)?.toInt() ?? 0,
        magnitud: (d['magnitud'] as num?)?.toInt() ?? 0,
        origenUid: d['origenUid'] as String? ?? '',
      );
}
