--- @meta declarations for Jade ORM — Lua Language Server type annotations
--- @brief Provides autocomplete and type checking for Jade's public API
--- @see https://github.com/AlehandroSV/jade/issues/65
---
--- @class Jade
--- @field _VERSION string Jade version string
--- @field String fun(length?: number): Jade.Column
--- @field Integer fun(): Jade.Column
--- @field BigInt fun(): Jade.Column
--- @field Float fun(): Jade.Column
--- @field Decimal fun(): Jade.Column
--- @field Boolean fun(): Jade.Column
--- @field Text fun(): Jade.Column
--- @field Timestamp fun(): Jade.Column
--- @field Date fun(): Jade.Column
--- @field UUID fun(): Jade.Column
--- @field CUID fun(): Jade.Column
--- @field NanoID fun(): Jade.Column
--- @field JSON fun(): Jade.Column
--- @field Enum fun(...: string): Jade.Column
--- @field Entity fun(table_name: string, columns: table<string, Jade.Column>): Jade.Entity
--- @field Relations Jade.RelationsModule
--- @field migration Jade.MigrationModule
--- @field transaction Jade.TransactionModule
--- @field SoftDelete Jade.SoftDeleteModule
--- @field Events Jade.EventsModule
--- @field security Jade.SecurityModule
--- @field Encryption Jade.EncryptionModule
--- @field Schema Jade.SchemaModule
--- @field Declarative Jade.DeclarativeModule
--- @field drivers Jade.DriversModule
--- @field cache Jade.CacheModule
--- @field database Jade.DatabaseModule
--- @field config Jade.ConfigModule
--- @field log Jade.LogModule
--- @field plugin Jade.PluginModule
--- @field pluginLoader Jade.PluginLoaderModule
--- @field inflection Jade.InflectionModule
--- @field configure fun(opts: Jade.Config): Jade.Driver
--- @field configureFromEnvironment fun(basePath: string): Jade.Driver
--- @field driver fun(): Jade.Driver
--- @field disconnect fun()
--- @field raw fun(sql: string, ...: any): table
--- @field on fun(event: string, handler: function)
--- @field use fun(plugin: table, options?: table): boolean, string?
--- @field unloadPlugin fun(name: string): boolean, string?
--- @field createTable fun(name: string, fn: function)
--- @field dropTable fun(name: string)
--- @field renameTable fun(old_name: string, new_name: string)
--- @field addColumn fun(table_name: string, column_name: string, type_name: string, options?: table)
--- @field dropColumn fun(table_name: string, column_name: string)
--- @field renameColumn fun(table_name: string, old_name: string, new_name: string)
--- @field addIndex fun(table_name: string, columns: string[], options?: table)
--- @field dropIndex fun(table_name: string, index_name: string)
--- @field addForeignKey fun(table_name: string, options: table)
--- @field dropForeignKey fun(table_name: string, constraint_name: string)

require("jade.util.compat")

local Jade = {
    _VERSION = require("jade._VERSION"),
}

-- Errors (typed catalog J0xxx–J5xxx)
Jade.errors = require("jade.errors")

-- Types
Jade.String = require("jade.types.string")
Jade.Integer = require("jade.types.integer")
Jade.Boolean = require("jade.types.boolean")
Jade.Text = require("jade.types.text")
Jade.Timestamp = require("jade.types.timestamp")
Jade.Float = require("jade.types.float")
Jade.Decimal = require("jade.types.decimal")
Jade.UUID = require("jade.types.uuid")
Jade.Date = require("jade.types.date")
Jade.CUID = require("jade.types.cuid")
Jade.NanoID = require("jade.types.nanoid")
Jade.BigInt = require("jade.types.bigint")
Jade.JSON = require("jade.types.json")
Jade.Enum = require("jade.types.enum")

-- Entity
Jade.Entity = require("jade.entity")

-- Relations
Jade.Relations = require("jade.entity.relations")

-- Migration
Jade.migration = require("jade.migration")

-- Transaction
Jade.transaction = require("jade.transaction.manager")

-- Events
Jade.Events = require("jade.entity.events")

-- Security
Jade.security = require("jade.security")

-- Lazy modules: load on first access (lighter require("jade"))
local LAZY_MODULES = {
    Audit = "jade.audit",
    Encryption = "jade.encryption",
    SoftDelete = "jade.entity.soft_delete",
    Seed = "jade.seed",
    Schema = "jade.schema",
    Declarative = "jade.schema.declarative",
    Cache = "jade.cache",
    Database = "jade.database",
}

setmetatable(Jade, {
    __index = function(t, key)
        local mod = LAZY_MODULES[key]
        if mod then
            local loaded = require(mod)
            rawset(t, key, loaded)
            return loaded
        end
    end
})

-- Driver registry
Jade.drivers = require("jade.driver")

-- Config
Jade.config = require("jade.config")

-- Utility
Jade.log = require("jade.util.log")
Jade.inflection = require("jade.util.inflection")

-- Context (coroutine-safe state)
local context = require("jade.util.context")

-- Plugin System
Jade.plugin = require("jade.plugin")
Jade.pluginLoader = require("jade.plugin.loader")

--- Convenience: jade.use(plugin, options) delegates to jade.plugin.use()
--- @param plugin table The plugin module/table
--- @param options table|nil Options passed to plugin.setup()
--- @return boolean ok
--- @return string|nil error
function Jade.use(plugin, options)
    return Jade.plugin.use(plugin, options)
end

--- Convenience: jade.unloadPlugin(name) delegates to jade.plugin.unloadPlugin()
--- @param name string
--- @return boolean ok
--- @return string|nil error
function Jade.unloadPlugin(name)
    return Jade.plugin.unloadPlugin(name)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- Context (coroutine-safe state)
local context = require("jade.util.context")

function Jade.configure(opts)
    -- Support URL-based configuration
    if opts.url then
        opts = Jade.config.parseURL(opts.url)
    end

    if opts.database then
        Jade.config.set(opts)
    end

    local db = opts.database or opts
    local driver_name = db.driver or "postgresql"

    local DriverClass = Jade.drivers.get(driver_name)
    local driver = DriverClass.new()

    -- Load plugins configured in jade.config.lua (plugins field)
    if opts.plugins then
        local results_ = Jade.pluginLoader.loadAll(Jade, opts.plugins)
        for name_, res_ in pairs(results_) do
            if not res_.ok then
                Jade.errors.raise(Jade.errors.CONFIG_INVALID, {
                    details = "failed to load plugin '" .. name_ .. "': " .. tostring(res_.error),
                }, 2)
            end
        end
    end

    driver:connect(db)

    -- Wire plugin query hooks (beforeQuery/afterQuery) onto this driver
    if Jade.plugin and Jade.plugin.applyDriverExtensions then
        Jade.plugin.applyDriverExtensions(driver)
    end

    context.set("driver", driver)
    context.set("config", db)

    return driver
end

--- Configure from environment-specific config files
---@param basePath string Base path for config files
---@return Jade.Driver Configured driver
function Jade.configureFromEnvironment(basePath)
    local env_config = Jade.config.loadForEnvironment(basePath)
    return Jade.configure(env_config)
end

--- Get the current database driver
---@return Jade.Driver Current driver instance
---@error If Jade is not configured
function Jade.driver()
    local driver = context.get("driver")
    if not driver then
        Jade.errors.raise(Jade.errors.CONFIG_MISSING, { path = "jade.configure()" }, 2)
    end
    return driver
end

--- Disconnect the current database driver
function Jade.disconnect()
    local driver = context.get("driver")
    if driver then
        driver:disconnect()
        context.set("driver", nil)
    end
end

--- Create a raw SQL expression
---@param sql string Raw SQL string
---@vararg any Bindings for the SQL
---@return table Raw SQL expression
function Jade.raw(sql, ...)
    return { _raw = sql, _bindings = { ... } }
end

--- Register an event handler
---@param event_name string Event name
---@param handler function Event handler function
function Jade.on(event_name, handler)
    return Jade.Events.on(event_name, handler)
end

--- Create a new table (DDL)
---@param name string Table name
---@param fn function Table definition function
function Jade.createTable(name, fn)
    return Jade.Schema.createTable(Jade.driver(), name, fn)
end

--- Drop a table (DDL)
---@param name string Table name
function Jade.dropTable(name)
    return Jade.Schema.dropTable(Jade.driver(), name)
end

--- Rename a table (DDL)
---@param old_name string Current table name
---@param new_name string New table name
function Jade.renameTable(old_name, new_name)
    return Jade.Schema.renameTable(Jade.driver(), old_name, new_name)
end

--- Add a column to a table (DDL)
---@param table_name string Table name
---@param column_name string Column name
---@param type_name string Column type
---@param options? table Column options
function Jade.addColumn(table_name, column_name, type_name, options)
    return Jade.Schema.addColumn(Jade.driver(), table_name, column_name, type_name, options)
end

--- Drop a column from a table (DDL)
---@param table_name string Table name
---@param column_name string Column name
function Jade.dropColumn(table_name, column_name)
    return Jade.Schema.dropColumn(Jade.driver(), table_name, column_name)
end

--- Rename a column (DDL)
---@param table_name string Table name
---@param old_name string Current column name
---@param new_name string New column name
function Jade.renameColumn(table_name, old_name, new_name)
    return Jade.Schema.renameColumn(Jade.driver(), table_name, old_name, new_name)
end

--- Add an index to a table (DDL)
---@param table_name string Table name
---@param columns string[] Column names to index
---@param options? table Index options
function Jade.addIndex(table_name, columns, options)
    return Jade.Schema.addIndex(Jade.driver(), table_name, columns, options)
end

--- Drop an index (DDL)
---@param table_name string Table name
---@param index_name string Index name
function Jade.dropIndex(table_name, index_name)
    return Jade.Schema.dropIndex(Jade.driver(), table_name, index_name)
end

--- Add a foreign key constraint (DDL)
---@param table_name string Table name
---@param options table Foreign key options
function Jade.addForeignKey(table_name, options)
    return Jade.Schema.addForeignKey(Jade.driver(), table_name, options)
end

--- Drop a foreign key constraint (DDL)
---@param table_name string Table name
---@param constraint_name string Constraint name
function Jade.dropForeignKey(table_name, constraint_name)
    return Jade.Schema.dropForeignKey(Jade.driver(), table_name, constraint_name)
end

---------------------------------------------------------------------------
-- Declarative Schema (.jade file support)
---------------------------------------------------------------------------

--- Load a .jade schema file and return parsed schema
---@param filepath string Path to .jade file
---@return table schema Parsed schema with models and options
function Jade.loadSchema(filepath)
    local f = io.open(filepath, "r")
    if not f then
        Jade.errors.raise(Jade.errors.CONFIG_MISSING, { path = filepath }, 2)
    end
    local content = f:read("*a")
    f:close()
    return Jade.Declarative.parsedeclarativeSchema(content)
end

--- Load a .jade file and generate entities
---@param filepath string Path to .jade file
---@return table<string, Jade.Entity> entities Map of entity name to entity
function Jade.loadEntities(filepath)
    local schema = Jade.loadSchema(filepath)
    local entities = {}
    for name, model in pairs(schema.models) do
        entities[name] = Jade.Declarative.generateEntity(model)
        local driver = context.get("driver")
        if driver then
            entities[name]:configure(driver)
        end
    end
    return entities
end

--- Load a .jade file and sync tables to database
---@param filepath string Path to .jade file
function Jade.syncSchema(filepath)
    local schema = Jade.loadSchema(filepath)
    local driver = Jade.driver()
    for _, model in pairs(schema.models) do
        Jade.Declarative.createTableFromModel(driver, model)
    end
end

-- Only safe path characters for shell fallback (no quotes, $, `;, |, &, etc.)
local LOAD_MODELS_SAFE_DIR = "^[%w_%./\\:%-]+$"
local LOAD_MODELS_SAFE_FILE = "^[%w_%-]+%.lua$"

--- Whether a directory path may be passed to a shell listing fallback.
---@param path any
---@return boolean
local function isSafeShellPath(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    if path:find("\0", 1, true) then
        return false
    end
    if path:find("..", 1, true) then
        return false
    end
    return path:match(LOAD_MODELS_SAFE_DIR) ~= nil
end

--- List generated model files without interpolating untrusted paths into a shell.
--- Prefers lfs.dir; shell is a last resort and only for whitelisted paths.
---@param dir string
---@return table<string, string> available model name -> file path
local function listModelFiles(dir)
    local available = {}

    local ok_lfs, lfs_mod = pcall(require, "lfs")
    if ok_lfs and lfs_mod and lfs_mod.dir then
        local ok_dir, iter, state = pcall(lfs_mod.dir, dir)
        if ok_dir and type(iter) == "function" then
            for filename in iter, state do
                if type(filename) == "string" and filename:match(LOAD_MODELS_SAFE_FILE) then
                    local name = filename:gsub("%.lua$", "")
                    available[name] = dir .. "/" .. filename
                end
            end
            return available
        end
        -- lfs present but directory missing/unreadable
        return available
    end

    if not isSafeShellPath(dir) then
        return available
    end

    local handle = io.popen('ls "' .. dir .. '" 2>/dev/null')
    if handle then
        for filename in handle:lines() do
            if filename:match(LOAD_MODELS_SAFE_FILE) then
                local name = filename:gsub("%.lua$", "")
                available[name] = dir .. "/" .. filename
            end
        end
        handle:close()
    end

    if not next(available) then
        handle = io.popen('dir "' .. dir .. '" /b 2>nul')
        if handle then
            for filename in handle:lines() do
                if filename:match(LOAD_MODELS_SAFE_FILE) then
                    local name = filename:gsub("%.lua$", "")
                    available[name] = dir .. "/" .. filename
                end
            end
            handle:close()
        end
    end

    return available
end

--- Load generated model files lazily from a directory
--- Models are loaded on first access, not upfront.
--- Iteration is Lua 5.1-safe via `:modelNames()` / `:each()` (do not rely on `pairs`).
---@param dir? string Directory path (default: "jade/generated")
---@return table<string, Jade.Entity> models Proxy table that loads models on demand
function Jade.loadModels(dir)
    dir = dir or "jade/generated"
    local cache = {}

    local available = listModelFiles(dir)

    local proxy = {}

    -- Reload a single model (or all if no name given)
    ---@param name? string Model name to reload (nil = reload all)
    function proxy:reload(name)
        if name then
            cache[name] = nil
        else
            for k in pairs(cache) do cache[k] = nil end
        end
    end

    -- Clear all cached models
    function proxy:clearCache()
        for k in pairs(cache) do cache[k] = nil end
    end

    --- Sorted list of discovered model names (works on Lua 5.1).
    ---@return string[]
    function proxy:modelNames()
        local names = {}
        for name in pairs(available) do
            names[#names + 1] = name
        end
        table.sort(names)
        return names
    end

    --- Iterator of name, loaded-model pairs (works on Lua 5.1).
    ---@return fun(): string?, Jade.Entity?
    function proxy:each()
        local names = self:modelNames()
        local i = 0
        return function()
            i = i + 1
            local name = names[i]
            if name == nil then
                return nil
            end
            return name, self[name]
        end
    end

    --- Load every model into a plain map (works on Lua 5.1).
    ---@return table<string, Jade.Entity>
    function proxy:list()
        local models = {}
        for name, model in self:each() do
            models[name] = model
        end
        return models
    end

    -- Return proxy that loads on access
    return setmetatable(proxy, {
        __index = function(_, key)
            if not available[key] then return nil end
            if cache[key] then return cache[key] end

            local driver = context.get("driver")
            local ok, model = pcall(dofile, available[key])
            if ok and type(model) == "table" and model._table then
                if driver then
                    model:configure(driver)
                end
                cache[key] = model
                return model
            end
            return nil
        end,
        -- Lua 5.2+ only; Lua 5.1 ignores this and must use :each() / :modelNames()
        __pairs = function(t)
            return t:each()
        end,
    })
end

--- Initialize Jade with a single call: configure + sync schema + load models
---@param schema_path? string Path to .jade schema file (default: "schema/models.jade")
---@param opts? table Override options: { database = {...}, sync = true/false }
---@return table<string, Jade.Entity> models Lazy-loaded model proxy
function Jade.init(schema_path, opts)
    schema_path = schema_path or "schema/models.jade"
    opts = opts or {}

    -- 1. Load config
    local config_path = opts.config_path or "jade.config.lua"
    local config_ok, config = pcall(dofile, config_path)
    if not config_ok then
        error("Failed to load config from " .. config_path .. ": " .. tostring(config))
    end

    -- Apply overrides
    if opts.database then
        config.database = opts.database
    end

    -- 2. Configure Jade
    Jade.configure(config)

    -- 3. Sync schema (create tables) unless explicitly skipped
    local should_sync = opts.sync
    if should_sync == nil then
        -- Auto-detect: sync if schema file exists
        local f = io.open(schema_path, "r")
        if f then
            f:close()
            should_sync = true
        else
            should_sync = false
        end
    end

    if should_sync then
        Jade.syncSchema(schema_path)
    end

    -- 4. Load and return models
    return Jade.loadModels(opts.models_dir or "jade/generated")
end

-- Shorthand Entity constructor that auto-configures the driver
local original_entity = Jade.Entity
Jade.Entity = function(table_name, columns)
    local entity = original_entity.new(table_name, columns)
    local driver = context.get("driver")
    if driver then
        entity:configure(driver)
    end
    return entity
end

return Jade
