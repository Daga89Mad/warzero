// lib/models/trofeo_model.dart

/// Un TROFEO es un coleccionable de perfil. Se consigue de una de tres formas
/// (ver [TrofeoOrigen]):
///   · al alcanzar cierto valor en una MÉTRICA acumulada del jugador,
///   · al completar un RETO concreto,
///   · al completar una HISTORIA concreta.
///
/// El catálogo lo definen los editores (colección Firestore `Trofeos`) y el
/// backend devuelve, por jugador, cada trofeo activo con su estado `conseguido`.
class TrofeoModel {
  final String id;
  final String nombre;
  final String descripcion;

  /// Emoji del trofeo (por defecto 🏆 si el editor no puso ninguno).
  final String icono;

  /// Cómo se consigue: [TrofeoOrigen.metrica], [TrofeoOrigen.reto] o
  /// [TrofeoOrigen.historia].
  final String origen;

  /// Id del reto o de la historia (vacío en los de métrica).
  final String origenId;

  /// Etiqueta legible del reto/historia (la escribe el editor de trofeos).
  final String origenNombre;

  /// Clave de la métrica evaluada (ver [TrofeoMetrica]). Solo en los de métrica.
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
    this.origen = TrofeoOrigen.metrica,
    this.origenId = '',
    this.origenNombre = '',
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
      origen: TrofeoOrigen.normalizar(d['origen'] ?? d['Origen']),
      origenId: (d['origenId'] ?? d['OrigenId'] ?? '').toString(),
      origenNombre: (d['origenNombre'] ?? d['OrigenNombre'] ?? '').toString(),
      metrica: (d['metrica'] ?? d['Metrica'] ?? '').toString(),
      operador: (d['operador'] ?? d['Operador'] ?? '>=').toString(),
      objetivo: _int(d['objetivo'] ?? d['Objetivo']),
      orden: _int(d['orden'] ?? d['Orden']),
      conseguido: d['conseguido'] == true,
    );
  }

  /// Texto legible de la condición, p. ej. "Victorias de combate: 100" o
  /// "Completa el reto «Resistencia demoníaca»".
  String get condicionTexto => TrofeoOrigen.textoCondicion(
        origen: origen,
        origenNombre: origenNombre,
        metrica: metrica,
        operador: operador,
        objetivo: objetivo,
      );
}

/// Formas de conseguir un trofeo. Los valores DEBEN coincidir con
/// `WarZeroTrofeos.OrigenMetrica/OrigenReto/OrigenHistoria` del backend.
class TrofeoOrigen {
  static const String metrica = 'metrica';
  static const String reto = 'reto';
  static const String historia = 'historia';

  /// Valor guardado → origen válido. Ausente o desconocido = métrica (los
  /// trofeos creados antes de existir este campo son todos de métrica).
  static String normalizar(dynamic v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == reto || s == historia ? s : metrica;
  }

  /// Texto de la condición, compartido por el perfil y el editor.
  static String textoCondicion({
    required String origen,
    required String origenNombre,
    required String metrica,
    required String operador,
    required int objetivo,
  }) {
    final nombre = origenNombre.trim();
    switch (origen) {
      case reto:
        return nombre.isEmpty
            ? 'Completa un reto'
            : 'Completa el reto «$nombre»';
      case historia:
        return nombre.isEmpty
            ? 'Completa una historia'
            : 'Completa la historia $nombre';
    }
    final m = TrofeoMetrica.porClave(metrica);
    final etiqueta = m?.label ?? metrica;
    if (operador == '>=') return '$etiqueta: $objetivo';
    return '$etiqueta $operador $objetivo';
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
