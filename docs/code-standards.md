<!-- base-commit: cb7adeb58111582b0b55a4e97a4f751f34a6a46e -->
<!-- generated: 2026-07-01 -->

# Code Standards

Greenfield repo (no code at generation time).
These are seed standards derived from the confirmed requirements (`.code-foundations/research/2026-07-01-calenminder-requirements.md`).
Regenerate after the first real build phase so examples point at actual files.

## Forbidden Patterns

**Never use private EventKit API for RSVP** (e.g. KVC `setValue:forKey:` on `participantStatus`).
It is App Store rejection risk and server propagation is undefined.
Participation status is display/filter-only in this app; there is no RSVP action anywhere.

```swift
// BAD - private API, rejection risk, undefined sync behavior
attendee.setValue(EKParticipantStatus.accepted.rawValue, forKey: "participantStatus")

// GOOD - read-only use for filtering
let visible = events.filter { $0.participation != .declined }
```

**Never persist `eventIdentifier` as the durable key for an EventKit item.**
It can change when an event moves between calendars or sync cycles.
Persist `calendarItemExternalIdentifier` + occurrence date, with predicate re-query as fallback.

**Never call deprecated `requestAccess(to:)`.**
Use `requestFullAccessToEvents()` / `requestFullAccessToReminders()` (iOS 17+ model).

**Never block on synchronous-looking EventKit reminder fetches.**
Reminders are predicate + completion-handler only; wrap in async and treat results as snapshots that `EKEventStoreChanged` invalidates.

## Error Handling

Expected failures are typed and carry their recovery route; only programmer errors trap.

```swift
// Store errors name the user-facing recovery, not just a message.
enum CalendarStoreError: Error {
    case accessDenied(EKEntityType)   // -> settings deep link + placeholder UI
    case writeOnlyAccess              // -> full-access re-request explanation
    case itemDeletedUnderneath        // -> refresh() == false; dismiss editor, refetch window
    case saveFailed(underlying: Error)
}
```

Failures are never swallowed: every save/fetch path surfaces a typed error or an observable empty/placeholder state.

## Naming Conventions

Domain terms are load-bearing; do not blur them:

- "Event" = time-sensitive calendar item from a provider. Never call a task an event.
- "Task" = day-scoped completable item (EKReminder-backed). Never "reminder" in UI/API names; "reminder" is reserved for the EventKit storage layer.
- `Event` (canonical domain type) vs `EKEvent` (system type); the EK prefix marks the EventKit layer.
- IDs: `externalIdentifier` (+ occurrence date) for durable references - never a bare `id` for cross-layer identifiers.

## File Organization

Target layout (established Phase 1; create subfolders as later phases build them out; keep this section in sync):

```
calenminder/                 # repo root
├── project.yml               # XcodeGen source of truth; `xcodegen generate` writes Calenminder.xcodeproj
├── Calenminder/               # App target (SwiftUI) -- UI only
│   └── UI/                    # Views, view models (Phase 4)
├── CalenminderKit/            # Shared framework: cross-target code, linked by app + widget
│   ├── Domain/                 # Canonical Event/Task models (pure, no I/O) (Phase 2)
│   ├── Store/                  # EKEventStore wrappers for events + reminders (Phase 3)
│   └── Agenda/                 # Agenda assembly, filtering, change coalescing (Phase 4)
├── CalenminderWidget/         # WidgetKit extension (Lock Screen + Home Screen)
├── CalenminderIntents/        # Shared App Intents framework target -- scaffolded Phase 1.
│                               # IMPORTANT: an App Intent invoked by a widget's interactive
│                               # Button(intent:) must be declared directly inside
│                               # CalenminderWidget, not here -- confirmed empirically in the
│                               # Phase 1 spike (see plan Execution Log). This target may still
│                               # be safe for App Intents invoked only from the app's own
│                               # process (Siri/Shortcuts); re-verify before relying on that.
└── CalenminderTests/           # Unit tests (Swift Testing); mirrors source folder names
```

Dependency direction: `Domain` imports nothing internal; `Store` imports `Domain`; `Agenda` imports `Store` + `Domain`; `UI` imports all; nothing imports `UI`. `CalenminderKit` (the framework housing `Domain`/`Store`/`Agenda`) is linked+embedded by both `Calenminder` and `CalenminderWidget`.

Note for Phase 2: `Domain`'s "zero imports of EventKit/UIKit/networking" requirement (DW-2.1) needs to be checkable; if `Domain` and `Store` end up as subfolders of the same `CalenminderKit` target, that check must be file-level (e.g. a grep-based static check), since a single Xcode target has no built-in per-file import isolation. Splitting `Domain` into its own target is the alternative if a target-level check is preferred.

## Testing Patterns

- Swift Testing (`import Testing`) for unit tests; XCUITest only for the few end-to-end flows.
- Stores are protocol-backed so agenda/filter logic tests run against fakes, never the real event store.
- Recurrence guard test is mandatory: a series edit must not clobber a detached occurrence.
- EventKit integration tests hit the simulator's real system store: tag simulator-only, run serially.

## Technology Decisions

- iOS 17 minimum; iOS 18 Controls are a progressive enhancement behind availability checks.
- EventKit is the only event source (revised 2026-07-03; Google REST integration dropped). No RSVP actions anywhere; participation status is read-only.
- Tasks are EKReminders in a dedicated list. Do not introduce a parallel local task store.
- No backend, no networking layer at all in v1.
- Widget interactivity is `Button(intent:)`/`Toggle(intent:)` only. No gesture APIs in widget code; they silently do nothing.
- App Intents invoked by a widget's `Button(intent:)` must be declared directly in the widget extension target, never in a separate shared framework -- confirmed empirically Phase 1 (see plan Execution Log): an identical intent in `CalenminderIntents` never fired from a real tap (`linkd` reported it `Missing`), the same intent declared in `CalenminderWidget` worked immediately.
- Swift language mode: **Swift 5** project-wide (not Swift 6 strict concurrency). EventKit's completion-handler APIs are not Sendable-audited in this SDK; fighting strict-concurrency region checks against an un-audited system framework is not worth the tax given how much Store-layer code calls them. Revisit if Apple ships a Sendable-safe EventKit surface.
- Project generation: `project.yml` (XcodeGen) is the source of truth; run `xcodegen generate` (or `make generate`) to regenerate `Calenminder.xcodeproj` after editing it. The generated `.xcodeproj`, `Info.plist`s, and `.entitlements` files are committed too, so `xcodebuild` works standalone without requiring XcodeGen downstream.

## Exemplar Files

None yet (no code).
After the first build phase, replace this section with pointers to the canonical provider client and one merge test file.
