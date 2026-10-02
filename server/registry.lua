---@class RegisteredModelDefinition
---@field name string
---@field owner string
---@field prefix string
---@field eventName string
---@field features table<string, boolean>

---@type table<string, RegisteredModelDefinition>
local models = {}

--- Normalize enabled feature flags.
---@param features table<string, any>?
---@return table<string, boolean>
local function normalizeFeatures(features)
    local output = {}

    for key, value in pairs(features or {}) do
        output[key] = value and true or false
    end

    return output
end

--- Register one model owner globally.
exports('registerModelOwner', function(definition)
    if type(definition) ~= 'table' then
        return false, 'definition must be a table'
    end

    local name = definition.name
    local owner = definition.owner

    if type(name) ~= 'string' or name == '' then
        return false, 'definition.name is required'
    end

    if type(owner) ~= 'string' or owner == '' then
        return false, 'definition.owner is required'
    end

    local existing = models[name]

    -- Prevent multiple owners for the same model.
    if existing and existing.owner ~= owner then
        return false, ('model "%s" is already owned by "%s"'):format(name, existing.owner)
    end

    models[name] = {
        name = name,
        owner = owner,
        prefix = definition.prefix,
        eventName = definition.eventName,
        features = normalizeFeatures(definition.features),
    }

    return true
end)

--- Get one registered model definition.
exports('getModelDefinition', function(name)
    return models[name]
end)

--- Check if a model exists.
exports('hasModel', function(name)
    return models[name] ~= nil
end)

--- Remove a model only if the owner matches.
exports('unregisterModelOwner', function(name, owner)
    local existing = models[name]
    if not existing then
        return false, 'model not found'
    end

    if existing.owner ~= owner then
        return false, ('model "%s" is owned by "%s"'):format(name, existing.owner)
    end

    models[name] = nil
    return true
end)

--- List all registered models.
exports('listModels', function()
    return models
end)

--- Allow clients to fetch a model definition via callback.
lib.callback.register('model:getModelDefinition', function(source, name)
    return models[name]
end)

-- Auto cleanup when an owner resource stops.
AddEventHandler('onResourceStop', function(resourceName)
    for name, definition in pairs(models) do
        if definition.owner == resourceName then
            models[name] = nil
        end
    end
end)

-- Check for updates
lib.versionCheck('luminary-roleplay/model')