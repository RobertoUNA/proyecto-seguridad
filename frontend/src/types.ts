export interface CantonProperties {
  codigo: string
  nombre: string
  poblacion: number | null
  fuente: string
  fecha_obtencion: string
}

export interface GeoFeature<P = Record<string, unknown>> {
  type: 'Feature'
  properties: P
  geometry: GeoJSON.Geometry | null
}

export interface GeoCollection<P = Record<string, unknown>> {
  type: 'FeatureCollection'
  features: GeoFeature<P>[]
}

export type CantonCollection = GeoCollection<CantonProperties>

export interface DelitoRow {
  id: number
  canton_id: number | null
  provincia: string | null
  distrito: string | null
  tipo: string
  modalidad: string | null
  fecha: string
  cantidad: number
  fuente: string
  fecha_obtencion: string
}

export interface DelitoTotalesProperties {
  codigo: string | null
  nombre: string
  total_delitos: number
  tipos_distintos: number
}

export type DelitoTotalesCollection = GeoCollection<DelitoTotalesProperties>

export interface DelitosResponse {
  delitos: DelitoRow[]
  totales: DelitoTotalesCollection
  resumen: { registro_cantidad: number }
  fuente: string
  descripcion_fuente: string
  fecha_obtencion: string | null
}

export interface DelitoFiltros {
  canton?: string
  tipo?: string
  modalidad?: string
  desde?: string
  hasta?: string
}

export interface FuenteInfo {
  fuente: string
  fecha_obtencion: string | null
  descripcion: string
}