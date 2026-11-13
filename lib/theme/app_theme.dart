import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografía de títulos (capitales romanas ornamentadas).
const String displayFont = 'CinzelDecorative';

/// Tipografía de lectura (serif de libro antiguo).
const String bodyFont = 'CrimsonText';

/// Estilo para títulos fijos de la interfaz.
TextStyle displayStyle({
  double size = 22,
  Color color = AppColors.ink,
  FontWeight weight = FontWeight.w700,
}) {
  return TextStyle(
    fontFamily: displayFont,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: 0.6,
    height: 1.15,
  );
}

/// Transición entre pantallas: la nueva aparece con un fundido y un leve
/// ascenso; la anterior se aleja apenas. Suave y corta.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  static final _fade = CurveTween(curve: Curves.easeOutCubic);
  static final _slide = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));
  static final _recede = Tween<double>(
    begin: 1,
    end: 0.97,
  ).chain(CurveTween(curve: Curves.easeOut));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ScaleTransition(
      scale: secondaryAnimation.drive(_recede),
      child: FadeTransition(
        opacity: animation.drive(_fade),
        child: SlideTransition(position: animation.drive(_slide), child: child),
      ),
    );
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.bark,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.bark,
    onPrimary: AppColors.vellum,
    secondary: AppColors.gold,
    onSecondary: AppColors.ink,
    surface: AppColors.vellum,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSoft,
    surfaceContainerLowest: AppColors.vellum,
    surfaceContainerLow: AppColors.vellum,
    surfaceContainer: AppColors.vellum,
    surfaceContainerHigh: AppColors.parchment,
    surfaceContainerHighest: AppColors.parchment,
    outline: AppColors.goldDeep,
    outlineVariant: AppColors.parchmentDeep,
    error: AppColors.crimson,
    onError: AppColors.vellum,
    surfaceTint: Colors.transparent,
  );

  const border = BorderSide(color: AppColors.gold, width: 1.5);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: border,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: bodyFont,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.parchment,
    splashFactory: InkRipple.splashFactory,
    splashColor: AppColors.gold.withValues(alpha: 0.18),
    highlightColor: AppColors.gold.withValues(alpha: 0.08),
    textTheme: base.textTheme
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 19),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 17),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 15),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 19),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 17),
        )
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const SoftPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ink,
      foregroundColor: AppColors.goldLight,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: displayStyle(size: 24, color: AppColors.goldLight),
      shape: const Border(bottom: BorderSide(color: AppColors.gold, width: 2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 18),
      floatingLabelStyle: const TextStyle(
        color: AppColors.bark,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: AppColors.inkSoft.withValues(alpha: 0.6)),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.goldDeep),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.gold, width: 2.5),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.bark,
      selectionColor: AppColors.gold.withValues(alpha: 0.35),
      selectionHandleColor: AppColors.goldDeep,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.bark,
        foregroundColor: AppColors.vellum,
        textStyle: const TextStyle(
          fontFamily: bodyFont,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.gold),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.bark,
        textStyle: const TextStyle(
          fontFamily: bodyFont,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.bark),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.vellum,
      shape: shape,
      titleTextStyle: displayStyle(size: 20),
      contentTextStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 18,
        color: AppColors.ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 17,
        color: AppColors.vellum,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.vellum,
      headerBackgroundColor: AppColors.bark,
      headerForegroundColor: AppColors.vellum,
      shape: shape,
    ),
    popupMenuTheme: PopupMenuThemeData(color: AppColors.vellum, shape: shape),
    dropdownMenuTheme: const DropdownMenuThemeData(),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold),
      ),
      textStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        color: AppColors.vellum,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gold,
    ),
    dividerColor: AppColors.parchmentDeep,
  );
}
