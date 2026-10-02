--- Paging utilities for large model data sets.
--- Auto-loaded as part of model's server scripts.
---
--- Store-owner resources register paged callbacks via the exported helper:
---   exports.model:registerPagedCallback('vehicles:getPage', { ... })
---
--- This lets clients call the callback page-by-page using ClientModelConnection:resyncPaged()
--- or the standalone client paging loader in @model.client.paging.

---@generic TInput, TOutput
---@class LmModelPagedCallbackOptions<TInput, TOutput>
---@field getItems fun(source: number, ...: any): table
---@field map fun(item: TInput, source: number, ...: any): TOutput|nil
---@field sort fun(a: TInput, b: TInput): boolean
---@field before fun(source: number): nil
---@field minPageSize integer
---@field maxPageSize integer
---@field defaultPageSize integer

---@generic T
---@class LmModelPagedResult<T>
---@field items T[]
---@field cursor integer
---@field nextCursor integer|nil
---@field total integer

---@param callbackName string
---@param options LmModelPagedCallbackOptions<any, any>
local function registerPagedCallback(callbackName, options)
    if type(callbackName) ~= 'string' or callbackName == '' then
        error('expected callbackName to be a non-empty string', 2)
    end

    if type(options) ~= 'table' then
        error('expected options to be a table', 2)
    end

    if type(options.getItems) ~= 'function' then
        error('expected options.getItems to be a function', 2)
    end

    if type(options.map) ~= 'function' then
        error('expected options.map to be a function', 2)
    end

    lib.callback.register(callbackName, function(source, cursor, pageSize, ...)
        local before = options.before
        if type(before) == 'function' then
            before(source)
        end

        local items = {}
        local sourceItems = options.getItems(source, ...) or {}

        for _, value in pairs(sourceItems) do
            items[#items + 1] = value
        end

        local sorter = options.sort
        if type(sorter) == 'function' then
            table.sort(items, sorter)
        end

        local minSize = math.max(1, tonumber(options.minPageSize) or 25)
        local maxSize = math.max(minSize, tonumber(options.maxPageSize) or 500)
        local defaultSize = math.max(minSize, math.min(maxSize, tonumber(options.defaultPageSize) or 150))

        local total = #items
        local startIndex = math.max(1, tonumber(cursor) or 1)
        local limit = math.max(minSize, math.min(maxSize, tonumber(pageSize) or defaultSize))
        local lastIndex = math.min(total, startIndex + limit - 1)
        local pageItems = {}

        for index = startIndex, lastIndex do
            local mapped = options.map(items[index], source, ...)
            if mapped ~= nil then
                pageItems[#pageItems + 1] = mapped
            end
        end

        ---@type LmModelPagedResult<any>
        return {
            items = pageItems,
            cursor = startIndex,
            nextCursor = lastIndex < total and lastIndex + 1 or nil,
            total = total,
        }
    end)
end



--- Expose so store-owner resources can register paged callbacks without requiring a file.
exports('registerPagedCallback', registerPagedCallback)
