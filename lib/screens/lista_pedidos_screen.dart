import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_pedido_screen.dart';
import 'crear_pedido_screen.dart';

class ListaPedidosScreen extends StatefulWidget {
  const ListaPedidosScreen({super.key});

  @override
  State<ListaPedidosScreen> createState() => ListaPedidosScreenState();
}

class ListaPedidosScreenState extends State<ListaPedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _pedidosFiltrados = [];

  final Map<int, String> _clientesNombres = {};
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
    _searchController.addListener(_filtrarPedidos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> recargarPedidos() => _cargarPedidos();

  Future<void> _cargarPedidos() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final comercialId = prefs.getInt('comercial_id');
      final db = DatabaseHelper.instance;

      var pedidosRaw = await db.obtenerPedidos();
      if (comercialId != null) {
        pedidosRaw = pedidosRaw.where((p) => p['cmr'] == comercialId).toList();
      }

      final clientes = await db.obtenerClientes();
      _clientesNombres.clear();
      for (var c in clientes) {
        _clientesNombres[c['id']] = c['nombre'];
      }

      // 🟢 USAR TOTALES DE VELNEO (ya vienen calculados correctamente)
      final List<Map<String, dynamic>> pedidosCalculados = [];

      for (var p in pedidosRaw) {
        final pMod = Map<String, dynamic>.from(p);

        // Usar los totales de Velneo si existen, si no calcular
        if (p['base_total'] != null &&
            p['iva_total'] != null &&
            p['total'] != null) {
          // ✅ Usar totales de Velneo directamente
          pMod['base_calculada'] = (p['base_total'] as num).toDouble();
          pMod['iva_calculado'] = (p['iva_total'] as num).toDouble();
          pMod['total_calculado'] = (p['total'] as num).toDouble();

          print(
            '✅ Pedido ${p['id']}: Usando totales de Velneo - Base=${p['base_total']}, IVA=${p['iva_total']}, Total=${p['total']}',
          );
        } else {
          // ⚠️ Calcular manualmente si no vienen de Velneo (fallback)
          print(
            '⚠️ Pedido ${p['id']}: Calculando totales manualmente (no vienen de Velneo)',
          );

          final lineas = await db.obtenerLineasPedido(p['id']);
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

            // Aplicar descuentos
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

        pedidosCalculados.add(pMod);
      }

      setState(() {
        _pedidos = pedidosCalculados;
        _pedidosFiltrados = pedidosCalculados;
        _isLoading = false;
      });

      if (_searchController.text.isNotEmpty) _filtrarPedidos();
    } catch (e) {
      print('❌ Error al cargar pedidos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _obtenerNombreCliente(int? id) {
    if (id == null) return 'Cliente desconocido';
    return _clientesNombres[id] ?? 'Cliente no encontrado ($id)';
  }

  void _filtrarPedidos() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _pedidosFiltrados = _pedidos);
      return;
    }
    setState(() {
      _pedidosFiltrados = _pedidos.where((p) {
        final n = (p['numero'] ?? '').toString().toLowerCase();
        final c = _obtenerNombreCliente(p['cliente_id']).toLowerCase();
        return n.contains(query) || c.contains(query);
      }).toList();
    });
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

  Future<void> _sincronizarPendientes() async {
    final pendientes = _pedidos.where((p) => p['sincronizado'] == 0).toList();
    if (pendientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pedidos pendientes')),
      );
      return;
    }

    setState(() => _sincronizando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final key = prefs.getString('velneo_api_key');
      if (url == null) return;

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        key!,
      );
      final db = DatabaseHelper.instance;

      for (var p in pendientes) {
        final lineas = await db.obtenerLineasPedido(p['id']);

        final pedidoMap = {
          'cliente_id': p['cliente_id'],
          'fecha': p['fecha'],
          'observaciones': p['observaciones'],
          'total': p['total_calculado'],
          'cmr': p['cmr'],
          'serie_id': p['serie_id'],
          'direccion_entrega_id': p['direccion_entrega_id'],
          'lineas': lineas
              .map(
                (l) => {
                  'articulo_id': l['articulo_id'],
                  'cantidad': l['cantidad'],
                  'precio': l['precio'],
                  'dto1': l['dto1'],
                  'dto2': l['dto2'],
                  'dto3': l['dto3'],
                  'tipo_iva': l['tipo_iva'],
                },
              )
              .toList(),
        };

        await api.crearPedido(pedidoMap);
        await db.actualizarPedidoSincronizado(p['id'], 1);
      }
      await _cargarPedidos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronización completada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int count = _pedidos.where((p) => p['sincronizado'] == 0).length;

    return Column(
      children: [
        // Barra Superior
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
                    hintText: 'Buscar pedido...',
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
              if (count > 0) ...[
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
                    tooltip: 'Sincronizar $count pendientes',
                  ),
                ),
              ],
            ],
          ),
        ),

        // Lista Limpia
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _pedidosFiltrados.isEmpty
              ? const Center(child: Text('No hay pedidos'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _pedidosFiltrados.length,
                  itemBuilder: (context, index) {
                    final p = _pedidosFiltrados[index];

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
                              builder: (_) => DetallePedidoScreen(pedido: p),
                            ),
                          );
                          _cargarPedidos();
                        },
                        // 🟢 DISEÑO LIMPIO
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            title: Text(
                              p['numero']?.toString().isNotEmpty == true
                                  ? '${p['numero']}'
                                  : 'Borrador #${p['id']}',
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
                                Text(
                                  _formatearFecha(p['fecha']),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(
                              '${(p['total_calculado'] ?? 0.0).toStringAsFixed(2)}€',
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
