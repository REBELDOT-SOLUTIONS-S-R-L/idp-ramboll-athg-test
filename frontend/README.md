# frontend — TanStack Start

React + SSR frontend for the IDP demo. See the [root README](../README.md) for
architecture, how the services connect, and deployment instructions.

## Commands

```bash
pnpm install          # install dependencies
pnpm dev              # dev server (http://localhost:3000)
pnpm build            # production build → dist/client + dist/server/server.js
pnpm start            # run the production server (srvx)
pnpm generate-routes  # regenerate the route tree
```

## Configuration

| Variable      | Default                 | Description            |
| ------------- | ----------------------- | ---------------------- |
| `BACKEND_URL` | `http://localhost:3001` | Rust backend base URL |
