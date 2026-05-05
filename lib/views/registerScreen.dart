// lib/views/register_screen.dart

import 'package:flutter/material.dart';
import 'package:warzero/core/firebaseCrudService.dart';
import 'package:warzero/views/menu.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _authService = FirebaseCrudService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _aliasCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Validación y registro ──────────────────────────────────
  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final alias = _aliasCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (email.isEmpty || alias.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'Rellena todos los campos.');
      return;
    }
    if (alias.length < 3 || alias.length > 20) {
      setState(
          () => _errorMessage = 'El alias debe tener entre 3 y 20 caracteres.');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // registerWithEmail ya crea el perfil en Firestore
      await _authService.registerWithEmail(
        email: email,
        password: password,
        alias: alias,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MenuScreen()),
      );
    } on Exception catch (e) {
      setState(
          () => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030810),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────
              const Text('WARZERO',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC8A860),
                      letterSpacing: 8)),
              const SizedBox(height: 6),
              const Text('CREAR CUENTA',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 10,
                      color: Color(0xFF506070),
                      letterSpacing: 3)),

              const SizedBox(height: 40),

              // ── Email ────────────────────────────────────
              _FieldLabel('CORREO ELECTRÓNICO'),
              const SizedBox(height: 6),
              _InputField(
                controller: _emailCtrl,
                hint: 'comandante@warzero.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
              ),

              const SizedBox(height: 20),

              // ── Alias ────────────────────────────────────
              _FieldLabel('NOMBRE DE COMANDANTE'),
              const SizedBox(height: 6),
              _InputField(
                controller: _aliasCtrl,
                hint: 'Entre 3 y 20 caracteres',
                prefixIcon: Icons.person_outline,
                maxLength: 20,
              ),

              const SizedBox(height: 20),

              // ── Contraseña ───────────────────────────────
              _FieldLabel('CONTRASEÑA'),
              const SizedBox(height: 6),
              _InputField(
                controller: _passwordCtrl,
                hint: 'Mínimo 6 caracteres',
                prefixIcon: Icons.lock_outline,
                obscure: _obscurePassword,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),

              const SizedBox(height: 20),

              // ── Confirmar contraseña ──────────────────────
              _FieldLabel('CONFIRMAR CONTRASEÑA'),
              const SizedBox(height: 6),
              _InputField(
                controller: _confirmCtrl,
                hint: 'Repite la contraseña',
                prefixIcon: Icons.lock_outline,
                obscure: _obscureConfirm,
                onToggleObscure: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),

              const SizedBox(height: 16),

              // ── Error ─────────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A0808),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFC04040).withOpacity(0.4),
                        width: 1),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 9,
                        color: Color(0xFFFF8080),
                        height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Botón REGISTRAR ───────────────────────────
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFFC8A860)))
                    : GestureDetector(
                        onTap: _register,
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8A860).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFC8A860).withOpacity(0.6),
                                width: 1),
                          ),
                          child: const Text('CREAR CUENTA',
                              style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 13,
                                  letterSpacing: 3,
                                  color: Color(0xFFC8A860),
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
              ),

              const SizedBox(height: 24),

              // ── Link a login ──────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text(
                    '¿Ya tienes cuenta?  INICIAR SESIÓN',
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 9,
                        color: Color(0xFF506070),
                        letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 8,
            letterSpacing: 2,
            color: Color(0xFF506070)),
      );
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final TextInputType keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final int? maxLength;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.onToggleObscure,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080D18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFFC8A860).withOpacity(0.2), width: 1),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: const TextStyle(
            fontFamily: 'Cinzel', fontSize: 12, color: Color(0xFFD0C090)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              fontFamily: 'Cinzel', fontSize: 10, color: Color(0xFF3A4A5A)),
          prefixIcon:
              Icon(prefixIcon, size: 18, color: const Color(0xFF506070)),
          suffixIcon: onToggleObscure != null
              ? IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: const Color(0xFF506070),
                  ),
                  onPressed: onToggleObscure,
                )
              : null,
          counterText: '', // Ocultar el contador de maxLength
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
