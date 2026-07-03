# Calenminder - Requirements

A native iOS app that unifies Apple Calendar events and day-scoped tasks (no fixed time, completable), surfaced together in-app and on the Lock Screen.

- **Date:** 2026-07-01, revised 2026-07-03
- **Status:** confirmed - research questions resolved; scope revised 2026-07-03: Google Calendar integration dropped by user decision, Apple Calendar (EventKit) only; consequently RSVP is view-only in v1 (confirmed trade-off)

## Problem

The user currently fakes non-time-sensitive reminders as calendar events (e.g. a recurring Monday 6pm "bring recycling to curb" event that has no real time).
Calendars pollute the schedule with fake times; reminders apps lack the calendar context.
Calenminder makes the distinction first-class:

- **Event:** time-sensitive, lives in Apple Calendar (any account the system syncs: iCloud, Google-via-iOS-Settings, Exchange, local), full CRUD.
- **Task:** belongs to a day, not a time ("do this sometime today"), can recur, can be marked complete.

## Confirmed scope (v1)

### Events

- Source: EventKit only - every calendar visible to iOS (iCloud, local, subscribed, and any account added in iOS Settings, including Google if the user adds it there).
- Full CRUD, including recurring events with "this event" / "this and future events" edit spans.
- **RSVP is view-only (revised 2026-07-03):** participation status (accepted / declined / tentative) is displayed and used for filtering, but responding to invites is impossible via EventKit (`participantStatus` is read-only through iOS 26; no public workaround).
  The user responds in Apple Calendar/Mail when needed.
  Full RSVP would require a direct provider client (Google REST or iCloud CalDAV); both are deferred.

### Tasks

- Day-scoped: due date with no time component; today's incomplete tasks are the core working set.
- Complete / un-complete; overdue incomplete tasks roll forward visually.
- Recurrence: at minimum weekly-by-weekday ("every Monday"), matching the recycling use case.
- Storage: EKReminders in a dedicated Reminders list (confirmed 2026-07-01).
  Rationale: native date-only due dates, completion state, weekly recurrence rules, free iCloud sync, Siri and Reminders-app interop, and Apple's own Reminders widget proves tap-to-complete from a widget extension works.
  Accepted trade-offs: tasks visible/editable in the Reminders app; async predicate-only fetching; one recurrence rule per reminder.

### Lock Screen

- An `accessoryRectangular` WidgetKit widget showing today's events (participation status accepted or tentative; declined excluded) and today's incomplete tasks.
- **Resolved: swipe-to-complete is not achievable** (no gestures in any widget family through iOS 26).
- **Fallback interaction (confirmed):** tap-to-complete - a leading checkbox `Button(intent: CompleteTaskIntent(id:))` per task row (the Things 3 / Apple Reminders pattern); row text deep-links into the app.
  On a locked device the button is inert until Face ID authenticates; glance-to-unlock makes this invisible in practice.
- Capacity: ~2 rows per rectangular widget; multiple widgets extend capacity.
- Optional nice-to-have: iOS 18+ `ControlWidgetButton` ("add task") for the Lock Screen corner slots, availability-gated.
- Widget freshness: reload on app foreground and after every mutation; timeline entries roll the day over at midnight.

### Sync, offline, conflicts

- EventKit is offline-capable by design: writes land in the local system database immediately and the OS syncs them to iCloud/CalDAV/Exchange.
- Conflict resolution on the sync path is OS-owned and opaque; the app's obligations are:
  refetch the visible window on the coarse `EKEventStoreChanged` notification and diff against its snapshot,
  call `EKEvent.refresh()` before saving an in-flight edit (false = deleted underneath),
  and call `refreshSourcesIfNecessary()` on foreground (best-effort).
- No app-level sync engine, mirror, or pending-operation queue is needed.

### Auth and permissions

- EventKit events: `requestFullAccessToEvents()` (iOS 17+ model) + `NSCalendarsFullAccessUsageDescription`; full access required (write-only cannot read the schedule).
- EventKit reminders: `requestFullAccessToReminders()` + `NSRemindersFullAccessUsageDescription`.
- The widget extension needs the same usage-description keys in its own Info.plist; the main app must obtain permission first (widgets cannot prompt) and the widget renders a "grant access" placeholder otherwise.

### Data model (shape, not architecture)

- Canonical `Event` and `Task` domain types wrapping EventKit objects; provider protocols kept thin so fakes drive logic tests.
- Identifier strategy: persist `calendarItemExternalIdentifier` + occurrence date (syncs across devices), with predicate re-query as fallback; `eventIdentifier` alone is not stable across calendar moves.
- Recurrence: EventKit hands the app pre-expanded occurrences; never touch RRULE.

## Platform baseline

- iOS 17 minimum (interactive widgets + current EventKit permission model); iOS 18+ Controls availability-gated.
- Swift + SwiftUI, WidgetKit + App Intents extensions.

## Resolved research questions

1. **Lock Screen swipe-to-complete?** No - impossible through iOS 26; fallback is per-row tap-to-complete via `Button(intent:)`, which works in Lock Screen rectangular widgets on iOS 17+.
2. **EventKit vs Google API?** Superseded 2026-07-03: Google integration dropped entirely; EventKit is the sole event source.
   The 2026-07-01 finding stands for the record: EventKit cannot RSVP, so any future RSVP feature requires a direct provider client.
3. **Where do Tasks live?** EKReminders in a dedicated list (confirmed 2026-07-01).
4. **Offline + conflict resolution?** Trivial in the revised scope: EventKit is local-first with OS-owned sync; the app snapshot-diffs on `EKEventStoreChanged` and refreshes before saves.

## Deliberately deferred

- Google Calendar integration (direct REST + OAuth) - revive if events outside the iOS system calendars are needed, or when RSVP becomes a must-have.
- RSVP (accept/decline/maybe) - requires a direct provider client (Google REST or iCloud CalDAV); revive when responding in Apple Calendar becomes annoying enough.
- Companion server / push-fresh sync.
- Google Tasks / Todoist import.
- Task time-blocking, subtasks, tags, priorities beyond what EKReminder offers.
- iPad / macOS / watchOS targets.
- Live Activities, iOS 26 widget push reloads.

## Decisions confirmed by the user

1. 2026-07-01: Tasks as EKReminders (alternative: SwiftData + CloudKit model; Reminders-app visibility accepted).
2. 2026-07-01: no backend (alternative: companion server) - now moot for events, still true overall.
3. 2026-07-03: Apple Calendar only; Google Calendar integration dropped (was: direct REST + OAuth with full RSVP).
4. 2026-07-03: v1 ships without RSVP (view-only participation status; alternative was an iCloud CalDAV client).

## Pre-plan validation spikes

- 1-hour spike: widget-extension `Button(intent:)` marking an `EKReminder` complete via `store.save` - high-confidence but not explicitly documented by Apple as third-party-permitted from an extension.
- Verify empirically: completing a recurring EKReminder rolls to the next occurrence system-side.

## Next step

```
/code-foundations:plan .code-foundations/research/2026-07-01-calenminder-requirements.md
```
