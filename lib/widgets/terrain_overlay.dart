// lib/widgets/terrain_overlay.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Tipos de terreno ──────────────────────────────────────────
enum TerrainOverlay { none, grass, ice, volcanic, desert }

// ── Mapa de coordenadas → terreno ─────────────────────────────
// Fácil de ampliar: añade más entradas o carga desde Firebase
const Map<String, TerrainOverlay> kTerrainMap = {
  // Añade terrenos aquí: 'B5': TerrainOverlay.volcanic
};

TerrainOverlay terrainAt(String coord) =>
    kTerrainMap[coord] ?? TerrainOverlay.none;

// ─────────────────────────────────────────────────────────────
// PAINTERS
// ─────────────────────────────────────────────────────────────

// ── Hierba ────────────────────────────────────────────────────
class GrassPainter extends CustomPainter {
  const GrassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Veladura verde semi-transparente sobre la imagen
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0x661A3A14));

    // Briznas de hierba con líneas irregulares
    final bladePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final random = _SeededRandom(42);
    for (int i = 0; i < 28; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final h = 6 + random.nextDouble() * 10;
      final lean = (random.nextDouble() - 0.5) * 6;
      final shade = random.nextDouble();

      bladePaint.color = Color.lerp(
        const Color(0xFF2A5A1A),
        const Color(0xFF4A8A28),
        shade,
      )!
          .withOpacity(0.75 + shade * 0.25);

      final path = Path()
        ..moveTo(x, baseY)
        ..quadraticBezierTo(
            x + lean * 0.5, baseY - h * 0.5, x + lean, baseY - h);
      canvas.drawPath(path, bladePaint);
    }

    // Manchas de luz (rocío)
    final dewPaint = Paint()
      ..color = const Color(0x1890D060)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (int i = 0; i < 4; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 5, dewPaint);
    }
  }

  @override
  bool shouldRepaint(GrassPainter _) => false;
}

// ── Hielo ─────────────────────────────────────────────────────
class IcePainter extends CustomPainter {
  const IcePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Veladura azul glacial semi-transparente sobre la imagen
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0x558EC8E8));

    // Cristales de hielo: líneas que irradian desde centros
    final crackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0xAAFFFFFF);

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Grietas principales desde el centro
    final pi = math.pi;
    final angles = List.generate(12, (i) => i * pi / 6);
    for (final angle in angles) {
      final len = 18 + (angle * 7) % 14;
      final ex = cx + len * _cos(angle);
      final ey = cy + len * _sin(angle);
      canvas.drawLine(Offset(cx, cy), Offset(ex, ey), crackPaint);
      // Sub-grieta
      crackPaint.color = const Color(0x66FFFFFF);
      crackPaint.strokeWidth = 0.4;
      final midX = (cx + ex) / 2;
      final midY = (cy + ey) / 2;
      final subAngle = angle + 0.8;
      canvas.drawLine(
        Offset(midX, midY),
        Offset(midX + 8 * _cos(subAngle), midY + 8 * _sin(subAngle)),
        crackPaint,
      );
      crackPaint.color = const Color(0xAAFFFFFF);
      crackPaint.strokeWidth = 0.6;
    }

    // Brillo central
    final glowPaint = Paint()
      ..color = const Color(0x50FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(cx, cy), 8, glowPaint);

    // Reflejos de luz en la superficie
    final shinePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x30FFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromCircle(center: Offset(10, 10), radius: 14));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(14, 12), width: 20, height: 14),
      shinePaint,
    );
  }

  double _cos(double a) => math.cos(a);
  double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(IcePainter _) => false;
}

// ── Volcánico ─────────────────────────────────────────────────
class VolcanicPainter extends CustomPainter {
  const VolcanicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Veladura volcánica semi-transparente
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0x662A1008));

    // Grietas de lava
    final lavaPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFF6010);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0x40FF4000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final random = _SeededRandom(7);
    for (int i = 0; i < 5; i++) {
      final path = _randomCrack(random, size);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, lavaPaint);
    }

    // Cenizas / puntos oscuros
    final ashPaint = Paint()..color = const Color(0x553A2010);
    for (int i = 0; i < 8; i++) {
      final r = _SeededRandom(i * 13 + 5);
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        2 + r.nextDouble() * 4,
        ashPaint,
      );
    }
  }

  Path _randomCrack(_SeededRandom r, Size size) {
    final path = Path();
    final startX = r.nextDouble() * size.width;
    final startY = r.nextDouble() * size.height;
    path.moveTo(startX, startY);
    double x = startX, y = startY;
    for (int s = 0; s < 4; s++) {
      x += (r.nextDouble() - 0.5) * size.width * 0.5;
      y += (r.nextDouble() - 0.5) * size.height * 0.5;
      x = x.clamp(0, size.width);
      y = y.clamp(0, size.height);
      path.lineTo(x, y);
    }
    return path;
  }

  @override
  bool shouldRepaint(VolcanicPainter _) => false;
}

// ── Desierto ──────────────────────────────────────────────────
class DesertPainter extends CustomPainter {
  const DesertPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Veladura arena semi-transparente
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0x55D4A850));

    // Dunas: ondas suaves
    final dunePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    final random = _SeededRandom(13);
    for (int i = 0; i < 5; i++) {
      final baseY = (i + 0.5) * size.height / 5;
      dunePaint.color = Color.lerp(
        const Color(0x30E8C060),
        const Color(0x30805010),
        i / 5,
      )!;
      final path = Path()..moveTo(0, baseY);
      double x = 0;
      while (x < size.width) {
        final waveW = 12 + random.nextDouble() * 16;
        final waveH = 1 + random.nextDouble() * 3;
        path.quadraticBezierTo(x + waveW / 2, baseY - waveH, x + waveW, baseY);
        x += waveW;
      }
      canvas.drawPath(path, dunePaint);
    }

    // Granos de arena
    final grainPaint = Paint()..color = const Color(0x40A07820);
    for (int i = 0; i < 20; i++) {
      final r = _SeededRandom(i * 7 + 3);
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        0.8,
        grainPaint,
      );
    }

    // Brillo de calor en la esquina sup-izq
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.width * 0.2, size.height * 0.2),
          width: 24,
          height: 16),
      Paint()
        ..color = const Color(0x20FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(DesertPainter _) => false;
}

// ── Utilidad: generador pseudo-aleatorio con semilla ──────────
class _SeededRandom {
  int _seed;
  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = (_seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_seed & 0x7FFFFFFF) / 0x7FFFFFFF;
  }
}

// ── Widget helper ─────────────────────────────────────────────
CustomPainter? terrainPainter(TerrainOverlay t) {
  switch (t) {
    case TerrainOverlay.grass:
      return const GrassPainter();
    case TerrainOverlay.ice:
      return const IcePainter();
    case TerrainOverlay.volcanic:
      return const VolcanicPainter();
    case TerrainOverlay.desert:
      return const DesertPainter();
    case TerrainOverlay.none:
      return null;
  }
}
