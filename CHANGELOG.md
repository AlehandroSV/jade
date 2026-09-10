# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-09-10

Jade v2 is an **ecosystem cut**, not a rewrite of the core. The core ships a
coherent, audited 2.0.0 baseline: declarative `.jade` models, a typed error
catalog, English-only runtime messages, and the audit bug-fix series.

> **Version injection:** the tree keeps `src/jade/_VERSION.lua` as `"scm"` and
> the rockspec as `scm-1`. The release workflow (`.github/workflows/release.yml`)
> injects the tag version at publish time (`v2.0.0` → `2.0.0` / `2.0.0-1`).

### Breaking

- **Runtime i18n removed from core** (#161 / #162). Messages are English-only.
  `jade.i18n` / locale switching is no longer part of the core API.
- **Typed errors are the public contract** (#163 / #164 / #166 / #187).
  Critical paths raise `jade.errors` with `J####` codes. Callers should match
  on `err.code` rather than message strings.
- **Plugin options reach `extendEntity`** (#183 / #192). Hooks that previously
  saw `{}` now receive the real per-plugin install options.
- **`unloadPlugin` actually unloads** (#171 / #188). CRUD/query hooks registered
  by a plugin are cleared; the previous no-op behavior is gone.
- **Migration tracker is per-migration and portable** (#176 / #177 / #195 / #205).
  Tracker DDL is no longer PostgreSQL-only; SQLite/MySQL work. Each migration
  is recorded inside its own transaction.

### Added

- Declarative `.jade` schema parser with `loadEntities` / `generateEntity`
  wiring model relations (#178 / #197).
- Migration generators emit runnable Lua (`createTable` function API,
  `addColumn` with length) (#172 / #186 / #202).
- Cabochon brand assets and README identity (#167).

### Fixed

Audit series #170–#187 (PRs #188–#205):

| Issue | Fix |
|---|---|
| #170 | `jade.util.hash` parses on Lua 5.1/5.2 (no binary `~`) |
| #171 | `unloadPlugin` clears hooks under each type axis |
| #172 | Migration codegen emits valid `createTable` |
| #173 | `hasMany`/`hasOne` FK placed on parent, not child |
| #174 | `Query:toSQL` restores `_where` on generate/validate error |
| #175 | Pool `transaction` binds the whole fn to one leased connection |
| #176 | Tracker written per migration inside the same transaction |
| #177 | Tracker DDL portable across SQLite/MySQL/PostgreSQL |
| #178 | `loadEntities`/`generateEntity` wire `model.relations` |
| #179 | `classifyDriverError` maps table/column before DB; MySQL `ssl_verify=false` → `REQUIRED` |
| #180 | `loadModels` free of shell injection; Lua 5.1-safe iteration |
| #181 | Path validation rejects Windows absolute/UNC paths; `writeMigration` name whitelist |
| #182 | Rollback/file specs load and run (`after_each`, Lua 5.1 syntax) |
| #183 | `extendEntity` receives real install options |
| #184 | `errors.getMessage` keeps literal `%` in details |
| #185 | `Entity.new` lazy-loads `jade.encryption` |
| #186 | `generateAddColumn` emits valid Lua when length is set |
| #187 | Bare `error()` on critical paths migrated to `jade.errors.raise` |

### Security

- Windows absolute paths and UNC paths rejected in path validation (#181).
- `loadModels` directory listing hardened against shell metacharacters (#180).
- MySQL SSL: `ssl_verify=false` no longer enables `VERIFY_CA` (#179).

### Validation

- Unit suite: **856 tests, all green** on Lua 5.1, 5.2, 5.3, 5.4.
- CI matrix: Lua 5.1–5.5 + LuaJIT.

### Upgrade notes from 1.x

1. Remove any `jade.i18n` / locale configuration.
2. Handle errors via `err.code` (`J####`) from `jade.errors`.
3. If you call `unloadPlugin`, expect hooks to be cleared for real.
4. Re-run migrations on SQLite/MySQL — tracker DDL is now portable.
5. Plugin authors: `extendEntity` context now carries install options.

[2.0.0]: https://github.com/Jade-ORM/jade-orm-core/releases/tag/v2.0.0
