// Ítem 7.2 (THR-06 / CTL-06) — Empaqueta el registro de eventos de seguridad sin modificar main.ts:
//  · SecurityEventFilter como filtro global (APP_FILTER).
//  · CorrelationIdMiddleware en todas las rutas (NestModule.configure).
import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { CorrelationIdMiddleware } from './correlation-id.middleware';
import { SecurityEventFilter } from './security-event.filter';

@Module({
  providers: [{ provide: APP_FILTER, useClass: SecurityEventFilter }],
})
export class SecurityLoggingModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(CorrelationIdMiddleware).forRoutes('*');
  }
}
