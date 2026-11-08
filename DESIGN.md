---
name: NZ Transport Planner
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
    height: "620px"
---

# Design System: NZ Transport Planner

## 1. Overview

**Creative North Star: "The Departure Board"**

A station departure board seen from across a dark concourse. The surface is unlit black; the only things that exist are the characters the board has chosen to light. The next departure is brightest, the ones after it are dimmer, and nothing else is on. Every glyph is information: a time, a route number, a stop name, a walk. There is no frame around the board and no decoration on it, because a board that decorated itself would be a worse board.

That metaphor sets the density and the restraint. The popover is a single column of services, 360 points wide, read top to bottom in the order you could catch them. Hierarchy comes from three things only: weight, brightness and position. The recommended journey is full white and semibold with every leg shown; alternatives collapse to one line each at 60% brightness. Color appears in the popover as two lamps only: green for "Live" when realtime data is flowing, orange for a late bus or an error. Both are the size of a caption.

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
- **Dimmed White** (#FFFFFF at 55%, SwiftUI `.secondary`): supporting evidence. Walk legs, arrival lines, status lines, explanatory captions in Settings.
- **Alternative rows** are white at 60% row opacity (85% under Increase Contrast), not a third grey, and never combine with Dimmed White: two dimming steps would drop small text below 4.5:1.

### Semantic
- **Live Green** (#30D158, system green): the "Live" badge only, meaning realtime delays are being applied. Delays under three minutes are not printed at all, so a late bus is never shown in the "good" color.
- **Delay Orange** (#FF9F0A, system orange): a delay of three minutes or more, a realtime error, a failing setting. Never for emphasis.

### Named Rules
**The Two Lamps Rule.** Inside the popover and leave panel, green and orange are the only chromatic colors permitted; the panel's default button is tinted neutral grey. Settings keeps the system accent on its stock controls, because native beats custom there. Each is caption-sized, each means one state, neither is ever used for decoration or emphasis. Route colors from the GTFS feed are ignored.

**The Menu Bar Exception.** The status item is the one place urgency is colored, because it is read from across the screen: orange from 10 minutes out, Go Red (#FF453A, system red) at the leave time. Nothing else uses red.

**The Unlit Rule.** The background is #000000 and stays there. Hierarchy is created by turning text down, never by turning the surface up.

## 3. Typography

**Display Font:** none. There is no display tier.
**Body Font:** SF Pro Text via `-apple-system` (falls back to system-ui)
**Label/Mono Font:** same family with tabular figures (`monospacedDigit()`) on every time and duration

**Character:** the native macOS voice at its most literal. Nothing is styled to look like a headline; the headline is just the largest, heaviest line on the board.

### Hierarchy
- **Headline** (semibold 600, 15px, SwiftUI `.title3`): the single leave statement. "Leave in 12 min", "Leave now", "Leave at 5:03 pm". Tabular digits so the number does not jitter as it counts down.
- **Title** (12px, `.callout`): the leave time in every row, semibold on the recommended row and regular on alternatives.
- **Body** (regular 400, 13px, `.body`): settings labels and form controls. Not used in the popover.
- **Label** (regular 400, 10px, `.caption`): everything else on the board: legs, route numbers (semibold), home times, delay figures, the Apple Maps estimate, status badges, explanatory captions.

### Named Rules
**The Tabular Rule.** Any glyph that represents a time, a count of minutes or a distance uses tabular figures. Proportional digits in a countdown are a defect.

**The Three Steps Rule.** The popover uses exactly three sizes: headline, title for leave times and the footer answers, and label for everything else. Adding a fourth size is adding noise.

## 4. Elevation

Flat, tonal only. The popover has no shadows, no dividers inside it, no inset panels, and no borders except the single small remedy button and the keyboard focus outline. Depth is conveyed by brightness: full white is nearest, dimmed white is behind it, 60% alternative rows are behind that. The single `Divider()` above the footer is the only rule on the board and separates actions from information.

Settings use the stock macOS grouped form, which brings its own tonal grouping. Do not add to it.

### Named Rules
**The Flat Board Rule.** Nothing on the board casts a shadow and nothing has an outline. If a row needs a box to be readable, the row has too much in it. The leave panel is the one exception: it floats over other apps, so it keeps the system window shadow, a hairline edge and 10 point corners.

## 5. Components

### Popover
Character: the board itself. 360 points wide, 12 point padding on every side, 10 point spacing between the headline, journey block and footer. Black background, dark color scheme forced regardless of system appearance.

### Headline
Leave statement at headline weight, left aligned, with the realtime badge on the same baseline at the far right. When no journey is recommended the status message takes the headline slot in the same weight: "Starting", "Set up your commute", "Set your office", "Set your home", "Downloading timetable", "Preparing timetable", "Timetable not downloaded yet", "Timetable download failed", "Timetable needs re-downloading", "No stops near the office" or "home", "All stops near the office are off" (or "home"), "No services between 4:40 and 5:30 pm", "No more services today", "No later option today", "Could not plan a route", "No commute today", "Not today", "On your way", "Done for today". Away from the office, the countdown gives way to "Away from the office" with "Reminders paused" as a dimmed caption, and the rows stay beneath it (an Apple Maps estimate is hidden, since it describes leaving from somewhere else). After Going, "On your way" keeps the chosen bus beneath it in the leave panel's two lines until its arrival time, then reads "Done for today". When only the Apple Maps estimate is available, the headline is that estimate ("Leave at ~5:02 pm") and the status moves to the caption beneath it.

### Journey Row
Character: a board row. A 62 point leave-time column, then the legs, with times trailing at the right edge. Row times are board clocks without am/pm ("4:52"), like the menu bar; the headline, sentences, notifications and VoiceOver keep the full time.
- **Recommended:** full detail. Leave time in title weight. Walk legs in dimmed label with the figure.walk symbol ("5 min walk", no metres). The walk home is left out; the "home" time already includes it. Ride legs as two label lines: mode symbol, route number and the time the bus leaves the stop in semibold, then on the first bus a delay of three minutes or more in orange ("4 min late") (the headsign is hover help only: the stop line gives the direction); then "board stop → alight stop", wrapping to a second line rather than truncating a stop name, with the dimmed "home" time trailing on that last line so the row reads in travel order. No duration; it is the gap between the two times already on the row.
- **Delays** read like a departure board: a late bus shows its timetable time with "4 min late" in orange beside it. Delays under three minutes are not printed; the leave and home times already include them, and the Live badge says realtime is applied. A delay always sits on the bus, never beside "home".
- **Alternative:** one line at 60% opacity: leave time in regular weight, route numbers ("OUT → NX2") in semibold, "from" and the boarding stop, and the mode symbol, only when they differ from the recommended row's (route numbers keep their width; the stop name truncates first), and the bare home time trailing (the recommended row above names the column). A delay of three minutes or more sits after the route numbers in full-strength orange outside the dimming. Up to four shown.
- **VoiceOver:** each row is one element read as a sentence: "Leave 5:02 pm, INN 5:08 pm from Lower Albert Street, 4 min late, home 5:23 pm". The recommended row adds the walk to the stop and where to get off.
- **Padding:** 4 points vertical, none horizontal. No background, no border.

### Footer Actions
Character: words, not buttons. Title-sized (`.callout`) text buttons in primary white (never the system accent), so the answers are never the smallest text on the board,, each with a hit area taller than its text in a single row, showing only what would do something now: Going (semibold, the primary answer; only from 10 minutes out, so "yes, that bus" twenty minutes early cannot end the day) and Next (with a plan), Previous (only while an option is skipped; steps back one at a time), Not today (with a plan or estimate) or Undo (once the day is settled; Previous and Undo never show together), Next and Previous are kept short so the widest state (Going, Next, Previous, Not today) fits on one line beside the icons. Trailing icon-only buttons for Maps (map, once both places are set), Refresh (arrow.clockwise, once set up; the last update time is its help text), Settings (gearshape) and Quit (power). Icon-only buttons carry VoiceOver labels and help text; Refresh, Settings and Quit have R, comma and Q shortcuts. The same action has the same name in the popover, the leave panel and notifications; reminders from 10 minutes out (and the leave-now and missed ones) add Going; earlier ones offer only Next and Not today.
- **Pressed and disabled:** the word dims (60% pressed, 40% disabled). No hover color.
- **Focus:** a quiet hairline outline in primary white at 50%, since the custom style draws no system ring.
- **Next** is disabled, with help text saying why, when no later option exists; the leave panel follows the same rule.

### Badges
Caption-sized text with an optional SF Symbol, never a pill, shown only beside a plan. "Live" in green with the radio-waves symbol (help text gives the time of the last update; Settings states it in dimmed text, since green belongs to the badge), "Live unavailable" in orange with the warning triangle when realtime failed. When the AT key was rejected it is a borderless button that opens Settings on the Data tab; when the API is unreachable it is plain text, since there is nothing to fix. Without an AT key there is no badge.

### Fallback Block
When the timetable cannot plan at all (not downloaded yet, no usable stops, a failed plan), the Apple Maps estimate becomes the headline and counts down like a plan, marked approximate ("Leave in ~14 min", spoken "about"; "~14m" in the menu bar, "Go" at zero) and two label lines sit beneath it: "Apple Maps estimate, home 5:22 pm" and the dimmed reason. During the first download the reason follows the import live ("Timetable 42% downloaded", "Preparing timetable"); without an estimate the headline carries the status ("Downloading timetable", "Timetable download failed") and the progress is the caption. When the timetable answered but has nothing to catch ("No services between 4:40 and 5:30 pm", "No more services today", "No later option today"), there is no estimate: it would invent a bus, often tomorrow's. An estimate that departs on another day is dropped. The headline and all its captions (estimate, reason, "Reminders paused", the orange "Timetable is 9 days old. Latest download failed" with its download button beside it) form one block with 2 point spacing. When the status has a single remedy (Open Settings, Retry download, Open Route for either place) it follows as the popover's only bordered button, at small control size like the leave panel's. The notification and location Fix buttons use the same small bordered style.

### Leave Panel
A floating black panel under the status item with the system shadow, a hairline edge and 10 point corners, since it sits over arbitrary windows. The headline counts down like the popover's. Two label lines: "INN 5:08 pm from Lower Albert Street" in white with an orange delay after it from three minutes, then "home 5:23 pm" dimmed (", 1 transfer" when there is one). It follows realtime changes to the same trip while open. Going (semibold, default, Return once the panel is clicked, tinted neutral grey) and Next as small bordered buttons because the panel waits for an answer; Not today borderless and dimmed at the trailing edge, the dismissive choice. VoiceOver announces it when it appears.

### Settings Forms
Stock macOS `Form` with `.formStyle(.grouped)`, three tabs, 520 points wide; Commute and Route are 620 tall so they never scroll, Data is 380 so the window fits the tab: Commute (places, leave window, days, reminders, launch at login), Route (transfers, time at the stop, "Stops within … 600 m", walking pace; then the stops near each place with the walk time the popover uses, and one timetable status row with its download button while there is no timetable), Data (timetable status as "Downloaded 4 Nov" with the timetable version in its help, or "Downloaded 4 Nov. Latest download failed"; a small bordered button on that same row, only when it would fix something (failed or missing), named for what it will do ("Download", "Retry download"; the popover uses the same name); a refused login item gets an orange caption with an Open button for Login Items; a failed status in orange; the AT key with "Working, checked 2:05 pm" directly beneath, and sign-up help only while the key is empty or rejected). A failed refresh with a timetable on disk stays in the Data tab until that timetable is over a week old; then the popover shows the orange note under the headline. Launch at login reflects what macOS actually registered. Stepper labels read like stock settings: the noun leading, the value trailing ("Stops within … 600 m", "Walking pace … 5 km/h"), optional detail dimmed after it. Sliders are not used; their tick marks are noise. Warnings about notifications and location appear only once both places are set, which is also when the app asks for those permissions (never while the user is still typing the home address), and the location line speaks only when it changes reminders (away, off, too vague). Labels are plain nouns without colons; the leave window shows clock times ("Earliest 4:40 pm, 20 min before") so nobody does arithmetic. Standard `DatePicker`, `Stepper`, `Picker`, `Toggle`, `SecureField`. Weekday and reminder-lead ("Remind": "20 min", "15 min", "10 min", "5 min", "Now") selectors are small button-style toggles in a row whose VoiceOver labels are the visible words, with the detail as a hint; with Now off a dimmed caption says nothing pops up at the leave time. The place search field shows the chosen place as labelled content with a borderless Change button, or a labelled rounded-border text field with the hint as its placeholder and up to five completion rows directly beneath the field as borderless buttons. Office is focused when Settings opens empty. "No matches" shows dimmed after typing pauses; a failed lookup says so in orange. Return picks the first row; Cancel or Escape keeps the saved place. Explanatory text is caption-sized and dimmed. Nothing here is custom.

On first launch, before the commute is set, Settings opens by itself on the Commute tab.

### Menu Bar Label
An SF Symbol for the mode (bus, tram, ferry) followed by a terse countdown: "12m", "Go", or a clock time without am/pm ("5:05") from 60 minutes out, the same threshold as the headline. VoiceOver hears the full sentence ("Leave in 12 minutes"). At Go the symbol becomes figure.walk. Other states change the symbol only: checkmark.circle when on your way, moon when there is nothing more today (Not today, no commute today, no services left), the plain bus before setup (so a new user can find the app) and away from the office (VoiceOver tells the two apart), arrow.down.circle while the first timetable downloads, warning triangle when the timetable failed or no stops are usable, and a bus with "~14m" when the Apple Maps estimate is standing in. Titles stay this short, with tabular digits, so the status item barely changes width. Every state is one rendered image with the same geometry: a template when calm, orange or red otherwise, switching to the system's darker orange (#C93400) and red (#D70015) on a light menu bar. An Apple Maps estimate escalates the same way as a plan. VoiceOver reads "Done for today" once the chosen bus has arrived. Static; the model updates it just after each minute boundary of the countdown (every 30 seconds otherwise), in step with the popover. No TimelineView, no animation.

## 6. Do's and Don'ts

### Do:
- **Do** keep the background #000000 in both the popover and Settings. Never raise it to a grey.
- **Do** carry hierarchy with weight (600 vs 400) and brightness (100%, 55%, 60% row opacity) only.
- **Do** use tabular figures on every time, minute count and metre count.
- **Do** keep green for "Live" only, orange for delays of three minutes or more and for errors, and use each at caption size only.
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
- **Don't** end interface text with a full stop. Two sentences in one line are joined with ". " and the last one stays open: "Away from the office. Reminders paused".
