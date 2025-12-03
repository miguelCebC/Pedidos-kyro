import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../database_helper.dart';
import 'auth_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _comercialIdController = TextEditingController();
  final _codigoAppController = TextEditingController();
  final _serverUrlController = TextEditingController(
    text: 'tecerp.nunsys.com:4331/TORRAL/TecERPv7_dat_dat',
  );
  final _apiVersionController = TextEditingController(text: 'v1');
  final _apiKeyController = TextEditingController(text: '123456');

  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void dispose() {
    _comercialIdController.dispose();
    _serverUrlController.dispose();
    _apiVersionController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    final comercialId = int.tryParse(_comercialIdController.text.trim());
    final codigoApp = _codigoAppController.text.trim();

    if (comercialId == null || codigoApp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Revisa los datos de acceso')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Validando acceso...';
    });

    try {
      String serverUrl = _serverUrlController.text.trim();
      final apiVersion = _apiVersionController.text.trim();
      if (serverUrl.endsWith('/')) {
        serverUrl = serverUrl.substring(0, serverUrl.length - 1);
      }
      final fullUrl = '$serverUrl/$apiVersion';
      String finalUrl = fullUrl.startsWith('http')
          ? fullUrl
          : 'https://$fullUrl';

      final apiKey = _apiKeyController.text.trim();
      final apiService = VelneoAPIService(finalUrl, apiKey);

      // --- 1. Descargar entidades ---
      setState(() => _statusMessage = 'Buscando entidad...');
      final resultado = await apiService.obtenerClientes();
      final clientesLista = resultado['clientes'] as List;
      final comercialesLista = resultado['comerciales'] as List;

      final db = DatabaseHelper.instance;
      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesLista.cast<Map<String, dynamic>>(),
      );
      await db.insertarClientesLote(clientesLista.cast<Map<String, dynamic>>());

      // --- 2. Validar ID Entidad ---
      Map<String, dynamic>? entidadEncontrada;
      try {
        entidadEncontrada = comercialesLista.firstWhere(
          (c) => c['id'].toString() == comercialId.toString(),
        );
      } catch (e) {
        try {
          entidadEncontrada = clientesLista.firstWhere(
            (c) => c['id'].toString() == comercialId.toString(),
          );
        } catch (e) {
          // No existe
        }
      }

      if (entidadEncontrada == null) {
        throw Exception('No existe ninguna Entidad con ID $comercialId.');
      }

      // --- 3. Buscar el usuario asociado ---
      setState(() => _statusMessage = 'Verificando usuario...');
      final usuariosLista = await apiService.obtenerTodosUsuarios();
      await db.insertarUsuariosLote(usuariosLista.cast<Map<String, dynamic>>());

      Map<String, dynamic>? usuario;
      try {
        usuario = usuariosLista.cast<Map<String, dynamic>>().firstWhere(
          (u) => u['ent'].toString() == comercialId.toString(),
        );
      } catch (e) {
        // Fallback
      }

      if (usuario == null) {
        throw Exception(
          'La entidad "${entidadEncontrada['nombre']}" no tiene un Usuario de App asociado (USR_M).',
        );
      }

      // --- 4. Validar permisos en usr_apl ---
      setState(() => _statusMessage = 'Verificando permisos...');
      final usrAplLista = await apiService.obtenerTodosUsrApl();

      // 🟢 CHEQUEO DE LISTA VACÍA CON MENSAJE CLARO
      if (usrAplLista.isEmpty) {
        throw Exception(
          'La lista de permisos (USR_APL) está vacía. Revisa la conexión o el nombre de la tabla en Velneo.',
        );
      }

      // 🟢 BÚSQUEDA Y COMPARACIÓN MANUAL (Como pediste)
      Map<String, dynamic>? relacionEncontrada;

      // Convertimos a String para asegurar la comparación
      final String targetUsrM = usuario['id'].toString();
      final String targetAplTec = codigoApp.toString();

      print('🔍 Buscando permiso: UsrM=$targetUsrM, AplTec=$targetAplTec');

      for (var reg in usrAplLista) {
        final String dbUsrM = reg['usr_m'].toString();
        final String dbAplTec = reg['apl_tec'].toString();

        if (dbUsrM == targetUsrM && dbAplTec == targetAplTec) {
          relacionEncontrada = reg;
          break; // Encontrado
        }
      }

      if (relacionEncontrada == null) {
        // Si falla, buscamos qué permisos TIENE ese usuario para mostrar error útil
        final permisosUsuario = usrAplLista
            .where((reg) => reg['usr_m'].toString() == targetUsrM)
            .map((reg) => reg['apl_tec'].toString())
            .toList();

        throw Exception(
          'No se encontró relación entre el Usuario ${usuario['name']} (ID: $targetUsrM) y la App $codigoApp.\n'
          'Permisos encontrados para este usuario: ${permisosUsuario.isEmpty ? "Ninguno" : permisosUsuario.join(", ")}',
        );
      }

      // Si llega aquí, ha encontrado la relación.
      // 🟢 Nota: No verificamos 'off' como pediste.

      // 5. Éxito - Guardar sesión
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('velneo_url', finalUrl);
      await prefs.setString('velneo_api_key', apiKey);
      await prefs.setInt('comercial_id', comercialId);
      await prefs.setString(
        'comercial_nombre',
        entidadEncontrada['nombre'] ?? 'Usuario',
      );

      await db.eliminarContrasenaLocal();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error de Acceso'),
          content: SingleChildScrollView(
            child: Text(e.toString().replaceAll('Exception: ', '')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF032458)),
              const SizedBox(height: 20),
              Text(_statusMessage),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(
                Icons.business_center,
                size: 80,
                color: Color(0xFF032458),
              ),
              const SizedBox(height: 16),
              const Text(
                'TecERP',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF032458),
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _codigoAppController,
                decoration: const InputDecoration(
                  labelText: 'Código App',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _comercialIdController,
                decoration: const InputDecoration(
                  labelText: 'ID Entidad / Comercial',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Servidor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _apiVersionController,
                decoration: const InputDecoration(
                  labelText: 'Versión API',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _iniciarSesion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF032458),
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 32,
                  ),
                ),
                child: const Text(
                  'INICIAR SESIÓN',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
