// lib/views/crear_carta_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart'; // kEjercitos
import 'seleccionar_carta_screen.dart';

/// Pantalla para crear o editar una carta.
///
/// Si [cartaEditar] es null → modo creación (Firestore `.add()`).
/// Si [cartaEditar] no es null → modo edición (Firestore `.update()`).
class CrearCartaScreen extends StatefulWidget {
  final CartaModel? cartaEditar;

  const CrearCartaScreen({super.key, this.cartaEditar});

  @override
  State<CrearCartaScreen> createState() => _CrearCartaScreenState();
}

class _CrearCartaScreenState extends State<CrearCartaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;

  bool get _editMode => widget.cartaEditar != null;

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late final TextEditingController _imagenCtrl;
  late final TextEditingController _fuerzaCtrl;
  late final TextEditingController _defensaCtrl;
  late final TextEditingController _costeCtrl;
  late final TextEditingController _idHabilidadCtrl;
  late final TextEditingController _movimientoCtrl;
  late final TextEditingController _evolucionCosteCtrl;

  late int _ejercito;
  late int _tipo;
  late CondicionCarta _condicion;
  CartaModel? _evolucionCarta;
  bool _saving = false;
  bool _loadingEvol = false;

  @override
  void initState() {
    super.initState();
    final c = widget.cartaEditar;
    _nombreCtrl = TextEditingController(text: c?.nombre ?? '');
    _descripcionCtrl = TextEditingController(text: c?.descripcion ?? '');
    _imagenCtrl = TextEditingController(text: c?.imagen ?? '');
    _fuerzaCtrl = TextEditingController(text: '${c?.fuerza ?? 1}');
    _defensaCtrl = TextEditingController(text: '${c?.defensa ?? 0}');
    _costeCtrl = TextEditingController(text: '${c?.coste ?? 1}');
    _idHabilidadCtrl = TextEditingController(text: '${c?.idHabilidad ?? 0}');
    _movimientoCtrl = TextEditingController(text: '${c?.movimiento ?? 1}');
    _evolucionCosteCtrl = TextEditingController(text: '${c?.evolucion ?? 0}');
    _ejercito = c?.ejercito ?? 1;
    _tipo = c?.tipo ?? 1;
    _condicion = c?.condicion ?? CondicionCarta.basica;

    // Cargar carta de evolución si existe
    if (c != null && c.idEvolucion.isNotEmpty) {
      _cargarEvolucion(c.idEvolucion);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _imagenCtrl.dispose();
    _fuerzaCtrl.dispose();
    _defensaCtrl.dispose();
    _costeCtrl.dispose();
    _idHabilidadCtrl.dispose();
    _movimientoCtrl.dispose();
    _evolucionCosteCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarEvolucion(String id) async {
    setState(() => _loadingEvol = true);
    try {
      final doc = await _db.collection('Cartas').doc(id).get();
      if (doc.exists && mounted) {
        setState(() {
          _evolucionCarta = CartaModel.fromFirestore(doc);
          _loadingEvol = false;
        });
      } else {
        if (mounted) setState(() => _loadingEvol = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEvol = false);
    }
  }

  Future<void> _seleccionarEvolucion() async {
    final result = await Navigator.of(context).push<CartaModel>(
      MaterialPageRoute(
        builder: (_) => SeleccionarCartaScreen(
          excluirId: widget.cartaEditar?.id,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _evolucionCarta = result);
    }
  }

  Map<String, dynamic> _buildData() => {
        'Nombre': _nombreCtrl.text.trim(),
        'Descripcion': _descripcionCtrl.text.trim(),
        'Ejercito': _ejercito,
        'Fuerza': int.tryParse(_fuerzaCtrl.text) ?? 1,
        'Defensa': int.tryParse(_defensaCtrl.text) ?? 0,
        'Coste': int.tryParse(_costeCtrl.text) ?? 1,
        'IdHabilidad': int.tryParse(_idHabilidadCtrl.text) ?? 0,
        'Imagen': _imagenCtrl.text.trim(),
        'Movimiento': _condicion == CondicionCarta.estatica
            ? 0
            : int.tryParse(_movimientoCtrl.text) ?? 1,
        'Tipo': _tipo,
        'IdEvolucion': _evolucionCarta?.id ?? '',
        'Evolucion': int.tryParse(_evolucionCosteCtrl.text) ?? 0,
        'Condicion': _condicion.value,
      };

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      if (_editMode) {
        // Actualizar documento existente
        await _db
            .collection('Cartas')
            .doc(widget.cartaEditar!.id)
            .update(_buildData());
      } else {
        // Crear documento nuevo con ID auto
        await _db.collection('Cartas').add(_buildData());
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _editMode ? 'Carta actualizada' : 'Carta creada correctamente',
              style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF1A2A0A),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Error: $e', style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF2A0A0A),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: Color(0xFFC8A860)),
        title: Text(
          _editMode ? 'EDITAR CARTA' : 'CREAR CARTA',
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'Cinzel',
            letterSpacing: 3,
            color: Color(0xFFC8A860),
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFC8A860)),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _guardar,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    'GUARDAR',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cinzel',
                      letterSpacing: 2,
                      color: Color(0xFF4ABB58),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            // ── ID (solo en modo edición) ───────────────────
            if (_editMode) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1220),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF506070).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fingerprint,
                        size: 14, color: Color(0xFF506070)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.cartaEditar!.id,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF506070),
                          fontFamily: 'Cinzel',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── NOMBRE ─────────────────────────────────────
            _SectionLabel('NOMBRE'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _nombreCtrl,
              hint: 'Nombre de la carta',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),

            const SizedBox(height: 20),

            // ── DESCRIPCIÓN ────────────────────────────────
            _SectionLabel('DESCRIPCIÓN'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _descripcionCtrl,
              hint: 'Descripción de la carta',
              maxLines: 3,
            ),

            const SizedBox(height: 20),

            // ── IMAGEN URL ─────────────────────────────────
            _SectionLabel('IMAGEN (URL)'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _imagenCtrl,
              hint: 'https://...',
              keyboardType: TextInputType.url,
            ),
            if (_imagenCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  _imagenCtrl.text.trim(),
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 60,
                    color: const Color(0xFF0A1220),
                    child: const Center(
                      child: Text('Vista previa no disponible',
                          style: TextStyle(
                              color: Color(0xFF506070),
                              fontFamily: 'Cinzel',
                              fontSize: 9)),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── EJÉRCITO ───────────────────────────────────
            _SectionLabel('EJÉRCITO'),
            const SizedBox(height: 6),
            _buildDropdown<int>(
              value: _ejercito,
              items: kEjercitos
                  .map((e) => DropdownMenuItem(
                        value: e.id,
                        child: Text('${e.icono}  ${e.nombre}',
                            style: const TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: 12,
                                color: Color(0xFFE0D8C0))),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _ejercito = v!),
            ),

            const SizedBox(height: 20),

            // ── TIPO ───────────────────────────────────────
            _SectionLabel('TIPO DE MOVIMIENTO'),
            const SizedBox(height: 6),
            _buildDropdown<int>(
              value: _tipo,
              items: const [
                DropdownMenuItem(
                    value: 1,
                    child: Text('🗡️  Terrestre',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 12,
                            color: Color(0xFFE0D8C0)))),
                DropdownMenuItem(
                    value: 2,
                    child: Text('🦅  Volador',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 12,
                            color: Color(0xFFE0D8C0)))),
                DropdownMenuItem(
                    value: 3,
                    child: Text('⚓  Marino',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 12,
                            color: Color(0xFFE0D8C0)))),
              ],
              onChanged: (v) => setState(() => _tipo = v!),
            ),

            const SizedBox(height: 20),

            // ── CONDICIÓN ──────────────────────────────────
            _SectionLabel('CONDICIÓN'),
            const SizedBox(height: 6),
            _buildDropdown<int>(
              value: _condicion.value,
              items: CondicionCarta.values
                  .map((c) => DropdownMenuItem(
                        value: c.value,
                        child: Text('${c.icon}  ${c.label}',
                            style: TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: 12,
                                color: Color(c.colorValue))),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _condicion = CondicionCartaExt.fromInt(v!)),
            ),
            if (_condicion == CondicionCarta.evolucion)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'No se puede añadir a mazos ni se reparte al final de turno. '
                  'Solo se obtiene evolucionando una carta básica.',
                  style: TextStyle(
                      fontSize: 8,
                      color: Color(0xFFC060E0),
                      fontFamily: 'Cinzel',
                      height: 1.5),
                ),
              ),
            if (_condicion == CondicionCarta.estatica)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Movimiento fijo 0. Solo se coloca en celdas donde ya tenías '
                  'una carta del turno anterior. No se puede mover tras colocarla.',
                  style: TextStyle(
                      fontSize: 8,
                      color: Color(0xFFE0A030),
                      fontFamily: 'Cinzel',
                      height: 1.5),
                ),
              ),

            const SizedBox(height: 20),

            // ── STATS NUMÉRICOS ────────────────────────────
            _SectionLabel('ESTADÍSTICAS'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _buildNumberField(
                      controller: _fuerzaCtrl,
                      label: 'Fuerza',
                      icon: Icons.bolt,
                      color: const Color(0xFFC04040))),
              const SizedBox(width: 10),
              Expanded(
                  child: _buildNumberField(
                      controller: _defensaCtrl,
                      label: 'Defensa',
                      icon: Icons.shield_outlined,
                      color: const Color(0xFF40B070))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _buildNumberField(
                      controller: _costeCtrl,
                      label: 'Coste',
                      icon: Icons.monetization_on_outlined,
                      color: const Color(0xFFB08040))),
              const SizedBox(width: 10),
              Expanded(
                  child: AbsorbPointer(
                absorbing: _condicion == CondicionCarta.estatica,
                child: Opacity(
                  opacity: _condicion == CondicionCarta.estatica ? 0.4 : 1.0,
                  child: _buildNumberField(
                      controller: _condicion == CondicionCarta.estatica
                          ? TextEditingController(text: '0')
                          : _movimientoCtrl,
                      label: _condicion == CondicionCarta.estatica
                          ? 'Mov (fijo 0)'
                          : 'Movimiento',
                      icon: Icons.open_with,
                      color: const Color(0xFF4080C0)),
                ),
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _buildNumberField(
                      controller: _idHabilidadCtrl,
                      label: 'ID Habilidad',
                      icon: Icons.auto_awesome,
                      color: const Color(0xFF8060C0))),
              const Expanded(child: SizedBox()),
            ]),

            const SizedBox(height: 28),

            // ── EVOLUCIÓN ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E18),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFFA040C0).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('EVOLUCIÓN',
                      style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Cinzel',
                          letterSpacing: 2,
                          color: Color(0xFFA040C0),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildNumberField(
                    controller: _evolucionCosteCtrl,
                    label: 'Coste evolución (energías)',
                    icon: Icons.flash_on,
                    color: const Color(0xFFC060E0),
                  ),
                  const SizedBox(height: 12),
                  const Text('CARTA EVOLUCIÓN',
                      style: TextStyle(
                          fontSize: 8,
                          fontFamily: 'Cinzel',
                          letterSpacing: 1.5,
                          color: Color(0xFF7A6A40))),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _seleccionarEvolucion,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1220),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _evolucionCarta != null
                              ? const Color(0xFFA040C0).withOpacity(0.5)
                              : const Color(0xFF506070).withOpacity(0.3),
                        ),
                      ),
                      child: _loadingEvol
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFFC060E0)),
                              ),
                            )
                          : _evolucionCarta != null
                              ? Row(children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: const Color(0xFF050C14),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: _evolucionCarta!.imagen.isNotEmpty
                                          ? Image.network(
                                              _evolucionCarta!.imagen,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                      Icons.shield_outlined,
                                                      size: 14,
                                                      color: Color(0xFF2A3A4A)),
                                            )
                                          : const Icon(Icons.shield_outlined,
                                              size: 14,
                                              color: Color(0xFF2A3A4A)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_evolucionCarta!.nombre,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFFC060E0),
                                                fontFamily: 'Cinzel')),
                                        Text('ID: ${_evolucionCarta!.id}',
                                            style: const TextStyle(
                                                fontSize: 8,
                                                color: Color(0xFF506070),
                                                fontFamily: 'Cinzel')),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => _evolucionCarta = null),
                                    child: const Icon(Icons.close,
                                        size: 16, color: Color(0xFF506070)),
                                  ),
                                ])
                              : const Row(children: [
                                  Icon(Icons.add_circle_outline,
                                      size: 18, color: Color(0xFF506070)),
                                  SizedBox(width: 10),
                                  Text('Pulsa para elegir carta de evolución',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF506070),
                                          fontFamily: 'Cinzel')),
                                ]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── BOTÓN GUARDAR ──────────────────────────────
            GestureDetector(
              onTap: _saving ? null : _guardar,
              child: Container(
                width: double.infinity,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFF4ABB58).withOpacity(0.25),
                    const Color(0xFF4ABB58).withOpacity(0.08),
                  ]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4ABB58).withOpacity(0.6),
                    width: 1,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF4ABB58)),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              _editMode
                                  ? Icons.save_outlined
                                  : Icons.add_circle_outline,
                              size: 16,
                              color: const Color(0xFF4ABB58)),
                          const SizedBox(width: 10),
                          Text(
                            _editMode ? 'GUARDAR CAMBIOS' : 'CREAR CARTA',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Cinzel',
                              letterSpacing: 2,
                              color: Color(0xFF4ABB58),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(
          color: Color(0xFFE0D8C0), fontFamily: 'Cinzel', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0xFF506070), fontFamily: 'Cinzel', fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0A1220),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: const Color(0xFFC8A860).withOpacity(0.2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: const Color(0xFFC8A860).withOpacity(0.15))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFC8A860), width: 1)),
        errorStyle: const TextStyle(
            color: Color(0xFFC04040), fontFamily: 'Cinzel', fontSize: 9),
      ),
      onChanged: (_) {
        if (controller == _imagenCtrl) setState(() {});
      },
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1,
                  color: color.withOpacity(0.8))),
        ]),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              color: color,
              fontFamily: 'Cinzel',
              fontSize: 16,
              fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0A1220),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: color.withOpacity(0.2))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: color.withOpacity(0.15))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: color, width: 1)),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1220),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFC8A860).withOpacity(0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: const Color(0xFF0C1A2A),
          icon:
              const Icon(Icons.expand_more, size: 18, color: Color(0xFF506070)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 9,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: Color(0xFF7A6A40),
            fontWeight: FontWeight.bold));
  }
}
