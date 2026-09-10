CREATE TABLE IF NOT EXISTS delito (
    id SERIAL PRIMARY KEY,
    canton_id INTEGER REFERENCES canton(id) ON DELETE CASCADE,
    provincia VARCHAR(50),
    distrito VARCHAR(100),
    tipo VARCHAR(100) NOT NULL,
    modalidad VARCHAR(150),
    fecha DATE NOT NULL,
    cantidad INTEGER NOT NULL DEFAULT 1,
    fuente VARCHAR(50) DEFAULT 'OIJ/CKAN',
    fecha_obtencion TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_delito_canton_tipo_fecha
    ON delito (COALESCE(canton_id, 0), tipo, COALESCE(modalidad, ''), fecha);

CREATE INDEX IF NOT EXISTS idx_delito_canton ON delito (canton_id);
CREATE INDEX IF NOT EXISTS idx_delito_fecha ON delito (fecha);
CREATE INDEX IF NOT EXISTS idx_delito_tipo ON delito (tipo);
CREATE INDEX IF NOT EXISTS idx_delito_canton_fecha ON delito (canton_id, fecha);