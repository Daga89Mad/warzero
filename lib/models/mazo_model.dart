// lib/models/mazo_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'carta_model.dart';

/// Entrada en el mazo: referencia a una carta + cantidad
class MazoEntrada {
  final String idCarta;
  final int cantidad;

  const MazoEntrada({required this.idCarta, required this.cantidad});

  factory MazoEntrada.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MazoEntrada(
      idCarta:  doc.id,
      cantidad: (d['Cantidad'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Mazo sin resolver (solo IDs)
class MazoModel {
  final String id;
  final List<MazoEntrada> entradas;

  const MazoModel({required this.id, required this.entradas});
}

/// Mazo resuelto: cartas completas listas para jugar
class MazoResuelto {
  final String id;

  /// Lista expandida: si Cantidad=2 → la carta aparece 2 veces
  final List<CartaModel> cartas;

  const MazoResuelto({required this.id, required this.cartas});

  int get total => cartas.length;
}
