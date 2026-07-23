import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una temática (paleta) de WarZero. Todas mantienen el estilo bélico; varían
/// en luminosidad y acento. Las dos últimas son claras.
class WarZeroTheme {
  final String id;
  final String nombre;
  final Brightness brillo;
  final Color fondo; // scaffold
  final Color superficie; // paneles / surface
  final Color primario; // acento principal
  final Color secundario;
  final Color error;
  final Color texto; // texto base
  final Color textoTenue; // etiquetas / atenuado
  final Color borde;

  /// Los mismos colores como ThemeExtension (para leerlos con context.war).
  WarColors get colores => WarColors(
        fondo: fondo,
        superficie: superficie,
        primario: primario,
        secundario: secundario,
        error: error,
        texto: texto,
        textoTenue: textoTenue,
        borde: borde,
      );
  const WarZeroTheme({
    required this.id,
    required this.nombre,
    required this.brillo,
    required this.fondo,
    required this.superficie,
    required this.primario,
    required this.secundario,
    required this.error,
    required this.texto,
    required this.textoTenue,
    required this.borde,
  });

  bool get esClaro => brillo == Brightness.light;

  ThemeData construir() {
    final base = esClaro ? ThemeData.light() : ThemeData.dark();
    final scheme =
        (esClaro ? const ColorScheme.light() : const ColorScheme.dark())
            .copyWith(
      primary: primario,
      secondary: secundario,
      surface: superficie,
      error: error,
      brightness: brillo,
    );
    return base.copyWith(
      brightness: brillo,
      extensions: <ThemeExtension<dynamic>>[colores],
      scaffoldBackgroundColor: fondo,
      colorScheme: scheme,
      textTheme: base.textTheme.apply(bodyColor: texto, displayColor: texto),
      appBarTheme: AppBarTheme(
        backgroundColor: superficie,
        foregroundColor: primario,
        elevation: 0,
      ),
      iconTheme: IconThemeData(color: primario),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: textoTenue),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: borde.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(6),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primario, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        filled: true,
        fillColor: superficie,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: esClaro
              ? superficie
              : Color.alphaBlend(primario.withOpacity(0.10), superficie),
          foregroundColor: primario,
          side: BorderSide(color: borde, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primario
                : Colors.transparent),
        checkColor: WidgetStateProperty.all(fondo),
        side: BorderSide(color: borde),
      ),
    );
  }
}

/// Las 5 temáticas disponibles (todas bélicas; #4 y #5 más luminosas).
const List<WarZeroTheme> kWarZeroThemes = [
  WarZeroTheme(
    id: 'bunker',
    nombre: 'Búnker',
    brillo: Brightness.dark,
    fondo: Color(0xFF030810),
    superficie: Color(0xFF0A1220),
    primario: Color(0xFFC8A860),
    secundario: Color(0xFF4ABB58),
    error: Color(0xFFC04040),
    texto: Color(0xFFC8C0A8),
    textoTenue: Color(0xFF7A6040),
    borde: Color(0xFF7A5A18),
  ),
  WarZeroTheme(
    id: 'acero',
    nombre: 'Acero',
    brillo: Brightness.dark,
    fondo: Color(0xFF0B0F14),
    superficie: Color(0xFF141C26),
    primario: Color(0xFF7FB4D6),
    secundario: Color(0xFF6FCF97),
    error: Color(0xFFD1605A),
    texto: Color(0xFFCBD5E0),
    textoTenue: Color(0xFF6B7A8A),
    borde: Color(0xFF3A4A5A),
  ),
  WarZeroTheme(
    id: 'oliva',
    nombre: 'Campaña',
    brillo: Brightness.dark,
    fondo: Color(0xFF171A12),
    superficie: Color(0xFF232717),
    primario: Color(0xFFB9C44E),
    secundario: Color(0xFFCBA24A),
    error: Color(0xFFC0553F),
    texto: Color(0xFFD8DCC0),
    textoTenue: Color(0xFF8A8C6E),
    borde: Color(0xFF5A5E38),
  ),
  WarZeroTheme(
    id: 'desierto',
    nombre: 'Desierto',
    brillo: Brightness.light,
    fondo: Color(0xFFE8DFC8),
    superficie: Color(0xFFF2EAD6),
    primario: Color(0xFF8A5A20),
    secundario: Color(0xFF6E7A2E),
    error: Color(0xFFA33A2A),
    texto: Color(0xFF2C2416),
    textoTenue: Color(0xFF6E6248),
    borde: Color(0xFFB89A66),
  ),
  WarZeroTheme(
    id: 'alba',
    nombre: 'Alba',
    brillo: Brightness.light,
    fondo: Color(0xFFEDEFE6),
    superficie: Color(0xFFFFFFFF),
    primario: Color(0xFF3A5A8A),
    secundario: Color(0xFF4A7A3A),
    error: Color(0xFFB03A2E),
    texto: Color(0xFF1E2430),
    textoTenue: Color(0xFF5A6472),
    borde: Color(0xFF9AA6B6),
  ),
];

/// Controlador global de ajustes (tema + escala de texto), persistido con
/// shared_preferences. Instancia única `settingsController` accesible desde
/// main.dart y la pantalla de ajustes. Sin paquete de estado: ChangeNotifier
/// + AnimatedBuilder en la raíz.
class SettingsController extends ChangeNotifier {
  static const _kTema = 'wz_tema_id';
  static const _kEscala = 'wz_text_scale';

  static const double escalaMin = 0.85;
  static const double escalaMax = 1.50;

  int _temaIndex = 0;
  double _escala = 1.0;

  int get temaIndex => _temaIndex;
  double get escala => _escala;
  WarZeroTheme get tema =>
      kWarZeroThemes[_temaIndex.clamp(0, kWarZeroThemes.length - 1)];

  Future<void> cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      final id = p.getString(_kTema);
      final idx = kWarZeroThemes.indexWhere((t) => t.id == id);
      _temaIndex = idx >= 0 ? idx : 0;
      _escala = (p.getDouble(_kEscala) ?? 1.0).clamp(escalaMin, escalaMax);
    } catch (_) {
      _temaIndex = 0;
      _escala = 1.0;
    }
    notifyListeners();
  }

  Future<void> setTemaIndex(int i) async {
    if (i < 0 || i >= kWarZeroThemes.length || i == _temaIndex) return;
    _temaIndex = i;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kTema, kWarZeroThemes[i].id);
    } catch (_) {}
  }

  Future<void> setEscala(double v) async {
    v = v.clamp(escalaMin, escalaMax);
    if (v == _escala) return;
    _escala = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kEscala, v);
    } catch (_) {}
  }
}

/// Instancia global.
final settingsController = SettingsController();

/// Colores personalizados de WarZero transportados por el ThemeData. Las
/// pantallas los leen con `context.war.<color>` y se recolorean al cambiar tema.
@immutable
class WarColors extends ThemeExtension<WarColors> {
  final Color fondo;
  final Color superficie;
  final Color primario;
  final Color secundario;
  final Color error;
  final Color texto;
  final Color textoTenue;
  final Color borde;

  const WarColors({
    required this.fondo,
    required this.superficie,
    required this.primario,
    required this.secundario,
    required this.error,
    required this.texto,
    required this.textoTenue,
    required this.borde,
  });

  @override
  WarColors copyWith({
    Color? fondo,
    Color? superficie,
    Color? primario,
    Color? secundario,
    Color? error,
    Color? texto,
    Color? textoTenue,
    Color? borde,
  }) =>
      WarColors(
        fondo: fondo ?? this.fondo,
        superficie: superficie ?? this.superficie,
        primario: primario ?? this.primario,
        secundario: secundario ?? this.secundario,
        error: error ?? this.error,
        texto: texto ?? this.texto,
        textoTenue: textoTenue ?? this.textoTenue,
        borde: borde ?? this.borde,
      );

  @override
  WarColors lerp(ThemeExtension<WarColors>? other, double t) {
    if (other is! WarColors) return this;
    return WarColors(
      fondo: Color.lerp(fondo, other.fondo, t)!,
      superficie: Color.lerp(superficie, other.superficie, t)!,
      primario: Color.lerp(primario, other.primario, t)!,
      secundario: Color.lerp(secundario, other.secundario, t)!,
      error: Color.lerp(error, other.error, t)!,
      texto: Color.lerp(texto, other.texto, t)!,
      textoTenue: Color.lerp(textoTenue, other.textoTenue, t)!,
      borde: Color.lerp(borde, other.borde, t)!,
    );
  }
}

/// Acceso cómodo desde cualquier widget: `context.war.primario`, etc.
extension WarColorsX on BuildContext {
  WarColors get war =>
      Theme.of(this).extension<WarColors>() ?? kWarZeroThemes.first.colores;
}
