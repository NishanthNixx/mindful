import 'package:flutter/material.dart';

// Design tokens from the Stitch "Mindfull" design system: warm parchment
// surfaces, deep sage ink, Literata headings and Plus Jakarta Sans body.

const _serif = 'Literata';
const _sans = 'PlusJakartaSans';

/// Extra tokens Material's ColorScheme doesn't cover.
@immutable
class MindfullTokens extends ThemeExtension<MindfullTokens> {
  const MindfullTokens({
    required this.canvas,
    required this.card,
    required this.cardBorder,
    required this.cardShadow,
    required this.chip,
    required this.symptomChip,
    required this.medChip,
    required this.onMedChip,
    required this.brand,
    required this.onBrand,
    required this.headerScrim,
  });

  /// Page background under everything.
  final Color canvas;

  /// Paper card fill (slightly translucent so nature backgrounds show through).
  final Color card;
  final Color cardBorder;
  final List<BoxShadow> cardShadow;

  /// Neutral pill (suggestions, sleep badge).
  final Color chip;

  /// Selected symptom chip (warm terracotta wash).
  final Color symptomChip;

  /// Medication chip (mint).
  final Color medChip;
  final Color onMedChip;

  /// Deep sage used for the FAB and active nav pill.
  final Color brand;
  final Color onBrand;

  /// Translucent header background.
  final Color headerScrim;

  static MindfullTokens of(BuildContext context) =>
      Theme.of(context).extension<MindfullTokens>()!;

  static const light = MindfullTokens(
    canvas: Color(0xFFFCF9F2),
    card: Color(0xD9FFFFFD),
    cardBorder: Color(0x99E7E5E4),
    cardShadow: [
      BoxShadow(
        color: Color(0x0F3D6858),
        blurRadius: 20,
        offset: Offset(0, 4),
        spreadRadius: -2,
      ),
      BoxShadow(color: Color(0x082D3430), blurRadius: 6, offset: Offset(0, 2)),
    ],
    chip: Color(0xE6F1EEE7),
    symptomChip: Color(0x409B471F),
    medChip: Color(0xFFB0EDCF),
    onMedChip: Color(0xFF1F5A43),
    brand: Color(0xFF3D6858),
    onBrand: Color(0xFFFFFFFF),
    headerScrim: Color(0xBFFCF9F2),
  );

  static const dark = MindfullTokens(
    canvas: Color(0xFF141512),
    card: Color(0xD91F211D),
    cardBorder: Color(0x1FFFFFFF),
    cardShadow: [
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 20,
        offset: Offset(0, 4),
        spreadRadius: -4,
      ),
    ],
    chip: Color(0xFF2A2C27),
    symptomChip: Color(0x59D9764A),
    medChip: Color(0xFF1F4A3A),
    onMedChip: Color(0xFFB0EDCF),
    brand: Color(0xFF6FA88F),
    onBrand: Color(0xFF0B1F17),
    headerScrim: Color(0xCC141512),
  );

  @override
  MindfullTokens copyWith() => this;

  @override
  MindfullTokens lerp(MindfullTokens? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF255041),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF3D6858),
  onPrimaryContainer: Color(0xFFB6E5D1),
  primaryFixed: Color(0xFFBEEDD8),
  primaryFixedDim: Color(0xFFA2D0BD),
  onPrimaryFixed: Color(0xFF002117),
  onPrimaryFixedVariant: Color(0xFF234E40),
  secondary: Color(0xFF2F6951),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFB0EDCF),
  onSecondaryContainer: Color(0xFF336D55),
  secondaryFixed: Color(0xFFB3F0D2),
  secondaryFixedDim: Color(0xFF97D3B6),
  onSecondaryFixed: Color(0xFF002115),
  onSecondaryFixedVariant: Color(0xFF12503B),
  tertiary: Color(0xFF7C3008),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFF9B471F),
  onTertiaryContainer: Color(0xFFFFD1BF),
  tertiaryFixed: Color(0xFFFFDBCD),
  tertiaryFixedDim: Color(0xFFFFB597),
  onTertiaryFixed: Color(0xFF360F00),
  onTertiaryFixedVariant: Color(0xFF7B2F07),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF93000A),
  surface: Color(0xFFFCF9F2),
  onSurface: Color(0xFF1C1C18),
  onSurfaceVariant: Color(0xFF414944),
  surfaceDim: Color(0xFFDCDAD3),
  surfaceBright: Color(0xFFFCF9F2),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF6F3EC),
  surfaceContainer: Color(0xFFF1EEE7),
  surfaceContainerHigh: Color(0xFFEBE8E1),
  surfaceContainerHighest: Color(0xFFE5E2DB),
  outline: Color(0xFF717974),
  outlineVariant: Color(0xFFC0C8C3),
  inverseSurface: Color(0xFF31312C),
  onInverseSurface: Color(0xFFF3F0E9),
  inversePrimary: Color(0xFFA2D0BD),
  surfaceTint: Color(0xFF3C6757),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

// Stitch only designed light mode; dark is derived from the same seed with
// warm, low-glare neutrals for night-time / migraine use.
final ColorScheme _darkScheme =
    ColorScheme.fromSeed(
      seedColor: const Color(0xFF3D6858),
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      surface: const Color(0xFF141512),
      onSurface: const Color(0xFFE6E2DA),
      onSurfaceVariant: const Color(0xFFC0C8C3),
      surfaceContainerLowest: const Color(0xFF0F100E),
      surfaceContainerLow: const Color(0xFF1B1C19),
      surfaceContainer: const Color(0xFF1F211D),
      surfaceContainerHigh: const Color(0xFF2A2C27),
      surfaceContainerHighest: const Color(0xFF353731),
      tertiary: const Color(0xFFFFB597),
    );

TextTheme _textTheme(Color ink, Color muted) {
  TextStyle serif(double size, double height, FontWeight w, [double em = 0]) =>
      TextStyle(
        fontFamily: _serif,
        fontSize: size,
        height: height / size,
        fontWeight: w,
        letterSpacing: size * em,
        color: ink,
      );
  TextStyle sans(
    double size,
    double height,
    FontWeight w, [
    double em = 0,
    Color? c,
  ]) => TextStyle(
    fontFamily: _sans,
    fontSize: size,
    height: height / size,
    fontWeight: w,
    letterSpacing: size * em,
    color: c ?? ink,
  );
  return TextTheme(
    displayLarge: serif(40, 48, FontWeight.w500, -0.02),
    displayMedium: serif(36, 44, FontWeight.w500, -0.015),
    displaySmall: serif(32, 40, FontWeight.w500, -0.015), // headline-xl
    headlineLarge: serif(28, 36, FontWeight.w500, -0.01),
    headlineMedium: serif(26, 34, FontWeight.w500, -0.01), // headline-xl-mobile
    headlineSmall: serif(24, 32, FontWeight.w500, -0.01), // headline-lg
    titleLarge: serif(20, 28, FontWeight.w600), // headline-md
    titleMedium: sans(16, 24, FontWeight.w600),
    titleSmall: sans(14, 20, FontWeight.w600),
    bodyLarge: sans(18, 28, FontWeight.w400), // body-lg
    bodyMedium: sans(16, 24, FontWeight.w400), // body-md
    bodySmall: sans(14, 20, FontWeight.w400, 0, muted), // body-sm
    labelLarge: sans(15, 20, FontWeight.w600, 0.01), // label-lg
    labelMedium: sans(13, 18, FontWeight.w600, 0.02), // label-md
    labelSmall: sans(
      12,
      16,
      FontWeight.w500,
      0.03,
      muted,
    ), // label-sm (12 for legibility)
  );
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark ? _darkScheme : _lightScheme;
  final tokens = isDark ? MindfullTokens.dark : MindfullTokens.light;
  final text = _textTheme(scheme.onSurface, scheme.onSurfaceVariant);
  const pill = StadiumBorder();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: _sans,
    textTheme: text,
    scaffoldBackgroundColor: tokens.canvas,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.headerScrim,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        minimumSize: const Size(48, 48),
        side: BorderSide(
          color: tokens.brand.withValues(alpha: 0.3),
          width: 1.5,
        ),
        foregroundColor: isDark ? scheme.primary : tokens.brand,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: tokens.chip,
      selectedColor: tokens.symptomChip,
      labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        side: BorderSide(color: tokens.cardBorder),
        backgroundColor: tokens.chip,
        foregroundColor: scheme.onSurfaceVariant,
        selectedBackgroundColor: tokens.brand,
        selectedForegroundColor: tokens.onBrand,
        textStyle: text.labelMedium,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tokens.brand
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 10,
      activeTrackColor: tokens.brand,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: tokens.brand.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
      showValueIndicator: ShowValueIndicator.never,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.chip,
      hintStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: pill,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.labelLarge?.copyWith(
        color: scheme.onInverseSurface,
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodySmall,
      iconColor: scheme.onSurfaceVariant,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.brand,
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 8,
      borderRadius: BorderRadius.circular(8),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? tokens.brand : null,
      ),
      checkColor: WidgetStatePropertyAll(tokens.canvas),
      side: BorderSide(color: scheme.outline, width: 1.5),
    ),
  );
}
