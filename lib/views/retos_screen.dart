import 'package:flutter/material.dart';

import 'package:warzero/services/settings_controller.dart';

/// Pantalla de Retos.
/// De momento muestra 10 retos bloqueados.
class RetosScreen extends StatelessWidget {
  const RetosScreen({super.key});

  static const int _slots = 10;

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    return DefaultTabController(
      length: 1,
      child: Scaffold(
        backgroundColor: war.fondo,
        appBar: AppBar(
          backgroundColor: war.superficie,
          iconTheme: IconThemeData(
            color: war.primario,
          ),
          title: Text(
            'RETOS',
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Cinzel',
              letterSpacing: 3,
              color: war.primario,
            ),
          ),
          bottom: TabBar(
            indicatorColor: war.primario,
            labelColor: war.primario,
            unselectedLabelColor: war.textoTenue,
            labelStyle: const TextStyle(
              fontSize: 10,
              fontFamily: 'Cinzel',
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
            tabs: const [
              Tab(
                text: '🏆 RETOS',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ListaRetos(
              slots: _slots,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListaRetos extends StatelessWidget {
  final int slots;

  const _ListaRetos({
    required this.slots,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        16,
      ),
      itemCount: slots + 1,
      separatorBuilder: (_, __) {
        return const SizedBox(height: 6);
      },
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(
              bottom: 6,
            ),
            child: Text(
              'PRÓXIMAMENTE · $slots RETOS',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
                color: war.textoTenue,
              ),
            ),
          );
        }

        return _EntradaRetoBloqueado(
          numero: i,
        );
      },
    );
  }
}

class _EntradaRetoBloqueado extends StatelessWidget {
  final int numero;

  const _EntradaRetoBloqueado({
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
              'Reto bloqueado',
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
