import 'package:flutter/material.dart';

/// El Bouni Pièces Auto — rouge — package com.elbouni.annaba
/// (variante unique ; l'ancienne variante bleue "Annaba Edition" a été retirée)
class AppConfig {
  final String appName;
  final Color primaryColor;
  final Color primaryDark;

  const AppConfig._({
    required this.appName,
    required this.primaryColor,
    required this.primaryDark,
  });

  static const _instance = AppConfig._(
    appName: 'El Bouni Pièces Auto',
    primaryColor: Color(0xFFDC2626), // rouge
    primaryDark: Color(0xFFA31515),
  );

  static AppConfig current() => _instance;
}
