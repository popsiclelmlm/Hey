# Design

## Current Shape

`Index.ets` mixes four responsibilities:

- App shell: navigation, top bar, selected screen.
- Presentation: every page and row/card builder.
- Workflow orchestration: start/stop VPN, import config, update subscriptions, delay tests.
- Formatting/localization glue: timestamps, byte formatting, status labels, translated messages.

This is workable for a prototype but not for a VPN client that will keep gaining pages and advanced settings.

## Target Module Layout

```text
entry/src/main/ets/
  pages/
    Index.ets
  shell/
    AppScreen.ets
    NavigationRail.ets
    TopBar.ets
  components/
    SectionHeader.ets
    SettingControls.ets
    StatusTiles.ets
    LogList.ets
  features/
    servers/
      ServersPage.ets
      ServerCard.ets
      ServerDelayPresenter.ets
      ServerActions.ets
    import/
      ImportPage.ets
      ConfigEditor.ets
      ImportActions.ets
    subscriptions/
      SubscriptionsPage.ets
      SubscriptionGroupRow.ets
      SubscriptionNodeRow.ets
      SubscriptionActions.ets
    routing/
      RoutingPage.ets
      RoutingActions.ets
      RoutingMode.ets
    settings/
      SettingsPage.ets
      SettingsActions.ets
    runtime/
      RuntimePage.ets
      RuntimePanel.ets
      DiagnosticActions.ets
    platform/
      PerAppPage.ets
      AssetsPage.ets
      ScannerPage.ets
      AboutPage.ets
  utils/
    Formatters.ets
    LocalizationPresenter.ets
```

## Refactoring Strategy

### Phase 1: Extract Pure Helpers

Move formatting and presentation helpers out first:

- `formatBytes`
- `formatTime`
- `statusLabel`
- `statusColor`
- `statusBackground`
- `profileSavedText`
- `subscriptionStatusText`
- delay result text/color
- core-message localization mapping

These are low risk because they can be covered by unit tests and do not touch ArkUI component ownership.

### Phase 2: Extract Shared UI Components

Move small reusable UI builders:

- `SectionHeader`
- `SettingToggle`
- `SettingInput`
- `MetricTile`
- `FlagTile`
- `LogPanel`/`LogList`

Prefer plain `@Component` structs with explicit props and callback fields. Keep callbacks narrow, for example `onToggle(action: string)` rather than passing the whole page state.

### Phase 3: Extract Feature Pages With State Still Owned By Index

Move page builders into feature components while `Index.ets` still owns state and passes down:

- data arrays
- selected IDs
- localized labels
- busy flags
- callbacks

This creates clean UI boundaries without changing the state model yet.

### Phase 4: Extract Feature Actions

Move behavior-heavy methods into action/coordinator classes:

- `ConnectionActions.start/stop`
- `SubscriptionActions.update/saveGroup/selectNode`
- `ImportActions.importManualConfig`
- `SettingsActions.persist/changeLanguage`
- `DelayTestActions.testVisibleNodes`
- `DiagnosticActions.refresh/clear`

Each action class should return a typed result object rather than mutating UI state directly. `Index.ets` applies the result to `@State`.

### Phase 5: Split State Models

Only after behavior is stable, introduce feature state objects:

- `ServerState`
- `SubscriptionState`
- `SettingsState`
- `RuntimeState`
- `ImportState`

Do this gradually. Avoid a large "rewrite all state" commit.

## State Ownership Rules

- Stores remain under `storage/`.
- Network/runtime side effects remain under `services/`, `vpn/`, or `native/`.
- Feature UI modules may call only callbacks passed from `Index.ets` during the first extraction phases.
- Feature action modules may call stores/services directly, but must return typed results.
- Shared formatting/localization helpers must stay side-effect free.

## Suggested Commit Slices

1. Extract formatters and localization presenter with tests.
2. Extract shared UI components.
3. Extract servers/import/subscriptions pages.
4. Extract routing/settings pages.
5. Extract logs/runtime/platform placeholder pages.
6. Extract action coordinators.
7. Add focused tests for action coordinators.

Each slice should build and preserve the current UI.

## Risks

- ArkUI callback/prop typing can be strict. Keep component APIs small and explicit.
- Moving too much state at once will create hard-to-debug UI reactivity issues.
- Some builders may be easier to extract after pure helpers are moved.

## Validation

- `hvigorw test`
- `hvigorw assembleApp`
- UI smoke tests:
  - navigation still switches all pages
  - start/stop buttons remain enabled/disabled correctly
  - subscription update and node selection still update config
  - routing mode persists
  - settings persist
  - delay test updates visible node rows

