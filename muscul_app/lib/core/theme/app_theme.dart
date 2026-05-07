import 'package:flutter/material.dart';

/// Design tokens for Muscul. Built around a single rule: the user is in a gym,
/// hands sweaty, phone often on a bench. Everything must be readable at arm's
/// length under harsh fluorescent lighting and tappable without precision.
///
/// Dark mode is the default experience — most lifters train in artificially
/// lit rooms or evening sessions, and dark UIs reduce glare and OLED battery.
class AppTokens {
  // Brand & accents -------------------------------------------------------
  /// Vivid red-orange — primary action, branding, "energy" cue.
  static const brandRed = Color(0xFFFF3D2A);
  static const brandRedDeep = Color(0xFFC92A1B);
  static const brandRedDark = Color(0xFF3D1410);

  /// Warm amber — secondary highlights, planned/target hints.
  static const accentAmber = Color(0xFFFFB020);
  static const accentAmberDark = Color(0xFF3A2705);

  /// Electric lime — "GO!" state, PR celebration, success burst.
  static const accentLime = Color(0xFFB8FF1F);
  static const accentLimeDark = Color(0xFF22300A);

  /// Cool green — completed/validated set indicator.
  static const successGreen = Color(0xFF22C55E);
  static const successGreenDark = Color(0xFF0F3322);

  static const dangerRed = Color(0xFFFF4D5E);

  // Dark surfaces (OLED-friendly stack) -----------------------------------
  static const darkBg = Color(0xFF0A0A0C);
  static const darkSurface = Color(0xFF141418);
  static const darkSurfaceLow = Color(0xFF101013);
  static const darkSurfaceContainer = Color(0xFF1A1A20);
  static const darkSurfaceContainerHigh = Color(0xFF24242C);
  static const darkSurfaceContainerHighest = Color(0xFF2D2D36);
  static const darkOutline = Color(0xFF34343E);
  static const darkOutlineVariant = Color(0xFF22222A);

  static const darkOnSurface = Color(0xFFF2F2F5);
  static const darkOnSurfaceVariant = Color(0xFFA8A8B3);
  static const darkOnSurfaceMuted = Color(0xFF6E6E78);

  // Light surfaces --------------------------------------------------------
  static const lightBg = Color(0xFFF7F7F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceContainer = Color(0xFFF2F2F4);
  static const lightSurfaceContainerHigh = Color(0xFFE8E8EC);
  static const lightOutline = Color(0xFFCFCFD6);
  static const lightOutlineVariant = Color(0xFFE2E2E7);

  static const lightOnSurface = Color(0xFF0F0F12);
  static const lightOnSurfaceVariant = Color(0xFF55555E);

  // Sizing — gym-friendly (sweaty hands, glance reads) --------------------
  static const double tapTarget = 56;
  static const double tapTargetXL = 72;
  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 16;
  static const double radiusXL = 20;
}

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppTokens.brandRedDeep,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFE0DA),
      onPrimaryContainer: Color(0xFF410B04),
      secondary: Color(0xFFB57400),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFE2B0),
      onSecondaryContainer: Color(0xFF332100),
      tertiary: Color(0xFF4D7300),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFD8F69C),
      onTertiaryContainer: Color(0xFF1A2900),
      error: Color(0xFFC4344A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD9),
      onErrorContainer: Color(0xFF410008),
      surface: AppTokens.lightSurface,
      onSurface: AppTokens.lightOnSurface,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFAFAFC),
      surfaceContainer: AppTokens.lightSurfaceContainer,
      surfaceContainerHigh: AppTokens.lightSurfaceContainerHigh,
      surfaceContainerHighest: Color(0xFFDDDDE2),
      onSurfaceVariant: AppTokens.lightOnSurfaceVariant,
      outline: AppTokens.lightOutline,
      outlineVariant: AppTokens.lightOutlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF1F1F25),
      onInverseSurface: Color(0xFFF2F2F5),
      inversePrimary: AppTokens.brandRed,
    );
    return _build(scheme, isDark: false);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppTokens.brandRed,
      onPrimary: Color(0xFF240805),
      primaryContainer: AppTokens.brandRedDark,
      onPrimaryContainer: Color(0xFFFFD9D2),
      secondary: AppTokens.accentAmber,
      onSecondary: Color(0xFF2B1B00),
      secondaryContainer: AppTokens.accentAmberDark,
      onSecondaryContainer: Color(0xFFFFE2B0),
      tertiary: AppTokens.accentLime,
      onTertiary: Color(0xFF132000),
      tertiaryContainer: AppTokens.accentLimeDark,
      onTertiaryContainer: Color(0xFFE3FFB0),
      error: AppTokens.dangerRed,
      onError: Color(0xFF2B0008),
      errorContainer: Color(0xFF560A1A),
      onErrorContainer: Color(0xFFFFD9DD),
      surface: AppTokens.darkBg,
      onSurface: AppTokens.darkOnSurface,
      surfaceContainerLowest: AppTokens.darkSurfaceLow,
      surfaceContainerLow: AppTokens.darkSurface,
      surfaceContainer: AppTokens.darkSurfaceContainer,
      surfaceContainerHigh: AppTokens.darkSurfaceContainerHigh,
      surfaceContainerHighest: AppTokens.darkSurfaceContainerHighest,
      onSurfaceVariant: AppTokens.darkOnSurfaceVariant,
      outline: AppTokens.darkOutline,
      outlineVariant: AppTokens.darkOutlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppTokens.lightSurface,
      onInverseSurface: AppTokens.lightOnSurface,
      inversePrimary: AppTokens.brandRedDeep,
    );
    return _build(scheme, isDark: true);
  }

  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = _textTheme(scheme);

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // App bar — flat, integrated with the page surface so a single tap zone
      // doesn't fight the hero content underneath.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),
      // Cards: tonal surface, no drop shadow (we layer with surfaceContainer).
      cardTheme: CardTheme(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppTokens.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppTokens.tapTarget),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
        ),
      ),
      // Bottom navigation — pill indicator, bold selected label.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        elevation: 0,
        height: 72,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.2,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
        dividerColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        modalBackgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXL),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outline,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHigh,
        ),
        trackOutlineColor:
            WidgetStateProperty.all(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
      ),
    );
  }

  /// Type scale tuned for glanceable reads at arm's length. Numbers default to
  /// tabular figures so reps/kg don't shift width as digits change.
  static TextTheme _textTheme(ColorScheme scheme) {
    const tabular = [FontFeature.tabularFigures()];
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 56,
        height: 1.05,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.5,
        color: scheme.onSurface,
        fontFeatures: tabular,
      ),
      displayMedium: TextStyle(
        fontSize: 44,
        height: 1.05,
        fontWeight: FontWeight.w900,
        letterSpacing: -1,
        color: scheme.onSurface,
        fontFeatures: tabular,
      ),
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: scheme.onSurface,
        fontFeatures: tabular,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: scheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
