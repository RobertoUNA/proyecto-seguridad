CREATE TABLE IF NOT EXISTS infraestructura (
    id SERIAL PRIMARY KEY,
    osm_type VARCHAR(10) NOT NULL CHECK (osm_type IN ('node', 'way', 'relation')),
    osm_id BIGINT NOT NULL,
    canton_id INTEGER REFERENCES canton(id) ON DELETE SET NULL,
    provincia VARCHAR(50),
    distrito VARCHAR(100),
    nombre VARCHAR(200),
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('hospital', 'clinica', 'comisaria')),
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    fuente VARCHAR(50) NOT NULL DEFAULT 'OSM/Overpass',
    fecha_obtencion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_infraestructura_osm
    ON infraestructura (osm_type, osm_id);

CREATE INDEX IF NOT EXISTS idx_infraestructura_canton ON infraestructura (canton_id);
CREATE INDEX IF NOT EXISTS idx_infraestructura_tipo ON infraestructura (tipo);
