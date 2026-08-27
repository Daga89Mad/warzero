// lib/views/modo_historia_screen.dart

import 'package:flutter/material.dart';

import 'package:warzero/models/lobby_model.dart'; // kEjercitos
import 'package:warzero/services/settings_controller.dart';

/// Modo Historia: pestañas con los 4 ejércitos y una quinta de Retos.
/// De momento todas las entradas aparecen bloqueadas (se desarrollarán
/// más adelante): 10 historias por ejército y 10 retos.
class ModoHistoriaScreen extends StatelessWidget {
  const ModoHistoriaScreen({super.key});

  static const int _slots = 10;

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    final tabs = <_TabInfo>[
      for (final e in kEjercitos)
        _TabInfo(
          label: e.nombre.toUpperCase(),
          icono: e.icono,
        ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: war.fondo,
        appBar: AppBar(
          backgroundColor: war.superficie,
          iconTheme: IconThemeData(color: war.primario),
          title: Text(
            'MODO HISTORIA',
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Cinzel',
              letterSpacing: 3,
              color: war.primario,
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: war.primario,
            labelColor: war.primario,
            unselectedLabelColor: war.textoTenue,
            labelStyle: const TextStyle(
              fontSize: 10,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 10,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
            ),
            tabs: [
              for (final t in tabs) Tab(text: '${t.icono} ${t.label}'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in tabs) const _ListaBloqueada(slots: _slots),
          ],
        ),
      ),
    );
  }
}

class _TabInfo {
  final String label;
  final String icono;
  const _TabInfo({
    required this.label,
    required this.icono,
  });
}

class _ListaBloqueada extends StatelessWidget {
  final int slots;

  const _ListaBloqueada({
    required this.slots,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: slots + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'PRÓXIMAMENTE · $slots HISTORIAS',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
                color: war.textoTenue,
              ),
            ),
          );
        }

        return _EntradaBloqueada(
          numero: i,
        );
      },
    );
  }
}

class _EntradaBloqueada extends StatelessWidget {
  final int numero;

  const _EntradaBloqueada({
    required this.numero,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = war.textoTenue;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent.withOpacity(0.12),
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
              'Historia bloqueada',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Cinzel',
                letterSpacing: 0.5,
                color: war.textoTenue,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Icon(
            Icons.lock_outline,
            size: 18,
            color: accent.withOpacity(0.6),
          ),
        ],
      ),
    );
  }
}
