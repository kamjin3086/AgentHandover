<p align="center">
  <img src="resources/favicon.png" width="140" alt="AgentHandover — briefcase with binoculars" />
</p>

<h1 align="center">AgentHandover</h1>

<p align="center">
  <strong>Watch your screen. Learn your workflows. Hand them to agents.</strong>
</p>

<p align="center">
  <a href="#install">Install</a> &middot;
  <a href="#how-it-works">How It Works</a> &middot;
  <a href="#why-not-just-screen-recording">Why Not Just Screen Recording</a> &middot;
  <a href="#usage">Usage</a> &middot;
  <a href="#privacy">Privacy</a>
</p>

---

Every time you hand a task to an AI agent, you end up explaining the same steps you already know how to do. Open this app, go to this URL, fill in these fields, click submit, verify it worked. You do it every day without thinking — but your agent needs a manual.

AgentHandover writes that manual by watching you work. It runs locally on your Mac, observes your screen, and turns your real workflows into step-by-step procedures that agents like Claude Code and OpenClaw can follow.

You keep working. AgentHandover watches, learns, and writes the manual.

## What You Get

```
You work normally on your laptop
        ↓
AgentHandover silently observes (screenshots + vision model)
        ↓
It understands what you're doing, not just what's on screen
        ↓
Repeated workflows are detected, aligned, and merged automatically
        ↓
Behavioral synthesis extracts the strategy behind the steps
        ↓
You review and approve in the menu bar app
        ↓
Agent-ready procedure files exported to OpenClaw / Claude Code
```

**No macros. No brittle automation scripts. No manual documentation.** AgentHandover captures *intent* — what you're doing and why — augmented with real DOM context (CSS selectors, ARIA labels, form field IDs) from the Chrome extension. The output isn't just mechanical steps — it's a procedure with strategy, selection criteria, content templates, guardrails, and timing patterns that agents can follow with judgment, not just clicks.

## Why Not Just Screen Recording?

Screen recording gives you pixels. AgentHandover gives you *understanding*.

| | Screen recording | AgentHandover |
|---|---|---|
| **What it captures** | Raw video frames | Structured intent + DOM context: "User is filing an expense report in Chrome on Expensify, clicking `#submit-btn` in a form with ARIA label 'Expense Form'" |
| **What it knows** | Nothing — just pixels | App context, task purpose, step sequence, CSS selectors, form field IDs, ARIA labels, verification criteria |
| **How it handles noise** | Records everything equally | Classifies activity into 8 types (work, research, communication, entertainment...) and filters noise automatically |
| **How it handles interruptions** | Breaks the recording | Tracks task continuity across interruptions — if you pause for Slack and come back, it reconnects the workflow |
| **What happens with repetition** | You get multiple identical recordings | Demonstrations are semantically aligned and merged into one canonical procedure with typed variables, confidence scores, and behavioral insights |
| **What the output looks like** | A video file | A structured SKILL.md with steps, strategy, selection criteria, content templates, guardrails, timing patterns, inputs, outputs, preconditions, verification criteria, failure recovery, and a DOM hints appendix with CSS selectors for browser automation |
| **Can an agent use it?** | No | Yes — with lifecycle gates, readiness checks, and execution monitoring |

The intelligence comes from a **local vision-language model** that looks at each screenshot and answers: *What app is this? What is the user doing? Is this a repeatable workflow or just browsing?* That structured understanding is what makes the difference between "a recording" and "a learned procedure."

## How It Works

### The observation pipeline

AgentHandover runs four layers of intelligence on every screen capture:

**Layer 1: See** — A local vision model (running on your machine, not in the cloud) looks at each screenshot and produces a structured annotation: what app is open, what URL, what the user is doing, what they'll likely do next, and whether this looks like a repeatable workflow. When the Chrome extension is loaded, this is enriched with **real DOM context** — CSS selectors, ARIA labels, `data-testid` attributes, form field names, and Shadow DOM paths — giving agents precise targets for browser automation, not just visual descriptions.

**Layer 2: Classify** — An 8-class activity classifier separates signal from noise. Your expense filing is "work." Your Reddit scrolling is "entertainment." Your Slack reply is "communication." Only workflow-relevant activity feeds into learning. You can override any classification with policy rules (e.g., "always ignore YouTube", "always track VS Code").

**Layer 3: Connect** — A continuity tracker links related work across interruptions, app switches, and time gaps. If you start a PR review, get pulled into a Slack thread, and come back 20 minutes later, AgentHandover knows it's the same task. It builds confidence-ranked spans, not hard IDs — when uncertain, it keeps segments separate rather than falsely merging.

**Layer 4: Learn** — When the same workflow appears in 2+ demonstrations, the system aligns steps semantically using Needleman-Wunsch dynamic programming (not positional matching), extracts parameters that vary across demonstrations (e.g., the domain name you searched), detects branches and variants, and produces a canonical procedure with evidence-weighted confidence. Pre-computed alignments, parameters, and branches are fed into the VLM so it can focus on strategy and decision logic instead of step discovery.

**Layer 5: Synthesize** — After 3+ observations accumulate, a behavioral synthesis pass extracts the higher-level patterns behind the steps: the overall *strategy* (why you do this, not just what you click), *selection criteria* (what you engage with vs skip), *content templates* (structural patterns in text you produce), *guardrails* (things you consistently avoid), *decision branches* (conditions that determine different paths), and *timing patterns* (phases, durations, think points). This runs automatically in the daily batch and re-runs every 3 additional observations. Before raw annotations expire at 14 days, valuable evidence (content produced, dwell-time engagement signals, URL patterns) is extracted and stored permanently on the procedure.

### Screenshots are temporary

Screenshots are captured as half-resolution JPEGs (~270 KB each), deduplicated via perceptual hashing (70% of frames are duplicates and get dropped immediately), and **deleted the moment the vision model finishes annotating them**. Only the structured JSON annotation (~500 bytes) is kept. Your screen content never accumulates on disk.

### Two observation modes

**Focus Recording** — Click Record in the menu bar, name the task, perform it, click Stop. One demonstration → one SKILL.md in ~60 seconds.

```bash
agenthandover focus start "File expense report"
# ... do the workflow ...
agenthandover focus stop
```

**Passive Discovery** — Just work normally. When the same task appears in 2+ demonstrations (detected by embedding similarity), a procedure is generated automatically. No user action required.

### Any vision model, not just Qwen

AgentHandover defaults to local Qwen models via Ollama because they're free, fast, and private. But you can use **any of 6 supported backends**:

| Backend | How to use | Best for |
|---------|-----------|----------|
| **Ollama** (default) | `ollama pull qwen3.5:2b` | Local, free, private |
| **MLX** | Apple Silicon native | Fastest on Mac |
| **llama.cpp** | CPU/GPU flexible | Cross-platform local |
| **OpenAI** | `mode = "remote"` in config | Highest quality (GPT-4o) |
| **Anthropic** | `mode = "remote"` in config | Claude vision |
| **Google** | `mode = "remote"` in config | Gemini vision |

Switch models by editing `annotation_model` and `sop_model` in config, or run `agenthandover setup --vlm` for guided setup. Remote APIs require explicit opt-in and show a privacy warning.

### Review and approve

Generated procedures appear as drafts in the menu bar app. You review, approve, and promote them through a lifecycle:

```
Observed → Draft → Reviewed → Verified → Agent Ready
```

Each promotion requires your approval. No procedure reaches agents without your sign-off. The system suggests promotions based on evidence (observation count, confidence, execution success rate) but never auto-promotes.

The menu bar app surfaces:
- **Draft SOPs** to approve or reject
- **Trust suggestions** — earned enough evidence for higher agent permissions
- **Lifecycle upgrades** — ready for promotion based on observation evidence
- **Merge candidates** — similar procedures that might be duplicates
- **Drift alerts** — procedures whose observed behavior has changed
- **Stale alerts** — procedures not seen recently

### Agent-ready export

Approved procedures are compiled into target-specific formats from a single canonical source:

| Format | Location | Used by |
|--------|----------|---------|
| **SKILL.md** | `~/.openclaw/workspace/memory/apprentice/sops/` | OpenClaw agents |
| **Claude Code Skill** | `~/.claude/skills/<slug>/SKILL.md` | Claude Code (`/skill-name`) |
| **v3 Procedure JSON** | `~/.agenthandover/knowledge/procedures/` | Any agent via Query API |

Agents query `GET /ready` on port 9477 to discover executable procedures, or `GET /bundle/<slug>` for a fully resolved handoff package with readiness checks, preflight validation, and execution stats.

### What makes a procedure "agent ready"?

Not just generation — a procedure must pass multiple gates:

| Gate | What it checks | Who decides |
|------|---------------|-------------|
| **Lifecycle** | Has the human reviewed and promoted it through observed → draft → reviewed → verified → agent_ready? | Human |
| **Trust level** | Is the agent authorized to execute (not just observe or draft)? | Human (via trust suggestions) |
| **Freshness** | Has the procedure been observed recently? Stale procedures auto-demote. | System |
| **Preflight** | Are required apps running? Any blocked domains? Steps present? | System |
| **Evidence** | How many observations? Any contradictions? What's the confidence? | System |
| **Execution history** | Has it succeeded when agents tried it before? 3+ failures → auto-demotion. | System |

All six must pass. A procedure with lifecycle=agent_ready but low freshness won't execute. A fresh procedure with trust=observe won't execute either. The system is designed to be **truthful about readiness** — it will never tell an agent a procedure is ready when it isn't.

## Install

### Recommended: macOS Installer

Download the latest `.pkg` from [**Releases**](https://github.com/sandroandric/AgentHandover/releases) and double-click to install.

Then:

```bash
agenthandover doctor     # Verify everything is set up
agenthandover start all  # Start observing
```

That's it. The daemon, worker, CLI, and Chrome extension are installed to standard paths.

<details>
<summary><strong>Developer install</strong> (Homebrew or source)</summary>

**Homebrew:**
```bash
brew tap sandroandric/agenthandover
brew install --HEAD agenthandover
```

**Source build** (requires Rust, Node.js 18+, Python 3.11+):
```bash
git clone https://github.com/sandroandric/AgentHandover.git && cd AgentHandover
just build-all           # Daemon, CLI, worker venv, extension, app
./scripts/setup.sh       # Native messaging host + VLM setup

# Install launchd services (rewrite paths for source build):
cp resources/launchd/com.agenthandover.*.plist ~/Library/LaunchAgents/
sed -i '' "s|/usr/local/bin/agenthandover-daemon|$(pwd)/target/release/agenthandover-daemon|" \
    ~/Library/LaunchAgents/com.agenthandover.daemon.plist
sed -i '' "s|/usr/local/lib/agenthandover/venv/bin/python|$(pwd)/worker/.venv/bin/python|" \
    ~/Library/LaunchAgents/com.agenthandover.worker.plist
sed -i '' "s|/usr/local/lib/agenthandover|$(pwd)/worker|" \
    ~/Library/LaunchAgents/com.agenthandover.worker.plist
```

</details>

### First-time setup

After install, three things need to happen once:

**1. Grant permissions**

```bash
agenthandover doctor
```

Fix any `FAIL` items. Usually:
- **Accessibility** — System Settings → Privacy & Security → Accessibility → add `agenthandover-daemon`
- **Screen Recording** — same location

**2. Pull VLM models** (~6 GB for default local models)

```bash
ollama pull qwen3.5:2b         # Scene annotation
ollama pull qwen3.5:4b         # SOP generation
ollama pull all-minilm:l6-v2   # Task embeddings
```

Or: `agenthandover setup --vlm` for guided setup (includes cloud API option).

**3. Load Chrome extension** (recommended — adds CSS selectors, ARIA labels, and form field IDs to procedures)

Open `chrome://extensions` → Enable Developer Mode → Load unpacked → select the extension directory shown by `agenthandover doctor`.

## Usage

### CLI quick reference

| Command | Description |
|---------|-------------|
| `agenthandover status` | Service health and stats |
| `agenthandover start all` | Start daemon + worker |
| `agenthandover stop all` | Stop services |
| `agenthandover focus start "title"` | Record a workflow |
| `agenthandover focus stop` | Stop recording, generate SOP |
| `agenthandover sops list` | List all SOPs |
| `agenthandover sops drafts` | List SOPs awaiting review |
| `agenthandover sops approve <slug>` | Approve a draft for export |
| `agenthandover sops promote <slug> <state>` | Promote lifecycle (e.g., `reviewed`, `agent_ready`) |
| `agenthandover doctor` | Pre-flight health check |
| `agenthandover watch` | Live dashboard |
| `agenthandover export --format claude-skill` | Re-export as Claude Code skills |
| `agenthandover logs worker -f` | Follow worker logs |

### Query API (for agent developers)

The worker runs a local HTTP API on port 9477:

```bash
# Discover agent-ready procedures
curl http://localhost:9477/ready

# Get a full handoff bundle for execution
curl http://localhost:9477/bundle/file-expense-report

# List all procedures (any lifecycle state)
curl http://localhost:9477/procedures

# Browse curation queue
curl http://localhost:9477/curation/queue

# Promote via API
curl -X POST http://localhost:9477/curation/promote \
  -H 'Content-Type: application/json' \
  -d '{"slug": "file-expense-report", "to_state": "agent_ready"}'
```

## Architecture

```
┌──────────────────────────────────────────────────────┐
│              Menu Bar App (SwiftUI)                   │
│   Status · Focus recording · Review queue · Digest   │
└───────────────────────┬──────────────────────────────┘
                        │ trigger files (JSON)
                        ▼
Chrome Extension ──→ Daemon (Rust) ──SQLite WAL──→ Worker (Python)
  DOM snapshots       Screenshots                    ┌──────────────────┐
  Click intent        OS Accessibility               │ Pipeline v2 +VLM │
  Secure fields       Clipboard + dHash              │ Variant alignment │
                      Focus session tags             │ Behavioral synth  │
                                                     └────────┬─────────┘
                                                               │
                                    ┌──────────────────────────┼──────────────────────────┐
                                    ▼                          ▼                          ▼
                              SKILL.md SOPs          v3 Procedures (KB)            Query API
                              (OpenClaw,             (strategy, guardrails,        (port 9477)
                               Claude Code)           templates, evidence)
```

| Component | Language | Role |
|-----------|----------|------|
| **Daemon** | Rust | Always-on observer — screenshots, OS events, clipboard, dHash dedup |
| **Worker** | Python | Pipeline — VLM annotation, classification, segmentation, variant alignment, SOP generation, behavioral synthesis, evidence extraction, lifecycle, curation |
| **Extension** | TypeScript | Chrome MV3 — DOM snapshots, click intent, dwell/scroll tracking |
| **CLI** | Rust | Service management, focus recording, SOP approval, lifecycle promotion |
| **App** | SwiftUI | Menu bar — status, focus recording, review queue, daily digest |

### Processing budget

AgentHandover uses ~40% of GPU time per work hour. 36 minutes of headroom remain for your own GPU tasks.

| Stage | Time per hour | Notes |
|-------|---------------|-------|
| Scene annotation | 15.6 min | ~75 frames after dedup and stale-skip |
| Frame diffs | 4.5 min | Consecutive frame comparison |
| Task segmentation | 0.8 min | CPU only (embeddings) |
| SOP generation | 2.4 min | Thinking mode, enriched with variant analysis |
| Behavioral synthesis | 0.5 min | Daily batch only, when 3+ observations accumulate |

## Privacy

AgentHandover is designed to never leave your machine:

- **Local-first.** All VLM inference runs locally via Ollama by default. Cloud APIs are opt-in with explicit consent and a privacy warning.
- **Screenshots are temporary.** Raw JPEGs are deleted immediately after the vision model annotates them. Only the structured annotation (~500 bytes) is kept — never the screenshot itself.
- **Auto-redaction.** API keys, tokens, passwords, and credit card numbers are detected and scrubbed before storage.
- **Secure field exclusion.** Password and credit card inputs are dropped entirely — never captured, never stored.
- **Encryption at rest.** Artifacts use zstd compression + XChaCha20-Poly1305.
- **Configurable retention.** Raw events pruned after 14 days, episodes after 90 days. Valuable evidence (content patterns, engagement signals, timing) is extracted and stored permanently on procedures before raw events expire.
- **No telemetry.** Pipeline metrics are local-only JSON files. Nothing phones home. Ever.

## Configuration

Config lives at `~/Library/Application Support/agenthandover/config.toml`.

<details>
<summary>Full configuration reference</summary>

### Observer

| Key | Default | Description |
|-----|---------|-------------|
| `t_dwell_seconds` | 3 | Inactivity before dwell snapshot |
| `screenshot_max_per_minute` | 20 | Screenshot rate limit |
| `screenshot_quality` | 70 | JPEG quality 1-100 |
| `screenshot_scale` | 0.5 | Resolution scale (0.5 = half) |

### VLM

| Key | Default | Description |
|-----|---------|-------------|
| `annotation_model` | qwen3.5:2b | Any Ollama model name, or cloud model ID |
| `sop_model` | qwen3.5:4b | SOP generation model |
| `mode` | local | `local` (Ollama) or `remote` (cloud API) |
| `provider` | — | For remote: `openai`, `anthropic`, or `google` |
| `max_jobs_per_day` | 50 | VLM inference budget |
| `max_compute_minutes_per_day` | 20 | GPU time budget |

### Features

| Key | Default | Description |
|-----|---------|-------------|
| `activity_classification` | true | 8-class activity taxonomy |
| `continuity_tracking` | true | Task continuity across interruptions |
| `lifecycle_management` | true | 7-state procedure lifecycle |
| `curation` | true | Merge/upgrade/drift detection |
| `runtime_validation` | true | Pre-execution app-running checks |

### Privacy

| Key | Default | Description |
|-----|---------|-------------|
| `enable_inline_secret_redaction` | true | Auto-redact API keys, tokens |
| `secure_field_drop` | true | Drop events from password fields |

### Storage

| Key | Default | Description |
|-----|---------|-------------|
| `retention_days_raw` | 14 | Days to keep raw events |
| `retention_days_episodes` | 90 | Days to keep episodes |

</details>

## Troubleshooting

<details>
<summary>Services not starting</summary>

```bash
agenthandover doctor        # Check all prerequisites
agenthandover logs daemon   # Daemon-specific errors
agenthandover logs worker   # Worker-specific errors
```

</details>

<details>
<summary>No events being captured</summary>

- Verify Accessibility permission: System Settings → Privacy & Security → Accessibility
- Check `agenthandover status` for daemon health
- Ensure Chrome extension is loaded and enabled

</details>

<details>
<summary>No SOPs being generated</summary>

- **Passive mode** requires 2+ similar demonstrations of the same workflow within a 24-hour window
- Verify Ollama is running: `ollama list`
- Check worker logs: `agenthandover logs worker -f`
- Ensure `annotation_enabled = true` in config

</details>

<details>
<summary>Extension not connecting</summary>

- Run `agenthandover doctor` to verify native messaging host
- Reload the extension in `chrome://extensions`
- Check Chrome developer console for errors

</details>

## Uninstall

```bash
agenthandover uninstall              # Remove services, keep data
agenthandover uninstall --purge-data # Remove everything
```

## License

MIT
