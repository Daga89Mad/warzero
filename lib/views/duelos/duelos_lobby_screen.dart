// lib/views/duelos/duelos_lobby_screen.dart
//
// MODO DUELOS — menú de salas: EN CURSO / PÚBLICAS / PRIVADA y CREAR DUELO
// (nombre, mapa de 7×7 obligatorio, fin de turno y si es privada). Mismo
// aspecto que la Sala de Guerra del modo partida, pero todo va por la API de
// duelos (DuelosService).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:warzero/services/settings_controller.dart';

import '../../models/lobby_model.dart' show ModoTurno;
import '../../services/duelos_service.dart';
import '../../services/mapa_service.dart';
import '../lobby_screen.dart' show ModoTurnoSelector;
import 'duelos_partida_screen.dart';
import 'duelos_sala_screen.dart';

/// Acento del modo Duelos (el mismo que su botón en JUGAR).
const Color kDuelosAcento = Color(0xFF40C08A);

class DuelosLobbyScreen extends StatefulWidget {
  const DuelosLobbyScreen({super.key});

  @override
  State<DuelosLobbyScreen> createState() => _DuelosLobbyScreenState();
}

class _DuelosLobbyScreenState extends State<DuelosLobbyScreen>
    with SingleTickerProviderStateMixin {
  final _service = DuelosService();
  late final TabController _tabs;

  /// Se incrementa para que las pestañas recarguen al volver de una sala.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _alias {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final emailPart = user?.email?.split('@').first.trim() ?? '';
    if (emailPart.isNotEmpty) return emailPart;
    return 'Jugador';
  }

  Future<void> _abrir(DuelosSala sala) async {
    final destino = sala.esperando
        ? DuelosSalaScreen(salaId: sala.id, uid: _uid, alias: _alias)
        : DuelosPartidaScreen(salaId: sala.id, uid: _uid);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => destino));
    if (mounted) setState(() => _version++);
  }

  Future<void> _unirseYAbrir(String id, {String? contrasena}) async {
    try {
      final sala = await _service.unirse(
          id: id, uid: _uid, alias: _alias, contrasena: contrasena);
      if (!mounted) return;
      await _abrir(sala);
    } catch (e) {
      _error(e.toString());
    }
  }

  void _error(String msg) {
    if (!mounted) return;
    final war = context.war;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontFamily: 'Cinzel', fontSize: 11)),
      backgroundColor: war.error.withOpacity(0.25),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _crear() async {
    final sala = await showDialog<DuelosSala>(
      context: context,
      builder: (_) => _CrearDueloDialog(
        service: _service,
        uid: _uid,
        alias: _alias,
      ),
    );
    if (sala != null && mounted) await _abrir(sala);
  }

  Future<void> _unirsePrivada() async {
    final datos = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _UnirsePrivadaDialog(),
    );
    if (datos == null) return;
    await _unirseYAbrir(datos.$1, contrasena: datos.$2);
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: war.primario),
        title: Text(
          'DUELOS',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: 4,
            color: war.primario,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: war.primario,
          indicatorWeight: 1.5,
          labelStyle: const TextStyle(
              fontSize: 10, letterSpacing: 2, fontFamily: 'Cinzel'),
          unselectedLabelColor: war.textoTenue,
          labelColor: war.primario,
          tabs: const [
            Tab(text: 'EN CURSO'),
            Tab(text: 'PÚBLICAS'),
            Tab(text: 'PRIVADA'),
          ],
        ),
        actions: [
          DuelosBoton(label: 'CREAR DUELO', icon: Icons.add, onTap: _crear),
          const SizedBox(width: 12),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ListaDuelos(
            key: ValueKey('mis$_version'),
            cargar: () => _service.misDuelos(_uid),
            vacio: 'No tienes duelos activos.\nCrea uno o únete a una sala.',
            iconoVacio: Icons.inbox_outlined,
            uid: _uid,
            onTap: _abrir,
          ),
          _ListaDuelos(
            key: ValueKey('pub$_version'),
            cargar: () => _service.publicas(_uid),
            vacio: 'No hay duelos públicos.\n¡Crea el primero!',
            iconoVacio: Icons.public_off,
            uid: _uid,
            onTap: (s) => s.soyParticipante ? _abrir(s) : _unirseYAbrir(s.id),
          ),
          _PestanaPrivada(onUnirse: _unirsePrivada),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA DE DUELOS (EN CURSO / PÚBLICAS)
// ─────────────────────────────────────────────────────────────
class _ListaDuelos extends StatefulWidget {
  final Future<List<DuelosSala>> Function() cargar;
  final String vacio;
  final IconData iconoVacio;
  final String uid;
  final void Function(DuelosSala) onTap;

  const _ListaDuelos({
    super.key,
    required this.cargar,
    required this.vacio,
    required this.iconoVacio,
    required this.uid,
    required this.onTap,
  });

  @override
  State<_ListaDuelos> createState() => _ListaDuelosState();
}

class _ListaDuelosState extends State<_ListaDuelos> {
  Future<List<DuelosSala>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.cargar();
  }

  Future<void> _recargar() async {
    setState(() => _future = widget.cargar());
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return FutureBuilder<List<DuelosSala>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: war.primario));
        }
        if (snap.hasError) {
          return DuelosMensaje(
            icono: Icons.cloud_off,
            texto: 'No se pudieron cargar los duelos.\n${snap.error}',
            accion: 'REINTENTAR',
            onAccion: _recargar,
          );
        }
        final duelos = snap.data ?? const [];
        if (duelos.isEmpty) {
          return RefreshIndicator(
            color: war.primario,
            backgroundColor: war.superficie,
            onRefresh: _recargar,
            child: ListView(children: [
              const SizedBox(height: 120),
              DuelosMensaje(icono: widget.iconoVacio, texto: widget.vacio),
            ]),
          );
        }
        return RefreshIndicator(
          color: war.primario,
          backgroundColor: war.superficie,
          onRefresh: _recargar,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: duelos.length,
            itemBuilder: (_, i) => _TarjetaDuelo(
              sala: duelos[i],
              uid: widget.uid,
              onTap: () => widget.onTap(duelos[i]),
            ),
          ),
        );
      },
    );
  }
}

class _TarjetaDuelo extends StatelessWidget {
  final DuelosSala sala;
  final String uid;
  final VoidCallback onTap;

  const _TarjetaDuelo({
    required this.sala,
    required this.uid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    late final String estado;
    late final Color color;
    late final IconData icono;
    if (sala.finalizada) {
      estado = switch (sala.resultado) {
        'victoria' => 'VICTORIA',
        'derrota' => 'DERROTA',
        _ => 'TABLAS',
      };
      color = sala.resultado == 'victoria'
          ? const Color(0xFFFFCC00)
          : war.textoTenue;
      icono = sala.resultado == 'victoria'
          ? Icons.emoji_events
          : Icons.flag_outlined;
    } else if (sala.enCurso) {
      if (sala.yaJugue) {
        estado = 'EN ESPERA';
        color = war.primario;
        icono = Icons.hourglass_top;
      } else {
        estado = 'JUGAR';
        color = kDuelosAcento;
        icono = Icons.play_arrow;
      }
    } else if (sala.soyParticipante) {
      estado = 'EN SALA';
      color = war.primario;
      icono = Icons.meeting_room;
    } else {
      estado = sala.llena ? 'LLENA' : 'ENTRAR';
      color = sala.llena ? war.textoTenue : war.secundario;
      icono = Icons.sports_kabaddi_outlined;
    }

    final rival = sala.jugadores
        .where((j) => j.uid != uid)
        .map((j) => j.alias)
        .join(', ');

    return GestureDetector(
      onTap: sala.llena && !sala.soyParticipante ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.30), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withOpacity(0.30), width: 1),
              ),
              child: Icon(icono, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sala.nombre,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: war.primario,
                          fontFamily: 'Cinzel',
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.person, size: 10, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        rival.isEmpty
                            ? '${sala.numJugadores}/${sala.maxJugadores} · esperando rival'
                            : sala.soyParticipante
                                ? 'contra $rival'
                                : '${sala.numJugadores}/${sala.maxJugadores} · $rival',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9,
                            color: color.withOpacity(0.85),
                            fontFamily: 'Cinzel',
                            letterSpacing: 1),
                      ),
                    ),
                    if (sala.enCurso) ...[
                      const SizedBox(width: 10),
                      Text('TURNO ${sala.turno}',
                          style: TextStyle(
                              fontSize: 8,
                              color: color.withOpacity(0.85),
                              fontFamily: 'Cinzel',
                              letterSpacing: 1)),
                    ],
                    if (sala.esPrivada) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.lock, size: 9, color: color.withOpacity(0.6)),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(
                      [
                        if (sala.mapaNombre.isNotEmpty)
                          sala.mapaNombre.toUpperCase(),
                        textoModoDuelo(sala.modoTurno),
                      ].join('  ·  '),
                      style: TextStyle(
                          fontSize: 7,
                          color: war.textoTenue,
                          fontFamily: 'Cinzel',
                          letterSpacing: 1)),
                ],
              ),
            ),
            DuelosChip(label: estado, color: color),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PESTAÑA PRIVADA
// ─────────────────────────────────────────────────────────────
class _PestanaPrivada extends StatelessWidget {
  final VoidCallback onUnirse;
  const _PestanaPrivada({required this.onUnirse});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 48, color: war.borde),
          const SizedBox(height: 16),
          Text('DUELO PRIVADO',
              style: TextStyle(
                  fontSize: 14,
                  color: war.primario,
                  letterSpacing: 4,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Introduce el código de la sala y la contraseña\n'
            'que te ha pasado tu rival.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                color: war.textoTenue,
                fontFamily: 'Cinzel',
                height: 1.8,
                letterSpacing: 1),
          ),
          const SizedBox(height: 32),
          DuelosBoton(
              label: 'UNIRSE CON CÓDIGO',
              icon: Icons.vpn_key,
              onTap: onUnirse,
              width: 210),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO: CREAR DUELO
// ─────────────────────────────────────────────────────────────
class _CrearDueloDialog extends StatefulWidget {
  final DuelosService service;
  final String uid;
  final String alias;

  const _CrearDueloDialog({
    required this.service,
    required this.uid,
    required this.alias,
  });

  @override
  State<_CrearDueloDialog> createState() => _CrearDueloDialogState();
}

class _CrearDueloDialogState extends State<_CrearDueloDialog> {
  final _nombreCtrl = TextEditingController(text: 'Mi duelo');
  final _passCtrl = TextEditingController();
  bool _esPrivada = false;
  bool _creando = false;
  String? _error;

  ModoTurno _modoTurno = ModoTurno.rapida;

  List<MapaInfo> _mapas = [];
  bool _cargandoMapas = true;
  String? _errorMapas;

  /// Mapa elegido. Es obligatorio: no hay tablero "sin mapa".
  String? _mapaId;

  @override
  void initState() {
    super.initState();
    _cargarMapas();
  }

  /// Solo valen los mapas de 7×7 (el tablero de los duelos) que NO están
  /// ocultos (`seleccionable` = false en la edición de mapas). Las casillas
  /// que no son de tierra quedan bloqueadas.
  Future<void> _cargarMapas() async {
    try {
      final todos = await MapaService().obtenerMapas(soloSeleccionables: true);
      if (!mounted) return;
      setState(() {
        _mapas = todos
            .where((m) => m.seleccionable && m.filas == 7 && m.columnas == 7)
            .toList();
        if (_mapas.isNotEmpty && !_mapas.any((m) => m.id == _mapaId)) {
          _mapaId = _mapas.first.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _errorMapas = e.toString());
    } finally {
      if (mounted) setState(() => _cargandoMapas = false);
    }
  }

  void _reintentarMapas() {
    setState(() {
      _cargandoMapas = true;
      _errorMapas = null;
    });
    _cargarMapas();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    if (_mapaId == null) {
      setState(() => _error = 'Elige un mapa.');
      return;
    }
    if (_esPrivada && _passCtrl.text.isEmpty) {
      setState(() => _error = 'Una sala privada necesita contraseña.');
      return;
    }
    setState(() {
      _creando = true;
      _error = null;
    });
    try {
      final sala = await widget.service.crear(
        uid: widget.uid,
        alias: widget.alias,
        nombre: nombre,
        esPrivada: _esPrivada,
        contrasena: _esPrivada ? _passCtrl.text : '',
        mapaId: _mapaId!,
        modoTurno: _modoTurno,
      );
      if (mounted) Navigator.of(context).pop(sala);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Dialog(
      backgroundColor: war.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: war.borde.withOpacity(0.4), width: 1),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CREAR DUELO',
                style: TextStyle(
                    fontSize: 16,
                    color: war.primario,
                    fontFamily: 'Cinzel',
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Divider(color: war.primario.withOpacity(0.2)),
            const SizedBox(height: 16),
            const DuelosEtiqueta('NOMBRE DEL DUELO'),
            DuelosCampoTexto(controller: _nombreCtrl, hint: 'Mi duelo'),
            const SizedBox(height: 16),
            const DuelosEtiqueta('MAPA'),
            if (_cargandoMapas)
              SizedBox(
                height: 36,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: war.textoTenue, strokeWidth: 1.5),
                  ),
                ),
              )
            else if (_errorMapas != null)
              _AvisoMapas(
                texto: 'No se pudieron cargar los mapas.',
                onReintentar: _reintentarMapas,
              )
            else if (_mapas.isEmpty)
              const _AvisoMapas(
                texto: 'No hay mapas de 7×7 disponibles para duelos.',
              )
            else
              ..._mapas.map((m) {
                final sel = m.id == _mapaId;
                return GestureDetector(
                  onTap: () => setState(() => _mapaId = m.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? kDuelosAcento.withOpacity(0.08) : war.fondo,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: sel
                            ? kDuelosAcento.withOpacity(0.6)
                            : war.borde.withOpacity(0.25),
                        width: sel ? 1.2 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.map_outlined,
                          size: 14,
                          color: sel ? kDuelosAcento : war.textoTenue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          m.nombre.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              color: sel ? kDuelosAcento : war.textoTenue,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1,
                              fontWeight:
                                  sel ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                      if (sel)
                        const Icon(Icons.check_circle,
                            size: 14, color: kDuelosAcento),
                    ]),
                  ),
                );
              }),
            const SizedBox(height: 16),
            const DuelosEtiqueta('FIN DE TURNO'),
            ModoTurnoSelector(
              selected: _modoTurno,
              onChanged: (m) => setState(() => _modoTurno = m),
            ),
            const SizedBox(height: 6),
            Text(
              'Si un jugador no cierra su turno a tiempo, se cierra sin '
              'mover. Con 3 turnos seguidos sin pulsar FIN DE TURNO pierde '
              'el duelo.',
              style: TextStyle(
                  fontSize: 8,
                  color: war.textoTenue,
                  fontFamily: 'Cinzel',
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _esPrivada = !_esPrivada),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _esPrivada ? war.primario : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: war.borde, width: 1),
                  ),
                  child: _esPrivada
                      ? Icon(Icons.check, size: 14, color: war.fondo)
                      : null,
                ),
                const SizedBox(width: 10),
                Text('DUELO PRIVADO',
                    style: TextStyle(
                        fontSize: 10,
                        color: war.texto,
                        fontFamily: 'Cinzel',
                        letterSpacing: 1.5)),
              ]),
            ),
            if (_esPrivada) ...[
              const SizedBox(height: 16),
              const DuelosEtiqueta('CONTRASEÑA'),
              DuelosCampoTexto(
                  controller: _passCtrl, hint: '••••••', oculto: true),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      fontSize: 10, color: war.error, fontFamily: 'Cinzel')),
            ],
            const SizedBox(height: 24),
            Row(children: [
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
                  label: 'CREAR',
                  icon: Icons.check,
                  cargando: _creando,
                  onTap: (_creando || _mapaId == null) ? null : _crear,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Aviso dentro del selector de mapas (sin mapas o error al cargarlos).
class _AvisoMapas extends StatelessWidget {
  final String texto;
  final VoidCallback? onReintentar;
  const _AvisoMapas({required this.texto, this.onReintentar});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: war.fondo,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: war.borde.withOpacity(0.3), width: 1),
      ),
      child: Row(children: [
        Icon(Icons.map_outlined, size: 14, color: war.textoTenue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texto,
              style: TextStyle(
                  fontSize: 9, color: war.textoTenue, fontFamily: 'Cinzel')),
        ),
        if (onReintentar != null)
          GestureDetector(
            onTap: onReintentar,
            child: Icon(Icons.refresh, size: 16, color: war.primario),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO: UNIRSE A UN DUELO PRIVADO
// ─────────────────────────────────────────────────────────────
class _UnirsePrivadaDialog extends StatefulWidget {
  const _UnirsePrivadaDialog();

  @override
  State<_UnirsePrivadaDialog> createState() => _UnirsePrivadaDialogState();
}

class _UnirsePrivadaDialogState extends State<_UnirsePrivadaDialog> {
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Dialog(
      backgroundColor: war.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: war.borde.withOpacity(0.4), width: 1),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UNIRSE A UN DUELO PRIVADO',
                style: TextStyle(
                    fontSize: 13,
                    color: war.primario,
                    fontFamily: 'Cinzel',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            Divider(color: war.primario.withOpacity(0.2)),
            const SizedBox(height: 16),
            const DuelosEtiqueta('CÓDIGO DE SALA'),
            DuelosCampoTexto(controller: _idCtrl, hint: 'Código…'),
            const SizedBox(height: 16),
            const DuelosEtiqueta('CONTRASEÑA'),
            DuelosCampoTexto(
                controller: _passCtrl, hint: '••••••', oculto: true),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: DuelosBoton(
                label: 'ENTRAR',
                icon: Icons.login,
                onTap: () {
                  final id = _idCtrl.text.trim();
                  if (id.isEmpty) return;
                  Navigator.of(context).pop((id, _passCtrl.text));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WIDGETS COMPARTIDOS DEL MODO DUELOS
// ─────────────────────────────────────────────────────────────

/// Texto corto del modo de fin de turno de un duelo.
String textoModoDuelo(ModoTurno m) => switch (m) {
      ModoTurno.rapida => 'RÁPIDA · 30 S',
      ModoTurno.diario => 'DIARIO · 00:00 UTC',
      ModoTurno.turno12h => 'TURNO 12 H',
    };

class DuelosBoton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double? width;
  final bool tenue;
  final bool cargando;
  final Color? color;

  const DuelosBoton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.width,
    this.tenue = false,
    this.cargando = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final activo = onTap != null;
    final c = tenue ? war.textoTenue : (color ?? war.primario);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: activo || cargando ? 1 : 0.4,
        child: Container(
          width: width,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tenue ? Colors.transparent : c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.withOpacity(0.45), width: 1),
          ),
          child: cargando
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: c, strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: c),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 9,
                              color: c,
                              fontFamily: 'Cinzel',
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class DuelosChip extends StatelessWidget {
  final String label;
  final Color color;
  const DuelosChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.40), width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 8,
              color: color,
              fontFamily: 'Cinzel',
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold)),
    );
  }
}

class DuelosEtiqueta extends StatelessWidget {
  final String texto;
  const DuelosEtiqueta(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texto,
          style: TextStyle(
              fontSize: 8,
              color: war.textoTenue,
              fontFamily: 'Cinzel',
              letterSpacing: 2)),
    );
  }
}

class DuelosCampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool oculto;

  const DuelosCampoTexto({
    super.key,
    required this.controller,
    required this.hint,
    this.oculto = false,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return TextField(
      controller: controller,
      obscureText: oculto,
      style: TextStyle(color: war.texto, fontFamily: 'Cinzel', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: war.textoTenue.withOpacity(0.6),
            fontFamily: 'Cinzel',
            fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: war.borde.withOpacity(0.4), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: war.primario, width: 1.2),
          borderRadius: BorderRadius.circular(4),
        ),
        fillColor: war.fondo,
        filled: true,
      ),
    );
  }
}

class DuelosMensaje extends StatelessWidget {
  final IconData icono;
  final String texto;
  final String? accion;
  final VoidCallback? onAccion;

  const DuelosMensaje({
    super.key,
    required this.icono,
    required this.texto,
    this.accion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: war.borde),
            const SizedBox(height: 16),
            Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    color: war.textoTenue,
                    fontFamily: 'Cinzel',
                    height: 1.8,
                    letterSpacing: 1)),
            if (accion != null) ...[
              const SizedBox(height: 16),
              DuelosBoton(
                  label: accion!,
                  icon: Icons.refresh,
                  onTap: onAccion,
                  width: 170),
            ],
          ],
        ),
      ),
    );
  }
}
