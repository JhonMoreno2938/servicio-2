require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const path = require('path');
const multer = require('multer');
const { v2: cloudinary } = require('cloudinary');

const app = express();
app.use(express.json());
app.use(cors());

// Servir los archivos estáticos de la carpeta public
app.use(express.static(path.join(__dirname, 'public')));

// Configuración de la conexión a MySQL
const pool = mysql.createPool({
    host: process.env.DB_HOST || '192.168.0.103',
    port: process.env.DB_PORT || 3310,
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || 'admin',
    database: process.env.DB_NAME || 'rastro',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

// ============================================
// UTILIDADES
// ============================================
const esTexto = (v) => typeof v === 'string' && v.trim().length > 0;
const opcional = (v) => (typeof v === 'string' ? v.trim() || null : null);

// ============================================
// ENDPOINT: Obtener solo los nombres de las especies
// ============================================
app.get('/api/especies/nombres', async (req, res) => {
    try {
        const query = 'SELECT nombre FROM especie ORDER BY nombre ASC';
        const [rows] = await pool.execute(query);

        // Transformamos el resultado para devolver directamente un array plano de strings ['Perro', 'Gato', ...]
        const nombres = rows.map(especie => especie.nombre);

        return res.status(200).json(nombres);

    } catch (error) {
        console.error('Error al obtener los nombres de las especies:', error);
        return res.status(500).json({ error: 'Error interno del servidor al consultar las especies.' });
    }
});

// ============================================
// ENDPOINT: Subir foto (POST /api/upload)
// Sube la imagen a Cloudinary y devuelve su URL pública
// ============================================
cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true
});

// La imagen se mantiene en memoria (no se escribe en disco)
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 }, // máx. 5 MB
    fileFilter: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase();
        const extOk = ['.jpg', '.jpeg', '.png', '.webp'].includes(ext);
        // Flutter (http.MultipartFile.fromBytes) puede enviar 'application/octet-stream'
        const mimeOk = file.mimetype.startsWith('image/') || file.mimetype === 'application/octet-stream';
        const permitido = extOk && mimeOk;
        cb(permitido ? null : new Error('Solo se permiten imágenes JPG, PNG o WEBP.'), permitido);
    }
});

// Convierte el buffer en un stream y lo sube a Cloudinary
const subirACloudinary = (buffer) =>
    new Promise((resolve, reject) => {
        const stream = cloudinary.uploader.upload_stream(
            { folder: 'rastro/reportes', resource_type: 'image' },
            (error, result) => (error ? reject(error) : resolve(result))
        );
        stream.end(buffer);
    });

app.post('/api/upload', (req, res) => {
    upload.single('foto')(req, res, async (err) => {
        if (err) {
            return res.status(400).json({ error: err.message });
        }
        if (!req.file) {
            return res.status(400).json({ error: 'No se recibió ninguna imagen.' });
        }

        try {
            const result = await subirACloudinary(req.file.buffer);
            return res.status(201).json({
                url: result.secure_url,       // URL completa https://res.cloudinary.com/...
                public_id: result.public_id   // útil si luego quieres borrar la imagen
            });
        } catch (error) {
            console.error('Error al subir imagen a Cloudinary:', error);
            return res.status(500).json({ error: 'No se pudo subir la imagen.' });
        }
    });
});

// ============================================
// ENDPOINT: Registrar Reporte mediante Stored Procedure
// ============================================
app.post('/api/reportes', async (req, res) => {
    try {
        const {
            nombre_usuario,
            nombre_animal,
            nombre_especie,
            descripcion_animal,
            descripcion_lugar,
            fecha_perdio,
            url_foto
        } = req.body;

        // Validaciones básicas de campos obligatorios
        if (!esTexto(nombre_usuario) || !esTexto(nombre_animal) || !esTexto(nombre_especie) ||
            !esTexto(descripcion_animal) || !esTexto(descripcion_lugar) || !esTexto(fecha_perdio) || !esTexto(url_foto)) {
            return res.status(400).json({
                error: 'Todos los campos son obligatorios para registrar el reporte.'
            });
        }

        // Llamada al Stored Procedure:
        // Pasamos 7 parámetros de entrada (?) y declaramos uno de salida (@mensaje)
        const query = 'CALL registrar_reporte(?, ?, ?, ?, ?, ?, ?, @mensaje)';
        const values = [
            nombre_usuario.trim(),
            nombre_animal.trim(),
            nombre_especie.trim(),
            descripcion_animal.trim(),
            descripcion_lugar.trim(),
            fecha_perdio.trim(),
            url_foto.trim()
        ];

        // Ejecutamos la llamada al SP
        await pool.execute(query, values);

        // Recuperamos el valor de la variable de salida (@mensaje) definida en MySQL
        const [resultMensaje] = await pool.execute('SELECT @mensaje AS mensaje');
        const mensajeSp = resultMensaje[0].mensaje;

        // Verificamos si el procedimiento retornó un mensaje de error controlado
        if (mensajeSp && mensajeSp.startsWith('Error:')) {
            return res.status(400).json({ error: mensajeSp });
        }

        return res.status(201).json({
            mensaje: mensajeSp || 'Se registró el reporte con éxito.'
        });

    } catch (error) {
        console.error('Error al registrar el reporte:', error);
        return res.status(500).json({ error: 'Error interno del servidor al procesar el reporte.' });
    }
});

// ============================================
// ENDPOINT: Ver mis reportes mediante Stored Procedure (GET)
// ============================================
app.get('/api/reportes/usuario/:nombre_usuario', async (req, res) => {
    try {
        const { nombre_usuario } = req.params;

        // Validar que el parámetro no esté vacío
        if (!esTexto(nombre_usuario)) {
            return res.status(400).json({
                error: 'El nombre de usuario es obligatorio en la ruta.'
            });
        }

        // Llamada al Stored Procedure
        const query = 'CALL mirar_mis_reportes(?)';
        const [rows] = await pool.execute(query, [nombre_usuario.trim()]);

        // MySQL con `mysql2/promise` devuelve los resultados del SP en el primer índice del arreglo (`rows[0]`)
        const reportes = rows[0];

        return res.status(200).json({
            usuario: nombre_usuario.trim(),
            reportes: reportes
        });

    } catch (error) {
        console.error('Error al consultar los reportes del usuario:', error);
        return res.status(500).json({ error: 'Error interno del servidor al consultar los reportes.' });
    }
});

// ============================================
// ENDPOINT: Ver reportes activos de otros usuarios (GET)
// ============================================
app.get('/api/reportes', async (req, res) => {
    try {
        const { usuario } = req.query;

        // Validar que se envíe el usuario que está consultando
        if (!esTexto(usuario)) {
            return res.status(400).json({
                error: 'El parámetro "usuario" es obligatorio en la consulta (ej. /api/reportes?usuario=cgomez).'
            });
        }

        // Llamada al Stored Procedure pasando el parámetro de entrada
        const query = 'CALL mirar_reportes(?)';
        const [rows] = await pool.execute(query, [usuario.trim()]);

        const reportes = rows[0];

        return res.status(200).json({
            total_reportes: reportes.length,
            reportes: reportes
        });

    } catch (error) {
        console.error('Error al consultar los reportes:', error);
        return res.status(500).json({ error: 'Error interno del servidor al consultar los reportes.' });
    }
});

// ============================================
// ENDPOINT: Registrar Avistamiento mediante Stored Procedure (POST)
// ============================================
app.post('/api/avistamientos', async (req, res) => {
    try {
        const {
            nombre_usuario,
            descripcion,
            id_reporte,
            fecha_encontro
        } = req.body;

        // Validaciones básicas de campos obligatorios
        if (!esTexto(nombre_usuario) || !esTexto(descripcion) || !id_reporte || !esTexto(fecha_encontro)) {
            return res.status(400).json({
                error: 'Los campos nombre_usuario, descripcion, id_reporte y fecha_encontro son obligatorios.'
            });
        }

        // Llamada al Stored Procedure:
        // Pasamos 4 parámetros de entrada (?) y declaramos uno de salida (@mensaje)
        const query = 'CALL registrar_avistamiento(?, ?, ?, ?, @mensaje)';
        const values = [
            nombre_usuario.trim(),
            descripcion.trim(),
            id_reporte,
            fecha_encontro.trim()
        ];

        // Ejecutamos la llamada al SP
        await pool.execute(query, values);

        // Recuperamos el valor de la variable de salida (@mensaje) definida en MySQL
        const [resultMensaje] = await pool.execute('SELECT @mensaje AS mensaje');
        const mensajeSp = resultMensaje[0].mensaje;

        // Verificamos si el procedimiento retornó un mensaje de error controlado
        if (mensajeSp && mensajeSp.startsWith('Error:')) {
            return res.status(400).json({ error: mensajeSp });
        }

        return res.status(201).json({
            mensaje: mensajeSp || 'Se registró el avistamiento con éxito.'
        });

    } catch (error) {
        console.error('Error al registrar el avistamiento:', error);
        return res.status(500).json({ error: 'Error interno del servidor al procesar el avistamiento.' });
    }
});

// ============================================
// ENDPOINT: Consultar reporte específico por ID (GET)
// ============================================
app.get('/api/reportes/:id/detalle', async (req, res) => {
    try {
        const { id } = req.params;

        // Validar que el ID sea numérico
        if (!id || isNaN(id)) {
            return res.status(400).json({
                error: 'El ID del reporte es obligatorio y debe ser un número válido.'
            });
        }

        // Llamada al Stored Procedure
        const query = 'CALL consultar_mi_reporte(?)';
        const [rows] = await pool.execute(query, [id]);

        const resultados = rows[0];

        // Si no existe el reporte o no tiene avistamientos, de igual forma validamos si trajo filas
        if (!resultados || resultados.length === 0) {
            return res.status(404).json({ error: 'Reporte no encontrado.' });
        }

        return res.status(200).json({
            id_reporte: id,
            total_avistamientos: resultados.length,
            avistamientos: resultados
        });

    } catch (error) {
        console.error('Error al consultar el detalle del reporte:', error);
        return res.status(500).json({ error: 'Error interno del servidor al consultar el reporte.' });
    }
});

// ============================================
// ENDPOINT: Cambiar el estado de un reporte a 'cancelado' (PATCH)
// ============================================
app.patch('/api/reportes/:id/cancelar', async (req, res) => {
    try {
        const { id } = req.params;

        // Validar que el ID sea numérico
        if (!id || isNaN(id)) {
            return res.status(400).json({
                error: 'El ID del reporte es obligatorio y debe ser un número válido.'
            });
        }

        const query = `
            UPDATE reporte
            SET estado_reporte = 'cancelado'
            WHERE id = ?
        `;

        const [result] = await pool.execute(query, [id]);

        // Verificar si el reporte existe en la base de datos
        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Reporte no encontrado.' });
        }

        return res.status(200).json({
            mensaje: 'El estado del reporte ha sido actualizado a cancelado con éxito.'
        });

    } catch (error) {
        console.error('Error al cancelar el reporte:', error);
        return res.status(500).json({ error: 'Error interno del servidor al procesar la solicitud.' });
    }
});

// ============================================
// ENDPOINT: Cambiar el estado de un reporte a 'encontrado' (PATCH)
// ============================================
app.patch('/api/reportes/:id/encontrado', async (req, res) => {
    try {
        const { id } = req.params;

        // Validar que el ID sea numérico
        if (!id || isNaN(id)) {
            return res.status(400).json({
                error: 'El ID del reporte es obligatorio y debe ser un número válido.'
            });
        }

        const query = `
            UPDATE reporte
            SET estado_reporte = 'encontrado'
            WHERE id = ?
        `;

        const [result] = await pool.execute(query, [id]);

        // Verificar si el reporte existe en la base de datos
        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Reporte no encontrado.' });
        }

        return res.status(200).json({
            mensaje: 'El estado del reporte ha sido actualizado a encontrado con éxito.'
        });

    } catch (error) {
        console.error('Error al actualizar el reporte a encontrado:', error);
        return res.status(500).json({ error: 'Error interno del servidor al procesar la solicitud.' });
    }
});

// Iniciar servidor
const PORT = process.env.PORT || 8083;
app.listen(PORT, () => {
    console.log(`✅ Servidor corriendo en el puerto ${PORT}`);
});