local Model = require('@model.imports.model')

---@class InvokerFeatureOptions
---@field allowedStoreMethods table<string, boolean>
---@field allowedRecordMethods table<string, boolean>
---@field allowDefaultRecordMethods boolean?

local InvokerFeature = {}

---@param target table
---@param methodName string
---@param allowed table<string, boolean>
---@param options InvokerFeatureOptions
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

    if isRecord and Model.DEFAULT_RECORD_METHODS[methodName] and not options.allowDefaultRecordMethods then
        return false, ('default record method "%s" is not allowed'):format(methodName)
    end

    if allowed and not allowed[methodName] then
        return false, ('method "%s" is not allowed'):format(methodName)
    end

    return true, method
end

---@param options InvokerFeatureOptions?
---@return InvokerFeatureOptions
local function normalizeOptions(options)
    options = options or {}

    options.allowedStoreMethods = options.allowedStoreMethods or {}
    options.allowedRecordMethods = options.allowedRecordMethods or {}
    options.allowDefaultRecordMethods = options.allowDefaultRecordMethods == true

    return options
end

--- Attach store and record exports for cross-resource invocation.
---@param store BaseStore
---@param options InvokerFeatureOptions
function InvokerFeature.attach(store, options)
    options = normalizeOptions(options)

    local exportPrefix = store.prefix:sub(1, 1):upper() .. store.prefix:sub(2)

    store.featureState.invoker = {
        prefix = exportPrefix,
        allowedStoreMethods = options.allowedStoreMethods,
        allowedRecordMethods = options.allowedRecordMethods,
        allowDefaultRecordMethods = options.allowDefaultRecordMethods,
    }

    exports(('invoke%sStore'):format(exportPrefix), function(methodName, ...)
        local ok, methodOrError = resolveCallable(store, methodName, options.allowedStoreMethods, options, false)
        if not ok then
            return nil
        end

        return methodOrError(store, ...)
    end)

    exports(('invoke%sRecord'):format(exportPrefix), function(id, methodName, ...)
        local record = store:record(id)
        if not record then
            return nil
        end

        local ok, methodOrError = resolveCallable(record, methodName, options.allowedRecordMethods, options, true)
        if not ok then
            return nil
        end

        return methodOrError(record, ...)
    end)
end

return InvokerFeature
