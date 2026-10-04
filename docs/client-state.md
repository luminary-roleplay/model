# Client State

`ClientState` is a **pure client-side** local state system  no server involvement whatsoever. It allows one client script (the *owner*) to maintain a keyed collection of records and other client scripts in the same resource (or different resources) to mirror those records through local events.

This is useful for things like NUI state, per-player UI data, or any ephemeral client-side collection that multiple scripts need to observe.

---

## Concepts

| Role | Class | Created by |
|---|---|---|
| Owner | `ClientStateOwner` | `ClientState.register(config)` |
| Mirror | `ClientStateMirror` | `ClientState.connect(config)` |

Local events are scoped with `:local` to avoid collisions with net events. All events also carry an `ownerResource` field so multiple owners using the same `eventName` do not interfere.

---

## Manifest setup

```lua
-- fxmanifest.lua
dependency 'model'
```

Load modules in code with `require(...)`, e.g. `local ClientState = require('@model.client.state')`.

---

## Owner  `ClientState.register(config)`

```lua
local ClientState = require('@model.client.state')

local playerState = ClientState.register({
    -- Unique identifier for this state bus.
    eventName = 'playerState',

    -- Optional custom record class (defaults to ClientStateRecord).
    recordClass = MyStateRecord,
})
```

### Owner methods

```lua
-- Create a record. The data table must contain the key used as `id`.
-- Returns the wrapped record.
playerState:create({ id = 'health', value = 100 })

-- Update a record. Merges diff into record.data.
-- Returns true on success or false if the record doesn't exist.
playerState:update('health', { value = 80 })

-- Delete a record. Returns true on success.
playerState:delete('health')

-- Read (inherited from SharedBaseContainer)
playerState:get('health')      -- public data table
playerState:getAll()           -- { [id] = data }
playerState:record('health')   -- raw wrapped record
```

Internally, `create` and `update` also fire `{eventName}:local:create` / `update` / `delete` so any mirrors are notified immediately.

When a mirror asks for a sync (`requestSync` event), the owner responds with a full `serializeAll()` snapshot.

---

## Mirror  `ClientState.connect(config)`

```lua
local ClientState = require('@model.client.state')

local playerMirror = ClientState.connect({
    -- Must match the owner's eventName.
    eventName = 'playerState',

    -- Resource name that owns this state. Defaults to the current resource
    -- when used within the same resource as the owner.
    resource = GetCurrentResourceName(),

    -- Optional custom record class.
    recordClass = MyStateRecord,

    -- Load a snapshot immediately at connect time. Default: true.
    autoLoad = true,

    -- Register local event listeners. Default: true.
    autoListen = true,
})
```

### Mirror methods

Mirrors are read-only  they receive the owner's changes but cannot push updates.

```lua
playerMirror:get('health')    -- returns public data or nil
playerMirror:getAll()         -- { [id] = data }
playerMirror:record('health') -- raw wrapped record

-- Discard current state and request a fresh snapshot from the owner.
playerMirror:resync()
```

---

## Local event bus

| Event | Fired by | Args |
|---|---|---|
| `{eventName}:local:create` | Owner `create()` | `ownerResource, id, payload` |
| `{eventName}:local:update` | Owner `update()` | `ownerResource, id, diff` |
| `{eventName}:local:delete` | Owner `delete()` | `ownerResource, id` |
| `{eventName}:local:requestSync` | Mirror `resync()` | `targetResource` |
| `{eventName}:local:reset` | Owner (on sync request) | `targetResource, snapshot` |

Mirrors filter events by `ownerResource` to ensure they only react to their designated owner. `reset` events are filtered by `targetResource` so only the requesting mirror applies the snapshot.

---

## Example

```lua
-- client/hud_state.lua  (owner)
local ClientState = require('@model.client.state')

local hudState = ClientState.register({ eventName = 'hudState' })

hudState:create({ id = 'money',  value = 0 })
hudState:create({ id = 'health', value = 100 })

-- Later, update a value:
hudState:update('money', { value = 5000 })
```

```lua
-- client/nui_bridge.lua  (mirror in the same resource)
local ClientState = require('@model.client.state')

local hud = ClientState.connect({
    eventName = 'hudState',
    resource  = GetCurrentResourceName(),
})

-- Observe the current snapshot at any time:
local money = hud:get('money')
SendNUIMessage({ type = 'updateMoney', value = money and money.value or 0 })

-- Or react to live events:
AddEventHandler('hudState:local:update', function(ownerResource, id, diff)
    if id == 'money' then
        SendNUIMessage({ type = 'updateMoney', value = diff.value })
    end
end)
```
