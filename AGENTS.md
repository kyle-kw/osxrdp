# Repository Guidelines

## Project Structure & Module Organization

This is a macOS 12.4+ Xcode project written in C, C++, Objective-C, and Objective-C++. `ServerApp/OSXRDP/` contains the menu-bar server application, Dashboard, settings and permissions UI, screen recording, clipboard, and virtual-display code. Connection state is reduced in `Utils/ConnectionState.*` and coordinated by `Utils/ConnectionStatusCoordinator.*`; UI surfaces observe its notification instead of polling independently. `osxup/` builds the xrdp backend module; `ScreenMirrorLib/` provides shared-memory, IPC, and stream helpers. Login/session orchestration lives in `osxrdp_sessionmanager/`, while `OSXRDPUninstaller/` is the companion removal app. Open `ScreenMirror.xcworkspace` when changing multiple targets. Installer inputs, launchd plists, configuration, images, and build scripts are under `package/`; third-party zlog artifacts are in `extern_lib/`. Lightweight tests live in `tests/`.

## Build, Test, and Development Commands

- `bash tests/run_unit_tests.sh` compiles and runs the C/C++/Objective-C++ unit suite with clang, verifies required English localization keys, and rejects Korean text in repository sources. It requires macOS and Xcode Command Line Tools.
- `xcodebuild -project ServerApp/OSXRDP.xcodeproj -scheme OSXRDP -configuration Debug -destination 'generic/platform=macOS' build` builds the main app for local development when shared-library products and local signing are already available.
- `bash package/build_unsigned.sh` is the authoritative clean build: it builds every target in dependency order for arm64 and x86_64 and creates `package/osxrdp_installer_v*_unsigned.pkg`. This is the same full build exercised by CI and needs no Developer ID certificate.

Do not use `package/build_once.sh` or `package/packaging.sh` unless you have the maintainer's signing identities and notarization profile.

## Coding Style & Naming Conventions

Match the surrounding source: four-space indentation, opening braces on the declaration line, and paired `.h`/`.c`, `.cpp`, or `.mm` files. Use `PascalCase` for C++/Objective-C types, `lowerCamelCase` for variables, leading underscores for C++ fields, and module-prefixed C functions such as `xstream_create` or `ClipProtocol_IsSafeRelativePath`. No repository-wide formatter is configured; keep diffs focused and preserve local conventions. New code should compile cleanly with the Xcode warning settings and the test suite's `-Wall -Wextra` flags.

## UI and State Guidelines

Keep the server as a menu-bar AppKit application. Build the Dashboard, permissions window, and settings window with Auto Layout and native AppKit controls; `Base.lproj/MainMenu.xib` is only bootstrap wiring, so do not reintroduce fixed-frame panels or duplicate Settings/About tabs there. Support the existing 560 × 450 default Dashboard size, its 520 × 420 minimum, window resizing, and both light and dark appearances.

Treat `ConnectionStatusCoordinator` as the single source for diagnostics, desired running state, start/stop actions, and the two-second refresh timer. Add state transitions to the named `ConnectionState` enum and pure reducer helpers rather than magic numbers. Dashboard, menu, permissions, and Diagnostics UI should subscribe to `OSXRDPConnectionStatusDidChangeNotification`; do not add per-view status timers. Keep menu actions and Dashboard actions consistent, and require confirmation only when stopping or quitting an active RDP connection.

Permission requests must preserve existing grants: never add `tccutil reset` to normal setup or retry flows. Use the permission helpers to request access or open the corresponding System Settings pane. Route login-item changes through `StartupManager`, preserve its `Unsupported` / `Disabled` / `RequiresApproval` / `Enabled` distinctions, surface `NSError` failures, and roll switches back when an operation fails.

The project is English-only. Put user-facing strings in `ServerApp/OSXRDP/en.lproj/Localizable.strings`; do not add Korean documentation, `ko.lproj`, or Korean text to repository sources.

## Testing Guidelines

Add focused files named `tests/test_<feature>.<c|cpp|mm>`. Use `TEST_CASE` with descriptive snake-case names and register each case with `RUN_TEST`; add new binaries to `tests/run_unit_tests.sh`. Add every new UI key to the English string catalog and to the required-key checks in `tests/test_strings.sh` where appropriate. State or operation changes should cover permission transitions, automatic startup, deliberate stop persistence, retry behavior, and Ready/Connected transitions in reducer-level tests. There is no numeric coverage threshold, but bug fixes should include a regression test when the affected logic can be isolated.

## Commit & Pull Request Guidelines

Recent history favors short, imperative subjects beginning with verbs such as `Fix`, `Add`, or `Improve`. Keep each commit scoped; use the body to explain behavioral or security-sensitive choices. Pull requests should summarize user-visible impact, list validation performed, link relevant issues, and include screenshots for UI changes. Note the tested macOS/Xcode version and call out changes to signing, launchd plists, IPC trust, or package layout.
