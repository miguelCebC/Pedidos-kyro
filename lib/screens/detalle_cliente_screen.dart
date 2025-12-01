import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';

class DetalleClienteScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const DetalleClienteScreen({super.key, required this.cliente});

  @override
  State<DetalleClienteScreen> createState() => _DetalleClienteScreenState();
}

class _DetalleClienteScreenState extends State<DetalleClienteScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 🟢 6 Pestañas: Datos, Tlf, Email, Dir, Tarifas, Base Conocimiento
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildBaseConocimiento() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      // Consulta local a la tabla 'movimientos'
      future: DatabaseHelper.instance.obtenerMovimientosPorCliente(
        widget.cliente['id'],
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final movimientos = snapshot.data ?? [];

        if (movimientos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('Sin movimientos'),
                SizedBox(height: 8),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: movimientos.length,
          itemBuilder: (context, index) {
            final mov = movimientos[index];

            // Datos ya cruzados en el SQL (JOIN)
            final fecha = _formatearFecha(mov['fecha']);
            final numDoc = mov['num_doc'] ?? 'S/D';
            final nombreArt = mov['nombre_articulo'] ?? 'Artículo desconocido';
            final refArt = mov['codigo_articulo'] ?? '???';

            final entrada = (mov['entrada'] as num?)?.toDouble() ?? 0.0;
            final salida = (mov['salida'] as num?)?.toDouble() ?? 0.0;
            final precio = (mov['precio'] as num?)?.toDouble() ?? 0.0;

            final bool esSalida = salida > 0;
            final cantidad = esSalida ? salida : entrada;
            final color = esSalida ? Colors.red[700] : Colors.green[700];
            final signo = esSalida ? '-' : '+';

            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          numDoc,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF032458),
                          ),
                        ),
                        Text(
                          fecha,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nombreArt,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Ref: $refArt',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color!.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$signo${cantidad.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${precio.toStringAsFixed(2)} €',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.isEmpty) return '';
    try {
      final fecha = DateTime.parse(fechaStr);
      return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    } catch (e) {
      return fechaStr;
    }
  }

  Future<void> _lanzarAccion(String tipo, String valor) async {
    Uri? uri;
    if (valor.isEmpty) return;
    if (tipo == 'tel') {
      uri = Uri.parse('tel:$valor');
    } else if (tipo == 'email')
      uri = Uri.parse('mailto:$valor');
    else if (tipo == 'map')
      uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(valor)}');

    try {
      if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (e) {
      print('Error: $e');
    }
  }

  // WIDGETS AUXILIARES (Reutilizados de tu código anterior para las otras pestañas)
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF032458)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatosGenerales() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoRow(
          Icons.business,
          'Nombre Comercial',
          widget.cliente['nom_com'] ?? '',
        ),
        _buildInfoRow(
          Icons.person,
          'Nombre Fiscal',
          widget.cliente['nom_fis'] ?? widget.cliente['nombre'],
        ),
        _buildInfoRow(Icons.badge, 'CIF / NIF', widget.cliente['cif'] ?? ''),
      ],
    );
  }

  // 🟢 PESTAÑA CONTACTOS (Teléfonos y Emails)
  Widget _buildListaContactosFiltrada(List<String> tipos) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.obtenerContactosPorCliente(
        widget.cliente['id'],
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final contactos = snapshot.data!
            .where((c) => tipos.contains(c['tipo']))
            .toList();
        if (contactos.isEmpty) {
          return const Center(child: Text('No hay registros'));
        }

        return ListView.separated(
          itemCount: contactos.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final c = contactos[index];
            return ListTile(
              leading: Icon(
                c['tipo'] == 'E' ? Icons.email : Icons.phone,
                color: const Color(0xFF032458),
              ),
              title: Text(c['valor'] ?? ''),
              subtitle: Text(c['nombre'] ?? ''),
              onTap: () =>
                  _lanzarAccion(c['tipo'] == 'E' ? 'email' : 'tel', c['valor']),
            );
          },
        );
      },
    );
  }

  Widget _buildListaDirecciones() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.obtenerDireccionesPorCliente(
        widget.cliente['id'],
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay direcciones asignadas'));
        }
        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (ctx, i) {
            final d = snapshot.data![i];
            return ListTile(
              leading: const Icon(Icons.place, color: Colors.red),
              title: Text(d['direccion']),
              onTap: () => _lanzarAccion('map', d['direccion']),
            );
          },
        );
      },
    );
  }

  // 🟢 PESTAÑA TARIFAS
  Widget _buildListaTarifas() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.obtenerTarifasPorCliente(
        widget.cliente['id'],
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('No hay tarifas especiales'));
        }
        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (ctx, i) {
            final t = snapshot.data![i];
            return ListTile(
              title: Text(t['nombre_articulo'] ?? 'Art. Desconocido'),
              subtitle: Text('Ref: ${t['codigo_articulo']}'),
              trailing: Text(
                '${t['precio']}€',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha Cliente'),
        backgroundColor: const Color(0xFF032458),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'DATOS'),
            Tab(text: 'TELÉFONOS'),
            Tab(text: 'EMAILS'),
            Tab(text: 'DIRECCIONES'),
            Tab(text: 'BASE CONOCIMIENTO'), // 🟢 Nueva
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDatosGenerales(),
          _buildListaContactosFiltrada(['T', 'F']),
          _buildListaContactosFiltrada(['E']),
          _buildListaDirecciones(),
          // _buildListaTarifas(),
          _buildBaseConocimiento(), // 🟢 Contenido de la nueva pestaña
        ],
      ),
    );
  }
}
