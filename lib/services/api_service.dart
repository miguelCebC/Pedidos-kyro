import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/debug_logs_screen.dart';
import '../database_helper.dart';

class VelneoAPIService {
  final String baseUrl;
  final String apiKey;
  final http.Client _client = http.Client();
  final Function(String)? onLog;

  static int _fallosConsecutivos = 0;
  static const int _limiteFallos = 5; // A los 5 fallos seguidos, se cierra

  // Callback estático para avisar a la UI que debe cerrarse
  static Function(String motivo)? onCierreForzoso;

  VelneoAPIService(this.baseUrl, this.apiKey, {this.onLog});

  void _log(String message) {
    if (onLog != null) {
      onLog!(message);
    }
    print(message);
  }

  static http.Client createHttpClient() {
    return http.Client();
  }

  String _buildUrl(String endpoint) {
    return '$baseUrl$endpoint?api_key=$apiKey';
  }

  Future<http.Response> _getWithSSL(String url) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);

    try {
      // Configuración de timeout corto para no hacer esperar mucho al usuario
      final request = await httpClient.getUrl(Uri.parse(url));
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final stringData = await response.transform(utf8.decoder).join();

      final httpResponse = http.Response(
        stringData,
        response.statusCode,
        headers: {
          'content-type':
              response.headers.contentType?.toString() ?? 'application/json',
        },
      );

      // SI LLEGAMOS AQUÍ, LA CONEXIÓN TÉCNICA FUE EXITOSA

      // Si el servidor responde (aunque sea 404 o 500), técnicamente hay conexión.
      // Pero si es un error grave (500) o de red, consideramos fallo.
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 500) {
        // ✅ ÉXITO: Reseteamos el contador global
        if (_fallosConsecutivos > 0) {
          _log('✅ Conexión recuperada. Contador de fallos reseteado.');
          _fallosConsecutivos = 0;
        }
        return httpResponse;
      } else {
        throw Exception('Error servidor ${httpResponse.statusCode}');
      }
    } catch (e) {
      // ❌ FALLO DETECTADO
      _fallosConsecutivos++;
      _log('⚠️ Fallo de conexión #$_fallosConsecutivos / $_limiteFallos: $e');

      // 🟢 VERIFICAR SI SUPERAMOS EL LÍMITE
      if (_fallosConsecutivos >= _limiteFallos) {
        _log('⛔ LÍMITE DE FALLOS ALCANZADO. SOLICITANDO CIERRE.');
        if (onCierreForzoso != null) {
          onCierreForzoso!(
            'Se ha perdido la conexión con el servidor tras $_limiteFallos intentos fallidos.',
          );
        }
      }

      // Re-lanzamos el error para que la pantalla local sepa que falló esta petición concreta
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  String _buildUrlWithParams(String endpoint, Map<String, String>? params) {
    final uri = Uri.parse('$baseUrl$endpoint');
    final queryParams = {'api_key': apiKey};
    if (params != null) {
      queryParams.addAll(params);
    }
    return uri.replace(queryParameters: queryParams).toString();
  }

  double _convertirADouble(dynamic valor) {
    if (valor == null) return 0.0;
    if (valor is double) return valor;
    if (valor is int) return valor.toDouble();
    if (valor is String) return double.tryParse(valor) ?? 0.0;
    return 0.0;
  }
  // En lib/services/api_service.dart

  // En lib/services/api_service.dart

  Future<List<dynamic>> obtenerArticulos() async {
    try {
      final allArticulos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📦 Descargando artículos (Todos, con campo OFF)...');

      while (true) {
        // 🟢 PEDIMOS EL CAMPO 'off' Y QUITAMOS FILTROS
        final url = _buildUrlWithParams('/art_m', {
          'fields':
              'id,ref,name,pvp,exs,fam,prv,cod_bar,off', // <--- Pedimos 'off'
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
        });

        _log('  📄 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
            }

            final listaRaw = data['art_m'] ?? data['ART_M'];

            if (listaRaw != null && listaRaw is List) {
              final articulosList = listaRaw;

              if (articulosList.isEmpty) break;

              final articulos = articulosList.map((articulo) {
                // 🟢 DETECTAR VALOR OFF (Boolean o String)
                // Velneo puede devolver true/false o "true"/"false". SQLite necesita 1/0.
                dynamic offRaw = articulo['off'] ?? articulo['OFF'];
                int offVal = 0;
                if (offRaw == true ||
                    offRaw.toString().toLowerCase() == 'true') {
                  offVal = 1;
                }

                return {
                  'id': articulo['id'] ?? articulo['ID'],
                  'codigo': articulo['ref'] ?? articulo['REF'] ?? '',
                  'nombre':
                      articulo['name'] ?? articulo['NAME'] ?? 'Sin nombre',
                  'descripcion': articulo['name'] ?? articulo['NAME'] ?? '',
                  'precio': _convertirADouble(
                    articulo['pvp'] ?? articulo['PVP'],
                  ),
                  'stock': articulo['exs'] ?? articulo['EXS'] ?? 0,
                  'img': '',
                  'familia': articulo['fam'] ?? articulo['FAM'] ?? '',
                  'proveedor_id': articulo['prv'] ?? articulo['PRV'] ?? 0,
                  'codigo_barras':
                      articulo['cod_bar'] ?? articulo['COD_BAR'] ?? '',
                  'off':
                      offVal, // 🟢 Guardamos el estado (0=Activo, 1=Inactivo)
                };
              }).toList();

              allArticulos.addAll(articulos);
              _log('    -> Recibidos ${articulos.length} artículos');

              if (articulos.length < pageSize) break;
              if (totalCount > 0 && allArticulos.length >= totalCount) break;

              page++;
              await Future.delayed(const Duration(milliseconds: 100));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('❌ Error en página $page: $e');
          if (allArticulos.isNotEmpty) break;
          rethrow;
        }
      }

      _log('✅ Total artículos descargados: ${allArticulos.length}');
      return allArticulos;
    } catch (e) {
      _log('❌ Error en obtenerArticulos: $e');
      rethrow;
    }
  }

  // 🟢 NUEVO: Obtener un PEDIDO individual completo
  Future<Map<String, dynamic>?> obtenerPedido(int id) async {
    try {
      final url = _buildUrl('/VTA_PED_G/$id');
      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        Map<String, dynamic>? p;

        if (data is Map<String, dynamic>) {
          if (data.containsKey('id'))
            p = data;
          else if (data['vta_ped_g'] != null &&
              (data['vta_ped_g'] as List).isNotEmpty) {
            p = data['vta_ped_g'][0];
          }
        }

        if (p != null) {
          return {
            'id': p['id'],
            'cliente_id': p['clt'] ?? 0,
            'cmr': p['cmr'] ?? 0,
            'serie_id': p['ser'] ?? 0,
            'fecha': p['fch'] ?? DateTime.now().toIso8601String(),
            'numero': p['num_ped'] ?? '',
            'estado': p['est'] ?? '',
            'observaciones': p['obs'] ?? '',
            'total': _convertirADouble(p['tot_ped']),
            'base_total': _convertirADouble(p['bas_tot']),
            'iva_total': _convertirADouble(p['iva_tot']),
            'sincronizado': 1,
            'con_kyr': (p['con_kyr'] == true || p['con_kyr'] == 1) ? 1 : 0,
          };
        }
      }
      return null;
    } catch (e) {
      print('Error obtenerPedido: $e');
      return null;
    }
  }

  // 🟢 NUEVO: Obtener un PRESUPUESTO individual completo
  Future<Map<String, dynamic>?> obtenerPresupuesto(int id) async {
    try {
      final url = _buildUrl('/VTA_PRE_G/$id');
      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        Map<String, dynamic>? p;

        if (data is Map<String, dynamic>) {
          if (data.containsKey('id'))
            p = data;
          else if (data['vta_pre_g'] != null &&
              (data['vta_pre_g'] as List).isNotEmpty) {
            p = data['vta_pre_g'][0];
          }
        }

        if (p != null) {
          return {
            'id': p['id'],
            'cliente_id': p['clt'] ?? 0,
            'comercial_id': p['cmr'] ?? 0,
            'serie_id': p['ser'] ?? 0,
            'fecha': p['fch'] ?? DateTime.now().toIso8601String(),
            'numero': p['num_pre'] ?? '',
            'estado': p['est'] ?? '',
            'observaciones': p['obs'] ?? '',
            'total': _convertirADouble(p['tot_pre']),
            'base_total': _convertirADouble(p['bas_tot']),
            'iva_total': _convertirADouble(p['iva_tot']),
            'sincronizado': 1,
          };
        }
      }
      return null;
    } catch (e) {
      print('Error obtenerPresupuesto: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> obtenerClientes() async {
    try {
      final allClientes = <dynamic>[];
      final allComerciales = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📦 Descargando clientes (OPTIMIZADO y SEPARADO)...');

      while (true) {
        final StringBuffer urlBuffer = StringBuffer();
        String base = baseUrl;
        if (base.endsWith('/')) base = base.substring(0, base.length - 1);

        urlBuffer.write('$base/ENT_M');
        urlBuffer.write(
          '?fields=id,nom_fis,eml,tlf,dir,es_cmr,cmr,cif,nom_com,name',
        );
        urlBuffer.write('&api_key=$apiKey');
        urlBuffer.write('&page[size]=$pageSize');
        urlBuffer.write('&page[number]=$page');

        final url = urlBuffer.toString();

        _log('  📄 Página $page...');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['total_count'] != null) totalCount = data['total_count'];

            if (data['ent_m'] != null && data['ent_m'] is List) {
              final entidadesList = data['ent_m'] as List;

              if (entidadesList.isEmpty) break;

              for (var entidad in entidadesList) {
                String nombreFinal =
                    (entidad['nom_fis'] != null &&
                        entidad['nom_fis'].toString().isNotEmpty)
                    ? entidad['nom_fis']
                    : (entidad['name'] ?? 'Sin nombre');

                int cmrSeguro = 0;
                if (entidad['cmr'] != null) {
                  cmrSeguro = int.tryParse(entidad['cmr'].toString()) ?? 0;
                }

                if (entidad['es_cmr'] == true) {
                  allComerciales.add({
                    'id': entidad['id'],
                    'nombre': nombreFinal,
                    'email': entidad['eml'] ?? '',
                    'telefono': entidad['tlf'] ?? '',
                    'direccion': entidad['dir'] ?? '',
                  });
                } else {
                  allClientes.add({
                    'id': entidad['id'],
                    'nombre': nombreFinal,
                    'email': entidad['eml'] ?? '',
                    'telefono': entidad['tlf'] ?? '',
                    'direccion': entidad['dir'] ?? '',
                    // 🟢 Guardamos el ID limpio y seguro
                    'cmr': cmrSeguro,
                    'cif': entidad['cif'] ?? '',
                    'nom_fis': entidad['nom_fis'] ?? '',
                    'nom_com': entidad['nom_com'] ?? '',
                  });
                }
              }
              // ... resto del código

              if (entidadesList.length < pageSize) break;
              if (totalCount > 0 &&
                  (allClientes.length + allComerciales.length) >= totalCount) {
                break;
              }
              page++;
              await Future.delayed(const Duration(milliseconds: 100));
            } else {
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          if (allClientes.isEmpty && allComerciales.isEmpty) rethrow;
          break;
        }
      }

      _log(
        '✅ Clientes: ${allClientes.length} | Comerciales: ${allComerciales.length}',
      );
      return {'clientes': allClientes, 'comerciales': allComerciales};
    } catch (e) {
      _log('❌ Error en obtenerClientes: $e');
      rethrow;
    }
  }
  // En lib/services/api_service.dart

  // 🟢 DESCARGAR MOVIMIENTOS (Para Sincronización)
  Future<List<dynamic>> obtenerMovimientos([DateTime? desde]) async {
    try {
      final allMovs = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      bool deberiasContinuar = true;

      _log('📦 Descargando movimientos (MOV_G)...');

      while (deberiasContinuar) {
        final params = {
          'fields':
              'id,clt,art,fch,can_ent,can_sal,pre,num_doc,mod_tim', // Campos necesarios
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
          'sort': '-fch', // Ordenar por fecha (más reciente primero)
        };

        // URL segura
        final url = _buildUrlWithParams('/MOV_G', params);

        _log('  📄 Página $page');

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['mov_g'] ?? data['MOV_G'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((mov) {
              return {
                'id': mov['id'] ?? mov['ID'],
                'cliente_id': mov['clt'] ?? mov['CLT'] ?? 0,
                'articulo_id': mov['art'] ?? mov['ART'] ?? 0,
                'fecha': mov['fch'] ?? mov['FCH'] ?? '',
                'num_doc': mov['num_doc'] ?? mov['NUM_DOC'] ?? '',
                'entrada': _convertirADouble(mov['can_ent'] ?? mov['CAN_ENT']),
                'salida': _convertirADouble(mov['can_sal'] ?? mov['CAN_SAL']),
                'precio': _convertirADouble(mov['pre'] ?? mov['PRE']),
              };
            }).toList();

            // Filtro de fecha si es incremental
            if (desde != null) {
              // Lógica incremental simple: si encontramos un registro más viejo que 'desde', paramos.
              // (Asumiendo que 'mod_tim' o 'fch' son fiables)
              // ...
            }

            allMovs.addAll(lista);
            _log('    -> ${lista.length} movimientos recuperados');

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }

      _log('✅ Total movimientos descargados: ${allMovs.length}');
      return allMovs;
    } catch (e) {
      _log('❌ Error en obtenerMovimientos: $e');
      rethrow;
    }
  }

  // ===============================================
  // 🟢 FASE 1: SINCRONIZACIÓN DE MAESTROS (Splash Screen)
  // ===============================================
  Future<void> sincronizarMaestros() async {
    _log('🚀 [SPLASH] Iniciando sincronización de MAESTROS...');
    final db = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();

    try {
      // 1. SERIES
      _log('📦 Descargando Series...');
      final series = await obtenerSeries();
      await db.limpiarSeries();
      await db.insertarSeriesLote(series.cast<Map<String, dynamic>>());

      // 2. Formas de Pago
      _log('📦 Descargando Formas de Pago...');
      final formasPago = await obtenerFormasPago();
      await db.insertarFormasPagoLote(formasPago.cast<Map<String, dynamic>>());

      // 3. Familias
      _log('📦 Descargando Familias...');
      final familias = await obtenerFamilias();
      await db.limpiarFamilias();
      await db.insertarFamiliasLote(familias.cast<Map<String, dynamic>>());

      // 4. Configuración de IVA
      _log('📦 Descargando IVA...');
      final configIva = await obtenerConfiguracionIVA();
      if (configIva.isNotEmpty) {
        await prefs.setDouble('iva_general', configIva['iva_general']!);
        await prefs.setDouble('iva_reducido', configIva['iva_reducido']!);
        await prefs.setDouble(
          'iva_superreducido',
          configIva['iva_superreducido']!,
        );
        await prefs.setDouble('iva_exento', configIva['iva_exento']!);
      }

      // 5. Maestros CRM
      _log('📦 Descargando Maestros CRM...');

      final tiposVisita = await obtenerTiposVisita();
      await db.limpiarTiposVisita();
      await db.insertarTiposVisitaLote(
        tiposVisita.cast<Map<String, dynamic>>(),
      );

      final provincias = await obtenerProvincias();
      await db.limpiarProvincias();
      await db.insertarProvinciasLote(provincias.cast<Map<String, dynamic>>());

      final zonas = await obtenerZonasTecnicas();
      await db.limpiarZonasTecnicas();
      await db.insertarZonasTecnicasLote(zonas.cast<Map<String, dynamic>>());

      final poblaciones = await obtenerPoblaciones();
      await db.limpiarPoblaciones();
      await db.insertarPoblacionesLote(
        poblaciones.cast<Map<String, dynamic>>(),
      );

      final campanas = await obtenerCampanas();
      await db.limpiarCampanas();
      await db.insertarCampanasLote(campanas.cast<Map<String, dynamic>>());

      _log('✅ [SPLASH] Maestros sincronizados correctamente.');
    } catch (e) {
      _log('❌ Error en sincronizarMaestros: $e');
      rethrow;
    }
    _log('📦 Descargando Presupuestos...');
    final presupuestos = await obtenerPresupuestos();
    await db.limpiarPresupuestos();
    await db.insertarPresupuestosLote(
      presupuestos.cast<Map<String, dynamic>>(),
    );

    _log('📦 Descargando Líneas de Presupuestos...');
    final lineasPresupuesto = await obtenerTodasLineasPresupuesto();
    await db.insertarLineasPresupuestoLote(
      lineasPresupuesto.cast<Map<String, dynamic>>(),
    );

    // 7. Pedidos
    _log('📦 Descargando Pedidos...');
    final pedidos = await obtenerPedidos();
    await db.limpiarPedidos();
    await db.insertarPedidosLote(pedidos.cast<Map<String, dynamic>>());

    _log('📦 Descargando Líneas de Pedidos...');
    final lineasPedido = await obtenerTodasLineasPedido();
    await db.insertarLineasPedidoLote(
      lineasPedido.cast<Map<String, dynamic>>(),
    );
  }

  Future<List<dynamic>> obtenerMovimientosCliente(int clienteId) async {
    try {
      final allMovs = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando historial de movimientos del cliente $clienteId...');

      while (true) {
        // Pedimos los campos exactos que has indicado
        final url = _buildUrlWithParams('/MOV_G', {
          'filter[clt]': clienteId.toString(),
          'fields': 'id,art,fch,can_ent,can_sal,pre,num_doc',
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
          'sort': '-fch', // Ordenar por fecha (más reciente primero)
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          // Tu JSON devuelve "mov_g"
          final listaRaw = data['mov_g'] ?? data['MOV_G'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((mov) {
              return {
                'id': mov['id'],
                'articulo_id': mov['art'] ?? 0, // ID para buscar luego en local
                'fecha': mov['fch'] ?? '',
                'num_doc': mov['num_doc'] ?? '',
                // Convertimos strings numéricos a double
                'entrada': _convertirADouble(mov['can_ent']),
                'salida': _convertirADouble(mov['can_sal']),
                'precio': _convertirADouble(mov['pre']),
              };
            }).toList();

            allMovs.addAll(lista);

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }

      _log('✅ Total movimientos recuperados: ${allMovs.length}');
      return allMovs;
    } catch (e) {
      _log('❌ Error en obtenerMovimientosCliente: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> obtenerDetalleArticulo(int id) async {
    try {
      // 1. Construcción MANUAL de la URL para asegurar el formato exacto
      // Formato deseado: .../ART_M/1234?fields=id,img&api_key=...
      final StringBuffer urlBuffer = StringBuffer();

      // Aseguramos que no haya doble barra // entre base y endpoint
      String base = baseUrl;
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);

      urlBuffer.write('$base/ART_M/$id');
      urlBuffer.write('?fields=id,img'); // 🟢 Coma literal, sin codificar
      urlBuffer.write('&api_key=$apiKey');

      final url = urlBuffer.toString();

      // 🕵️ LOG DE DEBUG: LA LLAMADA
      print('🚀 [DEBUG API] Request URL: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      // 🕵️ LOG DE DEBUG: LA RESPUESTA
      print('📩 [DEBUG API] Status Code: ${response.statusCode}');
      print(
        '📦 [DEBUG API] Body (primeros 200 chars): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Lógica de parsing robusta (por si devuelve objeto o lista)
        Map<String, dynamic>? articuloRaw;

        if (data is Map<String, dynamic>) {
          // Caso A: Devuelve objeto directo { "id": ... }
          // A veces Velneo devuelve el objeto directo si se pide por ID
          if (data.containsKey('id')) {
            articuloRaw = data;
          }
          // Caso B: Devuelve envuelto en { "art_m": [ ... ] }
          else if (data['art_m'] != null && data['art_m'] is List) {
            final lista = data['art_m'] as List;
            if (lista.isNotEmpty) articuloRaw = lista[0];
          }
        }

        if (articuloRaw != null) {
          print(
            '✅ [DEBUG API] Imagen encontrada: ${articuloRaw['img'] != null ? "SÍ (${articuloRaw['img'].toString().length} chars)" : "NO"}',
          );

          return {'id': articuloRaw['id'], 'img': articuloRaw['img'] ?? ''};
        } else {
          print(
            '⚠️ [DEBUG API] No se pudo extraer el objeto articulo del JSON',
          );
        }
      } else {
        print('❌ [DEBUG API] Error del servidor: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      print('❌ [DEBUG API] Excepción: $e');
      return null;
    }
  }

  // 🟢 OBTENER PEDIDOS (Lista completa)
  Future<List<dynamic>> obtenerPedidos([int? comercialId]) async {
    try {
      final allPedidos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando pedidos...');

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        };
        if (comercialId != null) params['filter[cmr]'] = comercialId.toString();

        final url = _buildUrlWithParams('/VTA_PED_G', params);
        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['vta_ped_g'] as List?;

          if (listaRaw == null || listaRaw.isEmpty) break;

          final lista = listaRaw.map((p) {
            return {
              'id': p['id'],
              'cliente_id': p['clt'] ?? 0,
              'cmr': p['cmr'] ?? 0,
              'serie_id': p['ser'] ?? 0,
              'fecha': p['fch'] ?? DateTime.now().toIso8601String(),
              'numero': p['num_ped'] ?? '',
              'estado': p['est'] ?? '',
              'observaciones': p['obs'] ?? '',
              // 🟢 MAPEO DE TOTALES DEL SERVIDOR
              'total': _convertirADouble(p['tot_ped']),
              'base_total': _convertirADouble(p['bas_tot']),
              'iva_total': _convertirADouble(p['iva_tot']),
              'sincronizado': 1,
            };
          }).toList();

          allPedidos.addAll(lista);
          if (lista.length < pageSize) break;
          page++;
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      return allPedidos;
    } catch (e) {
      _log('❌ Error obtenerPedidos: $e');
      rethrow;
    }
  }

  // 🟢 ACTUALIZAR PEDIDO (Recuperar totales calculados)
  Future<Map<String, dynamic>> actualizarPedido(
    int pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      // 1. Cabecera
      final req = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PED_G/$pedidoId')),
      );
      req.headers.set('Content-Type', 'application/json');
      req.write(
        json.encode({
          'clt': pedido['cliente_id'],
          'obs': pedido['observaciones'],
          if (pedido['con_kyr'] != null) 'con_kyr': pedido['con_kyr'],
        }),
      );
      final res = await req.close();
      final stringData = await res.transform(utf8.decoder).join();

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // 2. Líneas con Seguridad
        if (pedido.containsKey('lineas')) {
          final actuales = await obtenerLineasPedido(pedidoId);
          for (var l in actuales) {
            // 🛑 SEGURIDAD: ID del pedido debe coincidir
            if (l['pedido_id'].toString() != pedidoId.toString()) continue;

            await httpClient
                .deleteUrl(Uri.parse(_buildUrl('/VTA_PED_LIN_G/${l['id']}')))
                .then((r) => r.close())
                .then((r) => r.drain());
          }
          if (pedido['lineas'] != null) {
            for (var l in pedido['lineas']) await crearLineaPedido(pedidoId, l);
          }
        }
        return _extraerTotales(json.decode(stringData), 'vta_ped_g', pedidoId);
      }
      throw Exception('Error actualizar pedido: $stringData');
    } finally {
      httpClient.close();
    }
  }

  // 🟢 1. OBTENER FORMAS DE PAGO (Con estructura: id, name)
  Future<List<dynamic>> obtenerFormasPago() async {
    try {
      final allItems = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📦 Descargando formas de pago...');

      while (true) {
        // Pedimos ID y NAME (según tu JSON)
        final url = _buildUrlWithParams('/FPG_M', {
          'fields': 'id,name',
          'page[size]': pageSize.toString(),
          'page[number]': page.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // Buscamos la lista (fpg_m o FPG_M)
          final listaRaw = data['fpg_m'] ?? data['FPG_M'];

          if (listaRaw != null && listaRaw is List) {
            if (listaRaw.isEmpty) break;

            final lista = listaRaw.map((item) {
              return {
                'id': item['id'],
                // 🟢 IMPORTANTE: Leemos 'name' como indica tu JSON
                'nombre': item['name'] ?? item['NAME'] ?? 'Sin nombre',
              };
            }).toList();

            allItems.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      _log('✅ Formas de pago descargadas: ${allItems.length}');
      return allItems;
    } catch (e) {
      _log('❌ Error en obtenerFormasPago: $e');
      return [];
    }
  }

  // 🟢 2. OBTENER SERIES (Asumiendo misma estructura: id, name)
  // En lib/services/api_service.dart

  Future<List<dynamic>> obtenerSeries() async {
    try {
      _log('📦 Descargando series (SER_M)...');

      // CORRECCIÓN: Solicitamos 'ser_tip' que es el campo real en tu JSON
      final url = _buildUrlWithParams('/SER_M', {'fields': 'id,name,ser_tip'});

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final listaRaw = data['ser_m'] ?? data['SER_M'];

        if (listaRaw != null && listaRaw is List) {
          final lista = listaRaw.map((s) {
            return {
              'id': s['id'],
              'nombre': s['name'] ?? 'Sin nombre',
              // CORRECCIÓN: Mapeamos 'ser_tip' al campo 'tipo' de la app
              'tipo': s['ser_tip'] ?? '',
            };
          }).toList();
          return lista;
        }
      }
      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      _log('❌ Error en obtenerSeries: $e');
      return [];
    }
  }

  // 🟢 MÉTODO NUEVO: Descargar Contactos
  Future<List<Map<String, dynamic>>> obtenerContactos() async {
    try {
      final allContactos = <Map<String, dynamic>>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📦 Descargando contactos (Teléfonos/Emails)...');

      while (true) {
        // Endpoint /CTT_M (Tabla de contactos)
        final url = _buildUrlWithParams('/CTT_M', {
          'fields': 'id,ent,ctt_clf,val,prn,name', // Campos necesarios
          'page[size]': '$pageSize',
          'page[number]': '$page',
        });

        _log('  📄 Página $page...');

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['ctt_m'] != null && data['ctt_m'] is List) {
            final lista = data['ctt_m'] as List;
            if (lista.isEmpty) break;

            for (var c in lista) {
              allContactos.add({
                'id': c['id'],
                'cliente_id': c['ent'] ?? 0,
                'tipo': c['ctt_clf'] ?? '', // T=Tel, E=Email, F=Fax
                'nombre': c['name'] ?? '',
                'valor': c['val'] ?? '',
                // Convertimos "1" string a 1 entero
                'es_principal': (c['prn'] != null && c['prn'].toString() == '1')
                    ? 1
                    : 0,
              });
            }

            if (lista.length < pageSize) break;
            page++;
            await Future.delayed(const Duration(milliseconds: 100));
          } else {
            break;
          }
        } else {
          // Si falla (ej: no existe el endpoint) salimos para no bloquear
          _log('⚠️ Error descargando contactos: ${response.statusCode}');
          break;
        }
      }

      _log('✅ Total contactos descargados: ${allContactos.length}');
      return allContactos;
    } catch (e) {
      _log('❌ Error en obtenerContactos: $e');
      return []; // Retornamos vacío para no romper la sincronización global
    }
  }

  // Actualizar presupuesto existente
  Future<Map<String, dynamic>> actualizarPresupuesto(
    int presupuestoId,
    Map<String, dynamic> presupuesto,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final req = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PRE_G/$presupuestoId')),
      );
      req.headers.set('Content-Type', 'application/json');
      req.write(
        json.encode({
          'clt': presupuesto['cliente_id'],
          'obs': presupuesto['observaciones'],
          'est': presupuesto['estado'],
          'ser': presupuesto['serie_id'],
        }),
      );
      final res = await req.close();
      final stringData = await res.transform(utf8.decoder).join();

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (presupuesto.containsKey('lineas')) {
          final actuales = await obtenerLineasPresupuesto(presupuestoId);
          for (var l in actuales) {
            // 🛑 SEGURIDAD: ID del presupuesto debe coincidir
            if (l['presupuesto_id'].toString() != presupuestoId.toString())
              continue;

            await httpClient
                .deleteUrl(Uri.parse(_buildUrl('/VTA_PRE_LIN_G/${l['id']}')))
                .then((r) => r.close())
                .then((r) => r.drain());
          }
          if (presupuesto['lineas'] != null) {
            for (var l in presupuesto['lineas'])
              await crearLineaPresupuesto(presupuestoId, l);
          }
        }
        return _extraerTotales(
          json.decode(stringData),
          'vta_pre_g',
          presupuestoId,
        );
      }
      throw Exception('Error act presupuesto: $stringData');
    } finally {
      httpClient.close();
    }
  }

  // 🟢 1. OBTENER FOTO PEDIDO (Sin guardar en local)
  Future<String?> obtenerFotoPedido(int pedidoId) async {
    try {
      // Pedimos solo el campo 'fot' para no traer datos innecesarios
      final url = '${_buildUrl('/VTA_PED_G/$pedidoId')}&fields=id,fot';

      print('📸 Descargando foto del pedido #$pedidoId...');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Lógica para extraer el dato sea cual sea el formato de respuesta
        Map<String, dynamic>? registro;

        if (data is Map<String, dynamic>) {
          if (data.containsKey('id')) {
            registro = data;
          } else if (data['vta_ped_g'] != null &&
              (data['vta_ped_g'] is List) &&
              (data['vta_ped_g'] as List).isNotEmpty) {
            registro = data['vta_ped_g'][0];
          }
        }

        if (registro != null) {
          final foto = registro['fot'] as String?;
          if (foto != null && foto.isNotEmpty) {
            print('✅ Foto encontrada (${foto.length} caracteres)');
            return foto;
          }
        }
      }
      print('⚠️ No hay foto o error en respuesta');
      return null;
    } catch (e) {
      print('❌ Error obteniendo foto: $e');
      return null;
    }
  }

  Map<String, dynamic> _extraerTotales(
    dynamic jsonRes,
    String keyLista,
    int defaultId,
  ) {
    dynamic obj;
    if (jsonRes is Map<String, dynamic>) {
      if (jsonRes.containsKey(keyLista) &&
          (jsonRes[keyLista] as List).isNotEmpty) {
        obj = jsonRes[keyLista][0];
      } else if (jsonRes.containsKey('id')) {
        obj = jsonRes;
      }
    }
    if (obj != null) {
      // Claves pueden ser tot_ped (pedidos) o tot_pre (presupuestos)
      double total = _convertirADouble(obj['tot_ped'] ?? obj['tot_pre']);
      return {
        'id': obj['id'] ?? defaultId,
        'server_total': total,
        'server_base': _convertirADouble(obj['bas_tot']),
        'server_iva': _convertirADouble(obj['iva_tot']),
        'success': true,
      };
    }
    return {'id': defaultId, 'success': true};
  }

  int? _extraerId(dynamic jsonRes, String keyLista) {
    if (jsonRes is Map<String, dynamic>) {
      // 1. Buscar en la lista principal (ej: crm_age)
      if (jsonRes.containsKey(keyLista) &&
          jsonRes[keyLista] is List &&
          (jsonRes[keyLista] as List).isNotEmpty) {
        final item = jsonRes[keyLista][0];
        return item['id'] ?? item['ID'];
      }
      // 2. Buscar en la lista con Mayúsculas (ej: CRM_AGE)
      String keyUpper = keyLista.toUpperCase();
      if (jsonRes.containsKey(keyUpper) &&
          jsonRes[keyUpper] is List &&
          (jsonRes[keyUpper] as List).isNotEmpty) {
        final item = jsonRes[keyUpper][0];
        return item['id'] ?? item['ID'];
      }
      // 3. Buscar en la raíz del objeto
      if (jsonRes['id'] != null) return jsonRes['id'];
      if (jsonRes['ID'] != null) return jsonRes['ID'];
    }
    return null;
  }

  // 🟢 2. ACTUALIZAR FOTO PEDIDO (Subir o Borrar)
  Future<bool> actualizarFotoPedido(int pedidoId, String? base64Foto) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(
        seconds: 60,
      ); // Más tiempo para subir imágenes

    try {
      print('📤 Subiendo/Actualizando foto pedido #$pedidoId...');

      // Enviamos cadena vacía "" si base64Foto es null, para borrarla en Velneo
      final bodyVelneo = {'fot': base64Foto ?? ""};

      // Petición POST al recurso específico ID para hacer update parcial
      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PED_G/$pedidoId')),
      );

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(bodyVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        print('✅ Foto actualizada correctamente en servidor');
        return true;
      } else {
        print('❌ Error subiendo foto (${response.statusCode}): $stringData');
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Excepción subiendo foto: $e');
      return false;
    } finally {
      httpClient.close();
    }
  }

  Future<List<dynamic>> obtenerPresupuestos([int? comercialId]) async {
    try {
      final allPresupuestos = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando presupuestos...');

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        };
        if (comercialId != null) params['filter[cmr]'] = comercialId.toString();

        final url = _buildUrlWithParams('/VTA_PRE_G', params);
        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['vta_pre_g'] as List?;

          if (listaRaw == null || listaRaw.isEmpty) break;

          final lista = listaRaw.map((p) {
            return {
              'id': p['id'],
              'cliente_id': p['clt'] ?? 0,
              'comercial_id': p['cmr'] ?? 0,
              'fecha': p['fch'] ?? DateTime.now().toIso8601String(),
              'numero': p['num_pre'] ?? '', // Nota: num_pre en presupuestos
              'estado': p['est'] ?? '',
              'observaciones': p['obs'] ?? '',
              // 🟢 MAPEO DE TOTALES (Usando tot_pre para presupuestos)
              'total': _convertirADouble(p['tot_pre']),
              'base_total': _convertirADouble(p['bas_tot']),
              'iva_total': _convertirADouble(p['iva_tot']),
              'sincronizado': 1,
            };
          }).toList();

          allPresupuestos.addAll(lista);
          if (lista.length < pageSize) break;
          page++;
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      return allPresupuestos;
    } catch (e) {
      _log('❌ Error obtenerPresupuestos: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerTodasLineasPedido() async {
    try {
      final allLineas = <dynamic>[];
      int page = 1;
      const int pageSize = 2000;
      int totalCount = 0;

      _log('📄 Descargando TODAS las líneas de pedido...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final allLineas = <dynamic>[];
          int page = 1;
          const int pageSize = 2000;

          _log('📄 Descargando TODAS las líneas de pedido...');

          while (true) {
            final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
              'page[number]': page.toString(),
              'page[size]': pageSize.toString(),
            });

            try {
              final response = await _getWithSSL(
                url,
              ).timeout(const Duration(seconds: 90));
              if (response.statusCode == 200) {
                final data = json.decode(response.body);
                final listaRaw = data['vta_ped_lin_g'] ?? data['VTA_PED_LIN_G'];

                if (listaRaw != null && listaRaw is List) {
                  if (listaRaw.isEmpty) break;
                  final lineasList = listaRaw.map((linea) {
                    return {
                      'id': linea['id'] ?? linea['ID'],
                      'pedido_id': linea['vta_ped'] ?? linea['VTA_PED'] ?? 0,
                      'articulo_id': linea['art'] ?? linea['ART'] ?? 0,
                      'cantidad': _convertirADouble(
                        linea['can_ped'] ?? linea['CAN_PED'],
                      ),
                      'precio': _convertirADouble(linea['pre'] ?? linea['PRE']),
                      'por_descuento': _convertirADouble(
                        linea['por_dto'] ?? linea['POR_DTO'],
                      ),
                      'dto1': _convertirADouble(linea['dto1'] ?? linea['DTO1']),
                      'dto2': _convertirADouble(linea['dto2'] ?? linea['DTO2']),
                      'dto3': _convertirADouble(linea['dto3'] ?? linea['DTO3']),
                      'por_iva': _convertirADouble(
                        linea['iva_pje'] ?? linea['IVA_PJE'],
                      ),
                      'tipo_iva':
                          linea['reg_iva_vta'] ?? linea['REG_IVA_VTA'] ?? 'G',
                    };
                  }).toList();
                  allLineas.addAll(lineasList);
                  if (listaRaw.length < pageSize) break;
                  page++;
                  await Future.delayed(const Duration(milliseconds: 200));
                } else {
                  break;
                }
              } else {
                throw Exception('HTTP ${response.statusCode}');
              }
            } catch (e) {
              break;
            }
          }
          return allLineas;
        } catch (e) {
          return [];
        }
      }
      _log('✅ TOTAL líneas de pedido descargadas: ${allLineas.length}');
      return allLineas;
    } catch (e) {
      _log('❌ Error en obtenerTodasLineasPedido: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerTodasLineasPresupuesto() async {
    try {
      final allLineas = <dynamic>[];
      int page = 1;
      const int pageSize = 2000;
      int totalCount = 0;

      _log('📄 Descargando TODAS las líneas de presupuesto...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_PRE_LIN_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_pre_lin_g'] != null &&
                data['vta_pre_lin_g'] is List) {
              final lineasList = (data['vta_pre_lin_g'] as List).map((linea) {
                return {
                  'presupuesto_id': linea['vta_pre'] ?? 0,
                  'articulo_id': linea['art'] ?? 0,
                  'cantidad': _convertirADouble(linea['can']),
                  'precio': _convertirADouble(linea['pre']),
                  'por_descuento': _convertirADouble(linea['por_dto']),
                  'por_iva': _convertirADouble(linea['iva_pje']),
                  'tipo_iva': linea['reg_iva_vta'] ?? 'G',
                };
              }).toList();

              if (lineasList.isEmpty) {
                _log('  🏁 No hay más líneas de presupuesto');
                break;
              }

              allLineas.addAll(lineasList);
              _log(
                '  ✅ Página $page: ${lineasList.length} líneas (Acumulado: ${allLineas.length}/$totalCount)',
              );

              if (lineasList.length < pageSize) {
                _log('  🏁 Última página (${lineasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allLineas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allLineas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron líneas de presupuesto');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allLineas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL líneas de presupuesto descargadas: ${allLineas.length}');
      return allLineas;
    } catch (e) {
      _log('❌ Error en obtenerTodasLineasPresupuesto: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerLeads([int? comercialId]) async {
    try {
      final allLeads = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      print(
        '📄 Descargando leads${comercialId != null ? ' del comercial $comercialId' : ''}...',
      );

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        };

        // Agregar filtro de comercial si se proporciona
        if (comercialId != null) {
          params['filter[cmr]'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/CRM_LEA', params);

        print('  📥 Página $page');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              print('  📊 Total registros en servidor: $totalCount');
            }

            if (data['crm_lea'] != null && data['crm_lea'] is List) {
              final leadsList = (data['crm_lea'] as List).map((lead) {
                return {
                  'id': lead['id'],
                  'nombre': lead['name'] ?? '',
                  'fecha_alta': lead['fch_alt'],
                  'campana_id': lead['crm_cam_com'] ?? 0,
                  'cliente_id': lead['cli'] ?? 0,
                  'asunto': lead['asu'] ?? '',
                  'descripcion': lead['dsc'] ?? '',
                  'comercial_id': lead['com'] ?? 0,
                  'estado': lead['crm_est_lea'] ?? '',
                  'fecha': lead['fch'],
                  'enviado': (lead['env'] == true) ? 1 : 0,
                  'agendado': (lead['age'] == true) ? 1 : 0,
                  'agenda_id': lead['crm_age'] ?? 0,
                };
              }).toList();

              if (leadsList.isEmpty) {
                print('  🏁 No hay más leads');
                break;
              }

              allLeads.addAll(leadsList);
              print(
                '  ✅ Página $page: ${leadsList.length} leads (Acumulado: ${allLeads.length}/$totalCount)',
              );

              if (leadsList.length < pageSize) {
                print('  🏁 Última página (${leadsList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allLeads.length >= totalCount) {
                print(
                  '  🏁 Total alcanzado (${allLeads.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              print('  ⚠️ No hay campo crm_lea en respuesta');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          print('  ❌ Error en página $page: $e');
          if (allLeads.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      print('✅ TOTAL leads descargados: ${allLeads.length}');
      return allLeads;
    } catch (e) {
      print('❌ Error en obtenerLeads: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerAgenda([int? comercialId]) async {
    try {
      final allAgendas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      DebugLogger.log(
        '📄 Descargando agenda${comercialId != null ? ' del comercial $comercialId' : ''}...',
      );

      while (true) {
        final params = {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
          'sort': '-id',
        };

        if (comercialId != null) {
          params['com'] = comercialId.toString();
        }

        final url = _buildUrlWithParams('/CRM_AGE', params);

        DebugLogger.log('  📥 Descargando página $page...');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              DebugLogger.log('  📊 Total registros: $totalCount');
            }

            if (data['crm_age'] != null && data['crm_age'] is List) {
              final agendasList = data['crm_age'] as List;
              if (page == 1 && agendasList.isNotEmpty) {
                print('========================================');
                print('🔍 DEBUG API - Primer registro RAW:');
                final primer = agendasList[0];
                print('ID: ${primer['id']}');
                print('asu: ${primer['asu']}');
                print('fch_ini: ${primer['fch_ini']}');
                print('hor_ini RAW: "${primer['hor_ini']}"');
                print('hor_ini TIPO: ${primer['hor_ini'].runtimeType}');
                print('hor_fin RAW: "${primer['hor_fin']}"');
                print('========================================');
              }
              if (agendasList.isEmpty) {
                DebugLogger.log('  🏁 No hay más registros en página $page');
                break;
              }

              final agendas = agendasList
                  .where((agenda) {
                    return agenda['fch_ini'] != null &&
                        agenda['fch_ini'].toString().isNotEmpty;
                  })
                  .map((agenda) {
                    String? limpiarFecha(dynamic fecha) {
                      if (fecha == null) return null;
                      String fechaStr = fecha.toString();
                      if (fechaStr.isEmpty) return null;

                      fechaStr = fechaStr
                          .replaceAll(RegExp(r'[^\d\-T:.\s]'), '')
                          .trim();

                      if (fechaStr.length >= 19) {
                        fechaStr = fechaStr.substring(0, 19);
                      }

                      if (RegExp(
                        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$',
                      ).hasMatch(fechaStr)) {
                        return fechaStr;
                      }

                      return null;
                    }

                    String? limpiarHora(dynamic hora) {
                      if (hora == null) return null;

                      String horaStr = hora.toString().trim();
                      if (horaStr.isEmpty) return null;

                      print('🕐 limpiarHora RAW: "$horaStr"');

                      // Si viene en formato GMT: "Mon Nov 17 09:00:00 2025 GMT"
                      if (horaStr.contains('GMT')) {
                        try {
                          // Extraer la hora usando regex
                          final regex = RegExp(r'\d{2}:\d{2}:\d{2}');
                          final match = regex.firstMatch(horaStr);

                          if (match != null) {
                            final horaExtraida = match.group(0)!;
                            print('✅ Hora extraída de GMT: "$horaExtraida"');
                            return horaExtraida;
                          }
                        } catch (e) {
                          print('❌ Error parseando hora GMT: $horaStr - $e');
                        }
                      }

                      // Si ya viene en formato "HH:MM:SS" directo
                      if (horaStr.contains(':')) {
                        final resultado = horaStr.split('.').first;
                        print('✅ Hora formato directo: "$resultado"');
                        return resultado;
                      }

                      print('⚠️ No se pudo extraer hora de: "$horaStr"');
                      return null;
                    }

                    DebugLogger.log(
                      '🕐 Hora RAW: ${agenda['hor_ini']} → Limpia: ${limpiarHora(agenda['hor_ini'])}',
                    );

                    return {
                      'id': agenda['id'],
                      'nombre': agenda['name'] ?? '',
                      'cliente_id': agenda['cli'] ?? 0,
                      'tipo_visita': agenda['tip_vis'] ?? 0,
                      'asunto': agenda['asu'] ?? '',
                      'comercial_id': agenda['com'] ?? 0,
                      'campana_id': agenda['crm_cam_com'] ?? 0,
                      'fecha_inicio': limpiarFecha(agenda['fch_ini']) ?? '',
                      'hora_inicio': limpiarHora(agenda['hor_ini']) ?? '',
                      'fecha_fin': limpiarFecha(agenda['fch_fin']) ?? '',
                      'hora_fin': limpiarHora(agenda['hor_fin']) ?? '',
                      'fecha_proxima_visita':
                          limpiarFecha(agenda['fch_pro_vis']) ?? '',
                      'hora_proxima_visita':
                          limpiarHora(agenda['hor_pro_vis']) ?? '',
                      'descripcion': agenda['dsc'] ?? '',
                      'todo_dia': (agenda['tod_dia'] == true) ? 1 : 0,
                      'lead_id': agenda['crm_lea'] ?? 0,
                      'presupuesto_id': agenda['vta_pre_g'] ?? 0,
                      'generado': (agenda['gen'] == true) ? 1 : 0,
                      'sincronizado': 1,
                      'no_gen_pro_vis': agenda['no_gen_pro_vis'] ?? false,
                      'no_gen_tri': agenda['no_gen_tri'] ?? false,
                    };
                  })
                  .toList();

              allAgendas.addAll(agendas);
              DebugLogger.log(
                '  ✅ Página $page: ${agendas.length} registros válidos (Total acumulado: ${allAgendas.length}/$totalCount)',
              );

              if (agendasList.length < pageSize) {
                DebugLogger.log(
                  '  🏁 Última página detectada (${agendasList.length} < $pageSize)',
                );
                break;
              }

              if (totalCount > 0 && allAgendas.length >= totalCount) {
                DebugLogger.log(
                  '  🏁 Total alcanzado (${allAgendas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              DebugLogger.log('  ⚠️ No hay campo crm_age en respuesta');
              break;
            }
          } else {
            DebugLogger.log('  ❌ Error HTTP ${response.statusCode}');
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          DebugLogger.log('  ❌ Error en página $page: $e');
          if (allAgendas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      DebugLogger.log(
        '✅ TOTAL agenda descargada: ${allAgendas.length} eventos válidos',
      );
      return allAgendas;
    } catch (e) {
      DebugLogger.log('❌ Error en obtenerAgenda: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerCampanas() async {
    try {
      print('📄 Descargando campañas comerciales...');

      final url = _buildUrlWithParams('/CRM_CAM_COM', {
        'page[number]': '1',
        'page[size]': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['crm_cam_com'] != null && data['crm_cam_com'] is List) {
          final campanasList = (data['crm_cam_com'] as List).map((campana) {
            return {
              'id': campana['id'],
              'nombre': campana['name'] ?? 'Sin nombre',
              'fecha_inicio': campana['fch_ini'],
              'fecha_fin': campana['fch_fin'],
              'sector': campana['sec'] ?? 0,
              'provincia_id': campana['pro_m'] ?? 0,
              'poblacion_id': campana['pob'] ?? 0,
            };
          }).toList();

          print('✅ ${campanasList.length} campañas descargadas');
          return campanasList;
        }
      }

      throw Exception('Error al obtener campañas: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerCampanas: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerTiposVisita() async {
    try {
      print('📄 Descargando tipos de visita...');

      final url = _buildUrlWithParams('/TIP_VIS', {
        'page[number]': '1',
        'page[size]': '50',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['tip_vis'] != null && data['tip_vis'] is List) {
          final tiposList = (data['tip_vis'] as List).map((tipo) {
            return {'id': tipo['id'], 'nombre': tipo['name'] ?? 'Sin nombre'};
          }).toList();

          print('✅ ${tiposList.length} tipos de visita descargados');
          return tiposList;
        }
      }

      throw Exception(
        'Error al obtener tipos de visita: ${response.statusCode}',
      );
    } catch (e) {
      print('❌ Error en obtenerTiposVisita: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerProvincias() async {
    try {
      print('📄 Descargando provincias...');

      final url = _buildUrlWithParams('/PRO_M', {
        'page[number]': '1',
        'page[size]': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['pro_m'] != null && data['pro_m'] is List) {
          final provinciasList = (data['pro_m'] as List).map((provincia) {
            return {
              'id': provincia['id'],
              'nombre': provincia['name'] ?? 'Sin nombre',
              'prefijo_cp': provincia['pre_cps'] ?? '',
              'pais': provincia['pai'] ?? 0,
            };
          }).toList();

          print('✅ ${provinciasList.length} provincias descargadas');
          return provinciasList;
        }
      }

      throw Exception('Error al obtener provincias: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerProvincias: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerZonasTecnicas() async {
    try {
      print('📄 Descargando zonas técnicas...');

      final url = _buildUrlWithParams('/ZN_TCN', {
        'page[number]': '1',
        'page[size]': '100',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['zn_tcn'] != null && data['zn_tcn'] is List) {
          final zonasList = (data['zn_tcn'] as List).map((zona) {
            return {
              'id': zona['id'],
              'nombre': zona['name'] ?? 'Sin nombre',
              'observaciones': zona['observaciones'] ?? '',
              'tecnico_id': zona['tec'] ?? 0,
            };
          }).toList();

          print('✅ ${zonasList.length} zonas técnicas descargadas');
          return zonasList;
        }
      }

      throw Exception(
        'Error al obtener zonas técnicas: ${response.statusCode}',
      );
    } catch (e) {
      print('❌ Error en obtenerZonasTecnicas: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerPoblaciones() async {
    try {
      print('📄 Descargando poblaciones...');

      final url = _buildUrlWithParams('/POB', {
        'page[number]': '1',
        'page[size]': '1000',
      });

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['pob'] != null && data['pob'] is List) {
          final poblacionesList = (data['pob'] as List).map((poblacion) {
            return {
              'id': poblacion['id'],
              'nombre': poblacion['name'] ?? 'Sin nombre',
              'km': poblacion['km'] ?? 0,
              'zona_tecnica_id': poblacion['zn_tcn'] ?? 0,
              'codigo_postal': poblacion['cp'] ?? '',
            };
          }).toList();

          print('✅ ${poblacionesList.length} poblaciones descargadas');
          return poblacionesList;
        }
      }

      throw Exception('Error al obtener poblaciones: ${response.statusCode}');
    } catch (e) {
      print('❌ Error en obtenerPoblaciones: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> obtenerLineasPedido(int pedidoId) async {
    try {
      // Filtro estricto por ID de pedido
      final url = _buildUrlWithParams('/VTA_PED_LIN_G', {
        'filter[vta_ped]': pedidoId.toString(),
        'page[size]': '100',
      });
      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lista = data['vta_ped_lin_g'] ?? data['VTA_PED_LIN_G'];
        if (lista != null && lista is List) {
          return lista
              .map(
                (l) => {
                  'id': l['id'],
                  'pedido_id': l['vta_ped'],
                  'articulo_id': l['art'],
                  'cantidad': _convertirADouble(l['can_ped']), // Campo can_ped
                  'precio': _convertirADouble(l['pre']),
                  'tipo_iva': l['reg_iva_vta'] ?? 'G',
                  'por_descuento': _convertirADouble(l['por_dto']),
                  'dto1': _convertirADouble(l['dto1']),
                  'dto2': _convertirADouble(l['dto2']),
                  'dto3': _convertirADouble(l['dto3']),
                },
              )
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> obtenerLineasPresupuesto(int presupuestoId) async {
    try {
      // Filtro estricto por ID de presupuesto
      final url = _buildUrlWithParams('/VTA_PRE_LIN_G', {
        'filter[vta_pre]': presupuestoId.toString(),
        'page[size]': '100',
      });
      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lista = data['vta_pre_lin_g'] ?? data['VTA_PRE_LIN_G'];
        if (lista != null && lista is List) {
          return lista
              .map(
                (l) => {
                  'id': l['id'],
                  'presupuesto_id': l['vta_pre'],
                  'articulo_id': l['art'],
                  'cantidad': _convertirADouble(l['can']), // Campo can
                  'precio': _convertirADouble(l['pre']),
                  'tipo_iva': l['reg_iva_vta'] ?? 'G',
                  'por_descuento': _convertirADouble(l['por_dto']),
                  // mapeo resto dtos...
                },
              )
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> crearPedido(Map<String, dynamic> pedido) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final header = {
        'emp': '1',
        'clt': pedido['cliente_id'],
        'fch': pedido['fecha'],
        if (pedido['cmr'] != null) 'cmr': pedido['cmr'],
        if (pedido['serie_id'] != null) 'ser': pedido['serie_id'],
        if (pedido['direccion_entrega_id'] != null)
          'dir_env': pedido['direccion_entrega_id'],
        'obs': pedido['observaciones'] ?? '',
      };

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PED_G')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(header));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final res = json.decode(stringData);
        final nuevoId = _extraerId(res, 'vta_ped_g');

        if (nuevoId != null && pedido['lineas'] != null) {
          for (var linea in pedido['lineas']) {
            await crearLineaPedido(nuevoId, linea);
          }
        }
        return _extraerTotales(res, 'vta_ped_g', nuevoId ?? 0);
      }
      throw Exception('Error pedido: $stringData');
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> crearLineaPedido(
    int pedidoId,
    Map<String, dynamic> linea,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final lineaVelneo = {
        'vta_ped': pedidoId,
        'emp': '1',
        'art': linea['articulo_id'],
        'can_ped': _convertirADouble(linea['cantidad']), // Campo can_ped
        'pre': _convertirADouble(linea['precio']),
        'reg_iva_vta': linea['tipo_iva'] ?? linea['reg_iva_vta'] ?? 'G',
        'dto1': _convertirADouble(linea['dto1']),
        'dto2': _convertirADouble(linea['dto2']),
        'dto3': _convertirADouble(linea['dto3']),
      };

      // Gestión de descuento único
      double dto = _convertirADouble(linea['por_dto']);
      if (dto == 0) dto = _convertirADouble(linea['por_descuento']);
      if (dto == 0) dto = _convertirADouble(linea['descuento']);
      if (dto > 0) lineaVelneo['por_dto'] = dto;

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PED_LIN_G')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(lineaVelneo));

      final response = await request.close();
      await response.drain(); // Limpiar respuesta

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true};
      }
      throw Exception('Error línea pedido: ${response.statusCode}');
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> crearPresupuesto(
    Map<String, dynamic> presupuesto,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final header = {
        'emp': '1',
        'clt': presupuesto['cliente_id'],
        'obs': presupuesto['observaciones'] ?? '',
        if (presupuesto['comercial_id'] != null)
          'cmr': presupuesto['comercial_id'],
        if (presupuesto['serie_id'] != null) 'ser': presupuesto['serie_id'],
      };

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PRE_G')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(header));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final res = json.decode(stringData);
        final nuevoId = _extraerId(res, 'vta_pre_g');

        if (nuevoId != null && presupuesto['lineas'] != null) {
          for (var linea in presupuesto['lineas']) {
            await crearLineaPresupuesto(nuevoId, linea);
          }
        }
        return _extraerTotales(res, 'vta_pre_g', nuevoId ?? 0);
      }
      throw Exception('Error crear presupuesto: $stringData');
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> crearLineaPresupuesto(
    int presupuestoId,
    Map<String, dynamic> linea,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final lineaVelneo = {
        'vta_pre': presupuestoId,
        'emp': '1',
        'art': linea['articulo_id'],
        'can': _convertirADouble(linea['cantidad']), // Campo can
        'pre': _convertirADouble(linea['precio']),
        // 🟢 Asegurar valor por defecto para IVA
        'reg_iva_vta': linea['tipo_iva'] ?? linea['reg_iva_vta'] ?? 'G',
        'dto1': _convertirADouble(linea['dto1']),
        'dto2': _convertirADouble(linea['dto2']),
        'dto3': _convertirADouble(linea['dto3']),
      };

      double dto = _convertirADouble(linea['por_dto']);
      if (dto == 0) dto = _convertirADouble(linea['por_descuento']);
      if (dto == 0) dto = _convertirADouble(linea['descuento']);
      if (dto > 0) lineaVelneo['por_dto'] = dto;

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/VTA_PRE_LIN_G')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(lineaVelneo));

      final response = await request.close();
      await response.drain();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true};
      }
      throw Exception('Error línea presupuesto: ${response.statusCode}');
    } finally {
      httpClient.close();
    }
  }

  Future<List<dynamic>> obtenerDirecciones() async {
    try {
      final allDirecciones = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      _log('📄 Descargando direcciones...');

      while (true) {
        final url = _buildUrlWithParams('/DIR_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['dir_m'] != null && data['dir_m'] is List) {
            final lista = (data['dir_m'] as List).map((d) {
              return {
                'id': d['id'],
                'ent': d['ent'], // ID del cliente
                'direccion': d['dir_ver'] ?? d['dir'] ?? 'Sin dirección',
              };
            }).toList();

            if (lista.isEmpty) break;
            allDirecciones.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      _log('✅ Direcciones descargadas: ${allDirecciones.length}');
      return allDirecciones;
    } catch (e) {
      _log('❌ Error obtenerDirecciones: $e');
      return [];
    }
  }

  // 🟢 CREAR VISITA (Corregido con _extraerId)
  Future<Map<String, dynamic>> crearVisitaAgenda(
    Map<String, dynamic> visita,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final visitaVelneo = {
        'cli': visita['cliente_id'],
        'tip_vis': visita['tipo_visita'],
        'asu': visita['asunto'],
        'com': visita['comercial_id'],
        'fch_ini': visita['fecha_inicio'],
        'dsc': visita['descripcion'] ?? '',
        'tod_dia': visita['todo_dia'] == 1,
        'no_gen_tri': visita['no_gen_tri'] ?? false,
        'no_gen_pro_vis': visita['no_gen_pro_vis'] ?? false,
      };

      // Campos opcionales
      if (visita['hora_inicio'] != null)
        visitaVelneo['hor_ini'] = visita['hora_inicio'];
      if (visita['fecha_fin'] != null)
        visitaVelneo['fch_fin'] = visita['fecha_fin'];
      if (visita['hora_fin'] != null)
        visitaVelneo['hor_fin'] = visita['hora_fin'];
      if (visita['campana_id'] != 0)
        visitaVelneo['crm_cam_com'] = visita['campana_id'];
      if (visita['direccion_id'] != null && visita['direccion_id'] != 0) {
        visitaVelneo['dir_m'] = visita['direccion_id'];
      }

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/CRM_AGE')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(visitaVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      // Log para depuración si falla
      print('📥 Respuesta API Crear Visita: $stringData');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respuesta = json.decode(stringData);

        // Usamos el helper para buscar el ID donde sea
        final id = _extraerId(respuesta, 'crm_age');

        if (id != null) {
          return {'id': id, 'success': true};
        } else {
          // Si es 200 pero no hay ID, lanzamos error mostrando lo que llegó
          throw Exception(
            'Velneo devolvió OK pero sin ID. Respuesta: $stringData',
          );
        }
      }
      throw Exception('Error HTTP ${response.statusCode}: $stringData');
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> actualizarVisitaAgenda(
    String visitaId,
    Map<String, dynamic> visita,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = ((c, h, p) => true);
    try {
      final visitaVelneo = {
        'cli': visita['cliente_id'],
        'tip_vis': visita['tipo_visita'],
        'asu': visita['asunto'],
        'com': visita['comercial_id'],
        'fch_ini': visita['fecha_inicio'],
        'dsc': visita['descripcion'] ?? '',
        'tod_dia': visita['todo_dia'] == 1,
        'no_gen_tri': visita['no_gen_tri'] ?? false,
        'no_gen_pro_vis': visita['no_gen_pro_vis'] ?? false,
      };

      if (visita['hora_inicio'] != null)
        visitaVelneo['hor_ini'] = visita['hora_inicio'];
      if (visita['fecha_fin'] != null)
        visitaVelneo['fch_fin'] = visita['fecha_fin'];
      if (visita['hora_fin'] != null)
        visitaVelneo['hor_fin'] = visita['hora_fin'];
      if (visita['fecha_proxima_visita'] != null)
        visitaVelneo['fch_pro_vis'] = visita['fecha_proxima_visita'];
      if (visita['hora_proxima_visita'] != null)
        visitaVelneo['hor_pro_vis'] = visita['hora_proxima_visita'];
      if (visita['campana_id'] != 0)
        visitaVelneo['crm_cam_com'] = visita['campana_id'];
      if (visita['lead_id'] != 0) visitaVelneo['crm_lea'] = visita['lead_id'];

      // 🟢 CORRECCIÓN: Actualizar también la dirección
      if (visita['direccion_id'] != null && visita['direccion_id'] != 0) {
        visitaVelneo['dir_m'] = visita['direccion_id'];
      }

      final request = await httpClient.postUrl(
        Uri.parse(_buildUrl('/CRM_AGE/$visitaId')),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(visitaVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final respuesta = json.decode(stringData);
        final idRespuesta = _extraerId(respuesta, 'crm_age');

        return {'id': idRespuesta ?? int.tryParse(visitaId), 'success': true};
      }
      throw Exception('Error HTTP ${response.statusCode}: $stringData');
    } finally {
      httpClient.close();
    }
  }
  // 🟢 BORRAR VISITA
  /*  Future<bool> deleteVisitaAgenda(String visitaId) async {
    final httpClient = HttpClient()..badCertificateCallback = ((c, h, p) => true);
    try {
      final request = await httpClient.deleteUrl(Uri.parse(_buildUrl('/CRM_AGE/$visitaId')));
      final response = await request.close();
      // Consumir respuesta aunque no la usemos para liberar el socket
      await response.drain(); 

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }
      throw Exception('Error HTTP ${response.statusCode}');
    } finally {
      httpClient.close();
    }
  }*/

  Future<bool> deleteVisitaAgenda(String visitaId) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      DebugLogger.log('🗑️ API: Eliminando visita #$visitaId');

      final request = await httpClient
          .deleteUrl(Uri.parse(_buildUrl('/CRM_AGE/$visitaId')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      DebugLogger.log('📥 API: Status ${response.statusCode}');
      DebugLogger.log('📥 API: Respuesta: $stringData');

      if (response.statusCode == 200 || response.statusCode == 204) {
        DebugLogger.log('✅ API: Visita #$visitaId eliminada');
        return true;
      }

      DebugLogger.log('❌ API: Error HTTP ${response.statusCode}');
      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      DebugLogger.log('❌ API: Excepción - $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> crearLead(Map<String, dynamic> lead) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      print('📝 Creando lead en Velneo...');

      final leadVelneo = {
        'asu': lead['asunto'],
        'dsc': lead['descripcion'] ?? '',
        'com': lead['comercial_id'],
        'crm_est_lea': lead['estado'],
      };

      if (lead['cliente_id'] != null && lead['cliente_id'] != 0) {
        leadVelneo['cli'] = lead['cliente_id'];
      }
      if (lead['campana_id'] != null && lead['campana_id'] != 0) {
        leadVelneo['crm_cam_com'] = lead['campana_id'];
      }

      final jsonData = json.encode(leadVelneo);
      print('📤 JSON enviado: $jsonData');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/CRM_LEA')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      print('📥 Respuesta - Status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respuesta = json.decode(stringData);

        int? leadId;
        if (respuesta['crm_lea'] != null &&
            respuesta['crm_lea'] is List &&
            (respuesta['crm_lea'] as List).isNotEmpty) {
          leadId = respuesta['crm_lea'][0]['id'];
        } else if (respuesta['id'] != null) {
          leadId = respuesta['id'];
        }

        if (leadId == null) {
          throw Exception('No se pudo obtener el ID del lead');
        }

        print('✅ Lead creado con ID $leadId');
        return {'id': leadId, 'success': true};
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      print('❌ Error al crear lead: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, dynamic>> actualizarLead(
    String leadId,
    Map<String, dynamic> lead,
  ) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      print('📝 Actualizando lead #$leadId en Velneo...');

      final leadVelneo = {
        'asu': lead['asunto'],
        'dsc': lead['descripcion'] ?? '',
        'com': lead['comercial_id'],
        'crm_est_lea': lead['estado'],
      };

      if (lead['cliente_id'] != null && lead['cliente_id'] != 0) {
        leadVelneo['cli'] = lead['cliente_id'];
      }
      if (lead['campana_id'] != null && lead['campana_id'] != 0) {
        leadVelneo['crm_cam_com'] = lead['campana_id'];
      }

      final jsonData = json.encode(leadVelneo);
      print('📤 JSON enviado: $jsonData');

      final request = await httpClient
          .postUrl(Uri.parse(_buildUrl('/CRM_LEA/$leadId')))
          .timeout(const Duration(seconds: 30));

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Flutter App');
      request.write(jsonData);

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final stringData = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      print('📥 Respuesta - Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ Lead actualizado correctamente');
        return {'id': int.parse(leadId), 'success': true};
      }

      throw Exception('Error HTTP ${response.statusCode}');
    } catch (e) {
      print('❌ Error al actualizar lead: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }
  // En lib/services/api_service.dart, añadir estas dos funciones después de obtenerTodasLineasPresupuesto():

  Future<List<dynamic>> obtenerTarifasCliente() async {
    try {
      final allTarifas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📄 Descargando tarifas por cliente...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_TAR_CLI_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));
          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_tar_cli_g'] != null &&
                data['vta_tar_cli_g'] is List) {
              final tarifasList = (data['vta_tar_cli_g'] as List).map((tarifa) {
                return {
                  'id': tarifa['id'],
                  'cliente_id': tarifa['clt'] ?? 0,
                  'articulo_id': tarifa['art'] ?? 0,
                  'precio': _convertirADouble(tarifa['pre']),
                  'por_descuento': _convertirADouble(tarifa['por_dto']),
                };
              }).toList();

              if (tarifasList.isEmpty) {
                _log('  🏁 No hay más tarifas por cliente');
                break;
              }

              allTarifas.addAll(tarifasList);
              _log(
                '  ✅ Página $page: ${tarifasList.length} tarifas (Acumulado: ${allTarifas.length}/$totalCount)',
              );

              if (tarifasList.length < pageSize) {
                _log('  🏁 Última página (${tarifasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allTarifas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allTarifas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron tarifas por cliente');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allTarifas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL tarifas por cliente descargadas: ${allTarifas.length}');
      return allTarifas;
    } catch (e) {
      _log('❌ Error en obtenerTarifasCliente: $e');
      return [];
    }
  }

  Future<List<dynamic>> obtenerTarifasArticulo() async {
    try {
      final allTarifas = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;
      int totalCount = 0;

      _log('📄 Descargando tarifas por artículo...');

      while (true) {
        final url = _buildUrlWithParams('/VTA_TAR_ART_G', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        _log('  📥 Página $page - URL: $url');

        try {
          final response = await _getWithSSL(
            url,
          ).timeout(const Duration(seconds: 45));
          _log('  📥 Status code: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['total_count'] != null) {
              totalCount = data['total_count'];
              _log('  📊 Total registros en servidor: $totalCount');
            }

            if (data['vta_tar_art_g'] != null &&
                data['vta_tar_art_g'] is List) {
              final tarifasList = (data['vta_tar_art_g'] as List).map((tarifa) {
                return {
                  'id': tarifa['id'],
                  'articulo_id': tarifa['art'] ?? 0,
                  // 🟢 Mapear nombre tarifa si viene en el JSON (ej: 'tar_name' o 'nom')
                  'nombre_tarifa':
                      tarifa['tar_name'] ??
                      tarifa['nom'] ??
                      'Tarifa ${tarifa['tar'] ?? ''}',
                  'precio': _convertirADouble(tarifa['pre']),
                  'por_descuento': _convertirADouble(tarifa['por_dto']),
                };
              }).toList();

              if (tarifasList.isEmpty) {
                _log('  🏁 No hay más tarifas por artículo');
                break;
              }

              allTarifas.addAll(tarifasList);
              _log(
                '  ✅ Página $page: ${tarifasList.length} tarifas (Acumulado: ${allTarifas.length}/$totalCount)',
              );

              if (tarifasList.length < pageSize) {
                _log('  🏁 Última página (${tarifasList.length} < $pageSize)');
                break;
              }

              if (totalCount > 0 && allTarifas.length >= totalCount) {
                _log(
                  '  🏁 Total alcanzado (${allTarifas.length} >= $totalCount)',
                );
                break;
              }

              page++;
              await Future.delayed(const Duration(milliseconds: 200));
            } else {
              _log('  ⚠️ No se encontraron tarifas por artículo');
              break;
            }
          } else {
            throw Exception('Error HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('  ❌ Error en página $page: $e');
          if (allTarifas.isEmpty) {
            rethrow;
          }
          break;
        }
      }

      _log('✅ TOTAL tarifas por artículo descargadas: ${allTarifas.length}');
      return allTarifas;
    } catch (e) {
      _log('❌ Error en obtenerTarifasArticulo: $e');
      return [];
    }
  }
  // ... dentro de la clase VelneoAPIService ...

  Future<List<dynamic>> obtenerFamilias() async {
    try {
      print('📄 Descargando familias...');
      final allFamilias = <dynamic>[];
      int page = 1;
      const int pageSize = 1000;

      while (true) {
        final url = _buildUrlWithParams('/FAM_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['fam_m'] != null && data['fam_m'] is List) {
            final lista = (data['fam_m'] as List).map((fam) {
              return {
                'id': fam['id'],
                'nombre': fam['name'] ?? fam['nom'] ?? 'Sin nombre',
              };
            }).toList();

            if (lista.isEmpty) break;
            allFamilias.addAll(lista);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      print('✅ Familias descargadas: ${allFamilias.length}');
      return allFamilias;
    } catch (e) {
      print('❌ Error en obtenerFamilias: $e');
      return []; // Retornar vacío en caso de error para no bloquear sync
    }
  }

  // Obtener todos los usuarios
  Future<List> obtenerTodosUsuarios() async {
    final allUsuarios = <Map<String, dynamic>>[];
    int page = 1;
    const pageSize = 1000;

    try {
      while (true) {
        final url = _buildUrlWithParams('/USR_M', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final listaRaw = data['USR_M'] ?? data['usr_m'];

          if (listaRaw != null && listaRaw is List) {
            final lista = listaRaw;

            if (lista.isEmpty) break;

            final listaMapeada = lista.map((item) {
              return {
                'id': item['id'] ?? item['ID'],
                'name': item['name'] ?? item['NAME'] ?? '',
                'ent': item['ent'] ?? item['ENT'],
              };
            }).toList();

            allUsuarios.addAll(listaMapeada.cast<Map<String, dynamic>>());

            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      return allUsuarios;
    } catch (e) {
      throw Exception('Error al obtener usuarios: $e');
    }
  }

  Future<List> obtenerTodosUsrApl() async {
    final allUsrApl = <Map<String, dynamic>>[];
    int page = 1;
    const pageSize = 1000;

    try {
      while (true) {
        // 🟢 Usamos MAYÚSCULAS para la tabla y QUITAMOS el filtro 'fields'
        // Esto asegura que baje todo el objeto tal cual
        final url = _buildUrlWithParams('/USR_APL', {
          'page[number]': page.toString(),
          'page[size]': pageSize.toString(),
        });

        final response = await _getWithSSL(
          url,
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          // Intentamos leer con mayúsculas o minúsculas
          final listaRaw = data['USR_APL'] ?? data['usr_apl'];

          if (listaRaw != null && listaRaw is List) {
            final lista = listaRaw;

            if (lista.isEmpty) break;

            final listaMapeada = lista.map((item) {
              // Mapeo flexible
              final id = item['id'] ?? item['ID'];
              final usrM = item['usr_m'] ?? item['USR_M'];
              final aplTec = item['apl_tec'] ?? item['APL_TEC'];

              // Campo OFF (opcional, por defecto false si no viene)
              dynamic offRaw = item['off'] ?? item['OFF'];
              bool offValue = false;
              if (offRaw == true ||
                  offRaw.toString().toLowerCase() == 'true' ||
                  offRaw == 1 ||
                  offRaw.toString() == '1') {
                offValue = true;
              }

              return {
                'id': id,
                'usr_m': usrM,
                'apl_tec': aplTec,
                'off': offValue,
              };
            }).toList();

            allUsrApl.addAll(listaMapeada);
            if (lista.length < pageSize) break;
            page++;
          } else {
            break;
          }
        } else {
          throw Exception('Error HTTP ${response.statusCode}');
        }
      }
      return allUsrApl;
    } catch (e) {
      throw Exception('Error al obtener USR_APL: $e');
    }
  }

  Future<bool> probarConexion() async {
    try {
      final url = _buildUrl('/ART_M');
      print('Probando conexión con: $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      print('Respuesta de prueba - Status: ${response.statusCode}');

      if (response.statusCode == 400) {
        print('Error 400 - Respuesta: ${response.body}');
      }

      return response.statusCode == 200;
    } catch (e) {
      print('Error en probarConexion: $e');
      return false;
    }
  }

  Future<int> crearCliente(Map<String, dynamic> cliente) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final clienteVelneo = {
        'nom_fis': cliente['nombre'],
        'nom_com': cliente['nombre_comercial'] ?? '',
        'cif': cliente['cif'] ?? '',
        'tlf': cliente['telefono'] ?? '',
        'eml': cliente['email'] ?? '',
        'dir': cliente['direccion'] ?? '',
        'es_clt': true,
        'emp': '1',
      };

      if (cliente['comercial_id'] != null) {
        clienteVelneo['cmr'] = cliente['comercial_id'];
      }

      //  IMPRIMIR LA URL PARA VERIFICARLA
      final urlDestino = _buildUrl('/ENT_M');
      print(
        '🚀 [DEBUG] URL API: $urlDestino',
      ); // <--- ESTA LÍNEA TE DIRÁ LA URL

      final request = await httpClient.postUrl(Uri.parse(urlDestino));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(clienteVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      //  IMPRIMIR LA RESPUESTA DEL SERVIDOR SI FALLA
      print('📥 [DEBUG] Status: ${response.statusCode}');
      if (response.statusCode != 200 && response.statusCode != 201) {
        print('📥 [DEBUG] Error Body: $stringData');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(stringData);
        if (data['id'] != null) return data['id'];
        if (data['ent_m'] != null && (data['ent_m'] as List).isNotEmpty) {
          return data['ent_m'][0]['id'];
        }
      }
      throw Exception(
        'Error creando cliente: ${response.statusCode} - $stringData',
      );
    } finally {
      httpClient.close();
    }
  }

  //  2. CREAR CONTACTO (CORREGIDO: Ignora SSL)
  Future<void> crearContacto(Map<String, dynamic> contacto) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final contactoVelneo = {
        'ent': contacto['cliente_id'],
        'ctt_clf': contacto['tipo'],
        'val': contacto['valor'],
        'name': contacto['nombre'] ?? '',
        'prn': contacto['es_principal'] == 1,
      };

      final request = await httpClient.postUrl(Uri.parse(_buildUrl('/CTT_M')));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(contactoVelneo));

      final response = await request.close();
      await response.drain();
    } catch (e) {
      print('⚠️ Error creando contacto: $e');
    } finally {
      httpClient.close();
    }
  }

  Future<void> crearDireccion(Map<String, dynamic> direccion) async {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final direccionVelneo = {
        'ent': direccion['cliente_id'],
        'dir': direccion['direccion'],
        'cps': direccion['cp'] ?? '',
        'loc': direccion['poblacion'] ?? '',
        'cmr': direccion['comercial_id'],
        'tip_de_dir': 1,
        'pai': 1,
        'name': direccion['direccion'],
        'off': false,
      };

      print(
        '🚀 [DEBUG DIR] Enviando JSON CORRECTO: ${json.encode(direccionVelneo)}',
      );

      final request = await httpClient.postUrl(Uri.parse(_buildUrl('/DIR_M')));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.write(json.encode(direccionVelneo));

      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();

      print('📥 [DEBUG DIR] Respuesta: ${response.statusCode} - $stringData');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Error al crear dirección: $stringData');
      }
    } catch (e) {
      print('❌ Error creando dirección: $e');
    } finally {
      httpClient.close();
    }
  }

  Future<Map<String, double>> obtenerConfiguracionIVA() async {
    try {
      final url = _buildUrlWithParams('/IMP_M', {'page[size]': '100'});
      print('📥 Descargando configuración de IVA desde $url');

      final response = await _getWithSSL(
        url,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        double general = 21.0;
        double reducido = 10.0;
        double superReducido = 4.0;
        double exento = 0.0;

        // Mapeo de la respuesta
        if (data['imp_m'] != null && data['imp_m'] is List) {
          for (var imp in data['imp_m']) {
            final codigo = imp['cod']?.toString() ?? '';
            final porcentaje = _convertirADouble(imp['por']);

            if (codigo == 'G') general = porcentaje;
            if (codigo == 'R') reducido = porcentaje;
            if (codigo == 'S') superReducido = porcentaje;
            if (codigo == 'X') exento = porcentaje;
          }
        }

        return {
          'iva_general': general,
          'iva_reducido': reducido,
          'iva_superreducido': superReducido,
          'iva_exento': exento,
        };
      }
      print('⚠️ Error descargando IVA: Status ${response.statusCode}');
      return {};
    } catch (e) {
      print('❌ Error en obtenerConfiguracionIVA: $e');
      return {};
    }
  }

  void dispose() {
    _client.close();
  }
}
