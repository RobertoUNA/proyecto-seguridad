# syntax=docker/dockerfile:1
# =============================================================================
# Imagen del backend NestJS — Ítem 3.3 (THR-05 / CTL-05)
# Responsable: Brandon Corrales · Revisor: Roberto
#
# Imagen base fijada por digest (consultado el 2026-11-11 con
# `docker pull node:22-alpine` + `docker inspect --format '{{index .RepoDigests 0}}'`):
#   node:22-alpine  ->  sha256:5b05da3f938f1c604b24c633646d48805a6667f378cb4908438616f3cc48a0bf  (Node v22.23.5)
# Para actualizarla: repetir la consulta, cambiar el digest en AMBAS etapas y
# volver a ejecutar scripts/container-scan (Trivy) antes de aprobar la imagen.
# =============================================================================

# ---------- Etapa 1: compilación (incluye devDependencies, no llega a runtime) ----------
FROM node:22-alpine@sha256:5b05da3f938f1c604b24c633646d48805a6667f378cb4908438616f3cc48a0bf AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY nest-cli.json tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

# ---------- Etapa 2: runtime (solo dependencias de producción + dist/) ----------
FROM node:22-alpine@sha256:5b05da3f938f1c604b24c633646d48805a6667f378cb4908438616f3cc48a0bf AS runtime
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app

# Los archivos quedan con dueño root y el proceso corre como `node`:
# la aplicación puede leer su código pero no modificarlo.
COPY package.json package-lock.json ./
# Tras instalar, se eliminan npm, npx, corepack y yarn: no se usan en ejecución y
# sus dependencias internas (pacote, sigstore, brace-expansion, ip-address, picomatch)
# eran hallazgos HIGH de Trivy en la imagen. Menos binarios = menos superficie (CTL-05).
RUN npm ci --omit=dev --no-audit --no-fund \
 && npm cache clean --force \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-* /root/.npm
COPY --from=build /app/dist ./dist

# Trazabilidad commit <-> imagen (también se fija como etiqueta OCI en el build).
ARG COMMIT_SHA=local
ENV COMMIT_SHA=${COMMIT_SHA}
LABEL org.opencontainers.image.title="proyecto-seguridad-backend" \
      org.opencontainers.image.source="https://github.com/RobertoUNA/proyecto-seguridad" \
      org.opencontainers.image.revision="${COMMIT_SHA}"

# Usuario no root explícito (UID 1000 de la imagen oficial). Ver policy/container.rego (3.4).
USER node

EXPOSE 3000
# wget de busybox (la imagen alpine no trae curl).
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:3000/api/health || exit 1

CMD ["node", "dist/main.js"]
