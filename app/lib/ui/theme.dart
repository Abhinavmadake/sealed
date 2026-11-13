import 'package:flutter/material.dart';

const serifFamily = 'serif';

abstract final class Graphite {
  static const ink = Color(0xFF111113);
  static const paper = Color(0xFFDCDAD5);
  static const chalk = Color(0xFFECEAE5);
  static const pill = Color(0xFF161617);
  static const pillSelected = Color(0xFF34343A);
}

ColorScheme _scheme(Brightness b) => b == Brightness.dark
    ? const ColorScheme(
        brightness: Brightness.dark,
        primary: Graphite.chalk,
        onPrimary: Graphite.ink,
        primaryContainer: Color(0xFF26262A),
        onPrimaryContainer: Graphite.chalk,
        secondary: Color(0xFFB9B6B0),
        onSecondary: Graphite.ink,
        secondaryContainer: Color(0xFF1C1C1E),
        onSecondaryContainer: Color(0xFFD6D3CD),
        tertiary: Color(0xFFCFC8B8),
        onTertiary: Graphite.ink,
        tertiaryContainer: Color(0xFF2A2824),
        onTertiaryContainer: Color(0xFFE6DFCF),
        error: Color(0xFFE58A73),
        onError: Graphite.ink,
        errorContainer: Color(0xFF3A1E18),
        onErrorContainer: Color(0xFFF2C3B6),
        surface: Graphite.ink,
        onSurface: Graphite.chalk,
        onSurfaceVariant: Color(0xFF8F8D88),
        surfaceContainerLowest: Color(0xFF080809),
        surfaceContainerLow: Color(0xFF17171A),
        surfaceContainer: Color(0xFF1B1B1E),
        surfaceContainerHigh: Color(0xFF212124),
        surfaceContainerHighest: Color(0xFF29292D),
        outline: Color(0xFF4A4947),
        outlineVariant: Color(0xFF29292B),
        inverseSurface: Graphite.chalk,
        onInverseSurface: Graphite.ink,
        inversePrimary: Graphite.ink,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      )
    : const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF151515),
        onPrimary: Graphite.chalk,
        primaryContainer: Color(0xFFC8C6C0),
        onPrimaryContainer: Color(0xFF151515),
        secondary: Color(0xFF3D3C3A),
        onSecondary: Graphite.chalk,
        secondaryContainer: Color(0xFFD2D0CA),
        onSecondaryContainer: Color(0xFF2A2927),
        tertiary: Color(0xFF4A4538),
        onTertiary: Graphite.chalk,
        tertiaryContainer: Color(0xFFCCC6B6),
        onTertiaryContainer: Color(0xFF2E2A20),
        error: Color(0xFFA8361F),
        onError: Graphite.chalk,
        errorContainer: Color(0xFFE9C9BF),
        onErrorContainer: Color(0xFF5A1A0E),
        surface: Graphite.paper,
        onSurface: Color(0xFF121212),
        onSurfaceVariant: Color(0xFF5F5D59),
        surfaceContainerLowest: Color(0xFFE8E6E2),
        surfaceContainerLow: Color(0xFFE2E0DB),
        surfaceContainer: Color(0xFFD6D4CF),
        surfaceContainerHigh: Color(0xFFCFCDC8),
        surfaceContainerHighest: Color(0xFFC8C6C0),
        outline: Color(0xFF9C9993),
        outlineVariant: Color(0xFFC2BFB9),
        inverseSurface: Color(0xFF151515),
        onInverseSurface: Graphite.chalk,
        inversePrimary: Graphite.chalk,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      );

TextTheme _text(ColorScheme s) {
  final base = (s.brightness == Brightness.dark ? Typography.material2021().white : Typography.material2021().black)
      .apply(bodyColor: s.onSurface, displayColor: s.onSurface);
  TextStyle? light(TextStyle? t, double spacing) => t?.copyWith(fontWeight: FontWeight.w300, letterSpacing: spacing);
  return base.copyWith(
    displayLarge: light(base.displayLarge, -1.5),
    displayMedium: light(base.displayMedium, -1.2),
    displaySmall: light(base.displaySmall, -1),
    headlineLarge: light(base.headlineLarge, -0.8),
    headlineMedium: light(base.headlineMedium, -0.6),
    headlineSmall: light(base.headlineSmall, -0.4),
    titleLarge: light(base.titleLarge, -0.2),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w400),
    labelSmall: base.labelSmall?.copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w500),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final s = _scheme(brightness);
  final text = _text(s);
  final hairline = BorderSide(color: s.outlineVariant, width: 0.8);
  const pill = StadiumBorder();
  const tight = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6)));
  final buttonText = text.labelLarge?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.4);

  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    textTheme: text,
    scaffoldBackgroundColor: s.surface,
    canvasColor: s.surface,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        minimumSize: const Size(64, 52),
        textStyle: buttonText,
        disabledBackgroundColor: s.onSurface.withValues(alpha: 0.12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        minimumSize: const Size(64, 52),
        foregroundColor: s.onSurface,
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        side: const BorderSide(color: Color(0x40FFFFFF), width: 0.8),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: s.onSurface, shape: pill, textStyle: buttonText),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: s.onSurface)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        side: BorderSide(color: s.outline, width: 0.8),
        selectedBackgroundColor: s.primary,
        selectedForegroundColor: s.onPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surface.withValues(alpha: 0.88),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: hairline),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: s.outline, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: s.onSurface, width: 1.2),
      ),
      labelStyle: TextStyle(color: s.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: s.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: s.surfaceContainerLow,
      shape: tight.copyWith(side: hairline),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant, thickness: 0.8),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      iconColor: s.onSurfaceVariant,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodyMedium?.copyWith(color: s.onSurfaceVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primary,
      foregroundColor: s.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: pill,
      extendedTextStyle: buttonText,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.inverseSurface,
      contentTextStyle: TextStyle(color: s.onInverseSurface),
      shape: tight,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.onSurface,
      linearTrackColor: s.outlineVariant,
      circularTrackColor: s.outlineVariant,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerLow,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        side: BorderSide(color: Color(0x24FFFFFF)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surfaceContainerHigh,
      elevation: 6,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Color(0x24FFFFFF)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    ),
    bannerTheme: const MaterialBannerThemeData(backgroundColor: Color(0x12FFFFFF), elevation: 0),
    badgeTheme: BadgeThemeData(backgroundColor: s.onSurface, textColor: s.surface),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.surface : s.outline),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? s.onSurface : s.surfaceContainerHigh,
      ),
      trackOutlineColor: WidgetStateProperty.all(s.outline),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.onSurface : null),
      checkColor: WidgetStateProperty.all(s.surface),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: s.onSurface,
      inactiveTrackColor: s.outlineVariant,
      thumbColor: s.onSurface,
    ),
  );
}

TextStyle eyebrow(BuildContext context) {
  final t = Theme.of(context);
  return t.textTheme.labelSmall!.copyWith(color: t.colorScheme.onSurfaceVariant);
}

TextStyle serifAccent(BuildContext context, {double size = 20}) => TextStyle(
  fontFamily: serifFamily,
  fontStyle: FontStyle.italic,
  fontSize: size,
  color: Theme.of(context).colorScheme.onSurface,
  letterSpacing: -0.2,
);
