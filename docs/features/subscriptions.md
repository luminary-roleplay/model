# Feature: subscriptions

Adds fine-grained subscription tracking to a store. It supports **player ID subscriptions** (for synced UIs pushed to multiple clients in real time) and optional **resource subscriptions** (for server-to-server mirrors). When enabled alongside [`sync`](sync.md), only subscribed targets receive updates  nothing is broadcast to players or resources that haven't opted in.

> **Requires:** `sync` feature must also be enabled.

---

## Why use this?

Without subscriptions, every record change is broadcast to **all connected clients**  wasteful and potentially a security issue if some data should only be seen by certain players.

With player subscriptions you can:

- Open a UI on a client and **subscribe** it to receive live updates for the records it cares about
- Have **multiple clients** watching the same record simultaneously; all of them get the diff the moment data changes on the server
- **Unsubscribe** when the UI closes, stopping updates with zero cleanup code needed on the client
- Show different players different subsets of the same store (e.g. a mechanic sees all active jobs, a client sees only their own)

The sync feature pushes only diffs (not full payloads) on each update, so keeping many players subscribed is lightweight.

---

## Configuration

```lua
features = {
    subscriptions = {
        -- 'player' (default), 'resource', or 'both'
        mode = 'player',

        -- Optional override for net/callback prefix; defaults to store.eventName
        eventName = 'jobs',
    },
    -- sync must be enabled for broadcasts to be sent.
    sync = { clients = true },
}
```

`subscriptions = true` is shorthand for `subscriptions = {}` (defaults to `mode = 'player'`).

---

## How it works end-to-end

```
Client opens UI
  └─ ClientModel:subscribe()
       └─ TriggerServerEvent('{eventName}:subscribeAll')
            └─ server: subscribePlayer(src)
            └─ server: sends current snapshot via create events

Server: record data changes (setData / setDataMany)
  └─ sync feature resolves getSubscribedPlayers(id)
  └─ TriggerClientEvent('{eventName}:updateData', subscribedPlayers, id, diff)
       └─ each subscribed client's ClientModel applies the diff
       └─ each UI re-renders with the new data

Client closes UI
  └─ ClientModel:unsubscribe()
       └─ TriggerServerEvent('{eventName}:unsubscribeAll')
            └─ server: unsubscribePlayer(src)
            └─ no more updates sent to that player
```

---

## Real-time UI example

A garage management UI where **any number of mechanics** can have the panel open at once and all see live vehicle status updates.

### Owner resource  server

```lua
-- garage_resource/server/main.lua
local Model = require('@model.imports.model')

local Vehicles = Model.register({
    name       = 'vehicles',
    primaryKey = 'id',
    public     = function(r)
        return { id = r.id, plate = r:get('plate'), status = r:get('status') }
    end,
    features = {
        sync          = { clients = true },
        subscriptions = true,   -- mode = 'player' by default
        client_requests = {
            eventName = 'vehicles',
            allowedRecordMethods = { setStatus = true },
        },
    },
})

-- A mechanic claims a job  update status for everyone watching
RegisterNetEvent('garage:claimJob', function(vehicleId)
    local record = Vehicles:record(vehicleId)
    if not record then return end

    record:setData('status', ('claimed_by_%d'):format(source))
    -- sync feature automatically sends updateData only to subscribed players
end)
```

### Consuming resource  server (optional, for a separate HUD resource)

Not needed for client UIs  use `ClientModel` directly on the client side.

### Consuming resource  client

```lua
-- garage_resource/client/ui.lua
local ClientModel = require('@model.client.model')

local vehicles = ClientModel.connect({
    model    = 'vehicles',
    features = { remote = { autoLoad = false, autoListen = true } },
})

-- Called when the mechanic opens the garage panel
local function openGarageUI()
    -- Subscribe to all vehicles  server sends current snapshot via create events,
    -- then pushes diffs for every subsequent change to any subscribed player.
    vehicles:subscribe()

    -- The local mirror is now populated and stays live.
    -- Pass to NUI or use directly.
    SendNUIMessage({
        action   = 'setVehicles',
        vehicles = vehicles:getAll(),
    })
end

-- Called when the mechanic closes the panel
local function closeGarageUI()
    vehicles:unsubscribe()   -- server stops sending updates to this player
end

-- React to live updates  re-render only when something actually changes
AddEventHandler('vehicles:updateData', function(id, diff)
    -- The ClientModel has already applied the diff to its mirror.
    -- Just push the updated record to the UI.
    SendNUIMessage({
        action  = 'updateVehicle',
        id      = id,
        vehicle = vehicles:get(id),
    })
end)

AddEventHandler('vehicles:delete', function(id)
    SendNUIMessage({ action = 'removeVehicle', id = id })
end)
```

Multiple mechanics can have the panel open simultaneously. Each has their own subscription; the server sends `updateData` to all of them independently whenever any vehicle changes.

### Narrow subscription  single record

If the player only cares about one vehicle (e.g. a status tracker for their own car):

```lua
-- Subscribe to one record only
vehicles:subscribeTo(vehicleId)

-- Unsubscribe when done
vehicles:unsubscribeFrom(vehicleId)
```

The server will only push `create`/`updateData`/`delete` events for that specific record to this player.

---

## Player subscription API

### `store:subscribePlayer(playerId)`
Subscribe a player to all records.

### `store:unsubscribePlayer(playerId)`
Unsubscribe a player from everything. Called automatically on `playerDropped`.

### `store:subscribePlayerTo(playerId, id)`
Subscribe a player to one record.

### `store:unsubscribePlayerFrom(playerId, id)`
Unsubscribe a player from one record.

### `store:isPlayerSubscribed(playerId, id?)`
Returns `true` if the player has a global subscription or a per-record subscription for `id`.

### `store:getSubscribedPlayers(id?)`
Returns an array of player IDs that should receive updates for `id`. Merges global + per-record subscribers.

### `store:serializeForPlayer(playerId, context?)`
Returns `{ [id] = publicData }` for only the records the player is subscribed to. Used internally by the `subscribeAll` handler to send the initial snapshot.

---

## Client net events handled automatically

When player mode is enabled these server-side net event handlers are registered automatically:

| Event | Behavior |
|---|---|
| `{eventName}:subscribeAll` | `subscribePlayer(src)` + send current snapshot via `create` events |
| `{eventName}:unsubscribeAll` | send `delete` for visible records + `unsubscribePlayer(src)` |
| `{eventName}:subscribe` | `subscribePlayerTo(src, id)` + send `create` for that record |
| `{eventName}:unsubscribe` | `unsubscribePlayerFrom(src, id)` + send `delete` for that record |

These map directly to the `ClientModel` client-side helpers:

| Client call | Server event fired |
|---|---|
| `connection:subscribe()` | `{eventName}:subscribeAll` |
| `connection:unsubscribe()` | `{eventName}:unsubscribeAll` |
| `connection:subscribeTo(id)` | `{eventName}:subscribe` |
| `connection:unsubscribeFrom(id)` | `{eventName}:unsubscribe` |

---

## Resource subscription methods

Available when `mode = 'resource'` or `mode = 'both'`. Used for server-to-server mirrors via [`RemoteModel`](../remote-model.md).

### `store:subscribeResource(resourceName)`
Subscribe a resource to all records.

### `store:unsubscribeResource(resourceName)`
Remove all subscriptions for a resource.

### `store:subscribeResourceTo(resourceName, id)`
Subscribe a resource to one record.

### `store:unsubscribeResourceFrom(resourceName, id)`
Remove a per-record subscription for a resource.

### `store:isResourceSubscribed(resourceName, id?)`
Returns `true` if the resource has a global or per-record subscription.

### `store:getSubscribedResources(id?)`
Returns an array of all resource names that will receive updates for `id`.

---

## Subscribing from a server-side mirror resource

Use the [`invoker`](invoker.md) feature to expose subscription management, then call via `RemoteModel`:

```lua
-- Owner resource features config
features = {
    sync          = true,
    subscriptions = { mode = 'resource' },
    invoker = {
        allowedStoreMethods = {
            subscribeResource   = true,
            unsubscribeResource = true,
        },
    },
}
```

```lua
-- Mirror resource
local vehicles = RemoteModel.connect({
    model    = 'vehicles',
    features = {
        proxy  = true,
        mirror = { subscribe = 'all', autoLoad = true },
        -- subscribe = 'all' calls subscribeResource automatically via proxy
    },
})
```

See [Remote Model](../remote-model.md) for the full workflow.

---

## Interaction with sync

When `subscriptions` is active the [`sync`](sync.md) feature resolves targets before every broadcast:

| Broadcast direction | Resolved via |
|---|---|
| Server → clients | `store:getSubscribedPlayers(id)` |
| Server → resources | `store:getSubscribedResources(id)` |

If no players (or resources) are subscribed for a record, no event is fired at all  zero wasted network traffic.
