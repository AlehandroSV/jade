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

-- Audit
Jade.Audit = require("jade.audit")

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

-- Current driver instance
local current_driver = nil

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
    current_driver = DriverClass.new()

    -- Load plugins configured in jade.config.lua (plugins field)
    if opts.plugins then
        local results_ = Jade.pluginLoader.loadAll(Jade, opts.plugins)
        for name_, res_ in pairs(results_) do
            if not res_.ok then
                error("failed to load plugin '" .. name_ .. "': " .. tostring(res_.error))
            end
        end
    end

    current_driver:connect(db)

    return current_driver
end

-- Configure from environment-specific config files
function Jade.configureFromEnvironment(basePath)
    local env_config = Jade.config.loadForEnvironment(basePath)
    return Jade.configure(env_config)
end

function Jade.driver()
    if not current_driver then
        error(Jade.i18n.t("not_configured"))
    end
    return current_driver
end

function Jade.disconnect()
    if current_driver then
        current_driver:disconnect()
        current_driver = nil
    end
end

function Jade.raw(sql, ...)
    return { _raw = sql, _bindings = { ... } }
end

-- Event convenience
function Jade.on(event_name, handler)
    return Jade.Events.on(event_name, handler)
end

-- DDL shortcuts (delegate to Schema module with current driver)
function Jade.createTable(name, fn)
    return Jade.Schema.createTable(Jade.driver(), name, fn)
end

function Jade.dropTable(name)
    return Jade.Schema.dropTable(Jade.driver(), name)
end

function Jade.renameTable(old_name, new_name)
    return Jade.Schema.renameTable(Jade.driver(), old_name, new_name)
end

function Jade.addColumn(table_name, column_name, type_name, options)
    return Jade.Schema.addColumn(Jade.driver(), table_name, column_name, type_name, options)
end

function Jade.dropColumn(table_name, column_name)
    return Jade.Schema.dropColumn(Jade.driver(), table_name, column_name)
end

function Jade.renameColumn(table_name, old_name, new_name)
    return Jade.Schema.renameColumn(Jade.driver(), table_name, old_name, new_name)
end

function Jade.addIndex(table_name, columns, options)
    return Jade.Schema.addIndex(Jade.driver(), table_name, columns, options)
end

function Jade.dropIndex(table_name, index_name)
    return Jade.Schema.dropIndex(Jade.driver(), table_name, index_name)
end

function Jade.addForeignKey(table_name, options)
    return Jade.Schema.addForeignKey(Jade.driver(), table_name, options)
end

function Jade.dropForeignKey(table_name, constraint_name)
    return Jade.Schema.dropForeignKey(Jade.driver(), table_name, constraint_name)
end

-- Shorthand Entity constructor that auto-configures the driver
local original_entity = Jade.Entity
Jade.Entity = function(table_name, columns)
    local entity = original_entity.new(table_name, columns)
    if current_driver then
        entity:configure(current_driver)
    end
    return entity
end

return Jade