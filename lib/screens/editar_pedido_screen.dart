import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/buscar_articulo_dialog.dart';
import '../widgets/editar_linea_dialog.dart';
import '../widgets/linea_pedido_widget.dart';

class EditarPedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const EditarPedidoScreen({super.key, required this.pedido});

  @override
  State<EditarPedidoScreen> createState() => _EditarPedidoScreenState();
}

class _EditarPedidoScreenState extends State<EditarPedidoScreen> {
  Map<String, dynamic>? _clienteSeleccionado;
  final _observacionesController = TextEditingController();
  final List<LineaPedidoData> _lineas = [];
  bool _isLoading = true;
  bool _guardando = false;

  // Listas maestras
  List<Map<String, dynamic>> _direccionesCliente = [];
  List<Map<String, dynamic>> _series = [];
  List<Map<String, dynamic>> _formasPago = [];

  // Campos del formulario
  int? _direccionEntregaId;
  int? _serieSeleccionadaId;
  int? _formaPagoSeleccionadaId;
  DateTime? _fechaPedido;
  DateTime? _fechaEntrega;

  // Foto
  String? _fotoBase64;
  bool _fotoModificada = false; // Para saber si hay que subirla/borrarla

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

  // --- CARGA DE DATOS ---
  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;

      // 1. Cargar Maestros (Series, Formas Pago)
      final series = await db.obtenerSeries(tipo: 'V');
      final formasPago = await db.obtenerFormasPago();

      // 2. Cargar Cliente
      final clientes = await db.obtenerClientes();
      final cliente = clientes.firstWhere(
        (c) => c['id'] == widget.pedido['cliente_id'],
        orElse: () => {
          'id': widget.pedido['cliente_id'],
          'nombre': 'Cliente desconocido',
        },
      );

      // 3. Cargar Direcciones del cliente
      final direcciones = await db.obtenerDirecciones(
        ent: widget.pedido['cliente_id'],
      );

      // 4. Cargar Líneas
      final lineasRaw = await db.obtenerLineasPedido(widget.pedido['id']);
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
            dto1: (linea['dto1'] as num?)?.toDouble() ?? 0.0,
            dto2: (linea['dto2'] as num?)?.toDouble() ?? 0.0,
            dto3: (linea['dto3'] as num?)?.toDouble() ?? 0.0,
            tipoIva: tipoIvaDb,
          ),
        );
      }

      // 5. Cargar Foto (Desde API, ya que no se guarda local el base64 completo)
      String? foto;
      try {
        final prefs = await SharedPreferences.getInstance();
        String url = prefs.getString('velneo_url') ?? '';
        String apiKey = prefs.getString('velneo_api_key') ?? '';
        if (url.isNotEmpty) {
          if (!url.startsWith('http')) url = 'https://$url';
          final apiService = VelneoAPIService(url, apiKey);
          foto = await apiService.obtenerFotoPedido(widget.pedido['id']);
        }
      } catch (e) {
        print('Error cargando foto: $e');
      }

      // 6. Asignar valores al estado
      if (mounted) {
        setState(() {
          _series = series;
          _formasPago = formasPago;
          _clienteSeleccionado = cliente;
          _direccionesCliente = direcciones;
          _lineas.addAll(lineasCargadas);
          _observacionesController.text = widget.pedido['observaciones'] ?? '';
          _fotoBase64 = foto;

          // Asignar campos del pedido
          _serieSeleccionadaId = widget.pedido['serie_id'] == 0
              ? null
              : widget.pedido['serie_id'];
          _formaPagoSeleccionadaId = widget.pedido['forma_pago'] == 0
              ? null
              : widget.pedido['forma_pago'];
          _direccionEntregaId = widget.pedido['direccion_entrega_id'] == 0
              ? null
              : widget.pedido['direccion_entrega_id'];

          if (widget.pedido['fecha'] != null) {
            _fechaPedido = DateTime.tryParse(widget.pedido['fecha']);
          }
          if (widget.pedido['fecha_entrega'] != null) {
            _fechaEntrega = DateTime.tryParse(widget.pedido['fecha_entrega']);
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error cargando datos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LÓGICA DE NEGOCIO ---

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => const BuscarClienteDialog(),
    );
    if (cliente != null) {
      setState(() {
        _clienteSeleccionado = cliente;
        _direccionEntregaId = null;
        _direccionesCliente = [];
      });
      // Cargar direcciones del nuevo cliente
      final db = DatabaseHelper.instance;
      final dirs = await db.obtenerDirecciones(ent: cliente['id']);
      setState(() {
        _direccionesCliente = dirs;
        if (dirs.isNotEmpty) _direccionEntregaId = dirs.first['id'];
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
          dto1: 0,
          dto2: 0,
          dto3: 0,
          tipoIva: 'G',
        ),
      );

      if (lineaConPrecio != null) {
        setState(() => _lineas.add(lineaConPrecio));
      }
    }
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
        dto1: lineaActual.dto1,
        dto2: lineaActual.dto2,
        dto3: lineaActual.dto3,
        tipoIva: lineaActual.tipoIva,
      ),
    );

    if (lineaEditada != null) {
      setState(() => _lineas[index] = lineaEditada);
    }
  }

  double _calcularTotal() {
    return _lineas.fold(0, (sum, l) {
      final base = l.cantidad * l.precioNeto;
      return sum + (base * (1 + (l.porcentajeIva / 100)));
    });
  }

  // --- GESTIÓN DE FECHAS ---
  Future<void> _seleccionarFecha(bool esEntrega) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: esEntrega
          ? (_fechaEntrega ?? DateTime.now())
          : (_fechaPedido ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        if (esEntrega) {
          _fechaEntrega = picked;
        } else {
          _fechaPedido = picked;
        }
      });
    }
  }

  // --- GESTIÓN DE FOTO ---
  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (image == null) return;

      final bytes = await File(image.path).readAsBytes();
      final String base64String = base64Encode(bytes);

      setState(() {
        _fotoBase64 = base64String;
        _fotoModificada = true;
      });
    } catch (e) {
      print('Error cámara: $e');
    }
  }

  void _borrarFoto() {
    setState(() {
      _fotoBase64 = null;
      _fotoModificada = true; // Marcar para borrar en servidor
    });
  }

  // --- GUARDAR CAMBIOS ---
  Future<void> _guardarCambios() async {
    if (_guardando) return;

    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
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

      // 1. Preparar Datos
      final pedidoData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'cmr': comercialId,
        'observaciones': _observacionesController.text,
        'direccion_entrega_id': _direccionEntregaId,
        'serie_id': _serieSeleccionadaId,
        'forma_pago': _formaPagoSeleccionadaId,
        'fecha':
            _fechaPedido?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'fecha_entrega': _fechaEntrega?.toIso8601String(),
        'lineas': _lineas.map((linea) {
          return {
            'articulo_id': linea.articulo['id'],
            'cantidad': linea.cantidad,
            'precio': linea.precio,
            'tipo_iva': linea.tipoIva,
            'dto1': linea.dto1,
            'dto2': linea.dto2,
            'dto3': linea.dto3,
            'por_dto': linea.descuento,
          };
        }).toList(),
      };

      // 2. Actualizar en API
      await apiService
          .actualizarPedido(widget.pedido['id'], pedidoData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw Exception('Timeout servidor'),
          );

      // 3. Actualizar Foto si cambió
      if (_fotoModificada) {
        await apiService.actualizarFotoPedido(
          widget.pedido['id'],
          _fotoBase64, // Si es null, la borrará
        );
      }

      // 4. Actualizar BD Local
      final db = DatabaseHelper.instance;
      await db.actualizarPedido(widget.pedido['id'], {
        'cliente_id': _clienteSeleccionado!['id'],
        'observaciones': _observacionesController.text,
        'direccion_entrega_id': _direccionEntregaId,
        'serie_id': _serieSeleccionadaId,
        'forma_pago': _formaPagoSeleccionadaId,
        'fecha': _fechaPedido?.toIso8601String(),
        'fecha_entrega': _fechaEntrega?.toIso8601String(),
        'total': _calcularTotal(),
        'sincronizado': 1,
      });

      // Reinsertar líneas locales
      await db.eliminarLineasPedido(widget.pedido['id']);
      for (var linea in _lineas) {
        await db.insertarLineaPedido({
          'pedido_id': widget.pedido['id'],
          'articulo_id': linea.articulo['id'],
          'cantidad': linea.cantidad,
          'precio': linea.precio,
          'tipo_iva': linea.tipoIva,
          'por_descuento': linea.descuento,
          'dto1': linea.dto1,
          'dto2': linea.dto2,
          'dto3': linea.dto3,
        });
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pedido actualizado correctamente'),
          backgroundColor: Color(0xFF032458),
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
        builder: (_) => AlertDialog(
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
        title: Text('Editar Pedido ${widget.pedido['numero']}'),
        backgroundColor: const Color(0xFF162846),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // CLIENTE
                Card(
                  child: ListTile(
                    title: Text(
                      _clienteSeleccionado?['nombre'] ?? 'Cliente *',
                      style: TextStyle(
                        fontWeight: _clienteSeleccionado != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: _clienteSeleccionado != null
                        ? Text('ID: ${_clienteSeleccionado!['id']}')
                        : null,
                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),

                // DIRECCIÓN DE ENTREGA
                if (_clienteSeleccionado != null &&
                    _direccionesCliente.isNotEmpty)
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
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Dirección Principal'),
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
                        onChanged: (v) =>
                            setState(() => _direccionEntregaId = v),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // FECHAS Y SERIE
                Row(
                  children: [
                    // Fecha Pedido
                    Expanded(
                      child: InkWell(
                        onTap: () => _seleccionarFecha(false),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today, size: 20),
                          ),
                          child: Text(
                            _fechaPedido != null
                                ? '${_fechaPedido!.day}/${_fechaPedido!.month}/${_fechaPedido!.year}'
                                : '-',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Fecha Entrega
                    Expanded(
                      child: InkWell(
                        onTap: () => _seleccionarFecha(true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Entrega',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.local_shipping, size: 20),
                          ),
                          child: Text(
                            _fechaEntrega != null
                                ? '${_fechaEntrega!.day}/${_fechaEntrega!.month}/${_fechaEntrega!.year}'
                                : 'Sin fecha',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // SERIE
                if (_series.isNotEmpty)
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Serie',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _serieSeleccionadaId,
                    items: _series.map((s) {
                      return DropdownMenuItem<int>(
                        value: s['id'],
                        child: Text(
                          s['nombre'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _serieSeleccionadaId = v),
                  ),
                if (_series.isNotEmpty) const SizedBox(height: 16),

                // FORMA DE PAGO
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Forma de Pago',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  initialValue: _formaPagoSeleccionadaId,
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sin especificar'),
                    ),
                    ..._formasPago.map(
                      (f) => DropdownMenuItem<int>(
                        value: f['id'],
                        child: Text(
                          f['nombre'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _formaPagoSeleccionadaId = v),
                ),
                const SizedBox(height: 16),

                // OBSERVACIONES
                TextField(
                  controller: _observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // SECCIÓN FOTO
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.camera_alt, color: Color(0xFF032458)),
                            SizedBox(width: 8),
                            Text(
                              'Fotografía',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_fotoBase64 != null)
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(_fotoBase64!),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                  size: 30,
                                ),
                                onPressed: _borrarFoto,
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _tomarFoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Galería'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _tomarFoto(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Cámara'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ARTÍCULOS
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
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_lineas.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Sin artículos'),
                    ),
                  )
                else
                  ..._lineas.asMap().entries.map((entry) {
                    final index = entry.key;
                    return LineaPedidoWidget(
                      linea: entry.value,
                      onDelete: () => setState(() => _lineas.removeAt(index)),
                      onEdit: () => _editarLinea(index),
                      onUpdate: () => setState(() {}),
                    );
                  }),

                const SizedBox(height: 16),

                // TOTAL
                Card(
                  color: const Color(0xFF032458).withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
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
                  ),
                ),

                const SizedBox(height: 24),

                // BOTÓN GUARDAR
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
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'GUARDAR CAMBIOS',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
