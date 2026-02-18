use chrono::Utc;
use oc_apprentice_common::status::{DaemonStatus, WorkerStatus};
use std::sync::Mutex;

/// Mutex to serialize tests that modify the HOME env var (process-global state).
static HOME_LOCK: Mutex<()> = Mutex::new(());

fn sample_daemon_status() -> DaemonStatus {
    let now = Utc::now();
    DaemonStatus {
        pid: 12345,
        version: "0.1.0".to_string(),
        started_at: now,
        heartbeat: now,
        events_today: 42,
        permissions_ok: true,
        accessibility_permitted: true,
        screen_recording_permitted: true,
        db_path: "/tmp/test.db".to_string(),
        uptime_seconds: 3600,
    }
}

fn sample_worker_status() -> WorkerStatus {
    let now = Utc::now();
    WorkerStatus {
        pid: 54321,
        version: "0.1.0".to_string(),
        started_at: now,
        heartbeat: now,
        events_processed_today: 100,
        sops_generated: 3,
        last_pipeline_duration_ms: Some(250),
        consecutive_errors: 0,
        vlm_available: true,
        sop_inducer_available: false,
    }
}

#[test]
fn daemon_status_serialization_roundtrip() {
    let status = sample_daemon_status();
    let json = serde_json::to_string_pretty(&status).expect("serialize");
    let deserialized: DaemonStatus = serde_json::from_str(&json).expect("deserialize");

    assert_eq!(status.pid, deserialized.pid);
    assert_eq!(status.version, deserialized.version);
    assert_eq!(status.started_at, deserialized.started_at);
    assert_eq!(status.heartbeat, deserialized.heartbeat);
    assert_eq!(status.events_today, deserialized.events_today);
    assert_eq!(status.permissions_ok, deserialized.permissions_ok);
    assert_eq!(status.accessibility_permitted, deserialized.accessibility_permitted);
    assert_eq!(status.screen_recording_permitted, deserialized.screen_recording_permitted);
    assert_eq!(status.db_path, deserialized.db_path);
    assert_eq!(status.uptime_seconds, deserialized.uptime_seconds);
}

#[test]
fn worker_status_serialization_roundtrip() {
    let status = sample_worker_status();
    let json = serde_json::to_string_pretty(&status).expect("serialize");
    let deserialized: WorkerStatus = serde_json::from_str(&json).expect("deserialize");

    assert_eq!(status.pid, deserialized.pid);
    assert_eq!(status.version, deserialized.version);
    assert_eq!(status.started_at, deserialized.started_at);
    assert_eq!(status.heartbeat, deserialized.heartbeat);
    assert_eq!(status.events_processed_today, deserialized.events_processed_today);
    assert_eq!(status.sops_generated, deserialized.sops_generated);
    assert_eq!(status.last_pipeline_duration_ms, deserialized.last_pipeline_duration_ms);
    assert_eq!(status.consecutive_errors, deserialized.consecutive_errors);
    assert_eq!(status.vlm_available, deserialized.vlm_available);
    assert_eq!(status.sop_inducer_available, deserialized.sop_inducer_available);
}

#[test]
fn worker_status_optional_fields() {
    let mut status = sample_worker_status();
    status.last_pipeline_duration_ms = None;
    let json = serde_json::to_string(&status).expect("serialize");
    let deserialized: WorkerStatus = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(deserialized.last_pipeline_duration_ms, None);
}

#[test]
fn write_and_read_daemon_status_file() {
    let _lock = HOME_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().expect("create tempdir");
    let original_home = std::env::var("HOME").ok();
    std::env::set_var("HOME", tmp.path());

    let status = sample_daemon_status();
    oc_apprentice_common::status::write_status_file("daemon-status.json", &status)
        .expect("write status file");

    let read_back: DaemonStatus =
        oc_apprentice_common::status::read_status_file("daemon-status.json")
            .expect("read status file");

    // Restore HOME before assertions (so panics don't leave it wrong)
    if let Some(home) = original_home {
        std::env::set_var("HOME", home);
    }

    assert_eq!(status.pid, read_back.pid);
    assert_eq!(status.version, read_back.version);
    assert_eq!(status.events_today, read_back.events_today);
    assert_eq!(status.db_path, read_back.db_path);
}

#[test]
fn write_and_read_worker_status_file() {
    let _lock = HOME_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().expect("create tempdir");
    let original_home = std::env::var("HOME").ok();
    std::env::set_var("HOME", tmp.path());

    let status = sample_worker_status();
    oc_apprentice_common::status::write_status_file("worker-status.json", &status)
        .expect("write status file");

    let read_back: WorkerStatus =
        oc_apprentice_common::status::read_status_file("worker-status.json")
            .expect("read status file");

    if let Some(home) = original_home {
        std::env::set_var("HOME", home);
    }

    assert_eq!(status.pid, read_back.pid);
    assert_eq!(status.events_processed_today, read_back.events_processed_today);
    assert_eq!(status.sops_generated, read_back.sops_generated);
}

#[test]
fn read_nonexistent_status_file_returns_error() {
    let _lock = HOME_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().expect("create tempdir");
    let original_home = std::env::var("HOME").ok();
    std::env::set_var("HOME", tmp.path());

    let result = oc_apprentice_common::status::read_status_file::<DaemonStatus>("nonexistent.json");

    if let Some(home) = original_home {
        std::env::set_var("HOME", home);
    }

    assert!(result.is_err());
}

#[test]
fn write_status_creates_directory_if_missing() {
    let _lock = HOME_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().expect("create tempdir");
    let original_home = std::env::var("HOME").ok();
    std::env::set_var("HOME", tmp.path());

    let expected_dir = if cfg!(target_os = "macos") {
        tmp.path().join("Library/Application Support/oc-apprentice")
    } else {
        tmp.path().join(".local/share/oc-apprentice")
    };
    assert!(!expected_dir.exists());

    let status = sample_daemon_status();
    oc_apprentice_common::status::write_status_file("daemon-status.json", &status)
        .expect("write status file");

    let dir_exists = expected_dir.exists();

    if let Some(home) = original_home {
        std::env::set_var("HOME", home);
    }

    assert!(dir_exists);
}

#[test]
fn atomic_write_overwrites_previous_status() {
    let _lock = HOME_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().expect("create tempdir");
    let original_home = std::env::var("HOME").ok();
    std::env::set_var("HOME", tmp.path());

    let mut status = sample_daemon_status();
    status.events_today = 10;
    oc_apprentice_common::status::write_status_file("daemon-status.json", &status)
        .expect("write first");

    status.events_today = 99;
    status.heartbeat = Utc::now();
    oc_apprentice_common::status::write_status_file("daemon-status.json", &status)
        .expect("write second");

    let read_back: DaemonStatus =
        oc_apprentice_common::status::read_status_file("daemon-status.json")
            .expect("read back");

    if let Some(home) = original_home {
        std::env::set_var("HOME", home);
    }

    assert_eq!(read_back.events_today, 99);
}
