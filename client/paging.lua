--- Client-side paged dataset loader for large model data sets.
---
--- Usage (in a consuming resource):
---   local Paging = require('@model.client.paging')
---   local items, usedPaging, total = Paging.loadPagedDataset('vehicles:getPage', 150, function(item, index)
---       return item
---   end)
---
--- When the paged callback does not exist or returns an invalid response the function
--- returns nil, false, nil so callers can fall back to a full resync.

---@param callbackName string
---@param pageSize integer|nil
---@param map (fun(item: any, index: integer): any)|nil
---@param ... any Extra arguments forwarded to every page request.
---@return table|nil items
---@return boolean usedPaging
---@return integer|nil total
local function loadPagedDataset(callbackName, pageSize, map, ...)
    if type(callbackName) ~= 'string' or callbackName == '' then
        error('expected callbackName to be a non-empty string', 2)
    end

    local output = {}
    local cursor = 1
    local usedPaged = false
    local total = nil
    local extraArgs = { ... }

    while true do
        local page = lib.callback.await(callbackName, false, cursor, pageSize or 150, table.unpack(extraArgs))

        if type(page) ~= 'table' or type(page.items) ~= 'table' then
            if usedPaged then
                break
            end

            return nil, false, nil
        end

        usedPaged = true
        total = tonumber(page.total) or total

        for index = 1, #page.items do
            local item = page.items[index]

            if type(map) == 'function' then
                item = map(item, index)
            end

            if item ~= nil then
                output[#output + 1] = item
            end
        end

        if not page.nextCursor then
            break
        end

        cursor = tonumber(page.nextCursor) or 0
        if cursor < 1 then
            break
        end

        Wait(0)
    end

    return output, true, total
end

return {
    loadDataset = loadPagedDataset,
    loadPagedDataset = loadPagedDataset,
}
