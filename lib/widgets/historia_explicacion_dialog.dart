// lib/widgets/historia_explicacion_dialog.dart
//
// VENTANA EXPLICATIVA de las batallas del modo historia. Sale ANTES de empezar
// a jugar (turno 1) y cuenta cómo funciona la batalla:
//
//   • Las secciones propias de la batalla las genera el servidor a partir de
//     su definición y llegan en `historia.explicacion`
//     ([{icono, titulo, texto}, …], ver WarZeroHistoriaExplicacion.cs):
//     objetivo, derrota, tropas, enemigo, bombardeo, casillas desactivadoras…
//   • Las reglas GENERALES del modo historia (turnos por tiempo, abandonar,
//     volver a la parte 1) se añaden aquí, porque dependen del cliente
//     (duración real del turno).
//
// Es bloqueante: no se cierra tocando fuera ni con el botón atrás. Devuelve
// true si el jugador pulsa «¡A LA BATALLA!» y false si pulsa «SALIR» (el
// llamador abandona la batalla).
//
// RETOS: la misma ventana sale al empezar un reto.
//   • Reto sobre el motor de historia (`historia.esReto`): igual que una
//     batalla, con las reglas del reto en vez de las del modo historia.
//   • Reto de partida normal: `mostrarExplicacionReto`, con las secciones de
//     `reto.explicacion` (WarZeroRetos.ConstruirExplicacionReto).

import 'package:flutter/material.dart';

const Color _oro = Color(0xFFC8A860);
const Color _tenue = Color(0xFF6A7A8A);
const Color _texto = Color(0xFFD8D0B8);
const Color _fondo = Color(0xFF0A1220);
const Color _panel = Color(0xFF0E1A2C);

/// Una sección de la ventana.
class _Seccion {
  final String icono;
  final String titulo;
  final String texto;
  const _Seccion(this.icono, this.titulo, this.texto);
}

/// Muestra la ventana explicativa de la batalla [historia] (el campo
/// `historia` del estado de la partida). [segundosTurno] es la duración del
/// turno en partida rápida. Devuelve true = jugar, false = salir.
Future<bool> mostrarExplicacionHistoria(
  BuildContext context, {
  required Map<String, dynamic> historia,
  required int segundosTurno,
}) async {
  final secciones = <_Seccion>[];

  final raw = historia['explicacion'];
  if (raw is List) {
    for (final s in raw) {
      if (s is! Map) continue;
      final texto = (s['texto'] ?? '').toString().trim();
      if (texto.isEmpty) continue;
      secciones.add(_Seccion(
        (s['icono'] ?? '•').toString(),
        (s['titulo'] ?? '').toString(),
        texto,
      ));
    }
  }

  // Partidas creadas antes de que existiera `explicacion`: al menos el
  // objetivo, deducido de los campos de siempre.
  if (secciones.isEmpty) {
    final turnos = (historia['turnosSupervivencia'] as num?)?.toInt() ?? 0;
    final conquistar = historia['jugadorObjetivo'] == 'conquistar';
    secciones.add(_Seccion(
      '🎯',
      'Objetivo',
      conquistar
          ? 'Conquista el cuartel enemigo.'
          : 'Resiste hasta cerrar el turno $turnos sin que conquisten tu cuartel.',
    ));
  }

  final esReto = historia['esReto'] == true;
  if (esReto) {
    secciones.add(_Seccion(
        '⏱',
        'Reglas del reto',
        [
          '• Turnos por tiempo: tienes $segundosTurno segundos por turno. El reloj '
              'arranca al cerrar el informe del turno anterior (en el primer turno, '
              'al cerrar esta ventana). Si se agota, el turno se cierra con lo que '
              'hayas hecho.',
          '• Si sales de la partida (o cierras la app) ABANDONAS el reto: tendrás '
              'que empezarlo de nuevo.',
          '• Este reto no aparece en tus partidas en curso.',
        ].join('\n')));
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) => PopScope(
        canPop: false,
        child: _VentanaExplicacion(
          titulo: (historia['titulo'] ?? 'Reto')
              .toString()
              .replaceFirst(RegExp(r'^Reto\s*·\s*'), ''),
          subtitulo: 'RETO',
          secciones: secciones,
        ),
      ),
    );
    return r ?? true;
  }

  // Reglas generales del modo historia.
  final partes = (historia['partes'] as num?)?.toInt() ?? 1;
  secciones.add(_Seccion(
    '⏱',
    'Reglas del modo historia',
    [
      '• Turnos por tiempo: tienes $segundosTurno segundos por turno. El reloj '
          'arranca al cerrar el informe del turno anterior (en el primer turno, '
          'al cerrar esta ventana). Si se agota, el turno se cierra con lo que '
          'hayas hecho.',
      '• Si sales de la partida (o cierras la app) la ABANDONAS: la batalla '
          'se cierra y tendrás que empezar la historia de nuevo'
          '${partes > 1 ? ' desde la parte 1' : ''}.',
      if (partes > 1)
        '• Tienes que superar las $partes partes seguidas: si pierdes cualquiera, '
            'vuelves a la parte 1.',
      '• Esta batalla no aparece en tus partidas en curso.',
    ].join('\n'),
  ));

  final titulo = (historia['titulo'] ?? 'Batalla').toString();
  final parte = (historia['parte'] as num?)?.toInt() ?? 1;

  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.85),
    builder: (ctx) => PopScope(
      canPop: false,
      child: _VentanaExplicacion(
        titulo: titulo,
        subtitulo: partes > 1 ? 'PARTE $parte DE $partes' : null,
        secciones: secciones,
      ),
    ),
  );
  return r ?? true;
}

/// Ventana explicativa de un RETO de partida normal ([reto] = el campo `reto`
/// del estado de la partida). [segundosTurno] es la duración del turno en
/// partida rápida (0 = sin límite de tiempo). Devuelve true = jugar, false =
/// salir (el reto sigue en curso y se puede reanudar desde Retos).
Future<bool> mostrarExplicacionReto(
  BuildContext context, {
  required Map<String, dynamic> reto,
  required int segundosTurno,
}) async {
  final secciones = <_Seccion>[];
  final raw = reto['explicacion'];
  if (raw is List) {
    for (final s in raw) {
      if (s is! Map) continue;
      final texto = (s['texto'] ?? '').toString().trim();
      if (texto.isEmpty) continue;
      secciones.add(_Seccion(
        (s['icono'] ?? '•').toString(),
        (s['titulo'] ?? '').toString(),
        texto,
      ));
    }
  }
  if (secciones.isEmpty) {
    final desc = (reto['descripcion'] ?? '').toString();
    if (desc.isNotEmpty) secciones.add(_Seccion('📜', 'El reto', desc));
  }

  secciones.add(_Seccion(
      '⏱',
      'Reglas del reto',
      [
        if (segundosTurno > 0)
          '• Turnos por tiempo: tienes $segundosTurno segundos por turno. Si se '
              'agota, el turno se cierra con lo que hayas hecho.',
        '• Si sales, el reto sigue en curso: vuelve a entrar desde la pantalla de '
            'Retos y lo reanudas donde lo dejaste.',
        '• Si lo pierdes, puedes volver a intentarlo cuando quieras.',
      ].join('\n')));

  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.85),
    builder: (ctx) => PopScope(
      canPop: false,
      child: _VentanaExplicacion(
        titulo: (reto['titulo'] ?? 'Reto').toString(),
        subtitulo: 'RETO',
        secciones: secciones,
      ),
    ),
  );
  return r ?? true;
}

class _VentanaExplicacion extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<_Seccion> secciones;

  const _VentanaExplicacion({
    required this.titulo,
    required this.subtitulo,
    required this.secciones,
  });

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: _fondo,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _oro.withOpacity(0.45)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: alto * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cabecera ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Column(
                children: [
                  if (subtitulo != null)
                    Text(
                      subtitulo!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 9,
                        letterSpacing: 2.5,
                        color: _tenue,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    titulo.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 14,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                      color: _oro,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _oro.withOpacity(0.2)),
            // ── Secciones ────────────────────────────────────────────
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                itemCount: secciones.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _TarjetaSeccion(seccion: secciones[i]),
              ),
            ),
            Divider(height: 1, color: _oro.withOpacity(0.2)),
            // ── Botones ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'SALIR',
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: _tenue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: _oro.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _oro.withOpacity(0.7)),
                      ),
                      child: const Text(
                        '¡A LA BATALLA!',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          color: _oro,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaSeccion extends StatelessWidget {
  final _Seccion seccion;
  const _TarjetaSeccion({required this.seccion});

  @override
  Widget build(BuildContext context) {
    final lineas = seccion.texto.split('\n');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _oro.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(seccion.icono, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  seccion.titulo.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    color: _oro,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in lineas)
            if (l.trim().isNotEmpty) _Linea(texto: l),
        ],
      ),
    );
  }
}

/// Una línea de texto; las que empiezan por "• " se pintan como viñeta con
/// sangría.
class _Linea extends StatelessWidget {
  final String texto;
  const _Linea({required this.texto});

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontSize: 11.5, height: 1.45, color: _texto);
    final t = texto.trimRight();
    if (t.startsWith('• ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(color: _oro, height: 1.45)),
            Expanded(child: Text(t.substring(2), style: estilo)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(t, style: estilo),
    );
  }
}
