// lib/views/trofeos_screen.dart

import 'package:flutter/material.dart';

import '../models/trofeo_model.dart';
import '../services/settings_controller.dart';
import '../services/trofeos_service.dart';

/// Pantalla de TROFEOS de un jugador. Muestra todos los trofeos activos, con los
/// conseguidos arriba y los pendientes debajo, y una cabecera con el porcentaje.
///
/// Sirve tanto para el perfil propio como para el público (solo cambia el [uid]);
/// es de solo lectura en ambos casos.
class TrofeosScreen extends StatefulWidget {
  final String uid;

  /// Alias a mostrar en la cabecera ("Trofeos de X"). Vacío = "Mis trofeos".
  final String alias;

  const TrofeosScreen({super.key, required this.uid, this.alias = ''});

  @override
  State<TrofeosScreen> createState() => _TrofeosScreenState();
}

class _TrofeosScreenState extends State<TrofeosScreen> {
  final _svc = TrofeosService();

  bool _loading = true;
  TrofeosResult _data = TrofeosResult.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _svc.obtener(widget.uid);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    final conseguidos =
        _data.trofeos.where((t) => t.conseguido).toList(growable: false);
    final pendientes =
        _data.trofeos.where((t) => !t.conseguido).toList(growable: false);

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('TROFEOS',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: war.primario)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: war.primario),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: war.primario))
          : RefreshIndicator(
              onRefresh: _load,
              color: war.primario,
              backgroundColor: war.superficie,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _Cabecera(
                    alias: widget.alias,
                    conseguidos: _data.conseguidos,
                    total: _data.total,
                    porcentaje: _data.porcentaje,
                  ),
                  const SizedBox(height: 24),
                  if (_data.total == 0)
                    _Vacio(war: war)
                  else ...[
                    _SectionLabel('CONSEGUIDOS · ${conseguidos.length}', war),
                    const SizedBox(height: 12),
                    if (conseguidos.isEmpty)
                      _NotaTenue('Aún no has conseguido ningún trofeo.', war)
                    else
                      for (final t in conseguidos) ...[
                        _TrofeoTile(trofeo: t, war: war),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 16),
                    _SectionLabel('PENDIENTES · ${pendientes.length}', war),
                    const SizedBox(height: 12),
                    if (pendientes.isEmpty)
                      _NotaTenue('¡Los has conseguido todos!', war)
                    else
                      for (final t in pendientes) ...[
                        _TrofeoTile(trofeo: t, war: war),
                        const SizedBox(height: 10),
                      ],
                  ],
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CABECERA — anillo de progreso + conseguidos/total
// ─────────────────────────────────────────────────────────────
class _Cabecera extends StatelessWidget {
  final String alias;
  final int conseguidos;
  final int total;
  final int porcentaje;

  const _Cabecera({
    required this.alias,
    required this.conseguidos,
    required this.total,
    required this.porcentaje,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const oro = Color(0xFFE0B040);
    final titulo =
        alias.trim().isEmpty ? 'MIS TROFEOS' : alias.trim().toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: oro.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : (porcentaje / 100.0),
                    strokeWidth: 6,
                    backgroundColor: war.borde.withOpacity(0.4),
                    valueColor: const AlwaysStoppedAnimation<Color>(oro),
                  ),
                ),
                Text('$porcentaje%',
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: oro)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: war.texto)),
                const SizedBox(height: 6),
                Text('$conseguidos de $total trofeos',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        color: war.textoTenue)),
              ],
            ),
          ),
          const Text('🏆', style: TextStyle(fontSize: 30)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TILE de un trofeo (conseguido o pendiente)
// ─────────────────────────────────────────────────────────────
class _TrofeoTile extends StatelessWidget {
  final TrofeoModel trofeo;
  final WarColors war;

  const _TrofeoTile({required this.trofeo, required this.war});

  @override
  Widget build(BuildContext context) {
    final logrado = trofeo.conseguido;
    const oro = Color(0xFFE0B040);
    final accent = logrado ? oro : war.textoTenue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: logrado ? war.superficie : war.fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: accent.withOpacity(logrado ? 0.45 : 0.18), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medalla / icono. En pendientes se muestra tenue (bloqueado).
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(logrado ? 0.18 : 0.08),
              border: Border.all(
                  color: accent.withOpacity(logrado ? 0.6 : 0.25), width: 1.2),
            ),
            child: Opacity(
              opacity: logrado ? 1 : 0.45,
              child: Text(trofeo.icono, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trofeo.nombre.isEmpty ? 'Trofeo' : trofeo.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: logrado ? war.texto : war.textoTenue),
                      ),
                    ),
                    if (logrado)
                      const Icon(Icons.verified, size: 16, color: oro)
                    else
                      Icon(Icons.lock_outline, size: 14, color: war.borde),
                  ],
                ),
                if (trofeo.descripcion.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    trofeo.descripcion.trim(),
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        height: 1.4,
                        color: war.textoTenue),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  trofeo.condicionTexto,
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 9,
                      letterSpacing: 0.5,
                      color: accent.withOpacity(logrado ? 0.9 : 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AUXILIARES
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final WarColors war;
  const _SectionLabel(this.text, this.war);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Container(height: 1, color: war.borde.withOpacity(0.5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  letterSpacing: 2,
                  color: war.textoTenue)),
        ),
        Expanded(
            child: Container(height: 1, color: war.borde.withOpacity(0.5))),
      ],
    );
  }
}

class _NotaTenue extends StatelessWidget {
  final String texto;
  final WarColors war;
  const _NotaTenue(this.texto, this.war);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(texto,
          style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 10,
              color: war.textoTenue.withOpacity(0.8))),
    );
  }
}

class _Vacio extends StatelessWidget {
  final WarColors war;
  const _Vacio({required this.war});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text('🏆', style: TextStyle(fontSize: 40, color: war.textoTenue)),
          const SizedBox(height: 12),
          Text('Todavía no hay trofeos disponibles.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Cinzel', fontSize: 11, color: war.textoTenue)),
        ],
      ),
    );
  }
}
