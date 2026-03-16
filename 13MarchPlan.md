# AgentHandover Workflow Compiler Program Plan

## Summary

AgentHandover should be built as a **workflow compiler**, not as a better SOP generator. The product goal is: observe a messy human workday, separate signal from noise, recover full task continuity across interruptions, induce stable reusable procedures, let humans curate and promote them, and then hand agents a **truthful, executable bundle** that matches the human's real workflow.

This plan assumes:
- **Full-product scope**, not worker-only. That includes capture enrichment, worker logic, knowledge model, query/API contract, export targets, and human curation surfaces.
- **Moonshot target**, but delivered in staged gates so the system becomes truthful before it becomes ambitious.
- **Delivery-aware plan**, with sequencing, acceptance criteria, no-ship conditions, and rough resourcing.

The current repo already has the right spine in [task_segmenter.py](/Users/sandroandric/Desktop/openmimic/worker/src/oc_apprentice_worker/task_segmenter.py#L1), [procedure_schema.py](/Users/sandroandric/Desktop/openmimic/worker/src/oc_apprentice_worker/procedure_schema.py#L1), and [query_api.py](/Users/sandroandric/Desktop/openmimic/worker/src/oc_apprentice_worker/query_api.py#L232). The plan below strengthens those seams instead of replacing them with a parallel architecture.

## Program Rules

- **Truth before intelligence.** No new learning features ship on top of misleading readiness, weak freshness enforcement, or adapter mismatch.
- **One canonical procedure bundle.** All exports for Codex/OpenClaw/Claude Code compile from the same resolved bundle, never from divergent template paths.
- **Lifecycle and trust stay separate.** Lifecycle answers "what maturity state is this procedure in?" Trust answers "what is the agent allowed to do with it?"
- **No silent auto-merge.** The system may suggest merges, but must not silently unify procedures until evidence is strong and/or a human approves.
- **No hard persistent task identity early.** Early continuity should be confidence-ranked and reversible; false merges are more damaging than duplicate spans.
- **No launch claims beyond the runtime contract.** `/ready`, preflight, freshness, UI labels, and exported artifacts must all mean the same thing.

## Canonical Product Model

The system should converge on six first-class objects.

1. **Observed Event Context**
Each captured event carries not only current annotation data, but enough context to distinguish work from noise and preserve continuity across interruptions. Required fields: `activity_type`, `learnability`, `classification_confidence`, `browser_profile_id`, `account_scope`, `privacy_zone`, `tab_lineage`, `source_app`, `session_span_hint`, and provenance of the classification.

2. **Task Span**
A task span is the recoverable unit of human work. It represents one likely end-to-end task, even if interrupted. Required fields: `span_id`, `goal_summary`, `continuity_confidence`, `state`, `parent_span_id`, `interruption_refs`, `supporting_event_ids`, `matched_procedure_candidates`, and `variant_context`.

3. **Canonical Procedure**
The existing v3 procedure remains the durable knowledge object, but it must become the only source of truth. It must be rich enough to hold inputs, outputs, environment requirements, expected outcomes, branches, staleness, evidence, recurrence, chain metadata, lifecycle state, trust level, and compiled outputs.

4. **Procedure Bundle**
This is the agent-facing resolved package. It combines the canonical procedure with readiness state, freshness, preflight results, constraints, provenance, export targets, and target-specific compiled artifacts. Agents should consume this, not raw procedures plus disconnected metadata.

5. **Curation Artifact**
This covers merge candidates, upgrade candidates, drift reports, repeated-work families, and review suggestions. It is not agent-facing by default; it is for the human who is shaping what the agents will get.

6. **Execution Record**
This records real agent runs against a procedure bundle: start, progress, deviation, failure, retries, outcome verification, escalation, and resulting effects on evidence/trust/freshness.

## Public Interfaces And Contract Changes

- The capture pipeline should add enriched event context fields to the observation payload rather than forcing the worker to infer everything from `what_doing`, app, and URL alone.
- The query API should expose four stable surfaces:
  - `GET /procedures` for searchable inventory and summaries.
  - `GET /bundle/:slug` for the single resolved handoff package.
  - `GET /ready` for procedures that are truly eligible for agent use under the current contract.
  - `GET /curation/*` for merge, upgrade, drift, family, and recurrence views.
- `/ready` must be split conceptually into `agent_ready` and `draftable`. Drafts may be candidate work products, but must not be presented as runnable unless the contract explicitly says "draft-only."
- Preflight must return only checks that were actually executed. Advisory metadata should be labeled advisory, not validation.
- Export targets must compile from the canonical procedure bundle and declare compile status, generated timestamp, target version, and checksum.

## Delivery Plan

### Phase A: Contract Stabilization

Fix the current truthfulness blockers before deeper feature work.
- Make `/ready` reflect the real execution contract. Draft procedures may remain discoverable, but not under an execution-ready surface.
- Make freshness a real execution gate, not a warning that still yields `can_execute=true`.
- Move the default OpenClaw path onto the same bundle/compiler path as the richer target writers.
- Make preflight truthful by labeling unvalidated environment data as advisory until true validation exists.
- Add contract tests that compare API readiness, preflight readiness, and export readiness for the same procedure.

**Acceptance criteria:** there is no test case where a draft or stale procedure is surfaced as executable, and all export targets read from the same resolved procedure bundle.

### Phase 0: Evaluation Harness And Replay Corpus

Build the measurement system before building more intelligence.
- Create a replay corpus of messy real workflows with interruptions, unrelated browsing, communication detours, and resumptions.
- Add ground truth for work vs noise, task boundaries, repeated workflow families, and procedure readiness.
- Expand end-to-end tests so they measure false-ready, false-merge, export parity, and continuity quality, not just whether the pipeline runs.
- Add a scorecard that every later phase must improve against.

**Acceptance criteria:** baseline metrics exist for task-boundary quality, work/noise classification, false-ready rate, export parity, and recurring-work clustering quality.

### Phase 1: Capture Enrichment And Policy Controls

Improve the raw evidence before trying to learn more from it.
- Enrich captured context with browser profile, stronger tab lineage, account hints, and privacy/source metadata. This likely requires daemon and extension payload changes, not just worker changes.
- Add user policy controls that let users mark apps, browser profiles, sites, and sources as `ignore`, `never learn`, `personal`, `work`, or `always include`.
- Introduce two explicit axes for classification:
  - `activity_type`: work, research, communication, setup, personal admin, entertainment, dead time, context switch.
  - `learnability`: ignore, context-only, candidate workflow, execution-relevant.
- Persist classification confidence and rationale source so the system can explain why an observation did or did not contribute to a learned workflow.

**Acceptance criteria:** the system can reliably exclude obvious noise, users can override classification, and every learned observation has provenance for why it counted.

### Phase 2: Continuity Graph And Task Spans

Recover real tasks from messy behavior without overcommitting to false identity.
- Replace purely local segmentation with a continuity layer that can classify a new segment as `continue`, `resume`, `branch`, `restart`, or `new task`.
- Build a continuity graph across interruptions, tab switches, app switches, and moderate time gaps.
- Keep continuity confidence-ranked and revisable rather than assigning irreversible persistent task IDs too early.
- Use procedure candidates only as supporting evidence for continuity, not as the primary truth source.
- Surface uncertainty: the system should know when it is unsure whether two segments are the same task.

**Acceptance criteria:** interruption-heavy workflows reconnect with materially better precision/recall than current app/intent/gap heuristics, and false merges remain below the agreed threshold.

### Phase 3: Canonical Bundle, Lifecycle, And Readiness Gate

This is the product spine. It should move earlier than heavy induction work.
- Keep the v3 procedure as the only durable knowledge object and extend it with explicit lifecycle state, trust state, compiled outputs, readiness summary, and provenance links.
- Separate lifecycle from trust:
  - Lifecycle: `observed`, `draft`, `reviewed`, `verified`, `agent_ready`, `stale`, `archived`.
  - Trust: `observe`, `suggest`, `draft`, `execute_with_approval`, `autonomous`.
- Introduce a bundle compiler that resolves one canonical procedure into target artifacts for Codex/OpenClaw/Claude Code with parity checks.
- Make readiness depend on lifecycle, trust, freshness, evidence sufficiency, constraints, and successful preflight.
- Ensure the human review path promotes procedures through lifecycle, not by mutating ad hoc export state.

**Acceptance criteria:** every target export comes from the same bundle, lifecycle and trust transitions are explicit and validated, and the same procedure yields the same readiness truth in UI, API, verifier, and export.

### Phase 4: Workflow Induction Quality

Once the contract is honest, improve what gets compiled.
- Replace simple positional alignment with semantic alignment across demonstrations.
- Detect workflow variants, extract parameters, preserve branches, and normalize stable structure from messy repeated observations.
- Infer typed inputs, outputs, preconditions, postconditions, and expected outcomes from accumulated evidence instead of leaving those mostly empty.
- Add evidence-weighted normalization so heavily repeated steps become canonical while rarer variants are preserved as branches or variant families.
- Prevent duplicate proliferation by preferring familying and candidate merges over generating near-identical procedures.

**Acceptance criteria:** repeated demonstrations of the same workflow converge into one procedure family with variants and typed parameters, rather than many similar drafts.

### Phase 5: Repeated-Work Meta Layer And Human Curation

Turn the backend signals into an actual product the human can use.
- Build a repeated-work dashboard that shows recurring workflows, merge candidates, drift, upgrade candidates, and procedure families.
- Expose why the system thinks procedures should merge or upgrade.
- Add human actions for merge, split, reject, snooze, archive, promote, demote, and re-observe.
- Show drift and freshness in plain language so users know when a procedure is likely outdated.
- Keep app, CLI, and API terminology aligned so the same objects and states exist everywhere.

**Acceptance criteria:** a human can understand what the system learned repeatedly, see where it is wrong or stale, and curate procedures into a cleaner agent-facing library.

### Phase 6: Runtime Validation And Execution Feedback

Only now should the system claim it is learning from agents, not just from humans.
- Implement true environment validation for required apps, known profiles/accounts, reachable URLs when appropriate, and prerequisite state.
- Add post-execution verification that uses observed outcomes to decide success, partial success, retry, or escalation.
- Feed execution outcomes back into evidence, trust advice, drift detection, and lifecycle state.
- Support escalation rules and demotion rules so repeated failures reduce readiness rather than silently accumulating.
- Make execution feedback a first-class contributor to procedure quality, not a side log.

**Acceptance criteria:** verified procedures improve or degrade based on actual agent runs, and repeated failures can reliably demote readiness or raise review requirements.

### Phase 7: Operational Hardening And Launch Packaging

This phase turns a strong system into a shippable one.
- Add performance budgets for classification, continuity, induction, and bundle compilation so idle-time processing stays practical.
- Add migration and compatibility rules for stored procedures, compiled outputs, and new event fields.
- Add product telemetry that is local-first and privacy-safe: false-ready rejections, review conversion, drift frequency, execution success, and time-to-agent-ready.
- Tighten onboarding so a new user can understand what is being captured, what is ignored, and when learned procedures become usable.
- Freeze launch claims to the strongest contract the product can actually satisfy.

**Acceptance criteria:** onboarding, capture, curation, and handoff all use the same terminology and the system can be shipped without overpromising.

## Delivery Mechanics

- **Track 1: Capture and context.** Owns daemon/extension payload changes, event enrichment, privacy/source metadata, and policy enforcement.
- **Track 2: Learning core.** Owns classification, continuity, induction, recurrence, drift, and procedure family logic.
- **Track 3: Handoff and product surfaces.** Owns canonical bundle, lifecycle/trust enforcement, exports, query API, review surfaces, and execution feedback.

Recommended staffing:
- **Minimum serious team:** 3 engineers, one per track, plus product/UX support for curation surfaces.
- **Solo founder path:** execute sequentially; expect the program to be materially slower and to prioritize truthfulness over breadth.
- **Rough timing:** 10-14 weeks to a truthful beta with contract stabilization through Phase 5 for a 3-person team; 20-32 weeks to the full moonshot including execution feedback and hardening. Solo path is roughly 2x to 3x slower.

## Test Plan

- **Replay tests:** messy multi-app workflows, interruptions, detours, entertainment noise, and resumptions.
- **Classification tests:** work vs non-work, learnability axis, policy overrides, privacy exclusions, and confidence fallback behavior.
- **Continuity tests:** tab switches, app switches, same-task resumptions, unrelated branches, long-gap restarts, and cross-day repeats.
- **Compiler parity tests:** same canonical procedure yields equivalent required fields and readiness semantics across OpenClaw, Claude Code, and generic skill output.
- **Readiness tests:** draft cannot be executable, stale cannot be executable, lifecycle/trust mismatch is rejected, false-ready is impossible in test fixtures.
- **Induction tests:** parameter extraction, branch preservation, evidence weighting, variant family creation, and no duplicate explosion.
- **Curation tests:** merge candidates, drift reports, upgrade suggestions, family grouping, reject/snooze flows, and no silent auto-merge.
- **Execution tests:** true preflight validation, outcome verification, retry/escalation behavior, trust advice, and demotion after repeated failure.
- **Launch tests:** first-week experience, onboarding clarity, export discoverability, review usability, and end-to-end "observe -> review -> hand to agent" flow.

## Beta And GA Gates

**Truthful Beta**
- Zero false-ready cases in automated tests.
- Export parity across all supported targets for required handoff fields.
- Work/noise precision high enough that obvious entertainment/dead-time is rarely learned.
- Continuity materially better than current local heuristics.
- Human can inspect recurring work, promote/demote procedures, and hand agents reviewed bundles.

**GA-Grade Moonshot**
- Strong task continuity across interruptions and moderate cross-session gaps.
- Stable variant handling and procedure family curation.
- Real runtime validation and post-execution verification.
- Execution feedback measurably improves procedure quality and trust decisions.
- Product copy and system behavior match exactly.

## Assumptions And Defaults

- OpenClaw, Codex-style consumers, and Claude Code remain first-class export targets.
- Human review remains mandatory before a procedure becomes `agent_ready`.
- The system remains local-first and privacy-preserving; no cloud dependency is introduced by this plan.
- Existing v3 procedure storage is retained and extended rather than replaced.
- The first public launch should be positioned as **truthful beta** unless execution feedback and runtime validation are fully operational.
- If a tradeoff appears between richer learning and preventing false-ready handoff, the plan chooses safety and truthfulness first.
