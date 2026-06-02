// lib/utils/debug_log.dart
//
// Log en pantalla, sin cable ni PC. Captura mensajes con appLog(...) y los
// muestra en un panel superpuesto (DebugLogOverlay) que se abre con un botón
// flotante. Pensado para diagnosticar en dispositivos reales (p. ej. la tablet)
// donde no es cómodo leer la consola de `flutter run`.
//
// Uso:
//   1. En cualquier sitio: appLog('🔵 mi mensaje');
//   2. Envuelve tu pantalla con DebugLogOverlay(child: ...) (o añádelo al Stack)
//      para ver el botón flotante 🐞 y abrir el panel.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Bus global de logs en memoria. Notifica a los oyentes (el panel) cuando llega
/// una línea nueva. Mantiene como máximo [_maxLineas] para no crecer sin fin.
class DebugLog {
  DebugLog._();
  static final DebugLog instance = DebugLog._();

  static const int _maxLineas = 400;
  final ValueNotifier<List<String>> lineas = ValueNotifier<List<String>>([]);

  void add(String mensaje) {
    final hora = TimeOfDay.fromDateTime(DateTime.now());
    final hh = hora.hour.toString().padLeft(2, '0');
    final mm = hora.minute.toString().padLeft(2, '0');
    final ss = DateTime.now().second.toString().padLeft(2, '0');
    final linea = '[$hh:$mm:$ss] $mensaje';

    // También a la consola, por si hay cable conectado.
    debugPrint(linea);

    final actual = List<String>.from(lineas.value)..add(linea);
    if (actual.length > _maxLineas) {
      actual.removeRange(0, actual.length - _maxLineas);
    }
    lineas.value = actual;
  }

  void clear() => lineas.value = [];
}

/// Función corta para registrar un mensaje (en panel + consola).
void appLog(String mensaje) => DebugLog.instance.add(mensaje);

/// Envuelve un widget para añadir un botón flotante 🐞 que abre el panel de log.
/// Colócalo lo más arriba posible (p. ej. en el `builder` de MaterialApp o
/// envolviendo el Scaffold de la pantalla de juego).
class DebugLogOverlay extends StatefulWidget {
  final Widget child;
  const DebugLogOverlay({super.key, required this.child});

  @override
  State<DebugLogOverlay> createState() => _DebugLogOverlayState();
}

class _DebugLogOverlayState extends State<DebugLogOverlay> {
  bool _abierto = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,

          // Botón flotante para abrir/cerrar el panel.
          Positioned(
            right: 8,
            bottom: 80,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => setState(() => _abierto = !_abierto),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A2838),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFC8A860)),
                  ),
                  child: const Icon(Icons.bug_report,
                      color: Color(0xFFC8A860), size: 22),
                ),
              ),
            ),
          ),

          // Panel de log.
          if (_abierto)
            Positioned.fill(
              child: SafeArea(
                child: Material(
                  color: const Color(0xF20A1018),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('LOG DE DIAGNÓSTICO',
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFFC8A860),
                                    fontWeight: FontWeight.bold)),
                          ),
                          TextButton(
                            onPressed: () => DebugLog.instance.clear(),
                            child: const Text('LIMPIAR',
                                style: TextStyle(color: Color(0xFFC8A860))),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _abierto = false),
                            child: const Text('CERRAR',
                                style: TextStyle(color: Color(0xFFC8A860))),
                          ),
                        ],
                      ),
                      const Divider(color: Color(0xFF223040), height: 1),
                      Expanded(
                        child: ValueListenableBuilder<List<String>>(
                          valueListenable: DebugLog.instance.lineas,
                          builder: (_, lista, __) {
                            if (lista.isEmpty) {
                              return const Center(
                                child: Text('Sin mensajes todavía.',
                                    style: TextStyle(
                                        color: Color(0xFF5A6B7A),
                                        fontFamily: 'monospace')),
                              );
                            }
                            return ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(8),
                              itemCount: lista.length,
                              itemBuilder: (_, i) {
                                // reverse: mostramos el más reciente abajo.
                                final linea = lista[lista.length - 1 - i];
                                final esError = linea.contains('🔴');
                                final esOk = linea.contains('🟢');
                                final esWarn = linea.contains('🟡');
                                Color color = const Color(0xFFB8C4D0);
                                if (esError) {
                                  color = const Color(0xFFFF8A80);
                                } else if (esOk) {
                                  color = const Color(0xFF9FE0A0);
                                } else if (esWarn) {
                                  color = const Color(0xFFE0C880);
                                }
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: SelectableText(
                                    linea,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        height: 1.3,
                                        color: color),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
