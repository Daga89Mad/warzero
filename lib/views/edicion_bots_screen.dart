// lib/views/edicion_bots_screen.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lobby_model.dart' show EjercitoInfo;
import '../services/ejercito_service.dart';

/// Pantalla de administración de BOTS (solo editores). Mismo patrón visual que
/// la edición de Mapas / Historias.
///
/// Por cada bot permite configurar:
///   · ACTIVO         → si entra a rellenar salas públicas nuevas.
///   · PARTIDAS       → cuántas partidas simultáneas puede jugar (`maxPartidas`).
///   · EJÉRCITO       → con qué ejército juega (`ejercitoId`). IMPORTANTE: sin
///                      ejército asignado el servidor le reparte un mazo del
///                      catálogo completo y mezcla cartas de varios ejércitos.
/// Y muestra en vivo:
///   · EN JUEGO       → en cuántas partidas está metido ahora (`partidasActivas`,
///                      lo escribe el orquestador del backend en cada barrido).
///
/// Al activar un bot, el orquestador (BotOrchestratorService) lo detecta y lo
/// mete a rellenar las PARTIDAS PÚBLICAS más antiguas: llena primero la sala más
/// vieja y, si sobran bots, desborda a la siguiente. Si desactivas un bot, deja
/// de entrar a salas nuevas, pero TERMINA las partidas que ya está jugando.
///
/// Escribe en la colección Firestore `Bots`, un documento por bot:
///   alias           : String   (nombre visible en la partida)
///   activo          : bool     (lo pone/quita este panel; lo lee el orquestador)
///   orden           : int      (prioridad de asignación; menor entra antes)
///   maxPartidas     : int      (partidas simultáneas; por defecto 1)
///   ejercitoId      : int      (1..N; ejército con el que juega)
///   partidasActivas : int      (SOLO LECTURA: lo escribe el backend)
///
/// El `id` del documento ES el uid del bot dentro de la partida (bot_0…bot_49).
class EdicionBotsScreen extends StatefulWidget {
  const EdicionBotsScreen({super.key});

  @override
  State<EdicionBotsScreen> createState() => _EdicionBotsScreenState();
}

class _EdicionBotsScreenState extends State<EdicionBotsScreen> {
  static const _accent = Color(0xFF50B060);

  /// Nº de bots que gestiona el panel. Sembrará bot_0 … bot_(_numBots-1).
  static const _numBots = 50;

  /// Límites del control de partidas simultáneas.
  static const _minPartidas = 1;
  static const _maxPartidas = 20;

  /// Cada cuánto se refresca el contador "en juego" (campo `partidasActivas`).
  static const _refrescoContadores = Duration(seconds: 20);

  final _col = FirebaseFirestore.instance.collection('Bots');
  final _ejercitoService = EjercitoService();

  bool _loading = true;
  String? _error;
  List<_BotResumen> _bots = [];
  List<EjercitoInfo> _ejercitos = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresco periódico SOLO del contador de partidas: los documentos de `Bots`
    // son diminutos, así que es una lectura barata.
    _timer = Timer.periodic(_refrescoContadores, (_) => _refrescarContadores());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Carga ejércitos y bots, sembrando los documentos que falten (así el panel y
  /// el orquestador comparten siempre las mismas entradas). No pisa los que ya
  /// existan: respeta su `activo`, `orden`, `alias`, `maxPartidas` y `ejercitoId`.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ejercitos = await _ejercitoService.fetchEjercitos();
      final snap = await _col.get();
      final existentes = {for (final d in snap.docs) d.id: d};

      // Sembrar los que falten (en lotes para no disparar 50 escrituras sueltas).
      // El ejército se reparte en rueda para que los bots no jueguen todos igual.
      final batch = FirebaseFirestore.instance.batch();
      var faltan = 0;
      for (var i = 0; i < _numBots; i++) {
        final id = 'bot_$i';
        if (!existentes.containsKey(id)) {
          final ejercitoId =
              ejercitos.isEmpty ? 1 : ejercitos[i % ejercitos.length].id;
          batch.set(_col.doc(id), {
            'alias': 'IA Recluta ${i + 1}',
            'activo': false,
            'orden': i,
            'maxPartidas': 1,
            'ejercitoId': ejercitoId,
          });
          faltan++;
        }
      }
      if (faltan > 0) {
        await batch.commit();
        return _load(); // recarga con los recién creados
      }

      final lista = snap.docs.map(_BotResumen.fromDoc).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

      if (!mounted) return;
      setState(() {
        _ejercitos = ejercitos;
        _bots = lista;
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

  /// Relee SOLO `partidasActivas` de cada bot, sin tocar el resto del estado
  /// local (para no pisar cambios optimistas de los interruptores).
  Future<void> _refrescarContadores() async {
    if (_loading || !mounted) return;
    try {
      final snap = await _col.get();
      final activas = <String, int>{
        for (final d in snap.docs)
          d.id: (d.data()['partidasActivas'] as num?)?.toInt() ?? 0,
      };
      if (!mounted) return;
      setState(() {
        for (final b in _bots) {
          b.partidasActivas = activas[b.id] ?? b.partidasActivas;
        }
      });
    } catch (_) {
      // Silencioso: es un refresco de cortesía, no una acción del usuario.
    }
  }

  Future<void> _toggle(_BotResumen bot, bool activo) async {
    // Optimista: reflejamos el cambio ya y persistimos.
    setState(() => bot.activo = activo);
    try {
      await _col.doc(bot.id).update({'activo': activo});
      _toast(activo
          ? '${bot.alias} activado: entrará a rellenar salas públicas'
          : '${bot.alias} desactivado: no entrará a salas nuevas');
    } catch (e) {
      if (mounted) setState(() => bot.activo = !activo); // revertir
      _toast('No se pudo actualizar: $e', error: true);
    }
  }

  /// Cambia las partidas simultáneas de un bot (con clamp) y lo persiste.
  Future<void> _setMaxPartidas(_BotResumen bot, int nuevo) async {
    final valor = nuevo.clamp(_minPartidas, _maxPartidas);
    if (valor == bot.maxPartidas) return;
    final anterior = bot.maxPartidas;
    setState(() => bot.maxPartidas = valor);
    try {
      await _col.doc(bot.id).update({'maxPartidas': valor});
    } catch (e) {
      if (mounted) setState(() => bot.maxPartidas = anterior); // revertir
      _toast('No se pudo actualizar partidas: $e', error: true);
    }
  }

  /// Asigna el ejército con el que juega el bot. Sin esto, el servidor le
  /// reparte un mazo del catálogo completo y mezcla cartas de varios ejércitos.
  Future<void> _setEjercito(_BotResumen bot, int ejercitoId) async {
    if (ejercitoId == bot.ejercitoId) return;
    final anterior = bot.ejercitoId;
    setState(() => bot.ejercitoId = ejercitoId);
    try {
      await _col.doc(bot.id).update({'ejercitoId': ejercitoId});
      _toast('${bot.alias} → ${_nombreEjercito(ejercitoId)}');
    } catch (e) {
      if (mounted) setState(() => bot.ejercitoId = anterior); // revertir
      _toast('No se pudo cambiar el ejército: $e', error: true);
    }
  }

  Future<void> _setTodos(bool activo) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final b in _bots) {
      batch.update(_col.doc(b.id), {'activo': activo});
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final b in _bots) {
          b.activo = activo;
        }
      });
      _toast(
          activo ? 'Todos los bots activados' : 'Todos los bots desactivados');
    } catch (e) {
      _toast('No se pudo aplicar a todos: $e', error: true);
    }
  }

  /// Aplica el mismo nº de partidas simultáneas a TODOS los bots.
  Future<void> _setPartidasTodos(int valor) async {
    final v = valor.clamp(_minPartidas, _maxPartidas);
    final batch = FirebaseFirestore.instance.batch();
    for (final b in _bots) {
      batch.update(_col.doc(b.id), {'maxPartidas': v});
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final b in _bots) {
          b.maxPartidas = v;
        }
      });
      _toast(
          'Todos los bots a $v ${v == 1 ? "partida" : "partidas"} simultáneas');
    } catch (e) {
      _toast('No se pudo aplicar a todos: $e', error: true);
    }
  }

  /// Reparte los ejércitos en rueda entre todos los bots (1,2,3,4,1,2,…), para
  /// que la población de bots no juegue toda con el mismo ejército.
  Future<void> _repartirEjercitos() async {
    if (_ejercitos.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < _bots.length; i++) {
      final eid = _ejercitos[i % _ejercitos.length].id;
      batch.update(_col.doc(_bots[i].id), {'ejercitoId': eid});
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _bots.length; i++) {
          _bots[i].ejercitoId = _ejercitos[i % _ejercitos.length].id;
        }
      });
      _toast('Ejércitos repartidos entre los ${_bots.length} bots');
    } catch (e) {
      _toast('No se pudieron repartir: $e', error: true);
    }
  }

  /// Hoja inferior para elegir el ejército de un bot.
  void _elegirEjercito(_BotResumen bot) {
    if (_ejercitos.isEmpty) {
      _toast('No hay ejércitos disponibles', error: true);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'EJÉRCITO DE ${bot.alias.toUpperCase()}',
                style: const TextStyle(
                  color: _accent,
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            ..._ejercitos.map((e) {
              final sel = e.id == bot.ejercitoId;
              return ListTile(
                leading: Text(e.icono, style: const TextStyle(fontSize: 22)),
                title: Text(
                  e.nombre,
                  style: TextStyle(
                    color: sel ? _accent : Colors.white,
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: e.descripcion.isEmpty
                    ? null
                    : Text(
                        e.descripcion,
                        style: const TextStyle(
                          color: Color(0xFF8A94A0),
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                        ),
                      ),
                trailing: sel
                    ? const Icon(Icons.check, color: _accent, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  _setEjercito(bot, e.id);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _nombreEjercito(int id) {
    for (final e in _ejercitos) {
      if (e.id == id) return e.nombre;
    }
    return id <= 0 ? 'Sin ejército' : 'Ejército $id';
  }

  String _iconoEjercito(int id) {
    for (final e in _ejercitos) {
      if (e.id == id) return e.icono;
    }
    return '⚔️';
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cinzel')),
      backgroundColor:
          error ? const Color(0xFF3A0E0E) : const Color(0xFF0E2A14),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final activos = _bots.where((b) => b.activo).length;
    final enJuego = _bots.fold<int>(0, (s, b) => s + b.partidasActivas);
    return Scaffold(
      backgroundColor: const Color(0xFF060E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        iconTheme: const IconThemeData(color: _accent),
        title: const Text(
          'BOTS · RELLENO DE SALAS',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Cinzel',
            letterSpacing: 2,
            color: _accent,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(
                          color: Color(0xFFFF6060), fontFamily: 'Cinzel'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    _cabecera(activos, enJuego),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _bots.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _BotTile(
                          bot: _bots[i],
                          accent: _accent,
                          minPartidas: _minPartidas,
                          maxPartidas: _maxPartidas,
                          nombreEjercito: _nombreEjercito(_bots[i].ejercitoId),
                          iconoEjercito: _iconoEjercito(_bots[i].ejercitoId),
                          onChanged: (v) => _toggle(_bots[i], v),
                          onPartidas: (v) => _setMaxPartidas(_bots[i], v),
                          onEjercito: () => _elegirEjercito(_bots[i]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _cabecera(int activos, int enJuego) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy_outlined, color: _accent, size: 20),
              const SizedBox(width: 8),
              Text(
                '$activos / ${_bots.length} activos',
                style: const TextStyle(
                  color: _accent,
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.videogame_asset_outlined,
                  color: Color(0xFF8A94A0), size: 16),
              const SizedBox(width: 4),
              Text(
                '$enJuego en juego',
                style: const TextStyle(
                  color: Color(0xFF8A94A0),
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              _MiniBoton(
                  label: 'TODOS',
                  accent: _accent,
                  onTap: () => _setTodos(true)),
              const SizedBox(width: 8),
              _MiniBoton(
                  label: 'NINGUNO',
                  accent: const Color(0xFF808890),
                  onTap: () => _setTodos(false)),
            ],
          ),
          const SizedBox(height: 12),
          // Atajo: partidas simultáneas para TODOS de golpe.
          Row(
            children: [
              const Icon(Icons.dynamic_feed_outlined,
                  color: Color(0xFF8A94A0), size: 16),
              const SizedBox(width: 8),
              const Text(
                'Partidas a todos:',
                style: TextStyle(
                  color: Color(0xFF8A94A0),
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              _MiniBoton(
                  label: '1',
                  accent: _accent,
                  onTap: () => _setPartidasTodos(1)),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: '2',
                  accent: _accent,
                  onTap: () => _setPartidasTodos(2)),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: '3',
                  accent: _accent,
                  onTap: () => _setPartidasTodos(3)),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: '5',
                  accent: _accent,
                  onTap: () => _setPartidasTodos(5)),
            ],
          ),
          const SizedBox(height: 10),
          // Atajo: repartir ejércitos en rueda.
          Row(
            children: [
              const Icon(Icons.flag_outlined,
                  color: Color(0xFF8A94A0), size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Repartir ejércitos entre todos los bots',
                  style: TextStyle(
                    color: Color(0xFF8A94A0),
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                  ),
                ),
              ),
              _MiniBoton(
                  label: 'REPARTIR',
                  accent: _accent,
                  onTap: _repartirEjercitos),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Cada bot juega con SU ejército: sin asignarlo, el servidor le '
            'reparte cartas de varios ejércitos mezcladas. "En juego" lo escribe '
            'el backend y se refresca solo cada 20 s. Al desactivar un bot deja '
            'de entrar a salas nuevas, pero termina las que ya juega.',
            style: TextStyle(
              color: Color(0xFF8A94A0),
              fontFamily: 'Cinzel',
              fontSize: 10,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Resumen mutable de un bot para la UI.
class _BotResumen {
  final String id;
  final String alias;
  final int orden;
  bool activo;
  int maxPartidas;
  int ejercitoId;

  /// Partidas en las que está metido AHORA. Solo lectura: lo escribe el
  /// orquestador del backend en cada barrido.
  int partidasActivas;

  _BotResumen({
    required this.id,
    required this.alias,
    required this.orden,
    required this.activo,
    required this.maxPartidas,
    required this.ejercitoId,
    required this.partidasActivas,
  });

  factory _BotResumen.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final mp = (data['maxPartidas'] as num?)?.toInt() ??
        (data['partidasSimultaneas'] as num?)?.toInt() ??
        1;
    return _BotResumen(
      id: d.id,
      alias: (data['alias'] as String?) ?? d.id,
      orden: (data['orden'] as num?)?.toInt() ?? 0,
      activo: (data['activo'] as bool?) ?? false,
      maxPartidas: mp < 1 ? 1 : mp,
      ejercitoId: (data['ejercitoId'] as num?)?.toInt() ?? 0,
      partidasActivas: (data['partidasActivas'] as num?)?.toInt() ?? 0,
    );
  }
}

class _BotTile extends StatelessWidget {
  final _BotResumen bot;
  final Color accent;
  final int minPartidas;
  final int maxPartidas;
  final String nombreEjercito;
  final String iconoEjercito;
  final ValueChanged<bool> onChanged;
  final ValueChanged<int> onPartidas;
  final VoidCallback onEjercito;

  const _BotTile({
    required this.bot,
    required this.accent,
    required this.minPartidas,
    required this.maxPartidas,
    required this.nombreEjercito,
    required this.iconoEjercito,
    required this.onChanged,
    required this.onPartidas,
    required this.onEjercito,
  });

  @override
  Widget build(BuildContext context) {
    final on = bot.activo;
    final jugando = bot.partidasActivas > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: on ? accent.withOpacity(0.55) : const Color(0xFF1A2436),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (on ? accent : const Color(0xFF808890)).withOpacity(0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    (on ? accent : const Color(0xFF808890)).withOpacity(0.30),
              ),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 20,
              color: on ? accent : const Color(0xFF808890),
            ),
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
                        bot.alias,
                        style: TextStyle(
                          color: on ? Colors.white : const Color(0xFFB0B8C0),
                          fontFamily: 'Cinzel',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    // EN JUEGO: partidas en las que está metido ahora mismo.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (jugando ? accent : const Color(0xFF6A727C))
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (jugando ? accent : const Color(0xFF6A727C))
                              .withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        '🎮 ${bot.partidasActivas}/${bot.maxPartidas}',
                        style: TextStyle(
                          color: jugando ? accent : const Color(0xFF6A727C),
                          fontFamily: 'Cinzel',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // EJÉRCITO: pulsable para cambiarlo.
                GestureDetector(
                  onTap: onEjercito,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: bot.ejercitoId > 0
                          ? const Color(0xFF12203A)
                          : const Color(0xFF3A2A0E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: bot.ejercitoId > 0
                            ? const Color(0xFF2A3A56)
                            : const Color(0xFFE0A030),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(bot.ejercitoId > 0 ? iconoEjercito : '⚠️',
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 6),
                        Text(
                          bot.ejercitoId > 0
                              ? nombreEjercito
                              : 'SIN EJÉRCITO (mezcla cartas)',
                          style: TextStyle(
                            color: bot.ejercitoId > 0
                                ? const Color(0xFFB0B8C0)
                                : const Color(0xFFE0A030),
                            fontFamily: 'Cinzel',
                            fontSize: 9,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more,
                            size: 13, color: Color(0xFF6A727C)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _StepperPartidas(
                  valor: bot.maxPartidas,
                  accent: accent,
                  onMenos: bot.maxPartidas > minPartidas
                      ? () => onPartidas(bot.maxPartidas - 1)
                      : null,
                  onMas: bot.maxPartidas < maxPartidas
                      ? () => onPartidas(bot.maxPartidas + 1)
                      : null,
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            activeColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Control compacto "− N +" para las partidas simultáneas de un bot.
class _StepperPartidas extends StatelessWidget {
  final int valor;
  final Color accent;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;

  const _StepperPartidas({
    required this.valor,
    required this.accent,
    required this.onMenos,
    required this.onMas,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Máx. partidas',
          style: TextStyle(
            color: Color(0xFF6A727C),
            fontFamily: 'Cinzel',
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        _StepBtn(icon: Icons.remove, accent: accent, onTap: onMenos),
        Container(
          constraints: const BoxConstraints(minWidth: 26),
          alignment: Alignment.center,
          child: Text(
            '$valor',
            style: TextStyle(
              color: accent,
              fontFamily: 'Cinzel',
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        _StepBtn(icon: Icons.add, accent: accent, onTap: onMas),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const _StepBtn({
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? accent : const Color(0xFF3A424C);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.40)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _MiniBoton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _MiniBoton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withOpacity(0.40)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontFamily: 'Cinzel',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
