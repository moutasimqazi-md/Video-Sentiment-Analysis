import 'package:flutter/material.dart';

/// NeuroLens look: warm off-white surfaces, coral accent (an AA-contrast shade for text and buttons), soft cards.
class NlColors {
  static const coral = Color(0xFFF4685F);
  static const coralInk = Color(0xFFC13530);
  static const coralSoft = Color(0xFFFFF0ED);
  static const blue = Color(0xFF4A7CF0);
  static const blueSoft = Color(0xFFE9F0FF);
  static const green = Color(0xFF137350);
  static const greenSoft = Color(0xFFE3F6EE);
  static const amber = Color(0xFF8F5A05);
  static const amberSoft = Color(0xFFFFF4DE);
  static const bg = Color(0xFFFCFAF8);
  static const ink = Color(0xFF17203A);
  static const muted = Color(0xFF55617C);
  static const border = Color(0xFFE8EAF3);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: NlColors.coral,
    brightness: b,
    primary: dark ? const Color(0xFFFF9487) : NlColors.coralInk,
    onPrimary: dark ? const Color(0xFF3A1210) : Colors.white,
    surface: dark ? const Color(0xFF161D33) : Colors.white,
    onSurface: dark ? const Color(0xFFEEF1FB) : NlColors.ink,
    onSurfaceVariant: dark ? const Color(0xFFA1ABC9) : NlColors.muted,
    outlineVariant: dark ? const Color(0xFF263050) : NlColors.border,
    secondaryContainer: dark ? const Color(0xFF3A2328) : NlColors.coralSoft,
    onSecondaryContainer: dark ? const Color(0xFFFF9487) : NlColors.coralInk,
    surfaceContainerHighest: dark ? const Color(0xFF1B2340) : const Color(0xFFF6F7FB),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0E1322) : NlColors.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0E1322) : NlColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: scheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: BorderSide(color: scheme.outlineVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: dark ? 0.6 : 0.7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}
