// lib/views/perfil_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:warzero/core/firebaseCrudService.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PerfilScreen — Pantalla de perfil del jugador.
//
// EDITABLE:   alias, imagenPerfil (URL)
// SOLO LECTURA: email, nivel, experiencia, dinero, fecha de registro
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

  // Datos del jugador
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

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02050D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              size: 16, color: Color(0xFFC8A860)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('PERFIL',
            style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 13,
                letterSpacing: 3,
                color: Color(0xFFC8A860))),
        actions: [
          // Botón GUARDAR en el AppBar
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
                    color: _saving
                        ? const Color(0xFF0A1A0A)
                        : const Color(0xFF1A3A0A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF4ABB58).withOpacity(0.6),
                        width: 1),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Color(0xFF4ABB58)))
                      : const Text('GUARDAR',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 9,
                              letterSpacing: 1.5,
                              color: Color(0xFF4ABB58),
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A860)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar preview ──────────────────────────
                  _AvatarPreview(imageUrl: _imagenCtrl.text),

                  const SizedBox(height: 28),

                  // ── EDITABLE ────────────────────────────────
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

                  // ── SOLO LECTURA ─────────────────────────────
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

                  // ── ESTADÍSTICAS ─────────────────────────────
                  _SectionLabel('ESTADÍSTICAS'),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: '⭐',
                          label: 'NIVEL',
                          value: '$_nivel',
                          color: const Color(0xFFC8A860),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: '✨',
                          label: 'EXPERIENCIA',
                          value: '$_experiencia',
                          color: const Color(0xFF4ABB58),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: '💰',
                          label: 'DINERO',
                          value: '$_dinero',
                          color: const Color(0xFFD4A800),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Barra de progreso XP
                  _XpBar(nivel: _nivel, experiencia: _experiencia),

                  const SizedBox(height: 28),

                  // ── Mensajes ─────────────────────────────────
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
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF080D18),
          border: Border.all(
              color: const Color(0xFFC8A860).withOpacity(0.5), width: 2),
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
  Widget build(BuildContext context) => const Icon(
        Icons.person_outline,
        size: 50,
        color: Color(0xFF506070),
      );
}

// ─────────────────────────────────────────────────────────────
// BARRA XP
// ─────────────────────────────────────────────────────────────
class _XpBar extends StatelessWidget {
  final int nivel;
  final int experiencia;
  const _XpBar({required this.nivel, required this.experiencia});

  @override
  Widget build(BuildContext context) {
    final xpSiguiente = nivel * 1000;
    final xpEnNivelActual = experiencia % xpSiguiente;
    final progreso = (xpEnNivelActual / xpSiguiente).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PROGRESO NIVEL $nivel → ${nivel + 1}',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 7,
                    letterSpacing: 1.5,
                    color: Color(0xFF506070))),
            Text('$xpEnNivelActual / $xpSiguiente XP',
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 7,
                    color: Color(0xFF506070))),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progreso,
            minHeight: 6,
            backgroundColor: const Color(0xFF1A2A3A),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC8A860)),
          ),
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7,
                letterSpacing: 2,
                color: Color(0xFF506070))),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF080D18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: const Color(0xFFC8A860).withOpacity(0.25), width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLength: maxLength,
            onChanged: onChanged,
            style: const TextStyle(
                fontFamily: 'Cinzel', fontSize: 12, color: Color(0xFFD0C090)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  fontFamily: 'Cinzel', fontSize: 10, color: Color(0xFF3A4A5A)),
              prefixIcon: Icon(icon, size: 18, color: const Color(0xFF506070)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cinzel',
                fontSize: 7,
                letterSpacing: 2,
                color: Color(0xFF506070))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF060B14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF1A2A3A), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF3A4A5A)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 11,
                        color: Color(0xFF506070))),
              ),
              const Icon(Icons.lock_outline,
                  size: 12, color: Color(0xFF2A3A4A)),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF080D18),
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
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 6,
                  color: Color(0xFF506070),
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
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFF1A2A3A),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
              style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 8,
                  letterSpacing: 2,
                  color: Color(0xFF506070))),
        ),
        Expanded(
          child: Container(height: 1, color: const Color(0xFF1A2A3A)),
        ),
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
    final color = isError ? const Color(0xFFFF8080) : const Color(0xFF4ABB58);
    final bg = isError ? const Color(0xFF2A0808) : const Color(0xFF0A2A0A);
    final border = isError ? const Color(0xFFC04040) : const Color(0xFF2A6A2A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border.withOpacity(0.5), width: 1),
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
