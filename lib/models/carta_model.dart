// lib/models/carta_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

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
  /// Cadena vacía si la carta no puede evolucionar.
  final String idEvolucion;

  /// Coste en energías para evolucionar esta carta.
  /// 0 si la carta no puede evolucionar.
  final int evolucion;

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
  });

  /// True si esta carta tiene una evolución configurada.
  bool get puedeEvolucionar => idEvolucion.isNotEmpty && evolucion > 0;

  // ── Parseo robusto ────────────────────────────────────────
  /// Convierte int, double o String a int. Devuelve [fallback] si null.
  static int _parseInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  /// Lee un campo probando primero la clave PascalCase y luego snake_case.
  /// Acepta el valor como int, double o String.
  static int _field(Map<String, dynamic> d, String pascal, String snake,
          {int fallback = 0}) =>
      _parseInt(d[pascal] ?? d[snake], fallback: fallback);

  /// Lee un campo string probando primero PascalCase y luego camelCase.
  static String _fieldStr(Map<String, dynamic> d, String pascal, String camel,
          {String fallback = ''}) =>
      (d[pascal] ?? d[camel])?.toString() ?? fallback;

  // ── Desde la colección Cartas de Firestore (siempre PascalCase) ──
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
    );
  }

  /// Construye una CartaModel desde un Map guardado en el tablero de Firestore.
  /// Acepta tanto PascalCase ('Fuerza') como snake_case ('fuerza') para ser
  /// compatible con datos guardados por versiones anteriores del código.
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
      );

  // ── Serialización ─────────────────────────────────────────
  /// Guarda con PascalCase — igual que la colección Cartas de Firestore.
  /// Usado para serializar cartas en el tablero compartido.
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
