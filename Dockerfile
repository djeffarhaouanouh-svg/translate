# syntax=docker/dockerfile:1
# --- Flutter Web (release) ---
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build

# Build-time args. Railway forwards service variables to Docker builds as
# build args when the ARG name matches, so we read the Next.js-style names
# that already exist in the Railway project and re-emit them under the
# Flutter-side dart-define names the Dart code expects.
ARG NEXT_PUBLIC_SUPABASE_URL=""
ARG NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=""

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY analysis_options.yaml ./
COPY lib ./lib
COPY web ./web

RUN flutter config --no-analytics \
  && flutter build web --release \
       --dart-define=TOKEN_API_BASE= \
       --dart-define=SUPABASE_URL=${NEXT_PUBLIC_SUPABASE_URL} \
       --dart-define=SUPABASE_PUBLISHABLE_KEY=${NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY}

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
