// lib/views/perfil_publico_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/lobby_model.dart' show kEjercitos, EjercitoInfo;
import '../models/jugador_model.dart' show MonedaZeroExt;
import '../services/settings_controller.dart';
import '../services/warzero_api.dart';

/// PERFIL PÚBLICO — vista de SOLO LECTURA del perfil de otro jugador.
///
/// Se abre al pulsar un jugador en el ranking. Muestra datos públicos: avatar,
/// alias, nivel, experiencia, victorias totales y victorias por modo (2/4/6/8).
/// No muestra datos privados (correo, oro, cristales) ni permite editar.
///
/// Los datos básicos (alias, imagen, nivel, XP, victorias) llegan ya desde la
/// fila del ranking, así que se pintan al instante. Las victorias por modo se
/// intentan leer del doc del jugador como EXTRA (best-effort): si las reglas de
/// Firestore no permiten leer el doc de otro jugador, simplemente no se muestran.
class PerfilPublicoScreen extends StatefulWidget {
  final String uid;
  final String alias;
  final String imagen;
  final int nivel;
  final int experiencia;
  final int victorias;

  const PerfilPublicoScreen({
    super.key,
    required this.uid,
    required this.alias,
    required this.imagen,
    required this.nivel,
    required this.experiencia,
    required this.victorias,
  });

  @override
  State<PerfilPublicoScreen> createState() => _PerfilPublicoScreenState();
}

class _PerfilPublicoScreenState extends State<PerfilPublicoScreen> {
  final _api = WarZeroApi();
  int? _vic2, _vic4, _vic6, _vic8; // null = aún no cargado / no disponible
  Map<int, int> _porcentajes = {}; // ejercitoId → % de colección

  @override
  void initState() {
    super.initState();
    _cargarExtras();
  }

  /// Lee, best-effort, las victorias por modo (del doc del jugador) y el % de
  /// colección por ejército (de la API). Silencioso: si algo falla, esa parte
  /// simplemente no se muestra.
  Future<void> _cargarExtras() async {
    // Victorias por modo (del doc del jugador).
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Jugadores')
          .doc(widget.uid)
          .get();
      final d = doc.data();
      if (d != null && mounted) {
        setState(() {
          _vic2 = (d['victorias2'] as num?)?.toInt() ?? 0;
          _vic4 = (d['victorias4'] as num?)?.toInt() ?? 0;
          _vic6 = (d['victorias6'] as num?)?.toInt() ?? 0;
          _vic8 = (d['victorias8'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // Sin permisos o error: se deja la sección por modo oculta.
    }

    // Colección por ejército (%). La API acepta el uid de cualquier jugador.
    try {
      final pct = await _api.obtenerPorcentajes(widget.uid);
      final map = <int, int>{};
      for (final raw in (pct?['porcentajes'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final ej = (m['ejercito'] as num?)?.toInt() ?? 0;
        if (ej != 0) map[ej] = (m['porcentaje'] as num?)?.toInt() ?? 0;
      }
      if (mounted) setState(() => _porcentajes = map);
    } catch (_) {
      // Si falla, no se muestra la sección de colección.
    }
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final nombre =
        widget.alias.trim().isEmpty ? 'Jugador' : widget.alias.trim();
    final tieneModos = _vic2 != null;

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('PERFIL',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: war.primario)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar con el icono del Nexo encima (superíndice).
            SizedBox(
              width: 112,
              height: 104,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: war.primario.withOpacity(0.5), width: 2),
                      color: war.primario.withOpacity(0.12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.imagen.startsWith('http')
                        ? Image.network(
                            widget.imagen,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.person,
                                color: war.primario, size: 48),
                          )
                        : Icon(Icons.person, color: war.primario, size: 48),
                  ),
                  Positioned(
                    top: 0,
                    right: 4,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: war.fondo,
                        border: const Border.fromBorderSide(
                            BorderSide(color: Color(0xFF9B5CFF), width: 1.5)),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF9B5CFF).withOpacity(0.5),
                              blurRadius: 8),
                        ],
                      ),
                      child: const Icon(Icons.hexagon_outlined,
                          size: 15, color: Color(0xFF9B5CFF)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: war.texto,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nivel ${widget.nivel < 1 ? 1 : widget.nivel} · ${widget.experiencia} XP',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 11,
                color: war.textoTenue,
              ),
            ),
            const SizedBox(height: 28),

            _SectionLabel('ESTADÍSTICAS', war),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    icon: '⭐',
                    label: 'NIVEL',
                    value: '${widget.nivel < 1 ? 1 : widget.nivel}',
                    color: war.primario,
                    war: war,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCell(
                    icon: '✨',
                    label: 'EXPERIENCIA',
                    value: '${widget.experiencia}',
                    color: war.secundario,
                    war: war,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCell(
                    icon: '🏆',
                    label: 'VICTORIAS',
                    value: '${widget.victorias}',
                    color: const Color(0xFF4ABB58),
                    war: war,
                  ),
                ),
              ],
            ),

            if (tieneModos) ...[
              const SizedBox(height: 28),
              _SectionLabel('VICTORIAS POR MODO', war),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _StatCell(
                        icon: '🏆',
                        label: '2 JUGADORES',
                        value: '$_vic2',
                        color: war.primario,
                        war: war),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCell(
                        icon: '🏆',
                        label: '4 JUGADORES',
                        value: '$_vic4',
                        color: war.primario,
                        war: war),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCell(
                        icon: '🏆',
                        label: '6 JUGADORES',
                        value: '$_vic6',
                        color: war.primario,
                        war: war),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCell(
                        icon: '🏆',
                        label: '8 JUGADORES',
                        value: '$_vic8',
                        color: war.primario,
                        war: war),
                  ),
                ],
              ),
            ],

            // Colección por ejército (% de cartas conseguidas).
            if (_porcentajes.isNotEmpty) ...[
              const SizedBox(height: 28),
              _SectionLabel('COLECCIÓN POR EJÉRCITO', war),
              const SizedBox(height: 14),
              for (final e in kEjercitos) ...[
                if (e != kEjercitos.first) const SizedBox(height: 10),
                _BarraColeccion(
                  ejercito: e,
                  pct: (_porcentajes[e.id] ?? 0).clamp(0, 100),
                  war: war,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final WarColors war;
  const _SectionLabel(this.text, this.war);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
          color: war.primario,
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;
  final WarColors war;

  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.war,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 6,
                  color: war.textoTenue,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

/// Barra de progreso del % de colección de un ejército.
class _BarraColeccion extends StatelessWidget {
  final EjercitoInfo ejercito;
  final int pct;
  final WarColors war;

  const _BarraColeccion({
    required this.ejercito,
    required this.pct,
    required this.war,
  });

  @override
  Widget build(BuildContext context) {
    final color = MonedaZeroExt.fromEjercito(ejercito.id).color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(ejercito.icono, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ejercito.nombre.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        letterSpacing: 1,
                        color: war.texto)),
              ),
              Text('$pct%',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              minHeight: 5,
              backgroundColor: war.borde.withOpacity(0.5),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
