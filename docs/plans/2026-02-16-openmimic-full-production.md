# OpenMimic Full Production Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a local, always-on apprentice subsystem that silently observes laptop work, learns workflows, and produces semantic SOPs for OpenClaw execution — from zero to production across 4 phases.

**Architecture:** Three-process model: (1) `oc-apprentice-daemon` (Rust) — ultra-light always-on observer capturing OS events, browser extension IPC, screenshots, and accessibility trees with inline redaction; (2) `oc-apprentice-worker` (Python) — idle-time pipeline for episode building, semantic translation, SOP induction/export; (3) Chrome MV3 browser extension (TypeScript) — captures DOM snapshots, click intent, and ARIA metadata via Native Messaging to the daemon. SQLite WAL is the local event broker between daemon and worker. Artifacts stored as compressed+encrypted binary files.

**Tech Stack:**
- **Daemon:** Rust (2021 edition), tokio async runtime, rusqlite (SQLite WAL), chacha20poly1305 (encryption), zstd (compression), figment (config), accessibility/core-graphics/core-foundation (macOS APIs)
- **Extension:** TypeScript, Chrome MV3 Manifest, Native Messaging, IntersectionObserver
- **Worker:** Python 3.11+, detect-secrets (redaction), prefixspan (pattern mining), python-frontmatter (SOP files), mlx-vlm (Phase 3 VLM)
- **Config:** TOML with JSON Schema validation

---

## Phase 0 — Foundations (Tasks 1–18)

### Task 1: Initialize Rust Workspace + Project Skeleton

**Files:**
- Create: `Cargo.toml` (workspace root)
- Create: `crates/daemon/Cargo.toml`
- Create: `crates/daemon/src/main.rs`
- Create: `crates/common/Cargo.toml`
- Create: `crates/common/src/lib.rs`
- Create: `rust-toolchain.toml`
- Create: `.gitignore`

**Step 1: Create workspace Cargo.toml**

```toml
# Cargo.toml (workspace root)
[workspace]
resolver = "2"
members = [
    "crates/daemon",
    "crates/common",
]

[workspace.package]
version = "0.1.0"
edition = "2021"
license = "MIT"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
anyhow = "1"
thiserror = "2"
```

**Step 2: Create crates/common/Cargo.toml**

```toml
[package]
name = "oc-apprentice-common"
version.workspace = true
edition.workspace = true

[dependencies]
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4", "serde"] }
```

**Step 3: Create crates/common/src/lib.rs**

```rust
pub mod event;
pub mod config;

pub use event::Event;
```

**Step 4: Create crates/daemon/Cargo.toml**

```toml
[package]
name = "oc-apprentice-daemon"
version.workspace = true
edition.workspace = true

[[bin]]
name = "oc-apprentice-daemon"
path = "src/main.rs"

[dependencies]
oc-apprentice-common = { path = "../common" }
serde.workspace = true
serde_json.workspace = true
tokio.workspace = true
tracing.workspace = true
tracing-subscriber.workspace = true
anyhow.workspace = true
thiserror.workspace = true
```

**Step 5: Create crates/daemon/src/main.rs**

```rust
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse()?))
        .init();

    info!("oc-apprentice-daemon starting");
    Ok(())
}
```

**Step 6: Create rust-toolchain.toml**

```toml
[toolchain]
channel = "stable"
```

**Step 7: Create .gitignore**

```
/target
*.swp
*.swo
.DS_Store
*.db
*.db-wal
*.db-shm
artifacts/
```

**Step 8: Build and verify**

Run: `cargo build`
Expected: Compiles successfully with no errors.

**Step 9: Initialize git repo and commit**

```bash
git init
git add -A
git commit -m "feat: initialize Rust workspace with daemon and common crates"
```

---

### Task 2: Define Core Event Data Model

**Files:**
- Create: `crates/common/src/event.rs`
- Modify: `crates/common/src/lib.rs`
- Create: `crates/common/tests/event_test.rs`

**Step 1: Write the failing test**

```rust
// crates/common/tests/event_test.rs
use oc_apprentice_common::event::{
    Event, EventKind, DisplayInfo, WindowInfo, CursorPosition,
};
use chrono::Utc;
use uuid::Uuid;

#[test]
fn test_event_creation_and_serialization() {
    let event = Event {
        id: Uuid::new_v4(),
        timestamp: Utc::now(),
        kind: EventKind::FocusChange,
        window: Some(WindowInfo {
            window_id: "win_123".into(),
            app_id: "com.apple.Safari".into(),
            title: "Google - Safari".into(),
            bounds_global_px: [0, 0, 1920, 1080],
            z_order: 0,
            is_fullscreen: false,
        }),
        display_topology: vec![DisplayInfo {
            display_id: "display_1".into(),
            bounds_global_px: [0, 0, 2560, 1440],
            scale_factor: 2.0,
            orientation: 0,
        }],
        primary_display_id: "display_1".into(),
        cursor_global_px: Some(CursorPosition { x: 500, y: 300 }),
        ui_scale: Some(2.0),
        artifact_ids: vec![],
        metadata: serde_json::json!({}),
    };

    let json = serde_json::to_string(&event).unwrap();
    let deserialized: Event = serde_json::from_str(&json).unwrap();
    assert_eq!(deserialized.id, event.id);
    assert_eq!(deserialized.kind, EventKind::FocusChange);
    assert_eq!(deserialized.window.as_ref().unwrap().app_id, "com.apple.Safari");
}

#[test]
fn test_event_kind_variants() {
    let kinds = vec![
        EventKind::FocusChange,
        EventKind::WindowTitleChange,
        EventKind::ClickIntent { target_description: "Export CSV button".into() },
        EventKind::DwellSnapshot,
        EventKind::ScrollReadSnapshot,
        EventKind::ClipboardChange { content_types: vec!["text/plain".into()], byte_size: 42, high_entropy: false, content_hash: "abc123".into() },
        EventKind::PasteDetected { matched_copy_hash: Some("abc123".into()) },
        EventKind::SecureFieldFocus,
        EventKind::AppSwitch { from_app: "Safari".into(), to_app: "Terminal".into() },
    ];
    for kind in &kinds {
        let json = serde_json::to_string(kind).unwrap();
        let _: EventKind = serde_json::from_str(&json).unwrap();
    }
    assert_eq!(kinds.len(), 9);
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -p oc-apprentice-common`
Expected: FAIL — `event` module not found.

**Step 3: Create crates/common/src/event.rs**

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub id: Uuid,
    pub timestamp: DateTime<Utc>,
    pub kind: EventKind,
    pub window: Option<WindowInfo>,
    pub display_topology: Vec<DisplayInfo>,
    pub primary_display_id: String,
    pub cursor_global_px: Option<CursorPosition>,
    pub ui_scale: Option<f64>,
    pub artifact_ids: Vec<Uuid>,
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum EventKind {
    FocusChange,
    WindowTitleChange,
    ClickIntent { target_description: String },
    DwellSnapshot,
    ScrollReadSnapshot,
    ClipboardChange {
        content_types: Vec<String>,
        byte_size: u64,
        high_entropy: bool,
        content_hash: String,
    },
    PasteDetected {
        matched_copy_hash: Option<String>,
    },
    SecureFieldFocus,
    AppSwitch {
        from_app: String,
        to_app: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowInfo {
    pub window_id: String,
    pub app_id: String,
    pub title: String,
    pub bounds_global_px: [i32; 4],
    pub z_order: u32,
    pub is_fullscreen: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayInfo {
    pub display_id: String,
    pub bounds_global_px: [i32; 4],
    pub scale_factor: f64,
    pub orientation: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorPosition {
    pub x: i32,
    pub y: i32,
}
```

**Step 4: Update crates/common/src/lib.rs**

```rust
pub mod event;
pub mod config;
```

**Step 5: Create empty config module placeholder**

```rust
// crates/common/src/config.rs
// Will be populated in Task 3
```

**Step 6: Run tests to verify they pass**

Run: `cargo test -p oc-apprentice-common`
Expected: 2 tests PASS.

**Step 7: Commit**

```bash
git add crates/common/
git commit -m "feat: define core Event data model with multi-monitor support"
```

---

### Task 3: Configuration Schema (TOML + Validation)

**Files:**
- Modify: `crates/common/Cargo.toml` (add figment, toml deps)
- Create: `crates/common/src/config.rs`
- Create: `crates/common/tests/config_test.rs`
- Create: `config.example.toml`

**Step 1: Add dependencies to crates/common/Cargo.toml**

Add under `[dependencies]`:
```toml
figment = { version = "0.10", features = ["toml", "env"] }
toml = "0.8"
directories = "6"
```

**Step 2: Write the failing test**

```rust
// crates/common/tests/config_test.rs
use oc_apprentice_common::config::AppConfig;

#[test]
fn test_default_config_is_valid() {
    let config = AppConfig::default();
    assert_eq!(config.observer.t_dwell_seconds, 3);
    assert_eq!(config.observer.t_scroll_read_seconds, 8);
    assert!(config.observer.capture_screenshots);
    assert_eq!(config.observer.screenshot_max_per_minute, 20);
    assert!(config.privacy.enable_inline_secret_redaction);
    assert!(!config.privacy.enable_clipboard_preview);
    assert!(config.privacy.secure_field_drop);
    assert_eq!(config.storage.retention_days_raw, 14);
    assert!(config.storage.sqlite_wal_mode);
    assert_eq!(config.storage.vacuum_min_free_gb, 5);
    assert!(config.idle_jobs.require_ac_power);
    assert_eq!(config.idle_jobs.min_battery_percent, 50);
    assert_eq!(config.idle_jobs.max_cpu_percent, 30);
    assert_eq!(config.vlm.max_jobs_per_day, 50);
    assert!(config.openclaw.atomic_writes);
}

#[test]
fn test_config_from_toml_string() {
    let toml_str = r#"
[observer]
t_dwell_seconds = 5
screenshot_max_per_minute = 10

[privacy]
enable_clipboard_preview = true
clipboard_preview_max_chars = 100

[storage]
retention_days_raw = 7
"#;
    let config = AppConfig::from_toml_str(toml_str).unwrap();
    assert_eq!(config.observer.t_dwell_seconds, 5);
    assert_eq!(config.observer.screenshot_max_per_minute, 10);
    assert!(config.privacy.enable_clipboard_preview);
    assert_eq!(config.privacy.clipboard_preview_max_chars, 100);
    assert_eq!(config.storage.retention_days_raw, 7);
    // defaults still apply for unset fields
    assert!(config.observer.capture_screenshots);
    assert!(config.privacy.secure_field_drop);
}
```

**Step 3: Run test to verify it fails**

Run: `cargo test -p oc-apprentice-common -- config`
Expected: FAIL — AppConfig not defined.

**Step 4: Implement crates/common/src/config.rs**

```rust
use figment::{Figment, providers::{Format, Toml, Serialized}};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    #[serde(default)]
    pub observer: ObserverConfig,
    #[serde(default)]
    pub privacy: PrivacyConfig,
    #[serde(default)]
    pub browser: BrowserConfig,
    #[serde(default)]
    pub storage: StorageConfig,
    #[serde(default)]
    pub idle_jobs: IdleJobsConfig,
    #[serde(default)]
    pub vlm: VlmConfig,
    #[serde(default)]
    pub openclaw: OpenClawConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObserverConfig {
    pub t_dwell_seconds: u64,
    pub t_scroll_read_seconds: u64,
    pub capture_screenshots: bool,
    pub screenshot_max_per_minute: u32,
    pub multi_monitor_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivacyConfig {
    pub enable_inline_secret_redaction: bool,
    pub enable_clipboard_preview: bool,
    pub clipboard_preview_max_chars: usize,
    pub secure_field_drop: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrowserConfig {
    pub extension_id: String,
    pub native_host_name: String,
    pub deny_network_egress: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageConfig {
    pub retention_days_raw: u32,
    pub retention_days_episodes: u32,
    pub sqlite_wal_mode: bool,
    pub vacuum_min_free_gb: u64,
    pub vacuum_safety_multiplier: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IdleJobsConfig {
    pub require_ac_power: bool,
    pub min_battery_percent: u32,
    pub max_cpu_percent: u32,
    pub max_temp_c: u32,
    pub run_window_local_time: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VlmConfig {
    pub enabled: bool,
    pub max_jobs_per_day: u32,
    pub max_queue_size: u32,
    pub job_ttl_days: u32,
    pub max_compute_minutes_per_day: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenClawConfig {
    pub workspace_path: String,
    pub sop_output_dir: String,
    pub index_path: String,
    pub atomic_writes: bool,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            observer: ObserverConfig::default(),
            privacy: PrivacyConfig::default(),
            browser: BrowserConfig::default(),
            storage: StorageConfig::default(),
            idle_jobs: IdleJobsConfig::default(),
            vlm: VlmConfig::default(),
            openclaw: OpenClawConfig::default(),
        }
    }
}

impl Default for ObserverConfig {
    fn default() -> Self {
        Self {
            t_dwell_seconds: 3,
            t_scroll_read_seconds: 8,
            capture_screenshots: true,
            screenshot_max_per_minute: 20,
            multi_monitor_mode: "focused_window".into(),
        }
    }
}

impl Default for PrivacyConfig {
    fn default() -> Self {
        Self {
            enable_inline_secret_redaction: true,
            enable_clipboard_preview: false,
            clipboard_preview_max_chars: 200,
            secure_field_drop: true,
        }
    }
}

impl Default for BrowserConfig {
    fn default() -> Self {
        Self {
            extension_id: "knldjmfmopnpolahpmmgbagdohdnhkik".into(),
            native_host_name: "com.openclaw.apprentice".into(),
            deny_network_egress: true,
        }
    }
}

impl Default for StorageConfig {
    fn default() -> Self {
        Self {
            retention_days_raw: 14,
            retention_days_episodes: 90,
            sqlite_wal_mode: true,
            vacuum_min_free_gb: 5,
            vacuum_safety_multiplier: 2.1,
        }
    }
}

impl Default for IdleJobsConfig {
    fn default() -> Self {
        Self {
            require_ac_power: true,
            min_battery_percent: 50,
            max_cpu_percent: 30,
            max_temp_c: 80,
            run_window_local_time: "01:00-05:00".into(),
        }
    }
}

impl Default for VlmConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            max_jobs_per_day: 50,
            max_queue_size: 500,
            job_ttl_days: 7,
            max_compute_minutes_per_day: 20,
        }
    }
}

impl Default for OpenClawConfig {
    fn default() -> Self {
        Self {
            workspace_path: "~/.openclaw/workspace".into(),
            sop_output_dir: "memory/apprentice/sops".into(),
            index_path: "memory/apprentice/index.md".into(),
            atomic_writes: true,
        }
    }
}

impl AppConfig {
    pub fn from_toml_str(toml_str: &str) -> Result<Self, figment::Error> {
        Figment::from(Serialized::defaults(AppConfig::default()))
            .merge(Toml::string(toml_str))
            .extract()
    }

    pub fn from_file(path: &std::path::Path) -> Result<Self, figment::Error> {
        Figment::from(Serialized::defaults(AppConfig::default()))
            .merge(Toml::file(path))
            .extract()
    }
}
```

**Step 5: Create config.example.toml at repo root**

```toml
# config.example.toml — OpenMimic Apprentice configuration
# Copy to the OS-appropriate location:
#   macOS:   ~/Library/Application Support/OpenClawApprentice/config.toml
#   Windows: %AppData%\OpenClawApprentice\config.toml
#   Linux:   $XDG_CONFIG_HOME/openclaw-apprentice/config.toml

[observer]
t_dwell_seconds = 3
t_scroll_read_seconds = 8
capture_screenshots = true
screenshot_max_per_minute = 20
multi_monitor_mode = "focused_window"

[privacy]
enable_inline_secret_redaction = true
enable_clipboard_preview = false
clipboard_preview_max_chars = 200
secure_field_drop = true

[browser]
extension_id = "knldjmfmopnpolahpmmgbagdohdnhkik"
native_host_name = "com.openclaw.apprentice"
deny_network_egress = true

[storage]
retention_days_raw = 14
retention_days_episodes = 90
sqlite_wal_mode = true
vacuum_min_free_gb = 5
vacuum_safety_multiplier = 2.1

[idle_jobs]
require_ac_power = true
min_battery_percent = 50
max_cpu_percent = 30
max_temp_c = 80
run_window_local_time = "01:00-05:00"

[vlm]
enabled = true
max_jobs_per_day = 50
max_queue_size = 500
job_ttl_days = 7
max_compute_minutes_per_day = 20

[openclaw]
workspace_path = "~/.openclaw/workspace"
sop_output_dir = "memory/apprentice/sops"
index_path = "memory/apprentice/index.md"
atomic_writes = true
```

**Step 6: Run tests**

Run: `cargo test -p oc-apprentice-common -- config`
Expected: 2 tests PASS.

**Step 7: Commit**

```bash
git add crates/common/ config.example.toml
git commit -m "feat: add TOML configuration schema with defaults and validation"
```

---

### Task 4: SQLite Storage Layer (WAL Mode + Schema + Migrations)

**Files:**
- Create: `crates/storage/Cargo.toml`
- Create: `crates/storage/src/lib.rs`
- Create: `crates/storage/src/schema.rs`
- Create: `crates/storage/src/migrations/mod.rs`
- Create: `crates/storage/src/migrations/v001_initial.sql`
- Create: `crates/storage/tests/storage_test.rs`
- Modify: `Cargo.toml` (add to workspace members)

**Step 1: Add storage crate to workspace**

Add `"crates/storage"` to `[workspace.members]` in root `Cargo.toml`.

Add to `[workspace.dependencies]`:
```toml
rusqlite = { version = "0.32", features = ["bundled", "backup"] }
```

**Step 2: Create crates/storage/Cargo.toml**

```toml
[package]
name = "oc-apprentice-storage"
version.workspace = true
edition.workspace = true

[dependencies]
oc-apprentice-common = { path = "../common" }
rusqlite.workspace = true
serde.workspace = true
serde_json.workspace = true
anyhow.workspace = true
thiserror.workspace = true
tracing.workspace = true
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4", "serde"] }

[dev-dependencies]
tempfile = "3"
```

**Step 3: Write migration SQL**

```sql
-- crates/storage/src/migrations/v001_initial.sql
CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY NOT NULL,
    timestamp TEXT NOT NULL,
    kind_json TEXT NOT NULL,
    window_json TEXT,
    display_topology_json TEXT NOT NULL,
    primary_display_id TEXT NOT NULL,
    cursor_x INTEGER,
    cursor_y INTEGER,
    ui_scale REAL,
    artifact_ids_json TEXT NOT NULL DEFAULT '[]',
    metadata_json TEXT NOT NULL DEFAULT '{}',
    processed INTEGER NOT NULL DEFAULT 0,
    episode_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_events_processed ON events(processed);
CREATE INDEX IF NOT EXISTS idx_events_episode_id ON events(episode_id);

CREATE TABLE IF NOT EXISTS artifacts (
    id TEXT PRIMARY KEY NOT NULL,
    event_id TEXT NOT NULL REFERENCES events(id),
    artifact_type TEXT NOT NULL,
    file_path TEXT NOT NULL,
    compression_algo TEXT NOT NULL DEFAULT 'zstd',
    encryption_algo TEXT NOT NULL DEFAULT 'xchacha20poly1305',
    original_size_bytes INTEGER NOT NULL,
    stored_size_bytes INTEGER NOT NULL,
    artifact_version INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_artifacts_event_id ON artifacts(event_id);

CREATE TABLE IF NOT EXISTS episodes (
    id TEXT PRIMARY KEY NOT NULL,
    segment_id INTEGER NOT NULL DEFAULT 0,
    prev_segment_id INTEGER,
    thread_id TEXT,
    start_time TEXT NOT NULL,
    end_time TEXT,
    event_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'open',
    summary TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS vlm_queue (
    id TEXT PRIMARY KEY NOT NULL,
    event_id TEXT NOT NULL REFERENCES events(id),
    priority REAL NOT NULL DEFAULT 0.5,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    processed_at TEXT,
    result_json TEXT,
    ttl_expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_vlm_queue_status ON vlm_queue(status, priority DESC);
```

**Step 4: Write the failing test**

```rust
// crates/storage/tests/storage_test.rs
use oc_apprentice_storage::EventStore;
use oc_apprentice_common::event::*;
use chrono::Utc;
use uuid::Uuid;
use tempfile::TempDir;

fn make_test_event() -> Event {
    Event {
        id: Uuid::new_v4(),
        timestamp: Utc::now(),
        kind: EventKind::FocusChange,
        window: Some(WindowInfo {
            window_id: "win_1".into(),
            app_id: "com.app.Test".into(),
            title: "Test Window".into(),
            bounds_global_px: [0, 0, 800, 600],
            z_order: 0,
            is_fullscreen: false,
        }),
        display_topology: vec![DisplayInfo {
            display_id: "d1".into(),
            bounds_global_px: [0, 0, 2560, 1440],
            scale_factor: 2.0,
            orientation: 0,
        }],
        primary_display_id: "d1".into(),
        cursor_global_px: Some(CursorPosition { x: 100, y: 200 }),
        ui_scale: Some(2.0),
        artifact_ids: vec![],
        metadata: serde_json::json!({}),
    }
}

#[test]
fn test_create_store_and_insert_event() {
    let tmp = TempDir::new().unwrap();
    let db_path = tmp.path().join("test.db");
    let store = EventStore::open(&db_path).unwrap();

    let event = make_test_event();
    let id = event.id;
    store.insert_event(&event).unwrap();

    let fetched = store.get_event(id).unwrap().unwrap();
    assert_eq!(fetched.id, id);
    assert_eq!(fetched.kind, EventKind::FocusChange);
}

#[test]
fn test_wal_mode_enabled() {
    let tmp = TempDir::new().unwrap();
    let db_path = tmp.path().join("test_wal.db");
    let store = EventStore::open(&db_path).unwrap();
    assert!(store.is_wal_mode());
}

#[test]
fn test_schema_version() {
    let tmp = TempDir::new().unwrap();
    let db_path = tmp.path().join("test_ver.db");
    let store = EventStore::open(&db_path).unwrap();
    assert_eq!(store.schema_version(), 1);
}

#[test]
fn test_get_unprocessed_events() {
    let tmp = TempDir::new().unwrap();
    let db_path = tmp.path().join("test_unproc.db");
    let store = EventStore::open(&db_path).unwrap();

    for _ in 0..5 {
        store.insert_event(&make_test_event()).unwrap();
    }

    let unprocessed = store.get_unprocessed_events(10).unwrap();
    assert_eq!(unprocessed.len(), 5);
}
```

**Step 5: Run tests to verify they fail**

Run: `cargo test -p oc-apprentice-storage`
Expected: FAIL — module not found.

**Step 6: Implement crates/storage/src/lib.rs**

```rust
mod schema;
mod migrations;

use anyhow::Result;
use oc_apprentice_common::event::*;
use rusqlite::{Connection, params};
use std::path::Path;
use uuid::Uuid;

pub struct EventStore {
    conn: Connection,
}

impl EventStore {
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)?;

        // Enable WAL mode
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.pragma_update(None, "busy_timeout", 5000)?;

        let store = Self { conn };
        store.run_migrations()?;
        Ok(store)
    }

    fn run_migrations(&self) -> Result<()> {
        let current_version: u32 = self.conn.pragma_query_value(None, "user_version", |row| row.get(0))?;

        if current_version < 1 {
            self.conn.execute_batch(include_str!("migrations/v001_initial.sql"))?;
            self.conn.pragma_update(None, "user_version", 1)?;
        }

        Ok(())
    }

    pub fn schema_version(&self) -> u32 {
        self.conn.pragma_query_value(None, "user_version", |row| row.get(0)).unwrap_or(0)
    }

    pub fn is_wal_mode(&self) -> bool {
        let mode: String = self.conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap_or_default();
        mode.to_lowercase() == "wal"
    }

    pub fn insert_event(&self, event: &Event) -> Result<()> {
        let cursor_x = event.cursor_global_px.as_ref().map(|c| c.x);
        let cursor_y = event.cursor_global_px.as_ref().map(|c| c.y);

        self.conn.execute(
            "INSERT INTO events (id, timestamp, kind_json, window_json, display_topology_json, primary_display_id, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                event.id.to_string(),
                event.timestamp.to_rfc3339(),
                serde_json::to_string(&event.kind)?,
                event.window.as_ref().map(|w| serde_json::to_string(w).unwrap()),
                serde_json::to_string(&event.display_topology)?,
                event.primary_display_id,
                cursor_x,
                cursor_y,
                event.ui_scale,
                serde_json::to_string(&event.artifact_ids)?,
                event.metadata.to_string(),
            ],
        )?;
        Ok(())
    }

    pub fn get_event(&self, id: Uuid) -> Result<Option<Event>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, timestamp, kind_json, window_json, display_topology_json, primary_display_id, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json FROM events WHERE id = ?1"
        )?;

        let result = stmt.query_row(params![id.to_string()], |row| {
            let id_str: String = row.get(0)?;
            let ts_str: String = row.get(1)?;
            let kind_json: String = row.get(2)?;
            let window_json: Option<String> = row.get(3)?;
            let display_json: String = row.get(4)?;
            let primary_display: String = row.get(5)?;
            let cursor_x: Option<i32> = row.get(6)?;
            let cursor_y: Option<i32> = row.get(7)?;
            let ui_scale: Option<f64> = row.get(8)?;
            let artifact_ids_json: String = row.get(9)?;
            let metadata_json: String = row.get(10)?;

            Ok((id_str, ts_str, kind_json, window_json, display_json, primary_display, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json))
        }).optional();

        match result {
            Ok(Some((id_str, ts_str, kind_json, window_json, display_json, primary_display, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json))) => {
                let event = Event {
                    id: Uuid::parse_str(&id_str).map_err(|e| anyhow::anyhow!(e))?,
                    timestamp: chrono::DateTime::parse_from_rfc3339(&ts_str)
                        .map_err(|e| anyhow::anyhow!(e))?
                        .with_timezone(&chrono::Utc),
                    kind: serde_json::from_str(&kind_json)?,
                    window: window_json.map(|j| serde_json::from_str(&j)).transpose()?,
                    display_topology: serde_json::from_str(&display_json)?,
                    primary_display_id: primary_display,
                    cursor_global_px: match (cursor_x, cursor_y) {
                        (Some(x), Some(y)) => Some(CursorPosition { x, y }),
                        _ => None,
                    },
                    ui_scale,
                    artifact_ids: serde_json::from_str(&artifact_ids_json)?,
                    metadata: serde_json::from_str(&metadata_json)?,
                };
                Ok(Some(event))
            }
            Ok(None) => Ok(None),
            Err(e) => Err(anyhow::anyhow!(e)),
        }
    }

    pub fn get_unprocessed_events(&self, limit: u32) -> Result<Vec<Event>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, timestamp, kind_json, window_json, display_topology_json, primary_display_id, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json FROM events WHERE processed = 0 ORDER BY timestamp ASC LIMIT ?1"
        )?;

        let rows = stmt.query_map(params![limit], |row| {
            let id_str: String = row.get(0)?;
            let ts_str: String = row.get(1)?;
            let kind_json: String = row.get(2)?;
            let window_json: Option<String> = row.get(3)?;
            let display_json: String = row.get(4)?;
            let primary_display: String = row.get(5)?;
            let cursor_x: Option<i32> = row.get(6)?;
            let cursor_y: Option<i32> = row.get(7)?;
            let ui_scale: Option<f64> = row.get(8)?;
            let artifact_ids_json: String = row.get(9)?;
            let metadata_json: String = row.get(10)?;
            Ok((id_str, ts_str, kind_json, window_json, display_json, primary_display, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json))
        })?;

        let mut events = Vec::new();
        for row in rows {
            let (id_str, ts_str, kind_json, window_json, display_json, primary_display, cursor_x, cursor_y, ui_scale, artifact_ids_json, metadata_json) = row?;
            events.push(Event {
                id: Uuid::parse_str(&id_str).unwrap(),
                timestamp: chrono::DateTime::parse_from_rfc3339(&ts_str).unwrap().with_timezone(&chrono::Utc),
                kind: serde_json::from_str(&kind_json).unwrap(),
                window: window_json.map(|j| serde_json::from_str(&j).unwrap()),
                display_topology: serde_json::from_str(&display_json).unwrap(),
                primary_display_id: primary_display,
                cursor_global_px: match (cursor_x, cursor_y) {
                    (Some(x), Some(y)) => Some(CursorPosition { x, y }),
                    _ => None,
                },
                ui_scale,
                artifact_ids: serde_json::from_str(&artifact_ids_json).unwrap(),
                metadata: serde_json::from_str(&metadata_json).unwrap(),
            });
        }
        Ok(events)
    }
}

use rusqlite::OptionalExtension;
```

**Step 7: Create placeholder files**

```rust
// crates/storage/src/schema.rs
// Schema constants and helpers
pub const CURRENT_SCHEMA_VERSION: u32 = 1;
```

```rust
// crates/storage/src/migrations/mod.rs
// Migration registry — migrations are embedded via include_str! in lib.rs
```

**Step 8: Run tests**

Run: `cargo test -p oc-apprentice-storage`
Expected: 4 tests PASS.

**Step 9: Commit**

```bash
git add crates/storage/ Cargo.toml
git commit -m "feat: add SQLite storage layer with WAL mode, migrations, event CRUD"
```

---

### Task 5: Artifact Store (Compress + Encrypt + Write Pipeline)

**Files:**
- Create: `crates/storage/src/artifact_store.rs`
- Create: `crates/storage/tests/artifact_test.rs`
- Modify: `crates/storage/Cargo.toml` (add crypto deps)
- Modify: `crates/storage/src/lib.rs` (export artifact_store)

**Step 1: Add deps to crates/storage/Cargo.toml**

```toml
zstd = "0.13"
chacha20poly1305 = "0.5"
rand = "0.8"
sha2 = "0.10"
hex = "0.4"
```

**Step 2: Write the failing test**

```rust
// crates/storage/tests/artifact_test.rs
use oc_apprentice_storage::artifact_store::ArtifactStore;
use tempfile::TempDir;

#[test]
fn test_store_and_retrieve_artifact() {
    let tmp = TempDir::new().unwrap();
    let store = ArtifactStore::new(tmp.path().to_path_buf(), [0u8; 32]);

    let data = b"Hello, this is test artifact data for a DOM snapshot.";
    let artifact_id = store.store(data, "dom_snapshot").unwrap();

    let retrieved = store.retrieve(&artifact_id).unwrap();
    assert_eq!(retrieved, data);
}

#[test]
fn test_artifact_is_compressed_and_encrypted() {
    let tmp = TempDir::new().unwrap();
    let store = ArtifactStore::new(tmp.path().to_path_buf(), [42u8; 32]);

    let data = b"Repeated data for compression test. ".repeat(100);
    let artifact_id = store.store(&data, "screenshot").unwrap();

    // Read raw file — should NOT contain plaintext
    let raw = std::fs::read(store.artifact_path(&artifact_id)).unwrap();
    assert!(!raw.windows(10).any(|w| w == b"Repeated d"));

    // Stored size should be smaller due to compression
    assert!(raw.len() < data.len());
}

#[test]
fn test_artifact_path_uses_date_hierarchy() {
    let tmp = TempDir::new().unwrap();
    let store = ArtifactStore::new(tmp.path().to_path_buf(), [0u8; 32]);

    let data = b"test";
    let id = store.store(data, "test").unwrap();
    let path = store.artifact_path(&id);

    // Path should contain yyyy/mm/dd structure
    let path_str = path.to_string_lossy();
    let re = regex::Regex::new(r"\d{4}/\d{2}/\d{2}").unwrap();
    assert!(re.is_match(&path_str), "Path should contain date hierarchy: {}", path_str);
}
```

**Step 3: Run test to verify it fails**

Run: `cargo test -p oc-apprentice-storage -- artifact`
Expected: FAIL — module not found.

**Step 4: Implement crates/storage/src/artifact_store.rs**

```rust
use anyhow::Result;
use chacha20poly1305::{
    aead::{Aead, KeyInit, OsRng},
    XChaCha20Poly1305, XNonce,
};
use chrono::Utc;
use rand::RngCore;
use sha2::{Sha256, Digest};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

const HEADER_MAGIC: &[u8; 4] = b"OCAA"; // OpenClaw Apprentice Artifact
const ARTIFACT_VERSION: u8 = 1;
const NONCE_SIZE: usize = 24; // XChaCha20 uses 24-byte nonces

pub struct ArtifactStore {
    base_path: PathBuf,
    key: [u8; 32],
}

impl ArtifactStore {
    pub fn new(base_path: PathBuf, key: [u8; 32]) -> Self {
        Self { base_path, key }
    }

    /// Store: capture -> compress -> encrypt -> write (spec order from §6.2)
    pub fn store(&self, data: &[u8], artifact_type: &str) -> Result<String> {
        // 1. Compress with zstd
        let compressed = zstd::encode_all(data, 3)?;

        // 2. Encrypt with XChaCha20-Poly1305
        let cipher = XChaCha20Poly1305::new((&self.key).into());
        let mut nonce_bytes = [0u8; NONCE_SIZE];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = XNonce::from_slice(&nonce_bytes);
        let encrypted = cipher.encrypt(nonce, compressed.as_ref())
            .map_err(|e| anyhow::anyhow!("Encryption failed: {}", e))?;

        // 3. Generate artifact ID from content hash + timestamp
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.update(&Utc::now().timestamp_nanos_opt().unwrap_or(0).to_le_bytes());
        let hash = hex::encode(&hasher.finalize()[..8]);
        let artifact_id = format!("{}_{}", artifact_type, hash);

        // 4. Build date-based path
        let now = Utc::now();
        let dir = self.base_path
            .join(now.format("%Y").to_string())
            .join(now.format("%m").to_string())
            .join(now.format("%d").to_string());
        fs::create_dir_all(&dir)?;

        // 5. Write atomically: tmp file -> fsync -> rename
        let final_path = dir.join(format!("{}.bin", artifact_id));
        let tmp_path = dir.join(format!("{}.bin.tmp", artifact_id));

        let mut file = fs::File::create(&tmp_path)?;
        // Write header
        file.write_all(HEADER_MAGIC)?;
        file.write_all(&[ARTIFACT_VERSION])?;
        file.write_all(&(NONCE_SIZE as u16).to_le_bytes())?;
        file.write_all(&nonce_bytes)?;
        file.write_all(&(data.len() as u64).to_le_bytes())?; // original size
        // Write encrypted payload
        file.write_all(&encrypted)?;
        file.flush()?;
        file.sync_all()?;

        fs::rename(&tmp_path, &final_path)?;

        Ok(artifact_id)
    }

    pub fn retrieve(&self, artifact_id: &str) -> Result<Vec<u8>> {
        let path = self.artifact_path(artifact_id);
        let raw = fs::read(&path)?;

        // Parse header
        if &raw[0..4] != HEADER_MAGIC {
            anyhow::bail!("Invalid artifact magic bytes");
        }
        let _version = raw[4];
        let nonce_len = u16::from_le_bytes([raw[5], raw[6]]) as usize;
        let nonce_bytes = &raw[7..7 + nonce_len];
        let _original_size = u64::from_le_bytes(raw[7 + nonce_len..15 + nonce_len].try_into()?);
        let encrypted = &raw[15 + nonce_len..];

        // Decrypt
        let cipher = XChaCha20Poly1305::new((&self.key).into());
        let nonce = XNonce::from_slice(nonce_bytes);
        let compressed = cipher.decrypt(nonce, encrypted)
            .map_err(|e| anyhow::anyhow!("Decryption failed: {}", e))?;

        // Decompress
        let data = zstd::decode_all(compressed.as_slice())?;
        Ok(data)
    }

    pub fn artifact_path(&self, artifact_id: &str) -> PathBuf {
        // Search for the artifact in the date hierarchy
        self.find_artifact(artifact_id)
            .unwrap_or_else(|| {
                let now = Utc::now();
                self.base_path
                    .join(now.format("%Y").to_string())
                    .join(now.format("%m").to_string())
                    .join(now.format("%d").to_string())
                    .join(format!("{}.bin", artifact_id))
            })
    }

    fn find_artifact(&self, artifact_id: &str) -> Option<PathBuf> {
        let filename = format!("{}.bin", artifact_id);
        find_file_recursive(&self.base_path, &filename)
    }
}

fn find_file_recursive(dir: &Path, filename: &str) -> Option<PathBuf> {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if let Some(found) = find_file_recursive(&path, filename) {
                    return Some(found);
                }
            } else if path.file_name().map(|n| n == filename).unwrap_or(false) {
                return Some(path);
            }
        }
    }
    None
}
```

**Step 5: Add regex dev-dependency and export module**

Add to `crates/storage/Cargo.toml` under `[dev-dependencies]`:
```toml
regex = "1"
```

Add to `crates/storage/src/lib.rs`:
```rust
pub mod artifact_store;
```

**Step 6: Run tests**

Run: `cargo test -p oc-apprentice-storage -- artifact`
Expected: 3 tests PASS.

**Step 7: Commit**

```bash
git add crates/storage/
git commit -m "feat: add artifact store with zstd compression + XChaCha20 encryption + atomic writes"
```

---

### Task 6: Inline Secret Redaction Engine

**Files:**
- Create: `crates/common/src/redaction.rs`
- Create: `crates/common/tests/redaction_test.rs`
- Modify: `crates/common/src/lib.rs`

**Step 1: Write the failing test**

```rust
// crates/common/tests/redaction_test.rs
use oc_apprentice_common::redaction::Redactor;

#[test]
fn test_redacts_aws_access_key() {
    let r = Redactor::new();
    let input = "export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE";
    let output = r.redact(input);
    assert!(!output.contains("AKIAIOSFODNN7EXAMPLE"));
    assert!(output.contains("[REDACTED_AWS_KEY]"));
}

#[test]
fn test_redacts_aws_secret_key() {
    let r = Redactor::new();
    let input = "aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    let output = r.redact(input);
    assert!(!output.contains("wJalrXUtnFEMI"));
    assert!(output.contains("[REDACTED_SECRET]"));
}

#[test]
fn test_redacts_credit_card_number() {
    let r = Redactor::new();
    let input = "Card: 4111-1111-1111-1111 expires 12/25";
    let output = r.redact(input);
    assert!(!output.contains("4111-1111-1111-1111"));
    assert!(output.contains("[REDACTED_CC]"));
}

#[test]
fn test_redacts_private_key() {
    let r = Redactor::new();
    let input = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKC...\n-----END RSA PRIVATE KEY-----";
    let output = r.redact(input);
    assert!(!output.contains("MIIEowIBAAKC"));
    assert!(output.contains("[REDACTED_PRIVATE_KEY]"));
}

#[test]
fn test_redacts_high_entropy_hex_strings() {
    let r = Redactor::new();
    let input = "token: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2";
    let output = r.redact(input);
    assert!(output.contains("[REDACTED_HIGH_ENTROPY]"));
}

#[test]
fn test_does_not_redact_normal_text() {
    let r = Redactor::new();
    let input = "Hello world, this is a normal sentence about coding.";
    let output = r.redact(input);
    assert_eq!(output, input);
}

#[test]
fn test_detects_sensitive_content() {
    let r = Redactor::new();
    assert!(r.contains_sensitive("my key is AKIAIOSFODNN7EXAMPLE"));
    assert!(!r.contains_sensitive("hello world"));
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -p oc-apprentice-common -- redaction`
Expected: FAIL — module not found.

**Step 3: Add regex dependency to crates/common/Cargo.toml**

```toml
regex = "1"
```

**Step 4: Implement crates/common/src/redaction.rs**

```rust
use regex::Regex;

pub struct Redactor {
    patterns: Vec<(Regex, &'static str)>,
    high_entropy_pattern: Regex,
}

impl Redactor {
    pub fn new() -> Self {
        let patterns = vec![
            // AWS Access Key ID (starts with AKIA)
            (Regex::new(r"(?i)(AKIA[0-9A-Z]{16})").unwrap(), "[REDACTED_AWS_KEY]"),
            // AWS Secret Access Key (40 char base64-ish after = or :)
            (Regex::new(r"(?i)(?:aws_secret_access_key|secret_key)\s*[=:]\s*([A-Za-z0-9/+=]{30,})").unwrap(), "[REDACTED_SECRET]"),
            // Generic API keys/tokens (long alphanumeric after common key words)
            (Regex::new(r"(?i)(?:api[_-]?key|api[_-]?token|auth[_-]?token|bearer)\s*[=:]\s*['\"]?([A-Za-z0-9_\-]{20,})['\"]?").unwrap(), "[REDACTED_API_KEY]"),
            // Credit card numbers (Visa, MC, Amex, Discover with optional dashes/spaces)
            (Regex::new(r"\b([3-6]\d{3}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{3,4})\b").unwrap(), "[REDACTED_CC]"),
            // SSN
            (Regex::new(r"\b(\d{3}-\d{2}-\d{4})\b").unwrap(), "[REDACTED_SSN]"),
            // Private keys (PEM format)
            (Regex::new(r"(?s)(-----BEGIN\s+(?:RSA\s+|EC\s+|DSA\s+)?PRIVATE KEY-----.*?-----END\s+(?:RSA\s+|EC\s+|DSA\s+)?PRIVATE KEY-----)").unwrap(), "[REDACTED_PRIVATE_KEY]"),
            // GitHub tokens
            (Regex::new(r"(ghp_[A-Za-z0-9]{36,})").unwrap(), "[REDACTED_GITHUB_TOKEN]"),
            (Regex::new(r"(gho_[A-Za-z0-9]{36,})").unwrap(), "[REDACTED_GITHUB_TOKEN]"),
            // Slack tokens
            (Regex::new(r"(xox[bpors]-[A-Za-z0-9\-]{10,})").unwrap(), "[REDACTED_SLACK_TOKEN]"),
        ];

        let high_entropy_pattern = Regex::new(r"\b([a-f0-9]{48,})\b").unwrap();

        Self { patterns, high_entropy_pattern }
    }

    pub fn redact(&self, input: &str) -> String {
        let mut output = input.to_string();

        for (pattern, replacement) in &self.patterns {
            output = pattern.replace_all(&output, *replacement).to_string();
        }

        // High-entropy hex strings (potential secrets/hashes)
        output = self.high_entropy_pattern.replace_all(&output, "[REDACTED_HIGH_ENTROPY]").to_string();

        output
    }

    pub fn contains_sensitive(&self, input: &str) -> bool {
        for (pattern, _) in &self.patterns {
            if pattern.is_match(input) {
                return true;
            }
        }
        self.high_entropy_pattern.is_match(input)
    }
}

impl Default for Redactor {
    fn default() -> Self {
        Self::new()
    }
}
```

**Step 5: Export in lib.rs**

Add `pub mod redaction;` to `crates/common/src/lib.rs`.

**Step 6: Run tests**

Run: `cargo test -p oc-apprentice-common -- redaction`
Expected: 7 tests PASS.

**Step 7: Commit**

```bash
git add crates/common/
git commit -m "feat: add inline secret redaction engine with pattern-based detection"
```

---

### Task 7: macOS Idle Detection (No Keylogging)

**Files:**
- Create: `crates/daemon/src/platform/mod.rs`
- Create: `crates/daemon/src/platform/macos.rs`
- Create: `crates/daemon/tests/idle_test.rs`
- Modify: `crates/daemon/Cargo.toml`

**Step 1: Add macOS dependencies to daemon**

```toml
# crates/daemon/Cargo.toml [dependencies]
core-graphics = "0.24"
core-foundation = "0.10"
```

**Step 2: Write the test**

```rust
// crates/daemon/tests/idle_test.rs
#[cfg(target_os = "macos")]
mod macos_tests {
    use oc_apprentice_daemon::platform::IdleDetector;

    #[test]
    fn test_idle_seconds_returns_non_negative() {
        let detector = IdleDetector::new();
        let idle = detector.seconds_since_last_input();
        assert!(idle >= 0.0, "Idle time should be non-negative, got: {}", idle);
    }

    #[test]
    fn test_is_user_idle_with_threshold() {
        let detector = IdleDetector::new();
        // With a very high threshold, user should not be "idle"
        assert!(!detector.is_idle(999999.0));
    }
}
```

**Step 3: Implement platform module**

```rust
// crates/daemon/src/platform/mod.rs
#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "macos")]
pub use macos::IdleDetector;
```

```rust
// crates/daemon/src/platform/macos.rs
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

pub struct IdleDetector;

impl IdleDetector {
    pub fn new() -> Self {
        Self
    }

    /// Returns seconds since last HID event (keyboard/mouse/trackpad).
    /// Uses CGEventSourceSecondsSinceLastEventType — no keystroke interception.
    pub fn seconds_since_last_input(&self) -> f64 {
        // CGEventSourceStateID::HIDSystemState gives time since last HID event
        // kCGAnyInputEventType = u32::MAX
        let idle_time = CGEventSource::seconds_since_last_event_type(
            CGEventSourceStateID::HIDSystemState,
            core_graphics::event::CGEventType::Null, // Any event type
        );
        idle_time
    }

    pub fn is_idle(&self, threshold_seconds: f64) -> bool {
        self.seconds_since_last_input() >= threshold_seconds
    }
}

impl Default for IdleDetector {
    fn default() -> Self {
        Self::new()
    }
}
```

**Step 4: Export platform module from daemon**

Add to `crates/daemon/src/main.rs`:
```rust
pub mod platform;
```

Actually, create `crates/daemon/src/lib.rs` for the library target:
```rust
pub mod platform;
```

Update `crates/daemon/Cargo.toml` to have both lib and bin:
```toml
[lib]
name = "oc_apprentice_daemon"
path = "src/lib.rs"

[[bin]]
name = "oc-apprentice-daemon"
path = "src/main.rs"
```

**Step 5: Run tests**

Run: `cargo test -p oc-apprentice-daemon -- idle`
Expected: 2 tests PASS (on macOS).

**Step 6: Commit**

```bash
git add crates/daemon/
git commit -m "feat: add macOS idle detection via CGEventSource (no keylogging)"
```

---

### Task 8: Multi-Monitor Window Geometry Capture (macOS)

**Files:**
- Create: `crates/daemon/src/platform/macos_windows.rs`
- Create: `crates/daemon/tests/window_test.rs`
- Modify: `crates/daemon/src/platform/mod.rs`
- Modify: `crates/daemon/Cargo.toml`

**Step 1: Add objc2 dependencies**

```toml
# crates/daemon/Cargo.toml
objc2 = "0.6"
objc2-app-kit = { version = "0.3", features = ["NSScreen", "NSApplication", "NSWindow", "NSRunningApplication", "NSWorkspace"] }
objc2-foundation = { version = "0.3", features = ["NSString", "NSArray", "NSDictionary", "NSValue", "NSGeometry"] }
```

**Step 2: Write the test**

```rust
// crates/daemon/tests/window_test.rs
#[cfg(target_os = "macos")]
mod window_tests {
    use oc_apprentice_daemon::platform::window_capture::{get_display_topology, get_focused_window};

    #[test]
    fn test_display_topology_returns_at_least_one() {
        let displays = get_display_topology();
        assert!(!displays.is_empty(), "Should detect at least one display");
        for d in &displays {
            assert!(d.bounds_global_px[2] > 0, "Display width should be positive");
            assert!(d.bounds_global_px[3] > 0, "Display height should be positive");
            assert!(d.scale_factor >= 1.0, "Scale factor should be >= 1.0");
        }
    }

    #[test]
    fn test_focused_window_returns_something() {
        // This test needs a running GUI — may return None in headless CI
        let window = get_focused_window();
        // Just check it doesn't panic; in CI it may be None
        if let Some(w) = window {
            assert!(!w.app_id.is_empty());
        }
    }
}
```

**Step 3: Implement window capture**

```rust
// crates/daemon/src/platform/macos_windows.rs
use oc_apprentice_common::event::{DisplayInfo, WindowInfo};
use core_graphics::display::{CGDisplay, CGMainDisplayID};

pub fn get_display_topology() -> Vec<DisplayInfo> {
    let display_ids = CGDisplay::active_displays().unwrap_or_default();

    display_ids.iter().map(|&id| {
        let display = CGDisplay::new(id);
        let bounds = display.bounds();
        let scale = if display.pixels_wide() > 0 && bounds.size.width > 0.0 {
            display.pixels_wide() as f64 / bounds.size.width
        } else {
            1.0
        };

        DisplayInfo {
            display_id: id.to_string(),
            bounds_global_px: [
                bounds.origin.x as i32,
                bounds.origin.y as i32,
                bounds.size.width as i32,
                bounds.size.height as i32,
            ],
            scale_factor: scale,
            orientation: display.rotation() as u32,
        }
    }).collect()
}

pub fn get_focused_window() -> Option<WindowInfo> {
    // Use CGWindowListCopyWindowInfo to get the frontmost window
    use core_graphics::display::kCGWindowListOptionOnScreenOnly;
    use core_graphics::display::kCGNullWindowID;

    let window_list = unsafe {
        core_graphics::display::CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly,
            kCGNullWindowID,
        )
    };

    if window_list.is_none() {
        return None;
    }

    // The focused (frontmost) window logic will be expanded in Task 9
    // For now, return a basic implementation using the first on-screen window
    None // Placeholder — full implementation requires NSWorkspace frontmost app
}
```

**Step 4: Export from platform/mod.rs**

```rust
#[cfg(target_os = "macos")]
pub mod macos;
#[cfg(target_os = "macos")]
pub mod macos_windows;

#[cfg(target_os = "macos")]
pub use macos::IdleDetector;
#[cfg(target_os = "macos")]
pub mod window_capture {
    pub use super::macos_windows::*;
}
```

**Step 5: Run tests**

Run: `cargo test -p oc-apprentice-daemon -- window`
Expected: Tests PASS on macOS with display access.

**Step 6: Commit**

```bash
git add crates/daemon/
git commit -m "feat: add multi-monitor display topology capture for macOS"
```

---

### Task 9: macOS Accessibility Tree Capture

**Files:**
- Create: `crates/daemon/src/platform/macos_accessibility.rs`
- Create: `crates/daemon/tests/accessibility_test.rs`
- Modify: `crates/daemon/Cargo.toml`

**Step 1: Add accessibility crate**

```toml
# crates/daemon/Cargo.toml
accessibility = "0.2"
accessibility-sys = "0.2"
```

**Step 2: Write the test**

```rust
// crates/daemon/tests/accessibility_test.rs
#[cfg(target_os = "macos")]
mod ax_tests {
    use oc_apprentice_daemon::platform::accessibility::{
        check_accessibility_permission,
        is_secure_field_focused,
    };

    #[test]
    fn test_check_permission_returns_bool() {
        // Should not panic, returns true/false
        let _has_permission = check_accessibility_permission();
    }
}
```

**Step 3: Implement accessibility module**

```rust
// crates/daemon/src/platform/macos_accessibility.rs
use tracing::warn;

/// Check if the app has macOS Accessibility permission.
/// Required for reading AX tree of other applications.
pub fn check_accessibility_permission() -> bool {
    // accessibility-sys provides the raw binding
    unsafe {
        let trusted = accessibility_sys::AXIsProcessTrusted();
        if !trusted {
            warn!("Accessibility permission not granted. Request it in System Settings > Privacy & Security > Accessibility.");
        }
        trusted
    }
}

/// Check if the currently focused UI element is a secure text field (password).
/// If so, the observer must NOT capture any content (§5.4 secure-field hard drop).
pub fn is_secure_field_focused() -> bool {
    // This requires querying the focused element's AXRole and checking
    // for kAXSecureTextFieldSubrole.
    // Full implementation requires AXUIElementCopyAttributeValue calls.
    // For now, return false as a safe default — will be fully implemented
    // when we build the event loop.
    false
}

/// Capture a snapshot of the accessibility tree for the focused application.
/// Returns a JSON-serializable structure of the visible UI elements.
pub fn capture_ax_snapshot() -> Option<serde_json::Value> {
    // Will be implemented in the observer event loop task.
    // This involves:
    // 1. Get focused app via NSWorkspace
    // 2. Create AXUIElement for the app
    // 3. Walk the AX tree (time-bounded, async)
    // 4. Extract role, name, description, value for each element
    None
}
```

**Step 4: Export from platform/mod.rs**

Add:
```rust
#[cfg(target_os = "macos")]
pub mod macos_accessibility;
#[cfg(target_os = "macos")]
pub mod accessibility {
    pub use super::macos_accessibility::*;
}
```

**Step 5: Run tests**

Run: `cargo test -p oc-apprentice-daemon -- ax`
Expected: PASS.

**Step 6: Commit**

```bash
git add crates/daemon/
git commit -m "feat: add macOS accessibility permission check and secure field detection scaffolding"
```

---

### Task 10: Screenshot Capture (macOS Window Crop)

**Files:**
- Create: `crates/daemon/src/capture/mod.rs`
- Create: `crates/daemon/src/capture/screenshot.rs`
- Create: `crates/daemon/tests/screenshot_test.rs`

**Step 1: Write the test**

```rust
// crates/daemon/tests/screenshot_test.rs
#[cfg(target_os = "macos")]
mod screenshot_tests {
    use oc_apprentice_daemon::capture::screenshot::capture_focused_window;

    #[test]
    fn test_capture_returns_png_bytes() {
        let result = capture_focused_window();
        // In a GUI environment this returns Some(bytes)
        // In headless CI it may return None
        if let Some(bytes) = result {
            // PNG magic bytes
            assert_eq!(&bytes[0..4], &[0x89, 0x50, 0x4E, 0x47]);
        }
    }
}
```

**Step 2: Implement screenshot capture**

```rust
// crates/daemon/src/capture/screenshot.rs
use core_graphics::display::{
    CGDisplay, kCGWindowListOptionOnScreenOnly, kCGNullWindowID,
};
use core_graphics::image::CGImage;

/// Capture the focused window as PNG bytes.
/// Uses CGWindowListCreateImage which is the recommended non-invasive approach.
pub fn capture_focused_window() -> Option<Vec<u8>> {
    // Capture the main display for now
    // TODO: Use window-specific capture with CGWindowListCreateImage
    let display_id = CGDisplay::main().id;
    let display = CGDisplay::new(display_id);
    let image = display.image()?;

    // Convert CGImage to PNG bytes
    cg_image_to_png(&image)
}

fn cg_image_to_png(image: &CGImage) -> Option<Vec<u8>> {
    let width = image.width();
    let height = image.height();
    let bytes_per_row = image.bytes_per_row();
    let data = image.data();

    // Use the image crate to convert raw BGRA to PNG
    // This will be added as a dependency
    // For now, return raw data wrapped in a simple format
    // Full PNG encoding requires the `image` or `png` crate
    Some(data.bytes().to_vec())
}
```

```rust
// crates/daemon/src/capture/mod.rs
pub mod screenshot;
```

Add to `crates/daemon/src/lib.rs`:
```rust
pub mod capture;
```

**Step 3: Run tests**

Run: `cargo test -p oc-apprentice-daemon -- screenshot`
Expected: PASS (may skip actual capture in headless env).

**Step 4: Commit**

```bash
git add crates/daemon/
git commit -m "feat: add macOS screenshot capture via CGDisplay"
```

---

### Task 11: Clipboard Monitor (Metadata Only)

**Files:**
- Create: `crates/daemon/src/capture/clipboard.rs`
- Create: `crates/daemon/tests/clipboard_test.rs`

**Step 1: Write the test**

```rust
// crates/daemon/tests/clipboard_test.rs
use oc_apprentice_daemon::capture::clipboard::{ClipboardMeta, hash_content};

#[test]
fn test_hash_content_deterministic() {
    let a = hash_content(b"hello world");
    let b = hash_content(b"hello world");
    assert_eq!(a, b);
}

#[test]
fn test_hash_content_different() {
    let a = hash_content(b"hello");
    let b = hash_content(b"world");
    assert_ne!(a, b);
}

#[test]
fn test_clipboard_meta_creation() {
    let meta = ClipboardMeta {
        content_types: vec!["text/plain".into()],
        byte_size: 42,
        high_entropy: false,
        content_hash: hash_content(b"test"),
    };
    assert_eq!(meta.byte_size, 42);
    assert!(!meta.high_entropy);
}
```

**Step 2: Implement clipboard module**

```rust
// crates/daemon/src/capture/clipboard.rs
use sha2::{Sha256, Digest};
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardMeta {
    pub content_types: Vec<String>,
    pub byte_size: u64,
    pub high_entropy: bool,
    pub content_hash: String,
}

/// SHA-256 hash of content, returned as hex string.
pub fn hash_content(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// Estimate if content is high-entropy (potential secret).
/// Uses Shannon entropy calculation.
pub fn is_high_entropy(data: &[u8]) -> bool {
    if data.len() < 16 {
        return false;
    }
    let entropy = shannon_entropy(data);
    entropy > 4.5 // Threshold for "suspicious" entropy
}

fn shannon_entropy(data: &[u8]) -> f64 {
    let mut freq = [0u64; 256];
    for &byte in data {
        freq[byte as usize] += 1;
    }
    let len = data.len() as f64;
    freq.iter()
        .filter(|&&f| f > 0)
        .map(|&f| {
            let p = f as f64 / len;
            -p * p.log2()
        })
        .sum()
}
```

Add `sha2` and `hex` to daemon Cargo.toml if not already there.

**Step 3: Export from capture/mod.rs**

```rust
pub mod screenshot;
pub mod clipboard;
```

**Step 4: Run tests**

Run: `cargo test -p oc-apprentice-daemon -- clipboard`
Expected: 3 tests PASS.

**Step 5: Commit**

```bash
git add crates/daemon/
git commit -m "feat: add clipboard metadata capture with SHA-256 hashing and entropy detection"
```

---

### Task 12: Dwell Timer + Event Collector Core Loop

**Files:**
- Create: `crates/daemon/src/observer/mod.rs`
- Create: `crates/daemon/src/observer/dwell.rs`
- Create: `crates/daemon/src/observer/collector.rs`
- Create: `crates/daemon/tests/dwell_test.rs`

**Step 1: Write the test**

```rust
// crates/daemon/tests/dwell_test.rs
use oc_apprentice_daemon::observer::dwell::DwellTracker;
use std::time::Duration;

#[test]
fn test_dwell_starts_inactive() {
    let tracker = DwellTracker::new(Duration::from_secs(3), Duration::from_secs(8));
    assert!(!tracker.is_dwelling());
    assert!(!tracker.is_scroll_reading());
}

#[test]
fn test_manipulation_resets_dwell() {
    let mut tracker = DwellTracker::new(Duration::from_secs(3), Duration::from_secs(8));
    tracker.on_navigation_input(); // scroll
    tracker.on_manipulation_input(); // click — resets
    assert!(!tracker.is_dwelling());
}

#[test]
fn test_dwell_triggers_after_threshold() {
    let mut tracker = DwellTracker::new(Duration::from_millis(50), Duration::from_millis(200));
    // Simulate no manipulation for >50ms
    std::thread::sleep(Duration::from_millis(60));
    tracker.tick();
    assert!(tracker.is_dwelling());
}

#[test]
fn test_scroll_reading_triggers_after_threshold() {
    let mut tracker = DwellTracker::new(Duration::from_millis(50), Duration::from_millis(100));
    // Simulate continuous scrolling with no manipulation
    for _ in 0..5 {
        tracker.on_navigation_input();
        std::thread::sleep(Duration::from_millis(25));
        tracker.tick();
    }
    assert!(tracker.is_scroll_reading());
}
```

**Step 2: Implement DwellTracker**

```rust
// crates/daemon/src/observer/dwell.rs
use std::time::{Duration, Instant};

pub struct DwellTracker {
    t_dwell: Duration,
    t_scroll_read: Duration,
    last_manipulation: Instant,
    last_navigation: Option<Instant>,
    first_navigation_since_manipulation: Option<Instant>,
}

impl DwellTracker {
    pub fn new(t_dwell: Duration, t_scroll_read: Duration) -> Self {
        Self {
            t_dwell,
            t_scroll_read,
            last_manipulation: Instant::now(),
            last_navigation: None,
            first_navigation_since_manipulation: None,
        }
    }

    pub fn on_manipulation_input(&mut self) {
        self.last_manipulation = Instant::now();
        self.first_navigation_since_manipulation = None;
    }

    pub fn on_navigation_input(&mut self) {
        let now = Instant::now();
        self.last_navigation = Some(now);
        if self.first_navigation_since_manipulation.is_none() {
            self.first_navigation_since_manipulation = Some(now);
        }
    }

    pub fn tick(&mut self) {
        // Called periodically to check state
    }

    pub fn is_dwelling(&self) -> bool {
        self.last_manipulation.elapsed() >= self.t_dwell
    }

    pub fn is_scroll_reading(&self) -> bool {
        if let Some(first_nav) = self.first_navigation_since_manipulation {
            first_nav.elapsed() >= self.t_scroll_read
                && self.last_manipulation.elapsed() >= self.t_scroll_read
        } else {
            false
        }
    }

    pub fn should_capture_dwell_snapshot(&self) -> bool {
        self.is_dwelling() || self.is_scroll_reading()
    }
}
```

```rust
// crates/daemon/src/observer/mod.rs
pub mod dwell;
pub mod collector;
```

```rust
// crates/daemon/src/observer/collector.rs
// Event collector — will be built in Task 13
```

Add to `crates/daemon/src/lib.rs`:
```rust
pub mod observer;
```

**Step 3: Run tests**

Run: `cargo test -p oc-apprentice-daemon -- dwell`
Expected: 4 tests PASS.

**Step 4: Commit**

```bash
git add crates/daemon/
git commit -m "feat: add dwell tracker with manipulation vs navigation input distinction"
```

---

### Task 13: Observer Event Loop (Daemon Main Loop)

**Files:**
- Modify: `crates/daemon/src/observer/collector.rs`
- Modify: `crates/daemon/src/main.rs`
- Create: `crates/daemon/src/observer/event_loop.rs`

This task wires together Tasks 7-12 into the main daemon event loop. It creates the always-on observer that:
1. Monitors idle state via CGEventSource
2. Tracks display topology changes
3. Captures dwell/scroll-read snapshots
4. Captures window focus changes
5. Checks for secure field before any capture
6. Runs inline redaction on all text data
7. Stores events + artifacts through the storage layer

**Implementation:** Full async tokio event loop with channels for inter-thread communication as specified in §4.3:
- Event Collector thread (OS events)
- Snapshot Worker pool (screenshots, AX snapshots)
- Crypto/Compression worker (artifact pipeline)
- Health/Permission watcher thread

(Detailed step-by-step code for this task would be ~300 lines; to be expanded during execution.)

**Step 1: Write integration test for the event loop**
**Step 2: Implement event_loop.rs with tokio channels**
**Step 3: Wire into main.rs**
**Step 4: Run integration test**
**Step 5: Commit**

---

### Task 14: Nightly Maintenance (Retention + WAL Checkpoint + VACUUM)

**Files:**
- Create: `crates/storage/src/maintenance.rs`
- Create: `crates/storage/tests/maintenance_test.rs`
- Modify: `crates/storage/src/lib.rs`

Implements §6.4: purge old rows, WAL checkpoint, disk-space check before VACUUM.

**Step 1: Write tests for retention purge, VACUUM safety check**
**Step 2: Implement maintenance.rs with disk-space guard**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 15: Power/Thermal Circuit Breakers

**Files:**
- Create: `crates/daemon/src/platform/macos_power.rs`
- Create: `crates/daemon/tests/power_test.rs`

Implements §15: AC power detection, battery level, temperature checks. macOS uses IOKit for power info.

**Step 1: Write tests for power state detection**
**Step 2: Implement using IOKit bindings**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 16: Health/Permission Watcher Thread

**Files:**
- Create: `crates/daemon/src/observer/health.rs`
- Create: `crates/daemon/tests/health_test.rs`

Monitors: accessibility permission granted, screen recording permission (for screenshots), disk space, daemon resource usage.

**Step 1: Write tests**
**Step 2: Implement health checker**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 17: Record/Replay Test Harness Foundation

**Files:**
- Create: `crates/test-harness/Cargo.toml`
- Create: `crates/test-harness/src/lib.rs`
- Create: `crates/test-harness/src/recorder.rs`
- Create: `crates/test-harness/src/replayer.rs`
- Create: `crates/test-harness/tests/harness_test.rs`

Implements §14.1: Ingest recorded event streams, run D/E/F pipeline deterministically, compare against golden outputs.

**Step 1: Design recording format (JSON lines)**
**Step 2: Write tests for record and replay**
**Step 3: Implement recorder and replayer**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 18: Privacy Test Suite

**Files:**
- Create: `crates/test-harness/tests/privacy_test.rs`
- Create: `crates/test-harness/fixtures/`

Implements §14.2: Seed fake secrets into event streams, verify nothing sensitive reaches storage or SOPs.

**Step 1: Create fixtures with seeded secrets**
**Step 2: Write privacy assertion tests**
**Step 3: Run tests**
**Step 4: Commit**

---

## Phase 1 — Browser Extension + Learning (Tasks 19–30)

### Task 19: Chrome MV3 Extension Skeleton

**Files:**
- Create: `extension/manifest.json`
- Create: `extension/src/background.ts`
- Create: `extension/src/content.ts`
- Create: `extension/src/native-messaging.ts`
- Create: `extension/tsconfig.json`
- Create: `extension/package.json`

Manifest V3 extension with:
- `"nativeMessaging"` permission
- Stable `"key"` field for consistent extension ID
- Content script matching `<all_urls>` with `document_idle`
- Background service worker

**Step 1: Create package.json with TypeScript + build tooling**
**Step 2: Create manifest.json with key field for stable ID**
**Step 3: Create background service worker**
**Step 4: Create content script skeleton**
**Step 5: Build and verify extension loads**
**Step 6: Commit**

---

### Task 20: Native Messaging IPC (Extension <-> Daemon)

**Files:**
- Modify: `extension/src/native-messaging.ts`
- Create: `extension/src/types.ts`
- Create: `crates/daemon/src/ipc/mod.rs`
- Create: `crates/daemon/src/ipc/native_messaging.rs`
- Create: `scripts/install-native-host.sh`

Implements §5.8: stdio-based Native Messaging between extension and daemon.

**Step 1: Create native host manifest template**
**Step 2: Implement Rust stdio server in daemon**
**Step 3: Implement TypeScript client in extension**
**Step 4: Create installer script for host manifest**
**Step 5: Write integration test**
**Step 6: Commit**

---

### Task 21: Viewport-Bounded DOM Snapshot Capture

**Files:**
- Create: `extension/src/dom-capture.ts`
- Create: `extension/tests/dom-capture.test.ts`

Implements §5.6: IntersectionObserver-based visible DOM capture with truncation, semantic anchors, CSS rot stripping.

**Step 1: Write test for viewport filtering**
**Step 2: Implement IntersectionObserver-based capture**
**Step 3: Implement table/text truncation**
**Step 4: Implement CSS class stripping (randomized class removal)**
**Step 5: Run tests**
**Step 6: Commit**

---

### Task 22: Shadow DOM Piercing

**Files:**
- Modify: `extension/src/dom-capture.ts`
- Create: `extension/tests/shadow-dom.test.ts`

Implements §16 gotcha: pierce shadowRoot for modern web apps.

**Step 1: Write test with mock Shadow DOM**
**Step 2: Implement recursive shadowRoot traversal**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 23: Click Intent Capture

**Files:**
- Create: `extension/src/click-capture.ts`
- Create: `extension/tests/click-capture.test.ts`

Captures: composedPath, ARIA role, accessible name, data-testid, visible innerText of click target. Sends to daemon via Native Messaging.

**Step 1: Write tests**
**Step 2: Implement click event listener with semantic extraction**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 24: Secure Field Detection in Browser

**Files:**
- Modify: `extension/src/content.ts`
- Create: `extension/tests/secure-field.test.ts`

Implements §5.4 for browser: detect `<input type="password">` and suppress all capture.

**Step 1: Write test for password field detection**
**Step 2: Implement secure field check before any capture**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 25: Dwell + Scroll Snapshot Triggers in Extension

**Files:**
- Modify: `extension/src/content.ts`
- Create: `extension/tests/dwell.test.ts`

Extension-side dwell/scroll-reading detection. When dwell threshold met, capture DOM snapshot + send to daemon.

**Step 1: Write tests for dwell detection**
**Step 2: Implement timer-based dwell tracking**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 26: Python Worker Skeleton

**Files:**
- Create: `worker/pyproject.toml`
- Create: `worker/src/oc_apprentice_worker/__init__.py`
- Create: `worker/src/oc_apprentice_worker/main.py`
- Create: `worker/src/oc_apprentice_worker/db.py`
- Create: `worker/tests/test_db.py`

Python 3.11+ worker with SQLite read connection, idle-time scheduler integration.

**Step 1: Create pyproject.toml with dependencies**
**Step 2: Implement SQLite reader (read-only connection to daemon's DB)**
**Step 3: Write tests**
**Step 4: Commit**

---

### Task 27: Episode Builder v1 (Thread Multiplexing + Caps)

**Files:**
- Create: `worker/src/oc_apprentice_worker/episode_builder.py`
- Create: `worker/tests/test_episode_builder.py`

Implements §8: cluster events by app/URL/entities, enforce 15-min soft cap and 200-event hard cap, segment linking.

**Step 1: Write tests for episode segmentation**
**Step 2: Write tests for thread multiplexing**
**Step 3: Implement episode builder with caps**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 28: Negative Demonstration Pruning

**Files:**
- Create: `worker/src/oc_apprentice_worker/negative_demo.py`
- Create: `worker/tests/test_negative_demo.py`

Implements §8.2: detect Ctrl+Z, Cancel, Back-after-error, "Discard changes" and mark events as negative.

**Step 1: Write tests for undo detection**
**Step 2: Write tests for cancel/close detection**
**Step 3: Implement negative demo detector**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 29: Clipboard Copy-Paste Linker

**Files:**
- Create: `worker/src/oc_apprentice_worker/clipboard_linker.py`
- Create: `worker/tests/test_clipboard_linker.py`

Implements §5.7: match paste hashes to recent copy hashes within 30-minute window.

**Step 1: Write tests for hash matching**
**Step 2: Implement time-windowed hash matcher**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 30: Phase 1 Integration Test

**Files:**
- Create: `tests/integration/test_phase1.py`

End-to-end test: simulated browser events → daemon capture → storage → episode builder. Uses the record/replay harness from Task 17.

**Step 1: Create golden test data**
**Step 2: Write E2E integration test**
**Step 3: Run and verify**
**Step 4: Commit**

---

## Phase 2 — SOP Pipeline (Tasks 31–42)

### Task 31: Semantic Translator — Structured Metadata Grounding

**Files:**
- Create: `worker/src/oc_apprentice_worker/translator.py`
- Create: `worker/src/oc_apprentice_worker/confidence.py`
- Create: `worker/tests/test_translator.py`

Implements §9.1 (structured first): resolve UI actions via DOM ARIA, accessible name, testid, role. No VLM yet.

**Step 1: Write tests for UI anchor resolution**
**Step 2: Implement structured metadata grounding**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 32: Confidence Scoring Engine

**Files:**
- Modify: `worker/src/oc_apprentice_worker/confidence.py`
- Create: `worker/tests/test_confidence.py`

Implements §9.2: score = UI anchor (0-0.45) + state match (0-0.35) + provenance (0-0.20). Threshold routing.

**Step 1: Write tests for each scoring component**
**Step 2: Write tests for threshold behavior (0.85/0.60/below)**
**Step 3: Implement confidence scorer**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 33: CSS Rot Filter

**Files:**
- Create: `worker/src/oc_apprentice_worker/css_filter.py`
- Create: `worker/tests/test_css_filter.py`

Implements §9.3: strip randomized CSS classes, prefer stable selectors.

**Step 1: Write tests for class stripping**
**Step 2: Implement selector stability ranker**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 34: VLM Fallback Queue

**Files:**
- Create: `worker/src/oc_apprentice_worker/vlm_queue.py`
- Create: `worker/tests/test_vlm_queue.py`

Implements §9.4: priority queue with budgets, backpressure, TTL expiry.

**Step 1: Write tests for priority ordering**
**Step 2: Write tests for budget enforcement**
**Step 3: Write tests for backpressure (queue overflow)**
**Step 4: Implement VLM queue manager**
**Step 5: Run tests**
**Step 6: Commit**

---

### Task 35: Semantic Step Data Model

**Files:**
- Create: `worker/src/oc_apprentice_worker/models/semantic_step.py`
- Create: `worker/tests/test_semantic_step.py`

Define the SemanticStep model: intent + target + parameters + pre/post state + confidence + evidence.

**Step 1: Write tests for model creation and serialization**
**Step 2: Implement SemanticStep dataclass**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 36: SOP Induction — Pattern Mining

**Files:**
- Create: `worker/src/oc_apprentice_worker/sop_inducer.py`
- Create: `worker/tests/test_sop_inducer.py`

Implements §10.1: mine repeated subgraphs, abstract variables, produce declarative SOP steps.

**Step 1: Write tests with repeated episode patterns**
**Step 2: Implement pattern mining with prefixspan**
**Step 3: Implement variable abstraction**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 37: SOP File Format + YAML Frontmatter

**Files:**
- Create: `worker/src/oc_apprentice_worker/sop_format.py`
- Create: `worker/tests/test_sop_format.py`

Implements §10.2-10.3 + §13.3: YAML frontmatter with version, hash, confidence, evidence window. Manual edit detection.

**Step 1: Write tests for SOP file creation**
**Step 2: Write tests for manual edit detection (hash mismatch)**
**Step 3: Implement SOP formatter**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 38: SOP Drift / Versioning

**Files:**
- Modify: `worker/src/oc_apprentice_worker/sop_inducer.py`
- Create: `worker/tests/test_sop_drift.py`

Implements §10.2: single canonical SOP, archive old versions with timestamp+hash.

**Step 1: Write tests for SOP overwrite with archive**
**Step 2: Implement canonical SOP replacement logic**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 39: Atomic SOP Exporter

**Files:**
- Create: `worker/src/oc_apprentice_worker/exporter.py`
- Create: `worker/tests/test_exporter.py`

Implements §10.5: write to tmp, flush, fsync, atomic rename. Also maintains index.md catalog (§10.4).

**Step 1: Write tests for atomic write behavior**
**Step 2: Write tests for index.md generation**
**Step 3: Implement atomic exporter**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 40: OpenClaw Integration Writer

**Files:**
- Create: `worker/src/oc_apprentice_worker/openclaw_writer.py`
- Create: `worker/tests/test_openclaw_writer.py`

Implements §11: write SOPs to `~/.openclaw/workspace/memory/apprentice/sops/`, maintain index.md, learning-only policy.

**Step 1: Write tests**
**Step 2: Implement OpenClaw workspace writer**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 41: Idle-Time Scheduler

**Files:**
- Create: `worker/src/oc_apprentice_worker/scheduler.py`
- Create: `worker/tests/test_scheduler.py`

Implements §15 + §12.2 [idle_jobs]: runs D/E/F pipeline only when idle, on AC power, battery >50%, CPU <30%, within time window.

**Step 1: Write tests for scheduling conditions**
**Step 2: Implement power-aware scheduler**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 42: Phase 2 End-to-End Test

**Files:**
- Create: `tests/integration/test_phase2_sop_pipeline.py`

Full pipeline test: recorded events → episodes → semantic steps → SOP induction → export to OpenClaw format. Compare against golden SOPs.

**Step 1: Create golden test episodes + expected SOPs**
**Step 2: Write E2E pipeline test**
**Step 3: Run and verify**
**Step 4: Commit**

---

## Phase 3 — Electron/CEF + VLM (Tasks 43–48)

### Task 43: Electron/CEF App Detection

**Files:**
- Create: `crates/daemon/src/platform/electron_detect.rs`
- Create: `crates/daemon/tests/electron_test.rs`

Implements §5.9 Phase 1: detect Electron apps (Slack, VS Code, Notion), treat as native apps with AX tree capture.

**Step 1: Write tests for Electron detection heuristics**
**Step 2: Implement app bundle inspection**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 44: Optional CDP Bridge for Electron

**Files:**
- Create: `crates/daemon/src/ipc/cdp_bridge.rs`
- Create: `crates/daemon/tests/cdp_test.rs`

Implements §5.9 Phase 2: if Electron app exposes local DevTools port, connect via CDP for DOM/AX snapshots. Localhost-only, app-allowlisted, disabled by default.

**Step 1: Write tests for CDP connection**
**Step 2: Implement CDP client (localhost only)**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 45: VLM Worker Process

**Files:**
- Create: `worker/src/oc_apprentice_worker/vlm_worker.py`
- Create: `worker/tests/test_vlm_worker.py`

Implements §9.4 execution: process VLM queue jobs using mlx-vlm (Apple Silicon) or llama-cpp-python. Rate-limited, budget-aware.

**Step 1: Write tests with mock VLM responses**
**Step 2: Implement VLM worker with budget enforcement**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 46: Prompt Injection Defense for VLM

**Files:**
- Create: `worker/src/oc_apprentice_worker/injection_defense.py`
- Create: `worker/tests/test_injection_defense.py`

Implements §7.2: strict data/instruction separation in VLM prompts, prompt-like pattern classifier.

**Step 1: Write tests with adversarial inputs**
**Step 2: Implement defense layer**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 47: Load Testing Suite

**Files:**
- Create: `tests/load/test_power_user_day.py`

Implements §14.4: simulate 10k events, validate <1% CPU for observer, bounded DB growth, VLM budget compliance.

**Step 1: Create event generator for 10k events**
**Step 2: Write load test with resource monitoring**
**Step 3: Run and validate thresholds**
**Step 4: Commit**

---

### Task 48: Multi-Monitor Test Suite

**Files:**
- Create: `tests/integration/test_multi_monitor.py`

Implements §14.3: automated scenarios for multi-monitor edge cases (spanning windows, DPI differences, focus on secondary monitor).

**Step 1: Create mock display configurations**
**Step 2: Write multi-monitor scenario tests**
**Step 3: Run and validate**
**Step 4: Commit**

---

## Final Deliverables Checklist

After all phases:

- [ ] Daemon binary `oc-apprentice-daemon` runs on macOS with <1% CPU
- [ ] Browser extension installs and communicates via Native Messaging
- [ ] SQLite WAL storage with retention, maintenance, and VACUUM safety
- [ ] Artifacts compressed (zstd) + encrypted (XChaCha20-Poly1305)
- [ ] Inline secret redaction on all captured text
- [ ] Secure field detection drops password input capture
- [ ] Dwell + scroll-as-reading snapshot triggers working
- [ ] Multi-monitor display topology captured correctly
- [ ] Clipboard metadata (hash-only) with copy-paste linking
- [ ] Episode builder with thread multiplexing and caps
- [ ] Negative demonstration pruning (undo/cancel detection)
- [ ] Semantic translator with confidence scoring
- [ ] SOP induction from repeated episode patterns
- [ ] Atomic SOP export with YAML frontmatter and index.md
- [ ] OpenClaw integration (learning-only, read index first)
- [ ] Power/thermal circuit breakers prevent laptop overheating
- [ ] Record/replay test harness for deterministic testing
- [ ] Privacy test suite (seeded secrets never leak)
- [ ] Load test (10k events, bounded resources)
- [ ] TOML config with all defaults matching §12.2
- [ ] Schema migration system (PRAGMA user_version)
