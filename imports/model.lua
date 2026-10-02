local SharedUtils = require('@model.shared.utils')

local modelResource = 'model'
local currentResource = GetCurrentResourceName()

---@class ModelRecord: SharedBaseRecord
---@field store BaseStore
---@field state table
---@field version number
---@field _dirty boolean
---@field _dirtyFields table<string, boolean>
local Record = lib.class('ModelRecord', require('@model.shared.base_record'))

---@class BaseStoreConfig
---@field name string
---@field prefix string?
---@field eventName string?
---@field primaryKey string
---@field storeClass table?
---@field recordClass table?
---@field features table<string, any>?
---@field hooks table<string, function>?
---@field parse fun(row: table): table
---@field serialize fun(data: table): table
---@field runtime fun(data: table): table
---@field public fun(record: ModelRecord, context?: any): table

---@class BaseStore: SharedBaseContainer
---@field config BaseStoreConfig
---@field name string
---@field prefix string
---@field eventName string
---@field resourceName string
---@field recordClass table
---@field dirtyRecords table<any, boolean>
---@field dirtyOrder any[]
---@field featureState table<string, any>
---@field hooks table<string, function>
local BaseStore = lib.class('BaseStore', require('@model.shared.base_container'))

---@type table<string, boolean>
local DEFAULT_RECORD_METHODS = {
    constructor = true,
    get = true,
    setData = true,
    setDataMany = true,
    setState = true,
    setStateMany = true,
    save = true,
    toPublic = true,
}

---@type table<string, fun(): table>
local featureLoaders = {
    db = function()
        return require('@model.imports.features.db')
    end,
    invoker = function()
        return require('@model.imports.features.invoker')
    end,
    subscriptions = function()
        return require('@model.imports.features.subscriptions')
    end,
    sync = function()
        return require('@model.imports.features.sync')
    end,
    client_requests = function()
        return require('@model.imports.features.client_requests')
    end,
}

---@param store BaseStore
---@param id any
---@param row table
function Record:constructor(store, id, row)
    local data = store.config.parse and store.config.parse(row) or row
    local state = store.config.runtime and store.config.runtime(data) or {}

    self.store = store
    self.manager = store
    self.id = id
    self.data = data
    self.state = state
    self.version = tonumber(data.version) or 1
    self._dirty = false
    self._dirtyFields = {}

    self.data.version = self.version
end

--- Read from runtime state first, then persisted data.
---@param key string
---@return any
function Record:get(key)
    if self.state[key] ~= nil then
        return self.state[key]
    end

    return self.data[key]
end

--- Update persisted data.
---@param key string
---@param value any
---@param context any?
---@return boolean, string?
function Record:setData(key, value, context)
    local oldValue = self.data[key]
    if SharedUtils.deepEqual(oldValue, value) then return false end

    local ok, nextValue, err = self.store:_runBeforeHook('beforeSetData', self, key, value, context)
    if ok == false then
        return false, err
    end

    if nextValue ~= nil then
        value = nextValue
    end

    self.data[key] = value
    self.version += 1
    self.data.version = self.version
    self._dirty = true
    self._dirtyFields[key] = true
    self._dirtyFields.version = true

    self.store:_queueDirty(self)
    self.store:_runAfterHook('afterSetData', self, key, oldValue, value, context)
    self.store:_emitDataChanged(self, key, oldValue, value, context)

    return true
end

--- Update multiple persisted fields.
---@param values table
---@param context any?
---@return boolean, string?
function Record:setDataMany(values, context)
    local changed = false

    for key, value in pairs(values) do
        local oldValue = self.data[key]

        if not SharedUtils.deepEqual(oldValue, value) then
            local ok, nextValue, err = self.store:_runBeforeHook('beforeSetData', self, key, value, context)
            if ok == false then
                return false, err
            end

            if nextValue ~= nil then
                value = nextValue
            end

            self.data[key] = value
            self._dirtyFields[key] = true
            changed = true

            self.store:_runAfterHook('afterSetData', self, key, oldValue, value, context)
            self.store:_emitDataChanged(self, key, oldValue, value, context)
        end
    end

    if not changed then return false end

    self.version += 1
    self.data.version = self.version
    self._dirty = true
    self._dirtyFields.version = true

    self.store:_queueDirty(self)

    return true
end

--- Update runtime-only state.
---@param key string
---@param value any
---@param context any?
---@return boolean, string?
function Record:setState(key, value, context)
    local oldValue = self.state[key]
    if SharedUtils.deepEqual(oldValue, value) then return false end

    local ok, nextValue, err = self.store:_runBeforeHook('beforeSetState', self, key, value, context)
    if ok == false then
        return false, err
    end

    if nextValue ~= nil then
        value = nextValue
    end

    self.state[key] = value

    self.store:_runAfterHook('afterSetState', self, key, oldValue, value, context)
    self.store:_emitStateChanged(self, key, oldValue, value, context)

    return true
end

--- Update multiple runtime-only fields.
---@param values table
---@param context any?
---@return boolean, string?
function Record:setStateMany(values, context)
    local changed = false

    for key, value in pairs(values) do
        local oldValue = self.state[key]

        if not SharedUtils.deepEqual(oldValue, value) then
            local ok, nextValue, err = self.store:_runBeforeHook('beforeSetState', self, key, value, context)
            if ok == false then
                return false, err
            end

            if nextValue ~= nil then
                value = nextValue
            end

            self.state[key] = value
            changed = true

            self.store:_runAfterHook('afterSetState', self, key, oldValue, value, context)
            self.store:_emitStateChanged(self, key, oldValue, value, context)
        end
    end

    return changed
end

--- Flush one record through the store.
---@param context any?
---@return boolean
function Record:save(context)
    return self.store:flushRecord(self, context)
end

--- Serialize record for external use.
---@param context any?
---@return table
function Record:toPublic(context)
    if self.store.config.public then
        return self.store.config.public(self, context)
    end

    return self.data
end

---@param config BaseStoreConfig
function BaseStore:constructor(config)
    assert(type(config) == 'table', 'config must be a table')
    assert(type(config.name) == 'string', 'config.name is required')
    assert(type(config.primaryKey) == 'string', 'config.primaryKey is required')

    self:super()

    self.config = config
    self.name = config.name
    self.prefix = config.prefix or config.name
    self.eventName = config.eventName or config.name
    self.resourceName = currentResource
    self.recordClass = config.recordClass or Record
    self.dirtyRecords = {}
    self.dirtyOrder = {}
    self.featureState = {}
    self.hooks = config.hooks or {}
end

--- Run a before hook.
---@param name string
---@param ... any
---@return boolean, any?, string?
function BaseStore:_runBeforeHook(name, ...)
    local hook = self.hooks[name]
    if type(hook) ~= 'function' then
        return true
    end

    local ok, valueOrReason = hook(self, ...)
    if ok == false then
        return false, nil, valueOrReason
    end

    if ok == true then
        return true, valueOrReason
    end

    return true
end

--- Run an after hook.
---@param name string
---@param ... any
function BaseStore:_runAfterHook(name, ...)
    local hook = self.hooks[name]
    if type(hook) == 'function' then
        hook(self, ...)
    end
end

--- Queue a dirty record only once.
---@param record ModelRecord
function BaseStore:_queueDirty(record)
    if self.dirtyRecords[record.id] then return end

    self.dirtyRecords[record.id] = true
    self.dirtyOrder[#self.dirtyOrder + 1] = record.id
end

--- Emit persisted data change.
---@param record ModelRecord
---@param key string
---@param oldValue any
---@param newValue any
---@param context any?
function BaseStore:_emitDataChanged(record, key, oldValue, newValue, context)
    TriggerEvent(('%s:dataChanged'):format(self.eventName), record.id, key, oldValue, newValue, context, record)
end

--- Emit runtime state change.
---@param record ModelRecord
---@param key string
---@param oldValue any
---@param newValue any
---@param context any?
function BaseStore:_emitStateChanged(record, key, oldValue, newValue, context)
    TriggerEvent(('%s:stateChanged'):format(self.eventName), record.id, key, oldValue, newValue, context, record)
end

--- Create a new in-memory record.
---@param data table
---@param context any?
---@return ModelRecord|false, string?
function BaseStore:create(data, context)
    local ok, nextData, err = self:_runBeforeHook('beforeCreate', data, context)
    if ok == false then
        return false, err
    end

    data = nextData or data

    local id = data[self.config.primaryKey]
    assert(id ~= nil, 'create requires a primary key value unless db feature inserts it')

    local record = self.recordClass:new(self, id, data)
    self.records[id] = record

    self:_runAfterHook('afterCreate', record, context)
    TriggerEvent(('%s:created'):format(self.eventName), id, record, context)

    return record
end

--- Delete an in-memory record.
---@param id any
---@param context any?
---@return boolean, string?
function BaseStore:delete(id, context)
    local record = self.records[id]
    if not record then return false, 'record not found' end

    local ok, _, err = self:_runBeforeHook('beforeDelete', record, context)
    if ok == false then
        return false, err
    end

    self.records[id] = nil
    self.dirtyRecords[id] = nil

    self:_runAfterHook('afterDelete', record, context)
    TriggerEvent(('%s:deleted'):format(self.eventName), id, record, context)

    return true
end

--- Serialize one record.
---@param id any
---@param context any?
---@return table|nil
function BaseStore:serializeOne(id, context)
    local record = self.records[id]
    return record and record:toPublic(context) or nil
end

--- Serialize all records.
---@param context any?
---@return table<any, table>
function BaseStore:serializeAll(context)
    local output = {}

    for id, record in pairs(self.records) do
        output[id] = record:toPublic(context)
    end

    return output
end

--- Base flush does nothing unless db feature overrides it.
---@param record ModelRecord
---@param context any?
---@return boolean
function BaseStore:flushRecord(record, context)
    return true
end

--- Flush all dirty records.
---@param context any?
---@return number
function BaseStore:flushDirty(context)
    local flushed = 0
    local pending = self.dirtyOrder
    self.dirtyOrder = {}

    for i = 1, #pending do
        local id = pending[i]
        local record = self.records[id]

        if record and record._dirty then
            local ok = self:flushRecord(record, context)

            if ok then
                record._dirty = false
                record._dirtyFields = {}
                self.dirtyRecords[id] = nil
                flushed += 1
            end
        else
            self.dirtyRecords[id] = nil
        end
    end

    return flushed
end

---@class ModelModule
---@field Record table
---@field BaseStore table
---@field DEFAULT_RECORD_METHODS table<string, boolean>
local Model = {
    Record = Record,
    BaseStore = BaseStore,
    DEFAULT_RECORD_METHODS = DEFAULT_RECORD_METHODS,
}

--- Validate owner config and feature dependencies.
---@param config BaseStoreConfig
local function validateOwnerConfig(config)
    local features = config.features or {}

    if features.sync and not (config.eventName or (type(features.sync) == 'table' and features.sync.eventName)) then
        error('sync feature requires eventName', 3)
    end

    if features.invoker then
        local invoker = features.invoker == true and {} or features.invoker

        if type(invoker.allowedStoreMethods) ~= 'table' then
            error('invoker feature requires allowedStoreMethods table', 3)
        end

        if type(invoker.allowedRecordMethods) ~= 'table' then
            error('invoker feature requires allowedRecordMethods table', 3)
        end

        if invoker.allowDefaultRecordMethods ~= nil and type(invoker.allowDefaultRecordMethods) ~= 'boolean' then
            error('invoker.allowDefaultRecordMethods must be a boolean', 3)
        end
    end

    if features.subscriptions and not features.sync then
        error('subscriptions feature requires sync feature', 3)
    end

    if features.client_requests then
        local requests = features.client_requests == true and {} or features.client_requests

        if type(config.eventName or requests.eventName) ~= 'string' then
            error('client_requests feature requires eventName', 3)
        end

        if type(requests.allowedStoreMethods) ~= 'table' then
            error('client_requests feature requires allowedStoreMethods table', 3)
        end

        if type(requests.allowedRecordMethods) ~= 'table' then
            error('client_requests feature requires allowedRecordMethods table', 3)
        end

        if requests.allowDefaultRecordMethods ~= nil and type(requests.allowDefaultRecordMethods) ~= 'boolean' then
            error('client_requests.allowDefaultRecordMethods must be a boolean', 3)
        end
    end
end

--- Create a model without registry ownership.
---@param config BaseStoreConfig
---@return BaseStore
function Model.define(config)
    validateOwnerConfig(config)

    local storeClass = config.storeClass or BaseStore
    local store = storeClass:new(config)
    local features = config.features or {}

    for featureName, options in pairs(features) do
        if options then
            local loader = featureLoaders[featureName]
            assert(loader, ('unknown feature "%s"'):format(featureName))

            local feature = loader()
            feature.attach(store, options == true and {} or options, config)
        end
    end

    return store
end

--- Create a model and register owner metadata.
---@param config BaseStoreConfig
---@return BaseStore
function Model.register(config)
    local store = Model.define(config)

    local ok, err = exports[modelResource]:registerModelOwner({
        name = config.name,
        owner = currentResource,
        prefix = config.prefix or config.name,
        eventName = config.eventName or config.name,
        features = config.features or {},
    })

    if not ok then
        error(err, 2)
    end

    return store
end

return Model