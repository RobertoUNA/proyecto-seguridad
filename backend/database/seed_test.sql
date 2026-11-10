-- Semilla de datos ficticios y controlados para el ambiente aislado de CI y pruebas (Ítems 3.1 y 4.1)
-- No contiene datos personales ni depende de conexiones a fuentes OSINT externas.

INSERT INTO canton (codigo, nombre, poblacion, geom, fuente, fecha_obtencion)
VALUES
  (
    '1001',
    'SAN JOSÉ',
    352381,
    ST_GeomFromText('MULTIPOLYGON(((-84.12 9.91, -84.04 9.91, -84.04 9.96, -84.12 9.96, -84.12 9.91)))', 4326),
    'SNIT/ArcGIS',
    NOW()
  ),
  (
    '2001',
    'ALAJUELA',
    322143,
    ST_GeomFromText('MULTIPOLYGON(((-84.28 9.98, -84.18 9.98, -84.18 10.06, -84.28 10.06, -84.28 9.98)))', 4326),
    'SNIT/ArcGIS',
    NOW()
  ),
  (
    '3001',
    'CARTAGO',
    166204,
    ST_GeomFromText('MULTIPOLYGON(((-83.96 9.83, -83.88 9.83, -83.88 9.89, -83.96 9.89, -83.96 9.83)))', 4326),
    'SNIT/ArcGIS',
    NOW()
  )
ON CONFLICT (codigo) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  poblacion = EXCLUDED.poblacion,
  geom = EXCLUDED.geom;

INSERT INTO delito (canton_id, provincia, distrito, tipo, modalidad, fecha, cantidad, fuente, fecha_obtencion)
SELECT c.id, 'SAN JOSÉ', 'CARMEN', 'ASALTO', 'ARMA DE FUEGO', DATE '2024-05-15', 25, 'OIJ/CKAN', NOW()
FROM canton c WHERE c.codigo = '1001'
ON CONFLICT DO NOTHING;

INSERT INTO delito (canton_id, provincia, distrito, tipo, modalidad, fecha, cantidad, fuente, fecha_obtencion)
SELECT c.id, 'ALAJUELA', 'CENTRAL', 'HURTO', 'DESCUIDO', DATE '2024-06-10', 12, 'OIJ/CKAN', NOW()
FROM canton c WHERE c.codigo = '2001'
ON CONFLICT DO NOTHING;

INSERT INTO accidente (canton_id, canton_nombre, provincia, distrito, anio, clase, tipo, cantidad, fuente, fecha_obtencion)
SELECT c.id, 'SAN JOSÉ', 'SAN JOSÉ', 'CARMEN', 2024, 'Con heridos graves', 'Colisión con motocicleta', 18, 'COSEVI', NOW()
FROM canton c WHERE c.codigo = '1001'
ON CONFLICT DO NOTHING;

INSERT INTO accidente (canton_id, canton_nombre, provincia, distrito, anio, clase, tipo, cantidad, fuente, fecha_obtencion)
SELECT c.id, 'CARTAGO', 'CARTAGO', 'ORIENTAL', 2024, 'Solo heridos leves', 'Atropello a persona', 5, 'COSEVI', NOW()
FROM canton c WHERE c.codigo = '3001'
ON CONFLICT DO NOTHING;

INSERT INTO infraestructura (osm_type, osm_id, canton_id, provincia, distrito, nombre, tipo, lat, lon, fuente, fecha_obtencion)
SELECT 'node', 900001, c.id, 'SAN JOSÉ', 'HOSPITAL', 'Hospital San Juan de Dios (Test)', 'hospital', 9.9325, -84.0841, 'OSM/Overpass', NOW()
FROM canton c WHERE c.codigo = '1001'
ON CONFLICT (osm_type, osm_id) DO NOTHING;

INSERT INTO infraestructura (osm_type, osm_id, canton_id, provincia, distrito, nombre, tipo, lat, lon, fuente, fecha_obtencion)
SELECT 'node', 900002, c.id, 'CARTAGO', 'ORIENTAL', 'Hospital Max Peralta (Test)', 'hospital', 9.8601, -83.9188, 'OSM/Overpass', NOW()
FROM canton c WHERE c.codigo = '3001'
ON CONFLICT (osm_type, osm_id) DO NOTHING;
