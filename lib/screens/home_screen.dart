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
  int _selectedIndex = 0;
  String _nombreComercial = 'Cargando...';

  // 🟢 Variable estado CRM
  bool _crmActivo = false;

  final GlobalKey<CatalogoClientesScreenState> _clientesKey = GlobalKey();
  final GlobalKey<ListaPedidosScreenState> _pedidosKey = GlobalKey();

  // 🟢 Estructura dinámica del menú
  List<Map<String, dynamic>> _menuOptions = [];

  @override
  void initState() {
    super.initState();
    _cargarConfiguracionUsuario();

    // Listener para cierres forzosos por token/conexión
    VelneoAPIService.onCierreForzoso = (mensaje) {
      _mostrarDialogoCierre(mensaje);
    };
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

  Future<void> _cargarConfiguracionUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nombreComercial = prefs.getString('comercial_nombre') ?? 'Comercial';
        _crmActivo = prefs.getBool('crm_activo') ?? false;
        _construirMenu();
      });
    }
  }

  // 🟢 Construye el menú dinámicamente según la configuración
  void _construirMenu() {
    _menuOptions = [
      {
        'title': 'Artículos',
        'icon': Icons.inventory_2,
        'screen': const CatalogoArticulosScreen(),
        'fab_icon': null,
        'fab_action': null,
      },
      {
        'title': 'Pedidos',
        'icon': Icons.shopping_cart,
        'screen': ListaPedidosScreen(key: _pedidosKey),
        'fab_icon': Icons.add,
        'fab_action': (BuildContext ctx) async {
          final result = await Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const CrearPedidoScreen()),
          );
          if (result == true) _pedidosKey.currentState?.recargarPedidos();
        },
      },
      {
        'title': 'Clientes',
        'icon': Icons.people,
        'screen': CatalogoClientesScreen(key: _clientesKey),
        'fab_icon': Icons.add,
        'fab_action': (BuildContext ctx) async {
          final result = await Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const CrearClienteScreen()),
          );
          if (result == true) _clientesKey.currentState?.recargarClientes();
        },
      },
    ];

    if (_crmActivo) {
      _menuOptions.addAll([
        {
          'title': 'Presupuestos',
          'icon': Icons.request_quote,
          'screen': const PresupuestosScreen(),
          'fab_icon': Icons.add,
          'fab_action': (BuildContext ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const CrearPresupuestoScreen()),
            );
            // Si necesitas recargar, usa GlobalKey como en pedidos
          },
        },
        {
          'title': 'Agenda CRM',
          'icon': Icons.calendar_month,
          'screen': const CRMCalendarioScreen(),
          'fab_icon': Icons.add,
          'fab_action': (BuildContext ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const CrearVisitaScreen()),
            );
          },
        },
        {
          'title': 'Leads',
          'icon': Icons.filter_alt,
          'screen': const LeadsScreen(),
          'fab_icon': Icons.add,
          'fab_action': (BuildContext ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const CrearEditarLeadScreen()),
            );
          },
        },
      ]);
    }

    // Corregir índice si quedó fuera de rango tras desactivar CRM
    if (_selectedIndex >= _menuOptions.length) {
      _selectedIndex = 0;
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

  // 🟢 FAB dinámico
  void _onFabPressed() {
    final action =
        _menuOptions[_selectedIndex]['fab_action'] as Function(BuildContext)?;
    if (action != null) {
      action(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si la lista no está inicializada, mostrar carga
    if (_menuOptions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currentOption = _menuOptions[_selectedIndex];
    final bool showFab = currentOption['fab_action'] != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentOption['title']),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              // 🟢 Esperar retorno para recargar configuración (si cambió CRM activo)
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
              );
              _cargarConfiguracionUsuario();
            },
          ),
        ],
      ),

      // Cuerpo dinámico
      body: currentOption['screen'] as Widget,

      // Botón Flotante dinámico
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: _onFabPressed,
              backgroundColor: const Color(0xFF032458),
              child: Icon(
                currentOption['fab_icon'] as IconData? ?? Icons.add,
                color: Colors.white,
              ),
            )
          : null,

      // Menú Lateral (Drawer) dinámico
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
              accountEmail: const Text("TecERP"),
            ),

            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _menuOptions.length,
                itemBuilder: (context, index) {
                  final opt = _menuOptions[index];
                  // 🟢 DIVISOR ANTES DE LA SECCIÓN CRM (Si existe)
                  // Detectamos cambio de "bloque" asumiendo que los primeros 3 son fijos
                  if (index == 3 && _crmActivo) {
                    return Column(
                      children: [
                        const Divider(),
                        _buildDrawerItem(index, opt['icon'], opt['title']),
                      ],
                    );
                  }
                  return _buildDrawerItem(index, opt['icon'], opt['title']);
                },
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text('Configuración'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConfiguracionScreen(),
                  ),
                );
                _cargarConfiguracionUsuario();
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
