// Ítem 7.2 (THR-06 / CTL-06) — Identificador de correlación por petición.
// Acepta X-Correlation-Id solo si es un UUID válido; si falta o es inválido, genera uno nuevo.
// Nunca se reutiliza un valor arbitrario del cliente: evita inyectar texto en los logs.
import { Injectable, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { NextFunction, Request, Response } from 'express';

export const CORRELATION_HEADER = 'X-Correlation-Id';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type RequestWithCorrelation = Request & { correlationId?: string };

export function resolveCorrelationId(value: unknown): string {
  return typeof value === 'string' && UUID_RE.test(value) ? value.toLowerCase() : randomUUID();
}

@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  use(req: RequestWithCorrelation, res: Response, next: NextFunction): void {
    const id = resolveCorrelationId(req.headers[CORRELATION_HEADER.toLowerCase()]);
    req.correlationId = id;
    res.setHeader(CORRELATION_HEADER, id);
    next();
  }
}
