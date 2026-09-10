import type {
  CantonCollection,
  DelitoFiltros,
  DelitoTotalesCollection,
  DelitosResponse,
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