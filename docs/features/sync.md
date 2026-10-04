# Feature: sync

Broadcasts record changes to other server resources (via local events) and/or to all connected clients (via `TriggerClientEvent`). Any resource that holds a mirror  either through [RemoteModel](../remote-model.md) or [ClientModel](../client-model.md)  receives live diffs automatically.

---

## Configuration

```lua
features = {
    sync = {
        -- Override the base event name used for broadcasts.
        -- Defaults to store.eventName (which defaults to config.name).
        eventName = 'vehicles',

        -- Also broadcast to all clients with TriggerClientEvent(-1, ...).
        -- Default: false.
        clients = true,

        -- Register the :getAll and :getOne ox_lib callbacks automatically.
        -- Set to false if you want to register them yourself.
        -- Default: true.
        registerCallbacks = true,
    },
}
```

`sync = true` is shorthand for `sync = {}` (all defaults).

### Dependency on `subscriptions`

When the [`subscriptions`](subscriptions.md) feature is also enabled, `sync` targets:

- subscribed resources for server-side local events
- subscribed player IDs for client net events

Without subscriptions, server-side broadcasts are skipped (no resource targets), and client events use global broadcast when `clients = true`.

---

## Events emitted

All events are fired under the configured `eventName` prefix.

### Server-to-server (local events, scoped to subscribed resources)

| Event | Args |
|---|---|
| `{eventName}:create` | `targetResource, id, payload, context` |
| `{eventName}:updateData` | `targetResource, id, diff, context` |
| `{eventName}:updateState` | `targetResource, id, diff, context` |
| `{eventName}:delete` | `targetResource, id, context` |

Listeners in [RemoteModel](../remote-model.md) filter by `targetResource == GetCurrentResourceName()`.

### Server-to-client (net events, when `clients = true`)

| Net event | Args |
|---|---|
| `{eventName}:create` | `id, payload` |
| `{eventName}:updateData` | `id, diff` |
| `{eventName}:updateState` | `id, diff` |
| `{eventName}:delete` | `id` |

These are received by [ClientModel](../client-model.md) listeners automatically. With player subscriptions enabled, each event is emitted only to matching subscribed player IDs.

> `updateData` carries the changed fields plus the new `version` value. `updateState` carries only the changed runtime fields (no version bump).

---

## ox_lib callbacks registered

When `registerCallbacks` is not `false`, two callbacks are registered:

| Callback | Returns |
|---|---|
| `{eventName}:getAll` | `store:serializeAll()` or player-filtered `store:serializeForPlayer(source)` |
| `{eventName}:getOne` | `store:serializeOne(id)` or `nil` when caller is not subscribed |

These are used by `ClientModel.connect()` and `RemoteModel.connect()` to load the initial snapshot.

---

## What triggers a broadcast

| Action | `updateData` | `updateState` | `create` | `delete` |
|---|---|---|---|---|
| `record:setData(key, value)` | ✓ `{ [key]=value, version=N }` | | | |
| `record:setDataMany(values)` | ✓ one diff per changed field, one version | | | |
| `record:setState(key, value)` | | ✓ `{ [key]=value }` | | |
| `record:setStateMany(values)` | | ✓ one diff per changed field | | |
| `store:create(data)` | | | ✓ | |
| `store:delete(id)` | | | | ✓ |

---

## Example: listening for changes in the owning resource

You can still listen to the local events inside the owner resource itself:

```lua
AddEventHandler('vehicles:dataChanged', function(id, key, oldValue, newValue, context, record)
    print(('vehicle %s: %s changed from %s to %s'):format(id, key, oldValue, newValue))
end)

AddEventHandler('vehicles:stateChanged', function(id, key, oldValue, newValue)
    -- runtime-only state changed, e.g. speed, zone
end)
```
