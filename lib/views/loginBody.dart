// lib/views/loginBody.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:warzero/core/firebaseCrudService.dart';
import 'package:warzero/views/menu.dart';
import 'package:warzero/views/registerScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginBody extends StatefulWidget {
  const LoginBody({super.key});

  @override
  State<LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<LoginBody> {
  // Servicio de autenticación
  final FirebaseCrudService _authService = FirebaseCrudService();

  // Controladores y almacenamiento seguro
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Estado interno
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _remember = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) return;

    final savedEmail = prefs.getString('saved_email');
    final savedPass = await _secureStorage.read(key: 'saved_pass');

    if (!mounted) return; // widget may be disposed after await
    if (savedEmail != null) _emailCtrl.text = savedEmail;
    if (savedPass != null) _passCtrl.text = savedPass;

    setState(() => _remember = true);
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Inicio de sesión con email y contraseña
      await _authService.signInWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      final prefs = await SharedPreferences.getInstance();

      // Gestión de “Recuérdame”
      if (_remember) {
        await prefs.setBool('remember_me', true);
        await prefs.setString('saved_email', _emailCtrl.text.trim());
        await _secureStorage.write(key: 'saved_pass', value: _passCtrl.text);
      } else {
        await prefs.remove('remember_me');
        await prefs.remove('saved_email');
        await _secureStorage.delete(key: 'saved_pass');
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MenuScreen()));
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Abre el diálogo de "¿Olvidaste tu contraseña?" con el correo que
  /// haya escrito el usuario ya rellenado.
  Future<void> _olvidePassword() async {
    final enviadoA = await showDialog<String>(
      context: context,
      builder: (_) => _OlvidePasswordDialog(
        emailInicial: _emailCtrl.text.trim(),
        authService: _authService,
      ),
    );
    if (enviadoA == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          'Si existe una cuenta con $enviadoA, recibirás un correo para crear '
          'una contraseña nueva. Revisa también la carpeta de spam.',
        ),
      ),
    );
  }

  void _goToRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Imagen superior (asegúrate de declarar el asset en pubspec.yaml)
                Image.asset(
                  'assets/images/logo.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 32),

                // Campo de correo electrónico
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),

                const SizedBox(height: 16),

                // Campo de contraseña
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),

                // Enlace "¿Olvidaste tu contraseña?"
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _olvidePassword,
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                ),

                // Checkbox “Recuérdame”
                CheckboxListTile(
                  title: const Text('Recuérdame'),
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                // Mensaje de error
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],

                const SizedBox(height: 16),

                // Botón de inicio de sesión
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _signIn,
                        child: const Text('Iniciar sesión'),
                      ),

                const SizedBox(height: 12),

                // Enlace a registro
                TextButton(
                  onPressed: _goToRegister,
                  child: const Text('¿Nuevo usuario? Regístrate'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO "¿OLVIDASTE TU CONTRASEÑA?"
// Devuelve el correo al que se ha enviado el enlace, o null si se cancela.
// ─────────────────────────────────────────────────────────────
class _OlvidePasswordDialog extends StatefulWidget {
  final String emailInicial;
  final FirebaseCrudService authService;

  const _OlvidePasswordDialog({
    required this.emailInicial,
    required this.authService,
  });

  @override
  State<_OlvidePasswordDialog> createState() => _OlvidePasswordDialogState();
}

class _OlvidePasswordDialogState extends State<_OlvidePasswordDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.emailInicial);
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final email = _ctrl.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Introduce un correo electrónico válido.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.authService.enviarRecuperacionPassword(email);
      if (!mounted) return;
      Navigator.of(context).pop(email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recuperar contraseña'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escribe el correo de tu cuenta y te enviaremos un enlace para '
            'crear una contraseña nueva.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: widget.emailInicial.isEmpty,
            keyboardType: TextInputType.emailAddress,
            enabled: !_enviando,
            onSubmitted: (_) => _enviar(),
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.email),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        _enviando
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ElevatedButton(
                onPressed: _enviar,
                child: const Text('Enviar enlace'),
              ),
      ],
    );
  }
}
