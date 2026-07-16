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

- **Declarative Schema** - Define entities in Lua
- **Query Builder** - Chainable queries with JOINs, GROUP BY, HAVING, DISTINCT
- **Relations** - belongsTo, hasMany, hasOne, hasAndBelongsToMany, hasManyThrough
- **Eager Loading** - Load relations in batch with `include()`
- **Validations** - presence, uniqueness, length, format, inclusion, numericality, custom
- **Callbacks** - before/after/around hooks for create, update, delete, save
- **Migrations** - Automatic database management with DDL operations
- **Transactions** - Support for transactions with commit/rollback
- **Soft Delete** - Logical deletion with deleted_at
- **Connection Pooling** - Configurable connection pool
- **Security** - SQL injection detection, input validation
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
        driver = "postgresql",
        host = "localhost",
        port = 5432,
        database = "myapp",
        user = "postgres",
        password = "secret"
    }
})

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

### Validations

```lua
-- Add validations
User:validatePresenceOf("name")
User:validateUniquenessOf("email")
User:validateLengthOf("name", { min = 2, max = 100 })
User:validateFormatOf("email", { pattern = "^[%w%.]+@[%w%.]+$" })
User:validateInclusionOf("role", { values = {"admin", "user", "moderator"} })
User:validateNumericalityOf("age", { integer_only = true })
User:validateCustom("age", function(value)
    return value >= 18
end, "Must be 18 or older")

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
jade.addColumn("users", "phone", "string", { length = 20 })
jade.dropColumn("users", "phone")
jade.addIndex("users", "email", { unique = true })
jade.addForeignKey("posts", {
    column = "user_id",
    references_table = "users",
    references_column = "id"
})
```

### Transactions

```lua
jade.transaction.run(jade.driver(), function(tx)
    local user = User:create({ name = "Lucas" })
    Post:create({ title = "Hello", user_id = user.id })
end)
-- Auto-commit if no error, rollback if error
```

### Soft Delete

```lua
jade.SoftDelete.setup(User)

-- Delete is now soft delete
User:delete(id)              -- Sets deleted_at

-- Additional methods
User:forceDelete(id)         -- Real delete
User:withTrashed():get()     -- Include deleted
User:onlyTrashed():get()     -- Only deleted
User:restore(id)             -- Restore
```

### Connection Pooling

```lua
jade.configure({
    database = {
        driver = "postgresql",
        host = "localhost",
        database = "myapp",
        pool_size = 10,      -- Max connections
        pool_min = 2,        -- Min idle connections
        pool_timeout = 300   -- Idle timeout (seconds)
    }
})
```

### Migrations

```lua
local jade = require("jade")
jade.migration.init(driver)      -- Create tracker table
jade.migration.migrate(driver)   -- Run pending migrations
jade.migration.rollback(driver)  -- Rollback last migration
jade.migration.preview(driver)   -- Show pending
jade.migration.status(driver)    -- General summary
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
```

### License

MIT

---

## PT-BR

### Sobre

Jade e um ORM/Data Mapper moderno para Lua que oferece uma experiencia moderna de desenvolvimento, incluindo schema declarativo, migrations automaticas, query builder, relacoes, validacoes, callbacks e muito mais.

**Nao escondemos o SQL** - toda operacao pode ser visualizada e auditada.

### Features

- **Schema Declarativo** - Defina entidades em Lua
- **Query Builder** - Consultas chainable com JOINs, GROUP BY, HAVING, DISTINCT
- **Relacoes** - belongsTo, hasMany, hasOne, hasAndBelongsToMany, hasManyThrough
- **Eager Loading** - Carregue relacoes em batch com `include()`
- **Validacoes** - presence, uniqueness, length, format, inclusion, numericality, custom
- **Callbacks** - Hooks before/after/around para create, update, delete, save
- **Migrations** - Gerenciamento automatico do banco com operacoes DDL
- **Transactions** - Suporte a transacoes com commit/rollback
- **Soft Delete** - Exclusao logica com deleted_at
- **Connection Pooling** - Pool de conexoes configuravel
- **Seguranca** - Deteccao de SQL injection, validacao de entrada
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
        driver = "postgresql",
        host = "localhost",
        port = 5432,
        database = "myapp",
        user = "postgres",
        password = "secret"
    }
})

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

### Query Builder

```lua
-- WHERE
User:where(User.age:gt(18)):get()

-- AND / OR
User:where(User.age:gt(18):band(User.active:eq(true))):get()

-- JOIN
User:join("posts", User.id:eq(jade.Post.user_id)):get()

-- GROUP BY / HAVING
User:select("department", "COUNT(*) as count"):groupBy("department"):get()

-- DISTINCT
User:distinct():get()

-- Agregacoes
User:count()
User:sum("age")
User:average("age")
User:min("age")
User:max("age")

-- Paginacao
User:paginate({ page = 2, perPage = 20 })
```

### Operadores

```lua
-- Comparacao
User:where(User.name:eq("Joao")):get()
User:where(User.age:gt(18)):get()

-- Padroes
User:where(User.name:like("%Joao%")):get()
User:where(User.name:ilike("%joao%")):get()  -- Case-insensitive

-- Conjuntos
User:where(User.id:isIn({1, 2, 3})):get()
User:where(User.id:notIn({4, 5, 6})):get()

-- Null
User:where(User.deleted_at:isNull()):get()

-- Faixas
User:where(User.age:between(18, 65)):get()
```

### Relacoes

```lua
local Post = jade.Entity("posts", {
    id = jade.Integer():primaryKey(),
    title = jade.String(255),
    user_id = jade.Integer(),
})

-- Definir relacoes
Post:belongsTo(User)
User:hasMany(Post)
User:hasOne(Profile)
User:hasAndBelongsToMany(Tag)
User:hasManyThrough(Comment, Post)

-- Lazy loading
local user = User:find(1)
local posts = user.posts:load()

-- Eager loading (evitar N+1)
local users = User:include("posts"):get()
```

### Validacoes

```lua
-- Adicionar validacoes
User:validatePresenceOf("name")
User:validateUniquenessOf("email")
User:validateLengthOf("name", { min = 2, max = 100 })
User:validateFormatOf("email", { pattern = "^[%w%.]+@[%w%.]+$" })
User:validateInclusionOf("role", { values = {"admin", "user", "moderator"} })
User:validateNumericalityOf("age", { integer_only = true })

-- Validar manualmente
local errors = User:validate(data)

-- Validacoes rodam automaticamente em create/update
User:create({ name = "" })  -- Lanca erro de validacao
```

### Callbacks

```lua
-- Registrar callbacks
User:beforeCreate(function(instance, data)
    data.name = data.name:upper()
end)

User:afterCreate(function(instance, data)
    print("Usuario criado: " .. instance.name)
end)

User:beforeSave(function(instance, data)
    -- Roda antes de create e update
end)
```

### Schema (DDL)

```lua
-- Criar tabela
jade.createTable("users", function(t)
    t:column("id", "integer", { primary_key = true })
    t:column("name", "string", { length = 100, nullable = false })
    t:column("email", "string", { unique = true })
    t:timestamps()
end)

-- Outras operacoes DDL
jade.dropTable("users")
jade.addColumn("users", "phone", "string", { length = 20 })
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

### Soft Delete

```lua
jade.SoftDelete.setup(User)

-- Delete agora e soft delete
User:delete(id)              -- Seta deleted_at

-- Metodos adicionais
User:forceDelete(id)         -- Delete real
User:withTrashed():get()     -- Inclui deletados
User:onlyTrashed():get()     -- Apenas deletados
User:restore(id)             -- Restaura
```

### Pool de Conexoes

```lua
jade.configure({
    database = {
        driver = "postgresql",
        host = "localhost",
        database = "myapp",
        pool_size = 10,      -- Maximo de conexoes
        pool_min = 2,        -- Minimo de conexoes idle
        pool_timeout = 300   -- Timeout idle (segundos)
    }
})
```

### Migrations

```lua
local jade = require("jade")
jade.migration.init(driver)      -- Cria tabela tracker
jade.migration.migrate(driver)   -- Roda migracoes pendentes
jade.migration.rollback(driver)  -- Desfaz ultima migracao
jade.migration.preview(driver)   -- Mostra pendentes
jade.migration.status(driver)    -- Resumo geral
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
```

### Licenca

MIT
