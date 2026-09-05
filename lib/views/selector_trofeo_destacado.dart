// lib/views/selector_trofeo_destacado.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/trofeo_model.dart';
import '../services/settings_controller.dart';

/// Abre un selector (bottom sheet) para elegir el TROFEO DESTACADO del jugador
/// entre los que ha conseguido. Persiste la elección en el propio doc del
/// jugador (`Jugadores/{uid}.trofeoDestacado`, permitido por las reglas para el
/// dueño) y devuelve el id elegido ('' = ninguno) o null si se cerró sin cambios.
///
/// Reutilizable: hoy lo usa el perfil, pero sirve en cualquier pantalla que tenga
/// la lista de trofeos conseguidos del propio jugador.
Future<String?> mostrarSelectorTrofeoDestacado(
  BuildContext context, {
  required String uid,
  required List<TrofeoModel> conseguidos,
  required String actualId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SelectorTrofeoSheet(
      uid: uid,
      conseguidos: conseguidos,
      actualId: actualId,
    ),
  );
}

class _SelectorTrofeoSheet extends StatefulWidget {
  final String uid;
  final List<TrofeoModel> conseguidos;
  final String actualId;

  const _SelectorTrofeoSheet({
    required this.uid,
    required this.conseguidos,
    required this.actualId,
  });

  @override
  State<_SelectorTrofeoSheet> createState() => _SelectorTrofeoSheetState();
}

class _SelectorTrofeoSheetState extends State<_SelectorTrofeoSheet> {
  bool _guardando = false;

  Future<void> _elegir(String id) async {
    if (_guardando) return;
    if (id == widget.actualId) {
      Navigator.of(context).pop(); // sin cambios
      return;
    }
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance
          .collection('Jugadores')
          .doc(widget.uid)
          .set({'trofeoDestacado': id}, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const oro = Color(0xFFE0B040);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: war.fondo,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: oro.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Asa.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: war.borde,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text('TROFEO DESTACADO',
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          color: war.primario)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Elige el trofeo que verá todo el mundo junto a tu alias.',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      color: war.textoTenue),
                ),
              ),
            ),
            Divider(height: 1, color: war.borde.withOpacity(0.4)),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                children: [
                  // Opción "Ninguno".
                  _OpcionNinguno(
                    seleccionado: widget.actualId.isEmpty,
                    onTap: _guardando ? null : () => _elegir(''),
                    war: war,
                  ),
                  const SizedBox(height: 8),
                  for (final t in widget.conseguidos) ...[
                    _OpcionTrofeo(
                      trofeo: t,
                      seleccionado: t.id == widget.actualId,
                      onTap: _guardando ? null : () => _elegir(t.id),
                      war: war,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcionNinguno extends StatelessWidget {
  final bool seleccionado;
  final VoidCallback? onTap;
  final WarColors war;
  const _OpcionNinguno(
      {required this.seleccionado, required this.onTap, required this.war});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: war.superficie.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: seleccionado ? war.primario : war.borde.withOpacity(0.3),
              width: seleccionado ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: war.borde.withOpacity(0.15),
              ),
              child: Icon(Icons.block, size: 18, color: war.textoTenue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text('Ninguno',
                  style: TextStyle(
                      fontFamily: 'Cinzel', fontSize: 12, color: war.texto)),
            ),
            if (seleccionado)
              Icon(Icons.check_circle, size: 18, color: war.primario),
          ],
        ),
      ),
    );
  }
}

class _OpcionTrofeo extends StatelessWidget {
  final TrofeoModel trofeo;
  final bool seleccionado;
  final VoidCallback? onTap;
  final WarColors war;
  const _OpcionTrofeo({
    required this.trofeo,
    required this.seleccionado,
    required this.onTap,
    required this.war,
  });

  @override
  Widget build(BuildContext context) {
    const oro = Color(0xFFE0B040);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: war.superficie,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: seleccionado ? oro : oro.withOpacity(0.25),
              width: seleccionado ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: oro.withOpacity(0.18),
                border: Border.all(color: oro.withOpacity(0.6), width: 1.2),
              ),
              child: Text(trofeo.icono, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trofeo.nombre.isEmpty ? 'Trofeo' : trofeo.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: war.texto),
                  ),
                  if (trofeo.descripcion.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      trofeo.descripcion.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 9,
                          height: 1.3,
                          color: war.textoTenue),
                    ),
                  ],
                ],
              ),
            ),
            if (seleccionado)
              const Icon(Icons.check_circle, size: 18, color: oro),
          ],
        ),
      ),
    );
  }
}
