// lib/models/trofeo_model.dart

/// Un TROFEO es un coleccionable de perfil que se consigue a lo largo de las
/// partidas al alcanzar cierto valor en una MÉTRICA acumulada del jugador.
///
/// El catálogo lo definen los editores (colección Firestore `Trofeos`) y el
/// backend devuelve, por jugador, cada trofeo activo con su estado `conseguido`.
class TrofeoModel {
  final String id;
  final String nombre;
  final String descripcion;

  /// Emoji del trofeo (por defecto 🏆 si el editor no puso ninguno).
  final String icono;

  /// Clave de la métrica evaluada (ver [TrofeoMetrica]).
  final String metrica;

  /// Operador de comparación: ">=" (por defecto), ">", "==", "<=", "<".
  final String operador;

  /// Valor objetivo a alcanzar.
  final int objetivo;

  /// Orden de presentación.
  final int orden;

  /// ¿Lo ha conseguido el jugador consultado?
  final bool conseguido;

  const TrofeoModel({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
    required this.metrica,
    required this.operador,
    required this.objetivo,
    required this.orden,
    required this.conseguido,
  });

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  factory TrofeoModel.fromMap(Map<String, dynamic> d) {
    final icono = (d['icono'] ?? d['Icono'] ?? '').toString().trim();
    return TrofeoModel(
      id: (d['id'] ?? '').toString(),
      nombre: (d['nombre'] ?? d['Nombre'] ?? '').toString(),
      descripcion: (d['descripcion'] ?? d['Descripcion'] ?? '').toString(),
      icono: icono.isEmpty ? '🏆' : icono,
      metrica: (d['metrica'] ?? d['Metrica'] ?? '').toString(),
      operador: (d['operador'] ?? d['Operador'] ?? '>=').toString(),
      objetivo: _int(d['objetivo'] ?? d['Objetivo']),
      orden: _int(d['orden'] ?? d['Orden']),
      conseguido: d['conseguido'] == true,
    );
  }

  /// Texto legible de la condición, p. ej. "Gana 100 combates".
  String get condicionTexto {
    final m = TrofeoMetrica.porClave(metrica);
    final etiqueta = m?.label ?? metrica;
    final op = operador == '>=' ? 'Alcanza' : operador;
    if (operador == '>=') return '$etiqueta: $objetivo';
    return '$etiqueta $op $objetivo';
  }
}

/// Catálogo (cliente) de métricas disponibles para definir trofeos. DEBE
/// coincidir con `WarZeroTrofeos.MetricasValidas` del backend.
class TrofeoMetrica {
  final String clave;
  final String label;
  final String icono;

  const TrofeoMetrica(this.clave, this.label, this.icono);

  static const List<TrofeoMetrica> todas = [
    TrofeoMetrica('victoriasCombate', 'Victorias de combate', '⚔️'),
    TrofeoMetrica('derrotasCombate', 'Derrotas de combate', '🛡️'),
    TrofeoMetrica('partidasGanadas', 'Partidas ganadas', '👑'),
    TrofeoMetrica('victoriasSinBots2', 'Victorias 2 jugadores sin bots', '👥'),
    TrofeoMetrica('victoriasSinBots4', 'Victorias 4 jugadores sin bots', '👥'),
    TrofeoMetrica('victoriasSinBots6', 'Victorias 6 jugadores sin bots', '👥'),
    TrofeoMetrica('victoriasSinBots8', 'Victorias 8 jugadores sin bots', '👥'),
    TrofeoMetrica('cuartelesConquistados', 'Cuarteles conquistados', '🏰'),
    TrofeoMetrica('nivel', 'Nivel alcanzado', '⭐'),
    TrofeoMetrica('experiencia', 'Experiencia total', '✨'),
    TrofeoMetrica('dinero', 'Oro acumulado', '🪙'),
  ];

  static TrofeoMetrica? porClave(String clave) {
    for (final m in todas) {
      if (m.clave == clave) return m;
    }
    return null;
  }
}
