import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import 'detalle_articulo_screen.dart';

class CatalogoArticulosScreen extends StatefulWidget {
  const CatalogoArticulosScreen({super.key});

  @override
  State<CatalogoArticulosScreen> createState() =>
      _CatalogoArticulosScreenState();
}

class _CatalogoArticulosScreenState extends State<CatalogoArticulosScreen> {
  final List<Map<String, dynamic>> _articulos = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _cargarArticulos(reset: true);

    // 🟢 Sincronizar artículos en segundo plano al entrar
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarFondo());

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _cargarArticulos();
      }
    });
    _searchController.addListener(_onSearchChanged);
  }

  // Sincronización silenciosa
  Future<void> _sincronizarFondo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final apiKey = prefs.getString('velneo_api_key');
      if (url == null || apiKey == null) return;

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey,
      );
      final articulos = await api.obtenerArticulos();

      if (articulos.isNotEmpty) {
        await DatabaseHelper.instance.insertarArticulosLote(articulos.cast());
        if (mounted) {
          _cargarArticulos(reset: true); // Refrescar lista si hay nuevos
        }
      }
    } catch (e) {
      print("Sync fondo articulos error: $e");
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _cargarArticulos(reset: true),
    );
  }

  Future<void> _cargarArticulos({bool reset = false}) async {
    if (_isLoading && !reset) return;
    setState(() {
      _isLoading = true;
      if (reset) {
        _articulos.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });

    try {
      final nuevos = await DatabaseHelper.instance.obtenerArticulosPaginados(
        busqueda: _searchController.text,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      if (mounted) {
        setState(() {
          if (nuevos.length < _pageSize) _hasMore = false;
          _articulos.addAll(nuevos);
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar artículo...',
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
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _articulos.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _articulos.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final art = _articulos[index];
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetalleArticuloScreen(articulo: art),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        // 🟢 IMAGEN CON LAZY LOADING + CACHÉ
                        ArticuloImagenWidget(articulo: art),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                art['nombre'] ?? 'Sin nombre',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF032458),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Ref: ${art['codigo'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${(art['precio'] as num).toStringAsFixed(2)}€',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF032458),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ],
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

class ArticuloImagenWidget extends StatefulWidget {
  final Map<String, dynamic> articulo;
  const ArticuloImagenWidget({super.key, required this.articulo});
  @override
  State<ArticuloImagenWidget> createState() => _ArticuloImagenWidgetState();
}

class _ArticuloImagenWidgetState extends State<ArticuloImagenWidget> {
  static final Map<int, String> _memoriaImagenes = {}; // Caché estática
  String? _imagenBase64;
  bool _intentadoCargar = false;

  @override
  void initState() {
    super.initState();
    final id = widget.articulo['id'];
    // 1. Buscar en memoria
    if (_memoriaImagenes.containsKey(id)) {
      _imagenBase64 = _memoriaImagenes[id];
    }
    // 2. Buscar en dato local
    else if (widget.articulo['img'] != null &&
        widget.articulo['img'].toString().isNotEmpty) {
      _imagenBase64 = widget.articulo['img'];
    }
    // 3. Descargar si no hay
    if (_imagenBase64 == null || _imagenBase64!.isEmpty) {
      _descargarImagen();
    }
  }

  Future<void> _descargarImagen() async {
    if (_intentadoCargar) return;
    _intentadoCargar = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final key = prefs.getString('velneo_api_key');
      if (url != null && key != null) {
        final api = VelneoAPIService(
          url.startsWith('http') ? url : 'https://$url',
          key,
        );
        final det = await api.obtenerDetalleArticulo(widget.articulo['id']);
        if (mounted &&
            det != null &&
            det['img'] != null &&
            det['img'].isNotEmpty) {
          _memoriaImagenes[widget.articulo['id']] = det['img'];
          setState(() => _imagenBase64 = det['img']);
        }
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_imagenBase64 == null || _imagenBase64!.isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.inventory_2, color: Colors.grey),
      );
    }
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(_imagenBase64!),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(
            width: 60,
            height: 60,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image),
          ),
        ),
      );
    } catch (e) {
      return Container(width: 60, height: 60, color: Colors.grey[200]);
    }
  }
}
