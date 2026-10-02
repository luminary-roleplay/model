# Server Model

A server-side model is a store of `ModelRecord` instances living in one authoritative resource. Records hold both persisted data and optional runtime-only state. Everything else in the library (sync, subscriptions, invoker, client mirrors) is built on top of this layer.

## Manifest setup

```lua
-- fxmanifest.lua
dependency 'model'
```

Load modules in code with `require(...)`, e.g. `local Model = require('@model.imports.model')`.

---

## `Model.register(config)` vs `Model.define(config)`

| Function | Registry entry | Use when |
|---|---|---|
| `Model.register(config)` | Yes — advertises the model globally | Your resource owns the data |
| `Model.define(config)` | No | Internal/private stores not consumed by other resources |

Both return a `BaseStore` and attach all requested features.

---

## `BaseStoreConfig` reference

```lua
---@class BaseStoreConfig
local config = {
    -- Required
    name       = 'vehicles',     -- unique model name
    primaryKey = 'id',           -- field used as record key

    -- Optional identity overrides
    prefix    = 'vehicles',      -- export prefix for invoker (defaults to name)
    eventName = 'vehicles',      -- base event / callback name (defaults to name)

    -- Optional transform functions
    parse     = function(row)  return row end,  -- called when loading a row (DB → memory)
    serialize = function(data) return data end, -- called when writing to DB (memory → DB)
    runtime   = function(data) return {} end,   -- called to build initial runtime state
    public    = function(record, context)       -- called when serializing for sync/invoker
        return { id = record.id, plate = record:get('plate') }
    end,

    -- Custom classes
    storeClass  = MyStore,    -- replace BaseStore entirely
    recordClass = MyRecord,   -- replace ModelRecord entirely

    -- Feature configuration (see feature docs)
    features = { ... },

    -- Lifecycle hooks
    hooks = { ... },
}
```

---

## `BaseStore` API

### Creating and deleting records

```lua
-- Create a record. Returns (ModelRecord, nil) or (false, errorString).
-- If the db feature is enabled, this will INSERT the row first.
local record, err = store:create({ id = 1, plate = 'ABC123' })

-- Delete a record. Returns (true, nil) or (false, errorString).
-- If the db feature is enabled, this runs the soft-delete query first.
local ok, err = store:delete(1)
```

> `create` requires the primary key field to already be set **unless** the `db` feature provides it from an auto-increment insert.

### Reading records

```lua
-- Returns the record's public data table (via record:toPublic()).
store:get(id)

-- Returns a table of { [id] = publicData } for all records.
store:getAll()

-- Returns the raw wrapped ModelRecord object.
store:record(id)

-- Serialize one record for external use (calls public() config fn if set).
store:serializeOne(id, context?)

-- Serialize all records.
store:serializeAll(context?)
```

### Flushing dirty records

When a record's persisted data is changed via `setData` / `setDataMany`, the record is marked dirty and queued. The `db` feature auto-flushes on a timer, but you can also flush manually:

```lua
-- Flush one record immediately.
store:flushRecord(record, context?)

-- Flush all queued dirty records. Returns the number successfully flushed.
store:flushDirty(context?)
```

### Local change events

Every change fires a local server event you can listen to in the same resource:

| Event | Args |
|---|---|
| `{eventName}:created` | `id, record, context` |
| `{eventName}:deleted` | `id, record, context` |
| `{eventName}:dataChanged` | `id, key, oldValue, newValue, context, record` |
| `{eventName}:stateChanged` | `id, key, oldValue, newValue, context, record` |

---

## `ModelRecord` API

```lua
-- Read a field — checks runtime state first, then persisted data.
record:get(key)

-- Write one persisted field. Returns (true) or (false, errorString).
-- Increments version, marks dirty, fires dataChanged.
record:setData(key, value, context?)

-- Write multiple persisted fields atomically. Single version bump.
record:setDataMany({ plate = 'XYZ', color = 'red' }, context?)

-- Write one runtime-only field (never persisted to DB, but synced).
record:setState(key, value, context?)

-- Write multiple runtime fields.
record:setStateMany({ speed = 120, zone = 'city' }, context?)

-- Trigger an immediate DB flush for this record.
record:save(context?)

-- Get the serialized public representation.
record:toPublic(context?)
```

`record.data` — the raw persisted data table.
`record.state` — the raw runtime-only state table.
`record.id` — the primary key value.
`record.version` — auto-incrementing integer, bumped on every `setData` call.

---

## Hooks

Hooks intercept lifecycle events and can block or transform updates. All hooks receive the store as the first argument.

```lua
hooks = {
    -- Called before create. Return false, reason to abort.
    -- Return true, newData to replace the data table.
    beforeCreate = function(store, data, context)
        if not data.plate then return false, 'plate is required' end
    end,

    afterCreate = function(store, record, context) end,

    -- Called before each setData call.
    -- Return false, reason to reject.
    -- Return true, newValue to replace the incoming value.
    beforeSetData = function(store, record, key, value, context)
        if key == 'plate' and #value > 8 then
            return false, 'plate too long'
        end
    end,

    afterSetData = function(store, record, key, oldValue, newValue, context) end,

    beforeSetState = function(store, record, key, value, context) end,
    afterSetState  = function(store, record, key, oldValue, newValue, context) end,

    beforeDelete = function(store, record, context) end,
    afterDelete  = function(store, record, context) end,
}
```

---

## Extending with custom classes

```lua
local Model = require('@model.imports.model')

---@class VehicleRecord: ModelRecord
local VehicleRecord = lib.class('VehicleRecord', Model.Record)

function VehicleRecord:getPlate()
    return self:get('plate')
end

function VehicleRecord:setPlate(plate)
    return self:setData('plate', plate)
end

local Vehicles = Model.register({
    name        = 'vehicles',
    primaryKey  = 'id',
    recordClass = VehicleRecord,
    -- ...
})
```

Likewise, extend `Model.BaseStore` to add custom store-level methods.

> **Do not define `__index` or `__newindex` on your custom class.**
>
> `lib.class` sets these metamethods internally for method dispatch and field assignment. Assigning `MyRecord.__index = function(...)` or `MyRecord.__newindex = function(...)` directly on a subclass **replaces** the library's handlers and will break things silently — methods may stop resolving, `self.field = value` assignments may be lost, or you may get infinite loops.
>
> Add behaviour by defining normal methods with the `:method()` syntax. If you need to intercept a field write inside a custom accessor, use `rawset(self, key, value)` instead of `self[key] = value`.
