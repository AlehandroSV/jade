---@meta jade

--- Jade ORM Type Definitions for Lua Language Server (LuaLS)
--- Provides autocomplete and type checking for Jade's public API.
---@see https://github.com/AlehandroSV/jade/issues/65

-- ============================================================================
-- Jade Module
-- ============================================================================

---@class Jade
---@field _VERSION string Jade version string
---@field String fun(length?: number): Jade.Column
---@field Integer fun(): Jade.Column
---@field BigInt fun(): Jade.Column
---@field Float fun(): Jade.Column
---@field Decimal fun(): Jade.Column
---@field Boolean fun(): Jade.Column
---@field Text fun(): Jade.Column
---@field Timestamp fun(): Jade.Column
---@field Date fun(): Jade.Column
---@field UUID fun(): Jade.Column
---@field CUID fun(): Jade.Column
---@field NanoID fun(): Jade.Column
---@field JSON fun(): Jade.Column
---@field Enum fun(...: string): Jade.Column
---@field Entity Jade.EntityModule
---@field Relations Jade.RelationsModule
---@field migration Jade.MigrationModule
---@field transaction Jade.TransactionModule
---@field SoftDelete Jade.SoftDeleteModule
---@field Events Jade.EventsModule
---@field security Jade.SecurityModule
---@field Audit Jade.AuditModule
---@field Encryption Jade.EncryptionModule
---@field Schema Jade.SchemaModule
---@field Declarative Jade.DeclarativeModule
---@field drivers Jade.DriversModule
---@field cache Jade.CacheModule
---@field database Jade.DatabaseModule
---@field config Jade.ConfigModule
---@field log Jade.LogModule
---@field configure fun(config: Jade.Config)
---@field driver fun(): Jade.Driver
local Jade = {}

-- ============================================================================
-- Column Types
-- ============================================================================

---@class Jade.Column
---@field _name string Column name
---@field _table string Table name
---@field _type string Column type identifier
---@field _length? number Maximum length for string types
---@field _primary_key boolean Whether this is a primary key
---@field _not_null boolean Whether this column is NOT NULL
---@field _unique boolean Whether this column has a UNIQUE constraint
---@field _default any Default value
---@field _encrypted boolean Whether this column is encrypted
---@field _enum_values string[] Enum allowed values
function Jade.Column:primaryKey() return self end
function Jade.Column:notNull() return self end
function Jade.Column:unique() return self end
function Jade.Column:default(value) return self end
function Jade.Column:defaultNow() return self end
function Jade.Column:encrypted() return self end
function Jade.Column:onDelete(action) return self end
function Jade.Column:onUpdate(action) return self end

-- ============================================================================
-- Entity
-- ============================================================================

---@class Jade.EntityModule
---@overload fun(table_name: string, columns: table<string, Jade.Column>, options?: Jade.EntityOptions): Jade.Entity

---@class Jade.EntityOptions
---@field database? string Database name override
---@field encryption? table Encryption configuration

---@class Jade.Entity : table
---@field _table string Database table name
---@field _columns table<string, Jade.Column> Column definitions
---@field _relations table<string, Jade.Relation> Relation definitions
---@field _validations table Validations registered on this entity
---@field _callbacks table Callbacks registered on this entity
---@field _scopes table<string, function> Named query scopes
---@field _driver? Jade.Driver Currently attached driver instance
---@field _database? string Optional database override

--- Attach a driver to this entity for database operations
---@param driver Jade.Driver Database driver instance
function Jade.Entity:configure(driver) end

--- Define or invoke a named query scope
---@param name string Scope identifier
---@vararg function|any Scope function or filter arguments
---@return Jade.Entity|Jade.Query
function Jade.Entity:scope(name, ...) end

--- Create a new record
---@param data table<string, any> Record data
---@return Jade.Instance
function Jade.Entity:create(data) end

--- Find a record by primary key
---@param id any Primary key value
---@return Jade.Instance?
function Jade.Entity:find(id) end

--- Get the first matching record
---@return Jade.Instance?
function Jade.Entity:first() end

--- Get all matching records
---@return Jade.Instance[]
function Jade.Entity:all() end

--- Start a query chain with a WHERE condition
---@param condition Jade.Condition|string Column name or condition
---@vararg any Condition arguments if condition is a string
---@return Jade.Query
function Jade.Entity:where(condition, ...) end

--- Order results by column
---@param column string Column name
---@param direction? string Sort direction: "asc" (default) or "desc"
---@return Jade.Query
function Jade.Entity:orderBy(column, direction) end

--- Limit the number of results
---@param n number Maximum number of rows
---@return Jade.Query
function Jade.Entity:limit(n) end

--- Skip a number of results
---@param n number Number of rows to skip
---@return Jade.Query
function Jade.Entity:offset(n) end

--- Select specific columns
---@vararg string Column names to select
---@return Jade.Query
function Jade.Entity:select(...) end

--- Eager-load a relation
---@param relation string Relation name
---@return Jade.Query
function Jade.Entity:include(relation) end

--- Count matching records
---@return number
function Jade.Entity:count() end

--- Sum a column
---@param column string Column name
---@return number
function Jade.Entity:sum(column) end

--- Average of a column
---@param column string Column name
---@return number
function Jade.Entity:average(column) end

--- Minimum value of a column
---@param column string Column name
---@return any
function Jade.Entity:min(column) end

--- Maximum value of a column
---@param column string Column name
---@return any
function Jade.Entity:max(column) end

--- Get paginated results
---@param options Jade.PaginateOptions Pagination options
---@return Jade.PaginatedResult
function Jade.Entity:paginate(options) end

--- Update records matching condition
---@param condition table<string, any> Where condition as key-value pairs
---@param data table<string, any> Update data
---@return number Number of affected rows
function Jade.Entity:updateAll(condition, data) end

--- Delete records matching condition
---@param condition table<string, any> Where condition as key-value pairs
---@return number Number of deleted rows
function Jade.Entity:deleteAll(condition) end

--- Bulk insert multiple records
---@param records table[] Array of record data
---@return number Number of inserted rows
function Jade.Entity:bulkCreate(records) end

--- Register a validation for presence
---@param column string Column name
---@param options? table Validation options
function Jade.Entity:validatePresenceOf(column, options) end

--- Register a validation for uniqueness
---@param column string Column name
---@param options? table Validation options
function Jade.Entity:validateUniquenessOf(column, options) end

--- Register a validation for length
---@param column string Column name
---@param options? table Validation options
function Jade.Entity:validateLengthOf(column, options) end

--- Register a validation for format
---@param column string Column name
---@param options? table Validation options
function Jade.Entity:validateFormatOf(column, options) end

--- Register a validation for inclusion in a set
---@param column string Column name
---@param options? table Validation options
function Jade.Entity:validateInclusionOf(column, options) end

--- Register a validation for numericality
---@param column string Column name
---@param options? table Validation options
function Jade.Entity:validateNumericalityOf(column, options) end

--- Register a custom validation
---@param column string Column name
---@param fn function Validation function
---@param message? string Error message
function Jade.Entity:validateCustom(column, fn, message) end

--- Register a beforeCreate callback
---@param fn function Callback function
function Jade.Entity:beforeCreate(fn) end

--- Register an afterCreate callback
---@param fn function Callback function
function Jade.Entity:afterCreate(fn) end

--- Register a beforeUpdate callback
---@param fn function Callback function
function Jade.Entity:beforeUpdate(fn) end

--- Register an afterUpdate callback
---@param fn function Callback function
function Jade.Entity:afterUpdate(fn) end

--- Register a beforeDestroy callback
---@param fn function Callback function
function Jade.Entity:beforeDestroy(fn) end

--- Register an afterDestroy callback
---@param fn function Callback function
function Jade.Entity:afterDestroy(fn) end

--- Register a beforeSave callback (create + update)
---@param fn function Callback function
function Jade.Entity:beforeSave(fn) end

--- Register an afterSave callback (create + update)
---@param fn function Callback function
function Jade.Entity:afterSave(fn) end

--- Enable soft delete on this entity
---@param options? Jade.SoftDeleteOptions Soft delete options
function Jade.Entity:softDelete(options) end

--- Restore soft-deleted records
---@param condition table<string, any> Where condition
---@return number Number of restored rows
function Jade.Entity:restore(condition) end

--- Include soft-deleted records in query
---@return Jade.Query
function Jade.Entity:withTrashed() end

--- Return only soft-deleted records
---@return Jade.Query
function Jade.Entity:onlyTrashed() end

-- ============================================================================
-- Query
-- ============================================================================

---@class Jade.Query : table
---@field _entity Jade.Entity The entity this query targets
---@field _table string Target table name
---@field _where Jade.Condition[] WHERE clause conditions
---@field _orderBy {column: string, dir: string}[] ORDER BY clauses
---@field _limit? integer LIMIT count
---@field _offset? integer OFFSET skip count
---@field _select string[] SELECT columns
---@field _includes string[] Eager-loaded relations
---@field _bindings any[] Parameter bindings
---@field _joins {type: string, table: string, on: any}[] JOIN definitions
---@field _groupBy string[] GROUP BY columns
---@field _having Jade.Condition[] HAVING conditions
---@field _distinct boolean Whether to use DISTINCT
---@field _cache_ttl? number Cache TTL in seconds
---@field _cache_key? string Cache key
---@field _timeout? number Query timeout in milliseconds
---@field _include_trashed boolean Include soft-deleted records
---@field _only_trashed boolean Only soft-deleted records

--- Add a WHERE condition
---@param condition Jade.Condition|string Column name or condition
---@vararg any Condition arguments
---@return Jade.Query
function Jade.Query:where(condition, ...) end

--- Add an ORDER BY clause
---@param column string Column name
---@param direction? string "asc" or "desc"
---@return Jade.Query
function Jade.Query:orderBy(column, direction) end

--- Set LIMIT
---@param n number Maximum rows
---@return Jade.Query
function Jade.Query:limit(n) end

--- Set OFFSET
---@param n number Rows to skip
---@return Jade.Query
function Jade.Query:offset(n) end

--- Select specific columns
---@vararg string Column names
---@return Jade.Query
function Jade.Query:select(...) end

--- Eager-load a relation
---@param relation string Relation name
---@return Jade.Query
function Jade.Query:include(relation) end

--- Use DISTINCT
---@return Jade.Query
function Jade.Query:distinct() end

--- Add a JOIN
---@param table_name string Table to join
---@param on Jade.Condition Join condition
---@return Jade.Query
function Jade.Query:join(table_name, on) end

--- Add a LEFT JOIN
---@param table_name string Table to join
---@param on Jade.Condition Join condition
---@return Jade.Query
function Jade.Query:leftJoin(table_name, on) end

--- Add GROUP BY
---@vararg string Column names
---@return Jade.Query
function Jade.Query:groupBy(...) end

--- Add HAVING condition
---@param condition Jade.Condition Having condition
---@return Jade.Query
function Jade.Query:having(condition) end

--- Execute query and return all results
---@return Jade.Instance[]
function Jade.Query:get() end

--- Execute query and return first result
---@return Jade.Instance?
function Jade.Query:first() end

--- Find by primary key
---@param id any Primary key value
---@return Jade.Instance?
function Jade.Query:find(id) end

--- Count matching rows
---@return number
function Jade.Query:count() end

--- Sum a column
---@param column string Column name
---@return number
function Jade.Query:sum(column) end

--- Average of a column
---@param column string Column name
---@return number
function Jade.Query:average(column) end

--- Minimum value
---@param column string Column name
---@return any
function Jade.Query:min(column) end

--- Maximum value
---@param column string Column name
---@return any
function Jade.Query:max(column) end

--- Paginate results
---@param options Jade.PaginateOptions Pagination options
---@return Jade.PaginatedResult
function Jade.Query:paginate(options) end

--- Update all matching records
---@param data table<string, any> Update data
---@return number Affected rows
function Jade.Query:updateAll(data) end

--- Delete all matching records
---@return number Deleted rows
function Jade.Query:deleteAll() end

--- Set cache TTL
---@param seconds number Cache TTL in seconds
---@param key? string Optional cache key
---@return Jade.Query
function Jade.Query:cache(seconds, key) end

--- Set query timeout
---@param ms number Timeout in milliseconds
---@return Jade.Query
function Jade.Query:timeout(ms) end

--- Include soft-deleted records
---@return Jade.Query
function Jade.Query:withTrashed() end

--- Only soft-deleted records
---@return Jade.Query
function Jade.Query:onlyTrashed() end

-- ============================================================================
-- Instance
-- ============================================================================

---@class Jade.Instance : table
---@field _entity Jade.Entity The entity this instance belongs to
---@field _data table<string, any> Raw record data
---@field _original table<string, any> Original data before changes
---@field _dirty boolean Whether data has been modified
---@field _new boolean Whether this is a new (unsaved) record
---@field _loaded_relations table<string, any> Eager-loaded relations

--- Save the instance (create or update)
---@return Jade.Instance
function Jade.Instance:save() end

--- Destroy the record
---@return Jade.Instance
function Jade.Instance:destroy() end

--- Update record fields
---@param data table<string, any> Fields to update
---@return Jade.Instance
function Jade.Instance:update(data) end

--- Reload from database
---@return Jade.Instance
function Jade.Instance:reload() end

--- Convert to plain table
---@return table<string, any>
function Jade.Instance:toTable() end

--- Check if a relation is loaded
---@param name string Relation name
---@return boolean
function Jade.Instance:isLoaded(name) end

-- ============================================================================
-- Condition / Expression
-- ============================================================================

---@class Jade.Condition

---@class Jade.Expression
---@field _column string Column name
---@field _table string Table name

--- Equal to value
---@param value any Comparison value
---@return Jade.Condition
function Jade.Expression:eq(value) end

--- Not equal to value
---@param value any Comparison value
---@return Jade.Condition
function Jade.Expression:neq(value) end

--- Less than value
---@param value any Comparison value
---@return Jade.Condition
function Jade.Expression:lt(value) end

--- Less than or equal to value
---@param value any Comparison value
---@return Jade.Condition
function Jade.Expression:le(value) end

--- Greater than value
---@param value any Comparison value
---@return Jade.Condition
function Jade.Expression:gt(value) end

--- Greater than or equal to value
---@param value any Comparison value
---@return Jade.Condition
function Jade.Expression:ge(value) end

--- LIKE pattern match
---@param value string Pattern
---@return Jade.Condition
function Jade.Expression:like(value) end

--- IN list of values
---@param values any[] List of values
---@return Jade.Condition
function Jade.Expression:inList(values) end

--- NOT IN list of values
---@param values any[] List of values
---@return Jade.Condition
function Jade.Expression:notInList(values) end

--- Between two values
---@param low any Lower bound
---@param high any Upper bound
---@return Jade.Condition
function Jade.Expression:between(low, high) end

--- IS NULL
---@return Jade.Condition
function Jade.Expression:isNull() end

--- IS NOT NULL
---@return Jade.Condition
function Jade.Expression:isNotNull() end

-- ============================================================================
-- Relations
-- ============================================================================

---@class Jade.RelationsModule

--- Create a foreign key relation
---@param target_entity Jade.Entity Target entity
---@param options? Jade.RelationOptions Relation options
---@return Jade.Relation
function Jade.RelationsModule.ForeignKey(target_entity, options) end

--- Create a hasMany relation
---@param source_entity Jade.Entity Source entity
---@param target_entity Jade.Entity Target entity
---@param options? Jade.RelationOptions Relation options
---@return Jade.Relation
function Jade.RelationsModule.hasMany(source_entity, target_entity, options) end

--- Create a hasOne relation
---@param source_entity Jade.Entity Source entity
---@param target_entity Jade.Entity Target entity
---@param options? Jade.RelationOptions Relation options
---@return Jade.Relation
function Jade.RelationsModule.hasOne(source_entity, target_entity, options) end

--- Create a belongsTo relation
---@param target_entity Jade.Entity Target entity
---@param options? Jade.RelationOptions Relation options
---@return Jade.Relation
function Jade.RelationsModule.belongsTo(target_entity, options) end

--- Create a hasAndBelongsToMany relation
---@param target_entity Jade.Entity Target entity
---@param options? Jade.RelationOptions Relation options
---@return Jade.Relation
function Jade.RelationsModule.hasAndBelongsToMany(target_entity, options) end

---@class Jade.Relation
---@field type string Relation type: "belongsTo", "hasMany", "hasOne", "hasAndBelongsToMany", "hasManyThrough"
---@field source Jade.Entity Source entity
---@field target Jade.Entity Target entity
---@field foreign_key string Foreign key column name
---@field onDelete string ON DELETE action
---@field onUpdate string ON UPDATE action

---@class Jade.RelationOptions
---@field foreign_key? string Foreign key column name
---@field onDelete? string ON DELETE action: CASCADE, SET NULL, RESTRICT, NO ACTION
---@field onUpdate? string ON UPDATE action: CASCADE, SET NULL, RESTRICT, NO ACTION
---@field through? string Through table for hasManyThrough
---@field pivot? string Pivot table for hasAndBelongsToMany

-- ============================================================================
-- Pagination
-- ============================================================================

---@class Jade.PaginateOptions
---@field page? number Page number (default: 1)
---@field per_page? number Items per page (default: 20)

---@class Jade.PaginatedResult
---@field data Jade.Instance[] Records for current page
---@field total number Total number of records
---@field page number Current page number
---@field per_page number Items per page
---@field total_pages number Total number of pages
---@field has_next boolean Whether there is a next page
---@field has_prev boolean Whether there is a previous page

-- ============================================================================
-- Soft Delete
-- ============================================================================

---@class Jade.SoftDeleteModule

--- Setup soft delete on an entity
---@param entity Jade.Entity Entity to configure
---@param options? Jade.SoftDeleteOptions Soft delete options
function Jade.SoftDeleteModule.setup(entity, options) end

--- Check if an entity has soft delete enabled
---@param entity Jade.Entity Entity to check
---@return boolean
function Jade.SoftDeleteModule.isSoftDeleted(entity) end

--- Get the soft delete column name
---@param entity Jade.Entity Entity to check
---@return string
function Jade.SoftDeleteModule.getSoftDeleteColumn(entity) end

---@class Jade.SoftDeleteOptions
---@field column? string Soft delete column name (default: "deleted_at")
---@field cascade? boolean Cascade soft delete to relations (default: true)

-- ============================================================================
-- Migration
-- ============================================================================

---@class Jade.MigrationModule

--- Initialize migration tracking
---@param driver Jade.Driver Database driver
function Jade.MigrationModule.init(driver) end

--- Run pending migrations
---@param driver Jade.Driver Database driver
---@param steps? number Number of migrations to run
function Jade.MigrationModule.run(driver, steps) end

--- Rollback migrations
---@param driver Jade.Driver Database driver
---@param steps? number Number of migrations to rollback
function Jade.MigrationModule.rollback(driver, steps) end

--- Get migration status
---@param driver Jade.Driver Database driver
---@return table Migration status info
function Jade.MigrationModule.status(driver) end

-- ============================================================================
-- Transaction
-- ============================================================================

---@class Jade.TransactionModule

--- Execute a function inside a transaction
---@param fn function Function to execute
---@return any Return value from fn
function Jade.TransactionModule.execute(fn) end

-- ============================================================================
-- Driver
-- ============================================================================

---@class Jade.Driver
---@field _type string Driver type: "postgresql", "mysql", "sqlite"

--- Execute a raw SQL query
---@param sql string SQL query
---@param params? any[] Query parameters
---@return table[] Query results
function Jade.Driver:execute(sql, params) end

--- Execute a query and return affected row count
---@param sql string SQL query
---@param params? any[] Query parameters
---@return number Affected rows
function Jade.Driver:executeNonQuery(sql, params) end

--- Get the last inserted ID
---@return number|string
function Jade.Driver:lastInsertId() end

--- Begin a transaction
function Jade.Driver:beginTransaction() end

--- Commit the current transaction
function Jade.Driver:commit() end

--- Rollback the current transaction
function Jade.Driver:rollback() end

--- Close the connection
function Jade.Driver:close() end

-- ============================================================================
-- Events
-- ============================================================================

---@class Jade.EventsModule

--- Register an event listener
---@param event string Event name
---@param fn function Callback function
function Jade.EventsModule.on(event, fn) end

--- Remove an event listener
---@param event string Event name
---@param fn function Callback function
function Jade.EventsModule.off(event, fn) end

--- Emit an event
---@param event string Event name
---@vararg any Event arguments
function Jade.EventsModule.emit(event, ...) end

-- ============================================================================
-- Security
-- ============================================================================

---@class Jade.SecurityModule

--- Sanitize a string for safe SQL usage
---@param value string Input value
---@return string Sanitized value
function Jade.SecurityModule.sanitize(value) end

--- Escape a string for Lua string interpolation
---@param value string Input value
---@return string Escaped value
function Jade.SecurityModule.escapeLuaString(value) end

-- ============================================================================
-- Cache
-- ============================================================================

---@class Jade.CacheModule

--- Set a cache entry
---@param key string Cache key
---@param value any Value to cache
---@param ttl? number Time to live in seconds
function Jade.CacheModule.set(key, value, ttl) end

--- Get a cache entry
---@param key string Cache key
---@return any|nil Cached value or nil
function Jade.CacheModule.get(key) end

--- Delete a cache entry
---@param key string Cache key
function Jade.CacheModule.delete(key) end

--- Clear all cache entries
function Jade.CacheModule.clear() end

-- ============================================================================
-- Database (Multi-Database Support)
-- ============================================================================

---@class Jade.DatabaseModule

--- Connect to a named database
---@param name string Database name
---@return Jade.Driver
function Jade.DatabaseModule.connect(name) end

--- Register a database configuration
---@param name string Database name
---@param config Jade.DatabaseConfig Database configuration
function Jade.DatabaseModule.register(name, config) end

---@class Jade.DatabaseConfig
---@field driver string Driver type
---@field host? string Database host
---@field port? number Database port
---@field database string Database name
---@field user? string Database user
---@field password? string Database password
---@field ssl? boolean Use SSL connection

-- ============================================================================
-- Config
-- ============================================================================

---@class Jade.ConfigModule

--- Load configuration from file
---@param path? string Config file path
---@return Jade.Config
function Jade.ConfigModule.load(path) end

---@class Jade.Config
---@field database Jade.DatabaseConfig Database configuration
---@field pool? Jade.PoolConfig Connection pool settings
---@field logging? Jade.LoggingConfig Logging configuration
---@field encryption? Jade.EncryptionConfig Encryption settings

---@class Jade.PoolConfig
---@field max_size? number Maximum pool size (default: 10)
---@field min_size? number Minimum pool size (default: 2)
---@field idle_timeout? number Idle timeout in seconds (default: 300)

---@class Jade.LoggingConfig
---@field level? string Log level: "debug", "info", "warn", "error"
---@field sql? boolean Log SQL queries

---@class Jade.EncryptionConfig
---@field key string Encryption key
---@field algorithm? string Encryption algorithm (default: "aes")

-- ============================================================================
-- Encryption
-- ============================================================================

---@class Jade.EncryptionModule

--- Encrypt a value
---@param value string Value to encrypt
---@return string Encrypted value
function Jade.EncryptionModule.encrypt(value) end

--- Decrypt a value
---@param encrypted string Encrypted value
---@return string Decrypted value
function Jade.EncryptionModule.decrypt(encrypted) end

-- ============================================================================
-- Schema (DDL Operations)
-- ============================================================================

---@class Jade.SchemaModule

--- Create a table
---@param name string Table name
---@param fn function Table definition function
function Jade.SchemaModule.create(name, fn) end

--- Alter a table
---@param name string Table name
---@param fn function Alteration function
function Jade.SchemaModule.alter(name, fn) end

--- Drop a table
---@param name string Table name
function Jade.SchemaModule.drop(name) end

-- ============================================================================
-- Declarative Schema
-- ============================================================================

---@class Jade.DeclarativeModule

--- Define a schema declaratively
---@param definition table Schema definition
function Jade.DeclarativeModule.define(definition) end

-- ============================================================================
-- Drivers Module
-- ============================================================================

---@class Jade.DriversModule

--- Register a new driver
---@param name string Driver name
---@param driver Jade.Driver Driver instance
function Jade.DriversModule.register(name, driver) end

--- Get a registered driver
---@param name string Driver name
---@return Jade.Driver?
function Jade.DriversModule.get(name) end

-- ============================================================================
-- Log Module
-- ============================================================================

---@class Jade.LogModule

--- Log a debug message
---@param message string Log message
---@vararg any Format arguments
function Jade.LogModule.debug(message, ...) end

--- Log an info message
---@param message string Log message
---@vararg any Format arguments
function Jade.LogModule.info(message, ...) end

--- Log a warning message
---@param message string Log message
---@vararg any Format arguments
function Jade.LogModule.warn(message, ...) end

--- Log an error message
---@param message string Log message
---@vararg any Format arguments
function Jade.LogModule.error(message, ...) end

-- ============================================================================
-- Audit Module
-- ============================================================================

---@class Jade.AuditModule

--- Enable audit logging on an entity
---@param entity Jade.Entity Entity to audit
---@param options? table Audit options
function Jade.AuditModule.setup(entity, options) end

--- Get audit log for a record
---@param entity Jade.Entity Entity to query
---@param id any Record ID
---@return table[] Audit log entries
function Jade.AuditModule.getLog(entity, id) end

return Jade
