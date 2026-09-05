// lib/views/perfil_publico_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/lobby_model.dart' show kEjercitos, EjercitoInfo;
import '../models/jugador_model.dart' show MonedaZeroExt;
import '../services/settings_controller.dart';
import '../services/trofeos_service.dart';
import '../services/warzero_api.dart';
import 'trofeos_screen.dart';

/// PERFIL PÚBLICO — vista de SOLO LECTURA del perfil de otro jugador.
///
/// Se abre al pulsar un jugador en el ranking. Muestra datos públicos: avatar,
/// alias, trofeo destacado, nivel, experiencia, victorias totales y por modo.
/// No muestra datos privados (correo, oro, cristales) ni permite editar.
///
/// Las victorias por modo, el % de colección y los trofeos se piden por la API
/// (con credenciales de admin), que puede leer el doc de CUALQUIER jugador; el
/// cliente no lee esos docs directamente (las reglas lo bloquean).
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
  final _trofeosSvc = TrofeosService();

  int? _vic2, _vic4, _vic6, _vic8; // null = aún no cargado / no disponible
  Map<int, int> _porcentajes = {}; // ejercitoId → % de colección
  TrofeosResult _trofeos = TrofeosResult.empty;

  @override
  void initState() {
    super.initState();
    _cargarExtras();
    _cargarTrofeos();
  }

  /// Trofeos del jugador (para el destacado junto al alias y el % conseguido).
  Future<void> _cargarTrofeos() async {
    final r = await _trofeosSvc.obtener(widget.uid);
    if (!mounted) return;
    setState(() => _trofeos = r);
  }

  /// Carga, best-effort, el % de colección por ejército y las victorias por modo.
  Future<void> _cargarExtras() async {
    int? v2, v4, v6, v8;
    final pctMap = <int, int>{};

    // ── Vía API (correcta para el perfil de otros jugadores) ──────────────
    try {
      final pct = await _api.obtenerPorcentajes(widget.uid);

      for (final raw in (pct?['porcentajes'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final ej = (m['ejercito'] as num?)?.toInt() ?? 0;
        if (ej != 0) pctMap[ej] = (m['porcentaje'] as num?)?.toInt() ?? 0;
      }

      // Victorias por modo (si el backend ya las incluye en la respuesta).
      if (pct != null && pct.containsKey('victorias2')) {
        v2 = (pct['victorias2'] as num?)?.toInt() ?? 0;
        v4 = (pct['victorias4'] as num?)?.toInt() ?? 0;
        v6 = (pct['victorias6'] as num?)?.toInt() ?? 0;
        v8 = (pct['victorias8'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      // Si falla la API, no se muestran esas secciones (o se intenta el fallback).
    }

    // ── Fallback: lectura directa del doc ─────────────────────────────────
    if (v2 == null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('Jugadores')
            .doc(widget.uid)
            .get();
        final d = doc.data();
        if (d != null) {
          v2 = (d['victorias2'] as num?)?.toInt() ?? 0;
          v4 = (d['victorias4'] as num?)?.toInt() ?? 0;
          v6 = (d['victorias6'] as num?)?.toInt() ?? 0;
          v8 = (d['victorias8'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {
        // Sin permisos o error: la sección por modo queda oculta.
      }
    }

    if (!mounted) return;
    setState(() {
      _porcentajes = pctMap;
      if (v2 != null) {
        _vic2 = v2;
        _vic4 = v4;
        _vic6 = v6;
        _vic8 = v8;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final nombre =
        widget.alias.trim().isEmpty ? 'Jugador' : widget.alias.trim();
    final tieneModos = _vic2 != null;
    final dest = _trofeos.destacado;
    const oro = Color(0xFFE0B040);

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
            // Alias con el icono del trofeo destacado delante.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dest != null) ...[
                  Text(dest.icono, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
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
                ),
              ],
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
            // Nombre del trofeo destacado.
            if (dest != null) ...[
              const SizedBox(height: 5),
              Text(
                '🏆 ${dest.nombre}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 11,
                  color: oro,
                ),
              ),
            ],
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

            // Trofeos: % conseguido + acceso a la lista (solo lectura).
            if (_trofeos.total > 0) ...[
              const SizedBox(height: 28),
              _SectionLabel('TROFEOS', war),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TrofeosScreen(uid: widget.uid, alias: nombre),
                  ),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: war.superficie,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: oro.withOpacity(0.35), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TROFEOS CONSEGUIDOS',
                                style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 10,
                                    letterSpacing: 1,
                                    color: war.texto)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (_trofeos.porcentaje / 100.0)
                                    .clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor: war.borde.withOpacity(0.5),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(oro),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${_trofeos.porcentaje}%',
                          style: const TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: oro)),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right,
                          size: 18, color: war.textoTenue),
                    ],
                  ),
                ),
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
