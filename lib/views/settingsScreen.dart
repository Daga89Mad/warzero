import 'package:flutter/material.dart';
import 'package:warzero/services/settings_controller.dart';

import '../services/cuenta_service.dart';
import '../services/permisos.dart';
import 'diagnostico_screen.dart';
import 'tutorial_screen.dart';

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
              const SizedBox(height: 24),

              // ── Tablero ──────────────────────────────────────
              _Seccion(
                titulo: 'TABLERO',
                color: tema.primario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vista en perspectiva 3D del tablero. Desactívalo para '
                      'verlo plano (cenital, de frente).',
                      style: TextStyle(color: tema.textoTenue, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      value: settingsController.tablero3D,
                      activeColor: tema.primario,
                      onChanged: (v) =>
                          settingsController.setTablero3D(v ?? true),
                      title: Text(
                        'Tablero en 3D',
                        style: TextStyle(
                          color: tema.texto,
                          fontFamily: 'Cinzel',
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Tutorial (visible para todos los jugadores) ──
              _Seccion(
                titulo: 'TUTORIAL',
                color: tema.primario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Aprende lo esencial con una partida guiada: energía Zero, '
                      'atributos de las cartas, cómo desplegarlas, moverlas, el '
                      'combate y las cartas de acción.',
                      style: TextStyle(color: tema.textoTenue, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TutorialScreen()),
                      ),
                      icon: const Icon(Icons.school),
                      label: const Text('Ver tutorial'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Cuenta y privacidad ──────────────────────────
              // Obligatorio para App Store: política de privacidad accesible
              // desde la app (5.1.1(i)) y borrado de cuenta en la app (5.1.1(v)).
              _Seccion(
                titulo: 'CUENTA Y PRIVACIDAD',
                color: tema.primario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Consulta cómo tratamos tus datos o elimina tu cuenta y '
                      'todos sus datos de forma permanente.',
                      style: TextStyle(color: tema.textoTenue, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _abrirPrivacidad(context),
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('Política de privacidad'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC04040),
                        side: const BorderSide(color: Color(0xFFC04040)),
                      ),
                      onPressed: () => _eliminarCuenta(context),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Eliminar mi cuenta'),
                    ),
                  ],
                ),
              ),

              // ── Diagnóstico (solo cuentas de editor/QA) ──────
              // Se OCULTA por completo si el usuario no tiene permisos de editor
              // (mismo criterio que la edición de contenido: ver permisos.dart).
              if (esEditor()) ...[
                const SizedBox(height: 24),
                _Seccion(
                  titulo: 'DIAGNÓSTICO',
                  color: tema.primario,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Herramientas para depurar red y notificaciones push.',
                        style: TextStyle(color: tema.textoTenue, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const DiagnosticoScreen()),
                        ),
                        icon: const Icon(Icons.bug_report),
                        label: const Text('Abrir diagnóstico'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Acciones de cuenta ────────────────────────────────────────────────────

  static Future<void> _abrirPrivacidad(BuildContext context) async {
    final ok = await CuentaService().abrirPoliticaPrivacidad();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la política de privacidad.'),
        ),
      );
    }
  }

  static Future<void> _eliminarCuenta(BuildContext context) async {
    final eliminada = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogoEliminarCuenta(),
    );
    if (eliminada != true || !context.mounted) return;

    // La sesión ya está cerrada: el _AuthGate de main.dart muestra el login.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Tu cuenta y tus datos se han eliminado.')),
    );
  }
}

/// Diálogo de confirmación del borrado. Pide la contraseña (reautenticación)
/// y devuelve true si la cuenta se eliminó.
class _DialogoEliminarCuenta extends StatefulWidget {
  const _DialogoEliminarCuenta();

  @override
  State<_DialogoEliminarCuenta> createState() => _DialogoEliminarCuentaState();
}

class _DialogoEliminarCuentaState extends State<_DialogoEliminarCuenta> {
  final _passCtrl = TextEditingController();
  bool _enCurso = false;
  bool _verPass = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() {
      _enCurso = true;
      _error = null;
    });
    try {
      await CuentaService().eliminarCuenta(password: _passCtrl.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCurso = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ELIMINAR CUENTA',
          style: TextStyle(fontFamily: 'Cinzel', letterSpacing: 2)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrarán de forma PERMANENTE tu cuenta, tu colección de '
              'cartas, tus mazos, tus estadísticas y tu progreso. Esta acción '
              'no se puede deshacer.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passCtrl,
              enabled: !_enCurso,
              obscureText: !_verPass,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Contraseña',
                errorText: _error,
                suffixIcon: IconButton(
                  icon:
                      Icon(_verPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _verPass = !_verPass),
                ),
              ),
              onSubmitted: (_) => _enCurso ? null : _confirmar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCurso ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC04040),
          ),
          onPressed: _enCurso ? null : _confirmar,
          child: _enCurso
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Eliminar'),
        ),
      ],
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
