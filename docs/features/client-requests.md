# Feature: client_requests

Registers `RegisterNetEvent` handlers that let clients call store and record methods over the network. All requests are validated against an allowlist, private methods are always blocked, and a sliding-window rate limiter protects the server from abuse.

This feature pairs with [ClientModel](../client-model.md)'s `requestStore` / `requestRecord` helpers on the client side.

---

## Configuration

```lua
features = {
    client_requests = {
        -- Override the base event name.
        -- Defaults to store.eventName (which defaults to config.name).
        eventName = 'vehicles',

        -- Store methods clients are allowed to call.
        allowedStoreMethods = {
            lock   = true,
            unlock = true,
        },

        -- Record methods clients are allowed to call.
        allowedRecordMethods = {
            setColor = true,
        },

        -- Also allow the built-in default record methods.
        -- Default: false. See invoker docs for the list of default methods.
        allowDefaultRecordMethods = false,

        -- Sliding-window rate limit applied per source, per method key.
        -- Default: 8 calls per 1 000 ms.
        rateLimit = {
            limit    = 8,
            windowMs = 1000,
        },

        -- Optional: called before a store method is executed.
        -- Return false to deny. Return nothing (nil) to allow.
        authorizeStoreMethod = function(source, store, methodName, ...)
            if methodName == 'lock' and not isAdmin(source) then
                return false
            end
        end,

        -- Optional: called before a record method is executed.
        -- Return false to deny. Return nothing (nil) to allow.
        authorizeRecordMethod = function(source, store, record, methodName, ...)
            -- Only allow the record owner to modify it.
            if record:get('owner') ~= GetPlayerIdentifier(source) then
                return false
            end
        end,
    },
}
```

---

## Net events registered

| Net event | Payload | Handled call |
|---|---|---|
| `{eventName}:requestStore` | `methodName, ...args` | `store[methodName](store, ..., context)` |
| `{eventName}:requestRecord` | `id, methodName, ...args` | `record[methodName](record, ..., context)` |

The `context` table injected as the final argument always contains:

```lua
{
    source      = src,              -- player server ID
    requestType = 'client_store' | 'client_record',
    model       = store.name,
}
```

Your store/record methods can inspect `context.source` to identify the requesting player.

---

## Security model

Requests are rejected (silently dropped) when any of the following are true:

1. `source` is not a real client ( ≤ 0).
2. The rate limit is exceeded for this source + method key.
3. `methodName` starts with `_`.
4. The method does not exist on the store / record.
5. The method is a default record method and `allowDefaultRecordMethods` is `false`.
6. The method is not in the corresponding allowlist.
7. The `authorizeStoreMethod` / `authorizeRecordMethod` callback returns `false`.

For `requestRecord`, requests for non-existent record IDs are also silently dropped.

---

## Rate limiting details

The limiter uses a per-source, per-key sliding window (reset on first touch per window):

- **Store requests** key: `store:{methodName}`
- **Record requests** key: `record:{id}:{methodName}`

Rate limit state is cleaned up automatically when a player disconnects (`playerDropped`).

---

## Client-side usage

```lua
-- client/my_script.lua
local ClientModel = require('@model.client.model')

local vehicles = ClientModel.connect({ model = 'vehicles' })

-- Fire-and-forget store method
vehicles:requestStore('lock', vehicleId)

-- Fire-and-forget record method
vehicles:requestRecord(vehicleId, 'setColor', 'red')

-- Convenience wrappers already provided by ClientModelConnection:
vehicles:lock(vehicleId)    -- → requestStore('lock', vehicleId)
vehicles:unlock(vehicleId)  -- → requestStore('unlock', vehicleId)
```

See [Client Model](../client-model.md) for the full client-side API.
