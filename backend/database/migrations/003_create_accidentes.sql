CREATE TABLE IF NOT EXISTS accidente (
    id SERIAL PRIMARY KEY,
    canton_id INTEGER REFERENCES canton(id) ON DELETE SET NULL,
    canton_nombre VARCHAR(100),
    provincia VARCHAR(50),
    distrito VARCHAR(100),
    anio SMALLINT NOT NULL CHECK (anio BETWEEN 1900 AND 2100),
    clase VARCHAR(100) NOT NULL,
    tipo VARCHAR(150) NOT NULL,
    cantidad INTEGER NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    fuente VARCHAR(50) NOT NULL DEFAULT 'COSEVI',
    fecha_obtencion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_accidente_agregado
    ON accidente (
        COALESCE(canton_id, 0),
        COALESCE(canton_nombre, ''),
        anio,
        clase,
        tipo,
        COALESCE(provincia, ''),
        COALESCE(distrito, '')
    );

CREATE INDEX IF NOT EXISTS idx_accidente_canton_anio ON accidente (canton_id, anio);
CREATE INDEX IF NOT EXISTS idx_accidente_anio ON accidente (anio);
CREATE INDEX IF NOT EXISTS idx_accidente_tipo ON accidente (tipo);
