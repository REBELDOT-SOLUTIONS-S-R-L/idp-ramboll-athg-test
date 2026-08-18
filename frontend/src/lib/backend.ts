import { createServerFn } from '@tanstack/react-start'

export type BackendInfo = {
  service: string
  version: string
  description: string
  uptime_seconds: number
  request_count: number
  now: number
}

export type BackendItem = {
  id: number
  name: string
  description: string
}

/**
 * Resolve the Rust backend base URL.
 *
 * Server functions execute on the Node server, so `process.env` is available
 * there. Defaults to localhost for local development; in the Docker Compose
 * deployment the frontend is given BACKEND_URL=http://backend:3001.
 */
function backendUrl(): string {
  return process.env.BACKEND_URL ?? 'http://localhost:3001'
}

async function getJson<T>(path: string): Promise<T> {
  const url = `${backendUrl()}${path}`
  let res: Response
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(5000) })
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err)
    throw new Error(`Could not reach backend at ${url} (${reason})`)
  }
  if (!res.ok) {
    throw new Error(`Backend ${path} responded with status ${res.status}`)
  }
  return (await res.json()) as T
}

/** Fetch service metadata from the Rust backend. */
export const fetchBackendInfo = createServerFn({ method: 'GET' }).handler(() =>
  getJson<BackendInfo>('/api/info'),
)

/** Fetch the demo items from the Rust backend. */
export const fetchBackendItems = createServerFn({ method: 'GET' }).handler(() =>
  getJson<BackendItem[]>('/api/items'),
)
