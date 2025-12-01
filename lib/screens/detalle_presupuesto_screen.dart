import 'package:flutter/material.dart';
import '../database_helper.dart';
import 'editar_presupuesto_screen.dart';

class DetallePresupuestoScreen extends StatefulWidget {
  final Map<String, dynamic> presupuesto;

  const DetallePresupuestoScreen({super.key, required this.presupuesto});

  @override
  State<DetallePresupuestoScreen> createState() =>
      _DetallePresupuestoScreenState();
}

class _DetallePresupuestoScreenState extends State<DetallePresupuestoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 🟢 Usamos una variable local para poder refrescar los datos de cabecera
  late Map<String, dynamic> _presupuesto;

  List<Map<String, dynamic>> _lineas = [];
  Map<String, dynamic>? _cliente;

  String _nombreComercial = 'No asignado';
  String _nombreSerie = 'General';
  String _nombreFormaPago = 'No especificada';
  String _direccionEntrega = 'Principal del cliente';

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _presupuesto = widget.presupuesto; // Inicializar con los datos recibidos
    _tabController = TabController(length: 3, vsync: this);
    _cargarDetalle();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 🟢 CÁLCULO DE TOTALES (PRIORIDAD SERVIDOR)
  Map<String, double> _calcularResumen() {
    // 1. Intentar leer los totales que vienen de la API (guardados en BD)
    int sincronizado = (_presupuesto['sincronizado'] as int?) ?? 0;

    // Mapeo desde la BD local (que se llenó con tot_pre, bas_tot, iva_tot)
    double totalDb = (_presupuesto['total'] as num?)?.toDouble() ?? 0.0;
    double baseDb = (_presupuesto['base_total'] as num?)?.toDouble() ?? 0.0;
    double ivaDb = (_presupuesto['iva_total'] as num?)?.toDouble() ?? 0.0;

    // Si está sincronizado o si los valores son válidos (distintos de 0), USAMOS LOS DEL SERVIDOR
    if (sincronizado == 1 || (totalDb != 0 || baseDb != 0)) {
      return {'base': baseDb, 'iva': ivaDb, 'total': totalDb};
    }

    // 2. Si es un borrador local nuevo (sin datos de servidor), calculamos sumando líneas
    double baseImponible = 0.0;
    double totalIva = 0.0;

    for (var l in _lineas) {
      double precio = (l['precio'] as num?)?.toDouble() ?? 0.0;
      double cantidad = (l['cantidad'] as num?)?.toDouble() ?? 0.0;
      double porIva = (l['por_iva'] as num?)?.toDouble() ?? 0.0;

      // Descuentos en cascada
      double dto = (l['por_descuento'] as num?)?.toDouble() ?? 0.0;
      double dto1 = (l['dto1'] as num?)?.toDouble() ?? 0.0;
      double dto2 = (l['dto2'] as num?)?.toDouble() ?? 0.0;
      double dto3 = (l['dto3'] as num?)?.toDouble() ?? 0.0;

      double precioNeto = precio;
      if (dto > 0) precioNeto *= (1 - dto / 100);
      if (dto1 > 0) precioNeto *= (1 - dto1 / 100);
      if (dto2 > 0) precioNeto *= (1 - dto2 / 100);
      if (dto3 > 0) precioNeto *= (1 - dto3 / 100);

      double baseLinea = precioNeto * cantidad;
      double ivaLinea = baseLinea * (porIva / 100);

      baseImponible += baseLinea;
      totalIva += ivaLinea;
    }

    return {
      'base': baseImponible,
      'iva': totalIva,
      'total': baseImponible + totalIva,
    };
  }

  Future<void> _cargarDetalle() async {
    final db = DatabaseHelper.instance;

    // 🟢 1. Refrescar Cabecera desde BD (importante para traer los totales actualizados)
    try {
      final presupuestos = await db.obtenerPresupuestos();
      final fresco = presupuestos.firstWhere(
        (p) => p['id'] == widget.presupuesto['id'],
        orElse: () => widget.presupuesto,
      );
      if (mounted) {
        setState(() => _presupuesto = fresco);
      }
    } catch (e) {
      print('Error refrescando cabecera: $e');
    }

    // 2. Cargar Líneas
    final lineasRaw = await db.obtenerLineasPresupuesto(_presupuesto['id']);
    final articulos = await db.obtenerArticulos();

    final lineasConArticulo = <Map<String, dynamic>>[];
    for (var linea in lineasRaw) {
      final articulo = articulos.firstWhere(
        (a) => a['id'] == linea['articulo_id'],
        orElse: () => {
          'id': linea['articulo_id'],
          'nombre': 'Artículo no encontrado',
          'codigo': '---',
        },
      );

      lineasConArticulo.add({
        ...linea,
        'articulo_nombre': articulo['nombre'],
        'articulo_codigo': articulo['codigo'],
      });
    }

    // 3. Cargar Cliente
    final clientes = await db.obtenerClientes();
    final cliente = clientes.firstWhere(
      (c) => c['id'] == _presupuesto['cliente_id'],
      orElse: () => {
        'id': _presupuesto['cliente_id'],
        'nombre': 'Cliente desconocido',
        'direccion': 'Sin dirección',
      },
    );

    // 4. Cargar Datos Auxiliares
    String dirNombre = cliente['direccion'] ?? 'Principal';
    if (_presupuesto['direccion_entrega_id'] != null &&
        _presupuesto['direccion_entrega_id'] != 0) {
      dirNombre = await db.obtenerDireccionPorId(
        _presupuesto['direccion_entrega_id'],
      );
    }

    String nomCmr = 'No asignado';
    if (_presupuesto['comercial_id'] != null &&
        _presupuesto['comercial_id'] != 0) {
      final cmr = await db.obtenerComercialPorId(_presupuesto['comercial_id']);
      if (cmr != null) nomCmr = cmr['nombre'];
    }

    String nomSerie = 'General';
    if (_presupuesto['serie_id'] != null && _presupuesto['serie_id'] != 0) {
      nomSerie = await db.obtenerNombreSerie(_presupuesto['serie_id']);
    }

    String nomFpg = 'No especificada';
    if (_presupuesto['forma_pago'] != null && _presupuesto['forma_pago'] != 0) {
      nomFpg = await db.obtenerNombreFormaPago(_presupuesto['forma_pago']);
    }

    if (mounted) {
      setState(() {
        _lineas = lineasConArticulo;
        _cliente = cliente;
        _nombreComercial = nomCmr;
        _nombreSerie = nomSerie;
        _nombreFormaPago = nomFpg;
        _direccionEntrega = dirNombre;
        _isLoading = false;
      });
    }
  }

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(fechaStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (e) {
      return fechaStr;
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

  @override
  Widget build(BuildContext context) {
    final resumen = _calcularResumen();
    final numeroPresupuesto =
        _presupuesto['numero']?.toString().isNotEmpty == true
        ? _presupuesto['numero']
        : 'Borrador #${_presupuesto['id']}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Presupuesto $numeroPresupuesto'),
        backgroundColor: const Color(0xFF162846),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      EditarPresupuestoScreen(presupuesto: _presupuesto),
                ),
              );
              if (resultado == true) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Presupuesto actualizado.'),
                    backgroundColor: Color(0xFF032458),
                  ),
                );
                // Recargar datos (incluyendo cabecera actualizada)
                setState(() => _isLoading = true);
                _cargarDetalle();
              }
            },
            tooltip: 'Editar presupuesto',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'DATOS'),
            Tab(text: 'DETALLE'),
            Tab(text: 'OBSERV.'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTabCabecera(resumen),
                _buildTabLineas(),
                _buildTabObservaciones(),
              ],
            ),
    );
  }

  Widget _buildTabCabecera(Map<String, double> resumen) {
    final estado = _getNombreEstado(_presupuesto['estado']);
    final colorEstado = _getColorEstado(_presupuesto['estado']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Tarjeta de Estado
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorEstado.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorEstado),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colorEstado),
              const SizedBox(width: 8),
              Text(
                'Estado: $estado',
                style: TextStyle(
                  color: colorEstado,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Tarjeta de Información
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow('Cliente', _cliente?['nombre'] ?? ''),
                _buildInfoRow('Fecha', _formatearFecha(_presupuesto['fecha'])),
                if (_presupuesto['fecha_validez'] != null)
                  _buildInfoRow(
                    'Válido hasta',
                    _formatearFecha(_presupuesto['fecha_validez']),
                  ),
                _buildInfoRow('Serie', _nombreSerie),
                _buildInfoRow('Forma Pago', _nombreFormaPago),
                _buildInfoRow('Comercial', _nombreComercial),
                _buildInfoRow('Dirección', _direccionEntrega),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Sincronizado: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Icon(
                      _presupuesto['sincronizado'] == 1
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: _presupuesto['sincronizado'] == 1
                          ? const Color(0xFF032458)
                          : const Color(0xFFF44336),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Tarjeta de Totales
        Card(
          color: const Color(0xFF032458).withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Base Imponible:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${resumen['base']!.toStringAsFixed(2)} €',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total IVA:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${resumen['iva']!.toStringAsFixed(2)} €',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL:',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                    Text(
                      '${resumen['total']!.toStringAsFixed(2)} €',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF032458),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabLineas() {
    if (_lineas.isEmpty) {
      return const Center(child: Text("No hay líneas en este presupuesto"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _lineas.length,
      itemBuilder: (ctx, i) {
        final linea = _lineas[i];
        final cantidad = (linea['cantidad'] as num).toDouble();
        final precio = (linea['precio'] as num).toDouble();
        final dto = (linea['por_descuento'] as num?)?.toDouble() ?? 0.0;

        // Cálculo rápido para visualización en línea
        double subtotal = cantidad * precio;
        if (dto > 0) subtotal *= (1 - dto / 100);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linea['articulo_nombre'] ?? 'Artículo',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Código: ${linea['articulo_codigo'] ?? ''}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cant: $cantidad'),
                    Text('Precio: ${precio.toStringAsFixed(2)}€'),
                  ],
                ),
                if (dto > 0)
                  Text(
                    'Dto: ${dto.toStringAsFixed(2)}%',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Subtotal: ${subtotal.toStringAsFixed(2)}€',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF032458),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabObservaciones() {
    final observaciones = _presupuesto['observaciones']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Observaciones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              Text(
                observaciones.isNotEmpty
                    ? observaciones
                    : 'Sin observaciones registradas.',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
