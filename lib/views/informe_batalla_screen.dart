// lib/views/informe_batalla_screen.dart

import 'package:flutter/material.dart';
import '../models/lobby_model.dart';
import '../models/carta_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA INFORME DE BATALLA
// Pestañas: COMBATES · ENERGIES · MOVIMIENTOS · CARTA
// ─────────────────────────────────────────────────────────────────────────────

class InformeBatallaScreen extends StatefulWidget {
  final List<Map<String, dynamic>> combateLog;
  final List<Map<String, dynamic>> movimientosLog;
  final List<Map<String, dynamic>> farmeoLog;
  final List<Map<String, dynamic>> accionesLog;
  final String? rayoCoord;
  final List<Map<String, dynamic>> historial;
  final String localUid;
  final List<LobbyJugador> jugadores;
  final int turno;

  /// Carta nueva recibida este turno (null si aún no se ha repartido).
  final CartaModel? ultimaCartaRepartida;

  const InformeBatallaScreen({
    super.key,
    required this.combateLog,
    required this.movimientosLog,
    required this.historial,
    required this.localUid,
    required this.jugadores,
    required this.turno,
    this.farmeoLog = const [],
    this.accionesLog = const [],
    this.rayoCoord,
    this.ultimaCartaRepartida,
  });

  @override
  State<InformeBatallaScreen> createState() => _InformeBatallaScreenState();
}

class _InformeBatallaScreenState extends State<InformeBatallaScreen> {
  late int _selectedTurno;
  late List<Map<String, dynamic>> _combateActual;
  late List<Map<String, dynamic>> _movActual;
  late List<Map<String, dynamic>> _farmeoActual;
  late List<Map<String, dynamic>> _accionesActual;
  String? _rayoActual;

  @override
  void initState() {
    super.initState();
    _selectedTurno = widget.turno;
    _combateActual = widget.combateLog;
    _movActual = widget.movimientosLog;
    _farmeoActual = widget.farmeoLog;
    _accionesActual = widget.accionesLog;
    _rayoActual = widget.rayoCoord;
  }

  void _selectTurno(
    int turno,
    List<Map<String, dynamic>> combate,
    List<Map<String, dynamic>> mov,
    List<Map<String, dynamic>> farmeo,
    List<Map<String, dynamic>> acciones,
    String? rayoCoord,
  ) {
    setState(() {
      _selectedTurno = turno;
      _combateActual = combate;
      _movActual = mov;
      _farmeoActual = farmeo;
      _accionesActual = acciones;
      _rayoActual = rayoCoord;
    });
  }

  String _alias(String uid) {
    try {
      return widget.jugadores.firstWhere((j) => j.uid == uid).alias;
    } catch (_) {
      return uid.length > 6 ? uid.substring(0, 6) : uid;
    }
  }

  Color _colorZona(String? zone) {
    switch (zone) {
      case 'north':
        return const Color(0xFFC04040);
      case 'south':
        return const Color(0xFF4ABB58);
      case 'west':
        return const Color(0xFF4060D0);
      case 'east':
        return const Color(0xFFC0A820);
      default:
        return const Color(0xFF888888);
    }
  }

  List<
      ({
        int turno,
        List<Map<String, dynamic>> combate,
        List<Map<String, dynamic>> mov,
        List<Map<String, dynamic>> farmeo,
        List<Map<String, dynamic>> acciones,
        String? rayoCoord,
      })> get _opciones {
    final result = <({
      int turno,
      List<Map<String, dynamic>> combate,
      List<Map<String, dynamic>> mov,
      List<Map<String, dynamic>> farmeo,
      List<Map<String, dynamic>> acciones,
      String? rayoCoord,
    })>[];

    for (final entry in widget.historial) {
      final t = (entry['turno'] as num?)?.toInt() ?? 0;
      final c = (entry['combateLog'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final m = (entry['movimientosLog'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final f = (entry['farmeoLog'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final ac = (entry['accionesLog'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final r = entry['rayoCoord'] as String?;
      if (!result.any((o) => o.turno == t)) {
        result.add((
          turno: t,
          combate: c,
          mov: m,
          farmeo: f,
          acciones: ac,
          rayoCoord: r
        ));
      }
    }

    if (!result.any((o) => o.turno == widget.turno)) {
      result.add((
        turno: widget.turno,
        combate: widget.combateLog,
        mov: widget.movimientosLog,
        farmeo: widget.farmeoLog,
        acciones: widget.accionesLog,
        rayoCoord: widget.rayoCoord,
      ));
    }

    result.sort((a, b) => b.turno.compareTo(a.turno));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final opciones = _opciones;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF060E1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF060E1A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFC8A860), size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('INFORME DE BATALLA',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      letterSpacing: 2,
                      color: Color(0xFFC8A860))),
              Text('TURNO $_selectedTurno',
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 8,
                      letterSpacing: 1.5,
                      color: Color(0xFF506070))),
            ],
          ),
          actions: [
            if (opciones.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DropdownButton<int>(
                  value: _selectedTurno,
                  dropdownColor: const Color(0xFF0A1525),
                  underline: const SizedBox(),
                  icon: const Icon(Icons.history,
                      color: Color(0xFFC8A860), size: 16),
                  items: opciones
                      .map((o) => DropdownMenuItem(
                            value: o.turno,
                            child: Text('T${o.turno}',
                                style: const TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 10,
                                    color: Color(0xFFC8A860))),
                          ))
                      .toList(),
                  onChanged: (t) {
                    if (t == null) return;
                    final o = opciones.firstWhere((o) => o.turno == t);
                    _selectTurno(
                        t, o.combate, o.mov, o.farmeo, o.acciones, o.rayoCoord);
                  },
                ),
              ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFFC8A860),
            indicatorWeight: 1.5,
            labelColor: Color(0xFFC8A860),
            unselectedLabelColor: Color(0xFF506070),
            labelStyle: TextStyle(
                fontFamily: 'Cinzel', fontSize: 9, letterSpacing: 1.5),
            tabs: [
              Tab(text: 'COMBATES'),
              Tab(text: 'ENERGIES'),
              Tab(text: 'CARTA'),
              Tab(text: 'MOVIMIENTOS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CombatesTab(
              combateLog: _combateActual,
              accionesLog: _accionesActual,
              localUid: widget.localUid,
              alias: _alias,
              colorZona: _colorZona,
            ),
            _EnergiesTab(
              farmeoLog: _farmeoActual,
              rayoCoord: _rayoActual,
              localUid: widget.localUid,
              alias: _alias,
              colorZona: _colorZona,
            ),
            _CartaTab(carta: widget.ultimaCartaRepartida),
            _MovimientosTab(
              movimientosLog: _movActual,
              localUid: widget.localUid,
              alias: _alias,
              colorZona: _colorZona,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB CARTA NUEVA
// ─────────────────────────────────────────────────────────────────────────────

class _CartaTab extends StatelessWidget {
  final CartaModel? carta;
  const _CartaTab({required this.carta});

  @override
  Widget build(BuildContext context) {
    if (carta == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_outlined, size: 40, color: Color(0xFF2A3A4A)),
              SizedBox(height: 16),
              Text('Sin carta nueva este turno.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      color: Color(0xFF506070))),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1525),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFC8A860).withOpacity(0.3), width: 1),
            ),
            child: const Column(
              children: [
                Text('✨ NUEVA CARTA RECIBIDA',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        letterSpacing: 2,
                        color: Color(0xFFC8A860))),
                SizedBox(height: 2),
                Text('Añadida a tu mano al inicio del turno',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        color: Color(0xFF506070))),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Imagen de la carta ───────────────────────────────
          Container(
            width: 140,
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFF0C1A2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFE0C060).withOpacity(0.6), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE0C060).withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: carta!.imagen.isNotEmpty
                  ? Image.network(
                      carta!.imagen,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _CartaPlaceholder(),
                    )
                  : const _CartaPlaceholder(),
            ),
          ),

          const SizedBox(height: 20),

          // ── Nombre ──────────────────────────────────────────
          Text(
            carta!.nombre.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 14,
              letterSpacing: 2,
              color: Color(0xFFC8A860),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          // ── Tipo + Ejército ──────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(carta!.tipoIcon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(carta!.tipoLabel.toUpperCase(),
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      color: Color(0xFF8A9AAA),
                      letterSpacing: 1.5)),
              const SizedBox(width: 12),
              const Text('·', style: TextStyle(color: Color(0xFF506070))),
              const SizedBox(width: 12),
              Text('EJÉRCITO ${carta!.ejercito}',
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      color: Color(0xFF8A9AAA),
                      letterSpacing: 1.5)),
            ],
          ),

          const SizedBox(height: 20),

          // ── Stats grid ──────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatCard(
                  icon: '⚔',
                  label: 'FUERZA',
                  value: carta!.fuerza,
                  color: const Color(0xFFE08040)),
              const SizedBox(width: 10),
              _StatCard(
                  icon: '🛡',
                  label: 'DEFENSA',
                  value: carta!.defensa,
                  color: const Color(0xFF4090D0)),
              const SizedBox(width: 10),
              _StatCard(
                  icon: '⚡',
                  label: 'COSTE',
                  value: carta!.coste,
                  color: const Color(0xFFD4A800)),
              const SizedBox(width: 10),
              _StatCard(
                  icon: '↗',
                  label: 'MOV',
                  value: carta!.movimiento,
                  color: const Color(0xFF4ABB58)),
            ],
          ),

          const SizedBox(height: 20),

          // ── Descripción ──────────────────────────────────────
          if (carta!.descripcion.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF080F1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1A2A3A), width: 1),
              ),
              child: Text(
                carta!.descripcion,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    color: Color(0xFF6A7A8A),
                    height: 1.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String label;
  final int value;
  final Color color;

  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text('$value',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 6,
                  color: Color(0xFF506070),
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _CartaPlaceholder extends StatelessWidget {
  const _CartaPlaceholder();
  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(Icons.shield_outlined, size: 60, color: Color(0xFFB08040)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB COMBATES
// ─────────────────────────────────────────────────────────────────────────────

class _CombatesTab extends StatelessWidget {
  final List<Map<String, dynamic>> combateLog;
  final List<Map<String, dynamic>> accionesLog;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _CombatesTab(
      {required this.combateLog,
      required this.accionesLog,
      required this.localUid,
      required this.alias,
      required this.colorZona});

  bool _meImplica(Map<String, dynamic> c) {
    final g = c['ganadorUid'] as String?;
    final d = List<String>.from(c['derrotadosUid'] as List? ?? []);
    return g == localUid || d.contains(localUid);
  }

  /// Disparos que impactaron sobre alguna carta (destruyeron algo). La carta
  /// enemiga desaparece del tablero (correcto), pero el impacto debe verse aquí.
  List<Map<String, dynamic>> get _disparosConImpacto {
    return accionesLog
        .where((a) {
          if (a['tipo'] != 'disparo') return false;
          final destruidas = a['cartasDestruidas'] as List? ?? [];
          return destruidas.isNotEmpty;
        })
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final disparos = _disparosConImpacto;

    if (combateLog.isEmpty && disparos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 40, color: Color(0xFF2A3A4A)),
              SizedBox(height: 16),
              Text('Sin combates este turno.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      color: Color(0xFF506070))),
              SizedBox(height: 8),
              Text(
                  'Las cartas de distintos jugadores\nno coincidieron en ninguna celda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      color: Color(0xFF3A4A5A),
                      height: 1.6)),
            ],
          ),
        ),
      );
    }
    final locales = combateLog.where(_meImplica).toList();
    final otros = combateLog.where((c) => !_meImplica(c)).toList();
    final total = locales.length + otros.length + disparos.length;
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: total,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        // Primero combates (locales y luego ajenos), después los disparos.
        if (i < locales.length + otros.length) {
          final data =
              i < locales.length ? locales[i] : otros[i - locales.length];
          return _CombateTile(
            data: data,
            localUid: localUid,
            alias: alias,
            colorZona: colorZona,
            esLocal: i < locales.length,
          );
        }
        final d = disparos[i - locales.length - otros.length];
        return _DisparoTile(
          data: d,
          localUid: localUid,
          alias: alias,
          colorZona: colorZona,
        );
      },
    );
  }
}

/// Ficha para un disparo que impactó: quién disparó, celda objetivo y cartas
/// enemigas destruidas por el impacto.
class _DisparoTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _DisparoTile(
      {required this.data,
      required this.localUid,
      required this.alias,
      required this.colorZona});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF40C0FF);
    final uid = data['uid'] as String? ?? '';
    final zona = data['zona'] as String?;
    final objetivo = data['objetivo'] as String? ?? '?';
    final habilidad = data['habilidadNombre'] as String? ?? 'Disparo';
    final esLocal = uid == localUid;
    final destruidas = (data['cartasDestruidas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final zonaColor = colorZona(zona);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text('CELDA $objetivo',
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: accent)),
                const Spacer(),
                _Badge(label: habilidad.toUpperCase(), color: accent),
              ],
            ),
          ),
          // ── Cuerpo ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: zonaColor)),
                    const SizedBox(width: 8),
                    Text(
                      esLocal
                          ? 'TÚ disparaste'
                          : '${alias(uid).toUpperCase()} disparó',
                      style: TextStyle(
                          fontFamily: 'Cinzel', fontSize: 9, color: zonaColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('CARTAS DESTRUIDAS',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        letterSpacing: 1,
                        color: Color(0xFF506070))),
                const SizedBox(height: 4),
                ...destruidas.map((c) {
                  final nombre =
                      (c['Nombre'] ?? c['nombre'] ?? 'Carta').toString();
                  final ownerUid = (c['ownerUid'] ?? '').toString();
                  final owner = ownerUid == localUid
                      ? '(tuya)'
                      : ownerUid.isNotEmpty
                          ? '(${alias(ownerUid)})'
                          : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        const Text('✖',
                            style: TextStyle(
                                fontSize: 9, color: Color(0xFFC04040))),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('$nombre $owner',
                              style: const TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 9,
                                  color: Color(0xFF8A9AAA)),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CombateTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;
  final bool esLocal;

  const _CombateTile(
      {required this.data,
      required this.localUid,
      required this.alias,
      required this.colorZona,
      required this.esLocal});

  @override
  Widget build(BuildContext context) {
    final coord = data['coord'] as String? ?? '?';
    final ganadorUid = data['ganadorUid'] as String?;
    final ganadorZone = data['ganadorZone'] as String?;
    final derrotados = List<String>.from(data['derrotadosUid'] as List? ?? []);
    final energies =
        Map<String, dynamic>.from(data['energiesGanadas'] as Map? ?? {});
    final pc = Map<String, dynamic>.from(data['pcGanados'] as Map? ?? {});
    final detalle = (data['detalle'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final esEmpate = ganadorUid == null;
    final accentColor = esEmpate
        ? const Color(0xFF888888)
        : (esLocal && ganadorUid == localUid)
            ? const Color(0xFF4ABB58)
            : esLocal
                ? const Color(0xFFC04040)
                : const Color(0xFFC8A860);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withOpacity(0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(children: [
              Text('⚔  CELDA $coord',
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      letterSpacing: 1.5,
                      color: Color(0xFFC8A860))),
              const Spacer(),
              if (esLocal) _Badge(label: 'TU COMBATE', color: accentColor),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esEmpate)
                  const Text(
                      '🤝  EMPATE — las cartas se mantienen hasta el desempate',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          color: Color(0xFF888888)))
                else ...[
                  Row(children: [
                    Icon(Icons.emoji_events,
                        size: 13, color: colorZona(ganadorZone)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            'VICTORIA: ${alias(ganadorUid!).toUpperCase()}',
                            style: TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: 9,
                                letterSpacing: 1,
                                color: colorZona(ganadorZone)))),
                  ]),
                  if (energies.containsKey(ganadorUid))
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 19),
                      child: Text(
                          '+${energies[ganadorUid]} pts  ·  +${pc[ganadorUid] ?? 0} PC',
                          style: const TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 8,
                              color: Color(0xFF506070))),
                    ),
                  if (derrotados.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Icons.close,
                            size: 12, color: Color(0xFFC04040)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                'DERROTADOS: ${derrotados.map(alias).map((s) => s.toUpperCase()).join(', ')}',
                                style: const TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 9,
                                    color: Color(0xFFC04040)))),
                      ]),
                    ),
                ],
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF1A2A3A), height: 1),
                  const SizedBox(height: 8),
                  ...detalle.map((d) => _GrupoDesglose(
                      data: d, alias: alias, colorZona: colorZona)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrupoDesglose extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _GrupoDesglose(
      {required this.data, required this.alias, required this.colorZona});

  @override
  Widget build(BuildContext context) {
    final uid = data['ownerUid'] as String? ?? '';
    final zone = data['ownerZone'] as String?;
    final fuerza = (data['totalFuerza'] as num?)?.toInt() ?? 0;
    final defensa = (data['totalDefensa'] as num?)?.toInt() ?? 0;
    final poderNeto = (data['poderNeto'] as num?)?.toInt() ?? 0;
    final numCartas = (data['numCartas'] as num?)?.toInt() ?? 0;
    final cartas = (data['cartas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final color = colorZona(zone);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 6),
            Text(alias(uid).toUpperCase(),
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    letterSpacing: 1,
                    color: color)),
            const Spacer(),
            _StatBadge('⚔', fuerza),
            const SizedBox(width: 4),
            _StatBadge('🛡', defensa),
            const SizedBox(width: 4),
            _StatBadge('⚡', poderNeto, highlight: poderNeto > 0),
          ]),
          if (cartas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cartas.map((c) {
                  final nombre =
                      (c['nombre'] ?? c['Nombre'] ?? 'Carta').toString();
                  final f = ((c['fuerza'] ?? c['Fuerza'] ?? 0) as num).toInt();
                  final d =
                      ((c['defensa'] ?? c['Defensa'] ?? 0) as num).toInt();
                  final red = ((c['reduccionVeneno'] ?? 0) as num).toInt();
                  final esc = ((c['bonusEscudo'] ?? 0) as num).toInt();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      Expanded(
                          child: Text(nombre,
                              style: const TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 8,
                                  color: Color(0xFF506070)),
                              overflow: TextOverflow.ellipsis)),
                      _CardStatRow(
                          fuerza: f, defensa: d, reduccion: red, escudo: esc),
                    ]),
                  );
                }).toList(),
              ),
            ),
          Text('$numCartas ${numCartas == 1 ? 'carta' : 'cartas'}',
              style: const TextStyle(
                  fontFamily: 'Cinzel', fontSize: 7, color: Color(0xFF3A4A5A))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB ENERGIES
// ─────────────────────────────────────────────────────────────────────────────

class _EnergiesTab extends StatelessWidget {
  final List<Map<String, dynamic>> farmeoLog;
  final String? rayoCoord;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _EnergiesTab(
      {required this.farmeoLog,
      required this.rayoCoord,
      required this.localUid,
      required this.alias,
      required this.colorZona});

  @override
  Widget build(BuildContext context) {
    final tieneData = farmeoLog.isNotEmpty || rayoCoord != null;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (rayoCoord != null) _RayoBanner(coord: rayoCoord!),
        if (rayoCoord != null) const SizedBox(height: 14),
        _ReglasFarmeoCard(),
        const SizedBox(height: 14),
        if (!tieneData || farmeoLog.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1525),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1A2A3A), width: 1),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_outlined, size: 36, color: Color(0xFF2A3A4A)),
                SizedBox(height: 12),
                Text('Sin farmeo este turno.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        color: Color(0xFF506070))),
              ],
            ),
          )
        else
          ...farmeoLog.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FarmeoTile(
                    data: entry,
                    localUid: localUid,
                    alias: alias,
                    colorZona: colorZona),
              )),
      ],
    );
  }
}

class _RayoBanner extends StatelessWidget {
  final String coord;
  const _RayoBanner({required this.coord});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A0A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFFD4A800).withOpacity(0.5), width: 1),
      ),
      child: Row(children: [
        const Text('⚡', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RAYO ACTIVO',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    letterSpacing: 2,
                    color: Color(0xFFD4A800))),
            Text('Celda  $coord  →  +10 Energies',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF8A8A50))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFD4A800).withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: const Color(0xFFD4A800).withOpacity(0.4), width: 0.5),
          ),
          child: Text(coord,
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4A800))),
        ),
      ]),
    );
  }
}

class _ReglasFarmeoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A2A3A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('REGLAS DE FARMEO',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  letterSpacing: 2,
                  color: Color(0xFF506070))),
          const SizedBox(height: 8),
          _ReglaRow(
              icon: '🏴',
              label: 'Carta en continente enemigo',
              bonus: '+5 / carta'),
          const SizedBox(height: 4),
          _ReglaRow(
              icon: '🏝', label: 'Carta en isla central', bonus: '+7 / carta'),
          const SizedBox(height: 4),
          _ReglaRow(
              icon: '⚡',
              label: 'Carta en posición del rayo',
              bonus: '+10 / carta'),
          const SizedBox(height: 4),
          _ReglaRow(icon: '🍀', label: 'Turno sin ganar energías', bonus: '+3'),
        ],
      ),
    );
  }
}

class _ReglaRow extends StatelessWidget {
  final String icon;
  final String label;
  final String bonus;
  const _ReglaRow(
      {required this.icon, required this.label, required this.bonus});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(icon, style: const TextStyle(fontSize: 11)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  color: Color(0xFF6A7A8A)))),
      Text(bonus,
          style: const TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 8,
              color: Color(0xFFD4A800),
              fontWeight: FontWeight.bold)),
    ]);
  }
}

class _FarmeoTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _FarmeoTile(
      {required this.data,
      required this.localUid,
      required this.alias,
      required this.colorZona});

  @override
  Widget build(BuildContext context) {
    final uid = data['uid'] as String? ?? '';
    final zona = data['zona'] as String?;
    final total = (data['totalEnergies'] as num?)?.toInt() ?? 0;
    final detalle = Map<String, dynamic>.from(data['detalle'] as Map? ?? {});
    final contEnemigo = (detalle['continenteEnemigo'] as num?)?.toInt() ?? 0;
    final isla = (detalle['islaCentral'] as num?)?.toInt() ?? 0;
    final rayo = (detalle['rayo'] as num?)?.toInt() ?? 0;
    final suerte = (detalle['suerteDelPerdedor'] as num?)?.toInt() ?? 0;
    final esLocal = uid == localUid;
    final color = colorZona(zona);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: esLocal
                ? const Color(0xFFD4A800).withOpacity(0.5)
                : color.withOpacity(0.25),
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 8),
              Expanded(
                child: Row(children: [
                  Text(alias(uid).toUpperCase(),
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: color)),
                  if (esLocal) ...[
                    const SizedBox(width: 6),
                    const Text('(TÚ)',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            color: Color(0xFF506070))),
                  ],
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A800).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFFD4A800).withOpacity(0.5),
                      width: 0.5),
                ),
                child: Text('+$total ⚡',
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4A800))),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (contEnemigo > 0)
                  _FarmeoRow(
                      icon: '🏴',
                      label: 'Continente enemigo',
                      value: contEnemigo),
                if (isla > 0)
                  _FarmeoRow(icon: '🏝', label: 'Isla central', value: isla),
                if (rayo > 0)
                  _FarmeoRow(
                      icon: '⚡', label: 'Rayo', value: rayo, highlight: true),
                if (suerte > 0)
                  _FarmeoRow(
                      icon: '🍀',
                      label: 'Suerte del perdedor',
                      value: suerte,
                      highlight: true),
                if (contEnemigo == 0 && isla == 0 && rayo == 0 && suerte == 0)
                  const Text('Sin fuentes de farmeo.',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          color: Color(0xFF506070))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmeoRow extends StatelessWidget {
  final String icon;
  final String label;
  final int value;
  final bool highlight;
  const _FarmeoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    color: Color(0xFF8A9AAA)))),
        Text('+$value',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: highlight
                    ? const Color(0xFFD4A800)
                    : const Color(0xFF4ABB58))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB MOVIMIENTOS
// ─────────────────────────────────────────────────────────────────────────────

class _MovimientosTab extends StatelessWidget {
  final List<Map<String, dynamic>> movimientosLog;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _MovimientosTab(
      {required this.movimientosLog,
      required this.localUid,
      required this.alias,
      required this.colorZona});

  @override
  Widget build(BuildContext context) {
    if (movimientosLog.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 40, color: Color(0xFF2A3A4A)),
              SizedBox(height: 16),
              Text('Sin movimientos registrados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      color: Color(0xFF506070))),
            ],
          ),
        ),
      );
    }
    final locales = movimientosLog.where((m) => m['uid'] == localUid).toList();
    final otros = movimientosLog.where((m) => m['uid'] != localUid).toList();
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: locales.length + otros.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final data =
            i < locales.length ? locales[i] : otros[i - locales.length];
        return _MovimientoTile(
            data: data, localUid: localUid, alias: alias, colorZona: colorZona);
      },
    );
  }
}

class _MovimientoTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String localUid;
  final String Function(String) alias;
  final Color Function(String?) colorZona;

  const _MovimientoTile(
      {required this.data,
      required this.localUid,
      required this.alias,
      required this.colorZona});

  @override
  Widget build(BuildContext context) {
    final uid = data['uid'] as String? ?? '';
    final zone = data['zona'] as String?;
    final celdas = Map<String, dynamic>.from(data['celdas'] as Map? ?? {});
    final esLocal = uid == localUid;
    final color = colorZona(zone);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 8),
              Text(alias(uid).toUpperCase(),
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      letterSpacing: 1.5,
                      color: color)),
              if (esLocal) ...[
                const SizedBox(width: 6),
                const Text('(TÚ)',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        color: Color(0xFF506070))),
              ],
            ]),
          ),
          if (celdas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Sin cartas en el tablero.',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      color: Color(0xFF506070))),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: celdas.entries.map((entry) {
                  final coord = entry.key;
                  final cartas = (entry.value as List<dynamic>)
                      .map((c) => Map<String, dynamic>.from(c as Map))
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1E2E),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                                color: const Color(0xFF1A2A3A), width: 0.5),
                          ),
                          child: Text(coord,
                              style: const TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 8,
                                  color: Color(0xFFC8A860))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: cartas.map((c) {
                              final nombre =
                                  (c['Nombre'] ?? c['nombre'] ?? 'Carta')
                                      .toString();
                              final fuerza =
                                  ((c['Fuerza'] ?? c['fuerza'] ?? 0) as num)
                                      .toInt();
                              final defensa =
                                  ((c['Defensa'] ?? c['defensa'] ?? 0) as num)
                                      .toInt();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(nombre,
                                          style: const TextStyle(
                                              fontFamily: 'Cinzel',
                                              fontSize: 9,
                                              color: Color(0xFF8A9AAA)),
                                          overflow: TextOverflow.ellipsis)),
                                  const SizedBox(width: 8),
                                  _CardStatRow(
                                      fuerza: fuerza, defensa: defensa),
                                ]),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS COMPARTIDOS
// ─────────────────────────────────────────────────────────────────────────────
class _StatBadge extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;
  const _StatBadge(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: highlight ? const Color(0xFF1A3A1A) : const Color(0xFF0D1E2E),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color:
                  highlight ? const Color(0xFF2A6A2A) : const Color(0xFF1A2A3A),
              width: 0.5),
        ),
        child: Text('$label$value',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 8,
                color: highlight
                    ? const Color(0xFF4ABB58)
                    : const Color(0xFF506070))),
      );
}

class _CardStatRow extends StatelessWidget {
  final int fuerza;
  final int defensa;
  final int reduccion;
  final int escudo;
  const _CardStatRow(
      {required this.fuerza,
      required this.defensa,
      this.reduccion = 0,
      this.escudo = 0});

  @override
  Widget build(BuildContext context) {
    final efectivaRaw = defensa - reduccion + escudo;
    final efectiva = efectivaRaw > 0 ? efectivaRaw : 0;
    final modificada = reduccion > 0 || escudo > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('⚔', style: TextStyle(fontSize: 9)),
        const SizedBox(width: 2),
        Text('$fuerza',
            style: const TextStyle(
                fontFamily: 'Cinzel', fontSize: 9, color: Color(0xFFE08040))),
        const SizedBox(width: 8),
        const Text('🛡', style: TextStyle(fontSize: 9)),
        const SizedBox(width: 2),
        if (modificada) ...[
          Text('$efectiva',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 9,
                  color: escudo > 0 && reduccion == 0
                      ? const Color(0xFF9AD0FF)
                      : const Color(0xFF5AD07A))),
          const SizedBox(width: 3),
          if (reduccion > 0)
            Text('☠-$reduccion',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF2BA046))),
          if (escudo > 0)
            Text(' 🛡+$escudo',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    color: Color(0xFF6AB0FF))),
        ] else
          Text('$defensa',
              style: const TextStyle(
                  fontFamily: 'Cinzel', fontSize: 9, color: Color(0xFF4090D0))),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5),
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7,
                color: Color(0xFFC8A860),
                letterSpacing: 1)),
      );
}
