// lib/services/accion_controller.dart

import '../models/accion_pendiente.dart';
import '../models/board_state.dart';
import '../models/carta_model.dart';
import '../models/game_config.dart';
import '../models/habilidad_model.dart';
import 'habilidad_service.dart';

/// Fase del flujo de selección de una acción.
enum FaseAccion {
  /// No hay acción en curso.
  inactivo,

  /// Esperando que el jugador toque celdas objetivo en el tablero.
  /// Las celdas elegibles están en [AccionController.objetivosValidos].
  seleccionandoObjetivos,

  /// Solo para teletransporte: ya se eligió el destino, falta que el
  /// jugador elija qué carta propia mover (vía modal/sidebar).
  seleccionandoCartaTeleport,
}

/// Controlador del flujo de declaración de una habilidad/acción.
///
/// Diseñado para ser usado desde `game_screen.dart` como una propiedad
/// `late AccionController _accionController;`. La pantalla llama a sus
/// métodos dentro de `setState(() {...})` para refrescar la UI.
///
/// FLUJO TÍPICO
///   1. `iniciarDesdeCartaDeMano(...)` o `iniciarDesdeCartaDeTablero(...)`.
///      → `fase` pasa a `seleccionandoObjetivos`,
///        `objetivosValidos` se calcula con HabilidadService.
///   2. `seleccionarObjetivo(coord)` por cada celda hasta completar
///      `habilidad.numObjetivos`.
///        - Si la habilidad es teletransporte, al completar pasa a
///          `seleccionandoCartaTeleport`.
///        - Si no, queda en estado "listo": `lista == true`.
///   3. (Solo teletransporte) `setCartaTeleport(coord, indice)` para
///      registrar la carta propia.
///   4. `construir(...)` devuelve la `AccionPendiente` final.
///   5. El llamador descuenta energías y añade la acción a su lista
///      `_accionesPendientes`. Luego llama `cancelar()` para resetear.
///
/// En cualquier momento `cancelar()` resetea sin construir.
class AccionController {
  AccionController({required GameConfig config}) : _config = config;

  GameConfig _config;

  /// Permite refrescar la config si el tablero cambia (carga de terreno).
  void actualizarConfig(GameConfig config) {
    _config = config;
  }

  // ── Estado ────────────────────────────────────────────────

  FaseAccion _fase = FaseAccion.inactivo;
  Habilidad? _habilidad;
  String _origen = '';
  int _costeHabilidad = 0;

  /// Carta de acción jugada desde la mano (mutuamente excluyente con
  /// _cartaTableroCoord/_cartaTableroIndice).
  CartaModel? _cartaAccionDeMano;
  int? _indiceMano;

  /// Carta del tablero con habilidad propia.
  String? _cartaTableroCoord;
  int? _cartaTableroIndice;

  final List<String> _objetivos = [];
  Set<String> _objetivosValidos = const {};

  String? _cartaTeleportCoord;
  int? _cartaTeleportIndice;
  String? _cartaTeleportId;

  // ── Getters públicos ──────────────────────────────────────

  FaseAccion get fase => _fase;
  Habilidad? get habilidad => _habilidad;
  String get origen => _origen;
  int get costeHabilidad => _costeHabilidad;
  bool get activo => _fase != FaseAccion.inactivo;

  /// Inmutable: lista de objetivos seleccionados (en orden).
  List<String> get objetivos => List.unmodifiable(_objetivos);

  /// Inmutable: celdas elegibles ahora mismo.
  Set<String> get objetivosValidos => _objetivosValidos;

  bool get esCartaDeAccion => _cartaAccionDeMano != null;
  bool get esHabilidadDeTablero => _cartaTableroCoord != null;

  CartaModel? get cartaAccionDeMano => _cartaAccionDeMano;
  int? get indiceMano => _indiceMano;
  String? get cartaTableroCoord => _cartaTableroCoord;
  int? get cartaTableroIndice => _cartaTableroIndice;

  String? get cartaTeleportCoord => _cartaTeleportCoord;
  int? get cartaTeleportIndice => _cartaTeleportIndice;

  /// True si ya se han seleccionado todos los objetivos requeridos.
  bool get objetivosCompletos =>
      _habilidad != null && _objetivos.length >= _habilidad!.numObjetivos;

  /// True si la acción está lista para construir AccionPendiente.
  bool get lista {
    if (_habilidad == null) return false;
    if (!objetivosCompletos) return false;
    if (_habilidad!.requiereCartaPropia) {
      return _cartaTeleportCoord != null && _cartaTeleportIndice != null;
    }
    return true;
  }

  // ── Inicio ────────────────────────────────────────────────

  /// Inicia la selección desde una carta de acción jugada desde la mano.
  /// El origen del rango es el cuartel general del jugador.
  ///
  /// Devuelve false si la carta no tiene habilidad válida en el catálogo.
  bool iniciarDesdeCartaDeMano({
    required CartaModel carta,
    required int indiceMano,
    required String obeliscoLocal,
    required Map<String, String> obeliscosPorJugador,
  }) {
    if (!carta.tieneHabilidad) return false;
    final h = CatalogoHabilidades.get(carta.idHabilidad);
    if (h == null) return false;

    _reset();
    _habilidad = h;
    _origen = obeliscoLocal;
    _costeHabilidad = carta.costeHabilidad;
    _cartaAccionDeMano = carta;
    _indiceMano = indiceMano;
    _objetivosValidos = HabilidadService.calcularObjetivosValidos(
      origen: _origen,
      habilidad: h,
      config: _config,
      obeliscosPorJugador: obeliscosPorJugador,
    );
    _fase = FaseAccion.seleccionandoObjetivos;
    return true;
  }

  /// Inicia la selección desde una carta en el tablero con habilidad propia.
  /// El origen del rango es la celda de esa carta.
  ///
  /// Devuelve false si la carta no tiene habilidad válida en el catálogo.
  bool iniciarDesdeCartaDeTablero({
    required CartaEnCelda cartaEnCelda,
    required String coord,
    required int indiceCelda,
    required Map<String, String> obeliscosPorJugador,
  }) {
    final carta = cartaEnCelda.carta;
    if (!carta.tieneHabilidad) return false;
    final h = CatalogoHabilidades.get(carta.idHabilidad);
    if (h == null) return false;

    _reset();
    _habilidad = h;
    _origen = coord;
    _costeHabilidad = carta.costeHabilidad;
    _cartaTableroCoord = coord;
    _cartaTableroIndice = indiceCelda;
    _objetivosValidos = HabilidadService.calcularObjetivosValidos(
      origen: _origen,
      habilidad: h,
      config: _config,
      obeliscosPorJugador: obeliscosPorJugador,
    );
    _fase = FaseAccion.seleccionandoObjetivos;
    return true;
  }

  // ── Selección ─────────────────────────────────────────────

  /// Añade/quita una celda objetivo. Devuelve:
  ///   - true: la operación se realizó (añadió o quitó).
  ///   - false: la celda no es válida o no hay habilidad activa.
  ///
  /// Comportamiento:
  ///   - Si la celda ya está seleccionada → se quita (toggle).
  ///   - Si no está y aún quedan slots libres → se añade.
  ///   - Si ya se llegó al máximo → no se añade.
  ///   - Si al añadir se completan los objetivos Y la habilidad requiere
  ///     carta propia → la fase transita a `seleccionandoCartaTeleport`.
  bool seleccionarObjetivo(String coord) {
    if (_fase != FaseAccion.seleccionandoObjetivos) return false;
    if (_habilidad == null) return false;
    if (!_objetivosValidos.contains(coord)) return false;

    if (_objetivos.contains(coord)) {
      _objetivos.remove(coord);
      return true;
    }
    if (_objetivos.length >= _habilidad!.numObjetivos) return false;

    _objetivos.add(coord);
    if (objetivosCompletos && _habilidad!.requiereCartaPropia) {
      _fase = FaseAccion.seleccionandoCartaTeleport;
    }
    return true;
  }

  /// Para teletransporte: registra la carta propia que se moverá. Debe
  /// llamarse cuando la fase es `seleccionandoCartaTeleport`.
  /// Devuelve false si la fase es otra.
  bool setCartaTeleport(String coord, int indice, {String? cartaId}) {
    if (_fase != FaseAccion.seleccionandoCartaTeleport) return false;
    _cartaTeleportCoord = coord;
    _cartaTeleportIndice = indice;
    _cartaTeleportId = cartaId;
    return true;
  }

  // ── Finalización ──────────────────────────────────────────

  /// Cancela la acción en curso y limpia todo el estado.
  void cancelar() {
    _reset();
  }

  /// Construye una `AccionPendiente` con los datos seleccionados.
  /// Solo válido cuando `lista == true`. No resetea el estado: el llamador
  /// debe invocar `cancelar()` cuando termine de procesar.
  AccionPendiente? construir({
    required String uid,
    required String zona,
    required int turno,
  }) {
    if (!lista || _habilidad == null) return null;

    return AccionPendiente(
      habilidadId: _habilidad!.id,
      uid: uid,
      zona: zona,
      origen: _origen,
      objetivos: List<String>.from(_objetivos),
      turno: turno,
      cartaOrigenCoord: _cartaTeleportCoord,
      cartaOrigenIndice: _cartaTeleportIndice,
      cartaOrigenId: _cartaTeleportId,
      cartaAccionId: _cartaAccionDeMano?.id,
      costePagado: _costeHabilidad,
    );
  }

  // ── Internos ──────────────────────────────────────────────

  void _reset() {
    _fase = FaseAccion.inactivo;
    _habilidad = null;
    _origen = '';
    _costeHabilidad = 0;
    _cartaAccionDeMano = null;
    _indiceMano = null;
    _cartaTableroCoord = null;
    _cartaTableroIndice = null;
    _objetivos.clear();
    _objetivosValidos = const {};
    _cartaTeleportCoord = null;
    _cartaTeleportIndice = null;
    _cartaTeleportId = null;
  }
}
