import 'package:flutter/material.dart';
// Mantener si se usa en otros lados
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
// import 'screens/login_screen.dart'; // Ya no es necesario importarlo aquí directamente si usas splash
// import 'screens/auth_screen.dart';
import 'screens/splash_screen.dart'; // 🟢 1. IMPORTAR EL SPLASH SCREEN

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VelneoApp());
}

class VelneoApp extends StatelessWidget {
  // Puedes cambiarlo a StatelessWidget si ya no gestionas estado aquí
  const VelneoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRM Velneo',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],

      // 🟢 2. CAMBIAR EL HOME AL SPLASH SCREEN
      home: const SplashScreen(),
    );
  }
}
