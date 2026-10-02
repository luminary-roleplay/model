local SharedUtils = require('@model.shared.utils')

---@class SharedBaseContainer
---@field records table<any, any>
---@field recordClass table?
local SharedBaseContainer = lib.class('SharedBaseContainer')

function SharedBaseContainer:constructor()
    self.records = {}
end

--- Wrap one record payload.
---@param id any
---@param payload table
---@return any
function SharedBaseContainer:_wrapRecord(id, payload)
    if self.recordClass then
        return self.recordClass:new(self, id, payload)
    end

    return payload
end

--- Get one record payload.
---@param id any
---@return table|nil
function SharedBaseContainer:get(id)
    local record = self.records[id]
    return record and (record.data or record) or nil
end

--- Get all payloads.
---@return table<any, table>
function SharedBaseContainer:getAll()
    local output = {}

    for id, record in pairs(self.records) do
        output[id] = record.data or record
    end

    return output
end

--- Get raw wrapped record.
---@param id any
---@return any
function SharedBaseContainer:record(id)
    return self.records[id]
end

--- Apply a diff to one wrapped record.
---@param id any
---@param diff table
---@return boolean
function SharedBaseContainer:_applyDiff(id, diff)
    local record = self.records[id]
    if not record then return false end

    local data = record.data or record

    if diff.version and data.version and diff.version < data.version then
        return false
    end

    SharedUtils.mergeInto(data, diff)
    return true
end

return SharedBaseContainer