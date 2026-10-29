// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ServicioBScreen(),
    );
  }
}

class ServicioBScreen extends StatefulWidget {
  const ServicioBScreen({super.key});

  @override
  State<ServicioBScreen> createState() => _ServicioBScreenState();
}

class _ServicioBScreenState extends State<ServicioBScreen> {
  // 1. Configuración de URLs del Servicio Central (Servicio A)
  final String loginUrl = 'http://192.168.0.103:8081/index.html';
  final String dashboardUrl = 'http://192.168.0.103:8081/dashboard.html';
  final String baseUrl = 'http://192.168.0.103:8083';

  String? usuarioFinal;
  String? tokenFinal;
  bool sesionValida = false;
  bool cargando = true;

  // Reportes del usuario de la sesión
  List<Map<String, dynamic>> reportes = [];
  bool cargandoReportes = false;
  String? errorReportes;

  @override
  void initState() {
    super.initState();
    _validarYCargarSesion();
  }

  // 2. Método de validación (se llama en el initState)
  void _validarYCargarSesion() {
    final uri = Uri.base;
    final String? usuarioUrl = uri.queryParameters['usuario'];
    String? tokenUrl = uri.queryParameters['token'];

    if (tokenUrl != null) tokenUrl = tokenUrl.replaceAll('"', '').trim();

    final String? usuarioSesion = html.window.sessionStorage['usuario'];
    final String? tokenSesion = html.window.sessionStorage['token'];

    // Caso A: Llega por URL desde el Servicio A
    if (tokenUrl != null &&
        usuarioUrl != null &&
        tokenUrl.isNotEmpty &&
        usuarioUrl.isNotEmpty) {
      usuarioFinal = usuarioUrl;
      tokenFinal = tokenUrl;

      html.window.sessionStorage['usuario'] = usuarioFinal!;
      html.window.sessionStorage['token'] = tokenFinal!;

      // Limpia los parámetros de la URL manteniendo solo la ruta
      html.window.history.replaceState({}, '', uri.path);

      setState(() {
        sesionValida = true;
        cargando = false;
      });
      _cargarReportes();
    }
    // Caso B: Ya existe sesión en sessionStorage
    else if (tokenSesion != null &&
        usuarioSesion != null &&
        tokenSesion.isNotEmpty &&
        usuarioSesion.isNotEmpty) {
      usuarioFinal = usuarioSesion;
      tokenFinal = tokenSesion;

      setState(() {
        sesionValida = true;
        cargando = false;
      });
      _cargarReportes();
    }
    // Caso C: No hay token ni sesión activa
    else {
      setState(() {
        sesionValida = false;
        cargando = false;
      });
      html.window.location.replace('$loginUrl?logout=true');
    }
  }

  // Consulta los reportes del usuario de la sesión
  Future<void> _cargarReportes() async {
    if (usuarioFinal == null) return;

    setState(() {
      cargandoReportes = true;
      errorReportes = null;
    });

    try {
      final resp = await http.get(
        Uri.parse(
          '$baseUrl/api/reportes/usuario/${Uri.encodeComponent(usuarioFinal!)}',
        ),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final lista = (data['reportes'] as List<dynamic>? ?? []);
        reportes = lista
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        errorReportes = 'No se pudieron cargar tus reportes.';
      }
    } catch (e) {
      errorReportes = 'Error de conexión con el servidor.';
    } finally {
      if (mounted) setState(() => cargandoReportes = false);
    }
  }

  // 👇 NUEVO: muestra un SnackBar en la pantalla principal
  void _mostrarMensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  // 👇 NUEVO: cambia el estado de un reporte
  // accion: 'cancelar' o 'encontrado'
  // PATCH /api/reportes/:id/cancelar
  // PATCH /api/reportes/:id/encontrado
  Future<void> _cambiarEstado(dynamic id, String accion) async {
    try {
      final resp = await http.patch(
        Uri.parse('$baseUrl/api/reportes/$id/$accion'),
      );
      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200) {
        _mostrarMensaje(data['mensaje'] ?? 'Estado actualizado con éxito.');
        await _cargarReportes(); // refresca la lista
      } else {
        _mostrarMensaje(
          data['error'] ?? 'No se pudo actualizar el reporte.',
          error: true,
        );
      }
    } catch (e) {
      _mostrarMensaje('Error de conexión con el servidor.', error: true);
    }
  }

  // 3. Salida y navegación
  void _cerrarSesion() {
    html.window.sessionStorage.clear();
    html.window.location.replace('$loginUrl?logout=true');
  }

  void _volverAlDashboard() {
    html.window.location.href = dashboardUrl;
  }

  // Al volver del formulario se recargan los reportes
  Future<void> _abrirFormularioReporte() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ReporteFormScreen(baseUrl: baseUrl, usuario: usuarioFinal!),
      ),
    );
    if (mounted) _cargarReportes();
  }

  void _abrirTodosReportes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TodosReportesScreen(baseUrl: baseUrl, usuario: usuarioFinal!),
      ),
    );
  }

  // 👇 NUEVO: abre la tabla de avistamientos de un reporte propio
  void _verAvistamientos(Map<String, dynamic> reporte) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvistamientosReporteScreen(
          baseUrl: baseUrl,
          idReporte: reporte['id'],
          nombreAnimal: (reporte['nombre_animal'] ?? '').toString(),
        ),
      ),
    );
  }

  Widget _construirListaReportes() {
    if (cargandoReportes) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorReportes != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            errorReportes!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (reportes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Aún no has registrado reportes.')),
      );
    }

    // 👇 CAMBIO: se pasan los callbacks para mostrar los botones
    return Column(
      children: reportes
          .map(
            (r) => ReporteCard(
              reporte: r,
              onCancelar: () => _cambiarEstado(r['id'], 'cancelar'),
              onEncontrado: () => _cambiarEstado(r['id'], 'encontrado'),
              onVerAvistamientos: () => _verAvistamientos(r), // 👈 NUEVO
            ),
          )
          .toList(),
    );
  }

  // 4. Interfaz gráfica
  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!sesionValida) {
      return const Scaffold(
        body: Center(child: Text('Redirigiendo al login...')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Usuario: ${usuarioFinal ?? ""}',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: MediaQuery.of(context).size.width < 600
            ? [
                IconButton(
                  tooltip: 'Volver al Dashboard',
                  onPressed: _volverAlDashboard,
                  icon: const Icon(Icons.dashboard),
                ),
                IconButton(
                  tooltip: 'Cerrar Sesión',
                  onPressed: _cerrarSesion,
                  icon: const Icon(Icons.logout),
                ),
                const SizedBox(width: 8),
              ]
            : [
                TextButton.icon(
                  onPressed: _volverAlDashboard,
                  icon: const Icon(Icons.dashboard, color: Colors.white),
                  label: const Text(
                    'Volver al Dashboard',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _cerrarSesion,
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text(
                    'Cerrar Sesión',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
              ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Text(
                  '¡Bienvenido al Servicio B!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _abrirFormularioReporte,
                      icon: const Icon(Icons.pets),
                      label: const Text('Registrar reporte'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _abrirTodosReportes,
                      icon: const Icon(Icons.list_alt),
                      label: const Text('Todos los reportes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mis reportes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Recargar',
                      onPressed: cargandoReportes ? null : _cargarReportes,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _construirListaReportes(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// FORMULARIO: Registrar reporte
// GET  /api/especies/nombres  (llena el combobox)
// POST /api/upload            (sube la foto)
// POST /api/reportes
// ============================================
class ReporteFormScreen extends StatefulWidget {
  final String baseUrl;
  final String usuario;

  const ReporteFormScreen({
    super.key,
    required this.baseUrl,
    required this.usuario,
  });

  @override
  State<ReporteFormScreen> createState() => _ReporteFormScreenState();
}

class _ReporteFormScreenState extends State<ReporteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreAnimalCtrl = TextEditingController();
  final _descAnimalCtrl = TextEditingController();
  final _descLugarCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _urlFotoCtrl = TextEditingController();

  List<String> _especies = [];
  String? _especieSeleccionada;

  bool _cargandoEspecies = true;
  bool _enviando = false;
  bool _subiendoFoto = false;

  @override
  void initState() {
    super.initState();
    _cargarEspecies();
  }

  @override
  void dispose() {
    _nombreAnimalCtrl.dispose();
    _descAnimalCtrl.dispose();
    _descLugarCtrl.dispose();
    _fechaCtrl.dispose();
    _urlFotoCtrl.dispose();
    super.dispose();
  }

  // Llena el combobox con los nombres de las especies
  Future<void> _cargarEspecies() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.baseUrl}/api/especies/nombres'),
      );

      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        _especies = data.map((e) => e.toString()).toList();
      } else {
        _mostrarMensaje('No se pudieron cargar las especies.', error: true);
      }
    } catch (e) {
      _mostrarMensaje('Error de conexión al cargar las especies.', error: true);
    } finally {
      if (mounted) setState(() => _cargandoEspecies = false);
    }
  }

  Future<void> _seleccionarFecha() async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: hoy,
      firstDate: DateTime(2000),
      lastDate: hoy,
    );

    if (fecha != null) {
      final mes = fecha.month.toString().padLeft(2, '0');
      final dia = fecha.day.toString().padLeft(2, '0');
      setState(() => _fechaCtrl.text = '${fecha.year}-$mes-$dia');
    }
  }

  // Abre la galería, sube la imagen al backend y guarda la ruta devuelta
  Future<void> _seleccionarYSubirFoto() async {
    try {
      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (resultado == null || resultado.files.isEmpty) return;

      final archivo = resultado.files.first;
      final bytes = archivo.bytes;

      if (bytes == null) {
        _mostrarMensaje('No se pudo leer la imagen.', error: true);
        return;
      }

      setState(() => _subiendoFoto = true);

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/api/upload'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('foto', bytes, filename: archivo.name),
      );

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      final data = jsonDecode(resp.body);

      if (resp.statusCode == 201) {
        // Ahora la URL ya viene completa desde Cloudinary (https://res.cloudinary.com/...)
        setState(() => _urlFotoCtrl.text = data['url'].toString());
      } else {
        _mostrarMensaje(
          data['error'] ?? 'No se pudo subir la foto.',
          error: true,
        );
      }
    } catch (e) {
      _mostrarMensaje('Error al subir la foto.', error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);

    try {
      final resp = await http.post(
        Uri.parse('${widget.baseUrl}/api/reportes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre_usuario': widget.usuario,
          'nombre_animal': _nombreAnimalCtrl.text.trim(),
          'nombre_especie': _especieSeleccionada,
          'descripcion_animal': _descAnimalCtrl.text.trim(),
          'descripcion_lugar': _descLugarCtrl.text.trim(),
          'fecha_perdio': _fechaCtrl.text.trim(),
          'url_foto': _urlFotoCtrl.text.trim(),
        }),
      );

      final data = jsonDecode(resp.body);

      if (resp.statusCode == 201) {
        _mostrarMensaje(data['mensaje'] ?? 'Se registró el reporte con éxito.');
        if (mounted) Navigator.of(context).pop();
      } else {
        _mostrarMensaje(
          data['error'] ?? 'No se pudo registrar el reporte.',
          error: true,
        );
      }
    } catch (e) {
      _mostrarMensaje('Error de conexión con el servidor.', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarMensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  String? _obligatorio(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar reporte'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    initialValue: widget.usuario,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nombreAnimalCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del animal',
                      border: OutlineInputBorder(),
                    ),
                    validator: _obligatorio,
                  ),
                  const SizedBox(height: 16),
                  _cargandoEspecies
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value: _especieSeleccionada,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Especie',
                            border: OutlineInputBorder(),
                          ),
                          items: _especies
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _especieSeleccionada = v),
                          validator: (v) =>
                              v == null ? 'Selecciona una especie' : null,
                        ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descAnimalCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción del animal',
                      border: OutlineInputBorder(),
                    ),
                    validator: _obligatorio,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descLugarCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción del lugar',
                      border: OutlineInputBorder(),
                    ),
                    validator: _obligatorio,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fechaCtrl,
                    readOnly: true,
                    onTap: _seleccionarFecha,
                    decoration: const InputDecoration(
                      labelText: 'Fecha en que se perdió',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: _obligatorio,
                  ),
                  const SizedBox(height: 16),
                  // Campo de la foto + botón a la derecha
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _urlFotoCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Foto',
                            hintText: 'Selecciona una foto de tu galería',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Sube una foto'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _subiendoFoto
                              ? null
                              : _seleccionarYSubirFoto,
                          icon: _subiendoFoto
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.photo_library),
                          label: Text(
                            _subiendoFoto ? 'Subiendo...' : 'Galería',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_urlFotoCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _urlFotoCtrl.text,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Text('No se pudo mostrar la vista previa.'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_enviando || _subiendoFoto) ? null : _enviar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Registrar reporte'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// PANTALLA: Reportes activos de otros usuarios
// GET /api/reportes?usuario=<usuario>
// ============================================
class TodosReportesScreen extends StatefulWidget {
  final String baseUrl;
  final String usuario;

  const TodosReportesScreen({
    super.key,
    required this.baseUrl,
    required this.usuario,
  });

  @override
  State<TodosReportesScreen> createState() => _TodosReportesScreenState();
}

class _TodosReportesScreenState extends State<TodosReportesScreen> {
  List<Map<String, dynamic>> _reportes = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Se envía el usuario como query parameter
      final uri = Uri.parse('${widget.baseUrl}/api/reportes')
          .replace(queryParameters: {'usuario': widget.usuario});

      final resp = await http.get(uri);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final lista = (data['reportes'] as List<dynamic>? ?? []);
        _reportes = lista
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (resp.statusCode == 400) {
        // Mensaje de validación del backend
        final data = jsonDecode(resp.body);
        _error = data['error'] ?? 'Solicitud inválida.';
      } else {
        _error = 'No se pudieron cargar los reportes.';
      }
    } catch (e) {
      _error = 'Error de conexión con el servidor.';
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // 👇 NUEVO: abre el formulario de avistamiento y recarga al volver
  Future<void> _abrirAvistamiento(Map<String, dynamic> reporte) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvistamientoFormScreen(
          baseUrl: widget.baseUrl,
          usuario: widget.usuario,
          idReporte: reporte['id'],
          nombreAnimal: (reporte['nombre_animal'] ?? '').toString(),
        ),
      ),
    );
    if (mounted) _cargarReportes();
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargarReportes,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_reportes.isEmpty) {
      return const Center(
        child: Text('No hay reportes activos de otros usuarios.'),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _reportes.length,
          // 👇 CAMBIO: solo el botón de avistamiento (sin Cancelado/Encontrado)
          itemBuilder: (_, i) => ReporteCard(
            reporte: _reportes[i],
            onAvistamiento: () => _abrirAvistamiento(_reportes[i]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes de otros usuarios'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargarReportes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _construirContenido(),
    );
  }
}

// ============================================
// FORMULARIO: Registrar avistamiento
// POST /api/avistamientos
// ============================================
class AvistamientoFormScreen extends StatefulWidget {
  final String baseUrl;
  final String usuario;
  final dynamic idReporte;
  final String nombreAnimal;

  const AvistamientoFormScreen({
    super.key,
    required this.baseUrl,
    required this.usuario,
    required this.idReporte,
    required this.nombreAnimal,
  });

  @override
  State<AvistamientoFormScreen> createState() => _AvistamientoFormScreenState();
}

class _AvistamientoFormScreenState extends State<AvistamientoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();

  bool _enviando = false;

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _fechaCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: hoy,
      firstDate: DateTime(2000),
      lastDate: hoy,
    );

    if (fecha != null) {
      final mes = fecha.month.toString().padLeft(2, '0');
      final dia = fecha.day.toString().padLeft(2, '0');
      setState(() => _fechaCtrl.text = '${fecha.year}-$mes-$dia');
    }
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);

    try {
      final resp = await http.post(
        Uri.parse('${widget.baseUrl}/api/avistamientos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre_usuario': widget.usuario,
          'descripcion': _descripcionCtrl.text.trim(),
          'id_reporte': widget.idReporte,
          'fecha_encontro': _fechaCtrl.text.trim(),
        }),
      );

      final data = jsonDecode(resp.body);

      if (resp.statusCode == 201) {
        _mostrarMensaje(
          data['mensaje'] ?? 'Se registró el avistamiento con éxito.',
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        _mostrarMensaje(
          data['error'] ?? 'No se pudo registrar el avistamiento.',
          error: true,
        );
      }
    } catch (e) {
      _mostrarMensaje('Error de conexión con el servidor.', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarMensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  String? _obligatorio(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar avistamiento'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    initialValue: widget.usuario,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.nombreAnimal,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Animal reportado',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descripcionCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descripción del avistamiento',
                      hintText: 'Dónde y cómo lo viste',
                      border: OutlineInputBorder(),
                    ),
                    validator: _obligatorio,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fechaCtrl,
                    readOnly: true,
                    onTap: _seleccionarFecha,
                    decoration: const InputDecoration(
                      labelText: 'Fecha en que lo viste',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: _obligatorio,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _enviando ? null : _enviar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Registrar avistamiento'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// PANTALLA: Avistamientos de un reporte (tabla)
// GET /api/reportes/:id/detalle
// ============================================
class AvistamientosReporteScreen extends StatefulWidget {
  final String baseUrl;
  final dynamic idReporte;
  final String nombreAnimal;

  const AvistamientosReporteScreen({
    super.key,
    required this.baseUrl,
    required this.idReporte,
    required this.nombreAnimal,
  });

  @override
  State<AvistamientosReporteScreen> createState() =>
      _AvistamientosReporteScreenState();
}

class _AvistamientosReporteScreenState
    extends State<AvistamientosReporteScreen> {
  List<Map<String, dynamic>> _avistamientos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarAvistamientos();
  }

  Future<void> _cargarAvistamientos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final resp = await http.get(
        Uri.parse('${widget.baseUrl}/api/reportes/${widget.idReporte}/detalle'),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final lista = (data['avistamientos'] as List<dynamic>? ?? []);

        // El SP usa LEFT JOIN: si el reporte no tiene avistamientos devuelve
        // una fila con descripcion y fecha_encontro en null. Se descarta.
        _avistamientos = lista
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(
              (a) => a['descripcion'] != null || a['fecha_encontro'] != null,
            )
            .toList();
      } else if (resp.statusCode == 404) {
        _error = 'Reporte no encontrado.';
      } else if (resp.statusCode == 400) {
        final data = jsonDecode(resp.body);
        _error = data['error'] ?? 'Solicitud inválida.';
      } else {
        _error = 'No se pudieron cargar los avistamientos.';
      }
    } catch (e) {
      _error = 'Error de conexión con el servidor.';
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _fecha(dynamic v) {
    final texto = (v ?? '').toString();
    if (texto.isEmpty) return '—';

    final parsed = DateTime.tryParse(texto);
    if (parsed == null) return texto;

    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(parsed.day)}/${dos(parsed.month)}/${parsed.year}';
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargarAvistamientos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_avistamientos.isEmpty) {
      return const Center(
        child: Text('Este reporte aún no tiene avistamientos.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 600),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      Colors.green.withValues(alpha: 0.15),
                    ),
                    columns: const [
                      DataColumn(
                        label: Text(
                          '#',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Fecha en que se vio',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Descripción',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: List.generate(_avistamientos.length, (i) {
                      final a = _avistamientos[i];
                      return DataRow(
                        cells: [
                          DataCell(Text('${i + 1}')),
                          DataCell(Text(_fecha(a['fecha_encontro']))),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: Text((a['descripcion'] ?? '').toString()),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Avistamientos de ${widget.nombreAnimal}',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargarAvistamientos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _construirContenido(),
    );
  }
}

// ============================================
// TARJETA: un reporte
// Si se pasan onCancelar / onEncontrado, se muestran los botones
// Si se pasa onAvistamiento, se muestra el botón de avistamiento
// ============================================
class ReporteCard extends StatelessWidget {
  final Map<String, dynamic> reporte;
  final VoidCallback? onCancelar; // 👈 NUEVO
  final VoidCallback? onEncontrado; // 👈 NUEVO
  final VoidCallback? onAvistamiento; // 👈 NUEVO
  final VoidCallback? onVerAvistamientos; // 👈 NUEVO

  const ReporteCard({
    super.key,
    required this.reporte,
    this.onCancelar,
    this.onEncontrado,
    this.onAvistamiento,
    this.onVerAvistamientos,
  });

  String _texto(dynamic v) => (v ?? '').toString();

  String _fecha(dynamic v, {bool conHora = false}) {
    final texto = _texto(v);
    if (texto.isEmpty) return '—';

    final parsed = DateTime.tryParse(texto);
    if (parsed == null) return texto;

    final f = parsed.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    final base = '${dos(f.day)}/${dos(f.month)}/${f.year}';
    return conHora ? '$base ${dos(f.hour)}:${dos(f.minute)}' : base;
  }

  Color _colorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'encontrado':
        return Colors.green;
      case 'cancelado':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Widget _fila(IconData icono, String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$etiqueta: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: valor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _texto(reporte['nombre_animal']);
    final especie = _texto(reporte['nombre_especie']);
    final estadoCrudo = _texto(reporte['estado_reporte']);
    final estado = estadoCrudo.isEmpty
        ? '—'
        : estadoCrudo[0].toUpperCase() + estadoCrudo.substring(1);
    final urlFoto = _texto(reporte['url_foto']);
    final avistamientos =
        int.tryParse(_texto(reporte['cantidad_avistamientos'])) ?? 0;
    final colorEstado = _colorEstado(estadoCrudo);

    // 👇 NUEVO
    final yaCancelado = estadoCrudo.toLowerCase() == 'cancelado';
    final yaEncontrado = estadoCrudo.toLowerCase() == 'encontrado';
    final mostrarAcciones = onCancelar != null || onEncontrado != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (urlFoto.isNotEmpty)
            Image.network(
              urlFoto,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 190,
                color: Colors.grey.shade300,
                child: const Center(
                  child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        estado,
                        style: TextStyle(
                          color: colorEstado,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: colorEstado.withValues(alpha: 0.15),
                      side: BorderSide(color: colorEstado),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                _fila(Icons.pets, 'Especie', especie),
                _fila(
                  Icons.event,
                  'Se perdió el',
                  _fecha(reporte['fecha_perdio']),
                ),
                _fila(
                  Icons.description,
                  'Animal',
                  _texto(reporte['descripcion_animal']),
                ),
                _fila(
                  Icons.place,
                  'Lugar',
                  _texto(reporte['descripcion_lugar']),
                ),
                _fila(Icons.visibility, 'Avistamientos', '$avistamientos'),
                const SizedBox(height: 12),
                Text(
                  'Reportado el ${_fecha(reporte['fecha_hora_reporte'], conHora: true)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                // 👇 NUEVO: botones Cancelado / Encontrado
                if (mostrarAcciones) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (yaCancelado || yaEncontrado)
                              ? null
                              : onCancelar,
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancelado'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (yaCancelado || yaEncontrado)
                              ? null
                              : onEncontrado,
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Encontrado'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 👇 NUEVO: botón para ver la tabla de avistamientos
                  if (onVerAvistamientos != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onVerAvistamientos,
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Avistamientos'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ],
                // 👇 NUEVO: botón Avistamiento (reportes de otros usuarios)
                if (onAvistamiento != null) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onAvistamiento,
                      icon: const Icon(Icons.visibility),
                      label: const Text('Avistamiento'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
