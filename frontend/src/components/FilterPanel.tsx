import type { DelitoFiltros } from '../types'

interface Props {
  cantones: { codigo: string; nombre: string }[]
  tipos: string[]
  filtros: DelitoFiltros
  cargando: boolean
  onChange: (filtros: DelitoFiltros) => void
  onAplicar: () => void
  onLimpiar: () => void
}

export default function FilterPanel({
  cantones,
  tipos,
  filtros,
  cargando,
  onChange,
  onAplicar,
  onLimpiar,
}: Props) {
  const set = (campo: keyof DelitoFiltros, valor: string) =>
    onChange({ ...filtros, [campo]: valor || undefined })

  return (
    <aside className="panel filtros">
      <h2>Filtros</h2>

      <label className="campo">
        <span>Tipo de delito</span>
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

      <label className="campo">
        <span>Desde</span>
        <input
          type="date"
          value={filtros.desde ?? ''}
          onChange={(e) => set('desde', e.target.value)}
        />
      </label>

      <label className="campo">
        <span>Hasta</span>
        <input
          type="date"
          value={filtros.hasta ?? ''}
          onChange={(e) => set('hasta', e.target.value)}
        />
      </label>

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
    </aside>
  )
}