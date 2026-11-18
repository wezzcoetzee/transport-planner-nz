# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Recorded as `ios` so Apple-native guidance applies. The product is a macOS menu bar app (SwiftUI, macOS 26, `LSUIElement`, no dock icon). Ignore touch-only iOS advice such as tab bars, 44pt targets and gestures.

## Users

Auckland commuters deciding when to stop working and walk to the bus. They glance at the menu bar throughout the afternoon and occasionally open the popover. The settings window is visited once at setup and rarely after.

Context: a Mac with the menu bar always visible, often in a bright office, sometimes in a dim one. The commuter is mid-task in another app. The interaction budget is one glance or one click.

Audience scope: a public community app for any Auckland commuter with a Mac, distributed through GitHub Releases. Independent project, not affiliated with or endorsed by Auckland Transport.

## Product Purpose

Show the single moment to leave so commuters arrive at the stop just before the bus, never waiting fifteen minutes. Secondary: show the next best option if they miss it, and why that option was picked (route, walk, arrival home).

Success: commuters trust the countdown enough to stop checking the AT app. The tool disappears into the commute.

## Positioning

What AT Mobile and Google Maps transit cannot truthfully claim:

- **Leave time, not departure time.** The answer is when to walk out of the office (`departure - walk - buffer`), a countdown to standing up, not a list of buses.
- **Lives in the menu bar.** A zero-click glance while working. No app to open, no phone to pick up.
- **Quiet away from the office.** Location-aware: no countdown, reminders or panel when the commuter is not at work.
- **Works offline, no key.** Plans from a local SQLite copy of the public AT GTFS timetable. Realtime delays and cancellations are optional, via a free AT developer key.

## Operating Context

- Afternoon ritual: the commuter works in other apps; the menu bar countdown changes state at 10 minutes out and at the leave time.
- Staged notifications (default 10 min, 5 min, now) with Next, Not today and Going actions; each replaces the last.
- At the leave time, a panel under the menu bar waits until answered and follows realtime changes to that bus.
- Settings is a one-time setup: office and home by address search, ideal leave time and window, transfers, stop buffer, search radius, walking pace, excluded stops, optional AT key.
- First launch downloads and imports the timetable; until it can plan, an Apple Maps transit estimate stands in.

## Capabilities and Constraints

- Direct and one-transfer journeys only.
- Auckland Transport data only. Route colours from the feed are not used.
- Fallback to an Apple Maps estimate when the timetable cannot plan; when the timetable simply has no bus left, it says so instead of guessing.
- All preferences and the AT key live in local UserDefaults. No account, no server.
- Ad-hoc signed, not notarised. First launch needs Open Anyway.
- Existing codebase: SwiftUI, Swift 6 strict concurrency, XcodeGen (`project.yml`).

## Brand Personality

Calm, precise, quiet.

Voice is a terse colleague who knows the timetable: "Leave in 12 min", "195 5:05 pm from Lower Albert Street, home 5:23 pm". Numbers carry the meaning; words only label them. No exclamation marks, no encouragement, no emoji.

References: Linear for restraint and typographic hierarchy; Apple Weather and Stocks for glanceable, numbers-first native surfaces.

## Anti-references

- AT Mobile and Google Maps transit: coloured route pills, maps, decorative iconography, route branding as ornament.
- Generic SaaS dashboards: cards inside cards, a hero metric with a small label, gradient accents, light-grey subtitle lines above sections.
- Anything that needs reading rather than glancing.

## Evidence on Hand

- Screenshots of every state from a pinned Debug build: `screenshots/raw/mac/`.
- Framed 2880x1800 set with headlines: `screenshots/framed/mac/`, copy in `screenshots/manifest.json`.
- App icon: `NZTransportPlanner/Resources/AppIcon.icns`, rendered by `scripts/icon/`.
- None: no testimonials, user counts, reviews, press or App Store listing. Do not fabricate them.

## Product Principles

1. **One number first.** The time to leave is the whole product. Everything else is supporting evidence and sits visually below it.
2. **Evidence, not decoration.** A route number, a stop name, an arrival time earn their place because they explain the recommendation. Nothing appears for texture.
3. **Native by default.** System typography, standard macOS controls, standard settings layout. Familiarity is the affordance; there is nothing to learn.
4. **Quiet until it matters.** The menu bar label is static and terse. Notifications and the leave panel are the only interruptions, and only at the configured moments.
5. **Dense and dark.** A core design constraint: true black background, white primary text, information-dense, no card or pill chrome. This overrides any generic guidance against pure black.

## Accessibility & Inclusion

macOS defaults are sufficient: respect Dynamic Type, Reduce Motion, and Increase Contrast. Provide VoiceOver labels on icon-only buttons. No continuously repainting animation, ever, regardless of system settings (high-refresh display, GPU cost).
