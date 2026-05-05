// lib/models/board_state.dart

import 'carta_model.dart';

/// Una carta colocada en el tablero, con su propietario
class CartaEnCelda {
  final CartaModel carta;
  final String ownerUid; // uid del jugador propietario
  final String ownerZone; // 'north','south','west','east'...

  const CartaEnCelda({
    required this.carta,
    required this.ownerUid,
    required this.ownerZone,
  });

  /// Serializa la carta para guardar en Firestore dentro del tablero.
  Map<String, dynamic> toMap() => {
        ...carta.toMap(),
        'ownerUid': ownerUid,
        'ownerZone': ownerZone,
      };

  factory CartaEnCelda.fromMap(Map<String, dynamic> d) => CartaEnCelda(
        carta: CartaModel.fromMap(d),
        ownerUid: d['ownerUid'] as String? ?? '',
        ownerZone: d['ownerZone'] as String? ?? '',
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

  /// Suma de defensa de todas las cartas en la celda.
  int get defensaTotal => cartas.fold(0, (s, c) => s + c.carta.defensa);

  /// Fuerza total de las cartas de un propietario concreto.
  int fuerzaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.carta.fuerza);

  /// Defensa total de las cartas de un propietario concreto.
  int defensaDe(String ownerUid) => cartas
      .where((c) => c.ownerUid == ownerUid)
      .fold(0, (s, c) => s + c.carta.defensa);

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

  const BoardState({
    this.celdas = const {},
    this.turnoActual = 1,
    this.ownerTurno,
  });

  CeldaState getCelda(String coord) =>
      celdas[coord] ?? CeldaState(coord: coord);

  BoardState placeCarta(String coord, CartaEnCelda carta) {
    final celda = getCelda(coord).addCarta(carta);
    return BoardState(
      celdas: {...celdas, coord: celda},
      turnoActual: turnoActual,
      ownerTurno: ownerTurno,
    );
  }

  /// Reemplaza la celda completa (usado para mover cartas entre celdas).
  BoardState setCelda(String coord, CeldaState celda) => BoardState(
        celdas: {...celdas, coord: celda},
        turnoActual: turnoActual,
        ownerTurno: ownerTurno,
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
  }) =>
      BoardState(
        celdas: celdas ?? this.celdas,
        turnoActual: turnoActual ?? this.turnoActual,
        ownerTurno: ownerTurno ?? this.ownerTurno,
      );

  BoardState nextTurn(String nextOwner) => BoardState(
        celdas: celdas,
        turnoActual: turnoActual + 1,
        ownerTurno: nextOwner,
      );
}
