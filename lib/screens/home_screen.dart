import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';

// Pantallas principales
import 'catalogo_articulos_screen.dart';
import 'catalogo_clientes_screen.dart';
import 'lista_pedidos_screen.dart';
import 'presupuestos_screen.dart';
import 'leads_screen.dart';
import 'crm_calendario_screen.dart';

// Pantallas de configuración y acceso
import 'configuracion_screen.dart';
import 'login_screen.dart';

// Pantallas de creación (para el botón flotante)
import 'crear_pedido_screen.dart';
import 'crear_cliente_screen.dart';
import 'crear_presupuesto_screen.dart';
import 'crear_visita_screen.dart';
import 'crear_editar_lead_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Índice seleccionado del menú (0: Artículos por defecto)
  int _selectedIndex = 0;
  String _nombreComercial = 'Cargando...';

  // Keys globales para recargar listas tras acciones
  final GlobalKey<CatalogoClientesScreenState> _clientesKey = GlobalKey();
  final GlobalKey<ListaPedidosScreenState> _pedidosKey = GlobalKey();
  // Puedes añadir más keys si necesitas recargar otras pantallas (ej: presupuestos)

  late List<Widget> _screens;
  late List<String> _titles;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();

    // Listener para cierres forzosos por token/conexión
    VelneoAPIService.onCierreForzoso = (mensaje) {
      _mostrarDialogoCierre(mensaje);
    };

    // 🟢 DEFINICIÓN DE PANTALLAS (Orden coincide con Drawer)
    _screens = [
      const CatalogoArticulosScreen(), // 0
      ListaPedidosScreen(key: _pedidosKey), // 1
      CatalogoClientesScreen(key: _clientesKey), // 2
      const PresupuestosScreen(), // 3
      const CRMCalendarioScreen(), // 4
      const LeadsScreen(), // 5
    ];

    _titles = [
      'Catálogo de Artículos',
      'Lista de Pedidos',
      'Cartera de Clientes',
      'Presupuestos',
      'Agenda CRM',
      'Gestión de Leads',
    ];

    // Sincronización automática al iniciar
    /* WidgetsBinding.instance.addPostFrameCallback((_) {
      _sincronizarGlobalEnSegundoPlano();
    });*/
  }

  void _mostrarDialogoCierre(String mensaje) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.signal_wifi_off, color: Colors.red),
                SizedBox(width: 10),
                Text('Sin Conexión'),
              ],
            ),
            content: Text(
              '$mensaje\n\nLa aplicación se cerrará por seguridad.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => SystemNavigator.pop(),
                child: const Text(
                  'CERRAR APLICACIÓN',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombreComercial = prefs.getString('comercial_nombre') ?? 'Comercial';
    });
  }

  // 🟢 GESTIÓN INTELIGENTE DEL BOTÓN FLOTANTE
  void _onFabPressed() async {
    switch (_selectedIndex) {
      case 1: // Pedidos
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearPedidoScreen()),
        );
        if (result == true) _pedidosKey.currentState?.recargarPedidos();
        break;

      case 2: // Clientes
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearClienteScreen()),
        );
        if (result == true) _clientesKey.currentState?.recargarClientes();
        break;

      case 3: // Presupuestos
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearPresupuestoScreen()),
        );
        // Si tuvieras key para presupuestos, aquí recargarías
        break;

      case 4: // Agenda
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearVisitaScreen()),
        );
        break;

      case 5: // Leads
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CrearEditarLeadScreen()),
        );
        break;

      default:
        // Artículos (0) no tiene acción de crear
        break;
    }
  }

  // 🟢 MOTOR DE SINCRONIZACIÓN COMPLETO
  Future<void> _sincronizarGlobalEnSegundoPlano() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final apiKey = prefs.getString('velneo_api_key');
      final comercialId = prefs.getInt('comercial_id');

      if (url == null || apiKey == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⬇️ Sincronizando datos completos...'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF032458),
          ),
        );
      }

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey,
      );
      final db = DatabaseHelper.instance;

      print('🚀 [HOME] Iniciando Sincronización Completa...');

      // 1. Conexión
      if (!await api.probarConexion()) {
        print('⚠️ [HOME] No hay conexión con la API.');
        return;
      }

      // 2. Artículos
      final articulosLista = await api.obtenerArticulos();
      await db.limpiarArticulos();
      const batchSize = 500;
      for (var i = 0; i < articulosLista.length; i += batchSize) {
        final end = (i + batchSize < articulosLista.length)
            ? i + batchSize
            : articulosLista.length;
        await db.insertarArticulosLote(
          articulosLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      // 2.1 Familias
      await db.limpiarFamilias();
      await db.insertarFamiliasLote(
        (await api.obtenerFamilias()).cast<Map<String, dynamic>>(),
      );

      // 3. Clientes y Comerciales
      final resultadoClientes = await api.obtenerClientes();
      final clientesList = resultadoClientes['clientes'] as List;
      final comercialesList = resultadoClientes['comerciales'] as List;

      await db.limpiarClientes();
      for (var i = 0; i < clientesList.length; i += batchSize) {
        final end = (i + batchSize < clientesList.length)
            ? i + batchSize
            : clientesList.length;
        await db.insertarClientesLote(
          clientesList.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesList.cast<Map<String, dynamic>>(),
      );

      // 3.1 Contactos
      final contactos = await api.obtenerContactos();
      await db.insertarContactosLote(contactos);

      // 4. Series y Formas de Pago
      await db.limpiarSeries();
      await db.insertarSeriesLote(
        (await api.obtenerSeries()).cast<Map<String, dynamic>>(),
      );
      await db.insertarFormasPagoLote(
        (await api.obtenerFormasPago()).cast<Map<String, dynamic>>(),
      );

      // 5. Direcciones
      await db.limpiarDirecciones();
      await db.insertarDireccionesLote(
        (await api.obtenerDirecciones()).cast<Map<String, dynamic>>(),
      );

      // 6. CRM Maestros
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        (await api.obtenerTiposVisita()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarProvincias();
      await db.insertarProvinciasLote(
        (await api.obtenerProvincias()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarZonasTecnicas();
      await db.insertarZonasTecnicasLote(
        (await api.obtenerZonasTecnicas()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarPoblaciones();
      await db.insertarPoblacionesLote(
        (await api.obtenerPoblaciones()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarCampanas();
      await db.insertarCampanasLote(
        (await api.obtenerCampanas()).cast<Map<String, dynamic>>(),
      );

      // 7. Transaccional (Leads, Agenda, Pedidos, Presupuestos)
      await db.limpiarLeads();
      await db.insertarLeadsLote(
        (await api.obtenerLeads()).cast<Map<String, dynamic>>(),
      );

      await db.limpiarAgenda();
      await db.insertarAgendasLote(
        (await api.obtenerAgenda(comercialId)).cast<Map<String, dynamic>>(),
      );

      await db.limpiarPedidos();
      await db.insertarPedidosLote(
        (await api.obtenerPedidos()).cast<Map<String, dynamic>>(),
      );
      await db.insertarLineasPedidoLote(
        (await api.obtenerTodasLineasPedido()).cast<Map<String, dynamic>>(),
      );

      await db.limpiarPresupuestos();
      await db.insertarPresupuestosLote(
        (await api.obtenerPresupuestos()).cast<Map<String, dynamic>>(),
      );
      await db.insertarLineasPresupuestoLote(
        (await api.obtenerTodasLineasPresupuesto())
            .cast<Map<String, dynamic>>(),
      );

      // 8. Tarifas
      await db.limpiarTarifasCliente();
      await db.insertarTarifasClienteLote(
        (await api.obtenerTarifasCliente()).cast<Map<String, dynamic>>(),
      );
      await db.limpiarTarifasArticulo();
      await db.insertarTarifasArticuloLote(
        (await api.obtenerTarifasArticulo()).cast<Map<String, dynamic>>(),
      );

      // 9. Movimientos
      await db.limpiarMovimientos();
      final movimientos = await api.obtenerMovimientos();
      for (var i = 0; i < movimientos.length; i += batchSize) {
        final end = (i + batchSize < movimientos.length)
            ? i + batchSize
            : movimientos.length;
        await db.insertarMovimientosLote(
          movimientos.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      // 10. IVA
      final configIva = await api.obtenerConfiguracionIVA();
      if (configIva.isNotEmpty) {
        await prefs.setDouble('iva_general', configIva['iva_general']!);
        await prefs.setDouble('iva_reducido', configIva['iva_reducido']!);
        await prefs.setDouble(
          'iva_superreducido',
          configIva['iva_superreducido']!,
        );
        await prefs.setDouble('iva_exento', configIva['iva_exento']!);
      }

      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      print('✅ [HOME] Sincronización completa finalizada.');

      if (mounted) {
        _pedidosKey.currentState?.recargarPedidos();
        _clientesKey.currentState?.recargarClientes();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos actualizados'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("⚠️ Error en sync fondo: $e");
    }
  }

  void _cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _seleccionarOpcionMenu(int index) {
    Navigator.pop(context); // Cerrar drawer
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar botón flotante excepto en Artículos (0)
    final bool showFab = _selectedIndex != 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
            ),
          ),
        ],
      ),

      // Cuerpo
      body: IndexedStack(index: _selectedIndex, children: _screens),

      // Botón Flotante
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: _onFabPressed,
              backgroundColor: const Color(0xFF032458),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,

      // Menú Lateral (Drawer)
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF032458)),
              accountName: Text(
                _nombreComercial,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              accountEmail: const Text("CRM Velneo v7"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Color(0xFF032458)),
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(0, Icons.inventory_2, 'Artículos'),
                  _buildDrawerItem(1, Icons.shopping_cart, 'Pedidos'),
                  _buildDrawerItem(2, Icons.people, 'Clientes'),
                  const Divider(),
                  _buildDrawerItem(3, Icons.request_quote, 'Presupuestos'),
                  _buildDrawerItem(4, Icons.calendar_month, 'Agenda'),
                  _buildDrawerItem(5, Icons.filter_alt, 'Leads'),
                ],
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text('Configuración'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConfiguracionScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: Colors.red),
              ),
              onTap: _cerrarSesion,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String title) {
    final bool isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFF032458) : Colors.grey[700],
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? const Color(0xFF032458) : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFF032458).withOpacity(0.1),
      onTap: () => _seleccionarOpcionMenu(index),
    );
  }
}
