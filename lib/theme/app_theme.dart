import 'package:flutter/material.dart';
import '../config/app_config.dart';

/// Palette et thème visuels VROUM DZ — thème CLAIR (fond blanc). Un seul
/// point de vérité pour les couleurs ; les écrans doivent utiliser ces
/// tokens plutôt que des couleurs codées en dur.
///
/// Remplace l'ancien thème sombre (fond #0A0A0A) : demande explicite de
/// retirer le noir au profit du blanc, avec des images de fond
/// thématiques par écran (voir widgets/screen_background.dart) qui
/// nécessitent un fond clair pour rester lisibles.
class AppColors {
  AppColors._();

  // Marque — vert VROUM DZ. Ne pas changer sans mettre à jour aussi
  // l'icône de l'app / le splash screen.
  static const primary = Color(0xFF22C55E);
  static const primaryDark = Color(0xFF16A34A);
  static const primaryLight = Color(0xFFE7F9EE);

  // États métier — indépendants de la couleur de marque.
  static const enchere = Color(0xFFF97316); // orange — enchères/offres
  static const sos = Color(0xFFEF4444); // rouge — alertes/SOS/expiré

  // Fond clair
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF7F8FA);
  static const border = Color(0xFFE5E7EB);

  // Texte
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF4B5563);
  static const textMuted = Color(0xFF9CA3AF);

  // États (assurance/CT/entretien) — vert/orange/rouge, indépendants de
  // la couleur de marque pour rester lisibles même si la marque change.
  static const success = primary;
  static const successBg = Color(0xFFDCFCE7);
  static const warning = enchere;
  static const warningBg = Color(0xFFFEF3C7);
  static const error = sos;
  static const errorBg = Color(0xFFFEE2E2);
}

class AppTheme {
  AppTheme._();

  static ShapeBorder get cardShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      );

  /// Thème clair VROUM DZ. [config] permet de garder la couleur de marque
  /// pilotée depuis AppConfig plutôt que dupliquée ici.
  static ThemeData light(AppConfig config) {
    final scheme = ColorScheme.fromSeed(
      seedColor: config.primaryColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: config.primaryColor,
      onPrimary: Colors.white,
      secondary: config.enchereColor,
      error: config.sosColor,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            headlineSmall: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
            titleLarge: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            bodySmall: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: config.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: config.primaryColor.withValues(alpha: 0.35),
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: config.primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: config.primaryColor,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: config.primaryColor, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        prefixIconColor: AppColors.textMuted,
      ),

      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.primaryLight,
        labelStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: config.primaryColor.withValues(alpha: 0.14),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? config.primaryColor : AppColors.textMuted,
          );
        }),
      ),
    );
  }

  /// Thème sombre VROUM DZ — fonds ardoise, texte clair, accent vert.
  static ThemeData dark(AppConfig config) {
    const bg = Color(0xFF0B1220);
    const surface = Color(0xFF151C2C);
    const surfaceMuted = Color(0xFF1C2436);
    const border = Color(0xFF2A3348);
    const textPrimary = Color(0xFFF3F4F6);
    const textSecondary = Color(0xFFCBD5E1);
    const textMuted = Color(0xFF94A3B8);

    final scheme = ColorScheme.fromSeed(
      seedColor: config.primaryColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: config.primaryColor,
      onPrimary: Colors.white,
      secondary: config.enchereColor,
      error: config.sosColor,
      surface: surface,
      onSurface: textPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: config.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: config.primaryColor.withValues(alpha: 0.35),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: config.primaryColor,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: config.primaryColor),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: config.primaryColor, width: 1.6),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        prefixIconColor: textMuted,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceMuted,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: config.primaryColor.withValues(alpha: 0.22),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? config.primaryColor : textMuted,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return config.primaryColor;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return config.primaryColor.withValues(alpha: 0.35);
          }
          return border;
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: textSecondary, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
      ),
    );
  }
}
