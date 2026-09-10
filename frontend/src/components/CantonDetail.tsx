import type { DetalleFuente, FuenteInfo } from '../types'

interface Props {
  seleccion: { codigo: string; nombre: string }
  datos: DetalleFuente | null
  fuenteMapa: FuenteInfo
  etiquetaMetrica: string
  cargando: boolean
  error: string | null
  onCerrar: () => void
}

function agruparPorTipo(datos: DetalleFuente) {
  const mapa = new Map<string, number>()
  for (const d of datos.registros) {
    mapa.set(d.tipo, (mapa.get(d.tipo) ?? 0) + d.cantidad)
  }
  return [...mapa.entries()].sort((a, b) => b[1] - a[1])
}

export default function CantonDetail({
  seleccion,
  datos,
  fuenteMapa,
  etiquetaMetrica,
  cargando,
  error,
  onCerrar,
}: Props) {
  const tipos = datos ? agruparPorTipo(datos) : []
  const max = tipos.length ? tipos[0][1] : 1

  return (
    <aside className="panel detalle">
      <div className="detalle-cabecera">
        <h2>{seleccion.nombre}</h2>
        <button className="btn" onClick={onCerrar} aria-label="Cerrar">
          ✕
        </button>
      </div>

      {error && <p className="error">{error}</p>}
      {cargando && <p className="nota">Cargando detalle…</p>}

      {!cargando && !error && datos && (
        <>
          <p className="resumen">
            <strong>{datos.resumen.registro_cantidad.toLocaleString('es-CR')}</strong>{' '}
            {etiquetaMetrica} en el periodo seleccionado
          </p>

          <h3>Distribución por tipo</h3>
          <ul className="barras">
            {tipos.map(([tipo, cantidad]) => (
              <li key={tipo}>
                <div className="barra-fila">
                  <span className="barra-etiqueta">{tipo}</span>
                  <span className="barra-valor">
                    {cantidad.toLocaleString('es-CR')}
                  </span>
                </div>
                <div className="barra-trazado">
                  <div
                    className="barra-llenado"
                    style={{ width: `${(cantidad / max) * 100}%` }}
                  />
                </div>
              </li>
            ))}
          </ul>

          <p className="procedencia">
            Fuente: <strong>{datos.fuente}</strong>
            <br />
            {datos.fecha_obtencion &&
              `Datos obtenidos el ${new Date(datos.fecha_obtencion).toLocaleString('es-CR')}`}
          </p>
        </>
      )}

      <p className="procedencia">
        Geometría de cantones: <strong>{fuenteMapa.fuente}</strong>
      </p>
      <p className="nota">
        Los valores son correlaciones agregadas por cantón, no causalidad.
      </p>
    </aside>
  )
}
