---@class ClientModelConnection: SharedBaseContainer
---@field definition RegisteredModelDefinition
---@field config table
---@field recordClass table
local ClientModelConnection = lib.class('ClientModelConnection', require('@model.shared.base_container'))

local ClientModel = {}

---@param definition RegisteredModelDefinition
---@param config table
function ClientModelConnection:constructor(definition, config)
    self:super()

    self.definition = definition
    self.config = config
    self.recordClass = (config.features.remote and config.features.remote.recordClass)
        or (config.features.mirror and config.features.mirror.recordClass)
        or require('@model.client.record')

    self:_setup(config.features)
end

--- Setup client mirror/proxy behavior.
---@param features table
function ClientModelConnection:_setup(features)
    local mirrorOptions = features.remote or features.mirror or {}
    local eventName = self.definition.eventName

    if mirrorOptions.autoLoad ~= false then
        self:resync()
    end

    if mirrorOptions.autoListen ~= false then
        RegisterNetEvent(('%s:create'):format(eventName), function(id, payload)
            self.records[id] = self:_wrapRecord(id, payload)
        end)

        RegisterNetEvent(('%s:updateData'):format(eventName), function(id, diff)
            self:_applyDiff(id, diff)
        end)

        RegisterNetEvent(('%s:updateState'):format(eventName), function(id, diff)
            self:_applyDiff(id, diff)
        end)

        RegisterNetEvent(('%s:delete'):format(eventName), function(id)
            self.records[id] = nil
        end)
    end
end

--- Reload full snapshot from server.
---@return table<any, any>
function ClientModelConnection:resync()
    local all = lib.callback.await(('%s:getAll'):format(self.definition.eventName), false)
    self.records = {}

    for id, payload in pairs(all or {}) do
        self.records[id] = self:_wrapRecord(id, payload)
    end

    return self.records
end

--- Reload full snapshot using paged loading to avoid large single-transfer payloads.
--- Requires the store owner to have registered a paged callback at '{eventName}:getPage'
--- via exports.model:registerPagedCallback(...). Each item returned by the paged
--- callback must embed the primary key under the field named by `options.primaryKey`
--- (defaults to 'id').
---@param options {pageSize?: integer, primaryKey?: string, callbackName?: string}?
---@return table<any, any> records
---@return boolean usedPaging True when paged loading succeeded; false when it fell back to resync.
function ClientModelConnection:resyncPaged(options)
    local opts = options or {}
    local eventName = self.definition.eventName
    local callbackName = opts.callbackName or ('%s:getPage'):format(eventName)
    local primaryKey = opts.primaryKey or 'id'
    local pageSize = opts.pageSize or 150

    local Paging = require('@model.client.paging')
    local items, usedPaging = Paging.loadPagedDataset(callbackName, pageSize)

    if not usedPaging or not items then
        return self:resync(), false
    end

    self.records = {}

    for _, item in ipairs(items) do
        local id = item[primaryKey]
        if id ~= nil then
            self.records[id] = self:_wrapRecord(id, item)
        end
    end

    return self.records, true
end

--- Build one request event name.
---@param name string
---@return string
function ClientModelConnection:_event(name)
    return ('%s:%s'):format(self.definition.eventName, name)
end

--- Request a store method from server.
---@param methodName string
---@param ... any
---@return boolean
function ClientModelConnection:requestStore(methodName, ...)
    TriggerServerEvent(self:_event('requestStore'), methodName, ...)
    return true
end

--- Request a record method from server.
---@param id any
---@param methodName string
---@param ... any
---@return boolean
function ClientModelConnection:requestRecord(id, methodName, ...)
    TriggerServerEvent(self:_event('requestRecord'), id, methodName, ...)
    return true
end

--- Small convenience wrappers.
---@param id any
---@return boolean
function ClientModelConnection:lock(id)
    return self:requestStore('lock', id)
end

---@param id any
---@return boolean
function ClientModelConnection:unlock(id)
    return self:requestStore('unlock', id)
end

---@param id any
---@return boolean
function ClientModelConnection:subscribeTo(id)
    TriggerServerEvent(self:_event('subscribe'), id)
    return true
end

---@param id any
---@return boolean
function ClientModelConnection:unsubscribeFrom(id)
    TriggerServerEvent(self:_event('unsubscribe'), id)
    return true
end

---@return boolean
function ClientModelConnection:subscribe()
    TriggerServerEvent(self:_event('subscribeAll'))
    return true
end

---@return boolean
function ClientModelConnection:unsubscribe()
    TriggerServerEvent(self:_event('unsubscribeAll'))
    return true
end

--- Connect to a server-owned client-synced model.
---@param config {model:string, features?:table}
---@return ClientModelConnection
function ClientModel.connect(config)
    assert(type(config) == 'table', 'config must be a table')
    assert(type(config.model) == 'string', 'config.model is required')

    local definition = lib.callback.await('model:getModelDefinition', false, config.model)
    if not definition then
        error(('model "%s" is not registered'):format(config.model), 2)
    end

    if not definition.features.sync then
        error(('model "%s" does not support client sync'):format(config.model), 2)
    end

    local features = config.features or {
        remote = true,
    }

    return ClientModelConnection:new(definition, {
        features = features,
    })
end

return ClientModel