local Db = require('@model.imports.db')

---@class DbFeatureOptions
---@field selectAll string?
---@field insert string?
---@field update string?
---@field delete string?
---@field autoLoad boolean?
---@field autoBatch boolean?
---@field batchInterval number?

local DbFeature = {}

--- Attach optional db persistence.
---@param store BaseStore
---@param options DbFeatureOptions
function DbFeature.attach(store, options)
    store.featureState.db = options

    local batchInterval = options.batchInterval or 5000
    local startedThread = false

    --- Serialize a record for db writes.
    ---@param record ModelRecord
    ---@return table
    function store:_dbSerialize(record)
        if self.config.serialize then
            return self.config.serialize(record.data)
        end

        return record.data
    end

    --- Persist one dirty record.
    ---@param record ModelRecord
    ---@param context any?
    ---@return boolean
    function store:flushRecord(record, context)
        if not record or not record._dirty then return true end
        if not options.update then return true end

        Db.updateFile(options.update, self:_dbSerialize(record))
        return true
    end

    --- Load all rows into memory.
    function store:dbLoad()
        if not options.selectAll then return end

        local rows = Db.queryFile(options.selectAll)

        for i = 1, #rows do
            local row = rows[i]
            local id = row[self.config.primaryKey]

            if id ~= nil then
                self.records[id] = self.recordClass:new(self, id, row)
            end
        end
    end

    local baseCreate = store.create

    -- Insert row before memory create.
    function store:create(data, context)
        if options.insert then
            local payload = self.config.serialize and self.config.serialize(data) or data
            local insertId = Db.insertFile(options.insert, payload)

            if data[self.config.primaryKey] == nil and insertId ~= nil then
                data[self.config.primaryKey] = insertId
            end
        end

        return baseCreate(self, data, context)
    end

    local baseDelete = store.delete

    -- Delete row before memory delete.
    function store:delete(id, context)
        if options.delete then
            Db.updateFile(options.delete, {
                [self.config.primaryKey] = id,
            })
        end

        return baseDelete(self, id, context)
    end

    if options.autoLoad ~= false then
        store:dbLoad()
    end

    if options.autoBatch ~= false and not startedThread then
        startedThread = true

        -- Flush dirty rows on interval.
        CreateThread(function()
            while true do
                Wait(batchInterval)
                store:flushDirty()
            end
        end)
    end
end

return DbFeature