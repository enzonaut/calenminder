# Plan: Calenminder v1 (Apple-only) - calendar events + day-scoped tasks for iOS
**Created:** 2026-07-03
**Status:** in-progress
**Started:** 2026-07-03 (feature branch: feature/calenminder-v1)
**Current Phase:** 5
**Complexity:** medium
---
## Context
Non-time-sensitive to-dos currently get faked as timed calendar events.
Calenminder makes the Event/Task distinction first-class: Apple Calendar events (EventKit, full CRUD, participation status view-only) alongside day-scoped completable tasks (EKReminders), in one agenda and on the Lock Screen.
Requirements doc: `.code-foundations/research/2026-07-01-calenminder-requirements.md` (confirmed 2026-07-01, revised 2026-07-03: Google Calendar dropped; v1 ships without RSVP).
Supersedes `2026-07-01-calenminder-v1.md`.

Success criteria: Apple Calendar events visible/editable in one agenda; tasks creatable, recurring weekly, completable, rolled over daily; Lock Screen widget shows today's accepted/tentative events plus incomplete tasks and completes a task with one tap; declined events excluded.

## Constraints
- Native iOS 17+ minimum, Swift + SwiftUI; iOS 18 Controls availability-gated.
- EventKit is the only event source; no networking layer at all in v1.
- No RSVP actions anywhere; participation status is read-only (EventKit API limit); no private API ever.
- Tasks are EKReminders in a dedicated list; no parallel local task store.
- Lock Screen interaction is tap-to-complete via `Button(intent:)`; swipe gestures are impossible in WidgetKit.
- Persist `calendarItemExternalIdentifier` + occurrence date for durable references, never bare `eventIdentifier`.

## Chosen Approach
**EventKit-native with thin protocol seams** -- EventKit is queried live as the single source of truth (it is the local cache; the OS owns sync); `EventStoring`/`TaskStoring` protocols wrap it so agenda/filter logic tests run against fakes; an `AgendaService` in the shared target assembles day-window snapshots for both app and widget.
Rationale: zero duplicated state, no sync engine to build, the OS handles offline and conflicts.
**Fallback:** if live queries prove too slow for widget timelines, persist the day snapshot to the App Group container without changing store contracts.

## Rejected Approaches
- **Canonical mirror store:** re-mirrors a database that is already local; pure overhead with a single provider.
- **Direct iCloud CalDAV client (for RSVP):** rejected 2026-07-03 with the Google integration; RSVP is not worth the app's largest component (user-confirmed).

---
## Implementation Phases

### Phase 1: Scaffold + risk spike
**Model:** sonnet
**Skills:** cc-pseudocode-programming
**Gate:** Standard

**Goal:** Stand up the multi-target Xcode workspace and empirically resolve the one unverified platform assumption: a widget-extension `Button(intent:)` can mark an EKReminder complete.

**Scope:**
- IN: Xcode project; targets: app, WidgetKit extension, `CalenminderIntents` shared intents target, shared framework/package for cross-target code (layout per `docs/code-standards.md` File Organization); App Group + entitlements; Reminders/Calendars usage-description keys in BOTH app and widget Info.plists; Swift Testing unit-test target; spike widget with a hardcoded `Button(intent:)` completing a test reminder.
- OUT: real UI, domain models, stores.

**Constraints:** spike uses only public API; main app must request Reminders full access before the widget spike runs (widgets cannot prompt).
**Edge cases:** spike verdict on locked device (Face ID gate) vs unlocked; permission-denied placeholder rendering in widget (resolved by Phase 5 DW-5.4; noted here only as spike observation).

**Approach notes:** Spike-first ordering is deliberate -- the verdict changes Phase 5's interaction contract (tap-to-complete vs deep-link fallback).
**File hints:** repo root -- greenfield; establish layout from `docs/code-standards.md` File Organization.
**Depends on:** none | **Unlocks:** Phases 2, 5 (spike verdict)
**Produces:** building workspace; shared App Group identifier constant exposed from the shared target; spike verdict (`widgetCanWriteReminders: true/false`) recorded in Execution Log and consumed by Phase 5.

**Done when:**
- [ ] DW-1.1: all targets build and unit-test target runs on an iOS 17 simulator
- [ ] DW-1.2: spike executed on simulator or device; verdict + evidence (screenshot/log) recorded in Execution Log
- [ ] DW-1.3: both Info.plists carry `NSRemindersFullAccessUsageDescription` and `NSCalendarsFullAccessUsageDescription`

**Difficulty:** MEDIUM
**Uncertainty:** spike may fail -> Phase 5 rows become deep links; no other phase changes.

### Phase 2: Domain core
**Model:** opus
**Skills:** ca-architecture-boundaries, aposd-designing-deep-modules
**Gate:** Full

**Goal:** Pure domain layer: canonical models, store protocols, and agenda assembly/filter logic -- no I/O imports anywhere.

**Scope:**
- IN: `Event` (canonical, with `externalIdentifier` + occurrence date, read-only participation status), `Task` (day-scoped, completable, weekly recurrence), `EventStoring` + `TaskStoring` protocols, pure agenda assembly (chronological interleave, day-window membership, overdue-task rollover) with TWO named status filters -- `.agenda` (declined excluded; needsAction kept, marked pending) for in-app, `.widget` (accepted/tentative only) for the Lock Screen -- and a day-window value type.
- OUT: EventKit implementation, persistence, UI.

**Constraints:** Domain imports nothing internal and no EventKit/UIKit/networking frameworks; "Event"/"Task" naming per `docs/code-standards.md`.
**Edge cases:** all-day vs timed events in day-window membership; participation-status boundary values per filter (`.agenda`: declined excluded, needsAction kept-as-pending; `.widget`: accepted/tentative only); task due-day comparison across timezones/DST.

**Approach notes:** The two protocols below are the pinned seam -- Phase 3 implements them verbatim, Phases 4/5 consume them. Internal refinement allowed only if all phases update together.
**File hints:** `Calenminder/Domain/` -- per standards layout.
**Depends on:** Phase 1 | **Unlocks:** Phases 3, 4
**Produces:** compiled Domain module: `Event`, `Task`, agenda assembly pure functions with the two named status filters (`AgendaFilter.agenda` / `AgendaFilter.widget`), and this contract:

```swift
protocol EventStoring {
    var changes: AsyncStream<Void> { get }             // coarse change signal
    func events(in window: DayWindow) async throws -> [Event]
    func create(_ draft: EventDraft) async throws -> Event
    func update(_ event: Event, span: EditSpan) async throws        // .thisEvent | .futureEvents
    func delete(_ event: Event, span: EditSpan) async throws
}
protocol TaskStoring {
    var changes: AsyncStream<Void> { get }
    func tasks(dueOn day: DayStamp, includeCompleted: Bool) async throws -> [Task]
    func incompleteTasks(overdueAsOf day: DayStamp) async throws -> [Task]  // unbounded lookback for rollover display
    func add(_ draft: TaskDraft) async throws -> Task
    func setCompleted(_ task: Task, _ completed: Bool) async throws
}
```

**Done when:**
- [ ] DW-2.1: Domain target compiles with zero imports of EventKit/UIKit/networking
- [ ] DW-2.2: agenda assembly covered by table-driven tests (interleave order, declined excluded, completed-task exclusion, overdue rollover)
- [ ] DW-2.3: day-membership and status predicates covered by boundary tests (midnight, all-day, DST transition, each participation status)

**Difficulty:** LOW
**Uncertainty:** None.

### Phase 3: EventKit stores
**Model:** sonnet
**Skills:** aposd-designing-deep-modules
**Gate:** Standard

**Goal:** EventKit-backed implementations of both Domain protocols: live event queries/CRUD and EKReminder-backed tasks.

**Scope:**
- IN: permission flow (`requestFullAccessToEvents`/`...ToReminders`); day-window event queries; event create/update/delete with `EKSpan`; detached-occurrence correctness; `ReminderTaskStore` on a dedicated Reminders list (date-only `dueDateComponents`, weekly `EKRecurrenceRule`, complete/uncomplete, overdue lookback via `predicateForIncompleteReminders(withDueDateStarting:ending:)`); republishing `EKEventStoreChanged` as the `changes` stream; `refreshSourcesIfNecessary()` on foreground.
- OUT: RSVP (does not exist in v1), UI.

**Constraints:** persist `calendarItemExternalIdentifier` + occurrence date, never bare `eventIdentifier`; reminders fetching is async/predicate-only; Gregorian calendar for `dueDateComponents`; no deprecated `requestAccess(to:)`.
**Edge cases:** permission denied or write-only -> typed failure surfaced, never silent; reminder completed by another client can have `isCompleted == true` with nil `completionDate`; only one recurrence rule honored per reminder; event moved between calendars changes `eventIdentifier`; deleted-underneath detection via `refresh() == false`.

**File hints:** `Calenminder/Store/` -- per standards layout.
**Depends on:** Phase 2 | **Unlocks:** Phase 4
**Produces:** `EventKitEventStore: EventStoring` and `ReminderTaskStore: TaskStoring`, both usable from app and widget processes.
**Rollback:** event/task deletes act on the user's live system stores with no programmatic undo -- destructive paths require the Phase 4 confirmation UI; this phase performs no migrations and nothing else irreversible.

**Done when:**
- [ ] DW-3.1: protocol conformance tests pass against a seeded fixture-store abstraction (day-window fetch, overdue lookback, span edits, typed permission errors)
- [ ] DW-3.2: recurring edit spans and detached occurrences verified (series edit does not clobber a detached occurrence)
- [ ] DW-3.3: task lifecycle (create date-only, recur weekly, complete, uncomplete) verified on simulator against the real Reminders store
- [ ] DW-3.4: permission-denied and write-only paths produce typed errors with recovery guidance

**Difficulty:** MEDIUM
**Uncertainty:** system-store integration tests may be flaky in CI -> simulator-only test tag, run serially.

### Phase 4: Agenda service + app UI
**Model:** sonnet
**Skills:** aposd-designing-deep-modules, ca-architecture-boundaries
**Gate:** Full

**Goal:** The agenda coordinator over both stores, and the full SwiftUI app around it.

**Scope:**
- IN: `AgendaService` (serves day-window agenda snapshots via Domain assembly functions, listens to store change streams, refreshes on foreground, calls `WidgetCenter.reloadTimelines` after mutations); agenda view (timed events interleaved chronologically, tasks in a day section); event detail (shows read-only participation status) and edit with span picker; task add/complete/uncomplete; overdue-task rollover display; calendar visibility toggles; permission onboarding flow; deep-link routing (event/task detail).
- OUT: widget UI (Phase 5), RSVP (does not exist), store-review polish.

**Constraints:** UI reads only through `AgendaService`; in-app agenda uses `AgendaFilter.agenda` (declined excluded, pending invites shown with a pending marker; declined visible only on invite detail).
**Edge cases:** midnight rollover while app foregrounded; edit failure rolls back optimistic state with error surfaced; deep link with malformed or unknown/deleted ID shows a not-found state, never crashes.

**Approach notes:** AgendaService is shared-target code so the Phase 5 widget calls the same API.
**File hints:** `Calenminder/Agenda/`, `Calenminder/UI/` -- per standards layout.
**Depends on:** Phases 2, 3 | **Unlocks:** Phase 5
**Produces:** `AgendaService.agenda(for: DayWindow, filter: AgendaFilter) -> AgendaSnapshot` (events + tasks, filtered) in the shared target; deep-link URL scheme; complete app UI.
**Security-sensitive:** yes -- deep-link URLs are untrusted, externally-triggerable input.
**Rollback:** store deletes are gated behind a confirmation dialog; failed edit mutations roll back their optimistic UI state.

**Done when:**
- [ ] DW-4.1: AgendaService assembly/filter behavior covered by tests against fake stores
- [ ] DW-4.2: full flows verified on simulator: create/edit/delete event (both spans); create/complete recurring task; calendar toggles
- [ ] DW-4.3: view models unit-tested; agenda + detail + onboarding covered by snapshot/UI tests
- [ ] DW-4.4: malformed and unknown-ID deep links land on a not-found state without crashing

**Difficulty:** MEDIUM
**Uncertainty:** declined-event presentation is a taste call -> ship the stated default, revisit after use.

### Phase 5: Widget + App Intents
**Model:** sonnet
**Skills:** cc-pseudocode-programming
**Gate:** Standard

**Goal:** Lock Screen and Home Screen widgets showing today's accepted/tentative events and incomplete tasks, with one-tap task completion.

**Scope:**
- IN: `accessoryRectangular` + `systemSmall`/`systemMedium` families; timeline provider reading `AgendaSnapshot` via shared target; per-row checkmark `Button(intent: CompleteTaskIntent)` (if Phase 1 verdict true) or deep-link rows (if false); event rows deep-link; midnight-boundary timeline entries; permission-missing placeholder; reload triggers (app foreground, post-mutation, post-intent); iOS 18 `ControlWidgetButton` "add task" behind availability check (best-effort, explicitly non-blocking for the phase gate).
- OUT: Live Activities, iOS 26 push reloads, watchOS/macOS widgets, configurable widget intents beyond defaults.

**Constraints:** widget uses `AgendaFilter.widget` (accepted/tentative only; declined and needsAction never render); only `Button`/`Toggle`/`Link`/`widgetURL` interaction primitives (no gesture modifiers -- they silently no-op); tap targets sized per HIG; widget Info.plist carries EventKit usage keys (from Phase 1).
**Edge cases:** empty states (no events, no tasks, both); more items than rows -> overflow count; day rollover at midnight without a reload; `CompleteTaskIntent` fired for a task deleted or already completed elsewhere (stale cached timeline) -> graceful no-op + timeline reload, never a crash or error dialog.

**Approach notes:** Phase 1 spike verdict selects the row interaction; both variants keep identical layout so the swap is contained.
**File hints:** `CalenminderWidget/`, `CalenminderIntents/` -- per standards layout.
**Depends on:** Phases 4, 1 | **Unlocks:** none (terminal)
**Produces:** shipping widget extension + `CompleteTaskIntent`/deep-link routes -- the user-observable Lock Screen deliverable.

**Done when:**
- [ ] DW-5.1: Lock Screen widget renders today's accepted/tentative events + incomplete tasks on simulator; declined, needsAction, and completed items absent
- [ ] DW-5.2: tapping the row checkmark completes the task and the widget updates without app launch (or documented deep-link fallback if spike verdict was false)
- [ ] DW-5.3: midnight rollover produces tomorrow's entries without manual refresh
- [ ] DW-5.4: empty, overflow, and permission-missing states render correctly (snapshot tests)
- [ ] DW-5.5: `CompleteTaskIntent` on a stale (deleted/already-completed) task id is a graceful no-op that reloads the timeline

**Difficulty:** MEDIUM
**Uncertainty:** None beyond the Phase 1 verdict, already bounded.

---
## Test Coverage
**Level:** High on logic, pragmatic on UI (user-chosen 2026-07-01): ~100% on Domain, agenda, and store logic via fakes; view models unit-tested; thin SwiftUI views and widget layouts verified by snapshot/UI tests, not exhaustively.

## Test Plan
Build/static checks:
- [ ] T-1.2 (DW-1.1, DW-1.3): CI script builds all targets + runs unit tests on iOS 17 simulator; static check asserts both Info.plists carry the EventKit usage-description keys
- [ ] T-2.4 (DW-2.1): static import check -- Domain sources contain no EventKit/UIKit/networking imports

Unit (fakes, no I/O):
- [ ] T-2.1 (DW-2.2): agenda assembly table -- chronological interleave, declined excluded, completed tasks excluded, overdue rollover included
- [ ] T-2.2 (DW-2.3): boundaries -- event ending 00:00, starting 23:59, all-day, DST spring-forward/fall-back day; task due-day across timezone/DST; every participation status through BOTH filters (`.agenda`: accepted/tentative/needsAction kept, declined excluded; `.widget`: accepted/tentative only)
- [ ] T-2.3 (dirty): event with missing/garbled identifiers -> excluded gracefully, no crash
- [ ] T-3.1 (DW-3.1, DW-3.4): store conformance against fixture store -- day-window fetch, overdue lookback, span edits, typed permission-denied/write-only errors
- [ ] T-3.2 (dirty): reminder completed elsewhere with nil `completionDate`; second recurrence rule silently dropped; `refresh() == false` (deleted underneath); event moved between calendars (external-identifier re-resolution)
- [ ] T-4.1 (DW-4.1): AgendaService assembly/filter against fake stores; change-stream triggers re-query
- [ ] T-4.2 (dirty): store throwing mid-assembly -> partial agenda + error state, never empty-silent
- [ ] T-4.5 (dirty): edit mutation failure rolls back optimistic UI state and surfaces the error
- [ ] T-4.6 (DW-4.4, dirty): malformed and unknown/deleted-ID deep links -> not-found state, no crash
- [ ] T-4.3 (DW-4.3): view-model unit tests; agenda/detail/onboarding snapshot or UI tests

Integration (simulator):
- [ ] T-3.3 (DW-3.2, DW-3.3): recurring spans + detached occurrences and task lifecycle against real Reminders/Calendar stores
- [ ] T-4.4 (DW-4.2): end-to-end CRUD/task flows; midnight rollover while app foregrounded
- [ ] T-5.1 (DW-5.1, DW-5.4): widget snapshot tests -- populated, empty, overflow, permission-missing, declined and needsAction absent
- [ ] T-5.4 (DW-5.5, dirty): `CompleteTaskIntent` with a deleted and an already-completed task id -> no-op + timeline reload, no crash

Manual (device):
- [ ] T-1.1 (DW-1.2): spike verdict, locked + unlocked
- [ ] T-5.2 (DW-5.2): Lock Screen tap-to-complete end-to-end
- [ ] T-5.3 (DW-5.3): midnight rollover overnight check

---
## Assumptions
| Assumption | Confidence | Verify Before Phase | Fallback If Wrong |
|---|---|---|---|
| Widget-extension intent can write EKReminders | Medium-high (unofficial) | Phase 1 spike | Phase 5 rows deep-link into app |
| Completing a recurring EKReminder rolls to next occurrence system-side | Medium | Phase 3 (T-3.3) | ReminderTaskStore generates next occurrence itself |
| Live EventKit queries fast/fresh enough for widget timelines | High | Phase 5 | Persist day snapshot to App Group cache (Chosen Approach fallback) |

## Decision Log
| Decision | Alternatives Considered | Rationale | Phase |
|---|---|---|---|
| EventKit-native, thin protocol seams | Canonical mirror store | Zero duplicated state; OS owns sync/offline | all |
| Apple Calendar only (2026-07-03) | Google direct REST + OAuth (original plan) | User dropped Google; removes OAuth/sync-engine complexity | all |
| No RSVP in v1 (2026-07-03) | iCloud CalDAV client | EventKit cannot RSVP; CalDAV client not worth it (user-confirmed) | 4 |
| Tasks as EKReminders | SwiftData + CloudKit model | Native fit, free sync/Siri; Reminders visibility accepted | 3 |
| Spike-first phase ordering | Spike inside Phase 5 | Verdict changes Phase 5's interaction contract | 1 |

---
## Notes
- EventKit integration tests hit the simulator's real system store -- simulator-only test tag, run serially, keep out of parallel unit-test invocations.
- Recurrence guard test (series edit preserves detached occurrence) is mandatory per code-standards (T-3.3).
- Declined-event presentation default: excluded from agenda, visible on invite detail (Phase 4 uncertainty note).
- needsAction (pending) invites: shown in-app with a pending marker, excluded from the widget (`AgendaFilter.agenda` vs `.widget`) -- default taken 2026-07-03, user notified.
- No Google prerequisites remain; the build needs no external accounts or credentials.
- If the user later revives Google or RSVP, the superseded 2026-07-01 plan holds the researched sync-engine design (mirror + pending-op queue + etag merge).
---
## Execution Log

### Phase 1: Scaffold + risk spike (Gate: Standard)
- [x] BUILD: Discovery + design + implementation (stub -> implement -> validate) complete
- [x] REVIEW: Verification passed
- [x] Committed
Commit: e8ad2c6
Summary: 5-target Xcode workspace (app, CalenminderKit shared framework, CalenminderIntents, widget extension, Swift Testing tests) builds and tests green via XcodeGen/Makefile; spike verdict widgetCanWriteReminders: true (widget Button(intent:) completes an EKReminder), with the constraint that widget-invoked intents must be declared inside the widget target, not a shared framework.

### Phase 2: Domain core (Gate: Full)
- [x] BUILD: Discovery + design + implementation (stub -> implement -> validate) complete
- [x] REVIEW: Verification passed
- [x] Committed
Commit: 37322f3
Summary: Pure Domain layer in CalenminderKit/Domain/ - Event/DayTask models (task type deliberately spelled DayTask to dodge _Concurrency.Task), DayStamp/DayWindow civil-date types, the pinned EventStoring/TaskStoring protocols exactly as planned, and assembleAgenda with AgendaFilter.agenda/.widget; 44/44 tests green, import boundary enforced by in-suite scan + scripts/check-domain-imports.sh.

### Phase 3: EventKit stores (Gate: Standard)
- [x] BUILD: Discovery + design + implementation (stub -> implement -> validate) complete
- [x] REVIEW: Verification passed
- [x] Committed
Commit: 1cf1bad
Summary: EventKitEventStore + ReminderTaskStore implement the Domain protocols verbatim over an internal DTO provider seam (fixture-testable); durable refs are (externalIdentifier, occurrenceDate); 78 unit + 5 integration tests green; assumption settled: EventKit auto-advances completed recurring reminders, so setCompleted is a pass-through (no app-side rollover).

### Phase 4: Agenda service + app UI (Gate: Full, security-sensitive)
- [x] BUILD: Discovery + design + implementation (stub -> implement -> validate) complete
- [x] REVIEW: 3-sample majority PASS; sample 2 FAIL (midnight rollover while foregrounded unhandled) -> fixed (isFollowingToday + NSCalendarDayChanged in AgendaViewModel, 5 new tests) -> re-verified PASS (unanimous)
- [x] Committed
Commit: a951615
Summary: AgendaService.agenda(for:filter:) in CalenminderKit/Agenda/ is the single read path (assembly, filters, change-stream merge, widget reloads); full app UI shipped (agenda, event detail/edit with spans, tasks, calendar toggles, onboarding, defensively parsed calenminder:// deep links); AgendaViewModel owns optimistic rollback and follows today across midnight; 158 unit + 9 integration tests green.

### Phase 1 details (2026-07-03)

**Spike verdict: `widgetCanWriteReminders: true`.**

A `Button(intent:)` fired from the widget extension process CAN mark an `EKReminder` complete without launching the app, confirmed by a real tap on a real Home Screen widget on the iOS 26.5 simulator (iPhone 17 Pro), verified two independent ways: (1) the unified system log recorded `WidgetSpikeCompleteIntent` executing `perform()` and logging `spike outcome: success`; (2) relaunching the app showed "Last widget spike outcome: success" read back from the shared App Group `UserDefaults`, written by the widget extension process. Evidence (screenshots + full log trace) committed at `.code-foundations/build/phase-1-spike-evidence/`.

**Important packaging finding for Phase 5:** the first spike attempt declared the intent in the shared `CalenminderIntents` framework target (the plan's original "shared intents target" placement) and it did **not** work — the button absorbed taps but `perform()` never ran. The unified log showed `linkd` (the App Intents registry) reporting `Missing: com.enzonaut.calenminder:CompleteSpikeReminderIntent` even though the framework's own `Metadata.appintents` was present inside the extension bundle (confirmed via a controlled A/B test: an identical intent declared directly inside the `CalenminderWidget` extension target worked on the first real tap; the framework-declared one never fired across two separate rebuild+retest cycles, including after fixing framework embedding). **Conclusion: App Intents invoked by a widget's interactive `Button(intent:)` must be declared directly in the consuming widget extension target in this toolchain, not in a separate shared framework.** Phase 5 should declare `CompleteTaskIntent` directly in `CalenminderWidget`, not `CalenminderIntents` — or budget time to find/verify a cross-module registration workaround before relying on the original plan wording. `CalenminderIntents` remains scaffolded (plan's Phase 1 scope requires the target to exist) and hosts a documented-but-unwired example (`CompleteSpikeReminderIntent.swift`) demonstrating the finding; it may still be useful for non-button-invoked App Intents (Siri/Shortcuts from the app's own process) which was not tested here and should not be assumed safe without re-verification.

**Other notes:**
- No iOS 17 simulator runtime was installable in this sandbox (network-restricted; only iOS 26.5 was pre-installed). `IPHONEOS_DEPLOYMENT_TARGET = 17.0` is set on every target and all builds/tests ran against the iOS 26.5 simulator, which is backward-compatible the same way a real device on a newer OS would be. Re-verify on an actual iOS 17 simulator/device opportunistically in a later phase if one becomes available.
- Swift language mode set to **Swift 5** (not Swift 6 strict concurrency) project-wide: EventKit's completion-handler APIs are not Sendable-audited in this SDK, and fighting strict-concurrency region checks against an un-audited system framework was not worth the tax, especially with Phase 3's much heavier EventKit usage ahead. Revisit if Apple ships a Sendable-safe EventKit surface.
- `docs/code-standards.md` File Organization updated to add the `CalenminderKit/` shared framework target (holds cross-target code, starting with the App Group identifier constant `CalenminderKit.AppGroup.identifier`); `Domain/Store/Agenda` are planned to live there once Phase 2/3 populate them, though Phase 2 may need to split `Domain` into its own target for DW-2.1's "Domain target compiles with zero EventKit/UIKit/networking imports" to be enforceable at the target level rather than just by file-level convention — flagging for Phase 2 planning.
