---@class LmModelDbAdapter
---@field query fun(query: string, params?: table): table
---@field single fun(query: string, params?: table): table|nil
---@field scalar fun(query: string, params?: table): any
---@field insert fun(query: string, params?: table): number|nil
---@field update fun(query: string, params?: table): number
---@field execute fun(query: string, params?: table): number
---@field transaction fun(queries: table, params?: table): boolean
---@field prepare fun(query: string, params?: table): table
---@field queryFile fun(path: string, params?: table): table
---@field singleFile fun(path: string, params?: table): table|nil
---@field scalarFile fun(path: string, params?: table): any
---@field insertFile fun(path: string, params?: table): number|nil
---@field updateFile fun(path: string, params?: table): number
---@field executeFile fun(path: string, params?: table): number
---@field loadQuery fun(path: string): string
---@field hasDependency boolean
---@field usingExports boolean

local currentResource = GetCurrentResourceName()
local hasMySQLGlobal = rawget(_G, 'MySQL') ~= nil

---@param resourceName string
---@param dependencyName string
---@return boolean
local function hasDependency(resourceName, dependencyName)
    local count = GetNumResourceMetadata(resourceName, 'dependency')

    for i = 0, count - 1 do
        local value = GetResourceMetadata(resourceName, 'dependency', i)
        if value == dependencyName then
            return true
        end
    end

    return false
end

---@param resourceName string
---@param path string
---@return string
local function loadQuery(resourceName, path)
    local query = LoadResourceFile(resourceName, path)

    if not query then
        error(("Failed to load SQL file '%s' from resource '%s'"):format(path, resourceName), 2)
    end

    return query
end

local declaredLMPOSTGRESDependency = hasDependency(currentResource, 'postgres')
local postgresState = GetResourceState('postgres')

-- Fail early if postgres is unavailable.
if postgresState ~= 'started' then
    if declaredLMPOSTGRESDependency then
        error(
            ("Resource '%s' loaded model DB module and declares dependency 'postgres', but postgres is not started. " ..
            "Make sure 'ensure postgres' is above '%s'."):format(currentResource, currentResource),
            2
        )
    end

    error(
        ("Resource '%s' loaded model DB module, but postgres is not started. " ..
        "Start postgres first or remove the DB feature/module from this resource."):format(currentResource),
        2
    )
end

-- Warn when falling back to exports.
if not declaredLMPOSTGRESDependency then
    print(("[model] Resource '%s' loaded the DB module without declaring dependency 'postgres'. " ..
        "Falling back to exports.postgres. Consider adding `dependency 'postgres'` to the resource manifest.")
        :format(currentResource))
end

---@type LmModelDbAdapter
local Db = {
    hasDependency = declaredLMPOSTGRESDependency,
    usingExports = not declaredLMPOSTGRESDependency or not hasMySQLGlobal,
}

---@param query string
---@param params table?
---@return table
function Db.query(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.query.await(query, params or {})
    end

    return exports.postgres:query_async(query, params or {})
end

---@param query string
---@param params table?
---@return table|nil
function Db.single(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.single.await(query, params or {})
    end

    return exports.postgres:single_async(query, params or {})
end

---@param query string
---@param params table?
---@return any
function Db.scalar(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.scalar.await(query, params or {})
    end

    return exports.postgres:scalar_async(query, params or {})
end

---@param query string
---@param params table?
---@return number|nil
function Db.insert(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.insert.await(query, params or {})
    end

    return exports.postgres:insert_async(query, params or {})
end

---@param query string
---@param params table?
---@return number
function Db.update(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.update.await(query, params or {}) or 0
    end

    return exports.postgres:update_async(query, params or {}) or 0
end

---@param query string
---@param params table?
---@return number
function Db.execute(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.rawExecute.await(query, params or {}) or 0
    end

    return exports.postgres:execute_async(query, params or {}) or 0
end

---@param queries table
---@param params table?
---@return boolean
function Db.transaction(queries, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.transaction.await(queries, params or {})
    end

    return exports.postgres:transaction_async(queries, params or {})
end

---@param query string
---@param params table?
---@return table
function Db.prepare(query, params)
    if declaredLMPOSTGRESDependency and hasMySQLGlobal then
        return Postgres.prepare.await(query, params or {})
    end

    return exports.postgres:prepare_async(query, params or {})
end

---@param path string
---@return string
function Db.loadQuery(path)
    return loadQuery(currentResource, path)
end

---@param path string
---@param params table?
---@return table
function Db.queryFile(path, params)
    return Db.query(Db.loadQuery(path), params)
end

---@param path string
---@param params table?
---@return table|nil
function Db.singleFile(path, params)
    return Db.single(Db.loadQuery(path), params)
end

---@param path string
---@param params table?
---@return any
function Db.scalarFile(path, params)
    return Db.scalar(Db.loadQuery(path), params)
end

---@param path string
---@param params table?
---@return number|nil
function Db.insertFile(path, params)
    return Db.insert(Db.loadQuery(path), params)
end

---@param path string
---@param params table?
---@return number
function Db.updateFile(path, params)
    return Db.update(Db.loadQuery(path), params)
end

---@param path string
---@param params table?
---@return number
function Db.executeFile(path, params)
    return Db.execute(Db.loadQuery(path), params)
end

return Db