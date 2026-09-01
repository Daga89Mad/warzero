// lib/views/mazo_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart';
import '../services/warzero_api.dart';
import '../services/settings_controller.dart';
import '../widgets/card_detail_overlay.dart';

// ─────────────────────────────────────────────────────────────
// MAZO SCREEN  (gestión de mazos por ejército)
// ─────────────────────────────────────────────────────────────

/// Mazo de un jugador, extendido con metadatos de la UI
class _MazoPerfil {
  final String id;
  final String nombre;
  final int ejercitoId;
  final bool esPrincipal;
  final List<String> cartaIds; // IDs de cartas (mazo repartible, máx. 8)

  /// IDs de cartas ESPECIALES seleccionadas para el cuartel (máx. 3). Se
  /// guardan aparte de [cartaIds] porque las especiales NO se reparten: solo
  /// definen cuáles pueden comprarse en el cuartel durante la partida.
  final List<String> especialesIds;

  final int total;

  const _MazoPerfil({
    required this.id,
    required this.nombre,
    required this.ejercitoId,
    required this.esPrincipal,
    required this.cartaIds,
    this.especialesIds = const [],
    required this.total,
  });

  factory _MazoPerfil.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return _MazoPerfil(
      id: doc.id,
      nombre: d['nombre'] as String? ?? 'Mazo sin nombre',
      ejercitoId: (d['ejercitoId'] as num?)?.toInt() ?? 1,
      esPrincipal: d['esPrincipal'] as bool? ?? false,
      cartaIds: List<String>.from(d['cartaIds'] as List? ?? []),
      especialesIds: List<String>.from(d['especialesIds'] as List? ?? []),
      total: (d['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Igual que [fromFirestore] pero desde el JSON de la API (GET /warzero/mismazos).
  factory _MazoPerfil.fromMap(Map<String, dynamic> d) {
    return _MazoPerfil(
      id: d['id'] as String? ?? '',
      nombre: d['nombre'] as String? ?? 'Mazo sin nombre',
      ejercitoId: (d['ejercitoId'] as num?)?.toInt() ?? 1,
      esPrincipal: d['esPrincipal'] as bool? ?? false,
      cartaIds: List<String>.from(d['cartaIds'] as List? ?? []),
      especialesIds: List<String>.from(d['especialesIds'] as List? ?? []),
      total: (d['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class MazoScreen extends StatefulWidget {
  const MazoScreen({super.key});

  @override
  State<MazoScreen> createState() => _MazoScreenState();
}

class _MazoScreenState extends State<MazoScreen> {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  int _selectedEjercitoId = 1;
  List<EjercitoInfo> _ejercitos = [];
  List<_MazoPerfil> _mazos = [];
  List<CartaModel> _todasLasCartas = [];
  bool _loading = true;
  bool _error = false;
  final _api = WarZeroApi();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  EjercitoInfo _ejercitoFromMap(Map<String, dynamic> m) => EjercitoInfo(
        id: (m['id'] as num?)?.toInt() ?? 0,
        nombre: (m['nombre'] as String?)?.isNotEmpty == true
            ? m['nombre'] as String
            : 'Ejército ${m['id']}',
        descripcion: m['descripcion'] as String? ?? '',
        icono: (m['icono'] as String?)?.isNotEmpty == true
            ? m['icono'] as String
            : '⚔️',
      );

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final data = await _api.obtenerMisMazos(_uid);

      final ejercitos = ((data['ejercitos'] as List?) ?? [])
          .map((e) => _ejercitoFromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final cartas = ((data['cartas'] as List?) ?? [])
          .map((e) => CartaModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final mazos = ((data['mazos'] as List?) ?? [])
          .map((e) => _MazoPerfil.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      if (!mounted) return;
      setState(() {
        _ejercitos = ejercitos.isNotEmpty ? ejercitos : kEjercitos;
        _selectedEjercitoId = _ejercitos.isNotEmpty ? _ejercitos.first.id : 1;
        _todasLasCartas = cartas;
        _mazos = mazos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _retry() => _loadData();

  List<_MazoPerfil> get _mazosDelEjercito =>
      _mazos.where((m) => m.ejercitoId == _selectedEjercitoId).toList();

  List<CartaModel> get _cartasDelEjercito => _todasLasCartas
      .where((c) =>
          c.ejercito == _selectedEjercitoId && !c.esEvolucion && !c.esEspecial)
      .toList();

  /// Cartas ESPECIALES del ejército seleccionado, ordenadas de forma estable
  /// (por número y luego coste) para que la preselección por defecto sea
  /// determinista.
  List<CartaModel> get _especialesDelEjercito => _todasLasCartas
      .where((c) => c.ejercito == _selectedEjercitoId && c.esEspecial)
      .toList()
    ..sort((a, b) {
      final n = a.numero.compareTo(b.numero);
      return n != 0 ? n : a.coste.compareTo(b.coste);
    });

  Future<void> _crearMazo() async {
    if (_mazosDelEjercito.length >= 3) {
      _showToast('Máximo 3 mazos por ejército');
      return;
    }
    final ejInfo = _ejercitos.firstWhere((e) => e.id == _selectedEjercitoId,
        orElse: () => EjercitoInfo(
            id: _selectedEjercitoId,
            nombre: 'Ejército',
            descripcion: '',
            icono: '⚔️'));

    final nombre = await _showNombreDialog(
        'NUEVO MAZO', '${ejInfo.nombre} ${_mazosDelEjercito.length + 1}');
    if (nombre == null) return;

    final esPrimero = _mazosDelEjercito.isEmpty;
    await _db.collection('Jugadores').doc(_uid).collection('Mazos').add({
      'nombre': nombre,
      'ejercitoId': _selectedEjercitoId,
      'esPrincipal': esPrimero,
      'cartaIds': [],
      'total': 0,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    await _loadData();
  }

  Future<void> _eliminarMazo(_MazoPerfil mazo) async {
    final confirm = await _showConfirmDialog(
        '¿Eliminar "${mazo.nombre}"?', 'Esta acción no se puede deshacer.');
    if (!confirm) return;

    await _db
        .collection('Jugadores')
        .doc(_uid)
        .collection('Mazos')
        .doc(mazo.id)
        .delete();

    setState(() {
      _mazos = _mazos.where((m) => m.id != mazo.id).toList();
    });

    if (mazo.esPrincipal) {
      final resto = _mazosDelEjercito;
      if (resto.isNotEmpty) {
        await _setPrincipal(resto.first);
      }
    }
    await _loadData();
  }

  Future<void> _setPrincipal(_MazoPerfil mazo) async {
    final batch = _db.batch();
    for (final m in _mazosDelEjercito) {
      batch.update(
        _db.collection('Jugadores').doc(_uid).collection('Mazos').doc(m.id),
        {'esPrincipal': false},
      );
    }
    batch.update(
      _db.collection('Jugadores').doc(_uid).collection('Mazos').doc(mazo.id),
      {'esPrincipal': true},
    );
    await batch.commit();
    await _loadData();
  }

  Future<void> _renombrarMazo(_MazoPerfil mazo) async {
    final nombre = await _showNombreDialog('RENOMBRAR MAZO', mazo.nombre);
    if (nombre == null) return;
    await _db
        .collection('Jugadores')
        .doc(_uid)
        .collection('Mazos')
        .doc(mazo.id)
        .update({'nombre': nombre});
    await _loadData();
  }

  void _openBuilder(_MazoPerfil mazo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DeckBuilderScreen(
        mazo: mazo,
        cartasDisponibles: _cartasDelEjercito,
        especialesDisponibles: _especialesDelEjercito,
        todasLasCartas: _todasLasCartas,
        uid: _uid,
        onSave: _loadData,
      ),
    ));
  }

  void _showToast(String msg) {
    final war = context.war;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
      backgroundColor: war.superficie,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<String?> _showNombreDialog(String title, String initialValue) async {
    final war = context.war;
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: war.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: war.borde.withOpacity(0.4)),
        ),
        title: Text(title,
            style: TextStyle(
              fontSize: 13,
              color: war.primario,
              fontFamily: 'Cinzel',
              letterSpacing: 2,
            )),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: war.texto, fontFamily: 'Cinzel'),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: war.borde.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: war.primario),
            ),
            fillColor: war.fondo,
            filled: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCELAR',
                style: TextStyle(color: war.textoTenue, fontFamily: 'Cinzel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text('ACEPTAR',
                style: TextStyle(color: war.primario, fontFamily: 'Cinzel')),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String body) async {
    final war = context.war;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: war.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: war.borde.withOpacity(0.4)),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: 13, color: war.primario, fontFamily: 'Cinzel')),
        content: Text(body,
            style: TextStyle(
                fontSize: 10, color: war.textoTenue, fontFamily: 'Cinzel')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCELAR',
                style: TextStyle(color: war.textoTenue, fontFamily: 'Cinzel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ELIMINAR',
                style: TextStyle(color: war.error, fontFamily: 'Cinzel')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        title: Text(
          'MIS MAZOS',
          style: TextStyle(
            fontSize: 15,
            color: war.primario,
            fontFamily: 'Cinzel',
            letterSpacing: 4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: war.primario))
          : _error
              ? _MazosErrorState(onRetry: _retry)
              : Column(
                  children: [
                    _EjercitoTabs(
                      ejercitos: _ejercitos,
                      selected: _selectedEjercitoId,
                      onSelect: (id) =>
                          setState(() => _selectedEjercitoId = id),
                    ),
                    Divider(color: war.primario.withOpacity(0.12), height: 1),
                    Expanded(
                      child: _MazoList(
                        mazos: _mazosDelEjercito,
                        canAdd: _mazosDelEjercito.length < 3,
                        onAdd: _crearMazo,
                        onEdit: _openBuilder,
                        onRename: _renombrarMazo,
                        onDelete: _eliminarMazo,
                        onSetPrincipal: _setPrincipal,
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ESTADO DE ERROR / REINTENTO
// ─────────────────────────────────────────────────────────────
class _MazosErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _MazosErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 40, color: war.error),
          const SizedBox(height: 12),
          Text('No se pudieron cargar los mazos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: war.texto, fontFamily: 'Cinzel', fontSize: 11)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh, size: 16, color: war.primario),
            label: Text('REINTENTAR',
                style: TextStyle(
                    color: war.primario,
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    letterSpacing: 1.5)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: war.primario.withOpacity(0.35)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TABS DE EJÉRCITO
// ─────────────────────────────────────────────────────────────
class _EjercitoTabs extends StatelessWidget {
  final List<EjercitoInfo> ejercitos;
  final int selected;
  final void Function(int) onSelect;

  const _EjercitoTabs({
    required this.ejercitos,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      color: war.superficie,
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: ejercitos.map((e) {
          final sel = e.id == selected;
          return GestureDetector(
            onTap: () => onSelect(e.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:
                    sel ? war.primario.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: sel
                      ? war.primario.withOpacity(0.5)
                      : war.borde.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.icono, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    e.nombre,
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                      color: sel ? war.primario : war.textoTenue,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA DE MAZOS DEL EJÉRCITO SELECCIONADO
// ─────────────────────────────────────────────────────────────
class _MazoList extends StatelessWidget {
  final List<_MazoPerfil> mazos;
  final bool canAdd;
  final VoidCallback onAdd;
  final void Function(_MazoPerfil) onEdit;
  final void Function(_MazoPerfil) onRename;
  final void Function(_MazoPerfil) onDelete;
  final void Function(_MazoPerfil) onSetPrincipal;

  const _MazoList({
    required this.mazos,
    required this.canAdd,
    required this.onAdd,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onSetPrincipal,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        ...mazos.map((m) => _MazoCard(
              mazo: m,
              onEdit: () => onEdit(m),
              onRename: () => onRename(m),
              onDelete: () => onDelete(m),
              onSetPrincipal: () => onSetPrincipal(m),
            )),
        for (int i = mazos.length; i < 3; i++)
          _EmptySlot(
            slotNumber: i + 1,
            canAdd: canAdd && i == mazos.length,
            onAdd: onAdd,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TARJETA DE MAZO
// ─────────────────────────────────────────────────────────────
class _MazoCard extends StatelessWidget {
  final _MazoPerfil mazo;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onSetPrincipal;

  const _MazoCard({
    required this.mazo,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onSetPrincipal,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    // Principal → dorado del tema; secundario → azul semántico.
    final accent = mazo.esPrincipal ? war.primario : const Color(0xFF4060A8);

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withOpacity(mazo.esPrincipal ? 0.45 : 0.25),
            width: mazo.esPrincipal ? 1.5 : 1,
          ),
          boxShadow: mazo.esPrincipal
              ? [
                  BoxShadow(
                    color: war.primario.withOpacity(0.06),
                    blurRadius: 12,
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (mazo.esPrincipal)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.star, size: 14, color: war.primario),
                  ),
                Expanded(
                  child: Text(
                    mazo.nombre,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: mazo.esPrincipal ? war.primario : war.texto,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (mazo.esPrincipal)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: war.primario.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                          color: war.primario.withOpacity(0.3), width: 1),
                    ),
                    child: Text(
                      'PRINCIPAL',
                      style: TextStyle(
                        fontSize: 7,
                        color: war.primario,
                        fontFamily: 'Cinzel',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  color: war.superficie,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: war.borde.withOpacity(0.3)),
                  ),
                  icon: Icon(Icons.more_vert, size: 16, color: war.textoTenue),
                  onSelected: (v) {
                    switch (v) {
                      case 'editar':
                        onEdit();
                        break;
                      case 'renombrar':
                        onRename();
                        break;
                      case 'principal':
                        onSetPrincipal();
                        break;
                      case 'eliminar':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    _popupItem(context, 'editar', Icons.edit, 'Editar cartas',
                        war.primario),
                    _popupItem(context, 'renombrar', Icons.title, 'Renombrar',
                        war.texto),
                    if (!mazo.esPrincipal)
                      _popupItem(context, 'principal', Icons.star_outline,
                          'Marcar como principal', war.secundario),
                    _popupItem(context, 'eliminar', Icons.delete_outline,
                        'Eliminar', war.error),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatChip(
                  icon: Icons.style,
                  label: '${mazo.total} cartas',
                  color: accent,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.edit_outlined,
                  label: 'EDITAR MAZO',
                  color: accent.withOpacity(0.7),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _popupItem(BuildContext context, String value,
      IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontFamily: 'Cinzel',
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SLOT VACÍO
// ─────────────────────────────────────────────────────────────
class _EmptySlot extends StatelessWidget {
  final int slotNumber;
  final bool canAdd;
  final VoidCallback onAdd;

  const _EmptySlot({
    required this.slotNumber,
    required this.canAdd,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return GestureDetector(
      onTap: canAdd ? onAdd : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: canAdd
                ? war.primario.withOpacity(0.25)
                : war.borde.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Center(
          child: canAdd
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline,
                        size: 16, color: war.textoTenue),
                    const SizedBox(width: 8),
                    Text(
                      'CREAR NUEVO MAZO',
                      style: TextStyle(
                        fontSize: 10,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                )
              : Text(
                  'SLOT $slotNumber — BLOQUEADO',
                  style: TextStyle(
                    fontSize: 9,
                    color: war.borde,
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DECK BUILDER  (editor de cartas de un mazo)
// ─────────────────────────────────────────────────────────────
class _DeckBuilderScreen extends StatefulWidget {
  final _MazoPerfil mazo;
  final List<CartaModel> cartasDisponibles;

  /// Cartas ESPECIALES del ejército, entre las que se eligen las (máx. 3) que
  /// aparecerán en el cuartel durante la partida.
  final List<CartaModel> especialesDisponibles;

  /// Lista COMPLETA de cartas del ejército (incluidas las de evolución, que
  /// `cartasDisponibles` no contiene). Se usa para resolver, en local, la carta
  /// a la que evoluciona cada carta base y así poder mostrar la flecha de
  /// evolución al ampliar la carta.
  final List<CartaModel> todasLasCartas;

  final String uid;
  final VoidCallback onSave;

  const _DeckBuilderScreen({
    required this.mazo,
    required this.cartasDisponibles,
    required this.especialesDisponibles,
    required this.todasLasCartas,
    required this.uid,
    required this.onSave,
  });

  @override
  State<_DeckBuilderScreen> createState() => _DeckBuilderScreenState();
}

class _DeckBuilderScreenState extends State<_DeckBuilderScreen> {
  final _db = FirebaseFirestore.instance;
  late Map<String, int> _cantidades;
  bool _saving = false;

  static const int _maxCartasMazo = 8;
  static const int _maxEspeciales = 3;

  /// IDs de especiales seleccionadas para el cuartel (máx. [_maxEspeciales]).
  late Set<String> _especialesSel;

  int get _total => _cantidades.values.fold(0, (s, v) => s + v);
  int get _totalEspeciales => _especialesSel.length;

  @override
  void initState() {
    super.initState();
    _cantidades = {for (final c in widget.cartasDisponibles) c.id: 0};

    // Saneo: el tope de 8 solo se aplicaba al guardar, así que un mazo antiguo
    // (o editado fuera del editor) podía tener en Firestore más de 8 ids,
    // duplicados o ids que ya no existen en el catálogo. Aquí nos quedamos con
    // las primeras [_maxCartasMazo] cartas VÁLIDAS y DISTINTAS en el orden
    // guardado, y si el mazo guardado no coincide con eso lo reescribimos para
    // dejarlo canónico (≤8, sin duplicados ni ids inválidos).
    final saneados = <String>[];
    for (final id in widget.mazo.cartaIds) {
      if (saneados.length >= _maxCartasMazo) break;
      if (!_cantidades.containsKey(id)) continue; // no está en el catálogo
      if (_cantidades[id] == 1) continue; // duplicado (ya añadida)
      _cantidades[id] = 1;
      saneados.add(id);
    }

    // Como [saneados] solo filtra/recorta (nunca reordena), una longitud
    // distinta a la guardada implica que algo se descartó → hay que persistir.
    if (saneados.length != widget.mazo.cartaIds.length) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _persistirSaneo(saneados));
    }

    // Especiales: preselección provisional a partir de lo que trae el perfil.
    // Se refina con la lectura real de Firestore en [_cargarEspeciales].
    _especialesSel = {...widget.mazo.especialesIds};
    _cargarEspeciales();
  }

  /// Carga las especiales seleccionadas del mazo desde Firestore (fuente de
  /// verdad, por si la API que llenó el perfil no incluía `especialesIds`) y
  /// aplica los defaults:
  ///   • Se descartan ids que ya no existan en el catálogo del ejército.
  ///   • Si no hay ninguna guardada, se preseleccionan las del ejército
  ///     (hasta [_maxEspeciales]) → así los 3 especiales existentes son las
  ///     3 por defecto automáticamente.
  ///   • Recorte de seguridad a [_maxEspeciales].
  Future<void> _cargarEspeciales() async {
    Set<String> sel = {...widget.mazo.especialesIds};
    try {
      final doc = await _db
          .collection('Jugadores')
          .doc(widget.uid)
          .collection('Mazos')
          .doc(widget.mazo.id)
          .get();
      final raw = doc.data()?['especialesIds'];
      if (raw is List) sel = raw.map((e) => e.toString()).toSet();
    } catch (_) {
      // Silencioso: nos quedamos con la preselección del perfil.
    }

    final validas = widget.especialesDisponibles.map((c) => c.id).toSet();
    sel = sel.where(validas.contains).toSet();

    // Default: si no hay ninguna, preseleccionar las del ejército (≤ máx.).
    if (sel.isEmpty) {
      sel = widget.especialesDisponibles
          .take(_maxEspeciales)
          .map((c) => c.id)
          .toSet();
    } else if (sel.length > _maxEspeciales) {
      sel = sel.take(_maxEspeciales).toSet();
    }

    if (mounted) setState(() => _especialesSel = sel);
  }

  void _toggleEspecial(String id) {
    if (_especialesSel.contains(id)) {
      setState(() => _especialesSel.remove(id));
      return;
    }
    if (_especialesSel.length >= _maxEspeciales) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('El cuartel admite como máximo $_maxEspeciales '
              'especiales'),
          duration: Duration(seconds: 2),
        ));
      return;
    }
    setState(() => _especialesSel.add(id));
  }

  /// Reescribe en Firestore el mazo ya saneado (≤8, sin duplicados ni ids
  /// inválidos). Silencioso: si falla, el recorte del servidor sigue cubriendo
  /// la lectura, así que no molestamos al usuario mientras edita.
  Future<void> _persistirSaneo(List<String> ids) async {
    try {
      await _db
          .collection('Jugadores')
          .doc(widget.uid)
          .collection('Mazos')
          .doc(widget.mazo.id)
          .update({'cartaIds': ids, 'total': ids.length});
    } catch (_) {
      // Silencioso a propósito.
    }
  }

  Future<void> _save() async {
    if (_total > _maxCartasMazo) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Quita cartas: el máximo es $_maxCartasMazo'),
          duration: Duration(seconds: 2),
        ));
      return;
    }
    setState(() => _saving = true);
    final expandido = <String>[];
    for (final entry in _cantidades.entries) {
      for (int i = 0; i < entry.value; i++) {
        expandido.add(entry.key);
      }
    }
    await _db
        .collection('Jugadores')
        .doc(widget.uid)
        .collection('Mazos')
        .doc(widget.mazo.id)
        .update({
      'cartaIds': expandido,
      'total': expandido.length,
      'especialesIds': _especialesSel.toList(),
    });
    widget.onSave();
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
    }
  }

  void _toggle(String cartaId) {
    final current = _cantidades[cartaId] ?? 0;
    if (current >= 1) {
      setState(() => _cantidades[cartaId] = 0);
      return;
    }
    if (_total >= _maxCartasMazo) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('El mazo está limitado a $_maxCartasMazo cartas'),
          duration: Duration(seconds: 2),
        ));
      return;
    }
    setState(() => _cantidades[cartaId] = 1);
  }

  /// Resuelve, en local, la carta a la que evoluciona [idEvolucion] buscándola
  /// en la lista completa del ejército. Se pasa a `showCardDetail` para que la
  /// carta ampliada muestre la flecha de evolución (y su cara evolucionada).
  Future<CartaModel?> _resolverEvolucion(String idEvolucion) async {
    for (final c in widget.todasLasCartas) {
      if (c.id == idEvolucion) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.mazo.nombre.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                color: war.primario,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
              ),
            ),
            Text(
              '$_total / $_maxCartasMazo cartas',
              style: TextStyle(
                fontSize: 9,
                color: war.textoTenue,
                fontFamily: 'Cinzel',
              ),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: war.primario.withOpacity(0.14),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: war.primario.withOpacity(0.4), width: 1),
              ),
              child: _saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: war.primario, strokeWidth: 2))
                  : Text(
                      'GUARDAR',
                      style: TextStyle(
                        fontSize: 10,
                        color: war.primario,
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildEspecialesBar(),
          Expanded(
            child: widget.cartasDisponibles.isEmpty
                ? Center(
                    child: Text(
                      'No hay cartas para este ejército.',
                      style: TextStyle(
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: widget.cartasDisponibles.length,
                    itemBuilder: (_, i) {
                      final carta = widget.cartasDisponibles[i];
                      final qty = _cantidades[carta.id] ?? 0;
                      return _CardPickerTile(
                        carta: carta,
                        qty: qty,
                        onTap: () => _toggle(carta.id),
                        // Pulsación larga: abrir la carta en grande (misma
                        // vista de detalle que en la colección / tablero). Se
                        // pasa el resolvedor de evolución para que salga la
                        // flecha que permite ver la carta a la que evoluciona.
                        onLongPress: () => showCardDetail(
                          context,
                          carta,
                          resolveEvolucion: _resolverEvolucion,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Barra superior con las cartas ESPECIALES del ejército. El jugador elige
  /// cuáles (máx. [_maxEspeciales]) aparecerán en el cuartel durante la
  /// partida. Si el ejército no tiene especiales, no se muestra nada.
  Widget _buildEspecialesBar() {
    final war = context.war;
    if (widget.especialesDisponibles.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: war.superficie,
        border: Border(
          bottom: BorderSide(color: war.primario.withOpacity(0.12)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Text(
                'ESPECIALES DEL CUARTEL',
                style: TextStyle(
                  fontSize: 10,
                  color: war.primario,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '$_totalEspeciales / $_maxEspeciales',
                style: TextStyle(
                  fontSize: 10,
                  color: war.textoTenue,
                  fontFamily: 'Cinzel',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.especialesDisponibles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final carta = widget.especialesDisponibles[i];
                return _EspecialPickerTile(
                  carta: carta,
                  selected: _especialesSel.contains(carta.id),
                  onTap: () => _toggleEspecial(carta.id),
                  onLongPress: () => showCardDetail(context, carta),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TILE DE CARTA ESPECIAL (selector del cuartel)
// ─────────────────────────────────────────────────────────────
class _EspecialPickerTile extends StatelessWidget {
  final CartaModel carta;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _EspecialPickerTile({
    required this.carta,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = selected ? war.primario : war.borde;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 74,
        decoration: BoxDecoration(
          color: selected ? war.primario.withOpacity(0.07) : war.fondo,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withOpacity(selected ? 0.55 : 0.20),
            width: selected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: carta.imagen.isNotEmpty
                        ? Image.network(
                            carta.imagen,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.star,
                              size: 26,
                              color: accent.withOpacity(0.5),
                            ),
                          )
                        : Icon(Icons.star,
                            size: 26, color: accent.withOpacity(0.5)),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: selected
                          ? war.primario
                          : war.textoTenue.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              carta.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 7,
                color: selected ? war.texto : war.textoTenue,
                fontFamily: 'Cinzel',
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardPickerTile extends StatelessWidget {
  final CartaModel carta;
  final int qty; // 0 o 1
  final VoidCallback onTap;

  /// Pulsación larga: abre la carta en grande (vista de detalle). Opcional.
  final VoidCallback? onLongPress;

  const _CardPickerTile({
    required this.carta,
    required this.qty,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final selected = qty > 0;
    final accent = selected ? war.primario : war.borde;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? war.primario.withOpacity(0.07) : war.superficie,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withOpacity(selected ? 0.50 : 0.18),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '${carta.fuerza}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: accent,
                    fontFamily: 'Cinzel',
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Center(
                  child: carta.imagen.isNotEmpty
                      ? Image.network(carta.imagen,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                                Icons.shield_outlined,
                                size: 32,
                                color: accent.withOpacity(0.5),
                              ))
                      : Icon(Icons.shield_outlined,
                          size: 32, color: accent.withOpacity(0.5)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                carta.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 7,
                  color: selected ? war.texto : war.textoTenue,
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(1, (i) {
                  final filled = i < qty;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 20,
                    height: 8,
                    decoration: BoxDecoration(
                      color: filled
                          ? war.primario.withOpacity(0.70)
                          : war.borde.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                          color: filled
                              ? war.primario.withOpacity(0.4)
                              : war.borde.withOpacity(0.2),
                          width: 0.5),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
