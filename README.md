# IDP Demo — TanStack Start × Rust

A minimal, deployable full-stack demo for an internal developer platform (IDP).
It pairs a **TanStack Start** frontend (React + SSR) with a **Rust** (axum)
backend and wires them together with a single, simple interservice call.

## Architecture

```
┌──────────────────────────┐    HTTP (server function)    ┌───────────────────────┐
│  frontend (Node 3000)    │ ───────────────────────────▶ │  backend (Rust 3001)  │
│  TanStack Start (React)  │     GET /api/info            │  axum                 │
│                          │     GET /api/items           │                       │
│                          │ ◀─────────────────────────── │                       │
└──────────────────────────┘             JSON              └───────────────────────┘
```

- **`frontend/`** — TanStack Start (React 19, file-based routing, Tailwind).
- **`backend/`** — Rust + [axum](https://github.com/tokio-rs/axum) HTTP server.

## How the services connect

The browser never calls the backend directly. Instead:

1. The page calls a TanStack Start **server function**
   (`fetchBackendInfo`, `fetchBackendItems`) in
   [`frontend/src/lib/backend.ts`](frontend/src/lib/backend.ts).
2. The server function runs on the frontend's Node server and makes a normal
   `fetch` to the Rust backend.
3. The backend URL comes from the `BACKEND_URL` environment variable
   (defaults to `http://localhost:3001` locally, `http://backend:3001` in
   Docker Compose).

## Backend API

| Method | Path        | Description                                 |
| ------ | ----------- | ------------------------------------------- |
| GET    | `/health`   | Liveness probe (used by the IDP / Compose) |
| GET    | `/api/info` | Service metadata + uptime + request counter |
| GET    | `/api/items`| A small list of demo items                  |

## Local development

Prerequisites: Node ≥ 20, pnpm, Rust (stable).

Backend (terminal 1):

```bash
cd backend
cargo run          # listens on http://localhost:3001
```

Frontend (terminal 2):

```bash
cd frontend
pnpm install
pnpm dev           # listens on http://localhost:3000
```

Open http://localhost:3000.

## Run with Docker Compose

```bash
docker compose up --build
```

- Frontend: http://localhost:3000
- Backend:  http://localhost:3001

Compose connects the two services over an internal network and waits for the
backend's `/health` check before starting the frontend.

## Building for production

```bash
# Frontend — builds dist/client (static) + dist/server/server.js (server entry)
cd frontend && pnpm build
pnpm start     # runs: srvx --prod -s dist/client dist/server/server.js

# Backend
cd backend && cargo build --release
```

## Deploying through an IDP

Each service ships a production `Dockerfile`:

- [`backend/Dockerfile`](backend/Dockerfile) — multi-stage Rust build into a
  minimal Debian runtime with a `/health` HEALTHCHECK.
- [`frontend/Dockerfile`](frontend/Dockerfile) — multi-stage Node build served
  by [`srvx`](https://srvx.h3.dev).

Point your IDP at the two containers and:

1. Expose the frontend on port `3000` (public).
2. Keep the backend on port `3001` (internal), or expose it for debugging.
3. Set `BACKEND_URL` on the frontend to the backend's internal address
   (e.g. `http://backend:3001`).
4. Use `GET /health` on the backend as the liveness/readiness probe.

## Environment variables

| Variable      | Service  | Default                        | Description                  |
| ------------- | -------- | ------------------------------ | ---------------------------- |
| `BACKEND_URL` | frontend | `http://localhost:3001`        | Base URL of the Rust backend |
| `PORT`        | both     | `3000` / `3001`               | Listen port                  |
| `RUST_LOG`    | backend  | `backend=info,tower_http=info` | Log level                    |
