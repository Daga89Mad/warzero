// lib/views/perfil_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:warzero/core/firebaseCrudService.dart';
import '../services/settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PerfilScreen — Pantalla de perfil del jugador.
// ─────────────────────────────────────────────────────────────────────────────

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _svc = FirebaseCrudService();

  final _aliasCtrl = TextEditingController();
  final _imagenCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _successMsg;

  String _email = '';
  int _nivel = 1;
  int _experiencia = 0;
  int _dinero = 0;
  String _fechaRegistro = '';

  String get _uid => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadPerfil();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _imagenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPerfil() async {
    try {
      final doc = await _db.collection('Jugadores').doc(_uid).get();
      if (!doc.exists || !mounted) return;

      final d = doc.data() as Map<String, dynamic>;

      final ts = d['fechaRegistro'];
      String fechaStr = '';
      if (ts is Timestamp) {
        final dt = ts.toDate().toLocal();
        fechaStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }

      setState(() {
        _aliasCtrl.text = d['alias']?.toString() ?? '';
        _imagenCtrl.text = d['imagenPerfil']?.toString() ?? '';
        _email = _auth.currentUser?.email ?? '';
        _nivel = (d['nivel'] as num?)?.toInt() ?? 1;
        _experiencia = (d['experiencia'] as num?)?.toInt() ?? 0;
        _dinero = (d['dinero'] as num?)?.toInt() ?? 0;
        _fechaRegistro = fechaStr;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _guardar() async {
    final alias = _aliasCtrl.text.trim();
    final imagen = _imagenCtrl.text.trim();

    if (alias.isEmpty) {
      setState(() => _error = 'El alias no puede estar vacío.');
      return;
    }
    if (alias.length < 3 || alias.length > 20) {
      setState(() => _error = 'El alias debe tener entre 3 y 20 caracteres.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _successMsg = null;
    });

    try {
      await _svc.actualizarPerfil(
        uid: _uid,
        alias: alias,
        imagenPerfil: imagen,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _successMsg = 'Perfil guardado correctamente.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
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
          icon: Icon(Icons.arrow_back_ios, size: 16, color: war.primario),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('PERFIL',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: war.primario)),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _saving ? null : _guardar,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: war.secundario.withOpacity(_saving ? 0.06 : 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: war.secundario.withOpacity(0.6), width: 1),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: war.secundario))
                      : Text('GUARDAR',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 9,
                              letterSpacing: 1.5,
                              color: war.secundario,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: war.primario))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AvatarPreview(imageUrl: _imagenCtrl.text),
                  const SizedBox(height: 28),
                  _SectionLabel('DATOS EDITABLES'),
                  const SizedBox(height: 14),
                  _EditableField(
                    label: 'NOMBRE DE COMANDANTE',
                    controller: _aliasCtrl,
                    icon: Icons.person_outline,
                    hint: 'Tu alias en el juego',
                    maxLength: 20,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  _EditableField(
                    label: 'URL DE IMAGEN DE PERFIL',
                    controller: _imagenCtrl,
                    icon: Icons.image_outlined,
                    hint: 'https://...',
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel('INFORMACIÓN DE CUENTA'),
                  const SizedBox(height: 14),
                  _ReadOnlyField(
                      label: 'CORREO ELECTRÓNICO',
                      value: _email,
                      icon: Icons.email_outlined),
                  const SizedBox(height: 10),
                  _ReadOnlyField(
                      label: 'FECHA DE REGISTRO',
                      value: _fechaRegistro.isEmpty ? '—' : _fechaRegistro,
                      icon: Icons.calendar_today_outlined),
                  const SizedBox(height: 28),
                  _SectionLabel('ESTADÍSTICAS'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: '⭐',
                          label: 'NIVEL',
                          value: '$_nivel',
                          color: war.primario,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: '✨',
                          label: 'EXPERIENCIA',
                          value: '$_experiencia',
                          color: war.secundario,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: '💰',
                          label: 'DINERO',
                          value: '$_dinero',
                          color: const Color(0xFFD4A800), // oro (semántico)
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _XpBar(nivel: _nivel, experiencia: _experiencia),
                  const SizedBox(height: 28),
                  if (_successMsg != null)
                    _MessageBanner(msg: _successMsg!, isError: false),
                  if (_error != null)
                    _MessageBanner(msg: _error!, isError: true),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AVATAR PREVIEW
// ─────────────────────────────────────────────────────────────
class _AvatarPreview extends StatelessWidget {
  final String imageUrl;
  const _AvatarPreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: war.superficie,
          border: Border.all(color: war.primario.withOpacity(0.5), width: 2),
        ),
        child: ClipOval(
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _AvatarPlaceholder(),
                )
              : const _AvatarPlaceholder(),
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();
  @override
  Widget build(BuildContext context) => Icon(
        Icons.person_outline,
        size: 50,
        color: context.war.textoTenue,
      );
}

class _XpBar extends StatelessWidget {
  final int nivel;
  final int experiencia;
  const _XpBar({required this.nivel, required this.experiencia});

  // XP total acumulada para ALCANZAR un nivel: 1000 * (2^(n-1) - 1).
  static int _xpParaAlcanzar(int n) => 1000 * ((1 << (n - 1)) - 1);

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final xpBase = _xpParaAlcanzar(nivel);
    final xpTecho = _xpParaAlcanzar(nivel + 1);
    final costeNivel = (xpTecho - xpBase).clamp(1, 1 << 30);
    final xpEnNivelActual = (experiencia - xpBase).clamp(0, costeNivel);
    final progreso = (xpEnNivelActual / costeNivel).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PROGRESO NIVEL $nivel → ${nivel + 1}',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 12,
                letterSpacing: 1.2,
                color: war.primario)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progreso,
            minHeight: 12,
            backgroundColor: war.borde.withOpacity(0.3),
            valueColor: AlwaysStoppedAnimation(war.primario),
          ),
        ),
        const SizedBox(height: 4),
        Text('$xpEnNivelActual / $costeNivel XP',
            style: TextStyle(fontSize: 11, color: war.textoTenue)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CAMPO EDITABLE
// ─────────────────────────────────────────────────────────────
class _EditableField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final void Function(String)? onChanged;

  const _EditableField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7,
                letterSpacing: 2,
                color: war.textoTenue)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: war.superficie,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: war.primario.withOpacity(0.25), width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLength: maxLength,
            onChanged: onChanged,
            style:
                TextStyle(fontFamily: 'Cinzel', fontSize: 12, color: war.texto),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 10,
                  color: war.textoTenue.withOpacity(0.6)),
              prefixIcon: Icon(icon, size: 18, color: war.textoTenue),
              counterText: '',
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CAMPO SOLO LECTURA
// ─────────────────────────────────────────────────────────────
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7,
                letterSpacing: 2,
                color: war.textoTenue)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: war.fondo,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: war.borde.withOpacity(0.5), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: war.textoTenue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(value,
                    style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        color: war.textoTenue)),
              ),
              Icon(Icons.lock_outline, size: 12, color: war.borde),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: war.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 6,
                  color: war.textoTenue,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    return Row(
      children: [
        Expanded(
            child: Container(height: 1, color: war.borde.withOpacity(0.5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  letterSpacing: 2,
                  color: war.textoTenue)),
        ),
        Expanded(
            child: Container(height: 1, color: war.borde.withOpacity(0.5))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MENSAJE (éxito / error)
// ─────────────────────────────────────────────────────────────
class _MessageBanner extends StatelessWidget {
  final String msg;
  final bool isError;

  const _MessageBanner({required this.msg, required this.isError});

  @override
  Widget build(BuildContext context) {
    final war = context.war;
    final color = isError ? war.error : war.secundario;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 9,
                    color: color,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}
