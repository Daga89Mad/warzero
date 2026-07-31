// lib/screens/alianza_screen.dart

import 'package:flutter/material.dart';

import '../services/warzero_api.dart';
import '../models/alianza_estado.dart';

/// Pantalla de ALIANZA (partidas de 4+ jugadores).
///
/// - Si NO tienes alianza activa: lista de jugadores; eliges uno e indicas
///   cuántos turnos dura la alianza → se envía la propuesta.
/// - Si tienes una propuesta saliente pendiente: se muestra a la espera de
///   respuesta.
/// - Si ya tienes una alianza activa: se muestra tu aliado y un botón TRAICIÓN
///   (se hace efectiva al resolver el turno; tu aliado se entera después).
class AlianzaScreen extends StatefulWidget {
  final WarZeroApi api;
  final String lobbyId;
  final String miUid;

  /// Jugadores (menos tú y menos los eliminados): cada uno { uid, alias, color }.
  final List<Map<String, dynamic>> jugadores;

  /// Estado inicial `alianzas` (para pintar sin esperar a la red).
  final Map<String, dynamic> alianzasIniciales;

  const AlianzaScreen({
    super.key,
    required this.api,
    required this.lobbyId,
    required this.miUid,
    required this.jugadores,
    required this.alianzasIniciales,
  });

  @override
  State<AlianzaScreen> createState() => _AlianzaScreenState();
}

class _AlianzaScreenState extends State<AlianzaScreen> {
  static const _oro = Color(0xFFC8A860);
  static const _fondo = Color(0xFF0A1018);
  static const _panel = Color(0xFF0C1828);
  static const _rojo = Color(0xFFE06060);

  late Map<String, dynamic> _alianzas;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _alianzas = Map<String, dynamic>.from(widget.alianzasIniciales);
  }

  EstadoAlianzas get _estado => EstadoAlianzas.fromMap(_alianzas);

  String _alias(String uid) {
    for (final j in widget.jugadores) {
      if (j['uid'] == uid) return (j['alias'] ?? 'Jugador').toString();
    }
    return uid == widget.miUid ? 'Tú' : 'Jugador';
  }

  Color _color(String uid) {
    for (final j in widget.jugadores) {
      if (j['uid'] == uid && j['color'] is Color) return j['color'] as Color;
    }
    return _oro;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          error ? const Color(0xFF5A1A1A) : const Color(0xFF17324A),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _proponer(String paraUid) async {
    final turnos = await _pedirTurnos();
    if (turnos == null || !mounted) return;
    setState(() => _enviando = true);
    try {
      final r = await widget.api.proponerAlianza(
        lobbyId: widget.lobbyId,
        deUid: widget.miUid,
        paraUid: paraUid,
        turnos: turnos,
      );
      _aplicarResultado(r);
      _snack(r.mensaje.isEmpty ? 'Propuesta enviada.' : r.mensaje,
          error: !r.ok);
    } catch (e) {
      _snack('No se pudo enviar la propuesta: $e', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _traicionar() async {
    final ok = await _confirmar(
      titulo: 'Traicionar alianza',
      cuerpo: 'Al resolver este turno dejarás de ser aliado y podrás atacar. '
          'Tu aliado se enterará DESPUÉS de resolver. ¿Seguro?',
      confirmar: 'TRAICIONAR',
      peligro: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _enviando = true);
    try {
      final r = await widget.api.traicionarAlianza(
        lobbyId: widget.lobbyId,
        uid: widget.miUid,
      );
      _aplicarResultado(r);
      _snack(r.mensaje.isEmpty ? 'Traición marcada.' : r.mensaje, error: !r.ok);
    } catch (e) {
      _snack('No se pudo marcar la traición: $e', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _aplicarResultado(AlianzaResult r) {
    final est = r.estado;
    if (est != null && est['alianzas'] is Map) {
      setState(
          () => _alianzas = Map<String, dynamic>.from(est['alianzas'] as Map));
    }
  }

  Future<int?> _pedirTurnos() async {
    int turnos = 3;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _oro.withOpacity(0.4)),
          ),
          title: const Text('Duración de la alianza',
              style: TextStyle(
                  color: Color(0xFFE0D8C0),
                  fontFamily: 'Cinzel',
                  fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Cuántos turnos durará la alianza?',
                  style: TextStyle(color: Color(0xFFB0C0D0), fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pill(Icons.remove,
                      () => setLocal(() => turnos = (turnos - 1).clamp(1, 20))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('$turnos',
                        style: const TextStyle(
                            color: _oro,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cinzel')),
                  ),
                  _pill(Icons.add,
                      () => setLocal(() => turnos = (turnos + 1).clamp(1, 20))),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF9AB0C0))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(turnos),
              child: const Text('PROPONER',
                  style: TextStyle(color: _oro, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1525),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _oro.withOpacity(0.4)),
          ),
          child: Icon(icon, color: _oro, size: 20),
        ),
      );

  Future<bool?> _confirmar({
    required String titulo,
    required String cuerpo,
    required String confirmar,
    bool peligro = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: (peligro ? _rojo : _oro).withOpacity(0.5)),
          ),
          title: Text(titulo,
              style: TextStyle(
                  color: peligro ? _rojo : const Color(0xFFE0D8C0),
                  fontFamily: 'Cinzel',
                  fontSize: 16)),
          content: Text(cuerpo,
              style: const TextStyle(color: Color(0xFFB0C0D0), fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF9AB0C0))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmar,
                  style: TextStyle(
                      color: peligro ? _rojo : _oro,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final est = _estado;
    final alianza = est.alianzaDe(widget.miUid);
    final saliente = est.propuestaSalienteDe(widget.miUid);

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: const Color(0xF202050D),
        elevation: 0,
        title: const Text('ALIANZA',
            style: TextStyle(
                fontFamily: 'Cinzel',
                letterSpacing: 3,
                color: _oro,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: _oro),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: alianza != null
                ? _vistaAliado(alianza)
                : (saliente != null
                    ? _vistaPropuestaEnviada(saliente)
                    : _vistaSeleccion()),
          ),
          if (_enviando)
            Container(
              color: Colors.black38,
              child:
                  const Center(child: CircularProgressIndicator(color: _oro)),
            ),
        ],
      ),
    );
  }

  // ── Ya aliado: mostrar aliado + botón TRAICIÓN ──────────────────────────
  Widget _vistaAliado(AlianzaActiva a) {
    final otro = a.otro(widget.miUid);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.handshake, color: _oro, size: 48),
          const SizedBox(height: 12),
          Center(
            child: Text('Aliado con ${_alias(otro)}',
                style: const TextStyle(
                    color: Color(0xFFE0D8C0),
                    fontFamily: 'Cinzel',
                    fontSize: 18)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Turnos restantes: ${a.turnosRestantes}',
                style: const TextStyle(color: Color(0xFF9AD06A), fontSize: 14)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _oro.withOpacity(0.25)),
            ),
            child: const Text(
              'Mientras dure la alianza, vuestras cartas suman fuerza y comparten '
              'casilla, pero cada uno recibe la mitad de PC en las batallas. El '
              'cuartel de tu aliado sí es conquistable.',
              style: TextStyle(
                  color: Color(0xFFB0C0D0), fontSize: 12, height: 1.4),
            ),
          ),
          const Spacer(),
          _botonGrande(
            label: 'TRAICIÓN',
            icon: Icons.dangerous,
            color: _rojo,
            onTap: _enviando ? null : _traicionar,
          ),
          const SizedBox(height: 6),
          const Text(
            'La traición se aplica al resolver el turno: dejarás de ser aliado y '
            'podrás atacar. Tu aliado se enterará después.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7A8A9A), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Propuesta saliente pendiente ────────────────────────────────────────
  Widget _vistaPropuestaEnviada(PropuestaAlianza p) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hourglass_top, color: _oro, size: 48),
          const SizedBox(height: 16),
          Text('Propuesta enviada a ${_alias(p.paraUid)}',
              style: const TextStyle(
                  color: Color(0xFFE0D8C0),
                  fontFamily: 'Cinzel',
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text('Duración: ${p.turnos} turnos · esperando respuesta…',
              style: const TextStyle(color: Color(0xFF9AB0C0), fontSize: 13)),
        ],
      ),
    );
  }

  // ── Selección de jugador para proponer ──────────────────────────────────
  Widget _vistaSeleccion() {
    if (widget.jugadores.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay jugadores disponibles para aliarte.',
              style: TextStyle(color: Color(0xFF9AB0C0))),
        ),
      );
    }
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Elige un jugador para proponerle una alianza e indica cuántos turnos '
            'durará.',
            style: TextStyle(color: Color(0xFFB0C0D0), fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: widget.jugadores.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final j = widget.jugadores[i];
              final uid = j['uid'].toString();
              return InkWell(
                onTap: _enviando ? null : () => _proponer(uid),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _oro.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: _color(uid)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_alias(uid),
                            style: const TextStyle(
                                color: Color(0xFFE0D8C0),
                                fontFamily: 'Cinzel',
                                fontSize: 14)),
                      ),
                      const Icon(Icons.handshake, color: _oro, size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _botonGrande({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(onTap == null ? 0.15 : 0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.7), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontFamily: 'Cinzel',
                      fontSize: 16,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
}
