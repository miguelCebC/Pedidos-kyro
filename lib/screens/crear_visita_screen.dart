import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../widgets/buscar_cliente_dialog.dart';
import 'debug_logs_screen.dart';

class CrearVisitaScreen extends StatefulWidget {
  final DateTime? fechaSeleccionada;

  const CrearVisitaScreen({super.key, this.fechaSeleccionada});

  @override
  State<CrearVisitaScreen> createState() => _CrearVisitaScreenState();
}

class _CrearVisitaScreenState extends State<CrearVisitaScreen> {
  final _asuntoController = TextEditingController();
  final _descripcionController = TextEditingController();
  List<Map<String, dynamic>> _direccionesFiltradas = [];
  int? _direccionSeleccionadaId;
  Map<String, dynamic>? _clienteSeleccionado;
  int? _comercialId;
  int? _tipoVisita;
  int? _campanaSeleccionada;
  DateTime? _fechaInicio;
  TimeOfDay _horaInicio = TimeOfDay.now();
  DateTime? _fechaFin;
  TimeOfDay? _horaFin;
  DateTime? _fechaProximaVisita;
  TimeOfDay? _horaProximaVisita;
  bool _todoDia = false;
  bool _isLoading = false;
  bool _guardando = false;

  // ==================================================
  // == 🟢 1. "VISITA CERRADA" AÑADIDO ==
  // Por defecto 'false' para que el usuario decida
  // ==================================================
  bool _visitaCerrada = false;

  List<Map<String, dynamic>> _tiposVisita = [];
  List<Map<String, dynamic>> _campanas = [];

  @override
  void initState() {
    super.initState();
    _fechaInicio = widget.fechaSeleccionada ?? DateTime.now();
    _fechaFin = _fechaInicio;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;

    final tiposVisita = await db.obtenerTiposVisita();
    final campanas = await db.obtenerCampanas();

    setState(() {
      _comercialId = prefs.getInt('comercial_id');
      _tiposVisita = tiposVisita;
      _campanas = campanas;

      if (_tiposVisita.isNotEmpty) {
        _tipoVisita = _tiposVisita.first['id'];
      }
    });
  }

  Future<void> _cargarDireccionesCliente(int clienteId) async {
    final db = DatabaseHelper.instance;
    final direcciones = await db.obtenerDirecciones(ent: clienteId);
    setState(() {
      _direccionesFiltradas = direcciones;
      _direccionSeleccionadaId = direcciones.isNotEmpty
          ? direcciones.first['id']
          : null;
    });
  }

  Future<void> _seleccionarCliente() async {
    final cliente = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const BuscarClienteDialog(),
    );
    if (cliente != null) {
      setState(() => _clienteSeleccionado = cliente);
      // 🟢 Llamada nueva
      _cargarDireccionesCliente(cliente['id']);
    }
  }

  Future<void> _seleccionarFecha(
    bool esInicio, {
    bool esProxima = false,
  }) async {
    // 🟢 Leer los días por defecto para la fecha inicial de "próxima visita"
    final prefs = await SharedPreferences.getInstance();
    final int diasDefecto = prefs.getInt('proxima_visita_dias') ?? 60;

    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio
          ? (_fechaInicio ?? DateTime.now())
          : (esProxima
                ? (_fechaProximaVisita ??
                      DateTime.now().add(Duration(days: diasDefecto)))
                : (_fechaFin ?? DateTime.now())),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'ES'),
    );

    if (fecha != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = fecha;
        } else if (esProxima) {
          _fechaProximaVisita = fecha;
        } else {
          _fechaFin = fecha;
        }
      });
    }
  }

  Future<void> _seleccionarHora(bool esInicio, {bool esProxima = false}) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: esInicio
          ? _horaInicio
          : (esProxima
                ? (_horaProximaVisita ?? const TimeOfDay(hour: 9, minute: 0))
                : (_horaFin ?? TimeOfDay.now())),
    );

    if (hora != null) {
      setState(() {
        if (esInicio) {
          _horaInicio = hora;
        } else if (esProxima) {
          _horaProximaVisita = hora;
        } else {
          _horaFin = hora;
        }
      });
    }
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'No seleccionada';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearHora(TimeOfDay? hora) {
    if (hora == null) return 'No seleccionada';
    return '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _guardarVisita() async {
    if (_guardando) {
      DebugLogger.log('⚠️ BLOQUEADO: Ya se está guardando una visita');
      return;
    }

    final ejecutionId = DateTime.now().millisecondsSinceEpoch;

    DebugLogger.log(
      '🚀 ========== INICIO _guardarVisita (ID: $ejecutionId) ==========',
    );

    if (_asuntoController.text.isEmpty) {
      DebugLogger.log('❌ Asunto vacío');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El asunto es obligatorio')));
      return;
    }
    if (_clienteSeleccionado == null) {
      DebugLogger.log('❌ Cliente no seleccionado');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }
    if (_comercialId == null) {
      DebugLogger.log('❌ Comercial no configurado');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay comercial asignado. Ve a Configuración'),
        ),
      );
      return;
    }
    if (_tipoVisita == null) {
      DebugLogger.log('❌ Tipo de visita no seleccionado');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un tipo de visita')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _guardando = true;
    });

    try {
      final fechaHoraInicio = DateTime(
        _fechaInicio!.year,
        _fechaInicio!.month,
        _fechaInicio!.day,
        _horaInicio.hour,
        _horaInicio.minute,
      );

      final String horaInicioStr =
          '${_horaInicio.hour.toString().padLeft(2, '0')}:${_horaInicio.minute.toString().padLeft(2, '0')}:00';
      DateTime fechaHoraFin;
      String horaFinStr;

      if (_fechaFin != null && _horaFin != null) {
        fechaHoraFin = DateTime(
          _fechaFin!.year,
          _fechaFin!.month,
          _fechaFin!.day,
          _horaFin!.hour,
          _horaFin!.minute,
        );
        horaFinStr =
            '${_horaFin!.hour.toString().padLeft(2, '0')}:${_horaFin!.minute.toString().padLeft(2, '0')}:00';
      } else {
        fechaHoraFin = fechaHoraInicio;
        horaFinStr = horaInicioStr;
      }

      String? fechaProximaStr;
      String? horaProximaStr;
      bool crearVisitaManualmente = false;

      // Siempre deshabilitamos el trigger de Velneo
      const bool noGenProVis = true;
      const bool noGenTri = true;

      if (_visitaCerrada) {
        // --- CASO 1: VISITA CERRADA ---
        DebugLogger.log(
          '📦 Lógica: Visita Cerrada. No se crea próxima visita.',
        );
        crearVisitaManualmente = false;
      } else {
        // --- CASO 2: VISITA ABIERTA (CREACIÓN MANUAL) ---
        DebugLogger.log(
          '📦 Lógica: Visita Abierta. App creará la próxima visita.',
        );
        crearVisitaManualmente = true; // Nuestra app lo hará

        // Calculamos la fecha/hora que usaremos para la creación manual
        if (_fechaProximaVisita != null && _horaProximaVisita != null) {
          DebugLogger.log('📦 ...usando fecha/hora manual para visita nueva');
          fechaProximaStr = _fechaProximaVisita!.toIso8601String().split(
            'T',
          )[0]; // "YYYY-MM-DD"
          horaProximaStr =
              '${_horaProximaVisita!.hour.toString().padLeft(2, '0')}:${_horaProximaVisita!.minute.toString().padLeft(2, '0')}:00'; // "HH:MM:SS"
        } else {
          // Si el usuario NO PUSO fecha/hora, las calculamos NOSOTROS
          DebugLogger.log('📦 ...calculando fecha/hora por defecto...');

          // 🟢 Leer los días de las Preferencias
          final prefs = await SharedPreferences.getInstance();
          final int diasDefecto = prefs.getInt('proxima_visita_dias') ?? 60;
          DebugLogger.log('📦 ...usando $diasDefecto días por defecto.');

          // 🟢 LÍNEA CORREGIDA: Usar _fechaInicio en lugar de DateTime.now()
          final fechaDefecto = _fechaInicio!.add(Duration(days: diasDefecto));

          fechaProximaStr = fechaDefecto.toIso8601String().split(
            'T',
          )[0]; // "YYYY-MM-DD"
          horaProximaStr = "09:00:00"; // Hora por defecto
        }
      }

      // ==================================================

      DebugLogger.log(
        '📅 Fecha-hora construida: ${fechaHoraInicio.toIso8601String()}',
      );

      final visitaData = {
        'cliente_id': _clienteSeleccionado!['id'],
        'tipo_visita': _tipoVisita,
        'asunto': _asuntoController.text,
        'comercial_id': _comercialId,
        'campana_id': _campanaSeleccionada ?? 0,
        'fecha_inicio': fechaHoraInicio.toIso8601String(),
        'hora_inicio': horaInicioStr,
        'fecha_fin': fechaHoraFin.toIso8601String(),
        'hora_fin': horaFinStr,
        'descripcion': _descripcionController.text,
        'todo_dia': _todoDia ? 1 : 0,
        'lead_id': 0,
        'presupuesto_id': 0,
        'generado': 1,
        // --- Campos de Próxima Visita (SIEMPRE DESACTIVADOS) ---
        'fecha_proxima_visita': null, // Se gestiona manualmente
        'hora_proxima_visita': null, // Se gestiona manualmente
        'no_gen_pro_vis': noGenProVis, // <-- true
        'no_gen_tri': noGenTri, // <-- true
        'direccion_id': _direccionSeleccionadaId ?? 0,
      };

      DebugLogger.log(
        '📦 Datos preparados: Cliente=${visitaData['cliente_id']}, Tipo=${visitaData['tipo_visita']}',
      );

      final prefs = await SharedPreferences.getInstance();
      String url = prefs.getString('velneo_url') ?? '';
      final String apiKey = prefs.getString('velneo_api_key') ?? '';

      if (url.isEmpty || apiKey.isEmpty) {
        throw Exception('Configura la URL y API Key en Configuración');
      }

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      DebugLogger.log('🌐 Conectando a: $url');

      final apiService = VelneoAPIService(url, apiKey);
      final db = DatabaseHelper.instance;

      DebugLogger.log(
        '📤 ===== LLAMANDO A crearVisitaAgenda (Visita Actual) =====',
      );

      final resultado = await apiService
          .crearVisitaAgenda(visitaData)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              DebugLogger.log('❌ TIMEOUT (ID: $ejecutionId)');
              throw Exception('Timeout: El servidor tardó más de 45 segundos');
            },
          );

      DebugLogger.log(
        '📥 ===== RESPUESTA crearVisitaAgenda (ID: $ejecutionId) =====',
      );

      final idVelneo = resultado['id'];
      DebugLogger.log('✅ Visita actual creada con ID: $idVelneo');

      if (idVelneo == null) {
        throw Exception('No se recibió ID de Velneo para la visita actual');
      }

      DebugLogger.log('💾 Guardando visita actual #$idVelneo en BD local...');

      final visitaLocal = Map<String, dynamic>.from(visitaData);
      visitaLocal['id'] = idVelneo;
      visitaLocal['sincronizado'] = 1;

      try {
        await db.insertarAgendasLote([visitaLocal]);
        DebugLogger.log('✅ Visita actual #$idVelneo guardada en BD local');
      } catch (e) {
        DebugLogger.log('❌ Error al guardar visita local: $e');
      }

      // [DENTRO DE LA FUNCIÓN _guardarVisita]
      // ... después de guardar la visita actual ...

      // --- PASO 2: CREACIÓN MANUAL DE LA PRÓXIMA VISITA ---
      if (crearVisitaManualmente) {
        DebugLogger.log('🚀 ===== INICIO Creación Manual Próxima Visita =====');

        // Preparamos la *nueva* visita
        // Parseamos la hora y fecha calculadas
        final dtProxima = DateTime.parse(fechaProximaStr!);
        final todProxima = TimeOfDay(
          hour: int.parse(horaProximaStr!.split(':')[0]),
          minute: int.parse(horaProximaStr.split(':')[1]),
        );

        final fechaHoraInicioProxima = DateTime(
          dtProxima.year,
          dtProxima.month,
          dtProxima.day,
          todProxima.hour,
          todProxima.minute,
        );

        // 🟢 INICIO DE CAMBIOS
        final visitaNuevaData = {
          'cliente_id': _clienteSeleccionado!['id'],
          'tipo_visita': _tipoVisita,
          // 1. Usar el mismo asunto que la visita actual
          'asunto': _asuntoController.text,
          'comercial_id': _comercialId,
          'campana_id': _campanaSeleccionada ?? 0,
          'fecha_inicio': fechaHoraInicioProxima.toIso8601String(),
          'hora_inicio': horaProximaStr,
          'fecha_fin': fechaHoraInicioProxima.toIso8601String(),
          'hora_fin': horaProximaStr,
          'descripcion': '',
          'todo_dia': _todoDia ? 1 : 0,
          'lead_id': 0,
          'presupuesto_id': 0,
          'generado': 1,

          // 2. Desactivar los triggers para ESTA visita
          'fecha_proxima_visita': null,
          'hora_proxima_visita': null,
          'no_gen_pro_vis': true, // 🟢 Evita que esta visita genere otra
          'no_gen_tri': true, // 🟢 Evita que esta visita genere otra
        };
        // 🟢 FIN DE CAMBIOS

        DebugLogger.log(
          '📤 ===== LLAMANDO A crearVisitaAgenda (Visita Nueva) =====',
        );
        final resultadoNuevaVisita = await apiService.crearVisitaAgenda(
          visitaNuevaData,
        );
        DebugLogger.log(
          '📥 ===== RESPUESTA crearVisitaAgenda (Visita Nueva) =====',
        );

        // ... resto de la función ...

        final idVelneoNueva = resultadoNuevaVisita['id'];
        if (idVelneoNueva != null) {
          DebugLogger.log('✅ Visita nueva creada con ID: $idVelneoNueva');
          // Guardar también esta en la BD local
          final visitaLocalNueva = Map<String, dynamic>.from(visitaNuevaData);
          visitaLocalNueva['id'] = idVelneoNueva;
          visitaLocalNueva['sincronizado'] = 1;
          await db.insertarAgendasLote([visitaLocalNueva]);
          DebugLogger.log('💾 Visita nueva guardada en BD local');
        } else {
          DebugLogger.log(
            '⚠️ Error: La creación manual de la próxima visita no devolvió ID',
          );
          // No lanzamos error fatal, pero avisamos
          throw Exception(
            'Se guardó la visita actual, pero falló la creación de la próxima visita.',
          );
        }
      }

      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      if (!mounted) return;

      DebugLogger.log('✅ ========== FIN _guardarVisita ==========');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Visita #$idVelneo creada ${crearVisitaManualmente ? "y próxima visita generada" : ""}',
          ),
          backgroundColor: const Color(0xFF032458),
          action: SnackBarAction(
            label: 'Ver Logs',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DebugLogsScreen(),
                ),
              );
            },
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e, stackTrace) {
      setState(() {
        _isLoading = false;
        _guardando = false;
      });

      DebugLogger.log('❌ ERROR CRÍTICO: $e');
      DebugLogger.log('❌ STACKTRACE: $stackTrace');
      DebugLogger.log('❌ ========== FIN _guardarVisita (CON ERROR) ==========');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error al crear visita'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugLogsScreen(),
                    ),
                  );
                },
                child: const Text('Ver Logs Completos'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
      appBar: AppBar(title: const Text('Nueva Visita'), actions: [
   
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Creando visita...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _asuntoController,
                  decoration: const InputDecoration(
                    labelText: 'Asunto *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
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

                    trailing: const Icon(Icons.search),
                    onTap: _seleccionarCliente,
                  ),
                ),
                const SizedBox(height: 16),
                if (_tiposVisita.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: _tipoVisita,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Visita *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    isExpanded: true,
                    items: _tiposVisita.map((tipo) {
                      return DropdownMenuItem<int>(
                        value: tipo['id'],
                        child: Text(
                          tipo['nombre'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _tipoVisita = value);
                    },
                  )
                else
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No hay tipos de visita. Sincroniza los datos en Configuración.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _campanaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Campaña Comercial (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.campaign),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sin campaña'),
                    ),
                    ..._campanas.map((campana) {
                      return DropdownMenuItem<int?>(
                        value: campana['id'],
                        child: Text(
                          campana['nombre'],
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() => _campanaSeleccionada = value);
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Dirección (opcional)',
                        border: InputBorder.none,
                        icon: Icon(Icons.location_on, color: Colors.grey),
                      ),
                      initialValue: _direccionSeleccionadaId,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Sin dirección'),
                        ),
                        ..._direccionesFiltradas.map((dir) {
                          return DropdownMenuItem<int?>(
                            value: dir['id'],
                            child: Text(
                              dir['direccion'],
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _direccionSeleccionadaId = value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Todo el día'),
                  value: _todoDia,
                  onChanged: (value) {
                    setState(() => _todoDia = value);
                  },
                  activeThumbColor: const Color(0xFF032458),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Fecha Inicio'),
                        subtitle: Text(_formatearFecha(_fechaInicio)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _seleccionarFecha(true),
                      ),
                      if (!_todoDia)
                        ListTile(
                          title: const Text('Hora Inicio'),
                          subtitle: Text(_formatearHora(_horaInicio)),
                          trailing: const Icon(Icons.access_time),
                          onTap: () => _seleccionarHora(true),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Fecha Fin (opcional)'),
                        subtitle: Text(_formatearFecha(_fechaFin)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _seleccionarFecha(false),
                      ),
                      if (!_todoDia)
                        ListTile(
                          title: const Text('Hora Fin (opcional)'),
                          subtitle: Text(_formatearHora(_horaFin)),
                          trailing: const Icon(Icons.access_time),
                          onTap: () => _seleccionarHora(false),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ==================================================
                // == 🟢 4. INTERRUPTOR "VISITA CERRADA" AÑADIDO ==
                // ==================================================
                SwitchListTile(
                  title: const Text('Visita Cerrada'),
                  subtitle: Text(
                    _visitaCerrada
                        ? 'No se generará una próxima visita.'
                        : 'Se generará una próxima visita (automática o manual).',
                  ),
                  value: _visitaCerrada,
                  onChanged: (value) {
                    setState(() => _visitaCerrada = value);
                  },
                  activeThumbColor: const Color(0xFF032458),
                ),
                const SizedBox(height: 16),

                // ==================================================
                // == 🟢 5. PRÓXIMA VISITA (AHORA CONDICIONAL) ==
                // ==================================================
                if (!_visitaCerrada)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Fecha Próxima Visita (opcional)'),
                          subtitle: Text(_formatearFecha(_fechaProximaVisita)),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () =>
                              _seleccionarFecha(false, esProxima: true),
                        ),
                        if (!_todoDia)
                          ListTile(
                            title: const Text('Hora Próxima Visita (opcional)'),
                            subtitle: Text(_formatearHora(_horaProximaVisita)),
                            trailing: const Icon(Icons.access_time),
                            onTap: () =>
                                _seleccionarHora(false, esProxima: true),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            // 🟢 5. Texto actualizado
                            'Si dejas estos campos vacíos, se programará una visita automática según los días de configuración.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ==================================================
                const SizedBox(height: 16),

                // Descripción
                TextField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Notas',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 24),

                // Botón guardar
                ElevatedButton.icon(
                  onPressed: _isLoading || _guardando ? null : _guardarVisita,
                  icon: const Icon(Icons.save),
                  label: const Text('CREAR VISITA'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF032458),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'La visita se intentará sincronizar automáticamente con Velneo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _asuntoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }
}
