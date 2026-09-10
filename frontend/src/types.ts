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

export type FuenteActiva = 'delitos' | 'accidentes'

export interface AccidenteFiltros {
  canton?: string
  anio?: string
  clase?: string
  tipo?: string
}

export interface FiltrosMapa extends DelitoFiltros, AccidenteFiltros {}

export interface AccidenteRow {
  id: number
  canton_id: number | null
  canton_nombre: string | null
  provincia: string | null
  distrito: string | null
  anio: number
  clase: string
  tipo: string
  cantidad: number
  fuente: string
  fecha_obtencion: string
}

export interface AccidenteTotalesProperties {
  codigo: string | null
  nombre: string
  total_accidentes: number
  clases_distintas: number
  tipos_distintos: number
}

export type AccidenteTotalesCollection = GeoCollection<AccidenteTotalesProperties>

export interface AccidentesResponse {
  accidentes: AccidenteRow[]
  totales: AccidenteTotalesCollection
  resumen: { registro_cantidad: number }
  fuente: string
  descripcion_fuente: string
  fecha_obtencion: string | null
}

export interface CapaMapaProperties {
  codigo: string | null
  nombre: string
  total: number
}

export type CapaMapaCollection = GeoCollection<CapaMapaProperties>

export interface DetalleFuente {
  registros: { tipo: string; cantidad: number }[]
  resumen: { registro_cantidad: number }
  fuente: string
  descripcion_fuente: string
  fecha_obtencion: string | null
}

export interface FuenteInfo {
  fuente: string
  fecha_obtencion: string | null
  descripcion: string
}
