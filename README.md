# model

A standalone, modular data-model library for FiveM/RedM. It provides a structured, server-authoritative store of typed records with optional persistence, cross-resource synchronisation, and client mirroring — all wired together through a central registry.

> **This library is intended for experienced Lua and FiveM/RedM developers.** It assumes a solid understanding of the FiveM/RedM resource system, server/client boundaries, net events, exports, and `ox_lib`. Issues asking for general scripting help or "how do I use Lua" will be closed without response. If you are just getting started with FiveM/RedM development, this is not the right starting point.

## Requirements

| Requirement | Required |
|---|---|
| `ox_lib` | Yes |
| `postgres` | Must be running when using the `db` feature (the `db` module talks to `Postgres.*`/`exports.postgres`, not `oxmysql`) |

## Installation

Add `model` to your resource manifest **before** the resource that consumes it:

```lua
-- fxmanifest.lua (consuming resource)
dependency 'model'
```

Then load modules directly in your Lua code via `require(...)`, for example:

```lua
local Model = require('@model.imports.model')
local Db = require('@model.imports.db')
local ClientModel = require('@model.client.model')
```

### Paged loading for large data sets

`model` ships built-in paging helpers so resources with large stores can avoid sending the entire dataset in a single net transfer.

**Server** — register a paged callback from your store-owner resource (no `require` needed; `registerPagedCallback` is an model export):

```lua
-- server/vehicles.lua
exports.model:registerPagedCallback('vehicles:getPage', {
    getItems = function(source)
        return Vehicles:getAllArray()     -- return the full in-memory list; model slices it
    end,
    map = function(record, source)
        return record:toPublic()         -- each item must embed the primary key (e.g. { id = ..., ... })
    end,
})
```

**Client** — either use the standalone paging loader:

```lua
-- client/vehicles.lua
local Paging = require('@model.client.paging')

local items, usedPaging = Paging.loadPagedDataset('vehicles:getPage', 150, function(item)
    return item
end)
```

Or use the built-in `resyncPaged()` on a `ClientModelConnection`:

```lua
local ClientModel = require('@model.client.model')

local vehicles = ClientModel.connect({ model = 'vehicles', features = { remote = { autoLoad = false } } })
local records, usedPaging = vehicles:resyncPaged({ primaryKey = 'id', pageSize = 150 })
-- falls back to vehicles:resync() automatically if the paged callback is unavailable
```

## Core Concepts

```
┌────────────────────────────────────────────────────────┐
│  model (registry)                                   │
│  Tracks: name → { owner, eventName, features }        │
└────────────────────────────────────────────────────────┘
         ▲                              ▲
         │ registerModelOwner           │ getModelDefinition
         │                              │
┌────────┴──────────┐       ┌──────────┴──────────────┐
│  Owner resource   │       │  Consumer resource       │
│  Model.register() │       │  RemoteModel.connect()   │
│  BaseStore        │──────▶│  RemoteConnection        │
│  ModelRecord      │ sync  │  (mirror + proxy)        │
└───────────────────┘       └─────────────────────────-┘
         │ TriggerClientEvent
         ▼
┌─────────────────────────┐
│  Client resource        │
│  ClientModel.connect()  │
│  ClientModelConnection  │
└─────────────────────────┘
```

**BaseStore** — Lives in the owning server resource. Holds all `ModelRecord` instances in memory, fires local change events, and drives optional features.

**ModelRecord** — A single item inside a store. Separates *persisted data* (written to DB, synced) from *runtime state* (in-memory only, also synced).

**Registry** — A small global service running inside `model` itself. Every store that calls `Model.register()` advertises its name, owner, and feature flags so other resources can discover it.

**Features** — Opt-in capabilities attached to a store at creation time:

| Feature | Summary |
|---|---|
| [`db`](docs/features/db.md) | Persist records to MySQL via oxmysql |
| [`sync`](docs/features/sync.md) | Broadcast changes to server resources and/or clients |
| [`subscriptions`](docs/features/subscriptions.md) | Per-player and/or per-resource subscription targeting |
| [`invoker`](docs/features/invoker.md) | Expose store/record methods as exports to other server resources |
| [`client_requests`](docs/features/client-requests.md) | Let clients call store/record methods over net events (rate-limited) |

## Quick Example

```lua
-- server/vehicles.lua  (owner resource)
local Model = require('@model.imports.model')

local Vehicles = Model.register({
    name       = 'vehicles',
    eventName  = 'vehicles',
    primaryKey = 'id',

    parse     = function(row) return row end,
    serialize = function(data) return data end,
    public    = function(record) return { id = record.id, plate = record:get('plate') } end,

    features = {
        db = {
            selectAll = 'queries/vehicles/select_all.sql',
            update    = 'queries/vehicles/update.sql',
        },
        sync          = { clients = true },
        subscriptions = true,
        invoker = {
            allowedStoreMethods  = { lock = true, unlock = true },
            allowedRecordMethods = { setPlate = true },
        },
        client_requests = {
            allowedStoreMethods  = {},
            allowedRecordMethods = {},
        },
    },
})
```

```lua
-- client/vehicles.lua
local ClientModel = require('@model.client.model')

local vehicles = ClientModel.connect({ model = 'vehicles' })

-- vehicles:get(id)      → public payload table
-- vehicles:getAll()     → table<id, payload>
-- vehicles:resync()     → reload full snapshot from server
```

## Documentation

- [Features Overview](docs/features.md) — High-level guide to feature roles and common stacks
- [Server Model](docs/server-model.md) — `BaseStore`, `ModelRecord`, hooks, `define` vs `register`
- [Hooks](docs/hooks.md) — Lifecycle hook reference, return semantics, and examples
- [Client Model](docs/client-model.md) — `ClientModel.connect`, mirroring, client requests
- [Remote Model](docs/remote-model.md) — Server-to-server proxy and mirror via `RemoteModel.connect`
- [Client State](docs/client-state.md) — Pure client-side local state (no server involvement)
- **Examples**
  - [DB-persisted, live-synced zones](docs/examples/zones.md) — full worked example combining `db` + `sync` + `client_requests` + `hooks`
- **Features**
  - [db](docs/features/db.md)
  - [sync](docs/features/sync.md)
  - [subscriptions](docs/features/subscriptions.md)
  - [invoker](docs/features/invoker.md)
  - [client-requests](docs/features/client-requests.md)

## Acknowledgements

This library is built on **ox_lib**, the excellent FiveM/RedM utility library that powers the class system, callbacks, and much of the ergonomic foundation here.

- **[Overextended/ox_lib](https://github.com/overextended/ox_lib)** — The original library
- **[CommunityOx/ox_lib](https://github.com/CommunityOx/ox_lib)** — The active community fork with ongoing updates (recommended)

If you're setting up a new server, use the CommunityOx version.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
