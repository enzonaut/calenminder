<!-- base-commit: c59182e -->
<!-- generated: 2026-07-04 -->

# App Store Metadata Draft

Draft copy for App Store Connect. Character-count fields are machine-checked
(`CalenminderTests/AppStoreMetadataTests.swift`) against the App Store's field limits - keep this file's
structure (one value per labeled line, exact heading text) intact so that check keeps working.

## App Name

Calenminder

## Subtitle

<!-- max 30 characters -->
Events and tasks, separated

## Description

Most calendar apps force a chore like "take out the recycling" into the same time-boxed slot as a 2pm
meeting. Calenminder keeps them apart. Events are the time-sensitive things on your calendar - meetings,
appointments, flights - shown and edited in full, including recurring series. Tasks are day-scoped things
you need to get done, not scheduled to the minute; they can repeat daily or weekly, roll forward when
you miss a day, and get checked off with one tap.

Everything lives in one agenda, with year, month, week, and day views and swipe navigation between them.
A Lock Screen widget keeps today's events and open tasks visible without unlocking your phone, and you can
complete a task right from the widget.

Tasks are backed by Apple Reminders under the hood, so they sync via iCloud and work with Siri and the
Reminders app for free. There's no separate account, no sign-in, and no proprietary data format to get
locked into.

Calenminder is open source and does not collect any data. There are no servers, no analytics, and no
third-party SDKs anywhere in the app - everything runs on your device using Apple's own Calendar and
Reminders frameworks. You can read the full source on GitHub.

## Keywords

<!-- max 100 characters, comma-separated, no spaces after commas -->
calendar,tasks,todo,reminders,agenda,planner,widget,lock screen,eventkit,privacy,open source

## Category

Productivity

## Privacy "Nutrition Label" Answers

Answer for every requested data-type category: **Data Not Collected**.

Justification, per data type Apple's questionnaire asks about:

- **Contact Info** (name, email, phone, address): not collected. No account or sign-in exists anywhere in
  the app.
- **Health & Fitness, Financial Info, Location, Sensitive Info**: not applicable. Calenminder never
  requests or accesses any of these.
- **Contacts**: not accessed. Calenminder does not read the system Contacts/Address Book.
- **User Content** (Calendar/Reminders data specifically): accessed on-device only, through Apple's
  EventKit framework, with the user's explicit system permission. This data is never transmitted off the
  device, never sent to a server (there is no server), and never linked to an identity by the developer -
  it is read and written directly against Apple's own system store, the same store the built-in Calendar
  and Reminders apps use. Per Apple's own "data collected" definition (data transmitted off the device or
  otherwise linked to a user's identity by the developer), this does not qualify as collection.
- **Identifiers, Purchases, Usage Data, Diagnostics, Browsing/Search History, Other Data**: not collected.
  No analytics, crash-reporting, or advertising SDK of any kind is linked into the app (verifiable directly
  in `project.yml`, the app's build configuration).

## Age Rating Answers

All content-based questions: **No**.

- Cartoon or Fantasy Violence: No
- Realistic Violence: No
- Sexual Content or Nudity: No
- Profanity or Crude Humor: No
- Alcohol, Tobacco, or Drug Use/References: No
- Mature/Suggestive Themes: No
- Horror/Fear Themes: No
- Gambling (simulated or real-money): No
- Contests: No
- Unrestricted Web Access: No
- User-Generated Content shared with other users: No (all data is local/private to the user's own EventKit
  store; there is no sharing, posting, or social feature of any kind)

Resulting rating: **4+**.

## Support URL

https://github.com/enzonaut/calenminder

## Privacy Policy URL

https://github.com/enzonaut/calenminder/blob/main/PRIVACY.md

## Review Notes for Apple

Calenminder needs Calendar and Reminders permission (the standard EventKit system prompts) to demonstrate
its core functionality - the app's entire agenda is empty without them. Please grant both when prompted on
first launch. No account, sign-in, or credentials of any kind are needed or exist - there is nothing to log
into. The app makes no network requests; all functionality is available fully offline. To see the Lock
Screen widget, add it via the Lock Screen editor after granting permissions and creating at least one event
or task.
