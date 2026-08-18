import { createFileRoute } from '@tanstack/react-router'
import { useCallback, useEffect, useState } from 'react'
import {
  fetchBackendInfo,
  fetchBackendItems,
  type BackendInfo,
  type BackendItem,
} from '#/lib/backend'

export const Route = createFileRoute('/')({ component: Home })

type LoadState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; info: BackendInfo; items: BackendItem[] }

function Home() {
  const [state, setState] = useState<LoadState>({ status: 'loading' })

  const load = useCallback(async () => {
    setState({ status: 'loading' })
    try {
      const [info, items] = await Promise.all([
        fetchBackendInfo(),
        fetchBackendItems(),
      ])
      setState({ status: 'ready', info, items })
    } catch (err) {
      setState({
        status: 'error',
        message: err instanceof Error ? err.message : String(err),
      })
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto max-w-3xl px-6 py-16">
        <header className="mb-10">
          <p className="text-sm font-medium uppercase tracking-widest text-cyan-400">
            IDP Demo
          </p>
          <h1 className="mt-2 text-4xl font-bold">TanStack Start × Rust</h1>
          <p className="mt-3 text-slate-400">
            A minimal frontend + backend demo with interservice connectivity,
            ready to deploy through your internal developer platform.
          </p>
        </header>

        <section className="mb-6 rounded-xl border border-slate-800 bg-slate-900/50 p-6">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Backend connection</h2>
            <StatusBadge status={state.status} />
          </div>

          {state.status === 'loading' && (
            <p className="mt-4 text-slate-400">Contacting the Rust backend…</p>
          )}

          {state.status === 'error' && (
            <div className="mt-4 rounded-lg border border-red-900/60 bg-red-950/40 p-4 text-red-300">
              <p className="font-medium">Could not reach the backend</p>
              <p className="mt-1 text-sm text-red-400">{state.message}</p>
            </div>
          )}

          {state.status === 'ready' && (
            <div className="mt-4">
              <dl className="grid grid-cols-2 gap-4 text-sm">
                <Stat label="Service" value={state.info.service} />
                <Stat label="Version" value={state.info.version} />
                <Stat label="Uptime" value={`${state.info.uptime_seconds}s`} />
                <Stat
                  label="Requests served"
                  value={String(state.info.request_count)}
                />
              </dl>
              <p className="mt-4 text-sm text-slate-500">
                {state.info.description}
              </p>
            </div>
          )}
        </section>

        {state.status === 'ready' && (
          <section className="mb-6 rounded-xl border border-slate-800 bg-slate-900/50 p-6">
            <h2 className="text-lg font-semibold">Items from the backend</h2>
            <ul className="mt-4 divide-y divide-slate-800">
              {state.items.map((item) => (
                <li key={item.id} className="flex items-baseline gap-4 py-3">
                  <span className="text-sm font-semibold text-cyan-400">
                    #{item.id}
                  </span>
                  <div>
                    <p className="font-medium">{item.name}</p>
                    <p className="text-sm text-slate-400">{item.description}</p>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        )}

        <button
          type="button"
          onClick={load}
          disabled={state.status === 'loading'}
          className="rounded-lg bg-cyan-500 px-4 py-2 font-medium text-slate-950 transition hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {state.status === 'loading' ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
    </main>
  )
}

function StatusBadge({ status }: { status: LoadState['status'] }) {
  if (status === 'loading') {
    return (
      <span className="rounded-full bg-amber-500/15 px-3 py-1 text-xs font-medium text-amber-300">
        Connecting…
      </span>
    )
  }
  if (status === 'error') {
    return (
      <span className="rounded-full bg-red-500/15 px-3 py-1 text-xs font-medium text-red-300">
        Unreachable
      </span>
    )
  }
  return (
    <span className="rounded-full bg-emerald-500/15 px-3 py-1 text-xs font-medium text-emerald-300">
      Connected
    </span>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-slate-500">{label}</dt>
      <dd className="mt-1 text-slate-100">{value}</dd>
    </div>
  )
}
