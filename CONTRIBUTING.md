# Contributing to model

Thank you for taking the time to contribute. This document covers everything you need to know before opening an issue or pull request.

---

## Table of contents

- [Reporting bugs](#reporting-bugs)
- [Requesting features](#requesting-features)
- [Development setup](#development-setup)
- [Code style](#code-style)
- [Design principles](#design-principles)
- [Pull request process](#pull-request-process)
- [Acknowledgements](#acknowledgements)
- [License](#license)

---

## Reporting bugs

Open an issue and include:

1. **Minimal model config**  the exact `Model.register(...)` call that reproduces the problem
2. **Feature options**  every feature key and its options table
3. **Stack trace or error output**  copy the full server/client console output
4. **Expected vs actual behaviour**  what you expected to happen, and what actually happened
5. **Environment**  FiveM/RedM artifact version, ox_lib version, oxmysql version (if using the `db` feature)

The more specific the reproduction is, the faster it gets fixed.

---

## Requesting features

Open an issue describing:

- The problem you are trying to solve (not just the solution you have in mind)
- Whether it should be a new **feature** (opt-in at `Model.register` time) or a change to the core API
- Any API shape you have in mind

---

## Development setup

1. Clone or copy the resource into your FiveM/RedM server's resource folder:
   ```
   resources/[lib]/model/
   ```

2. Add `ensure model` to your `server.cfg` **before** any resource that depends on it.

3. There is no offline unit-test harness  all testing is done end-to-end against a running `cfx-server`. Create a small test resource that exercises the change and verify behaviour in-game or via server console output.

---

## Code style

| Rule | Detail |
|---|---|
| Indentation | **Tabs**  no spaces |
| Locals | `snake_case` |
| Classes and module tables | `PascalCase` |
| Private fields / methods | Prefix with `_` (e.g. `_applyDiff`, `_setupMirror`) |
| Module return | Every file returns a single table or class |
| Requires | Always use `require('@model.path.to.module')`  no relative paths |
| Globals | **Never.** All state must be local to the module |
| Comments | Only where the logic is non-obvious; don't restate what the code says |

---

## Design principles

### Features are opt-in

New capabilities must be implemented as features attached at `Model.register` / `Model.define` time via `config.features`. Do not add behaviour to `BaseStore`, `ModelRecord`, or the base container classes unless it is truly universal.

A feature file:
- Lives in `imports/features/`
- Exports one table with an `attach(store, options)` function
- Adds methods directly onto the store instance  avoid shared mutable state
- Must be a no-op when disabled (never assume another feature is present unless the docs explicitly declare a dependency)

### Never redefine `__index` or `__newindex` on a `lib.class` subclass

`lib.class` controls these metamethods internally for method dispatch and instance field writes. Overriding them on a subclass breaks things silently  methods stop resolving, `self.field = value` assignments are lost, or you get infinite loops.

- Define all behaviour as normal `:method()` functions
- When you need to write directly to an instance table (e.g. inside a custom accessor), use `rawset(self, key, value)`  not `self[key] = value`

### Server exports vs client callbacks

Server-side exports (`exports('name', fn)`) are **not** accessible from client scripts. Any data a client needs from the model registry must come through a `lib.callback`. Do not add server exports expecting them to work client-side.

### Sync is push-only, diffs only

The `sync` feature sends targeted diffs (`updateData` / `updateState`)  not full record payloads  on every change. Changes to the wire format must preserve this contract. Do not add full-snapshot broadcasts on every write.

### Security  validate on the server

The `client_requests` and `subscriptions` features accept net events from clients. Any new server-side net event handler must:
- Validate `source` before acting (never trust client-provided player IDs)
- Check against an allowlist before calling methods on a store or record
- Rate-limit if it can be triggered arbitrarily

---

## Pull request process

1. **Branch from `main`**  use a descriptive branch name, e.g. `fix/invoker-nil-method` or `feat/db-batch-size-option`
2. **Keep the scope tight**  one fix or one feature per PR; don't mix refactoring with functional changes
3. **Update documentation**  if you add or change a feature option, update the corresponding file in `docs/features/`. If you change the core API, update `docs/server-model.md`, `docs/client-model.md`, or `docs/remote-model.md` as appropriate
4. **Test end-to-end**  confirm the change works against a running FiveM server with the affected feature(s) enabled
5. **Describe what changed and why** in the PR description  not just what files were touched

---

## Acknowledgements

model is built on top of **ox_lib**, without which the class system, callback layer, and a significant amount of the ergonomics here would not exist.

- Original library by [Overextended](https://github.com/overextended/ox_lib)  the foundation everything is built on.
- Active community fork maintained by [CommunityOx](https://github.com/CommunityOx/ox_lib)  **this is the recommended version to use.** It continues to receive updates and community-driven improvements.

If you are setting up a new server or updating an existing one, please use the CommunityOx fork.

---

## License

By contributing you agree that your changes will be released under the same [GNU Lesser General Public License v3.0](LICENSE) that covers this project.
