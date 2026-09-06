# Tideng

iPad-only SMART on FHIR client. The user enters any FHIR R4 base URL, signs in through
SMART standalone launch, and browses clinical data. No PHI is stored on device beyond
the OAuth token set.

## Layout

```
App/
  project.yml       XcodeGen source of truth — edit this, never the .xcodeproj
  Sources/
    App/            AppRouter, Deeplink, SceneDelegate, AppConfiguration
    Pages/          MVVMC features, one directory each
    Shared/         Business-agnostic infrastructure only
  Resources/        Localizable.xcstrings, assets
  Packages/         FHIRCore, FHIRClient, SmartAuth (local SPM)
Server/             docker-compose for the local FHIR server + Keycloak
```

## Commands

```bash
xcodegen generate                    # REQUIRED after adding/removing/moving any file

# -derivedDataPath build is not optional: the localization step below looks for
# .stringsdata under ./build, and without it Xcode hides them in ~/Library.
xcodebuild -project Tideng.xcodeproj -scheme Tideng \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Tideng.xcodeproj -scheme Tideng \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test CODE_SIGNING_ALLOWED=NO    # app target

cd Packages/<name> && swift test     # package tests
cd ../Server && docker-compose up -d # local SMART launcher (needs `colima start`)
```

## Hard constraints

### Never `import ModelsR4` in app code — use the `FHIR.` namespace

FHIR R4 resource names collide with Swift and Foundation types:

| FHIR resource | collides with | symptom |
|---|---|---|
| `Observation` | Swift Observation framework | `@Observable` fails to expand: *"'Observable' is not a member type of struct 'ModelsR4.Observation'"* |
| `Task` | Swift Concurrency | `Task { }` resolves to the FHIR resource |
| `Bundle` | `Foundation.Bundle` | cannot read app resources |
| `Group` / `Media` / `Signature` | SwiftUI / Foundation | silently resolves to the wrong type |

`FHIRCore` exposes `enum FHIR` with typealiases. Add new ones there instead of importing
`ModelsR4`. A global `@_exported import` is what caused all of the above.

### Swift Testing: `.serialized` only serializes *within* one suite

Different suites still run in parallel. Tests that share static state (the `URLProtocol`
stubs) must be nested under a single `.serialized` parent suite — otherwise they overwrite
each other's stubbed responses and fail in ways that point nowhere near the real cause.

### Nested `#require` does not compile

`try #require(f(try #require(x)))` → *"recursive expansion of macro"*. Split into two lines.

### The SMART launcher base URL needs the `sim` segment

```
http://localhost:8090/v/r4/sim/e30/fhir
                            ^^^ base64url("{}") — minimal launch options
```

Without it, discovery **still succeeds** but authorize fails with
`Invalid launch options: SyntaxError: Unexpected end of JSON input`. The failure surfaces
only when the user taps sign-in, far from its cause.

### iPad orientation

All four orientations are declared. `UIRequiresFullScreen` is deprecated as of iPadOS 26
and orientation locks are being phased out — do not reintroduce one. The window minimum
size is set in `SceneDelegate` instead.

## Localization

Base language is `en`; `zh-Hant` is a translation. `SWIFT_EMIT_LOC_STRINGS` must stay `YES`
— with it off, only the legacy extractor runs and it recognizes just `Text("literal")`,
so `Button` / `Label` / `TextField` / `ContentUnavailableView` strings get mass-flagged stale.

Workflow — **keys belong to the compiler, values belong to you**. Never invent a key:

```bash
# 1. write English literals directly inside Text() / String(localized:)
# 2. build (produces .stringsdata)
# 3. sync them into the catalog — repeat --stringsdata per file, it is not space-separated
find build/Build/Intermediates.noindex/Tideng.build -name '*.stringsdata'
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata <f1> --stringsdata <f2> ...
# 4. fill in zh-Hant for the keys that appeared; clear stale ones
```

Done means **stale = 0 and untranslated = 0**.

Literals must sit directly inside `Text()` / `String(localized:)`. Passing a
`LocalizedStringKey` as a parameter lands it in `__PotentialKeys` and gets it flagged stale —
someone cleaning up by the warning then deletes a live translation.

### What the app may localize, and what it may not

The app owns the *label* for a thing it can identify; it does not own the server's data.
Two rules, and the boundary between them is not obvious:

- **Names** are keyed off the LOINC `code`, never the server's `display` — the same vital
  arrives as English, an abbreviation or blank depending on the server. Unknown code falls
  back to `display`.
- **Units** are keyed off the UCUM `Quantity.code`, never the LOINC code. A unit says what
  the number *is*. Deriving it from the observation type would render a server's 100.4 °F
  as 100.4 °C — that is altering the value's meaning, not translating it. Unknown UCUM code
  falls back to the server's `Quantity.unit` string.

Only rate units actually differ by locale (`/min` is written 次/分 in Taiwanese charting);
`°C`, `%`, `mmHg` are universal but still go through the catalog so a future locale has
somewhere to change them.

Things that deliberately stay untranslated (`shouldTranslate: false`): the example URL
`https://example.org/fhir` and the `client_id` field name — translating them would leave the
user unsure what to type.

Packages carry no UI copy. `FHIRClientError` / `SmartAuthError` expose a `description` for
logs and `serverDiagnostics` for the server's own wording; `Sources/Shared/ErrorMessage.swift`
maps cases to localized text.

## Architecture

Features follow the MVVMC skills (`mvvmc-structure`, `-model`, `-viewmodel`, `-view`,
`-hostcontroller`, `-navigation`). Project-specific points:

- **FHIRModels types are the DTO layer.** Each feature declares its own domain model and
  converts in `<Feature>ViewModel+Models.swift`. Conversion lives on the domain model side
  (`init?(resource:)`), not as an extension on the FHIR type — extending `FHIR.Patient`
  would leak it to every other feature in the module.
- **`FHIRClient` knows nothing about auth.** It takes a `TokenProviding`; `SmartAuth`
  implements it. Dependency direction is `SmartAuth → FHIRClient`, never the reverse.
- **FHIRModels is pinned `exact: "0.9.3"`.** Siming must stay on the same version.
