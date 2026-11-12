import 'package:flutter/material.dart';

import 'models.dart';

/// One accented colour, calm graphite surfaces and a single warning colour.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.warning,
    required this.success,
    required this.reasoning,
    required this.code,
    required this.sidebar,
  });

  final Color warning;
  final Color success;
  final Color reasoning;
  final Color code;
  final Color sidebar;

  static const AppColors _fallback = AppColors(
    warning: Color(0xFFE3B341),
    success: Color(0xFF5FD3A1),
    reasoning: Color(0xFF171C27),
    code: Color(0xFF0D1117),
    sidebar: Color(0xFF0D1016),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? _fallback;

  @override
  AppColors copyWith({
    Color? warning,
    Color? success,
    Color? reasoning,
    Color? code,
    Color? sidebar,
  }) => AppColors(
    warning: warning ?? this.warning,
    success: success ?? this.success,
    reasoning: reasoning ?? this.reasoning,
    code: code ?? this.code,
    sidebar: sidebar ?? this.sidebar,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      reasoning: Color.lerp(reasoning, other.reasoning, t)!,
      code: Color.lerp(code, other.code, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
    );
  }
}

const Color _seed = Color(0xFF7C8CFF);

/// Compactness flags shared by widgets that cannot rely on [VisualDensity]
/// alone (message spacing, list padding, composer margins).
class AppDensity extends ThemeExtension<AppDensity> {
  const AppDensity({required this.compact});

  final bool compact;

  static bool isCompact(BuildContext context) =>
      Theme.of(context).extension<AppDensity>()?.compact ?? false;

  @override
  AppDensity copyWith({bool? compact}) =>
      AppDensity(compact: compact ?? this.compact);

  @override
  AppDensity lerp(ThemeExtension<AppDensity>? other, double t) {
    if (other is! AppDensity) return this;
    return t < 0.5 ? this : other;
  }
}

ColorScheme _darkScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  );
  return base.copyWith(
    primary: const Color(0xFF9AA7FF),
    onPrimary: const Color(0xFF0B1020),
    primaryContainer: const Color(0xFF1C2350),
    onPrimaryContainer: const Color(0xFFDDE1FF),
    secondary: const Color(0xFFA8B6D0),
    onSecondary: const Color(0xFF10151F),
    tertiary: const Color(0xFFC7B3FF),
    onTertiary: const Color(0xFF1B1030),
    surface: const Color(0xFF101319),
    onSurface: const Color(0xFFE8EAF0),
    onSurfaceVariant: const Color(0xFFA0A8B8),
    surfaceContainerLowest: const Color(0xFF0A0C10),
    surfaceContainerLow: const Color(0xFF141821),
    surfaceContainer: const Color(0xFF181D27),
    surfaceContainerHigh: const Color(0xFF1E2430),
    surfaceContainerHighest: const Color(0xFF232A37),
    outline: const Color(0xFF3A4252),
    outlineVariant: const Color(0xFF283040),
    error: const Color(0xFFFF8A8A),
    onError: const Color(0xFF2A0507),
    errorContainer: const Color(0xFF3A1518),
    onErrorContainer: const Color(0xFFFFDAD6),
  );
}

ColorScheme _lightScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
  );
  return base.copyWith(
    primary: const Color(0xFF5265E8),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDDE1FF),
    onPrimaryContainer: const Color(0xFF11164A),
    tertiary: const Color(0xFF6E4EC4),
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF11161F),
    onSurfaceVariant: const Color(0xFF566070),
    surfaceContainerLowest: const Color(0xFFF8F9FC),
    surfaceContainerLow: const Color(0xFFF3F5F9),
    surfaceContainer: const Color(0xFFEDF0F5),
    surfaceContainerHigh: const Color(0xFFE7EBF2),
    surfaceContainerHighest: const Color(0xFFE0E5EE),
    outline: const Color(0xFF8A94A6),
    outlineVariant: const Color(0xFFD5DBE5),
    error: const Color(0xFFB3261E),
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410E0B),
  );
}

TextTheme _textTheme(Brightness brightness, String? fontFamily) {
  final base = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  final fonts = fontFamily == null ? base : base.apply(fontFamily: fontFamily);
  final body = fonts.bodyMedium ?? const TextStyle();
  return fonts.copyWith(
    displaySmall: body.copyWith(
      fontSize: 30,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    headlineMedium: body.copyWith(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleLarge: body.copyWith(
      fontSize: 20,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: body.copyWith(
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: body.copyWith(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: body.copyWith(fontSize: 15, height: 1.45),
    bodyMedium: body.copyWith(fontSize: 14, height: 1.4),
    bodySmall: body.copyWith(fontSize: 12, height: 1.35),
    labelLarge: body.copyWith(
      fontSize: 14,
      height: 1.2,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: body.copyWith(
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: body.copyWith(
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
  );
}

ThemeData buildTheme(
  Brightness brightness, {
  String? fontFamily,
  UiDensity density = UiDensity.normal,
}) {
  final isDark = brightness == Brightness.dark;
  final compact = density == UiDensity.compact;
  final scheme = isDark ? _darkScheme() : _lightScheme();
  final textTheme = _textTheme(brightness, fontFamily);
  final background = scheme.surfaceContainerLowest;
  final outline = scheme.outlineVariant.withValues(alpha: 0.7);
  final radius = BorderRadius.circular(14);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    materialTapTargetSize: compact
        ? MaterialTapTargetSize.shrinkWrap
        : MaterialTapTargetSize.padded,
    extensions: [
      AppColors(
        warning: isDark ? const Color(0xFFE3B341) : const Color(0xFF8A5B00),
        success: isDark ? const Color(0xFF5FD3A1) : const Color(0xFF1F7A55),
        reasoning: isDark ? const Color(0xFF171C27) : const Color(0xFFF0F2F9),
        code: isDark ? const Color(0xFF0D1117) : const Color(0xFFF4F6FA),
        sidebar: isDark ? const Color(0xFF0D1016) : const Color(0xFFF5F7FB),
      ),
      AppDensity(compact: compact),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleMedium,
      toolbarHeight: compact ? 52 : 60,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: isDark
          ? const Color(0xFF0D1016)
          : const Color(0xFFF5F7FB),
      surfaceTintColor: Colors.transparent,
      width: 320,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.outline,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: textTheme.titleLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 10 : 13,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: outline.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? scheme.surfaceContainerLow : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline.withValues(alpha: 0.55)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: outline.withValues(alpha: 0.55),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 0 : 2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, compact ? 40 : 46),
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: compact ? 9 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, compact ? 38 : 44),
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: compact ? 8 : 11,
        ),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 7 : 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        highlightColor: scheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: outline.withValues(alpha: 0.6)),
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelMedium,
      secondaryLabelStyle: textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: textTheme.labelMedium,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: textTheme.bodyMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      waitDuration: const Duration(milliseconds: 450),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      actionTextColor: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        scheme.outline.withValues(alpha: 0.55),
      ),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
    ),
  );
}
