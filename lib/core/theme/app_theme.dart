import 'package:flutter/material.dart';

class AppTheme {
  static const Color _seed = Color(0xFF0B6B5E);
  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final text = ThemeData(brightness: brightness).textTheme;
    return ThemeData(
      useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800), titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface, foregroundColor: scheme.onSurface, elevation: 0, scrolledUnderElevation: 1, titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w800)),
      cardTheme: CardThemeData(elevation: 0, margin: const EdgeInsets.symmetric(vertical: 6), color: scheme.surfaceContainerLow, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: scheme.surfaceContainerHighest.withValues(alpha: brightness == Brightness.light ? .55 : .35), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
      navigationBarTheme: NavigationBarThemeData(height: 72, elevation: 3, backgroundColor: scheme.surface, indicatorColor: scheme.primaryContainer, labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: .5)),
    );
  }
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);
}
