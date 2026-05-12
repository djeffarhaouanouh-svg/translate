# syntax=docker/dockerfile:1
# --- Flutter Web (release) ---
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY analysis_options.yaml ./
COPY lib ./lib
COPY web ./web

RUN flutter config --no-analytics \
  && flutter build web --release --dart-define=TOKEN_API_BASE=

# --- Node: API + static web ---
FROM node:22-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev

COPY backend/server.js ./server.js
COPY --from=flutter-build /app/build/web ./web

EXPOSE 8080
ENV PORT=8080

CMD ["node", "server.js"]
