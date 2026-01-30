import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.lightBackground,
      scaffoldBackgroundColor: AppColors.lightBackground,
      
      // Text Theme
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.lightTextPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.lightTextPrimary, fontSize: 14),
        titleMedium: TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
      ),

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.iconColorLight),
        titleTextStyle: TextStyle(
          color: AppColors.lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      
      // Drawer Theme
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.lightSurface,
      ),

      // Icon Theme
      iconTheme: const IconThemeData(color: AppColors.iconColorLight),
      
      // Correct ColorScheme
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightBackground,
        secondary: AppColors.accentTeal,
        background: AppColors.lightBackground,
        surface: AppColors.lightSurface,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.darkBackground,
      scaffoldBackgroundColor: AppColors.darkBackground,
      
      // Text Theme
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.darkTextPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.darkTextPrimary, fontSize: 14),
        titleMedium: TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
      ),

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.iconColorDark),
        titleTextStyle: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Drawer Theme
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.darkSurface,
      ),

      // Icon Theme
      iconTheme: const IconThemeData(color: AppColors.iconColorDark),
      
      // Correct ColorScheme
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkBackground,
        secondary: AppColors.accentTeal,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
      ),
    );
  }
}
