// lib/models/torneo_model.dart
//
// MODO TORNEO · modelos (espejo de Fenrir · WarZeroTorneos.cs).
//
// Un torneo tiene 3 fechas (inicio/fin de inscripción e inicio del torneo) y
// una lista de RONDAS. Cada ronda tiene varias PARTIDAS (p. ej. una de 4, una
// de 8, otra de 4 con lluvia de meteoritos y un duelo); la suma de PC de todas
// ellas da la clasificación y pasan [RondaTorneo.clasifican] jugadores a la
// siguiente ronda.

import 'package:warzero/models/jugador_model.dart'; // MonedaZero
import 'package:warzero/models/modo_partida.dart';

enum TipoPartidaTorneo { partida, duelo }

TipoPartidaTorneo tipoPartidaTorneoFromString(String? s) =>
    (s ?? '') == 'duelo' ? TipoPartidaTorneo.duelo : TipoPartidaTorneo.partida;

extension TipoPartidaTorneoX on TipoPartidaTorneo {
  String get id => this == TipoPartidaTorneo.duelo ? 'duelo' : 'partida';
  String get nombre => this == TipoPartidaTorneo.duelo ? 'DUELO' : 'PARTIDA';
}

DateTime? _fecha(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d?.toLocal();
}

int _int(dynamic v, [int def = 0]) =>
    v is int ? v : int.tryParse('${v ?? ''}') ?? def;

class PartidaTorneo {
  TipoPartidaTorneo tipo;
  int jugadores;
  ModoPartida modo;

  PartidaTorneo({
    this.tipo = TipoPartidaTorneo.partida,
    this.jugadores = 4,
    this.modo = ModoPartida.normal,
  });

  bool get esDuelo => tipo == TipoPartidaTorneo.duelo;

  factory PartidaTorneo.fromJson(Map<String, dynamic> j) => PartidaTorneo(
        tipo: tipoPartidaTorneoFromString(j['tipo']?.toString()),
        jugadores: _int(j['jugadores'], 4),
        modo: modoPartidaFromString(j['modo']?.toString()),
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo.id,
        'jugadores': esDuelo ? 2 : jugadores,
        'modo': esDuelo ? 'normal' : modo.id,
      };

  /// "Partida de 4 · ☄ METEORITOS" / "Duelo".
  String get resumen {
    if (esDuelo) return 'Duelo 1 vs 1';
    final m = modo == ModoPartida.normal ? '' : ' · ${modo.icono} ${modo.etiqueta}';
    return 'Partida de $jugadores$m';
  }

  PartidaTorneo copia() =>
      PartidaTorneo(tipo: tipo, jugadores: jugadores, modo: modo);
}

class RondaTorneo {
  int numero;

  /// Jugadores que pasan a la siguiente ronda por suma de PC (0 = final).
  int clasifican;
  List<PartidaTorneo> partidas;

  RondaTorneo({
    required this.numero,
    this.clasifican = 0,
    List<PartidaTorneo>? partidas,
  }) : partidas = partidas ?? [PartidaTorneo()];

  factory RondaTorneo.fromJson(Map<String, dynamic> j) => RondaTorneo(
        numero: _int(j['numero'], 1),
        clasifican: _int(j['clasifican']),
        partidas: ((j['partidas'] as List?) ?? [])
            .map((e) =>
                PartidaTorneo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'clasifican': clasifican,
        'partidas': partidas.map((p) => p.toJson()).toList(),
      };
}

/// Cristal Zero a partir de su clave de Firestore (zeroPuro por defecto).
MonedaZero monedaZeroFromKey(String? k) => MonedaZero.values.firstWhere(
    (m) => m.firestoreKey == k,
    orElse: () => MonedaZero.puro);

/// PREMIO de un rango de puestos (1–1, 2–2, 4–8…). XP, dinero, Cristales Zero
/// y carta se entregan solos al finalizar el torneo; [externo] (camiseta,
/// metálico…) solo se muestra y lo entrega la organización.
class PremioTorneo {
  int desde;
  int hasta;
  int xp;
  int dinero;
  int zero;
  MonedaZero zeroTipo;
  String cartaId;
  String cartaNombre;
  int cartaCantidad;
  String externo;

  PremioTorneo({
    this.desde = 1,
    this.hasta = 1,
    this.xp = 0,
    this.dinero = 0,
    this.zero = 0,
    this.zeroTipo = MonedaZero.puro,
    this.cartaId = '',
    this.cartaNombre = '',
    this.cartaCantidad = 1,
    this.externo = '',
  });

  factory PremioTorneo.fromJson(Map<String, dynamic> j) => PremioTorneo(
        desde: _int(j['desde'], 1),
        hasta: _int(j['hasta'], 1),
        xp: _int(j['xp']),
        dinero: _int(j['dinero']),
        zero: _int(j['zero']),
        zeroTipo: monedaZeroFromKey(j['zeroTipo']?.toString()),
        cartaId: j['cartaId']?.toString() ?? '',
        cartaNombre: j['cartaNombre']?.toString() ?? '',
        cartaCantidad: _int(j['cartaCantidad'], 1),
        externo: j['externo']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'desde': desde,
        'hasta': hasta < desde ? desde : hasta,
        'xp': xp,
        'dinero': dinero,
        'zero': zero,
        'zeroTipo': zeroTipo.firestoreKey,
        'cartaId': cartaId,
        'cartaCantidad': cartaId.isEmpty ? 0 : cartaCantidad,
        'externo': externo.trim(),
      };

  bool get tieneCarta => cartaId.isNotEmpty;
  bool get tieneExterno => externo.trim().isNotEmpty;
  bool get vacio =>
      xp == 0 && dinero == 0 && zero == 0 && !tieneCarta && !tieneExterno;

  /// "1º" · "2º" · "4º – 8º"
  String get puestos => desde == hasta ? '${desde}º' : '${desde}º – ${hasta}º';

  /// Partes del premio dentro de la app, para listarlas.
  List<String> get partesApp => [
        if (xp > 0) '$xp XP',
        if (dinero > 0) '$dinero dinero',
        if (zero > 0) '$zero Zero ${zeroTipo.colorNombre}',
        if (tieneCarta)
          '${cartaCantidad > 1 ? '${cartaCantidad}× ' : ''}Carta ${cartaNombre.isNotEmpty ? cartaNombre : cartaId}',
      ];

  PremioTorneo copia() => PremioTorneo.fromJson(toJson())
    ..cartaNombre = cartaNombre;
}

/// Premio ya repartido a un jugador (Torneos/{id}/Premiados/{uid}).
class PremiadoTorneo {
  final String uid;
  final String alias;
  final int puesto;
  final PremioTorneo premio;
  final bool externoEntregado;

  const PremiadoTorneo({
    required this.uid,
    required this.alias,
    required this.puesto,
    required this.premio,
    required this.externoEntregado,
  });

  factory PremiadoTorneo.fromJson(Map<String, dynamic> j) => PremiadoTorneo(
        uid: j['uid']?.toString() ?? '',
        alias: j['alias']?.toString() ?? '',
        puesto: _int(j['puesto']),
        premio: PremioTorneo.fromJson(j),
        externoEntregado: j['externoEntregado'] == true,
      );

  String get nombre => alias.isNotEmpty ? alias : uid;
}

class TorneoModel {
  String id;
  String nombre;
  String descripcion;
  DateTime? inicioInscripcion;
  DateTime? finInscripcion;
  DateTime? inicioTorneo;

  /// borrador | publicado | en_curso | finalizado
  String estado;
  int rondaActual;
  List<RondaTorneo> rondas;
  List<PremioTorneo> premios;
  bool premiosEntregados;

  TorneoModel({
    this.id = '',
    this.nombre = '',
    this.descripcion = '',
    this.inicioInscripcion,
    this.finInscripcion,
    this.inicioTorneo,
    this.estado = 'borrador',
    this.rondaActual = 0,
    List<RondaTorneo>? rondas,
    List<PremioTorneo>? premios,
    this.premiosEntregados = false,
  })  : rondas = rondas ?? [RondaTorneo(numero: 1)],
        premios = premios ?? [];

  factory TorneoModel.fromJson(Map<String, dynamic> j) => TorneoModel(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        descripcion: j['descripcion']?.toString() ?? '',
        inicioInscripcion: _fecha(j['inicioInscripcion']),
        finInscripcion: _fecha(j['finInscripcion']),
        inicioTorneo: _fecha(j['inicioTorneo']),
        estado: j['estado']?.toString() ?? 'borrador',
        rondaActual: _int(j['rondaActual']),
        rondas: ((j['rondas'] as List?) ?? [])
            .map((e) =>
                RondaTorneo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        premios: ((j['premios'] as List?) ?? [])
            .map((e) =>
                PremioTorneo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        premiosEntregados: j['premiosEntregados'] == true,
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'nombre': nombre.trim(),
        'descripcion': descripcion.trim(),
        'inicioInscripcion': inicioInscripcion?.toUtc().toIso8601String(),
        'finInscripcion': finInscripcion?.toUtc().toIso8601String(),
        'inicioTorneo': inicioTorneo?.toUtc().toIso8601String(),
        'estado': estado,
        'rondas': rondas.map((r) => r.toJson()).toList(),
        'premios': premios.map((p) => p.toJson()).toList(),
      };

  String get estadoNombre {
    switch (estado) {
      case 'publicado':
        return 'PUBLICADO';
      case 'en_curso':
        return 'EN CURSO';
      case 'finalizado':
        return 'FINALIZADO';
      default:
        return 'BORRADOR';
    }
  }
}

/// Respuesta de /warzero/torneos/vigente (y de cada fila del listado admin).
class TorneoVigente {
  final TorneoModel? torneo;
  final int inscritos;
  final bool inscrito;

  /// pendiente | abierta | cerrada  (calculado con la hora del servidor)
  final String estadoInscripcion;

  const TorneoVigente({
    this.torneo,
    this.inscritos = 0,
    this.inscrito = false,
    this.estadoInscripcion = 'pendiente',
  });

  static const ninguno = TorneoVigente();

  bool get hayTorneo => torneo != null;
  bool get inscripcionAbierta => estadoInscripcion == 'abierta';
  bool get inscripcionPendiente => estadoInscripcion == 'pendiente';
  bool get gruposSorteados => (torneo?.rondaActual ?? 0) > 0;

  factory TorneoVigente.fromJson(Map<String, dynamic> j) {
    final t = j['torneo'];
    return TorneoVigente(
      torneo: t is Map ? TorneoModel.fromJson(Map<String, dynamic>.from(t)) : null,
      inscritos: _int(j['inscritos']),
      inscrito: j['inscrito'] == true,
      estadoInscripcion: j['estadoInscripcion']?.toString() ?? 'pendiente',
    );
  }
}

class InscritoTorneo {
  final String uid;
  final String alias;
  final DateTime? fecha;

  const InscritoTorneo({required this.uid, this.alias = '', this.fecha});

  factory InscritoTorneo.fromJson(Map<String, dynamic> j) => InscritoTorneo(
        uid: j['uid']?.toString() ?? '',
        alias: j['alias']?.toString() ?? '',
        fecha: _fecha(j['fecha']),
      );

  String get nombre => alias.isNotEmpty ? alias : uid;
}

class GrupoTorneo {
  final String id;
  final int ronda;
  final int partida;
  final int grupo;
  final TipoPartidaTorneo tipo;
  final ModoPartida modo;
  final int capacidad;
  final List<String> jugadores;
  final List<String> alias;
  final bool descansa;
  final String estado;

  const GrupoTorneo({
    required this.id,
    required this.ronda,
    required this.partida,
    required this.grupo,
    required this.tipo,
    required this.modo,
    required this.capacidad,
    required this.jugadores,
    required this.alias,
    required this.descansa,
    required this.estado,
  });

  factory GrupoTorneo.fromJson(Map<String, dynamic> j) => GrupoTorneo(
        id: j['id']?.toString() ?? '',
        ronda: _int(j['ronda']),
        partida: _int(j['partida']),
        grupo: _int(j['grupo']),
        tipo: tipoPartidaTorneoFromString(j['tipo']?.toString()),
        modo: modoPartidaFromString(j['modo']?.toString()),
        capacidad: _int(j['capacidad']),
        jugadores: ((j['jugadores'] as List?) ?? []).map((e) => '$e').toList(),
        alias: ((j['alias'] as List?) ?? []).map((e) => '$e').toList(),
        descansa: j['descansa'] == true,
        estado: j['estado']?.toString() ?? '',
      );

  /// Nombre a mostrar del jugador i (alias o uid).
  String nombre(int i) =>
      i < alias.length && alias[i].isNotEmpty ? alias[i] : jugadores[i];
}

/// Formato corto dd/MM/yyyy HH:mm (sin depender de intl).
String fechaTorneo(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Formato muy corto dd/MM.
String fechaCortaTorneo(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}';
}
