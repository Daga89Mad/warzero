// lib/models/historia_model.dart

/// Una página de una historia: una imagen y su descripción. Las páginas se
/// muestran en orden cronológico (campo `orden`, o el orden del array).
class HistoriaPagina {
  final String imagen;
  final String descripcion;
  final int orden;

  const HistoriaPagina({
    required this.imagen,
    required this.descripcion,
    this.orden = 0,
  });

  factory HistoriaPagina.fromMap(Map<String, dynamic> d) => HistoriaPagina(
        imagen: (d['imagen'] ?? d['Imagen'] ?? '').toString(),
        descripcion: (d['descripcion'] ?? d['Descripcion'] ?? '').toString(),
        orden: _int(d['orden'] ?? d['Orden']),
      );

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
}

/// Una historia de un ejército. Hay 10 por ejército (orden 1..10). Permanece
/// bloqueada hasta que el jugador la consigue; mientras lo está, el servidor no
/// envía ni el título ni las páginas (para no destripar el contenido).
class HistoriaModel {
  final String id;
  final int ejercito;
  final int orden; // 1..10
  final String titulo; // vacío si está bloqueada
  final List<HistoriaPagina> paginas;
  final bool desbloqueada;

  /// Historia "por defecto": está desbloqueada para todos los jugadores sin
  /// necesidad de conseguirla. El servidor ya la devuelve con
  /// `desbloqueada = true`; este flag solo sirve para poder distinguirla en la
  /// UI (p.ej. mostrar una etiqueta) si hiciera falta.
  final bool porDefecto;

  const HistoriaModel({
    required this.id,
    required this.ejercito,
    required this.orden,
    required this.titulo,
    required this.paginas,
    required this.desbloqueada,
    this.porDefecto = false,
  });

  factory HistoriaModel.fromMap(Map<String, dynamic> d) {
    final paginasRaw = (d['paginas'] ?? d['Paginas']) as List? ?? const [];
    final paginas = paginasRaw
        .map((e) => HistoriaPagina.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    // Orden cronológico: por el campo `orden` si existe; si no, el del array.
    if (paginas.any((p) => p.orden != 0)) {
      paginas.sort((a, b) => a.orden.compareTo(b.orden));
    }

    return HistoriaModel(
      id: (d['id'] ?? '').toString(),
      ejercito: _int(d['ejercito'] ?? d['Ejercito']),
      orden: _int(d['orden'] ?? d['Orden']),
      titulo: (d['titulo'] ?? d['Titulo'] ?? '').toString(),
      paginas: paginas,
      desbloqueada: d['desbloqueada'] == true,
      porDefecto: d['porDefecto'] == true || d['PorDefecto'] == true,
    );
  }

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
}
