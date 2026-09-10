import { useCallback, useEffect, useMemo, useState } from 'react'
import 'leaflet/dist/leaflet.css'
import './App.css'
import { fetchCantones, fetchDelitos, fetchDelitosPorCanton, fetchTipos } from './api'
import type {
  CantonCollection,
  DelitoFiltros,
  DelitoTotalesCollection,
  DelitosResponse,
  FuenteInfo,
} from './types'
import MapView from './components/MapView'
import FilterPanel from './components/FilterPanel'
import CantonDetail from './components/CantonDetail'

export default function App() {
  const [cantones, setCantones] = useState<CantonCollection | null>(null)
  const [tipos, setTipos] = useState<string[]>([])
  const [filtros, setFiltros] = useState<DelitoFiltros>({})
  const [delitosPorCanton, setDelitosPorCanton] =
    useState<DelitoTotalesCollection>({ type: 'FeatureCollection', features: [] })
  const [seleccion, setSeleccion] = useState<{
    codigo: string
    nombre: string
  } | null>(null)
  const [detalle, setDetalle] = useState<DelitosResponse | null>(null)
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [fuenteMapa, setFuenteMapa] = useState<FuenteInfo>({
    fuente: 'SNIT/ArcGIS',
    fecha_obtencion: null,
    descripcion: 'Límites cantonales publicados por SNIT/ArcGIS',
  })

  useEffect(() => {
    let activo = true
    ;(async () => {
      try {
        const [cs, ts, pc] = await Promise.all([
          fetchCantones(),
          fetchTipos(),
          fetchDelitosPorCanton({}),
        ])
        if (!activo) return
        setCantones(cs)
        setTipos(ts.tipos)
        setDelitosPorCanton(pc)
        setFuenteMapa({
          fuente: 'OIJ/CKAN + SNIT/ArcGIS',
          fecha_obtencion: null,
          descripcion: 'Delitos agregados por cantón (Poder Judicial)',
        })
      } catch (e) {
        if (activo)
          setError(
            e instanceof Error ? e.message : 'No se pudieron cargar los cantones',
          )
      }
    })()
    return () => {
      activo = false
    }
  }, [])

  const listaCantones = useMemo(
    () =>
      (cantones?.features ?? [])
        .map((f) => ({ codigo: f.properties.codigo, nombre: f.properties.nombre }))
        .sort((a, b) => a.nombre.localeCompare(b.nombre)),
    [cantones],
  )

  const actualizarCoropleta = useCallback(
    async (f: DelitoFiltros) => {
      const porCanton = await fetchDelitosPorCanton(f)
      setDelitosPorCanton(porCanton)
      setFuenteMapa((prev) => ({
        ...prev,
        fuente: 'OIJ/CKAN + SNIT/ArcGIS',
        descripcion: 'Delitos agregados por cantón (Poder Judicial)',
      }))
    },
    [],
  )

  const aplicarFiltros = useCallback(async () => {
    setCargando(true)
    setError(null)
    try {
      await actualizarCoropleta(filtros)
      if (filtros.canton) {
        const canton = (cantones?.features ?? []).find(
          (f) => f.properties.codigo === filtros.canton,
        )
        if (canton)
          setSeleccion({
            codigo: canton.properties.codigo,
            nombre: canton.properties.nombre,
          })
      } else {
        setSeleccion(null)
        setDetalle(null)
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al consultar delitos')
    } finally {
      setCargando(false)
    }
  }, [filtros, cantones, actualizarCoropleta])

  const seleccionarCanton = useCallback(
    async (codigo: string, nombre: string) => {
      setSeleccion({ codigo, nombre })
      setCargando(true)
      setError(null)
      setDetalle(null)
      try {
        const d = await fetchDelitos({ ...filtros, canton: codigo })
        setDetalle(d)
        setFuenteMapa({
          fuente: d.fuente,
          fecha_obtencion: d.fecha_obtencion,
          descripcion: d.descripcion_fuente,
        })
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Error al cargar el detalle')
      } finally {
        setCargando(false)
      }
    },
    [filtros],
  )

  const limpiarFiltros = useCallback(() => {
    setFiltros({})
    setSeleccion(null)
    setDetalle(null)
    void actualizarCoropleta({})
  }, [actualizarCoropleta])

  return (
    <div className="app">
      <header className="cabecera">
        <div>
          <h1>Observatorio de Seguridad Vial y Urbana</h1>
          <p className="sub">
            Costa Rica — delitos, accidentes e infraestructura de atención
          </p>
        </div>
        <div className="estado-fuente" title={fuenteMapa.descripcion}>
          <span className="punto" />
          Fuente activa: {fuenteMapa.fuente}
        </div>
      </header>

      <main className="contenido">
        <FilterPanel
          cantones={listaCantones}
          tipos={tipos}
          filtros={filtros}
          cargando={cargando}
          onChange={setFiltros}
          onAplicar={() => void aplicarFiltros()}
          onLimpiar={limpiarFiltros}
        />

        <div className="mapa-wrapper">
          {cantones ? (
            <MapView
              cantones={cantones}
              delitosPorCanton={delitosPorCanton}
              cantonSeleccionado={seleccion}
              onSeleccionar={(c, n) => void seleccionarCanton(c, n)}
            />
          ) : (
            <p className="nota">Cargando cantones…</p>
          )}
          <div className="leyenda">
            <span className="swatch" style={{ background: 'rgb(153,102,255)' }} />
            bajo
            <span className="swatch" style={{ background: 'rgb(184,86,163)' }} />
            medio
            <span className="swatch" style={{ background: 'rgb(178,24,21)' }} />
            alto
            <span className="leyenda-nota">
              (intensidad relativa: {delitosPorCanton.features.length} cantones con datos)
            </span>
          </div>
        </div>

        {seleccion && (
          <CantonDetail
            seleccion={seleccion}
            datos={detalle}
            fuenteMapa={fuenteMapa}
            cargando={cargando}
            error={error}
            onCerrar={() => {
              setSeleccion(null)
              setDetalle(null)
            }}
          />
        )}
      </main>

      <footer className="pie">
        <span>
          Fuentes: OIJ / Poder Judicial · COSEVI · SNIT · OpenStreetMap (Overpass)
        </span>
        <span>
          Datos agregados por cantón, sin perfiles individuales. Módulo activo:
          delitos (OIJ/CKAN).
        </span>
      </footer>
    </div>
  )
}