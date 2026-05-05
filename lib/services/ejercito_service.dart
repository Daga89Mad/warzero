// lib/services/ejercito_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lobby_model.dart';

// ── Lista de respaldo si Firestore está vacío o inaccesible ──
const List<EjercitoInfo> _kFallback = [
  EjercitoInfo(
      id: 1,
      nombre: 'LEGIÓN DE HIERRO',
      descripcion: 'Infantería pesada y artillería de asedio.',
      icono: '⚔️'),
  EjercitoInfo(
      id: 2,
      nombre: 'GUARDIA DEL NORTE',
      descripcion: 'Especialistas en combate ártico y guerrilla.',
      icono: '🛡️'),
  EjercitoInfo(
      id: 3,
      nombre: 'FLOTA IMPERIAL',
      descripcion: 'Dominio naval y ataques anfibios.',
      icono: '⚓'),
  EjercitoInfo(
      id: 4,
      nombre: 'ORDEN DEL CREPÚSCULO',
      descripcion: 'Unidades de élite y operaciones encubiertas.',
      icono: '🌒'),
];

class EjercitoService {
  static final EjercitoService _instance = EjercitoService._();
  factory EjercitoService() => _instance;
  EjercitoService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<EjercitoInfo>? _cache;

  List<EjercitoInfo> _parse(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return _kFallback;
    final list = docs.map((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return EjercitoInfo(
        id: int.tryParse(doc.id) ?? 0,
        nombre: d['Nombre'] as String? ?? 'Ejército ${doc.id}',
        descripcion: d['Descripcion'] as String? ?? '',
        icono:
            (d['Icono'] as String? ?? '').isEmpty ? '⚔️' : d['Icono'] as String,
      );
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  Future<List<EjercitoInfo>> fetchEjercitos({bool forceRefresh = false}) async {
    if (_cache != null && !forceRefresh) return _cache!;
    try {
      final snap = await _db.collection('Ejercitos').get();
      _cache = _parse(snap.docs);
    } catch (_) {
      _cache = _kFallback;
    }
    return _cache!;
  }

  Stream<List<EjercitoInfo>> ejercitosStream() {
    return _db.collection('Ejercitos').snapshots().map((snap) {
      final list = _parse(snap.docs);
      _cache = list;
      return list;
    }).handleError((_) => _kFallback);
  }

  Future<EjercitoInfo> getById(int id) async {
    final list = await fetchEjercitos();
    return list.firstWhere(
      (e) => e.id == id,
      orElse: () => EjercitoInfo(
          id: id, nombre: 'Ejército $id', descripcion: '', icono: '⚔️'),
    );
  }
}
