// lib/views/edicion_trofeos_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trofeo_model.dart';

/// Pantalla de administración de TROFEOS (solo editores). Lista todos los
/// trofeos definidos y permite crear/editar/borrar cada uno: nombre, descripción,
/// icono, condición de obtención (métrica + operador + objetivo), orden y si está
/// activo. Escribe directamente en la colección Firestore `Trofeos` (mismo patrón
/// que EdicionHistoriasScreen con `Historias`).
class EdicionTrofeosScreen extends StatefulWidget {
  const EdicionTrofeosScreen({super.key});

  @override
  State<EdicionTrofeosScreen> createState() => _EdicionTrofeosScreenState();
}

class _EdicionTrofeosScreenState extends State<EdicionTrofeosScreen> {
  static const _fondo = Color(0xFF060E1A);
  static const _barra = Color(0xFF02050D);
  static const _accent = Color(0xFFA040C0);
  static const _card = Color(0xFF0A1220);
  static const _oro = Color(0xFFC8A860);
  static const _tenue = Color(0xFF506070);

  final _col = FirebaseFirestore.instance.collection('Trofeos');

  bool _loading = true;
  String? _error;
  List<_TrofeoDoc> _trofeos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _col.get();
      final list = snap.docs.map((doc) {
        final d = doc.data();
        final icono = (d['Icono'] ?? d['icono'] ?? '').toString().trim();
        final activoRaw = d['Activo'] ?? d['activo'];
        return _TrofeoDoc(
          id: doc.id,
          nombre: (d['Nombre'] ?? d['nombre'] ?? '').toString(),
          descripcion: (d['Descripcion'] ?? d['descripcion'] ?? '').toString(),
          icono: icono.isEmpty ? '🏆' : icono,
          metrica: (d['Metrica'] ?? d['metrica'] ?? '').toString(),
          operador: (d['Operador'] ?? d['operador'] ?? '>=').toString(),
          objetivo: _int(d['Objetivo'] ?? d['objetivo']),
          orden: _int(d['Orden'] ?? d['orden']),
          activo: activoRaw == null ? true : activoRaw == true,
        );
      }).toList()
        ..sort((a, b) {
          final o = a.orden.compareTo(b.orden);
          return o != 0 ? o : a.nombre.compareTo(b.nombre);
        });
      if (!mounted) return;
      setState(() {
        _trofeos = list;
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

  Future<void> _editar([_TrofeoDoc? existente]) async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditorTrofeo(existente: existente)),
    );
    if (cambiado == true) _load();
  }

  Future<void> _borrar(_TrofeoDoc t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Borrar trofeo',
            style: TextStyle(color: _oro, fontFamily: 'Cinzel', fontSize: 14)),
        content: Text(
          '¿Seguro que quieres borrar "${t.nombre.isEmpty ? t.id : t.nombre}"?\n\n'
          'Los jugadores que ya lo tuvieran conseguido lo conservan en su perfil, '
          'pero dejará de mostrarse.',
          style: const TextStyle(
              color: Color(0xFFB0C0D0), fontSize: 12, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _tenue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar',
                style: TextStyle(color: Color(0xFFE06060))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _col.doc(t.id).delete();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _barra,
        iconTheme: const IconThemeData(color: _accent),
        title: const Text('EDICIÓN · TROFEOS',
            style: TextStyle(
                fontSize: 13,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
                color: _accent)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('NUEVO',
            style: TextStyle(
                fontFamily: 'Cinzel', fontSize: 11, letterSpacing: 1.5)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No se pudieron cargar los trofeos.\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11,
                          color: _tenue,
                          fontFamily: 'Cinzel',
                          height: 1.4),
                    ),
                  ),
                )
              : _trofeos.isEmpty
                  ? const Center(
                      child: Text('No hay trofeos. Pulsa NUEVO para crear uno.',
                          style: TextStyle(
                              color: _tenue,
                              fontFamily: 'Cinzel',
                              fontSize: 11)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _trofeos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = _trofeos[i];
                        return _TrofeoRow(
                          trofeo: t,
                          onEdit: () => _editar(t),
                          onDelete: () => _borrar(t),
                        );
                      },
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Datos de un trofeo cargado
// ─────────────────────────────────────────────────────────────
class _TrofeoDoc {
  final String id;
  final String nombre;
  final String descripcion;
  final String icono;
  final String metrica;
  final String operador;
  final int objetivo;
  final int orden;
  final bool activo;

  const _TrofeoDoc({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
    required this.metrica,
    required this.operador,
    required this.objetivo,
    required this.orden,
    required this.activo,
  });
}

// ─────────────────────────────────────────────────────────────
// Fila de la lista
// ─────────────────────────────────────────────────────────────
class _TrofeoRow extends StatelessWidget {
  final _TrofeoDoc trofeo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TrofeoRow({
    required this.trofeo,
    required this.onEdit,
    required this.onDelete,
  });

  static const _card = Color(0xFF0A1220);
  static const _oro = Color(0xFFC8A860);
  static const _tenue = Color(0xFF506070);

  @override
  Widget build(BuildContext context) {
    final m = TrofeoMetrica.porClave(trofeo.metrica);
    final cond =
        '${m?.label ?? trofeo.metrica} ${trofeo.operador} ${trofeo.objetivo}';
    final activo = trofeo.activo;

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color:
                  (activo ? _oro : _tenue).withOpacity(activo ? 0.35 : 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              child: Text('#${trofeo.orden}',
                  style: const TextStyle(
                      fontSize: 10, color: _tenue, fontFamily: 'Cinzel')),
            ),
            const SizedBox(width: 4),
            Opacity(
              opacity: activo ? 1 : 0.4,
              child: Text(trofeo.icono, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trofeo.nombre.isEmpty
                              ? '(sin nombre)'
                              : trofeo.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Cinzel',
                              fontWeight: FontWeight.bold,
                              color: activo ? const Color(0xFFE0D8C0) : _tenue),
                        ),
                      ),
                      if (!activo)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('OCULTO',
                              style: TextStyle(
                                  fontSize: 7,
                                  letterSpacing: 1,
                                  color: _tenue,
                                  fontFamily: 'Cinzel')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(cond,
                      style: const TextStyle(
                          fontSize: 10, color: _oro, fontFamily: 'Cinzel')),
                  if (trofeo.descripcion.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(trofeo.descripcion.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10, color: _tenue, height: 1.3)),
                  ],
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFE06060)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EDITOR de un trofeo (crear / editar)
// ─────────────────────────────────────────────────────────────
class _EditorTrofeo extends StatefulWidget {
  final _TrofeoDoc? existente;
  const _EditorTrofeo({this.existente});

  @override
  State<_EditorTrofeo> createState() => _EditorTrofeoState();
}

class _EditorTrofeoState extends State<_EditorTrofeo> {
  static const _fondo = Color(0xFF060E1A);
  static const _barra = Color(0xFF02050D);
  static const _accent = Color(0xFFA040C0);
  static const _card = Color(0xFF0A1220);
  static const _oro = Color(0xFFC8A860);
  static const _tenue = Color(0xFF506070);

  static const _operadores = ['>=', '>', '==', '<=', '<'];

  final _col = FirebaseFirestore.instance.collection('Trofeos');

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _iconoCtrl;
  late final TextEditingController _objetivoCtrl;
  late final TextEditingController _ordenCtrl;

  late String _metrica;
  late String _operador;
  late bool _activo;

  bool _saving = false;

  bool get _esNuevo => widget.existente == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _nombreCtrl = TextEditingController(text: e?.nombre ?? '');
    _descCtrl = TextEditingController(text: e?.descripcion ?? '');
    _iconoCtrl = TextEditingController(text: e?.icono ?? '🏆');
    _objetivoCtrl = TextEditingController(text: (e?.objetivo ?? 1).toString());
    _ordenCtrl = TextEditingController(text: (e?.orden ?? 0).toString());
    _metrica = e?.metrica.isNotEmpty == true
        ? e!.metrica
        : TrofeoMetrica.todas.first.clave;
    // Si la métrica guardada ya no existe en el catálogo, cae a la primera.
    if (TrofeoMetrica.porClave(_metrica) == null) {
      _metrica = TrofeoMetrica.todas.first.clave;
    }
    _operador = _operadores.contains(e?.operador) ? e!.operador : '>=';
    _activo = e?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    _iconoCtrl.dispose();
    _objetivoCtrl.dispose();
    _ordenCtrl.dispose();
    super.dispose();
  }

  static int _int(String s, {int fallback = 0}) =>
      int.tryParse(s.trim()) ?? fallback;

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacío.')),
      );
      return;
    }

    setState(() => _saving = true);
    final icono = _iconoCtrl.text.trim();
    final data = <String, dynamic>{
      'Nombre': nombre,
      'Descripcion': _descCtrl.text.trim(),
      'Icono': icono.isEmpty ? '🏆' : icono,
      'Metrica': _metrica,
      'Operador': _operador,
      'Objetivo': _int(_objetivoCtrl.text, fallback: 1),
      'Orden': _int(_ordenCtrl.text),
      'Activo': _activo,
    };

    try {
      if (_esNuevo) {
        await _col.add(data);
      } else {
        await _col.doc(widget.existente!.id).set(data, SetOptions(merge: true));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metricaSel = TrofeoMetrica.porClave(_metrica);

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _barra,
        iconTheme: const IconThemeData(color: _accent),
        title: Text(_esNuevo ? 'NUEVO TROFEO' : 'EDITAR TROFEO',
            style: const TextStyle(
                fontSize: 13,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
                color: _accent)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _guardar,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _accent))
                : const Text('GUARDAR',
                    style: TextStyle(
                        color: _accent,
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label('NOMBRE'),
          _campo(_nombreCtrl, hint: 'p. ej. Veterano de guerra'),
          const SizedBox(height: 16),
          _label('DESCRIPCIÓN'),
          _campo(_descCtrl, hint: 'Texto explicativo (opcional)', maxLines: 3),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('ICONO'),
                    _campo(_iconoCtrl, hint: '🏆', center: true),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('ORDEN'),
                    _campo(_ordenCtrl,
                        hint: '0',
                        keyboard: TextInputType.number,
                        soloDigitos: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _label('CONDICIÓN DE OBTENCIÓN'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _tenue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _subLabel('MÉTRICA'),
                const SizedBox(height: 6),
                _dropdownMetrica(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _subLabel('OPERADOR'),
                          const SizedBox(height: 6),
                          _dropdownOperador(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _subLabel('OBJETIVO'),
                          const SizedBox(height: 6),
                          _campo(_objetivoCtrl,
                              hint: '100',
                              keyboard: TextInputType.number,
                              soloDigitos: true),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Vista previa de la condición.
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _oro.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _oro.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Se consigue cuando  '
                    '${metricaSel?.label ?? _metrica} '
                    '$_operador ${_objetivoCtrl.text.trim().isEmpty ? '?' : _objetivoCtrl.text.trim()}',
                    style: const TextStyle(
                        color: _oro, fontSize: 11, fontFamily: 'Cinzel'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Activo.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _tenue.withOpacity(0.3)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: _accent,
              title: const Text('Activo',
                  style: TextStyle(
                      color: Color(0xFFE0D8C0),
                      fontFamily: 'Cinzel',
                      fontSize: 12)),
              subtitle: const Text(
                  'Si se desactiva, deja de mostrarse y de otorgarse.',
                  style: TextStyle(color: _tenue, fontSize: 10)),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 8,
                letterSpacing: 1.5,
                color: _oro,
                fontFamily: 'Cinzel')),
      );

  Widget _subLabel(String t) => Text(t,
      style: const TextStyle(
          fontSize: 8, letterSpacing: 1, color: _tenue, fontFamily: 'Cinzel'));

  Widget _campo(
    TextEditingController c, {
    String hint = '',
    int maxLines = 1,
    bool center = false,
    TextInputType keyboard = TextInputType.text,
    bool soloDigitos = false,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      textAlign: center ? TextAlign.center : TextAlign.start,
      onChanged: (_) => setState(() {}),
      inputFormatters:
          soloDigitos ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: Color(0xFFE0D8C0), fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: _tenue, fontSize: 12),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: _tenue.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _oro),
        ),
      ),
    );
  }

  Widget _dropdownMetrica() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tenue.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _metrica,
          isExpanded: true,
          dropdownColor: _card,
          icon: const Icon(Icons.arrow_drop_down, color: _accent),
          style: const TextStyle(color: Color(0xFFE0D8C0), fontSize: 12),
          items: [
            for (final m in TrofeoMetrica.todas)
              DropdownMenuItem(
                value: m.clave,
                child: Text('${m.icono}  ${m.label}',
                    style: const TextStyle(fontFamily: 'Cinzel', fontSize: 12)),
              ),
          ],
          onChanged: (v) => setState(() => _metrica = v ?? _metrica),
        ),
      ),
    );
  }

  Widget _dropdownOperador() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tenue.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _operador,
          isExpanded: true,
          dropdownColor: _card,
          icon: const Icon(Icons.arrow_drop_down, color: _accent),
          style: const TextStyle(color: Color(0xFFE0D8C0), fontSize: 14),
          items: [
            for (final op in _operadores)
              DropdownMenuItem(
                value: op,
                child: Text(op,
                    style: const TextStyle(fontFamily: 'Cinzel', fontSize: 14)),
              ),
          ],
          onChanged: (v) => setState(() => _operador = v ?? _operador),
        ),
      ),
    );
  }
}
