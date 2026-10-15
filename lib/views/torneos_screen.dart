// lib/views/torneos_screen.dart
//
// MODO TORNEO · vista del jugador ("ARENA").
//
// Estética propia, distinta de los menús de partida: fondo negro-azulado con
// resplandor y rejilla, tipografía sans gruesa, tarjetas de cristal y acentos
// neón.
//
// Estructura:
//   · HERO      nombre, estado y cuenta atrás al siguiente hito
//   · TIMELINE  Inscripción → Sorteo → Rondas → Final
//   · Pestañas  PARTIDAS · RANKING · TORNEO · PREMIOS
//       - PARTIDAS: tarjetas de enfrentamiento de la ronda en curso (rivales,
//         modo, estado, PC) con el botón para ENTRAR A LA SALA real (fase 2).
//         Antes del sorteo: tarjeta de inscripción.
//       - RANKING: clasificación de la ronda (provisional o cerrada) con la
//         línea de corte de los que pasan.
//       - TORNEO: cifras, fechas y formato de rondas.
//       - PREMIOS: podio y lista de premios.
//
// [GruposTorneoLista] se mantiene aquí porque la usa la edición de torneos.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:warzero/models/jugador_model.dart'; // MonedaZero.colorNombre
import 'package:warzero/models/modo_partida.dart';
import 'package:warzero/models/torneo_model.dart';
import 'package:warzero/services/settings_controller.dart';
import 'package:warzero/services/torneos_service.dart';
import 'package:warzero/views/duelos/duelos_sala_screen.dart';
import 'package:warzero/views/room_screen.dart';

// ── Paleta ARENA (independiente del tema del juego) ─────────────────────────
class _A {
  static const fondo = Color(0xFF07090F);
  static const fondo2 = Color(0xFF0E1220);
  static const cristal = Color(0x14FFFFFF);
  static const linea = Color(0x22FFFFFF);
  static const texto = Color(0xFFF2F4F8);
  static const tenue = Color(0xFF8A93A8);
  static const neon = Color(0xFFFF3B5C);
  static const neon2 = Color(0xFFFF8A3D);
  static const cian = Color(0xFF35D6FF);
  static const verde = Color(0xFF3DFFA2);
  static const oro = Color(0xFFFFC94A);
  static const plata = Color(0xFFC9D2E0);
  static const bronce = Color(0xFFE08A4A);

  static const degradado = LinearGradient(
    colors: [neon, neon2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

TextStyle _t(double size,
        {FontWeight w = FontWeight.w600,
        Color c = _A.texto,
        double ls = 0,
        double? h}) =>
    TextStyle(
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: ls,
        height: h);

// ═══════════════════════════════════════════════════════════════════════════
// PANTALLA
// ═══════════════════════════════════════════════════════════════════════════

class TorneosScreen extends StatefulWidget {
  /// Estado ya cargado en la pantalla JUGAR (evita una segunda espera).
  final TorneoVigente? inicial;
  const TorneosScreen({super.key, this.inicial});

  @override
  State<TorneosScreen> createState() => _TorneosScreenState();
}

class _TorneosScreenState extends State<TorneosScreen>
    with SingleTickerProviderStateMixin {
  final _svc = TorneosService();
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  late final TabController _tabs = TabController(length: 4, vsync: this);
  TorneoVigente? _v;
  List<GrupoTorneo> _grupos = [];
  ClasificacionTorneo _clasif = ClasificacionTorneo.vacia;
  int? _rondaRanking; // null = ronda en curso
  bool _cargando = true;
  bool _enviando = false;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _v = widget.inicial;
    _cargar();
    // Refresca la cuenta atrás cada segundo.
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final v = await _svc.vigente();
    var grupos = <GrupoTorneo>[];
    var clasif = ClasificacionTorneo.vacia;
    if (v.hayTorneo && v.gruposSorteados) {
      final id = v.torneo!.id;
      final r = await Future.wait([
        _svc.grupos(id).catchError((_) => <GrupoTorneo>[]),
        _svc.clasificacion(id, ronda: _rondaRanking),
      ]);
      grupos = r[0] as List<GrupoTorneo>;
      clasif = r[1] as ClasificacionTorneo;
    }
    if (!mounted) return;
    setState(() {
      _v = v;
      _grupos = grupos;
      _clasif = clasif;
      _cargando = false;
    });
  }

  Future<void> _verRanking(int ronda) async {
    final t = _v?.torneo;
    if (t == null) return;
    setState(() => _rondaRanking = ronda == t.rondaActual ? null : ronda);
    final c = await _svc.clasificacion(t.id, ronda: ronda);
    if (mounted) setState(() => _clasif = c);
  }

  /// Abre la sala real de [g] y, al volver, refresca el torneo.
  Future<void> _entrar(GrupoTorneo g) async {
    final uid = _uid;
    if (uid == null || !g.tieneSala) return;
    final i = g.jugadores.indexOf(uid);
    final alias = i >= 0 && i < g.alias.length && g.alias[i].isNotEmpty
        ? g.alias[i]
        : (FirebaseAuth.instance.currentUser?.displayName ?? 'Comandante');
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => g.tipo == TipoPartidaTorneo.duelo
          ? DuelosSalaScreen(salaId: g.salaId, uid: uid, alias: alias)
          : RoomScreen(lobbyId: g.salaId, localUid: uid, localAlias: alias),
    ));
    if (mounted) _cargar();
  }

  Future<void> _alternarInscripcion() async {
    final v = _v;
    if (v?.torneo == null) return;
    setState(() => _enviando = true);
    try {
      if (v!.inscrito) {
        await _svc.desinscribir(v.torneo!.id);
        _snack('Has anulado tu inscripción.');
      } else {
        await _svc.inscribir(v.torneo!.id);
        _snack('¡Inscrito! Te avisaremos cuando se sorteen los grupos.');
      }
      await _cargar();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _A.fondo2,
      behavior: SnackBarBehavior.floating,
      content: Text(m, style: _t(13)),
    ));
  }

  /// Grupos del jugador en la ronda en curso (incluye "descansa").
  List<GrupoTorneo> get _misGrupos {
    final t = _v?.torneo;
    if (t == null || _uid == null) return [];
    return _grupos
        .where((g) => g.ronda == t.rondaActual && g.jugadores.contains(_uid))
        .toList()
      ..sort((a, b) => a.partida.compareTo(b.partida));
  }

  @override
  Widget build(BuildContext context) {
    final t = _v?.torneo;
    return Scaffold(
      backgroundColor: _A.fondo,
      body: Stack(children: [
        const _FondoArena(),
        SafeArea(
          child: t == null
              ? _SinTorneo(cargando: _cargando)
              : NestedScrollView(
                  headerSliverBuilder: (_, __) => [
                    SliverToBoxAdapter(child: _Hero(v: _v!, cargando: _cargando)),
                    SliverToBoxAdapter(child: _Timeline(v: _v!)),
                    SliverPersistentHeader(pinned: true, delegate: _TabsHeader(_tabs)),
                  ],
                  body: TabBarView(controller: _tabs, children: [
                    _TabMisPartidas(
                      v: _v!,
                      grupos: _misGrupos,
                      uid: _uid,
                      enviando: _enviando,
                      onInscripcion: _alternarInscripcion,
                      onEntrar: _entrar,
                      onRefrescar: _cargar,
                    ),
                    _TabRanking(
                      t: t,
                      clasif: _clasif,
                      uid: _uid,
                      onRonda: _verRanking,
                      onRefrescar: _cargar,
                    ),
                    _TabTorneo(t: t, inscritos: _v!.inscritos, onRefrescar: _cargar),
                    _TabPremios(premios: t.premios, onRefrescar: _cargar),
                  ]),
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FONDO
// ═══════════════════════════════════════════════════════════════════════════

class _FondoArena extends StatelessWidget {
  const _FondoArena();

  @override
  Widget build(BuildContext context) =>
      Positioned.fill(child: CustomPaint(painter: _FondoPainter()));
}

class _FondoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          colors: [_A.fondo2, _A.fondo],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(r),
    );
    void glow(Offset c, double radio, Color col) => canvas.drawCircle(
        c,
        radio,
        Paint()
          ..shader = RadialGradient(colors: [col, col.withOpacity(0)])
              .createShader(Rect.fromCircle(center: c, radius: radio)));
    glow(Offset(s.width * 0.9, 40), s.width * 0.7, _A.neon.withOpacity(0.22));
    glow(Offset(0, s.height * 0.45), s.width * 0.6, _A.cian.withOpacity(0.08));

    final p = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;
    for (var x = 0.0; x < s.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (var y = 0.0; y < s.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// HERO
// ═══════════════════════════════════════════════════════════════════════════

/// Siguiente hito y su fecha, según el estado del torneo.
({String etiqueta, DateTime? fecha}) _siguienteHito(TorneoVigente v) {
  final t = v.torneo!;
  if (v.inscripcionPendiente) {
    return (etiqueta: 'ABRE LA INSCRIPCIÓN', fecha: t.inicioInscripcion);
  }
  if (v.inscripcionAbierta) {
    return (etiqueta: 'CIERRA LA INSCRIPCIÓN', fecha: t.finInscripcion);
  }
  if (t.inicioTorneo != null && DateTime.now().isBefore(t.inicioTorneo!)) {
    return (etiqueta: 'COMIENZA EL TORNEO', fecha: t.inicioTorneo);
  }
  return (etiqueta: 'EN JUEGO', fecha: null);
}

class _Hero extends StatelessWidget {
  final TorneoVigente v;
  final bool cargando;
  const _Hero({required this.v, required this.cargando});

  @override
  Widget build(BuildContext context) {
    final t = v.torneo!;
    final hito = _siguienteHito(v);
    final enCurso = t.rondaActual > 0 && t.estado != 'finalizado';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _A.texto),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          if (cargando)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _A.neon)),
          const SizedBox(width: 8),
          _Pill(
            texto: enCurso ? '● EN DIRECTO · RONDA ${t.rondaActual}' : t.estadoNombre,
            color: enCurso ? _A.neon : _A.cian,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TORNEO', style: _t(11, c: _A.neon, ls: 4, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(t.nombre.toUpperCase(),
                style: _t(28, w: FontWeight.w900, ls: 0.5, h: 1.05)),
            if (t.descripcion.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(t.descripcion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _t(12.5, c: _A.tenue, w: FontWeight.w400, h: 1.4)),
            ],
            const SizedBox(height: 16),
            if (hito.fecha != null)
              _CuentaAtras(etiqueta: hito.etiqueta, fecha: hito.fecha!)
            else
              _Cristal(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.bolt, color: _A.oro),
                  const SizedBox(width: 8),
                  Text(
                      t.estado == 'finalizado'
                          ? 'Torneo finalizado'
                          : 'El torneo está en marcha',
                      style: _t(14, w: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _CuentaAtras extends StatelessWidget {
  final String etiqueta;
  final DateTime fecha;
  const _CuentaAtras({required this.etiqueta, required this.fecha});

  @override
  Widget build(BuildContext context) {
    var d = fecha.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    final bloques = [
      (d.inDays, 'DÍAS'),
      (d.inHours % 24, 'HRS'),
      (d.inMinutes % 60, 'MIN'),
      (d.inSeconds % 60, 'SEG'),
    ];
    return _Cristal(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(etiqueta, style: _t(10.5, c: _A.tenue, ls: 2, w: FontWeight.w700)),
          const Spacer(),
          Text(fechaTorneo(fecha), style: _t(11, c: _A.tenue, w: FontWeight.w500)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < bloques.length; i++) ...[
            Expanded(
              child: Column(children: [
                Text(bloques[i].$1.toString().padLeft(2, '0'),
                    style: _t(30, w: FontWeight.w900, h: 1)),
                const SizedBox(height: 2),
                Text(bloques[i].$2, style: _t(9, c: _A.tenue, ls: 2)),
              ]),
            ),
            if (i < bloques.length - 1)
              Text(':', style: _t(24, c: _A.neon, w: FontWeight.w900)),
          ],
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE
// ═══════════════════════════════════════════════════════════════════════════

class _Timeline extends StatelessWidget {
  final TorneoVigente v;
  const _Timeline({required this.v});

  @override
  Widget build(BuildContext context) {
    final t = v.torneo!;
    final pasos = <String>['Inscripción', 'Sorteo'];
    for (var i = 0; i < t.rondas.length; i++) {
      pasos.add(i == t.rondas.length - 1 ? 'Final' : 'Ronda ${i + 1}');
    }

    int actual;
    if (v.inscripcionPendiente || v.inscripcionAbierta) {
      actual = 0;
    } else if (t.rondaActual == 0) {
      actual = 1;
    } else {
      actual = 1 + t.rondaActual;
    }
    if (t.estado == 'finalizado') actual = pasos.length;

    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: pasos.length,
        itemBuilder: (_, i) {
          final hecho = i < actual;
          final activo = i == actual;
          final color = hecho ? _A.verde : (activo ? _A.neon : _A.linea);
          return Row(children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: activo ? 22 : 16,
                height: activo ? 22 : 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hecho ? _A.verde : _A.fondo,
                  border: Border.all(color: color, width: 2),
                  boxShadow: activo
                      ? [BoxShadow(color: _A.neon.withOpacity(0.6), blurRadius: 12)]
                      : null,
                ),
                child: hecho ? const Icon(Icons.check, size: 11, color: _A.fondo) : null,
              ),
              const SizedBox(height: 6),
              Text(pasos[i].toUpperCase(),
                  style: _t(9,
                      ls: 1.2,
                      w: activo ? FontWeight.w800 : FontWeight.w600,
                      c: activo ? _A.texto : _A.tenue)),
            ]),
            if (i < pasos.length - 1)
              Container(
                width: 36,
                height: 2,
                margin: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
                color: hecho ? _A.verde : _A.linea,
              ),
          ]);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PESTAÑAS
// ═══════════════════════════════════════════════════════════════════════════

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabController c;
  _TabsHeader(this.c);

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: _A.fondo.withOpacity(0.94),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: _A.cristal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _A.linea),
        ),
        child: TabBar(
          controller: c,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            gradient: _A.degradado,
            borderRadius: BorderRadius.circular(10),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: _A.tenue,
          labelStyle: _t(10.5, w: FontWeight.w800, ls: 1),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: const [
            Tab(text: 'PARTIDAS'),
            Tab(text: 'RANKING'),
            Tab(text: 'TORNEO'),
            Tab(text: 'PREMIOS'),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.c != c;
}

// ── MIS PARTIDAS ─────────────────────────────────────────────────────────────

class _TabMisPartidas extends StatelessWidget {
  final TorneoVigente v;
  final List<GrupoTorneo> grupos;
  final String? uid;
  final bool enviando;
  final VoidCallback onInscripcion;
  final ValueChanged<GrupoTorneo> onEntrar;
  final Future<void> Function() onRefrescar;

  const _TabMisPartidas({
    required this.v,
    required this.grupos,
    required this.uid,
    required this.enviando,
    required this.onInscripcion,
    required this.onEntrar,
    required this.onRefrescar,
  });

  @override
  Widget build(BuildContext context) {
    final t = v.torneo!;
    final ronda = t.rondaActual > 0 && t.rondaActual <= t.rondas.length
        ? t.rondas[t.rondaActual - 1]
        : null;

    final hijos = <Widget>[];

    if (!v.gruposSorteados) {
      hijos.add(_TarjetaInscripcion(v: v, enviando: enviando, onTap: onInscripcion));
      hijos.add(const SizedBox(height: 8));
      hijos.add(_Vacio(
        icono: Icons.shuffle,
        titulo: 'Partidas sin asignar',
        texto: v.inscrito
            ? 'Cuando termine la inscripción se sortearán los grupos y aquí '
                'verás contra quién juegas en cada partida.'
            : 'Apúntate para recibir tus partidas cuando se haga el sorteo.',
      ));
    } else if (grupos.isEmpty) {
      hijos.add(const _Vacio(
        icono: Icons.visibility_outlined,
        titulo: 'No participas en esta ronda',
        texto: 'Puedes seguir el formato y los premios del torneo en las otras pestañas.',
      ));
    } else {
      final jugadas = grupos.where((g) => !g.descansa).toList();
      hijos.add(_ResumenRonda(
        ronda: t.rondaActual,
        esFinal: t.rondaActual == t.rondas.length,
        partidas: jugadas.length,
        terminadas: jugadas.where((g) => g.terminada).length,
        pc: jugadas.fold<int>(0, (a, g) => a + (g.pcDe(uid) ?? 0)),
        clasifican: ronda?.clasifican ?? 0,
        finalizado: t.estado == 'finalizado',
      ));
      hijos.add(const SizedBox(height: 14));
      for (var i = 0; i < grupos.length; i++) {
        final g = grupos[i];
        hijos.add(_TarjetaEnfrentamiento(
          grupo: g,
          uid: uid,
          formato: ronda != null && g.partida - 1 < ronda.partidas.length
              ? ronda.partidas[g.partida - 1]
              : null,
          inicio: t.inicioTorneo,
          plazoHoras: t.plazoArranqueHoras,
          indice: i,
          onEntrar: () => onEntrar(g),
        ));
        hijos.add(const SizedBox(height: 12));
      }
    }

    return RefreshIndicator(
      color: _A.neon,
      backgroundColor: _A.fondo2,
      onRefresh: onRefrescar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: hijos,
      ),
    );
  }
}

class _ResumenRonda extends StatelessWidget {
  final int ronda;
  final bool esFinal;
  final int partidas;
  final int terminadas;
  final int pc;
  final int clasifican;
  final bool finalizado;
  const _ResumenRonda({
    required this.ronda,
    required this.esFinal,
    required this.partidas,
    required this.terminadas,
    required this.pc,
    required this.clasifican,
    required this.finalizado,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(esFinal ? 'GRAN FINAL' : 'RONDA $ronda', style: _t(22, w: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            esFinal
                ? 'Gana quien más PC sume entre todas las partidas'
                : 'Suma PC en tus partidas · pasan los $clasifican mejores',
            style: _t(12, c: _A.tenue, w: FontWeight.w400),
          ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: _A.degradado,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text('$pc', style: _t(20, w: FontWeight.w900, h: 1)),
          Text('TUS PC', style: _t(8, ls: 1.5, w: FontWeight.w800)),
        ]),
      ),
      ]),
      const SizedBox(height: 12),
      // Progreso de la ronda
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: partidas == 0 ? 0 : terminadas / partidas,
              minHeight: 6,
              backgroundColor: _A.linea,
              valueColor: const AlwaysStoppedAnimation(_A.verde),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(finalizado ? 'TORNEO TERMINADO' : '$terminadas / $partidas jugadas',
            style: _t(10.5, c: _A.tenue, w: FontWeight.w700, ls: 1)),
      ]),
    ]);
  }
}

class _TarjetaEnfrentamiento extends StatelessWidget {
  final GrupoTorneo grupo;
  final String? uid;
  final PartidaTorneo? formato;
  final DateTime? inicio;
  final int plazoHoras;
  final int indice;
  final VoidCallback onEntrar;

  const _TarjetaEnfrentamiento({
    required this.grupo,
    required this.uid,
    required this.formato,
    required this.inicio,
    required this.plazoHoras,
    required this.indice,
    required this.onEntrar,
  });

  ({String texto, Color color, IconData icono}) get _estado {
    if (grupo.descansa) {
      return (texto: 'PASE DIRECTO', color: _A.cian, icono: Icons.fast_forward);
    }
    switch (grupo.estado) {
      case 'jugando':
        return (texto: 'EN JUEGO', color: _A.neon, icono: Icons.bolt);
      case 'terminada':
        return (texto: 'TERMINADA', color: _A.verde, icono: Icons.check_circle);
      default:
        return (texto: 'PENDIENTE', color: _A.oro, icono: Icons.schedule);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duelo = grupo.tipo == TipoPartidaTorneo.duelo;
    final modo = grupo.modo;
    final estado = _estado;
    final rivales = <int>[
      for (var i = 0; i < grupo.jugadores.length; i++)
        if (grupo.jugadores[i] != uid) i
    ];
    final miIdx = grupo.jugadores.indexOf(uid ?? '');
    final acento = duelo ? _A.cian : (modo == ModoPartida.normal ? _A.neon : _A.neon2);
    final capacidad = formato?.jugadores ?? grupo.capacidad;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + indice * 90),
      curve: Curves.easeOutCubic,
      builder: (_, a, child) => Opacity(
        opacity: a,
        child: Transform.translate(offset: Offset(0, 20 * (1 - a)), child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [acento.withOpacity(0.18), _A.cristal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: acento.withOpacity(0.35)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: [
            // Número de partida gigante de fondo.
            Positioned(
              right: -6,
              top: -22,
              child: Text('${grupo.partida}',
                  style: _t(110, w: FontWeight.w900, c: Colors.white.withOpacity(0.05))),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('PARTIDA ${grupo.partida}',
                      style: _t(11, c: acento, ls: 2, w: FontWeight.w800)),
                  const Spacer(),
                  _Pill(texto: estado.texto, color: estado.color, icono: estado.icono),
                ]),
                const SizedBox(height: 6),
                Text(duelo ? 'Duelo 1 vs 1' : 'Batalla de $capacidad',
                    style: _t(19, w: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (!duelo && modo != ModoPartida.normal)
                    _Etiqueta(texto: '${modo.icono}  ${modo.etiqueta}', color: _A.neon2),
                  if (!grupo.descansa)
                    _Etiqueta(texto: '${grupo.jugadores.length} jugadores', color: _A.tenue),
                  if (!duelo && !grupo.descansa && grupo.jugadores.length < capacidad)
                    _Etiqueta(
                        texto: '+${capacidad - grupo.jugadores.length} bots',
                        color: _A.tenue),
                ]),
                const SizedBox(height: 16),
                if (grupo.descansa)
                  Text('Número impar de jugadores: pasas esta partida sin jugar.',
                      style: _t(12.5, c: _A.tenue, w: FontWeight.w400))
                else if (duelo && rivales.length == 1)
                  _VersusDuelo(
                    yo: miIdx >= 0 ? grupo.nombre(miIdx) : 'Tú',
                    rival: grupo.nombre(rivales.first),
                    color: acento,
                  )
                else
                  _MesaJugadores(grupo: grupo, uid: uid, color: acento),
                if (grupo.terminada) ...[
                  const SizedBox(height: 14),
                  _ResultadoGrupo(grupo: grupo, uid: uid),
                ],
                if (!grupo.descansa) ...[
                  const SizedBox(height: 16),
                  _BotonJugar(
                    grupo: grupo,
                    inicio: inicio,
                    plazoHoras: plazoHoras,
                    color: acento,
                    onEntrar: onEntrar,
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _VersusDuelo extends StatelessWidget {
  final String yo;
  final String rival;
  final Color color;
  const _VersusDuelo({required this.yo, required this.rival, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _Avatar(nombre: yo, color: color, yo: true, grande: true)),
      Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _A.degradado,
          boxShadow: [BoxShadow(color: _A.neon.withOpacity(0.5), blurRadius: 16)],
        ),
        child: Text('VS', style: _t(14, w: FontWeight.w900, ls: 1)),
      ),
      Expanded(child: _Avatar(nombre: rival, color: _A.tenue, grande: true)),
    ]);
  }
}

class _MesaJugadores extends StatelessWidget {
  final GrupoTorneo grupo;
  final String? uid;
  final Color color;
  const _MesaJugadores({required this.grupo, required this.uid, required this.color});

  @override
  Widget build(BuildContext context) {
    // Tú primero, luego los rivales.
    final orden = List<int>.generate(grupo.jugadores.length, (i) => i)
      ..sort((a, b) {
        final ay = grupo.jugadores[a] == uid ? 0 : 1;
        final by = grupo.jugadores[b] == uid ? 0 : 1;
        return ay.compareTo(by);
      });
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: [
        for (final i in orden)
          SizedBox(
            width: 68,
            child: _Avatar(
              nombre: grupo.nombre(i),
              color: color,
              yo: grupo.jugadores[i] == uid,
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String nombre;
  final Color color;
  final bool yo;
  final bool grande;
  const _Avatar({
    required this.nombre,
    required this.color,
    this.yo = false,
    this.grande = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = grande ? 58.0 : 44.0;
    final limpio = nombre.trim();
    final ini = limpio.isEmpty ? '?' : limpio.characters.first.toUpperCase();
    // Color estable por nombre para los rivales.
    final hue = (limpio.hashCode % 360).abs().toDouble();
    final base = yo ? color : HSLColor.fromAHSL(1, hue, 0.45, 0.45).toColor();
    return Column(children: [
      Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [base, base.withOpacity(0.35)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: yo ? Colors.white : Colors.white24, width: yo ? 2 : 1),
          boxShadow: yo ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 14)] : null,
        ),
        child: Text(ini, style: _t(grande ? 22 : 17, w: FontWeight.w900)),
      ),
      const SizedBox(height: 6),
      Text(yo ? 'TÚ' : nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _t(11,
              w: yo ? FontWeight.w900 : FontWeight.w500,
              c: yo ? _A.texto : _A.tenue,
              ls: yo ? 1.5 : 0)),
    ]);
  }
}

class _BotonJugar extends StatelessWidget {
  final GrupoTorneo grupo;
  final DateTime? inicio;
  final int plazoHoras;
  final Color color;
  final VoidCallback onEntrar;
  const _BotonJugar({
    required this.grupo,
    required this.inicio,
    required this.plazoHoras,
    required this.color,
    required this.onEntrar,
  });

  @override
  Widget build(BuildContext context) {
    final terminada = grupo.terminada;
    final empezado = inicio == null || DateTime.now().isAfter(inicio!);
    final puedeEntrar = grupo.tieneSala && !terminada;

    if (puedeEntrar) {
      final jugando = grupo.estado == 'jugando';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: onEntrar,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(jugando ? Icons.play_arrow_rounded : Icons.login_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(jugando ? 'CONTINUAR PARTIDA' : 'ENTRAR A LA SALA',
                  style: _t(13, w: FontWeight.w900, ls: 1.5)),
            ]),
          ),
        ),
        if (!jugando) ...[
          const SizedBox(height: 8),
          Text(
            'Elige tu ejército dentro de la sala. Tienes $plazoHoras h para '
            'prepararte; después se juega sin quien no esté listo (0 PC).',
            textAlign: TextAlign.center,
            style: _t(10.5, c: _A.tenue, w: FontWeight.w400, h: 1.35),
          ),
        ],
      ]);
    }

    final texto = terminada
        ? 'PARTIDA TERMINADA'
        : empezado
            ? 'PREPARANDO SALA…'
            : 'DISPONIBLE EL ${fechaTorneo(inicio)}';
    return Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: _A.linea),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(terminada ? Icons.check : Icons.lock_clock, size: 16, color: _A.tenue),
        const SizedBox(width: 8),
        Text(texto, style: _t(11.5, c: _A.tenue, w: FontWeight.w800, ls: 1.2)),
      ]),
    );
  }
}

/// PC conseguidos por cada jugador en un grupo terminado (tú resaltado).
class _ResultadoGrupo extends StatelessWidget {
  final GrupoTorneo grupo;
  final String? uid;
  const _ResultadoGrupo({required this.grupo, required this.uid});

  @override
  Widget build(BuildContext context) {
    final orden = List<int>.generate(grupo.jugadores.length, (i) => i)
      ..sort((a, b) => (grupo.resultados[grupo.jugadores[b]] ?? 0)
          .compareTo(grupo.resultados[grupo.jugadores[a]] ?? 0));
    return _Cristal(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(children: [
        for (var k = 0; k < orden.length; k++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 22,
                child: Text('${k + 1}', style: _t(12, c: _A.tenue, w: FontWeight.w800)),
              ),
              Expanded(
                child: Text(
                  grupo.jugadores[orden[k]] == uid ? 'TÚ' : grupo.nombre(orden[k]),
                  overflow: TextOverflow.ellipsis,
                  style: _t(12.5,
                      w: grupo.jugadores[orden[k]] == uid ? FontWeight.w900 : FontWeight.w500,
                      c: grupo.jugadores[orden[k]] == uid ? _A.texto : _A.tenue),
                ),
              ),
              Text('${grupo.resultados[grupo.jugadores[orden[k]]] ?? 0} PC',
                  style: _t(12.5,
                      w: FontWeight.w900,
                      c: grupo.jugadores[orden[k]] == uid ? _A.verde : _A.texto)),
            ]),
          ),
      ]),
    );
  }
}

class _TarjetaInscripcion extends StatelessWidget {
  final TorneoVigente v;
  final bool enviando;
  final VoidCallback onTap;
  const _TarjetaInscripcion({required this.v, required this.enviando, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = v.torneo!;
    String titulo, sub, boton;
    bool activo;
    if (v.inscripcionPendiente) {
      titulo = 'Inscripción próximamente';
      sub = 'Abre el ${fechaTorneo(t.inicioInscripcion)}';
      boton = 'AÚN NO DISPONIBLE';
      activo = false;
    } else if (v.inscripcionAbierta) {
      titulo = v.inscrito ? '¡Estás dentro!' : 'Inscripción abierta';
      sub = 'Hasta el ${fechaTorneo(t.finInscripcion)}';
      boton = v.inscrito ? 'ANULAR INSCRIPCIÓN' : 'APUNTARME';
      activo = true;
    } else {
      titulo = v.inscrito ? 'Inscrito · esperando sorteo' : 'Inscripción cerrada';
      sub = 'El torneo empieza el ${fechaTorneo(t.inicioTorneo)}';
      boton = v.inscrito ? 'ESPERANDO SORTEO' : 'INSCRIPCIÓN CERRADA';
      activo = false;
    }
    final principal = activo && !v.inscrito;

    return _Cristal(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: v.inscrito
                  ? const LinearGradient(colors: [_A.verde, Color(0xFF1FB57A)])
                  : _A.degradado,
            ),
            child: Icon(v.inscrito ? Icons.verified : Icons.how_to_reg, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: _t(16, w: FontWeight.w800)),
              Text(sub, style: _t(12, c: _A.tenue, w: FontWeight.w400)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.groups_2_outlined, size: 16, color: _A.tenue),
          const SizedBox(width: 6),
          Text('${v.inscritos} inscritos', style: _t(12, c: _A.tenue)),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: activo && !enviando ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: principal ? _A.degradado : null,
              color: principal ? null : Colors.white.withOpacity(0.05),
              border: Border.all(color: principal ? Colors.transparent : _A.linea),
              boxShadow: principal
                  ? [
                      BoxShadow(
                          color: _A.neon.withOpacity(0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6))
                    ]
                  : null,
            ),
            child: enviando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(boton,
                    style: _t(13,
                        w: FontWeight.w900,
                        ls: 1.5,
                        c: activo ? (principal ? Colors.white : _A.neon) : _A.tenue)),
          ),
        ),
      ]),
    );
  }
}

// ── RANKING ──────────────────────────────────────────────────────────────────

class _TabRanking extends StatelessWidget {
  final TorneoModel t;
  final ClasificacionTorneo clasif;
  final String? uid;
  final ValueChanged<int> onRonda;
  final Future<void> Function() onRefrescar;

  const _TabRanking({
    required this.t,
    required this.clasif,
    required this.uid,
    required this.onRonda,
    required this.onRefrescar,
  });

  @override
  Widget build(BuildContext context) {
    final hijos = <Widget>[];
    final rondasConDatos = t.rondaActual.clamp(0, t.rondas.length);

    if (rondasConDatos == 0) {
      hijos.add(const _Vacio(
        icono: Icons.leaderboard_outlined,
        titulo: 'Aún no hay clasificación',
        texto: 'La clasificación aparece cuando empiecen a terminar las partidas.',
      ));
    } else {
      // Selector de ronda
      hijos.add(SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var r = 1; r <= rondasConDatos; r++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onRonda(r),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: clasif.ronda == r ? _A.degradado : null,
                    color: clasif.ronda == r ? null : _A.cristal,
                    border: Border.all(color: clasif.ronda == r ? Colors.transparent : _A.linea),
                  ),
                  child: Text(r == t.rondas.length ? 'FINAL' : 'RONDA $r',
                      style: _t(11, w: FontWeight.w800, ls: 1,
                          c: clasif.ronda == r ? Colors.white : _A.tenue)),
                ),
              ),
            ),
        ]),
      ));
      hijos.add(const SizedBox(height: 12));
      hijos.add(Row(children: [
        _Pill(
          texto: clasif.cerrada ? 'DEFINITIVA' : 'PROVISIONAL',
          color: clasif.cerrada ? _A.verde : _A.oro,
          icono: clasif.cerrada ? Icons.lock : Icons.timelapse,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            clasif.esFinal
                ? 'Clasificación final del torneo'
                : 'Pasan los ${clasif.clasifican} primeros',
            style: _t(11.5, c: _A.tenue, w: FontWeight.w500),
          ),
        ),
      ]));
      hijos.add(const SizedBox(height: 12));

      if (clasif.filas.isEmpty) {
        hijos.add(const _Vacio(
          icono: Icons.hourglass_empty,
          titulo: 'Sin resultados todavía',
          texto: 'En cuanto termine la primera partida verás aquí la tabla.',
        ));
      }
      for (var i = 0; i < clasif.filas.length; i++) {
        final f = clasif.filas[i];
        // Línea de corte entre el último que pasa y el primero que no.
        if (!clasif.esFinal && clasif.clasifican > 0 && i == clasif.clasifican) {
          hijos.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Container(height: 1, color: _A.neon.withOpacity(0.6))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('ZONA DE ELIMINACIÓN',
                    style: _t(9, c: _A.neon, ls: 2, w: FontWeight.w800)),
              ),
              Expanded(child: Container(height: 1, color: _A.neon.withOpacity(0.6))),
            ]),
          ));
        }
        hijos.add(_FilaRanking(
          fila: f,
          yo: f.uid == uid,
          pasa: !clasif.esFinal && i < clasif.clasifican,
          esFinal: clasif.esFinal,
        ));
      }
    }

    return RefreshIndicator(
      color: _A.neon,
      backgroundColor: _A.fondo2,
      onRefresh: onRefrescar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: hijos,
      ),
    );
  }
}

class _FilaRanking extends StatelessWidget {
  final FilaClasificacion fila;
  final bool yo;
  final bool pasa;
  final bool esFinal;
  const _FilaRanking({required this.fila, required this.yo, required this.pasa, required this.esFinal});

  Color get _medalla => switch (fila.puesto) {
        1 => _A.oro,
        2 => _A.plata,
        3 => _A.bronce,
        _ => _A.tenue,
      };

  @override
  Widget build(BuildContext context) {
    final podio = fila.puesto <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: yo ? _A.neon.withOpacity(0.14) : _A.cristal,
        border: Border.all(color: yo ? _A.neon.withOpacity(0.6) : _A.linea),
      ),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: podio ? _medalla.withOpacity(0.18) : Colors.transparent,
            border: Border.all(color: podio ? _medalla : _A.linea),
          ),
          child: Text('${fila.puesto}', style: _t(12, w: FontWeight.w900, c: podio ? _medalla : _A.tenue)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(yo ? '${fila.nombre} (TÚ)' : fila.nombre,
                overflow: TextOverflow.ellipsis,
                style: _t(13.5, w: yo ? FontWeight.w900 : FontWeight.w600)),
            Text('${fila.jugadas}/${fila.total} partidas',
                style: _t(10.5, c: _A.tenue, w: FontWeight.w500)),
          ]),
        ),
        if (pasa) const Icon(Icons.north_east, size: 16, color: _A.verde),
        if (esFinal && fila.puesto == 1) const Icon(Icons.emoji_events, size: 18, color: _A.oro),
        const SizedBox(width: 8),
        Text('${fila.pc}', style: _t(18, w: FontWeight.w900)),
        const SizedBox(width: 3),
        Text('PC', style: _t(10, c: _A.tenue, w: FontWeight.w800)),
      ]),
    );
  }
}

// ── TORNEO (formato) ─────────────────────────────────────────────────────────

class _TabTorneo extends StatelessWidget {
  final TorneoModel t;
  final int inscritos;
  final Future<void> Function() onRefrescar;
  const _TabTorneo({required this.t, required this.inscritos, required this.onRefrescar});

  @override
  Widget build(BuildContext context) {
    final totalPartidas = t.rondas.fold<int>(0, (a, r) => a + r.partidas.length);
    return RefreshIndicator(
      color: _A.neon,
      backgroundColor: _A.fondo2,
      onRefresh: onRefrescar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [
            Expanded(child: _Dato(valor: '$inscritos', etiqueta: 'JUGADORES')),
            const SizedBox(width: 10),
            Expanded(child: _Dato(valor: '${t.rondas.length}', etiqueta: 'RONDAS')),
            const SizedBox(width: 10),
            Expanded(child: _Dato(valor: '$totalPartidas', etiqueta: 'PARTIDAS')),
          ]),
          const SizedBox(height: 16),
          _Cristal(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _FilaFecha(Icons.how_to_reg, 'Abre inscripción', t.inicioInscripcion),
              _FilaFecha(Icons.lock_clock, 'Cierra inscripción', t.finInscripcion),
              _FilaFecha(Icons.flag, 'Comienza el torneo', t.inicioTorneo),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  const Icon(Icons.timer_outlined, size: 16, color: _A.tenue),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Turnos', style: _t(13, c: _A.tenue, w: FontWeight.w500))),
                  Text(t.modoTurnoNombre, style: _t(13, w: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('FORMATO', style: _t(11, c: _A.tenue, ls: 3, w: FontWeight.w800)),
          const SizedBox(height: 10),
          for (var i = 0; i < t.rondas.length; i++)
            _RondaFormato(
              ronda: t.rondas[i],
              esFinal: i == t.rondas.length - 1,
              actual: t.rondaActual == i + 1 && t.estado != 'finalizado',
            ),
        ],
      ),
    );
  }
}

class _RondaFormato extends StatelessWidget {
  final RondaTorneo ronda;
  final bool esFinal;
  final bool actual;
  const _RondaFormato({required this.ronda, required this.esFinal, required this.actual});

  @override
  Widget build(BuildContext context) {
    final c = actual ? _A.neon : (esFinal ? _A.oro : _A.cian);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Raíl vertical
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c,
                boxShadow: [BoxShadow(color: c.withOpacity(0.6), blurRadius: 10)],
              ),
            ),
            if (!esFinal) Expanded(child: Container(width: 2, color: _A.linea)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Cristal(
              borde: actual ? _A.neon.withOpacity(0.6) : null,
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(esFinal ? 'GRAN FINAL' : 'RONDA ${ronda.numero}',
                      style: _t(15, w: FontWeight.w900, c: c)),
                  const Spacer(),
                  if (actual) const _Pill(texto: 'AHORA', color: _A.neon),
                ]),
                const SizedBox(height: 10),
                for (final p in ronda.partidas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Icon(
                          p.esDuelo
                              ? Icons.sports_kabaddi
                              : (p.modo == ModoPartida.normal
                                  ? Icons.grid_view_rounded
                                  : Icons.local_fire_department),
                          size: 16,
                          color: _A.tenue),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.resumen, style: _t(13, w: FontWeight.w500))),
                    ]),
                  ),
                const SizedBox(height: 4),
                Text(
                  esFinal ? '🏆 Gana quien más PC sume' : '↗ Pasan los ${ronda.clasifican} con más PC',
                  style: _t(11.5, c: _A.tenue, w: FontWeight.w600),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── PREMIOS ──────────────────────────────────────────────────────────────────

class _TabPremios extends StatelessWidget {
  final List<PremioTorneo> premios;
  final Future<void> Function() onRefrescar;
  const _TabPremios({required this.premios, required this.onRefrescar});

  PremioTorneo? _de(int puesto) {
    for (final p in premios) {
      if (puesto >= p.desde && puesto <= p.hasta) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hijos = <Widget>[];
    if (premios.isEmpty) {
      hijos.add(const _Vacio(
          icono: Icons.emoji_events_outlined,
          titulo: 'Sin premios anunciados',
          texto: 'La organización aún no ha publicado los premios.'));
    } else {
      final p1 = _de(1), p2 = _de(2), p3 = _de(3);
      final hayExternos = premios.any((p) => p.tieneExterno);
      if (p1 != null || p2 != null || p3 != null) {
        hijos.add(SizedBox(
          height: 200,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _Podio(puesto: 2, premio: p2, alto: 110, color: _A.plata)),
            const SizedBox(width: 8),
            Expanded(child: _Podio(puesto: 1, premio: p1, alto: 150, color: _A.oro)),
            const SizedBox(width: 8),
            Expanded(child: _Podio(puesto: 3, premio: p3, alto: 85, color: _A.bronce)),
          ]),
        ));
        hijos.add(const SizedBox(height: 16));
      }
      for (final p in premios) {
        hijos.add(_TarjetaPremio(premio: p));
        hijos.add(const SizedBox(height: 10));
      }
      hijos.add(const SizedBox(height: 6));
      hijos.add(Text(
        'Los premios del juego llegan automáticamente al terminar el torneo.'
        '${hayExternos ? ' Los premios 🎁 los entrega la organización.' : ''}',
        style: _t(11.5, c: _A.tenue, w: FontWeight.w400, h: 1.4),
      ));
    }

    return RefreshIndicator(
      color: _A.neon,
      backgroundColor: _A.fondo2,
      onRefresh: onRefrescar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: hijos,
      ),
    );
  }
}

class _Podio extends StatelessWidget {
  final int puesto;
  final PremioTorneo? premio;
  final double alto;
  final Color color;
  const _Podio({
    required this.puesto,
    required this.premio,
    required this.alto,
    required this.color,
  });

  String get _resumen {
    final p = premio;
    if (p == null) return '—';
    if (p.tieneExterno) return '🎁 ${p.externo}';
    if (p.xp > 0) return '${p.xp} XP';
    if (p.dinero > 0) return '${p.dinero} dinero';
    if (p.tieneCarta) return 'Carta';
    if (p.zero > 0) return '${p.zero} Zero';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Icon(Icons.emoji_events,
          color: color,
          size: puesto == 1 ? 34 : 26,
          shadows: [Shadow(color: color.withOpacity(0.8), blurRadius: 16)]),
      const SizedBox(height: 4),
      Text(_resumen,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: _t(11, w: FontWeight.w800)),
      const SizedBox(height: 6),
      Container(
        height: alto,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.55), color.withOpacity(0.08)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(top: BorderSide(color: color, width: 2)),
        ),
        child: Text('$puesto', style: _t(30, w: FontWeight.w900)),
      ),
    ]);
  }
}

class _TarjetaPremio extends StatelessWidget {
  final PremioTorneo premio;
  const _TarjetaPremio({required this.premio});

  Color get _color => switch (premio.desde) {
        1 => _A.oro,
        2 => _A.plata,
        3 => _A.bronce,
        _ => _A.cian,
      };

  @override
  Widget build(BuildContext context) {
    final p = premio;
    final carta = p.cartaNombre.isNotEmpty ? p.cartaNombre : 'Carta';
    return _Cristal(
      borde: _color.withOpacity(0.35),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: _color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Icon(Icons.emoji_events, color: _color, size: 20),
            Text(p.puestos,
                textAlign: TextAlign.center,
                style: _t(11, w: FontWeight.w900, c: _color)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if (p.xp > 0)
              _Recompensa(icono: Icons.auto_graph, texto: '${p.xp} XP', color: _A.cian),
            if (p.dinero > 0)
              _Recompensa(icono: Icons.paid_outlined, texto: '${p.dinero}', color: _A.oro),
            if (p.zero > 0)
              _Recompensa(
                  icono: Icons.diamond_outlined,
                  texto: '${p.zero} Zero ${p.zeroTipo.colorNombre}',
                  color: const Color(0xFFB98CFF)),
            if (p.tieneCarta)
              _Recompensa(
                  icono: Icons.style,
                  texto: p.cartaCantidad > 1 ? '${p.cartaCantidad}× $carta' : carta,
                  color: _A.neon),
            if (p.tieneExterno)
              _Recompensa(icono: Icons.card_giftcard, texto: p.externo, color: _A.verde),
          ]),
        ),
      ]),
    );
  }
}

class _Recompensa extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  const _Recompensa({required this.icono, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(texto, style: _t(12, w: FontWeight.w700))),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// PIEZAS COMUNES ARENA
// ═══════════════════════════════════════════════════════════════════════════

class _Cristal extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borde;
  const _Cristal({required this.child, this.padding = EdgeInsets.zero, this.borde});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _A.cristal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borde ?? _A.linea),
        ),
        child: child,
      );
}

class _Pill extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData? icono;
  const _Pill({required this.texto, required this.color, this.icono});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(texto, style: _t(10, c: color, w: FontWeight.w800, ls: 1)),
        ]),
      );
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  const _Etiqueta({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(texto, style: _t(11, c: color, w: FontWeight.w700)),
      );
}

class _Dato extends StatelessWidget {
  final String valor;
  final String etiqueta;
  const _Dato({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) => _Cristal(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Text(valor, style: _t(24, w: FontWeight.w900)),
          Text(etiqueta, style: _t(9, c: _A.tenue, ls: 2, w: FontWeight.w700)),
        ]),
      );
}

class _FilaFecha extends StatelessWidget {
  final IconData icono;
  final String texto;
  final DateTime? fecha;
  const _FilaFecha(this.icono, this.texto, this.fecha);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icono, size: 16, color: _A.tenue),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: _t(13, c: _A.tenue, w: FontWeight.w500))),
          Text(fechaTorneo(fecha), style: _t(13, w: FontWeight.w700)),
        ]),
      );
}

class _Vacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  const _Vacio({required this.icono, required this.titulo, required this.texto});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _A.cristal,
              border: Border.all(color: _A.linea),
            ),
            child: Icon(icono, color: _A.tenue, size: 28),
          ),
          const SizedBox(height: 14),
          Text(titulo, textAlign: TextAlign.center, style: _t(16, w: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(texto,
              textAlign: TextAlign.center,
              style: _t(12.5, c: _A.tenue, w: FontWeight.w400, h: 1.45)),
        ]),
      );
}

class _SinTorneo extends StatelessWidget {
  final bool cargando;
  const _SinTorneo({required this.cargando});

  @override
  Widget build(BuildContext context) => Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _A.texto),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        Expanded(
          child: Center(
            child: cargando
                ? const CircularProgressIndicator(color: _A.neon)
                : const _Vacio(
                    icono: Icons.emoji_events_outlined,
                    titulo: 'No hay torneos',
                    texto: 'Cuando se anuncie un torneo lo verás aquí.'),
          ),
        ),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════
// LISTA DE GRUPOS (la usa la edición de torneos, con el tema del juego)
// ═══════════════════════════════════════════════════════════════════════════

/// Grupos agrupados por partida de la ronda. Con [soloUid] muestra solo los
/// grupos donde está ese jugador.
class GruposTorneoLista extends StatelessWidget {
  final List<GrupoTorneo> grupos;
  final RondaTorneo? ronda;
  final String? soloUid;

  const GruposTorneoLista({super.key, required this.grupos, this.ronda, this.soloUid});

  static const Color _acento = Color(0xFFE04444);

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final visibles = soloUid == null
        ? grupos
        : grupos.where((g) => g.jugadores.contains(soloUid)).toList();

    if (visibles.isEmpty) {
      return Text(
          soloUid == null ? 'Sin grupos.' : 'No estás en ningún grupo de esta ronda.',
          style: TextStyle(fontSize: 12, color: war.textoTenue));
    }

    final porPartida = <int, List<GrupoTorneo>>{};
    for (final g in visibles) {
      porPartida.putIfAbsent(g.partida, () => []).add(g);
    }
    final claves = porPartida.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in claves) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'PARTIDA $k · ${_titulo(porPartida[k]!.first, k)}',
              style: const TextStyle(
                  fontFamily: 'Cinzel', fontSize: 11, letterSpacing: 1, color: _acento),
            ),
          ),
          for (final g in porPartida[k]!)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: war.superficie,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: war.borde),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      g.descansa
                          ? 'DESCANSA (recibe la media de PC)'
                          : 'Grupo ${g.grupo} · ${g.jugadores.length} jugadores',
                      style: TextStyle(fontSize: 11, color: war.textoTenue),
                    ),
                  ),
                  if (!g.descansa)
                    Text(_estadoTexto(g),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: g.terminada
                                ? const Color(0xFF4ABB58)
                                : g.estado == 'jugando'
                                    ? const Color(0xFFE0A030)
                                    : war.textoTenue)),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (var i = 0; i < g.jugadores.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: g.jugadores[i] == soloUid ? _acento.withOpacity(0.18) : null,
                        border: Border.all(color: war.borde),
                      ),
                      child: Text(
                          g.terminada
                              ? '${g.nombre(i)} · ${g.resultados[g.jugadores[i]] ?? 0} PC'
                              : g.nombre(i),
                          style: TextStyle(fontSize: 11, color: war.texto)),
                    ),
                ]),
              ]),
            ),
        ],
      ],
    );
  }

  String _estadoTexto(GrupoTorneo g) {
    switch (g.estado) {
      case 'jugando':
        return 'EN JUEGO';
      case 'terminada':
        return 'TERMINADA';
      default:
        return g.tieneSala ? 'SALA ABIERTA' : 'SIN SALA';
    }
  }

    String _titulo(GrupoTorneo g, int partida) {
    if (g.tipo == TipoPartidaTorneo.duelo) return 'DUELO';
    final r = ronda;
    if (r != null && partida - 1 < r.partidas.length) {
      return r.partidas[partida - 1].resumen.toUpperCase();
    }
    final m = g.modo == ModoPartida.normal ? '' : ' · ${g.modo.etiqueta}';
    return 'DE ${g.capacidad}$m';
  }
}
