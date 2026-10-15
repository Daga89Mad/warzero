// lib/views/torneos_screen.dart
//
// MODO TORNEO · vista del jugador. Muestra el torneo vigente, sus fechas y
// rondas, permite apuntarse/borrarse mientras la inscripción esté abierta y,
// cuando el editor ha sorteado la ronda, los grupos (resaltando los propios).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:warzero/models/modo_partida.dart';
import 'package:warzero/models/torneo_model.dart';
import 'package:warzero/services/settings_controller.dart';
import 'package:warzero/services/torneos_service.dart';

const Color _kAcento = Color(0xFFE04444);

class TorneosScreen extends StatefulWidget {
  /// Estado ya cargado en la pantalla JUGAR (evita una segunda espera).
  final TorneoVigente? inicial;
  const TorneosScreen({super.key, this.inicial});

  @override
  State<TorneosScreen> createState() => _TorneosScreenState();
}

class _TorneosScreenState extends State<TorneosScreen> {
  final _svc = TorneosService();
  TorneoVigente? _v;
  List<GrupoTorneo> _grupos = [];
  bool _cargando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _v = widget.inicial;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final v = await _svc.vigente();
    var grupos = <GrupoTorneo>[];
    if (v.hayTorneo && v.gruposSorteados) {
      try {
        grupos = await _svc.grupos(v.torneo!.id, ronda: v.torneo!.rondaActual);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _v = v;
      _grupos = grupos;
      _cargando = false;
    });
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final v = _v;
    final t = v?.torneo;

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text('TORNEO',
            style: TextStyle(
                fontSize: 14,
                fontFamily: 'Cinzel',
                letterSpacing: 3,
                color: war.primario)),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando) const LinearProgressIndicator(minHeight: 2),
            if (!_cargando && t == null)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Text('No hay torneos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Cinzel', color: war.textoTenue)),
              ),
            if (t != null) ...[
              Text(t.nombre,
                  style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: _kAcento)),
              if (t.descripcion.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(t.descripcion, style: TextStyle(color: war.texto, height: 1.4)),
              ],
              const SizedBox(height: 16),
              _Fechas(t: t),
              const SizedBox(height: 16),
              _BotonInscripcion(v: v!, enviando: _enviando, onTap: _alternarInscripcion),
              const SizedBox(height: 24),
              if (t.premios.isNotEmpty) ...[
                _Titulo('PREMIOS'),
                _Premios(premios: t.premios),
                const SizedBox(height: 16),
              ],
              _Titulo('RONDAS'),
              for (final r in t.rondas) _RondaInfo(ronda: r, esUltima: r == t.rondas.last),
              if (_grupos.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Titulo('TUS GRUPOS · RONDA ${t.rondaActual}'),
                GruposTorneoLista(
                  grupos: _grupos,
                  ronda: t.rondaActual - 1 < t.rondas.length ? t.rondas[t.rondaActual - 1] : null,
                  soloUid: FirebaseAuth.instance.currentUser?.uid,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
                color: context.war.primario)),
      );
}

class _Fechas extends StatelessWidget {
  final TorneoModel t;
  const _Fechas({required this.t});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    Widget fila(IconData i, String l, DateTime? d) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(i, size: 16, color: war.textoTenue),
            const SizedBox(width: 8),
            Expanded(child: Text(l, style: TextStyle(fontSize: 12, color: war.textoTenue))),
            Text(fechaTorneo(d), style: TextStyle(fontSize: 12, color: war.texto)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kAcento.withOpacity(0.25)),
      ),
      child: Column(children: [
        fila(Icons.how_to_reg_outlined, 'Abre inscripción', t.inicioInscripcion),
        fila(Icons.lock_clock_outlined, 'Cierra inscripción', t.finInscripcion),
        fila(Icons.emoji_events_outlined, 'Comienza el torneo', t.inicioTorneo),
      ]),
    );
  }
}

class _BotonInscripcion extends StatelessWidget {
  final TorneoVigente v;
  final bool enviando;
  final VoidCallback onTap;
  const _BotonInscripcion({required this.v, required this.enviando, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    String texto;
    bool activo;
    if (v.inscripcionPendiente) {
      texto = 'INSCRIPCIÓN DESDE EL ${fechaTorneo(v.torneo?.inicioInscripcion)}';
      activo = false;
    } else if (v.inscripcionAbierta) {
      texto = v.inscrito ? 'ANULAR INSCRIPCIÓN' : 'APUNTARSE';
      activo = true;
    } else {
      texto = v.inscrito ? 'ESTÁS INSCRITO · INSCRIPCIÓN CERRADA' : 'INSCRIPCIÓN CERRADA';
      activo = false;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 48,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: v.inscrito && activo ? war.superficie : _kAcento,
            foregroundColor: v.inscrito && activo ? _kAcento : Colors.white,
            side: const BorderSide(color: _kAcento),
            disabledBackgroundColor: war.superficie,
            disabledForegroundColor: war.textoTenue,
          ),
          onPressed: activo && !enviando ? onTap : null,
          child: enviando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cinzel', letterSpacing: 1.5, fontSize: 12)),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '${v.inscritos} ${v.inscritos == 1 ? 'jugador inscrito' : 'jugadores inscritos'}'
        '${v.inscrito ? ' · tú incluido' : ''}',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: war.textoTenue),
      ),
    ]);
  }
}

class _Premios extends StatelessWidget {
  final List<PremioTorneo> premios;
  const _Premios({required this.premios});

  static const _oro = Color(0xFFE0B040);

  Color _colorPuesto(int puesto) {
    switch (puesto) {
      case 1:
        return _oro;
      case 2:
        return const Color(0xFFB8C0CC);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return _kAcento;
    }
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final hayExternos = premios.any((p) => p.tieneExterno);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final p in premios)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: war.superficie,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _colorPuesto(p.desde).withOpacity(0.5)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 64,
              child: Column(children: [
                Icon(Icons.emoji_events, color: _colorPuesto(p.desde), size: 22),
                const SizedBox(height: 2),
                Text(p.puestos,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _colorPuesto(p.desde))),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final parte in p.partesApp)
                  Text('• $parte',
                      style: TextStyle(fontSize: 12, color: war.texto, height: 1.5)),
                if (p.tieneExterno)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.card_giftcard, size: 14, color: _oro),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(p.externo,
                            style: const TextStyle(
                                fontSize: 12, color: _oro, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      Text(
        'Los premios del juego se reciben automáticamente al terminar el torneo.'
        '${hayExternos ? ' Los marcados con 🎁 los entrega la organización.' : ''}',
        style: TextStyle(fontSize: 11, color: war.textoTenue, height: 1.4),
      ),
    ]);
  }
}

class _RondaInfo extends StatelessWidget {
  final RondaTorneo ronda;
  final bool esUltima;
  const _RondaInfo({required this.ronda, required this.esUltima});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(esUltima ? 'RONDA ${ronda.numero} · FINAL' : 'RONDA ${ronda.numero}',
            style: TextStyle(
                fontFamily: 'Cinzel', fontWeight: FontWeight.bold, color: war.texto)),
        const SizedBox(height: 4),
        for (final p in ronda.partidas)
          Text('• ${p.resumen}', style: TextStyle(fontSize: 12, color: war.texto, height: 1.5)),
        const SizedBox(height: 4),
        Text(
          esUltima
              ? 'Gana quien más PC sume.'
              : 'Pasan los ${ronda.clasifican} con más PC.',
          style: TextStyle(fontSize: 11, color: war.textoTenue),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LISTA DE GRUPOS (compartida con la edición de torneos)
// ═══════════════════════════════════════════════════════════════════════════

/// Grupos agrupados por partida de la ronda. Con [soloUid] muestra solo los
/// grupos donde está ese jugador (vista del jugador).
class GruposTorneoLista extends StatelessWidget {
  final List<GrupoTorneo> grupos;
  final RondaTorneo? ronda;
  final String? soloUid;

  const GruposTorneoLista({super.key, required this.grupos, this.ronda, this.soloUid});

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
                  fontFamily: 'Cinzel', fontSize: 11, letterSpacing: 1, color: _kAcento),
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
                Text(
                  g.descansa ? 'DESCANSA (pasa sin jugar)' : 'Grupo ${g.grupo} · ${g.jugadores.length} jugadores',
                  style: TextStyle(fontSize: 11, color: war.textoTenue),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (var i = 0; i < g.jugadores.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: g.jugadores[i] == soloUid ? _kAcento.withOpacity(0.18) : null,
                        border: Border.all(color: war.borde),
                      ),
                      child: Text(g.nombre(i), style: TextStyle(fontSize: 11, color: war.texto)),
                    ),
                ]),
              ]),
            ),
        ],
      ],
    );
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
