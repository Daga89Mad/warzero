// lib/models/efecto_estado.dart

import 'dart:ui' show Color;

/// Tipos de efecto persistente que pueden estar activos sobre una celda o
/// sobre una carta.
///
/// IMPORTANTE: esta lista debe estar SINCRONIZADA con los tipos que escribe el
/// servidor en `efectosCelda` / `Efectos`. Faltaba `trampa` (Trampas.cs escribe
/// `tipo:"trampa"`), y como `fromName` caía por defecto en `veneno`, TODAS las
/// trampas se leían como veneno: el tablero pintaba calavera y tinte verde en
/// celdas con trampa, el preview de combate restaba defensa que no tocaba y las
/// trampas OCULTAS quedaban reveladas a todos los jugadores.
enum EfectoTipoEstado {
  veneno,
  paralisis,
  escudo,
  potFuerza,
  potDefensa,
  potMovimiento,
  // Invisibilidad: efecto que se ancla a UNA carta (no a la celda). Mientras
  // está activo, la carta solo es visible para su propietario (el rival no la
  // ve en el tablero). Se rompe al expirar los turnos, al entrar en combate o
  // al morir la carta.
  invisibilidad,
  // Trampa: efecto de CELDA colocado por un jugador. Mientras `oculta` sea true
  // solo la ve su dueño; al dispararse se revela para todos (oculta:false).
  trampa,
  // Muro: efecto de CELDA (acción Muro). Nadie puede terminar su movimiento en
  // ella ni atravesarla mientras dure. Es público.
  muro,
  // Confusión: efecto anclado a CARTAS (acción Confusión). La carta se mueve
  // sola cada turno, su dueño no la controla y en combate lucha como un bando
  // propio (también contra las cartas de su dueño). Es público.
  confusion,
  // futuro: regeneracion...
}

extension EfectoTipoEstadoExt on EfectoTipoEstado {
  String get nombre {
    switch (this) {
      case EfectoTipoEstado.veneno:
        return 'Veneno';
      case EfectoTipoEstado.paralisis:
        return 'Parálisis';
      case EfectoTipoEstado.escudo:
        return 'Escudo';
      case EfectoTipoEstado.potFuerza:
        return 'Fuerza+';
      case EfectoTipoEstado.potDefensa:
        return 'Defensa+';
      case EfectoTipoEstado.potMovimiento:
        return 'Movimiento+';
      case EfectoTipoEstado.invisibilidad:
        return 'Invisible';
      case EfectoTipoEstado.trampa:
        return 'Trampa';
      case EfectoTipoEstado.muro:
        return 'Muro';
      case EfectoTipoEstado.confusion:
        return 'Confusión';
    }
  }

  String get icon {
    switch (this) {
      case EfectoTipoEstado.veneno:
        return '☠';
      case EfectoTipoEstado.paralisis:
        return '⏱';
      case EfectoTipoEstado.escudo:
        return '🛡';
      case EfectoTipoEstado.potFuerza:
        return '💪';
      case EfectoTipoEstado.potDefensa:
        return '🛡';
      case EfectoTipoEstado.potMovimiento:
        return '💨';
      case EfectoTipoEstado.invisibilidad:
        return '👻';
      case EfectoTipoEstado.trampa:
        return '🕸';
      case EfectoTipoEstado.muro:
        return '🧱';
      case EfectoTipoEstado.confusion:
        return '🌀';
    }
  }

  /// Color identificativo del efecto. Se usa TANTO en el badge del tablero como
  /// en el chip del menú lateral, para que un mismo efecto se reconozca igual
  /// en los dos sitios.
  Color get color {
    switch (this) {
      case EfectoTipoEstado.veneno:
        return const Color(0xFF2BA046);
      case EfectoTipoEstado.paralisis:
        return const Color(0xFF2C90C8);
      case EfectoTipoEstado.escudo:
        return const Color(0xFF6AB0FF);
      case EfectoTipoEstado.potFuerza:
        return const Color(0xFFFFB84D);
      case EfectoTipoEstado.potDefensa:
        return const Color(0xFF9AD0FF);
      case EfectoTipoEstado.potMovimiento:
        return const Color(0xFF7FE0C0);
      case EfectoTipoEstado.invisibilidad:
        return const Color(0xFFB68CE0);
      case EfectoTipoEstado.trampa:
        return const Color(0xFFD08030);
      case EfectoTipoEstado.muro:
        return const Color(0xFFA8845C);
      case EfectoTipoEstado.confusion:
        return const Color(0xFFE060C0);
    }
  }

  /// Orden de presentación (perjudiciales primero, luego beneficiosos).
  int get orden {
    switch (this) {
      case EfectoTipoEstado.veneno:
        return 0;
      case EfectoTipoEstado.paralisis:
        return 1;
      case EfectoTipoEstado.confusion:
        return 2;
      case EfectoTipoEstado.trampa:
        return 3;
      case EfectoTipoEstado.muro:
        return 4;
      case EfectoTipoEstado.escudo:
        return 5;
      case EfectoTipoEstado.potFuerza:
        return 6;
      case EfectoTipoEstado.potDefensa:
        return 7;
      case EfectoTipoEstado.potMovimiento:
        return 8;
      case EfectoTipoEstado.invisibilidad:
        return 9;
    }
  }

  /// True si es una potenciación (buff que solo afecta a las cartas del origen).
  bool get esBuff =>
      this == EfectoTipoEstado.potFuerza ||
      this == EfectoTipoEstado.potDefensa ||
      this == EfectoTipoEstado.potMovimiento;

  /// Texto de magnitud con signo. El escudo NO suma defensa (es protección de
  /// celda), así que no muestra magnitud.
  String signoMagnitud(int magnitud) {
    if (magnitud <= 0) return '';
    switch (this) {
      case EfectoTipoEstado.veneno:
        return '-$magnitud';
      case EfectoTipoEstado.potFuerza:
      case EfectoTipoEstado.potDefensa:
      case EfectoTipoEstado.potMovimiento:
        return '+$magnitud';
      default:
        return '';
    }
  }

  /// Devuelve el tipo cuyo `name` coincide, o null si el servidor mandó un tipo
  /// que este cliente todavía no conoce. Preferir SIEMPRE esta sobre [fromName]
  /// cuando se pueda descartar el efecto: así un tipo nuevo no se disfraza de
  /// veneno en el tablero.
  static EfectoTipoEstado? tryFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final t in EfectoTipoEstado.values) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// Compatibilidad con el código antiguo. Un tipo desconocido cae en `veneno`,
  /// pero el `EfectoActivo` resultante queda marcado con `conocido == false`
  /// para que la UI lo pueda ignorar.
  static EfectoTipoEstado fromName(String? name) =>
      tryFromName(name) ?? EfectoTipoEstado.veneno;
}

/// Un efecto persistente activo sobre una celda o una carta.
///
/// USO EN CELDAS
///   Se guarda en `Map<String, List<EfectoActivo>> efectosCelda` dentro del
///   estado de la partida. Mientras la celda tenga un veneno con
///   `turnosRestantes > 0`, cualquier carta que esté o entre recibe el efecto.
///
/// USO EN CARTAS
///   Se guarda en el campo `Efectos: [...]` del Map de la carta dentro del
///   tablero. La carta arrastra el efecto aunque se mueva. El servicio de
///   combate consulta estos efectos para reducir la defensa de la carta.
class EfectoActivo {
  final EfectoTipoEstado tipo;
  final int turnosRestantes;

  /// Magnitud del efecto. Para veneno: defensa que resta.
  final int magnitud;

  /// Uid del jugador que originó el efecto. Útil para logs y para evitar
  /// stackear infinitos venenos del mismo origen (se refresca duración).
  final String origenUid;

  /// Nombre de tipo TAL CUAL vino del servidor. Se conserva para poder
  /// reserializar sin pérdida y para saber si el tipo era conocido.
  final String tipoRaw;

  /// Solo TRAMPAS: mientras es true, únicamente su dueño debe verla.
  final bool oculta;

  /// Solo TRAMPAS: habilidad que dispara, e info de la carta que la colocó.
  final int habilidadId;
  final String icono;
  final String cartaNombre;
  final String cartaId;

  const EfectoActivo({
    required this.tipo,
    required this.turnosRestantes,
    required this.magnitud,
    required this.origenUid,
    this.tipoRaw = '',
    this.oculta = false,
    this.habilidadId = 0,
    this.icono = '',
    this.cartaNombre = '',
    this.cartaId = '',
  });

  bool get expirado => turnosRestantes <= 0;

  /// False si el servidor mandó un `tipo` que este cliente no reconoce. La UI
  /// debe ignorar estos efectos en vez de pintarlos como veneno.
  bool get conocido =>
      tipoRaw.isEmpty || EfectoTipoEstadoExt.tryFromName(tipoRaw) != null;

  /// True si [viewerUid] debe ver este efecto. Solo restringe las trampas aún
  /// ocultas: las ve únicamente quien las colocó.
  bool visiblePara(String? viewerUid) {
    if (tipo != EfectoTipoEstado.trampa) return true;
    if (!oculta) return true;
    return origenUid.isNotEmpty && origenUid == viewerUid;
  }

  /// Icono a mostrar: el propio de la trampa si el servidor mandó uno, si no el
  /// icono genérico del tipo.
  String get iconoMostrado => icono.isNotEmpty ? icono : tipo.icon;

  EfectoActivo copyWith({
    EfectoTipoEstado? tipo,
    int? turnosRestantes,
    int? magnitud,
    String? origenUid,
    String? tipoRaw,
    bool? oculta,
    int? habilidadId,
    String? icono,
    String? cartaNombre,
    String? cartaId,
  }) =>
      EfectoActivo(
        tipo: tipo ?? this.tipo,
        turnosRestantes: turnosRestantes ?? this.turnosRestantes,
        magnitud: magnitud ?? this.magnitud,
        origenUid: origenUid ?? this.origenUid,
        tipoRaw: tipoRaw ?? this.tipoRaw,
        oculta: oculta ?? this.oculta,
        habilidadId: habilidadId ?? this.habilidadId,
        icono: icono ?? this.icono,
        cartaNombre: cartaNombre ?? this.cartaNombre,
        cartaId: cartaId ?? this.cartaId,
      );

  /// Devuelve una copia con `turnosRestantes - 1`. Usado al cerrar cada turno.
  EfectoActivo decrementar() => copyWith(turnosRestantes: turnosRestantes - 1);

  Map<String, dynamic> toMap() => {
        'tipo': tipoRaw.isNotEmpty ? tipoRaw : tipo.name,
        'turnosRestantes': turnosRestantes,
        'magnitud': magnitud,
        'origenUid': origenUid,
        // Campos de trampa: solo se reescriben si venían, para no ensuciar los
        // efectos normales ni romper el round-trip con el servidor.
        if (tipo == EfectoTipoEstado.trampa) 'oculta': oculta,
        if (habilidadId != 0) 'habilidadId': habilidadId,
        if (icono.isNotEmpty) 'icono': icono,
        if (cartaNombre.isNotEmpty) 'cartaNombre': cartaNombre,
        if (cartaId.isNotEmpty) 'cartaId': cartaId,
      };

  factory EfectoActivo.fromMap(Map<String, dynamic> d) {
    final raw = d['tipo'] as String? ?? '';
    return EfectoActivo(
      tipo: EfectoTipoEstadoExt.fromName(raw),
      tipoRaw: raw,
      turnosRestantes: (d['turnosRestantes'] as num?)?.toInt() ?? 0,
      magnitud: (d['magnitud'] as num?)?.toInt() ?? 0,
      origenUid: d['origenUid'] as String? ?? '',
      oculta: d['oculta'] == true,
      habilidadId: (d['habilidadId'] as num?)?.toInt() ?? 0,
      icono: d['icono'] as String? ?? '',
      cartaNombre: d['cartaNombre'] as String? ?? '',
      cartaId: d['cartaId'] as String? ?? '',
    );
  }
}
