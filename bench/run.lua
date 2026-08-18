-- Jade ORM Benchmark Suite
-- Usage: lua bench/run.lua

local script_path = debug.getinfo(1, "S").source:sub(2)
local dir = script_path:match("(.*[/\\])")
package.path = dir .. "../src/?.lua;" .. package.path
package.path = dir .. "../src/?/init.lua;" .. package.path

-- Load compatibility layer for Lua 5.1
require("jade.util.compat")

local Jade = require("jade")
local Entity = require("jade.entity")
local Query = require("jade.query")
local Condition = require("jade.query.condition")

-- Configuration
local ITERATIONS = 1000
local WARMUP = 50

-- Benchmark runner
local function benchmark(name, fn)
    -- Warmup
    for _ = 1, WARMUP do
        fn()
    end

    -- Measure
    local start = os.clock()
    for _ = 1, ITERATIONS do
        fn()
    end
    local elapsed = os.clock() - start
    local ops = math.floor(ITERATIONS / elapsed)

    return {
        name = name,
        elapsed = elapsed,
        ops = ops,
    }
end

-- Mock driver for benchmarks
local function mock_driver()
    return {
        execute = function(sql, bindings)
            return { { id = 1, name = "test" } }
        end,
        generateSelect = function(query)
            return "SELECT * FROM users", {}
        end,
    }
end

-- Setup
Jade.configure({ driver = "sqlite", database = ":memory:" })

local User = Entity.new("users", {
    id = Jade.Integer():primaryKey(),
    name = Jade.String(100),
    email = Jade.String(200),
})
User._driver = mock_driver()

local results = {}

-- Query Benchmarks
print("=== Jade Benchmark Suite ===")
print(string.format("Iterations: %d | Warmup: %d\n", ITERATIONS, WARMUP))

print("Query Benchmarks:")

results[#results + 1] = benchmark("Simple SELECT", function()
    local q = Query.new(User)
    q:_compileSelect()
end)

results[#results + 1] = benchmark("ORDER BY", function()
    local q = Query.new(User)
    q:orderBy("name", "ASC")
    q:_compileSelect()
end)

results[#results + 1] = benchmark("LIMIT/OFFSET", function()
    local q = Query.new(User)
    q:limit(10):offset(20)
    q:_compileSelect()
end)

results[#results + 1] = benchmark("Complex query", function()
    local q = Query.new(User)
    q:where(Condition.new("age", ">", 18, "users"))
        :orderBy("name", "ASC")
        :limit(10)
        :offset(0)
    q:_compileSelect()
end)

results[#results + 1] = benchmark("COUNT", function()
    local q = Query.new(User)
    q:count()
end)

results[#results + 1] = benchmark("EXISTS", function()
    local q = Query.new(User)
    q:exists()
end)

-- Entity Benchmarks
print("\nEntity Benchmarks:")

results[#results + 1] = benchmark("Entity creation", function()
    local e = Entity.new("test_" .. math.random(1000), {
        id = Jade.Integer():primaryKey(),
        name = Jade.String(100),
    })
end)

results[#results + 1] = benchmark("Entity with relations", function()
    local Post = Entity.new("posts_" .. math.random(1000), {
        id = Jade.Integer():primaryKey(),
        title = Jade.String(200),
        user_id = Jade.Integer(),
    })
    Post:belongsTo(User, { foreign_key = "user_id" })
end)

-- Condition Benchmarks
print("\nCondition Benchmarks:")

results[#results + 1] = benchmark("Simple condition", function()
    Condition.new("name", "=", "John", "users")
end)

results[#results + 1] = benchmark("Compound condition", function()
    local c1 = Condition.new("age", ">", 18, "users")
    local c2 = Condition.new("status", "=", "active", "users")
    c1:band(c2)
end)

results[#results + 1] = benchmark("Raw condition", function()
    Jade.raw("age > ? AND status = ?", 18, "active")
end)

-- Schema Benchmarks
print("\nSchema Benchmarks:")

results[#results + 1] = benchmark("Declarative parse", function()
    Entity.new("schema_test_" .. math.random(1000), {
        id = Jade.Integer():primaryKey(),
        name = Jade.String(100),
        email = Jade.String(200),
        age = Jade.Integer(),
        active = Jade.Boolean(),
        created_at = Jade.DateTime(),
    })
end)

-- Print results
print("\n" .. string.rep("-", 60))
print(string.format("%-30s %10s %15s", "Benchmark", "Time", "Ops/s"))
print(string.rep("-", 60))

for _, r in ipairs(results) do
    print(string.format("%-30s %10.3fs %15s", r.name, r.elapsed, tostring(r.ops)))
end

print(string.rep("-", 60))
print("\nBenchmark complete.")
