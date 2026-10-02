local SharedUtils = require('@model.shared.utils')

---@class ClientStateOwner: SharedBaseContainer
---@field eventName string
---@field ownerResource string
---@field recordClass table
local ClientStateOwner = lib.class('ClientStateOwner', require('@model.shared.base_container'))

---@class ClientStateMirror: SharedBaseContainer
---@field eventName string
---@field ownerResource string
---@field recordClass table
local ClientStateMirror = lib.class('ClientStateMirror', require('@model.shared.base_container'))

local ClientState = {}
local currentResource = GetCurrentResourceName()

---@param eventName string
---@return string
local function localEvent(eventName)
    return ('%s:local'):format(eventName)
end

---@param config {eventName:string, recordClass?:table}
function ClientStateOwner:constructor(config)
    self:super()

    self.eventName = config.eventName
    self.ownerResource = currentResource
    self.recordClass = config.recordClass or require('@model.client.state_record')

    AddEventHandler(('%s:requestSync'):format(localEvent(self.eventName)), function(targetResource)
        if targetResource ~= self.ownerResource then
            TriggerEvent(('%s:reset'):format(localEvent(self.eventName)), targetResource, self:serializeAll())
        end
    end)
end

--- Create local client-owned state.
---@param data table
---@return any
function ClientStateOwner:create(data)
    local id = data.id
    self.records[id] = self:_wrapRecord(id, SharedUtils.shallowCopy(data))

    TriggerEvent(('%s:create'):format(localEvent(self.eventName)), self.ownerResource, id, self.records[id].data)
    return self.records[id]
end

---@param id any
---@param diff table
---@return boolean
function ClientStateOwner:update(id, diff)
    local record = self.records[id]
    if not record then return false end

    SharedUtils.mergeInto(record.data, diff)
    TriggerEvent(('%s:update'):format(localEvent(self.eventName)), self.ownerResource, id, diff)

    return true
end

---@param id any
---@return boolean
function ClientStateOwner:delete(id)
    if not self.records[id] then return false end

    self.records[id] = nil
    TriggerEvent(('%s:delete'):format(localEvent(self.eventName)), self.ownerResource, id)

    return true
end

---@return table<any, table>
function ClientStateOwner:serializeAll()
    return self:getAll()
end

---@param config {resource:string, eventName:string, recordClass?:table, autoLoad?:boolean, autoListen?:boolean}
function ClientStateMirror:constructor(config)
    self:super()

    self.ownerResource = config.resource
    self.eventName = config.eventName
    self.recordClass = config.recordClass or require('@model.client.state_record')

    if config.autoLoad ~= false then
        self:resync()
    end

    if config.autoListen ~= false then
        AddEventHandler(('%s:create'):format(localEvent(self.eventName)), function(ownerResource, id, payload)
            if ownerResource ~= self.ownerResource then return end
            self.records[id] = self:_wrapRecord(id, payload)
        end)

        AddEventHandler(('%s:update'):format(localEvent(self.eventName)), function(ownerResource, id, diff)
            if ownerResource ~= self.ownerResource then return end
            self:_applyDiff(id, diff)
        end)

        AddEventHandler(('%s:delete'):format(localEvent(self.eventName)), function(ownerResource, id)
            if ownerResource ~= self.ownerResource then return end
            self.records[id] = nil
        end)

        AddEventHandler(('%s:reset'):format(localEvent(self.eventName)), function(targetResource, snapshot)
            if targetResource ~= currentResource then return end

            self.records = {}

            for id, payload in pairs(snapshot or {}) do
                self.records[id] = self:_wrapRecord(id, payload)
            end
        end)
    end
end

--- Ask owner resource for a fresh local snapshot.
function ClientStateMirror:resync()
    TriggerEvent(('%s:requestSync'):format(localEvent(self.eventName)), currentResource)
end

---@param config {eventName:string, recordClass?:table}
---@return ClientStateOwner
function ClientState.register(config)
    return ClientStateOwner:new(config)
end

---@param config {resource:string, eventName:string, recordClass?:table, autoLoad?:boolean, autoListen?:boolean}
---@return ClientStateMirror
function ClientState.connect(config)
    return ClientStateMirror:new(config)
end

return ClientState