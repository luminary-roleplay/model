# Features Overview

This page gives a quick summary of each model feature and when to use it.

## At a glance

| Feature | Purpose | Typical use |
|---|---|---|
| [`db`](features/db.md) | Persist records to MySQL with periodic dirty flushing | Any authoritative store that must survive restarts |
| [`sync`](features/sync.md) | Broadcast create/update/delete changes to mirrors and clients | Live UI/state updates |
| [`subscriptions`](features/subscriptions.md) | Target sync delivery to subscribed players (or resources) | Per-player synced UIs and reduced fanout |
| [`invoker`](features/invoker.md) | Expose allowlisted store/record methods as exports | Cross-resource server calls without custom events |
| [`client_requests`](features/client-requests.md) | Allow clients to request allowlisted store/record actions | Controlled client-driven updates |

## How they fit together

- `sync` is the delivery layer for model changes.
- `subscriptions` scopes that delivery so updates go only to subscribed targets.
- `db` handles persistence and dirty flushing of persisted fields.
- `invoker` enables server-to-server method calls.
- `client_requests` enables client-to-server method calls with rate limiting and authorization hooks.

## Common stacks

### Server-authoritative persisted model with synced UI

Use:
- `db`
- `sync` (with `clients = true`)
- `subscriptions` (player mode)
- `client_requests` (for limited client actions)

### Cross-resource shared model (server-only)

Use:
- `sync`
- `subscriptions` (`resource` or `both` mode)
- `invoker`

### Minimal in-memory model

Use:
- no features, or just `sync` if you only need live propagation

## Full worked example

- [DB-persisted, live-synced zones](examples/zones.md) — combines `db`, `sync`, `client_requests`, and `hooks` for a real server-authoritative-area feature, with a working copy of the resource in this project.

## Notes

- Features are opt-in via `config.features` when creating the store.
- You can combine features in the same model.
- `subscriptions` requires `sync`.
- Player-mode subscriptions are designed for “only update this player’s UI when subscribed” flows.
- Hooks are configured separately via `config.hooks`; see [Hooks](hooks.md).

For API details and configuration options, use the per-feature docs linked above.
