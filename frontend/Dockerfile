# syntax=docker/dockerfile:1
# =============================================================================
# Imagen del frontend React + Vite servida por nginx sin privilegios — Ítem 3.3
# (THR-05 / CTL-05) · Responsable: Brandon Corrales · Revisor: Roberto
#
# Imágenes base fijadas por digest (consultadas el 2026-11-11 con docker pull + docker inspect):
#   node:22-alpine                      -> sha256:5b05da3f938f1c604b24c633646d48805a6667f378cb4908438616f3cc48a0bf
#   nginxinc/nginx-unprivileged:alpine  -> sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e  (nginx 1.31.7)
# =============================================================================

# ---------- Etapa 1: compilación de la SPA ----------
FROM node:22-alpine@sha256:5b05da3f938f1c604b24c633646d48805a6667f378cb4908438616f3cc48a0bf AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# ---------- Etapa 2: runtime estático (sin Node, sin código fuente) ----------
FROM nginxinc/nginx-unprivileged:alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e AS runtime

ARG COMMIT_SHA=local
LABEL org.opencontainers.image.title="proyecto-seguridad-frontend" \
      org.opencontainers.image.source="https://github.com/RobertoUNA/proyecto-seguridad" \
      org.opencontainers.image.revision="${COMMIT_SHA}"

# La imagen base (alpine 3.24.2) trae paquetes con CVE HIGH/CRITICAL que ya tienen
# versión corregida en el repositorio de Alpine (curl, libexpat, libxslt, musl, zlib,
# brotli-libs). Se actualizan como root SOLO durante el build y se vuelve a UID 101.
# curl no se necesita (el HEALTHCHECK usa wget de busybox), así que se elimina.
USER root
RUN apk upgrade --no-cache \
 && apk del --no-cache curl
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html

# Ítem 6.2: upstream de /api configurable sin reconstruir la imagen (misma imagen y digest en
# docker-compose y en Render). El entrypoint de la imagen base procesa /etc/nginx/templates con
# envsubst, SOLO para variables API_* (las variables de nginx como $host no se tocan), y escribe
# en /tmp (admite escritura con read_only + tmpfs). Por defecto, el backend de docker-compose.
ENV API_UPSTREAM=http://backend:3000 \
    NGINX_ENVSUBST_FILTER=^API_ \
    NGINX_ENVSUBST_OUTPUT_DIR=/tmp

# Usuario no root explícito (UID 101 = nginx en la imagen unprivileged). Ver policy/container.rego (3.4).
USER 101

EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
