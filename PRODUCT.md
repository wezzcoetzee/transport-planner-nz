# Product

## Register

product

## Users

Auckland commuters deciding when to stop working and walk to the bus. They glance at the menu bar throughout the afternoon and occasionally open the popover. The settings window is visited once at setup and rarely after.

Context: a Mac with the menu bar always visible, often in a bright office, sometimes in a dim one. The commuter is mid-task in another app. The interaction budget is one glance or one click.

## Product Purpose

Show the single moment to leave so commuters arrive at the stop just before the bus, never waiting fifteen minutes. Secondary: show the next best option if they miss it, and why that option was picked (route, walk, arrival home).

Success: commuters trust the countdown enough to stop checking the AT app. The tool disappears into the commute.

## Brand Personality

Calm, precise, quiet.

Voice is a terse colleague who knows the timetable: "Leave in 12 min", "195 from Lower Albert at 5:05, home 5:23". Numbers carry the meaning; words only label them. No exclamation marks, no encouragement, no emoji.

References: Linear for restraint and typographic hierarchy; Apple Weather and Stocks for glanceable, numbers-first native surfaces.

## Anti-references

- AT Mobile and Google Maps transit: coloured route pills, maps, decorative iconography, route branding as ornament.
- Generic SaaS dashboards: cards inside cards, a hero metric with a small label, gradient accents, light-grey subtitle lines above sections.
- Anything that needs reading rather than glancing.

## Design Principles

1. **One number first.** The time to leave is the whole product. Everything else is supporting evidence and sits visually below it.
2. **Evidence, not decoration.** A route number, a stop name, an arrival time earn their place because they explain the recommendation. Nothing appears for texture.
3. **Native by default.** System typography, standard macOS controls, standard settings layout. Familiarity is the affordance; there is nothing to learn.
4. **Quiet until it matters.** The menu bar label is static and terse. Notifications are the only interruption, and only at the configured moments.
5. **Dense and dark.** A core design constraint: true black background, white primary text, information-dense, no card or pill chrome. This overrides any generic guidance against pure black.

## Accessibility & Inclusion

macOS defaults are sufficient: respect Dynamic Type, Reduce Motion, and Increase Contrast. Provide VoiceOver labels on icon-only buttons. No continuously repainting animation, ever, regardless of system settings (high-refresh display, GPU cost).
