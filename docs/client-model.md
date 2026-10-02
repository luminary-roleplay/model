# Client Model

`ClientModel.connect()` creates a client-side mirror of a server-owned model. It loads an initial snapshot via an ox_lib callback and then keeps itself up-to-date by listening to net events pushed by the server's [`sync`](features/sync.md) feature.

It also provides helpers to fire requests at the server via the [`client_requests`](features/client-requests.md) feature.

---

## Manifest setup

```lua
-- fxmanifest.lua  (the resource that uses the client model)
dependency 'model'
```

Load modules in code with `require(...)`, e.g. `local ClientModel = require('@model.client.model')`.

---

## `ClientModel.connect(config)`

```lua
local ClientModel = require('@model.client.model')

local vehicles = ClientModel.connect({
    -- Name of the registered model (must match the server owner's config.name).
    model = 'vehicles',

    -- Feature options. Defaults to { remote = true } when omitted.
    features = {
        remote = {
            -- Load a full snapshot when connect() is called. Default: true.
            autoLoad = true,

            -- Register net event listeners for live updates. Default: true.
            autoListen = true,

            -- Custom record class used to wrap incoming payloads.
            -- Defaults to the base ClientRecord.
            recordClass = MyClientRecord,
        },
    },
})
```

Returns a `ClientModelConnection`.

> `connect` errors immediately if the model is not registered or if it does not have the `sync` feature enabled on the server.

---

## `ClientModelConnection` API

### Reading data

```lua
-- Returns the public data table for one record (or nil).
vehicles:get(id)

-- Returns { [id] = data } for all currently mirrored records.
vehicles:getAll()

-- Returns the raw wrapped record object (ClientRecord instance if recordClass is set).
vehicles:record(id)
```

### Resyncing

```lua
-- Discard the current mirror and reload a fresh snapshot from the server.
-- Uses lib.callback.await internally.
vehicles:resync()
```

### Requesting server-side actions

These all fire net events and return `true` immediately (fire-and-forget). The server executes the method if the [`client_requests`](features/client-requests.md) feature allows it.

```lua
-- Call any method on the store.
vehicles:requestStore(methodName, ...)

-- Call any method on a specific record.
vehicles:requestRecord(id, methodName, ...)

-- Built-in convenience wrappers (call requestStore internally):
vehicles:lock(id)
vehicles:unlock(id)
```

### Subscriptions

When the server has the [`subscriptions`](features/subscriptions.md) feature enabled, you can narrow down which records you receive updates for:

```lua
-- Subscribe to one record.
vehicles:subscribeTo(id)
vehicles:unsubscribeFrom(id)

-- Subscribe/unsubscribe from all records.
vehicles:subscribe()
vehicles:unsubscribe()
```

---

## Custom record class

Extend the base `ClientStateRecord` to attach helpers to individual records:

```lua
local ClientRecord = require('@model.client.record')

---@class MyVehicleRecord: ClientRecord
local MyVehicleRecord = lib.class('MyVehicleRecord', ClientRecord)

function MyVehicleRecord:getPlate()
    return self.data.plate
end

function MyVehicleRecord:isLocked()
    return self.data.locked == true
end
```

```lua
local vehicles = ClientModel.connect({
    model    = 'vehicles',
    features = {
        remote = { recordClass = MyVehicleRecord },
    },
})

local record = vehicles:record(someId)
if record and record:isLocked() then ... end
```

> **Do not define `__index` or `__newindex` on your custom record class.**
>
> `lib.class` controls these metamethods internally. Overriding them on a subclass breaks method dispatch and field assignment. Define all behaviour as normal `:method()` functions. If you need to write directly to the instance table (e.g. when caching a result inside `__index`), use `rawset(self, key, value)` — never `self[key] = value`.

---

## Mirror vs `remote` feature key

`config.features.remote` and `config.features.mirror` are treated identically by `ClientModelConnection`. The `remote` key is the conventional name for client-side usage; `mirror` is an alias also accepted for consistency with the server-side [RemoteModel](remote-model.md) API.

---

## Lifecycle of a mirror

```
connect()
  └─ lib.callback.await('{eventName}:getAll')  → initial snapshot
       └─ records populated

server fires:
  '{eventName}:create'      → records[id] = wrapped payload
  '{eventName}:updateData'  → merge diff into records[id].data
  '{eventName}:updateState' → merge diff into records[id].data
  '{eventName}:delete'      → records[id] = nil

resync()
  └─ records cleared, snapshot reloaded
```

The version field in `updateData` diffs is used to skip out-of-order packets — if the incoming `version` is lower than what is already stored, the diff is discarded.
