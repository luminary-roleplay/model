# Feature: invoker

Exposes store and record methods as FiveM/RedM **exports** so other server resources can directly call them without raw event wiring. Access is restricted to an explicit allowlist, and private methods (prefixed with `_`) are always blocked.

The generated exports are named `invoke{Prefix}Store` and `invoke{Prefix}Record`, where `Prefix` is `config.prefix` (defaults to `config.name`).

---

## Configuration

```lua
features = {
    invoker = {
        -- Store methods callable by other resources.
        allowedStoreMethods = {
            lock   = true,
            unlock = true,
        },

        -- Record methods callable by other resources.
        allowedRecordMethods = {
            setPlate = true,
            setOwner = true,
        },

        -- Allow the built-in default record methods (get, setData, setDataMany,
        -- setState, setStateMany, save, toPublic). Default: false.
        allowDefaultRecordMethods = false,
    },
}
```

`invoker = true` is **not** valid  you must always supply the allowlists.

---

## Generated exports

Given `config.prefix = 'vehicles'` (or `config.name = 'vehicles'`):

```lua
-- Call a store method
exports['owner_resource']:invokeVehiclesStore(methodName, ...args)

-- Call a record method
exports['owner_resource']:invokeVehiclesRecord(id, methodName, ...args)
```

Both exports return whatever the underlying method returns, or `nil` on access denial.

---

## Using a `StoreProxy`

Instead of calling raw exports, consuming resources can use the `Proxy` helper which wraps the exports and forwards any unknown method call transparently:

```lua
-- consuming_resource/server/vehicles.lua
local Proxy = require('@model.imports.proxy')

local vehicles = Proxy('owner_resource', 'Vehicles')  -- note: capitalised prefix

-- Calls exports['owner_resource']:invokeVehiclesStore('lock', 123)
vehicles:lock(123)

-- Get a record proxy
local record = vehicles:record(123)

-- Calls exports['owner_resource']:invokeVehiclesRecord(123, 'setPlate', 'NEW')
record:setPlate('NEW')
```

Or use [RemoteModel.connect](../remote-model.md) with `features.proxy = true`, which builds the proxy automatically.

---

## Access rules

| Scenario | Allowed |
|---|---|
| Method name starts with `_` | ❌ Always blocked |
| Method not in `allowedStoreMethods` / `allowedRecordMethods` | ❌ Blocked |
| Method in allowlist | ✓ |
| Default record methods with `allowDefaultRecordMethods = true` | ✓ |
| Default record methods without that flag | ❌ Blocked even if listed |

Default record methods include: `constructor`, `get`, `setData`, `setDataMany`, `setState`, `setStateMany`, `save`, `toPublic`.

---

## Full example (owner resource)

```lua
local Model = require('@model.imports.model')

---@class VehicleRecord: ModelRecord
local VehicleRecord = lib.class('VehicleRecord', require('@model.imports.model').Record)

function VehicleRecord:lock()
    return self:setState('locked', true)
end

function VehicleRecord:unlock()
    return self:setState('locked', false)
end

local Vehicles = Model.register({
    name        = 'vehicles',
    primaryKey  = 'id',
    recordClass = VehicleRecord,
    features = {
        invoker = {
            allowedStoreMethods  = {},
            allowedRecordMethods = { lock = true, unlock = true },
        },
    },
})
```

```lua
-- another_resource/server/main.lua
local Proxy = require('@model.imports.proxy')
local vehicles = Proxy('owner_resource', 'Vehicles')

vehicles:record(vehicleId):lock()
```
