// lib/views/crear_carta_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/carta_model.dart';
import '../models/lobby_model.dart'; // kEjercitos
import '../services/admin_cuentas_service.dart';
import '../services/permisos.dart';
import '../services/warzero_api.dart';
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
  final _api = WarZeroApi();

  bool get _editMode => widget.cartaEditar != null;

  /// El botón "enviar a todos los usuarios" solo aparece al editar una carta ya
  /// existente (necesita su id) y solo para cuentas con permisos de editor.
  bool get _puedeRepartir => _editMode && esEditor();

  bool _enviandoATodos = false;
  bool _enviandoAJugador = false;
  final _adminApi = AdminCuentasService();

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late final TextEditingController _imagenCtrl;
  late final TextEditingController _fuerzaCtrl;
  late final TextEditingController _defensaCtrl;
  late final TextEditingController _costeCtrl;
  late final TextEditingController _idHabilidadCtrl;
  late final TextEditingController _costeHabilidadCtrl;
  late final TextEditingController _movimientoCtrl;
  late final TextEditingController _evolucionCosteCtrl;
  late final TextEditingController _numeroCtrl;

  late int _ejercito;
  late int _tipo;
  late CondicionCarta _condicion;
  CartaModel? _evolucionCarta;
  bool _saving = false;
  bool _loadingEvol = false;
  bool _porDefecto = false;

  /// Peso de aparición en sobres, elegido por rareza (ver `_rarezasProb`).
  late double _probabilidad;

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
    _costeHabilidadCtrl =
        TextEditingController(text: '${c?.costeHabilidad ?? 0}');
    _movimientoCtrl = TextEditingController(text: '${c?.movimiento ?? 1}');
    _evolucionCosteCtrl = TextEditingController(text: '${c?.evolucion ?? 0}');
    _numeroCtrl = TextEditingController(text: '${c?.numero ?? 0}');
    _probabilidad = c == null
        ? _rarezasProb.first.peso // nueva carta → Común
        : _pesoRarezaMasCercana(c.probabilidad);
    _ejercito = c?.ejercito ?? 1;
    _tipo = c?.tipo ?? 1;
    _condicion = c?.condicion ?? CondicionCarta.basica;
    _porDefecto = c?.porDefecto ?? false;

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
    _costeHabilidadCtrl.dispose();
    _movimientoCtrl.dispose();
    _evolucionCosteCtrl.dispose();
    _numeroCtrl.dispose();
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
    if (result == null || !mounted) return;

    // Una evolución puede evolucionar a su vez (27 → 28), pero la cadena NO
    // puede volver sobre sí misma (27 → 28 → 27): el backend se protege con un
    // tope de 10 eslabones, pero el resultado sería una colección incoherente.
    final error = await _validarCadenaEvolucion(result);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF2A0A0A),
        ),
      );
      return;
    }
    setState(() => _evolucionCarta = result);
  }

  /// Recorre la cadena que cuelga de [elegida] siguiendo `IdEvolucion`. Devuelve
  /// null si es válida, o el texto del error si vuelve a esta misma carta o si
  /// supera los 10 eslabones (mismo tope que `MaxCadenaEvolucion` en el backend).
  Future<String?> _validarCadenaEvolucion(CartaModel elegida) async {
    final propioId = widget.cartaEditar?.id;
    // Carta nueva: aún no tiene id, no puede formar un ciclo consigo misma.
    if (propioId == null || propioId.isEmpty) return null;
    if (elegida.id == propioId) {
      return 'Una carta no puede evolucionar en sí misma.';
    }

    final vistos = <String>{propioId, elegida.id};
    var actual = elegida.idEvolucion;
    var eslabones = 1; // la propia `elegida` ya es el primer eslabón

    while (actual.isNotEmpty && eslabones < 10) {
      if (actual == propioId) {
        return 'Cadena circular: esa carta acaba evolucionando de nuevo en '
            '"${_nombreCtrl.text.trim()}".';
      }
      if (!vistos.add(actual)) break; // ciclo entre terceras cartas: ya existía
      try {
        final doc = await _db.collection('Cartas').doc(actual).get();
        if (!doc.exists) break;
        actual = CartaModel.fromFirestore(doc).idEvolucion;
      } catch (_) {
        break; // sin red: no bloqueamos la edición
      }
      eslabones++;
    }

    if (actual.isNotEmpty && eslabones >= 10) {
      return 'La cadena de evolución supera los 10 eslabones.';
    }
    return null;
  }

  /// Opciones de rareza para la probabilidad de sobre. Cada una es un PESO
  /// relativo; el servidor lo normaliza sobre la suma de pesos del ejército.
  ///   Común 100  ·  Rara 20  ·  Épica 5  ·  Legendaria 1
  static const List<_RarezaProb> _rarezasProb = [
    _RarezaProb('Común', 100, Color(0xFF9AA5B1)),
    _RarezaProb('Rara', 20, Color(0xFF3B9EE0)),
    _RarezaProb('Épica', 5, Color(0xFFB060E0)),
    _RarezaProb('Legendaria', 1, Color(0xFFE0A020)),
  ];

  /// Devuelve el peso de la rareza cuyo valor está más cerca de [v] (para
  /// mapear cartas antiguas con probabilidad numérica libre a una rareza).
  static double _pesoRarezaMasCercana(double v) {
    var best = _rarezasProb.first;
    var bestDist = (v - best.peso).abs();
    for (final r in _rarezasProb) {
      final d = (v - r.peso).abs();
      if (d < bestDist) {
        bestDist = d;
        best = r;
      }
    }
    return best.peso;
  }

  Map<String, dynamic> _buildData() => {
        'Nombre': _nombreCtrl.text.trim(),
        'Descripcion': _descripcionCtrl.text.trim(),
        'Ejercito': _ejercito,
        'Fuerza': int.tryParse(_fuerzaCtrl.text) ?? 1,
        'Defensa': int.tryParse(_defensaCtrl.text) ?? 0,
        'Coste': int.tryParse(_costeCtrl.text) ?? 1,
        'IdHabilidad': int.tryParse(_idHabilidadCtrl.text) ?? 0,
        'CosteHabilidad': int.tryParse(_costeHabilidadCtrl.text) ?? 0,
        'Imagen': _imagenCtrl.text.trim(),
        'Movimiento': _condicion == CondicionCarta.estatica
            ? 0
            : int.tryParse(_movimientoCtrl.text) ?? 1,
        'Tipo': _tipo,
        'IdEvolucion': _evolucionCarta?.id ?? '',
        'Evolucion': int.tryParse(_evolucionCosteCtrl.text) ?? 0,
        'Condicion': _condicion.value,
        'PorDefecto': _porDefecto,
        'Numero': int.tryParse(_numeroCtrl.text) ?? 0,
        'Probabilidad': _probabilidad,
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

      // El backend cachea el catálogo de cartas 10 minutos: sin esto, los
      // cambios de número o de cadena de evolución no se ven en "Mi colección"
      // hasta que caduca el TTL. Best-effort: si falla, no rompe el guardado.
      await _api.invalidarCatalogo();

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

  /// Reparte esta carta a la colección de TODOS los usuarios (solo editores).
  /// Pide confirmación, llama al backend y muestra el resultado.
  Future<void> _enviarATodos() async {
    final carta = widget.cartaEditar;
    if (carta == null || _enviandoATodos) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1828),
        title: const Text('Enviar a todos los usuarios',
            style: TextStyle(color: Color(0xFFE0C060), fontFamily: 'Cinzel')),
        content: Text(
          'La carta "${carta.nombre}" se añadirá a la colección de TODOS los '
          'usuarios que aún no la tengan. Esta acción no se puede deshacer.',
          style: const TextStyle(color: Color(0xFFB0C0D0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF90A0B0))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Enviar',
                style: TextStyle(color: Color(0xFF4ABB58))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enviandoATodos = true);
    try {
      final res = await _api.enviarCartaATodos(carta.id);
      if (!mounted) return;
      final otorgadas = (res['otorgadas'] as num?)?.toInt() ?? 0;
      final yaTenian = (res['yaTenian'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Carta enviada. Nuevos: $otorgadas · Ya la tenían: $yaTenian',
              style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF1A2A0A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar: $e',
              style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF2A0A0A),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoATodos = false);
    }
  }

  /// Envía esta carta a UN jugador indicando su correo (solo editores).
  /// El servidor valida el token y el claim de editor, suma las copias a su
  /// colección y deja registro en `AuditoriaCuentas`.
  Future<void> _enviarAJugador() async {
    final carta = widget.cartaEditar;
    if (carta == null || _enviandoAJugador) return;

    final datos = await showDialog<_DatosEnvioJugador>(
      context: context,
      builder: (_) => _EnviarAJugadorDialog(nombreCarta: carta.nombre),
    );
    if (datos == null || !mounted) return;

    setState(() => _enviandoAJugador = true);
    try {
      final r = await _adminApi.enviarCarta(
        email: datos.email,
        cartaId: carta.id,
        cantidad: datos.cantidad,
        motivo: datos.motivo,
      );
      if (!mounted) return;
      final quien = r.alias.isEmpty ? r.email : '${r.alias} (${r.email})';
      final detalle = r.nueva
          ? 'Carta nueva para el jugador · copias: ${r.cantidadNueva}'
          : 'Ya la tenía · copias: ${r.cantidadAnterior} → ${r.cantidadNueva}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('"${r.nombreCarta}" enviada a $quien.\n$detalle',
              style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF1A2A0A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No se pudo enviar: ${e.toString().replaceFirst('Exception: ', '')}',
              style: const TextStyle(fontFamily: 'Cinzel')),
          backgroundColor: const Color(0xFF2A0A0A),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoAJugador = false);
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
            // ── Check: pertenece al MAZO POR DEFECTO de su ejército ──────
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _porDefecto,
                activeColor: const Color(0xFFC8A860),
                title: const Text('Mazo por defecto',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        color: Color(0xFFC8A860))),
                subtitle: const Text(
                    'Si se marca, esta carta forma el mazo inicial de su '
                    'ejército para jugadores sin mazo propio.',
                    style: TextStyle(fontSize: 9, color: Color(0xFF7A8898))),
                onChanged: (v) => setState(() => _porDefecto = v),
              ),
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

            // ── COLECCIÓN (número de carta + probabilidad de sobre) ──
            _SectionLabel('COLECCIÓN'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _buildNumberField(
                      controller: _numeroCtrl,
                      label: 'Nº de carta',
                      icon: Icons.tag,
                      color: const Color(0xFF60A0E0))),
              const SizedBox(width: 10),
              Expanded(child: _buildRarezaProb()),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Nº de carta: posición dentro de su ejército para el catálogo. '
                'Las que un jugador no posea se muestran bloqueadas en ese hueco. '
                '0 = sin numerar (no cuenta para el % de completado).\n'
                'Rareza: define cada cuánto sale la carta al abrir sobres '
                '(Común = muy frecuente … Legendaria = muy rara).',
                style: TextStyle(
                    fontSize: 8,
                    color: Color(0xFF7A8898),
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
              const SizedBox(width: 10),
              Expanded(
                  child: AbsorbPointer(
                absorbing: _condicion == CondicionCarta.accion,
                child: Opacity(
                  opacity: _condicion == CondicionCarta.accion ? 0.4 : 1.0,
                  child: _buildNumberField(
                      controller: _costeHabilidadCtrl,
                      label: 'Coste habilidad',
                      icon: Icons.bolt,
                      color: const Color(0xFF40C0FF)),
                ),
              )),
            ]),
            if (_condicion == CondicionCarta.accion)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Carta de acción: se paga con el campo "Coste" de arriba. '
                  'Este campo (CosteHabilidad) no se usa en este caso: solo '
                  'aplica a la habilidad de una carta normal ya desplegada '
                  '(botón "Lanzar habilidad" en el tablero).',
                  style: TextStyle(
                      fontSize: 8,
                      color: Color(0xFF40C0FF),
                      fontFamily: 'Cinzel',
                      height: 1.5),
                ),
              ),

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

            // ── BOTÓN ENVIAR A TODOS LOS USUARIOS (solo editores) ──
            if (_puedeRepartir) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _enviandoATodos ? null : _enviarATodos,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFF3A78C8).withOpacity(0.22),
                      const Color(0xFF3A78C8).withOpacity(0.06),
                    ]),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF3A78C8).withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                  child: _enviandoATodos
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF6AA8E8)),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.groups_outlined,
                                size: 16, color: Color(0xFF6AA8E8)),
                            SizedBox(width: 10),
                            Text(
                              'ENVIAR A TODOS LOS USUARIOS',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Cinzel',
                                letterSpacing: 2,
                                color: Color(0xFF6AA8E8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              // ── BOTÓN ENVIAR A UN JUGADOR (solo editores) ──
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _enviandoAJugador ? null : _enviarAJugador,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFFC8A860).withOpacity(0.20),
                      const Color(0xFFC8A860).withOpacity(0.05),
                    ]),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFC8A860).withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                  child: _enviandoAJugador
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFFE0C060)),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_alt_1_outlined,
                                size: 16, color: Color(0xFFE0C060)),
                            SizedBox(width: 10),
                            Text(
                              'ENVIAR A UN JUGADOR',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Cinzel',
                                letterSpacing: 2,
                                color: Color(0xFFE0C060),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
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
    bool allowDecimal = false,
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
          keyboardType: allowDecimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          inputFormatters: allowDecimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : [FilteringTextInputFormatter.digitsOnly],
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

  Widget _buildRarezaProb() {
    const color = Color(0xFFE0A040);
    final sel = _rarezasProb.firstWhere((r) => r.peso == _probabilidad,
        orElse: () => _rarezasProb.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.casino_outlined, size: 12, color: color),
          const SizedBox(width: 5),
          Text('RAREZA (SOBRES)',
              style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cinzel',
                  letterSpacing: 1,
                  color: color.withOpacity(0.8))),
        ]),
        const SizedBox(height: 4),
        _buildDropdown<double>(
          value: sel.peso,
          items: [
            for (final r in _rarezasProb)
              DropdownMenuItem<double>(
                value: r.peso,
                child: Row(children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: r.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(r.nombre,
                      style: const TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 12,
                          color: Color(0xFFE0D8C0))),
                ]),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _probabilidad = v);
          },
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
/// Opción de rareza para la probabilidad de sobre: nombre + peso relativo.
class _RarezaProb {
  final String nombre;
  final double peso;
  final Color color;
  const _RarezaProb(this.nombre, this.peso, this.color);
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

// ─────────────────────────────────────────────────────────────
// DIÁLOGO "ENVIAR A UN JUGADOR"
// Devuelve el correo, las copias y el motivo, o null si se cancela.
// ─────────────────────────────────────────────────────────────

class _DatosEnvioJugador {
  final String email;
  final int cantidad;
  final String motivo;

  const _DatosEnvioJugador({
    required this.email,
    required this.cantidad,
    required this.motivo,
  });
}

class _EnviarAJugadorDialog extends StatefulWidget {
  final String nombreCarta;

  const _EnviarAJugadorDialog({required this.nombreCarta});

  @override
  State<_EnviarAJugadorDialog> createState() => _EnviarAJugadorDialogState();
}

class _EnviarAJugadorDialogState extends State<_EnviarAJugadorDialog> {
  static const _minCopias = 1;
  static const _maxCopias = 50; // mismo límite que el servidor

  static const _oro = Color(0xFFE0C060);
  static const _texto = Color(0xFFB0C0D0);
  static const _tenue = Color(0xFF90A0B0);

  final _emailCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  int _cantidad = 1;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Introduce el correo del jugador.');
      return;
    }
    Navigator.of(context).pop(_DatosEnvioJugador(
      email: email,
      cantidad: _cantidad,
      motivo: _motivoCtrl.text.trim(),
    ));
  }

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0xFF506070), fontFamily: 'Cinzel', fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: _tenue),
        filled: true,
        fillColor: const Color(0xFF0A1220),
        counterStyle: const TextStyle(color: _tenue, fontSize: 9),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: const Color(0xFFC8A860).withOpacity(0.2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFC8A860))),
      );

  Widget _botonCopias(IconData icon, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: _oro,
        disabledColor: _tenue.withOpacity(0.4),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0C1828),
      title: const Text('Enviar a un jugador',
          style: TextStyle(color: _oro, fontFamily: 'Cinzel')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La carta "${widget.nombreCarta}" se añadirá a la colección del '
              'jugador. Si ya la tiene, se suman las copias.',
              style: const TextStyle(color: _texto, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(
                  color: Color(0xFFE0D8C0), fontFamily: 'Cinzel', fontSize: 13),
              decoration:
                  _deco('Correo de login del jugador', Icons.alternate_email),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('COPIAS',
                    style: TextStyle(
                        color: _tenue,
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        letterSpacing: 1.5)),
                const Spacer(),
                _botonCopias(
                  Icons.remove_circle_outline,
                  _cantidad > _minCopias
                      ? () => setState(() => _cantidad--)
                      : null,
                ),
                SizedBox(
                  width: 32,
                  child: Text('$_cantidad',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _oro,
                          fontFamily: 'Cinzel',
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
                _botonCopias(
                  Icons.add_circle_outline,
                  _cantidad < _maxCopias
                      ? () => setState(() => _cantidad++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _motivoCtrl,
              maxLength: 200,
              maxLines: 2,
              style: const TextStyle(
                  color: Color(0xFFE0D8C0), fontFamily: 'Cinzel', fontSize: 12),
              decoration:
                  _deco('Motivo (opcional, queda registrado)', Icons.notes),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFC04040), fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: _tenue)),
        ),
        TextButton(
          onPressed: _confirmar,
          child:
              const Text('Enviar', style: TextStyle(color: Color(0xFF4ABB58))),
        ),
      ],
    );
  }
}
