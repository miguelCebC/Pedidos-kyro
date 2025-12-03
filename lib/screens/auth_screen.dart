import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _comercialIdController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _nuevaContrasenaController = TextEditingController();
  final _confirmarContrasenaController = TextEditingController();

  bool _isLoading = true;
  bool _esPrimeraVez = false;
  String _mensajeError = '';

  @override
  void initState() {
    super.initState();
    _verificarPrimeraVez();
  }

  @override
  void dispose() {
    _comercialIdController.dispose();
    _contrasenaController.dispose();
    _nuevaContrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    super.dispose();
  }

  Future<void> _verificarPrimeraVez() async {
    final db = DatabaseHelper.instance;
    final existeContrasena = await db.existeContrasenaLocal();

    setState(() {
      _esPrimeraVez = !existeContrasena;
      _isLoading = false;
    });
  }

  Future<void> _establecerContrasena() async {
    final comercialId = int.tryParse(_comercialIdController.text.trim());
    final nuevaContrasena = _nuevaContrasenaController.text.trim();
    final confirmarContrasena = _confirmarContrasenaController.text.trim();

    if (comercialId == null) {
      setState(() => _mensajeError = 'El ID debe ser un número válido');
      return;
    }

    if (nuevaContrasena.isEmpty || nuevaContrasena.length < 4) {
      setState(
        () => _mensajeError = 'La contraseña debe tener al menos 4 caracteres',
      );
      return;
    }

    if (nuevaContrasena != confirmarContrasena) {
      setState(() => _mensajeError = 'Las contraseñas no coinciden');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verificar que el comercial existe en la sesión guardada
      final prefs = await SharedPreferences.getInstance();
      final comercialGuardado = prefs.getInt('comercial_id');

      if (comercialGuardado == null || comercialGuardado != comercialId) {
        setState(() {
          _mensajeError =
              'El ID de comercial no coincide con la sesión guardada';
          _isLoading = false;
        });
        return;
      }

      // Guardar contraseña
      final db = DatabaseHelper.instance;
      await db.guardarContrasenaLocal(nuevaContrasena);

      if (!mounted) return;

      // Ir a home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _mensajeError = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _validarContrasena() async {
    final comercialId = int.tryParse(_comercialIdController.text.trim());
    final contrasena = _contrasenaController.text.trim();

    if (comercialId == null) {
      setState(() => _mensajeError = 'El ID debe ser un número válido');
      return;
    }

    if (contrasena.isEmpty) {
      setState(() => _mensajeError = 'La contraseña es obligatoria');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verificar comercial
      final prefs = await SharedPreferences.getInstance();
      final comercialGuardado = prefs.getInt('comercial_id');

      if (comercialGuardado == null || comercialGuardado != comercialId) {
        setState(() {
          _mensajeError = 'ID de comercial incorrecto';
          _isLoading = false;
        });
        return;
      }

      // Verificar contraseña
      final db = DatabaseHelper.instance;
      final contrasenaGuardada = await db.obtenerContrasenaLocal();

      if (contrasenaGuardada != contrasena) {
        setState(() {
          _mensajeError = 'Contraseña incorrecta';
          _isLoading = false;
        });
        return;
      }

      // Mostrar loading mínimo 3 segundos
      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      // Ir a home inmediatamente
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _mensajeError = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Icon(
                Icons.lock_outline,
                size: 80,
                color: Color(0xFF032458),
              ),
              const SizedBox(height: 24),
              Text(
                _esPrimeraVez ? 'Crear Contraseña' : 'Verificación',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF032458),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _esPrimeraVez
                    ? 'Establece una contraseña de seguridad'
                    : 'Ingresa tu ID y contraseña',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 48),

              // ID Comercial
              TextField(
                controller: _comercialIdController,
                decoration: const InputDecoration(
                  labelText: 'ID del Comercial *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),

              if (_esPrimeraVez) ...[
                // Nueva contraseña
                TextField(
                  controller: _nuevaContrasenaController,
                  decoration: const InputDecoration(
                    labelText: 'Nueva Contraseña *',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                    helperText: 'Mínimo 4 caracteres',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),

                // Confirmar contraseña
                TextField(
                  controller: _confirmarContrasenaController,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar Contraseña *',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ] else ...[
                // Contraseña existente
                TextField(
                  controller: _contrasenaController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña *',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _validarContrasena(),
                ),
              ],

              if (_mensajeError.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _mensajeError,
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Botón
              ElevatedButton(
                onPressed: _esPrimeraVez
                    ? _establecerContrasena
                    : _validarContrasena,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF032458),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _esPrimeraVez ? 'ESTABLECER CONTRASEÑA' : 'INGRESAR',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
