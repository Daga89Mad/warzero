// lib/views/admin_cuentas_screen.dart
//
// ADMINISTRACIÓN DE CUENTAS (solo editores).
//
// Permite buscar una cuenta por correo, UID o alias y cambiar su correo de
// login. El cambio lo hace el backend con el Admin SDK (inmediato y sin
// verificación del correo nuevo), exige un motivo y queda auditado en
// Firestore (`AuditoriaCuentas`).
//
// Tras el cambio, desde aquí se envía al correo nuevo el email de Firebase
// para crear contraseña: así el jugador confirma que el correo es suyo y
// recupera el acceso aunque no recuerde la contraseña.
//
// La visibilidad de esta pantalla depende de permisos.dart, pero la
// autorización REAL la hace el servidor con el custom claim `editor`.

import 'package:flutter/material.dart';

import '../core/firebaseCrudService.dart';
import '../services/admin_cuentas_service.dart';
import '../services/settings_controller.dart';

class AdminCuentasScreen extends StatefulWidget {
  const AdminCuentasScreen({super.key});

  @override
  State<AdminCuentasScreen> createState() => _AdminCuentasScreenState();
}

class _AdminCuentasScreenState extends State<AdminCuentasScreen> {
  static const _accent = Color(0xFFD06040);

  final _api = AdminCuentasService();
  final _busquedaCtrl = TextEditingController();

  bool _buscando = false;
  bool _haBuscado = false;
  String? _error;
  List<CuentaAdmin> _resultados = [];

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final q = _busquedaCtrl.text.trim();
    if (q.length < 3) {
      setState(() => _error = 'Escribe al menos 3 caracteres.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final r = await _api.buscar(q);
      if (!mounted) return;
      setState(() {
        _resultados = r;
        _haBuscado = true;
        _buscando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cambiarEmail(CuentaAdmin cuenta) async {
    final resultado = await showDialog<_ResultadoDialogo>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CambiarEmailAdminDialog(cuenta: cuenta, api: _api),
    );
    if (resultado == null || !mounted) return;

    final r = resultado.cambio;
    final partes = <String>[
      'Correo cambiado: ${r.emailAnterior} → ${r.emailNuevo}.',
      if (r.sesionesCerradas) 'Se han cerrado sus sesiones abiertas.',
      if (resultado.resetEnviado)
        'Se ha enviado un email para crear contraseña al correo nuevo.',
      if (resultado.errorReset != null)
        'No se pudo enviar el email de contraseña: ${resultado.errorReset}',
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(partes.join('\n')),
    ));

    // Refresca la búsqueda con el correo nuevo para ver el estado real.
    _busquedaCtrl.text = r.emailNuevo;
    await _buscar();
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Scaffold(
      backgroundColor: war.fondo,
      appBar: AppBar(
        backgroundColor: war.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 16, color: _accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('CUENTAS',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: _accent)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Busca por correo, UID o alias exacto.',
            style: TextStyle(fontSize: 12, color: war.textoTenue),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: war.superficie,
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: _accent.withOpacity(0.35), width: 1),
                  ),
                  child: TextField(
                    controller: _busquedaCtrl,
                    enabled: !_buscando,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _buscar(),
                    style: TextStyle(fontSize: 13, color: war.texto),
                    decoration: InputDecoration(
                      hintText: 'correo@ejemplo.com, UID o alias',
                      hintStyle: TextStyle(
                          fontSize: 12, color: war.textoTenue.withOpacity(0.6)),
                      prefixIcon:
                          Icon(Icons.search, size: 18, color: war.textoTenue),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent.withOpacity(0.15),
                    foregroundColor: _accent,
                    elevation: 0,
                    side: BorderSide(color: _accent.withOpacity(0.6)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _buscando ? null : _buscar,
                  child: _buscando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _accent),
                        )
                      : const Text('BUSCAR',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 10,
                              letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 12, color: war.error)),
          ],
          const SizedBox(height: 20),
          if (_haBuscado && _resultados.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: Text('No se ha encontrado ninguna cuenta.',
                    style: TextStyle(fontSize: 12, color: war.textoTenue)),
              ),
            ),
          for (final c in _resultados) ...[
            _CuentaCard(cuenta: c, onCambiarEmail: () => _cambiarEmail(c)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TARJETA DE CUENTA
// ─────────────────────────────────────────────────────────────
class _CuentaCard extends StatelessWidget {
  final CuentaAdmin cuenta;
  final VoidCallback onCambiarEmail;

  const _CuentaCard({required this.cuenta, required this.onCambiarEmail});

  static String _fecha(DateTime? d) {
    if (d == null) return '—';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const accent = _AdminCuentasScreenState._accent;

    Widget fila(String etiqueta, String valor) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(etiqueta,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 8,
                        letterSpacing: 1,
                        color: war.textoTenue)),
              ),
              Expanded(
                child: SelectableText(valor,
                    style: TextStyle(fontSize: 12, color: war.texto)),
              ),
            ],
          ),
        );

    Widget chip(String texto, Color color) => Container(
          margin: const EdgeInsets.only(right: 6, top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(texto,
              style: TextStyle(fontSize: 9, color: color, letterSpacing: 0.5)),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: war.borde.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cuenta.alias.isEmpty ? '(sin alias)' : cuenta.alias,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 14,
                  letterSpacing: 1,
                  color: war.primario)),
          fila('CORREO', cuenta.email.isEmpty ? '—' : cuenta.email),
          fila('UID', cuenta.uid),
          fila('CREADA', _fecha(cuenta.creada)),
          fila('ÚLTIMO ACCESO', _fecha(cuenta.ultimoAcceso)),
          Wrap(
            children: [
              chip(
                cuenta.emailVerificado ? 'CORREO VERIFICADO' : 'SIN VERIFICAR',
                cuenta.emailVerificado ? war.secundario : war.textoTenue,
              ),
              if (cuenta.deshabilitada) chip('DESHABILITADA', war.error),
              if (cuenta.esEditor) chip('EDITOR', const Color(0xFFA040C0)),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withOpacity(0.6)),
              ),
              onPressed: onCambiarEmail,
              icon: const Icon(Icons.alternate_email, size: 16),
              label: const Text('CAMBIAR CORREO',
                  style: TextStyle(
                      fontFamily: 'Cinzel', fontSize: 10, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO DE CAMBIO DE CORREO
// ─────────────────────────────────────────────────────────────

class _ResultadoDialogo {
  final CambioEmailAdminResult cambio;
  final bool resetEnviado;
  final String? errorReset;

  const _ResultadoDialogo({
    required this.cambio,
    required this.resetEnviado,
    this.errorReset,
  });
}

class _CambiarEmailAdminDialog extends StatefulWidget {
  final CuentaAdmin cuenta;
  final AdminCuentasService api;

  const _CambiarEmailAdminDialog({required this.cuenta, required this.api});

  @override
  State<_CambiarEmailAdminDialog> createState() =>
      _CambiarEmailAdminDialogState();
}

class _CambiarEmailAdminDialogState extends State<_CambiarEmailAdminDialog> {
  final _emailCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();

  bool _cerrarSesiones = true;
  bool _enviarReset = true;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _confirmarCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final nuevo = _emailCtrl.text.trim().toLowerCase();
    final repetido = _confirmarCtrl.text.trim().toLowerCase();
    final motivo = _motivoCtrl.text.trim();

    if (!nuevo.contains('@') || !nuevo.contains('.')) {
      setState(() => _error = 'Introduce un correo válido.');
      return;
    }
    if (nuevo != repetido) {
      setState(() => _error = 'Los dos correos no coinciden.');
      return;
    }
    if (nuevo == widget.cuenta.email.toLowerCase()) {
      setState(() => _error = 'El correo nuevo es igual al actual.');
      return;
    }
    if (motivo.length < 5) {
      setState(() => _error = 'Indica el motivo (mínimo 5 caracteres).');
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    CambioEmailAdminResult cambio;
    try {
      cambio = await widget.api.cambiarEmail(
        uid: widget.cuenta.uid,
        nuevoEmail: nuevo,
        motivo: motivo,
        cerrarSesiones: _cerrarSesiones,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    // El cambio ya está hecho: el email de contraseña es un extra y su fallo
    // no debe ocultar que el correo se cambió.
    var resetEnviado = false;
    String? errorReset;
    if (_enviarReset) {
      try {
        await FirebaseCrudService().enviarRecuperacionPassword(nuevo);
        resetEnviado = true;
      } catch (e) {
        errorReset = e.toString().replaceFirst('Exception: ', '');
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(_ResultadoDialogo(
      cambio: cambio,
      resetEnviado: resetEnviado,
      errorReset: errorReset,
    ));
  }

  InputDecoration _deco(String label, IconData icon) {
    final war = context.war;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 12, color: war.textoTenue),
      prefixIcon: Icon(icon, size: 18, color: war.textoTenue),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: war.primario.withOpacity(0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: war.primario),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    const accent = _AdminCuentasScreenState._accent;
    final c = widget.cuenta;

    return AlertDialog(
      backgroundColor: war.superficie,
      title: const Text('CAMBIAR CORREO',
          style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 13,
              letterSpacing: 1.5,
              color: accent)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.alias.isEmpty ? c.uid : c.alias}\nCorreo actual: ${c.email}',
              style: TextStyle(fontSize: 12, color: war.texto, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: war.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: war.error.withOpacity(0.4)),
              ),
              child: Text(
                'El cambio es inmediato y no se verifica el correo nuevo. '
                'Si está mal escrito, el jugador no podrá entrar. '
                'El correo antiguo no recibe ningún aviso.',
                style: TextStyle(fontSize: 11, color: war.texto, height: 1.4),
              ),
            ),
            if (c.esEditor) ...[
              const SizedBox(height: 8),
              Text(
                'Esta cuenta es editora: si su correo no está en permisos.dart '
                'perderá el acceso a las pantallas de edición.',
                style: TextStyle(fontSize: 11, color: war.error, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              enabled: !_enviando,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(fontSize: 13, color: war.texto),
              decoration: _deco('Correo nuevo', Icons.alternate_email),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmarCtrl,
              enabled: !_enviando,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(fontSize: 13, color: war.texto),
              decoration:
                  _deco('Repite el correo nuevo', Icons.alternate_email),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motivoCtrl,
              enabled: !_enviando,
              maxLines: 2,
              maxLength: 200,
              style: TextStyle(fontSize: 13, color: war.texto),
              decoration: _deco('Motivo (queda registrado)', Icons.notes),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _cerrarSesiones,
              activeColor: accent,
              onChanged: _enviando
                  ? null
                  : (v) => setState(() => _cerrarSesiones = v ?? true),
              title: Text('Cerrar sus sesiones abiertas',
                  style: TextStyle(fontSize: 12, color: war.texto)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _enviarReset,
              activeColor: accent,
              onChanged: _enviando
                  ? null
                  : (v) => setState(() => _enviarReset = v ?? true),
              title: Text(
                  'Enviar al correo nuevo un email para crear contraseña',
                  style: TextStyle(fontSize: 12, color: war.texto)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: TextStyle(fontSize: 12, color: war.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: Text('CANCELAR',
              style: TextStyle(color: war.textoTenue, letterSpacing: 1)),
        ),
        _enviando
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: accent),
                ),
              )
            : TextButton(
                onPressed: _confirmar,
                child: const Text('CAMBIAR',
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              ),
      ],
    );
  }
}
