# OpenMimic

A local, privacy-first apprentice that silently observes your macOS workflows and generates semantic SOPs (Standard Operating Procedures) that AI agents can execute.

**Observation is always-on; learning is delayed.** OpenMimic captures UI intent (not raw macros), runs heavy processing only during idle windows, and never takes actions on your behalf.

## Installation

### Option A: .pkg Installer (Recommended)

Download the latest `.pkg` from [Releases](https://github.com/sandroandric/OpenMimic/releases) and run it. The installer sets up everything automatically.

### Option B: Homebrew

```bash
brew tap sandroandric/openmimic
brew install openmimic
```

### Option C: Build from Source

```bash
git clone https://github.com/sandroandric/OpenMimic.git
cd OpenMimic

# Install just (task runner)
brew install just

# Build everything
just build-all

# Run tests
just test-all
```

## First Run

After installation, run the setup check:

```bash
openmimic doctor
```

This verifies all components are installed and guides you through permissions setup.

### Required Permissions

OpenMimic needs two macOS permissions:

1. **Accessibility** — to read window titles and UI elements
2. **Screen Recording** — to capture screenshots for visual context

Grant these in **System Settings > Privacy & Security**. The menu bar app will guide you through this on first launch.

### Chrome Extension

Load the extension for rich browser observation:

1. Open `chrome://extensions`
2. Enable **Developer Mode**
3. Click **Load unpacked** and select `/usr/local/lib/openmimic/extension/`

The extension communicates with the daemon locally via Chrome Native Messaging. No data leaves your machine.

## Usage

### Start Services

```bash
openmimic start all
```

Services auto-start on login via launchd. Use the menu bar app or CLI to control them.

### Check Status

```bash
openmimic status
```

Shows daemon and worker health, event counts, and SOP generation progress.

### View SOPs

```bash
openmimic sops list          # List generated SOPs
openmimic sops show <slug>   # View a specific SOP
openmimic sops dir           # Print SOPs directory path
```

### View Logs

```bash
openmimic logs daemon         # View daemon logs
openmimic logs worker -f      # Follow worker logs in real-time
```

### Configuration

```bash
openmimic config show         # Display current config
openmimic config edit         # Open in $EDITOR
openmimic config path         # Print config file path
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `openmimic status` | Show service health and stats |
| `openmimic start [daemon\|worker\|all]` | Start services via launchd |
| `openmimic stop [daemon\|worker\|all]` | Stop services |
| `openmimic restart [daemon\|worker\|all]` | Restart services |
| `openmimic logs <service> [-f] [-n N]` | View/follow log files |
| `openmimic config show\|edit\|path` | Manage configuration |
| `openmimic sops list\|show\|dir` | View generated SOPs |
| `openmimic doctor` | Run pre-flight checks |
| `openmimic uninstall [--purge-data]` | Remove OpenMimic |

## Configuration

The config file lives at `~/Library/Application Support/oc-apprentice/config.toml`.

| Section | Key | Default | Description |
|---------|-----|---------|-------------|
| `[observer]` | `t_dwell_seconds` | 3 | Inactivity before dwell snapshot |
| `[observer]` | `screenshot_max_per_minute` | 20 | Screenshot rate limit |
| `[privacy]` | `enable_inline_secret_redaction` | true | Auto-redact API keys, tokens |
| `[privacy]` | `secure_field_drop` | true | Drop events from password fields |
| `[storage]` | `retention_days_raw` | 14 | Days to keep raw events |
| `[storage]` | `retention_days_episodes` | 90 | Days to keep episodes |
| `[export]` | `adapter` | openclaw | Export adapter: `openclaw` or `generic` |
| `[export]` | `json_export` | false | Also write JSON alongside Markdown |
| `[vlm]` | `max_jobs_per_day` | 50 | VLM inference budget |
| `[idle_jobs]` | `require_ac_power` | true | Only process when plugged in |
| `[idle_jobs]` | `run_window_local_time` | 01:00-05:00 | Idle processing window |

## Architecture

Three-process system with SQLite WAL as local event broker:

```
Chrome Extension ──native messaging──> Daemon ──SQLite WAL──> Worker ──> SOPs
                                         |
                                    OS Accessibility
                                    Screenshots
                                    Clipboard
```

| Component | Language | Role |
|-----------|----------|------|
| **Daemon** | Rust | Always-on observer — OS events, screenshots, clipboard, health monitoring |
| **Worker** | Python | Idle-time processor — episodes, translation, confidence scoring, SOP induction |
| **Extension** | TypeScript | Chrome MV3 — DOM snapshots, click intent, dwell/scroll-read tracking |
| **CLI** | Rust | Service management — start/stop, status, logs, doctor, config |
| **Menu Bar App** | Swift | Visual status — green/yellow/red indicator, onboarding, controls |

## Troubleshooting

**Services not starting:**
```bash
openmimic doctor           # Check all prerequisites
openmimic logs daemon      # Check daemon logs for errors
openmimic logs worker      # Check worker logs
```

**No events being captured:**
- Verify Accessibility permission is granted
- Check `openmimic status` for daemon health
- Ensure Chrome extension is loaded and enabled

**No SOPs being generated:**
- SOPs require repeated workflow patterns (at least 3 similar episodes)
- Check `openmimic logs worker` for pipeline activity
- Ensure idle processing window is configured (default: 1:00-5:00 AM)

**Extension not connecting:**
- Verify native messaging host: `openmimic doctor`
- Check Chrome developer console for the extension
- Reload the extension in `chrome://extensions`

## Uninstall

```bash
openmimic uninstall              # Remove services, keep data
openmimic uninstall --purge-data # Remove everything including database
```

Or run the standalone uninstaller:
```bash
bash /usr/local/lib/openmimic/scripts/uninstall.sh
```

## Privacy

- **100% local.** No network egress from any component.
- **Auto-redaction.** API keys, tokens, passwords, and credit card numbers are detected and redacted before storage.
- **Secure field exclusion.** Password and credit-card input fields are dropped entirely.
- **Encryption at rest.** Screenshots and artifacts use zstd compression + XChaCha20-Poly1305 encryption.
- **Prompt injection defense.** DOM text is sanitized against 15 regex patterns across 7 threat categories.
- **Configurable retention.** Raw events pruned after 14 days, episodes after 90 days.

## License

MIT
