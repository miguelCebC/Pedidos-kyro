import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_presupuesto_screen.dart';

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
    // 🟢 Sincronización automática
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarFondo());
    _searchController.addListener(_filtrarPresupuestos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> recargarPresupuestos() => _cargarDatos();

  Future<void> _sincronizarFondo() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final apiKey = prefs.getString('velneo_api_key');
      if (url == null || apiKey == null) return;

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey,
      );

      final db = DatabaseHelper.instance;

      // 1. Descargar Presupuestos (Cabeceras)
      final presupuestosServer = await api.obtenerPresupuestos();

      if (presupuestosServer.isNotEmpty) {
        await db.insertarPresupuestosLote(
          presupuestosServer.cast<Map<String, dynamic>>(),
        );
      }

      // 2. Descargar Líneas
      final lineasServer = await api.obtenerTodasLineasPresupuesto();

      if (lineasServer.isNotEmpty) {
        // 🟢 FIX CRÍTICO: No borrar todas las líneas de golpe.
        // Solo borramos las líneas de los presupuestos que realmente hemos descargado (cabeceras).
        // Esto evita que si la API pagina o filtra, borremos líneas de otros presupuestos.

        if (presupuestosServer.isNotEmpty) {
          // Extraemos los IDs de los presupuestos descargados
          final idsDescargados = presupuestosServer
              .map((p) => p['id'])
              .join(',');

          if (idsDescargados.isNotEmpty) {
            final database = await db.database;
            // Borramos solo las líneas asociadas a los presupuestos que acabamos de traer
            await database.rawDelete(
              'DELETE FROM lineas_presupuesto WHERE presupuesto_id IN ($idsDescargados)',
            );
          }
        }

        // Insertamos las nuevas líneas
        await db.insertarLineasPresupuestoLote(
          lineasServer.cast<Map<String, dynamic>>(),
        );
      }

      if (mounted) {
        _cargarDatos();
        print("✅ Presupuestos sincronizados correctamente (Fix aplicado)");
      }
    } catch (e) {
      print("⚠️ Error en sync fondo presupuestos: $e");
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _cargarDatos() async {
    // Si no es sync silenciosa, mostramos carga
    if (!_sincronizando) setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');
      final db = DatabaseHelper.instance;

      var presupuestosRaw = await db.obtenerPresupuestos();
      if (comercialId != null) {
        presupuestosRaw = presupuestosRaw
            .where((p) => p['comercial_id'] == comercialId)
            .toList();
      }

      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var cliente in clientes) {
        _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
      }

      final List<Map<String, dynamic>> presupuestosCalculados = [];

      for (var p in presupuestosRaw) {
        final pMod = Map<String, dynamic>.from(p);

        double totalServer = (p['total'] as num?)?.toDouble() ?? 0.0;
        double baseServer = (p['base_total'] as num?)?.toDouble() ?? 0.0;
        int sincronizado = (p['sincronizado'] as int?) ?? 0;

        if (sincronizado == 1 || (totalServer != 0 || baseServer != 0)) {
          pMod['base_calculada'] = baseServer;
          pMod['iva_calculado'] = (p['iva_total'] as num?)?.toDouble() ?? 0.0;
          pMod['total_calculado'] = totalServer;
        } else {
          final lineas = await db.obtenerLineasPresupuesto(p['id']);
          double baseTotal = 0.0;
          double ivaTotal = 0.0;

          for (var l in lineas) {
            final double cant = (l['cantidad'] as num?)?.toDouble() ?? 0.0;
            final double prec = (l['precio'] as num?)?.toDouble() ?? 0.0;
            final double iva = (l['por_iva'] as num?)?.toDouble() ?? 0.0;
            double dto = (l['por_descuento'] as num?)?.toDouble() ?? 0.0;
            double d1 = (l['dto1'] as num?)?.toDouble() ?? 0.0;
            double d2 = (l['dto2'] as num?)?.toDouble() ?? 0.0;
            double d3 = (l['dto3'] as num?)?.toDouble() ?? 0.0;

            double precioNeto = prec;
            if (dto > 0) precioNeto *= (1 - dto / 100);
            if (d1 > 0) precioNeto *= (1 - d1 / 100);
            if (d2 > 0) precioNeto *= (1 - d2 / 100);
            if (d3 > 0) precioNeto *= (1 - d3 / 100);

            double baseLinea = precioNeto * cant;
            double ivaLinea = baseLinea * (iva / 100);

            baseTotal += baseLinea;
            ivaTotal += ivaLinea;
          }

          pMod['base_calculada'] = baseTotal;
          pMod['iva_calculado'] = ivaTotal;
          pMod['total_calculado'] = baseTotal + ivaTotal;
        }

        presupuestosCalculados.add(pMod);
      }

      presupuestosCalculados.sort((a, b) {
        try {
          final fechaA = DateTime.parse(a['fecha'] ?? '');
          final fechaB = DateTime.parse(b['fecha'] ?? '');
          return fechaB.compareTo(fechaA);
        } catch (e) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _presupuestos = presupuestosCalculados;
          _presupuestosFiltrados = presupuestosCalculados;
          _isLoading = false;
        });
        if (_searchController.text.isNotEmpty) _filtrarPresupuestos();
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
      final url = prefs.getString('velneo_url');
      final apiKey = prefs.getString('velneo_api_key');
      if (url == null) return;

      final apiService = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey!,
      );
      final db = DatabaseHelper.instance;

      int exitosos = 0;
      for (var p in pendientes) {
        try {
          final lineas = await db.obtenerLineasPresupuesto(p['id']);
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
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _presupuestosFiltrados.isEmpty
              ? const Center(child: Text('No hay presupuestos'))
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
                            title: Text(
                              numero,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
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
