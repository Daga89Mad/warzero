import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:warzero/services/reto_service.dart';
import 'package:warzero/services/settings_controller.dart';

/// Pantalla de Retos.
///
/// Muestra 10 huecos. Los que estén en `kRetosDisponibles` (ver
/// reto_service.dart) son jugables y arrancan la partida al pulsarlos; el resto
/// aparecen bloqueados hasta que se desarrollen.
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

  /// Reto jugable en la posición [numero], o null si ese hueco está bloqueado.
  RetoInfo? _disponible(int numero) {
    for (final r in kRetosDisponibles) {
      if (r.numero == numero) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final libres = slots - kRetosDisponibles.length;

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
              '${kRetosDisponibles.length} DISPONIBLES · $libres PRÓXIMAMENTE',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'Cinzel',
                letterSpacing: 2,
                color: war.textoTenue,
              ),
            ),
          );
        }

        final reto = _disponible(i);
        if (reto != null) {
          return _EntradaRetoDisponible(reto: reto);
        }

        return _EntradaRetoBloqueado(
          numero: i,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ENTRADA DISPONIBLE (jugable)
// ─────────────────────────────────────────────────────────────
class _EntradaRetoDisponible extends StatelessWidget {
  final RetoInfo reto;

  const _EntradaRetoDisponible({
    required this.reto,
  });

  Future<void> _jugar(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await RetoService().lanzarReto(
      context,
      uid: uid,
      retoId: reto.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final accent = war.primario;

    return GestureDetector(
      onTap: () => _jugar(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent.withOpacity(0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${reto.numero}.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reto.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'Cinzel',
                      letterSpacing: 0.5,
                      color: war.texto,
                    ),
                  ),
                  if (reto.descripcion.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      reto.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'Cinzel',
                        height: 1.4,
                        color: war.textoTenue,
                      ),
                    ),
                  ],
                  if (reto.etiquetas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final e in reto.etiquetas)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: accent.withOpacity(0.25),
                              ),
                            ),
                            child: Text(
                              e,
                              style: TextStyle(
                                fontSize: 8,
                                fontFamily: 'Cinzel',
                                letterSpacing: 0.5,
                                color: accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.play_arrow_rounded,
              size: 22,
              color: accent,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ENTRADA BLOQUEADA
// ─────────────────────────────────────────────────────────────
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
