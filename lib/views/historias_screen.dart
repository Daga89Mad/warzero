// lib/views/historias_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/historia_model.dart';
import '../models/lobby_model.dart'; // kEjercitos
import '../services/warzero_api.dart';
import '../services/settings_controller.dart';
import 'historia_detalle_screen.dart';

/// Pantalla de Historias: arriba un selector por ejército y debajo la lista de
/// 10 historias de ese ejército. Cada una está bloqueada hasta conseguirla.
class HistoriasScreen extends StatefulWidget {
  const HistoriasScreen({super.key});

  @override
  State<HistoriasScreen> createState() => _HistoriasScreenState();
}

class _HistoriasScreenState extends State<HistoriasScreen> {
  final _api = WarZeroApi();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  static const int _slotsPorEjercito = 10;

  bool _loading = true;
  String? _error;
  int _ejercitoSel = kEjercitos.first.id;

  /// ejercito → (orden → historia)
  final Map<int, Map<int, HistoriaModel>> _porEjercito = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final historias = await _api.obtenerHistorias(_uid);
      final map = <int, Map<int, HistoriaModel>>{};
      for (final h in historias) {
        map.putIfAbsent(h.ejercito, () => {})[h.orden] = h;
      }
      if (!mounted) return;
      setState(() {
        _porEjercito
          ..clear()
          ..addAll(map);
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

  void _abrir(HistoriaModel h) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HistoriaDetalleScreen(historia: h)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final delEjercito = _porEjercito[_ejercitoSel] ?? const {};

    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        iconTheme: IconThemeData(color: war.primario),
        title: Text(
          'HISTORIAS',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Cinzel',
            letterSpacing: 3,
            color: war.primario,
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in kEjercitos)
                  _FilterChip(
                    label: '${e.icono} ${e.nombre.toUpperCase()}',
                    selected: _ejercitoSel == e.id,
                    onTap: () => setState(() => _ejercitoSel = e.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_loading)
            Expanded(
              child: Center(
                child: CircularProgressIndicator(color: war.primario),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No se pudieron cargar las historias.\n$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: war.textoTenue,
                      fontFamily: 'Cinzel',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _slotsPorEjercito,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final orden = i + 1;
                  final h = delEjercito[orden];
                  final desbloqueada = h != null && h.desbloqueada;
                  return _HistoriaTile(
                    numero: orden,
                    titulo: desbloqueada ? h.titulo : null,
                    porDefecto: desbloqueada && h.porDefecto,
                    onTap: desbloqueada ? () => _abrir(h) : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TILE DE HISTORIA
// ─────────────────────────────────────────────────────────────
class _HistoriaTile extends StatelessWidget {
  final int numero;

  /// null → historia bloqueada.
  final String? titulo;

  /// Historia desbloqueada para todos por defecto (etiqueta informativa).
  final bool porDefecto;
  final VoidCallback? onTap;

  const _HistoriaTile({
    required this.numero,
    this.titulo,
    this.porDefecto = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final bloqueada = titulo == null;
    final accent = bloqueada ? war.textoTenue : war.primario;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent.withOpacity(bloqueada ? 0.12 : 0.35),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$numero.',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Cinzel',
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                bloqueada ? 'Historia bloqueada' : titulo!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.5,
                  color: bloqueada ? war.textoTenue : war.texto,
                  fontStyle: bloqueada ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (porDefecto) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: war.secundario.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: war.secundario.withOpacity(0.5)),
                ),
                child: Text(
                  'INICIAL',
                  style: TextStyle(
                    fontSize: 7,
                    fontFamily: 'Cinzel',
                    letterSpacing: 1,
                    color: war.secundario,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            Icon(
              bloqueada ? Icons.lock_outline : Icons.chevron_right,
              size: 18,
              color: accent.withOpacity(bloqueada ? 0.6 : 0.9),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHIP DE EJÉRCITO
// ─────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? war.primario.withOpacity(0.18) : war.superficie,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? war.primario : war.borde.withOpacity(0.4),
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
              color: selected ? war.primario : war.textoTenue,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
