# Usamos una imagen oficial y ligera de Node.js
FROM node:18-alpine

# Definimos el directorio de trabajo dentro del contenedor
WORKDIR /app

# Copiamos los archivos de dependencias del backend
COPY package*.json ./

# Instalamos únicamente las dependencias de producción
RUN npm install --production

# Copiamos todo el código fuente del backend y la carpeta public con Flutter adentro
COPY . .

# Exponemos el puerto en el que corre tu servidor (3001)
EXPOSE 3002

# Comando para iniciar la aplicación
CMD ["node", "server.js"]