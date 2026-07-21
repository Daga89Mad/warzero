// lib/models/board_state.dart

import 'carta_model.dart';
import 'efecto_estado.dart';

/// Una carta colocada en el tablero, con su propietario.
class CartaEnCelda {
  final CartaModel carta;
  final String ownerUid;
  final String ownerZone;
  final List<EfectoActivo> efectos;
  final int? ultimoUsoHabilidad;

  /// Identidad ÚNICA de esta instancia colocada en el tablero.
  ///
  /// OJO: `carta.id` es el id de CATÁLOGO (la plantilla), así que dos copias de
  /// la misma carta (p.ej. dos "Tiburón de combate") comparten `carta.id`. Para
  /// distinguir instancias concretas —y que, por ejemplo, marcar una como
  /// "ya movida este turno" NO afecte a otra copia recién desplegada— se usa
  /// este `instanceId`, que es propio de cada objeto colocado.
  ///
  /// Se genera al crear la carta si no se aporta uno. Se preserva a través de
  /// movimientos (misma instancia) y de `copyWith`. Al reconstruir el tablero
  /// desde el servidor cada turno se genera uno nuevo, lo cual es correcto: el
  /// rastreo de "movidas este turno" se reinicia en cada turno.
  final String instanceId;

  CartaEnCelda({
    required this.carta,
    required this.ownerUid,
    required this.ownerZone,
    this.efectos = const [],
    this.ultimoUsoHabilidad,
    String? instanceId,
  }) : instanceId = instanceId ?? _nuevaInstanceId();

  static int _contador = 0;
  static String _nuevaInstanceId() {
    _contador++;
    return 'i${DateTime.now().microsecondsSinceEpoch}_$_contador';
  }

  int get defensaReducidaPorEfectos {
    int total = 0;
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.veneno) total += e.magnitud;
    }
    return total;
  }

  /// Defensa extra por potenciación de defensa. (El escudo YA NO suma defensa:
  /// es solo una protección de celda.)
  int get defensaExtraPorEfectos {
    int total = 0;
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.potDefensa) total += e.magnitud;
    }
    return total;
  }

  /// Fuerza extra que aportan las potenciaciones de fuerza activas.
  int get fuerzaExtraPorEfectos {
    int total = 0;
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.potFuerza) total += e.magnitud;
    }
    return total;
  }

  /// Movimiento extra que aportan las potenciaciones de movimiento activas.
  int get movimientoExtraPorEfectos {
    int total = 0;
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.potMovimiento) total += e.magnitud;
    }
    return total;
  }

  int get defensaEfectiva {
    final r =
        carta.defensa - defensaReducidaPorEfectos + defensaExtraPorEfectos;
    return r > 0 ? r : 0;
  }

  /// Fuerza efectiva (con potenciación de fuerza).
  int get fuerzaEfectiva => carta.fuerza + fuerzaExtraPorEfectos;

  /// Movimiento efectivo (con potenciación de movimiento).
  int get movimientoEfectivo => carta.movimiento + movimientoExtraPorEfectos;

  /// True si la carta arrastra algún buff de potenciación activo.
  bool get potenciada {
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.potFuerza ||
          e.tipo == EfectoTipoEstado.potDefensa ||
          e.tipo == EfectoTipoEstado.potMovimiento) return true;
    }
    return false;
  }

  /// True si la carta arrastra un efecto de parálisis activo (no puede moverse).
  bool get paralizado {
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.paralisis) return true;
    }
    return false;
  }

  /// True si la carta arrastra un veneno activo (defensa reducida).
  bool get envenenada {
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.veneno) return true;
    }
    return false;
  }

  bool habilidadDisponible(int turnoActual) {
    if (!carta.tieneHabilidad) return false;
    if (ultimoUsoHabilidad == null) return true;
    return (turnoActual - ultimoUsoHabilidad!) > carta.enfriamientoHabilidad;
  }

  Map<String, dynamic> toMap() => {
        ...carta.toMap(),
        'ownerUid': ownerUid,
        'ownerZone': ownerZone,
        'instanceId': instanceId,
        if (efectos.isNotEmpty)
          'Efectos': efectos.map((e) => e.toMap()).toList(),
        if (ultimoUsoHabilidad != null)
          'UltimoUsoHabilidad': ultimoUsoHabilidad,
      };

  factory CartaEnCelda.fromMap(Map<String, dynamic> d) => CartaEnCelda(
        carta: CartaModel.fromMap(d),
        ownerUid: d['ownerUid'] as String? ?? '',
        ownerZone: d['ownerZone'] as String? ?? '',
        // Si el servidor conserva el instanceId lo reutilizamos; si no, se
        // genera uno nuevo (el rastreo por-turno se reinicia igualmente).
        instanceId: d['instanceId'] as String?,
        efectos: ((d['Efectos'] ?? d['efectos']) as List?)
                ?.map((m) =>
                    EfectoActivo.fromMap(Map<String, dynamic>.from(m as Map)))
                .toList() ??
            const [],
        ultimoUsoHabilidad:
            (d['UltimoUsoHabilidad'] ?? d['ultimoUsoHabilidad']) is num
                ? ((d['UltimoUsoHabilidad'] ?? d['ultimoUsoHabilidad']) as num)
                    .toInt()
                : null,
      );

  CartaEnCelda copyWith({
    CartaModel? carta,
    String? ownerUid,
    String? ownerZone,
    List<EfectoActivo>? efectos,
    int? ultimoUsoHabilidad,
  }) =>
      CartaEnCelda(
        carta: carta ?? this.carta,
        ownerUid: ownerUid ?? this.ownerUid,
        ownerZone: ownerZone ?? this.ownerZone,
        efectos: efectos ?? this.efectos,
        ultimoUsoHabilidad: ultimoUsoHabilidad ?? this.ultimoUsoHabilidad,
        // Preservar la identidad de instancia a través de copyWith.
        instanceId: instanceId,
      );
}

/// Estado de una celda del tablero
class CeldaState {
  final String coord;
  final List<CartaEnCelda> cartas;

  const CeldaState({required this.coord, this.cartas = const []});

  bool get isEmpty => cartas.isEmpty;

  int get fuerzaTotal => cartas.fold(0, (s, c) => s + c.carta.fuerza);
  int get fuerzaTotalEfectiva => cartas.fold(0, (s, c) => s + c.fuerzaEfectiva);
  int get defensaTotal => cartas.fold(0, (s, c) => s + c.carta.defensa);
  int get defensaTotalEfectiva =>
      cartas.fold(0, (s, c) => s + c.defensaEfectiva);

  int fuerzaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.carta.fuerza);
  int defensaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.carta.defensa);
  int defensaEfectivaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.defensaEfectiva);

  bool get hayCombate => cartas.map((c) => c.ownerUid).toSet().length > 1;

  CeldaState addCarta(CartaEnCelda c) =>
      CeldaState(coord: coord, cartas: [...cartas, c]);

  CeldaState removeCarta(int index) {
    final updated = [...cartas]..removeAt(index);
    return CeldaState(coord: coord, cartas: updated);
  }

  CeldaState withCartas(List<CartaEnCelda> nuevas) =>
      CeldaState(coord: coord, cartas: nuevas);
}

/// Estado completo del tablero en tiempo real
class BoardState {
  final Map<String, CeldaState> celdas;
  final int turnoActual;
  final String? ownerTurno;
  final Map<String, List<EfectoActivo>> efectosCelda;

  /// Coordenadas de las celdas de RAYO de farmeo (aparecen aleatoriamente y
  /// otorgan +10 Zero). Puede haber VARIAS simultáneas según el nº de jugadores.
  final Set<String> rayoCoords;

  const BoardState({
    this.celdas = const {},
    this.turnoActual = 1,
    this.ownerTurno,
    this.efectosCelda = const {},
    this.rayoCoords = const {},
  });

  CeldaState getCelda(String coord) =>
      celdas[coord] ?? CeldaState(coord: coord);

  List<EfectoActivo> getEfectosCelda(String coord) =>
      efectosCelda[coord] ?? const [];

  bool celdaEnvenenada(String coord) {
    final lista = efectosCelda[coord];
    if (lista == null) return false;
    return lista.any(
      (e) => e.tipo == EfectoTipoEstado.veneno && e.turnosRestantes > 0,
    );
  }

  bool celdaParalizada(String coord) {
    final lista = efectosCelda[coord];
    if (lista == null) return false;
    return lista.any(
      (e) => e.tipo == EfectoTipoEstado.paralisis && e.turnosRestantes > 0,
    );
  }

  /// Venenos activos en la celda con su origen y magnitud. Se usa para que el
  /// preview de combate reste defensa solo a las cartas ENEMIGAS del veneno
  /// (no a las del lanzador), igual que hace el servidor al resolver.
  List<({String origen, int magnitud})> venenosCelda(String coord) {
    final lista = efectosCelda[coord];
    if (lista == null) return const [];
    final res = <({String origen, int magnitud})>[];
    for (final e in lista) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo != EfectoTipoEstado.veneno) continue;
      res.add((origen: e.origenUid, magnitud: e.magnitud));
    }
    return res;
  }

  /// True si la celda debe marcarse con calavera: tiene un veneno de celda
  /// activo, o alguna carta en ella arrastra veneno (aunque se haya movido).
  bool celdaTieneVeneno(String coord) {
    if (celdaEnvenenada(coord)) return true;
    return getCelda(coord).cartas.any((c) => c.envenenada);
  }

  /// True si la celda debe marcarse con copo: tiene una parálisis de celda
  /// activa, o alguna carta en ella arrastra parálisis.
  bool celdaTieneParalisis(String coord) {
    if (celdaParalizada(coord)) return true;
    return getCelda(coord).cartas.any((c) => c.paralizado);
  }

  /// Escudos activos en la celda (origen + magnitud). Se usa para que el
  /// preview de combate sume defensa solo a las cartas del lanzador.
  List<({String origen, int magnitud})> escudosCelda(String coord) {
    final lista = efectosCelda[coord];
    if (lista == null) return const [];
    final res = <({String origen, int magnitud})>[];
    for (final e in lista) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo != EfectoTipoEstado.escudo) continue;
      res.add((origen: e.origenUid, magnitud: e.magnitud));
    }
    return res;
  }

  /// True si la celda está escudada (protección activa). El escudo es un efecto
  /// de CELDA (no viaja en las cartas), así que solo se mira efectosCelda.
  bool celdaTieneEscudo(String coord) {
    final lista = efectosCelda[coord];
    return lista != null &&
        lista.any(
            (e) => e.tipo == EfectoTipoEstado.escudo && e.turnosRestantes > 0);
  }

  /// True si la celda está escudada por OTRO jugador (distinto de [localUid]).
  /// Esas celdas están protegidas: no puedes mover tus cartas dentro ni
  /// afectarlas con acciones.
  bool celdaProtegidaPorRival(String coord, String? localUid) {
    final lista = efectosCelda[coord];
    if (lista == null) return false;
    return lista.any((e) =>
        e.tipo == EfectoTipoEstado.escudo &&
        e.turnosRestantes > 0 &&
        e.origenUid != localUid);
  }

  /// True si [coord] es una de las celdas de rayo activas.
  bool esRayo(String coord) => rayoCoords.contains(coord);

  BoardState setEfectosCelda(String coord, List<EfectoActivo> efectos) {
    final nuevos = Map<String, List<EfectoActivo>>.from(efectosCelda);
    if (efectos.isEmpty) {
      nuevos.remove(coord);
    } else {
      nuevos[coord] = efectos;
    }
    return copyWith(efectosCelda: nuevos);
  }

  BoardState placeCarta(String coord, CartaEnCelda carta) {
    final celda = getCelda(coord).addCarta(carta);
    return BoardState(
      celdas: {...celdas, coord: celda},
      turnoActual: turnoActual,
      ownerTurno: ownerTurno,
      efectosCelda: efectosCelda,
      rayoCoords: rayoCoords,
    );
  }

  BoardState setCelda(String coord, CeldaState celda) => BoardState(
        celdas: {...celdas, coord: celda},
        turnoActual: turnoActual,
        ownerTurno: ownerTurno,
        efectosCelda: efectosCelda,
        rayoCoords: rayoCoords,
      );

  int puntosJugador(String ownerZone) => celdas.values
      .expand((c) => c.cartas)
      .where((c) => c.ownerZone == ownerZone)
      .fold(0, (s, c) => s + c.carta.fuerza);

  BoardState copyWith({
    Map<String, CeldaState>? celdas,
    int? turnoActual,
    String? ownerTurno,
    Map<String, List<EfectoActivo>>? efectosCelda,
    Set<String>? rayoCoords,
  }) =>
      BoardState(
        celdas: celdas ?? this.celdas,
        turnoActual: turnoActual ?? this.turnoActual,
        ownerTurno: ownerTurno ?? this.ownerTurno,
        efectosCelda: efectosCelda ?? this.efectosCelda,
        rayoCoords: rayoCoords ?? this.rayoCoords,
      );

  /// Fija (o limpia, pasando {}) las celdas de rayo de forma explícita.
  /// `copyWith` no puede distinguir "no tocar" de "vaciar", por eso existe este.
  BoardState withRayos(Set<String> coords) => BoardState(
        celdas: celdas,
        turnoActual: turnoActual,
        ownerTurno: ownerTurno,
        efectosCelda: efectosCelda,
        rayoCoords: coords,
      );

  BoardState nextTurn(String nextOwner) => BoardState(
        celdas: celdas,
        turnoActual: turnoActual + 1,
        ownerTurno: nextOwner,
        efectosCelda: efectosCelda,
        rayoCoords: rayoCoords,
      );

  static Map<String, dynamic> efectosCeldaToFirestore(
          Map<String, List<EfectoActivo>> efectosCelda) =>
      efectosCelda
          .map((k, v) => MapEntry(k, v.map((ef) => ef.toMap()).toList()));

  static Map<String, List<EfectoActivo>> efectosCeldaFromFirestore(
      Map<String, dynamic>? raw) {
    final result = <String, List<EfectoActivo>>{};
    if (raw == null) return result;
    raw.forEach((k, v) {
      final lista = (v as List?)
              ?.map((m) =>
                  EfectoActivo.fromMap(Map<String, dynamic>.from(m as Map)))
              .toList() ??
          [];
      if (lista.isNotEmpty) result[k] = lista;
    });
    return result;
  }
}
