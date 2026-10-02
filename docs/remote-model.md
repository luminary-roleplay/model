# Remote Model

`RemoteModel.connect()` gives a **server-side** resource access to another resource's model. It supports two independent capabilities:

| Mode | Requires on server | What it does |
|---|---|---|
| `proxy` | [`invoker`](features/invoker.md) feature | Call store/record methods directly via exports |
| `mirror` | [`sync`](features/sync.md) feature | Keep a local in-memory copy, updated by live events |

Both modes can be combined in a single connection.

---

## Manifest setup

```lua
-- fxmanifest.lua  (consuming resource)
dependency 'model'
```

Load modules in code with `require(...)`, e.g. `local RemoteModel = require('@model.imports.remote_model')`.

---

## `RemoteModel.connect(config)`

```lua
local RemoteModel = require('@model.imports.remote_model')

local vehicles = RemoteModel.connect({
    -- Registered model name (must match config.name in the owner resource).
    model = 'vehicles',

    features = {
        -- Enable the store proxy (requires invoker feature on owner).
        proxy = true,

        -- Enable a local mirror (requires sync feature on owner).
        mirror = {
            -- Load a full snapshot immediately. Default: true.
            autoLoad = true,

            -- Register local event listeners for live diffs. Default: true.
            autoListen = true,

            -- Subscribe this resource to all updates at connect time.
            -- Requires subscriptions feature on owner. Default: nil (no auto-subscribe).
            subscribe = 'all',

            -- Custom class to wrap mirrored record payloads.
            recordClass = MyRemoteRecord,
        },
    },
})
```

Returns a `RemoteConnection`.

---

## `RemoteConnection` API

### Local mirror reads (requires `mirror`)

```lua
-- Return the cached public data for one record.
vehicles:get(id)

-- Return { [id] = data } for all cached records.
vehicles:getAll()

-- Return the raw wrapped record (if recordClass is set).
vehicles:record(id)

-- Reload a fresh snapshot from the owner (calls proxy:serializeAll()).
vehicles:resync()
```

### Proxy method calls (requires `proxy`)

Any method not defined on `RemoteConnection` itself is transparently forwarded through the `StoreProxy` to the owner resource's invoker exports:

```lua
vehicles:lock(123)        -- → exports['owner']:invokeVehiclesStore('lock', 123)
vehicles:unlock(123)      -- → exports['owner']:invokeVehiclesStore('unlock', 123)
```

To call a record method via proxy, access the proxy directly:

```lua
local proxy = vehicles.proxy    -- StoreProxy
proxy:record(123):setPlate('NEW')
-- → exports['owner']:invokeVehiclesRecord(123, 'setPlate', 'NEW')
```

> Methods that exist on `RemoteConnection` (like `get`, `getAll`, `record`, `resync`) are **not** forwarded. Only truly unknown keys pass through to the proxy.

### Subscription management (requires `proxy` + `subscriptions` on owner)

```lua
-- Subscribe this resource to all records.
vehicles:subscribeResource(GetCurrentResourceName())
vehicles:unsubscribeResource(GetCurrentResourceName())

-- Subscribe to a single record.
vehicles:subscribeResourceTo(GetCurrentResourceName(), id)
vehicles:unsubscribeResourceFrom(GetCurrentResourceName(), id)
```

These methods are forwarded to the proxy, which in turn calls the owner's `invoker` exports (the subscription methods must be in `allowedStoreMethods`).

When `mirror.subscribe = 'all'` is set, `subscribeResource` is called automatically during `_setupMirror`.

---

## Mirror event lifecycle

The mirror listens to local server events emitted by the owner's `sync` feature and filters by `targetResource == GetCurrentResourceName()`:

```
owner fires:  '{eventName}:create'      → mirror adds record
owner fires:  '{eventName}:updateData'  → mirror applies diff
owner fires:  '{eventName}:updateState' → mirror applies diff
owner fires:  '{eventName}:delete'      → mirror removes record
```

---

## Full example

```lua
-- owner_resource/server/vehicles.lua
local Model = require('@model.imports.model')

local Vehicles = Model.register({
    name       = 'vehicles',
    eventName  = 'vehicles',
    primaryKey = 'id',
    public     = function(r) return { id = r.id, plate = r:get('plate') } end,
    features = {
        sync          = true,
        subscriptions = true,
        invoker = {
            allowedStoreMethods  = { lock = true, unlock = true,
                                     subscribeResource = true, unsubscribeResource = true },
            allowedRecordMethods = { setPlate = true },
        },
    },
})
```

```lua
-- hud_resource/server/main.lua
local RemoteModel = require('@model.imports.remote_model')

local vehicles = RemoteModel.connect({
    model    = 'vehicles',
    features = {
        proxy  = true,
        mirror = { subscribe = 'all' },
    },
})

-- Local read (no network call)
local data = vehicles:get(vehicleId)

-- Proxy call (invokes export on owner_resource)
vehicles:lock(vehicleId)
```
