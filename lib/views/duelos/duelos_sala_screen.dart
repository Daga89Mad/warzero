// lib/views/duelos/duelos_sala_screen.dart
//
// MODO DUELOS — sala de espera. Cada jugador elige ejército; al elegirlo se
// abre una ventana con los generales de ese ejército y sus habilidades: elige
// dos y cuál de ellos es su COMANDANTE (el general que hay que proteger: si
// cae, pierde la batalla). El rival nunca sabe cuál es.
//
// La sala se refresca sondeando la API cada pocos segundos (las salas de duelo
// no se leen de Firestore). Cuando el anfitrión inicia, se pasa a la partida.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:warzero/services/settings_controller.dart';

import '../../models/lobby_model.dart';
import '../../services/duelos_service.dart';
import '../../services/ejercito_service.dart';
import 'duelos_lobby_screen.dart';
import 'duelos_partida_screen.dart';

class DuelosSalaScreen extends StatefulWidget {
  final String salaId;
  final String uid;
  final String alias;

  const DuelosSalaScreen({
    super.key,
    required this.salaId,
    required this.uid,
    required this.alias,
  });

  @override
  State<DuelosSalaScreen> createState() => _DuelosSalaScreenState();
}

class _DuelosSalaScreenState extends State<DuelosSalaScreen> {
  final _service = DuelosService();

  DuelosSala? _sala;
  DuelosCatalogo? _catalogo;
  Map<int, EjercitoInfo> _ejercitos = {};
  String? _error;
  bool _iniciando = false;
  bool _saliendo = false;
  bool _navegando = false;
  Timer? _sondeo;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    _sondeo = Timer.periodic(const Duration(seconds: 3), (_) => _refrescar());
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    try {
      final cat = await _service.catalogo();
      final ejs = await EjercitoService().fetchEjercitos();
      if (!mounted) return;
      setState(() {
        _catalogo = cat;
        _ejercitos = {for (final e in ejs) e.id: e};
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    await _refrescar();
  }

  Future<void> _refrescar() async {
    if (_navegando) return;
    try {
      final sala = await _service.sala(widget.salaId, widget.uid);
      if (!mounted) return;
      setState(() {
        _sala = sala;
        _error = null;
      });
      if (!sala.esperando) _irAPartida();
    } on DuelosError catch (e) {
      if (!mounted) return;
      // La sala ya no existe (se fue el otro jugador y estaba vacía).
      setState(() => _error = e.mensaje);
    } catch (_) {
      // Fallo de red puntual: el siguiente sondeo lo reintenta.
    }
  }

  void _irAPartida() {
    if (_navegando) return;
    _navegando = true;
    _sondeo?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          DuelosPartidaScreen(salaId: widget.salaId, uid: widget.uid),
    ));
  }

  void _aviso(String msg, {bool error = true}) {
    if (!mounted) return;
    final war = context.war;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontFamily: 'Cinzel', fontSize: 11)),
      backgroundColor: (error ? war.error : war.secundario).withOpacity(0.25),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Elección de ejército y generales ──────────────────────

  Future<void> _elegirEjercito(DuelosEjercitoInfo ejercito) async {
    final yo = _sala?.jugador(widget.uid);
    final mismo = yo?.ejercitoId == ejercito.id;
    final eleccion = await showDialog<_EleccionGenerales>(
      context: context,
      builder: (_) => DuelosGeneralesDialog(
        ejercito: ejercito,
        icono: _ejercitos[ejercito.id]?.icono ?? '⚔️',
        terminoComandante: _catalogo?.comandante ?? kDuelosTerminoComandante,
        generalesIniciales: mismo ? yo!.generales : const [],
        comandanteInicial: mismo ? yo!.comandante : null,
      ),
    );
    if (eleccion == null) return;
    try {
      final sala = await _service.elegir(
        id: widget.salaId,
        uid: widget.uid,
        ejercitoId: ejercito.id,
        generales: eleccion.generales,
        comandante: eleccion.comandante,
      );
      if (mounted) setState(() => _sala = sala);
    } catch (e) {
      _aviso(e.toString());
    }
  }

  Future<void> _iniciar() async {
    setState(() => _iniciando = true);
    try {
      final sala = await _service.iniciar(id: widget.salaId, uid: widget.uid);
      if (!mounted) return;
      setState(() => _sala = sala);
      if (!sala.esperando) _irAPartida();
    } catch (e) {
      _aviso(e.toString());
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  Future<void> _salir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final war = ctx.war;
        return AlertDialog(
          backgroundColor: war.superficie,
          title: Text('¿SALIR DE LA SALA?',
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 13, color: war.primario)),
          content: Text(
              'Dejarás tu sitio libre. Si eres el anfitrión, la sala pasará '
              'a tu rival (o se borrará si no hay nadie).',
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 10, color: war.texto)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('CANCELAR',
                    style: TextStyle(
                        fontFamily: 'Cinzel', color: war.textoTenue))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('SALIR',
                    style:
                        TextStyle(fontFamily: 'Cinzel', color: war.error))),
          ],
        );
      },
    );
    if (ok != true) return;
    setState(() => _saliendo = true);
    try {
      await _service.salir(id: widget.salaId, uid: widget.uid);
      _sondeo?.cancel();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _aviso(e.toString());
    } finally {
      if (mounted) setState(() => _saliendo = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final sala = _sala;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text(
          sala?.nombre.toUpperCase() ?? 'DUELO',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 3,
            color: war.primario,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (sala != null && sala.esPrivada)
            IconButton(
              tooltip: 'Copiar código de sala',
              icon: Icon(Icons.copy, size: 18, color: war.primario),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: sala.id));
                _aviso('Código copiado: ${sala.id}', error: false);
              },
            ),
          IconButton(
            tooltip: 'Salir de la sala',
            icon: Icon(Icons.logout, size: 18, color: war.error),
            onPressed: _saliendo ? null : _salir,
          ),
        ],
      ),
      body: sala == null
          ? (_error != null
              ? DuelosMensaje(
                  icono: Icons.error_outline,
                  texto: _error!,
                  accion: 'REINTENTAR',
                  onAccion: _cargarTodo)
              : Center(child: CircularProgressIndicator(color: war.primario)))
          : _cuerpo(sala),
    );
  }

  Widget _cuerpo(DuelosSala sala) {
    final war = context.war;
    final yo = sala.jugador(widget.uid);
    final soyHost = sala.hostUid == widget.uid;
    final puedeIniciar =
        soyHost && sala.llena && sala.jugadores.every((j) => j.listo);
    final cat = _catalogo;
    final miEjercito = cat?.ejercito(yo?.ejercitoId);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // ── Datos de la sala ──
              Row(children: [
                Icon(Icons.map_outlined, size: 12, color: war.textoTenue),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${sala.mapaNombre.isEmpty ? 'TABLERO DE DUELO' : sala.mapaNombre.toUpperCase()}'
                    '  ·  ${textoModoDuelo(sala.modoTurno)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        letterSpacing: 1.5),
                  ),
                ),
                const Spacer(),
                if (sala.esPrivada)
                  Text('CÓDIGO: ${sala.id}',
                      style: TextStyle(
                          fontSize: 8,
                          color: war.textoTenue,
                          fontFamily: 'Cinzel',
                          letterSpacing: 1)),
              ]),
              const SizedBox(height: 12),

              // ── Jugadores ──
              for (int i = 0; i < sala.maxJugadores; i++)
                _FilaJugador(
                  jugador: i < sala.jugadores.length ? sala.jugadores[i] : null,
                  ejercito: i < sala.jugadores.length
                      ? _ejercitos[sala.jugadores[i].ejercitoId]
                      : null,
                ),
              const SizedBox(height: 18),

              // ── Mi elección ──
              if (cat == null)
                Center(child: CircularProgressIndicator(color: war.primario))
              else if (yo != null && yo.listo && miEjercito != null)
                _ResumenEleccion(
                  ejercito: miEjercito,
                  icono: _ejercitos[miEjercito.id]?.icono ?? '⚔️',
                  generales: yo.generales,
                  comandante: yo.comandante,
                  terminoComandante: cat.comandante,
                  onCambiar: () => _elegirEjercito(miEjercito),
                  onOtroEjercito: () => setState(() => _cambiandoEjercito = true),
                )
              else
                const SizedBox.shrink(),
              if (cat != null && (yo == null || !yo.listo || _cambiandoEjercito)) ...[
                const DuelosEtiqueta('ELIGE TU EJÉRCITO'),
                for (final ej in cat.ejercitos)
                  _TarjetaEjercito(
                    ejercito: ej,
                    info: _ejercitos[ej.id],
                    seleccionado: yo?.ejercitoId == ej.id,
                    onTap: () async {
                      setState(() => _cambiandoEjercito = false);
                      await _elegirEjercito(ej);
                    },
                  ),
              ],
            ],
          ),
        ),

        // ── Pie: iniciar / esperar ──
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          decoration: BoxDecoration(
            color: war.superficie,
            border: Border(top: BorderSide(color: war.borde.withOpacity(0.3))),
          ),
          child: SafeArea(
            top: false,
            child: soyHost
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    if (!puedeIniciar)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          !sala.llena
                              ? 'Esperando a un rival…'
                              : 'Los dos jugadores tienen que elegir sus generales.',
                          style: TextStyle(
                              fontSize: 9,
                              color: war.textoTenue,
                              fontFamily: 'Cinzel'),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: DuelosBoton(
                        label: 'INICIAR DUELO',
                        icon: Icons.sports_kabaddi,
                        color: kDuelosAcento,
                        cargando: _iniciando,
                        onTap: puedeIniciar && !_iniciando ? _iniciar : null,
                      ),
                    ),
                  ])
                : Text(
                    yo?.listo == true
                        ? 'Esperando a que el anfitrión inicie el duelo…'
                        : 'Elige tu ejército y tus generales.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        letterSpacing: 1),
                  ),
          ),
        ),
      ],
    );
  }

  /// True mientras el jugador ya listo quiere cambiar de ejército.
  bool _cambiandoEjercito = false;
}

// ─────────────────────────────────────────────────────────────
// FILA DE JUGADOR
// ─────────────────────────────────────────────────────────────
class _FilaJugador extends StatelessWidget {
  final DuelosJugadorSala? jugador;
  final EjercitoInfo? ejercito;

  const _FilaJugador({required this.jugador, required this.ejercito});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final j = jugador;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: war.borde.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(j == null ? Icons.person_outline : Icons.person,
            size: 16, color: j == null ? war.textoTenue : war.primario),
        const SizedBox(width: 10),
        Expanded(
          child: j == null
              ? Text('Esperando rival…',
                  style: TextStyle(
                      fontSize: 10,
                      color: war.textoTenue,
                      fontFamily: 'Cinzel',
                      fontStyle: FontStyle.italic))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(j.alias,
                          style: TextStyle(
                              fontSize: 11,
                              color: war.texto,
                              fontFamily: 'Cinzel',
                              fontWeight: FontWeight.bold)),
                      if (j.esHost) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.star, size: 10, color: war.primario),
                      ],
                      if (j.propio) ...[
                        const SizedBox(width: 6),
                        Text('TÚ',
                            style: TextStyle(
                                fontSize: 7,
                                color: war.secundario,
                                fontFamily: 'Cinzel',
                                letterSpacing: 1)),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      j.propio && ejercito != null
                          ? '${ejercito!.icono} ${ejercito!.nombre}'
                          : j.listo
                              ? 'Generales elegidos'
                              : 'Eligiendo…',
                      style: TextStyle(
                          fontSize: 8,
                          color: war.textoTenue,
                          fontFamily: 'Cinzel'),
                    ),
                  ],
                ),
        ),
        if (j != null)
          DuelosChip(
            label: j.listo ? 'LISTO' : 'ELIGIENDO',
            color: j.listo ? kDuelosAcento : war.textoTenue,
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TARJETA DE EJÉRCITO
// ─────────────────────────────────────────────────────────────
class _TarjetaEjercito extends StatelessWidget {
  final DuelosEjercitoInfo ejercito;
  final EjercitoInfo? info;
  final bool seleccionado;
  final VoidCallback onTap;

  const _TarjetaEjercito({
    required this.ejercito,
    required this.info,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final acento = seleccionado ? war.primario : war.borde;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: seleccionado ? war.primario.withOpacity(0.08) : war.superficie,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: acento.withOpacity(seleccionado ? 0.6 : 0.2),
              width: seleccionado ? 1.5 : 1),
        ),
        child: Row(children: [
          Text(info?.icono ?? '⚔️', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((info?.nombre ?? ejercito.nombre).toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: seleccionado ? war.primario : war.texto,
                        fontFamily: 'Cinzel',
                        letterSpacing: 1)),
                const SizedBox(height: 3),
                Text(
                    '${ejercito.habilidadEjercito.nombre}: '
                    '${ejercito.habilidadEjercito.descripcion}',
                    style: TextStyle(
                        fontSize: 8,
                        color: war.textoTenue,
                        fontFamily: 'Cinzel',
                        height: 1.5)),
                const SizedBox(height: 3),
                Text(
                    'Generales: ${ejercito.generales.map((g) => g.nombre).join(', ')}',
                    style: TextStyle(
                        fontSize: 7,
                        color: war.textoTenue.withOpacity(0.8),
                        fontFamily: 'Cinzel',
                        height: 1.5)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: war.textoTenue),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RESUMEN DE LA ELECCIÓN PROPIA
// ─────────────────────────────────────────────────────────────
class _ResumenEleccion extends StatelessWidget {
  final DuelosEjercitoInfo ejercito;
  final String icono;
  final List<String> generales;
  final int? comandante;
  final String terminoComandante;
  final VoidCallback onCambiar;
  final VoidCallback onOtroEjercito;

  const _ResumenEleccion({
    required this.ejercito,
    required this.icono,
    required this.generales,
    required this.comandante,
    required this.terminoComandante,
    required this.onCambiar,
    required this.onOtroEjercito,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDuelosAcento.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kDuelosAcento.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icono, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('TU EJÉRCITO: ${ejercito.nombre.toUpperCase()}',
                  style: TextStyle(
                      fontSize: 10,
                      color: kDuelosAcento,
                      fontFamily: 'Cinzel',
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          for (int i = 0; i < generales.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(i == comandante ? Icons.shield : Icons.person,
                    size: 14,
                    color: i == comandante ? war.primario : war.textoTenue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(generales[i],
                      style: TextStyle(
                          fontSize: 10,
                          color: war.texto,
                          fontFamily: 'Cinzel')),
                ),
                if (i == comandante)
                  DuelosChip(
                      label: terminoComandante.toUpperCase(),
                      color: war.primario),
              ]),
            ),
          const SizedBox(height: 6),
          Text(
              'Tu rival no sabrá cuál es tu $terminoComandante. '
              'Guarnición: ${ejercito.guarnicion.map((s) => s.nombre).join(', ')}.',
              style: TextStyle(
                  fontSize: 8,
                  color: war.textoTenue,
                  fontFamily: 'Cinzel',
                  height: 1.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DuelosBoton(
                  label: 'CAMBIAR GENERALES',
                  icon: Icons.edit,
                  onTap: onCambiar),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DuelosBoton(
                  label: 'OTRO EJÉRCITO',
                  icon: Icons.swap_horiz,
                  tenue: true,
                  onTap: onOtroEjercito),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// VENTANA: GENERALES DEL EJÉRCITO + COMANDANTE
// ─────────────────────────────────────────────────────────────

class _EleccionGenerales {
  final List<String> generales;
  final int comandante;
  const _EleccionGenerales(this.generales, this.comandante);
}

class DuelosGeneralesDialog extends StatefulWidget {
  final DuelosEjercitoInfo ejercito;
  final String icono;
  final String terminoComandante;
  final List<String> generalesIniciales;
  final int? comandanteInicial;

  const DuelosGeneralesDialog({
    super.key,
    required this.ejercito,
    required this.icono,
    required this.terminoComandante,
    this.generalesIniciales = const [],
    this.comandanteInicial,
  });

  @override
  State<DuelosGeneralesDialog> createState() => _DuelosGeneralesDialogState();
}

class _DuelosGeneralesDialogState extends State<DuelosGeneralesDialog> {
  /// Nombres elegidos, en el orden en que se eligieron (máximo 2).
  late List<String> _elegidos;

  /// Nombre del general elegido como Comandante.
  String? _comandante;

  @override
  void initState() {
    super.initState();
    final validos = widget.ejercito.generales.map((g) => g.nombre).toSet();
    _elegidos = widget.generalesIniciales.where(validos.contains).take(2).toList();
    final ci = widget.comandanteInicial;
    if (ci != null && ci >= 0 && ci < _elegidos.length) {
      _comandante = _elegidos[ci];
    }
  }

  void _alternar(String nombre) {
    setState(() {
      if (_elegidos.contains(nombre)) {
        _elegidos.remove(nombre);
        if (_comandante == nombre) _comandante = null;
      } else if (_elegidos.length < 2) {
        _elegidos.add(nombre);
      } else {
        // Ya hay dos: sustituye al primero que se eligió.
        final fuera = _elegidos.removeAt(0);
        if (_comandante == fuera) _comandante = null;
        _elegidos.add(nombre);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final listo = _elegidos.length == 2 && _comandante != null;
    final termino = widget.terminoComandante;

    return Dialog(
      backgroundColor: war.superficie,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: war.borde.withOpacity(0.4), width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cabecera ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(children: [
                Text(widget.icono, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'GENERALES · ${widget.ejercito.nombre.toUpperCase()}',
                    style: TextStyle(
                        fontSize: 13,
                        color: war.primario,
                        fontFamily: 'Cinzel',
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _elegidos.length < 2
                    ? 'Elige dos generales (${_elegidos.length}/2).'
                    : 'Ahora elige a tu $termino: si cae, pierdes la batalla. '
                        'Tu rival no sabrá cuál es.',
                style: TextStyle(
                    fontSize: 9,
                    color: war.textoTenue,
                    fontFamily: 'Cinzel',
                    height: 1.5),
              ),
            ),
            const SizedBox(height: 10),

            // ── Lista de generales ──
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final g in widget.ejercito.generales)
                    _TarjetaGeneral(
                      general: g,
                      elegido: _elegidos.contains(g.nombre),
                      esComandante: _comandante == g.nombre,
                      puedeSerComandante:
                          _elegidos.length == 2 && _elegidos.contains(g.nombre),
                      terminoComandante: termino,
                      onTap: () => _alternar(g.nombre),
                      onComandante: () =>
                          setState(() => _comandante = g.nombre),
                    ),
                ],
              ),
            ),

            // ── Botones ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(children: [
                Expanded(
                  child: DuelosBoton(
                    label: 'CANCELAR',
                    icon: Icons.close,
                    tenue: true,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DuelosBoton(
                    label: 'CONFIRMAR',
                    icon: Icons.check,
                    color: kDuelosAcento,
                    onTap: listo
                        ? () => Navigator.of(context).pop(_EleccionGenerales(
                            List.of(_elegidos),
                            _elegidos.indexOf(_comandante!)))
                        : null,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaGeneral extends StatelessWidget {
  final DuelosGeneralInfo general;
  final bool elegido;
  final bool esComandante;
  final bool puedeSerComandante;
  final String terminoComandante;
  final VoidCallback onTap;
  final VoidCallback onComandante;

  const _TarjetaGeneral({
    required this.general,
    required this.elegido,
    required this.esComandante,
    required this.puedeSerComandante,
    required this.terminoComandante,
    required this.onTap,
    required this.onComandante,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final acento = esComandante
        ? war.primario
        : elegido
            ? kDuelosAcento
            : war.borde;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: elegido ? acento.withOpacity(0.08) : war.fondo,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: acento.withOpacity(elegido ? 0.7 : 0.25),
              width: elegido ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen de la carta.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 54,
                height: 72,
                child: general.imagen.isEmpty
                    ? Container(
                        color: war.superficie,
                        child: Icon(Icons.person, color: war.textoTenue))
                    : Image.network(
                        general.imagen,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            color: war.superficie,
                            child: Icon(Icons.person, color: war.textoTenue)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(general.nombre.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              color: elegido ? acento : war.texto,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold)),
                    ),
                    Icon(
                        elegido
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 16,
                        color: elegido ? acento : war.textoTenue),
                  ]),
                  const SizedBox(height: 4),
                  Text('⚔ ${general.ataque}   ❤ ${general.vidas}',
                      style: TextStyle(
                          fontSize: 8,
                          color: war.textoTenue,
                          fontFamily: 'Cinzel')),
                  const SizedBox(height: 4),
                  Text(general.habilidad.nombre.toUpperCase(),
                      style: TextStyle(
                          fontSize: 8,
                          color: war.secundario,
                          fontFamily: 'Cinzel',
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(general.habilidad.descripcion,
                      style: TextStyle(
                          fontSize: 8,
                          color: war.texto.withOpacity(0.85),
                          fontFamily: 'Cinzel',
                          height: 1.45)),
                  if (puedeSerComandante) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onComandante,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: esComandante
                              ? war.primario.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: war.primario
                                  .withOpacity(esComandante ? 0.8 : 0.35)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              esComandante
                                  ? Icons.shield
                                  : Icons.shield_outlined,
                              size: 12,
                              color: war.primario),
                          const SizedBox(width: 6),
                          Text(
                              esComandante
                                  ? 'TU ${terminoComandante.toUpperCase()}'
                                  : 'HACER ${terminoComandante.toUpperCase()}',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: war.primario,
                                  fontFamily: 'Cinzel',
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
