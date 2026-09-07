// lib/views/modo_historia_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:warzero/models/lobby_model.dart'; // kEjercitos
import 'package:warzero/services/historia_service.dart';
import 'package:warzero/services/settings_controller.dart';

/// Una batalla de historia YA disponible (jugable). El resto de entradas
/// aparecen bloqueadas hasta que se desarrollen.
///
/// Clave del mapa: '<ejercitoId>-<orden>' (p. ej. '3-1' = Demonios, historia 1).
class _BatallaDisponible {
  final String id; // historiaId del catálogo del servidor (p. ej. 'demonios_1')
  final String titulo;
  const _BatallaDisponible(this.id, this.titulo);
}

const Map<String, _BatallaDisponible> _batallasDisponibles = {
  '3-1': _BatallaDisponible('demonios_1', 'El asedio de Diente de Invierno'),
};

/// Modo Historia: pestañas con los 4 ejércitos. Cada ejército tiene 10 historias.
/// Las disponibles arrancan una partida contra la máquina al pulsarlas; el resto
/// permanecen bloqueadas.
class ModoHistoriaScreen extends StatelessWidget {
  const ModoHistoriaScreen({super.key});

  static const int _slots = 10;

  @override
  Widget build(BuildContext context) {
    final war = context.war;

    return DefaultTabController(
      length: kEjercitos.length,
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
              for (final e in kEjercitos)
                Tab(text: '${e.icono} ${e.nombre.toUpperCase()}'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final e in kEjercitos)
              _ListaHistorias(ejercitoId: e.id, slots: _slots),
          ],
        ),
      ),
    );
  }
}

class _ListaHistorias extends StatelessWidget {
  final int ejercitoId;
  final int slots;

  const _ListaHistorias({required this.ejercitoId, required this.slots});

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
              '$slots HISTORIAS',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
                color: war.textoTenue,
              ),
            ),
          );
        }

        final orden = i;
        final disponible = _batallasDisponibles['$ejercitoId-$orden'];
        if (disponible != null) {
          return _EntradaDisponible(numero: orden, batalla: disponible);
        }
        return _EntradaBloqueada(numero: orden);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ENTRADA DISPONIBLE (jugable)
// ─────────────────────────────────────────────────────────────
class _EntradaDisponible extends StatelessWidget {
  final int numero;
  final _BatallaDisponible batalla;

  const _EntradaDisponible({required this.numero, required this.batalla});

  Future<void> _jugar(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await HistoriaService().lanzarHistoria(
      context,
      uid: uid,
      historiaId: batalla.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = war.primario;

    return GestureDetector(
      onTap: () => _jugar(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.45)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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
                batalla.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Cinzel',
                  letterSpacing: 0.5,
                  color: war.texto,
                ),
              ),
            ),
            Icon(Icons.play_arrow_rounded, size: 22, color: accent),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ENTRADA BLOQUEADA
// ─────────────────────────────────────────────────────────────
class _EntradaBloqueada extends StatelessWidget {
  final int numero;

  const _EntradaBloqueada({required this.numero});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = war.textoTenue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.12)),
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
          Icon(Icons.lock_outline, size: 18, color: accent.withOpacity(0.6)),
        ],
      ),
    );
  }
}
