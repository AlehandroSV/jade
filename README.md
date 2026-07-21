# Jade

> A modern ORM for Lua.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[![Portugues](https://img.shields.io/badge/Portugu%C3%AAs-readme-blue)](#pt-br)
[![English](https://img.shields.io/badge/English-readme-green)](#en)

---

## EN

### About

Jade is a modern ORM/Data Mapper for Lua that offers a modern development experience, including declarative schema, automatic migrations, query builder, relations, validations, callbacks, and more.

**We don't hide SQL** - every operation can be viewed and audited.

### Features

- **Multi-Driver** - PostgreSQL, MySQL, SQLite
- **Declarative Schema** - Convention-over-configuration with automatic table names, timestamps, foreign keys
- **Query Builder** - Chainable queries with JOINs, GROUP BY, HAVING, DISTINCT, subqueries
- **Relations** - belongsTo, hasMany, hasOne, hasAndBelongsToMany, hasManyThrough
- **Eager Loading** - Load relations in batch with `include()`
- **Validations** - presence, uniqueness, length, format, inclusion, numericality, custom with scopes (create/update/save)
- **Named Scopes** - Reusable, chainable query patterns
- **Callbacks** - before/after/around hooks for create, update, delete, save
- **Bulk Operations** - insertAll, updateAll, deleteAll, upsert
- **Raw SQL** - `jade.raw()` for escape hatch queries
- **Subqueries** - WHERE IN/NOT IN with Query objects, column aliasing
- **Optimistic Locking** - Version-based conflict detection
- **Event System** - Entity events, global handlers with `jade.on()`
- **Database Views** - createView, View queries, dropView
- **Query Convenience** - exists(), empty(), pluck(), take(), inBatches()
- **Query Caching** - In-memory cache with TTL and pattern invalidation
- **Column Encryption** - Database-native AES (pgcrypto/AES_ENCRYPT) or custom Lua functions
- **Audit Trail** - Automatic change tracking via callbacks
- **Soft Delete with Cascade** - Logical deletion that cascades through relations
- **Multi-Database** - Named databases, read replicas, per-entity assignment
- **Environment Config** - dev/test/prod config files with env variable resolution
- **URL Connection Strings** - `postgresql://`, `mysql://`, `sqlite:///` parsing
- **Migrations** - Automatic database management with DDL operations
- **Transactions** - Support for transactions with commit/rollback
- **Connection Pooling** - Configurable connection pool
- **Test Helpers** - setup, truncateAll, transaction with auto-rollback, factory pattern
- **Seed System** - Register, execute, factory-based with faker defaults
- **Security** - SQL injection detection, identifier quoting, input validation
- **LuaLS Type Generation** - IDE autocomplete annotations from entity definitions
- **i18n** - Internationalization (English, Portuguese)

### Installation

```bash
luarocks install jade
```

### Quick Start

```lua
local jade = require("jade")

-- Configure connection
jade.configure({
    database = {
        driver = "postgresql",   -- or "mysql", "sqlite"
        host = "localhost",
        port = 5432,
        database = "myapp",
        user = "postgres",
        password = "secret"
    }
})

-- Or use a URL string
jade.configure({ url = "postgresql://user:pass@localhost:5432/myapp" })

-- Define entities
local User = jade.Entity("users", {
    id = jade.Integer():primaryKey(),
    name = jade.String(120),
    email = jade.String():unique(),
    active = jade.Boolean():default(true),
    created_at = jade.Timestamp():defaultNow()
})

-- CREATE
local user = User:create({ name = "Lucas", email = "lucas@email.com" })

-- READ
local user = User:find(1)
local users = User:where(User.active:eq(true)):orderBy(User.name):get()

-- UPDATE
user:update({ name = "New Name" })

-- DELETE
user:delete()
```

### Database Drivers

Jade supports three database drivers out of the box:

| Driver | Package | Key Features |
|--------|---------|-------------|
| PostgreSQL | luapgsql | RETURNING, CASCADE, TIMESTAMPTZ, JSONB |
| MySQL | luasql-mysql | AUTO_INCREMENT, backtick quoting, ENGINE=InnoDB |
| SQLite | luasql-sqlite3 | AUTOINCREMENT, WAL mode, foreign_keys pragma |

```lua
-- PostgreSQL
jade.configure({ database = { driver = "postgresql", ... } })

-- MySQL
jade.configure({ database = { driver = "mysql", ... } })

-- SQLite
jade.configure({ database = { driver = "sqlite", database = "app.db" } })
```

### Declarative Schema

Define entities with conventions — Jade handles the rest:

```lua
local User = jade.Entity("users", {
    name = jade.String(120):notNull(),
    email = jade.String():unique(),
    role = jade.String(50):default("user"),
})

-- Conventions applied automatically:
-- - Table name: pluralized from entity name
-- - id column: primary key + auto increment
-- - created_at / updated_at: timestamps
```

### Query Builder

```lua
-- WHERE
User:where(User.age:gt(18)):get()
User:where(User.active:eq(true)):get()

-- AND / OR
User:where(User.age:gt(18):band(User.active:eq(true))):get()
User:where(User.role:eq("admin"):bor(User.role:eq("moderator"))):get()

-- JOIN
User:join("posts", User.id:eq(jade.Post.user_id)):get()
User:leftJoin("profiles", User.id:eq(jade.Profiles.user_id)):get()

-- GROUP BY / HAVING
User:select("department", "COUNT(*) as count"):groupBy("department"):get()

-- DISTINCT
User:distinct():get()

-- ORDER BY
User:orderBy(User.name):get()
User:orderBy(User.name, "DESC"):get()

-- LIMIT / OFFSET
User:limit(10):offset(20):get()

-- Aggregations
User:count()
User:sum("age")
User:average("age")
User:min("age")
User:max("age")

-- Pagination
User:paginate({ page = 2, perPage = 20 })

-- Subqueries
local activeUsers = User:where(User.active:eq(true))
User:where(User.id:isIn(activeUsers)):get()

-- Raw SQL
User:where(jade.raw("age > ? OR active = ?", 18, true)):get()
```

### Query Convenience Methods

```lua
User:where(User.active:eq(true)):exists()   -- true/false
User:where(User.active:eq(true)):empty()    -- true/false
User:pluck("name")                          -- {"Lucas", "Joao", ...}
User:take(3)                                -- 3 random records
User:inBatches(100, function(batch)          -- process in batches
    for _, user in ipairs(batch) do
        -- process user
    end
end)
```

### Operators

```lua
-- Comparison
User:where(User.name:eq("John")):get()
User:where(User.age:gt(18)):get()
User:where(User.age:lt(65)):get()
User:where(User.age:gte(18)):get()
User:where(User.age:lte(65)):get()
User:where(User.name:neq("Admin")):get()

-- Pattern matching
User:where(User.name:like("%John%")):get()
User:where(User.name:notLike("%Admin%")):get()
User:where(User.name:ilike("%john%")):get()  -- Case-insensitive

-- Sets
User:where(User.id:isIn({1, 2, 3})):get()
User:where(User.id:notIn({4, 5, 6})):get()

-- Null checks
User:where(User.deleted_at:isNull()):get()
User:where(User.deleted_at:isNotNull()):get()

-- Ranges
User:where(User.age:between(18, 65)):get()
User:where(User.age:notBetween(0, 17)):get()
```

### Relations

```lua
local Post = jade.Entity("posts", {
    id = jade.Integer():primaryKey(),
    title = jade.String(255),
    user_id = jade.Integer(),
})

-- Define relations
Post:belongsTo(User)
User:hasMany(Post)
User:hasOne(Profile)
User:hasAndBelongsToMany(Tag)
User:hasManyThrough(Comment, Post)

-- Lazy loading
local user = User:find(1)
local posts = user.posts:load()

-- Eager loading (avoid N+1)
local users = User:include("posts"):get()
```

### Named Scopes

```lua
-- Define scopes
User:scope("active", function(query)
    return query:where(User.active:eq(true))
end)

User:scope("byRole", function(query, role)
    return query:where(User.role:eq(role))
end)

-- Use scopes (chainable)
User:scope("active"):get()
User:scope("byRole", "admin"):get()
User:scope("active"):scope("byRole", "admin"):orderBy(User.name):get()
```

### Validations

```lua
-- Add validations with scope support
User:validatePresenceOf("name")
User:validateUniquenessOf("email")
User:validateLengthOf("name", { min = 2, max = 100 })
User:validateFormatOf("email", { pattern = "^[%w%.]+@[%w%.]+$" })
User:validateInclusionOf("role", { values = {"admin", "user", "moderator"} })
User:validateNumericalityOf("age", { integer_only = true })
User:validateCustom("age", function(value)
    return value >= 18
end, "Must be 18 or older")

-- Scoped validations (only run on specific actions)
User:validatePresenceOf("password", { on = "create" })
User:validateUniquenessOf("email", { on = "create" })
User:validateNumericalityOf("age", { on = {"create", "update"} })

-- Validate manually
local errors = User:validate(data)
if errors then
    -- Handle errors
end

-- Validations run automatically on create/update
User:create({ name = "" })  -- Throws validation error
```

### Callbacks

```lua
-- Register callbacks
User:beforeCreate(function(instance, data)
    data.name = data.name:upper()
end)

User:afterCreate(function(instance, data)
    print("User created: " .. instance.name)
end)

User:beforeSave(function(instance, data)
    -- Runs before both create and update
end)

User:aroundSave(function(instance, data, next)
    -- Custom logic before
    next()
    -- Custom logic after
end)
```

### Bulk Operations

```lua
-- Insert multiple rows
User:insertAll({
    { name = "Lucas", email = "lucas@email.com" },
    { name = "Joao", email = "joao@email.com" },
    { name = "Maria", email = "maria@email.com" },
})

-- Update all matching rows
User:where(User.active:eq(false)):updateAll({ active = true })

-- Delete all matching rows
User:where(User.role:eq("guest")):deleteAll()

-- Upsert (insert or update on conflict)
User:upsert(
    { name = "Lucas", email = "lucas@email.com" },
    { "email" }  -- conflict columns
)
```

### Soft Delete with Cascade

```lua
jade.SoftDelete.setup(User, { cascade = true })

-- Delete is now soft delete
User:delete(id)              -- Sets deleted_at, cascades to relations

-- Additional methods
User:forceDelete(id)         -- Real delete
User:withTrashed():get()     -- Include deleted
User:onlyTrashed():get()     -- Only deleted
User:restore(id)             -- Restore (cascades to relations)
User:withoutTrashed():get()  -- Explicitly exclude deleted
```

### Optimistic Locking

```lua
-- Add version column for conflict detection
User:optimisticLocking()

-- On update, version is checked automatically
local user = User:find(1)
user:update({ name = "New Name" })  -- Includes AND version = ?

-- Returns nil on conflict (version mismatch)
```

### Event System

```lua
-- Define custom events
jade.Events.define(User, { "verified", "suspended" })

-- Fire events
User:fire("verified", { user_id = 1 })

-- Listen globally
jade.on("users.verified", function(data)
    print("User verified: " .. data.user_id)
end)

-- Built-in events: created, updated, deleted
```

### Database Views

```lua
-- Create a view
jade.createView("active_users", User:where(User.active:eq(true)))

-- Query a view
local view = jade.View("active_users")
local users = view:get()

-- Drop a view
jade.dropView("active_users")
```

### Audit Trail

```lua
-- Setup audit tracking for an entity
jade.Audit.setup(User, { ignore = {"updated_at"} })

-- Changes are automatically logged to jade_audit_logs table
-- Tracks: create, update (with old/new values), delete

-- Query audit logs
local logs = jade.Audit.query(jade.driver(), {
    table_name = "users",
    action = "update",
})
```

### Column Encryption

Jade supports two encryption modes: **database-native** (recommended for production) and **custom** (for user-provided logic).

#### Database-Native Encryption (AES)

Uses the database's built-in encryption functions. Requires PostgreSQL with pgcrypto extension or MySQL.

```lua
-- Configure encryption with a secret key
jade.Encryption.configure({ key = "my-secret-key" })

-- PostgreSQL: install pgcrypto extension first
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Mark columns as encrypted
local User = jade.Entity("users", {
    id = jade.Integer():primaryKey(),
    name = jade.String(120),
    email = jade.String(255):encrypted(),
    ssn = jade.String(11):encrypted(),
})

-- Values are encrypted in the database (not in Lua)
-- PostgreSQL: pgp_sym_encrypt/column, key
-- MySQL: AES_ENCRYPT(column, key)
-- Decryption happens automatically on SELECT
```

#### Custom Encryption (User-Provided Functions)

Provide your own encrypt/decrypt functions. Works with any database including SQLite.

```lua
-- Option 1: Inline functions
jade.Encryption.configure({
    key = "my-secret-key",
    algorithm = "custom",
    encrypt_fn = function(value, key)
        -- your encryption logic here
        return encrypted_value
    end,
    decrypt_fn = function(encrypted, key)
        -- your decryption logic here
        return original_value
    end,
})

-- Option 2: Separate files (recommended for complex logic)
jade.Encryption.configure({
    key = "my-secret-key",
    algorithm = "custom",
    encrypt_file = "encryption/encrypt.lua",
    decrypt_file = "encryption/decrypt.lua",
})
```

The encryption files must return a function:

```lua
-- encryption/encrypt.lua
return function(value, key)
    -- Example: simple Caesar cipher (NOT secure, just for demo)
    local result = {}
    for i = 1, #value do
        local byte = string.byte(value, i)
        local key_byte = string.byte(key, (i - 1) % #key + 1)
        result[i] = string.char((byte + key_byte) % 256)
    end
    return table.concat(result)
end
```

```lua
-- encryption/decrypt.lua
return function(encrypted, key)
    -- Reverse the encryption
    local result = {}
    for i = 1, #encrypted do
        local byte = string.byte(encrypted, i)
        local key_byte = string.byte(key, (i - 1) % #key + 1)
        result[i] = string.char((byte - key_byte) % 256)
    end
    return table.concat(result)
end
```

#### Encryption Configuration Options

```lua
jade.Encryption.configure({
    key = "secret",                    -- Encryption key (required)
    algorithm = "aes" | "custom",      -- "aes" for DB-native, "custom" for Lua functions
    database_encrypted = true,         -- Encrypt ALL columns in ALL entities
    fields = {                         -- Encrypt specific fields per entity
        users = {"ssn", "tax_id"},
        payments = {"card_number", "cvv"},
    },
    encrypt_fn = function,             -- Custom encrypt function (inline)
    decrypt_fn = function,             -- Custom decrypt function (inline)
    encrypt_file = "path/to/encrypt.lua",  -- Custom encrypt function (from file)
    decrypt_file = "path/to/decrypt.lua",  -- Custom decrypt function (from file)
})
```

### Query Caching

```lua
-- Cache a query result
User:where(User.active:eq(true)):cache(300):get()  -- TTL: 300 seconds

-- Custom cache key
User:where(User.role:eq("admin")):cache(600, "admin_users"):get()

-- Invalidate cache by pattern
jade.cache.invalidatePattern("users:*")
```

### Multi-Database Support

```lua
-- Register multiple databases
jade.database.configure({
    primary = { driver = "postgresql", host = "localhost", database = "myapp" },
    analytics = { driver = "postgresql", host = "localhost", database = "analytics" },
})

-- Connect to specific database
local analytics = jade.database.connect("analytics")

-- Read replicas
jade.database.addReplicas("primary", {
    { driver = "postgresql", host = "replica1", database = "myapp" },
    { driver = "postgresql", host = "replica2", database = "myapp" },
})
local replica = jade.database.getReplica("primary")

-- Per-entity database assignment
local Log = jade.Entity("logs", {}, { database = "analytics" })

-- Health check
local health = jade.database.healthCheck()
```

### Environment Config

```lua
-- jade.config.lua (base)
return {
    database = {
        driver = "postgresql",
        host = "localhost",
        database = "myapp",
    }
}

-- jade.config.production.lua (environment override)
return {
    database = {
        host = os.getenv("DB_HOST"),
        password = os.getenv("DB_PASSWORD"),
    }
}

-- Load with environment detection
jade.configureFromEnvironment(".")

-- Or use env vars in config: ${VAR_NAME} or ${VAR_NAME:default}
```

### Schema (DDL)

```lua
-- Create table
jade.createTable("users", function(t)
    t:column("id", "integer", { primary_key = true })
    t:column("name", "string", { length = 100, nullable = false })
    t:column("email", "string", { unique = true })
    t:timestamps()
end)

-- Other DDL operations
jade.dropTable("users")
jade.renameTable("users", "accounts")
jade.addColumn("users", "phone", "string", { length = 20 })
jade.dropColumn("users", "phone")
jade.renameColumn("users", "phone", "telephone")
jade.addIndex("users", "email", { unique = true })
jade.dropIndex("users", "users_idx_email")
jade.addForeignKey("posts", {
    column = "user_id",
    references_table = "users",
    references_column = "id",
    on_delete = "CASCADE"
})
jade.dropForeignKey("posts", "posts_fk_user_id")
```

### Transactions

```lua
jade.transaction.run(jade.driver(), function(tx)
    local user = User:create({ name = "Lucas" })
    Post:create({ title = "Hello", user_id = user.id })
end)
-- Auto-commit if no error, rollback if error
```

### Test Helpers

```lua
-- Setup test database
jade.test.setup(jade, { truncate = true })

-- Truncate specific tables
jade.test.truncateAll(jade.driver(), {"users", "posts"})

-- Run in transaction with auto-rollback
jade.test.transaction(jade.driver(), function()
    User:create({ name = "Test" })
    -- Automatically rolled back
end)

-- Factory pattern for test data
local user = jade.factory(User):create()
local admin = jade.factory(User):create({ role = "admin" })
local users = jade.factoryList(User, 10)
```

### Seed System

```lua
-- Register seed files
jade.Seed.register("users", "seeds/users.lua")
jade.Seed.register("posts", "seeds/posts.lua")

-- Execute seeds
jade.Seed.execute(jade.driver(), "seeds/users.lua")

-- Seed file formats:
-- 1. Simple: return { table = "users", data = { {name="Lucas"}, ... } }
-- 2. Array: return { {table="users", data={...}}, {table="posts", data={...}} }
-- 3. Factory: return { factories = {...}, data = {...} }
```

### Column Types

```lua
jade.String(120)      -- VARCHAR(120)
jade.Text()           -- TEXT
jade.Integer()        -- INTEGER
jade.Float()          -- FLOAT
jade.Decimal(10, 2)   -- DECIMAL(10,2)
jade.Boolean()        -- BOOLEAN
jade.Timestamp()      -- TIMESTAMPTZ
jade.Date()           -- DATE
jade.UUID()           -- UUID
```

### Column Modifiers

```lua
jade.Integer():primaryKey()   -- PRIMARY KEY
jade.String():unique()        -- UNIQUE
jade.String():notNull()       -- NOT NULL
jade.Boolean():default(true)  -- DEFAULT
jade.Timestamp():defaultNow() -- DEFAULT CURRENT_TIMESTAMP
jade.String():encrypted()     -- ENCRYPTED (requires Encryption.configure())
```

### License

MIT

---

## PT-BR

### Sobre

Jade e um ORM/Data Mapper moderno para Lua que oferece uma experiencia moderna de desenvolvimento, incluindo schema declarativo, migrations automaticas, query builder, relacoes, validacoes, callbacks e muito mais.

**Nao escondemos o SQL** - toda operacao pode ser visualizada e auditada.

### Features

- **Multi-Driver** - PostgreSQL, MySQL, SQLite
- **Schema Declarativo** - Convention-over-configuration com nomes de tabela automaticos, timestamps, foreign keys
- **Query Builder** - Consultas chainable com JOINs, GROUP BY, HAVING, DISTINCT, subqueries
- **Relacoes** - belongsTo, hasMany, hasOne, hasAndBelongsToMany, hasManyThrough
- **Eager Loading** - Carregue relacoes em batch com `include()`
- **Validacoes** - presence, uniqueness, length, format, inclusion, numericality, custom com escopos (create/update/save)
- **Named Scopes** - Padroes de query reutilizaveis e chainable
- **Callbacks** - Hooks before/after/around para create, update, delete, save
- **Operacoes em Bulk** - insertAll, updateAll, deleteAll, upsert
- **SQL Bruto** - `jade.raw()` para consultas escape hatch
- **Subqueries** - WHERE IN/NOT IN com objetos Query, aliasing de colunas
- **Locking Otimista** - Deteccao de conflito baseada em versao
- **Sistema de Eventos** - Eventos de entidade, handlers globais com `jade.on()`
- **Views de Banco** - createView, consultas View, dropView
- **Conveniencia de Query** - exists(), empty(), pluck(), take(), inBatches()
- **Cache de Query** - Cache em memoria com TTL e invalidacao por padrao
- **Criptografia de Coluna** - AES nativo do banco (pgcrypto/AES_ENCRYPT) ou funcoes customizadas
- **Trail de Auditoria** - Rastreamento automatico de mudancas via callbacks
- **Soft Delete com Cascata** - Exclusao logica que cascata pelas relacoes
- **Multi-Banco** - Bancos nomeados, read replicas, assignacao por entidade
- **Config por Ambiente** - Arquivos de config dev/test/prod com resolucao de variaveis de ambiente
- **URL Connection Strings** - Parsing de `postgresql://`, `mysql://`, `sqlite:///`
- **Migrations** - Gerenciamento automatico do banco com operacoes DDL
- **Transactions** - Suporte a transacoes com commit/rollback
- **Pool de Conexoes** - Pool de conexoes configuravel
- **Test Helpers** - setup, truncateAll, transaction com auto-rollback, padrao factory
- **Sistema de Seeds** - Register, execute, padrao factory com defaults faker
- **Seguranca** - Deteccao de SQL injection, quoting de identificadores, validacao de entrada
- **Geracao de Tipos LuaLS** - Anotacoes de autocomplete para IDE a partir de definicoes de entidade
- **i18n** - Internacionalizacao (Ingles, Portugues)

### Instalacao

```bash
luarocks install jade
```

### Quick Start

```lua
local jade = require("jade")

-- Configurar conexao
jade.configure({
    database = {
        driver = "postgresql",   -- ou "mysql", "sqlite"
        host = "localhost",
        port = 5432,
        database = "myapp",
        user = "postgres",
        password = "secret"
    }
})

-- Ou use uma URL
jade.configure({ url = "postgresql://user:pass@localhost:5432/myapp" })

-- Definir entidades
local User = jade.Entity("users", {
    id = jade.Integer():primaryKey(),
    name = jade.String(120),
    email = jade.String():unique(),
    active = jade.Boolean():default(true),
    created_at = jade.Timestamp():defaultNow()
})

-- CREATE
local user = User:create({ name = "Lucas", email = "lucas@email.com" })

-- READ
local user = User:find(1)
local users = User:where(User.active:eq(true)):orderBy(User.name):get()

-- UPDATE
user:update({ name = "Novo Nome" })

-- DELETE
user:delete()
```

### Drivers de Banco

| Driver | Pacote | Caracteristicas |
|--------|--------|----------------|
| PostgreSQL | luapgsql | RETURNING, CASCADE, TIMESTAMPTZ, JSONB |
| MySQL | luasql-mysql | AUTO_INCREMENT, quoting com backtick, ENGINE=InnoDB |
| SQLite | luasql-sqlite3 | AUTOINCREMENT, modo WAL, pragma foreign_keys |

### Schema Declarativo

```lua
local User = Jade.Entity("users", {
    name = Jade.String(120):notNull(),
    email = Jade.String():unique(),
    role = Jade.String(50):default("user"),
})

-- Convencoes aplicadas automaticamente:
-- - Nome da tabela: pluralizado
-- - Coluna id: primary key + auto increment
-- - created_at / updated_at: timestamps
```

### Query Builder

```lua
-- WHERE
User:where(User.age:gt(18)):get()

-- AND / OR
User:where(User.age:gt(18):band(User.active:eq(true))):get()

-- JOIN
User:join("posts", User.id:eq(jade.Post.user_id)):get()
User:leftJoin("profiles", User.id:eq(jade.Profiles.user_id)):get()

-- GROUP BY / HAVING
User:select("department", "COUNT(*) as count"):groupBy("department"):get()

-- Subqueries
local activeUsers = User:where(User.active:eq(true))
User:where(User.id:isIn(activeUsers)):get()

-- SQL Bruto
User:where(jade.raw("age > ? OR active = ?", 18, true)):get()
```

### Named Scopes

```lua
-- Definir scopes
User:scope("active", function(query)
    return query:where(User.active:eq(true))
end)

-- Usar scopes (chainable)
User:scope("active"):get()
User:scope("active"):orderBy(User.name):get()
```

### Validacoes

```lua
-- Com suporte a escopo
User:validatePresenceOf("name")
User:validateUniquenessOf("email")
User:validatePresenceOf("password", { on = "create" })
User:validateNumericalityOf("age", { on = {"create", "update"} })

-- Validacoes rodam automaticamente em create/update
User:create({ name = "" })  -- Lanca erro de validacao
```

### Operacoes em Bulk

```lua
-- Inserir multiplos registros
User:insertAll({
    { name = "Lucas", email = "lucas@email.com" },
    { name = "Joao", email = "joao@email.com" },
})

-- Atualizar todos que correspondem
User:where(User.active:eq(false)):updateAll({ active = true })

-- Upsert (insert ou update em caso de conflito)
User:upsert({ name = "Lucas", email = "lucas@email.com" }, { "email" })
```

### Soft Delete com Cascata

```lua
Jade.SoftDelete.setup(User, { cascade = true })

User:delete(id)              -- Seta deleted_at, cascata para relacoes
User:forceDelete(id)         -- Delete real
User:withTrashed():get()     -- Inclui deletados
User:onlyTrashed():get()     -- Apenas deletados
User:restore(id)             -- Restaura (cascata para relacoes)
```

### Multi-Banco

```lua
-- Registrar multiplos bancos
jade.database.configure({
    primary = { driver = "postgresql", host = "localhost", database = "myapp" },
    analytics = { driver = "postgresql", host = "localhost", database = "analytics" },
})

-- Read replicas
jade.database.addReplicas("primary", {
    { driver = "postgresql", host = "replica1", database = "myapp" },
})
local replica = jade.database.getReplica("primary")

-- Assignacao por entidade
local Log = jade.Entity("logs", {}, { database = "analytics" })
```

### Config por Ambiente

```lua
-- jade.config.lua (base)
return { database = { driver = "postgresql", host = "localhost", database = "myapp" } }

-- jade.config.production.lua (override)
return { database = { host = os.getenv("DB_HOST"), password = os.getenv("DB_PASSWORD") } }

-- Carregar com deteccao de ambiente
jade.configureFromEnvironment(".")
```

### Schema (DDL)

```lua
jade.createTable("users", function(t)
    t:column("id", "integer", { primary_key = true })
    t:column("name", "string", { length = 100, nullable = false })
    t:column("email", "string", { unique = true })
    t:timestamps()
end)

jade.dropTable("users")
jade.renameTable("users", "accounts")
jade.addColumn("users", "phone", "string", { length = 20 })
jade.dropColumn("users", "phone")
jade.renameColumn("users", "phone", "telephone")
jade.addIndex("users", "email", { unique = true })
```

### Transacoes

```lua
jade.transaction.run(jade.driver(), function(tx)
    local user = User:create({ name = "Lucas" })
    Post:create({ title = "Ola", user_id = user.id })
end)
-- Auto-commit se nao houver erro, rollback se houver
```

### Test Helpers

```lua
jade.test.setup(jade, { truncate = true })
jade.test.transaction(jade.driver(), function()
    User:create({ name = "Teste" })
    -- Automaticamente revertido
end)

local user = jade.factory(User):create()
local users = jade.factoryList(User, 10)
```

### Sistema de Seeds

```lua
jade.Seed.register("users", "seeds/users.lua")
jade.Seed.execute(jade.driver(), "seeds/users.lua")
```

### Tipos de Coluna

```lua
jade.String(120)      -- VARCHAR(120)
jade.Text()           -- TEXT
jade.Integer()        -- INTEGER
jade.Float()          -- FLOAT
jade.Decimal(10, 2)   -- DECIMAL(10,2)
jade.Boolean()        -- BOOLEAN
jade.Timestamp()      -- TIMESTAMPTZ
jade.Date()           -- DATE
jade.UUID()           -- UUID
```

### Modificadores de Coluna

```lua
jade.Integer():primaryKey()   -- PRIMARY KEY
jade.String():unique()        -- UNIQUE
jade.String():notNull()       -- NOT NULL
jade.Boolean():default(true)  -- DEFAULT
jade.Timestamp():defaultNow() -- DEFAULT CURRENT_TIMESTAMP
jade.String():encrypted()     -- ENCRIPTOGRAFADO (XOR+base64)
```

### Licenca

MIT
