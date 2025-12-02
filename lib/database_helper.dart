import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;
import 'screens/debug_logs_screen.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('velneo_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dbFilePath = path_helper.join(dbPath, filePath);

    return await openDatabase(dbFilePath, version: 7, onCreate: _createDB);
  }

  // ❌ ELIMINADO EL MÉTODO _onUpgrade para forzar el uso de _createDB (reinstalación)

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        email TEXT,
        telefono TEXT,
        direccion TEXT,
        cmr INTEGER,         
        cif TEXT,            
        nom_fis TEXT,        
        nom_com TEXT         
      )
    ''');
    // ... (Resto de tablas existentes igual que antes: articulos, usuarios, series, etc.)
    await db.execute('''
      CREATE TABLE articulos (
        id INTEGER PRIMARY KEY,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        precio REAL NOT NULL,
        stock INTEGER DEFAULT 0,
        img TEXT,  
        familia TEXT,        
        proveedor_id INTEGER, 
        codigo_barras TEXT,    
        off INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE usuarios (id INTEGER PRIMARY KEY, name TEXT, ent INTEGER)
    ''');
    await db.execute('''
      CREATE TABLE series (id INTEGER PRIMARY KEY, nombre TEXT, tipo TEXT)
    ''');
    await db.execute('''
      CREATE TABLE comerciales (id INTEGER PRIMARY KEY, nombre TEXT, email TEXT, telefono TEXT, direccion TEXT)
    ''');
    await db.execute('''
      CREATE TABLE provincias (id INTEGER PRIMARY KEY, nombre TEXT, prefijo_cp TEXT, pais INTEGER)
    ''');
    await db.execute('''
      CREATE TABLE zonas_tecnicas (id INTEGER PRIMARY KEY, nombre TEXT, observaciones TEXT, tecnico_id INTEGER)
    ''');
    await db.execute('''
      CREATE TABLE poblaciones (id INTEGER PRIMARY KEY, nombre TEXT, km INTEGER, zona_tecnica_id INTEGER, codigo_postal TEXT)
    ''');
    await db.execute('''
      CREATE TABLE campanas_comerciales (id INTEGER PRIMARY KEY, nombre TEXT, fecha_inicio TEXT, fecha_fin TEXT, sector INTEGER, provincia_id INTEGER, poblacion_id INTEGER)
    ''');
    await db.execute('''
      CREATE TABLE tipos_visita (id INTEGER PRIMARY KEY, nombre TEXT)
    ''');
    await db.execute('''
      CREATE TABLE leads (id INTEGER PRIMARY KEY, nombre TEXT, fecha_alta TEXT, campana_id INTEGER, cliente_id INTEGER, asunto TEXT, descripcion TEXT, comercial_id INTEGER, estado TEXT, fecha TEXT, enviado INTEGER DEFAULT 0, agendado INTEGER DEFAULT 0, agenda_id INTEGER)
    ''');
    await db.execute('''
      CREATE TABLE contactos (id INTEGER PRIMARY KEY, cliente_id INTEGER, tipo TEXT, nombre TEXT, valor TEXT, es_principal INTEGER DEFAULT 0)
    ''');
    await db.execute('''
      CREATE TABLE direcciones (id INTEGER PRIMARY KEY, ent INTEGER, direccion TEXT)
    ''');
    await db.execute('''
      CREATE TABLE agenda (id INTEGER PRIMARY KEY, nombre TEXT, cliente_id INTEGER, direccion_id INTEGER, tipo_visita INTEGER, asunto TEXT, comercial_id INTEGER, campana_id INTEGER, fecha_inicio TEXT, hora_inicio TEXT, fecha_fin TEXT, hora_fin TEXT, fecha_proxima_visita TEXT, hora_proxima_visita TEXT, descripcion TEXT, todo_dia INTEGER DEFAULT 0, lead_id INTEGER, presupuesto_id INTEGER, generado INTEGER DEFAULT 1, sincronizado INTEGER DEFAULT 0, no_gen_pro_vis INTEGER DEFAULT 0, no_gen_tri INTEGER DEFAULT 0)
    ''');
    await db.execute('''
      CREATE TABLE pedidos (id INTEGER PRIMARY KEY, cliente_id INTEGER, usuario_id INTEGER, cmr INTEGER, serie_id INTEGER, fecha TEXT, numero TEXT, num_doc INTEGER, fecha_entrega TEXT, forma_pago INTEGER, direccion_entrega_id INTEGER, estado TEXT, con_kyr INTEGER DEFAULT 0, observaciones TEXT, total REAL, base_total REAL, 
        iva_total REAL, sincronizado INTEGER DEFAULT 0)
    ''');
    await db.execute('''
      CREATE TABLE lineas_pedido (id INTEGER PRIMARY KEY AUTOINCREMENT, pedido_id INTEGER, articulo_id INTEGER, cantidad REAL, precio REAL, por_descuento REAL DEFAULT 0, dto1 REAL DEFAULT 0, dto2 REAL DEFAULT 0, dto3 REAL DEFAULT 0, por_iva REAL DEFAULT 0, tipo_iva TEXT DEFAULT 'G')
    ''');
    await db.execute('''
      CREATE TABLE formas_pago (id INTEGER PRIMARY KEY, nombre TEXT)
    ''');

    // TABLA PRESUPUESTOS ACTUALIZADA
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presupuestos (
        id INTEGER PRIMARY KEY,
        cliente_id INTEGER,
        comercial_id INTEGER,
        usuario_id INTEGER,
        serie_id INTEGER,
        fecha TEXT,
        numero TEXT,
        estado TEXT,
        observaciones TEXT,
        total REAL,
        base_total REAL,
        iva_total REAL,
        fecha_validez TEXT,
        fecha_aceptacion TEXT,
        sincronizado INTEGER DEFAULT 0,
        direccion_entrega_id INTEGER,
        forma_pago INTEGER -- 🟢 Esta columna ya está aquí
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lineas_presupuesto (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        presupuesto_id INTEGER,
        articulo_id INTEGER,
        cantidad REAL,
        precio REAL,
        por_descuento REAL DEFAULT 0,
        por_iva REAL DEFAULT 0,
        tipo_iva TEXT DEFAULT 'G',
        dto1 REAL DEFAULT 0,
        dto2 REAL DEFAULT 0,
        dto3 REAL DEFAULT 0
      )
    ''');
    // ... otras tablas (tarifas, familias, config_local, movimientos)
    await db.execute(
      'CREATE TABLE IF NOT EXISTS tarifas_cliente (id INTEGER PRIMARY KEY, cliente_id INTEGER, articulo_id INTEGER, precio REAL, por_descuento REAL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS familias (id INTEGER PRIMARY KEY, nombre TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS tarifas_articulo (id INTEGER PRIMARY KEY, articulo_id INTEGER, nombre_tarifa TEXT, precio REAL, por_descuento REAL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS config_local (clave TEXT PRIMARY KEY, valor TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS movimientos (id INTEGER PRIMARY KEY, cliente_id INTEGER, articulo_id INTEGER, fecha TEXT, num_doc TEXT, entrada REAL, salida REAL, precio REAL)',
    );
  }

  Future<void> insertarMovimientosLote(
    List<Map<String, dynamic>> movimientos,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var mov in movimientos) {
      batch.insert(
        'movimientos',
        mov,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<String> obtenerNombreSerie(int serieId) async {
    final db = await database;
    final res = await db.query(
      'series',
      columns: ['nombre'],
      where: 'id = ?',
      whereArgs: [serieId],
    );
    if (res.isNotEmpty) return res.first['nombre'] as String;
    return 'Serie $serieId';
  }

  Future<void> limpiarMovimientos() async {
    final db = await database;
    await db.delete('movimientos');
  }

  // Consulta con JOIN para sacar datos del artículo automáticamente
  Future<List<Map<String, dynamic>>> obtenerMovimientosPorCliente(
    int clienteId,
  ) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT m.*, a.codigo as codigo_articulo, a.nombre as nombre_articulo
      FROM movimientos m
      LEFT JOIN articulos a ON m.articulo_id = a.id
      WHERE m.cliente_id = ?
      ORDER BY m.fecha DESC
    ''',
      [clienteId],
    );
  }

  Future<void> insertarSeriesLote(List<Map<String, dynamic>> series) async {
    final db = await database;
    final batch = db.batch();

    for (var serie in series) {
      batch.insert(
        'series',
        serie,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // En lib/database_helper.dart
  Future<void> insertarFamiliasLote(List<Map<String, dynamic>> familias) async {
    final db = await database;
    final batch = db.batch();
    for (var f in familias) {
      batch.insert('familias', f, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> limpiarFamilias() async {
    final db = await database;
    await db.delete('familias');
  }

  Future<void> insertarContactosLote(
    List<Map<String, dynamic>> contactos,
  ) async {
    final db = await database;
    final batch = db.batch();

    // Borramos contactos anteriores para evitar duplicados al resincronizar
    await db.delete('contactos');

    for (var c in contactos) {
      batch.insert(
        'contactos',
        c,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 🟢 TRUCO: Si es principal (prn=1), actualizamos la ficha del cliente
      // para que salga bien en la rejilla del catálogo sin hacer queries lentas
      if (c['es_principal'] == 1) {
        if (c['tipo'] == 'T') {
          // Teléfono
          batch.rawUpdate('UPDATE clientes SET telefono = ? WHERE id = ?', [
            c['valor'],
            c['cliente_id'],
          ]);
        } else if (c['tipo'] == 'E') {
          // Email
          batch.rawUpdate('UPDATE clientes SET email = ? WHERE id = ?', [
            c['valor'],
            c['cliente_id'],
          ]);
        }
      }
    }
    await batch.commit(noResult: true);
  }

  // 2. Obtener todos los contactos de un cliente (Teléfonos y Emails)
  Future<List<Map<String, dynamic>>> obtenerContactosPorCliente(
    int clienteId,
  ) async {
    final db = await database;
    return await db.query(
      'contactos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'es_principal DESC, tipo ASC', // Principales primero
    );
  }

  // 3. Obtener direcciones de un cliente (Ya tenías la tabla, añadimos el getter filtrado)
  Future<List<Map<String, dynamic>>> obtenerDireccionesPorCliente(
    int clienteId,
  ) async {
    final db = await database;
    // Asumiendo que la tabla 'direcciones' tiene un campo 'ent' o 'cliente_id'
    // Si tu tabla direcciones usa 'ent', cambia 'cliente_id' por 'ent' abajo
    return await db.query(
      'direcciones',
      where: 'ent = ?',
      whereArgs: [clienteId],
    );
  }
  // En lib/database_helper.dart

  // 🟢 MÉTODO MEJORADO: Busca la familia siendo flexible con el tipo de dato
  Future<String> obtenerNombreFamilia(String? familiaIdStr) async {
    if (familiaIdStr == null || familiaIdStr.isEmpty || familiaIdStr == '0') {
      return 'Sin familia';
    }

    final db = await database;

    try {
      // 1. Intentamos buscar asumiendo que el ID es numérico (lo más común en vERP)
      final idInt = int.tryParse(familiaIdStr);

      if (idInt != null) {
        final result = await db.query(
          'familias',
          columns: ['nombre'],
          where: 'id = ?',
          whereArgs: [idInt],
          limit: 1,
        );
        if (result.isNotEmpty) {
          return result.first['nombre'] as String;
        }
      }

      // 2. Si falla o no es número, intentamos buscarlo como Texto (por si acaso)
      final resultText = await db.query(
        'familias',
        columns: ['nombre'],
        where:
            'id = ?', // SQLite convierte tipos automáticamente a veces, pero esto fuerza string
        whereArgs: [familiaIdStr],
        limit: 1,
      );

      if (resultText.isNotEmpty) {
        return resultText.first['nombre'] as String;
      }

      return 'Familia no encontrada ($familiaIdStr)';
    } catch (e) {
      print('Error buscando familia: $e');
      return 'Error datos';
    }
  }

  Future<List<Map<String, dynamic>>> obtenerArticulosPaginados({
    String? busqueda,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;

    // 🟢 FILTRO LOCAL: Solo artículos activos
    String whereClause =
        'nombre IS NOT NULL AND nombre != "" AND (off IS NULL OR off = 0)';
    List<dynamic> args = [];

    if (busqueda != null && busqueda.isNotEmpty) {
      whereClause += ' AND (nombre LIKE ? OR codigo LIKE ?)';
      args.add('%$busqueda%');
      args.add('%$busqueda%');
    }

    return await db.query(
      'articulos',
      columns: [
        'id',
        'codigo',
        'nombre',
        'descripcion',
        'precio',
        'stock',
        'familia',
        'proveedor_id',
        'codigo_barras',
        'off',
      ],
      where: whereClause,
      whereArgs: args,
      orderBy: 'nombre',
      limit: limit,
      offset: offset,
    );
  }

  Future<String> obtenerNombreCliente(int id) async {
    final db = await database;
    final result = await db.query(
      'clientes',
      columns: ['nombre'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['nombre'] as String;
    }
    return 'Proveedor no encontrado';
  }

  // Método para obtener las tarifas específicas de un artículo
  Future<List<Map<String, dynamic>>> obtenerTarifasPorArticulo(
    int articuloId,
  ) async {
    final db = await database;
    // Asegúrate de que la tabla 'tarifas_articulo' exista en tu DB
    return await db.query(
      'tarifas_articulo',
      where: 'articulo_id = ?',
      whereArgs: [articuloId],
      orderBy: 'precio DESC', // Opcional: ordenar por precio
    );
  }

  Future<List<Map<String, dynamic>>> obtenerSeries({String? tipo}) async {
    final db = await database;
    if (tipo != null) {
      return await db.query(
        'series',
        where: 'tipo = ?',
        whereArgs: [tipo],
        orderBy: 'nombre',
      );
    }
    return await db.query('series', orderBy: 'nombre');
  }

  Future<void> limpiarSeries() async {
    final db = await database;
    await db.delete('series');
  }

  Future<void> guardarContrasenaLocal(String contrasena) async {
    final db = await database;
    await db.insert('config_local', {
      'clave': 'contrasena_local',
      'valor': contrasena,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> obtenerContrasenaLocal() async {
    final db = await database;
    final resultado = await db.query(
      'config_local',
      where: 'clave = ?',
      whereArgs: ['contrasena_local'],
    );
    return resultado.isNotEmpty ? resultado.first['valor'] as String? : null;
  }

  Future<bool> existeContrasenaLocal() async {
    final contrasena = await obtenerContrasenaLocal();
    return contrasena != null && contrasena.isNotEmpty;
  }

  Future<int> contarAgendasPendientes([int? comercialId]) async {
    final db = await database;
    if (comercialId != null) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM agenda WHERE sincronizado = 0 AND comercial_id = ?',
        [comercialId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM agenda WHERE sincronizado = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> insertarPresupuesto(Map<String, dynamic> presupuesto) async {
    final db = await database;
    return await db.insert(
      'presupuestos',
      presupuesto,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertarLineaPresupuesto(Map<String, dynamic> linea) async {
    final db = await database;
    return await db.insert('lineas_presupuesto', linea);
  }

  Future<List<Map<String, dynamic>>> obtenerPresupuestos() async {
    final db = await database;
    return await db.query('presupuestos', orderBy: 'fecha DESC');
  }

  Future<List<Map<String, dynamic>>> obtenerLineasPresupuesto(
    int presupuestoId,
  ) async {
    final db = await database;
    return await db.query(
      'lineas_presupuesto',
      where: 'presupuesto_id = ?',
      whereArgs: [presupuestoId],
    );
  }

  Future<void> insertarPresupuestosLote(
    List<Map<String, dynamic>> presupuestos,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var presupuesto in presupuestos) {
      batch.insert(
        'presupuestos',
        presupuesto,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> limpiarPresupuestos() async {
    final db = await database;
    await db.delete('lineas_presupuesto');
    await db.delete('presupuestos');
  }

  Future<int> actualizarPresupuestoSincronizado(
    int presupuestoId,
    int sincronizado,
  ) async {
    final db = await database;
    return await db.update(
      'presupuestos',
      {'sincronizado': sincronizado},
      where: 'id = ?',
      whereArgs: [presupuestoId],
    );
  }

  Future<void> insertarUsuariosLote(List<Map<String, dynamic>> usuarios) async {
    final db = await database;
    final batch = db.batch();
    for (var usuario in usuarios) {
      batch.insert('usuarios', {
        'id': usuario['id'],
        'name': usuario['name'],
        'ent': usuario['ent'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertarCliente(Map<String, dynamic> cliente) async {
    final db = await database;
    return await db.insert(
      'clientes',
      cliente,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerClientes({
    String? busqueda,
    int? comercialId,
  }) async {
    final db = await database;

    String whereClause = '1=1';
    List<dynamic> args = [];

    // Filtro de búsqueda
    if (busqueda != null && busqueda.isNotEmpty) {
      whereClause += ' AND (nombre LIKE ? OR id LIKE ?)';
      args.add('%$busqueda%');
      args.add('%$busqueda%');
    }

    // 🟢 Filtro por Comercial
    if (comercialId != null) {
      whereClause += ' AND cmr = ?';
      args.add(comercialId);
    }

    return await db.query(
      'clientes',
      where: whereClause,
      whereArgs: args,
      orderBy: 'nombre',
    );
  }

  Future<int> actualizarPedidoSincronizado(
    int pedidoId,
    int sincronizado,
  ) async {
    final db = await database;
    return await db.update(
      'pedidos',
      {'sincronizado': sincronizado},
      where: 'id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<void> insertarArticulosLote(
    List<Map<String, dynamic>> articulos,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var articulo in articulos) {
      batch.insert(
        'articulos',
        articulo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertarClientesLote(List<Map<String, dynamic>> clientes) async {
    final db = await database;
    final batch = db.batch();
    for (var cliente in clientes) {
      batch.insert(
        'clientes',
        cliente,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertarComercialesLote(
    List<Map<String, dynamic>> comerciales,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var comercial in comerciales) {
      batch.insert(
        'comerciales',
        comercial,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerComerciales() async {
    final db = await database;
    return await db.query('comerciales', orderBy: 'nombre');
  }

  Future<void> insertarProvinciasLote(
    List<Map<String, dynamic>> provincias,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var provincia in provincias) {
      batch.insert(
        'provincias',
        provincia,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
  // ... dentro de DatabaseHelper ...

  // Insertar un solo contacto
  Future<int> insertarContacto(Map<String, dynamic> contacto) async {
    final db = await database;
    return await db.insert(
      'contactos',
      contacto,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Insertar una sola dirección
  Future<int> insertarDireccion(Map<String, dynamic> direccion) async {
    final db = await database;
    return await db.insert(
      'direcciones',
      direccion,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> limpiarProvincias() async {
    final db = await database;
    await db.delete('provincias');
  }

  Future<void> insertarZonasTecnicasLote(
    List<Map<String, dynamic>> zonas,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var zona in zonas) {
      batch.insert(
        'zonas_tecnicas',
        zona,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerZonasTecnicas() async {
    final db = await database;
    return await db.query('zonas_tecnicas', orderBy: 'nombre');
  }

  Future<void> limpiarZonasTecnicas() async {
    final db = await database;
    await db.delete('zonas_tecnicas');
  }

  Future<void> insertarPoblacionesLote(
    List<Map<String, dynamic>> poblaciones,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var poblacion in poblaciones) {
      batch.insert(
        'poblaciones',
        poblacion,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerPoblaciones([
    String? busqueda,
  ]) async {
    final db = await database;
    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'poblaciones',
        where: 'nombre LIKE ? OR codigo_postal LIKE ?',
        whereArgs: ['%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('poblaciones', orderBy: 'nombre');
  }

  Future<void> insertarCampanasLote(List<Map<String, dynamic>> campanas) async {
    final db = await database;
    final batch = db.batch();
    for (var campana in campanas) {
      batch.insert(
        'campanas_comerciales',
        campana,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerCampanas() async {
    final db = await database;
    return await db.query('campanas_comerciales', orderBy: 'fecha_inicio DESC');
  }

  Future<void> limpiarCampanas() async {
    final db = await database;
    await db.delete('campanas_comerciales');
  }

  Future<void> insertarTiposVisitaLote(List<Map<String, dynamic>> tipos) async {
    final db = await database;
    final batch = db.batch();
    for (var tipo in tipos) {
      batch.insert(
        'tipos_visita',
        tipo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerTiposVisita() async {
    final db = await database;
    return await db.query('tipos_visita', orderBy: 'id');
  }

  Future<void> limpiarTiposVisita() async {
    final db = await database;
    await db.delete('tipos_visita');
  }

  Future<void> insertarLeadsLote(List<Map<String, dynamic>> leads) async {
    final db = await database;
    final batch = db.batch();
    for (var lead in leads) {
      batch.insert('leads', lead, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerLeads([int? comercialId]) async {
    final db = await database;
    if (comercialId != null) {
      return await db.query(
        'leads',
        where: 'comercial_id = ?',
        whereArgs: [comercialId],
        orderBy: 'fecha DESC',
      );
    }
    return await db.query('leads', orderBy: 'fecha DESC');
  }

  Future<void> limpiarLeads() async {
    final db = await database;
    await db.delete('leads');
  }

  Future<Map<String, dynamic>?> obtenerComercialPorId(int id) async {
    final db = await database;
    final result = await db.query(
      'comerciales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> obtenerUsuarioPorComercial(
    int comercialId,
  ) async {
    final db = await database;
    final result = await db.query(
      'usuarios',
      where: 'ent = ?',
      whereArgs: [comercialId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> insertarAgendasLote(List<Map<String, dynamic>> agendas) async {
    final db = await database;
    final batch = db.batch();
    DebugLogger.log('💾 Insertando ${agendas.length} agendas en BD local...');
    for (var agenda in agendas) {
      batch.insert(
        'agenda',
        agenda,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    DebugLogger.log('✅ ${agendas.length} agendas insertadas en BD');
  }

  Future<List<Map<String, dynamic>>> obtenerAgenda([int? comercialId]) async {
    final db = await database;
    if (comercialId != null) {
      return await db.query(
        'agenda',
        where: 'comercial_id = ?',
        whereArgs: [comercialId],
        orderBy: 'fecha_inicio DESC',
      );
    }
    return await db.query('agenda', orderBy: 'fecha_inicio DESC');
  }

  Future<void> limpiarAgenda() async {
    final db = await database;
    await db.delete('agenda');
  }

  Future<int> eliminarVisita(int id) async {
    final db = await database;
    return await db.delete('agenda', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> limpiarPoblaciones() async {
    final db = await database;
    await db.delete('poblaciones');
  }

  Future<void> limpiarArticulos() async {
    final db = await database;
    await db.delete('articulos');
  }

  Future<void> limpiarClientes() async {
    final db = await database;
    await db.delete('clientes');
  }

  Future<void> limpiarComerciales() async {
    final db = await database;
    await db.delete('comerciales');
  }

  Future<int> insertarArticulo(Map<String, dynamic> articulo) async {
    final db = await database;
    return await db.insert(
      'articulos',
      articulo,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerArticulos([
    String? busqueda,
  ]) async {
    final db = await database;

    // 🟢 FILTRO LOCAL
    String baseWhere =
        'nombre IS NOT NULL AND nombre != "" AND (off IS NULL OR off = 0)';

    if (busqueda != null && busqueda.isNotEmpty) {
      return await db.query(
        'articulos',
        where: '$baseWhere AND (nombre LIKE ? OR codigo LIKE ? OR id LIKE ?)',
        whereArgs: ['%$busqueda%', '%$busqueda%', '%$busqueda%'],
      );
    }
    return await db.query('articulos', where: baseWhere, orderBy: 'nombre');
  }

  Future<int> insertarUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.insert(
      'usuarios',
      usuario,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertarPedido(Map<String, dynamic> pedido) async {
    final db = await database;
    return await db.insert(
      'pedidos',
      pedido,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertarLineaPedido(Map<String, dynamic> linea) async {
    final db = await database;
    // Asegurar que los campos existen en el mapa o poner 0
    if (!linea.containsKey('dto1')) linea['dto1'] = 0.0;
    if (!linea.containsKey('dto2')) linea['dto2'] = 0.0;
    if (!linea.containsKey('dto3')) linea['dto3'] = 0.0;
    return await db.insert('lineas_pedido', linea);
  }

  Future<List<Map<String, dynamic>>> obtenerPedidos() async {
    final db = await database;
    return await db.query('pedidos', orderBy: 'fecha DESC');
  }

  Future<List<Map<String, dynamic>>> obtenerLineasPedido(int pedidoId) async {
    final db = await database;
    return await db.query(
      'lineas_pedido',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<void> insertarPedidosLote(List<Map<String, dynamic>> pedidos) async {
    final db = await database;
    final batch = db.batch();
    for (var pedido in pedidos) {
      batch.insert(
        'pedidos',
        pedido,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertarLineasPedidoLote(
    List<Map<String, dynamic>> lineas,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var linea in lineas) {
      // Asegurar campos
      if (!linea.containsKey('dto1')) linea['dto1'] = 0.0;
      if (!linea.containsKey('dto2')) linea['dto2'] = 0.0;
      if (!linea.containsKey('dto3')) linea['dto3'] = 0.0;

      batch.insert(
        'lineas_pedido',
        linea,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertarLineasPresupuestoLote(
    List<Map<String, dynamic>> lineas,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var linea in lineas) {
      batch.insert(
        'lineas_presupuesto',
        linea,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<String> obtenerDireccionPorId(int id) async {
    final db = await database;
    final res = await db.query('direcciones', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first['direccion'] as String;
    return 'Dirección desconocida';
  }

  Future<int> actualizarPedido(int pedidoId, Map<String, dynamic> datos) async {
    final db = await database;
    return await db.update(
      'pedidos',
      datos,
      where: 'id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<int> eliminarLineasPedido(int pedidoId) async {
    final db = await database;
    return await db.delete(
      'lineas_pedido',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<int> actualizarPresupuesto(
    int presupuestoId,
    Map<String, dynamic> datos,
  ) async {
    final db = await database;
    return await db.update(
      'presupuestos',
      datos,
      where: 'id = ?',
      whereArgs: [presupuestoId],
    );
  }

  Future<int> eliminarLineasPresupuesto(int presupuestoId) async {
    final db = await database;
    return await db.delete(
      'lineas_presupuesto',
      where: 'presupuesto_id = ?',
      whereArgs: [presupuestoId],
    );
  }

  Future<void> limpiarBaseDatos() async {
    final db = await database;
    await db.delete('lineas_pedido');
    await db.delete('pedidos');
    await db.delete('agenda');
    await db.delete('leads');
    await db.delete('campanas_comerciales');
    await db.delete('tipos_visita');
    await db.delete('articulos');
    await db.delete('clientes');
    await db.delete('comerciales');
    await db.delete('usuarios');
    await db.delete('poblaciones');
    await db.delete('zonas_tecnicas');
    await db.delete('provincias');
    await db.delete('series');
  }

  Future<void> limpiarPedidos() async {
    final db = await database;
    await db.delete('lineas_pedido');
    await db.delete('pedidos');
  }

  Future<void> insertarTarifasClienteLote(
    List<Map<String, dynamic>> tarifas,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var tarifa in tarifas) {
      batch.insert(
        'tarifas_cliente',
        tarifa,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertarTarifasArticuloLote(
    List<Map<String, dynamic>> tarifas,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var tarifa in tarifas) {
      batch.insert(
        'tarifas_articulo',
        tarifa,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> limpiarTarifasCliente() async {
    final db = await database;
    await db.delete('tarifas_cliente');
  }

  Future<void> limpiarTarifasArticulo() async {
    final db = await database;
    await db.delete('tarifas_articulo');
  }

  Future<Map<String, dynamic>?> obtenerTarifaCliente(
    int clienteId,
    int articuloId,
  ) async {
    final db = await database;
    final result = await db.query(
      'tarifas_cliente',
      where: 'cliente_id = ? AND articulo_id = ?',
      whereArgs: [clienteId, articuloId],
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<Map<String, dynamic>?> obtenerTarifaArticulo(int articuloId) async {
    final db = await database;
    final result = await db.query(
      'tarifas_articulo',
      where: 'articulo_id = ?',
      whereArgs: [articuloId],
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<void> insertarDireccionesLote(
    List<Map<String, dynamic>> direcciones,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var dir in direcciones) {
      batch.insert(
        'direcciones',
        dir,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Obtener direcciones (filtradas por entidad 'ent' si se pasa el ID)
  Future<List<Map<String, dynamic>>> obtenerDirecciones({int? ent}) async {
    final db = await database;
    if (ent != null) {
      return await db.query(
        'direcciones',
        where: 'ent = ?',
        whereArgs: [ent],
        orderBy: 'direccion',
      );
    }
    return await db.query('direcciones', orderBy: 'direccion');
  }

  Future<void> limpiarDirecciones() async {
    final db = await database;
    await db.delete('direcciones');
  }

  Future<Map<String, double>> obtenerPrecioYDescuento(
    int clienteId,
    int articuloId,
    double pvpBase,
  ) async {
    final tarifaCliente = await obtenerTarifaCliente(clienteId, articuloId);
    if (tarifaCliente != null) {
      return {
        'precio': tarifaCliente['precio'] as double,
        'descuento': tarifaCliente['por_descuento'] as double,
      };
    }
    final tarifaArticulo = await obtenerTarifaArticulo(articuloId);
    if (tarifaArticulo != null) {
      return {
        'precio': tarifaArticulo['precio'] as double,
        'descuento': tarifaArticulo['por_descuento'] as double,
      };
    }
    return {'precio': pvpBase, 'descuento': 0.0};
  }
  // En lib/database_helper.dart

  // 🟢 1. Obtener Clientes Paginados (Para el catálogo)
  Future<List<Map<String, dynamic>>> obtenerClientesPaginados({
    String? busqueda,
    int? comercialId,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;

    String whereClause = '1=1';
    List<dynamic> args = [];

    // Filtro por Comercial
    if (comercialId != null) {
      whereClause += ' AND cmr = ?';
      args.add(comercialId);
    }

    // Filtro por Búsqueda (Nombre, Email, Teléfono, NIF)
    if (busqueda != null && busqueda.isNotEmpty) {
      whereClause +=
          ' AND (nombre LIKE ? OR email LIKE ? OR telefono LIKE ? OR cif LIKE ?)';
      args.add('%$busqueda%');
      args.add('%$busqueda%');
      args.add('%$busqueda%');
      args.add('%$busqueda%');
    }

    return await db.query(
      'clientes',
      where: whereClause,
      whereArgs: args,
      orderBy: 'nombre',
      limit: limit,
      offset: offset,
    );
  }

  // 🟢 2. Obtener Tarifas Especiales de un Cliente (con nombre del artículo)
  Future<List<Map<String, dynamic>>> obtenerTarifasPorCliente(
    int clienteId,
  ) async {
    final db = await database;
    // Hacemos un JOIN para saber el nombre del artículo al que aplica la tarifa
    return await db.rawQuery(
      '''
      SELECT t.*, a.nombre as nombre_articulo, a.codigo as codigo_articulo
      FROM tarifas_cliente t
      INNER JOIN articulos a ON t.articulo_id = a.id
      WHERE t.cliente_id = ?
      ORDER BY a.nombre
    ''',
      [clienteId],
    );
  }

  Future<void> insertarFormasPagoLote(List<Map<String, dynamic>> list) async {
    final db = await database;
    final batch = db.batch();
    // Borramos lo anterior para tener una copia limpia del servidor
    await db.delete('formas_pago');
    for (var item in list) {
      batch.insert(
        'formas_pago',
        item,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerFormasPago() async {
    final db = await database;
    return await db.query('formas_pago', orderBy: 'nombre');
  }

  Future<String> obtenerNombreFormaPago(int id) async {
    final db = await database;
    final res = await db.query(
      'formas_pago',
      columns: ['nombre'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (res.isNotEmpty) return res.first['nombre'] as String;
    return 'Forma Pago $id';
  }

  Future<int> actualizarImagenArticulo(int id, String imagenBase64) async {
    final db = await database;
    return await db.update(
      'Articulos',
      {'img': imagenBase64},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> eliminarContrasenaLocal() async {
    final db = await database;
    await db.delete(
      'config_local',
      where: 'clave = ?',
      whereArgs: ['contrasena_local'],
    );
  }
}
