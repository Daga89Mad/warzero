// lib/services/mapa_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:warzero/models/game_config.dart';

/// Modelo ligero de un mapa (para el selector en la creación de sala).
class MapaInfo {
  final String id;
  final String nombre;
  final int jugadores;
  final Map<String, TerrainType> terreno;

  /// Mapa de continentes (configurable por mapa en Firestore):
  ///   obeliscoCoord → lista de coordenadas que pertenecen a ese continente.
  ///
  /// Ejemplo mapa_clasico:
  ///   "A1"  → ["A1","A2","A3","A4","B1","B2","B3","B4"]           (rojo)
  ///   "F1"  → ["F1","F2","F3","F4","E1","E2","E3","E4","D1","D2","D3","D4"] (azul)
  ///   "A10" → ["A10","A9","A8","A7","B10","B9","B8","B7"]         (amarillo)
  ///   "F10" → ["F10","F9","F8","F7","E10","E9","E8","E7","D10","D9","D8","D7"] (verde)
  final Map<String, List<String>> continentes;

  /// Coordenadas de la isla central (bonus neutro de 7 Energies por carta).
  ///
  /// Ejemplo mapa_clasico: ["C4","C5","C6","C7","D5","D6"]
  final List<String> islaCentral;

  const MapaInfo({
    required this.id,
    required this.nombre,
    required this.jugadores,
    required this.terreno,
    this.continentes = const {},
    this.islaCentral = const [],
  });

  factory MapaInfo.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final terrenoRaw = d['terreno'] as Map<String, dynamic>? ?? {};

    // Parsear continentes: { "A1": ["A1","A2",...], "F1": [...] }
    final continentesRaw = d['continentes'] as Map<String, dynamic>? ?? {};
    final continentes = continentesRaw.map((obelisco, celdas) {
      final lista = (celdas as List<dynamic>).map((e) => e.toString()).toList();
      return MapEntry(obelisco, lista);
    });

    // Parsear isla central: ["C4","C5","C6","C7","D5","D6"]
    final islaCentralRaw = d['islaCentral'] as List<dynamic>? ?? [];
    final islaCentral = islaCentralRaw.map((e) => e.toString()).toList();

    return MapaInfo(
      id: doc.id,
      nombre: d['nombre'] as String? ?? doc.id,
      jugadores: (d['jugadores'] as num?)?.toInt() ?? 4,
      terreno: MapaService._parseTerreno(terrenoRaw),
      continentes: continentes,
      islaCentral: islaCentral,
    );
  }
}

class MapaService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Todos los mapas, filtrado en CLIENTE para evitar índices Firestore ──
  //
  // Usar where() en Firestore sobre campos que no son el ID requiere un índice
  // compuesto que puede no existir. Cargamos toda la colección y filtramos
  // en Dart: la colección Mapas será siempre pequeña (decenas de documentos).
  Future<List<MapaInfo>> obtenerMapas({int? jugadores}) async {
    final snap = await _db.collection('Mapas').get();
    final todos = snap.docs.map(MapaInfo.fromFirestore).toList();
    if (jugadores == null) return todos;
    return todos.where((m) => m.jugadores == jugadores).toList();
  }

  // ── Un mapa concreto por ID ───────────────────────────────
  Future<MapaInfo?> obtenerMapa(String mapaId) async {
    final doc = await _db.collection('Mapas').doc(mapaId).get();
    if (!doc.exists) return null;
    return MapaInfo.fromFirestore(doc);
  }

  // ── Aplica el terreno del mapa al GameConfig proporcionado ──
  Future<GameConfig> aplicarTerrenoAConfig(
      String mapaId, GameConfig config) async {
    final mapa = await obtenerMapa(mapaId);
    if (mapa == null) return config;
    return config.withTerrain(mapa.terreno);
  }

  // ── Convierte el map raw de Firestore {"B5": "sea",...} ──
  static Map<String, TerrainType> _parseTerreno(Map<String, dynamic> raw) {
    return raw.map((coord, valor) {
      final tipo = switch (valor as String? ?? 'land') {
        'sea' => TerrainType.sea,
        'deepSea' => TerrainType.deepSea,
        'amphibious' => TerrainType.amphibious,
        _ => TerrainType.land,
      };
      return MapEntry(coord, tipo);
    });
  }
}
