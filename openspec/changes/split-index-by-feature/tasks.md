# Tasks

## 1. Baseline

- [ ] Record current `Index.ets` method list and line count.
- [ ] Confirm current tests and app build pass before refactor.
- [ ] Add a small UI smoke checklist for current navigation and key controls.

## 2. Pure Helpers

- [ ] Create `utils/Formatters.ets`.
- [ ] Move byte, time, status, profile/subscription timestamp, and delay display helpers.
- [ ] Create `utils/LocalizationPresenter.ets`.
- [ ] Move core-message localization mapping out of `Index.ets`.
- [ ] Add unit tests for helper outputs.

## 3. Shared Components

- [ ] Create `components/SectionHeader.ets`.
- [ ] Create `components/SettingControls.ets`.
- [ ] Create `components/StatusTiles.ets`.
- [ ] Create `components/LogList.ets`.
- [ ] Replace equivalent builders in `Index.ets`.
- [ ] Build and smoke test.

## 4. Feature Page Components

- [ ] Create `features/servers/ServersPage.ets` and `ServerCard.ets`.
- [ ] Create `features/import/ImportPage.ets` and `ConfigEditor.ets`.
- [ ] Create `features/subscriptions/SubscriptionsPage.ets`, `SubscriptionGroupRow.ets`, and `SubscriptionNodeRow.ets`.
- [ ] Create `features/routing/RoutingPage.ets`.
- [ ] Create `features/settings/SettingsPage.ets`.
- [ ] Create runtime/platform feature pages.
- [ ] Reduce `Index.ets` to shell-level page selection.

## 5. Feature Actions

- [ ] Create connection action coordinator.
- [ ] Create subscription action coordinator.
- [ ] Create import/config action coordinator.
- [ ] Create settings action coordinator.
- [ ] Create delay-test action coordinator.
- [ ] Create diagnostics action coordinator.
- [ ] Add typed result objects for each coordinator.

## 6. State Split

- [ ] Define feature state interfaces.
- [ ] Move state fields from `Index.ets` into feature state groups.
- [ ] Keep state updates explicit and traceable.
- [ ] Avoid introducing broad global mutable state.

## 7. Acceptance

- [ ] `Index.ets` is under 500 lines.
- [ ] No single feature UI file exceeds 400 lines without a reason.
- [ ] Existing behavior is preserved.
- [ ] Unit tests cover extracted pure helpers and action coordinators.
- [ ] App build passes.
- [ ] HAP installs and route/page smoke tests pass.

