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
    port: 3308,
    user: 'admin',
    password: 'admin',
    database: 'viaje',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

// ============================================
// RUTAS DE CIUDADES
// ============================================
app.get('/api/ciudades', async (req, res) => {
    try {
        const [rows] = await pool.query('SELECT * FROM ciudad');
        res.json(rows);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error al obtener las ciudades' });
    }
});

// ============================================
// RUTAS DE VIAJES
// ============================================

// Registrar un nuevo viaje
app.post('/api/viajes', async (req, res) => {
    try {
        const { ciudad_id, fecha_viaje, motivo, usuario_uuid } = req.body;

        if (!usuario_uuid) {
            return res.status(401).json({ error: 'No se encontró el UUID del usuario' });
        }

        if (!ciudad_id || !fecha_viaje) {
            return res.status(400).json({ error: 'Faltan campos obligatorios' });
        }

        const query = 'INSERT INTO viaje (usuario_uuid, ciudad_id, fecha_viaje, motivo) VALUES (?, ?, ?, ?)';
        const [result] = await pool.query(query, [usuario_uuid, ciudad_id, fecha_viaje, motivo || '']);

        res.status(201).json({ 
            message: 'Viaje registrado con éxito', 
            viaje_id: result.insertId 
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error al registrar el viaje' });
    }
});

// Obtener los viajes de un usuario
app.get('/api/viajes/:uuid', async (req, res) => {
    try {
        const { uuid } = req.params;

        const query = `
            SELECT v.id, c.nombre AS ciudad, c.pais, v.fecha_viaje, v.motivo 
            FROM viaje v
            JOIN ciudad c ON v.ciudad_id = c.id
            WHERE v.usuario_uuid = ?
        `;
        const [rows] = await pool.query(query, [uuid]);
        res.json(rows);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Error al consultar los viajes' });
    }
});

// Iniciar servidor
const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
    console.log(`✅ Servidor corriendo en el puerto ${PORT}`);
});