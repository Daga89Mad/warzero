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

  /// Solo para habilidades con carta propia (teletransporte, invisibilidad y
  /// clon): ya se eligió la celda, falta que el jugador elija qué carta
  /// propia usar (vía modal/sidebar).
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
///      `habilidad.numObjetivos`. En las habilidades de SELECCIÓN ENCADENADA
///      (muro y fractura) los objetivos válidos se recalculan tras cada toque:
///        - Muro: 1ª celda en rango, luego colindantes a las ya elegidas.
///        - Fractura: 1º la celda origen (con cartas), luego el destino a
///          ≤ kFracturaDistanciaMax.
///      Quitar una celda ya elegida descarta también las posteriores.
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

  /// Objetivos válidos del PRIMER paso (los que calcula el rango). En la
  /// selección encadenada se vuelve a ellos al vaciar la selección.
  Set<String> _validosIniciales = const {};

  /// Contexto del tablero en el momento de iniciar la acción (para recalcular
  /// los pasos de muro y fractura sin depender de la pantalla).
  Map<String, String> _obeliscosPorJugador = const {};
  Set<String> _celdasMuro = const {};
  Set<String> _celdasOcupadas = const {};
  Set<String> _celdasProtegidasRival = const {};

  /// Fractura: tipos (1 tierra, 2 aire, 3 mar) de las cartas VISIBLES y no
  /// estáticas de cada celda, para ofrecer solo destinos donde alguna pueda
  /// aterrizar.
  Map<String, Set<int>> _tiposMoviblesPorCelda = const {};

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

  /// Texto de ayuda al iniciar la selección.
  String get mensajeInicio {
    final h = _habilidad;
    if (h == null) return '';
    switch (h.efecto.tipo) {
      case EfectoTipo.muro:
        return 'Muro: elige la primera celda y después '
            '${h.numObjetivos - 1} colindantes.';
      case EfectoTipo.fractura:
        return 'Fractura: elige la celda cuyas cartas quieres desplazar.';
      case EfectoTipo.clon:
        return 'Clon: elige la celda donde aparecerá el clon.';
      default:
        return h.numObjetivos == 1
            ? 'Selecciona una celda objetivo.'
            : 'Selecciona ${h.numObjetivos} celdas objetivo.';
    }
  }

  /// Texto de ayuda para el siguiente paso de una selección encadenada que
  /// aún no está completa (null si no aplica).
  String? get mensajeSiguientePaso {
    final h = _habilidad;
    if (h == null || !h.seleccionEncadenada || objetivosCompletos) return null;
    if (_objetivos.isEmpty) return mensajeInicio;
    if (h.efecto.tipo == EfectoTipo.fractura) {
      return 'Ahora elige el destino (máx. $kFracturaDistanciaMax celdas).';
    }
    final faltan = h.numObjetivos - _objetivos.length;
    return faltan == 1
        ? 'Elige 1 celda colindante más.'
        : 'Elige $faltan celdas colindantes más.';
  }

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
    Set<String> coordsPropias = const {},
    Set<String> celdasMuro = const {},
    Set<String> celdasOcupadas = const {},
    Set<String> celdasProtegidasRival = const {},
    Map<String, Set<int>> tiposMoviblesPorCelda = const {},
  }) {
    if (!carta.tieneHabilidad) return false;
    final h = CatalogoHabilidades.get(carta.idHabilidad);
    if (h == null) return false;

    _reset();
    _habilidad = h;
    _origen = obeliscoLocal;
    // Carta de ACCIÓN (jugada desde la mano): el coste es el campo normal
    // `Coste` de la carta -es el que se ve en la mano y en el detalle-, NO
    // `CosteHabilidad`. Ese otro campo solo aplica a habilidades lanzadas
    // desde una carta que NO es de acción (ver iniciarDesdeCartaDeTablero).
    _costeHabilidad = carta.coste;
    _cartaAccionDeMano = carta;
    _indiceMano = indiceMano;
    _guardarContexto(
      obeliscosPorJugador: obeliscosPorJugador,
      celdasMuro: celdasMuro,
      celdasOcupadas: celdasOcupadas,
      celdasProtegidasRival: celdasProtegidasRival,
      tiposMoviblesPorCelda: tiposMoviblesPorCelda,
    );
    _validosIniciales = HabilidadService.calcularObjetivosValidos(
      origen: _origen,
      habilidad: h,
      config: _config,
      obeliscosPorJugador: obeliscosPorJugador,
      coordsPropias: coordsPropias,
      celdasMuro: celdasMuro,
      celdasOcupadas: celdasOcupadas,
      celdasProtegidasRival: celdasProtegidasRival,
    );
    _objetivosValidos = _validosIniciales;
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
    Set<String> coordsPropias = const {},
    Set<String> celdasMuro = const {},
    Set<String> celdasOcupadas = const {},
    Set<String> celdasProtegidasRival = const {},
    Map<String, Set<int>> tiposMoviblesPorCelda = const {},
  }) {
    final carta = cartaEnCelda.carta;
    if (!carta.tieneHabilidad) return false;
    final h = CatalogoHabilidades.get(carta.idHabilidad);
    if (h == null) return false;

    _reset();
    _habilidad = h;
    _origen = coord;
    // Habilidad lanzada desde una carta que NO es de acción (carta normal
    // ya desplegada en el tablero, con idHabilidad>0): aquí sí se usa el
    // coste específico de la habilidad, `CosteHabilidad`.
    _costeHabilidad = carta.costeHabilidad;
    _cartaTableroCoord = coord;
    _cartaTableroIndice = indiceCelda;
    _guardarContexto(
      obeliscosPorJugador: obeliscosPorJugador,
      celdasMuro: celdasMuro,
      celdasOcupadas: celdasOcupadas,
      celdasProtegidasRival: celdasProtegidasRival,
      tiposMoviblesPorCelda: tiposMoviblesPorCelda,
    );
    _validosIniciales = HabilidadService.calcularObjetivosValidos(
      origen: _origen,
      habilidad: h,
      config: _config,
      obeliscosPorJugador: obeliscosPorJugador,
      coordsPropias: coordsPropias,
      celdasMuro: celdasMuro,
      celdasOcupadas: celdasOcupadas,
      celdasProtegidasRival: celdasProtegidasRival,
    );
    _objetivosValidos = _validosIniciales;
    _fase = FaseAccion.seleccionandoObjetivos;
    return true;
  }

  // ── Selección ─────────────────────────────────────────────

  /// Añade/quita una celda objetivo. Devuelve:
  ///   - true: la operación se realizó (añadió o quitó).
  ///   - false: la celda no es válida o no hay habilidad activa.
  ///
  /// Comportamiento:
  ///   - Si la celda ya está seleccionada → se quita (toggle). En la
  ///     selección encadenada (muro/fractura) se quitan también las posteriores.
  ///   - Si no está y aún quedan slots libres → se añade.
  ///   - Si ya se llegó al máximo → no se añade.
  ///   - Si al añadir se completan los objetivos Y la habilidad requiere
  ///     carta propia → la fase transita a `seleccionandoCartaTeleport`.
  bool seleccionarObjetivo(String coord) {
    if (_fase != FaseAccion.seleccionandoObjetivos) return false;
    if (_habilidad == null) return false;

    if (_objetivos.contains(coord)) {
      if (_habilidad!.seleccionEncadenada) {
        _objetivos.removeRange(_objetivos.indexOf(coord), _objetivos.length);
      } else {
        _objetivos.remove(coord);
      }
      _recalcularValidos();
      return true;
    }
    if (!_objetivosValidos.contains(coord)) return false;
    if (_objetivos.length >= _habilidad!.numObjetivos) return false;

    _objetivos.add(coord);
    _recalcularValidos();
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

  void _guardarContexto({
    required Map<String, String> obeliscosPorJugador,
    required Set<String> celdasMuro,
    required Set<String> celdasOcupadas,
    required Set<String> celdasProtegidasRival,
    required Map<String, Set<int>> tiposMoviblesPorCelda,
  }) {
    _obeliscosPorJugador = obeliscosPorJugador;
    _celdasMuro = celdasMuro;
    _celdasOcupadas = celdasOcupadas;
    _celdasProtegidasRival = celdasProtegidasRival;
    _tiposMoviblesPorCelda = tiposMoviblesPorCelda;
  }

  /// Recalcula los objetivos válidos tras cambiar la selección. Solo cambia
  /// algo en la selección encadenada; el resto conserva los del rango.
  void _recalcularValidos() {
    final h = _habilidad;
    if (h == null) return;
    if (!h.seleccionEncadenada || _objetivos.isEmpty) {
      _objetivosValidos = _validosIniciales;
      return;
    }
    if (objetivosCompletos) {
      _objetivosValidos = const {};
      return;
    }
    switch (h.efecto.tipo) {
      case EfectoTipo.muro:
        _objetivosValidos = HabilidadService.muroSiguientes(
          elegidas: _objetivos,
          config: _config,
          obeliscosPorJugador: _obeliscosPorJugador,
          celdasMuro: _celdasMuro,
          celdasOcupadas: _celdasOcupadas,
          celdasProtegidasRival: _celdasProtegidasRival,
          maxCeldas: h.numObjetivos,
        );
        break;
      case EfectoTipo.fractura:
        _objetivosValidos = HabilidadService.fracturaDestinos(
          origenFractura: _objetivos.first,
          config: _config,
          obeliscosPorJugador: _obeliscosPorJugador,
          celdasMuro: _celdasMuro,
          celdasProtegidasRival: _celdasProtegidasRival,
          tiposMovibles: _tiposMoviblesPorCelda[_objetivos.first] ?? const {},
        );
        break;
      default:
        _objetivosValidos = _validosIniciales;
    }
  }

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
    _validosIniciales = const {};
    _obeliscosPorJugador = const {};
    _celdasMuro = const {};
    _celdasOcupadas = const {};
    _celdasProtegidasRival = const {};
    _tiposMoviblesPorCelda = const {};
    _cartaTeleportCoord = null;
    _cartaTeleportIndice = null;
    _cartaTeleportId = null;
  }
}
