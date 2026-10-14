// lib/models/modo_partida.dart
//
// MODO DE PARTIDA (desplegable de CREAR SALA). Se guarda en la partida en el
// campo `modoPartida` y lo aplica el servidor en cada cierre de turno
// (Fenrir · ModosCatastrofe.cs):
//
//   normal       → partida clásica, sin eventos.
//   meteoritos   → LLUVIA DE METEORITOS. A partir del turno 10 y luego cada 5
//                  turnos (10, 15, 20…) las casillas del CENTRO del tablero se
//                  marcan con el % de que les caiga un disparo lejano; al cerrar
//                  ese turno caen 3 disparos repartidos entre ellas.
//   apocalipsis  → APOCALIPSIS. Misma cadencia pero en TODO el tablero: en cada
//                  fila caen 2 disparos lejanos y 1 parálisis lejana. El % de
//                  cada celda es la probabilidad de que le caiga una de las tres.
//
// Los impactos los lanza un "jugador" neutro ([kUidEvento]); un escudo propio
// sigue bloqueándolos, los cuarteles quedan fuera y no dan PC a nadie.
//
// El servidor publica el plan del turno de impacto en el campo `bombardeo` de
// la partida (el mismo que usa el bombardeo de historia), así que lo pinta la
// capa ya existente (bombardeo_overlay.dart) con la leyenda propia del modo.

enum ModoPartida { normal, meteoritos, apocalipsis }

/// UID neutro con el que el servidor firma los disparos/parálisis de los modos
/// catástrofe (espejo de `ModosCatastrofe.UidEvento`).
const String kUidEvento = '__evento__';

/// Cadencia de los impactos (espejo de las constantes del servidor).
const int kCatastrofePrimerTurno = 10;
const int kCatastrofeCadaTurnos = 5;

extension ModoPartidaX on ModoPartida {
  /// Valor que se guarda en Firestore (`modoPartida`).
  String get id {
    switch (this) {
      case ModoPartida.meteoritos:
        return 'meteoritos';
      case ModoPartida.apocalipsis:
        return 'apocalipsis';
      case ModoPartida.normal:
        return 'normal';
    }
  }

  String get nombre {
    switch (this) {
      case ModoPartida.meteoritos:
        return 'LLUVIA DE METEORITOS';
      case ModoPartida.apocalipsis:
        return 'APOCALIPSIS';
      case ModoPartida.normal:
        return 'NORMAL';
    }
  }

  /// Nombre corto para chips y listas.
  String get etiqueta {
    switch (this) {
      case ModoPartida.meteoritos:
        return 'METEORITOS';
      case ModoPartida.apocalipsis:
        return 'APOCALIPSIS';
      case ModoPartida.normal:
        return 'NORMAL';
    }
  }

  String get icono {
    switch (this) {
      case ModoPartida.meteoritos:
        return '☄';
      case ModoPartida.apocalipsis:
        return '☠';
      case ModoPartida.normal:
        return '⚔';
    }
  }

  /// Texto explicativo que se muestra bajo el desplegable al crear la sala.
  String get descripcion {
    switch (this) {
      case ModoPartida.meteoritos:
        return 'A partir del turno $kCatastrofePrimerTurno, y después cada '
            '$kCatastrofeCadaTurnos turnos, las casillas del centro del '
            'tablero se marcan con la probabilidad de que les caiga un '
            'disparo lejano. Al cerrar ese turno caen 3 disparos repartidos '
            'entre ellas, sobre las cartas que terminen allí. Un escudo propio '
            'los bloquea.';
      case ModoPartida.apocalipsis:
        return 'A partir del turno $kCatastrofePrimerTurno, y después cada '
            '$kCatastrofeCadaTurnos turnos, TODO el tablero se marca con '
            'probabilidades: en cada fila caen 2 disparos lejanos y 1 '
            'parálisis lejana al cerrar el turno. El % de cada casilla es la '
            'probabilidad de que le caiga una de las tres. Los cuarteles '
            'quedan fuera y un escudo propio los bloquea.';
      case ModoPartida.normal:
        return 'Partida clásica, sin eventos del tablero.';
    }
  }

  bool get tieneCatastrofes => this != ModoPartida.normal;

  /// Nombre con el que se presenta el "jugador" neutro en los informes.
  String get nombreEvento {
    switch (this) {
      case ModoPartida.meteoritos:
        return 'Lluvia de meteoritos';
      case ModoPartida.apocalipsis:
        return 'Apocalipsis';
      case ModoPartida.normal:
        return 'Evento';
    }
  }
}

/// Parsea el valor de Firestore (`modoPartida`). Ausente o desconocido = normal.
ModoPartida modoPartidaFromString(String? s) {
  switch ((s ?? '').trim().toLowerCase()) {
    case 'meteoritos':
      return ModoPartida.meteoritos;
    case 'apocalipsis':
      return ModoPartida.apocalipsis;
    default:
      return ModoPartida.normal;
  }
}

/// True si en [turno] caen impactos (10, 15, 20…).
bool esTurnoDeImpacto(ModoPartida modo, int turno) {
  if (!modo.tieneCatastrofes) return false;
  if (turno < kCatastrofePrimerTurno) return false;
  return (turno - kCatastrofePrimerTurno) % kCatastrofeCadaTurnos == 0;
}

/// Próximo turno de impacto ≥ [turno] (el propio [turno] si lo es).
int proximoTurnoDeImpacto(int turno) {
  if (turno <= kCatastrofePrimerTurno) return kCatastrofePrimerTurno;
  final k = (turno - kCatastrofePrimerTurno + kCatastrofeCadaTurnos - 1) ~/
      kCatastrofeCadaTurnos;
  return kCatastrofePrimerTurno + k * kCatastrofeCadaTurnos;
}

/// Alias a mostrar para un uid en informes/revisión: traduce el uid neutro del
/// evento; para el resto devuelve null (que el llamador use su alias normal).
String? aliasEvento(String? uid, {ModoPartida? modo}) {
  if (uid != kUidEvento) return null;
  return (modo ?? ModoPartida.normal).nombreEvento;
}
