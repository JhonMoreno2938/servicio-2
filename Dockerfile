FROM node:18-alpine
WORKDIR /app
COPY backend-viajes/package*.json ./
RUN npm install --production
COPY backend-viajes/ .
EXPOSE 8083
CMD ["node", "server.js"]