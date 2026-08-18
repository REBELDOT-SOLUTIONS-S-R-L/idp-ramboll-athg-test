# syntax=docker/dockerfile:1

# ---------- Build stage ----------
FROM rust:1.96-bookworm AS builder
WORKDIR /app

# Cache the dependency layer by building against a stub main first.
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main() {}' > src/main.rs \
    && cargo build --release \
    && rm -rf src

# Now build the real binary (only the backend crate recompiles).
COPY src ./src
RUN cargo build --release

# ---------- Runtime stage ----------
FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/backend /usr/local/bin/backend

ENV PORT=3001
EXPOSE 3001

# Liveness probe — used by the IDP / Docker Compose readiness gate.
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=12 \
  CMD curl -fsS http://localhost:3001/health || exit 1

CMD ["backend"]
