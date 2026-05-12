// lib/views/mazo_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart';
import '../services/ejercito_service.dart';
import '../services/mazo_service.dart';

// ─────────────────────────────────────────────────────────────
// MAZO SCREEN  (gestión de mazos por ejército)
// ─────────────────────────────────────────────────────────────

/// Mazo de un jugador, extendido con metadatos de la UI
class _MazoPerfil {
  final String id;
  final String nombre;
  final int ejercitoId;
  final bool esPrincipal;
  final List<String> cartaIds; // IDs de cartas
  final int total;

  const _MazoPerfil({
    required this.id,
    required this.nombre,
    required this.ejercitoId,
    required this.esPrincipal,
    required this.cartaIds,
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // Cargar ejércitos, cartas y mazos en paralelo
      final results = await Future.wait([
        EjercitoService().fetchEjercitos(),
        MazoService().fetchTodasLasCartas(),
        _db.collection('Jugadores').doc(_uid).collection('Mazos').get(),
      ]);

      final ejercitos = results[0] as List<EjercitoInfo>;
      final cartas = results[1] as List<CartaModel>;
      final snap = results[2] as QuerySnapshot;

      setState(() {
        _ejercitos = ejercitos;
        _selectedEjercitoId = ejercitos.isNotEmpty ? ejercitos.first.id : 1;
        _todasLasCartas = cartas;
        _mazos = snap.docs.map(_MazoPerfil.fromFirestore).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ── Mazos del ejército activo ─────────────────────────────
  List<_MazoPerfil> get _mazosDelEjercito =>
      _mazos.where((m) => m.ejercitoId == _selectedEjercitoId).toList();

  // ── Cartas del ejército activo ────────────────────────────
  List<CartaModel> get _cartasDelEjercito => _todasLasCartas
      .where((c) =>
          c.ejercito == _selectedEjercitoId &&
          !c.esEvolucion) // Evolución no se puede añadir a un mazo
      .toList();

  // ── Crear mazo vacío ──────────────────────────────────────
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

  // ── Eliminar mazo ─────────────────────────────────────────
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

    // Si era principal, promover el siguiente
    if (mazo.esPrincipal) {
      final resto = _mazosDelEjercito.where((m) => m.id != mazo.id).toList();
      if (resto.isNotEmpty) {
        await _setPrincipal(resto.first);
      }
    }
    await _loadData();
  }

  // ── Marcar como principal ─────────────────────────────────
  Future<void> _setPrincipal(_MazoPerfil mazo) async {
    final batch = _db.batch();
    // Desmarcar todos del ejército
    for (final m in _mazosDelEjercito) {
      batch.update(
        _db.collection('Jugadores').doc(_uid).collection('Mazos').doc(m.id),
        {'esPrincipal': false},
      );
    }
    // Marcar el elegido
    batch.update(
      _db.collection('Jugadores').doc(_uid).collection('Mazos').doc(mazo.id),
      {'esPrincipal': true},
    );
    await batch.commit();
    await _loadData();
  }

  // ── Editar mazo (nombre) ──────────────────────────────────
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

  // ── Abrir constructor de mazo ─────────────────────────────
  void _openBuilder(_MazoPerfil mazo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DeckBuilderScreen(
        mazo: mazo,
        cartasDisponibles: _cartasDelEjercito,
        uid: _uid,
        onSave: _loadData,
      ),
    ));
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
      backgroundColor: const Color(0xFF1A1408),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<String?> _showNombreDialog(String title, String initialValue) async {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF080D18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x405A4820)),
        ),
        title: Text(title,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFC8A860),
              fontFamily: 'Cinzel',
              letterSpacing: 2,
            )),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style:
              const TextStyle(color: Color(0xFFD0B870), fontFamily: 'Cinzel'),
          decoration: InputDecoration(
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0x40503214)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFC8A860)),
            ),
            fillColor: const Color(0xFF050A14),
            filled: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR',
                style:
                    TextStyle(color: Color(0xFF506070), fontFamily: 'Cinzel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('ACEPTAR',
                style:
                    TextStyle(color: Color(0xFFC8A860), fontFamily: 'Cinzel')),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF080D18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x405A4820)),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFFC8A860), fontFamily: 'Cinzel')),
        content: Text(body,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF506070), fontFamily: 'Cinzel')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR',
                style:
                    TextStyle(color: Color(0xFF506070), fontFamily: 'Cinzel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ELIMINAR',
                style:
                    TextStyle(color: Color(0xFFC04040), fontFamily: 'Cinzel')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        elevation: 0,
        title: const Text(
          'MIS MAZOS',
          style: TextStyle(
            fontSize: 15,
            color: Color(0xFFC8A860),
            fontFamily: 'Cinzel',
            letterSpacing: 4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A860)))
          : Column(
              children: [
                // ── Selector de ejército ──
                _EjercitoTabs(
                  ejercitos: _ejercitos,
                  selected: _selectedEjercitoId,
                  onSelect: (id) => setState(() => _selectedEjercitoId = id),
                ),

                const Divider(color: Color(0x20C8A860), height: 1),

                // ── Lista de mazos ──
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
    return Container(
      color: const Color(0xFF02050D),
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
                color: sel
                    ? const Color(0xFFC8A860).withOpacity(0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: sel
                      ? const Color(0xFFC8A860).withOpacity(0.5)
                      : const Color(0x30506070),
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
                      color: sel
                          ? const Color(0xFFC8A860)
                          : const Color(0xFF506070),
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
        // Mazos existentes
        ...mazos.map((m) => _MazoCard(
              mazo: m,
              onEdit: () => onEdit(m),
              onRename: () => onRename(m),
              onDelete: () => onDelete(m),
              onSetPrincipal: () => onSetPrincipal(m),
            )),

        // Slots vacíos
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
    final accent =
        mazo.esPrincipal ? const Color(0xFFC8A860) : const Color(0xFF4060A8);

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF080D18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withOpacity(mazo.esPrincipal ? 0.45 : 0.25),
            width: mazo.esPrincipal ? 1.5 : 1,
          ),
          boxShadow: mazo.esPrincipal
              ? [
                  BoxShadow(
                    color: const Color(0xFFC8A860).withOpacity(0.06),
                    blurRadius: 12,
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                if (mazo.esPrincipal)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.star, size: 14, color: Color(0xFFC8A860)),
                  ),
                Expanded(
                  child: Text(
                    mazo.nombre,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: mazo.esPrincipal
                          ? const Color(0xFFD0B870)
                          : const Color(0xFF8A7858),
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
                      color: const Color(0xFFC8A860).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                          color: const Color(0xFFC8A860).withOpacity(0.3),
                          width: 1),
                    ),
                    child: const Text(
                      'PRINCIPAL',
                      style: TextStyle(
                        fontSize: 7,
                        color: Color(0xFFC8A860),
                        fontFamily: 'Cinzel',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // Menú contextual
                PopupMenuButton<String>(
                  color: const Color(0xFF0A1220),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0x305A4820)),
                  ),
                  icon: const Icon(Icons.more_vert,
                      size: 16, color: Color(0xFF506070)),
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
                    _popupItem('editar', Icons.edit, 'Editar cartas',
                        const Color(0xFFC8A860)),
                    _popupItem('renombrar', Icons.title, 'Renombrar',
                        const Color(0xFF9A8060)),
                    if (!mazo.esPrincipal)
                      _popupItem('principal', Icons.star_outline,
                          'Marcar como principal', const Color(0xFF4ABB58)),
                    _popupItem('eliminar', Icons.delete_outline, 'Eliminar',
                        const Color(0xFFC04040)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Stats
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

  PopupMenuItem<String> _popupItem(
      String value, IconData icon, String label, Color color) {
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
    return GestureDetector(
      onTap: canAdd ? onAdd : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: canAdd ? const Color(0x40C8A860) : const Color(0x20506070),
            width: 1,
            // Simular línea punteada con opacidad baja
          ),
        ),
        child: Center(
          child: canAdd
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_circle_outline,
                        size: 16, color: Color(0xFF7A6040)),
                    SizedBox(width: 8),
                    Text(
                      'CREAR NUEVO MAZO',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF7A6040),
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                )
              : Text(
                  'SLOT $slotNumber — BLOQUEADO',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF2A3040),
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
  final String uid;
  final VoidCallback onSave;

  const _DeckBuilderScreen({
    required this.mazo,
    required this.cartasDisponibles,
    required this.uid,
    required this.onSave,
  });

  @override
  State<_DeckBuilderScreen> createState() => _DeckBuilderScreenState();
}

class _DeckBuilderScreenState extends State<_DeckBuilderScreen> {
  final _db = FirebaseFirestore.instance;
  late Map<String, int> _cantidades; // cartaId → cantidad (0, 1 o 2)
  bool _saving = false;

  int get _total => _cantidades.values.fold(0, (s, v) => s + v);

  @override
  void initState() {
    super.initState();
    // Inicializar con 0 y rellenar con lo guardado
    _cantidades = {for (final c in widget.cartasDisponibles) c.id: 0};
    for (final id in widget.mazo.cartaIds) {
      _cantidades[id] = (_cantidades[id] ?? 0) + 1;
    }
  }

  Future<void> _save() async {
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
    });
    widget.onSave();
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
    }
  }

  void _toggle(String cartaId) {
    final current = _cantidades[cartaId] ?? 0;
    setState(() {
      _cantidades[cartaId] = current >= 2 ? 0 : current + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.mazo.nombre.toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFC8A860),
                fontFamily: 'Cinzel',
                letterSpacing: 2,
              ),
            ),
            Text(
              '$_total cartas seleccionadas',
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF506070),
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
                color: const Color(0xFFC8A860).withOpacity(0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: const Color(0xFFC8A860).withOpacity(0.4), width: 1),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Color(0xFFC8A860), strokeWidth: 2))
                  : const Text(
                      'GUARDAR',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFC8A860),
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: widget.cartasDisponibles.isEmpty
          ? const Center(
              child: Text(
                'No hay cartas para este ejército.',
                style: TextStyle(
                  color: Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  fontSize: 11,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                );
              },
            ),
    );
  }
}

class _CardPickerTile extends StatelessWidget {
  final CartaModel carta;
  final int qty; // 0, 1 o 2
  final VoidCallback onTap;

  const _CardPickerTile({
    required this.carta,
    required this.qty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    final accent = selected ? const Color(0xFFC8A860) : const Color(0xFF2A3040);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC8A860).withOpacity(0.07)
              : const Color(0xFF080D18),
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
              // Fuerza
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

              // Arte placeholder
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

              // Nombre
              Text(
                carta.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 7,
                  color: selected
                      ? const Color(0xFFD0B870)
                      : const Color(0xFF506070),
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),

              // Cantidad
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (i) {
                  final filled = i < qty;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 20,
                    height: 8,
                    decoration: BoxDecoration(
                      color: filled
                          ? const Color(0xFFC8A860).withOpacity(0.70)
                          : const Color(0xFF1A2030),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                          color: filled
                              ? const Color(0xFFC8A860).withOpacity(0.4)
                              : const Color(0x20506070),
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
