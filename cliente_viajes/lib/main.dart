// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'config/theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Servicio B - Autenticación',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const ServicioBScreen(),
    );
  }
}

class ServicioBScreen extends StatefulWidget {
  const ServicioBScreen({super.key});

  @override
  State<ServicioBScreen> createState() => _ServicioBScreenState();
}

class _ServicioBScreenState extends State<ServicioBScreen> {
  // URLs del Servicio A
  final String loginUrl = 'http://127.0.0.1:5500/login_dashboard.html';
  final String dashboardUrl = 'http://127.0.0.1:5500/dashboard.html';
  final String baseUrl = 'http://127.0.0.1:8083';

  String? usuarioFinal;
  String? tokenFinal;

  bool sesionValida = false;
  bool isLoading = true;

  // Tabla "Mis transportes".
  List<Map<String, dynamic>> transportes = [];
  bool cargandoTransportes = false;
  String? errorTransportes;

  // Tabla "Transportes activos".
  List<Map<String, dynamic>> transportesActivos = [];
  bool cargandoActivos = false;
  String? errorActivos;

  // ID del transporte que se está inactivando (null si ninguno).
  String? inactivandoId;

  final ScrollController _scrollH = ScrollController();
  final ScrollController _scrollV = ScrollController();
  final ScrollController _scrollH2 = ScrollController();
  final ScrollController _scrollV2 = ScrollController();

  @override
  void initState() {
    super.initState();
    _validarSesion();
  }

  @override
  void dispose() {
    _scrollH.dispose();
    _scrollV.dispose();
    _scrollH2.dispose();
    _scrollV2.dispose();
    super.dispose();
  }

  // ============================================
  // 1. VALIDAR SESIÓN Y RECUPERAR TOKEN
  // ============================================
  void _validarSesion() {
    final uri = Uri.base;

    final String? usuarioUrl = uri.queryParameters['usuario'];
    String? tokenUrl = uri.queryParameters['token'];

    tokenUrl = tokenUrl?.replaceAll('"', '').trim();

    // Recuperar las credenciales guardadas en esta pestaña.
    final String? usuarioSesion = html.window.sessionStorage['usuario'];
    final String? tokenSesion = html.window.sessionStorage['token'];

    // Caso 1: el usuario llega desde el Servicio A
    // con el usuario y el token en la URL.
    if (usuarioUrl != null &&
        usuarioUrl.isNotEmpty &&
        tokenUrl != null &&
        tokenUrl.isNotEmpty) {
      usuarioFinal = usuarioUrl;
      tokenFinal = tokenUrl;

      // Guardar las credenciales en sessionStorage.
      html.window.sessionStorage['usuario'] = usuarioFinal!;
      html.window.sessionStorage['token'] = tokenFinal!;

      // Limpiar los parámetros de la URL para que
      // el token no permanezca visible en la barra.
      html.window.history.replaceState({}, '', uri.path);

      setState(() {
        sesionValida = true;
        isLoading = false;
      });

      _recargarTablas();

      return;
    }

    // Caso 2: ya existe una sesión en esta pestaña.
    if (usuarioSesion != null &&
        usuarioSesion.isNotEmpty &&
        tokenSesion != null &&
        tokenSesion.isNotEmpty) {
      usuarioFinal = usuarioSesion;
      tokenFinal = tokenSesion;

      setState(() {
        sesionValida = true;
        isLoading = false;
      });

      _recargarTablas();

      return;
    }

    // Caso 3: no hay usuario o token.
    _redireccionarAlLogin();
  }

  // ============================================
  // 2. REDIRECCIONAR AL LOGIN SI NO HAY SESIÓN
  // ============================================
  void _redireccionarAlLogin() {
    html.window.sessionStorage.remove('usuario');
    html.window.sessionStorage.remove('token');

    html.window.location.replace('$loginUrl?logout=true');
  }

  // ============================================
  // 3. CERRAR SESIÓN
  // ============================================
  void _cerrarSesion() {
    html.window.sessionStorage.remove('usuario');
    html.window.sessionStorage.remove('token');

    usuarioFinal = null;
    tokenFinal = null;

    html.window.location.replace('$loginUrl?logout=true');
  }

  // ============================================
  // 4. VOLVER AL DASHBOARD
  // ============================================
  void _volverAlDashboard() {
    html.window.location.href = dashboardUrl;
  }

  // ============================================
  // 5. ABRIR FORMULARIO DE REGISTRO
  // ============================================
  void _mostrarFormularioRegistro() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return RegistroPersonaDialog(
          baseUrl: baseUrl,
          usuario: usuarioFinal!,
        );
      },
    );
  }

  // ============================================
  // 6. ABRIR FORMULARIO DE REGISTRO DE TRANSPORTE
  // ============================================
  Future<void> _mostrarFormularioTransporte() async {
    final registrado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return RegistroTransporteDialog(
          baseUrl: baseUrl,
          usuario: usuarioFinal!,
        );
      },
    );

    // Si se registró un transporte, se actualiza la tabla.
    if (registrado == true && mounted) {
      _cargarTransportes();
    }
  }

  // ============================================
  // 7. CONSULTAR TRANSPORTES
  // ============================================
  void _recargarTablas() {
    _cargarTransportes();
    _cargarActivos();
  }

  // Consulta una ruta que recibe el usuario al final y devuelve una lista.
  // Lanza un String con el mensaje si el servidor responde con error.
  Future<List<Map<String, dynamic>>> _consultarLista(String ruta) async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl$ruta/${Uri.encodeComponent(usuarioFinal!)}'),
      headers: {'Accept': 'application/json'},
    );

    if (respuesta.statusCode == 200) {
      final lista = jsonDecode(respuesta.body) as List<dynamic>;
      return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    String mensaje =
        'No fue posible consultar los datos (código ${respuesta.statusCode})';
    try {
      final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
      mensaje = (datos['error'] ?? mensaje).toString();
    } catch (_) {}
    throw mensaje;
  }

  // GET /api/transportes/usuario/:usuario
  Future<void> _cargarTransportes() async {
    if (usuarioFinal == null) return;

    setState(() {
      cargandoTransportes = true;
      errorTransportes = null;
    });

    try {
      final datos = await _consultarLista('/api/transportes/usuario');
      if (!mounted) return;
      setState(() => transportes = datos);
    } on String catch (mensaje) {
      if (!mounted) return;
      setState(() => errorTransportes = mensaje);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorTransportes = 'No se pudo conectar con el servidor: $error';
      });
    } finally {
      if (mounted) {
        setState(() => cargandoTransportes = false);
      }
    }
  }

  // GET /api/transportes/disponibles/:usuario
  Future<void> _cargarActivos() async {
    if (usuarioFinal == null) return;

    setState(() {
      cargandoActivos = true;
      errorActivos = null;
    });

    try {
      final datos = await _consultarLista('/api/transportes/disponibles');
      if (!mounted) return;
      setState(() => transportesActivos = datos);
    } on String catch (mensaje) {
      if (!mounted) return;
      setState(() => errorActivos = mensaje);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorActivos = 'No se pudo conectar con el servidor: $error';
      });
    } finally {
      if (mounted) {
        setState(() => cargandoActivos = false);
      }
    }
  }

  // ============================================
  // 8. INACTIVAR TRANSPORTE
  // PATCH /api/transportes/:id/inactivar
  // ============================================
  void _mostrarSnack(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  // El ID puede llamarse distinto según lo que devuelva el procedimiento.
  dynamic _idTransporte(Map<String, dynamic> fila) {
    for (final clave in const [
      'id',
      'id_transporte',
      'transporte_id',
      'idTransporte',
    ]) {
      if (fila[clave] != null) return fila[clave];
    }
    return null;
  }

  bool _estaInactivo(Map<String, dynamic> fila) =>
      fila['estado']?.toString().toLowerCase() == 'inactivo';

  Future<void> _inactivarTransporte(Map<String, dynamic> fila) async {
    final id = _idTransporte(fila);
    if (id == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
      shape: AppTheme.formaTarjeta,
        title: const Text('Inactivar transporte'),
        content: Text('¿Seguro que quieres inactivar el transporte $id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Inactivar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => inactivandoId = id.toString());

    try {
      final respuesta = await http.patch(
        Uri.parse(
          '$baseUrl/api/transportes/'
          '${Uri.encodeComponent(id.toString())}/inactivar',
        ),
        headers: {'Accept': 'application/json'},
      );

      Map<String, dynamic> datos = {};
      try {
        datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
      } catch (_) {}

      if (!mounted) return;

      if (respuesta.statusCode == 200) {
        _mostrarSnack(
          (datos['mensaje'] ?? 'Transporte inactivado con éxito').toString(),
          AppColors.verde,
        );
        _recargarTablas();
      } else {
        _mostrarSnack(
          (datos['error'] ??
                  'No fue posible inactivar el transporte '
                      '(código ${respuesta.statusCode})')
              .toString(),
          AppColors.rojo,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _mostrarSnack('No se pudo conectar con el servidor: $error', AppColors.rojo);
    } finally {
      if (mounted) {
        setState(() => inactivandoId = null);
      }
    }
  }

  // ============================================
  // 9. ADQUIRIR / ACTUALIZAR CUPOS DE UN TRANSPORTE
  // ============================================
  Future<void> _abrirAdquirir(Map<String, dynamic> fila) async {
    final id = _idTransporte(fila);
    if (id == null) return;

    // Datos de la fila ya formateados para mostrarlos en el formulario.
    final detalle = fila.entries
        .map((e) => MapEntry(_etiqueta(e.key), _textoCelda(e.value)))
        .toList();

    final cambio = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AdquirirTransporteDialog(
          baseUrl: baseUrl,
          usuario: usuarioFinal!,
          transporteId: id,
          detalle: detalle,
        );
      },
    );

    // Si se adquirieron o actualizaron cupos, se recargan las tablas.
    if (cambio == true && mounted) {
      _recargarTablas();
    }
  }

  // ============================================
  // 10. VER PASAJEROS DE UN TRANSPORTE
  // GET /api/transportes/:id/pasajeros
  // ============================================
  void _abrirVerMas(Map<String, dynamic> fila) {
    final id = _idTransporte(fila);
    if (id == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return PasajerosTransporteDialog(
          baseUrl: baseUrl,
          transporteId: id,
          etiqueta: _etiqueta,
          textoCelda: _textoCelda,
        );
      },
    );
  }

  // ============================================
  // TABLAS
  // ============================================
  String _dos(int n) => n.toString().padLeft(2, '0');

  // "hora_salida" -> "Hora salida"
  String _etiqueta(String clave) {
    final t = clave.replaceAll('_', ' ').trim();
    return t.isEmpty ? clave : t[0].toUpperCase() + t.substring(1);
  }

  // Muestra las fechas ISO (2026-10-25T13:30:00.000Z) como
  // "2026-10-25 08:30" y los valores nulos como "-".
  String _textoCelda(dynamic valor) {
    if (valor == null) return '-';

    if (valor is String) {
      final iso = RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$',
      );
      if (iso.hasMatch(valor)) {
        final fecha = DateTime.tryParse(valor);
        if (fecha != null) {
          final l = fecha.toLocal();
          return '${l.year}-${_dos(l.month)}-${_dos(l.day)} '
              '${_dos(l.hour)}:${_dos(l.minute)}';
        }
      }
    }

    return valor.toString();
  }

  // Tarjeta con título, botón de refrescar y la tabla.
  Widget _construirTarjetaTabla({
    required String titulo,
    required IconData icono,
    required List<Map<String, dynamic>> datos,
    required bool cargando,
    required String? error,
    required VoidCallback onRecargar,
    required String textoVacio,
    required ScrollController scrollH,
    required ScrollController scrollV,
    bool conInactivar = false,
    bool conAdquirir = false,
    bool conVerMas = false,
  }) {
    final ancho = MediaQuery.of(context).size.width;
    final anchoTabla = ancho > 1048 ? 1000.0 : ancho - 48;

    return SizedBox(
      width: anchoTabla,
      child: Card(
        elevation: 2,
        color: Colors.white,
        shape: AppTheme.formaTarjeta,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: AppColors.verde),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar tabla',
                    onPressed: cargando ? null : onRecargar,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _contenidoTabla(
                datos: datos,
                cargando: cargando,
                error: error,
                onRecargar: onRecargar,
                textoVacio: textoVacio,
                scrollH: scrollH,
                scrollV: scrollV,
                conInactivar: conInactivar,
                conAdquirir: conAdquirir,
                conVerMas: conVerMas,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Botones de acción de una fila: Inactivar, Ver más y Adquirir.
  List<Widget> _botonesAccion(
    Map<String, dynamic> fila, {
    required bool conInactivar,
    required bool conAdquirir,
    required bool conVerMas,
  }) {
    final id = _idTransporte(fila);
    const sinId = 'La consulta no devuelve el ID del transporte';
    final botones = <Widget>[];

    // Destructivo: rojo.
    if (conInactivar) {
      final yaInactivo = _estaInactivo(fila);
      final puedeInactivar =
          id != null && !yaInactivo && inactivandoId == null;
      final inactivando = id != null && inactivandoId == id.toString();

      botones.add(
        Tooltip(
          message: id == null
              ? sinId
              : (yaInactivo ? 'Ya está inactivo' : 'Inactivar'),
          child: OutlinedButton.icon(
            onPressed: puedeInactivar ? () => _inactivarTransporte(fila) : null,
            icon: inactivando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.block, size: 18),
            label: const Text('Inactivar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.rojo,
              side: BorderSide(
                color: puedeInactivar ? AppColors.rojo : AppColors.borde,
              ),
            ),
          ),
        ),
      );
    }

    // Informativo: azul.
    if (conVerMas) {
      botones.add(
        Tooltip(
          message: id == null
              ? sinId
              : 'Ver los pasajeros de este transporte',
          child: FilledButton.tonalIcon(
            onPressed: id == null ? null : () => _abrirVerMas(fila),
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('Ver más'),
            style: FilledButton.styleFrom(foregroundColor: AppColors.azul),
          ),
        ),
      );
    }

    // Acción principal: verde.
    if (conAdquirir) {
      botones.add(
        Tooltip(
          message: id == null ? sinId : 'Adquirir cupos',
          child: FilledButton.tonalIcon(
            onPressed: id == null ? null : () => _abrirAdquirir(fila),
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Adquirir'),
          ),
        ),
      );
    }

    return botones;
  }

  // Pantallas angostas: cada fila se muestra como una tarjeta
  // en lugar de una tabla comprimida.
  Widget _listaTarjetas({
    required List<Map<String, dynamic>> datos,
    required String textoVacio,
    required ScrollController scrollV,
    required bool conInactivar,
    required bool conAdquirir,
    required bool conVerMas,
  }) {
    final decoracion = BoxDecoration(
      color: AppColors.fondo,
      borderRadius: BorderRadius.circular(AppTheme.radioTarjeta),
      border: Border.all(color: AppColors.borde),
    );

    if (datos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.paddingTarjeta),
        decoration: decoracion,
        child: Text(
          textoVacio,
          style: const TextStyle(color: AppColors.textoSuave),
        ),
      );
    }

    return SizedBox(
      height: 420,
      child: Scrollbar(
        controller: scrollV,
        thumbVisibility: true,
        child: ListView.separated(
          controller: scrollV,
          itemCount: datos.length,
          separatorBuilder: (context, indice) => const SizedBox(height: 12),
          itemBuilder: (context, indice) {
            final fila = datos[indice];
            final botones = _botonesAccion(
              fila,
              conInactivar: conInactivar,
              conAdquirir: conAdquirir,
              conVerMas: conVerMas,
            );

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.paddingTarjeta),
              decoration: decoracion,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...fila.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${_etiqueta(e.key)}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: _textoCelda(e.value)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (botones.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: botones),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _contenidoTabla({
    required List<Map<String, dynamic>> datos,
    required bool cargando,
    required String? error,
    required VoidCallback onRecargar,
    required String textoVacio,
    required ScrollController scrollH,
    required ScrollController scrollV,
    required bool conInactivar,
    required bool conAdquirir,
    required bool conVerMas,
  }) {
    if (cargando) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.rojo),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRecargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    // Pantallas angostas: tarjetas (sin tabla comprimida).
    if (MediaQuery.of(context).size.width < 700) {
      return _listaTarjetas(
        datos: datos,
        textoVacio: textoVacio,
        scrollV: scrollV,
        conInactivar: conInactivar,
        conAdquirir: conAdquirir,
        conVerMas: conVerMas,
      );
    }

    // Pantallas anchas: tabla con scroll vertical y horizontal.
    final hayAcciones = conInactivar || conAdquirir || conVerMas;

    // Las columnas salen de los campos que devuelve el procedimiento.
    final columnas = datos.isEmpty ? <String>[] : datos.first.keys.toList();

    final List<DataColumn> columnasTabla;
    final List<DataRow> filasTabla;

    if (datos.isEmpty) {
      columnasTabla = const [DataColumn(label: Text('Transportes'))];
      filasTabla = [
        DataRow(cells: [DataCell(Text(textoVacio))]),
      ];
    } else {
      columnasTabla = [
        ...columnas.map(
          (c) => DataColumn(
            label: Text(
              _etiqueta(c),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (hayAcciones)
          const DataColumn(
            label: Text(
              'Acciones',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ];

      filasTabla = datos.map((fila) {
        final celdas = columnas
            .map((c) => DataCell(Text(_textoCelda(fila[c]))))
            .toList();

        if (hayAcciones) {
          final botones = _botonesAccion(
            fila,
            conInactivar: conInactivar,
            conAdquirir: conAdquirir,
            conVerMas: conVerMas,
          );

          celdas.add(
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final boton in botones) ...[
                    boton,
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          );
        }

        return DataRow(cells: celdas);
      }).toList();
    }

    return SizedBox(
      height: 320,
      child: LayoutBuilder(
        builder: (context, restricciones) {
          return Scrollbar(
            controller: scrollH,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: scrollH,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: restricciones.maxWidth),
                child: Scrollbar(
                  controller: scrollV,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: scrollV,
                    child: DataTable(
                      columns: columnasTabla,
                      rows: filasTabla,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Logo con fondo blanco para que se vea bien sobre cualquier fondo.
  Widget _logo(String ruta) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(2),
        child: Image.asset(
          ruta,
          height: 44,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Muestra en la consola el motivo real por el que no cargó.
            debugPrint('No se pudo cargar $ruta: $error');
            return const SizedBox(
              height: 44,
              width: 44,
              child: Icon(Icons.image_not_supported, color: AppColors.textoSuave),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mientras se valida la sesión, mostrar un indicador.
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Sin sesión válida, no mostrar el contenido.
    if (!sesionValida || tokenFinal == null) {
      return const Scaffold(
        body: Center(child: Text('Acceso no autorizado')),
      );
    }

    // Contenido protegido del Servicio B.
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Servicio B - Usuario: ${usuarioFinal ?? ""}',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.verde,
        foregroundColor: Colors.white,
        // En pantallas angostas los botones pasan a ser solo íconos.
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
      bottomNavigationBar: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.borde)),
        ),
        child: SafeArea(
          top: false,
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _logo('assets/logoUniversidad.jpeg'),
              _logo('assets/logoIngenieria.jpeg'),
              _logo('assets/logoRedComunitaria.jpeg'),
            ],
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _mostrarFormularioRegistro,
                    icon: const Icon(Icons.person_add),
                    label: const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text(
                        'Registrarse',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _mostrarFormularioTransporte,
                    icon: const Icon(Icons.directions_bus),
                    label: const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text(
                        'Registrar transporte',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _construirTarjetaTabla(
                titulo: 'Mis transportes',
                icono: Icons.list_alt,
                datos: transportes,
                cargando: cargandoTransportes,
                error: errorTransportes,
                onRecargar: _cargarTransportes,
                textoVacio: 'No tienes transportes registrados',
                scrollH: _scrollH,
                scrollV: _scrollV,
                conInactivar: true,
                conVerMas: true,
              ),
              const SizedBox(height: 24),
              _construirTarjetaTabla(
                titulo: 'Transportes activos',
                icono: Icons.directions_bus_filled,
                datos: transportesActivos,
                cargando: cargandoActivos,
                error: errorActivos,
                onRecargar: _cargarActivos,
                textoVacio: 'No hay transportes activos disponibles',
                scrollH: _scrollH2,
                scrollV: _scrollV2,
                conAdquirir: true,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// FORMULARIO DE REGISTRO / ACTUALIZACIÓN DE PERSONA
// ============================================
class RegistroPersonaDialog extends StatefulWidget {
  final String baseUrl;
  final String usuario;

  const RegistroPersonaDialog({
    super.key,
    required this.baseUrl,
    required this.usuario,
  });

  @override
  State<RegistroPersonaDialog> createState() => _RegistroPersonaDialogState();
}

class _RegistroPersonaDialogState extends State<RegistroPersonaDialog> {
  final _formKey = GlobalKey<FormState>();

  final _primerNombreController = TextEditingController();
  final _segundoNombreController = TextEditingController();
  final _primerApellidoController = TextEditingController();
  final _segundoApellidoController = TextEditingController();
  final _numeroContactoController = TextEditingController();

  // Consultando los datos del usuario al abrir el formulario.
  bool _cargando = true;

  // Guardando o actualizando.
  bool _guardando = false;

  // true si el usuario ya tiene una persona registrada.
  bool _existe = false;

  bool get _ocupado => _cargando || _guardando;

  @override
  void initState() {
    super.initState();
    _consultarPersona();
  }

  @override
  void dispose() {
    _primerNombreController.dispose();
    _segundoNombreController.dispose();
    _primerApellidoController.dispose();
    _segundoApellidoController.dispose();
    _numeroContactoController.dispose();
    super.dispose();
  }

  // Campo obligatorio con longitud máxima (según la tabla).
  String? _validarObligatorio(String? valor, String campo, int max) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El campo $campo es obligatorio';
    }
    if (valor.trim().length > max) {
      return 'Máximo $max caracteres';
    }
    return null;
  }

  // Campo opcional con longitud máxima.
  String? _validarOpcional(String? valor, int max) {
    if (valor != null && valor.trim().length > max) {
      return 'Máximo $max caracteres';
    }
    return null;
  }

  String? _nullSiVacio(String texto) {
    final t = texto.trim();
    return t.isEmpty ? null : t;
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  Map<String, dynamic> _decodificar(String cuerpo) {
    try {
      return jsonDecode(cuerpo) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ============================================
  // CONSULTAR PERSONA POR USUARIO
  // GET /api/personas/:usuario
  // ============================================
  Future<void> _consultarPersona() async {
    try {
      final respuesta = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/personas/'
          '${Uri.encodeComponent(widget.usuario)}',
        ),
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (respuesta.statusCode == 200) {
        // El usuario ya está registrado: se cargan sus datos.
        final datos = _decodificar(respuesta.body);

        _primerNombreController.text = datos['primer_nombre'] ?? '';
        _segundoNombreController.text = datos['segundo_nombre'] ?? '';
        _primerApellidoController.text = datos['primer_apellido'] ?? '';
        _segundoApellidoController.text = datos['segundo_apellido'] ?? '';
        _numeroContactoController.text = datos['numero_contacto'] ?? '';

        setState(() => _existe = true);
      } else if (respuesta.statusCode == 404) {
        // No está registrado: el formulario queda vacío.
        setState(() => _existe = false);
      } else {
        final datos = _decodificar(respuesta.body);
        _mostrarMensaje(
          (datos['error'] ??
                  'No fue posible consultar los datos '
                      '(código ${respuesta.statusCode})')
              .toString(),
          AppColors.rojo,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // ============================================
  // GUARDAR PERSONA (REGISTRO NUEVO)
  // POST /api/personas
  // ============================================
  Future<void> _guardarPersona() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      final respuesta = await http.post(
        Uri.parse('${widget.baseUrl}/api/personas'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'primer_nombre': _primerNombreController.text.trim(),
          'segundo_nombre': _nullSiVacio(_segundoNombreController.text),
          'primer_apellido': _primerApellidoController.text.trim(),
          'segundo_apellido': _nullSiVacio(_segundoApellidoController.text),
          'numero_contacto': _numeroContactoController.text.trim(),
          'usuario': widget.usuario,
        }),
      );

      final datos = _decodificar(respuesta.body);

      if (!mounted) return;

      if (respuesta.statusCode == 201) {
        final mensaje = datos['mensaje'] ?? 'Persona registrada con éxito';
        Navigator.of(context).pop();
        _mostrarMensaje('$mensaje. ID: ${datos['id']}', AppColors.verde);
      } else {
        final mensaje = datos['error'] ??
            datos['mensaje'] ??
            'No fue posible registrar la persona '
                '(código ${respuesta.statusCode})';
        _mostrarMensaje(mensaje.toString(), AppColors.rojo);
      }
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  // ============================================
  // ACTUALIZAR NÚMERO DE CONTACTO
  // PATCH /api/personas/usuario/:usuario/contacto
  // ============================================
  Future<void> _actualizarContacto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      final respuesta = await http.patch(
        Uri.parse(
          '${widget.baseUrl}/api/personas/usuario/'
          '${Uri.encodeComponent(widget.usuario)}/contacto',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'numero_contacto': _numeroContactoController.text.trim(),
        }),
      );

      final datos = _decodificar(respuesta.body);

      if (!mounted) return;

      if (respuesta.statusCode == 200) {
        final mensaje =
            datos['mensaje'] ?? 'Número de contacto actualizado con éxito';
        Navigator.of(context).pop();
        _mostrarMensaje(mensaje.toString(), AppColors.verde);
      } else {
        final mensaje = datos['error'] ??
            datos['mensaje'] ??
            'No fue posible actualizar el número '
                '(código ${respuesta.statusCode})';
        _mostrarMensaje(mensaje.toString(), AppColors.rojo);
      }
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  // ============================================
  // CAMPO DE TEXTO REUTILIZABLE
  // soloLectura: true cuando la persona ya existe y el campo
  // no se puede actualizar (solo se actualiza el contacto).
  // ============================================
  Widget _campoTexto({
    required String etiqueta,
    required TextEditingController controller,
    required IconData icono,
    required String? Function(String?) validador,
    TextInputType tipoTeclado = TextInputType.text,
    bool soloLectura = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: tipoTeclado,
        textCapitalization: tipoTeclado == TextInputType.text
            ? TextCapitalization.words
            : TextCapitalization.none,
        enabled: !_ocupado,
        readOnly: soloLectura,
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: Icon(icono),
          border: AppTheme.bordeCampo,
          filled: soloLectura,
        ),
        validator: validador,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppTheme.formaTarjeta,
      title: Row(
        children: [
          const Icon(Icons.person_add_alt_1, color: AppColors.verde),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_existe ? 'Mis datos' : 'Registrarse'),
          ),
        ],
      ),
      content: SizedBox(
        width: AppTheme.anchoDialogo(context, 450),
        child: _cargando
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_existe)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Ya estás registrado. Solo puedes actualizar '
                            'tu número de contacto.',
                            style: TextStyle(color: AppColors.textoSuave),
                          ),
                        ),
                      _campoTexto(
                        etiqueta: 'Primer nombre',
                        controller: _primerNombreController,
                        icono: Icons.person,
                        soloLectura: _existe,
                        validador: (v) =>
                            _validarObligatorio(v, 'Primer nombre', 50),
                      ),
                      _campoTexto(
                        etiqueta: 'Segundo nombre (opcional)',
                        controller: _segundoNombreController,
                        icono: Icons.person_outline,
                        soloLectura: _existe,
                        validador: (v) => _validarOpcional(v, 50),
                      ),
                      _campoTexto(
                        etiqueta: 'Primer apellido',
                        controller: _primerApellidoController,
                        icono: Icons.badge_outlined,
                        soloLectura: _existe,
                        validador: (v) =>
                            _validarObligatorio(v, 'Primer apellido', 50),
                      ),
                      _campoTexto(
                        etiqueta: 'Segundo apellido (opcional)',
                        controller: _segundoApellidoController,
                        icono: Icons.badge,
                        soloLectura: _existe,
                        validador: (v) => _validarOpcional(v, 50),
                      ),
                      _campoTexto(
                        etiqueta: 'Número de contacto',
                        controller: _numeroContactoController,
                        icono: Icons.phone,
                        tipoTeclado: TextInputType.phone,
                        validador: (v) =>
                            _validarObligatorio(v, 'Número de contacto', 20),
                      ),

                      // Usuario recibido del Servicio A (solo lectura).
                      TextFormField(
                        initialValue: widget.usuario,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.account_circle),
                          border: AppTheme.bordeCampo,
                          helperText:
                              'Se asigna automáticamente desde tu sesión',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),

        // Guardar: solo cuando el usuario aún no está registrado.
        FilledButton.icon(
          onPressed: (_ocupado || _existe) ? null : _guardarPersona,
          icon: _guardando && !_existe
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_guardando && !_existe ? 'Guardando...' : 'Guardar'),
        ),

        // Actualizar: solo cuando el usuario ya está registrado.
        FilledButton.tonalIcon(
          onPressed: (_ocupado || !_existe) ? null : _actualizarContacto,
          icon: _guardando && _existe
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit),
          label: Text(
            _guardando && _existe ? 'Actualizando...' : 'Actualizar',
          ),
        ),
      ],
    );
  }
}


// ============================================
// FORMULARIO DE REGISTRO DE TRANSPORTE
// POST /api/transportes
// ============================================
class RegistroTransporteDialog extends StatefulWidget {
  final String baseUrl;
  final String usuario;

  const RegistroTransporteDialog({
    super.key,
    required this.baseUrl,
    required this.usuario,
  });

  @override
  State<RegistroTransporteDialog> createState() =>
      _RegistroTransporteDialogState();
}

class _RegistroTransporteDialogState extends State<RegistroTransporteDialog> {
  final _formKey = GlobalKey<FormState>();

  final _fechaComunidadController = TextEditingController();
  final _puntoComunidadController = TextEditingController();
  final _fechaCiudadController = TextEditingController();
  final _puntoCiudadController = TextEditingController();
  final _capacidadController = TextEditingController();

  // Tipos de transporte traídos del backend (si el endpoint existe).
  List<String> _tipos = [];
  String? _tipoSeleccionado;
  bool _cargandoTipos = true;
  bool _errorTipos = false;

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarTipos();
  }

  @override
  void dispose() {
    _fechaComunidadController.dispose();
    _puntoComunidadController.dispose();
    _fechaCiudadController.dispose();
    _puntoCiudadController.dispose();
    _capacidadController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  Map<String, dynamic> _decodificar(String cuerpo) {
    try {
      return jsonDecode(cuerpo) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ============================================
  // CARGAR TIPOS DE TRANSPORTE
  // GET /api/tipos-transporte/nombres
  // ============================================
  Future<void> _cargarTipos() async {
    try {
      final respuesta = await http.get(
        Uri.parse('${widget.baseUrl}/api/tipos-transporte/nombres'),
        headers: {'Accept': 'application/json'},
      );

      if (respuesta.statusCode == 200) {
        final lista = jsonDecode(respuesta.body) as List<dynamic>;
        _tipos = lista
            .map((e) => (e as Map<String, dynamic>)['nombre'].toString())
            .toList();
      } else {
        _errorTipos = true;
      }
    } catch (_) {
      _errorTipos = true;
    } finally {
      if (mounted) {
        setState(() => _cargandoTipos = false);
      }
    }
  }

  // ============================================
  // FECHA Y HORA
  // ============================================
  String _dos(int n) => n.toString().padLeft(2, '0');

  // Formato que espera el backend: YYYY-MM-DD HH:mm:ss
  String _formatear(DateTime d) =>
      '${d.year}-${_dos(d.month)}-${_dos(d.day)} '
      '${_dos(d.hour)}:${_dos(d.minute)}:00';

  Future<void> _seleccionarFechaHora(TextEditingController controller) async {
    final ahora = DateTime.now();

    final fecha = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(ahora.year, ahora.month, ahora.day),
      lastDate: DateTime(ahora.year + 5),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (hora == null || !mounted) return;

    controller.text = _formatear(
      DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute),
    );
  }

  // ============================================
  // VALIDACIONES
  // ============================================
  String? _obligatorio(String? valor, String campo) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El campo $campo es obligatorio';
    }
    return null;
  }

  String? _validarCapacidad(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'La capacidad es obligatoria';
    }
    final n = int.tryParse(valor.trim());
    if (n == null || n <= 0) {
      return 'Debe ser un entero mayor que cero';
    }
    return null;
  }

  // ============================================
  // GUARDAR TRANSPORTE
  // ============================================
  Future<void> _guardarTransporte() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final tipo = _tipoSeleccionado!;

    try {
      final respuesta = await http.post(
        Uri.parse('${widget.baseUrl}/api/transportes'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'nombre_tipo_transporte': tipo,
          'nombre_usuario': widget.usuario,
          'fecha_hora_salida_comunidad': _fechaComunidadController.text,
          'punto_encuentro_salida_comunidad':
              _puntoComunidadController.text.trim(),
          'fecha_hora_salida_ciudad': _fechaCiudadController.text,
          'punto_encuentro_salida_ciudad': _puntoCiudadController.text.trim(),
          'capacidad': int.parse(_capacidadController.text.trim()),
        }),
      );

      final datos = _decodificar(respuesta.body);

      if (!mounted) return;

      if (respuesta.statusCode == 201) {
        final mensaje = datos['mensaje'] ?? 'Transporte registrado con éxito';
        Navigator.of(context).pop(true);
        _mostrarMensaje(mensaje.toString(), AppColors.verde);
      } else {
        final mensaje = datos['error'] ??
            datos['mensaje'] ??
            'No fue posible registrar el transporte '
                '(código ${respuesta.statusCode})';
        _mostrarMensaje(mensaje.toString(), AppColors.rojo);
      }
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  // ============================================
  // CAMPOS REUTILIZABLES
  // ============================================
  Widget _campoTexto({
    required String etiqueta,
    required TextEditingController controller,
    required IconData icono,
    required String? Function(String?) validador,
    TextInputType tipoTeclado = TextInputType.text,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: tipoTeclado,
        inputFormatters: formatters,
        textCapitalization: tipoTeclado == TextInputType.text
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        enabled: !_guardando,
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: Icon(icono),
          border: AppTheme.bordeCampo,
        ),
        validator: validador,
      ),
    );
  }

  Widget _campoFechaHora({
    required String etiqueta,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        enabled: !_guardando,
        onTap: () => _seleccionarFechaHora(controller),
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: const Icon(Icons.event),
          suffixIcon: const Icon(Icons.access_time),
          border: AppTheme.bordeCampo,
          helperText: 'Toca para elegir fecha y hora',
        ),
        validator: (v) => _obligatorio(v, etiqueta),
      ),
    );
  }

  Widget _campoTipo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: _tipoSeleccionado,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Tipo de transporte',
          prefixIcon: const Icon(Icons.directions_bus),
          border: AppTheme.bordeCampo,
          errorText: _errorTipos
              ? 'No se pudieron cargar los tipos de transporte'
              : null,
        ),
        items: _tipos
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (_guardando || _tipos.isEmpty)
            ? null
            : (valor) => setState(() => _tipoSeleccionado = valor),
        validator: (v) => v == null ? 'Selecciona un tipo de transporte' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppTheme.formaTarjeta,
      title: const Row(
        children: [
          Icon(Icons.directions_bus, color: AppColors.verde),
          SizedBox(width: 12),
          Expanded(child: Text('Registrar transporte')),
        ],
      ),
      content: SizedBox(
        width: AppTheme.anchoDialogo(context, 450),
        child: _cargandoTipos
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _campoTipo(),
                      _campoFechaHora(
                        etiqueta: 'Fecha y hora de salida de la comunidad',
                        controller: _fechaComunidadController,
                      ),
                      _campoTexto(
                        etiqueta: 'Punto de encuentro en la comunidad',
                        controller: _puntoComunidadController,
                        icono: Icons.place,
                        validador: (v) => _obligatorio(
                          v,
                          'Punto de encuentro en la comunidad',
                        ),
                      ),
                      _campoFechaHora(
                        etiqueta: 'Fecha y hora de salida de la ciudad',
                        controller: _fechaCiudadController,
                      ),
                      _campoTexto(
                        etiqueta: 'Punto de encuentro en la ciudad',
                        controller: _puntoCiudadController,
                        icono: Icons.location_city,
                        validador: (v) => _obligatorio(
                          v,
                          'Punto de encuentro en la ciudad',
                        ),
                      ),
                      _campoTexto(
                        etiqueta: 'Capacidad',
                        controller: _capacidadController,
                        icono: Icons.people,
                        tipoTeclado: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validador: _validarCapacidad,
                      ),

                      // Usuario recibido del Servicio A (solo lectura).
                      TextFormField(
                        initialValue: widget.usuario,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.account_circle),
                          border: AppTheme.bordeCampo,
                          helperText:
                              'Se asigna automáticamente desde tu sesión',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed:
              (_cargandoTipos || _guardando) ? null : _guardarTransporte,
          icon: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_guardando ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}


// ============================================
// FORMULARIO PARA ADQUIRIR / ACTUALIZAR CUPOS
// GET   /api/transportes/:transporte_id/cupos/:usuario
// POST  /api/transportes/adquirir
// PATCH /api/transportes/actualizar-cupos
// ============================================
class AdquirirTransporteDialog extends StatefulWidget {
  final String baseUrl;
  final String usuario;
  final dynamic transporteId;
  final List<MapEntry<String, String>> detalle;

  const AdquirirTransporteDialog({
    super.key,
    required this.baseUrl,
    required this.usuario,
    required this.transporteId,
    required this.detalle,
  });

  @override
  State<AdquirirTransporteDialog> createState() =>
      _AdquirirTransporteDialogState();
}

class _AdquirirTransporteDialogState extends State<AdquirirTransporteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cuposController = TextEditingController();

  // Consultando los cupos del usuario al abrir el formulario.
  bool _cargando = true;

  // Adquiriendo o actualizando.
  bool _guardando = false;

  // true si el usuario ya tiene cupos reservados en este transporte.
  bool _tieneReserva = false;

  // Cupos que el usuario tiene reservados actualmente.
  int? _cuposAnteriores;

  bool get _ocupado => _cargando || _guardando;

  // El ID como número, que es lo que espera el backend.
  dynamic get _idNumerico =>
      int.tryParse(widget.transporteId.toString()) ?? widget.transporteId;

  @override
  void initState() {
    super.initState();
    _consultarCupos();
  }

  @override
  void dispose() {
    _cuposController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  Map<String, dynamic> _decodificar(String cuerpo) {
    try {
      return jsonDecode(cuerpo) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // Busca la cantidad reservada en la respuesta, sin importar el nombre
  // exacto del campo que devuelva el procedimiento.
  int? _extraerCupos(Map<String, dynamic> datos) {
    for (final clave in const [
      'cupos',
      'cupos_reservados',
      'cupos_adquiridos',
      'cantidad_reservada',
      'cantidad',
      'capacidad',
    ]) {
      if (datos[clave] != null) {
        final n = int.tryParse(datos[clave].toString());
        if (n != null) return n;
      }
    }

    // Si no coincide ningún nombre, se usa el primer número que no sea un ID.
    for (final entrada in datos.entries) {
      if (entrada.key.toLowerCase().contains('id')) continue;
      final n = int.tryParse(entrada.value.toString());
      if (n != null) return n;
    }

    return null;
  }

  // ============================================
  // CONSULTAR CUPOS DEL USUARIO EN ESTE TRANSPORTE
  // ============================================
  Future<void> _consultarCupos() async {
    try {
      final respuesta = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/transportes/'
          '${Uri.encodeComponent(widget.transporteId.toString())}'
          '/cupos/${Uri.encodeComponent(widget.usuario)}',
        ),
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (respuesta.statusCode == 200) {
        // Ya tiene cupos: se cargan en el formulario.
        final datos = _decodificar(respuesta.body);
        final cupos = _extraerCupos(datos);

        if (cupos != null) {
          _cuposController.text = cupos.toString();
        }

        setState(() {
          _tieneReserva = true;
          _cuposAnteriores = cupos;
        });
      } else if (respuesta.statusCode == 404) {
        // No tiene cupos en este transporte: formulario vacío.
        setState(() {
          _tieneReserva = false;
          _cuposAnteriores = null;
        });
      } else {
        final datos = _decodificar(respuesta.body);
        _mostrarMensaje(
          (datos['error'] ??
                  'No fue posible consultar los cupos '
                      '(código ${respuesta.statusCode})')
              .toString(),
          AppColors.rojo,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // ============================================
  // VALIDACIÓN
  // ============================================
  String? _validarCupos(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Los cupos son obligatorios';
    }

    final n = int.tryParse(valor.trim());
    if (n == null || n < 0) {
      return 'Debe ser un número entero';
    }

    // Al adquirir debe ser mayor que cero; al actualizar se permite 0.
    if (!_tieneReserva && n <= 0) {
      return 'Debe ser mayor que cero';
    }

    return null;
  }

  // ============================================
  // ADQUIRIR CUPOS
  // POST /api/transportes/adquirir
  // ============================================
  Future<void> _adquirir() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      final respuesta = await http.post(
        Uri.parse('${widget.baseUrl}/api/transportes/adquirir'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'transporte_id': _idNumerico,
          'nombre_usuario': widget.usuario,
          'capacidad': int.parse(_cuposController.text.trim()),
        }),
      );

      _procesarRespuesta(
        respuesta,
        exito: 200,
        mensajeExito: 'Cupos adquiridos con éxito',
        mensajeError: 'No fue posible adquirir los cupos',
      );
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  // ============================================
  // ACTUALIZAR CUPOS
  // PATCH /api/transportes/actualizar-cupos
  // ============================================
  Future<void> _actualizar() async {
    if (!_formKey.currentState!.validate()) return;

    final nuevos = int.parse(_cuposController.text.trim());

    if (nuevos == _cuposAnteriores) {
      _mostrarMensaje(
        'Los cupos nuevos son iguales a los que ya tienes',
        AppColors.azul,
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final respuesta = await http.patch(
        Uri.parse('${widget.baseUrl}/api/transportes/actualizar-cupos'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'transporte_id': _idNumerico,
          'nombre_usuario': widget.usuario,
          'cupos_anteriores': _cuposAnteriores,
          'cupos_nuevos': nuevos,
        }),
      );

      _procesarRespuesta(
        respuesta,
        exito: 200,
        mensajeExito: 'Cupos actualizados con éxito',
        mensajeError: 'No fue posible actualizar los cupos',
      );
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con el servidor: $error',
        AppColors.rojo,
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  // Si salió bien cierra el formulario devolviendo true; si no, muestra
  // el error que devolvió el procedimiento.
  void _procesarRespuesta(
    http.Response respuesta, {
    required int exito,
    required String mensajeExito,
    required String mensajeError,
  }) {
    final datos = _decodificar(respuesta.body);

    if (!mounted) return;

    if (respuesta.statusCode == exito) {
      final mensaje = datos['mensaje'] ?? mensajeExito;
      Navigator.of(context).pop(true);
      _mostrarMensaje(mensaje.toString(), AppColors.verde);
    } else {
      final mensaje = datos['error'] ??
          datos['mensaje'] ??
          '$mensajeError (código ${respuesta.statusCode})';
      _mostrarMensaje(mensaje.toString(), AppColors.rojo);
    }
  }

  // ============================================
  // INTERFAZ
  // ============================================
  Widget _datosTransporte() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borde),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos del transporte',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...widget.detalle.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${e.key}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: e.value),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _estado {
    if (!_tieneReserva) {
      return 'Aún no tienes cupos en este transporte.';
    }
    if (_cuposAnteriores == null) {
      return 'Ya tienes cupos en este transporte, pero no se pudo '
          'determinar cuántos.';
    }
    return 'Ya tienes $_cuposAnteriores cupo(s) reservado(s) en este '
        'transporte.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppTheme.formaTarjeta,
      title: Row(
        children: [
          const Icon(Icons.add_shopping_cart, color: AppColors.verde),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _tieneReserva ? 'Mis cupos del transporte' : 'Adquirir transporte',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: AppTheme.anchoDialogo(context, 450),
        child: _cargando
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _datosTransporte(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _estado,
                          style: const TextStyle(color: AppColors.textoSuave),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: TextFormField(
                          controller: _cuposController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          enabled: !_guardando,
                          decoration: InputDecoration(
                            labelText: _tieneReserva
                                ? 'Cupos nuevos'
                                : 'Cupos a adquirir',
                            prefixIcon: const Icon(Icons.people),
                            border: AppTheme.bordeCampo,
                            helperText: _tieneReserva
                                ? 'Usa 0 para liberar tus cupos'
                                : null,
                          ),
                          validator: _validarCupos,
                        ),
                      ),

                      // Usuario recibido del Servicio A (solo lectura).
                      TextFormField(
                        initialValue: widget.usuario,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.account_circle),
                          border: AppTheme.bordeCampo,
                          helperText:
                              'Se asigna automáticamente desde tu sesión',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),

        // Adquirir: solo si aún no tiene cupos en este transporte.
        FilledButton.icon(
          onPressed: (_ocupado || _tieneReserva) ? null : _adquirir,
          icon: _guardando && !_tieneReserva
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_shopping_cart),
          label: Text(
            _guardando && !_tieneReserva ? 'Adquiriendo...' : 'Adquirir',
          ),
        ),

        // Actualizar: solo si ya tiene cupos en este transporte.
        FilledButton.tonalIcon(
          onPressed: (_ocupado || !_tieneReserva || _cuposAnteriores == null)
              ? null
              : _actualizar,
          icon: _guardando && _tieneReserva
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit),
          label: Text(
            _guardando && _tieneReserva ? 'Actualizando...' : 'Actualizar',
          ),
        ),
      ],
    );
  }
}


// ============================================
// PASAJEROS DE UN TRANSPORTE
// GET /api/transportes/:id/pasajeros
// ============================================
class PasajerosTransporteDialog extends StatefulWidget {
  final String baseUrl;
  final dynamic transporteId;
  final String Function(String) etiqueta;
  final String Function(dynamic) textoCelda;

  const PasajerosTransporteDialog({
    super.key,
    required this.baseUrl,
    required this.transporteId,
    required this.etiqueta,
    required this.textoCelda,
  });

  @override
  State<PasajerosTransporteDialog> createState() =>
      _PasajerosTransporteDialogState();
}

class _PasajerosTransporteDialogState extends State<PasajerosTransporteDialog> {
  List<Map<String, dynamic>> _pasajeros = [];
  bool _cargando = true;
  String? _error;

  final ScrollController _scrollH = ScrollController();
  final ScrollController _scrollV = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargarPasajeros();
  }

  @override
  void dispose() {
    _scrollH.dispose();
    _scrollV.dispose();
    super.dispose();
  }

  Future<void> _cargarPasajeros() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/transportes/'
          '${Uri.encodeComponent(widget.transporteId.toString())}'
          '/pasajeros',
        ),
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (respuesta.statusCode == 200) {
        final lista = jsonDecode(respuesta.body) as List<dynamic>;
        setState(() {
          _pasajeros =
              lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      } else {
        String mensaje = 'No fue posible consultar los pasajeros '
            '(código ${respuesta.statusCode})';
        try {
          final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
          mensaje = (datos['error'] ?? mensaje).toString();
        } catch (_) {}
        setState(() => _error = mensaje);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar con el servidor: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  Widget _contenido(double ancho) {
    if (_cargando) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.rojo),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _cargarPasajeros,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    // Las columnas salen de los campos que devuelve el procedimiento.
    final columnas =
        _pasajeros.isEmpty ? <String>[] : _pasajeros.first.keys.toList();

    final List<DataColumn> columnasTabla;
    final List<DataRow> filasTabla;

    if (_pasajeros.isEmpty) {
      columnasTabla = const [DataColumn(label: Text('Pasajeros'))];
      filasTabla = const [
        DataRow(
          cells: [DataCell(Text('Este transporte aún no tiene pasajeros'))],
        ),
      ];
    } else {
      columnasTabla = columnas
          .map(
            (c) => DataColumn(
              label: Text(
                widget.etiqueta(c),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          )
          .toList();

      filasTabla = _pasajeros
          .map(
            (fila) => DataRow(
              cells: columnas
                  .map((c) => DataCell(Text(widget.textoCelda(fila[c]))))
                  .toList(),
            ),
          )
          .toList();
    }

    // Tabla con scroll vertical y horizontal.
    return SizedBox(
      height: 320,
      child: Scrollbar(
        controller: _scrollH,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollH,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: ancho),
            child: Scrollbar(
              controller: _scrollV,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollV,
                child: DataTable(
                  columns: columnasTabla,
                  rows: filasTabla,
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
    final pantalla = MediaQuery.of(context).size.width;
    final ancho = pantalla > 796 ? 700.0 : pantalla - 96;

    return AlertDialog(
      shape: AppTheme.formaTarjeta,
      title: Row(
        children: [
          const Icon(Icons.groups, color: AppColors.verde),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Pasajeros del transporte ${widget.transporteId}'),
          ),
        ],
      ),
      content: SizedBox(
        width: ancho,
        child: _contenido(ancho),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}