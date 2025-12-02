import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../database_helper.dart';
import 'login_screen.dart';
import 'auth_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _mensajeEstado = 'Iniciando...';
  double _progreso = 0.0;

  @override
  void initState() {
    super.initState();
    _iniciarCarga();
  }

  Future<void> _iniciarCarga() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('velneo_url');
    final apiKey = prefs.getString('velneo_api_key');
    final comercialId = prefs.getInt('comercial_id');

    // 1. Si no hay credenciales, ir al Login
    if (url == null || apiKey == null || comercialId == null) {
      if (!mounted) return;
      _navegar(const LoginScreen());
      return;
    }

    // 2. Iniciar Sincronización
    try {
      setState(() => _mensajeEstado = 'Conectando con el servidor...');

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey,
      );

      // Verificación rápida
      if (!await api.probarConexion()) {
        throw Exception('Sin conexión al servidor');
      }

      // 🟢 SINCRONIZACIÓN DE MAESTROS (Series, Formas Pago, etc.)
      setState(() {
        _mensajeEstado = 'Actualizando Maestros...';
        _progreso = 0.3;
      });

      await api.sincronizarMaestros();

      setState(() {
        _mensajeEstado = 'Finalizando...';
        _progreso = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      _navegar(const AuthScreen());
    } catch (e) {
      print('Error en Splash: $e');
      // Si falla (ej. sin internet), entramos igual para trabajar offline
      if (!mounted) return;
      _navegar(const AuthScreen());
    }
  }

  void _navegar(Widget pantalla) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (context) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF032458),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              'TecERP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: _progreso > 0 ? _progreso : null,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _mensajeEstado,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
