// Pruebas de integracion API + base de datos de pruebas (Items 4.3 y 4.1).
// Requieren Postgres/PostGIS con migraciones y backend/database/seed_test.sql
// cargados, y las variables DB_HOST, DB_PORT, DB_USER, DB_PASSWORD y DB_NAME.
// Si la base no esta disponible la suite FALLA (no se omite): un analisis que
// no se pudo ejecutar es incompleto, no aprobado.
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { DataSource } from 'typeorm';
import { AppModule } from '../src/app.module';

const MARCA = 'ZZ_TEST_INTEGRACION';

describe('API + BD de pruebas (integracion)', () => {
  let app: INestApplication;
  let db: DataSource;
  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(new ValidationPipe({ transform: true }));
    await app.init();
    db = app.get(DataSource);
  });

  afterAll(async () => {
    if (db) await db.query('DELETE FROM delito WHERE tipo = $1', [MARCA]);
    if (app) await app.close();
  });

  describe('GET /api/cantones', () => {
    it('devuelve FeatureCollection con los cantones de la semilla y cabeceras de fuente', async () => {
      const res = await http().get('/api/cantones').expect(200);
      expect(res.headers['x-data-source']).toBe('SNIT/ArcGIS');
      expect(res.headers['x-fetch-date']).toBeDefined();
      expect(res.body.type).toBe('FeatureCollection');
      const codigos = res.body.features.map((f: { properties: { codigo: string } }) => f.properties.codigo);
      expect(codigos).toEqual(expect.arrayContaining(['1001', '2001', '3001']));
    });

    it('GET /api/cantones/1001 devuelve el canton con geometria', async () => {
      const res = await http().get('/api/cantones/1001').expect(200);
      expect(res.body.properties.nombre).toBe('SAN JOSÉ');
      expect(res.body.geometry).not.toBeNull();
    });

    it('404 cuando el canton no existe', async () => {
      await http().get('/api/cantones/9999').expect(404);
    });
  });

  describe('GET /api/cantones/:id/panorama', () => {
    it('calcula el indice sobre los datos de la semilla', async () => {
      // scores semilla: SJ (25+18)/(1+1)=21.5 ; Alajuela 12/(1+0)=12 ; Cartago 5/(1+1)=2.5
      const res = await http().get('/api/cantones/1001/panorama').expect(200);
      expect(res.headers['x-data-source']).toContain('OSM/Overpass');
      expect(res.headers['x-fetch-date']).toBeDefined();
      const p = res.body.properties;
      expect(p.delitos.total).toBe(25);
      expect(p.accidentes.total).toBe(18);
      expect(p.infraestructura.total).toBe(1);
      expect(p.indice_cobertura_ratio).toBe(21.5);
      expect(p.indice_cobertura).toBe(100);
    });

    it('canton sin infraestructura (Alajuela) no divide entre cero', async () => {
      const res = await http().get('/api/cantones/2001/panorama').expect(200);
      expect(res.body.properties.indice_cobertura_ratio).toBe(12);
      expect(res.body.properties.indice_cobertura).toBe(67);
    });

    it('404 cuando el canton no existe', async () => {
      await http().get('/api/cantones/9999/panorama').expect(404);
    });
  });

  describe('GET /api/delitos', () => {
    it('filtro valido por canton devuelve solo sus delitos', async () => {
      const res = await http().get('/api/delitos?canton=1001').expect(200);
      expect(res.headers['x-data-source']).toBe('OIJ/CKAN');
      expect(res.body.delitos).toHaveLength(1);
      expect(res.body.delitos[0].tipo).toBe('ASALTO');
    });

    it('400 con canton inexistente', async () => {
      await http().get('/api/delitos?canton=NOEXISTE').expect(400);
    });

    it('400 con fecha invalida', async () => {
      await http().get('/api/delitos?desde=no-es-fecha').expect(400);
    });

    it("400 cuando 'desde' es mayor que 'hasta'", async () => {
      await http().get('/api/delitos?desde=2024-12-31&hasta=2024-01-01').expect(400);
    });

    it('un payload SQL en el filtro no rompe la consulta ni devuelve datos', async () => {
      const res = await http().get("/api/delitos?tipo=x'; DROP TABLE delito;--").expect(200);
      expect(res.body.delitos).toHaveLength(0);
      const filas = await db.query('SELECT COUNT(*)::int AS n FROM delito');
      expect(filas[0].n).toBeGreaterThan(0);
    });

    it('persistencia y limpieza: un registro insertado se consulta y desaparece al borrarlo', async () => {
      await db.query(
        `INSERT INTO delito (canton_id, provincia, distrito, tipo, modalidad, fecha, cantidad, fuente, fecha_obtencion)
         SELECT c.id, 'ALAJUELA', 'CENTRAL', $1, 'PRUEBA', DATE '2024-07-01', 3, 'TEST', NOW()
         FROM canton c WHERE c.codigo = '2001'`,
        [MARCA],
      );
      const con = await http().get(`/api/delitos?tipo=${MARCA}`).expect(200);
      expect(con.body.delitos).toHaveLength(1);
      expect(con.body.delitos[0].cantidad).toBe(3);

      await db.query('DELETE FROM delito WHERE tipo = $1', [MARCA]);
      const sin = await http().get(`/api/delitos?tipo=${MARCA}`).expect(200);
      expect(sin.body.delitos).toHaveLength(0);
    });
  });

  describe('GET /api/accidentes', () => {
    it('filtro valido por anio devuelve registros de la semilla', async () => {
      const res = await http().get('/api/accidentes?anio=2024').expect(200);
      expect(res.headers['x-data-source']).toBe('COSEVI');
      expect(res.body.accidentes.length).toBeGreaterThanOrEqual(2);
    });

    it('400 con anio no numerico', async () => {
      await http().get('/api/accidentes?anio=abc').expect(400);
    });

    it('400 con anio fuera de rango', async () => {
      await http().get('/api/accidentes?anio=1800').expect(400);
    });

    it('400 con canton inexistente', async () => {
      await http().get('/api/accidentes?canton=NOEXISTE').expect(400);
    });
  });
});
