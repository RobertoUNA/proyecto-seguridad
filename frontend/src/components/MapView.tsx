import { MapContainer, TileLayer, GeoJSON } from 'react-leaflet'
import type { Layer, PathOptions } from 'leaflet'
import type { CantonCollection, DelitoTotalesCollection } from '../types'

interface Props {
  cantones: CantonCollection
  delitosPorCanton: DelitoTotalesCollection
  cantonSeleccionado: { codigo: string; nombre: string } | null
  onSeleccionar: (codigo: string, nombre: string) => void
}

const MAX_VALOR = 1_000_000

function colorPorIntensidad(valor: number): string {
  const t = Math.min(1, valor / MAX_VALOR)
  const r = Math.round(153 + (178 - 153) * t)
  const g = Math.round(102 + (24 - 102) * t)
  const b = Math.round(255 + (21 - 255) * t)
  return `rgb(${r}, ${g}, ${b})`
}

const colorBase = 'rgba(58, 74, 102, 0.55)'

export default function MapView({
  cantones,
  delitosPorCanton,
  cantonSeleccionado,
  onSeleccionar,
}: Props) {
  const colorDeCanton = (codigo: string): string => {
    const f = delitosPorCanton.features.find(
      (x) => x.properties.codigo === codigo,
    )
    if (!f || f.geometry == null) return colorBase
    return colorPorIntensidad(f.properties.total_delitos)
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
    const f = delitosPorCanton.features.find(
      (x) => x.properties.codigo === codigo,
    )
    const total = f?.properties.total_delitos
    layer.on('click', () => onSeleccionar(codigo, nombre))
    layer.bindTooltip(
      `<strong>${nombre}</strong><br/>${
        total != null && total > 0
          ? `${total.toLocaleString('es-CR')} casos en el periodo`
          : f == null
            ? 'sin datos de delitos'
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
        key={`${cantonSeleccionado?.codigo ?? 'all'}-${delitosPorCanton.features.length}`}
        data={cantones}
        style={estiloCanton}
        onEachFeature={enCadaFeature}
      />
    </MapContainer>
  )
}