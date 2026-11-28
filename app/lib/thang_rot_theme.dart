import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const brandBlue = Color(0xFF0B4FD6);
const brandDark = Color(0xFF0A3A9E);
const brandButton = Color(0xFF0A2A6B);
const pageBackground = Color(0xFFF4F7FC);
const cardBorder = Color(0xFFE6EBF2);
const brandInk = Color(0xFF0F172A);
const mutedInk = Color(0xFF516078);
const blueTint = Color(0xFFEAF1FF);
const brandGradient = LinearGradient(
  colors: [brandDark, brandBlue, Color(0xFF3875E5)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const pageCorners = BorderRadius.vertical(bottom: Radius.circular(22));

ThemeData thangRotTheme() {
  const scheme = ColorScheme.light(
    primary: brandBlue,
    primaryContainer: blueTint,
    onPrimaryContainer: brandDark,
    secondary: brandDark,
    secondaryContainer: blueTint,
    onSecondaryContainer: brandDark,
    surface: Colors.white,
    onSurface: brandInk,
    onSurfaceVariant: mutedInk,
    outline: Color(0xFF8490A3),
    outlineVariant: cardBorder,
  );
  final theme = ThemeData(useMaterial3: true, colorScheme: scheme);
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(30));
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(15),
    borderSide: const BorderSide(color: cardBorder),
  );
  return theme.copyWith(
    scaffoldBackgroundColor: pageBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: pageBackground,
      foregroundColor: brandInk,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        color: brandInk,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: cardBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brandButton,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: pill,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: brandDark,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: const BorderSide(color: cardBorder),
        shape: pill,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brandDark,
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brandInk,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: Color(0xFFC7D9FF),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: field,
      enabledBorder: field,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: blueTint,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          color: states.contains(WidgetState.selected) ? brandButton : mutedInk,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
        ),
      ),
    ),
  );
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.size,
    this.decorative = false,
    this.wordmark = false,
  });

  final double size;
  final bool decorative;
  final bool wordmark;

  @override
  Widget build(BuildContext context) => Image.asset(
    wordmark
        ? 'assets/thang-rot/thang-rot-logo.png'
        : 'assets/thang-rot/app-logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: decorative ? null : 'ทางรอด',
    excludeFromSemantics: decorative,
  );
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: brandGradient,
        borderRadius: pageCorners,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 17),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: child,
          ),
        ),
      ),
    ),
  );
}
