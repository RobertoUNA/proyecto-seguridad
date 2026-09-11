import { MapContainer, TileLayer, GeoJSON, CircleMarker, Popup } from 'react-leaflet'
import type { Layer, PathOptions } from 'leaflet'
import type { CantonCollection, CapaMapaCollection, InfraestructuraRow } from '../types'

interface Props {
  cantones: CantonCollection
  totalesPorCanton: CapaMapaCollection
  etiquetaMetrica: string
  cantonSeleccionado: { codigo: string; nombre: string } | null
  onSeleccionar: (codigo: string, nombre: string) => void
  infraestructura: InfraestructuraRow[]
  mostrarInfraestructura: boolean
}

const colorPorTipoInfraestructura: Record<string, string> = {
  hospital: '#ff5d5d',
  clinica: '#35c4ff',
  comisaria: '#ffb020',
}

const etiquetaTipoInfraestructura: Record<string, string> = {
  hospital: 'Hospital',
  clinica: 'Clínica',
  comisaria: 'Comisaría',
}

function colorPorIntensidad(valor: number, maximo: number): string {
  const t = Math.min(1, valor / Math.max(maximo, 1))
  const r = Math.round(153 + (178 - 153) * t)
  const g = Math.round(102 + (24 - 102) * t)
  const b = Math.round(255 + (21 - 255) * t)
  return `rgb(${r}, ${g}, ${b})`
}

const colorBase = 'rgba(58, 74, 102, 0.55)'

export default function MapView({
  cantones,
  totalesPorCanton,
  etiquetaMetrica,
  cantonSeleccionado,
  onSeleccionar,
  infraestructura,
  mostrarInfraestructura,
}: Props) {
  const maximo = Math.max(...totalesPorCanton.features.map((f) => f.properties.total), 1)
  const colorDeCanton = (codigo: string): string => {
    const f = totalesPorCanton.features.find(
      (x) => x.properties.codigo === codigo,
    )
    if (!f || f.geometry == null) return colorBase
    return colorPorIntensidad(f.properties.total, maximo)
  }

  const estiloCanton = (
    feature?: GeoJSON.Feature | undefined,
  ): PathOptions => {
    const codigo = feature?.properties?.codigo as string | undefined
    const seleccionado = cantonSeleccionado?.codigo === codigo
    return {
      fillColor: codigo ? colorDeCanton(codigo) : colorBase,
      color: seleccionado ? '#ffdd57' : '#2b3852',
      weight: seleccionado ? 2.5 : 1,
      fillOpacity: 0.85,
    }
  }

  const enCadaFeature = (feature: GeoJSON.Feature, layer: Layer) => {
    const nombre = feature.properties?.nombre as string
    const codigo = feature.properties?.codigo as string
    const f = totalesPorCanton.features.find(
      (x) => x.properties.codigo === codigo,
    )
    const total = f?.properties.total
    layer.on('click', () => onSeleccionar(codigo, nombre))
    layer.bindTooltip(
      `<strong>${nombre}</strong><br/>${
        total != null && total > 0
          ? `${total.toLocaleString('es-CR')} ${etiquetaMetrica} en el periodo`
          : f == null
            ? `sin datos de ${etiquetaMetrica}`
            : '0 casos en el periodo'
      }`,
      { sticky: true },
    )
  }

  return (
    <MapContainer center={[9.7489, -83.7534]} zoom={8} className="mapa">
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contribuidores'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <GeoJSON
        key={`${cantonSeleccionado?.codigo ?? 'all'}-${totalesPorCanton.features.length}-${etiquetaMetrica}`}
        data={cantones}
        style={estiloCanton}
        onEachFeature={enCadaFeature}
      />
      {mostrarInfraestructura &&
        infraestructura.map((item) => (
          <CircleMarker
            key={`${item.osm_type}-${item.osm_id}`}
            center={[item.lat, item.lon]}
            radius={5}
            pathOptions={{
              color: '#1c2742',
              weight: 1,
              fillColor: colorPorTipoInfraestructura[item.tipo] ?? '#9fb0d3',
              fillOpacity: 0.9,
            }}
          >
            <Popup>
              <strong>{item.nombre ?? 'Sin nombre'}</strong>
              <br />
              {etiquetaTipoInfraestructura[item.tipo] ?? item.tipo}
            </Popup>
          </CircleMarker>
        ))}
    </MapContainer>
  )
}
