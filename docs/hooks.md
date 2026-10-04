# Hooks

Hooks let you intercept model lifecycle operations for validation, transformation, auditing, and access control.

They are configured on the store via `config.hooks` when calling `Model.define(...)` or `Model.register(...)`.

```lua
local Model = require('@model.imports.model')

local Vehicles = Model.register({
    name = 'vehicles',
    primaryKey = 'id',
    hooks = {
        beforeCreate = function(store, data, context) end,
        afterCreate = function(store, record, context) end,
        beforeSetData = function(store, record, key, value, context) end,
        afterSetData = function(store, record, key, oldValue, newValue, context) end,
        beforeSetState = function(store, record, key, value, context) end,
        afterSetState = function(store, record, key, oldValue, newValue, context) end,
        beforeDelete = function(store, record, context) end,
        afterDelete = function(store, record, context) end,
    },
})
```

## Available hooks

| Hook | Called when | Return behavior |
|---|---|---|
| `beforeCreate(store, data, context)` | before `store:create(data, context)` | `false, reason` rejects create; `true, newData` replaces data |
| `afterCreate(store, record, context)` | after a record is created | return ignored |
| `beforeSetData(store, record, key, value, context)` | before `record:setData` and each key in `setDataMany` | `false, reason` rejects change; `true, newValue` replaces value |
| `afterSetData(store, record, key, oldValue, newValue, context)` | after persisted data change | return ignored |
| `beforeSetState(store, record, key, value, context)` | before `record:setState` and each key in `setStateMany` | `false, reason` rejects change; `true, newValue` replaces value |
| `afterSetState(store, record, key, oldValue, newValue, context)` | after runtime state change | return ignored |
| `beforeDelete(store, record, context)` | before `store:delete(id, context)` | `false, reason` rejects delete |
| `afterDelete(store, record, context)` | after delete | return ignored |

## Context conventions

`context` is optional and passed through from the caller. For client-driven actions (via `client_requests`), context includes fields like:

- `source`  player server ID
- `requestType`  request source (`client_store` / `client_record`)
- `model`  model name
- `id`  record ID (record requests)

You can use this to enforce permissions in hooks.

## Example: validation + normalization

```lua
hooks = {
    beforeCreate = function(store, data)
        if type(data.plate) ~= 'string' or data.plate == '' then
            return false, 'plate is required'
        end

        data.plate = data.plate:upper()
        return true, data
    end,

    beforeSetData = function(store, record, key, value)
        if key == 'plate' then
            if type(value) ~= 'string' or #value > 8 then
                return false, 'invalid plate'
            end

            return true, value:upper()
        end
    end,
}
```

## Example: access control from client requests

```lua
hooks = {
    beforeDelete = function(store, record, context)
        local src = context and context.source

        if not src then
            return false, 'missing source'
        end

        if record:get('owner') ~= GetPlayerIdentifier(src) then
            return false, 'not owner'
        end
    end,
}
```

## Hook execution order

For a persisted update via `record:setData(key, value)`:

1. `beforeSetData`
2. data assignment + version bump + dirty queue
3. `afterSetData`
4. `dataChanged` event + optional sync broadcast

For runtime updates via `record:setState(key, value)`:

1. `beforeSetState`
2. runtime state assignment
3. `afterSetState`
4. `stateChanged` event + optional sync broadcast

## Best practices

- Keep hooks deterministic and fast.
- Use `before*` hooks for validation and shaping input.
- Put side effects (logging, analytics, notifications) in `after*` hooks.
- Return clear reason strings when rejecting writes.
- Prefer `client_requests` authorize callbacks for coarse route-level permission checks, and hooks for record-level business rules.

For full store/record API details, see [Server Model](server-model.md).
