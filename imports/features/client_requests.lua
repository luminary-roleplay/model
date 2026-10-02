local Model = require('@model.imports.model')

---@class ClientRequestsFeatureOptions
---@field eventName string?
---@field allowedStoreMethods table<string, boolean>
---@field allowedRecordMethods table<string, boolean>
---@field allowDefaultRecordMethods boolean?
---@field rateLimit {limit:number, windowMs:number}?
---@field authorizeStoreMethod fun(source:number, store:BaseStore, methodName:string, ...:any): boolean?
---@field authorizeRecordMethod fun(source:number, store:BaseStore, record:ModelRecord, methodName:string, ...:any): boolean?

local ClientRequestsFeature = {}

---@return number
local function now()
    return GetGameTimer()
end

---@param buckets table<number, table<string, table>>
---@param source number
---@param key string
---@return table
local function getBucket(buckets, source, key)
    local bySource = buckets[source]
    if not bySource then
        bySource = {}
        buckets[source] = bySource
    end

    local bucket = bySource[key]
    if not bucket then
        bucket = {
            count = 0,
            resetAt = 0,
        }
        bySource[key] = bucket
    end

    return bucket
end

---@param state table
---@param source number
---@param key string
---@param limit number
---@param windowMs number
---@return boolean
local function checkRateLimit(state, source, key, limit, windowMs)
    if not limit or limit <= 0 then
        return true
    end

    local bucket = getBucket(state.rateLimits, source, key)
    local current = now()

    if current >= bucket.resetAt then
        bucket.count = 0
        bucket.resetAt = current + windowMs
    end

    bucket.count = bucket.count + 1

    if bucket.count > limit then
        return false
    end

    return true
end

---@param target table
---@param methodName string
---@param allowed table<string, boolean>
---@param options ClientRequestsFeatureOptions
---@param isRecord boolean
---@return boolean, function|string
local function resolveCallable(target, methodName, allowed, options, isRecord)
    if type(methodName) ~= 'string' or methodName == '' then
        return false, 'invalid method name'
    end

    if methodName:sub(1, 1) == '_' then
        return false, ('method "%s" is private'):format(methodName)
    end

    local method = target[methodName]

    if type(method) ~= 'function' then
        return false, ('method "%s" does not exist'):format(methodName)
    end

    -- Block base record methods unless explicitly allowed.
    if isRecord and Model.DEFAULT_RECORD_METHODS[methodName] and not options.allowDefaultRecordMethods then
        return false, ('default record method "%s" is not allowed'):format(methodName)
    end

    if allowed and not allowed[methodName] then
        return false, ('method "%s" is not allowed'):format(methodName)
    end

    return true, method
end

---@param source any
---@return boolean
local function isRealClientSource(source)
    return type(source) == 'number' and source > 0
end

---@param options ClientRequestsFeatureOptions?
---@return ClientRequestsFeatureOptions
local function normalizeOptions(options)
    options = options or {}

    options.allowedStoreMethods = options.allowedStoreMethods or {}
    options.allowedRecordMethods = options.allowedRecordMethods or {}
    options.allowDefaultRecordMethods = options.allowDefaultRecordMethods == true
    options.rateLimit = options.rateLimit or {
        limit = 8,
        windowMs = 1000,
    }

    return options
end

--- Attach safe client request handlers.
---@param store BaseStore
---@param options ClientRequestsFeatureOptions
function ClientRequestsFeature.attach(store, options)
    options = normalizeOptions(options)
    local eventName = options.eventName or store.eventName

    store.featureState.clientRequests = {
        eventName = eventName,
        rateLimits = {},
    }

    -- Clean request rate state on disconnect.
    AddEventHandler('playerDropped', function()
        store.featureState.clientRequests.rateLimits[source] = nil
    end)

    RegisterNetEvent(('%s:requestStore'):format(eventName), function(methodName, ...)
        local src = source

        -- Only allow actual client net requests.
        if not isRealClientSource(src) then
            return
        end

        local state = store.featureState.clientRequests
        local rate = options.rateLimit

        if not checkRateLimit(state, src, ('store:%s'):format(tostring(methodName)), rate.limit, rate.windowMs) then
            return
        end

        local ok, methodOrError = resolveCallable(store, methodName, options.allowedStoreMethods, options, false)
        if not ok then
            return
        end

        if type(options.authorizeStoreMethod) == 'function' then
            local allowed = options.authorizeStoreMethod(src, store, methodName, ...)
            if allowed == false then
                return
            end
        end

        methodOrError(store, ..., {
            source = src,
            requestType = 'client_store',
            model = store.name,
        })
    end)

    RegisterNetEvent(('%s:requestRecord'):format(eventName), function(id, methodName, ...)
        local src = source

        -- Only allow actual client net requests.
        if not isRealClientSource(src) then
            return
        end

        id = tonumber(id)
        if not id then
            return
        end

        local record = store:get(id)
        if not record then
            return
        end

        local state = store.featureState.clientRequests
        local rate = options.rateLimit

        if not checkRateLimit(state, src, ('record:%s:%s'):format(id, tostring(methodName)), rate.limit, rate.windowMs) then
            return
        end

        local ok, methodOrError = resolveCallable(record, methodName, options.allowedRecordMethods, options, true)
        if not ok then
            return
        end

        if type(options.authorizeRecordMethod) == 'function' then
            local allowed = options.authorizeRecordMethod(src, store, record, methodName, ...)
            if allowed == false then
                return
            end
        end

        methodOrError(record, ..., {
            source = src,
            requestType = 'client_record',
            model = store.name,
            id = id,
        })
    end)
end

return ClientRequestsFeature