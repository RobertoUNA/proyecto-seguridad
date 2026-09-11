import type {
  CantonCollection,
  DelitoFiltros,
  DelitoTotalesCollection,
  DelitosResponse,
  AccidenteFiltros,
  AccidenteTotalesCollection,
  AccidentesResponse,
  InfraestructuraFiltros,
  InfraestructuraResponse,
  PanoramaResponse,
} from './types'

const API_BASE = '/api'

async function http<T>(url: string): Promise<T> {
  const res = await fetch(`${API_BASE}${url}`)
  if (!res.ok) {
    let message = `Error ${res.status}`
    try {
      const body = await res.json()
      message = body.message || message
    } catch {
      /* cuerpo no JSON */
    }
    throw new Error(message)
  }
  return res.json() as Promise<T>
}

export function fetchCantones(): Promise<CantonCollection> {
  return http<CantonCollection>('/cantones')
}

export function fetchTipos(): Promise<{ tipos: string[] }> {
  return http<{ tipos: string[] }>('/delitos/tipos')
}

export function fetchDelitos(filtros: DelitoFiltros): Promise<DelitosResponse> {
  const params = new URLSearchParams()
  if (filtros.canton) params.set('canton', filtros.canton)
  if (filtros.tipo) params.set('tipo', filtros.tipo)
  if (filtros.desde) params.set('desde', filtros.desde)
  if (filtros.hasta) params.set('hasta', filtros.hasta)
  const qs = params.toString()
  return http<DelitosResponse>(qs ? `/delitos?${qs}` : '/delitos')
}

export function fetchDelitosPorCanton(
  filtros: DelitoFiltros,
): Promise<DelitoTotalesCollection> {
  const params = new URLSearchParams()
  if (filtros.tipo) params.set('tipo', filtros.tipo)
  if (filtros.desde) params.set('desde', filtros.desde)
  if (filtros.hasta) params.set('hasta', filtros.hasta)
  const qs = params.toString()
  return http<DelitoTotalesCollection>(
    qs ? `/delitos/por-canton?${qs}` : '/delitos/por-canton',
  )
}

export function fetchAccidenteTipos(): Promise<{ tipos: string[] }> {
  return http<{ tipos: string[] }>('/accidentes/tipos')
}

export function fetchAccidenteClases(): Promise<{ clases: string[] }> {
  return http<{ clases: string[] }>('/accidentes/clases')
}

export function fetchAccidentes(filtros: AccidenteFiltros): Promise<AccidentesResponse> {
  const params = new URLSearchParams()
  if (filtros.canton) params.set('canton', filtros.canton)
  if (filtros.anio) params.set('anio', filtros.anio)
  if (filtros.clase) params.set('clase', filtros.clase)
  if (filtros.tipo) params.set('tipo', filtros.tipo)
  const qs = params.toString()
  return http<AccidentesResponse>(qs ? `/accidentes?${qs}` : '/accidentes')
}

export function fetchAccidentesPorCanton(
  filtros: AccidenteFiltros,
): Promise<AccidenteTotalesCollection> {
  const params = new URLSearchParams()
  if (filtros.anio) params.set('anio', filtros.anio)
  if (filtros.clase) params.set('clase', filtros.clase)
  if (filtros.tipo) params.set('tipo', filtros.tipo)
  const qs = params.toString()
  return http<AccidenteTotalesCollection>(
    qs ? `/accidentes/por-canton?${qs}` : '/accidentes/por-canton',
  )
}

export function fetchInfraestructura(
  filtros: InfraestructuraFiltros,
): Promise<InfraestructuraResponse> {
  const params = new URLSearchParams()
  if (filtros.canton) params.set('canton', filtros.canton)
  if (filtros.tipo) params.set('tipo', filtros.tipo)
  const qs = params.toString()
  return http<InfraestructuraResponse>(qs ? `/infraestructura?${qs}` : '/infraestructura')
}

export function fetchPanorama(id: string): Promise<PanoramaResponse> {
  return http<PanoramaResponse>(`/cantones/${encodeURIComponent(id)}/panorama`)
}
