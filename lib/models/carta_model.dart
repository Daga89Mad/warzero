// lib/models/carta_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────
// ENUM CONDICIÓN
// ─────────────────────────────────────────────────────────────
/// Define el comportamiento especial de la carta en el juego.
///
/// Se almacena como int en Firestore (campo `Condicion`).
///   0 → Básica
///   1 → Evolución
///   3 → Estática
///   4 → Acción
enum CondicionCarta {
  /// Carta normal, sin restricciones.
  basica,

  /// No se reparte al final de turno ni se puede añadir a un mazo.
  /// Solo sirve como destino de evolución de una carta básica.
  evolucion,

  /// Movimiento fijo 0. Solo se puede colocar en una celda donde el
  /// jugador ya tenía una carta del turno anterior (no vale una carta
  /// movida en el turno actual). No se puede mover tras colocarse.
  estatica,

  /// Reservada para futuro uso.
  accion,
}

extension CondicionCartaExt on CondicionCarta {
  /// Valor numérico que se guarda en Firestore.
  int get value {
    switch (this) {
      case CondicionCarta.basica:
        return 0;
      case CondicionCarta.evolucion:
        return 1;
      case CondicionCarta.estatica:
        return 3;
      case CondicionCarta.accion:
        return 4;
    }
  }

  /// Nombre para la UI.
  String get label {
    switch (this) {
      case CondicionCarta.basica:
        return 'Básica';
      case CondicionCarta.evolucion:
        return 'Evolución';
      case CondicionCarta.estatica:
        return 'Estática';
      case CondicionCarta.accion:
        return 'Acción';
    }
  }

  /// Icono corto para chips.
  String get icon {
    switch (this) {
      case CondicionCarta.basica:
        return '⚔️';
      case CondicionCarta.evolucion:
        return '🔄';
      case CondicionCarta.estatica:
        return '🏰';
      case CondicionCarta.accion:
        return '⚡';
    }
  }

  /// Color temático para la UI.
  int get colorValue {
    switch (this) {
      case CondicionCarta.basica:
        return 0xFF506070;
      case CondicionCarta.evolucion:
        return 0xFFC060E0;
      case CondicionCarta.estatica:
        return 0xFFE0A030;
      case CondicionCarta.accion:
        return 0xFF40C0FF;
    }
  }

  /// Convierte un int (de Firestore) al enum. Desconocidos → básica.
  static CondicionCarta fromInt(int v) {
    switch (v) {
      case 1:
        return CondicionCarta.evolucion;
      case 3:
        return CondicionCarta.estatica;
      case 4:
        return CondicionCarta.accion;
      default:
        return CondicionCarta.basica;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// CARTA MODEL
// ─────────────────────────────────────────────────────────────
class CartaModel {
  final String id;
  final String nombre;
  final String descripcion;
  final int ejercito;
  final int fuerza;

  /// Puntos de defensa que absorben la fuerza enemiga en combate.
  final int defensa;

  /// Coste energético. El ganador recibe este valor como Energies.
  final int coste;

  final int idHabilidad;
  final String imagen;
  final int movimiento;

  /// Tipo de movimiento:
  ///   1 → Terrestre  2 → Volador  3 → Marino
  final int tipo;

  /// ID de la carta que se obtiene al evolucionar.
  final String idEvolucion;

  /// Coste en energías para evolucionar esta carta.
  final int evolucion;

  /// Condición especial de la carta. Determina reglas de juego.
  final CondicionCarta condicion;

  const CartaModel({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.ejercito,
    required this.fuerza,
    this.defensa = 0,
    this.coste = 0,
    required this.idHabilidad,
    required this.imagen,
    required this.movimiento,
    this.tipo = 1,
    this.idEvolucion = '',
    this.evolucion = 0,
    this.condicion = CondicionCarta.basica,
  });

  /// True si esta carta tiene una evolución configurada.
  bool get puedeEvolucionar => idEvolucion.isNotEmpty && evolucion > 0;

  /// True si la carta es de tipo Evolución (no se reparte ni se mete en mazos).
  bool get esEvolucion => condicion == CondicionCarta.evolucion;

  /// True si la carta es Estática (mov 0, reglas de colocación especiales).
  bool get esEstatica => condicion == CondicionCarta.estatica;

  /// Movimiento efectivo: las estáticas siempre tienen 0.
  int get movimientoEfectivo => esEstatica ? 0 : movimiento;

  // ── Parseo robusto ────────────────────────────────────────
  static int _parseInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static int _field(Map<String, dynamic> d, String pascal, String snake,
          {int fallback = 0}) =>
      _parseInt(d[pascal] ?? d[snake], fallback: fallback);

  static String _fieldStr(Map<String, dynamic> d, String pascal, String camel,
          {String fallback = ''}) =>
      (d[pascal] ?? d[camel])?.toString() ?? fallback;

  // ── Desde la colección Cartas de Firestore (PascalCase) ───
  factory CartaModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CartaModel(
      id: doc.id,
      nombre: d['Nombre']?.toString() ?? 'Sin nombre',
      descripcion: d['Descripcion']?.toString() ?? '',
      ejercito: _parseInt(d['Ejercito']),
      fuerza: _parseInt(d['Fuerza']),
      defensa: _parseInt(d['Defensa']),
      coste: _parseInt(d['Coste']),
      idHabilidad: _parseInt(d['IdHabilidad']),
      imagen: d['Imagen']?.toString() ?? '',
      movimiento: _parseInt(d['Movimiento'], fallback: 1),
      tipo: _parseInt(d['Tipo'], fallback: 1),
      idEvolucion: d['IdEvolucion']?.toString() ?? '',
      evolucion: _parseInt(d['Evolucion']),
      condicion: CondicionCartaExt.fromInt(_parseInt(d['Condicion'])),
    );
  }

  /// Desde un Map del tablero de Firestore (PascalCase o snake_case).
  factory CartaModel.fromMap(Map<String, dynamic> d) => CartaModel(
        id: (d['id'] ?? d['Id'])?.toString() ?? '',
        nombre: (d['Nombre'] ?? d['nombre'])?.toString() ?? 'Sin nombre',
        descripcion: (d['Descripcion'] ?? d['descripcion'])?.toString() ?? '',
        ejercito: _field(d, 'Ejercito', 'ejercito'),
        fuerza: _field(d, 'Fuerza', 'fuerza'),
        defensa: _field(d, 'Defensa', 'defensa'),
        coste: _field(d, 'Coste', 'coste'),
        idHabilidad: _field(d, 'IdHabilidad', 'idHabilidad'),
        imagen: (d['Imagen'] ?? d['imagen'])?.toString() ?? '',
        movimiento: _field(d, 'Movimiento', 'movimiento', fallback: 1),
        tipo: _field(d, 'Tipo', 'tipo', fallback: 1),
        idEvolucion: _fieldStr(d, 'IdEvolucion', 'idEvolucion'),
        evolucion: _field(d, 'Evolucion', 'evolucion'),
        condicion:
            CondicionCartaExt.fromInt(_field(d, 'Condicion', 'condicion')),
      );

  // ── Serialización ─────────────────────────────────────────
  Map<String, dynamic> toMap() => {
        'id': id,
        'Nombre': nombre,
        'Descripcion': descripcion,
        'Ejercito': ejercito,
        'Fuerza': fuerza,
        'Defensa': defensa,
        'Coste': coste,
        'IdHabilidad': idHabilidad,
        'Imagen': imagen,
        'Movimiento': movimiento,
        'Tipo': tipo,
        'IdEvolucion': idEvolucion,
        'Evolucion': evolucion,
        'Condicion': condicion.value,
      };

  CartaModel copyWith({
    String? id,
    String? nombre,
    String? descripcion,
    int? ejercito,
    int? fuerza,
    int? defensa,
    int? coste,
    int? idHabilidad,
    String? imagen,
    int? movimiento,
    int? tipo,
    String? idEvolucion,
    int? evolucion,
    CondicionCarta? condicion,
  }) =>
      CartaModel(
        id: id ?? this.id,
        nombre: nombre ?? this.nombre,
        descripcion: descripcion ?? this.descripcion,
        ejercito: ejercito ?? this.ejercito,
        fuerza: fuerza ?? this.fuerza,
        defensa: defensa ?? this.defensa,
        coste: coste ?? this.coste,
        idHabilidad: idHabilidad ?? this.idHabilidad,
        imagen: imagen ?? this.imagen,
        movimiento: movimiento ?? this.movimiento,
        tipo: tipo ?? this.tipo,
        idEvolucion: idEvolucion ?? this.idEvolucion,
        evolucion: evolucion ?? this.evolucion,
        condicion: condicion ?? this.condicion,
      );

  String get tipoLabel {
    switch (tipo) {
      case 2:
        return 'Volador';
      case 3:
        return 'Marino';
      default:
        return 'Terrestre';
    }
  }

  String get tipoIcon {
    switch (tipo) {
      case 2:
        return '🦅';
      case 3:
        return '⚓';
      default:
        return '🗡️';
    }
  }
}
