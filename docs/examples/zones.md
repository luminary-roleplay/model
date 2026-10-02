# Example: a requireable per-resource model library (zones)

A complete example of building a small **library on top of `model`** — not a single resource that owns data, but a `require`-able factory that any resource calls to get its *own* independent store. This is the same shape `model` itself uses (`Model.register`), one layer up: instead of every feature hand-rolling `db`+`sync`+`client_requests`+`hooks` wiring from scratch, they call one function with a name and a permission filter.

A working copy of this lives in this project at `resources/[lib]/zones` — read this page alongside that library's code (`server/zones.lua`, `client/zones.lua`, `client/admin.lua`, `shared/validate.lua`).

---

## The problem this solves

Say three features (banking, restricted areas, delivery points) each want "an admin-editable area, persisted, synced live to every client." Each one *could* call `Model.register` directly and duplicate the same `db`/`sync`/`client_requests`/`hooks` boilerplate — subtly differently each time. Instead, wrap that boilerplate in a small library each of them requires:

```lua
-- banking's server code
local Zones = require('@zones.server.zones')
local BankZones = Zones.register({ name = 'banking_zones', permission = { admin = 0 } })
```

```lua
-- restricted-areas' server code, same library, totally separate table/store
local Zones = require('@zones.server.zones')
local RestrictedZones = Zones.register({ name = 'restricted_zones', permission = { headadmin = 0 } })
```

Each call to `register()` produces its own `model` `BaseStore`, its own Postgres table, its own sync event namespace — they don't share data or collide, the same way two different resources calling `Model.register({ name = 'vehicles' })` and `Model.register({ name = 'houses' })` don't collide.

---

## Why a library instead of one shared owner resource

The first version of this example was a single `zones` *resource* that owned one global `zones` model, and other resources read/wrote it via `exports.zones:*`, filtering by a `category` field. That works, but it has real costs:

- Every feature is forced into the same table shape (`type`/`label`/`category`/`shape`) — adding a feature-specific column means either overloading `shape` (fine for a while) or altering a table shared by everyone.
- Every feature is forced into the same permission model, because `client_requests` is configured once, for the whole shared store.
- The owning resource has to be started before *every* consumer, and consumers depend on its exports being stable — more coupling than "a resource picks a name and calls a function."

A `require`-based library avoids all of that: `Zones.register(config)` runs *inside the calling resource's own Lua environment* (that's what FXv2 OAL's cross-resource `require('@other.path')` actually does — it loads and executes the file's code as part of the caller, not as a call into a separate process). So `GetCurrentResourceName()`, `exports(...)`, and file loads inside the library all resolve to the *calling* resource, not to `zones` itself. Concretely:

- `Model.register({ name = 'banking_zones', ... })` called from inside `require('@zones.server.zones')` registers `banking_zones` with `owner = 'banking'` in `model`'s registry — not `owner = 'zones'`.
- If you called `exports('foo', fn)` from inside a required library module, it would register `foo` as an export of the *calling* resource, not the library.

This is exactly how `model` itself is meant to be consumed — `zones` is just one more layer of the same idea.

---

## Why the library doesn't use `model`'s `db` feature

The `db` feature ([docs](../features/db.md)) is file-path based: `selectAll = 'queries/vehicles/select_all.sql'` etc., loaded via `LoadResourceFile`. But because of the require-executes-in-the-caller behavior above, those file paths would be resolved against *whichever resource called `register()`* — meaning every consumer (`banking`, `restricted-areas`, ...) would need to carry its own copy of near-identical SQL files, just with a different table name hardcoded inside them. That defeats the point of a thin library.

Instead, `zones/server/zones.lua` builds the SQL as plain strings with the table name interpolated (validated against `^[%a_][%w_]*$` first, since you can't bind an identifier as a query parameter — only values), and does the actual reads/writes through `Db.query`/`Db.insert`/`Db.update` directly inside `hooks`, not through the `db` feature:

```lua
local insertSql = ('INSERT INTO %s (type, label, shape, created_by) VALUES (@type, @label, @shape, @created_by) RETURNING id'):format(tableName)

hooks = {
    beforeCreate = function(store, data, context)
        local ok, err = Validate.shape(data.type, data.shape)
        if not ok then return false, err end
        -- ...permission/context handling...

        -- Validate (and any consumer-supplied beforeCreate) MUST run before this —
        -- otherwise a rejected create still leaves an orphaned row in the DB.
        if data.id == nil then
            data.id = Db.insert(insertSql, { type = data.type, label = data.label, shape = json.encode(data.shape), created_by = data.created_by })
        end
    end,
    -- afterSetData / beforeDelete persist the same way — see the full file.
}
```

Startup load is the same trick, done manually instead of via the `db` feature's `dbLoad()`:

```lua
for _, row in ipairs(Db.query(selectAllSql)) do
    local id = row[Zones.config.primaryKey]
    if id ~= nil then
        Zones.records[id] = Zones.recordClass:new(Zones, id, row)
    end
end
```

This directly pokes `store.records`/`store.recordClass` from outside the class — which looks unusual, but it's exactly what `model`'s own `db` feature does internally (see `imports/features/db.lua`'s `dbLoad`). Any external module holding a `BaseStore` instance can do the same; `lib.class` instances don't restrict field access to methods defined on the class itself.

**Tradeoff, stated plainly:** no dirty-batching. Every `setData`/`setDataMany` call writes the full row immediately instead of queuing and flushing on a timer, because there's no `db` feature attached to do that queuing. Fine at admin-edit frequency (this is for zones an admin places, not high-frequency player state); don't reuse this specific persistence approach for something that changes many times per second.

---

## Composing hooks with a consumer's own hooks

Since the library owns `hooks.beforeCreate` etc. (for validation + persistence), a consumer's own `config.hooks.beforeCreate` can't just replace it — it needs to run *in addition to* the library's. The library does this by closing over the consumer's hooks and calling them at the right point:

```lua
beforeCreate = function(store, data, context)
    local ok, err = Validate.shape(data.type, data.shape)
    if not ok then return false, err end

    -- ...set data.created_by...

    if userHooks.beforeCreate then
        local userOk, userErr = userHooks.beforeCreate(store, data, context)
        if userOk == false then return false, userErr end
    end

    -- Only now, after both validations passed, do we write anything.
    if data.id == nil then
        data.id = Db.insert(...)
    end
end,
```

The ordering is the whole point: **validate and let every hook have veto power before doing anything with a side effect (the DB write).** Getting this backwards — inserting first, then letting a hook reject — leaves orphaned rows. This is the kind of bug that's easy to introduce when you first write "insert on create" as an `afterCreate` hook (since that reads naturally) and only surfaces once someone's `beforeCreate` hook actually rejects something.

---

## Consuming from a resource: banking, end to end

**`banking/fxmanifest.lua`**
```lua
dependencies { 'ox_lib', 'utils', 'core', 'model', 'postgres', 'zones' }
shared_scripts { '@ox_lib/init.lua', '@utils/init.lua', '@core/imports/import.lua' }
server_scripts { '@postgres/lib/Postgres.lua' }
```

**`banking/server/main.lua`**
```lua
local Zones = require('@zones.server.zones')

local BankZones = Zones.register({
    name = 'banking_zones',
    permission = { admin = 0 },
    public = function(record)
        return { balance_cap = record:get('balance_cap') }  -- merged into the base payload
    end,
})

-- Seed a zone per configured bank location, idempotently, on startup.
CreateThread(function()
    local haveLabel = {}
    for _, zone in pairs(BankZones:getAll()) do haveLabel[zone.label] = true end

    for _, bank in ipairs(Config.bankLocations) do
        if not haveLabel[bank.label] then
            BankZones:create({
                type = 'sphere',
                label = bank.label,
                shape = { coords = { x = bank.coords.x, y = bank.coords.y, z = bank.coords.z }, radius = 1.5 },
            })
        end
    end
end)
```

**`banking/client/main.lua`**
```lua
local ZonesClient = require('@zones.client.zones')

local BankZones = ZonesClient.connect({
    model = 'banking_zones',
    onEnter = function() utils.showTextUI('[E] Open Bank') end,
    onExit = function() utils.hideTextUI() end,
    inside = function()
        if IsControlJustReleased(0, 38) then
            TriggerServerEvent('banking:openAccount')
        end
    end,
})

require('@zones.client.admin').registerCommands(BankZones, { command = 'bankzone' })
```

That's the entire feature-side integration: no SQL files, no manual sync wiring, no manual zone rebuild loop — `banking` just describes what a bank zone *means* (the interaction) and what extra data it carries (`balance_cap`). `/bankzone create sphere Fleeca` opens `utils.creator`'s visual placement tool and creates the zone on save; `/bankzone edit <id>` reopens it pre-seeded with the existing shape.

---

## ox_lib for zones, `utils` for UI

This library draws the line deliberately: `client/shapes.lua` still builds real `lib.zones.poly/box/sphere` objects for containment/enter/exit detection — there's no reason to reinvent that, ox_lib's zone system is solid. What it *doesn't* use ox_lib for is UI: notifications (`utils.notify` instead of `lib.notify`) and menus (`utils.registerContext`/`utils.showContext` instead of `lib.registerContext`/`lib.showContext`), plus the admin zone-placement flow rides `utils.creator.startZone` — the project's own visual placement tool — rather than a hand-rolled point-capture command loop. Worth internalizing as a general pattern: "don't use library X" rarely means *none* of X, it means whichever *slice* of X the request was actually about — here, UI surface, not the geometry engine underneath it.

## Where this generalizes

The pattern — a `require`-able factory wrapping `Model.register` with sensible defaults for one recurring shape of data — isn't specific to zones. Anywhere you find yourself about to copy-paste the same `db`+`sync`+`client_requests`+`hooks` block into a third resource with only the field names changed, that's the signal to extract a small library like this one instead.
