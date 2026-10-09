# Underlog

A native iOS dive log, built with SwiftUI, SwiftData and Swift Charts.

## Features

- **Dive log**: dive list grouped by trip or month, search across sites, buddies, trips and notes.
- **Dive details**: max and average depth, duration, temperature, SAC, gas, buddies, notes, rating and a map of the site.
- **Profile chart**: depth over time with scrub-to-read values, and an audio graph for VoiceOver.
- **Manual entry and editing**: sites, trips, buddies, cylinders and gas mixes (air, nitrox, trimix), conditions and rating.
- **Import**: Garmin FIT activities (for example from a Descent dive computer, exported from Garmin Connect) and UDDF files.
- **Export**: the whole log as UDDF, an open format other dive logs can read.
- **Statistics**: totals, deepest and longest dives, dives per year, depth distribution.
- **Gas tools**: maximum operating depth, ppO₂, equivalent narcotic and air depth, best nitrox mix, surface air consumption.
- **Units**: metric or imperial; salt, fresh or EN 13319 water.
- **Accessibility**: VoiceOver labels throughout, Dynamic Type, accessible charts, 44 pt touch targets.

## Project layout

| Folder | Contents |
|---|---|
| `App/` | The SwiftUI app: models, screens, assets |
| `UnderlogCore/` | Platform-independent Swift package: dive maths, units, profile storage, FIT and UDDF import/export |
| `UITests/` | XCUITest end-to-end tests |
| `project.yml` | XcodeGen project definition (the `.xcodeproj` is generated, not committed) |

## Requirements

- macOS with Xcode 26 or later
- iOS 26 or later on the device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting started

```sh
xcodegen generate
open Underlog.xcodeproj
```

In Xcode, select your team under **Signing & Capabilities** to run on a device, then press Run.
Change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if you want a different bundle identifier.

## Tests

```sh
# Core logic (also runs on Linux)
swift test --package-path UnderlogCore

# UI tests
xcodebuild test -project Underlog.xcodeproj -scheme Underlog -destination 'platform=iOS Simulator,name=iPhone 17'
```

The UI tests launch the app with `-ui-testing`, which uses an in-memory log seeded with sample dives
(add `-empty-log` for an empty one), so they never touch real data.

## Continuous integration

- **Core tests** run on Linux for every change to `UnderlogCore/`.
- **iOS app** builds on a macOS runner when app code changes on `main`. UI tests run when started manually
  from the Actions tab with "Also run the UI tests" ticked, or when a pushed commit message contains `[ui-tests]`.

## Licence

All rights reserved. See [LICENSE](LICENSE).
