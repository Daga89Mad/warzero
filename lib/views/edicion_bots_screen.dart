// lib/views/edicion_bots_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Pantalla de administración de BOTS (solo editores). Mismo patrón visual que
/// la edición de Mapas / Historias.
///
/// Muestra 50 bots con un interruptor "activo" y un control de PARTIDAS
/// SIMULTÁNEAS. Al activar uno, el orquestador del backend
/// (BotOrchestratorService) lo detecta y lo mete a rellenar las PARTIDAS
/// PÚBLICAS más antiguas: llena primero la sala más vieja y, si sobran bots,
/// desborda a la siguiente. Cada bot puede jugar hasta `maxPartidas` partidas a
/// la vez. Si desactivas un bot, deja de entrar a salas nuevas (las partidas que
/// ya está jugando las termina igualmente: la recuperación del backend sigue
/// cerrando sus turnos aunque esté inactivo).
///
/// Escribe en la colección Firestore `Bots`, un documento por bot:
///   alias        : String   (nombre visible en la partida)
///   activo       : bool     (lo pone/quita este panel; lo lee el orquestador)
///   orden        : int      (prioridad de asignación; menor entra antes)
///   maxPartidas  : int      (partidas simultáneas; por defecto 1)
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

  final _col = FirebaseFirestore.instance.collection('Bots');

  bool _loading = true;
  String? _error;
  List<_BotResumen> _bots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carga los bots, sembrando los documentos que falten (así el panel y el
  /// orquestador comparten siempre las mismas entradas). No pisa los que ya
  /// existan: respeta su `activo`, `orden`, `alias` y `maxPartidas`.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _col.get();
      final existentes = {for (final d in snap.docs) d.id: d};

      // Sembrar los que falten (en lotes para no disparar 50 escrituras sueltas).
      final batch = FirebaseFirestore.instance.batch();
      var faltan = 0;
      for (var i = 0; i < _numBots; i++) {
        final id = 'bot_$i';
        if (!existentes.containsKey(id)) {
          batch.set(_col.doc(id), {
            'alias': 'IA Recluta ${i + 1}',
            'activo': false,
            'orden': i,
            'maxPartidas': 1,
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

  Future<void> _setTodos(bool activo) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final b in _bots) {
      batch.update(_col.doc(b.id), {'activo': activo});
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final b in _bots) b.activo = activo;
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
        for (final b in _bots) b.maxPartidas = v;
      });
      _toast(
          'Todos los bots a $v ${v == 1 ? "partida" : "partidas"} simultáneas');
    } catch (e) {
      _toast('No se pudo aplicar a todos: $e', error: true);
    }
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
                    _cabecera(activos),
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
                          onChanged: (v) => _toggle(_bots[i], v),
                          onPartidas: (v) => _setMaxPartidas(_bots[i], v),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _cabecera(int activos) {
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
                'Partidas simultáneas a todos:',
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
          const Text(
            'Los bots activos entran a rellenar las partidas públicas más '
            'antiguas: llenan primero la sala más vieja y, si sobran, pasan a '
            'la siguiente. Cada bot juega hasta su nº de "Partidas" a la vez '
            '(por defecto 1). Al desactivar uno deja de entrar a salas nuevas.',
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

  _BotResumen({
    required this.id,
    required this.alias,
    required this.orden,
    required this.activo,
    required this.maxPartidas,
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
    );
  }
}

class _BotTile extends StatelessWidget {
  final _BotResumen bot;
  final Color accent;
  final int minPartidas;
  final int maxPartidas;
  final ValueChanged<bool> onChanged;
  final ValueChanged<int> onPartidas;

  const _BotTile({
    required this.bot,
    required this.accent,
    required this.minPartidas,
    required this.maxPartidas,
    required this.onChanged,
    required this.onPartidas,
  });

  @override
  Widget build(BuildContext context) {
    final on = bot.activo;
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
                Text(
                  bot.alias,
                  style: TextStyle(
                    color: on ? Colors.white : const Color(0xFFB0B8C0),
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  on ? 'Activo · rellenando salas' : 'Inactivo',
                  style: TextStyle(
                    color: on ? accent : const Color(0xFF6A727C),
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    letterSpacing: 0.5,
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
          'Partidas',
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
