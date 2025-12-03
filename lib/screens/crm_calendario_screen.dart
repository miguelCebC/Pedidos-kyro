import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'detalle_visita_screen.dart';
import 'crear_visita_screen.dart';
import '../services/api_service.dart';

class CRMCalendarioScreen extends StatefulWidget {
  const CRMCalendarioScreen({super.key});

  @override
  State<CRMCalendarioScreen> createState() => _CRMCalendarioScreenState();
}

class _CRMCalendarioScreenState extends State<CRMCalendarioScreen>
    with AutomaticKeepAliveClientMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  final RangeSelectionMode _rangeSelectionMode =
      RangeSelectionMode.toggledOff; // 🟢 Por defecto selección simple
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  List<Map<String, dynamic>> _eventosVisibles =
      []; // 🟢 Lista dinámica (día o rango)
  int? _comercialId;
  String _comercialNombre = 'Sin comercial asignado';
  Map<DateTime, List<Map<String, dynamic>>> _eventos = {};
  List<Map<String, dynamic>> _eventosDelDia = [];
  bool _isLoading = true;
  bool _sincronizando = false;
  int _visitasPendientes = 0;

  final Map<int, String> _clientesNombres = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _cargarComercialYEventos();
    // 🟢 Sincronización automática
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarFondo());
  }

  // 🟢 MÉTODO NUEVO: Sincronización silenciosa
  Future<void> _sincronizarFondo() async {
    if (_sincronizando || _comercialId == null) return;
    setState(() => _sincronizando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('velneo_url');
      final apiKey = prefs.getString('velneo_api_key');
      if (url == null || apiKey == null) return;

      final api = VelneoAPIService(
        url.startsWith('http') ? url : 'https://$url',
        apiKey,
      );

      final db = DatabaseHelper.instance;
      await db.limpiarAgenda();
      final visitasComercial = await api.obtenerAgenda(_comercialId);
      await db.insertarAgendasLote(
        visitasComercial.cast<Map<String, dynamic>>(),
      );

      if (mounted) {
        _cargarEventos();
        print("✅ Agenda sincronizada en segundo plano");
      }
    } catch (e) {
      print("⚠️ Error en sync fondo agenda: $e");
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _cargarComercialYEventos() async {
    final prefs = await SharedPreferences.getInstance();
    final comercialId = prefs.getInt('comercial_id');
    final comercialNombre =
        prefs.getString('comercial_nombre') ?? 'Sin comercial asignado';

    setState(() {
      _comercialId = comercialId;
      _comercialNombre = comercialNombre;
    });

    if (comercialId != null) {
      await _cargarEventos();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarEventos() async {
    if (_comercialId == null) return;
    if (!_sincronizando) setState(() => _isLoading = true);

    final db = DatabaseHelper.instance;
    final agendas = await db.obtenerAgenda(_comercialId);
    final pendientes = await db.contarAgendasPendientes(_comercialId);

    final clientes = await db.obtenerClientes();
    _clientesNombres.clear();
    for (var cliente in clientes) {
      _clientesNombres[cliente['id'] as int] = cliente['nombre'] as String;
    }

    final Map<DateTime, List<Map<String, dynamic>>> eventosAgrupados = {};

    for (var agenda in agendas) {
      if (agenda['fecha_inicio'] != null &&
          agenda['fecha_inicio'].toString().isNotEmpty) {
        try {
          final fecha = DateTime.parse(agenda['fecha_inicio']);
          final fechaSoloDate = DateTime(fecha.year, fecha.month, fecha.day);

          if (eventosAgrupados[fechaSoloDate] == null) {
            eventosAgrupados[fechaSoloDate] = [];
          }
          eventosAgrupados[fechaSoloDate]!.add(agenda);
        } catch (e) {
          print('⚠️ Error parseando fecha: ${agenda['fecha_inicio']} - $e');
        }
      }
    }

    setState(() {
      _eventos = eventosAgrupados;
      _visitasPendientes = pendientes;
      _isLoading = false;
    });

    _cargarEventosDelDia(_selectedDay ?? _focusedDay);
  }

  void _cargarEventosDelDia(DateTime dia) {
    final diaKey = DateTime(dia.year, dia.month, dia.day);
    final eventos = _eventos[diaKey] ?? [];

    eventos.sort((a, b) {
      final horaA = a['hora_inicio']?.toString() ?? '';
      final horaB = b['hora_inicio']?.toString() ?? '';
      if (horaA.isEmpty) return 1;
      if (horaB.isEmpty) return -1;
      return horaA.compareTo(horaB);
    });

    setState(() {
      _eventosDelDia = eventos;
    });
  }

  List<Map<String, dynamic>> _getEventosParaDia(DateTime dia) {
    final diaKey = DateTime(dia.year, dia.month, dia.day);
    return _eventos[diaKey] ?? [];
  }

  String _formatearHora(String? horaStr) {
    if (horaStr == null || horaStr.isEmpty) return '--:--';
    try {
      if (horaStr.contains('T') || horaStr.contains('-')) {
        final dt = DateTime.parse(horaStr);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (horaStr.contains(':')) {
        final parts = horaStr.split(':');
        if (parts.length >= 2) {
          final hora = int.parse(parts[0]).toString().padLeft(2, '0');
          final minuto = int.parse(parts[1]).toString().padLeft(2, '0');
          return '$hora:$minuto';
        }
      }
      return '--:--';
    } catch (e) {
      return '--:--';
    }
  }

  String _obtenerNombreCliente(int? clienteId) {
    if (clienteId == null) return 'Sin cliente';
    return _clientesNombres[clienteId] ?? 'Cliente desconocido';
  }

  Future<void> _crearNuevaVisita() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CrearVisitaScreen(fechaSeleccionada: _selectedDay ?? _focusedDay),
      ),
    );

    if (resultado == true) {
      await _cargarEventos();
    }
  }

  void _cargarEventosRango(DateTime? start, DateTime? end) {
    if (start == null) return;

    final List<Map<String, dynamic>> eventosRango = [];
    final fechaFin = end ?? start; // Si end es null, es un rango de 1 día

    // Iteramos todas las fechas que tienen eventos
    _eventos.forEach((fecha, listaEventos) {
      // Normalizar fecha del mapa (ya viene normalizada, pero por seguridad)
      final fechaEvento = DateTime(fecha.year, fecha.month, fecha.day);
      final rangoInicio = DateTime(start.year, start.month, start.day);
      final rangoFin = DateTime(fechaFin.year, fechaFin.month, fechaFin.day);

      // Comprobar si está dentro del rango (inclusivo)
      if (fechaEvento.compareTo(rangoInicio) >= 0 &&
          fechaEvento.compareTo(rangoFin) <= 0) {
        eventosRango.addAll(listaEventos);
      }
    });

    _ordenarEventos(eventosRango);

    setState(() {
      _eventosVisibles = eventosRango;
    });
  }

  void _ordenarEventos(List<Map<String, dynamic>> lista) {
    lista.sort((a, b) {
      final fA = a['fecha_inicio'] ?? '';
      final fB = b['fecha_inicio'] ?? '';
      return fA.compareTo(fB);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _comercialId == null
          ? const Center(child: Text('No hay comercial asignado'))
          : Column(
              children: [
                TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: _getEventosParaDia,
                  locale: 'es_ES',
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarStyle: const CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Color(0xFF162846),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Color(0xFF032458),
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: BoxDecoration(
                      color: Color(0xFF032458),
                      shape: BoxShape.circle,
                    ),
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    _cargarEventosDelDia(selectedDay);
                  },
                  onFormatChanged: (format) =>
                      setState(() => _calendarFormat = format),
                  onPageChanged: (focusedDay) => _focusedDay = focusedDay,
                ),
                const Divider(height: 1),
                Expanded(
                  child: _eventosDelDia.isEmpty
                      ? const Center(
                          child: Text('No hay eventos para este día'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _eventosDelDia.length,
                          itemBuilder: (context, index) {
                            final evento = _eventosDelDia[index];
                            final hora = _formatearHora(evento['hora_inicio']);
                            final nombreCliente = _obtenerNombreCliente(
                              evento['cliente_id'],
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () async {
                                  final resultado = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          DetalleVisitaScreen(visita: evento),
                                    ),
                                  );
                                  if (mounted) await _cargarEventos();
                                },
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.white,
                                    child: Text(
                                      hora,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF032458),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    evento['asunto'] ?? 'Sin asunto',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(nombreCliente),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _comercialId != null
          ? FloatingActionButton(
              onPressed: _crearNuevaVisita,
              backgroundColor: const Color(0xFF032458),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
