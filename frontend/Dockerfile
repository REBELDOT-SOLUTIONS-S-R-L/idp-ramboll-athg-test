# syntax=docker/dockerfile:1

# ---------- Build stage ----------
FROM node:22-bookworm-slim AS build
WORKDIR /app

# Install pnpm (pinned to the major that matches pnpm-lock.yaml).
RUN npm install -g pnpm@11

# Install dependencies first for better layer caching.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Build the app. Output: dist/client (static) + dist/server/server.js (fetch entry).
COPY . .
RUN pnpm build

# ---------- Runtime stage ----------
FROM node:22-bookworm-slim AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    BACKEND_URL=http://backend:3001

# Install only production dependencies (react, @tanstack/*, srvx CLI).
RUN npm install -g pnpm@11
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --prod --frozen-lockfile

# Copy the built bundles from the build stage.
COPY --from=build /app/dist ./dist

ENV PATH="/app/node_modules/.bin:${PATH}"
EXPOSE 3000

# srvx serves dist/client as static assets and forwards everything else to the
# TanStack Start server entry (dist/server/server.js).
CMD ["srvx", "--prod", "-s", "dist/client", "dist/server/server.js"]
