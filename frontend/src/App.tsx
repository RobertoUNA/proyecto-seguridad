import { useCallback, useEffect, useMemo, useState } from 'react'
import 'leaflet/dist/leaflet.css'
import './App.css'
import {
  fetchAccidenteClases,
  fetchAccidenteTipos,
  fetchAccidentes,
  fetchAccidentesPorCanton,
  fetchCantones,
  fetchDelitos,
  fetchDelitosPorCanton,
  fetchInfraestructura,
  fetchPanorama,
  fetchTipos,
} from './api'
import type {
  AccidenteTotalesCollection,
  CapaMapaCollection,
  CantonCollection,
  DelitoTotalesCollection,
  DetalleFuente,
  FiltrosMapa,
  FuenteActiva,
  FuenteInfo,
  InfraestructuraRow,
  PanoramaResponse,
} from './types'
import MapView from './components/MapView'
import FilterPanel from './components/FilterPanel'
import CantonDetail from './components/CantonDetail'

function capaDesdeDelitos(datos: DelitoTotalesCollection): CapaMapaCollection {
  return {
    type: 'FeatureCollection',
    features: datos.features.map((feature) => ({
      ...feature,
      properties: {
        codigo: feature.properties.codigo,
        nombre: feature.properties.nombre,
        total: feature.properties.total_delitos,
      },
    })),
  }
}

function capaDesdeAccidentes(datos: AccidenteTotalesCollection): CapaMapaCollection {
  return {
    type: 'FeatureCollection',
    features: datos.features.map((feature) => ({
      ...feature,
      properties: {
        codigo: feature.properties.codigo,
        nombre: feature.properties.nombre,
        total: feature.properties.total_accidentes,
      },
    })),
  }
}

export default function App() {
  const [cantones, setCantones] = useState<CantonCollection | null>(null)
  const [fuente, setFuente] = useState<FuenteActiva>('delitos')
  const [tipos, setTipos] = useState<string[]>([])
  const [clases, setClases] = useState<string[]>([])
  const [filtros, setFiltros] = useState<FiltrosMapa>({})
  const [totalesPorCanton, setTotalesPorCanton] = useState<CapaMapaCollection>({
    type: 'FeatureCollection',
    features: [],
  })
  const [seleccion, setSeleccion] = useState<{ codigo: string; nombre: string } | null>(null)
  const [detalle, setDetalle] = useState<DetalleFuente | null>(null)
  const [panorama, setPanorama] = useState<PanoramaResponse | null>(null)
  const [cargandoPanorama, setCargandoPanorama] = useState(false)
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [mostrarInfraestructura, setMostrarInfraestructura] = useState(false)
  const [infraestructura, setInfraestructura] = useState<InfraestructuraRow[]>([])
  const [cargandoInfraestructura, setCargandoInfraestructura] = useState(false)
  const [fuenteMapa, setFuenteMapa] = useState<FuenteInfo>({
    fuente: 'OIJ/CKAN + SNIT/ArcGIS',
    fecha_obtencion: null,
    descripcion: 'Delitos agregados por cantón (Poder Judicial)',
  })

  const actualizarCoropleta = useCallback(
    async (fuenteActiva: FuenteActiva, filtrosActivos: FiltrosMapa) => {
      if (fuenteActiva === 'accidentes') {
        const datos = await fetchAccidentesPorCanton(filtrosActivos)
        setTotalesPorCanton(capaDesdeAccidentes(datos))
        setFuenteMapa({
          fuente: 'COSEVI + SNIT/ArcGIS',
          fecha_obtencion: null,
          descripcion: 'Accidentes de tránsito con víctimas agregados por cantón (COSEVI)',
        })
        return
      }

      const datos = await fetchDelitosPorCanton(filtrosActivos)
      setTotalesPorCanton(capaDesdeDelitos(datos))
      setFuenteMapa({
        fuente: 'OIJ/CKAN + SNIT/ArcGIS',
        fecha_obtencion: null,
        descripcion: 'Delitos agregados por cantón (Poder Judicial)',
      })
    },
    [],
  )

  useEffect(() => {
    let activo = true
    ;(async () => {
      try {
        const [cantonesData, tiposData, totalesData] = await Promise.all([
          fetchCantones(),
          fetchTipos(),
          fetchDelitosPorCanton({}),
        ])
        if (!activo) return
        setCantones(cantonesData)
        setTipos(tiposData.tipos)
        setTotalesPorCanton(capaDesdeDelitos(totalesData))
      } catch (causa) {
        if (activo) setError(causa instanceof Error ? causa.message : 'No se pudieron cargar los datos')
      }
    })()
    return () => {
      activo = false
    }
  }, [])

  const listaCantones = useMemo(
    () =>
      (cantones?.features ?? [])
        .map((feature) => ({ codigo: feature.properties.codigo, nombre: feature.properties.nombre }))
        .sort((a, b) => a.nombre.localeCompare(b.nombre)),
    [cantones],
  )

  const cambiarFuente = useCallback(
    async (nuevaFuente: FuenteActiva) => {
      setFuente(nuevaFuente)
      setFiltros({})
      setSeleccion(null)
      setDetalle(null)
      setPanorama(null)
      setError(null)
      setCargando(true)
      try {
        if (nuevaFuente === 'accidentes') {
          const [tiposData, clasesData] = await Promise.all([fetchAccidenteTipos(), fetchAccidenteClases()])
          setTipos(tiposData.tipos)
          setClases(clasesData.clases)
        } else {
          const tiposData = await fetchTipos()
          setTipos(tiposData.tipos)
          setClases([])
        }
        await actualizarCoropleta(nuevaFuente, {})
      } catch (causa) {
        setError(causa instanceof Error ? causa.message : 'No se pudo cambiar la fuente')
      } finally {
        setCargando(false)
      }
    },
    [actualizarCoropleta],
  )

  const aplicarFiltros = useCallback(async () => {
    setCargando(true)
    setError(null)
    try {
      await actualizarCoropleta(fuente, filtros)
      if (filtros.canton) {
        const canton = (cantones?.features ?? []).find((feature) => feature.properties.codigo === filtros.canton)
        if (canton) setSeleccion({ codigo: canton.properties.codigo, nombre: canton.properties.nombre })
      } else {
        setSeleccion(null)
        setDetalle(null)
        setPanorama(null)
      }
    } catch (causa) {
      setError(causa instanceof Error ? causa.message : 'Error al aplicar filtros')
    } finally {
      setCargando(false)
    }
  }, [actualizarCoropleta, cantones, filtros, fuente])

  const seleccionarCanton = useCallback(
    async (codigo: string, nombre: string) => {
      setSeleccion({ codigo, nombre })
      setCargando(true)
      setError(null)
      setDetalle(null)
      setPanorama(null)
      setCargandoPanorama(true)
      const panoramaPromise = fetchPanorama(codigo)
        .catch((causa) => {
          console.error('No se pudo cargar el panorama del cantón', causa)
          return null
        })
        .finally(() => setCargandoPanorama(false))
      try {
        if (fuente === 'accidentes') {
          const datos = await fetchAccidentes({ ...filtros, canton: codigo })
          setDetalle({
            registros: datos.accidentes,
            resumen: datos.resumen,
            fuente: datos.fuente,
            descripcion_fuente: datos.descripcion_fuente,
            fecha_obtencion: datos.fecha_obtencion,
          })
        } else {
          const datos = await fetchDelitos({ ...filtros, canton: codigo })
          setDetalle({
            registros: datos.delitos,
            resumen: datos.resumen,
            fuente: datos.fuente,
            descripcion_fuente: datos.descripcion_fuente,
            fecha_obtencion: datos.fecha_obtencion,
          })
        }
      } catch (causa) {
        setError(causa instanceof Error ? causa.message : 'Error al cargar el detalle')
      } finally {
        setCargando(false)
      }
      setPanorama(await panoramaPromise)
    },
    [filtros, fuente],
  )

  const alternarInfraestructura = useCallback(async () => {
    const activar = !mostrarInfraestructura
    setMostrarInfraestructura(activar)
    if (!activar || infraestructura.length > 0) return

    setCargandoInfraestructura(true)
    try {
      const datos = await fetchInfraestructura({})
      setInfraestructura(datos.infraestructura)
    } catch (causa) {
      setError(causa instanceof Error ? causa.message : 'No se pudo cargar infraestructura')
    } finally {
      setCargandoInfraestructura(false)
    }
  }, [mostrarInfraestructura, infraestructura.length])

  const limpiarFiltros = useCallback(() => {
    setFiltros({})
    setSeleccion(null)
    setDetalle(null)
    setPanorama(null)
    void actualizarCoropleta(fuente, {})
  }, [actualizarCoropleta, fuente])

  const etiquetaMetrica = fuente === 'accidentes' ? 'accidentes' : 'delitos'

  return (
    <div className="app">
      <header className="cabecera">
        <div>
          <h1>Observatorio de Seguridad Vial y Urbana</h1>
          <p className="sub">Costa Rica — delitos, accidentes e infraestructura de atención</p>
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
          clases={clases}
          fuente={fuente}
          filtros={filtros}
          cargando={cargando}
          onFuenteChange={(nuevaFuente) => void cambiarFuente(nuevaFuente)}
          onChange={setFiltros}
          onAplicar={() => void aplicarFiltros()}
          onLimpiar={limpiarFiltros}
          mostrarInfraestructura={mostrarInfraestructura}
          cargandoInfraestructura={cargandoInfraestructura}
          onToggleInfraestructura={() => void alternarInfraestructura()}
        />

        <div className="mapa-wrapper">
          {cantones ? (
            <MapView
              cantones={cantones}
              totalesPorCanton={totalesPorCanton}
              etiquetaMetrica={etiquetaMetrica}
              cantonSeleccionado={seleccion}
              onSeleccionar={(codigo, nombre) => void seleccionarCanton(codigo, nombre)}
              infraestructura={infraestructura}
              mostrarInfraestructura={mostrarInfraestructura}
            />
          ) : (
            <p className="nota">Cargando cantones…</p>
          )}
          <div className="leyenda">
            <span className="swatch" style={{ background: 'rgb(153,102,255)' }} /> bajo
            <span className="swatch" style={{ background: 'rgb(184,86,163)' }} /> medio
            <span className="swatch" style={{ background: 'rgb(178,24,21)' }} /> alto
            <span className="leyenda-nota">
              (intensidad relativa: {totalesPorCanton.features.length} cantones con datos)
            </span>
          </div>
          {mostrarInfraestructura && (
            <div className="leyenda leyenda-infraestructura">
              <span className="swatch" style={{ background: '#ff5d5d' }} /> hospital
              <span className="swatch" style={{ background: '#35c4ff' }} /> clínica
              <span className="swatch" style={{ background: '#ffb020' }} /> comisaría
              <span className="leyenda-nota">
                Infraestructura: © OpenStreetMap contributors, vía Overpass API
              </span>
            </div>
          )}
        </div>

        {seleccion && (
          <CantonDetail
            seleccion={seleccion}
            datos={detalle}
            fuenteMapa={fuenteMapa}
            etiquetaMetrica={etiquetaMetrica}
            cargando={cargando}
            error={error}
            panorama={panorama}
            cargandoPanorama={cargandoPanorama}
            onCerrar={() => {
              setSeleccion(null)
              setDetalle(null)
              setPanorama(null)
            }}
          />
        )}
      </main>

      <footer className="pie">
        <span>Fuentes: OIJ / Poder Judicial · COSEVI · SNIT · OpenStreetMap (Overpass)</span>
        <span>
          Datos agregados por cantón, sin perfiles individuales. Módulo activo: {etiquetaMetrica} ({fuente === 'accidentes' ? 'COSEVI' : 'OIJ/CKAN'}).
        </span>
      </footer>
    </div>
  )
}
