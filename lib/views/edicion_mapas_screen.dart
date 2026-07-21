// lib/views/edicion_mapas_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/game_config.dart';
import '../widgets/board_widget.dart' show BoardBackgroundImage;

/// Pantalla de administración de MAPAS (solo editores). Mismo patrón que la
/// edición de Cartas / Historias: un listado con los mapas existentes y un
/// editor a pantalla completa para crear / modificar / eliminar, más un botón
/// DUPLICAR que clona un mapa existente y lo abre en el editor para retocarlo.
///
/// Escribe directamente en la colección Firestore `Mapas`, con el mismo esquema
/// que consume [MapaService]:
///   nombre       : String
///   jugadores    : int (2 | 4 | 6 | 8)
///   filas        : int  (tamaño de rejilla propio del mapa)
///   columnas     : int  (idem; permite mapas más grandes que el preset)
///   imagen       : String (URL http(s) o ruta de asset; fondo del tablero)
///   terreno      : { "F5": "sea", "E7": "amphibious", ... }
///   islaCentral  : ["C4","C5","C6","C7","D5","D6"]
///   continentes  : { "A10": ["A10","A9","A8", ...], ... }  (obelisco → celdas)
class EdicionMapasScreen extends StatefulWidget {
  const EdicionMapasScreen({super.key});

  @override
  State<EdicionMapasScreen> createState() => _EdicionMapasScreenState();
}

class _EdicionMapasScreenState extends State<EdicionMapasScreen> {
  static const _accent = Color(0xFF40A0D0);
  final _col = FirebaseFirestore.instance.collection('Mapas');

  bool _loading = true;
  String? _error;
  List<_MapaResumen> _mapas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _col.get();
      final lista = snap.docs.map(_MapaResumen.fromDoc).toList()
        ..sort((a, b) {
          final c = a.jugadores.compareTo(b.jugadores);
          return c != 0
              ? c
              : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _mapas = lista;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cinzel')),
      backgroundColor:
          error ? const Color(0xFF3A0E0E) : const Color(0xFF0E2A14),
    ));
  }

  Future<void> _abrirEditor({String? docId}) async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditorMapa(docId: docId)),
    );
    if (cambiado == true) _load();
  }

  /// Duplica un mapa: pide el nuevo ID/nombre, copia el documento completo y
  /// abre el editor sobre la copia para que se puedan modificar sus datos.
  Future<void> _duplicar(_MapaResumen m) async {
    final sugerido = _idSugerido('${m.docId}_copia');
    final datos = await showDialog<_NuevoMapaDatos>(
      context: context,
      builder: (_) => _DialogoNuevoMapa(
        titulo: 'DUPLICAR MAPA',
        idInicial: sugerido,
        nombreInicial: '${m.nombre} (copia)',
        idsExistentes: _mapas.map((x) => x.docId).toSet(),
      ),
    );
    if (datos == null) return;

    try {
      final origen = await _col.doc(m.docId).get();
      final d = Map<String, dynamic>.from(origen.data() ?? const {});
      d['nombre'] = datos.nombre;
      await _col.doc(datos.docId).set(d);
      if (!mounted) return;
      _toast('Mapa duplicado como "${datos.nombre}".');
      await _abrirEditor(docId: datos.docId);
    } catch (e) {
      if (mounted) _toast('No se pudo duplicar: $e', error: true);
    }
  }

  Future<void> _crear() async {
    final datos = await showDialog<_NuevoMapaDatos>(
      context: context,
      builder: (_) => _DialogoNuevoMapa(
        titulo: 'NUEVO MAPA',
        idInicial: _idSugerido('mapa_nuevo'),
        nombreInicial: '',
        idsExistentes: _mapas.map((x) => x.docId).toSet(),
      ),
    );
    if (datos == null) return;
    try {
      final preset = GameConfig.forPlayerCount(4);
      await _col.doc(datos.docId).set({
        'nombre': datos.nombre,
        'jugadores': 4,
        'filas': preset.rows,
        'columnas': preset.cols,
        'imagen': '',
        'terreno': <String, dynamic>{},
        'islaCentral': <String>[],
        'continentes': <String, dynamic>{},
      });
      if (!mounted) return;
      await _abrirEditor(docId: datos.docId);
    } catch (e) {
      if (mounted) _toast('No se pudo crear: $e', error: true);
    }
  }

  /// Genera un id libre a partir de una base (base, base_2, base_3...).
  String _idSugerido(String base) {
    final usados = _mapas.map((m) => m.docId).toSet();
    if (!usados.contains(base)) return base;
    var i = 2;
    while (usados.contains('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: _accent),
        title: const Text(
          'EDICIÓN · MAPAS',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: _accent,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        onPressed: _loading ? null : _crear,
        icon: const Icon(Icons.add, color: Color(0xFF02050D)),
        label: const Text(
          'NUEVO MAPA',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Cinzel',
            letterSpacing: 1.5,
            color: Color(0xFF02050D),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No se pudieron cargar los mapas.\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF506070),
                        fontFamily: 'Cinzel',
                        height: 1.4,
                      ),
                    ),
                  ),
                )
              : _mapas.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay mapas.\nPulsa NUEVO MAPA para crear uno.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel',
                          height: 1.6,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _mapas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _MapaTile(
                        mapa: _mapas[i],
                        onTap: () => _abrirEditor(docId: _mapas[i].docId),
                        onDuplicar: () => _duplicar(_mapas[i]),
                      ),
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Resumen de un mapa para el listado
// ─────────────────────────────────────────────────────────────
class _MapaResumen {
  final String docId;
  final String nombre;
  final int jugadores;
  final int celdasTerreno;
  final int numContinentes;
  final int celdasIsla;
  final int? filas;
  final int? columnas;

  const _MapaResumen({
    required this.docId,
    required this.nombre,
    required this.jugadores,
    required this.celdasTerreno,
    required this.numContinentes,
    required this.celdasIsla,
    this.filas,
    this.columnas,
  });

  /// Tamaño mostrado: el propio del mapa, o el del preset si no lo define.
  String get tamanio {
    final cfg = GameConfig.forPlayerCount(jugadores);
    return '${filas ?? cfg.rows}×${columnas ?? cfg.cols}';
  }

  factory _MapaResumen.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return _MapaResumen(
      docId: doc.id,
      nombre: (d['nombre'] ?? doc.id).toString(),
      jugadores: (d['jugadores'] as num?)?.toInt() ?? 4,
      celdasTerreno: (d['terreno'] as Map?)?.length ?? 0,
      numContinentes: (d['continentes'] as Map?)?.length ?? 0,
      celdasIsla: (d['islaCentral'] as List?)?.length ?? 0,
      filas: (d['filas'] as num?)?.toInt(),
      columnas: (d['columnas'] as num?)?.toInt(),
    );
  }
}

class _MapaTile extends StatelessWidget {
  final _MapaResumen mapa;
  final VoidCallback onTap;
  final VoidCallback onDuplicar;

  const _MapaTile({
    required this.mapa,
    required this.onTap,
    required this.onDuplicar,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF40A0D0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withOpacity(0.30)),
              ),
              child: const Icon(Icons.map_outlined, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mapa.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'Cinzel',
                      color: Color(0xFFE0D8C0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${mapa.docId}  ·  ${mapa.jugadores} jugadores  ·  ${mapa.tamanio}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'Cinzel',
                      color: Color(0xFF506070),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${mapa.celdasTerreno} terreno · '
                    '${mapa.numContinentes} continentes · '
                    '${mapa.celdasIsla} isla',
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'Cinzel',
                      color: Color(0xFF405060),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Duplicar mapa',
              icon:
                  const Icon(Icons.copy_all_outlined, size: 18, color: accent),
              onPressed: onDuplicar,
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF506070)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Diálogo para crear / duplicar (id de documento + nombre)
// ─────────────────────────────────────────────────────────────
class _NuevoMapaDatos {
  final String docId;
  final String nombre;
  const _NuevoMapaDatos({required this.docId, required this.nombre});
}

class _DialogoNuevoMapa extends StatefulWidget {
  final String titulo;
  final String idInicial;
  final String nombreInicial;
  final Set<String> idsExistentes;

  const _DialogoNuevoMapa({
    required this.titulo,
    required this.idInicial,
    required this.nombreInicial,
    required this.idsExistentes,
  });

  @override
  State<_DialogoNuevoMapa> createState() => _DialogoNuevoMapaState();
}

class _DialogoNuevoMapaState extends State<_DialogoNuevoMapa> {
  late final TextEditingController _idCtrl =
      TextEditingController(text: widget.idInicial);
  late final TextEditingController _nombreCtrl =
      TextEditingController(text: widget.nombreInicial);
  String? _err;

  @override
  void dispose() {
    _idCtrl.dispose();
    _nombreCtrl.dispose();
    super.dispose();
  }

  void _aceptar() {
    final id = _idCtrl.text.trim();
    final nombre = _nombreCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _err = 'El ID no puede estar vacío.');
      return;
    }
    if (id.contains('/') || id.contains(' ')) {
      setState(() => _err = 'El ID no puede contener espacios ni "/".');
      return;
    }
    if (widget.idsExistentes.contains(id)) {
      setState(() => _err = 'Ya existe un mapa con ese ID.');
      return;
    }
    if (nombre.isEmpty) {
      setState(() => _err = 'El nombre no puede estar vacío.');
      return;
    }
    Navigator.of(context).pop(_NuevoMapaDatos(docId: id, nombre: nombre));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0C1828),
      title: Text(
        widget.titulo,
        style: const TextStyle(
          color: Color(0xFF40A0D0),
          fontFamily: 'Cinzel',
          fontSize: 14,
          letterSpacing: 1.5,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _campo(_idCtrl, 'ID del documento (ej. mapa_clasico)'),
          const SizedBox(height: 10),
          _campo(_nombreCtrl, 'Nombre visible (ej. Clásico)'),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!,
                style: const TextStyle(color: Color(0xFFE06060), fontSize: 11)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar',
              style: TextStyle(color: Color(0xFF90A0B0))),
        ),
        TextButton(
          onPressed: _aceptar,
          child:
              const Text('Aceptar', style: TextStyle(color: Color(0xFF40A0D0))),
        ),
      ],
    );
  }

  Widget _campo(TextEditingController c, String hint) => TextField(
        controller: c,
        style: const TextStyle(color: Color(0xFFE0D8C0), fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF405060), fontSize: 11),
          filled: true,
          fillColor: const Color(0xFF0A1220),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide:
                BorderSide(color: const Color(0xFF506070).withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFF40A0D0)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// EDITOR DE UN MAPA
// ─────────────────────────────────────────────────────────────

/// Herramienta (pincel) activa en la rejilla.
enum _Pincel {
  land,
  sea,
  deepSea,
  amphibious,
  islaCentral,
  continente,
  obelisco
}

class _EditorMapa extends StatefulWidget {
  final String? docId;
  const _EditorMapa({this.docId});

  @override
  State<_EditorMapa> createState() => _EditorMapaState();
}

class _EditorMapaState extends State<_EditorMapa> {
  static const _accent = Color(0xFF40A0D0);
  final _col = FirebaseFirestore.instance.collection('Mapas');
  final _nombreCtrl = TextEditingController();
  final _imagenCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  int _jugadores = 4;

  /// Tamaño de la rejilla del mapa. Se inicializa desde el preset del número de
  /// jugadores, pero es editable: así un mapa puede tener más celdas que el
  /// preset (p.ej. 4 jugadores en una rejilla 12×20).
  late int _filas;
  late int _columnas;

  /// Preview: pinta la imagen de fondo del tablero bajo las celdas.
  bool _preview = true;

  /// coord → terreno ('land' | 'sea' | 'deepSea' | 'amphibious').
  /// Las celdas ausentes se consideran `land` (igual que MapaService).
  final Map<String, String> _terreno = {};
  final Set<String> _islaCentral = {};

  /// Continentes en edición. Cada uno tiene un obelisco (coord) y sus celdas.
  final List<_ContinenteEdit> _continentes = [];

  _Pincel _pincel = _Pincel.sea;
  int _continenteSel = 0;

  @override
  void initState() {
    super.initState();
    final preset = GameConfig.forPlayerCount(_jugadores);
    _filas = preset.rows;
    _columnas = preset.cols;
    _load();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _imagenCtrl.dispose();
    super.dispose();
  }

  /// Config con la rejilla propia del mapa (no la del preset).
  GameConfig get _config => GameConfig.forPlayerCount(_jugadores)
      .withGrid(filas: _filas, columnas: _columnas);

  /// Al cambiar el número de jugadores se reajusta la rejilla al preset
  /// correspondiente (el editor la puede volver a agrandar después).
  void _setJugadores(int n) {
    final preset = GameConfig.forPlayerCount(n);
    setState(() {
      _jugadores = n;
      _filas = preset.rows;
      _columnas = preset.cols;
    });
  }

  Future<void> _load() async {
    try {
      if (widget.docId != null) {
        final doc = await _col.doc(widget.docId!).get();
        final d = doc.data() ?? const <String, dynamic>{};

        _nombreCtrl.text = (d['nombre'] ?? doc.id).toString();
        _imagenCtrl.text = (d['imagen'] ?? '').toString();
        _jugadores = (d['jugadores'] as num?)?.toInt() ?? 4;

        // Si el mapa no trae rejilla propia (mapas antiguos), se toma la del
        // preset del número de jugadores.
        final preset = GameConfig.forPlayerCount(_jugadores);
        _filas = (d['filas'] as num?)?.toInt() ?? preset.rows;
        _columnas = (d['columnas'] as num?)?.toInt() ?? preset.cols;

        final terrenoRaw = (d['terreno'] as Map?) ?? const {};
        terrenoRaw.forEach((k, v) {
          _terreno[k.toString()] = v?.toString() ?? 'land';
        });

        final islaRaw = (d['islaCentral'] as List?) ?? const [];
        _islaCentral.addAll(islaRaw.map((e) => e.toString()));

        final contRaw = (d['continentes'] as Map?) ?? const {};
        contRaw.forEach((obelisco, celdas) {
          _continentes.add(_ContinenteEdit(
            obelisco: obelisco.toString(),
            celdas: ((celdas as List?) ?? const [])
                .map((e) => e.toString())
                .toSet(),
          ));
        });
      }
    } catch (_) {
      // Si falla la carga se empieza en blanco.
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cinzel')),
      backgroundColor:
          error ? const Color(0xFF3A0E0E) : const Color(0xFF0E2A14),
    ));
  }

  // ── Interacción con la rejilla ────────────────────────────
  void _onCeldaTap(String coord) {
    setState(() {
      switch (_pincel) {
        case _Pincel.land:
          // `land` es el valor por defecto: se quita del mapa para no engordar
          // el documento con entradas redundantes.
          _terreno.remove(coord);
          break;
        case _Pincel.sea:
          _terreno[coord] = 'sea';
          break;
        case _Pincel.deepSea:
          _terreno[coord] = 'deepSea';
          break;
        case _Pincel.amphibious:
          _terreno[coord] = 'amphibious';
          break;
        case _Pincel.islaCentral:
          if (!_islaCentral.remove(coord)) _islaCentral.add(coord);
          break;
        case _Pincel.continente:
          if (_continentes.isEmpty) {
            _toast('Añade primero un continente.', error: true);
            return;
          }
          final c = _continentes[_continenteSel];
          if (!c.celdas.remove(coord)) c.celdas.add(coord);
          break;
        case _Pincel.obelisco:
          if (_continentes.isEmpty) {
            _toast('Añade primero un continente.', error: true);
            return;
          }
          final c = _continentes[_continenteSel];
          c.obelisco = coord;
          // El obelisco siempre pertenece a su continente.
          c.celdas.add(coord);
          break;
      }
    });
  }

  void _addContinente() {
    setState(() {
      _continentes.add(_ContinenteEdit(obelisco: '', celdas: {}));
      _continenteSel = _continentes.length - 1;
      _pincel = _Pincel.obelisco;
    });
    _toast('Toca una celda para fijar el obelisco del continente.');
  }

  void _removeContinente(int i) {
    setState(() {
      _continentes.removeAt(i);
      if (_continenteSel >= _continentes.length) {
        _continenteSel = _continentes.isEmpty ? 0 : _continentes.length - 1;
      }
    });
  }

  // ── Guardar / eliminar ────────────────────────────────────
  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _toast('El nombre no puede estar vacío.', error: true);
      return;
    }
    // Un continente sin obelisco no es representable en el esquema
    // (obeliscoCoord → celdas), así que se valida antes de guardar.
    final sinObelisco = _continentes.indexWhere((c) => c.obelisco.isEmpty);
    if (sinObelisco != -1) {
      _toast('El continente ${sinObelisco + 1} no tiene obelisco asignado.',
          error: true);
      return;
    }
    final obeliscos = _continentes.map((c) => c.obelisco).toList();
    if (obeliscos.toSet().length != obeliscos.length) {
      _toast('Hay dos continentes con el mismo obelisco.', error: true);
      return;
    }

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'nombre': nombre,
      'jugadores': _jugadores,
      'filas': _filas,
      'columnas': _columnas,
      'imagen': _imagenCtrl.text.trim(),
      'terreno': Map<String, dynamic>.from(_terreno),
      'islaCentral': _islaCentral.toList()..sort(),
      'continentes': {
        for (final c in _continentes) c.obelisco: (c.celdas.toList()..sort()),
      },
      // Lista explícita de obeliscos/cuarteles del mapa (coinciden con las claves
      // de `continentes`). El servidor la usa para asignar los cuarteles; si no
      // existe, cae a las claves de continentes y, en último caso, a las esquinas
      // por defecto.
      'obeliscos': obeliscos..sort(),
    };

    try {
      final id =
          widget.docId ?? 'mapa_${DateTime.now().millisecondsSinceEpoch}';
      await _col.doc(id).set(data, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('No se pudo guardar: $e', error: true);
      }
    }
  }

  Future<void> _eliminar() async {
    if (widget.docId == null) {
      Navigator.of(context).pop(false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1828),
        title: const Text('Eliminar mapa',
            style: TextStyle(color: Color(0xFFE06060), fontFamily: 'Cinzel')),
        content: const Text('Este mapa se borrará permanentemente.',
            style: TextStyle(color: Color(0xFFB0C0D0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF90A0B0))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(color: Color(0xFFE06060))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _col.doc(widget.docId!).delete();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('No se pudo eliminar: $e', error: true);
      }
    }
  }

  // ── Colores de la rejilla ─────────────────────────────────
  static const _colorTerreno = <String, Color>{
    'land': Color(0xFF2A3A2A),
    'sea': Color(0xFF1B4A78),
    'deepSea': Color(0xFF0E2A50),
    'amphibious': Color(0xFF2A6A6A),
  };

  /// Paleta cíclica para distinguir continentes en la rejilla.
  static const _coloresContinente = <Color>[
    Color(0xFFC04040),
    Color(0xFF4060D0),
    Color(0xFFC0A820),
    Color(0xFF4ABB58),
    Color(0xFFA040C0),
    Color(0xFF40A0C0),
    Color(0xFFD06040),
    Color(0xFF60C080),
  ];

  int? _continenteDe(String coord) {
    for (int i = 0; i < _continentes.length; i++) {
      if (_continentes[i].celdas.contains(coord)) return i;
    }
    return null;
  }

  /// Coordenadas ya definidas (terreno / isla / continentes) que caen fuera de
  /// la rejilla actual. Ocurre al reducir filas o columnas: no se borran (para
  /// no perder trabajo), pero conviene avisar de que no se están pintando.
  int get _celdasFueraDeRejilla {
    final cfg = _config;
    final validas = <String>{
      for (final r in cfg.rowLabels)
        for (final c in cfg.colLabels) '$r$c',
    };
    final definidas = <String>{
      ..._terreno.keys,
      ..._islaCentral,
      for (final c in _continentes) ...c.celdas,
    };
    return definidas.difference(validas).length;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF060E1A),
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    final cfg = _config;

    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: _accent),
        title: Text(
          widget.docId == null ? 'NUEVO MAPA' : 'EDITAR MAPA',
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: _accent,
          ),
        ),
        actions: [
          if (widget.docId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFE06060)),
              onPressed: _saving ? null : _eliminar,
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            // ── Nombre ──────────────────────────────────────
            _label('NOMBRE'),
            const SizedBox(height: 6),
            _campo(_nombreCtrl, hint: 'Nombre visible del mapa'),
            const SizedBox(height: 16),

            // ── Jugadores ───────────────────────────────────
            _label('JUGADORES'),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final n in [2, 4, 6, 8])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _chip(
                      label: '$n',
                      selected: _jugadores == n,
                      onTap: () => _setJugadores(n),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Cambiar el número de jugadores reajusta la rejilla al preset.',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF405060),
                fontFamily: 'Cinzel',
              ),
            ),
            const SizedBox(height: 16),

            // ── Tamaño de rejilla ───────────────────────────
            _label('TAMAÑO DE LA REJILLA'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'FILAS',
                    valor: _filas,
                    min: 4,
                    max: GameConfig.maxFilas,
                    onChanged: (v) => setState(() => _filas = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stepper(
                    label: 'COLUMNAS',
                    valor: _columnas,
                    min: 4,
                    max: GameConfig.maxColumnas,
                    onChanged: (v) => setState(() => _columnas = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${cfg.rows} × ${cfg.cols} = ${cfg.rows * cfg.cols} celdas  ·  '
              'filas A–${cfg.rowLabels.last}, columnas 1–${cfg.colLabels.last}',
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF506070),
                fontFamily: 'Cinzel',
              ),
            ),
            if (_celdasFueraDeRejilla > 0) ...[
              const SizedBox(height: 4),
              Text(
                '⚠ $_celdasFueraDeRejilla celdas definidas quedan fuera de la '
                'rejilla actual. Se conservan al guardar, pero no se pintan.',
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFFE0A030),
                  fontFamily: 'Cinzel',
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── Imagen del tablero ──────────────────────────
            _label('IMAGEN DEL TABLERO'),
            const SizedBox(height: 6),
            _campo(
              _imagenCtrl,
              hint: 'URL https://… o ruta de asset (assets/images/…)',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 4),
            const Text(
              'Vacío = imagen por defecto. Este fondo es el que usará '
              'BoardWidget en la partida de este mapa.',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF405060),
                fontFamily: 'Cinzel',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // ── Pinceles ────────────────────────────────────
            _label('PINCEL'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                    label: '🟩 TIERRA',
                    selected: _pincel == _Pincel.land,
                    onTap: () => setState(() => _pincel = _Pincel.land)),
                _chip(
                    label: '🟦 MAR',
                    selected: _pincel == _Pincel.sea,
                    onTap: () => setState(() => _pincel = _Pincel.sea)),
                _chip(
                    label: '🟪 MAR PROF.',
                    selected: _pincel == _Pincel.deepSea,
                    onTap: () => setState(() => _pincel = _Pincel.deepSea)),
                _chip(
                    label: '🟨 ANFIBIO',
                    selected: _pincel == _Pincel.amphibious,
                    onTap: () => setState(() => _pincel = _Pincel.amphibious)),
                _chip(
                    label: '⭐ ISLA CENTRAL',
                    selected: _pincel == _Pincel.islaCentral,
                    onTap: () => setState(() => _pincel = _Pincel.islaCentral)),
                _chip(
                    label: '🗺 CONTINENTE',
                    selected: _pincel == _Pincel.continente,
                    onTap: () => setState(() => _pincel = _Pincel.continente)),
                _chip(
                    label: '📍 OBELISCO',
                    selected: _pincel == _Pincel.obelisco,
                    onTap: () => setState(() => _pincel = _Pincel.obelisco)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _ayudaPincel(),
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF506070),
                fontFamily: 'Cinzel',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // ── Rejilla / preview ───────────────────────────
            Row(
              children: [
                _label(_preview ? 'PREVIEW DEL TABLERO' : 'REJILLA'),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _preview = !_preview),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _preview ? Icons.visibility : Icons.grid_on,
                        size: 14,
                        color: _accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _preview ? 'VER SOLO CELDAS' : 'VER CON IMAGEN',
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'Cinzel',
                          letterSpacing: 1,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _Rejilla(
              config: cfg,
              terreno: _terreno,
              islaCentral: _islaCentral,
              continenteDe: _continenteDe,
              obeliscos: {
                for (final c in _continentes)
                  if (c.obelisco.isNotEmpty) c.obelisco
              },
              colorTerreno: _colorTerreno,
              coloresContinente: _coloresContinente,
              // En preview se pinta la imagen del tablero detrás y las celdas
              // se vuelven translúcidas, para ver cómo casa el terreno con el
              // arte del mapa. Sigue siendo editable con los pinceles.
              preview: _preview,
              imagen: _imagenCtrl.text.trim(),
              onTap: _onCeldaTap,
            ),
            const SizedBox(height: 16),

            // ── Continentes ─────────────────────────────────
            Row(
              children: [
                _label('CONTINENTES (${_continentes.length})'),
                const Spacer(),
                GestureDetector(
                  onTap: _addContinente,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: _accent),
                      SizedBox(width: 4),
                      Text('AÑADIR',
                          style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1,
                              color: _accent)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_continentes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sin continentes. Añade uno y fija su obelisco tocando una celda.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF405060),
                    fontFamily: 'Cinzel',
                    height: 1.5,
                  ),
                ),
              )
            else
              for (int i = 0; i < _continentes.length; i++)
                _ContinenteCard(
                  numero: i + 1,
                  continente: _continentes[i],
                  color: _coloresContinente[i % _coloresContinente.length],
                  seleccionado: _continenteSel == i,
                  onSelect: () => setState(() {
                    _continenteSel = i;
                    if (_pincel != _Pincel.continente &&
                        _pincel != _Pincel.obelisco) {
                      _pincel = _Pincel.continente;
                    }
                  }),
                  onRemove: () => _removeContinente(i),
                ),
            const SizedBox(height: 16),

            // ── Isla central ────────────────────────────────
            _label('ISLA CENTRAL (${_islaCentral.length} celdas)'),
            const SizedBox(height: 6),
            Text(
              _islaCentral.isEmpty
                  ? 'Sin celdas. Usa el pincel ISLA CENTRAL sobre la rejilla.'
                  : (_islaCentral.toList()..sort()).join(', '),
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF90A0B0),
                fontFamily: 'Cinzel',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // ── Guardar ─────────────────────────────────────
            GestureDetector(
              onTap: _saving ? null : _guardar,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(_saving ? 0.3 : 1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _saving ? 'GUARDANDO…' : 'GUARDAR MAPA',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF02050D),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ayudaPincel() {
    switch (_pincel) {
      case _Pincel.land:
      case _Pincel.sea:
      case _Pincel.deepSea:
      case _Pincel.amphibious:
        return 'Toca una celda para asignarle ese terreno. TIERRA borra la '
            'entrada (es el valor por defecto).';
      case _Pincel.islaCentral:
        return 'Toca una celda para añadirla o quitarla de la isla central.';
      case _Pincel.continente:
        return 'Toca celdas para añadirlas o quitarlas del continente '
            'seleccionado abajo.';
      case _Pincel.obelisco:
        return 'Toca una celda para fijarla como obelisco del continente '
            'seleccionado abajo.';
    }
  }

  Widget _label(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 9,
          fontFamily: 'Cinzel',
          letterSpacing: 1.5,
          color: Color(0xFFC8A860),
        ),
      );

  Widget _campo(TextEditingController c,
          {String hint = '', VoidCallback? onChanged}) =>
      TextField(
        controller: c,
        onChanged: onChanged == null ? null : (_) => onChanged(),
        style: const TextStyle(color: Color(0xFFE0D8C0), fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF405060), fontSize: 11),
          filled: true,
          fillColor: const Color(0xFF0A1220),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide:
                BorderSide(color: const Color(0xFF506070).withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: _accent),
          ),
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color:
                selected ? _accent.withOpacity(0.18) : const Color(0xFF0A1220),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  selected ? _accent : const Color(0xFF506070).withOpacity(0.4),
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
              color: selected ? _accent : const Color(0xFF506070),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Stepper numérico (filas / columnas)
// ─────────────────────────────────────────────────────────────
class _Stepper extends StatelessWidget {
  final String label;
  final int valor;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.valor,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1220),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF506070).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 8,
                    fontFamily: 'Cinzel',
                    letterSpacing: 1,
                    color: Color(0xFF506070),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$valor',
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE0D8C0),
                  ),
                ),
              ],
            ),
          ),
          _btn(Icons.remove, valor > min ? () => onChanged(valor - 1) : null),
          const SizedBox(width: 4),
          _btn(Icons.add, valor < max ? () => onChanged(valor + 1) : null),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback? onTap) {
    const accent = Color(0xFF40A0D0);
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withOpacity(on ? 0.15 : 0.04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: accent.withOpacity(on ? 0.5 : 0.15)),
        ),
        child: Icon(icon, size: 16, color: accent.withOpacity(on ? 1 : 0.3)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Estado editable de un continente
// ─────────────────────────────────────────────────────────────
class _ContinenteEdit {
  String obelisco;
  final Set<String> celdas;
  _ContinenteEdit({required this.obelisco, required this.celdas});
}

class _ContinenteCard extends StatelessWidget {
  final int numero;
  final _ContinenteEdit continente;
  final Color color;
  final bool seleccionado;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _ContinenteCard({
    required this.numero,
    required this.continente,
    required this.color,
    required this.seleccionado,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final obelisco = continente.obelisco;
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF080D18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionado ? color : const Color(0xFF203040),
            width: seleccionado ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTINENTE $numero',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                      color: seleccionado ? color : const Color(0xFF90A0B0),
                      fontWeight:
                          seleccionado ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    obelisco.isEmpty
                        ? '⚠ sin obelisco · ${continente.celdas.length} celdas'
                        : 'obelisco $obelisco · ${continente.celdas.length} celdas',
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'Cinzel',
                      color: obelisco.isEmpty
                          ? const Color(0xFFE06060)
                          : const Color(0xFF506070),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 16, color: Color(0xFFE06060)),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REJILLA EDITABLE
// ─────────────────────────────────────────────────────────────
class _Rejilla extends StatelessWidget {
  final GameConfig config;
  final Map<String, String> terreno;
  final Set<String> islaCentral;
  final Set<String> obeliscos;
  final int? Function(String coord) continenteDe;
  final Map<String, Color> colorTerreno;
  final List<Color> coloresContinente;

  /// Si true, pinta la imagen del tablero detrás y las celdas translúcidas.
  final bool preview;
  final String imagen;

  final void Function(String coord) onTap;

  const _Rejilla({
    required this.config,
    required this.terreno,
    required this.islaCentral,
    required this.obeliscos,
    required this.continenteDe,
    required this.colorTerreno,
    required this.coloresContinente,
    required this.preview,
    required this.imagen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Reservamos una columna estrecha para las etiquetas de fila.
        const etiqueta = 18.0;
        final celda = ((box.maxWidth - etiqueta) / config.cols)
            .clamp(14.0, 44.0)
            .toDouble();

        final gridW = celda * config.cols;
        final gridH = celda * config.rows;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabecera de columnas
              Row(
                children: [
                  const SizedBox(width: etiqueta),
                  for (final c in config.colLabels)
                    SizedBox(
                      width: celda,
                      child: Text(
                        '$c',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: etiqueta + gridW,
                height: gridH,
                child: Stack(
                  children: [
                    // Fondo: la misma imagen que usará el tablero en partida,
                    // encajada exactamente sobre el área de celdas.
                    if (preview)
                      Positioned(
                        left: etiqueta,
                        top: 0,
                        width: gridW,
                        height: gridH,
                        child: BoardBackgroundImage(imagen: imagen),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int ri = 0; ri < config.rows; ri++)
                          Row(
                            children: [
                              SizedBox(
                                width: etiqueta,
                                height: celda,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    config.rowLabels[ri],
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Color(0xFF506070),
                                      fontFamily: 'Cinzel',
                                    ),
                                  ),
                                ),
                              ),
                              for (int ci = 0; ci < config.cols; ci++)
                                Builder(builder: (_) {
                                  final coord = config.coordLabel(ri, ci);
                                  return _Celda(
                                    coord: coord,
                                    size: celda,
                                    terreno: terreno[coord] ?? 'land',
                                    esIsla: islaCentral.contains(coord),
                                    esObelisco: obeliscos.contains(coord),
                                    continente: continenteDe(coord),
                                    colorTerreno: colorTerreno,
                                    coloresContinente: coloresContinente,
                                    preview: preview,
                                    onTap: () => onTap(coord),
                                  );
                                }),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Celda extends StatelessWidget {
  final String coord;
  final double size;
  final String terreno;
  final bool esIsla;
  final bool esObelisco;
  final int? continente;
  final Map<String, Color> colorTerreno;
  final List<Color> coloresContinente;
  final bool preview;
  final VoidCallback onTap;

  const _Celda({
    required this.coord,
    required this.size,
    required this.terreno,
    required this.esIsla,
    required this.esObelisco,
    required this.continente,
    required this.colorTerreno,
    required this.coloresContinente,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = colorTerreno[terreno] ?? colorTerreno['land']!;
    final colCont = continente == null
        ? null
        : coloresContinente[continente! % coloresContinente.length];

    // En preview las celdas son translúcidas: se ve la imagen del tablero
    // debajo y el terreno queda como una capa de color encima. En modo rejilla
    // el color es sólido, que es más cómodo para pintar.
    final fondo = preview
        // `land` sin definir no se tiñe: deja ver la imagen tal cual.
        ? (terreno == 'land' ? Colors.transparent : base.withOpacity(0.45))
        : base;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fondo,
          border: Border.all(
            color: colCont ??
                (preview ? const Color(0x40FFFFFF) : const Color(0xFF203040)),
            width: colCont != null ? 1.4 : 0.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (esIsla)
              Icon(Icons.star,
                  size: size * 0.5, color: const Color(0xFFE0C060)),
            if (esObelisco)
              Icon(Icons.place,
                  size: size * 0.55, color: colCont ?? const Color(0xFFE0D8C0)),
          ],
        ),
      ),
    );
  }
}
