# SteadyView for WoW: Forever

Version 0.1.3-beta.

## Installation
Extract the SteadyView directory into the WoW: Forever Interface/AddOns directory. Enter `/steadyview` to open settings or `/steadyview edit` to edit dots.

## Changes
- Dot size now scales from 2 to 100 interface pixels.
- Dot edge band and margin use the configured allowed regions and regenerate random dots when changed. Edge band sets the zone inward from the display edge; margin is the excluded outermost area.
- Manual editing saves each dot position by its current index and accounts for UIParent coordinates.
- Reference line thickness now scales up to 120 interface pixels, with line inset 0–45% and three selectable colors.
- Movement effect test button provides a 5-second visible test; actual movement uses GetUnitSpeed and the chosen threshold.
- Camera settings show status; unavailable CVars are reported as unsupported. Client-specific camera support cannot be guaranteed.

## Diagnostic
Enter `/sv status` in chat to view speed and camera status. Restart WoW after replacing the entire addon directory.

## Limitations
- This beta has not been run in the actual WoW: Forever game client.
- Camera movement detection requires the corresponding game events.
- Custom protected UI zones are not yet editable; only predefined exclusions are used for randomization.
- Compact backup does not include all settings.
- Visual comfort is individual; stop playing if symptoms develop.