// lib/views/diagnostico_screen.dart
//
// PANTALLA DE DIAGNÓSTICO CRUD — independiente del juego.
//
// Objetivo: aislar QUÉ operación de Firestore falla en la tablet, sin el ruido
// de listeners, sondeos ni timers del game_screen. Cada botón ejecuta UNA
// operación CRUD pura y muestra en pantalla el tiempo que tardó y el resultado.
//
// Cómo usarla: navega aquí pasando un lobbyId de una partida real (o usa el
// botón "Crear doc de prueba" para generar uno). Pulsa cada prueba en orden y
// anota cuáles tardan o fallan. Con eso sabremos si el problema es:
//   - escribir (update / set)
//   - leer del servidor (get Source.server)
//   - leer de caché (get Source.cache)
//   - el tamaño del documento (prueba de escritura grande)
//
// Esta pantalla NO depende de ningún modelo del juego: usa Map<String,dynamic>
// directamente para no arrastrar dependencias.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DiagnosticoScreen extends StatefulWidget {
  /// ID de una partida existente para probar lecturas reales. Si es null, usa
  /// un documento de prueba propio (colección 'Diagnostico').
  final String? lobbyId;

  const DiagnosticoScreen({super.key, this.lobbyId});

  @override
  State<DiagnosticoScreen> createState() => _DiagnosticoScreenState();
}

class _DiagnosticoScreenState extends State<DiagnosticoScreen> {
  final _db = FirebaseFirestore.instance;
  final List<_LogEntry> _log = [];
  bool _ocupado = false;

  late final String _miUid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';

  // ID de la partida, editable desde la propia pantalla.
  late final TextEditingController _lobbyCtrl =
      TextEditingController(text: widget.lobbyId ?? '');

  String? get _lobbyId {
    final t = _lobbyCtrl.text.trim();
    return t.isEmpty ? null : t;
  }

  DocumentReference<Map<String, dynamic>> get _refPartida =>
      _db.collection('Partidas').doc(_lobbyId);

  // Documento de prueba DENTRO del propio jugador, donde las reglas SÍ
  // conceden permiso al dueño. Así la prueba mide la RED, no los permisos.
  DocumentReference<Map<String, dynamic>> get _refPrueba =>
      _db.collection('Jugadores').doc(_miUid);

  // Partidas del usuario, para el desplegable. Cada entrada: id + descripción.
  List<_PartidaItem> _misPartidas = [];

  @override
  void dispose() {
    _lobbyCtrl.dispose();
    super.dispose();
  }

  void _add(String titulo, String detalle, {bool error = false}) {
    setState(() {
      _log.insert(
          0,
          _LogEntry(
            titulo: titulo,
            detalle: detalle,
            error: error,
            hora: TimeOfDay.now().format(context),
          ));
    });
  }

  /// Ejecuta [accion] midiendo el tiempo y capturando errores.
  Future<void> _medir(String nombre, Future<String> Function() accion) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final sw = Stopwatch()..start();
    try {
      final resultado = await accion();
      sw.stop();
      _add('✅ $nombre', '${sw.elapsedMilliseconds} ms · $resultado');
    } catch (e) {
      sw.stop();
      _add('❌ $nombre', '${sw.elapsedMilliseconds} ms · ${e.runtimeType}: $e',
          error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // PRUEBAS
  // ─────────────────────────────────────────────────────────

  // 1. Estado de la red de Firestore (info, no falla).
  Future<void> _infoRed() async {
    final u = FirebaseAuth.instance.currentUser;
    _add('ℹ️ Info',
        'uid: ${u?.uid ?? 'NULL'} · lobbyId: ${_lobbyId ?? '(ninguno)'}');
  }

  // ★★ TEST DE FUGA DE LISTENERS — simula tu ciclo entrar/salir de la partida.
  //
  // Firebase recomienda < 100 listeners de snapshots por cliente; en el plan
  // gratuito el límite de conexiones es 100. Si cada entrada a la partida deja
  // un listener abierto (no se cancela al salir), se van acumulando hasta que
  // TODAS las operaciones nuevas se cuelgan — justo la degradación que has
  // descrito (al principio va, luego nada va hasta reiniciar).
  //
  // Esta prueba abre N listeners sobre la partida, mide cuánto tarda una
  // lectura simple DESPUÉS de abrirlos (sin cerrarlos), luego los cierra y
  // vuelve a medir. Si la lectura se degrada con los listeners abiertos y
  // mejora al cerrarlos, hay fuga de listeners en el juego.
  Future<void> _testFugaListeners() async {
    if (_ocupado) return;
    if (_lobbyId == null) {
      _add('⚠️ Test fuga', 'Elige una partida primero (Cargar mis partidas).',
          error: true);
      return;
    }
    setState(() => _ocupado = true);
    _add('🧪 Test de fuga de listeners', 'Abriendo 30 listeners…');

    final subs = <StreamSubscription>[];
    try {
      // 1) Medir lectura ANTES.
      final t0 = await _medirLecturaServidor();

      // 2) Abrir 30 listeners y NO cerrarlos (simula 30 entradas con fuga).
      for (int i = 0; i < 30; i++) {
        subs.add(_refPartida.snapshots().listen((_) {}, onError: (_) {}));
      }
      await Future.delayed(const Duration(milliseconds: 1500));

      // 3) Medir lectura CON los 30 listeners abiertos.
      final t1 = await _medirLecturaServidor();

      // 4) Cerrar todos.
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
      await Future.delayed(const Duration(milliseconds: 1500));

      // 5) Medir lectura DESPUÉS de cerrarlos.
      final t2 = await _medirLecturaServidor();

      final degrada = t1 < 0 || (t0 >= 0 && t1 > t0 * 3);
      final recupera = t2 >= 0 && (t1 < 0 || t2 < t1);

      String veredicto;
      bool err;
      if (degrada && recupera) {
        veredicto = '⛔ HAY FUGA DE LISTENERS. Con 30 listeners abiertos la '
            'lectura se degradó (${_ms(t0)} → ${_ms(t1)}) y al cerrarlos se '
            'recuperó (${_ms(t2)}). En el juego, cada entrada a la partida '
            'está dejando un listener abierto. SOLUCIÓN: cancelar la '
            'suscripción al salir de la pantalla (en dispose).';
        err = true;
      } else if (t1 < 0) {
        veredicto = '⛔ Con 30 listeners abiertos, la lectura se COLGÓ '
            '(timeout). Es exactamente el límite de conexiones. Confirma fuga '
            'de listeners en el juego.';
        err = true;
      } else {
        veredicto = '✅ Sin degradación notable (${_ms(t0)} → ${_ms(t1)} → '
            '${_ms(t2)}). 30 listeners no saturan; si el juego falla, la fuga '
            'puede ser mayor o estar en otra parte.';
        err = false;
      }
      _add(err ? '❌ Test de fuga de listeners' : '✅ Test de fuga de listeners',
          veredicto,
          error: err);
    } catch (e) {
      _add('❌ Test de fuga de listeners', '${e.runtimeType}: $e', error: true);
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Lee la partida del servidor y devuelve los ms, o -1 si falla/timeout.
  Future<int> _medirLecturaServidor() async {
    final sw = Stopwatch()..start();
    try {
      await _refPartida
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  String _ms(int v) => v < 0 ? 'TIMEOUT' : '$v ms';

  // ★ Cargar las partidas donde el usuario es participante, para el desplegable.
  // Si la consulta por 'participantes' falla (índice o regla), cae a leer todas
  // las partidas visibles y filtrar en cliente.
  Future<void> _cargarMisPartidas() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    _add('🔄 Cargar mis partidas', 'Buscando uid=$_miUid …');
    try {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      try {
        // Vía principal: filtro en servidor por participantes.
        final q = await _db
            .collection('Partidas')
            .where('participantes', arrayContains: _miUid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
        docs = q.docs;
      } catch (_) {
        // Fallback: leer todas y filtrar en cliente (por si falta índice).
        final q = await _db
            .collection('Partidas')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));
        docs = q.docs.where((d) {
          final parts =
              List<String>.from(d.data()['participantes'] as List? ?? []);
          final jug = (d.data()['jugadores'] as List? ?? [])
              .map((j) => (j as Map)['uid'] as String?)
              .whereType<String>()
              .toList();
          return parts.contains(_miUid) || jug.contains(_miUid);
        }).toList();
      }

      final items = <_PartidaItem>[];
      for (final d in docs) {
        final data = d.data();
        final turno = data['turnoActual'] ?? '?';
        final estado = data['estado'] ?? '?';
        final nJug = (data['jugadores'] as List?)?.length ?? 0;
        items.add(_PartidaItem(
          id: d.id,
          desc: 'turno $turno · $estado · $nJug jug.',
        ));
      }
      setState(() => _misPartidas = items);

      if (items.isEmpty) {
        _add(
            '⚠️ Mis partidas',
            'No hay ninguna partida donde tu uid ($_miUid) sea participante. '
                'Si esperabas alguna, es que la app te ha logueado con un '
                'USUARIO DISTINTO al que está en la partida.',
            error: true);
      } else {
        _add('✅ Mis partidas',
            '${items.length} partida(s). Toca un chip de abajo para usar su ID.');
      }
    } catch (e) {
      _add('❌ Cargar mis partidas', '${e.runtimeType}: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ★ Diagnóstico de lectura de la partida indicada: dice el MOTIVO exacto si
  // falla (permiso vs no existe) y si tu uid está entre los jugadores.
  Future<void> _diagnosticarPartida() async {
    if (_ocupado) return;
    if (_lobbyId == null) {
      _add('⚠️ Diagnóstico partida', 'Escribe o elige un ID primero.',
          error: true);
      return;
    }
    setState(() => _ocupado = true);
    _add('🔬 Diagnóstico de PARTIDA', 'Leyendo ${_lobbyId!} …');
    try {
      DocumentSnapshot<Map<String, dynamic>> s;
      try {
        s = await _refPartida
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
      } on FirebaseException catch (fe) {
        if (fe.code == 'permission-denied') {
          _add(
              '⛔ Diagnóstico de PARTIDA',
              'PERMISSION-DENIED al leer. La regla de lectura desplegada NO '
                  'permite a tu usuario leer esta partida. Revisa que la regla '
                  'de Partidas sea "allow read: if request.auth != null" (y '
                  'vuelve a desplegarla), o que tu uid esté autorizado.',
              error: true);
          if (mounted) setState(() => _ocupado = false);
          return;
        }
        rethrow;
      }

      if (!s.exists) {
        _add(
            '⛔ Diagnóstico de PARTIDA',
            'La lectura respondió OK pero el documento NO EXISTE con ese ID.\n'
                'Casi seguro el ID está mal copiado (un carácter distinto). '
                'Compáralo con la consola, o usa "Cargar mis partidas" y elige '
                'de la lista.',
            error: true);
        if (mounted) setState(() => _ocupado = false);
        return;
      }

      // Existe: comprobar si mi uid está dentro.
      final data = s.data()!;
      final parts = List<String>.from(data['participantes'] as List? ?? []);
      final jug = (data['jugadores'] as List? ?? [])
          .map((j) => (j as Map)['uid'] as String?)
          .whereType<String>()
          .toList();
      final enParticipantes = parts.contains(_miUid);
      final enJugadores = jug.contains(_miUid);
      final turno = data['turnoActual'];
      final cerrados =
          List<String>.from(data['cerradoPor'] as List? ?? []).length;

      final ok = enParticipantes && enJugadores;
      _add(
          ok ? '✅ Diagnóstico de PARTIDA' : '⚠️ Diagnóstico de PARTIDA',
          'EXISTE · turno=$turno · cerradoPor=$cerrados\n'
          'Tu uid: $_miUid\n'
          'En participantes: ${enParticipantes ? 'SÍ' : 'NO'} · '
          'En jugadores: ${enJugadores ? 'SÍ' : 'NO'}\n'
          '${ok ? 'Todo correcto: puedes operar en esta partida.' : '⚠️ Tu usuario NO forma parte de esta partida. Por eso el juego puede fallar al cerrar turno: estás logueado con una cuenta distinta a la que está en la partida.'}',
          error: !ok);
    } catch (e) {
      _add('❌ Diagnóstico de PARTIDA', '${e.runtimeType}: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ★ PRUEBA CLAVE: detecta el fallo de contexto SSL / Google Play Services.
  //
  // El síntoma del error "Failed to update ssl context:
  // GooglePlayServicesNotAvailableException" es inequívoco: la CACHÉ responde
  // al instante, pero cualquier ida y vuelta al SERVIDOR se cuelga hasta el
  // timeout porque el canal gRPC seguro nunca llega a establecerse.
  //
  // Esta prueba: (1) escribe un valor único en TU perfil, (2) intenta leerlo
  // del SERVIDOR con timeout corto. Si la escritura "vuelve" pero la lectura de
  // servidor expira, es el patrón exacto de Play Services / SSL roto. Da un
  // veredicto en texto claro.
  Future<void> _pruebaServiciosGoogle() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    _add('🔬 Test Google Play / SSL', 'Ejecutando…');

    final marca = 'ssl_${DateTime.now().millisecondsSinceEpoch}';
    int msEscritura = -1;
    int msServidor = -1;
    int msCache = -1;
    String escrituraErr = '';
    String servidorErr = '';
    String cacheErr = '';

    // 1) Escritura.
    final sw1 = Stopwatch()..start();
    try {
      await _refPrueba.set({'_diagSsl': marca},
          SetOptions(merge: true)).timeout(const Duration(seconds: 12));
      msEscritura = sw1.elapsedMilliseconds;
    } catch (e) {
      msEscritura = sw1.elapsedMilliseconds;
      escrituraErr = '${e.runtimeType}';
    }

    // 2) Lectura SERVIDOR (timeout corto: si SSL está roto, expira).
    final sw2 = Stopwatch()..start();
    String leidoServidor = '';
    try {
      final s = await _refPrueba
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      msServidor = sw2.elapsedMilliseconds;
      leidoServidor = '${s.data()?['_diagSsl']}';
    } catch (e) {
      msServidor = sw2.elapsedMilliseconds;
      servidorErr = '${e.runtimeType}';
    }

    // 3) Lectura CACHÉ (debe ir rápida pase lo que pase).
    final sw3 = Stopwatch()..start();
    try {
      await _refPrueba
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 6));
      msCache = sw3.elapsedMilliseconds;
    } catch (e) {
      msCache = sw3.elapsedMilliseconds;
      cacheErr = '${e.runtimeType}';
    }

    // ── Veredicto ──
    final escOk = escrituraErr.isEmpty;
    final srvOk = servidorErr.isEmpty && leidoServidor == marca;
    final srvTimeout = servidorErr.contains('Timeout');

    String veredicto;
    bool esError;
    if (srvOk) {
      veredicto = '✅ CONEXIÓN SANA. El servidor responde y devuelve el dato '
          'recién escrito. Firestore funciona correctamente en este '
          'dispositivo: el problema NO es Google Play Services.';
      esError = false;
    } else if (escOk && srvTimeout) {
      veredicto = '⛔ DIAGNÓSTICO: GOOGLE PLAY SERVICES / SSL.\n'
          'La escritura volvió ($msEscritura ms) pero la lectura de SERVIDOR '
          'expiró ($msServidor ms) mientras la caché va rápida ($msCache ms). '
          'Es el patrón exacto de "Failed to update ssl context: '
          'GooglePlayServicesNotAvailableException". El canal seguro de '
          'Firestore no se establece.\n'
          'SOLUCIÓN: actualiza Google Play Services en este dispositivo desde '
          'la Play Store, o úsalo en un dispositivo/emulador con Play Store.';
      esError = true;
    } else if (!escOk && !srvOk) {
      veredicto = '⚠️ Ni escritura ni lectura de servidor funcionaron '
          '(escritura: ${escrituraErr.isEmpty ? 'ok' : escrituraErr}, '
          'servidor: ${servidorErr.isEmpty ? 'ok' : servidorErr}). '
          'Revisa permisos/conexión.';
      esError = true;
    } else {
      veredicto = 'Resultado mixto. Escritura: '
          '${escOk ? '$msEscritura ms ok' : escrituraErr}. '
          'Servidor: ${srvOk ? '$msServidor ms ok' : (servidorErr.isEmpty ? 'dato no coincide' : servidorErr)}. '
          'Caché: ${cacheErr.isEmpty ? '$msCache ms ok' : cacheErr}.';
      esError = true;
    }

    _add(
        esError ? '❌ Test Google Play / SSL' : '✅ Test Google Play / SSL',
        'Escritura: ${escOk ? '$msEscritura ms' : escrituraErr}  ·  '
        'Servidor: ${srvOk ? '$msServidor ms' : (servidorErr.isEmpty ? 'dato≠' : servidorErr)}  ·  '
        'Caché: ${cacheErr.isEmpty ? '$msCache ms' : cacheErr}\n\n$veredicto',
        error: esError);

    if (mounted) setState(() => _ocupado = false);
  }

  // 2. Escritura pequeña (merge de un campo de diagnóstico en el propio perfil).
  Future<void> _pruebaEscrituraPequena() => _medir(
        'Escritura pequeña (set merge)',
        () async {
          await _refPrueba.set(
              {'_diagPing': DateTime.now().toUtc().toIso8601String()},
              SetOptions(merge: true)).timeout(const Duration(seconds: 15));
          return 'campo "_diagPing" escrito en mi perfil';
        },
      );

  // ★★★ PRUEBA: escribir un campo inocuo al documento REAL de la partida.
  //
  // Usa el ID que hayas puesto arriba (debe ser una partida REAL donde seas
  // participante). Escribe un campo '_diagTest' y lo confirma leyendo del
  // servidor. Si ESTO se cuelga pero las escrituras a 'prueba' van bien,
  // el problema es ESTE documento concreto (su tamaño/estructura/historial).
  Future<void> _pruebaEscribirEnPartidaReal() async {
    if (_ocupado) return;
    if (_lobbyId == null) {
      _add('⚠️ Escribir en partida real',
          'Pon el ID REAL de una partida arriba (usa "Cargar mis partidas").',
          error: true);
      return;
    }
    setState(() => _ocupado = true);
    final marca = 'real_${DateTime.now().millisecondsSinceEpoch}';
    _add('🔬 Escribir en PARTIDA REAL', 'Doc ${_lobbyId!} · marca=$marca');

    // 1. UPDATE de un campo inocuo al documento real.
    final sw1 = Stopwatch()..start();
    try {
      await _refPartida
          .update({'_diagTest': marca}).timeout(const Duration(seconds: 12));
      _add('✅ UPDATE partida real',
          '${sw1.elapsedMilliseconds} ms (guardado, puede ser solo local)');
    } on FirebaseException catch (fe) {
      _add('🟥 UPDATE partida real',
          '${sw1.elapsedMilliseconds} ms — code="${fe.code}" msg="${fe.message}"',
          error: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    } catch (e) {
      _add(
          '🟥 UPDATE partida real',
          '${sw1.elapsedMilliseconds} ms — ${e.runtimeType} (TIMEOUT = el '
              'documento real no acepta escrituras)',
          error: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    }

    await Future.delayed(const Duration(seconds: 2));

    // 2. Leer forzando servidor para confirmar que subió.
    final sw2 = Stopwatch()..start();
    try {
      final s = await _refPartida
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      final leido = s.data()?['_diagTest'];
      if (leido == marca) {
        _add(
            '🟢 PARTIDA REAL: CONFIRMADO',
            'El servidor tiene la marca (${sw2.elapsedMilliseconds} ms). '
                'Escribir al documento real SÍ funciona. El problema del cierre '
                'NO es este documento.');
      } else {
        _add(
            '⛔ PARTIDA REAL: NO SUBIÓ',
            'UPDATE dio OK pero el servidor NO tiene la marca (tiene "$leido"). '
                'La escritura a ESTE documento se queda en local y no sube. '
                'El problema es específico de este documento.',
            error: true);
      }
    } catch (e) {
      _add('⛔ PARTIDA REAL: lectura servidor falló',
          '${sw2.elapsedMilliseconds} ms — ${e.runtimeType}',
          error: true);
    }

    if (mounted) setState(() => _ocupado = false);
  }

  // ★★★ PRUEBA DEFINITIVA: ¿la escritura llega al SERVIDOR o se queda en local?
  //
  // Con persistencia activada, una escritura devuelve "OK" en cuanto se guarda
  // en la CACHÉ LOCAL, aunque no haya llegado al servidor. Si el canal está
  // roto, la app cree que escribió pero en Firebase no aparece nada (justo lo
  // que has observado). Esta prueba escribe un valor único y luego lo lee
  // FORZANDO SERVIDOR: si el servidor devuelve el valor, la escritura subió de
  // verdad; si no, se quedó atrapada en local.
  Future<void> _pruebaLlegaAlServidor() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final marca = 'srv_${DateTime.now().millisecondsSinceEpoch}';
    final ref = _db.collection('prueba').doc('confirm_$_miUid');
    _add('🔬 ¿Llega al servidor?', 'Escribiendo marca=$marca …');

    // 1. Escribir (con persistencia, devuelve OK en cuanto está en local).
    final sw1 = Stopwatch()..start();
    try {
      await ref.set({'marca': marca}, SetOptions(merge: true)).timeout(
          const Duration(seconds: 12));
      _add(
          '✅ Escritura local',
          '${sw1.elapsedMilliseconds} ms (guardado, '
              'puede ser solo local)');
    } catch (e) {
      _add('🟥 Escritura', '${sw1.elapsedMilliseconds} ms — ${e.runtimeType}',
          error: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    }

    // 2. Esperar 2 s para dar tiempo a la sincronización con el servidor.
    await Future.delayed(const Duration(seconds: 2));

    // 3. Leer FORZANDO servidor. Si devuelve la marca, la escritura subió.
    final sw2 = Stopwatch()..start();
    try {
      final s = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      final leido = s.data()?['marca'];
      if (leido == marca) {
        _add(
            '🟢 CONFIRMADO EN SERVIDOR',
            'El servidor devolvió la marca (${sw2.elapsedMilliseconds} ms). '
                'Las escrituras SÍ llegan al servidor. El canal de escritura está '
                'sano.');
      } else {
        _add(
            '⛔ NO LLEGÓ AL SERVIDOR',
            'La escritura dio OK pero el servidor NO tiene la marca '
                '(devolvió "$leido"). La escritura se quedó en la CACHÉ LOCAL y no '
                'subió. ESTE es el problema: el canal de escritura de la tablet al '
                'servidor no está completando las subidas.',
            error: true);
      }
    } catch (e) {
      _add(
          '⛔ NO LLEGÓ AL SERVIDOR (lectura servidor falló)',
          '${sw2.elapsedMilliseconds} ms — ${e.runtimeType}. La lectura de '
              'servidor se colgó, lo que confirma que el canal de la tablet al '
              'servidor está roto (lee y escribe solo en local).',
          error: true);
    }

    if (mounted) setState(() => _ocupado = false);
  }

  // ★★ PRUEBA CLAVE: escribir en la colección PARTIDAS con un doc de prueba.
  //
  // Aísla si el problema es: (a) la colección Partidas/el transporte gRPC, o
  // (b) algo del documento concreto de la partida. Hace 3 escrituras a un doc
  // de prueba NUEVO dentro de Partidas, donde el propio usuario es
  // participante (para cumplir tus reglas):
  //   1. CREATE  → ¿se puede crear en Partidas?
  //   2. UPDATE simple (un campo) → ¿funciona el update con isParticipante?
  //   3. UPDATE con arrayUnion → replica EXACTAMENTE lo que hace cerrarTurno.
  //
  // Si las 3 funcionan → el problema NO es la colección ni gRPC; es el documento
  // real de la partida (o su regla evaluándose raro). REST no sería la solución.
  // Si la 1 o 2 o 3 se cuelga → es la colección/transporte; REST tiene sentido.
  Future<void> _pruebaEscrituraEnPartidas() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final docId = 'diag_${FirebaseAuth.instance.currentUser?.uid ?? 'anon'}';
    final ref = _db.collection('Partidas').doc(docId);
    _add('🧪 Escritura en PARTIDAS', 'Probando doc de prueba: $docId');

    // 1. CREATE (con el usuario como host y participante, para cumplir reglas).
    final sw1 = Stopwatch()..start();
    try {
      await ref.set({
        'hostUid': _miUid,
        'participantes': [_miUid],
        'estado': 'diag',
        'jugadores': [],
        'maxJugadores': 2,
        '_diag': DateTime.now().toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 12));
      _add('✅ 1·CREATE en Partidas', '${sw1.elapsedMilliseconds} ms — OK');
    } catch (e) {
      _add('❌ 1·CREATE en Partidas',
          '${sw1.elapsedMilliseconds} ms — ${e.runtimeType}: $e',
          error: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    }

    // 2. UPDATE simple (un campo). Igual que el paso que cuelga, sin arrayUnion.
    final sw2 = Stopwatch()..start();
    try {
      await ref.update({
        '_diagUpdate': DateTime.now().toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 12));
      _add('✅ 2·UPDATE simple en Partidas',
          '${sw2.elapsedMilliseconds} ms — OK');
    } catch (e) {
      _add('❌ 2·UPDATE simple en Partidas',
          '${sw2.elapsedMilliseconds} ms — ${e.runtimeType}: $e',
          error: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    }

    // 3. UPDATE con arrayUnion — EXACTAMENTE lo que hace cerrarTurno (paso 1).
    final sw3 = Stopwatch()..start();
    try {
      await ref.update({
        'cerradoPor': FieldValue.arrayUnion([_miUid]),
      }).timeout(const Duration(seconds: 12));
      _add('✅ 3·UPDATE arrayUnion en Partidas',
          '${sw3.elapsedMilliseconds} ms — OK');
    } catch (e) {
      _add('❌ 3·UPDATE arrayUnion en Partidas',
          '${sw3.elapsedMilliseconds} ms — ${e.runtimeType}: $e',
          error: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    }

    _add(
        '🟢 VEREDICTO',
        'Las 3 escrituras a Partidas funcionaron. El problema NO es la '
            'colección ni el transporte: es el DOCUMENTO concreto de la partida '
            '(o su regla isParticipante evaluándose con datos inesperados). '
            'REST NO sería la solución; hay que mirar el doc real / la regla.');

    // Limpieza: borrar el doc de prueba (somos host, la regla lo permite).
    try {
      await ref.delete().timeout(const Duration(seconds: 10));
    } catch (_) {}

    if (mounted) setState(() => _ocupado = false);
  }

  // 3. Lectura desde SERVIDOR del doc de prueba.
  Future<void> _pruebaLecturaServidorPrueba() => _medir(
        'Lectura SERVIDOR (mi perfil)',
        () async {
          final s = await _refPrueba
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 15));
          return s.exists
              ? 'existe, _diagPing=${s.data()?['_diagPing']}'
              : 'no existe';
        },
      );

  // 4. Lectura desde CACHÉ del doc de prueba.
  Future<void> _pruebaLecturaCachePrueba() => _medir(
        'Lectura CACHÉ (mi perfil)',
        () async {
          final s = await _refPrueba
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 15));
          return s.exists
              ? 'existe, _diagPing=${s.data()?['_diagPing']}'
              : 'no existe';
        },
      );

  // 5. Lectura por DEFECTO del doc de prueba (lo que hace el juego).
  Future<void> _pruebaLecturaDefectoPrueba() => _medir(
        'Lectura DEFECTO (mi perfil)',
        () async {
          final s = await _refPrueba.get().timeout(const Duration(seconds: 15));
          return s.exists ? 'existe' : 'no existe';
        },
      );

  // 6. Lectura SERVIDOR de la PARTIDA real (la que falla en el juego).
  Future<void> _pruebaLecturaPartidaServidor() => _medir(
        'Lectura SERVIDOR (PARTIDA real)',
        () async {
          if (_lobbyId == null) return 'sin lobbyId';
          final s = await _refPartida
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 20));
          if (!s.exists) return 'no existe';
          final data = s.data()!;
          final bytes = _estimarTamano(data);
          return 'turno=${data['turnoActual']} · ~$bytes bytes · '
              'cerradoPor=${(data['cerradoPor'] as List?)?.length ?? 0}';
        },
      );

  // 7. Lectura CACHÉ de la PARTIDA real.
  Future<void> _pruebaLecturaPartidaCache() => _medir(
        'Lectura CACHÉ (PARTIDA real)',
        () async {
          if (_lobbyId == null) return 'sin lobbyId';
          final s = await _refPartida
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 20));
          if (!s.exists) return 'no existe en caché';
          final data = s.data()!;
          final bytes = _estimarTamano(data);
          return 'turno=${data['turnoActual']} · ~$bytes bytes';
        },
      );

  // 8. Medir el TAMAÑO del documento de la partida (clave si supera ~1MB).
  Future<void> _pruebaTamanoPartida() => _medir(
        'Tamaño del doc PARTIDA',
        () async {
          if (_lobbyId == null) return 'sin lobbyId';
          DocumentSnapshot<Map<String, dynamic>> s;
          try {
            s = await _refPartida
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(seconds: 10));
            if (!s.exists) {
              s = await _refPartida
                  .get(const GetOptions(source: Source.server))
                  .timeout(const Duration(seconds: 20));
            }
          } catch (_) {
            s = await _refPartida
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 20));
          }
          if (!s.exists) return 'no existe';
          final data = s.data()!;
          final total = _estimarTamano(data);
          // Desglose por campo para ver qué ocupa más.
          final desglose = <String>[];
          data.forEach((k, v) {
            desglose.add('$k=${_estimarTamano(v)}');
          });
          desglose.sort((a, b) {
            final na = int.tryParse(a.split('=').last) ?? 0;
            final nb = int.tryParse(b.split('=').last) ?? 0;
            return nb.compareTo(na);
          });
          final top = desglose.take(5).join(' · ');
          final aviso = total > 800000
              ? '  ⚠️ CERCA DEL LÍMITE DE 1MB'
              : (total > 1000000 ? '  ⛔ SUPERA 1MB' : '');
          return '~$total bytes total$aviso\nTop campos: $top';
        },
      );

  // 9. Escritura GRANDE (simula el doc de partida creciendo).
  Future<void> _pruebaEscrituraGrande() => _medir(
        'Escritura GRANDE (~500KB)',
        () async {
          // Genera ~500 KB de datos para ver si una escritura grande se cuelga.
          final relleno = List.generate(
              5000, (i) => {'i': i, 'texto': 'x' * 80, 'n': i * 3.14});
          await _refPrueba.set({'_diagGrande': relleno},
              SetOptions(merge: true)).timeout(const Duration(seconds: 30));
          return 'escrito bloque grande (5000 items) en mi perfil';
        },
      );

  // 10. Limpiar los campos de diagnóstico del perfil (no borra el doc).
  Future<void> _limpiar() => _medir(
        'Borrar campos de diagnóstico',
        () async {
          await _refPrueba.set({
            '_diagPing': FieldValue.delete(),
            '_diagGrande': FieldValue.delete(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
          return 'campos _diag* borrados';
        },
      );

  /// Estima el tamaño en bytes de un valor serializado (aproximación JSON).
  int _estimarTamano(dynamic v) {
    if (v == null) return 4;
    if (v is num) return 8;
    if (v is bool) return 4;
    if (v is String) return v.length + 2;
    if (v is Timestamp) return 16;
    if (v is List) {
      var t = 2;
      for (final e in v) {
        t += _estimarTamano(e) + 1;
      }
      return t;
    }
    if (v is Map) {
      var t = 2;
      v.forEach((k, val) {
        t += '$k'.length + 2 + _estimarTamano(val) + 1;
      });
      return t;
    }
    return v.toString().length;
  }

  // ─────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1824),
        title: const Text('Diagnóstico Firestore',
            style: TextStyle(fontFamily: 'Cinzel', color: Color(0xFFC8A860))),
        iconTheme: const IconThemeData(color: Color(0xFFC8A860)),
      ),
      body: Column(
        children: [
          if (_ocupado)
            const LinearProgressIndicator(
                backgroundColor: Color(0xFF0F1824), color: Color(0xFFC8A860)),
          // Campo para introducir el ID de la partida.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: TextField(
              controller: _lobbyCtrl,
              style: const TextStyle(
                  color: Color(0xFFE0E0E0), fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'ID de la partida (lobbyId)',
                labelStyle: const TextStyle(color: Color(0xFFC8A860)),
                hintText: 'pega aquí el ID del documento de Partidas',
                hintStyle: const TextStyle(color: Color(0xFF5A6B7A)),
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0x55C8A860))),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC8A860))),
                isDense: true,
              ),
            ),
          ),
          // Chips con las partidas del usuario (tras "Cargar mis partidas").
          if (_misPartidas.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _misPartidas.map((p) {
                  final sel = p.id == _lobbyId;
                  return GestureDetector(
                    onTap: () => setState(() => _lobbyCtrl.text = p.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFFC8A860)
                            : const Color(0xFF12202E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x55C8A860)),
                      ),
                      child: Text(
                        '${p.id.substring(0, p.id.length > 8 ? 8 : p.id.length)}…  ${p.desc}',
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: sel
                                ? const Color(0xFF0A1018)
                                : const Color(0xFFB8C4D0)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn('Info', _infoRed),
                // Botón destacado: la prueba que da el veredicto.
                _btn('★ TEST GOOGLE PLAY / SSL', _pruebaServiciosGoogle,
                    destacado: true),
                _btn('🧪 ESCRIBIR EN PARTIDAS', _pruebaEscrituraEnPartidas,
                    destacado: true),
                _btn('🔬 ¿LLEGA AL SERVIDOR?', _pruebaLlegaAlServidor,
                    destacado: true),
                _btn(
                    '🎯 ESCRIBIR EN PARTIDA REAL', _pruebaEscribirEnPartidaReal,
                    destacado: true),
                _btn('📋 Cargar mis partidas', _cargarMisPartidas,
                    destacado: true),
                _btn('🔬 Diagnosticar PARTIDA', _diagnosticarPartida,
                    destacado: true),
                _btn('🧪 Test FUGA listeners', _testFugaListeners,
                    destacado: true),
                _btn('1· Escribir pequeño', _pruebaEscrituraPequena),
                _btn('2· Leer SERVIDOR prueba', _pruebaLecturaServidorPrueba),
                _btn('3· Leer CACHÉ prueba', _pruebaLecturaCachePrueba),
                _btn('4· Leer DEFECTO prueba', _pruebaLecturaDefectoPrueba),
                _btn('5· Leer SERVIDOR PARTIDA', _pruebaLecturaPartidaServidor),
                _btn('6· Leer CACHÉ PARTIDA', _pruebaLecturaPartidaCache),
                _btn('7· TAMAÑO partida', _pruebaTamanoPartida),
                _btn('8· Escribir GRANDE', _pruebaEscrituraGrande),
                _btn('Borrar prueba', _limpiar),
                _btn('Limpiar log', () async => setState(_log.clear)),
              ],
            ),
          ),
          const Divider(color: Color(0xFF223040), height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _log.length,
              itemBuilder: (_, i) {
                final e = _log[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: e.error
                        ? const Color(0x33FF5252)
                        : const Color(0x1FC8A860),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: e.error
                            ? const Color(0xFFFF5252)
                            : const Color(0x55C8A860)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('[${e.hora}] ${e.titulo}',
                          style: TextStyle(
                              color: e.error
                                  ? const Color(0xFFFF8A80)
                                  : const Color(0xFFC8A860),
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(e.detalle,
                          style: const TextStyle(
                              color: Color(0xFFB8C4D0),
                              fontFamily: 'monospace',
                              fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, Future<void> Function() onTap,
      {bool destacado = false}) {
    return ElevatedButton(
      onPressed: _ocupado ? null : () => onTap(),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            destacado ? const Color(0xFFC8A860) : const Color(0xFF1A2838),
        foregroundColor:
            destacado ? const Color(0xFF0A1018) : const Color(0xFFC8A860),
        side: BorderSide(
            color:
                destacado ? const Color(0xFFE0C880) : const Color(0x55C8A860)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
    );
  }
}

class _LogEntry {
  final String titulo;
  final String detalle;
  final bool error;
  final String hora;
  _LogEntry(
      {required this.titulo,
      required this.detalle,
      required this.error,
      required this.hora});
}

class _PartidaItem {
  final String id;
  final String desc;
  _PartidaItem({required this.id, required this.desc});
}
