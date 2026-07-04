# Privacy Policy

**Effective date: July 2026**

Calenminder is an iOS app.
This document explains, plainly, what happens to your data when you use it.

## The short version

Calenminder does not collect any data.
There are no servers, no analytics, no third-party SDKs, and no accounts.
Everything the app does happens on your device, using data already stored on your device through Apple's
own frameworks.
You can verify every claim below by reading the app's source code - the repository is public.

## What Calenminder accesses, and why

**Calendars.**
Calenminder reads and writes your calendar events through Apple's EventKit framework, with your explicit
permission (the standard iOS "Calendar Access" prompt).
This is how the app shows your events and lets you create, edit, and delete them.
Calendar data never leaves your device through Calenminder; it lives in the same system-managed store the
built-in Calendar app uses, and syncs (if at all) only the way you already have iCloud or your calendar
accounts configured at the system level - Calenminder has no part in that sync.

**Reminders.**
Calenminder's day-scoped tasks are backed by Apple's Reminders framework (EventKit), in a dedicated
reminders list, with your explicit permission (the standard iOS "Reminders Access" prompt).
This is how tasks are created, completed, and rolled forward.
As with calendars, this data lives in Apple's system store and never leaves your device through Calenminder.

**Notification/badge permission.**
Calenminder requests notification permission for exactly one purpose: setting the app icon's badge number to
your count of incomplete/overdue tasks for the day.
Calenminder does not send you push notifications, and does not use this permission for anything beyond the
badge count.

## What Calenminder does not do

- No network requests. There is no networking layer, no server, and no API calls anywhere in the app.
- No analytics, crash reporting, or telemetry of any kind.
- No third-party SDKs of any kind are linked into the app.
- No advertising, no ad identifiers, no tracking.
- No accounts, sign-in, or user profiles - there is nothing to create or log into.
- No data is collected, transmitted, sold, or shared with anyone, because none is collected in the first
  place.

## Data storage and your control

All calendar and reminder data managed through Calenminder stays inside Apple's own EventKit-backed system
stores on your device (and wherever you've configured those to sync via iCloud or other accounts at the
system level - a setting Calenminder does not control or participate in).
You can review, export, or delete this data at any time through the Settings app, the built-in Calendar and
Reminders apps, or by revoking Calenminder's Calendar/Reminders permissions in Settings > Privacy & Security.
Uninstalling Calenminder removes the app itself; it does not delete your calendar events or reminders, since
that data was never Calenminder's to hold onto - it belongs to your device's system stores.

## Children's privacy

Calenminder does not knowingly collect data from anyone, of any age, because it does not collect data at all.

## Changes to this policy

If this policy ever changes, the update will be committed to this same file in the public repository, where
the full history is visible.

## Contact

Calenminder is open source. Questions, issues, or concerns can be filed at:
https://github.com/enzonaut/calenminder
