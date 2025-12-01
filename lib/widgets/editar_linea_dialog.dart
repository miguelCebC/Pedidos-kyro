import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/iva_config.dart';

class EditarLineaDialog extends StatefulWidget {
  final Map<String, dynamic> articulo;
  final double cantidad;
  final double precio;
  final double descuento;
  final double dto1;
  final double dto2;
  final double dto3;
  final String tipoIva;

  const EditarLineaDialog({
    super.key,
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.descuento = 0.0,
    this.dto1 = 0.0,
    this.dto2 = 0.0,
    this.dto3 = 0.0,
    this.tipoIva = 'G',
  });

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late TextEditingController _cantidadController;
  late TextEditingController _precioController;
  late TextEditingController _descuentoController;
  late TextEditingController _dto1Controller;
  late TextEditingController _dto2Controller;
  late TextEditingController _dto3Controller;
  late String _tipoIvaSeleccionado;

  @override
  void initState() {
    super.initState();
    // Mostrar con comas para facilitar la lectura
    _cantidadController = TextEditingController(
      text: widget.cantidad.toString().replaceAll('.', ','),
    );
    _precioController = TextEditingController(
      text: widget.precio.toString().replaceAll('.', ','),
    );
    _descuentoController = TextEditingController(
      text: widget.descuento == 0
          ? ''
          : widget.descuento.toString().replaceAll('.', ','),
    );
    _dto1Controller = TextEditingController(
      text: widget.dto1 == 0 ? '' : widget.dto1.toString().replaceAll('.', ','),
    );
    _dto2Controller = TextEditingController(
      text: widget.dto2 == 0 ? '' : widget.dto2.toString().replaceAll('.', ','),
    );
    _dto3Controller = TextEditingController(
      text: widget.dto3 == 0 ? '' : widget.dto3.toString().replaceAll('.', ','),
    );

    _tipoIvaSeleccionado = widget.tipoIva;
    _cargarConfiguracionIva();
  }

  Future<void> _cargarConfiguracionIva() async {
    await IvaConfig.cargarConfiguracion();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _descuentoController.dispose();
    _dto1Controller.dispose();
    _dto2Controller.dispose();
    _dto3Controller.dispose();
    super.dispose();
  }

  // Helper: Convierte texto con coma o punto a double
  double _parseValue(String text) {
    if (text.isEmpty) return 0.0;
    String sanitized = text.replaceAll(',', '.');
    return double.tryParse(sanitized) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Línea'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.articulo['nombre'] ?? 'Artículo',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              widget.articulo['codigo'] ?? '',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cantidadController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _precioController,
                    decoration: const InputDecoration(
                      labelText: 'Precio (€)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descuentoController,
              decoration: const InputDecoration(
                labelText: 'Descuento (%)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.percent),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Descuentos Cascada (%)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dto1Controller,
                    decoration: const InputDecoration(
                      labelText: 'Dto 1',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _dto2Controller,
                    decoration: const InputDecoration(
                      labelText: 'Dto 2',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _dto3Controller,
                    decoration: const InputDecoration(
                      labelText: 'Dto 3',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipoIvaSeleccionado,
              decoration: const InputDecoration(
                labelText: 'Tipo de IVA',
                border: OutlineInputBorder(),
              ),
              items: IvaConfig.obtenerTipos().map((tipo) {
                return DropdownMenuItem(
                  value: tipo,
                  child: Text(IvaConfig.obtenerNombre(tipo)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _tipoIvaSeleccionado = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              LineaPedidoData(
                articulo: widget.articulo,
                cantidad: _parseValue(_cantidadController.text),
                precio: _parseValue(_precioController.text),
                descuento: _parseValue(_descuentoController.text),
                dto1: _parseValue(_dto1Controller.text),
                dto2: _parseValue(_dto2Controller.text),
                dto3: _parseValue(_dto3Controller.text),
                tipoIva: _tipoIvaSeleccionado,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
