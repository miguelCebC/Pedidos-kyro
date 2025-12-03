import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

int? _comercialSeleccionadoId;
String _comercialSeleccionadoNombre = 'Sin asignar';
List<Map<String, dynamic>> _comerciales = [];

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _diasVisitaController = TextEditingController();

  // 🟢 Variable para el módulo CRM
  bool _crmActivo = false;

  bool _isSyncing = false;
  String _syncStatus = '';
  double _syncProgress = 0.0;
  String _syncDetalle = '';
  final List<String> _logMessages = [];

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().substring(11, 19)} - $message',
      );
      if (_logMessages.length > 20) {
        _logMessages.removeAt(0);
      }
    });
    print(message);
  }

  Future<void> _cargarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;
    final comerciales = await db.obtenerComerciales();

    setState(() {
      _urlController.text =
          prefs.getString('velneo_url') ??
          'tecerp.nunsys.com:4331/TORRAL/TecERPv7_dat_dat/v1';
      _apiKeyController.text = prefs.getString('velneo_api_key') ?? '123456';
      _diasVisitaController.text = (prefs.getInt('proxima_visita_dias') ?? 60)
          .toString();

      // 🟢 Cargar estado del CRM
      _crmActivo = prefs.getBool('crm_activo') ?? false;

      _comercialSeleccionadoId = prefs.getInt('comercial_id');
      _comercialSeleccionadoNombre =
          prefs.getString('comercial_nombre') ?? 'Sin asignar';
      _comerciales = comerciales;
    });
  }

  Future<void> _guardarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('velneo_url', _urlController.text);
    await prefs.setString('velneo_api_key', _apiKeyController.text);
    final int dias = int.tryParse(_diasVisitaController.text) ?? 60;
    await prefs.setInt('proxima_visita_dias', dias);

    // 🟢 Guardar estado del CRM
    await prefs.setBool('crm_activo', _crmActivo);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada'),
        backgroundColor: Color(0xFF032458),
      ),
    );
  }

  Future<void> _seleccionarComercial() async {
    if (_comerciales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero sincroniza los datos para ver comerciales'),
        ),
      );
      return;
    }

    final seleccionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Seleccionar Comercial'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _comerciales.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  title: const Text('Sin asignar'),
                  leading: const Icon(Icons.clear),
                  onTap: () => Navigator.pop(dialogContext, {
                    'id': null,
                    'nombre': 'Sin asignar',
                  }),
                );
              }
              final comercial = _comerciales[index - 1];
              return ListTile(
                title: Text(comercial['nombre']),
                subtitle: Text('ID: ${comercial['id']}'),
                onTap: () => Navigator.pop(dialogContext, comercial),
              );
            },
          ),
        ),
      ),
    );

    if (seleccionado != null) {
      final prefs = await SharedPreferences.getInstance();
      if (seleccionado['id'] == null) {
        await prefs.remove('comercial_id');
        await prefs.remove('comercial_nombre');
      } else {
        await prefs.setInt('comercial_id', seleccionado['id']);
        await prefs.setString('comercial_nombre', seleccionado['nombre']);
      }

      setState(() {
        _comercialSeleccionadoId = seleccionado['id'];
        _comercialSeleccionadoNombre = seleccionado['nombre'];
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Comercial asignado: ${seleccionado['nombre']}'),
          backgroundColor: const Color(0xFF032458),
        ),
      );
    }
  }

  Future<void> _sincronizarDatos() async {
    if (_urlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos primero')),
      );
      return;
    }

    await _guardarConfiguracion();

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Iniciando...';
      _syncProgress = 0.0;
      _syncDetalle = '';
      _logMessages.clear();
    });

    try {
      String url = _urlController.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final apiService = VelneoAPIService(
        url,
        _apiKeyController.text,
        onLog: _addLog,
      );
      final db = DatabaseHelper.instance;

      // --- 1. Conexión ---
      setState(() {
        _syncStatus = 'Verificando conexión...';
        _syncProgress = 0.05;
      });

      final conexionOk = await apiService.probarConexion();
      if (!conexionOk) throw Exception('No se puede conectar a la API');

      // --- 2. Artículos ---
      setState(() {
        _syncStatus = 'Artículos...';
        _syncProgress = 0.10;
        _syncDetalle = 'Descargando catálogo de productos...';
      });
      final articulosLista = await apiService.obtenerArticulos();

      await db.limpiarArticulos();
      const batchSize = 500;

      for (var i = 0; i < articulosLista.length; i += batchSize) {
        final end = (i + batchSize < articulosLista.length)
            ? i + batchSize
            : articulosLista.length;

        await db.insertarArticulosLote(
          articulosLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );

        setState(() {
          _syncDetalle =
              'Guardando artículos ${i + 1}-$end de ${articulosLista.length}...';
        });
      }

      // --- 2.1 Familias ---
      setState(() {
        _syncStatus = 'Familias...';
        _syncProgress = 0.25;
        _syncDetalle = 'Descargando familias de artículos...';
      });
      final familiasLista = await apiService.obtenerFamilias();
      await db.limpiarFamilias();
      await db.insertarFamiliasLote(familiasLista.cast<Map<String, dynamic>>());

      // --- 3. Clientes y Comerciales ---
      setState(() {
        _syncStatus = 'Clientes...';
        _syncProgress = 0.30;
        _syncDetalle = 'Descargando clientes y comerciales...';
      });
      final resultadoClientes = await apiService.obtenerClientes();
      final clientesLista = resultadoClientes['clientes'] as List;
      final comercialesLista = resultadoClientes['comerciales'] as List;

      await db.limpiarClientes();
      for (var i = 0; i < clientesLista.length; i += batchSize) {
        final end = (i + batchSize < clientesLista.length)
            ? i + batchSize
            : clientesLista.length;
        await db.insertarClientesLote(
          clientesLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
      }

      await db.limpiarComerciales();
      await db.insertarComercialesLote(
        comercialesLista.cast<Map<String, dynamic>>(),
      );

      final contactos = await apiService.obtenerContactos();
      await db.insertarContactosLote(contactos);

      final comercialesDb = await db.obtenerComerciales();
      setState(() => _comerciales = comercialesDb);

      // --- 4. Series ---
      setState(() {
        _syncStatus = 'Series...';
        _syncProgress = 0.35;
        _syncDetalle = 'Descargando series de facturación...';
      });

      final seriesLista = await apiService.obtenerSeries();
      await db.limpiarSeries();
      await db.insertarSeriesLote(seriesLista.cast<Map<String, dynamic>>());

      setState(() {
        _syncDetalle = 'Descargando formas de pago...';
      });
      final formasPago = await apiService.obtenerFormasPago();
      await db.insertarFormasPagoLote(formasPago.cast<Map<String, dynamic>>());

      // --- 5. Direcciones ---
      setState(() {
        _syncStatus = 'Direcciones...';
        _syncProgress = 0.45;
        _syncDetalle = 'Descargando direcciones de clientes...';
      });
      final direcciones = await apiService.obtenerDirecciones();
      await db.limpiarDirecciones();
      await db.insertarDireccionesLote(
        direcciones.cast<Map<String, dynamic>>(),
      );

      // --- 6. Datos Maestros CRM (Solo si está activo el módulo) ---
      // Aunque no esté activo en local, es mejor sincronizarlos por si acaso se activa luego
      setState(() {
        _syncStatus = 'Datos CRM...';
        _syncProgress = 0.50;
        _syncDetalle = 'Descargando configuración CRM...';
      });

      final tiposVisita = await apiService.obtenerTiposVisita();
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        tiposVisita.cast<Map<String, dynamic>>(),
      );

      final provincias = await apiService.obtenerProvincias();
      await db.limpiarProvincias();
      await db.insertarProvinciasLote(provincias.cast<Map<String, dynamic>>());

      final zonas = await apiService.obtenerZonasTecnicas();
      await db.limpiarZonasTecnicas();
      await db.insertarZonasTecnicasLote(zonas.cast<Map<String, dynamic>>());

      final poblaciones = await apiService.obtenerPoblaciones();
      await db.limpiarPoblaciones();
      await db.insertarPoblacionesLote(
        poblaciones.cast<Map<String, dynamic>>(),
      );

      final campanas = await apiService.obtenerCampanas();
      await db.limpiarCampanas();
      await db.insertarCampanasLote(campanas.cast<Map<String, dynamic>>());

      // --- 7. Datos Transaccionales ---
      setState(() {
        _syncStatus = 'Datos Usuario...';
        _syncProgress = 0.70;
        _syncDetalle = 'Descargando leads y agenda...';
      });

      // Leads
      final leads = await apiService.obtenerLeads();
      await db.limpiarLeads();
      await db.insertarLeadsLote(leads.cast<Map<String, dynamic>>());

      // Agenda
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');

      final agenda = await apiService.obtenerAgenda(comercialId);
      await db.limpiarAgenda();
      await db.insertarAgendasLote(agenda.cast<Map<String, dynamic>>());

      // Pedidos
      setState(() {
        _syncDetalle = 'Descargando pedidos...';
      });
      final pedidos = await apiService.obtenerPedidos();
      await db.limpiarPedidos();
      await db.insertarPedidosLote(pedidos.cast<Map<String, dynamic>>());

      final lineasPedido = await apiService.obtenerTodasLineasPedido();
      await db.insertarLineasPedidoLote(
        lineasPedido.cast<Map<String, dynamic>>(),
      );

      // Presupuestos
      setState(() {
        _syncProgress = 0.85;
        _syncDetalle = 'Descargando presupuestos...';
      });
      final presupuestos = await apiService.obtenerPresupuestos();
      await db.limpiarPresupuestos();
      await db.insertarPresupuestosLote(
        presupuestos.cast<Map<String, dynamic>>(),
      );

      final lineasPresu = await apiService.obtenerTodasLineasPresupuesto();
      await db.insertarLineasPresupuestoLote(
        lineasPresu.cast<Map<String, dynamic>>(),
      );

      // --- 8. Tarifas ---
      setState(() {
        _syncProgress = 0.90;
        _syncDetalle = 'Descargando tarifas...';
      });

      final tarifasCli = await apiService.obtenerTarifasCliente();
      await db.limpiarTarifasCliente();
      await db.insertarTarifasClienteLote(
        tarifasCli.cast<Map<String, dynamic>>(),
      );

      final tarifasArt = await apiService.obtenerTarifasArticulo();
      await db.limpiarTarifasArticulo();
      await db.insertarTarifasArticuloLote(
        tarifasArt.cast<Map<String, dynamic>>(),
      );

      setState(() {
        _syncStatus = 'Movimientos...';
        _syncProgress = 0.92;
        _syncDetalle = 'Descargando histórico de movimientos...';
      });

      final movimientosLista = await apiService.obtenerMovimientos();
      await db.limpiarMovimientos();

      const batchSizeMov = 500;
      for (var i = 0; i < movimientosLista.length; i += batchSizeMov) {
        final end = (i + batchSizeMov < movimientosLista.length)
            ? i + batchSizeMov
            : movimientosLista.length;
        await db.insertarMovimientosLote(
          movimientosLista.sublist(i, end).cast<Map<String, dynamic>>(),
        );
        setState(() {
          _syncDetalle =
              'Guardando movimientos ${i + 1}-$end de ${movimientosLista.length}...';
        });
      }

      // --- 9. IVA ---
      setState(() {
        _syncStatus = 'Configurando IVA...';
        _syncProgress = 0.95;
        _syncDetalle = 'Descargando configuración de impuestos...';
      });

      final configIva = await apiService.obtenerConfiguracionIVA();

      if (configIva.isNotEmpty) {
        await prefs.setDouble('iva_general', configIva['iva_general']!);
        await prefs.setDouble('iva_reducido', configIva['iva_reducido']!);
        await prefs.setDouble(
          'iva_superreducido',
          configIva['iva_superreducido']!,
        );
        await prefs.setDouble('iva_exento', configIva['iva_exento']!);
      }

      // --- 10. Finalizar ---
      await prefs.setInt(
        'ultima_sincronizacion',
        DateTime.now().millisecondsSinceEpoch,
      );

      setState(() {
        _syncProgress = 1.0;
        _syncStatus = 'Completado';
        _syncDetalle = '¡Sincronización exitosa!';
        _isSyncing = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Sincronización completada con éxito'),
          backgroundColor: Color(0xFF032458),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncStatus = 'Error';
        _syncProgress = 0.0;
        _syncDetalle = 'Error: ${e.toString()}';
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Error de Sincronización'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ha ocurrido un error durante la sincronización:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(e.toString()),
                const SizedBox(height: 16),
                const Text(
                  'Revisa los logs para más detalles.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
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

  Future<void> _limpiarDatos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Eliminar todos los datos locales?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF44336),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await DatabaseHelper.instance.limpiarBaseDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos eliminados'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Conexión API',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL del Servidor',
              hintText: 'servidor:puerto/ruta/v1',
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
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _diasVisitaController,
            decoration: const InputDecoration(
              labelText: 'Días por defecto próxima visita',
              hintText: 'Ej: 30',
              border: OutlineInputBorder(),
              suffixText: 'días',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _guardarConfiguracion,
            icon: const Icon(Icons.save),
            label: const Text('Guardar Configuración'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF162846),
            ),
          ),
          const SizedBox(height: 24),

          // 🟢 SECCIÓN MÓDULOS ACTIVOS
          const Text(
            'Módulos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFCAD3E2)),
            ),
            child: SwitchListTile(
              title: const Text(
                'Módulo CRM',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Activa Presupuestos, Agenda y Gestión de Leads',
              ),
              value: _crmActivo,
              activeThumbColor: const Color(0xFF032458),
              onChanged: (bool value) {
                setState(() => _crmActivo = value);
                // Guardado automático al cambiar para mejor UX, o esperar al botón guardar
                _guardarConfiguracion();
              },
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Comercial Asignado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: Text(_comercialSeleccionadoNombre),
              subtitle: _comercialSeleccionadoId != null
                  ? Text('ID: $_comercialSeleccionadoId')
                  : const Text('No hay comercial asignado'),
              trailing: const Icon(Icons.person),
              onTap: _seleccionarComercial,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Este comercial se asignará automáticamente a todos los pedidos nuevos',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          if (_isSyncing) ...[
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      _syncStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _syncProgress,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF032458),
                      ),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_syncProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                    if (_syncDetalle.isNotEmpty) ...[const SizedBox(height: 8)],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else
            ElevatedButton.icon(
              onPressed: _sincronizarDatos,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar Datos'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
        ],
      ),
    );
  }
}
