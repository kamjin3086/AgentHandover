use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Status written by the daemon every 60s to daemon-status.json
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonStatus {
    pub pid: u32,
    pub version: String,
    pub started_at: DateTime<Utc>,
    pub heartbeat: DateTime<Utc>,
    pub events_today: u64,
    pub permissions_ok: bool,
    pub accessibility_permitted: bool,
    pub screen_recording_permitted: bool,
    pub db_path: String,
    pub uptime_seconds: u64,
}

/// Status written by the worker each poll cycle to worker-status.json
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkerStatus {
    pub pid: u32,
    pub version: String,
    pub started_at: DateTime<Utc>,
    pub heartbeat: DateTime<Utc>,
    pub events_processed_today: u64,
    pub sops_generated: u64,
    pub last_pipeline_duration_ms: Option<u64>,
    pub consecutive_errors: u32,
    pub vlm_available: bool,
    pub sop_inducer_available: bool,
}

/// Standard location for status files.
pub fn status_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    if cfg!(target_os = "macos") {
        PathBuf::from(home).join("Library/Application Support/oc-apprentice")
    } else {
        PathBuf::from(home).join(".local/share/oc-apprentice")
    }
}

/// Atomically write a status file (tmp + rename).
pub fn write_status_file(filename: &str, status: &impl Serialize) -> std::io::Result<()> {
    let dir = status_dir();
    std::fs::create_dir_all(&dir)?;
    let target = dir.join(filename);
    let tmp = dir.join(format!(".{}.tmp", filename));
    let json = serde_json::to_string_pretty(status)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    std::fs::write(&tmp, json.as_bytes())?;
    std::fs::rename(&tmp, &target)?;
    Ok(())
}

/// Read and deserialize a status file.
pub fn read_status_file<T: serde::de::DeserializeOwned>(filename: &str) -> std::io::Result<T> {
    let path = status_dir().join(filename);
    let content = std::fs::read_to_string(&path)?;
    serde_json::from_str(&content)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}
