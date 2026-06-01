# Split Index Page By Feature

## Why

`entry/src/main/ets/pages/Index.ets` has grown to more than 2000 lines and currently owns navigation, all page builders, connection actions, subscription actions, delay testing, settings persistence, logs, formatting, and localization glue.

This makes the app harder to extend safely. Upcoming work such as real per-node proxy delay tests, per-app proxy management, custom routing rules, asset management, QR scanning, backup/restore, and richer Xray config editors will add more state and workflows. Keeping all of that in one ArkUI page will increase merge conflicts, make UI changes risky, and make tests harder to target.

## What Changes

Refactor the application into feature-oriented ArkTS modules while preserving current user-visible behavior.

- Keep `pages/Index.ets` as the composition root: app lifecycle, current screen, dependency wiring, and cross-feature coordination.
- Extract reusable shell and UI pieces:
  - navigation rail
  - top bar
  - section header
  - setting toggle/input
  - metric/status/log tiles
- Extract page-level feature components:
  - servers and delay results
  - import/config editor
  - subscriptions and groups
  - routing modes and strategies
  - settings/language
  - per-app proxy placeholder
  - assets placeholder
  - logs/runtime
  - scanner
  - about
- Extract feature action logic from `Index.ets` into small coordinators:
  - connection actions
  - subscription actions
  - profile/config actions
  - settings actions
  - delay-test actions
  - diagnostics actions
- Add tests around extracted pure logic before moving behavior-heavy code.

## Non-Goals

- Do not redesign the UI in this change.
- Do not change VPN, Xray, tun2socks, subscription, or delay-test behavior.
- Do not replace current persistence stores.
- Do not introduce a global framework or large state-management dependency.
- Do not split into multiple Harmony route pages until feature modules are stable.

## Impact

- `Index.ets` should shrink to a readable app shell and orchestration file.
- Feature work can happen in smaller files with clearer ownership.
- Tests can target config generation, subscription mutation, delay results, and settings separately.
- Future pages can be promoted to real Harmony routes when needed without redoing feature boundaries.

