# Plan: Calenminder v1 - unified calendar events + day-scoped tasks for iOS
**Created:** 2026-07-01
**Status:** superseded - replaced by `2026-07-03-calenminder-v1-apple-only.md` after the user dropped Google Calendar integration (2026-07-03); never executed
**Complexity:** complex
---
## Context
Non-time-sensitive to-dos currently get faked as timed calendar events.
There is no iOS app that shows real calendar events (Google + Apple, with CRUD and RSVP) alongside day-scoped completable tasks in one view and on the Lock Screen.
Calenminder makes the Event/Task distinction first-class.
Requirements doc: `.code-foundations/research/2026-07-01-calenminder-requirements.md` (confirmed 2026-07-01).

Success criteria: events from both providers visible/editable in one agenda with working Google RSVP; tasks creatable, recurring weekly, completable, rolled over daily; Lock Screen widget shows today's accepted/maybe events plus incomplete tasks and completes a task with one tap; offline edits never lost, conflicts resolved with etag-checked merge; dual-sourced Google accounts deduped.

## Constraints
- Native iOS 17+ minimum, Swift + SwiftUI; iOS 18 Controls and iOS 26 widget push are availability-gated enhancements.
- Google Calendar via direct REST API + GoogleSignIn OAuth (RSVP requires it); tokens in Keychain.
- Apple calendars via EventKit; RSVP unavailable there in v1 (read-only `participantStatus`); no private API ever (App Store safety).
- Tasks are EKReminders in a dedicated list; no parallel local task store.
- No backend; sync is poll-based (foreground + BGAppRefreshTask); Google `events.watch` out of scope.
- Lock Screen interaction is tap-to-complete via `Button(intent:)`; swipe gestures are impossible in WidgetKit.
- Google writes must use etag/If-Match optimistic concurrency; local mutations enter a durable pending-op queue before any network call.
- Persist `calendarItemExternalIdentifier` + occurrence date for EventKit references, never bare `eventIdentifier`.

## Chosen Approach
**B: Federated providers, merge-on-read** -- EventKit is queried live (it is already the local cache and the OS owns Apple-side sync); Google gets a local App Group mirror + durable pending-op queue + syncToken loop; a thin agenda service merges and dedupes per day window at read time; per-provider capability flags drive the UI (e.g. RSVP only where supported).
Rationale: no duplicated EventKit state, sync complexity concentrated where unavoidable, matches the proven Fantastical shape.
**Fallback:** if query-time merge proves too slow or stale for the widget, promote the merged day-window snapshot to a persisted App Group cache (a scoped slice of Approach A) without changing provider contracts.

## Rejected Approaches
- **A: Canonical mirror store:** re-mirrors EventKit (already a local system DB), doubling state and inheriting unstable-identifier reconciliation; right shape for server-backed multi-provider products, wrong for two providers where one is local.
- **C: EventKit as hub:** disqualified -- EventKit attendees are read-only, so mirrored Google events would silently lose attendee/RSVP data; duplicate-event and sync-loop hazards.

---
## Implementation Phases

### Phase 1: Scaffold + risk spike
**Model:** sonnet
**Skills:** none -- project scaffolding plus an empirical platform spike; no design/refactoring skill triggers match
**Gate:** Standard

**Goal:** Stand up the multi-target Xcode workspace and empirically resolve the one unverified platform assumption: a widget-extension `Button(intent:)` can mark an EKReminder complete.

**Scope:**
- IN: Xcode project; targets: app, WidgetKit extension, shared framework/package for cross-target code; App Group + entitlements; Reminders/Calendars usage-description keys in BOTH app and widget Info.plists; Swift Testing unit-test target; spike widget with a hardcoded `Button(intent:)` completing a test reminder.
- OUT: real UI, domain models, providers, any Google code.

**Constraints:** spike uses only public API; main app must request Reminders full access before the widget spike runs (widgets cannot prompt).
**Edge cases:** spike verdict on locked device (Face ID gate) vs unlocked; permission-denied placeholder rendering in widget.

**Approach notes:** Spike-first ordering is deliberate -- the verdict changes Phase 6's interaction contract (tap-to-complete vs deep-link fallback).
**File hints:** repo root -- greenfield; establish layout from `docs/code-standards.md` File Organization.
**Depends on:** none | **Unlocks:** Phase 2
**Produces:** building workspace; shared App Group identifier constant exposed from the shared target; spike verdict (`widgetCanWriteReminders: true/false`) recorded in Execution Log and consumed by Phase 6.

**Done when:**
- [ ] DW-1.1: all targets build and unit-test target runs on an iOS 17 simulator
- [ ] DW-1.2: spike executed on simulator or device; verdict + evidence (screenshot/log) recorded in Execution Log
- [ ] DW-1.3: both Info.plists carry `NSRemindersFullAccessUsageDescription` and `NSCalendarsFullAccessUsageDescription`

**Difficulty:** MEDIUM
**Uncertainty:** spike may fail -> Phase 6 rows become deep links; no other phase changes.

### Phase 2: Domain core
**Model:** opus
**Skills:** ca-architecture-boundaries, aposd-designing-deep-modules
**Gate:** Full

**Goal:** Pure domain layer: canonical models, provider protocols, and merge/dedupe logic -- no I/O imports anywhere.

**Scope:**
- IN: `Event` (canonical, with `providerEventID`/`providerCalendarID`/`externalIdentifier`, participation status, capability set e.g. `.rsvp`), `Task` (day-scoped, completable, weekly recurrence), `EventProviding` + `TaskStoring` protocols, pure agenda merge + dedupe-by-iCal-UID functions, day-window value type.
- OUT: any provider implementation, persistence, UI.

**Constraints:** Domain imports nothing internal and no EventKit/networking frameworks; "Event" and "Task" naming per `docs/code-standards.md`.
**Edge cases:** dedupe when same iCal UID appears in two calendars (invite copies -- keep both); all-day vs timed events in day-window membership; declined-status filtering as a pure predicate; task due-day comparison across timezones/DST.

**Approach notes:** Design-it-twice applies to supporting types; the two protocols below are the pinned seam -- Phases 3/4 implement them verbatim, Phase 5 consumes them. Internal refinement allowed only if all three phases update together.
**File hints:** `Calenminder/Domain/` -- per standards layout.
**Depends on:** Phase 1 | **Unlocks:** Phases 3, 4, 5
**Produces:** compiled Domain module: `Event`, `Task`, `AgendaMerge` pure functions, and this contract:

```swift
protocol EventProviding {
    var capabilities: Set<ProviderCapability> { get }  // contains .rsvp where supported
    var changes: AsyncStream<Void> { get }             // coarse change signal
    func events(in window: DayWindow) async throws -> [Event]
    func create(_ draft: EventDraft) async throws -> Event
    func update(_ event: Event, span: EditSpan) async throws        // .thisEvent | .futureEvents
    func delete(_ event: Event, span: EditSpan) async throws
    func respond(to event: Event, status: RSVPStatus, notify: SendUpdatesPolicy) async throws
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
- [ ] DW-2.2: table-driven merge/dedupe tests pass (dual-sourced event collapses; invite copies in two calendars do not)
- [ ] DW-2.3: declined-exclusion and day-membership predicates covered by boundary tests (midnight, all-day, DST transition)

**Difficulty:** MEDIUM
**Uncertainty:** None.

### Phase 3: EventKit provider
**Model:** sonnet
**Skills:** aposd-designing-deep-modules
**Gate:** Standard

**Goal:** EventKit-backed implementations of both Domain protocols: live event queries/CRUD and EKReminder-backed tasks.

**Scope:**
- IN: permission flow (`requestFullAccessToEvents`/`...ToReminders`); day-window event queries; event create/update/delete with `EKSpan` (.thisEvent/.futureEvents); detached-occurrence correctness; `ReminderTaskStore` on a dedicated Reminders list (date-only `dueDateComponents`, weekly `EKRecurrenceRule`, complete/uncomplete, overdue lookback via `predicateForIncompleteReminders(withDueDateStarting:ending:)`); republishing `EKEventStoreChanged` as a provider change signal; `refreshSourcesIfNecessary()` on foreground.
- OUT: RSVP (capability absent by design), Google anything, UI.

**Constraints:** persist `calendarItemExternalIdentifier` + occurrence date, never bare `eventIdentifier`; reminders fetching is async/predicate-only; Gregorian calendar for `dueDateComponents`; no deprecated `requestAccess(to:)`.
**Edge cases:** permission denied or write-only -> typed failure surfaced, never silent; reminder completed by another client can have `isCompleted == true` with nil `completionDate`; only one recurrence rule honored per reminder; event moved between calendars changes `eventIdentifier`; deleted-underneath detection via `refresh() == false`.

**Approach notes:** EventKit is queried live -- no mirror of Apple-side data (Chosen Approach B).
**File hints:** `Calenminder/Providers/EventKitProvider/` -- per standards layout.
**Depends on:** Phase 2 | **Unlocks:** Phase 5
**Produces:** `EventKitEventProvider: EventProviding` (capabilities exclude `.rsvp`; `respond` throws unsupported) and `ReminderTaskStore: TaskStoring`, both usable from app and widget processes.
**Rollback:** event/task deletes act on the user's live system stores with no programmatic undo -- destructive paths require the Phase 5 confirmation UI; this phase performs no migrations and nothing else irreversible.

**Done when:**
- [ ] DW-3.1: protocol conformance tests pass against a seeded in-memory/fixture store abstraction
- [ ] DW-3.2: recurring edit spans and detached occurrences verified (series edit does not clobber a detached occurrence)
- [ ] DW-3.3: task lifecycle (create date-only, recur weekly, complete, uncomplete) verified on simulator against the real Reminders store
- [ ] DW-3.4: permission-denied and write-only paths produce typed errors with recovery guidance

**Difficulty:** MEDIUM
**Uncertainty:** system-store integration tests may be flaky in CI -> isolate behind a simulator-only test tag.

### Phase 4: Google provider
**Model:** opus
**Skills:** aposd-designing-deep-modules
**Gate:** Full

**Goal:** Google-backed `EventProviding` implementation: OAuth, REST client, offline-first mirror + pending-op queue, syncToken incremental sync, etag-checked writes, RSVP.

**Scope:**
- IN: GoogleSignIn OAuth (scope `calendar.events`; tokens in Keychain); REST client; App Group mirror store keyed by Google event id storing resource + etag + updated; durable pending-op queue (mutations enqueue before network); syncToken loop (identical query params; 410 -> wipe mirror only, keep queue, full resync, replay); writes via sparse `patch` with `If-Match` (412 -> refetch, three-way merge, auto-rebase non-overlapping fields, retry; same-field conflict -> surfaced for user resolution); RSVP via own-attendee `responseStatus` with `sendUpdates`; recurrence stored master + exception children with client-side expansion; exponential backoff on 403/429.
- OUT: Google Tasks, watch channels/push, multi-Google-account (single account v1), UI.

**Constraints:** never write server-managed fields; `status: cancelled` stubs tombstone local rows; instance-level RSVP patches the instance id, series-level patches the master.
**Edge cases:** 410 mid-pagination; expired refresh token -> re-auth signal; all-day (`date`) vs timed (`dateTime`); DST-crossing RRULE expansion; exception-instance not treated as new event; series edit does not clobber exceptions; attendee-response bumps auto-rebase without prompting.

**File hints:** `Calenminder/Providers/Google/` -- per standards layout.
**Depends on:** Phase 2 | **Unlocks:** Phase 5
**Produces:** `GoogleEventProvider: EventProviding` with capabilities including `.rsvp`; a `PendingOperationQueue` whose durability Phase 5 relies on for offline UX.
**Security-sensitive:** yes -- OAuth token handling, Keychain storage, untrusted network input.
**Rollback:** the 410 mirror wipe is safe by design -- the mirror is derived state, the pending queue survives the wipe, and resync/replay is idempotent; remote deletes are user-initiated and confirmed in the Phase 5 UI.

**Done when:**
- [ ] DW-4.1: sync-loop state machine covered by table-driven tests against a fake transport (initial, incremental, paginated-incremental, 410 recovery preserving queue)
- [ ] DW-4.2: 412 conflict path verified: non-overlapping auto-merge, same-field conflict surfaced, no blind retry with stale etag
- [ ] DW-4.3: RSVP round-trip verified against the real API on a test calendar (accept/decline/tentative, instance + series)
- [ ] DW-4.4: force-quit/offline durability: enqueued mutation survives process kill and replays on next launch
- [ ] DW-4.5: RRULE expansion parity tests against `events.instances` results for weekly/DST fixtures

**Difficulty:** HIGH
**Uncertainty:** RRULE edge coverage is open-ended -> bound v1 expansion to rule shapes Google emits for user-created events; log-and-skip unsupported shapes rather than mis-render.

### Phase 5: Agenda service + app UI
**Model:** sonnet
**Skills:** aposd-designing-deep-modules, ca-architecture-boundaries
**Gate:** Full

**Goal:** The merge-on-read coordinator over both providers, and the full SwiftUI app around it.

**Scope:**
- IN: `AgendaService` (registers providers, serves day-window agenda snapshots, applies dedupe + declined-exclusion predicates from Domain, listens to provider change signals, triggers sync on foreground + `BGAppRefreshTask`, calls `WidgetCenter.reloadTimelines` after mutations); agenda view (timed events interleaved chronologically, tasks in a day section); event detail/edit with span picker; capability-gated RSVP buttons; task add/complete/uncomplete; overdue-task rollover display; accounts screen (Google sign-in/out, calendar visibility toggles); onboarding permission flow; deep-link routing (event/task detail).
- OUT: widget UI (Phase 6), Apple-side RSVP (v1 scope), theming polish beyond a clean default.

**Constraints:** UI reads only through `AgendaService`; RSVP visibility driven by capability flags, never provider type checks; in-app list also excludes declined events (consistent with Lock Screen), with declined visible only on the event detail of an invite.
**Edge cases:** same event dual-sourced (suppressed EventKit copy must not reappear after sync); midnight rollover while app foregrounded; offline mutation shows optimistically with pending indicator; RSVP failure rolls back optimistic state with error surfaced; deep link with malformed or unknown/deleted ID shows a not-found state, never crashes.

**Approach notes:** AgendaService is shared-target code so Phase 6 extensions call the same API (federated read: live EventKit + Google mirror).
**File hints:** `Calenminder/Sync/`, `Calenminder/UI/` -- per standards layout.
**Depends on:** Phases 3, 4 | **Unlocks:** Phase 6
**Produces:** `AgendaService.agenda(for: DayWindow) -> AgendaSnapshot` (events + tasks, deduped, filtered) in the shared target; deep-link URL scheme; complete app UI.
**Security-sensitive:** yes -- deep-link URLs are untrusted, externally-triggerable input.
**Rollback:** provider deletes are gated behind a confirmation dialog; failed RSVP/edit mutations roll back their optimistic UI state.

**Done when:**
- [ ] DW-5.1: AgendaService merge/filter/dedupe behavior covered by tests against fake providers
- [ ] DW-5.2: full flows verified on simulator: create/edit/delete event on both providers; RSVP on Google event; create/complete recurring task
- [ ] DW-5.3: offline edit -> relaunch -> sync replay observable in UI (pending indicator clears)
- [ ] DW-5.4: view models unit-tested; agenda + detail + onboarding covered by snapshot/UI tests
- [ ] DW-5.5: malformed and unknown-ID deep links land on a not-found state without crashing

**Difficulty:** MEDIUM
**Uncertainty:** in-app declined-event presentation is a taste call -> ship the stated default, revisit after use.

### Phase 6: Widget + App Intents
**Model:** sonnet
**Skills:** none -- WidgetKit/App Intents surface work; constraints fully specified by requirements doc and code-standards; no available skill's triggers match
**Gate:** Standard

**Goal:** Lock Screen and Home Screen widgets showing today's accepted/maybe events and incomplete tasks, with one-tap task completion.

**Scope:**
- IN: `accessoryRectangular` + `systemSmall`/`systemMedium` families; timeline provider reading `AgendaSnapshot` via shared target; per-row checkmark `Button(intent: CompleteTaskIntent)` (if Phase 1 verdict true) or deep-link rows (if false); event rows deep-link; midnight-boundary timeline entries; permission-missing placeholder; reload triggers (app foreground, post-mutation, post-intent); iOS 18 `ControlWidgetButton` "add task" behind availability check (best-effort, explicitly non-blocking for the phase gate).
- OUT: Live Activities, iOS 26 push-based reloads, watchOS/macOS widgets, configurable widget intents beyond defaults.

**Constraints:** declined events never render; only `Button`/`Toggle`/`Link`/`widgetURL` interaction primitives (no gesture modifiers -- they silently no-op); tap targets sized per HIG to avoid accidental completion; widget Info.plist carries EventKit usage keys (from Phase 1).
**Edge cases:** empty states (no events, no tasks, both); more items than rows -> overflow count; day rollover at midnight without a reload; stale Google mirror (last-sync timestamp shown subtly if stale > 24h).

**Approach notes:** Phase 1 spike verdict selects the row interaction; both variants keep identical layout so the swap is contained.
**File hints:** `CalenminderWidget/`, `CalenminderIntents/` -- per standards layout.
**Depends on:** Phases 5, 1 | **Unlocks:** none (terminal)
**Produces:** shipping widget extension + `CompleteTaskIntent`/deep-link routes -- the user-observable Lock Screen deliverable.

**Done when:**
- [ ] DW-6.1: Lock Screen widget renders today's accepted/maybe events + incomplete tasks on simulator; declined and completed items absent
- [ ] DW-6.2: tapping the row checkmark completes the task and the widget updates without app launch (or documented deep-link fallback if spike verdict was false)
- [ ] DW-6.3: midnight rollover produces tomorrow's entries without manual refresh
- [ ] DW-6.4: empty, overflow, and permission-missing states render correctly (snapshot tests)

**Difficulty:** MEDIUM
**Uncertainty:** None beyond the Phase 1 verdict, already bounded.

---
## Test Coverage
**Level:** High on logic, pragmatic on UI (user-chosen 2026-07-01): ~100% on Domain, sync, merge, recurrence, and dedupe logic via fakes; view models unit-tested; thin SwiftUI views and widget layouts verified by snapshot/UI tests, not exhaustively.

## Test Plan
Build/static checks:
- [ ] T-1.2 (DW-1.1, DW-1.3): CI script builds all targets + runs unit tests on iOS 17 simulator; static check asserts both Info.plists carry the EventKit usage-description keys
- [ ] T-2.4 (DW-2.1): static import check -- Domain sources contain no EventKit/UIKit/networking imports

Unit (fakes, no I/O):
- [ ] T-2.1 (DW-2.2): merge/dedupe table -- dual-sourced event collapses; invite copies in two calendars kept; distinct events untouched
- [ ] T-2.2 (DW-2.3): day-membership boundaries -- event ending 00:00, starting 23:59, all-day, DST spring-forward/fall-back day; task due-day comparison across timezone/DST; participation-status boundary values (accepted/tentative kept, declined/needsAction handling per spec)
- [ ] T-2.3 (dirty): malformed/missing iCal UID -> no dedupe, no crash
- [ ] T-4.1 (DW-4.1): sync state machine -- initial, incremental, paginated incremental, 410 at page N (queue preserved), cancelled-stub tombstoning
- [ ] T-4.2 (DW-4.2): 412 paths -- attendee-bump auto-rebase; same-field conflict surfaced; stale-etag retry forbidden
- [ ] T-4.3 (DW-4.5): RRULE expansion parity vs recorded `events.instances` fixtures (weekly, DST-crossing, exception child, cancelled instance, all-day `date` vs timed `dateTime`)
- [ ] T-4.4 (dirty): garbage JSON, missing etag, 401 mid-sync (re-auth signal), 429 (backoff invoked), queue replay idempotence on double-launch
- [ ] T-3.1 (DW-3.1, DW-3.4): EventKit provider conformance against fixture store -- day-window fetch, overdue-task lookback, span edits, typed permission-denied/write-only errors
- [ ] T-3.2 (dirty): reminder completed elsewhere with nil `completionDate`; second recurrence rule silently dropped; `refresh() == false` (deleted underneath); event moved between calendars (external-identifier re-resolution)
- [ ] T-5.1 (DW-5.1): AgendaService filter/merge -- declined excluded, completed tasks excluded, pending-op optimistic overlay, dedupe stable across re-sync
- [ ] T-5.2 (dirty): provider throwing mid-merge -> partial agenda + error state, never empty-silent
- [ ] T-5.5 (dirty): RSVP/edit mutation failure rolls back optimistic UI state and surfaces the error
- [ ] T-5.6 (DW-5.5, dirty): malformed and unknown/deleted-ID deep links -> not-found state, no crash
- [ ] T-5.4 (DW-5.4): view-model unit tests; agenda/detail/onboarding snapshot or UI tests

Integration (simulator / real services):
- [ ] T-3.3 (DW-3.2, DW-3.3): recurring spans + detached occurrences and task lifecycle against real Reminders store
- [ ] T-4.5 (DW-4.3): RSVP round-trip on a dedicated test Google calendar (instance + series)
- [ ] T-4.6 (DW-4.4): offline mutation survives force-quit and replays
- [ ] T-5.3 (DW-5.2, DW-5.3): end-to-end CRUD/RSVP/task flows; offline edit -> relaunch -> replay; midnight rollover while app foregrounded
- [ ] T-6.1 (DW-6.1, DW-6.4): widget snapshot tests -- populated, empty, overflow, permission-missing, declined absent, stale-mirror (>24h) indicator

Manual (device):
- [ ] T-1.1 (DW-1.2): spike verdict, locked + unlocked
- [ ] T-6.2 (DW-6.2): Lock Screen tap-to-complete end-to-end
- [ ] T-6.3 (DW-6.3): midnight rollover overnight check

---
## Assumptions
| Assumption | Confidence | Verify Before Phase | Fallback If Wrong |
|---|---|---|---|
| Widget-extension intent can write EKReminders | Medium-high (unofficial) | Phase 1 spike | Phase 6 rows deep-link into app |
| Completing a recurring EKReminder rolls to next occurrence system-side | Medium | Phase 3 (T-3.3) | ReminderTaskStore generates next occurrence itself |
| Google RSVP patch works instance- and series-level as documented | High | Phase 4 (T-4.5) | Fall back to get-then-update full attendee list |
| Query-time merge fast/fresh enough for widget | High | Phase 6 | Persist merged day snapshot to App Group cache (Chosen Approach fallback) |
| Single Google account covers v1 | Confirmed by user | -- | Multi-account is additive later (provider instances per account) |

## Decision Log
| Decision | Alternatives Considered | Rationale | Phase |
|---|---|---|---|
| Federated merge-on-read (B) | Canonical mirror store (A); EventKit-as-hub (C) | No duplicated EventKit state; C disqualified by read-only attendees | all |
| Direct Google REST + OAuth | Google-via-EventKit CalDAV | EventKit cannot RSVP; REST gives syncToken + etag | 4 |
| Tasks as EKReminders | SwiftData + CloudKit model | Native fit, free sync/Siri; user accepted Reminders visibility | 3 |
| RSVP Google-only in v1 | iCloud CalDAV client; drop Apple events | Scope control; documented upgrade path | 4, 5 |
| No backend, poll-based sync | Companion server + push | User accepted staleness trade-off; zero infra | 4, 5 |
| Spike-first phase ordering | Spike inside Phase 6 | Verdict changes Phase 6's interaction contract | 1 |

---
## Notes
- Build prerequisite (user action, needed before Phase 4 integration tests): a Google Cloud project with an iOS OAuth client ID, and a test Google account + throwaway calendar for RSVP round-trips. `calendar.events` is a sensitive scope: fine unverified while the OAuth consent screen is in testing mode with the account added as a test user; Google verification is only needed for public distribution.
- EventKit integration tests hit the simulator's real system store -- tag them to run simulator-only and serially to avoid flakiness; keep them out of any parallel unit-test invocation.
- Recurrence guard tests (exception-not-new-event; series-edit-preserves-exception) are mandatory per code-standards and appear in T-4.3.
- In-app declined-event presentation default: excluded from agenda, visible on invite detail (Phase 5 uncertainty note).
- iOS 26 widget push reloads and Live Activities deliberately out of scope (requirements doc, Deferred).
---
## Execution Log
_To be filled during /code-foundations:build_
