# UI Architecture Spec

## ADDED Requirements

### Requirement: Feature-Oriented UI Modules

The app SHALL organize ArkUI page presentation by feature area instead of keeping all page builders in `pages/Index.ets`.

#### Scenario: Server list UI changes

- **WHEN** a developer modifies server row display, delay labels, or node selection controls
- **THEN** the primary files involved SHALL be under `features/servers/`
- **AND** unrelated settings, subscription, routing, and runtime UI files SHALL not need edits.

#### Scenario: Settings UI changes

- **WHEN** a developer adds a new persistent app setting
- **THEN** the page UI SHALL live under `features/settings/`
- **AND** persistence SHALL remain under `storage/SettingsStore.ets`
- **AND** config generation impact SHALL remain under `core/XrayConfig.ets`.

### Requirement: Thin Index Composition Root

`pages/Index.ets` SHALL be responsible for app shell composition and cross-feature coordination only.

#### Scenario: Open Index file

- **WHEN** a developer opens `pages/Index.ets`
- **THEN** it SHALL show lifecycle hooks, navigation state, top-level state wiring, and active feature page selection
- **AND** it SHALL not contain every feature's row/card/page builder.

### Requirement: Side Effects Outside Presentation Components

Presentation components SHALL not directly call stores, native bridge APIs, VPN APIs, or network services.

#### Scenario: Delay test button clicked

- **WHEN** the user taps delay test
- **THEN** the server page component SHALL call a callback
- **AND** a feature action/coordinator SHALL perform the service/store work
- **AND** the UI SHALL receive updated state from the composition root.

### Requirement: Incremental Refactor Safety

The refactor SHALL preserve existing behavior after each committed slice.

#### Scenario: Intermediate refactor commit

- **WHEN** a refactor slice is committed
- **THEN** unit tests SHALL pass
- **AND** `assembleApp` SHALL pass
- **AND** the main navigation and key workflows SHALL remain usable.

