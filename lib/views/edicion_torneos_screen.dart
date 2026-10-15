// lib/views/edicion_torneos_screen.dart
//
// EDICIÓN DE TORNEOS (solo editores). Lista de torneos y editor de cada uno:
//   · nombre, descripción y estado (borrador / publicado / en curso / finalizado)
//   · 3 fechas: inicio y fin de inscripción, inicio del torneo
//   · rondas → partidas (tipo, nº de jugadores, modo) y cuántos clasifican
//   · PREMIOS por rango de puestos: XP, dinero, Cristales Zero, carta y un
//     texto libre para premios fuera de la app (se reparten solos al
//     finalizar, salvo el externo)
//   · inscritos y sorteo aleatorio de grupos de la ronda 1
//
// Solo un torneo PUBLICADO o EN CURSO aparece a los jugadores (el más próximo).

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:warzero/models/carta_model.dart';
import 'package:warzero/models/jugador_model.dart'; // MonedaZero
import 'package:warzero/models/modo_partida.dart';
import 'package:warzero/models/torneo_model.dart';
import 'package:warzero/services/settings_controller.dart';
import 'package:warzero/services/torneos_service.dart';
import 'package:warzero/views/seleccionar_carta_screen.dart';
import 'package:warzero/views/torneos_screen.dart';

const Color _kAcento = Color(0xFFE04444);

class EdicionTorneosScreen extends StatefulWidget {
  const EdicionTorneosScreen({super.key});

  @override
  State<EdicionTorneosScreen> createState() => _EdicionTorneosScreenState();
}

class _EdicionTorneosScreenState extends State<EdicionTorneosScreen> {
  final _svc = TorneosService();
  late Future<List<TorneoVigente>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _svc.listarAdmin();
  }

  void _recargar() => setState(() => _futuro = _svc.listarAdmin());

  Future<void> _abrir(TorneoModel? t) async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditorTorneoScreen(torneo: t)),
    );
    if (cambiado == true) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text('ED. TORNEOS',
            style: TextStyle(
                fontSize: 14,
                fontFamily: 'Cinzel',
                letterSpacing: 3,
                color: war.primario)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _recargar),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kAcento,
        foregroundColor: Colors.white,
        onPressed: () => _abrir(null),
        icon: const Icon(Icons.add),
        label: const Text('NUEVO TORNEO',
            style: TextStyle(fontFamily: 'Cinzel', letterSpacing: 1)),
      ),
      body: FutureBuilder<List<TorneoVigente>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Mensaje(
                texto: '${snap.error}'.replaceFirst('Exception: ', ''),
                onReintentar: _recargar);
          }
          final lista = snap.data ?? [];
          if (lista.isEmpty) {
            return const _Mensaje(texto: 'No hay torneos. Crea el primero.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final v = lista[i];
              final t = v.torneo!;
              return InkWell(
                onTap: () => _abrir(t),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: war.superficie,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kAcento.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(t.nombre,
                              style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontWeight: FontWeight.bold,
                                  color: war.texto)),
                        ),
                        _Chip(texto: t.estadoNombre, color: _colorEstado(t.estado)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'Inscripción ${fechaTorneo(t.inicioInscripcion)} → '
                        '${fechaTorneo(t.finInscripcion)}\n'
                        'Inicio ${fechaTorneo(t.inicioTorneo)} · '
                        '${t.rondas.length} rondas · ${v.inscritos} inscritos',
                        style: TextStyle(fontSize: 11, color: war.textoTenue, height: 1.5),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Color _colorEstado(String estado) {
  switch (estado) {
    case 'publicado':
      return const Color(0xFF4ABB58);
    case 'en_curso':
      return const Color(0xFFE0A030);
    case 'finalizado':
      return Colors.grey;
    default:
      return const Color(0xFF3F8CFF);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EDITOR DE UN TORNEO
// ═══════════════════════════════════════════════════════════════════════════

class _EditorTorneoScreen extends StatefulWidget {
  final TorneoModel? torneo;
  const _EditorTorneoScreen({this.torneo});

  @override
  State<_EditorTorneoScreen> createState() => _EditorTorneoScreenState();
}

class _EditorTorneoScreenState extends State<_EditorTorneoScreen> {
  final _svc = TorneosService();
  late TorneoModel _t;
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  bool _guardando = false;
  bool _cambiado = false;

  List<InscritoTorneo>? _inscritos;
  List<PremiadoTorneo>? _premiados;
  List<GrupoTorneo>? _grupos;
  bool _cargandoExtra = false;

  bool get _esNuevo => _t.id.isEmpty;

  @override
  void initState() {
    super.initState();
    final o = widget.torneo;
    _t = o == null
        ? _plantilla()
        : TorneoModel(
            id: o.id,
            nombre: o.nombre,
            descripcion: o.descripcion,
            inicioInscripcion: o.inicioInscripcion,
            finInscripcion: o.finInscripcion,
            inicioTorneo: o.inicioTorneo,
            estado: o.estado,
            rondaActual: o.rondaActual,
            rondas: o.rondas
                .map((r) => RondaTorneo(
                    numero: r.numero,
                    clasifican: r.clasifican,
                    partidas: r.partidas.map((p) => p.copia()).toList()))
                .toList(),
            premios: o.premios.map((p) => p.copia()).toList(),
            premiosEntregados: o.premiosEntregados,
          );
    _nombre = TextEditingController(text: _t.nombre);
    _descripcion = TextEditingController(text: _t.descripcion);
    if (!_esNuevo) _cargarExtra();
  }

  /// Plantilla por defecto: inscripción de mañana a +7 días, torneo a +8.
  TorneoModel _plantilla() {
    final hoy = DateTime.now();
    final base = DateTime(hoy.year, hoy.month, hoy.day, 10);
    return TorneoModel(
      inicioInscripcion: base.add(const Duration(days: 1)),
      finInscripcion: base.add(const Duration(days: 7, hours: 12)),
      inicioTorneo: base.add(const Duration(days: 8)),
      rondas: [
        RondaTorneo(numero: 1, clasifican: 16, partidas: [
          PartidaTorneo(jugadores: 4),
          PartidaTorneo(jugadores: 8),
          PartidaTorneo(jugadores: 4, modo: ModoPartida.meteoritos),
          PartidaTorneo(tipo: TipoPartidaTorneo.duelo, jugadores: 2),
        ]),
        RondaTorneo(numero: 2, clasifican: 0, partidas: [PartidaTorneo(jugadores: 8)]),
      ],
      premios: [
        PremioTorneo(desde: 1, hasta: 1, xp: 5000, dinero: 1000, zero: 20),
        PremioTorneo(desde: 2, hasta: 2, xp: 3000, dinero: 500, zero: 10),
        PremioTorneo(desde: 3, hasta: 3, xp: 2000, dinero: 250, zero: 5),
      ],
    );
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _cargarExtra() async {
    setState(() => _cargandoExtra = true);
    try {
      final r = await Future.wait([
        _svc.inscritos(_t.id),
        _svc.grupos(_t.id, ronda: 1),
      ]);
      List<PremiadoTorneo>? premiados;
      if (_t.premiosEntregados) {
        try {
          premiados = await _svc.premiados(_t.id);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _inscritos = r[0] as List<InscritoTorneo>;
        _grupos = r[1] as List<GrupoTorneo>;
        _premiados = premiados;
      });
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _cargandoExtra = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m.replaceFirst('Exception: ', ''))));
  }

  // ── Validación local (el servidor vuelve a validar) ──────────────────────
  String? _validar() {
    if (_nombre.text.trim().isEmpty) return 'Falta el nombre.';
    final a = _t.inicioInscripcion, b = _t.finInscripcion, c = _t.inicioTorneo;
    if (a == null || b == null || c == null) return 'Faltan fechas.';
    if (!b.isAfter(a)) return 'El fin de inscripción debe ser posterior a su inicio.';
    if (c.isBefore(b)) return 'El torneo no puede empezar antes del cierre de inscripción.';
    if (_t.rondas.isEmpty) return 'Añade al menos una ronda.';
    for (var i = 0; i < _t.rondas.length; i++) {
      final r = _t.rondas[i];
      if (r.partidas.isEmpty) return 'La ronda ${i + 1} no tiene partidas.';
      final ultima = i == _t.rondas.length - 1;
      if (!ultima && r.clasifican < 1) return 'Indica cuántos clasifican en la ronda ${i + 1}.';
      if (!ultima && i > 0 && r.clasifican >= _t.rondas[i - 1].clasifican) {
        return 'En la ronda ${i + 1} deben clasificar menos que en la anterior.';
      }
    }
    final ocupados = <int>{};
    for (final p in _t.premios) {
      if (p.hasta < p.desde) return 'Rango de puestos no válido (${p.puestos}).';
      for (var k = p.desde; k <= p.hasta; k++) {
        if (!ocupados.add(k)) return 'El puesto ${k}º tiene más de un premio.';
      }
      if (p.vacio) return 'El premio ${p.puestos} está vacío.';
    }
    return null;
  }

  Future<void> _guardar() async {
    final err = _validar();
    if (err != null) return _snack(err);
    _t.nombre = _nombre.text;
    _t.descripcion = _descripcion.text;
    for (var i = 0; i < _t.rondas.length; i++) {
      _t.rondas[i].numero = i + 1;
    }
    _t.rondas.last.clasifican = 0;

    setState(() => _guardando = true);
    try {
      final g = await _svc.guardar(_t);
      if (!mounted) return;
      setState(() {
        _t.id = g.id;
        _t.rondaActual = g.rondaActual;
        _cambiado = true;
      });
      _snack('Torneo guardado.');
      _cargarExtra();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrar() async {
    final ok = await _confirmar('Borrar torneo',
        'Se borrará el torneo con sus inscritos y grupos. No se puede deshacer.');
    if (!ok) return;
    try {
      await _svc.borrar(_t.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _sortear() async {
    final cerrada = _t.finInscripcion != null &&
        DateTime.now().isAfter(_t.finInscripcion!);
    final rehacer = (_grupos?.isNotEmpty ?? false);
    final ok = await _confirmar(
      'Sortear grupos · Ronda 1',
      '${_inscritos?.length ?? 0} inscritos se repartirán al azar en cada '
          'partida de la ronda 1.'
          '${rehacer ? '\n\nYa hay un sorteo: se sustituirá.' : ''}'
          '${cerrada ? '' : '\n\nLa inscripción sigue abierta: se forzará el sorteo.'}',
    );
    if (!ok) return;
    setState(() => _cargandoExtra = true);
    try {
      final g = await _svc.sortear(_t.id, ronda: 1, forzar: !cerrada);
      if (!mounted) return;
      setState(() {
        _grupos = g;
        _t.rondaActual = 1;
        _t.estado = 'en_curso';
        _cambiado = true;
      });
      _snack('Grupos sorteados.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _cargandoExtra = false);
    }
  }

  Future<bool> _confirmar(String titulo, String texto) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('ACEPTAR')),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _elegirFecha(DateTime? actual, ValueChanged<DateTime> onOk) async {
    final base = actual ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return;
    final h = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (h == null) return;
    setState(() => onOk(DateTime(d.year, d.month, d.day, h.hour, h.minute)));
  }

  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_cambiado);
      },
      child: Scaffold(
        backgroundColor: war.fondo,
        appBar: AppBar(
          backgroundColor: war.superficie,
          iconTheme: IconThemeData(color: war.primario),
          title: Text(_esNuevo ? 'NUEVO TORNEO' : 'EDITAR TORNEO',
              style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Cinzel',
                  letterSpacing: 3,
                  color: war.primario)),
          actions: [
            if (!_esNuevo)
              IconButton(
                  tooltip: 'Borrar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _guardando ? null : _borrar),
            IconButton(
              tooltip: 'Guardar',
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              onPressed: _guardando ? null : _guardar,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _Seccion(titulo: 'DATOS'),
            TextField(
              controller: _nombre,
              style: TextStyle(color: war.texto),
              decoration: _deco(war, 'Nombre del torneo'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descripcion,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(color: war.texto),
              decoration: _deco(war, 'Descripción / premios'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _t.estado,
              dropdownColor: war.superficie,
              style: TextStyle(color: war.texto),
              decoration: _deco(war, 'Estado'),
              items: const [
                DropdownMenuItem(value: 'borrador', child: Text('Borrador (oculto)')),
                DropdownMenuItem(value: 'publicado', child: Text('Publicado (visible)')),
                DropdownMenuItem(value: 'en_curso', child: Text('En curso')),
                DropdownMenuItem(value: 'finalizado', child: Text('Finalizado')),
              ],
              onChanged: (v) => setState(() => _t.estado = v ?? 'borrador'),
            ),

            _Seccion(titulo: 'FECHAS'),
            _CampoFecha(
              etiqueta: 'Inicio de inscripción',
              valor: _t.inicioInscripcion,
              onTap: () => _elegirFecha(_t.inicioInscripcion, (d) => _t.inicioInscripcion = d),
            ),
            _CampoFecha(
              etiqueta: 'Fin de inscripción',
              valor: _t.finInscripcion,
              onTap: () => _elegirFecha(_t.finInscripcion, (d) => _t.finInscripcion = d),
            ),
            _CampoFecha(
              etiqueta: 'Inicio del torneo',
              valor: _t.inicioTorneo,
              onTap: () => _elegirFecha(_t.inicioTorneo, (d) => _t.inicioTorneo = d),
            ),

            _Seccion(titulo: 'RONDAS'),
            Text(
              'En cada ronda se juegan todas sus partidas; la suma de PC decide '
              'quién pasa a la siguiente. En la última ronda no clasifica nadie: '
              'gana quien más PC sume.',
              style: TextStyle(fontSize: 11, color: war.textoTenue, height: 1.4),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _t.rondas.length; i++)
              _RondaEditor(
                key: ObjectKey(_t.rondas[i]),
                indice: i,
                ronda: _t.rondas[i],
                esUltima: i == _t.rondas.length - 1,
                onCambio: () => setState(() {}),
                onBorrar: _t.rondas.length == 1
                    ? null
                    : () => setState(() => _t.rondas.removeAt(i)),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: _kAcento, side: const BorderSide(color: _kAcento)),
              onPressed: () => setState(() {
                final prev = _t.rondas.isNotEmpty ? _t.rondas.last : null;
                if (prev != null && prev.clasifican == 0) prev.clasifican = 8;
                _t.rondas.add(RondaTorneo(
                  numero: _t.rondas.length + 1,
                  partidas: [PartidaTorneo(jugadores: 8)],
                ));
              }),
              icon: const Icon(Icons.add),
              label: const Text('AÑADIR RONDA'),
            ),

            _Seccion(titulo: 'PREMIOS'),
            Text(
              'XP, dinero, Cristales Zero y cartas se entregan automáticamente al '
              'finalizar el torneo. Los premios fuera de la app (camiseta, '
              'metálico…) se muestran a los jugadores y los entrega la organización.',
              style: TextStyle(fontSize: 11, color: war.textoTenue, height: 1.4),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _t.premios.length; i++)
              _PremioEditor(
                key: ObjectKey(_t.premios[i]),
                premio: _t.premios[i],
                bloqueado: _t.premiosEntregados,
                onCambio: () => setState(() {}),
                onBorrar: () => setState(() => _t.premios.removeAt(i)),
              ),
            if (!_t.premiosEntregados)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: _kAcento, side: const BorderSide(color: _kAcento)),
                onPressed: () => setState(() {
                  final sig = _t.premios.isEmpty
                      ? 1
                      : _t.premios.map((p) => p.hasta).reduce((a, b) => a > b ? a : b) + 1;
                  _t.premios.add(PremioTorneo(desde: sig, hasta: sig));
                }),
                icon: const Icon(Icons.add),
                label: const Text('AÑADIR PREMIO'),
              ),

            if (!_esNuevo) ..._seccionInscritos(war),
            if (_premiados != null && _premiados!.isNotEmpty) ..._seccionPremiados(war),
          ],
        ),
      ),
    );
  }

  List<Widget> _seccionPremiados(WarColors war) {
    return [
      _Seccion(titulo: 'PREMIOS ENTREGADOS'),
      for (final p in _premiados!)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: war.superficie,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: war.borde),
          ),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Text('${p.puesto}º',
                  style: const TextStyle(
                      fontFamily: 'Cinzel', fontWeight: FontWeight.bold, color: _kAcento)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nombre, style: TextStyle(color: war.texto, fontWeight: FontWeight.bold)),
                if (p.premio.partesApp.isNotEmpty)
                  Text(p.premio.partesApp.join(' · '),
                      style: TextStyle(fontSize: 11, color: war.textoTenue)),
                if (p.premio.tieneExterno)
                  Text('Fuera de la app: ${p.premio.externo}',
                      style: TextStyle(fontSize: 11, color: war.texto)),
              ]),
            ),
            if (p.premio.tieneExterno)
              Column(children: [
                Checkbox(
                  value: p.externoEntregado,
                  activeColor: _kAcento,
                  onChanged: (v) => _marcarExterno(p, v ?? false),
                ),
                Text('Entregado', style: TextStyle(fontSize: 9, color: war.textoTenue)),
              ]),
          ]),
        ),
    ];
  }

  Future<void> _marcarExterno(PremiadoTorneo p, bool entregado) async {
    try {
      await _svc.marcarExterno(_t.id, p.uid, entregado);
      final lista = await _svc.premiados(_t.id);
      if (mounted) setState(() => _premiados = lista);
    } catch (e) {
      _snack('$e');
    }
  }

  List<Widget> _seccionInscritos(WarColors war) {
    return [
      _Seccion(titulo: 'INSCRITOS (${_inscritos?.length ?? '…'})'),
      if (_cargandoExtra) const LinearProgressIndicator(minHeight: 2),
      if (_inscritos != null && _inscritos!.isEmpty)
        Text('Aún no hay inscritos.', style: TextStyle(color: war.textoTenue, fontSize: 12)),
      if (_inscritos != null && _inscritos!.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _inscritos!
              .map((p) => _Chip(texto: p.nombre, color: war.textoTenue))
              .toList(),
        ),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: _kAcento, foregroundColor: Colors.white),
        onPressed: _cargandoExtra || (_inscritos?.length ?? 0) < 2 ? null : _sortear,
        icon: const Icon(Icons.shuffle),
        label: Text((_grupos?.isNotEmpty ?? false)
            ? 'REHACER SORTEO RONDA 1'
            : 'SORTEAR GRUPOS RONDA 1'),
      ),
      if (_grupos != null && _grupos!.isNotEmpty) ...[
        _Seccion(titulo: 'GRUPOS · RONDA 1'),
        GruposTorneoLista(grupos: _grupos!, ronda: _t.rondas.isNotEmpty ? _t.rondas.first : null),
      ],
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RONDA
// ═══════════════════════════════════════════════════════════════════════════

class _RondaEditor extends StatelessWidget {
  final int indice;
  final RondaTorneo ronda;
  final bool esUltima;
  final VoidCallback onCambio;
  final VoidCallback? onBorrar;

  const _RondaEditor({
    super.key,
    required this.indice,
    required this.ronda,
    required this.esUltima,
    required this.onCambio,
    this.onBorrar,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kAcento.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(esUltima ? 'RONDA ${indice + 1} · FINAL' : 'RONDA ${indice + 1}',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: _kAcento)),
            const Spacer(),
            if (onBorrar != null)
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: war.textoTenue),
                  onPressed: onBorrar),
          ]),
          for (var p = 0; p < ronda.partidas.length; p++)
            _PartidaEditor(
              key: ObjectKey(ronda.partidas[p]),
              indice: p,
              partida: ronda.partidas[p],
              onCambio: onCambio,
              onBorrar: ronda.partidas.length == 1
                  ? null
                  : () {
                      ronda.partidas.removeAt(p);
                      onCambio();
                    },
            ),
          TextButton.icon(
            onPressed: () {
              ronda.partidas.add(PartidaTorneo());
              onCambio();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Añadir partida'),
          ),
          if (!esUltima)
            Row(children: [
              Expanded(
                child: Text('Clasifican a la ronda ${indice + 2} (por suma de PC)',
                    style: TextStyle(fontSize: 12, color: war.texto)),
              ),
              _Contador(
                valor: ronda.clasifican,
                min: 1,
                max: 512,
                onCambio: (v) {
                  ronda.clasifican = v;
                  onCambio();
                },
              ),
            ]),
        ],
      ),
    );
  }
}

class _PartidaEditor extends StatelessWidget {
  final int indice;
  final PartidaTorneo partida;
  final VoidCallback onCambio;
  final VoidCallback? onBorrar;

  const _PartidaEditor({
    super.key,
    required this.indice,
    required this.partida,
    required this.onCambio,
    this.onBorrar,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final estilo = TextStyle(fontSize: 12, color: war.texto);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text('${indice + 1}.', style: TextStyle(color: war.textoTenue, fontSize: 12)),
        const SizedBox(width: 8),
        DropdownButton<TipoPartidaTorneo>(
          value: partida.tipo,
          dropdownColor: war.superficie,
          style: estilo,
          underline: const SizedBox(),
          items: TipoPartidaTorneo.values
              .map((t) => DropdownMenuItem(value: t, child: Text(t.nombre)))
              .toList(),
          onChanged: (v) {
            partida.tipo = v ?? TipoPartidaTorneo.partida;
            if (partida.esDuelo) {
              partida.jugadores = 2;
              partida.modo = ModoPartida.normal;
            } else if (partida.jugadores < 4) {
              partida.jugadores = 4;
            }
            onCambio();
          },
        ),
        const SizedBox(width: 10),
        if (!partida.esDuelo) ...[
          DropdownButton<int>(
            value: partida.jugadores,
            dropdownColor: war.superficie,
            style: estilo,
            underline: const SizedBox(),
            items: const [2, 4, 6, 8]
                .map((n) => DropdownMenuItem(value: n, child: Text('$n jug.')))
                .toList(),
            onChanged: (v) {
              partida.jugadores = v ?? 4;
              onCambio();
            },
          ),
          const SizedBox(width: 10),
          Flexible(
            child: DropdownButton<ModoPartida>(
              value: partida.modo,
              isExpanded: true,
              dropdownColor: war.superficie,
              style: estilo,
              underline: const SizedBox(),
              items: ModoPartida.values
                  .map((m) => DropdownMenuItem(
                      value: m, child: Text('${m.icono} ${m.etiqueta}', overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                partida.modo = v ?? ModoPartida.normal;
                onCambio();
              },
            ),
          ),
        ] else
          Expanded(child: Text('1 vs 1', style: TextStyle(fontSize: 12, color: war.textoTenue))),
        if (onBorrar != null)
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove_circle_outline, size: 18, color: war.textoTenue),
              onPressed: onBorrar),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PREMIO
// ═══════════════════════════════════════════════════════════════════════════

class _PremioEditor extends StatefulWidget {
  final PremioTorneo premio;
  final bool bloqueado;
  final VoidCallback onCambio;
  final VoidCallback onBorrar;

  const _PremioEditor({
    super.key,
    required this.premio,
    required this.bloqueado,
    required this.onCambio,
    required this.onBorrar,
  });

  @override
  State<_PremioEditor> createState() => _PremioEditorState();
}

class _PremioEditorState extends State<_PremioEditor> {
  late final TextEditingController _xp;
  late final TextEditingController _dinero;
  late final TextEditingController _zero;
  late final TextEditingController _externo;

  PremioTorneo get p => widget.premio;

  @override
  void initState() {
    super.initState();
    String n(int v) => v == 0 ? '' : '$v';
    _xp = TextEditingController(text: n(p.xp));
    _dinero = TextEditingController(text: n(p.dinero));
    _zero = TextEditingController(text: n(p.zero));
    _externo = TextEditingController(text: p.externo);
  }

  @override
  void dispose() {
    _xp.dispose();
    _dinero.dispose();
    _zero.dispose();
    _externo.dispose();
    super.dispose();
  }

  Future<void> _elegirCarta() async {
    final c = await Navigator.of(context).push<CartaModel>(
      MaterialPageRoute(builder: (_) => const SeleccionarCartaScreen()),
    );
    if (c == null) return;
    setState(() {
      p.cartaId = c.id;
      p.cartaNombre = c.nombre;
      if (p.cartaCantidad < 1) p.cartaCantidad = 1;
    });
    widget.onCambio();
  }

  Widget _numero(TextEditingController c, String label, ValueChanged<int> set) {
    final war = context.war;
    return Expanded(
      child: TextField(
        controller: c,
        enabled: !widget.bloqueado,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(color: war.texto, fontSize: 13),
        decoration: _deco(war, label),
        onChanged: (v) {
          set(int.tryParse(v) ?? 0);
          widget.onCambio();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final bloq = widget.bloqueado;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0B040).withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Rango de puestos
        Row(children: [
          const Icon(Icons.emoji_events, size: 18, color: Color(0xFFE0B040)),
          const SizedBox(width: 6),
          Text('PUESTO', style: TextStyle(fontSize: 11, color: war.textoTenue)),
          _Contador(
            valor: p.desde,
            min: 1,
            max: 999,
            onCambio: (v) {
              if (bloq) return;
              setState(() {
                p.desde = v;
                if (p.hasta < v) p.hasta = v;
              });
              widget.onCambio();
            },
          ),
          Text('A', style: TextStyle(fontSize: 11, color: war.textoTenue)),
          _Contador(
            valor: p.hasta,
            min: p.desde,
            max: 999,
            onCambio: (v) {
              if (bloq) return;
              setState(() => p.hasta = v);
              widget.onCambio();
            },
          ),
          const Spacer(),
          if (!bloq)
            IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: war.textoTenue),
                onPressed: widget.onBorrar),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _numero(_xp, 'Experiencia', (v) => p.xp = v),
          const SizedBox(width: 8),
          _numero(_dinero, 'Dinero', (v) => p.dinero = v),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _numero(_zero, 'Cristales Zero', (v) => p.zero = v),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<MonedaZero>(
              value: p.zeroTipo,
              isExpanded: true,
              dropdownColor: war.superficie,
              style: TextStyle(color: war.texto, fontSize: 13),
              decoration: _deco(war, 'Tipo de cristal'),
              items: MonedaZero.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.colorNombre)))
                  .toList(),
              onChanged: bloq
                  ? null
                  : (v) {
                      setState(() => p.zeroTipo = v ?? MonedaZero.puro);
                      widget.onCambio();
                    },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Carta
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: bloq ? null : _elegirCarta,
              child: InputDecorator(
                decoration: _deco(war, 'Carta de premio').copyWith(
                    suffixIcon: Icon(Icons.style_outlined, size: 18, color: war.textoTenue)),
                child: Text(
                  p.tieneCarta
                      ? (p.cartaNombre.isNotEmpty ? p.cartaNombre : p.cartaId)
                      : 'Ninguna (toca para elegir)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: p.tieneCarta ? war.texto : war.textoTenue),
                ),
              ),
            ),
          ),
          if (p.tieneCarta) ...[
            _Contador(
              valor: p.cartaCantidad,
              min: 1,
              max: 99,
              onCambio: (v) {
                if (bloq) return;
                setState(() => p.cartaCantidad = v);
                widget.onCambio();
              },
            ),
            if (!bloq)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Quitar carta',
                icon: Icon(Icons.close, size: 16, color: war.textoTenue),
                onPressed: () {
                  setState(() {
                    p.cartaId = '';
                    p.cartaNombre = '';
                  });
                  widget.onCambio();
                },
              ),
          ],
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _externo,
          enabled: !bloq,
          maxLines: 2,
          minLines: 1,
          style: TextStyle(color: war.texto, fontSize: 13),
          decoration: _deco(war, 'Premio fuera de la app (opcional)')
              .copyWith(hintText: 'Ej.: camiseta oficial, 50 € en metálico…'),
          onChanged: (v) {
            p.externo = v;
            widget.onCambio();
          },
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS AUXILIARES
// ═══════════════════════════════════════════════════════════════════════════

InputDecoration _deco(WarColors war, String label) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: war.textoTenue),
      filled: true,
      fillColor: war.superficie,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: war.borde)),
    );

class _Seccion extends StatelessWidget {
  final String titulo;
  const _Seccion({required this.titulo});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(titulo,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
                color: context.war.primario)),
      );
}

class _CampoFecha extends StatelessWidget {
  final String etiqueta;
  final DateTime? valor;
  final VoidCallback onTap;
  const _CampoFecha({required this.etiqueta, required this.valor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: _deco(war, etiqueta).copyWith(
              suffixIcon: Icon(Icons.event, color: war.textoTenue, size: 18)),
          child: Text(fechaTorneo(valor), style: TextStyle(color: war.texto)),
        ),
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  final int valor;
  final int min;
  final int max;
  final ValueChanged<int> onCambio;
  const _Contador({required this.valor, required this.min, required this.max, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 16),
          color: war.texto,
          onPressed: valor > min ? () => onCambio(valor - 1) : null),
      SizedBox(
          width: 34,
          child: Text('$valor',
              textAlign: TextAlign.center,
              style: TextStyle(color: war.texto, fontWeight: FontWeight.bold))),
      IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 16),
          color: war.texto,
          onPressed: valor < max ? () => onCambio(valor + 1) : null),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final Color color;
  const _Chip({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.7)),
        ),
        child: Text(texto,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      );
}

class _Mensaje extends StatelessWidget {
  final String texto;
  final VoidCallback? onReintentar;
  const _Mensaje({required this.texto, this.onReintentar});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.war.textoTenue)),
            if (onReintentar != null)
              TextButton(onPressed: onReintentar, child: const Text('REINTENTAR')),
          ]),
        ),
      );
}
