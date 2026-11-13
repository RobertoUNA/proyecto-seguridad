// Ítem 7.2 (THR-06 / CTL-06) — Registro de eventos de seguridad sin datos sensibles.
//
// Filtro global de excepciones: para toda respuesta 4xx/5xx escribe UNA línea JSON en stdout.
//  · HttpException (400, 404, ...): delega en el comportamiento normal de Nest (BaseExceptionFilter).
//  · Errores no controlados (5xx): responde con el MISMO cuerpo genérico de Nest
//    ({"statusCode":500,"message":"Internal server error"}) sin delegar, para que el logger de Nest
//    no imprima el mensaje ni el stack (que pueden contener SQL) en los logs del contenedor.
// El código HTTP y el cuerpo que recibe el cliente no cambian, y no se exponen trazas de pila.
//
// Nunca se registran: valores de parámetros (query, ruta, cuerpo), el mensaje de la excepción
// (puede repetir la entrada del cliente), cabeceras (Authorization, Cookie, ...) ni la IP en claro.
import { ArgumentsHost, Catch, HttpException, HttpStatus } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import { createHash, randomBytes } from 'crypto';
import { lookup } from 'dns/promises';
import { Request, Response } from 'express';
import { isIP } from 'net';
import { CORRELATION_HEADER, RequestWithCorrelation, resolveCorrelationId } from './correlation-id.middleware';

// --- Identificador del actor -------------------------------------------------------------------
// actor_id = SHA-256(sal + IP) truncado a 16 hex. Con LOG_ACTOR_SALT el identificador es estable
// entre reinicios; sin ella se usa una sal aleatoria del proceso y NO se puede correlacionar entre
// reinicios (actor_id_scope = "process").
const ENV_SALT = process.env.LOG_ACTOR_SALT;
const ACTOR_SALT = ENV_SALT && ENV_SALT.length > 0 ? ENV_SALT : randomBytes(32).toString('hex');
const ACTOR_SCOPE = ENV_SALT && ENV_SALT.length > 0 ? 'persistent' : 'process';

// Proxy de confianza (equivalente a `trust proxy = 1`, sin tocar main.ts):
//  · LOG_TRUSTED_PROXY = nombre DNS del proxy (en docker-compose: "frontend", el nginx).
//  · X-Forwarded-For SOLO se usa si la conexión TCP viene de una IP de ese proxy, y entonces se toma
//    únicamente el ÚLTIMO salto (el que agregó el proxy). nginx lo sobrescribe con $remote_addr.
//  · Cualquier otra conexión (p. ej. directa a 127.0.0.1:3001) usa la IP del socket: un cliente no
//    puede cambiar su actor_id enviando X-Forwarded-For.
// Sin LOG_TRUSTED_PROXY (por defecto) nunca se confía en X-Forwarded-For.
const TRUSTED_PROXY = (process.env.LOG_TRUSTED_PROXY ?? '').trim();
let trustedProxyIps = new Set<string>();

const normalizeIp = (ip: string): string => ip.replace(/^::ffff:/, '');

async function refreshTrustedProxy(): Promise<void> {
  try {
    const addrs = await lookup(TRUSTED_PROXY, { all: true });
    trustedProxyIps = new Set(addrs.map((a) => normalizeIp(a.address)));
  } catch {
    // Si no resuelve, se conserva el conjunto anterior (por defecto vacío: no se confía).
  }
}

if (TRUSTED_PROXY) {
  void refreshTrustedProxy();
  setInterval(() => void refreshTrustedProxy(), 30_000).unref();
}

export function clientIp(req: Request): string {
  const peer = normalizeIp(req.socket?.remoteAddress || 'unknown');
  const forwarded = req.headers['x-forwarded-for'];
  if (!trustedProxyIps.has(peer) || typeof forwarded !== 'string') return peer;
  const hops = forwarded.split(',').map((s) => s.trim()).filter(Boolean);
  const last = hops[hops.length - 1];
  return last && isIP(normalizeIp(last)) ? normalizeIp(last) : peer;
}

export function actorId(ip: string): string {
  return createHash('sha256').update(`${ACTOR_SALT}|${ip}`).digest('hex').slice(0, 16);
}

// --- Detección de patrones sospechosos (solo se registra el NOMBRE del patrón) -----------------
const PATTERNS: Array<[string, RegExp]> = [
  ['sql_injection', /('|%27)\s*(or|and)\b|\bunion\b[\s\S]*\bselect\b|--|\/\*|;\s*(drop|delete|insert|update|select)\b|\b(or|and)\s+\d+\s*=\s*\d+|\bsleep\s*\(|\bpg_sleep\b/i],
  ['path_traversal', /\.\.[\\/]|%2e%2e|\.\.%2f|%2e%2e%2f|\/etc\/passwd|\\windows\\/i],
  ['xss', /<\s*script|javascript:|on(error|load)\s*=|<\s*img[^>]+src/i],
  ['command_injection', /[;&|`]\s*(cat|ls|id|whoami|wget|curl|sh|bash)\b|\$\(/i],
  ['oversized_input', /^[\s\S]{512,}$/],
];

function collectStrings(value: unknown, out: string[], depth = 0): void {
  if (depth > 4 || value === null || value === undefined) return;
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => collectStrings(v, out, depth + 1));
  else if (typeof value === 'object') Object.values(value as Record<string, unknown>).forEach((v) => collectStrings(v, out, depth + 1));
  else out.push(String(value));
}

function safeDecode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

export function detectPatterns(values: string[]): string[] {
  const found = new Set<string>();
  for (const raw of values) {
    for (const v of [raw, safeDecode(raw)]) {
      for (const [name, re] of PATTERNS) if (re.test(v)) found.add(name);
    }
  }
  return [...found].sort();
}

// --- Ruta sin valores -------------------------------------------------------------------------
// Ruta coincidente: se registra el PATRÓN (/api/cantones/:id/panorama), no el valor de :id.
// Ruta inexistente: se registra la ruta sin query, sustituyendo los segmentos con caracteres no
// alfanuméricos o con forma de dato (números, hex/uuid largos) por ':redacted'.
function safeRoute(req: Request): string {
  const pattern = (req.route as { path?: string } | undefined)?.path;
  if (typeof pattern === 'string') return `${req.baseUrl || ''}${pattern}`;
  const path = (req.originalUrl || req.url || '').split('?')[0];
  const segments = path.split('/').map((seg) => {
    if (seg === '') return seg;
    if (!/^[A-Za-z_-]{1,40}$/.test(seg)) return ':redacted';
    return seg;
  });
  return segments.join('/').slice(0, 200);
}

function eventType(status: number, method: string, suspicious: string[]): string {
  if (suspicious.length > 0) return 'abuse_suspected';
  if (status >= 500) return 'server_error';
  const isWrite = !['GET', 'HEAD', 'OPTIONS'].includes(method);
  // La API pública es de solo lectura (KB, matriz de acceso): un intento de escritura rechazado
  // (404/405) es un acceso denegado, igual que un 401/403.
  if (status === 401 || status === 403 || status === 405 || (isWrite && status === 404)) return 'access_denied';
  if (status === 404) return 'not_found';
  return 'validation_rejected';
}

export interface SecurityEvent {
  timestamp: string;
  level: 'warn' | 'error';
  log_type: 'security_event';
  event_type: string;
  correlation_id: string;
  method: string;
  route: string;
  status_code: number;
  param_names: string[];
  suspicious_patterns: string[];
  actor_id: string;
  actor_id_scope: string;
  // Solo en errores no controlados (5xx): nombre de la clase del error, sin mensaje ni stack.
  error_class?: string;
}

export function buildSecurityEvent(req: RequestWithCorrelation, status: number): SecurityEvent {
  const query = (req.query ?? {}) as Record<string, unknown>;
  const params = (req.params ?? {}) as Record<string, unknown>;
  const body = req.body && typeof req.body === 'object' ? (req.body as Record<string, unknown>) : {};

  const values: string[] = [];
  collectStrings(query, values);
  collectStrings(params, values);
  collectStrings(body, values);
  // En rutas inexistentes los datos pueden venir en el propio path.
  if (!req.route) values.push((req.originalUrl || req.url || '').split('?')[0]);

  const paramNames = [
    ...Object.keys(query).map((k) => `query.${k}`),
    ...Object.keys(params).map((k) => `path.${k}`),
    ...Object.keys(body).map((k) => `body.${k}`),
  ]
    .map((n) => n.replace(/[^\w.\-[\]]/g, '_').slice(0, 64))
    .slice(0, 30);

  const suspicious = detectPatterns(values);
  return {
    timestamp: new Date().toISOString(),
    level: status >= 500 ? 'error' : 'warn',
    log_type: 'security_event',
    event_type: eventType(status, req.method, suspicious),
    correlation_id: req.correlationId ?? resolveCorrelationId(undefined),
    method: req.method,
    route: safeRoute(req),
    status_code: status,
    param_names: paramNames,
    suspicious_patterns: suspicious,
    actor_id: actorId(clientIp(req)),
    actor_id_scope: ACTOR_SCOPE,
  };
}

// Errores de la librería "http-errors" (p. ej. body-parser): Nest los responde con su propio
// statusCode y message. Se conserva ese mismo comportamiento.
function httpErrorLike(e: unknown): { statusCode: number; message: string } | null {
  const o = e as { statusCode?: unknown; message?: unknown } | null;
  return o && typeof o.statusCode === 'number' && typeof o.message === 'string' && o.message
    ? { statusCode: o.statusCode, message: o.message }
    : null;
}

// Nombre de la clase del error (QueryFailedError, TypeError, ...): solo [A-Za-z0-9_], sin mensaje ni stack.
function errorClass(e: unknown): string {
  const name = (e as { constructor?: { name?: unknown } } | null)?.constructor?.name;
  return typeof name === 'string' && /^[A-Za-z0-9_]{1,64}$/.test(name) ? name : 'UnknownError';
}

@Catch()
export class SecurityEventFilter extends BaseExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    if (host.getType() !== 'http') {
      super.catch(exception, host);
      return;
    }
    const http = host.switchToHttp();
    const req = http.getRequest<RequestWithCorrelation>();
    const res = http.getResponse<Response>();
    const isHttp = exception instanceof HttpException;
    const httpErr = isHttp ? null : httpErrorLike(exception);
    const status = isHttp ? exception.getStatus() : (httpErr?.statusCode ?? HttpStatus.INTERNAL_SERVER_ERROR);

    try {
      if (!req.correlationId) req.correlationId = resolveCorrelationId(undefined);
      if (!res.headersSent) res.setHeader(CORRELATION_HEADER, req.correlationId);
      if (status >= 400) {
        const event: SecurityEvent & { error_class?: string } = buildSecurityEvent(req, status);
        if (!isHttp) event.error_class = errorClass(exception);
        process.stdout.write(`${JSON.stringify(event)}\n`);
      }
    } catch {
      // El registro nunca debe impedir la respuesta normal al cliente.
    }

    if (isHttp) {
      // HttpException: comportamiento normal de Nest (no registra nada en su logger).
      super.catch(exception, host);
      return;
    }

    // Error no controlado: se responde con EXACTAMENTE el mismo cuerpo que usaría Nest, pero sin
    // delegar en BaseExceptionFilter, cuyo logger imprimiría el mensaje y el stack (que en errores
    // de TypeORM incluye el SQL) en los logs del contenedor.
    const body = httpErr ?? { statusCode: HttpStatus.INTERNAL_SERVER_ERROR, message: 'Internal server error' };
    const adapter = this.httpAdapterHost?.httpAdapter;
    if (res.headersSent) {
      if (adapter) adapter.end(res);
      else res.end();
    } else if (adapter) {
      adapter.reply(res, body, body.statusCode);
    } else {
      res.status(body.statusCode).json(body);
    }
  }
}
