---
name: When To Leave
description: A departure board in the menu bar. One time to leave, lit in white on black.
colors:
  board-black: "#000000"
  signal-white: "#FFFFFF"
  dimmed-white: "#FFFFFF8C"
  live-green: "#30D158"
  delay-orange: "#FF9F0A"
typography:
  headline:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.3
    fontFeature: "tnum"
  title:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.3
    fontFeature: "tnum"
  body:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 400
    lineHeight: 1.3
    fontFeature: "tnum"
rounded:
  none: "0px"
spacing:
  hair: "2px"
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "10px"
  xl: "12px"
components:
  popover:
    backgroundColor: "{colors.board-black}"
    textColor: "{colors.signal-white}"
    padding: "{spacing.xl}"
    width: "360px"
  headline-leave:
    typography: "{typography.headline}"
    textColor: "{colors.signal-white}"
  journey-row-recommended:
    typography: "{typography.title}"
    textColor: "{colors.signal-white}"
    padding: "{spacing.xs} 0"
  journey-row-alternative:
    typography: "{typography.title}"
    textColor: "{colors.dimmed-white}"
    padding: "{spacing.xs} 0"
  button-text:
    typography: "{typography.label}"
    textColor: "{colors.signal-white}"
    backgroundColor: "{colors.board-black}"
    padding: "0"
  badge-live:
    typography: "{typography.label}"
    textColor: "{colors.live-green}"
  badge-delay:
    typography: "{typography.label}"
    textColor: "{colors.delay-orange}"
  settings-window:
    backgroundColor: "{colors.board-black}"
    width: "520px"
    height: "460px"
---

# Design System: When To Leave

## 1. Overview

**Creative North Star: "The Departure Board"**

A station departure board seen from across a dark concourse. The surface is unlit black; the only things that exist are the characters the board has chosen to light. The next departure is brightest, the ones after it are dimmer, and nothing else is on. Every glyph is information: a time, a route number, a stop name, a walk. There is no frame around the board and no decoration on it, because a board that decorated itself would be a worse board.

That metaphor sets the density and the restraint. The popover is a single column of services, 360 points wide, read top to bottom in the order you could catch them. Hierarchy comes from three things only: weight, brightness and position. The recommended journey is full white and semibold; alternatives are the same rows at 70% brightness. Color appears in exactly two places, a green "Live" mark when realtime data is flowing and an orange figure when a bus is running late, and both are the size of a caption.

The system explicitly rejects the look of AT Mobile and Google Maps transit (coloured route pills, maps, decorative iconography) and of generic SaaS dashboards (cards inside cards, hero metric with a small label, gradient accents, light-grey subtitle lines above sections). Settings are plain macOS grouped forms and do not try to be interesting.

**Key Characteristics:**
- True black surface, white type, nothing between them
- One headline number; everything else is evidence beneath it
- Brightness and weight carry hierarchy, never boxes or rules
- SF system font throughout, tabular digits wherever a time appears
- Two semantic colors, each caption-sized and state-bound
- Static menu bar label, no motion anywhere

## 2. Colors

A monochrome board with two signal lamps.

### Primary
- **Signal White** (#FFFFFF): the lit character. Headline, recommended journey times, route numbers, action words. If it is white it is something you might act on.

### Neutral
- **Board Black** (#000000): the entire surface of the popover and settings window. A core design constraint; never tinted, never lifted to a dark grey.
- **Dimmed White** (#FFFFFF at 55%, SwiftUI `.secondary`): supporting evidence. Arrival times, walk legs, stop counts, status lines, explanatory captions in Settings.
- **Alternative rows** are the same tokens at 70% row opacity, not a third grey. One dimming mechanism, applied twice.

### Semantic
- **Live Green** (#30D158, system green): the "Live" badge only, meaning realtime delays are being applied. Also "on time" and small delays under three minutes.
- **Delay Orange** (#FF9F0A, system orange): a delay of three minutes or more, a realtime error, a failing setting. Never for emphasis.

### Named Rules
**The Two Lamps Rule.** Green and orange are the only chromatic colors permitted. Each is caption-sized, each means one state, neither is ever used for decoration or emphasis. Route colors from the GTFS feed are ignored.

**The Unlit Rule.** The background is #000000 and stays there. Hierarchy is created by turning text down, never by turning the surface up.

## 3. Typography

**Display Font:** none. There is no display tier.
**Body Font:** SF Pro Text via `-apple-system` (falls back to system-ui)
**Label/Mono Font:** same family with tabular figures (`monospacedDigit()`) on every time and duration

**Character:** the native macOS voice at its most literal. Nothing is styled to look like a headline; the headline is just the largest, heaviest line on the board.

### Hierarchy
- **Headline** (semibold 600, 15px, SwiftUI `.title3`): the single leave statement. "Leave in 12 min", "Leave now", "Leave at 5:03 pm". Tabular digits so the number does not jitter as it counts down.
- **Title** (semibold 600, 12px, `.callout`): the leave time of the recommended row, and route numbers in every row.
- **Body** (regular 400, 13px, `.body`): settings labels and form controls. Not used in the popover.
- **Label** (regular 400, 10px, `.caption` / `.caption2`): everything else on the board: legs, arrival times, durations, delay figures, footer actions, status badges, explanatory captions.

### Named Rules
**The Tabular Rule.** Any glyph that represents a time, a count of minutes or a distance uses tabular figures. Proportional digits in a countdown are a defect.

**The Two Steps Rule.** The popover uses exactly two effective sizes, headline and label, with title as the bridge on the recommended row. Adding a fourth size is adding noise.

## 4. Elevation

Flat, tonal only. The popover has no shadows, no borders, no dividers inside it, and no inset panels. Depth is conveyed by brightness: full white is nearest, dimmed white is behind it, 70% rows are behind that. The single `Divider()` above the footer is the only rule on the board and separates actions from information.

Settings use the stock macOS grouped form, which brings its own tonal grouping. Do not add to it.

### Named Rules
**The Flat Board Rule.** Nothing casts a shadow and nothing has an outline. If a row needs a box to be readable, the row has too much in it.

## 5. Components

### Popover
Character: the board itself. 360 points wide, 12 point padding on every side, 10 point spacing between the headline, journey block and footer. Black background, dark color scheme forced regardless of system appearance.

### Headline
Leave statement at headline weight, left aligned, with the realtime badge on the same baseline at the far right. When no journey is recommended the status message takes the headline slot in the same weight ("No commute today", "Skipped for today", "Set your office and home in Settings").

### Journey Row
Character: one line per service, like a board row. Three columns: a 62 point time column (leave time in title weight over arrival time in dimmed label), a leg list (walk legs in dimmed label with the figure.walk symbol; ride legs as two label lines: mode symbol, route number in semibold and dimmed headsign, then "board stop → alight stop" truncated in the middle), and a trailing column with duration, dimmed stop count and the optional delay figure ("+3 min late") in green or orange.
- **Recommended:** full opacity, leave time semibold.
- **Alternative:** identical structure at 70% opacity, leave time regular weight. Up to four shown.
- **Padding:** 4 points vertical, none horizontal. No background, no border.

### Footer Actions
Character: words, not buttons. Borderless caption-sized text buttons in a single row: Refresh (reads "Updating" while a plan runs; the last update time is its help text), Next option, Undo (only while an option is skipped), Not today or Un-skip, Maps. Trailing icon-only buttons for Settings (gear) and Quit (power). Icon-only buttons carry VoiceOver labels and help text; Refresh, Settings and Quit have R, comma and Q shortcuts.
- **Hover:** system borderless hover treatment. No custom hover color.
- **Focus:** system focus ring.

### Badges
Caption-sized text with an optional SF Symbol, never a pill. "Live" in green with the radio-waves symbol, "Schedule" in dimmed white when no key is set, "Schedule" in orange with the warning triangle when realtime failed. Help text on hover explains the state.

### Fallback Block
When the timetable cannot produce a journey, the Apple Maps estimate appears where the journey rows would: a title line "Apple Maps: leave 5:02 pm, home 5:22 pm" and a dimmed caption with the transit duration. The headline already carries the status. When the status has a single remedy (Open Settings, Retry download) it follows as a borderless caption button.

### Settings Forms
Stock macOS `Form` with `.formStyle(.grouped)`, three tabs (Commute, Stops, Data), 520 by 460 points. Standard `DatePicker`, `Stepper`, `Slider`, `Picker`, `Toggle`, `SecureField`. Weekday and reminder-lead selectors are small button-style toggles in a row. The place search field shows the chosen place as labelled content with a borderless Change button, or a rounded-border text field with up to five completion rows beneath it as borderless buttons. Return picks the first row; Cancel or Escape keeps the saved place. Explanatory text is caption-sized and dimmed. Nothing here is custom.

### Menu Bar Label
An SF Symbol for the mode (bus, tram, ferry) followed by a terse countdown: "12m", "Go", or a clock time without am/pm ("5:05") beyond 90 minutes. Other states change the symbol only: moon when skipped for today, gear when unconfigured, warning triangle when the timetable failed, and a bus with "~5:02" when the Apple Maps estimate is standing in. Titles stay this short, with tabular digits, so the status item barely changes width. Static; updated by the model every 30 seconds. No TimelineView, no animation.

## 6. Do's and Don'ts

### Do:
- **Do** keep the background #000000 in both the popover and Settings. Never raise it to a grey.
- **Do** carry hierarchy with weight (600 vs 400) and brightness (100%, 55%, 70% row opacity) only.
- **Do** use tabular figures on every time, minute count and metre count.
- **Do** keep green for "live" and small delays, orange for delays of three minutes or more and for errors, and use each at caption size only.
- **Do** use stock macOS controls in Settings and borderless text buttons in the popover.
- **Do** keep the menu bar label static and let the model update it on a timer.
- **Do** give every icon-only button a VoiceOver label.

### Don't:
- **Don't** reproduce AT Mobile or Google Maps transit: no coloured route pills, no maps, no decorative iconography, no GTFS route colours.
- **Don't** build a generic SaaS dashboard: no cards inside cards, no hero metric with a small label beneath it, no gradient accents, no light-grey subtitle lines above sections.
- **Don't** draw borders, shadows, side stripes or background tints around journey rows. A row is text on black.
- **Don't** add a third grey or a fourth type size. Dim what exists instead.
- **Don't** animate anything that repaints continuously: no pulses, shimmers, spinners or blur. The import phase is a text status, not a progress animation.
- **Don't** put a TimelineView or any self-updating view inside the MenuBarExtra label; it loops the status item and starves the main actor.
- **Don't** use exclamation marks, emoji or encouragement in copy. "Leave in 12 min" is the whole voice.
- **Don't** use em dashes anywhere in the interface.
