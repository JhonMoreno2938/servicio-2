const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const path = require('path');

const app = express();
app.use(express.json());
app.use(cors());

// Servir los archivos estáticos de la carpeta public
app.use(express.static(path.join(__dirname, 'public')));

// Configuración de la conexión a MySQL
const pool = mysql.createPool({
    host: '192.168.0.103',
    port: 3309,
    user: 'root',
    password: 'admin',
    database: 'terminal',
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
// ENDPOINT: REGISTRAR PERSONA
// POST /api/personas
// ============================================
app.post('/api/personas', async (req, res) => {
    try {
        const {
            primer_nombre,
            segundo_nombre,
            primer_apellido,
            segundo_apellido,
            numero_contacto,
            usuario
        } = req.body || {};

        // Obligatorios: primer_nombre, primer_apellido, numero_contacto, usuario
        if (
            !esTexto(primer_nombre) ||
            !esTexto(primer_apellido) ||
            !esTexto(numero_contacto) ||
            !esTexto(usuario)
        ) {
            return res.status(400).json({
                error: 'Los campos primer_nombre, primer_apellido, numero_contacto y usuario son obligatorios'
            });
        }

        // Longitudes máximas según la tabla (VARCHAR 50 y 20)
        if (
            primer_nombre.trim().length > 50 ||
            primer_apellido.trim().length > 50 ||
            usuario.trim().length > 50 ||
            numero_contacto.trim().length > 20 ||
            (opcional(segundo_nombre) || '').length > 50 ||
            (opcional(segundo_apellido) || '').length > 50
        ) {
            return res.status(400).json({
                error: 'Algún campo supera la longitud permitida (50 caracteres; número de contacto 20)'
            });
        }

        const [result] = await pool.execute(
            `INSERT INTO persona (
                primer_nombre,
                segundo_nombre,
                primer_apellido,
                segundo_apellido,
                numero_contacto,
                usuario
            ) VALUES (?, ?, ?, ?, ?, ?)`,
            [
                primer_nombre.trim(),
                opcional(segundo_nombre),
                primer_apellido.trim(),
                opcional(segundo_apellido),
                numero_contacto.trim(),
                usuario.trim()
            ]
        );

        return res.status(201).json({
            mensaje: 'Persona registrada con éxito',
            id: result.insertId
        });

    } catch (error) {
        console.error('Error al registrar la persona:', error);

        // usuario es UNIQUE
        if (error.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({
                error: 'El nombre de usuario ya está registrado'
            });
        }

        return res.status(500).json({
            error: 'Error interno al registrar la persona'
        });
    }
});

// ============================================
// ENDPOINT: CONSULTAR PERSONA POR USUARIO
// GET /api/personas/:usuario
// ============================================
app.get('/api/personas/:usuario', async (req, res) => {
    try {
        const { usuario } = req.params;

        if (!esTexto(usuario)) {
            return res.status(400).json({
                error: 'El nombre de usuario es obligatorio'
            });
        }

        const [rows] = await pool.execute(
            `SELECT
                primer_nombre,
                segundo_nombre,
                primer_apellido,
                segundo_apellido,
                numero_contacto,
                usuario
            FROM persona
            WHERE usuario = ?`,
            [usuario.trim()]
        );

        if (rows.length === 0) {
            return res.status(404).json({
                error: 'No existe una persona registrada con ese usuario'
            });
        }

        return res.status(200).json(rows[0]);

    } catch (error) {
        console.error('Error al consultar la persona:', error);

        return res.status(500).json({
            error: 'Error interno al consultar la persona'
        });
    }
});

// ============================================
// ENDPOINT: ACTUALIZAR NÚMERO DE CONTACTO POR USUARIO
// PATCH /api/personas/usuario/:usuario/contacto
// ============================================
app.patch('/api/personas/usuario/:usuario/contacto', async (req, res) => {
    try {
        const { usuario } = req.params;
        const { numero_contacto } = req.body;

        // Validar parámetro de la URL
        if (!usuario || typeof usuario !== 'string' || !usuario.trim()) {
            return res.status(400).json({
                error: 'El nombre de usuario es obligatorio'
            });
        }

        // Validar campo obligatorio en el body
        if (!numero_contacto || typeof numero_contacto !== 'string' || !numero_contacto.trim()) {
            return res.status(400).json({
                error: 'El campo numero_contacto es obligatorio'
            });
        }

        const query = `
            UPDATE persona
            SET numero_contacto = ?
            WHERE usuario = ?
        `;

        const [result] = await pool.execute(query, [
            numero_contacto.trim(),
            usuario.trim()
        ]);

        // Si no se afectó ninguna fila, el usuario no existe
        if (result.affectedRows === 0) {
            return res.status(404).json({
                error: 'No existe una persona registrada con ese usuario'
            });
        }

        return res.status(200).json({
            mensaje: 'Número de contacto actualizado con éxito'
        });

    } catch (error) {
        console.error('Error al actualizar el número de contacto:', error);

        return res.status(500).json({
            error: 'Error interno al actualizar el número de contacto'
        });
    }
});

// ============================================
// ENDPOINT: OBTENER SOLO NOMBRES DE TIPOS DE TRANSPORTE
// GET /api/tipos-transporte/nombres
// ============================================
app.get('/api/tipos-transporte/nombres', async (req, res) => {
    try {
        const query = `
            SELECT nombre 
            FROM tipo_transporte 
            ORDER BY nombre ASC
        `;

        const [rows] = await pool.execute(query);

        return res.status(200).json(rows);

    } catch (error) {
        console.error('Error al consultar los nombres de tipos de transporte:', error);

        return res.status(500).json({
            error: 'Error interno al consultar los tipos de transporte'
        });
    }
});

// ============================================
// ENDPOINT: REGISTRAR TRANSPORTE
// POST /api/transportes
// Ejecuta el procedimiento almacenado registrar_transporte
// ============================================
app.post('/api/transportes', async (req, res) => {
    try {
        const {
            nombre_tipo_transporte,
            nombre_usuario,
            fecha_hora_salida_comunidad,
            punto_encuentro_salida_comunidad,
            fecha_hora_salida_ciudad,
            punto_encuentro_salida_ciudad,
            capacidad
        } = req.body;

        // Validación básica de campos requeridos
        if (
            !nombre_tipo_transporte ||
            !nombre_usuario ||
            !fecha_hora_salida_comunidad ||
            !punto_encuentro_salida_comunidad ||
            !fecha_hora_salida_ciudad ||
            !punto_encuentro_salida_ciudad ||
            capacidad === undefined || capacidad === null
        ) {
            return res.status(400).json({
                error: 'Error: Todos los campos son obligatorios'
            });
        }

        // Llamada al procedimiento almacenado pasando parámetros y la variable @mensaje para el OUT
        const queryCall = `
            CALL registrar_transporte(
                ?, ?, ?, ?, ?, ?, ?, @mensaje
            )
        `;

        await pool.query(queryCall, [
            nombre_tipo_transporte.trim(),
            nombre_usuario.trim(),
            fecha_hora_salida_comunidad,
            punto_encuentro_salida_comunidad.trim(),
            fecha_hora_salida_ciudad,
            punto_encuentro_salida_ciudad.trim(),
            Number(capacidad)
        ]);

        // Obtener el valor de la variable de salida @mensaje
        const [resultado] = await pool.query('SELECT @mensaje AS mensaje');
        const mensaje = resultado[0]?.mensaje || '';

        // Comprobar la respuesta del procedimiento almacenado
        if (mensaje.startsWith('Éxito')) {
            return res.status(201).json({
                mensaje
            });
        } else {
            return res.status(400).json({
                error: mensaje || 'No fue posible registrar el transporte'
            });
        }

    } catch (error) {
        console.error('Error al registrar el transporte:', error);

        return res.status(500).json({
            error: 'Error interno al registrar el transporte'
        });
    }
});

// ============================================
// ENDPOINT: CONSULTAR TRANSPORTES DE UN USUARIO
// GET /api/transportes/usuario/:usuario
// Ejecuta el procedimiento almacenado consultar_mis_transportes
// ============================================
app.get('/api/transportes/usuario/:usuario', async (req, res) => {
    try {
        const { usuario } = req.params;

        // Validar que el parámetro usuario no esté vacío
        if (!usuario || typeof usuario !== 'string' || !usuario.trim()) {
            return res.status(400).json({
                error: 'El nombre de usuario es obligatorio'
            });
        }

        // Llamar al procedimiento almacenado
        const queryCall = 'CALL consultar_mis_transportes(?)';
        const [resultado] = await pool.query(queryCall, [usuario.trim()]);

        // En mysql2, el primer elemento (resultado[0]) contiene las filas devueltas por el SELECT del procedimiento
        const misTransportes = resultado[0] || [];

        return res.status(200).json(misTransportes);

    } catch (error) {
        console.error('Error al consultar los transportes del usuario:', error);

        return res.status(500).json({
            error: 'Error interno al consultar los transportes'
        });
    }
});

// ============================================
// ENDPOINT: INACTIVAR UN TRANSPORTE
// PATCH /api/transportes/:id/inactivar
// ============================================
app.patch('/api/transportes/:id/inactivar', async (req, res) => {
    try {
        const { id } = req.params;

        // Validar que el ID sea un número válido
        if (!id || isNaN(id)) {
            return res.status(400).json({
                error: 'El ID del transporte debe ser un número válido'
            });
        }

        const query = `
            UPDATE transporte
            SET estado = 'inactivo'
            WHERE id = ?
        `;

        const [result] = await pool.execute(query, [id]);

        // Si no afectó ninguna fila, el ID no existe en la BD
        if (result.affectedRows === 0) {
            return res.status(404).json({
                error: 'No se encontró un transporte con ese ID'
            });
        }

        return res.status(200).json({
            mensaje: 'Transporte inactivado con éxito'
        });

    } catch (error) {
        console.error('Error al inactivar el transporte:', error);

        return res.status(500).json({
            error: 'Error interno al inactivar el transporte'
        });
    }
});

// ============================================
// ENDPOINT: CONSULTAR TRANSPORTES ACTIVOS (EXCLUYENDO AL USUARIO ACTUAL)
// GET /api/transportes/disponibles/:usuario
// Ejecuta el procedimiento almacenado consultar_transportes
// ============================================
app.get('/api/transportes/disponibles/:usuario', async (req, res) => {
    try {
        const { usuario } = req.params;

        // Validar que el parámetro usuario esté presente
        if (!usuario || typeof usuario !== 'string' || !usuario.trim()) {
            return res.status(400).json({
                error: 'El nombre de usuario es obligatorio'
            });
        }

        // Llamar al procedimiento almacenado pasando el nombre de usuario
        const queryCall = 'CALL consultar_transportes(?)';
        const [resultado] = await pool.query(queryCall, [usuario.trim()]);

        // Extraer los resultados de la primera posición del array retornado por mysql2
        const transportesDisponibles = resultado[0] || [];

        return res.status(200).json(transportesDisponibles);

    } catch (error) {
        console.error('Error al consultar los transportes disponibles:', error);

        return res.status(500).json({
            error: 'Error interno al consultar los transportes'
        });
    }
});


app.post('/api/transportes/adquirir', async (req, res) => {
    try {
        const { transporte_id, nombre_usuario, capacidad } = req.body;

        if (!transporte_id || !nombre_usuario || !capacidad) {
            return res.status(400).json({
                error: 'Los campos transporte_id, nombre_usuario y capacidad son obligatorios'
            });
        }

        const queryCall = 'CALL adquirir_transporte(?, ?, ?, @mensaje)';
        await pool.query(queryCall, [Number(transporte_id), nombre_usuario.trim(), Number(capacidad)]);

        const [resultado] = await pool.query('SELECT @mensaje AS mensaje');
        const mensaje = resultado[0]?.mensaje || '';

        if (mensaje.startsWith('Éxito')) {
            return res.status(200).json({ mensaje });
        } else {
            return res.status(400).json({ error: mensaje });
        }
    } catch (error) {
        console.error('Error al adquirir transporte:', error);
        return res.status(500).json({ error: 'Error interno al adquirir el transporte' });
    }
});

// ============================================
// ENDPOINT: ACTUALIZAR O LIBERAR CUPOS DE UN TRANSPORTE
// PATCH /api/transportes/actualizar-cupos
// ============================================
app.patch('/api/transportes/actualizar-cupos', async (req, res) => {
    try {
        const { transporte_id, nombre_usuario, cupos_anteriores, cupos_nuevos } = req.body;

        if (
            !transporte_id ||
            !nombre_usuario ||
            cupos_anteriores === undefined ||
            cupos_nuevos === undefined
        ) {
            return res.status(400).json({
                error: 'Los campos transporte_id, nombre_usuario, cupos_anteriores y cupos_nuevos son obligatorios'
            });
        }

        const queryCall = 'CALL actualizar_cupos_transporte(?, ?, ?, ?, @mensaje)';
        await pool.query(queryCall, [
            Number(transporte_id),
            nombre_usuario.trim(),
            Number(cupos_anteriores),
            Number(cupos_nuevos)
        ]);

        const [resultado] = await pool.query('SELECT @mensaje AS mensaje');
        const mensaje = resultado[0]?.mensaje || '';

        if (mensaje.startsWith('Éxito')) {
            return res.status(200).json({ mensaje });
        } else {
            return res.status(400).json({ error: mensaje });
        }
    } catch (error) {
        console.error('Error al actualizar cupos:', error);
        return res.status(500).json({ error: 'Error interno al actualizar cupos' });
    }
});

// ============================================
// ENDPOINT: CONSULTAR CUPOS DE UN USUARIO EN UN TRANSPORTE
// GET /api/transportes/:transporte_id/cupos/:usuario
// Ejecuta el procedimiento almacenado mirar_cupos_transporte
// ============================================
app.get('/api/transportes/:transporte_id/cupos/:usuario', async (req, res) => {
    try {
        const { transporte_id, usuario } = req.params;

        // Validar el ID del transporte
        if (!transporte_id || isNaN(transporte_id)) {
            return res.status(400).json({
                error: 'El ID del transporte debe ser un número válido'
            });
        }

        // Validar el nombre de usuario
        if (!usuario || typeof usuario !== 'string' || !usuario.trim()) {
            return res.status(400).json({
                error: 'El nombre de usuario es obligatorio'
            });
        }

        // Llamada al procedimiento almacenado
        const queryCall = 'CALL mirar_cupos_transporte(?, ?)';
        const [resultado] = await pool.query(queryCall, [
            Number(transporte_id),
            usuario.trim()
        ]);

        const datosCupo = resultado[0] || [];

        // Si la consulta no devuelve filas, significa que el usuario no tiene reserva en ese transporte
        if (datosCupo.length === 0) {
            return res.status(404).json({
                error: 'El usuario no tiene cupos reservados en este transporte'
            });
        }

        // Retornar el registro con el ID del transporte y la cantidad reservada
        return res.status(200).json(datosCupo[0]);

    } catch (error) {
        console.error('Error al consultar los cupos del transporte:', error);

        return res.status(500).json({
            error: 'Error interno al consultar los cupos'
        });
    }
});

// ============================================
// ENDPOINT: CONSULTAR PASAJEROS Y CUPOS DE UN TRANSPORTE
// GET /api/transportes/:id/pasajeros
// ============================================
app.get('/api/transportes/:id/pasajeros', async (req, res) => {
    try {
        const { id } = req.params;

        if (!id || isNaN(id)) {
            return res.status(400).json({
                error: 'El ID del transporte debe ser un número válido'
            });
        }

        const queryCall = 'CALL consultar_cupos(?)';
        const [resultado] = await pool.query(queryCall, [Number(id)]);

        const pasajeros = resultado[0] || [];

        return res.status(200).json(pasajeros);

    } catch (error) {
        console.error('Error al consultar pasajeros del transporte:', error);

        return res.status(500).json({
            error: 'Error interno al consultar los pasajeros'
        });
    }
});

// Iniciar servidor
const PORT = process.env.PORT || 8083;
app.listen(PORT, () => {
    console.log(`✅ Servidor corriendo en el puerto ${PORT}`);
});