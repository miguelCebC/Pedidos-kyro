import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_presupuesto_screen.dart';
import 'crear_presupuesto_screen.dart';

class PresupuestosScreen extends StatefulWidget {
  const PresupuestosScreen({super.key});

  @override
  State<PresupuestosScreen> createState() => PresupuestosScreenState();
}

class PresupuestosScreenState extends State<PresupuestosScreen> {
  List<Map<String, dynamic>> _presupuestos = [];
  List<Map<String, dynamic>> _presupuestosFiltrados = [];
  final Map<int, String> _clientesNombres = {};
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _searchController.addListener(_filtrarPresupuestos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Método público para recargar desde el HomeScreen si es necesario
  Future<void> recargarPresupuestos() => _cargarDatos();

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');
      final db = DatabaseHelper.instance;

      // 1. Cargar Presupuestos Raw (Cabeceras)
      var presupuestosRaw = await db.obtenerPresupuestos();

      // Filtrar por comercial si está configurado
      if (comercialId != null) {
        presupuestosRaw = presupuestosRaw
            .where((p) => p['comercial_id'] == comercialId)
            .toList();
      }

      // 2. Cargar Clientes para mapear nombres
      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var cliente in clientes) {
        _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
      }

      // 🟢 3. RECALCULAR TOTALES CON IVA Y DESCUENTOS - VERSIÓN CORREGIDA
      final List<Map<String, dynamic>> presupuestosCalculados = [];

      for (var p in presupuestosRaw) {
        final lineas = await db.obtenerLineasPresupuesto(p['id']);
        double baseTotal = 0.0;
        double ivaTotal = 0.0;

        for (var l in lineas) {
          final double cant = (l['cantidad'] as num?)?.toDouble() ?? 0.0;
          final double prec = (l['precio'] as num?)?.toDouble() ?? 0.0;
          final double iva = (l['por_iva'] as num?)?.toDouble() ?? 0.0;

          // Descuentos en cascada
          double dto = (l['por_descuento'] as num?)?.toDouble() ?? 0.0;
          double d1 = (l['dto1'] as num?)?.toDouble() ?? 0.0;
          double d2 = (l['dto2'] as num?)?.toDouble() ?? 0.0;
          double d3 = (l['dto3'] as num?)?.toDouble() ?? 0.0;

          // 🔥 DEBUG: Imprimir valores para verificar
          print(
            'Línea: cant=$cant, prec=$prec, iva=$iva%, dto=$dto%, d1=$d1%, d2=$d2%, d3=$d3%',
          );

          // Cálculo Neto con descuentos en cascada
          double precioNeto = prec;
          if (dto > 0) precioNeto *= (1 - dto / 100);
          if (d1 > 0) precioNeto *= (1 - d1 / 100);
          if (d2 > 0) precioNeto *= (1 - d2 / 100);
          if (d3 > 0) precioNeto *= (1 - d3 / 100);

          print('  → Precio neto después descuentos: $precioNeto');

          // Base imponible de la línea (sin IVA)
          double baseLinea = precioNeto * cant;

          // IVA de la línea
          double ivaLinea = baseLinea * (iva / 100);

          print('  → Base línea: $baseLinea, IVA línea: $ivaLinea');

          baseTotal += baseLinea;
          ivaTotal += ivaLinea;
        }

        print(
          '📊 Presupuesto ${p['id']}: Base=$baseTotal, IVA=$ivaTotal, Total=${baseTotal + ivaTotal}',
        );

        // Crear una copia modificable del presupuesto con los nuevos totales
        final pMod = Map<String, dynamic>.from(p);
        pMod['base_calculada'] = baseTotal;
        pMod['iva_calculado'] = ivaTotal;
        pMod['total_calculado'] = baseTotal + ivaTotal;
        presupuestosCalculados.add(pMod);
      }

      // Ordenar por fecha descendente
      presupuestosCalculados.sort((a, b) {
        try {
          final fechaA = DateTime.parse(a['fecha'] ?? '');
          final fechaB = DateTime.parse(b['fecha'] ?? '');
          return fechaB.compareTo(fechaA);
        } catch (e) {
          return 0;
        }
      });

      setState(() {
        _presupuestos = presupuestosCalculados;
        _presupuestosFiltrados = presupuestosCalculados;
        _isLoading = false;
      });

      if (_searchController.text.isNotEmpty) {
        _filtrarPresupuestos();
      }
    } catch (e) {
      print('Error al cargar presupuestos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filtrarPresupuestos() {
    final query = _searchController.text.toLowerCase();

    if (query.isEmpty) {
      setState(() => _presupuestosFiltrados = _presupuestos);
      return;
    }

    setState(() {
      _presupuestosFiltrados = _presupuestos.where((presupuesto) {
        final numero = (presupuesto['numero'] ?? '').toString().toLowerCase();
        final clienteNombre = _obtenerNombreCliente(
          presupuesto['cliente_id'],
        ).toLowerCase();
        final observaciones = (presupuesto['observaciones'] ?? '')
            .toString()
            .toLowerCase();

        return numero.contains(query) ||
            clienteNombre.contains(query) ||
            observaciones.contains(query);
      }).toList();
    });
  }

  String _obtenerNombreCliente(int? clienteId) {
    if (clienteId == null) return 'Cliente desconocido';
    return _clientesNombres[clienteId] ?? 'Cliente no encontrado ($clienteId)';
  }

  String _formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '-';
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (e) {
      return fecha;
    }
  }

  String _getNombreEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'A':
        return 'Aceptado';
      case 'P':
        return 'Pendiente';
      case 'R':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  Color _getColorEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'A':
        return Colors.green;
      case 'P':
        return Colors.orange;
      case 'R':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _sincronizarPendientes() async {
    final pendientes = _presupuestos
        .where((p) => p['sincronizado'] == 0)
        .toList();

    if (pendientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay presupuestos pendientes')),
      );
      return;
    }

    setState(() => _sincronizando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isEmpty || apiKey.isEmpty) return;
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      int exitosos = 0;

      for (var p in pendientes) {
        try {
          final lineas = await db.obtenerLineasPresupuesto(p['id']);

          // Usamos el total calculado para enviarlo también si la API lo requiere,
          // aunque idealmente la API debería recalcularlo.
          final double totalEnvio = p['total_calculado'] ?? 0.0;

          final presupuestoData = {
            'cliente_id': p['cliente_id'],
            'comercial_id': p['comercial_id'],
            'serie_id': p['serie_id'],
            'fecha': p['fecha'],
            'observaciones': p['observaciones'],
            'estado': p['estado'],
            'total': totalEnvio,
            'lineas': lineas
                .map(
                  (l) => {
                    'articulo_id': l['articulo_id'],
                    'cantidad': l['cantidad'],
                    'precio': l['precio'],
                    'por_dto': l['por_descuento'],
                    'dto1': l['dto1'],
                    'dto2': l['dto2'],
                    'dto3': l['dto3'],
                    'reg_iva_vta': l['tipo_iva'],
                  },
                )
                .toList(),
          };

          await apiService.crearPresupuesto(presupuestoData);
          await db.actualizarPresupuestoSincronizado(p['id'], 1);
          exitosos++;
        } catch (e) {
          print('Error sincronizando presupuesto ${p['id']}: $e');
        }
      }

      await _cargarDatos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sincronización completada: $exitosos enviados'),
            backgroundColor: const Color(0xFF032458),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int countPendientes = _presupuestos
        .where((p) => p['sincronizado'] == 0)
        .length;

    return Column(
      children: [
        // 1. Barra de Búsqueda y Sincronización
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar presupuesto...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              if (countPendientes > 0) ...[
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF032458),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: _sincronizando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_upload, color: Colors.white),
                    onPressed: _sincronizando ? null : _sincronizarPendientes,
                    tooltip: 'Sincronizar $countPendientes pendientes',
                  ),
                ),
              ],
            ],
          ),
        ),

        // 2. Lista de Presupuestos
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _presupuestosFiltrados.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.request_quote_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No hay presupuestos',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _presupuestosFiltrados.length,
                  itemBuilder: (context, index) {
                    final p = _presupuestosFiltrados[index];
                    final numero = p['numero']?.toString().isNotEmpty == true
                        ? '${p['numero']}'
                        : 'Borrador #${p['id']}';
                    final estado = _getNombreEstado(p['estado']);
                    final colorEstado = _getColorEstado(p['estado']);

                    // Usamos el total calculado
                    final double totalMostrar = p['total_calculado'] ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DetallePresupuestoScreen(presupuesto: p),
                            ),
                          );
                          _cargarDatos();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            // Título con el número
                            title: Text(
                              numero,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            // Subtítulo con Cliente, Fecha y Estado
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  _obtenerNombreCliente(p['cliente_id']),
                                  style: TextStyle(color: Colors.grey[700]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      _formatearFecha(p['fecha']),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Pequeño indicador de estado
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorEstado.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        estado,
                                        style: TextStyle(
                                          color: colorEstado,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Total Calculado (con IVA) a la derecha
                            trailing: Text(
                              '${totalMostrar.toStringAsFixed(2)}€',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF032458),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
