use anyhow::Result;
use chrono::Timelike;
use std::path::PathBuf;
use tokio::sync::{mpsc, watch};
use tracing::{info, warn, error};
use tracing_subscriber::EnvFilter;

use oc_apprentice_daemon::ipc::native_messaging;
use oc_apprentice_daemon::observer::event_loop::{
    ObserverConfig, ObserverMessage, run_observer_loop, run_storage_writer,
};
use oc_apprentice_daemon::observer::health::HealthWatcher;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env()
                .add_directive("info".parse()?),
        )
        .init();

    info!("oc-apprentice-daemon starting");

    // Load AppConfig from standard config file location, fall back to defaults
    let app_config = {
        use oc_apprentice_common::config::AppConfig;

        let config_path = if cfg!(target_os = "macos") {
            std::env::var("HOME").ok().map(|home| {
                std::path::PathBuf::from(home)
                    .join("Library/Application Support/OpenClawApprentice/config.toml")
            })
        } else {
            std::env::var("HOME").ok().map(|home| {
                std::path::PathBuf::from(home)
                    .join(".config/oc-apprentice/config.toml")
            })
        };

        match config_path {
            Some(ref path) if path.is_file() => {
                match AppConfig::from_file(path) {
                    Ok(cfg) => {
                        info!(path = %path.display(), "Loaded configuration from file");
                        cfg
                    }
                    Err(e) => {
                        warn!(path = %path.display(), error = %e, "Failed to parse config, using defaults");
                        AppConfig::default()
                    }
                }
            }
            _ => {
                info!("No config file found, using defaults");
                AppConfig::default()
            }
        }
    };

    // Convert AppConfig -> ObserverConfig
    let config = ObserverConfig {
        t_dwell_seconds: app_config.observer.t_dwell_seconds,
        t_scroll_read_seconds: app_config.observer.t_scroll_read_seconds,
        capture_screenshots: app_config.observer.capture_screenshots,
        screenshot_max_per_minute: app_config.observer.screenshot_max_per_minute,
        poll_interval: std::time::Duration::from_millis(500),
        db_path: PathBuf::from("openmimic.db"),
    };

    // Channel for observer -> storage communication
    let (tx, rx) = mpsc::channel(1000);

    // Shutdown signal
    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    // Handle Ctrl+C
    let shutdown_tx_clone = shutdown_tx.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        info!("Received Ctrl+C, shutting down...");
        let _ = shutdown_tx_clone.send(true);
    });

    let db_path = config.db_path.clone();

    // Spawn storage writer
    let storage_handle = tokio::spawn(run_storage_writer(db_path.clone(), rx));

    // Spawn native messaging server (Chrome extension bridge)
    let native_tx = tx.clone();
    let native_handle = tokio::spawn(async move {
        // Create a channel to receive events from the native messaging server
        let (nm_event_tx, mut nm_event_rx) = mpsc::channel(256);

        // Spawn the forwarder that bridges Event -> ObserverMessage
        let forwarder_tx = native_tx;
        let forwarder_handle = tokio::spawn(async move {
            while let Some(event) = nm_event_rx.recv().await {
                if forwarder_tx.send(ObserverMessage::Event(event)).await.is_err() {
                    info!("Native messaging forwarder: main channel closed");
                    break;
                }
            }
        });

        // Run the native messaging server on stdio
        let mut server = native_messaging::stdio_server();
        if let Err(e) = server.run(nm_event_tx).await {
            warn!("Native messaging server exited: {}", e);
        }

        forwarder_handle.abort();
    });

    // Spawn health watcher (periodic background health checks)
    let health_shutdown_rx = shutdown_tx.subscribe();
    let health_handle = tokio::spawn(async move {
        let watcher = HealthWatcher::new(5, 512);
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        let mut shutdown_rx = health_shutdown_rx;

        loop {
            tokio::select! {
                _ = interval.tick() => {
                    let status = watcher.check();
                    if !status.is_healthy() {
                        warn!(
                            accessibility = status.accessibility_permitted,
                            screen_recording = status.screen_recording_permitted,
                            disk_ok = status.disk_space_ok,
                            free_gb = status.free_disk_gb,
                            memory_mb = status.daemon_memory_mb,
                            "Health check: unhealthy"
                        );
                    }
                }
                _ = shutdown_rx.changed() => {
                    info!("Health watcher shutting down");
                    break;
                }
            }
        }
    });

    // Spawn nightly maintenance trigger
    let maint_shutdown_rx = shutdown_tx.subscribe();
    let maint_db_path = db_path.clone();
    let maint_handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(3600));
        let mut shutdown_rx = maint_shutdown_rx;

        loop {
            tokio::select! {
                _ = interval.tick() => {
                    let hour = chrono::Local::now().hour();
                    if hour >= 1 && hour < 5 {
                        info!("Nightly maintenance window — running full maintenance");
                        match run_maintenance(&maint_db_path) {
                            Ok(report) => {
                                info!(
                                    events_purged = report.events_purged,
                                    episodes_purged = report.episodes_purged,
                                    vlm_purged = report.vlm_jobs_purged,
                                    artifacts = report.artifact_paths_to_delete.len(),
                                    vacuumed = report.vacuumed,
                                    "Nightly maintenance completed"
                                );
                            }
                            Err(e) => {
                                error!("Nightly maintenance failed: {}", e);
                            }
                        }
                    }
                }
                _ = shutdown_rx.changed() => {
                    info!("Maintenance timer shutting down");
                    break;
                }
            }
        }
    });

    // Spawn clipboard monitor (macOS only)
    #[cfg(target_os = "macos")]
    let clipboard_handle = {
        use oc_apprentice_daemon::platform::clipboard_monitor;
        let clip_tx = tx.clone();
        let clip_shutdown_rx = shutdown_tx.subscribe();
        tokio::spawn(async move {
            let (clip_event_tx, mut clip_event_rx) = mpsc::channel(64);

            // Spawn the forwarder that converts ClipboardMessage -> ObserverMessage
            let fwd_tx = clip_tx;
            let forwarder = tokio::spawn(async move {
                let mut hash_tracker = clipboard_monitor::ClipboardHashTracker::new();
                while let Some(msg) = clip_event_rx.recv().await {
                    match msg {
                        clipboard_monitor::ClipboardMessage::Change(change) => {
                            hash_tracker.record(change.content_hash.clone());
                            let event = oc_apprentice_common::event::Event {
                                id: uuid::Uuid::new_v4(),
                                timestamp: change.timestamp,
                                kind: oc_apprentice_common::event::EventKind::ClipboardChange {
                                    content_types: change.content_types,
                                    byte_size: change.byte_size,
                                    high_entropy: change.high_entropy,
                                    content_hash: change.content_hash,
                                },
                                window: None,
                                display_topology: vec![],
                                primary_display_id: "unknown".to_string(),
                                cursor_global_px: None,
                                ui_scale: None,
                                artifact_ids: vec![],
                                metadata: serde_json::json!({}),
                                display_ids_spanned: None,
                            };
                            if fwd_tx.send(ObserverMessage::Event(event)).await.is_err() {
                                info!("Clipboard forwarder: main channel closed");
                                break;
                            }
                        }
                        clipboard_monitor::ClipboardMessage::Shutdown => break,
                    }
                }
            });

            clipboard_monitor::run_clipboard_monitor(clip_event_tx, clip_shutdown_rx).await;
            forwarder.abort();
        })
    };

    // Create artifact store for screenshot capture.
    // Key is derived from a fixed seed — in production this should come from
    // the config or a key management service.  For now we use a deterministic
    // key so that artifacts can be read back by the same daemon instance.
    let artifact_store = {
        use oc_apprentice_storage::artifact_store::ArtifactStore;
        use sha2::{Digest, Sha256};

        let artifact_dir = db_path.parent().unwrap_or(std::path::Path::new(".")).join("artifacts");
        let mut hasher = Sha256::new();
        hasher.update(b"openmimic-local-artifact-key-v1");
        let key: [u8; 32] = hasher.finalize().into();

        Some(std::sync::Arc::new(ArtifactStore::new(artifact_dir, key)))
    };

    // Run observer loop (blocks until shutdown)
    let observer_result = run_observer_loop(config, tx, shutdown_rx, artifact_store).await;

    // Abort background tasks
    native_handle.abort();
    health_handle.abort();
    maint_handle.abort();
    #[cfg(target_os = "macos")]
    clipboard_handle.abort();

    // Wait for storage writer to finish
    storage_handle.await??;

    info!("oc-apprentice-daemon stopped");
    observer_result
}

/// Run full database maintenance cycle.
fn run_maintenance(
    db_path: &std::path::Path,
) -> Result<oc_apprentice_storage::maintenance::MaintenanceReport> {
    use oc_apprentice_storage::maintenance::MaintenanceRunner;

    let conn = rusqlite::Connection::open(db_path)?;
    let runner = MaintenanceRunner::new(&conn);
    runner.run_full_maintenance(
        db_path,
        14,  // retention_days_raw
        90,  // retention_days_episodes
        5,   // min_free_gb
        2.1, // vacuum_safety_multiplier
    )
}
