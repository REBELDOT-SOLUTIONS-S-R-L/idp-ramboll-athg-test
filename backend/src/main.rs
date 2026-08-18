use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    extract::State,
    http::StatusCode,
    middleware,
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::Serialize;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

/// Shared application state, cheap to clone and thread-safe.
#[derive(Clone)]
struct AppState {
    started_at: Instant,
    request_count: Arc<AtomicU64>,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
    version: &'static str,
}

#[derive(Serialize)]
struct InfoResponse {
    service: &'static str,
    version: &'static str,
    description: &'static str,
    uptime_seconds: u64,
    request_count: u64,
    now: u64,
}

#[derive(Serialize, Clone)]
struct Item {
    id: u32,
    name: &'static str,
    description: &'static str,
}

/// Middleware that increments the request counter for every incoming request.
async fn count_requests(
    State(state): State<AppState>,
    request: axum::extract::Request,
    next: middleware::Next,
) -> Response {
    state.request_count.fetch_add(1, Ordering::Relaxed);
    next.run(request).await
}

/// Liveness probe — used by the IDP / container orchestration.
async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        service: "backend",
        version: env!("CARGO_PKG_VERSION"),
    })
}

/// Service metadata + a bit of runtime state to prove the backend is alive.
async fn info(State(state): State<AppState>) -> Json<InfoResponse> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();

    Json(InfoResponse {
        service: "backend",
        version: env!("CARGO_PKG_VERSION"),
        description: "Rust backend for the IDP demo",
        uptime_seconds: state.started_at.elapsed().as_secs(),
        request_count: state.request_count.load(Ordering::Relaxed),
        now,
    })
}

/// A small list of demo items, consumed by the frontend.
async fn items() -> Json<Vec<Item>> {
    Json(vec![
        Item {
            id: 1,
            name: "Alpha",
            description: "First demo item served by the Rust backend",
        },
        Item {
            id: 2,
            name: "Bravo",
            description: "Second demo item served by the Rust backend",
        },
        Item {
            id: 3,
            name: "Charlie",
            description: "Third demo item served by the Rust backend",
        },
    ])
}

/// Friendly root so hitting the service base URL gives a useful hint.
async fn root() -> impl IntoResponse {
    (StatusCode::OK, "IDP demo backend — try /health, /api/info or /api/items\n")
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "backend=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let state = AppState {
        started_at: Instant::now(),
        request_count: Arc::new(AtomicU64::new(0)),
    };

    let app = Router::new()
        .route("/", get(root))
        .route("/health", get(health))
        .route("/api/info", get(info))
        .route("/api/items", get(items))
        .layer(middleware::from_fn_with_state(state.clone(), count_requests))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "3001".to_string());
    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("failed to bind listener");

    tracing::info!("backend listening on http://{addr}");

    axum::serve(listener, app)
        .await
        .expect("server error");
}
