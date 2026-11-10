import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

export interface HealthStatus {
  status: 'ok' | 'error';
  timestamp: string;
  uptime_seconds: number;
  version: string;
  commit_sha: string;
  database: {
    status: 'up' | 'down';
    postgis_version?: string;
  };
  fuente: string;
  fecha_obtencion: string;
}

@Injectable()
export class HealthService {
  constructor(
    @InjectDataSource()
    private readonly dataSource: DataSource,
  ) {}

  async check(): Promise<HealthStatus> {
    const now = new Date().toISOString();
    try {
      const rows = await this.dataSource.query(
        'SELECT 1 AS ok, PostGIS_Version() AS postgis_version',
      );
      const postgisVersion = rows?.[0]?.postgis_version ?? 'unknown';

      return {
        status: 'ok',
        timestamp: now,
        uptime_seconds: Math.round(process.uptime()),
        version: process.env.APP_VERSION || '0.1.0',
        commit_sha: process.env.COMMIT_SHA || 'local',
        database: {
          status: 'up',
          postgis_version: postgisVersion,
        },
        fuente: 'INTERNAL/HEALTH',
        fecha_obtencion: now,
      };
    } catch {
      throw new ServiceUnavailableException({
        status: 'error',
        timestamp: now,
        uptime_seconds: Math.round(process.uptime()),
        version: process.env.APP_VERSION || '0.1.0',
        commit_sha: process.env.COMMIT_SHA || 'local',
        database: {
          status: 'down',
        },
        fuente: 'INTERNAL/HEALTH',
        fecha_obtencion: now,
      });
    }
  }
}
