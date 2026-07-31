// lib/models/alianza_estado.dart

/// Modelo del bloque `alianzas` del estado de partida (lo que devuelve el
/// backend en `estado.alianzas`). Parseo tolerante desde el mapa JSON.
///
///   alianzas: {
///     propuestas: [ { deUid, paraUid, turnos, turnoPropuesta } ],
///     activas:    [ { uidA, uidB, turnosRestantes } ],
///     traiciones: [ { traidorUid, victimaUid } ],
///     avisos:     [ { paraUid, tipo, deUid, turno } ]
///   }
class EstadoAlianzas {
  final Map<String, dynamic> raw;
  final List<PropuestaAlianza> propuestas;
  final List<AlianzaActiva> activas;
  final List<AvisoAlianza> avisos;

  const EstadoAlianzas({
    required this.raw,
    required this.propuestas,
    required this.activas,
    required this.avisos,
  });

  static const EstadoAlianzas vacio = EstadoAlianzas(
    raw: {},
    propuestas: [],
    activas: [],
    avisos: [],
  );

  factory EstadoAlianzas.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return vacio;
    List<Map<String, dynamic>> lst(String k) => ((m[k] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return EstadoAlianzas(
      raw: Map<String, dynamic>.from(m),
      propuestas: lst('propuestas').map(PropuestaAlianza.fromMap).toList(),
      activas: lst('activas').map(AlianzaActiva.fromMap).toList(),
      avisos: lst('avisos').map(AvisoAlianza.fromMap).toList(),
    );
  }

  /// Aliado ACTIVO de [uid] (o null si no tiene alianza activa).
  String? aliadoDe(String uid) {
    for (final a in activas) {
      if (a.uidA == uid) return a.uidB;
      if (a.uidB == uid) return a.uidA;
    }
    return null;
  }

  /// Alianza activa que involucra a [uid] (o null).
  AlianzaActiva? alianzaDe(String uid) {
    for (final a in activas) {
      if (a.uidA == uid || a.uidB == uid) return a;
    }
    return null;
  }

  /// Propuesta ENTRANTE pendiente para [uid] (la primera encontrada), o null.
  PropuestaAlianza? propuestaEntrantePara(String uid) {
    for (final p in propuestas) {
      if (p.paraUid == uid) return p;
    }
    return null;
  }

  /// Propuesta SALIENTE pendiente de [uid] (la primera encontrada), o null.
  PropuestaAlianza? propuestaSalienteDe(String uid) {
    for (final p in propuestas) {
      if (p.deUid == uid) return p;
    }
    return null;
  }

  bool tieneAlianzaActiva(String uid) => aliadoDe(uid) != null;

  List<AvisoAlianza> avisosPara(String uid) =>
      avisos.where((a) => a.paraUid == uid).toList();
}

class PropuestaAlianza {
  final String deUid;
  final String paraUid;
  final int turnos;
  final int turnoPropuesta;

  const PropuestaAlianza({
    required this.deUid,
    required this.paraUid,
    required this.turnos,
    required this.turnoPropuesta,
  });

  factory PropuestaAlianza.fromMap(Map<String, dynamic> m) => PropuestaAlianza(
        deUid: m['deUid']?.toString() ?? '',
        paraUid: m['paraUid']?.toString() ?? '',
        turnos: (m['turnos'] as num?)?.toInt() ?? 1,
        turnoPropuesta: (m['turnoPropuesta'] as num?)?.toInt() ?? 0,
      );

  /// Clave única para no repetir el mismo aviso/diálogo en cada sondeo.
  String get clave => '$deUid->$paraUid@$turnoPropuesta:$turnos';
}

class AlianzaActiva {
  final String uidA;
  final String uidB;
  final int turnosRestantes;

  const AlianzaActiva({
    required this.uidA,
    required this.uidB,
    required this.turnosRestantes,
  });

  factory AlianzaActiva.fromMap(Map<String, dynamic> m) => AlianzaActiva(
        uidA: m['uidA']?.toString() ?? '',
        uidB: m['uidB']?.toString() ?? '',
        turnosRestantes: (m['turnosRestantes'] as num?)?.toInt() ?? 0,
      );

  String otro(String uid) => uid == uidA ? uidB : uidA;
}

class AvisoAlianza {
  final String paraUid;

  /// "traicionado" | "alianza_terminada" | "aceptada" | "rechazada"
  final String tipo;
  final String deUid;
  final int turno;

  const AvisoAlianza({
    required this.paraUid,
    required this.tipo,
    required this.deUid,
    required this.turno,
  });

  factory AvisoAlianza.fromMap(Map<String, dynamic> m) => AvisoAlianza(
        paraUid: m['paraUid']?.toString() ?? '',
        tipo: m['tipo']?.toString() ?? '',
        deUid: m['deUid']?.toString() ?? '',
        turno: (m['turno'] as num?)?.toInt() ?? 0,
      );

  String get clave => '$paraUid:$tipo:$deUid@$turno';
}
