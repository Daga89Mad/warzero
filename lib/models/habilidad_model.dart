// lib/models/habilidad_model.dart

// ─────────────────────────────────────────────────────────────
// RANGO DE OBJETIVO
// ─────────────────────────────────────────────────────────────

/// Tipo de rango: cómo se determinan las celdas elegibles como objetivo.
enum RangoTipo {
  /// Celdas ortogonalmente adyacentes al origen (4 vecinas si son válidas).
  frontera,

  /// Celdas alcanzables contando ≤ N pasos ortogonales desde el origen.
  /// Se calcula por BFS Manhattan SIN consultar terreno (es un rango de
  /// habilidad, no un movimiento físico).
  radio,

  /// Cualquier celda del tablero (excluido siempre el propio origen).
  cualquiera,

  /// Solo la propia celda de origen (donde se marca/lanza).
  propia,
}

class RangoHabilidad {
  final RangoTipo tipo;

  /// Distancia máxima en pasos ortogonales (solo relevante para [RangoTipo.radio]).
  final int distancia;

  const RangoHabilidad.frontera()
      : tipo = RangoTipo.frontera,
        distancia = 1;

  const RangoHabilidad.radioN(this.distancia) : tipo = RangoTipo.radio;

  const RangoHabilidad.cualquiera()
      : tipo = RangoTipo.cualquiera,
        distancia = 0;

  const RangoHabilidad.propia()
      : tipo = RangoTipo.propia,
        distancia = 0;

  String get label {
    switch (tipo) {
      case RangoTipo.frontera:
        return 'Cercano (adyacente)';
      case RangoTipo.radio:
        return 'Medio (radio $distancia)';
      case RangoTipo.cualquiera:
        return 'Lejano (cualquiera)';
      case RangoTipo.propia:
        return 'Cercano (misma celda)';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// EFECTO
// ─────────────────────────────────────────────────────────────

enum EfectoTipo {
  /// Al resolver el turno, destruye cualquier carta en la celda objetivo.
  /// No afecta al cuartel general como estructura, solo a las cartas que estén
  /// en esa celda en el momento de la resolución.
  disparo,

  /// Mueve una carta del jugador desde su celda actual a la celda objetivo.
  /// Suele ir acompañado de `excluyeCG=true` para no permitir colocar en CG.
  teletransporte,

  /// Marca la celda como envenenada durante N turnos y aplica el efecto a las
  /// cartas que estén o entren en la celda durante esa duración.
  /// Las cartas envenenadas pierden [defensaReducida] de defensa durante el
  /// resto de la duración (la carta arrastra el efecto aunque se mueva).
  veneno,

  /// Marca la celda como paralizada durante N turnos. Las cartas que estén o
  /// entren en la celda durante esa duración no pueden moverse hasta que el
  /// efecto expire (la carta arrastra el efecto aunque cambie de celda).
  paralisis,

  /// Marca la celda como escudada durante N turnos. Las cartas del LANZADOR
  /// que estén o entren en la celda ganan [defensaReducida] de defensa extra
  /// (el mismo campo se reutiliza como magnitud; aquí SUMA en vez de restar).
  escudo,
}

class EfectoHabilidad {
  final EfectoTipo tipo;

  /// Solo para veneno: cuánta defensa se resta a la carta afectada.
  final int defensaReducida;

  /// Solo para veneno: cuántos turnos dura el efecto.
  final int duracionTurnos;

  const EfectoHabilidad.disparo()
      : tipo = EfectoTipo.disparo,
        defensaReducida = 0,
        duracionTurnos = 0;

  const EfectoHabilidad.teletransporte()
      : tipo = EfectoTipo.teletransporte,
        defensaReducida = 0,
        duracionTurnos = 0;

  const EfectoHabilidad.veneno({
    this.defensaReducida = 3,
    this.duracionTurnos = 3,
  }) : tipo = EfectoTipo.veneno;

  const EfectoHabilidad.paralisis({
    this.duracionTurnos = 3,
  })  : tipo = EfectoTipo.paralisis,
        defensaReducida = 0;

  const EfectoHabilidad.escudo({
    this.defensaReducida = 3,
    this.duracionTurnos = 3,
  }) : tipo = EfectoTipo.escudo;
}

// ─────────────────────────────────────────────────────────────
// HABILIDAD
// ─────────────────────────────────────────────────────────────

/// Habilidad genérica reutilizable. Se identifica por [id] en el catálogo.
///
/// Tanto las cartas con `CondicionCarta.accion` como las cartas normales con
/// `idHabilidad > 0` resuelven su efecto mirando este catálogo: la lógica de
/// rango, efecto y restricciones es idéntica. Lo único que cambia es el
/// **origen** desde el que se calcula el rango:
///   - Carta de acción → origen = obelisco (cuartel general) del jugador.
///   - Habilidad de carta → origen = celda donde está la carta.
class Habilidad {
  final int id;
  final String nombre;
  final String descripcion;
  final String icon;

  final RangoHabilidad rango;
  final EfectoHabilidad efecto;

  /// Si true, los cuarteles generales no son objetivos válidos.
  final bool excluyeCG;

  /// Número de celdas objetivo a seleccionar (≥ 1).
  final int numObjetivos;

  /// Solo aplica a teletransporte: requiere que el jugador seleccione además
  /// una carta propia (origen del teletransporte) además del destino.
  final bool requiereCartaPropia;

  const Habilidad({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icon,
    required this.rango,
    required this.efecto,
    this.excluyeCG = false,
    this.numObjetivos = 1,
    this.requiereCartaPropia = false,
  });
}

// ─────────────────────────────────────────────────────────────
// CATÁLOGO
// ─────────────────────────────────────────────────────────────

/// Catálogo central de habilidades. La clave es el `id` que se asigna en
/// `CartaModel.idHabilidad`.
///
/// IDs reservados:
///   0       → sin habilidad
///   1, 2, 3 → disparo (cercano, medio, lejano)
///   4, 5    → teletransporte (medio, lejano) ← invertido a propósito
///   6, 7, 8 → veneno (cercano, medio, lejano)
///   9, 10, 11 → parálisis (cercano, medio, lejano)
///   12, 13, 14 → escudo (propia, adyacente, lejano)
///   15+      → reservado (futuras)
class CatalogoHabilidades {
  CatalogoHabilidades._();

  static const Map<int, Habilidad> _catalogo = {
    // ── DISPARO ────────────────────────────────────────────
    1: Habilidad(
      id: 1,
      nombre: 'Disparo cercano',
      descripcion:
          'Dispara a una celda adyacente al origen. Al resolver el turno '
          'cualquier carta en esa celda queda derrotada.',
      icon: '🎯',
      rango: RangoHabilidad.frontera(),
      efecto: EfectoHabilidad.disparo(),
    ),
    2: Habilidad(
      id: 2,
      nombre: 'Disparo medio',
      descripcion:
          'Dispara a una celda dentro de un radio de 7 desde el origen. '
          'Al resolver el turno cualquier carta en esa celda queda derrotada.',
      icon: '🎯',
      rango: RangoHabilidad.radioN(7),
      efecto: EfectoHabilidad.disparo(),
    ),
    3: Habilidad(
      id: 3,
      nombre: 'Disparo lejano',
      descripcion:
          'Dispara a cualquier celda del mapa. Al resolver el turno cualquier '
          'carta en esa celda queda derrotada.',
      icon: '🎯',
      rango: RangoHabilidad.cualquiera(),
      efecto: EfectoHabilidad.disparo(),
    ),

    // ── TELETRANSPORTE (invertido a propósito) ─────────────
    4: Habilidad(
      id: 4,
      nombre: 'Teletransporte medio',
      descripcion:
          'Mueve una de tus cartas a cualquier celda del mapa, excepto '
          'cuarteles generales.',
      icon: '✨',
      rango: RangoHabilidad.cualquiera(),
      efecto: EfectoHabilidad.teletransporte(),
      excluyeCG: true,
      requiereCartaPropia: true,
    ),
    5: Habilidad(
      id: 5,
      nombre: 'Teletransporte lejano',
      descripcion:
          'Mueve una de tus cartas a una celda dentro de un radio de 7 desde '
          'el origen, excepto cuarteles generales.',
      icon: '✨',
      rango: RangoHabilidad.radioN(7),
      efecto: EfectoHabilidad.teletransporte(),
      excluyeCG: true,
      requiereCartaPropia: true,
    ),

    // ── VENENO ─────────────────────────────────────────────
    6: Habilidad(
      id: 6,
      nombre: 'Veneno cercano',
      descripcion:
          'Envenena dos celdas adyacentes al origen. Durante 3 turnos las '
          'cartas en esas celdas (o que entren después) pierden 3 de defensa. '
          'La celda permanece envenenada los 3 turnos.',
      icon: '☠',
      rango: RangoHabilidad.frontera(),
      efecto: EfectoHabilidad.veneno(),
      numObjetivos: 2,
    ),
    7: Habilidad(
      id: 7,
      nombre: 'Veneno medio',
      descripcion:
          'Envenena una celda dentro de un radio de 7 desde el origen, '
          'excepto cuarteles generales. Durante 3 turnos las cartas en ella '
          '(o que entren después) pierden 3 de defensa.',
      icon: '☠',
      rango: RangoHabilidad.radioN(7),
      efecto: EfectoHabilidad.veneno(),
      excluyeCG: true,
    ),
    8: Habilidad(
      id: 8,
      nombre: 'Veneno lejano',
      descripcion:
          'Envenena cualquier celda del mapa. Durante 3 turnos las cartas en '
          'ella (o que entren después) pierden 3 de defensa.',
      icon: '☠',
      rango: RangoHabilidad.cualquiera(),
      efecto: EfectoHabilidad.veneno(),
    ),

    // ── PARÁLISIS ──────────────────────────────────────────
    9: Habilidad(
      id: 9,
      nombre: 'Parálisis cercana',
      descripcion:
          'Paraliza una celda adyacente al origen. Durante 3 turnos las cartas '
          'en esa celda (o que entren) no pueden moverse.',
      icon: '⏱',
      rango: RangoHabilidad.frontera(),
      efecto: EfectoHabilidad.paralisis(),
    ),
    10: Habilidad(
      id: 10,
      nombre: 'Parálisis media',
      descripcion:
          'Paraliza una celda dentro de un radio de 7 desde el origen, excepto '
          'cuarteles. Durante 3 turnos las cartas en ella (o que entren) no '
          'pueden moverse.',
      icon: '⏱',
      rango: RangoHabilidad.radioN(7),
      efecto: EfectoHabilidad.paralisis(),
      excluyeCG: true,
    ),
    11: Habilidad(
      id: 11,
      nombre: 'Parálisis lejana',
      descripcion:
          'Paraliza cualquier celda del mapa. Durante 3 turnos las cartas en '
          'ella (o que entren) no pueden moverse.',
      icon: '⏱',
      rango: RangoHabilidad.cualquiera(),
      efecto: EfectoHabilidad.paralisis(),
    ),

    // ── ESCUDO ─────────────────────────────────────────────
    12: Habilidad(
      id: 12,
      nombre: 'Escudo cercano',
      descripcion:
          'Escuda la propia celda de origen. Durante 3 turnos tus cartas en '
          'ella (o que entren) ganan 3 de defensa.',
      icon: '🛡',
      rango: RangoHabilidad.propia(),
      efecto: EfectoHabilidad.escudo(),
    ),
    13: Habilidad(
      id: 13,
      nombre: 'Escudo medio',
      descripcion:
          'Escuda una celda adyacente al origen. Durante 3 turnos tus cartas '
          'en ella (o que entren) ganan 3 de defensa.',
      icon: '🛡',
      rango: RangoHabilidad.frontera(),
      efecto: EfectoHabilidad.escudo(),
    ),
    14: Habilidad(
      id: 14,
      nombre: 'Escudo lejano',
      descripcion:
          'Escuda cualquier celda del mapa. Durante 3 turnos tus cartas en '
          'ella (o que entren) ganan 3 de defensa.',
      icon: '🛡',
      rango: RangoHabilidad.cualquiera(),
      efecto: EfectoHabilidad.escudo(),
    ),
  };

  /// Devuelve la habilidad asociada al id, o null si no existe.
  static Habilidad? get(int id) => _catalogo[id];

  /// True si el id tiene una habilidad registrada.
  static bool tieneHabilidad(int id) => id > 0 && _catalogo.containsKey(id);

  /// Lista completa de habilidades disponibles (para tools / editor).
  static List<Habilidad> get todas => _catalogo.values.toList(growable: false);
}
