import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/settings_controller.dart';
import '../services/warzero_api.dart'; // ajusta la ruta si tu api está en otra carpeta

/// Criterio de ordenación del ranking.
enum RankingOrden { experiencia, victorias }

extension on RankingOrden {
  String get apiValue =>
      this == RankingOrden.victorias ? 'victorias' : 'experiencia';
}

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final _api = WarZeroApi();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  RankingOrden _orden = RankingOrden.experiencia;

  bool _cargando = true;
  String? _error;
  int _miPosicion = 0;
  List<Map<String, dynamic>> _alrededor = const [];
  List<Map<String, dynamic>> _topDiez = const [];

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
      final data = await _api.obtenerRanking(_uid, orden: _orden.apiValue);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar el ranking.';
        });
        return;
      }
      setState(() {
        _miPosicion = (data['miPosicion'] as num?)?.toInt() ?? 0;
        _alrededor = ((data['alrededor'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _topDiez = ((data['topDiez'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'Error: $e';
      });
    }
  }

  void _cambiarOrden(RankingOrden nuevo) {
    if (nuevo == _orden) return;
    setState(() => _orden = nuevo);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: war.fondo,
        appBar: AppBar(
          backgroundColor: war.superficie,
          iconTheme: IconThemeData(color: war.primario),
          title: Text('RANKING',
              style: TextStyle(
                  fontFamily: 'Cinzel', letterSpacing: 2, color: war.primario)),
          bottom: TabBar(
            labelColor: war.primario,
            unselectedLabelColor: war.textoTenue,
            indicatorColor: war.primario,
            tabs: const [
              Tab(text: 'MI POSICIÓN'),
              Tab(text: 'TOP 10'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargar,
            ),
          ],
        ),
        body: Column(
          children: [
            _OrdenToggle(
              orden: _orden,
              onChanged: _cargando ? null : _cambiarOrden,
            ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorView(mensaje: _error!, onReintentar: _cargar)
                      : TabBarView(
                          children: [
                            _ListaRanking(
                              filas: _alrededor,
                              cabecera: _miPosicion > 0
                                  ? 'Tu posición: #$_miPosicion'
                                  : null,
                            ),
                            _ListaRanking(filas: _topDiez),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOGGLE DE CRITERIO
// ─────────────────────────────────────────────────────────────
class _OrdenToggle extends StatelessWidget {
  final RankingOrden orden;
  final void Function(RankingOrden)? onChanged;
  const _OrdenToggle({required this.orden, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: war.superficie.withOpacity(0.4),
      child: Row(
        children: [
          Text('ORDENAR POR',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: war.textoTenue)),
          const Spacer(),
          _SegBtn(
            label: 'EXPERIENCIA',
            seleccionado: orden == RankingOrden.experiencia,
            onTap: onChanged == null
                ? null
                : () => onChanged!(RankingOrden.experiencia),
          ),
          const SizedBox(width: 6),
          _SegBtn(
            label: 'VICTORIAS',
            seleccionado: orden == RankingOrden.victorias,
            onTap: onChanged == null
                ? null
                : () => onChanged!(RankingOrden.victorias),
          ),
        ],
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final VoidCallback? onTap;
  const _SegBtn(
      {required this.label, required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: seleccionado ? war.primario.withOpacity(0.16) : war.fondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionado ? war.primario : war.borde.withOpacity(0.4),
            width: seleccionado ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 8,
            letterSpacing: 1,
            fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
            color: seleccionado ? war.primario : war.textoTenue,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA
// ─────────────────────────────────────────────────────────────
class _ListaRanking extends StatelessWidget {
  final List<Map<String, dynamic>> filas;
  final String? cabecera;
  const _ListaRanking({required this.filas, this.cabecera});

  @override
  Widget build(BuildContext context) {
    if (filas.isEmpty) {
      return const Center(child: Text('Sin datos de ranking.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      itemCount: filas.length + (cabecera != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (cabecera != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              cabecera!,
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 14,
                letterSpacing: 1,
                color: context.war.primario,
              ),
            ),
          );
        }
        final fila = filas[index - (cabecera != null ? 1 : 0)];
        return _RankRow(fila: fila);
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  final Map<String, dynamic> fila;
  const _RankRow({required this.fila});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final esYo = fila['esYo'] == true;
    final pos = (fila['posicion'] as num?)?.toInt() ?? 0;
    final alias = (fila['alias'] as String?)?.trim();
    final nombre = (alias == null || alias.isEmpty) ? 'Jugador' : alias;
    final nivel = (fila['nivel'] as num?)?.toInt() ?? 1;
    final exp = (fila['experiencia'] as num?)?.toInt() ?? 0;
    final vic = (fila['victorias'] as num?)?.toInt() ?? 0;
    final der = (fila['derrotas'] as num?)?.toInt() ?? 0;
    final img = (fila['imagenPerfil'] as String?) ?? '';

    final primario = war.primario;
    final tenue = war.textoTenue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color:
            esYo ? primario.withOpacity(0.14) : war.superficie.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: esYo ? primario : primario.withOpacity(0.15),
          width: esYo ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Posición.
          SizedBox(
            width: 38,
            child: Text(
              '#$pos',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: pos <= 3 ? primario : tenue,
              ),
            ),
          ),
          // Avatar.
          _Avatar(url: img, color: primario),
          const SizedBox(width: 10),
          // Alias + nivel.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: war.texto,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Nivel $nivel · $exp XP',
                    style: TextStyle(fontSize: 12, color: tenue)),
              ],
            ),
          ),
          // Victorias / derrotas.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$vic V',
                  style: const TextStyle(
                      color: Color(0xFF4ABB58),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              Text('$der D',
                  style: const TextStyle(
                      color: Color(0xFFC04040),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final Color color;
  const _Avatar({required this.url, required this.color});

  @override
  Widget build(BuildContext context) {
    const size = 38.0;
    final tieneImg = url.startsWith('http');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5)),
        color: color.withOpacity(0.12),
      ),
      clipBehavior: Clip.antiAlias,
      child: tieneImg
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.person, color: color, size: 22),
            )
          : Icon(Icons.person, color: color, size: 22),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;
  const _ErrorView({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Color(0xFFC04040)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SelectableText(mensaje, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
