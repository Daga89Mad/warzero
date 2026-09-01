// lib/models/tienda_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Pestañas / categorías de la tienda. El valor [key] es lo que se guarda en
/// Firestore (campo `categoria`) y agrupa los artículos por pestaña.
enum TiendaCategoria { marcos, iconos, ofertas, packs }

extension TiendaCategoriaExt on TiendaCategoria {
  /// Clave persistida en Firestore.
  String get key {
    switch (this) {
      case TiendaCategoria.marcos:
        return 'marcos';
      case TiendaCategoria.iconos:
        return 'iconos';
      case TiendaCategoria.ofertas:
        return 'ofertas';
      case TiendaCategoria.packs:
        return 'packs';
    }
  }

  /// Nombre visible en la pestaña.
  String get label {
    switch (this) {
      case TiendaCategoria.marcos:
        return 'Marcos';
      case TiendaCategoria.iconos:
        return 'Iconos';
      case TiendaCategoria.ofertas:
        return 'Ofertas';
      case TiendaCategoria.packs:
        return 'Packs';
    }
  }

  /// Icono de la pestaña.
  IconData get icon {
    switch (this) {
      case TiendaCategoria.marcos:
        return Icons.crop_square;
      case TiendaCategoria.iconos:
        return Icons.face_outlined;
      case TiendaCategoria.ofertas:
        return Icons.local_offer_outlined;
      case TiendaCategoria.packs:
        return Icons.inventory_2_outlined;
    }
  }

  /// Convierte una clave de Firestore en su categoría. Desconocido → ofertas.
  static TiendaCategoria fromKey(String? key) {
    switch ((key ?? '').trim().toLowerCase()) {
      case 'marcos':
        return TiendaCategoria.marcos;
      case 'iconos':
        return TiendaCategoria.iconos;
      case 'packs':
        return TiendaCategoria.packs;
      case 'ofertas':
      default:
        return TiendaCategoria.ofertas;
    }
  }
}

/// Un artículo a la venta en la tienda. Los editores lo crean/editan desde la
/// pantalla "Editar Tienda"; la tienda lo muestra en su pestaña.
///
/// Documento en la colección Firestore `Tienda`:
///   categoria   : String  (marcos | iconos | ofertas | packs)
///   nombre      : String
///   descripcion : String
///   imagen      : String  (URL del arte)
///   coste       : int
///   moneda      : String  (etiqueta de la moneda, p. ej. "Zero Puro")
///   activo      : bool    (visible en la tienda)
///   orden       : int     (orden dentro de su pestaña; menor primero)
class ArticuloTienda {
  final String id;
  final TiendaCategoria categoria;
  final String nombre;
  final String descripcion;
  final String imagen;
  final int coste;
  final String moneda;
  final bool activo;
  final int orden;

  const ArticuloTienda({
    required this.id,
    required this.categoria,
    required this.nombre,
    required this.descripcion,
    required this.imagen,
    required this.coste,
    required this.moneda,
    required this.activo,
    required this.orden,
  });

  factory ArticuloTienda.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return ArticuloTienda(
      id: doc.id,
      categoria: TiendaCategoriaExt.fromKey(d['categoria'] as String?),
      nombre: (d['nombre'] as String?) ?? 'Artículo',
      descripcion: (d['descripcion'] as String?) ?? '',
      imagen: (d['imagen'] as String?) ?? '',
      coste: (d['coste'] as num?)?.toInt() ?? 0,
      moneda: (d['moneda'] as String?) ?? 'Zero Puro',
      activo: (d['activo'] as bool?) ?? true,
      orden: (d['orden'] as num?)?.toInt() ?? 0,
    );
  }

  /// Mapa para escribir en Firestore (sin el id, que es el nombre del doc).
  Map<String, dynamic> toMap() => {
        'categoria': categoria.key,
        'nombre': nombre,
        'descripcion': descripcion,
        'imagen': imagen,
        'coste': coste,
        'moneda': moneda,
        'activo': activo,
        'orden': orden,
      };

  ArticuloTienda copyWith({
    TiendaCategoria? categoria,
    String? nombre,
    String? descripcion,
    String? imagen,
    int? coste,
    String? moneda,
    bool? activo,
    int? orden,
  }) =>
      ArticuloTienda(
        id: id,
        categoria: categoria ?? this.categoria,
        nombre: nombre ?? this.nombre,
        descripcion: descripcion ?? this.descripcion,
        imagen: imagen ?? this.imagen,
        coste: coste ?? this.coste,
        moneda: moneda ?? this.moneda,
        activo: activo ?? this.activo,
        orden: orden ?? this.orden,
      );
}
