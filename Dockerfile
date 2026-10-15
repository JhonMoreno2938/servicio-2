FROM node:18-alpine
WORKDIR /app
COPY backend-viajes/package*.json ./
RUN npm install --production
COPY backend-viajes/ .
EXPOSE 3004
CMD ["node", "server.js"]