import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';

class EditarPresupuestoScreen extends StatefulWidget {
  final Map<String, dynamic> presupuesto;

  const EditarPresupuestoScreen({super.key, required this.presupuesto});

  @override
  State<EditarPresupuestoScreen> createState() =>
      _EditarPresupuestoScreenState();
}

class _EditarPresupuestoScreenState extends State<EditarPresupuestoScreen> {
  Map<String, dynamic>? _clienteSeleccionado;
  final _observacionesController = TextEditingController();
  final List<LineaPedidoData> _lineas = [];

  // Variables para Fecha y Dirección
  DateTime? _fechaPresupuesto;
  int? _direccionEntregaId;
  List<Map<String, dynamic>> _direccionesCliente = [];

  // Variables para Series
  List<Map<String, dynamic>> _series = [];
  int? _serieSeleccionadaId;

  bool _isLoading = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  // DEBUG JSON
  Future<void> _mostrarDebugJson() async {
    if (_clienteSeleccionado == null) return;

    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');

    final cabeceraJson = {
      'emp': '1',
      'emp_div': '1',
      'clt': _clienteSeleccionado!['id'],
      'cmr': comercialId,
      'obs': _observacionesController.text,
      'est': widget.presupuesto['estado'] ?? 'P',
      'ser': _serieSeleccionadaId,
      'fch': _fechaPresupuesto?.toIso8601String(),
      'dir_env': _direccionEntregaId,
    };

    final lineasJson = _lineas.map((l) {
      return {
        'vta_pre': widget.presupuesto['id'],
        'emp': '1',
        'art': l.articulo['id'],
        'can': l.cantidad,
        'pre': l.precio,
        'reg_iva_vta': l.tipoIva,
      };
    }).toList();

    final encoder = const JsonEncoder.withIndent('  ');
    final headerString = encoder.convert(cabeceraJson);
    final linesString = encoder.convert(lineasJson);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔍 DEBUG: JSON Presupuesto'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CABECERA:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  width: double.infinity,
                  child: Text(
                    headerString,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'LÍNEAS:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  width: double.infinity,
                  child: Text(
                    linesString,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
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

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;

      // 1. Cargar Series (Ventas)
      final series = await db.obtenerSeries(tipo: 'V');

      // 2. Cargar cliente
      final clientes = await db.obtenerClientes();
      final cliente = clientes.firstWhere(
        (c) => c['id'] == widget.presupuesto['cliente_id'],
        orElse: () => {
          'id': widget.presupuesto['cliente_id'],
          'nombre': 'Cliente no encontrado',
          'direccion': '',
        },
      );

      // 3. Cargar Direcciones del Cliente
      final direcciones = await db.obtenerDirecciones(
        ent: widget.presupuesto['cliente_id'],
      );

      // 4. Cargar líneas
      final lineasRaw = await db.obtenerLineasPresupuesto(
        widget.presupuesto['id'],
      );
      final articulos = await db.obtenerArticulos();

      final lineasCargadas = <LineaPedidoData>[];
      for (var linea in lineasRaw) {
        final articulo = articulos.firstWhere(
          (a) => a['id'] == linea['articulo_id'],
          orElse: () => {
            'id': linea['articulo_id'],
            'nombre': 'Artículo no encontrado',
            'codigo': 'N/A',
            'precio': 0.0,
          },
        );

        String tipoIvaDb = linea['tipo_iva']?.toString() ?? 'G';

        lineasCargadas.add(
          LineaPedidoData(
            articulo: articulo,
            cantidad: (linea['cantidad'] as num).toDouble(),
            precio: (linea['precio'] as num).toDouble(),
            descuento: (linea['por_descuento'] as num?)?.toDouble() ?? 0.0,
            tipoIva: tipoIvaDb,
          ),
        );
      }

      // Validar Serie seleccionada
      int? serieIdValido = widget.presupuesto['serie_id'];
      if (series.isNotEmpty) {
        final existeSerie = series.any((s) => s['id'] == serieIdValido);
        if (!existeSerie) {
          serieIdValido = series[0]['id'];
        }
      } else {
        serieIdValido = null;
      }

      setState(() {
        _series = series;
        _serieSeleccionadaId = serieIdValido;

        _clienteSeleccionado = cliente;
        _observacionesController.text =
            widget.presupuesto['observaciones'] ?? '';
        _lineas.addAll(lineasCargadas);

        // Asignar Fecha
        if (widget.presupuesto['fecha'] != null) {
          _fechaPresupuesto = DateTime.tryParse(widget.presupuesto['fecha']);
        }

        // Asignar Direcciones y selección
        _direccionesCliente = direcciones;
        _direccionEntregaId = widget.presupuesto['direccion_entrega_id'];

        if (_direccionEntregaId == 0) _direccionEntregaId = null;

        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando datos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarClienteDialog(),
    );

    if (cliente != null) {
      final db = DatabaseHelper.instance;
      final direcciones = await db.obtenerDirecciones(ent: cliente['id']);

      setState(() {
        _clienteSeleccionado = cliente;
        _direccionesCliente = direcciones;
        _direccionEntregaId = null;
        if (_direccionesCliente.isNotEmpty) {
          _direccionEntregaId = _direccionesCliente.first['id'];
        }
      });
    }
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaPresupuesto ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        _fechaPresupuesto = picked;
      });
    }
  }

  Future<void> _agregarLinea() async {
    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero selecciona un cliente')),
      );
      return;
    }

    final articulo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarArticuloDialog(),
    );

    if (articulo != null) {
      final db = DatabaseHelper.instance;
      final precioInfo = await db.obtenerPrecioYDescuento(
        _clienteSeleccionado!['id'],
        articulo['id'],
        articulo['precio'] ?? 0.0,
      );

      if (!mounted) return;

      final lineaConPrecio = await showDialog<LineaPedidoData>(
        context: context,
        builder: (dialogContext) => EditarLineaDialog(
          articulo: articulo,
          cantidad: 1,
          precio: precioInfo['precio']!,
          descuento: precioInfo['descuento']!,
          tipoIva: 'G',
        ),
      );

      if (lineaConPrecio != null) {
        setState(() {
          _lineas.add(lineaConPrecio);
        });
      }
    }
  }

  void _eliminarLinea(int index) {
    setState(() {
      _lineas.removeAt(index);
    });
  }

  Future<void> _editarLinea(int index) async {
    final lineaActual = _lineas[index];
    final lineaEditada = await showDialog<LineaPedidoData>(
      context: context,
      builder: (dialogContext) => EditarLineaDialog(
        articulo: lineaActual.articulo,
        cantidad: lineaActual.cantidad,
        precio: lineaActual.precio,
        descuento: lineaActual.descuento,
        tipoIva: lineaActual.tipoIva,
      ),
    );

    if (lineaEditada != null) {
      setState(() {
        _lineas[index] = lineaEditada;
      });
    }
  }

  double _calcularBaseImponible() {
    return _lineas.fold(0, (total, linea) {
      final subtotal = linea.cantidad * linea.precio;
      final descuento = subtotal * (linea.descuento / 100);
      return total + (subtotal - descuento);
    });
  }

  double _calcularTotalIva() {
    return _lineas.fold(0, (totalIva, linea) {
      final subtotal = linea.cantidad * linea.precio;
      final descuento = subtotal * (linea.descuento / 100);
      final baseLinea = subtotal - descuento;
      final ivaLinea = baseLinea * (linea.porcentajeIva / 100);
      return totalIva + ivaLinea;
    });
  }

  double _calcularTotal() {
    return _calcularBaseImponible() + _calcularTotalIva();
  }

  Future<void> _guardarCambios() async {
    if (_guardando) return;

    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }

    // Permitir guardar sin serie si la lista está vacía, pero avisar
    if (_serieSeleccionadaId == null && _series.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una serie')));
      return;
    }

    if (_lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un artículo')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';
      final comercialId = prefs.getInt('comercial_id');

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);

      final presupuestoData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'comercial_id': comercialId,
        'observaciones': _observacionesController.text,
        'estado': widget.presupuesto['estado'] ?? 'P',
        'serie_id': _serieSeleccionadaId,
        'fecha': _fechaPresupuesto?.toIso8601String(),
        'direccion_entrega_id': _direccionEntregaId,
        'lineas': _lineas
            .map(
              (linea) => {
                'articulo_id': linea.articulo['id'],
                'cantidad': linea.cantidad,
                'precio': linea.precio,
                'tipo_iva': linea.tipoIva,
              },
            )
            .toList(),
      };

      final resultado = await apiService
          .actualizarPresupuesto(widget.presupuesto['id'], presupuestoData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () =>
                throw Exception('Timeout: El servidor tardó demasiado'),
          );

      final totalFinal = resultado['server_total'] ?? _calcularTotal();
      final baseFinal = resultado['server_base'] ?? _calcularBaseImponible();
      final ivaFinal = resultado['server_iva'] ?? _calcularTotalIva();

      final db = DatabaseHelper.instance;
      await db.actualizarPresupuesto(widget.presupuesto['id'], {
        'cliente_id': _clienteSeleccionado!['id'],
        'observaciones': _observacionesController.text,
        'serie_id': _serieSeleccionadaId,
        'fecha': _fechaPresupuesto?.toIso8601String(),
        'direccion_entrega_id': _direccionEntregaId,
        'total': totalFinal,
        'base_total': baseFinal,
        'iva_total': ivaFinal,
        'sincronizado': 1,
      });

      await db.eliminarLineasPresupuesto(widget.presupuesto['id']);

      for (var linea in _lineas) {
        await db.insertarLineaPresupuesto({
          'presupuesto_id': widget.presupuesto['id'],
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
          'por_descuento': linea.descuento,
          'por_iva': linea.porcentajeIva,
          'tipo_iva': linea.tipoIva,
        });
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Presupuesto actualizado correctamente'),
          backgroundColor: Color(0xFF032458),
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceAll('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Presupuesto #${widget.presupuesto['id']}'),
        backgroundColor: const Color(0xFF162846),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.orange),
            onPressed: _mostrarDebugJson,
            tooltip: 'Ver JSON a enviar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Cliente
                Card(
                  child: ListTile(
                    title: Text(
                      _clienteSeleccionado?['nombre'] ??
                          'Seleccionar cliente *',
                      style: TextStyle(
                        fontWeight: _clienteSeleccionado != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),

                    leading: const Icon(Icons.business),
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),

                // FILA DE FECHA Y SERIE
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _seleccionarFecha,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today, size: 20),
                          ),
                          child: Text(
                            _fechaPresupuesto != null
                                ? '${_fechaPresupuesto!.day}/${_fechaPresupuesto!.month}/${_fechaPresupuesto!.year}'
                                : '-',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      // 🟢 MOSTRAR SIEMPRE EL DROPBOX (Aunque esté vacío)
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Serie',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 15,
                          ),
                        ),
                        // Si está vacío, value debe ser null para no romper
                        initialValue: _series.isNotEmpty
                            ? _serieSeleccionadaId
                            : null,
                        // Si está vacío, mostramos mensaje o deshabilitamos
                        items: _series.isEmpty
                            ? []
                            : _series.map((serie) {
                                return DropdownMenuItem<int>(
                                  value: serie['id'],
                                  child: Text(
                                    serie['nombre'],
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                        // Si no hay series, el onChanged null lo deshabilita
                        onChanged: _series.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  _serieSeleccionadaId = value;
                                });
                              },
                        // Texto cuando está deshabilitado
                        disabledHint: const Text(
                          "Sin series (Sincronizar)",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // DIRECCIÓN DE ENTREGA
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Dirección de Entrega',
                        border: InputBorder.none,
                        icon: Icon(Icons.location_on, color: Colors.grey),
                      ),
                      initialValue: _direccionEntregaId,
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(
                            _clienteSeleccionado?['direccion'] ??
                                'Dirección Fiscal (Principal)',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ..._direccionesCliente.map((dir) {
                          return DropdownMenuItem<int?>(
                            value: dir['id'],
                            child: Text(
                              dir['direccion'],
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }),
                      ],
                      onChanged: (v) => setState(() => _direccionEntregaId = v),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Observaciones
                TextField(
                  controller: _observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                // Título y botón agregar artículo
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Artículos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _agregarLinea,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF032458),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Lista de artículos
                if (_lineas.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: const Center(
                      child: Text(
                        'No hay artículos',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._lineas.asMap().entries.map((entry) {
                    final index = entry.key;
                    final linea = entry.value;
                    final subtotal = linea.cantidad * linea.precio;
                    final descuento = subtotal * (linea.descuento / 100);
                    final baseLinea = subtotal - descuento;
                    final ivaLinea = baseLinea * (linea.porcentajeIva / 100);
                    final totalLinea = baseLinea + ivaLinea;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF032458).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: Color(0xFF032458),
                          ),
                        ),
                        title: Text(
                          linea.articulo['nombre'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${linea.articulo['codigo']} - ${linea.cantidad} x ${linea.precio.toStringAsFixed(2)}€'
                          '${linea.descuento > 0 ? ' (-${linea.descuento}%)' : ''}'
                          '\nIVA: ${linea.tipoIva} (${linea.porcentajeIva}%)',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${totalLinea.toStringAsFixed(2)}€',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF032458),
                                  ),
                                ),
                                if (linea.descuento > 0 ||
                                    linea.porcentajeIva > 0)
                                  Text(
                                    'Base: ${baseLinea.toStringAsFixed(2)}€',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'editar',
                                  child: Text('Editar'),
                                ),
                                const PopupMenuItem(
                                  value: 'eliminar',
                                  child: Text(
                                    'Eliminar',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'editar') _editarLinea(index);
                                if (value == 'eliminar') _eliminarLinea(index);
                              },
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                // Card de totales
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  color: const Color(0xFF032458).withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Base Imponible:'),
                            Text(
                              '${_calcularBaseImponible().toStringAsFixed(2)}€',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('IVA:'),
                            Text(
                              '${_calcularTotalIva().toStringAsFixed(2)}€',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL:',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${_calcularTotal().toStringAsFixed(2)}€',
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

                // Botón guardar
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardarCambios,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF032458),
                      foregroundColor: Colors.white,
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Guardar Cambios',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
