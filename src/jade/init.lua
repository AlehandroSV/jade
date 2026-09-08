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

-- i18n
Jade.i18n = require("jade.i18n")

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

-- Soft Delete
Jade.SoftDelete = require("jade.entity.soft_delete")

-- Events
Jade.Events = require("jade.entity.events")

-- Security
Jade.security = require("jade.security")

-- Audit (lazy load to avoid circular dependency)
setmetatable(Jade, {
    __index = function(t, key)
        if key == "Audit" then
            local Audit = require("jade.audit")
            rawset(t, "Audit", Audit)
            return Audit
        end
    end
})

-- Encryption
Jade.Encryption = require("jade.encryption")

-- Schema (DDL operations)
Jade.Schema = require("jade.schema")

-- Declarative Schema
Jade.Declarative = require("jade.schema.declarative")

-- Driver registry
Jade.drivers = require("jade.driver")

-- Cache
Jade.cache = require("jade.cache")

-- Database (multi-database support)
Jade.database = require("jade.database")

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
    -- Set locale if provided
    if opts.locale then
        Jade.i18n.setLocale(opts.locale)
    end

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
                error("failed to load plugin '" .. name_ .. "': " .. tostring(res_.error))
            end
        end
    end

    driver:connect(db)

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
        error(Jade.i18n.t("not_configured"))
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
        error("Schema file not found: " .. filepath)
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

--- Load generated model files from a directory
---@param dir? string Directory path (default: "jade/models")
---@return table<string, Jade.Entity> models Map of model name to entity
function Jade.loadModels(dir)
    dir = dir or "jade/models"
    local models = {}
    local driver = context.get("driver")

    -- Try to load directory listing
    local ok, iter = pcall(function()
        -- Lua 5.2+ uses io.popen for directory listing
        local handle = io.popen('ls "' .. dir .. '" 2>/dev/null || dir /b "' .. dir .. '" 2>nul')
        if not handle then return nil end
        local result = handle:read("*a")
        handle:close()
        return result
    end)

    if not ok or not iter then
        -- Fallback: try common model names from .jade
        return models
    end

    for filename in iter:gmatch("[^\r\n]+") do
        if filename:match("%.lua$") then
            local model_name = filename:gsub("%.lua$", "")
            local filepath = dir .. "/" .. filename
            local model_ok, model = pcall(dofile, filepath)
            if model_ok and type(model) == "table" and model._table then
                if driver then
                    model:configure(driver)
                end
                models[model_name] = model
            end
        end
    end

    return models
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
