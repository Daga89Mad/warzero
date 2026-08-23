// lib/views/centro_mando_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/jugador_model.dart';
import '../models/lobby_model.dart';
import '../services/settings_controller.dart';
import '../services/warzero_api.dart';
import 'apertura_sobre_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CentroMandoScreen
//
// Centro de operaciones para abrir sobres. Se paga con CRISTALES ZERO:
//   • Sobre normal   → 10 (4 cartas)
//   • Sobre especial → 15 (6 cartas)
//   • Doble normal   → 18 (8 cartas)
// El sobre de un ejército se paga con su Cristal + el Cristal Puro (el Puro
// cubre lo que falte). El Puro se recarga +10 cada 12 h (al entrar aquí).
// ─────────────────────────────────────────────────────────────────────────────
class CentroMandoScreen extends StatefulWidget {
  const CentroMandoScreen({super.key});

  @override
  State<CentroMandoScreen> createState() => _CentroMandoScreenState();
}

class _CentroMandoScreenState extends State<CentroMandoScreen> {
  final _api = WarZeroApi();
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  String? _error;
  Map<MonedaZero, int> _cristales = {for (final m in MonedaZero.values) m: 0};
  int _proximaPuraMs = 0; // ms hasta la próxima recarga de energía pura
  int? _abriendoEjercito;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      // Al entrar, intenta recargar la energía pura (cada 12 h).
      int proxima = 0;
      try {
        final rec = await _api.reclamarEnergiaPura(_uid);
        proxima = (rec['proximaMs'] as num?)?.toInt() ?? 0;
      } catch (_) {/* si falla la recarga, seguimos con los saldos */}

      final data = await _api.obtenerPorcentajes(_uid);
      final zerosRaw = (data?['zeros'] as Map?) ?? {};
      final cristales = <MonedaZero, int>{};
      for (final m in MonedaZero.values) {
        cristales[m] = (zerosRaw[m.firestoreKey] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _cristales = cristales;
        _proximaPuraMs = proxima;
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

  int get _puro => _cristales[MonedaZero.puro] ?? 0;
  int _disponiblePara(int ejercitoId) =>
      (_cristales[MonedaZeroExt.fromEjercito(ejercitoId)] ?? 0) + _puro;

  /// Ruta del asset del sobre según ejército y tipo.
  ///   normal/doble → assets/images/Sobre<Color>.png
  ///   especial     → assets/images/SobreEspecial<Color>.png
  /// donde <Color> = Celeste/Escarlata/Fuego/Natural.
  String _imagenSobre(int ejercitoId, String tipo) {
    final color = MonedaZeroExt.fromEjercito(ejercitoId).colorNombre;
    final prefijo = tipo == 'especial' ? 'SobreEspecial' : 'Sobre';
    return 'assets/images/$prefijo$color.png';
  }

  Future<void> _abrir(EjercitoInfo ejercito, String tipo) async {
    if (_abriendoEjercito != null) return;
    setState(() => _abriendoEjercito = ejercito.id);
    try {
      final res = await _api.abrirSobre(_uid, ejercito.id, tipo: tipo);
      final cartas = ((res['cartas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;

      // Guard: si no llegan cartas (p. ej. backend desactualizado o pool
      // vacío), no abrimos la animación en blanco; avisamos.
      if (cartas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'El sobre no devolvió cartas. Revisa el backend '
              'o la probabilidad de las cartas del ejército.',
              style: TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
          backgroundColor: Color(0xFF7A1010),
        ));
        await _cargar();
        return;
      }

      final acento = MonedaZeroExt.fromEjercito(ejercito.id).color;
      final color = MonedaZeroExt.fromEjercito(ejercito.id).colorNombre;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AperturaSobreScreen(
          cartas: cartas,
          acento: acento,
          imagenSobre: _imagenSobre(ejercito.id, tipo),
          fondo: 'assets/images/Fondo$color.png',
          titulo: 'SOBRE ${ejercito.nombre}',
        ),
      ));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(fontFamily: 'Cinzel', fontSize: 10)),
        backgroundColor: const Color(0xFF7A1010),
      ));
    } finally {
      if (mounted) setState(() => _abriendoEjercito = null);
    }
  }

  String get _proximaTexto {
    if (_proximaPuraMs <= 0) return 'Energía pura lista';
    final h = _proximaPuraMs ~/ 3600000;
    final m = (_proximaPuraMs % 3600000) ~/ 60000;
    return 'Próxima energía pura en ${h}h ${m}m';
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
        title: Text('CENTRO DE MANDO',
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
                    _CristalesBar(
                        cristales: _cristales, proximaTexto: _proximaTexto),
                    const SizedBox(height: 22),
                    Text('ABRIR SOBRES',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 8,
                            letterSpacing: 2,
                            color: war.textoTenue)),
                    const SizedBox(height: 12),
                    for (final e in kEjercitos) ...[
                      _EjercitoSobres(
                        ejercito: e,
                        disponible: _disponiblePara(e.id),
                        abriendo: _abriendoEjercito == e.id,
                        bloqueadoOtro: _abriendoEjercito != null &&
                            _abriendoEjercito != e.id,
                        onAbrir: (tipo) => _abrir(e, tipo),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BARRA DE CRISTALES ZERO (+ Puro destacado y recarga)
// ─────────────────────────────────────────────────────────────
class _CristalesBar extends StatelessWidget {
  final Map<MonedaZero, int> cristales;
  final String proximaTexto;
  const _CristalesBar({required this.cristales, required this.proximaTexto});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: war.borde.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('CRISTALES ZERO',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 8,
                    letterSpacing: 2,
                    color: war.textoTenue)),
            const Spacer(),
            Text(proximaTexto,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 7,
                    color: MonedaZero.puro.color)),
          ]),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final m in MonedaZero.values)
                Column(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.color.withOpacity(0.25),
                        border: Border.all(color: m.color, width: 1.4),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text('${cristales[m] ?? 0}',
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: m.color)),
                    const SizedBox(height: 1),
                    Text(m.colorNombre.toUpperCase(),
                        style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: 6,
                            letterSpacing: 0.5,
                            color: war.textoTenue)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SOBRES DE UN EJÉRCITO (3 botones)
// ─────────────────────────────────────────────────────────────
class _EjercitoSobres extends StatelessWidget {
  final EjercitoInfo ejercito;
  final int disponible; // cristales del ejército + puro
  final bool abriendo;
  final bool bloqueadoOtro;
  final void Function(String tipo) onAbrir;

  const _EjercitoSobres({
    required this.ejercito,
    required this.disponible,
    required this.abriendo,
    required this.bloqueadoOtro,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final color = MonedaZeroExt.fromEjercito(ejercito.id).color;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(ejercito.icono, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(ejercito.nombre.toUpperCase(),
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    letterSpacing: 1,
                    color: war.texto)),
            const Spacer(),
            Icon(Icons.diamond, size: 11, color: color),
            const SizedBox(width: 3),
            Text('$disponible',
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _BotonSobre(
                    titulo: 'NORMAL',
                    coste: 10,
                    cartas: 4,
                    color: color,
                    disponible: disponible,
                    ocupado: abriendo || bloqueadoOtro,
                    cargando: abriendo,
                    onTap: () => onAbrir('normal'))),
            const SizedBox(width: 8),
            Expanded(
                child: _BotonSobre(
                    titulo: 'ESPECIAL',
                    coste: 15,
                    cartas: 6,
                    color: color,
                    disponible: disponible,
                    ocupado: abriendo || bloqueadoOtro,
                    cargando: abriendo,
                    onTap: () => onAbrir('especial'))),
            const SizedBox(width: 8),
            Expanded(
                child: _BotonSobre(
                    titulo: 'DOBLE',
                    coste: 18,
                    cartas: 8,
                    color: color,
                    disponible: disponible,
                    ocupado: abriendo || bloqueadoOtro,
                    cargando: abriendo,
                    onTap: () => onAbrir('doble'))),
          ]),
        ],
      ),
    );
  }
}

class _BotonSobre extends StatelessWidget {
  final String titulo;
  final int coste;
  final int cartas;
  final Color color;
  final int disponible;
  final bool ocupado;
  final bool cargando;
  final VoidCallback onTap;

  const _BotonSobre({
    required this.titulo,
    required this.coste,
    required this.cartas,
    required this.color,
    required this.disponible,
    required this.ocupado,
    required this.cargando,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final asequible = disponible >= coste;
    final activo = asequible && !ocupado;
    return GestureDetector(
      onTap: activo ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: activo ? color.withOpacity(0.14) : const Color(0xFF0C1622),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color:
                  activo ? color.withOpacity(0.7) : war.borde.withOpacity(0.4),
              width: 1),
        ),
        child: Column(
          children: [
            Text(titulo,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.bold,
                    color: activo ? color : war.textoTenue)),
            const SizedBox(height: 5),
            if (cargando)
              SizedBox(
                  height: 14,
                  width: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 1.5, color: color))
            else ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.diamond,
                    size: 10, color: asequible ? color : war.textoTenue),
                const SizedBox(width: 2),
                Text('$coste',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: asequible ? color : war.textoTenue)),
              ]),
              const SizedBox(height: 1),
              Text('$cartas cartas',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 6.5,
                      color: war.textoTenue)),
            ],
          ],
        ),
      ),
    );
  }
}
