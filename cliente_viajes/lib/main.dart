import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestión de Viajes - Flutter Frontend',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ViajesScreen(),
    );
  }
}

class ViajesScreen extends StatefulWidget {
  const ViajesScreen({super.key});

  @override
  State<ViajesScreen> createState() => _ViajesScreenState();
}

class _ViajesScreenState extends State<ViajesScreen> {
  // URLs de redirección correspondientes al Servicio A
  final String loginUrl = 'http://192.168.0.103:8081/index.html';
  final String dashboardUrl = 'http://192.168.0.103:8081/dashboard.html';
  final String baseUrl = 'http://192.168.0.103:3002';

  String? usuarioFinal;
  String? tokenFinal;
  bool sesionValida = false;
  bool isLoading = true;

  List<dynamic> ciudades = [];
  List<dynamic> viajes = [];
  int? ciudadSeleccionadaId;

  final TextEditingController _fechaController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _validarYCargarSesion();
  }

  // ============================================
  // 1. VALIDAR ACCESO (usuario + token)
  // ============================================
  void _validarYCargarSesion() {
    final uri = Uri.base;
    final String? usuarioUrl = uri.queryParameters['usuario'];
    String? tokenUrl = uri.queryParameters['token'];

    if (tokenUrl != null) {
      tokenUrl = tokenUrl.replaceAll('"', '').trim();
    }

    // Buscamos si hay sesión en el navegador (sessionStorage)
    final String? usuarioSesion = html.window.sessionStorage['usuario'];
    final String? tokenSesion = html.window.sessionStorage['token'];

    if (tokenUrl != null && usuarioUrl != null && tokenUrl.isNotEmpty && usuarioUrl.isNotEmpty) {
      // ✅ Viene desde el Servicio A con credenciales en la URL
      usuarioFinal = usuarioUrl;
      tokenFinal = tokenUrl;

      html.window.sessionStorage['usuario'] = usuarioFinal!;
      html.window.sessionStorage['token'] = tokenFinal!;

      print('✅ Acceso concedido desde el Servicio A: $usuarioFinal');
      setState(() => sesionValida = true);

      // Limpiamos la URL para no dejar el token expuesto
      html.window.history.replaceState({}, '', html.window.location.pathname);

      _cargarDatosIniciales();
    } else if (tokenSesion != null && usuarioSesion != null && tokenSesion.isNotEmpty && usuarioSesion.isNotEmpty) {
      // ✅ Ya tenía sesión activa en esta pestaña
      usuarioFinal = usuarioSesion;
      tokenFinal = tokenSesion;
      print('✅ Sesión recuperada: $usuarioFinal');
      setState(() => sesionValida = true);

      _cargarDatosIniciales();
    } else {
      // ❌ NO hay credenciales → Redirigimos al login del Servicio A
      print('❌ Acceso denegado: redirigiendo al login...');
      setState(() {
        sesionValida = false;
        isLoading = false;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        html.window.location.replace('$loginUrl?logout=true');
      });
    }
  }

  Future<void> _cargarDatosIniciales() async {
    setState(() => isLoading = true);
    await Future.wait([
      cargarCiudades(),
      cargarViajes(),
    ]);
    setState(() => isLoading = false);
  }

  // ============================================
  // 2.2 FUNCIÓN DE CERRAR SESIÓN (LOGOUT)
  // ============================================
  void _cerrarSesion() {
    print('👋 Cerrando sesión desde el Servicio B...');
    html.window.sessionStorage.clear();
    html.window.location.replace('$loginUrl?logout=true');
  }

  // ============================================
  // 2.3 FUNCIÓN DE VOLVER AL DASHBOARD
  // ============================================
  void _volverAlDashboard() {
    print('⬅️ Volviendo al dashboard del Servicio A...');
    html.window.location.href = dashboardUrl;
  }

  // ============================================
  // 2.4 CARGAR CIUDADES
  // ============================================
  Future<void> cargarCiudades() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/ciudades'),
        headers: {'Authorization': 'Bearer $tokenFinal'},
      );

      if (response.statusCode == 200) {
        setState(() {
          ciudades = jsonDecode(response.body);
        });
        print('✅ ${ciudades.length} ciudades cargadas');
      } else {
        print('❌ Error al cargar ciudades: HTTP ${response.statusCode}');
      }
    } catch (err) {
      print('❌ Error cargando ciudades: $err');
    }
  }

  // ============================================
  // 2.5 CARGAR VIAJES DEL USUARIO
  // ============================================
  Future<void> cargarViajes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/viajes/$usuarioFinal'),
        headers: {'Authorization': 'Bearer $tokenFinal'},
      );

      if (response.statusCode == 200) {
        setState(() {
          viajes = jsonDecode(response.body);
        });
        print('✅ ${viajes.length} viajes cargados para $usuarioFinal');
      } else {
        print('❌ Error al cargar viajes: HTTP ${response.statusCode}');
      }
    } catch (err) {
      print('❌ Error cargando viajes: $err');
    }
  }

  // ============================================
  // 2.6 REGISTRAR NUEVO VIAJE
  // ============================================
  Future<void> registrarViaje() async {
    if (ciudadSeleccionadaId == null || _fechaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor seleccione una ciudad y una fecha')),
      );
      return;
    }

    final data = {
      'ciudad_id': ciudadSeleccionadaId,
      'fecha_viaje': _fechaController.text,
      'motivo': _motivoController.text,
      'usuario_uuid': usuarioFinal,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/viajes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $tokenFinal',
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Viaje registrado con éxito!')),
        );
        _motivoController.clear();
        _fechaController.clear();
        setState(() => ciudadSeleccionadaId = null);
        cargarViajes();
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${errorData['error'] ?? 'Desconocido'}')),
        );
      }
    } catch (err) {
      print('❌ Error al enviar el formulario: $err');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión al registrar el viaje')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sesionValida) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Panel de Gestión de Viajes - Usuario: ${usuarioFinal ?? ""}'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          // Botón Volver al Dashboard
          TextButton.icon(
            onPressed: _volverAlDashboard,
            icon: const Icon(Icons.dashboard, color: Colors.white),
            label: const Text('Volver al Dashboard', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
          // Botón Cerrar Sesión
          TextButton.icon(
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Formulario de Registro
                  Expanded(
                    flex: 1,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Registrar Nuevo Viaje',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                  labelText: 'Seleccione Ciudad',
                                  border: OutlineInputBorder()),
                              value: ciudadSeleccionadaId,
                              items: ciudades.map<DropdownMenuItem<int>>((c) {
                                return DropdownMenuItem<int>(
                                  value: c['id'],
                                  child: Text('${c['nombre']} (${c['pais']})'),
                                );
                              }).toList(),
                              onChanged: (val) =>
                                  setState(() => ciudadSeleccionadaId = val),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _fechaController,
                              decoration: const InputDecoration(
                                  labelText: 'Fecha del viaje',
                                  hintText: 'YYYY-MM-DD',
                                  border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _motivoController,
                              decoration: const InputDecoration(
                                  labelText: 'Motivo del viaje',
                                  border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white),
                                onPressed: registrarViaje,
                                child: const Text('Guardar Viaje',
                                    style: TextStyle(fontSize: 16)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Tabla de Viajes Registrados
                  Expanded(
                    flex: 2,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Mis Viajes Registrados',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            Expanded(
                              child: viajes.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'No hay viajes registrados para este usuario.'))
                                  : ListView.builder(
                                      itemCount: viajes.length,
                                      itemBuilder: (context, index) {
                                        final v = viajes[index];
                                        final fechaMostrar = v['fecha_viaje'] != null
                                            ? v['fecha_viaje'].toString().split('T')[0]
                                            : 'N/A';
                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 6),
                                          child: ListTile(
                                            leading: const Icon(
                                                Icons.flight_takeoff,
                                                color: Colors.blue),
                                            title: Text(
                                                '${v['ciudad']} - ${v['pais']}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight
                                                        .bold)),
                                            subtitle: Text(
                                                'Fecha: $fechaMostrar\nMotivo: ${v['motivo'] ?? '-'}'),
                                            isThreeLine: true,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}