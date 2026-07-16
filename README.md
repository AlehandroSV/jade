# Jade

> A modern ORM for Lua.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[![Português](https://img.shields.io/badge/Português-readme-blue)](#pt-br)
[![English](https://img.shields.io/badge/English-readme-green)](#en)

---

## EN

### About

Jade is a modern ORM/Data Mapper for Lua that offers a modern development experience, including declarative schema, automatic migrations, query builder, and multi-database support.

**We don't hide SQL** — every operation can be viewed and audited.

### Features

- **Declarative Schema** — Define entities in Lua
- **Query Builder** — Chainable and intuitive queries
- **Migrations** — Automatic database management
- **Relations** — ForeignKey, hasMany, hasOne, belongsTo
- **Pagination** — Helper to paginate results
- **Transactions** — Support for transactions with commit/rollback
- **Soft Delete** — Logical deletion with deleted_at
- **Multi-database** — PostgreSQL (MySQL and SQLite coming soon)

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
User:create({ name = "Lucas", email = "lucas@email.com" })

-- READ
local user = User:find(1)
local users = User:where(User.active:eq(true)):orderBy(User.name):get()

-- UPDATE
user:update({ name = "New Name" })

-- DELETE
user:delete()
```

### Complete API

#### Column Types

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

#### Column Modifiers

```lua
jade.Integer():primaryKey()   -- PRIMARY KEY
jade.String():unique()        -- UNIQUE
jade.String():notNull()       -- NOT NULL
jade.Boolean():default(true)  -- DEFAULT
jade.Timestamp():defaultNow() -- DEFAULT CURRENT_TIMESTAMP
```

#### Query Builder

```lua
-- WHERE
User:where(User.age:gt(18)):get()
User:where(User.active:eq(true)):get()

-- AND / OR
User:where(User.age:gt(18):band(User.active:eq(true))):get()
User:where(User.role:eq("admin"):bor(User.role:eq("moderator"))):get()

-- ORDER BY
User:orderBy(User.name):get()
User:orderBy(User.name, "DESC"):get()

-- LIMIT / OFFSET
User:limit(10):get()
User:limit(10):offset(20):get()

-- Specific SELECT
User:select("id", "name"):get()

-- Pagination
User:paginate({ page = 2, perPage = 20 })
-- Returns: { items, total, page, per_page, last_page, has_next, has_prev }

-- Aggregations
User:count()
User:sum("age")
User:average("age")
```

#### Relations

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

-- Lazy loading
local user = User:find(1)
local posts = user.posts:load()
```

#### Transactions

```lua
jade.transaction.run(jade.driver(), function(tx)
    local user = User:create({ name = "Lucas" })
    Post:create({ title = "Hello", user_id = user.id })
end)
-- Auto-commit if no error, rollback if error
```

#### Soft Delete

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

#### Migrations

```lua
local jade = require("jade")
jade.migration.init(driver)      -- Create tracker table
jade.migration.migrate(driver)   -- Run pending migrations
jade.migration.rollback(driver)  -- Rollback last migration
jade.migration.preview(driver)   -- Show pending
jade.migration.status(driver)    -- General summary
```

### Project Structure

```
jade/
├── src/jade/
│   ├── init.lua           -- Public API
│   ├── schema/            -- Schema system
│   ├── types/             -- Column types (9 types)
│   ├── entity/            -- Entity, Instance, Relations, SoftDelete
│   ├── query/             -- Query Builder, Condition, Expression, Paginate
│   ├── driver/            -- Drivers (PostgreSQL)
│   ├── migration/         -- Migration engine
│   ├── transaction/       -- Transaction system
│   ├── i18n/              -- Internationalization (en, pt-br)
│   └── util/              -- Utilities
├── spec/                  -- 126 tests
├── jade-scm-1.rockspec    -- Rockspec
└── .github/workflows/     -- CI/CD
```

### Roadmap

- [x] LuaRocks publication
- [x] i18n (en/pt-br)
- [ ] MySQL driver
- [ ] SQLite driver
- [ ] LuaLS type generation
- [ ] Eager loading (include)
- [ ] Soft delete cascade

### Contributing

This is a project under development. Contributions are welcome!

### License

MIT

---

## PT-BR

### Sobre

Jade é um ORM/Data Mapper para Lua que oferece uma experiência moderna de desenvolvimento, incluindo schema declarativo, migrations automáticas, query builder e suporte a múltiplos bancos de dados.

**Não escondemos o SQL** — toda operação pode ser visualizada e auditada.

### Features

- **Schema Declarativo** — Define entidades em Lua
- **Query Builder** — Consultas chainable e intuitivas
- **Migrations** — Gerenciamento automático do banco
- **Relações** — ForeignKey, hasMany, hasOne, belongsTo
- **Paginação** — Helper para paginar resultados
- **Transactions** — Suporte a transações com commit/rollback
- **Soft Delete** — Exclusão lógica com deleted_at
- **Multi-database** — PostgreSQL (MySQL e SQLite em breve)

### Instalação

```bash
luarocks install jade
```

### Quick Start

```lua
local jade = require("jade")

-- Configurar conexão
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
User:create({ name = "Lucas", email = "lucas@email.com" })

-- READ
local user = User:find(1)
local users = User:where(User.active:eq(true)):orderBy(User.name):get()

-- UPDATE
user:update({ name = "Novo Nome" })

-- DELETE
user:delete()
```

### API Completa

#### Tipos de Coluna

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

#### Modificadores de Coluna

```lua
jade.Integer():primaryKey()   -- PRIMARY KEY
jade.String():unique()        -- UNIQUE
jade.String():notNull()       -- NOT NULL
jade.Boolean():default(true)  -- DEFAULT
jade.Timestamp():defaultNow() -- DEFAULT CURRENT_TIMESTAMP
```

#### Query Builder

```lua
-- WHERE
User:where(User.age:gt(18)):get()
User:where(User.active:eq(true)):get()

-- AND / OR
User:where(User.age:gt(18):band(User.active:eq(true))):get()
User:where(User.role:eq("admin"):bor(User.role:eq("moderator"))):get()

-- ORDER BY
User:orderBy(User.name):get()
User:orderBy(User.name, "DESC"):get()

-- LIMIT / OFFSET
User:limit(10):get()
User:limit(10):offset(20):get()

-- SELECT específico
User:select("id", "name"):get()

-- Paginação
User:paginate({ page = 2, perPage = 20 })
-- Retorna: { items, total, page, per_page, last_page, has_next, has_prev }

-- Agregações
User:count()
User:sum("age")
User:average("age")
```

#### Relações

```lua
local Post = jade.Entity("posts", {
    id = jade.Integer():primaryKey(),
    title = jade.String(255),
    user_id = jade.Integer(),
})

-- Definir relações
Post:belongsTo(User)
User:hasMany(Post)
User:hasOne(Profile)

-- Lazy loading
local user = User:find(1)
local posts = user.posts:load()
```

#### Transactions

```lua
jade.transaction.run(jade.driver(), function(tx)
    local user = User:create({ name = "Lucas" })
    Post:create({ title = "Hello", user_id = user.id })
end)
-- Auto-commit se não houver erro, rollback se houver
```

#### Soft Delete

```lua
jade.SoftDelete.setup(User)

-- Delete agora é soft delete
User:delete(id)              -- Seta deleted_at

-- Métodos adicionais
User:forceDelete(id)         -- Delete real
User:withTrashed():get()     -- Inclui deletados
User:onlyTrashed():get()     -- Apenas deletados
User:restore(id)             -- Restaura
```

#### Migrations

```lua
local jade = require("jade")
jade.migration.init(driver)      -- Cria tabela tracker
jade.migration.migrate(driver)   -- Roda migrações pendentes
jade.migration.rollback(driver)  -- Desfaz última migração
jade.migration.preview(driver)   -- Mostra pendentes
jade.migration.status(driver)    -- Resumo geral
```

### Estrutura do Projeto

```
jade/
├── src/jade/
│   ├── init.lua           -- API pública
│   ├── schema/            -- Sistema de schema
│   ├── types/             -- Tipos de coluna (9 tipos)
│   ├── entity/            -- Entity, Instance, Relations, SoftDelete
│   ├── query/             -- Query Builder, Condition, Expression, Paginate
│   ├── driver/            -- Drivers (PostgreSQL)
│   ├── migration/         -- Engine de migrations
│   ├── transaction/       -- Sistema de transações
│   ├── i18n/              -- Internacionalização (en, pt-br)
│   └── util/              -- Utilitários
├── spec/                  -- 126 testes
├── jade-scm-1.rockspec    -- Rockspec
└── .github/workflows/     -- CI/CD
```

### Roadmap

- [x] Publicação no LuaRocks
- [x] i18n (en/pt-br)
- [ ] MySQL driver
- [ ] SQLite driver
- [ ] LuaLS type generation
- [ ] Eager loading (include)
- [ ] Soft delete cascade

### Contribuindo

Este é um projeto em desenvolvimento. Contribuições são bem-vindas!

### Licença

MIT
