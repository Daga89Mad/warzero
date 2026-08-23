// lib/views/sobres_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/jugador_model.dart';
import '../models/lobby_model.dart';
import '../services/settings_controller.dart';
import '../services/warzero_api.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SobresScreen
//
// Permite abrir sobres por ejército. Cada sobre entrega una carta al azar
// (ponderada por su Probabilidad), otorga Zero del ejército y, con baja
// probabilidad, puede soltar una skin legendaria. Los saldos de las 5 monedas
// se muestran arriba y se refrescan tras cada apertura.
// ─────────────────────────────────────────────────────────────────────────────
class SobresScreen extends StatefulWidget {
  const SobresScreen({super.key});

  @override
  State<SobresScreen> createState() => _SobresScreenState();
}

class _SobresScreenState extends State<SobresScreen> {
  final _api = WarZeroApi();
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  String? _error;
  Map<MonedaZero, int> _zeros = {for (final m in MonedaZero.values) m: 0};
  final Set<int> _abriendo = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await _api.obtenerPorcentajes(_uid);
      final zerosRaw = (data?['zeros'] as Map?) ?? {};
      final zeros = <MonedaZero, int>{};
      for (final m in MonedaZero.values) {
        zeros[m] = (zerosRaw[m.firestoreKey] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _zeros = zeros;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _abrir(int ejercitoId) async {
    if (_abriendo.contains(ejercitoId)) return;
    setState(() => _abriendo.add(ejercitoId));
    try {
      final res = await _api.abrirSobre(_uid, ejercitoId);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _ResultadoSobreDialog(res: res),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor: const Color(0xFF7A1010),
      ));
    } finally {
      if (mounted) setState(() => _abriendo.remove(ejercitoId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('SOBRES',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: war.primario)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: war.primario))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: TextStyle(
                          fontFamily: 'Cinzel', color: war.textoTenue)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _MonedasBar(zeros: _zeros),
                    const SizedBox(height: 22),
                    Text('ABRE UN SOBRE',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            letterSpacing: 2,
                            color: war.textoTenue)),
                    const SizedBox(height: 12),
                    for (final e in kEjercitos) ...[
                      _SobreCard(
                        ejercito: e,
                        zero: _zeros[MonedaZeroExt.fromEjercito(e.id)] ?? 0,
                        abriendo: _abriendo.contains(e.id),
                        onAbrir: () => _abrir(e.id),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BARRA DE MONEDAS
// ─────────────────────────────────────────────────────────────
class _MonedasBar extends StatelessWidget {
  final Map<MonedaZero, int> zeros;
  const _MonedasBar({required this.zeros});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: war.borde.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final m in MonedaZero.values)
            Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m.color.withOpacity(0.25),
                    border: Border.all(color: m.color, width: 1.2),
                  ),
                ),
                const SizedBox(height: 5),
                Text('${zeros[m] ?? 0}',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: m.color)),
                const SizedBox(height: 2),
                Text(m.label.replaceFirst('Zero ', '').toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 5.5,
                        letterSpacing: 0.5,
                        color: war.textoTenue)),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TARJETA DE SOBRE (por ejército)
// ─────────────────────────────────────────────────────────────
class _SobreCard extends StatelessWidget {
  final EjercitoInfo ejercito;
  final int zero;
  final bool abriendo;
  final VoidCallback onAbrir;

  const _SobreCard({
    required this.ejercito,
    required this.zero,
    required this.abriendo,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final color = MonedaZeroExt.fromEjercito(ejercito.id).color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Text(ejercito.icono, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ejercito.nombre.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        letterSpacing: 1,
                        color: war.texto)),
                const SizedBox(height: 3),
                Text('$zero ${MonedaZeroExt.fromEjercito(ejercito.id).label}',
                    style: TextStyle(
                        fontFamily: 'Cinzel', fontSize: 8, color: color)),
              ],
            ),
          ),
          GestureDetector(
            onTap: abriendo ? null : onAbrir,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(abriendo ? 0.06 : 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.7), width: 1),
              ),
              child: abriendo
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6, color: color))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.card_giftcard, size: 14, color: color),
                      const SizedBox(width: 6),
                      Text('ABRIR',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO RESULTADO DEL SOBRE
// ─────────────────────────────────────────────────────────────
class _ResultadoSobreDialog extends StatelessWidget {
  final Map<String, dynamic> res;
  const _ResultadoSobreDialog({required this.res});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final nombre = res['nombre']?.toString() ?? 'Carta';
    final imagen = res['imagen']?.toString() ?? '';
    final nueva = res['nueva'] == true;
    final veces = (res['vecesObtenida'] as num?)?.toInt() ?? 0;
    final zeroGanado = (res['zeroGanado'] as num?)?.toInt() ?? 0;
    final skinLeg = res['skinLegendaria']?.toString();
    final tieneLeg = skinLeg != null && skinLeg.isNotEmpty;

    return Dialog(
      backgroundColor: war.superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(nueva ? '¡CARTA NUEVA!' : 'DUPLICADA',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                    color: nueva ? war.secundario : war.primario)),
            const SizedBox(height: 16),
            Container(
              width: 130,
              height: 178,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: war.primario.withOpacity(0.5), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: imagen.isNotEmpty
                    ? Image.network(imagen,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _ph(war))
                    : _ph(war),
              ),
            ),
            const SizedBox(height: 14),
            Text(nombre.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: war.texto)),
            const SizedBox(height: 6),
            Text('La tienes $veces ${veces == 1 ? "vez" : "veces"}',
                style: TextStyle(
                    fontFamily: 'Cinzel', fontSize: 9, color: war.textoTenue)),
            const SizedBox(height: 10),
            if (zeroGanado > 0)
              _chip(context, '+$zeroGanado Zero', war.primario),
            if (tieneLeg) ...[
              const SizedBox(height: 8),
              _chip(context, '✦ ¡SKIN LEGENDARIA DESBLOQUEADA!',
                  const Color(0xFFFF9500)),
            ],
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: war.primario.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: war.primario.withOpacity(0.6)),
                ),
                child: Text('CONTINUAR',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: war.primario)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String txt, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(txt,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color)),
      );

  Widget _ph(dynamic war) => Container(
        color: war.fondo,
        child: Icon(Icons.image_outlined, size: 30, color: war.borde),
      );
}
