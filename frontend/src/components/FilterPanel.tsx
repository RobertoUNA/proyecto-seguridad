import type { FiltrosMapa, FuenteActiva } from '../types'

interface Props {
  cantones: { codigo: string; nombre: string }[]
  tipos: string[]
  clases: string[]
  fuente: FuenteActiva
  filtros: FiltrosMapa
  cargando: boolean
  onFuenteChange: (fuente: FuenteActiva) => void
  onChange: (filtros: FiltrosMapa) => void
  onAplicar: () => void
  onLimpiar: () => void
  mostrarInfraestructura: boolean
  cargandoInfraestructura: boolean
  onToggleInfraestructura: () => void
}

export default function FilterPanel({
  cantones,
  tipos,
  clases,
  fuente,
  filtros,
  cargando,
  onFuenteChange,
  onChange,
  onAplicar,
  onLimpiar,
  mostrarInfraestructura,
  cargandoInfraestructura,
  onToggleInfraestructura,
}: Props) {
  const set = (campo: keyof FiltrosMapa, valor: string) =>
    onChange({ ...filtros, [campo]: valor || undefined })

  return (
    <aside className="panel filtros">
      <h2>Filtros</h2>

      <label className="campo">
        <span>Fuente de datos</span>
        <select value={fuente} onChange={(e) => onFuenteChange(e.target.value as FuenteActiva)}>
          <option value="delitos">Delitos (OIJ)</option>
          <option value="accidentes">Accidentes (COSEVI)</option>
        </select>
      </label>

      <label className="campo">
        <span>{fuente === 'delitos' ? 'Tipo de delito' : 'Tipo de accidente'}</span>
        <select
          value={filtros.tipo ?? ''}
          onChange={(e) => set('tipo', e.target.value)}
        >
          <option value="">Todos</option>
          {tipos.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </label>

      {fuente === 'delitos' ? (
        <>
          <label className="campo">
            <span>Desde</span>
            <input type="date" value={filtros.desde ?? ''} onChange={(e) => set('desde', e.target.value)} />
          </label>
          <label className="campo">
            <span>Hasta</span>
            <input type="date" value={filtros.hasta ?? ''} onChange={(e) => set('hasta', e.target.value)} />
          </label>
        </>
      ) : (
        <>
          <label className="campo">
            <span>Año</span>
            <input type="number" min="2018" max="2100" placeholder="Ej. 2024" value={filtros.anio ?? ''} onChange={(e) => set('anio', e.target.value)} />
          </label>
          <label className="campo">
            <span>Clase de accidente</span>
            <select value={filtros.clase ?? ''} onChange={(e) => set('clase', e.target.value)}>
              <option value="">Todas</option>
              {clases.map((clase) => <option key={clase} value={clase}>{clase}</option>)}
            </select>
          </label>
        </>
      )}

      <label className="campo">
        <span>Cantón</span>
        <select
          value={filtros.canton ?? ''}
          onChange={(e) => set('canton', e.target.value)}
        >
          <option value="">Todos los cantones</option>
          {cantones.map((c) => (
            <option key={c.codigo} value={c.codigo}>
              {c.nombre}
            </option>
          ))}
        </select>
      </label>

      <div className="botones">
        <button className="btn primario" onClick={onAplicar} disabled={cargando}>
          {cargando ? 'Cargando…' : 'Aplicar'}
        </button>
        <button className="btn" onClick={onLimpiar} disabled={cargando}>
          Limpiar
        </button>
      </div>

      <p className="nota">
        Los datos se agregan por cantón. Un valor alto no implica causalidad con
        la infraestructura cercana.
      </p>

      <h2>Capas adicionales</h2>
      <label className="campo campo-check">
        <input
          type="checkbox"
          checked={mostrarInfraestructura}
          onChange={onToggleInfraestructura}
        />
        <span>
          Infraestructura de atención (OSM){cargandoInfraestructura ? ' — cargando…' : ''}
        </span>
      </label>
      <p className="nota">
        Hospitales, clínicas y comisarías. Se superpone a la fuente activa, no
        la reemplaza.
      </p>
    </aside>
  )
}
