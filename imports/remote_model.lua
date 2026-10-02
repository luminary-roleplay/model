local Proxy = require('@model.imports.proxy')

local modelResource = 'model'
local currentResource = GetCurrentResourceName()

---@class RemoteConnection: SharedBaseContainer
---@field definition RegisteredModelDefinition
---@field config table
---@field proxy StoreProxy|nil
---@field recordClass table|nil
local RemoteConnection = lib.class('RemoteConnection', require('@model.shared.base_container'))

local RemoteModel = {}

---@param definition RegisteredModelDefinition
---@param config table
function RemoteConnection:constructor(definition, config)
    self:super()

    self.definition = definition
    self.config = config
    self.proxy = config.features.proxy and Proxy(definition.owner, definition.prefix) or nil
    self.recordClass = (config.features.mirror and config.features.mirror.recordClass) or nil

    if config.features.mirror then
        self:_setupMirror(config.features.mirror)
    end
end

--- Setup one remote mirror.
---@param options table
function RemoteConnection:_setupMirror(options)
    local eventName = self.definition.eventName

    if self.definition.features.subscriptions and options.subscribe == 'all' and self.proxy then
        self.proxy:subscribeResource(currentResource)
    end

    if options.autoLoad ~= false then
        self:resync()
    end

    if options.autoListen ~= false then
        AddEventHandler(('%s:create'):format(eventName), function(targetResource, id, payload)
            if targetResource ~= currentResource then return end
            self.records[id] = self:_wrapRecord(id, payload)
        end)

        AddEventHandler(('%s:updateData'):format(eventName), function(targetResource, id, diff)
            if targetResource ~= currentResource then return end
            self:_applyDiff(id, diff)
        end)

        AddEventHandler(('%s:updateState'):format(eventName), function(targetResource, id, diff)
            if targetResource ~= currentResource then return end
            self:_applyDiff(id, diff)
        end)

        AddEventHandler(('%s:delete'):format(eventName), function(targetResource, id)
            if targetResource ~= currentResource then return end
            self.records[id] = nil
        end)
    end
end

--- Reload full snapshot from the owner.
---@return table<any, any>
function RemoteConnection:resync()
    local all = self.proxy:serializeAll()
    self.records = {}

    for id, payload in pairs(all or {}) do
        self.records[id] = self:_wrapRecord(id, payload)
    end

    return self.records
end

RemoteConnection.__index = function(self, key)
    local method = RemoteConnection[key]
    if method ~= nil then
        return method
    end

    -- Unknown methods forward through store proxy.
    if self.proxy then
        local proxyMethod = self.proxy[key]
        if proxyMethod ~= nil then
            return function(_, ...)
                return proxyMethod(self.proxy, ...)
            end
        end
    end
end

RemoteConnection.__newindex = function(self, key, value)
    rawset(self, key, value)
end

--- Connect to a registered remote model.
---@param config {model:string, features:table}
---@return RemoteConnection
function RemoteModel.connect(config)
    assert(type(config) == 'table', 'config must be a table')
    assert(type(config.model) == 'string', 'config.model is required')

    local definition = exports[modelResource]:getModelDefinition(config.model)
    if not definition then
        error(('model "%s" is not registered'):format(config.model), 2)
    end

    local features = config.features or {}

    if features.proxy and not definition.features.invoker then
        error(('model "%s" does not support proxy access'):format(config.model), 2)
    end

    if features.mirror and not definition.features.sync then
        error(('model "%s" does not support mirror sync'):format(config.model), 2)
    end

    if features.mirror and features.mirror.subscribe and not definition.features.subscriptions then
        error(('model "%s" does not support subscriptions'):format(config.model), 2)
    end

    return RemoteConnection:new(definition, {
        features = features,
    })
end

return RemoteModel