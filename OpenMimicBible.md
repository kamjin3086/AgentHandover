# AgentHandoverBible

> **AgentHandover is a knowledge capture system that turns human expertise into agent capability.** You work normally. AgentHandover watches. Over time, any AI agent that connects to AgentHandover can do your routine work because it has your exact procedures, your preferences, your decision logic, your accounts, your context.
>
> **The product isn't the SOPs. The product is a portable, growing, machine-readable model of how you work.**

---

## 1. The Two Consumers

Everything AgentHandover produces serves two audiences from the same raw data.

### The AI Agent (Primary Consumer)

The agent needs to **execute work on the human's behalf**. This requires:

| Need | Description | Example |
|------|-------------|---------|
| **Executable Procedures** | Step-by-step with typed inputs, outputs, branches, retry logic, verification assertions | "Navigate to expiredomains.net, filter by date, for each row: if price < $50 AND DA > 20 add to buy list" |
| **Decision Logic** | The rules the human applies when choosing between options | "Domains under $50 → buy. $50-200 → flag. Over $200 → skip." |
| **User Profile** | Preferences, defaults, tool choices, communication style | "Uses Safari not Chrome. Signs emails 'Best, Sandro'. Saves files to ~/Desktop/projects/" |
| **Active Context** | Current projects, recent conversations, open tasks | "Working on OpenMimic v2. Last emailed John about domain list. Deploy due Friday." |
| **Trigger Conditions** | When to act without being asked | "Every Monday 9am: check expired domains. When email from X: process invoice." |
| **Constraints** | What the agent must NOT do, what needs approval | "Never spend > $200 without approval. Never email clients directly. Never delete files." |
| **Environment Specs** | What needs to be true before execution | "Logged into Gmail. Domain registrar tab open. VPN connected." |
| **Error Recovery** | What to do when things go wrong | "If login expired: re-auth at /login. If page timeout: retry 3x with 5s delay." |

### The Human (Oversight Layer)

The human needs to **understand, approve, and control**. This requires:

| Need | Description |
|------|-------------|
| **Awareness** | What did I do today? Where did my time go? |
| **Review** | What did OpenMimic learn? Is it correct? |
| **Control** | Approve/reject procedures. Set trust levels. Start/stop recording. |
| **Correction** | Fix what the agent gets wrong (feeds back into knowledge base). |
| **Trust calibration** | Gradually increase delegation as confidence grows. |

The human interface is deliberately minimal. The value is in the agent's capability, not in dashboards.

---

## 2. The Knowledge Base

The knowledge base is the core product. It is a persistent, growing, machine-readable model of how one specific human works. It lives locally and is portable across agent frameworks.

### Structure

```
~/.openmimic/
  knowledge/
    procedures/              # Executable workflows (machine-format JSON)
      {slug}.json
    profile.json             # User preferences, accounts, tools, style
    decisions.json           # Decision rules per procedure (inferred from variation)
    triggers.json            # When to auto-execute (time, event, state triggers)
    constraints.json         # Guardrails, limits, approval requirements
    context/
      projects.json          # Active projects and their state
      contacts.json          # Who the user communicates with and about what
      recent.json            # Rolling window of recent activity context
  observations/
    daily/
      2026-03-10.json        # Daily activity summary (processed, not raw)
    patterns/
      recurrence.json        # Detected recurring tasks
      chains.json            # Task dependency chains
      evolution.json         # How workflows change over time
  exports/                   # Adapter outputs for specific agent frameworks
    claude-skills/           # Claude Code SKILL.md format
    openclaw/                # OpenClaw workspace format
    generic/                 # Generic markdown SOPs
  config.json                # Trust levels, automation settings
```

### Machine Procedure Format

This is what agents consume. Not markdown. Structured, typed, executable.

```json
{
  "id": "check-expired-domains",
  "version": 4,
  "short_title": "Check expired domains",
  "description": "Review newly expired domains for purchase opportunities based on DA score and price criteria.",
  "tags": ["browsing", "research"],
  "confidence": 0.94,
  "observation_count": 7,
  "first_observed": "2026-02-15",
  "last_observed": "2026-03-10",
  "recurrence": {
    "pattern": "weekly",
    "day": "monday",
    "typical_time": "09:00",
    "avg_duration_minutes": 35
  },

  "inputs": [
    {
      "name": "date_range",
      "type": "date_range",
      "default": "last_7_days",
      "required": true,
      "description": "Which date range of expired domains to review"
    }
  ],
  "outputs": [
    {
      "name": "domain_list",
      "type": "spreadsheet_rows",
      "destination": "Google Sheets > Domain Research > {today_date}",
      "description": "Filtered list of domains meeting purchase criteria"
    }
  ],

  "environment": {
    "requires": ["browser", "google_sheets_access", "expiredomains_account"],
    "accounts": ["expiredomains.net", "google:sandro.a.andric@gmail.com"],
    "setup": [
      {"action": "ensure_logged_in", "service": "expiredomains.net"},
      {"action": "ensure_logged_in", "service": "google_sheets"}
    ]
  },

  "steps": [
    {
      "id": "s1",
      "action": "navigate",
      "target": "https://www.expiredomains.net/deleted-domains/",
      "app": "browser",
      "verify": {
        "type": "url_contains",
        "value": "deleted-domains"
      },
      "on_failure": {
        "retry": 2,
        "delay_seconds": 5,
        "then": "abort",
        "message": "Could not load expired domains page"
      }
    },
    {
      "id": "s2",
      "action": "input",
      "target": "date range filter",
      "value": "$date_range",
      "selector_hints": {
        "aria_label": "Date range",
        "fallback_text": "date range input"
      },
      "verify": {
        "type": "element_value_set"
      }
    },
    {
      "id": "s3",
      "action": "click",
      "target": "Search button",
      "verify": {
        "type": "page_contains",
        "value": "results"
      }
    },
    {
      "id": "s4",
      "action": "evaluate_rows",
      "description": "Apply purchase criteria to each domain row",
      "decision_ref": "domain_purchase_filter",
      "for_each": "row in search_results",
      "branches": [
        {
          "condition": "row.price < 50 AND row.domain_authority > 20",
          "action": "add_to_output",
          "label": "buy"
        },
        {
          "condition": "row.price >= 50 AND row.price < 200 AND row.domain_authority > 30",
          "action": "add_to_output",
          "label": "review"
        },
        {
          "condition": "default",
          "action": "skip"
        }
      ]
    },
    {
      "id": "s5",
      "action": "copy_to_clipboard",
      "target": "selected domains",
      "verify": {
        "type": "clipboard_not_empty"
      }
    },
    {
      "id": "s6",
      "action": "navigate",
      "target": "Google Sheets > Domain Research",
      "app": "browser"
    },
    {
      "id": "s7",
      "action": "paste",
      "target": "next empty row",
      "verify": {
        "type": "row_count_increased"
      }
    }
  ],

  "success_criteria": [
    {"type": "output_exists", "output": "domain_list"},
    {"type": "output_row_count", "output": "domain_list", "min": 0}
  ],

  "constraints": {
    "max_spend_usd": null,
    "requires_human_approval": false,
    "can_contact_external": false,
    "irreversible_steps": []
  },

  "error_recovery": [
    {
      "condition": "login_expired",
      "action": "re_authenticate",
      "target": "https://www.expiredomains.net/login/",
      "then": "retry_from_step",
      "step": "s1"
    },
    {
      "condition": "no_results",
      "action": "widen_date_range",
      "then": "retry_from_step",
      "step": "s2"
    }
  ],

  "expected_outcomes": [
    {
      "type": "data_transfer",
      "description": "Filtered domain list pasted into Google Sheets",
      "verification": {"type": "row_count_increased", "min_rows": 1}
    }
  ],

  "staleness": {
    "last_observed": "2026-03-10",
    "last_confirmed": "2026-03-10",
    "last_agent_success": null,
    "drift_signals": [],
    "confidence_trend": [0.85, 0.90, 0.94],
    "status": "current"
  },

  "evidence": {
    "observations": [
      {"date": "2026-02-15", "type": "focus", "duration_minutes": 32, "session_id": "sess_001"},
      {"date": "2026-02-22", "type": "passive", "duration_minutes": 28, "session_id": "sess_012"},
      {"date": "2026-03-01", "type": "passive", "duration_minutes": 40, "session_id": "sess_034"},
      {"date": "2026-03-10", "type": "passive", "duration_minutes": 35, "session_id": "sess_051"}
    ],
    "step_confidence": {
      "s1": {"observed": 7, "consistent": 7},
      "s2": {"observed": 7, "consistent": 7},
      "s3": {"observed": 7, "consistent": 7},
      "s4": {"observed": 7, "consistent": 5, "note": "branches vary by input"},
      "s5": {"observed": 7, "consistent": 6}
    },
    "contradictions": [
      {"date": "2026-02-22", "step": "s4", "note": "Bought domain with DA=18, below inferred threshold of 20"}
    ]
  },

  "metadata": {
    "source": "passive_discovery",
    "created_at": "2026-02-15T10:30:00Z",
    "updated_at": "2026-03-10T09:45:00Z",
    "human_reviewed": true,
    "human_edited": false,
    "confidence_breakdown": {
      "demo_count": 0.25,
      "step_consistency": 0.30,
      "annotation_quality": 0.22,
      "variable_detection": 0.12,
      "focus_bonus": 0.05
    }
  }
}
```

### User Profile

Accumulated from all observations. Updated continuously.

```json
{
  "identity": {
    "name": "Sandro Andric",
    "primary_email": "sandro.a.andric@gmail.com",
    "timezone": "America/New_York"
  },
  "tools": {
    "browser": "Google Chrome",
    "editor": "Visual Studio Code",
    "terminal": "Terminal.app",
    "email": "Gmail (web)",
    "documents": "Google Docs",
    "spreadsheets": "Google Sheets"
  },
  "accounts": [
    {"service": "gmail", "identity": "sandro.a.andric@gmail.com"},
    {"service": "github", "identity": "sandroandric"},
    {"service": "expiredomains.net", "identity": "sandro"}
  ],
  "working_patterns": {
    "typical_start": "08:30",
    "typical_end": "18:00",
    "deep_work_hours": ["09:00-12:00"],
    "admin_hours": ["13:00-14:00", "17:00-18:00"],
    "break_patterns": ["12:00-13:00"]
  },
  "communication_style": {
    "email_sign_off": "Best,\nSandro",
    "tone": "professional, direct",
    "response_time_typical_minutes": 30
  },
  "file_organization": {
    "projects_root": "~/Desktop/",
    "downloads_usage": "temporary, cleaned weekly",
    "naming_convention": "lowercase-with-hyphens"
  },
  "preferences": {
    "dark_mode": true,
    "keyboard_shortcuts_heavy_user": true,
    "copy_paste_workflow": true
  }
}
```

### Decision Rules

Inferred from observing the human make different choices on different inputs across multiple observations of the same workflow.

```json
{
  "domain_purchase_filter": {
    "procedure": "check-expired-domains",
    "applies_to_step": "s4",
    "inferred_from_observations": 5,
    "confidence": 0.88,
    "rules": [
      {
        "condition": "price < 50 AND domain_authority > 20",
        "action": "buy",
        "observed_count": 12,
        "description": "Cheap domains with decent authority — always buy"
      },
      {
        "condition": "price >= 50 AND price < 200 AND domain_authority > 30",
        "action": "flag_for_review",
        "observed_count": 4,
        "description": "Mid-range price but high authority — worth considering"
      },
      {
        "condition": "price >= 200",
        "action": "skip",
        "observed_count": 8,
        "description": "Too expensive — always skipped"
      }
    ]
  }
}
```

### Triggers

When the agent should act without being asked.

```json
{
  "triggers": [
    {
      "procedure": "check-expired-domains",
      "type": "schedule",
      "pattern": "weekly",
      "day": "monday",
      "time": "09:00",
      "enabled": true,
      "trust_level": "execute_with_approval"
    },
    {
      "procedure": "process-invoice",
      "type": "event",
      "condition": "email_received AND sender_domain = 'billing.stripe.com'",
      "enabled": true,
      "trust_level": "draft"
    },
    {
      "procedure": "daily-standup-prep",
      "type": "schedule",
      "pattern": "weekday",
      "time": "08:45",
      "enabled": false,
      "trust_level": "suggest"
    }
  ]
}
```

### Constraints

What the agent must never do, and what needs human sign-off.

```json
{
  "global": {
    "never_send_email_without_approval": true,
    "never_make_purchases_over_usd": 100,
    "never_delete_files_outside_trash": true,
    "never_share_credentials": true,
    "never_access_banking": true,
    "require_approval_for_external_communication": true
  },
  "per_procedure": {
    "check-expired-domains": {
      "max_domains_to_buy_per_run": 5,
      "requires_approval": false
    },
    "send-weekly-report": {
      "requires_approval": true,
      "approval_timeout_hours": 2,
      "on_timeout": "skip"
    }
  }
}
```

---

## 3. Data Flow: From Observation to Agent Capability

### Collection (Already Built)

```
User works normally
       |
       v
Daemon (Rust, always-on, <1% CPU)
  - Screenshots (JPEG, half-res, dhash dedup)
  - App switches (from_app, to_app, window_title)
  - Dwell snapshots (3s no manipulation = reading)
  - Clipboard changes (metadata + hash, not raw content)
  - Click intents (via Chrome extension)
  - DOM snapshots (viewport-bounded, via extension)
  - Accessibility tree (AX API, native apps)
  - Scroll-as-reading (8s continuous scroll)
       |
       v
SQLite WAL (event queue, encrypted artifacts on disk)
```

### Processing (Partially Built, Needs Enhancement)

```
Raw Events (SQLite)
       |
       v
+----------------------------------------------+
|           Daily Batch Processor               |  <-- NEW
|                                               |
|  1. Activity Timeline                         |
|     - Continuous stream of intent-based tasks  |
|     - Not app-based, not time-windowed        |
|     - Cross-app task continuity               |
|     - "User researched domains in Chrome,     |
|      copied data, pasted into Sheets,         |
|      emailed results" = ONE task              |
|                                               |
|  2. Task Identification                       |
|     - What is the user trying to accomplish?  |
|     - Intent from VLM annotation              |
|     - Clipboard transfers link apps           |
|     - Temporal proximity links actions        |
|                                               |
|  3. Pattern Engine                            |  <-- NEW
|     - Recurrence detection (daily/weekly)     |
|     - Task chains (A always followed by B)    |
|     - Workflow evolution (steps change)        |
|     - Duration tracking                       |
|                                               |
|  4. Knowledge Extraction                      |  <-- NEW
|     - Decision rules from variation           |
|     - User preferences from consistency       |
|     - Error recovery from observed retries    |
|     - Context from surrounding activity       |
|                                               |
|  5. SOP Pipeline (Existing, Enhanced)         |
|     - VLM annotation (Qwen 2B)               |
|     - Frame diffs                             |
|     - Timeline construction                   |
|     - SOP generation (Qwen 4B, thinking)     |
|     - Machine-format output (NEW)             |
+----------------------------------------------+
       |
       v
Knowledge Base (persistent, grows over time)
  - Procedures (machine JSON)
  - Profile (preferences, tools, accounts)
  - Decisions (branching rules)
  - Triggers (when to act)
  - Constraints (what NOT to do)
  - Context (projects, contacts, recent)
       |
       +---> Agent Interface (query API, skill exports)
       |
       +---> Human Interface (menu bar app, daily digest)
```

### Export (Built, Machine Format Needs Extension)

```
Knowledge Base
       |
       v
Export Adapters
  - Machine JSON (base schema built — extend with outcomes, staleness, evidence)
  - Claude Code skills (SKILL.md — built)
  - OpenClaw workspace (built)
  - Generic markdown (built)
  - Future: OpenAI GPTs, LangChain tools, etc.
```

---

## 4. How It Learns: The Processing Pipeline in Detail

### 4.1 Continuous Activity Stream

**Current state:** Events are isolated. A DwellSnapshot in Chrome and a ClipboardChange 2 seconds later are treated as unrelated.

**Target state:** Events form a continuous activity stream where intent is tracked across apps. The key linking signals:

| Signal | What It Tells Us |
|--------|-----------------|
| Clipboard transfer | User copied from App A, pasted in App B — same task |
| Temporal proximity | Actions < 30s apart are likely same task |
| URL/document topic | Research in Chrome tab about "domains" + editing Google Sheet named "Domain List" — same task |
| VLM annotation continuity | `what_doing` field stays semantically similar across frames |
| Window title continuity | Same document/page open across multiple snapshots |

### 4.2 Task Boundary Detection

A task starts when:
- User opens a new context (new app, new document, new URL topic)
- VLM `what_doing` changes semantically
- Gap > 5 minutes of inactivity

A task ends when:
- User switches to unrelated context
- Gap > 10 minutes
- User explicitly closes the relevant app/document

A task is the **same task across sessions** when:
- Same procedure detected (matching steps, apps, URLs)
- Same project context (same documents, same contacts)
- Temporal recurrence matches (same time of week)

### 4.2.1 Interruption and Resumption Model

Laptop work is not linear. Users get interrupted by Slack, jump to email, handle a quick request, and return to the original task 20 minutes later. Interruption and resumption must be **first-class**, not edge cases.

**Task states:**

| State | Definition | Detection Signal |
|-------|-----------|-----------------|
| **Active** | User is working on this task right now | Current app/document matches task context |
| **Paused** | User switched away but will return | Short gap (< 30 min), task artifacts still open |
| **Resumed** | User returned to a paused task | Same app/document/URL reopened, similar VLM annotation |
| **Abandoned** | User left and won't return this session | Long gap (> 60 min) with no return, artifacts closed |
| **Related** | User switched to a task that serves this one | Clipboard transfer, same project context, supporting activity |

**Interruption classification:**

```
Active task: "Writing quarterly report in Google Docs"
  |
  +--> Slack notification → opens Slack → replies in 30s → returns to Docs
  |    Classification: BRIEF INTERRUPT (not a task boundary)
  |
  +--> Email from boss → opens Gmail → reads → archives → returns to Docs
  |    Classification: RELATED INTERRUPT (email is about the same project)
  |
  +--> Phone call → idle 15 min → returns to Docs
  |    Classification: PAUSE + RESUME (same task continues)
  |
  +--> Starts completely different task → never returns to Docs today
       Classification: ABANDONED (task will appear as incomplete in daily summary)
```

**Implementation signals:**
- Window/tab still open in background → likely paused, not finished
- Clipboard content from Task A used in Task B → related tasks
- Same document edited in morning and afternoon → resumed task
- VLM `what_doing` returns to semantically similar description → resumption

### 4.3 Pattern Detection

After accumulating 2+ weeks of daily observations:

**Recurrence patterns:**
- Daily: "Check email at 9am, 1pm, 5pm"
- Weekly: "Review domains Monday, deploy Friday"
- Trigger-based: "Process invoice within 1h of receiving billing email"

**Task chains:**
- "After updating spreadsheet, always email John"
- "Before deploying, always run tests and check staging"

**Evolution:**
- "Used to copy-paste manually from website, now uses export button" (procedure updated)
- "Added a new step: now also checks domain backlinks" (procedure extended)
- "Stopped doing step 3 — it was for the old system" (procedure simplified)

### 4.4 Decision Extraction

This is the hardest and most valuable extraction. It requires multiple observations of the same task with different inputs leading to different outcomes.

**Method:**
1. Identify same-procedure observations (via SOP dedup fingerprinting)
2. Align the steps across observations
3. Find divergence points (same step in procedure, different action taken)
4. Correlate divergence with input differences
5. Infer the rule

**Example with 5 observations of "check expired domains":**

| Observation | Domain | Price | DA | Action |
|-------------|--------|-------|----|--------|
| 1 | foo.com | $20 | 25 | Bought |
| 2 | bar.com | $150 | 40 | Flagged |
| 3 | baz.com | $300 | 50 | Skipped |
| 4 | qux.com | $15 | 10 | Skipped |
| 5 | xyz.com | $45 | 35 | Bought |

**Inferred rule:** `IF price < 50 AND DA > 20 THEN buy. IF price 50-200 AND DA > 30 THEN flag. ELSE skip.`

Observation 4 is key — cheap but low DA, still skipped. That tells us DA matters, not just price.

### 4.5 Profile Building

The user profile is not configured — it's **inferred from observation**.

**How each field is derived:**

| Profile Field | Inferred From |
|--------------|---------------|
| Primary email | Most-used email account in observations |
| Browser preference | Which browser appears most in app switches |
| Editor preference | Which IDE/editor appears most |
| Working hours | Distribution of event timestamps across days |
| Communication style | Text patterns in composed emails (if clipboard captures drafts) |
| File organization | File paths seen in save/open dialogs |
| Keyboard shortcut usage | Ratio of keyboard vs mouse actions |

### 4.6 Error Recovery Learning

When the user encounters an error and recovers, the pattern is:

1. Normal step execution
2. Unexpected result (page error, login wall, timeout)
3. User takes recovery action (refresh, re-login, retry)
4. Resumes normal flow

OpenMimic detects this by:
- Negative demo detection (back button, undo, retry patterns)
- VLM annotation noting error states ("page shows 404", "login form appeared")
- Temporal pattern: pause → recovery action → resume

This becomes an `error_recovery` entry in the procedure.

### 4.7 Outcome Tracking

A lot of work is *read / compare / decide*, not just *click / type / submit*. The system must learn what changed in the world after a workflow, not only what clicks happened.

**What is an outcome?**

An outcome is the observable state change that results from executing a procedure:
- A spreadsheet gained 8 new rows
- An email was sent to john@example.com
- A file was saved to ~/Desktop/reports/q1.pdf
- A browser tab was closed (research complete, nothing saved)
- A deploy went live (terminal shows "deployed to production")

**How outcomes are detected:**

| Signal | Outcome Type |
|--------|-------------|
| New file on disk | File creation — capture path, type, size |
| Clipboard → paste into external app | Data transfer — note source and destination |
| Email compose window → send button | Communication — capture recipient, subject |
| Terminal shows success message | Command execution — capture exit status |
| Tab closed after extended reading | Research complete — note what was read |
| Spreadsheet row count changed | Data entry — capture before/after delta |
| Nothing changed | Informational task — user read but didn't act |

**Why outcomes matter for agents:**
- Success criteria become verifiable: "Did the spreadsheet actually get 8 rows?"
- Failed outcomes trigger retry: "Deploy command returned error — re-run"
- Outcome history helps decide trust promotion: "Agent produced correct outcome 9/10 times"
- Outcomes distinguish tasks from noise: a 20-minute browsing session with no outcome is likely recreational, not work

**Outcome schema (added to procedure):**

```json
{
  "expected_outcomes": [
    {
      "type": "file_created",
      "description": "Filtered domain list saved to Google Sheets",
      "verification": {"type": "row_count_increased", "min_rows": 1}
    },
    {
      "type": "communication_sent",
      "description": "Summary email sent to john@example.com",
      "verification": {"type": "email_in_sent_folder", "recipient_pattern": "john@"}
    }
  ]
}
```

### 4.8 Account and Workspace Awareness

Many repeated workflows are account-specific. "Log into Stripe" means different things for personal, staging, production, or client workspaces. The system must track **which tenant/workspace/environment** the user was operating in.

**What to track:**

| Dimension | Examples | Detection |
|-----------|----------|-----------|
| **Browser profile** | "Work" vs "Personal" Chrome profile | Profile name from window title or browser API |
| **Account/tenant** | stripe.com/personal vs stripe.com/client-co | URL subdomain, account switcher, logged-in identity |
| **Git repo/branch** | openmimic on main vs openmimic on feature/x | Terminal CWD, VS Code title bar, git status |
| **Environment** | staging vs production | URL patterns (staging.app.com vs app.com), terminal prompts |
| **Project context** | "Working on Project Alpha" | Active directory, open files, window titles |

**Why this matters:**
- Same sequence of clicks in staging vs production are **different procedures** with different risk profiles
- "Deploy to production" requires human approval; "deploy to staging" can be autonomous
- Account confusion is a top agent safety risk: wrong Stripe dashboard → wrong charges

**Knowledge base integration:**

```json
{
  "environment": {
    "requires": ["browser", "stripe_account"],
    "accounts": ["stripe.com:acct_personal"],
    "workspace_context": {
      "type": "saas_tenant",
      "identifier": "personal dashboard",
      "url_pattern": "dashboard.stripe.com/(?!test)"
    }
  }
}
```

### 4.9 Branch and Exception Extraction

Real workflows are branch-heavy: "if this field is blank", "if the report is late", "if I'm already logged in", "if validation fails." These branches are often **the actual workflow** — the happy path is the easy part.

Branch extraction must be a **core feature**, not a later refinement.

**Types of branches observed in real work:**

| Branch Type | Example | Detection Signal |
|-------------|---------|-----------------|
| **Pre-condition check** | "If already logged in, skip login" | User sometimes does steps 1-3, sometimes starts at step 4 |
| **Data-dependent** | "If field is blank, use default" | Same form filled differently based on content |
| **Error recovery** | "If validation fails, fix field X" | Back button, re-edit, retry patterns |
| **Time-dependent** | "If report is late, escalate to manager" | Different actions at different times/days |
| **Absence-based** | "If no results, try broader search" | Empty results → different action path |

**Extraction method:**
1. Align steps across multiple observations of the same procedure
2. Identify divergence points (same step position, different action)
3. Correlate with observable context (page content, time, prior steps)
4. Express as conditional: `IF <context> THEN <path_a> ELSE <path_b>`

**Branch confidence:** Each branch needs its own confidence score. A branch seen in 1/5 observations may be a rare edge case or an error. A branch seen in 3/5 is likely real decision logic.

### 4.10 Staleness and Drift Detection

Laptop workflows drift constantly. UIs change, team processes evolve, accounts rotate, new tools replace old ones. A procedure that was accurate 3 months ago may be wrong today.

**Staleness signals:**

| Signal | What It Means |
|--------|--------------|
| **Last observed > 30 days ago** | Procedure may be outdated — flag for re-observation |
| **Last confirmed (approved) > 60 days ago** | Even if observed, human hasn't verified recently |
| **Step failure rate increasing** | UI or process changed — steps no longer match reality |
| **New steps appearing** | User added a step the procedure doesn't have |
| **Steps disappearing** | User skips a step the procedure expects |
| **URL/selector changes** | Target page redesigned — DOM hints stale |
| **Confidence score dropping** | Multiple signals converging — procedure needs review |

**Staleness response:**

```json
{
  "staleness": {
    "last_observed": "2026-03-01",
    "last_confirmed": "2026-02-15",
    "last_agent_success": "2026-02-28",
    "drift_signals": [
      {"type": "new_step_observed", "step": "s3.5", "first_seen": "2026-03-01"},
      {"type": "url_changed", "old": "/dashboard/v2", "new": "/dashboard/v3"}
    ],
    "confidence_trend": [0.94, 0.91, 0.85],
    "status": "needs_review"
  }
}
```

When staleness is detected:
- Demote trust level one step (autonomous → execute_with_approval)
- Flag for human review with specific drift reason
- If agent executes, add extra verification at changed steps

---

## 5. Real-World User Scenarios

### Scenario 1: The Multi-Hour Research Task

**What happens:** User spends 3 hours researching expired domains. Opens 15 tabs, compares prices on 3 registrars, copies data into a spreadsheet, takes a coffee break in the middle, resumes, and finally emails a summary.

**What OpenMimic currently does:** Captures hundreds of events. Passive segmenter might create 5-6 separate segments (one per app or per break). Generates 5 mediocre SOPs.

**What OpenMimic should do:**
- Recognize this as ONE task spanning 3 hours and a break
- Link the Chrome research, the spreadsheet data entry, and the email as parts of the same workflow
- Generate ONE comprehensive procedure: "Domain Research and Reporting"
- Track the coffee break as a natural pause, not a task boundary
- Note that the email always goes to the same person with a similar format

### Scenario 2: The Daily Recurring Task

**What happens:** Every morning, user checks Gmail, scans for important emails, archives newsletters, responds to 2-3 messages.

**What OpenMimic currently does:** Captures each day's email session as an independent observation. Might generate an SOP after 2 observations. SOP is generic ("open Gmail, read emails").

**What OpenMimic should do:**
- After 3 days, detect the recurrence pattern: "Daily at ~9am, 15-20 minutes"
- After 5 days, extract the decision logic: "Emails from boss → respond immediately. Newsletters → archive. Client emails → flag for later."
- Build a trigger: schedule-based, every weekday at 9am
- Build the procedure with branches for different email types
- Track that response time to boss emails is < 5 minutes (urgency signal)

### Scenario 3: The One-Off Task

**What happens:** User sets up a new cloud server for the first time. Takes 45 minutes, involves AWS console, DNS configuration, SSH setup.

**What OpenMimic should do:**
- Capture it as a focus recording (or high-confidence passive detection)
- Generate a detailed procedure with all the specific steps
- Mark it as "one-off, no recurrence detected"
- Keep it in the knowledge base anyway — if user does it again in 3 months, OpenMimic links the observations and refines the SOP
- Note: the procedure is valuable for *delegation* even if the human won't repeat it — an agent can do it next time

### Scenario 4: The Evolving Workflow

**What happens:** In January, user deploys code by running 5 git commands manually. In February, they start using a deploy script. In March, they add a staging check before production deploy.

**What OpenMimic should do:**
- Detect that "deploy to production" is the same task despite changing steps
- Update the procedure to reflect the current version (not the January version)
- Keep history: "v1: manual git commands. v2: deploy script. v3: staging check added."
- If user reverts to manual commands one day (script broken?), detect it as an anomaly, not a new workflow

### Scenario 5: The Context Switch Heavy Day

**What happens:** User switches between 5 projects in a day. Email, Slack, code review, domain research, document writing. Rapid app switching, 200+ events.

**What OpenMimic should do:**
- Separate the day into task segments by intent, not by app
- "9:00-9:20 Email triage (recurring daily)"
- "9:20-10:45 Code review for PR #423 (project: OpenMimic)"
- "10:45-10:50 Slack responses (reactive, not a task)"
- "10:50-12:00 Domain research (recurring weekly)"
- "13:00-15:00 Documentation writing (project: OpenMimic)"
- Not generate SOPs for the Slack responses (too fragmented, no clear procedure)
- Generate/update SOPs for the recurring tasks (email, domain research)
- Tag the code review and documentation as project-specific tasks

### Scenario 6: The Agent Executing a Learned Task

**What happens:** It's Monday 9am. OpenMimic has learned "check expired domains" from 7 observations. Trust level is "execute with approval".

**What the agent does:**
1. Reads the procedure from the knowledge base
2. Checks environment specs: browser available, accounts accessible
3. Checks constraints: no spending limits violated
4. Executes step by step, using the decision rules for filtering
5. Generates the domain list in Google Sheets
6. Presents result to human: "Found 8 domains meeting criteria. 3 marked 'buy', 5 marked 'review'. See spreadsheet."
7. Human approves or corrects
8. If corrected: the correction is captured and the procedure/decision rules update

### Scenario 7: The Agent Learning From Corrections

**What happens:** Agent executed "check expired domains" but included domains with DA < 15 in the buy list. Human removes them.

**What OpenMimic does:**
- Detects the correction (rows removed from spreadsheet)
- Correlates with the decision rule: the threshold was DA > 20 but confidence was only 0.7
- Updates the decision rule: DA threshold confirmed at 20, confidence now 0.85
- Next execution: agent correctly filters out low-DA domains

---

## 6. The Human Interface

### Menu Bar App (Built)

Minimal, always accessible. Shows:
- System status (daemon/worker running)
- Focus recording button
- Workflows inbox (approve/reject/edit SOPs)

### Workflow Inbox (Built)

Master-detail view:
- Left: list of discovered workflows with short titles, tags, confidence
- Right: procedure detail view with steps, prerequisites, success criteria
- Actions: approve, reject, open in editor

### Micro-Review (To Build)

Review burden kills value. If users have to read long generated SOPs, they will stop. Review must be **extremely lightweight** — seconds, not minutes.

**Micro-review card (the default review UX):**

```
┌──────────────────────────────────────────────┐
│  Check expired domains                       │
│  Weekly · 35 min · 7 observations · 94%      │
│                                              │
│  Variables: date_range, price_threshold      │
│  Outcome: Filtered domains → Google Sheets   │
│                                              │
│  [✓ Approve]  [✗ Reject]  [→ See Details]   │
└──────────────────────────────────────────────┘
```

The user confirms **three things** in < 5 seconds:
1. **Title** — is this the right task? (1 glance)
2. **Variables** — are these the right inputs? (1 glance)
3. **Outcome** — is this what actually happens? (1 glance)

Full detail view is available but **not required** for approval. Most approvals should happen from the card.

**Batch review:** When multiple procedures are ready, present them as a swipeable stack, not a document list. Tinder-style approve/reject is faster than master-detail navigation.

### Evidence Transparency (To Build)

Users need to see **why** OpenMimic learned something. A draft procedure without evidence feels like a hallucination. Every draft must show its receipts.

**Evidence display (in detail view):**

```
📎 Evidence for "Check expired domains"
─────────────────────────────────────────
Observed 7 times between Feb 15 – Mar 10
  • Feb 15 (focus recording, 32 min) — first observation
  • Feb 22 (passive, 28 min) — same flow detected
  • Mar 1 (passive, 40 min) — new step: backlink check
  • Mar 10 (passive, 35 min) — most recent

Step confidence breakdown:
  Step 1: Navigate to site       ✓ 7/7 identical
  Step 2: Set date filter        ✓ 7/7 consistent
  Step 3: Apply search           ✓ 7/7 consistent
  Step 4: Evaluate rows          ⚡ 5/7 — branches vary
  Step 5: Check backlinks        ⚠️ 2/7 — new step (Mar 1+)
  Step 6: Copy to Sheets         ✓ 6/7 consistent

Decision rule evidence:
  "price < 50 AND DA > 20 → buy" — matched 12 observed choices
  1 contradiction: bought domain with DA=18 on Feb 22
```

**Key principles:**
- Every procedure links back to the specific observations that generated it
- Step-level confidence shows which parts are solid and which are uncertain
- Decision rules cite the observations they were inferred from, including contradictions
- Users can tap any evidence item to see the raw observation (screenshots, timeline)

### Daily Digest (To Build)

End-of-day notification or summary view:
- "Today: 5h 20m active work across 8 tasks"
- "2 new workflows learned, 1 existing updated"
- "3 procedures need review"
- Task breakdown by category with time spent

### Trust Level Controls (To Build)

Per-procedure or global setting:
- **Observe only** — learn but never act
- **Suggest** — notify human: "You usually do X now"
- **Draft** — agent prepares the work, human reviews before execution
- **Execute with approval** — agent does it, shows result, human confirms
- **Autonomous** — agent does it, human gets a summary

Default for new procedures: **Observe only**. Trust level can only be increased by the human, never by the system.

---

## 7. The Agent Interface

### How Agents Connect

Agents access the knowledge base through:

1. **File-based access** — read `~/.openmimic/knowledge/` directly (simplest, works with any agent)
2. **Skill exports** — SKILL.md files for Claude Code, workspace files for OpenClaw (existing adapters)
3. **Query API** (future) — local socket/HTTP for structured queries: "How does the user do X?", "What are the user's email preferences?", "What's the current project context?"

### What an Agent Gets When Asked "Do X"

```
Agent request: "Check expired domains"
       |
       v
Knowledge Base lookup:
  1. Procedure: check-expired-domains.json (full executable spec)
  2. Decision rules: domain_purchase_filter (branching logic)
  3. Profile: browser=Chrome, spreadsheet=Google Sheets
  4. Context: last run was 7 days ago, domain list has 45 entries
  5. Constraints: no spending limit, no approval needed
  6. Environment: needs browser + Google Sheets access
       |
       v
Agent has everything needed to execute
```

### Skill Export Strategy

The machine-format JSON is the source of truth. Export adapters transform it into framework-specific formats:

| Framework | Format | Adapter |
|-----------|--------|---------|
| Claude Code | `~/.claude/skills/<slug>/SKILL.md` | `claude_skill_writer.py` (built) |
| OpenClaw | `~/.openclaw/workspace/memory/apprentice/sops/` | `openclaw_writer.py` (built) |
| Generic Agents | Machine JSON (direct read) | File access (no adapter needed) |
| Future: OpenAI | Custom GPT actions schema | To build |
| Future: LangChain | Tool definitions | To build |

---

## 8. Day-1 Utility

Long-term learning is the vision, but users must get value **immediately**. A system that requires 2 weeks of observation before delivering anything will be uninstalled on day 2.

### Day-1 targets:

| Feature | Value | How | Status |
|---------|-------|-----|--------|
| **Activity search** | "What was I working on at 2pm?" "Where did I see that URL?" | Full-text search over VLM annotations, window titles, URLs | **To build** (P0) |
| **Session recall** | "Show me what I did in Chrome this morning" | Timeline view filtered by app + time | **To build** (P0) |
| **Focus recording** | "Record this setup task so I never forget the steps" | One-click recording → immediate SOP draft | **Built** |
| **First SOP draft** | One reviewed procedure from a single focus recording | Works from observation #1, no recurrence needed | **Built** |
| **Work timer** | "How long did I spend on Project X today?" | Automatic time tracking from app/document observation | **To build** |

### After 1 week:

| Feature | Value | How | Status |
|---------|-------|-----|--------|
| **Recurring task detection** | "You check email every morning around 9am" | Pattern engine needs 5+ observations | **To build** |
| **User profile draft** | "Your default browser is Chrome, you use VS Code, you work 9-6" | Profile builder aggregates 5 days of data | **To build** |
| **5-10 SOP drafts** | Passive discovery identifies repeated workflows | Segmenter + dedup over accumulated observations | **Built** |

### After 1 month:

| Feature | Value | How | Status |
|---------|-------|-----|--------|
| **Decision rules** | "When domain price < $50 and DA > 20, you always buy" | Multi-observation comparison extracts branching logic | **To build** |
| **Agent suggestions** | "It's Monday 9am — time for domain check?" | Triggers from recurrence detection | **To build** |
| **Mature procedures** | 15-25 high-confidence, reviewed workflows | Accumulated observations + human review | **To build** |

**Design principle:** Every feature must degrade gracefully to fewer observations. A procedure from 1 observation is less confident but still useful. A pattern from 3 days is tentative but worth surfacing. Never gate value behind arbitrary thresholds.

---

## 9. The Improvement Flywheel

```
Week 1: Agent knows nothing. Human does everything.
         OpenMimic observes and learns.

Week 2: Agent knows 5-10 procedures (drafts).
         Human reviews and approves the good ones.
         Agent can suggest: "It's Monday, time for domain check?"

Month 1: Agent knows 15-25 procedures.
          Decision rules emerging for key workflows.
          Agent handles email triage, routine lookups.
          Trust level: "draft" or "execute with approval" for proven tasks.

Month 3: Agent knows 40+ procedures.
          Rich decision trees for complex workflows.
          User profile mature (tools, preferences, patterns).
          Agent handles most admin, research, data entry.
          Trust level: "autonomous" for 10-15 well-proven tasks.

Month 6: Agent is a genuine work multiplier.
          Handles 2-3 hours of routine work per day.
          Human focuses on creative, strategic, novel work.
          The knowledge base IS the user's "work OS".
```

### The Correction Loop

The most powerful learning signal is human correction:

1. Agent executes a procedure
2. Human notices something wrong (wrong filter, wrong recipient, wrong format)
3. Human corrects it (edits spreadsheet, rewrites email, changes a step)
4. OpenMimic observes the correction as a new event
5. Diff between agent's output and human's correction reveals the error
6. Procedure/decision rules update
7. Next execution is correct

**One correction is worth more than 10 observations** because it directly identifies what the system got wrong.

---

## 10. Current State of Implementation

### Built and Working

| Component | Status | Notes |
|-----------|--------|-------|
| Daemon (Rust) | Production-ready | <1% CPU, captures all event types, 227 tests |
| Chrome Extension (TS) | Production-ready | MV3, DOM capture, click intent, 180 tests |
| SQLite Storage | Production-ready | WAL mode, artifact encryption, retention policies |
| CLI | Production-ready | status, doctor, focus, sops, export commands |
| Scene Annotator | Working | Qwen 2B, ~12s/frame, 3-frame context window |
| Frame Differ | Working | Consecutive annotation comparison |
| Focus Processor | Working | Full v2 pipeline orchestration |
| SOP Generator | Working | Qwen 4B with thinking, focus + passive modes |
| Task Segmenter | Working | Embedding-based clustering, passive discovery |
| Export Adapters | Working | OpenClaw, Claude Skills, Generic, SKILL.md |
| SOP JSON Schema | Working | Versioned JSON export (`sop_schema.py`), mirrors YAML frontmatter |
| SOP Dedup | Working | Structural fingerprint + merge |
| SOP Linter | Working | 5 error + 7 warning rules |
| Confidence Scoring | Working | 3-component additive model |
| SwiftUI Menu Bar App | Working | Status, focus recording, workflow inbox |
| **Total Tests** | **~970** | 227 Rust + 686 Python + 58 integration/E2E |

### Not Yet Built

| Component | Priority | Effort | Dependency |
|-----------|----------|--------|------------|
| Activity search / session recall | **P0** | Medium | VLM annotations + search index |
| Machine procedure format (full spec) | **P0** | Small | Schema exists (`sop_schema.py`) — extend with outcomes, staleness, evidence, branches |
| Interruption/resumption model | **P0** | Medium | Enhanced task segmenter |
| Branch/exception extraction | **P0** | Large | Multi-observation alignment |
| Privacy zoning | **P0** | Medium | Config system + app/URL matching |
| Micro-review UX | **P0** | Small | SwiftUI card-based approval flow |
| Evidence transparency | **P0** | Medium | Link procedures ↔ observations |
| Daily batch processor | **P0** | Large | Activity timeline, task boundary detection |
| Outcome tracking | **P1** | Medium | State change detection post-task |
| Account/workspace awareness | **P1** | Medium | URL/title parsing, profile detection |
| User profile builder | **P1** | Medium | Daily batch processor |
| Trigger/recurrence detection | **P1** | Medium | Pattern engine from daily processor |
| Decision extraction | **P1** | Large | Multiple observations of same procedure |
| Staleness/drift detection | **P1** | Small | Observation timestamps + step comparison |
| Constraint system | **P1** | Small | Schema definition + UI controls |
| Trust level controls (UI) | **P2** | Small | Constraint system |
| Agent query API | **P2** | Medium | Knowledge base structure |
| Daily digest (UI) | **P2** | Small | Daily batch processor |
| Cross-session task linking | **P2** | Large | Improved segmenter |
| Workflow evolution tracking | **P3** | Medium | SOP versioning + diff |
| Correction feedback loop | **P3** | Large | Agent execution + diff detection |

---

## 11. Architecture: Three-Process Model

### Process 1: Daemon (Rust)

Always-on, minimal resource usage. **Captures, never processes.**

- Screenshots (JPEG, half-res, dhash dedup, 50% scale)
- App/window events (focus change, title change, app switch)
- Dwell snapshots (3s no manipulation = user reading)
- Scroll-as-reading (8s continuous scroll)
- Clipboard (metadata + hash, not raw content by default)
- Click intents (via Chrome extension native messaging)
- DOM snapshots (viewport-bounded, via extension)
- Accessibility tree (AX API for native apps)

Storage: SQLite WAL (concurrent write) + encrypted artifact files.

### Process 2: Worker (Python)

Scheduled and idle-time processing. **Turns raw events into knowledge.**

Current pipeline:
1. Annotate frames (Qwen 2B, scene_annotator.py)
2. Compute frame diffs (frame_differ.py)
3. Build timeline (focus_processor.py)
4. Generate SOPs (sop_generator.py, Qwen 4B)
5. Export (claude_skill_writer.py, openclaw_writer.py, etc.)

Enhanced pipeline (to build):
1. Daily batch processing (activity timeline + task boundaries)
2. Pattern detection (recurrence, chains, evolution)
3. Knowledge extraction (decisions, profile, triggers, context)
4. Selective SOP generation (only for validated recurring tasks)
5. Machine-format export (JSON for agents)
6. Human-format export (SKILL.md, daily digest)

### Process 3: Chrome Extension (TypeScript, MV3)

Rich browser context via native messaging to daemon.

- Click target grounding (composedPath, ARIA metadata)
- Viewport-bounded DOM capture
- Dwell tracking per tab
- Secure field detection (drops capture on password fields)
- Tab URL and title tracking

### SwiftUI Menu Bar App

Human interface. Minimal but essential.

- System status (daemon/worker health, green/red indicator)
- Focus recording (start/stop/list)
- Workflow inbox (approve/reject/edit, NavigationSplitView)
- Trust level controls (per-procedure, future)
- Daily digest (future)

---

## 12. Privacy and Security

### Principles

1. **Local-only by default.** No data leaves the machine unless explicitly configured.
2. **Encrypted at rest.** All artifacts use XChaCha20-Poly1305. Key derived from machine identity.
3. **Secrets never captured.** Password fields → hard drop. High-entropy strings → inline redaction. API keys, credit cards, SSNs → detected and scrubbed before disk.
4. **Clipboard is metadata-only.** Types, size, entropy score, SHA-256 hash. Raw content opt-in with 24h retention.
5. **Observation ≠ Action.** OpenMimic observes only. It never types, clicks, sends, or modifies anything. (Until the agent executes, which requires explicit human approval.)
6. **Data/Instruction boundary.** VLM prompts strictly separate observed data from processing instructions. Prompt injection detection on captured text.
7. **User controls everything.** Can pause/stop at any time. Can delete any observation. Can exclude apps or websites. Can wipe entire knowledge base.

### Privacy Zoning

Not all apps and contexts deserve the same observation level. Users need fine-grained control over what gets captured, with sensible defaults that respect sensitive boundaries.

**Observation tiers per app/context:**

| Tier | What's Captured | Default For |
|------|----------------|-------------|
| **Full observation** | Screenshots, DOM, clipboard, accessibility tree, all events | Work apps (IDE, browser work profile, terminal) |
| **Metadata only** | App name, window title, timestamps, duration — NO screenshots or content | Personal browser profile, social media, messaging |
| **Blocked** | Nothing. App is invisible to OpenMimic. | Banking apps, HR tools, medical portals, password managers |
| **Temporary pause** | Global pause — nothing captured from any app | Activated manually or via schedule (e.g., "pause during lunch") |

**Default blocked list (out of the box):**
- Banking and finance apps (detected by bundle ID and URL patterns)
- Password managers (1Password, Bitwarden, LastPass, etc.)
- Health/medical portals
- HR and payroll systems
- Any app the user adds to the blocklist

**Browser-specific zoning:**
- Work profile → full observation
- Personal profile → metadata only (can be promoted by user)
- Incognito/private windows → always blocked
- Specific URL patterns can be blocked: `*bank*`, `*.gov/*`, user-defined patterns

**Context-sensitive escalation:**
- If user opens production console (detected by URL pattern), auto-elevate caution: metadata-only unless user has explicitly allowed
- Customer data screens: detect PII-heavy pages (forms with name/email/phone fields) and reduce to metadata-only

**Configuration:**

```toml
[privacy.zones]
# Per-app observation level
full_observation = ["com.apple.Terminal", "com.microsoft.VSCode", "com.google.Chrome.work"]
metadata_only = ["com.tinyspeck.slackmacgap", "com.google.Chrome.personal"]
blocked = ["com.1password.*", "com.apple.Safari.banking"]

# URL pattern blocking (applies to all browsers)
blocked_urls = ["*bank*", "*.gov/*", "payroll.*", "hr.*"]

# Temporary pause schedule
auto_pause = ["12:00-13:00"]  # Lunch break
```

### Redaction Pipeline

```
Capture → Tier -1: Privacy zone check (blocked apps/URLs → hard skip)
        → Tier 0: Hard drop (password fields, secure text inputs)
        → Tier 1: Inline redaction (API keys, AWS tokens, credit cards, private keys)
        → Tier 2: Idle deep scan (OCR-free regex over DOM/AX trees)
        → Disk (Zstd compress → XChaCha20-Poly1305 encrypt → atomic write)
```

### Agent Execution Security

When an agent eventually executes procedures:
- Constraints enforced at execution time (spending limits, contact restrictions)
- Irreversible actions require human approval
- All agent actions logged (separate from human observations)
- Agent cannot modify its own constraints or trust levels
- Kill switch: human can halt all agent execution instantly

---

## 13. Configuration

```toml
# ~/.openmimic/config.toml

[observer]
t_dwell_seconds = 3
screenshot_scale = 0.5
dhash_threshold = 10
multi_monitor_mode = "focused_window"

[privacy]
enable_inline_secret_redaction = true
enable_clipboard_preview = false
secure_field_drop = true

[vlm]
enabled = true
annotation_model = "qwen3.5:2b"
sop_model = "qwen3.5:4b"
max_jobs_per_day = 50
max_compute_minutes_per_day = 20

[knowledge]                          # NEW
daily_batch_enabled = true
daily_batch_time = "23:00"           # Process at end of day
profile_update_frequency = "daily"
pattern_detection_min_days = 7       # Need 7 days before detecting patterns
decision_extraction_min_observations = 3

[trust]                              # NEW
default_new_procedure = "observe"    # observe | suggest | draft | approve | autonomous
auto_promote_after_observations = 5  # Suggest promotion after N successful observations
auto_promote_max_level = "draft"     # Never auto-promote above this level

[constraints]                        # NEW
max_spend_usd_without_approval = 100
allow_external_communication = false
allow_file_deletion = false
```

---

## 14. Metrics and Success Criteria

### For the Product

| Metric | Target |
|--------|--------|
| Procedures learned after 1 week | 10-20 |
| Procedures learned after 1 month | 30-50 |
| Decision rules inferred after 1 month | 5-10 |
| Profile completeness after 1 week | 60% of fields populated |
| Agent execution success rate (approved tasks) | > 90% |
| Human correction rate (first month) | < 20% of agent executions need correction |
| Human correction rate (third month) | < 5% |
| Daily active observation hours | 6-10 hours (working day) |
| Knowledge base size after 3 months | < 50MB |
| CPU usage (daemon) | < 1% |
| CPU usage (worker, idle processing) | < 30% |

### For Individual Procedures

| Metric | Description |
|--------|-------------|
| Observation count | How many times this procedure has been seen |
| Step consistency | How stable the steps are across observations |
| Decision confidence | How well the branching rules predict human choices |
| Branch coverage | What % of observed branches are captured in the procedure |
| Agent success rate | How often the agent executes correctly |
| Time saved per execution | Duration when human does it vs when agent does it |
| Trust level | Current delegation level for this procedure |
| Days since last observation | Staleness indicator — flag if > 30 days |
| Days since last confirmation | Human review freshness — flag if > 60 days |
| Drift signals | Count of detected changes since last confirmation |

### For Day-1 Metrics

| Metric | Target |
|--------|--------|
| Time to first useful output | < 1 hour (activity search or focus SOP) |
| Review time per micro-review card | < 10 seconds |
| Approval rate (micro-review) | > 70% (if lower, drafts are too noisy) |
| Search recall accuracy | > 80% of "what was I doing at X?" queries answered |

---

## 15. Build Roadmap

### Phase 0: Foundation (DONE)
- Daemon, storage, extension, CLI, basic observation

### Phase 1: SOP Pipeline (DONE)
- VLM annotation, frame diffs, SOP generation, export adapters
- Focus recording, passive discovery, dedup, linting

### Phase 2: Agent-First Knowledge Base + Day-1 Utility (NEXT)
1. Activity search and session recall (day-1 utility)
2. Extend machine procedure schema (outcomes, staleness, evidence, branches — base schema exists in `sop_schema.py`)
3. Interruption/resumption model in task segmenter
5. Branch and exception extraction (core, not deferred)
6. Privacy zoning (app tiers, URL blocking, auto-pause)
7. Micro-review UX (approve/reject in seconds)
8. Evidence transparency (link drafts to observations)
9. Daily batch processor (activity timeline, task boundaries)
10. User profile builder (inferred from observations)
11. Recurrence/trigger detection
12. Constraint system + trust levels

### Phase 3: Intelligence Layer
1. Decision extraction from multi-observation comparison
2. Outcome tracking (what changed, not just what was clicked)
3. Account/workspace awareness (tenant, environment, profile)
4. Cross-session task linking
5. Workflow evolution tracking + staleness/drift detection
6. Error recovery pattern detection
7. Task chain discovery

### Phase 4: Agent Execution Loop
1. Agent query API (local)
2. Execution monitoring (observe agent's actions)
3. Correction feedback loop
4. Trust level auto-promotion based on success rate
5. Staleness-triggered trust demotion
6. Daily digest for human oversight

### Phase 5: Scale and Polish
1. Multiple agent framework adapters
2. Knowledge base sync (across machines)
3. Team knowledge sharing (opt-in, privacy-preserving)
4. Custom training data export (fine-tune personal models)

---

## 16. Key Design Principles

1. **Agent-first, human-friendly.** Every piece of data is structured for machine consumption first. Human-readable views are derived, not primary.

2. **Learn by watching, not by asking.** The user never fills out forms or answers questions. Everything is inferred from observation. The only human inputs are: start/stop recording, approve/reject, correct mistakes.

3. **Confidence grows over time.** Nothing is trusted on first observation. Procedures start as drafts with low confidence. Each additional observation, each human approval, each successful agent execution increases confidence.

4. **Quality over quantity.** Don't SOP everything. A user's day has hundreds of micro-actions. Only extract procedures for tasks that are repeated, take meaningful time, and have clear structure. 50 high-confidence procedures are worth more than 500 noisy ones.

5. **Local-first, private by default.** All data stays on the machine. All processing happens locally. No cloud, no telemetry, no sharing unless explicitly configured.

6. **Portable knowledge.** The knowledge base is not locked to any agent framework. It's structured JSON that any system can read. Export adapters are thin wrappers, not the core format.

7. **Corrections are gold.** When a human fixes what the agent got wrong, that single correction carries more signal than 10 passive observations. The system should make corrections easy and learning from them immediate.

8. **Graceful degradation.** If VLM is unavailable, fall back to heuristic processing. If the worker crashes, events are safely queued in SQLite. If the extension disconnects, native observation continues. Nothing is lost.

9. **Real work is messy.** Laptop work is fragmented, interrupt-driven, context-switching, exception-heavy, and always changing. The system must embrace this reality — not assume clean linear sessions. Interruptions, branches, and abandoned tasks are the norm, not edge cases.

10. **Day-1 value, month-1 power.** Users get immediate utility (search, recall, first SOP) before the system accumulates enough data for pattern detection, decision extraction, and autonomous execution. Never gate all value behind long-term learning.

11. **Show your work.** Every piece of inferred knowledge links back to the observations that generated it. Users must be able to see why OpenMimic learned something, inspect the evidence, and override when it's wrong. Trust requires transparency.

12. **Respect boundaries by default.** Privacy zoning, blocked apps, and sensitive context detection are out-of-the-box features, not opt-in configurations. The system must be safe before it is useful.
