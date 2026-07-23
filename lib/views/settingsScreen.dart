import 'package:flutter/material.dart';
import 'package:warzero/services/settings_controller.dart';
import '../services/settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final tema = settingsController.tema;
        return Scaffold(
          appBar: AppBar(
            title: const Text('AJUSTES',
                style: TextStyle(fontFamily: 'Cinzel', letterSpacing: 2)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Tamaño de texto ──────────────────────────────
              _Seccion(
                titulo: 'TAMAÑO DE TEXTO',
                color: tema.primario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Texto de ejemplo — así se verá.',
                      style: TextStyle(color: tema.texto, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.text_decrease,
                            color: tema.textoTenue, size: 20),
                        Expanded(
                          child: Slider(
                            value: settingsController.escala,
                            min: SettingsController.escalaMin,
                            max: SettingsController.escalaMax,
                            divisions: 11,
                            activeColor: tema.primario,
                            label:
                                '${(settingsController.escala * 100).round()}%',
                            onChanged: settingsController.setEscala,
                          ),
                        ),
                        Icon(Icons.text_increase,
                            color: tema.textoTenue, size: 24),
                      ],
                    ),
                    Center(
                      child: Text(
                          '${(settingsController.escala * 100).round()}%',
                          style:
                              TextStyle(color: tema.textoTenue, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Temática ─────────────────────────────────────
              _Seccion(
                titulo: 'TEMÁTICA',
                color: tema.primario,
                child: Column(
                  children: [
                    for (var i = 0; i < kWarZeroThemes.length; i++)
                      _TemaTile(
                        tema: kWarZeroThemes[i],
                        seleccionado: i == settingsController.temaIndex,
                        onTap: () => settingsController.setTemaIndex(i),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final Color color;
  final Widget child;
  const _Seccion(
      {required this.titulo, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 2,
                color: color)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _TemaTile extends StatelessWidget {
  final WarZeroTheme tema;
  final bool seleccionado;
  final VoidCallback onTap;
  const _TemaTile(
      {required this.tema, required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: tema.superficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionado ? tema.primario : tema.borde.withOpacity(0.4),
            width: seleccionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Muestra de paleta.
            _Swatch(color: tema.fondo, borde: tema.borde),
            _Swatch(color: tema.primario, borde: tema.borde),
            _Swatch(color: tema.secundario, borde: tema.borde),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tema.nombre,
                style: TextStyle(
                  color: tema.texto,
                  fontFamily: 'Cinzel',
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
            ),
            if (tema.esClaro)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.light_mode, size: 16, color: tema.textoTenue),
              ),
            Icon(
              seleccionado ? Icons.check_circle : Icons.circle_outlined,
              color: seleccionado ? tema.primario : tema.textoTenue,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final Color borde;
  const _Swatch({required this.color, required this.borde});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borde.withOpacity(0.5)),
      ),
    );
  }
}
