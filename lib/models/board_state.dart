// lib/models/board_state.dart

import 'carta_model.dart';
import 'efecto_estado.dart';

/// Una carta colocada en el tablero, con su propietario.
///
/// Lleva además los efectos persistentes que la afectan (veneno…) y la marca
/// del último turno en que usó su habilidad (para gestionar el enfriamiento
/// configurado en `CartaModel.enfriamientoHabilidad`).
class CartaEnCelda {
  final CartaModel carta;
  final String ownerUid; // uid del jugador propietario
  final String ownerZone; // 'north','south','west','east'...

  /// Efectos persistentes activos sobre esta carta concreta.
  /// La carta los arrastra aunque se mueva de celda.
  final List<EfectoActivo> efectos;

  /// Turno en que esta carta usó su habilidad por última vez.
  /// Null si nunca la ha usado.
  final int? ultimoUsoHabilidad;

  const CartaEnCelda({
    required this.carta,
    required this.ownerUid,
    required this.ownerZone,
    this.efectos = const [],
    this.ultimoUsoHabilidad,
  });

  // ── Reglas derivadas ──────────────────────────────────────

  /// Suma de la magnitud de los venenos activos que afectan a esta carta.
  int get defensaReducidaPorEfectos {
    int total = 0;
    for (final e in efectos) {
      if (e.turnosRestantes <= 0) continue;
      if (e.tipo == EfectoTipoEstado.veneno) total += e.magnitud;
    }
    return total;
  }

  /// Defensa efectiva tras aplicar reducciones por efectos activos
  /// (mínimo 0).
  int get defensaEfectiva {
    final r = carta.defensa - defensaReducidaPorEfectos;
    return r > 0 ? r : 0;
  }

  /// True si la habilidad de la carta está lista para usarse en [turnoActual].
  /// Tiene en cuenta `enfriamientoHabilidad` configurado en la carta.
  bool habilidadDisponible(int turnoActual) {
    if (!carta.tieneHabilidad) return false;
    if (ultimoUsoHabilidad == null) return true;
    return (turnoActual - ultimoUsoHabilidad!) > carta.enfriamientoHabilidad;
  }

  // ── Serialización ─────────────────────────────────────────

  /// Serializa la carta para guardar en Firestore dentro del tablero.
  Map<String, dynamic> toMap() => {
        ...carta.toMap(),
        'ownerUid': ownerUid,
        'ownerZone': ownerZone,
        if (efectos.isNotEmpty)
          'Efectos': efectos.map((e) => e.toMap()).toList(),
        if (ultimoUsoHabilidad != null)
          'UltimoUsoHabilidad': ultimoUsoHabilidad,
      };

  factory CartaEnCelda.fromMap(Map<String, dynamic> d) => CartaEnCelda(
        carta: CartaModel.fromMap(d),
        ownerUid: d['ownerUid'] as String? ?? '',
        ownerZone: d['ownerZone'] as String? ?? '',
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
      );
}

/// Estado de una celda del tablero
class CeldaState {
  final String coord; // e.g. "B5"
  final List<CartaEnCelda> cartas;

  const CeldaState({required this.coord, this.cartas = const []});

  bool get isEmpty => cartas.isEmpty;

  /// Suma de fuerza de todas las cartas en la celda.
  int get fuerzaTotal => cartas.fold(0, (s, c) => s + c.carta.fuerza);

  /// Suma de defensa BASE de todas las cartas en la celda (sin restar venenos).
  int get defensaTotal => cartas.fold(0, (s, c) => s + c.carta.defensa);

  /// Suma de defensa EFECTIVA: defensa base menos reducciones por venenos.
  int get defensaTotalEfectiva =>
      cartas.fold(0, (s, c) => s + c.defensaEfectiva);

  /// Fuerza total de las cartas de un propietario concreto.
  int fuerzaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.carta.fuerza);

  /// Defensa total (base) de las cartas de un propietario concreto.
  int defensaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.carta.defensa);

  /// Defensa efectiva (tras venenos) de un propietario concreto.
  int defensaEfectivaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.defensaEfectiva);

  /// Comprueba si hay cartas de más de un propietario (→ combate).
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
  final Map<String, CeldaState> celdas; // coord → CeldaState
  final int turnoActual;
  final String? ownerTurno; // uid del jugador que tiene el turno

  /// Efectos persistentes activos en celdas (veneno, etc.).
  /// Solo aparecen coords con al menos un efecto activo.
  final Map<String, List<EfectoActivo>> efectosCelda;

  const BoardState({
    this.celdas = const {},
    this.turnoActual = 1,
    this.ownerTurno,
    this.efectosCelda = const {},
  });

  CeldaState getCelda(String coord) =>
      celdas[coord] ?? CeldaState(coord: coord);

  // ── Efectos en celdas ─────────────────────────────────────

  /// Lista de efectos activos en la celda (nunca null).
  List<EfectoActivo> getEfectosCelda(String coord) =>
      efectosCelda[coord] ?? const [];

  /// True si la celda tiene al menos un veneno activo.
  bool celdaEnvenenada(String coord) {
    final lista = efectosCelda[coord];
    if (lista == null) return false;
    return lista.any(
      (e) => e.tipo == EfectoTipoEstado.veneno && e.turnosRestantes > 0,
    );
  }

  /// Devuelve un nuevo BoardState reemplazando los efectos de una celda.
  /// Si la lista queda vacía, la entrada se elimina del mapa.
  BoardState setEfectosCelda(String coord, List<EfectoActivo> efectos) {
    final nuevos = Map<String, List<EfectoActivo>>.from(efectosCelda);
    if (efectos.isEmpty) {
      nuevos.remove(coord);
    } else {
      nuevos[coord] = efectos;
    }
    return copyWith(efectosCelda: nuevos);
  }

  // ── Operaciones de tablero ────────────────────────────────

  BoardState placeCarta(String coord, CartaEnCelda carta) {
    final celda = getCelda(coord).addCarta(carta);
    return BoardState(
      celdas: {...celdas, coord: celda},
      turnoActual: turnoActual,
      ownerTurno: ownerTurno,
      efectosCelda: efectosCelda,
    );
  }

  /// Reemplaza la celda completa (usado para mover cartas entre celdas).
  BoardState setCelda(String coord, CeldaState celda) => BoardState(
        celdas: {...celdas, coord: celda},
        turnoActual: turnoActual,
        ownerTurno: ownerTurno,
        efectosCelda: efectosCelda,
      );

  /// Puntuación total de un jugador (suma de fuerzas en tablero).
  int puntosJugador(String ownerZone) => celdas.values
      .expand((c) => c.cartas)
      .where((c) => c.ownerZone == ownerZone)
      .fold(0, (s, c) => s + c.carta.fuerza);

  BoardState copyWith({
    Map<String, CeldaState>? celdas,
    int? turnoActual,
    String? ownerTurno,
    Map<String, List<EfectoActivo>>? efectosCelda,
  }) =>
      BoardState(
        celdas: celdas ?? this.celdas,
        turnoActual: turnoActual ?? this.turnoActual,
        ownerTurno: ownerTurno ?? this.ownerTurno,
        efectosCelda: efectosCelda ?? this.efectosCelda,
      );

  BoardState nextTurn(String nextOwner) => BoardState(
        celdas: celdas,
        turnoActual: turnoActual + 1,
        ownerTurno: nextOwner,
        efectosCelda: efectosCelda,
      );

  // ── Serialización de efectosCelda (helpers para Firestore) ──

  /// Convierte `efectosCelda` a un Map plano serializable para Firestore.
  static Map<String, dynamic> efectosCeldaToFirestore(
          Map<String, List<EfectoActivo>> efectosCelda) =>
      efectosCelda
          .map((k, v) => MapEntry(k, v.map((ef) => ef.toMap()).toList()));

  /// Reconstruye el mapa `efectosCelda` desde el JSON crudo de Firestore.
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
