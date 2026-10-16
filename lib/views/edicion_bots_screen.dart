// lib/views/edicion_bots_screen.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lobby_model.dart'
    show EjercitoInfo, LobbyModel, ModoTurno;
import '../models/modo_partida.dart';
import '../services/admin_bots_service.dart';
import '../services/ejercito_service.dart';
import '../services/warzero_api.dart';

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
///
/// ENVIAR A PARTIDA: cada bot tiene un botón que abre la lista de PARTIDAS
/// PÚBLICAS en espera y permite mandarlo directamente a una de ellas para que
/// ocupe un hueco (endpoint de editor /admin/bots/enviar). El bot entra esté
/// activo o no y sin contar su tope de partidas: es una orden explícita.
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

  /// Límites del control de espera (segundos) antes de entrar en salas
  /// proactivas. 0 = entra de inmediato; se ajusta en pasos de 15 s.
  static const _minEspera = 0;
  static const _maxEspera = 600; // 10 min
  static const _stepEspera = 15;

  /// Cada cuánto se refresca el contador "en juego" (campo `partidasActivas`).
  static const _refrescoContadores = Duration(seconds: 20);

  final _col = FirebaseFirestore.instance.collection('Bots');
  final _ejercitoService = EjercitoService();
  final _adminBots = AdminBotsService();

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
            'dificultad': 'medio',
            'estilo': 'equilibrado',
            'esperaSegundos': 0,
            'esBot': true,
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

  /// Marca si el bot CUENTA como bot (true) o "juega como humano" (false). Lo lee
  /// el backend al liquidar la partida para los trofeos "sin bots".
  Future<void> _toggleEsBot(_BotResumen bot, bool esBot) async {
    setState(() => bot.esBot = esBot);
    try {
      await _col.doc(bot.id).update({'esBot': esBot});
      _toast(esBot
          ? '${bot.alias} cuenta como BOT'
          : '${bot.alias} cuenta como HUMANO (juega como humano)');
    } catch (e) {
      if (mounted) setState(() => bot.esBot = !esBot); // revertir
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

  /// Cambia la espera (segundos) que debe llevar una sala en espera antes de que
  /// este bot entre por relleno proactivo, con clamp, y lo persiste.
  Future<void> _setEspera(_BotResumen bot, int nuevo) async {
    final valor = nuevo.clamp(_minEspera, _maxEspera);
    if (valor == bot.esperaSegundos) return;
    final anterior = bot.esperaSegundos;
    setState(() => bot.esperaSegundos = valor);
    try {
      await _col.doc(bot.id).update({'esperaSegundos': valor});
    } catch (e) {
      if (mounted) setState(() => bot.esperaSegundos = anterior); // revertir
      _toast('No se pudo actualizar la espera: $e', error: true);
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

  /// Cambia la DIFICULTAD del bot ('medio'|'alto') y la persiste.
  Future<void> _setDificultad(_BotResumen bot, String dif) async {
    if (dif == bot.dificultad || !kDificultades.contains(dif)) return;
    final anterior = bot.dificultad;
    setState(() => bot.dificultad = dif);
    try {
      await _col.doc(bot.id).update({'dificultad': dif});
      _toast('${bot.alias} → dificultad ${etiquetaDificultad(dif)}');
    } catch (e) {
      if (mounted) setState(() => bot.dificultad = anterior); // revertir
      _toast('No se pudo cambiar la dificultad: $e', error: true);
    }
  }

  /// Cambia el ESTILO del bot ('equilibrado'|'defensivo'|'agresivo').
  Future<void> _setEstilo(_BotResumen bot, String est) async {
    if (est == bot.estilo || !kEstilos.contains(est)) return;
    final anterior = bot.estilo;
    setState(() => bot.estilo = est);
    try {
      await _col.doc(bot.id).update({'estilo': est});
      _toast('${bot.alias} → estilo ${etiquetaEstilo(est)}');
    } catch (e) {
      if (mounted) setState(() => bot.estilo = anterior); // revertir
      _toast('No se pudo cambiar el estilo: $e', error: true);
    }
  }

  /// Diálogo para RENOMBRAR el bot (campo `alias`, el nombre visible en partida).
  Future<void> _renombrar(_BotResumen bot) async {
    final ctrl = TextEditingController(text: bot.alias);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1220),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _accent.withOpacity(0.4)),
        ),
        title: const Text(
          'RENOMBRAR BOT',
          style: TextStyle(
            color: _accent,
            fontFamily: 'Cinzel',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          style: const TextStyle(color: Colors.white, fontFamily: 'Cinzel'),
          cursorColor: _accent,
          decoration: InputDecoration(
            hintText: 'Nombre visible en la partida',
            hintStyle: const TextStyle(color: Color(0xFF6A727C)),
            counterStyle: const TextStyle(color: Color(0xFF6A727C)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1A2436)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCELAR',
                style:
                    TextStyle(color: Color(0xFF808890), fontFamily: 'Cinzel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text('GUARDAR',
                style: TextStyle(color: _accent, fontFamily: 'Cinzel')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nuevo == null || nuevo.isEmpty || nuevo == bot.alias) return;

    final anterior = bot.alias;
    setState(() => bot.alias = nuevo);
    try {
      await _col.doc(bot.id).update({'alias': nuevo});
      _toast('Renombrado: $anterior → $nuevo');
    } catch (e) {
      if (mounted) setState(() => bot.alias = anterior); // revertir
      _toast('No se pudo renombrar: $e', error: true);
    }
  }

  /// Aplica la misma dificultad a TODOS los bots.
  Future<void> _setDificultadTodos(String dif) async {
    if (!kDificultades.contains(dif)) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final b in _bots) {
      batch.update(_col.doc(b.id), {'dificultad': dif});
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final b in _bots) {
          b.dificultad = dif;
        }
      });
      _toast('Todos los bots → dificultad ${etiquetaDificultad(dif)}');
    } catch (e) {
      _toast('No se pudo aplicar a todos: $e', error: true);
    }
  }

  /// Aplica el mismo estilo a TODOS los bots.
  Future<void> _setEstiloTodos(String est) async {
    if (!kEstilos.contains(est)) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final b in _bots) {
      batch.update(_col.doc(b.id), {'estilo': est});
    }
    try {
      await batch.commit();
      if (!mounted) return;
      setState(() {
        for (final b in _bots) {
          b.estilo = est;
        }
      });
      _toast('Todos los bots → estilo ${etiquetaEstilo(est)}');
    } catch (e) {
      _toast('No se pudo aplicar a todos: $e', error: true);
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

  /// Abre la hoja con las PARTIDAS PÚBLICAS en espera para mandar a [bot] a
  /// ocupar un hueco en una de ellas.
  void _enviarAPartida(_BotResumen bot) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => _SalasPublicasSheet(
        bot: bot,
        accent: _accent,
        botIds: _bots.map((b) => b.id).toSet(),
        aliasBots: {for (final b in _bots) b.id: b.alias},
        onEnviar: (sala) => _confirmarEnvio(bot, sala),
      ),
    );
  }

  /// Pide confirmación y manda el bot a la sala. Devuelve true si se envió
  /// (la hoja se cierra) y false si se canceló o falló (la hoja sigue abierta).
  Future<bool> _confirmarEnvio(_BotResumen bot, LobbyModel sala) async {
    final huecos = sala.maxJugadores - sala.jugadores.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1220),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _accent.withOpacity(0.4)),
        ),
        title: const Text(
          'ENVIAR BOT',
          style: TextStyle(
            color: _accent,
            fontFamily: 'Cinzel',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          '¿Mandar a ${bot.alias} a la partida "${sala.nombre}"?\n\n'
          'Ocupará 1 de los $huecos ${huecos == 1 ? "hueco libre" : "huecos libres"} '
          'y jugará con ${_nombreEjercito(bot.ejercitoId)} '
          '(${etiquetaDificultad(bot.dificultad)} · ${etiquetaEstilo(bot.estilo)}).'
          '${bot.activo ? "" : "\n\nEl bot está DESACTIVADO: entrará igualmente en esta partida."}'
          '${bot.partidasActivas >= bot.maxPartidas ? "\n\nYa está en su máximo de partidas (${bot.maxPartidas}): esta se suma por encima del límite." : ""}',
          style: const TextStyle(
            color: Color(0xFFB0B8C0),
            fontFamily: 'Cinzel',
            fontSize: 11,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR',
                style:
                    TextStyle(color: Color(0xFF808890), fontFamily: 'Cinzel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('ENVIAR',
                style: TextStyle(
                    color: _accent,
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    try {
      final res = await _adminBots.enviarBotAPartida(
        botUid: bot.id,
        lobbyId: sala.id,
      );
      if (!mounted) return true;
      setState(() => bot.partidasActivas = res.partidasActivas);
      _toast('${bot.alias} va de camino a "${sala.nombre}"');
      return true;
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
      return false;
    }
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
                          minEspera: _minEspera,
                          maxEspera: _maxEspera,
                          stepEspera: _stepEspera,
                          nombreEjercito: _nombreEjercito(_bots[i].ejercitoId),
                          iconoEjercito: _iconoEjercito(_bots[i].ejercitoId),
                          onChanged: (v) => _toggle(_bots[i], v),
                          onPartidas: (v) => _setMaxPartidas(_bots[i], v),
                          onEspera: (v) => _setEspera(_bots[i], v),
                          onEjercito: () => _elegirEjercito(_bots[i]),
                          onDificultad: (v) => _setDificultad(_bots[i], v),
                          onEstilo: (v) => _setEstilo(_bots[i], v),
                          onEsBot: (v) => _toggleEsBot(_bots[i], v),
                          onRenombrar: () => _renombrar(_bots[i]),
                          onEnviarPartida: () => _enviarAPartida(_bots[i]),
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
          // Atajo: dificultad para TODOS.
          Row(
            children: [
              const Icon(Icons.speed_outlined,
                  color: Color(0xFF8A94A0), size: 16),
              const SizedBox(width: 8),
              const Text(
                'Dificultad a todos:',
                style: TextStyle(
                  color: Color(0xFF8A94A0),
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              _MiniBoton(
                  label: 'MEDIO',
                  accent: _accent,
                  onTap: () => _setDificultadTodos('medio')),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: 'ALTO',
                  accent: const Color(0xFFE0703A),
                  onTap: () => _setDificultadTodos('alto')),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: 'MAESTRO',
                  accent: const Color(0xFFC9A227),
                  onTap: () => _setDificultadTodos('maestro')),
            ],
          ),
          const SizedBox(height: 10),
          // Atajo: estilo para TODOS.
          Row(
            children: [
              const Icon(Icons.sports_kabaddi_outlined,
                  color: Color(0xFF8A94A0), size: 16),
              const SizedBox(width: 8),
              const Text(
                'Estilo a todos:',
                style: TextStyle(
                  color: Color(0xFF8A94A0),
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              _MiniBoton(
                  label: 'EQUIL.',
                  accent: _accent,
                  onTap: () => _setEstiloTodos('equilibrado')),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: 'DEFENS.',
                  accent: const Color(0xFF3A78E0),
                  onTap: () => _setEstiloTodos('defensivo')),
              const SizedBox(width: 6),
              _MiniBoton(
                  label: 'AGRES.',
                  accent: const Color(0xFFE0703A),
                  onTap: () => _setEstiloTodos('agresivo')),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'DIFICULTAD: Medio (jugador competente) o Alto (más despliegues, '
            'habilidades y evoluciones por turno, predice mejor y presiona más). '
            'ESTILO: Equilibrado, Defensivo (aguanta y farmea) o Agresivo (empuja a '
            'los cuarteles enemigos). Toca el lápiz para renombrar. Cada bot juega '
            'con SU ejército: sin asignarlo, el servidor le reparte cartas mezcladas. '
            '"En juego" lo escribe el backend y se refresca cada 20 s. Al desactivar '
            'un bot deja de entrar a salas nuevas, pero termina las que ya juega. '
            'ENVIAR A PARTIDA manda ese bot a una partida pública concreta.',
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

/// Valores admitidos para el perfil de un bot (deben coincidir con lo que lee el
/// backend en `PerfilBot.Parse`).
const kDificultades = <String>['medio', 'alto', 'maestro'];
const kEstilos = <String>['equilibrado', 'defensivo', 'agresivo'];

/// Etiquetas visibles.
String etiquetaDificultad(String d) => switch (d) {
      'alto' => 'Alto',
      'maestro' => 'Maestro',
      _ => 'Medio',
    };
String etiquetaEstilo(String e) => switch (e) {
      'defensivo' => 'Defensivo',
      'agresivo' => 'Agresivo',
      _ => 'Equilibrado',
    };

/// Resumen mutable de un bot para la UI.
class _BotResumen {
  final String id;
  String alias;
  final int orden;
  bool activo;
  int maxPartidas;
  int ejercitoId;

  /// Segundos que debe llevar una sala en espera antes de que este bot entre
  /// por relleno proactivo. 0 = de inmediato.
  int esperaSegundos;

  /// Perfil de juego: dificultad ('medio'|'alto'|'maestro') y estilo
  /// ('equilibrado'|'defensivo'|'agresivo'). Maestro = Alto + apertura
  /// económica, asedio en masa, conversión del excedente y mazo propio por
  /// ejército (lo escribe el backend en Jugadores/{uid}/Mazos).
  String dificultad;
  String estilo;

// Si true, CUENTA como bot (por defecto). Si false, el bot "juega como
  /// humano": no descalifica las victorias "sin bots" de sus rivales.
  bool esBot;

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
    required this.esperaSegundos,
    required this.dificultad,
    required this.estilo,
    required this.esBot,
    required this.partidasActivas,
  });

  factory _BotResumen.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final mp = (data['maxPartidas'] as num?)?.toInt() ??
        (data['partidasSimultaneas'] as num?)?.toInt() ??
        1;
    // Normaliza el perfil a los valores admitidos (retrocompatible: los bots
    // antiguos sin estos campos caen a medio/equilibrado = comportamiento actual).
    final dif = (data['dificultad'] as String?)?.trim().toLowerCase();
    final est = (data['estilo'] as String?)?.trim().toLowerCase();
    return _BotResumen(
      id: d.id,
      alias: (data['alias'] as String?) ?? d.id,
      orden: (data['orden'] as num?)?.toInt() ?? 0,
      activo: (data['activo'] as bool?) ?? false,
      maxPartidas: mp < 1 ? 1 : mp,
      ejercitoId: (data['ejercitoId'] as num?)?.toInt() ?? 0,
      esperaSegundos: (data['esperaSegundos'] as num?)?.toInt() ?? 0,
      dificultad: kDificultades.contains(dif) ? dif! : 'medio',
      estilo: kEstilos.contains(est) ? est! : 'equilibrado',
      esBot: (data['esBot'] as bool?) ?? true,
      partidasActivas: (data['partidasActivas'] as num?)?.toInt() ?? 0,
    );
  }
}

class _BotTile extends StatelessWidget {
  final _BotResumen bot;
  final Color accent;
  final int minPartidas;
  final int maxPartidas;
  final int minEspera;
  final int maxEspera;
  final int stepEspera;
  final String nombreEjercito;
  final String iconoEjercito;
  final ValueChanged<bool> onChanged;
  final ValueChanged<int> onPartidas;
  final ValueChanged<int> onEspera;
  final VoidCallback onEjercito;
  final ValueChanged<String> onDificultad;
  final ValueChanged<String> onEstilo;
  final ValueChanged<bool> onEsBot;
  final VoidCallback onRenombrar;
  final VoidCallback onEnviarPartida;

  const _BotTile({
    required this.bot,
    required this.accent,
    required this.minPartidas,
    required this.maxPartidas,
    required this.minEspera,
    required this.maxEspera,
    required this.stepEspera,
    required this.nombreEjercito,
    required this.iconoEjercito,
    required this.onChanged,
    required this.onPartidas,
    required this.onEspera,
    required this.onEjercito,
    required this.onDificultad,
    required this.onEstilo,
    required this.onEsBot,
    required this.onRenombrar,
    required this.onEnviarPartida,
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
                    // RENOMBRAR: lápiz para editar el nombre visible del bot.
                    GestureDetector(
                      onTap: onRenombrar,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.edit_outlined,
                            size: 15, color: accent.withOpacity(0.85)),
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
                const SizedBox(height: 8),
                // DIFICULTAD: Medio / Alto / Maestro.
                Row(
                  children: [
                    const SizedBox(
                      width: 62,
                      child: Text(
                        'Dificultad',
                        style: TextStyle(
                          color: Color(0xFF6A727C),
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _PerfilChip(
                      label: 'Medio',
                      seleccionado: bot.dificultad == 'medio',
                      color: accent,
                      onTap: () => onDificultad('medio'),
                    ),
                    const SizedBox(width: 6),
                    _PerfilChip(
                      label: 'Alto',
                      seleccionado: bot.dificultad == 'alto',
                      color: const Color(0xFFE0703A),
                      onTap: () => onDificultad('alto'),
                    ),
                    const SizedBox(width: 6),
                    _PerfilChip(
                      label: 'Maestro',
                      seleccionado: bot.dificultad == 'maestro',
                      color: const Color(0xFFC9A227),
                      onTap: () => onDificultad('maestro'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // ESTILO: Equilibrado / Defensivo / Agresivo.
                Row(
                  children: [
                    const SizedBox(
                      width: 62,
                      child: Text(
                        'Estilo',
                        style: TextStyle(
                          color: Color(0xFF6A727C),
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _PerfilChip(
                            label: 'Equil.',
                            seleccionado: bot.estilo == 'equilibrado',
                            color: accent,
                            onTap: () => onEstilo('equilibrado'),
                          ),
                          _PerfilChip(
                            label: 'Defens.',
                            seleccionado: bot.estilo == 'defensivo',
                            color: const Color(0xFF3A78E0),
                            onTap: () => onEstilo('defensivo'),
                          ),
                          _PerfilChip(
                            label: 'Agres.',
                            seleccionado: bot.estilo == 'agresivo',
                            color: const Color(0xFFE0703A),
                            onTap: () => onEstilo('agresivo'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // CUENTA COMO: Bot (esBot=true) / Humano (esBot=false). Un bot
                // marcado como Humano NO descalifica las victorias "sin bots".
                Row(
                  children: [
                    const SizedBox(
                      width: 62,
                      child: Text(
                        'Cuenta como',
                        style: TextStyle(
                          color: Color(0xFF6A727C),
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _PerfilChip(
                      label: 'Bot',
                      seleccionado: bot.esBot,
                      color: accent,
                      onTap: () => onEsBot(true),
                    ),
                    const SizedBox(width: 6),
                    _PerfilChip(
                      label: 'Humano',
                      seleccionado: !bot.esBot,
                      color: const Color(0xFF3AC07A),
                      onTap: () => onEsBot(false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 6),
                _StepperEspera(
                  segundos: bot.esperaSegundos,
                  accent: accent,
                  onMenos: bot.esperaSegundos > minEspera
                      ? () => onEspera(bot.esperaSegundos - stepEspera)
                      : null,
                  onMas: bot.esperaSegundos < maxEspera
                      ? () => onEspera(bot.esperaSegundos + stepEspera)
                      : null,
                ),
                const SizedBox(height: 8),
                // ENVIAR A PARTIDA: elegir una partida pública y mandar al bot.
                GestureDetector(
                  onTap: onEnviarPartida,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent.withOpacity(0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_outlined, size: 13, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          'ENVIAR A PARTIDA',
                          style: TextStyle(
                            color: accent,
                            fontFamily: 'Cinzel',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
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

/// Hoja inferior con las PARTIDAS PÚBLICAS en espera. Permite mandar a [bot]
/// a ocupar un hueco en una de ellas. Se lee del mismo endpoint que el lobby
/// (/warzero/publicas); el servidor invalida esa caché tras cada envío.
class _SalasPublicasSheet extends StatefulWidget {
  final _BotResumen bot;
  final Color accent;

  /// Uids de todos los bots del panel (para distinguir bots de humanos).
  final Set<String> botIds;

  /// uid → alias de los bots, para mostrar quién hay ya en cada sala.
  final Map<String, String> aliasBots;

  /// Envía el bot a la sala. Devuelve true si se envió (cierra la hoja).
  final Future<bool> Function(LobbyModel sala) onEnviar;

  const _SalasPublicasSheet({
    required this.bot,
    required this.accent,
    required this.botIds,
    required this.aliasBots,
    required this.onEnviar,
  });

  @override
  State<_SalasPublicasSheet> createState() => _SalasPublicasSheetState();
}

class _SalasPublicasSheetState extends State<_SalasPublicasSheet> {
  final _api = WarZeroApi();

  bool _cargando = true;
  String? _error;
  List<LobbyModel> _salas = [];

  /// Sala a la que se está enviando el bot ahora mismo (spinner en su fila).
  String? _enviandoA;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final raw = await _api.obtenerPublicas();
      final lista = <LobbyModel>[];
      for (final d in raw) {
        try {
          final id = d['id'] as String? ?? '';
          if (id.isEmpty) continue;
          final l = LobbyModel.fromMap(id, d);
          if (!l.esPrivada) lista.add(l);
        } catch (_) {
          // Documento malformado: se ignora.
        }
      }
      // Primero las que tienen hueco; dentro de cada grupo, la más antigua
      // primero (mismo criterio que el relleno automático).
      lista.sort((a, b) {
        final la = a.estaLleno ? 1 : 0;
        final lb = b.estaLleno ? 1 : 0;
        if (la != lb) return la.compareTo(lb);
        return a.creadoEn.compareTo(b.creadoEn);
      });
      if (!mounted) return;
      setState(() {
        _salas = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _enviar(LobbyModel sala) async {
    if (_enviandoA != null) return;
    setState(() => _enviandoA = sala.id);
    final ok = await widget.onEnviar(sala);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _enviandoA = null);
    }
  }

  String _hace(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  String _ritmo(ModoTurno m) => switch (m) {
        ModoTurno.diario => 'Diaria',
        ModoTurno.turno12h => '12 h',
        _ => 'Rápida',
      };

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final alto = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: SizedBox(
        height: alto,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.public, color: accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PARTIDAS PÚBLICAS',
                      style: TextStyle(
                        color: accent,
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh, color: accent, size: 20),
                    onPressed: _cargando || _enviandoA != null ? null : _cargar,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'Elige una partida para mandar a ${widget.bot.alias} a ocupar '
                'un hueco.',
                style: const TextStyle(
                  color: Color(0xFF8A94A0),
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                ),
              ),
            ),
            const Divider(color: Color(0xFF1A2436), height: 1),
            Expanded(child: _cuerpo(accent)),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo(Color accent) {
    if (_cargando) {
      return Center(
          child: CircularProgressIndicator(color: accent, strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudieron cargar las partidas:\n$_error',
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Color(0xFFFF6060), fontFamily: 'Cinzel'),
          ),
        ),
      );
    }
    if (_salas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay partidas públicas en espera ahora mismo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8A94A0),
              fontFamily: 'Cinzel',
              fontSize: 11,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _salas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _filaSala(_salas[i], accent),
    );
  }

  Widget _filaSala(LobbyModel sala, Color accent) {
    final yaDentro = sala.jugadores.any((j) => j.uid == widget.bot.id);
    final humanos =
        sala.jugadores.where((j) => !widget.botIds.contains(j.uid)).toList();
    final bots =
        sala.jugadores.where((j) => widget.botIds.contains(j.uid)).toList();
    final sinHumanos = humanos.isEmpty;
    final huecos = sala.maxJugadores - sala.jugadores.length;
    final enviando = _enviandoA == sala.id;

    String? motivo;
    if (yaDentro) {
      motivo = 'Ya está dentro';
    } else if (sala.estaLleno) {
      motivo = 'Llena';
    } else if (sinHumanos) {
      motivo = 'Sin humanos';
    }
    final puede = motivo == null && _enviandoA == null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: motivo == null
              ? accent.withOpacity(0.35)
              : const Color(0xFF1A2436),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sala.nombre.isEmpty ? sala.id : sala.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: motivo == null
                        ? Colors.white
                        : const Color(0xFF8A94A0),
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${sala.modoPartida.icono} ${sala.modoPartida.etiqueta} · '
                  '${_ritmo(sala.modoTurno)} · ${_hace(sala.creadoEn)}',
                  style: const TextStyle(
                    color: Color(0xFF8A94A0),
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '👤 ${humanos.map((j) => j.alias).join(", ")}'
                  '${bots.isEmpty ? "" : "   🤖 ${bots.map((j) => widget.aliasBots[j.uid] ?? j.alias).join(", ")}"}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB0B8C0),
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${sala.jugadores.length}/${sala.maxJugadores}',
                style: TextStyle(
                  color: huecos > 0 ? accent : const Color(0xFF6A727C),
                  fontFamily: 'Cinzel',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              if (enviando)
                SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(color: accent, strokeWidth: 2),
                )
              else if (motivo != null)
                Text(
                  motivo,
                  style: const TextStyle(
                    color: Color(0xFF6A727C),
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                  ),
                )
              else
                GestureDetector(
                  onTap: puede ? () => _enviar(sala) : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(puede ? 0.15 : 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: accent.withOpacity(puede ? 0.6 : 0.2)),
                    ),
                    child: Text(
                      'ENVIAR',
                      style: TextStyle(
                        color: puede ? accent : const Color(0xFF6A727C),
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
            ],
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

/// Control compacto "− Ns +" para la espera antes de entrar en salas proactivas.
class _StepperEspera extends StatelessWidget {
  final int segundos;
  final Color accent;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;

  const _StepperEspera({
    required this.segundos,
    required this.accent,
    required this.onMenos,
    required this.onMas,
  });

  String get _texto {
    if (segundos <= 0) return 'Ya';
    if (segundos < 60) return '${segundos}s';
    final m = segundos ~/ 60;
    final s = segundos % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Espera sala',
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
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          child: Text(
            _texto,
            style: TextStyle(
              color: accent,
              fontFamily: 'Cinzel',
              fontWeight: FontWeight.bold,
              fontSize: 12,
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

/// Chip seleccionable para elegir dificultad / estilo de un bot. Resaltado
/// cuando está activo; atenuado cuando no.
class _PerfilChip extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final Color color;
  final VoidCallback onTap;

  const _PerfilChip({
    required this.label,
    required this.seleccionado,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              seleccionado ? color.withOpacity(0.20) : const Color(0xFF0E1626),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: seleccionado
                ? color.withOpacity(0.85)
                : const Color(0xFF1A2436),
            width: seleccionado ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: seleccionado ? color : const Color(0xFF8A94A0),
            fontFamily: 'Cinzel',
            fontSize: 10,
            fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
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
