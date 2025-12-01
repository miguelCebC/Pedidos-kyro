import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'editar_pedido_screen.dart';

class DetallePedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const DetallePedidoScreen({super.key, required this.pedido});

  @override
  State<DetallePedidoScreen> createState() => _DetallePedidoScreenState();
}

class _DetallePedidoScreenState extends State<DetallePedidoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 🟢 Copia local para refrescar
  late Map<String, dynamic> _pedido;

  List<LineaDetalle> _lineas = [];
  Map<String, dynamic>? _cliente;

  String _nombreComercial = 'Cargando...';
  String _nombreSerie = 'Cargando...';
  String _nombreFormaPago = 'Cargando...';
  String _direccionEntrega = 'Cargando...';

  bool _isConfirmedKyro = false;
  bool _isConfirming = false;
  bool _isLoading = true;

  String? _fotoBase64;
  bool _cargandoFoto = false;
  bool _subiendoFoto = false;

  @override
  void initState() {
    super.initState();
    _pedido = widget.pedido; // Inicializamos copia local
    _tabController = TabController(length: 4, vsync: this);

    final conKyrVal = _pedido['con_kyr'];
    if (conKyrVal == 1 || conKyrVal == true || conKyrVal.toString() == 'true') {
      _isConfirmedKyro = true;
    } else {
      _isConfirmedKyro = false;
    }

    _cargarDetalle();
    _cargarFotoRemota();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 🟢 CÁLCULO DE TOTALES (PRIORIDAD SERVIDOR)
  Map<String, double> _calcularResumen() {
    // 1. Intentar leer los totales que vienen de la API (guardados en BD)
    int sincronizado = (_pedido['sincronizado'] as int?) ?? 0;

    // Mapeo desde la BD local (que se llenó con tot_ped, bas_tot, iva_tot)
    double totalDb = (_pedido['total'] as num?)?.toDouble() ?? 0.0;
    double baseDb = (_pedido['base_total'] as num?)?.toDouble() ?? 0.0;
    double ivaDb = (_pedido['iva_total'] as num?)?.toDouble() ?? 0.0;

    // Si está sincronizado o tiene datos válidos del servidor
    if (sincronizado == 1 || (totalDb != 0 || baseDb != 0)) {
      return {'base': baseDb, 'iva': ivaDb, 'total': totalDb};
    }

    // 2. Cálculo local fallback (solo para pedidos locales no sincronizados)
    double baseImponible = 0.0;
    double totalIva = 0.0;

    for (var l in _lineas) {
      double precioNeto = l.precio;

      if (l.porDescuento > 0) precioNeto *= (1 - l.porDescuento / 100);
      if (l.dto1 > 0) precioNeto *= (1 - l.dto1 / 100);
      if (l.dto2 > 0) precioNeto *= (1 - l.dto2 / 100);
      if (l.dto3 > 0) precioNeto *= (1 - l.dto3 / 100);

      double baseLinea = precioNeto * l.cantidad;
      double ivaLinea = baseLinea * (l.porIva / 100);

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

    // 🟢 1. Refrescar Cabecera desde BD (para tener totales actualizados tras editar)
    try {
      final pedidos = await db.obtenerPedidos();
      final fresco = pedidos.firstWhere(
        (p) => p['id'] == widget.pedido['id'],
        orElse: () => widget.pedido,
      );
      if (mounted) {
        setState(() => _pedido = fresco);
      }
    } catch (e) {
      print('Error refrescando pedido: $e');
    }

    final lineasRaw = await db.obtenerLineasPedido(_pedido['id']);
    final articulos = await db.obtenerArticulos();

    final lineasConArticulo = <LineaDetalle>[];
    for (var linea in lineasRaw) {
      final articulo = articulos.firstWhere(
        (a) => a['id'] == linea['articulo_id'],
        orElse: () => {'nombre': 'Desconocido', 'codigo': '---'},
      );

      lineasConArticulo.add(
        LineaDetalle(
          articuloNombre: articulo['nombre'],
          articuloCodigo: articulo['codigo'],
          cantidad: (linea['cantidad'] as num?)?.toDouble() ?? 0.0,
          precio: (linea['precio'] as num?)?.toDouble() ?? 0.0,
          porDescuento: (linea['por_descuento'] as num?)?.toDouble() ?? 0.0,
          porIva: (linea['por_iva'] as num?)?.toDouble() ?? 0.0,
          tipoIva: linea['tipo_iva']?.toString() ?? 'G',
          dto1: (linea['dto1'] as num?)?.toDouble() ?? 0.0,
          dto2: (linea['dto2'] as num?)?.toDouble() ?? 0.0,
          dto3: (linea['dto3'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }

    final clientes = await db.obtenerClientes();
    final cliente = clientes.firstWhere(
      (c) => c['id'] == _pedido['cliente_id'],
      orElse: () => {'id': _pedido['cliente_id'], 'nombre': 'Desconocido'},
    );

    String dirNombre = 'Principal del cliente';
    if (_pedido['direccion_entrega_id'] != null &&
        _pedido['direccion_entrega_id'] != 0) {
      dirNombre = await db.obtenerDireccionPorId(
        _pedido['direccion_entrega_id'],
      );
    } else {
      dirNombre = cliente['direccion'] ?? 'Principal';
    }

    String nomCmr = 'Sin asignar';
    if (_pedido['cmr'] != null && _pedido['cmr'] != 0) {
      final cmr = await db.obtenerComercialPorId(_pedido['cmr']);
      if (cmr != null) nomCmr = cmr['nombre'];
    }

    String nomSerie = 'General';
    if (_pedido['serie_id'] != null && _pedido['serie_id'] != 0) {
      nomSerie = await db.obtenerNombreSerie(_pedido['serie_id']);
    }

    String nomFpg = 'No especificada';
    if (_pedido['forma_pago'] != null && _pedido['forma_pago'] != 0) {
      nomFpg = await db.obtenerNombreFormaPago(_pedido['forma_pago']);
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

      setState(() => _subiendoFoto = true);
      final bytes = await File(image.path).readAsBytes();
      final String base64String = base64Encode(bytes);
      await _subirFotoAPI(base64String);
    } catch (e) {
      setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _subirFotoAPI(String? base64String) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      String apiKey = prefs.getString('velneo_api_key') ?? '';
      if (!url.startsWith('http')) url = 'https://$url';

      final apiService = VelneoAPIService(url, apiKey);
      final success = await apiService.actualizarFotoPedido(
        _pedido['id'],
        base64String,
      );

      if (success) {
        setState(() {
          _fotoBase64 = base64String;
          _subiendoFoto = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Foto actualizada')));
      }
    } catch (e) {
      setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _cargarFotoRemota() async {
    setState(() => _cargandoFoto = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      String apiKey = prefs.getString('velneo_api_key') ?? '';
      if (!url.startsWith('http')) url = 'https://$url';
      final apiService = VelneoAPIService(url, apiKey);
      final foto = await apiService.obtenerFotoPedido(_pedido['id']);
      if (mounted) {
        setState(() {
          _fotoBase64 = foto;
          _cargandoFoto = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargandoFoto = false);
    }
  }

  Future<void> _confirmarPedido() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Confirmar pedido? No se podrá editar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _isConfirming = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        String url = prefs.getString('velneo_url') ?? '';
        String apiKey = prefs.getString('velneo_api_key') ?? '';
        if (!url.startsWith('http')) url = 'https://$url';
        final api = VelneoAPIService(url, apiKey);
        await api.actualizarPedido(_pedido['id'], {'con_kyr': true});
        await DatabaseHelper.instance.actualizarPedido(_pedido['id'], {
          'con_kyr': 1,
        });
        setState(() {
          _isConfirmedKyro = true;
          _isConfirming = false;
        });
      } catch (e) {
        setState(() => _isConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumen = _calcularResumen();

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido ${_pedido['numero'] ?? ''}'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'DATOS'),
            Tab(text: 'DETALLE'),
            Tab(text: 'OBSERV.'),
            Tab(text: 'FOTO'),
          ],
        ),
        actions: [
          if (!_isConfirmedKyro)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarPedidoScreen(pedido: _pedido),
                  ),
                );
                if (res == true) {
                  setState(() => _isLoading = true);
                  _cargarDetalle();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTabCabecera(resumen),
                _buildTabLineas(),
                const Center(child: Text("Observaciones")),
                _buildTabFoto(),
              ],
            ),
    );
  }

  Widget _buildTabCabecera(Map<String, double> resumen) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isConfirmedKyro)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Pedido Confirmado',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow('Cliente', _cliente?['nombre'] ?? ''),
                _buildInfoRow('Fecha', _formatearFecha(_pedido['fecha'])),
                _buildInfoRow('Serie', _nombreSerie),
                _buildInfoRow('Forma Pago', _nombreFormaPago),
                _buildInfoRow('Dirección', _direccionEntrega),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 🟢 TARJETA DE TOTALES DESGLOSADA
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
    return ListView.builder(
      itemCount: _lineas.length,
      itemBuilder: (ctx, i) {
        final l = _lineas[i];
        return Card(
          child: ListTile(
            title: Text(l.articuloNombre),
            subtitle: Text('${l.cantidad} x ${l.precio} €'),
            trailing: Text('${(l.cantidad * l.precio).toStringAsFixed(2)}€'),
          ),
        );
      },
    );
  }

  Widget _buildTabFoto() {
    if (_cargandoFoto) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: _fotoBase64 != null
              ? Image.memory(base64Decode(_fotoBase64!))
              : const Center(
                  child: Icon(Icons.camera_alt, size: 50, color: Colors.grey),
                ),
        ),
        if (!_isConfirmedKyro)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => _tomarFoto(ImageSource.camera),
                child: const Text("Cámara"),
              ),
              const SizedBox(width: 20),
              ElevatedButton(
                onPressed: () => _tomarFoto(ImageSource.gallery),
                child: const Text("Galería"),
              ),
            ],
          ),
      ],
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
