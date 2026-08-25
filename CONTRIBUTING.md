# Contributing to Jade ORM

Thank you for your interest in contributing to Jade! This document will help you get started and ensure a smooth contribution experience.

---

## Table of Contents

- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [How to Add a Feature](#how-to-add-a-feature)
- [Code Conventions](#code-conventions)
- [Conventional Commits](#conventional-commits)
- [Reporting Bugs](#reporting-bugs)
- [Requesting Features](#requesting-features)
- [Submitting Pull Requests](#submitting-pull-requests)
- [License](#license)

---

## Development Setup

### Prerequisites

1. **Lua** — versions 5.2, 5.3, 5.4 must be available (local testing requires all three)
   - Windows: install each version to `C:/luaversion/lua5.X/`
   - Unix: use your package manager or compile from source
2. **LuaRocks** — for dependency management (`luarocks install`)
3. **Git** — for version control

### Installation

```bash
# Clone the repository
git clone https://github.com/AlehandroSV/jade.git
cd jade

# Install via LuaRocks (optional — for local development)
luarocks make jade-scm-1.rockspec
```

### Running Tests

```bash
# Run unit tests
make test              # or: lua spec/run.lua

# Run integration tests
make integration       # or: lua spec/integration/run.lua

# Lint check
make lint              # or: luacheck src/

# Benchmarks
make benchmark         # or: lua bench/run.lua
```

### Testing Across Lua Versions

Jade supports Lua 5.2, 5.3, and 5.4. Always verify your changes pass on all versions:

```bash
# Lua 5.2
"C:/luaversion/lua5.2/lua52.exe" spec/run.lua

# Lua 5.3
"C:/luaversion/lua5.3/lua53.exe" spec/run.lua

# Lua 5.4
"C:/luaversion/lua5.4/lua54.exe" spec/run.lua
```

On Linux/macOS:

```bash
lua52 spec/run.lua && lua53 spec/run.lua && lua54 spec/run.lua
```

The CI pipeline runs all three automatically on every push/PR.

---

## Project Structure

```
jade/
├── src/jade/                    # Core source code
│   ├── init.lua                 # Main entry point
│   ├── driver/                  # Database drivers
│   │   ├── postgresql.lua
│   │   ├── mysql.lua
│   │   ├── mariadb.lua
│   │   ├── sqlite.lua
│   │   └── pool.lua             # Connection pooling
│   ├── entity/                  # Entity system
│   ├── query/                   # Query builder
│   ├── schema/                  # Schema definition
│   ├── migration/               # Migration system
│   ├── types/                   # Column types
│   ├── errors/                  # Error classes
│   ├── security/                # Security utilities
│   ├── plugin/                  # Plugin system
│   ├── transaction/             # Transaction management
│   └── util/                    # Utilities
├── spec/                        # Test suite
│   ├── run.lua                  # Test runner — add new specs here
│   ├── helpers/                 # Test utilities
│   └── <module>/                # Per-module test directories
├── migrations/                  # Example migrations
├── fixtures/                    # Test fixtures
├── bench/                       # Benchmarks
├── scripts/                     # Release scripts
├── Makefile                     # Build commands
├── README.md                    # Documentation
└── jade-scm-1.rockspec          # LuaRocks manifest
```

### Key Files

| File | Purpose |
|------|---------|
| `src/jade/init.lua` | Main API entry point |
| `spec/run.lua` | Fixed list of test specs — **every new spec must be registered here** |
| `src/jade/driver/` | One file per database driver |
| `src/jade/entity/` | Entity, instance, relations, callbacks |
| `src/jade/query/` | Query builder, conditions, expressions |
| `.luarc.json` | LuaLS configuration |
| `.luacheckrc` | Luacheck linter config |

---

## How to Add a Feature

Follow these steps in order:

### 1. Receive and validate the issue

- Read the full issue description on GitHub
- Identify affected file(s)
- Validate the described problem locally with available Lua versions (5.2–5.4)
- Define the technical solution before writing code

### 2. Write tests first (TDD)

- Create spec file in `spec/{module}/{name}_spec.lua`
- Cover the **happy path** + **edge cases**
- Add the new spec to the fixed list in `spec/run.lua` if it doesn't exist yet
- Use native runner assertions: `assert.are.equal()`, `assert.is_true()`, `assert.has_error()`
- Run with `lua spec/run.lua` — **it should fail before implementation**

### 3. Implement the code

- Make the minimum change needed to pass the tests
- Follow existing project style conventions
- Never use MCP/tool calls for commits — only edit/write_file for code changes

### 4. Validate with all Lua versions

Run tests on Lua 5.2, 5.3, and 5.4. If all pass, proceed.

> **Note:** If CI fails on LuaJIT or Lua 5.5 but you can't reproduce locally, comment out the suspect spec in `spec/run.lua`, document it, and proceed. **Do not block merges for CI failures you cannot reproduce locally.**

### 5. Create internal documentation

Create `PRs/issue-{number}.md` in the parent ORM project (not in this repo).

### 6. Prepare for commit/push

The contributor (you) should:

```bash
cd jade
git add .
git commit -m "feat(description): short description of what was done

- Detail 1
- Detail 2

Closes #{number}"
git push origin your-branch-name
```

Then create a PR manually via GitHub.

---

## Code Conventions

### Naming

| Type | Convention | Example |
|------|-----------|---------|
| Files / Modules | `snake_case.lua` | `query_builder.lua` |
| Functions / Variables | `snake_case` | `get_user_by_id` |
| Classes / Entities | `PascalCase` | `User`, `Post` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_CONNECTIONS` |
| Private helpers | `_prefix_` | `_sanitize_input` |
| Tables / Columns | `snake_case` | `created_at`, `user_id` |

### Style

- **Indentation:** 4 spaces (no tabs)
- **Line length:** Soft limit at 100 characters. Break before operators.
- **Blank lines:** One between functions, two between modules. No trailing whitespace.
- **Errors:** Use the error hierarchy in `src/jade/errors/`. Never use bare `error("string")` — use typed errors.
- **Comments:** Only explain the **why**, never the **what**. Names should be self-explanatory.
- **Documentation:** JSDoc-style comments for public APIs using `---@param` / `---@return` annotations for LuaLS support.

### Lua-Specific Guidelines

- Use `local` for all variables unless truly global
- Return multiple values explicitly; avoid implicit globals
- Use `table.insert` / `table.concat` over raw array operations when possible
- Prefer `pairs()` for named tables, `ipairs()` for arrays
- Use `pcall` for error handling; avoid bare `xpcall`
- Keep metamethod usage minimal and well-documented
- Avoid LuaJIT-specific constructs unless gated behind a feature flag

---

## Conventional Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for changelog generation and clarity.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Code style changes (formatting, semicolons, etc.) |
| `refactor` | Code refactoring (no feature, no fix) |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |
| `perf` | Performance improvements |
| `ci` | CI configuration changes |
| `revert` | Reverting a previous commit |

### Scopes

| Scope | Area |
|-------|------|
| `driver` | Database driver code |
| `entity` | Entity system |
| `query` | Query builder |
| `schema` | Schema definition |
| `migration` | Migration system |
| `types` | Column types |
| `errors` | Error classes |
| `security` | Security utilities |
| `plugin` | Plugin system |
| `transaction` | Transaction management |
| `util` | Utilities |
| `pool` | Connection pooling |
| `general` | General / cross-cutting |

### Examples

```
feat(driver): add CockroachDB wire-compatible support
fix(query): handle null in where clause builder
docs(readme): add SSL/TLS examples
test(entity): add relation cascade coverage
refactor(query): simplify condition builder logic
perf(pool): reduce connection handoff overhead
```

### Rules

- Subject line: max 72 characters, lowercase, no period
- Body: wrap at 100 characters, explain **what** and **why**
- Use `Closes #N` or `Fixes #N` in the footer for linked issues
- Use `BREAKING CHANGE:` in the footer for breaking changes

---

## Reporting Bugs

Before creating a bug report:

1. **Search existing issues** — make sure the bug isn't already reported
2. **Try to reproduce** the bug consistently
3. **Gather environment info** (Lua version, OS, DB driver, Jade version)

### Creating an Issue

Use the **Bug Report** template (`.github/ISSUE_TEMPLATE/bug_report.md`). Fill in:

- Clear title with `[BUG]` prefix
- Steps to reproduce (numbered)
- Expected vs. actual behavior
- Environment details
- Minimal code example
- Logs/error output

---

## Requesting Features

Before requesting a feature:

1. **Check existing issues** — avoid duplicates
2. **Consider scope** — is this within the project's vision?

### Creating an Issue

Use the **Feature Request** template (`.github/ISSUE_TEMPLATE/feature_request.md`). Include:

- Problem statement
- Proposed solution
- Alternatives considered
- Use cases

---

## Submitting Pull Requests

### Before Submitting

- [ ] Tests are written and passing (`make test`)
- [ ] All Lua versions pass (5.2, 5.3, 5.4)
- [ ] Code follows conventions in this document
- [ ] Documentation is updated (README, inline docs)
- [ ] Commit message follows Conventional Commits format
- [ ] Related issue is linked (`Closes #N` or `References #N`)
- [ ] Linting passes (`make lint`)

### Branch Naming

```
<author>/<issue>/<type>/<slug>
```

Example: `alehandrosv/95/feat/json-operators`

### PR Template

Fill in the PR template (`.github/PULL_REQUEST_TEMPLATE.md`) completely. The checklist ensures reviewers have everything they need.

### Review Process

1. Push your branch and open a PR against `dev`
2. CI will run tests on all supported Lua versions
3. Address review feedback promptly
4. Once approved, a maintainer will merge the PR

> **Note:** PRs targeting `dev` only. Do not push directly to `dev` or `master`.

---

## Questions?

If you have questions about contributing, feel free to open a **Discussion** or reference an existing issue. Be respectful and patient — maintainers are volunteers helping build great software.

---

## License

By contributing to Jade, you agree that your contributions will be licensed under the MIT License (see [LICENSE](LICENSE)).