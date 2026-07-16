-- Simple test runner for Jade ORM
-- Usage: lua spec/run.lua

-- Setup package path
local script_path = debug.getinfo(1, "S").source:sub(2)
local dir = script_path:match("(.*[/\\])")
package.path = dir .. "../src/?.lua;" .. package.path
package.path = dir .. "../src/?/init.lua;" .. package.path
package.path = dir .. "?.lua;" .. package.path

-- Test framework
local M = {
    tests = {},
    passed = 0,
    failed = 0,
    errors = {},
    _before_each = nil,
}

function M.describe(name, fn)
    print("\n" .. name)
    fn()
    M._before_each = nil
end

function M.it(name, fn)
    if M._before_each then
        M._before_each()
    end
    local ok, err = pcall(fn)
    if ok then
        M.passed = M.passed + 1
        print("  \27[32m✓\27[0m " .. name)
    else
        M.failed = M.failed + 1
        M.errors[#M.errors + 1] = { test = name, error = err }
        print("  \27[31m✗\27[0m " .. name)
        print("    " .. tostring(err))
    end
end

function M.before_each(fn)
    M._before_each = fn
end

-- Assertions module
local assertions = {}

function assertions.equal(expected, actual)
    if expected ~= actual then
        error(string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 3)
    end
end

function assertions.same(expected, actual)
    if type(expected) ~= type(actual) then
        error(string.format("Type mismatch: expected %s, got %s", type(expected), type(actual)), 3)
    end
    if type(expected) == "table" then
        for k, v in pairs(expected) do
            if actual[k] ~= v then
                error(string.format("Key %s: expected %s, got %s", tostring(k), tostring(v), tostring(actual[k])), 3)
            end
        end
        for k in pairs(actual) do
            if expected[k] == nil then
                error(string.format("Unexpected key: %s", tostring(k)), 3)
            end
        end
    elseif expected ~= actual then
        error(string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 3)
    end
end

function assertions.is_true(val)
    if val ~= true then
        error(string.format("Expected true, got %s", tostring(val)), 3)
    end
end

function assertions.is_false(val)
    if val ~= false then
        error(string.format("Expected false, got %s", tostring(val)), 3)
    end
end

function assertions.is_not_nil(val)
    if val == nil then
        error("Expected not nil", 3)
    end
end

function assertions.is_truthy(val)
    if not val then
        error(string.format("Expected truthy, got %s", tostring(val)), 3)
    end
end

-- Wrap assertions with are table for busted compatibility
M.assert = { are = assertions }
-- Also expose directly for simpler syntax
M.assert.is_true = assertions.is_true
M.assert.is_false = assertions.is_false
M.assert.is_not_nil = assertions.is_not_nil
M.assert.is_truthy = assertions.is_truthy
M.assert.is_nil = function(val)
    if val ~= nil then
        error(string.format("Expected nil, got %s", tostring(val)), 3)
    end
end
M.assert.is_falsy = function(val)
    if val then
        error(string.format("Expected falsy, got %s", tostring(val)), 3)
    end
end
M.assert.is_truth = function(val)
    if not val then
        error(string.format("Expected truthy, got %s", tostring(val)), 3)
    end
end
M.assert.is_function = function(val)
    if type(val) ~= "function" then
        error(string.format("Expected function, got %s", type(val)), 3)
    end
end
M.assert.has_error = function(fn)
    local ok, err = pcall(fn)
    if ok then
        error("Expected error, but no error was raised", 3)
    end
end

-- Make available globally for test files
describe = M.describe
it = M.it
before_each = M.before_each
assert = M.assert

-- Load and run test files
local test_files = {
    "types/column_spec.lua",
    "types/types_spec.lua",
    "query/expression_spec.lua",
    "query/condition_spec.lua",
    "query/paginate_spec.lua",
    "entity/entity_spec.lua",
    "entity/instance_spec.lua",
    "entity/relations_spec.lua",
    "entity/entity_relations_spec.lua",
    "entity/proxy_spec.lua",
    "entity/soft_delete_spec.lua",
    "query/builder_spec.lua",
    "driver/postgresql_spec.lua",
    "migration/tracker_spec.lua",
    "migration/diff_spec.lua",
    "migration/generator_spec.lua",
    "transaction/transaction_spec.lua",
    "i18n/i18n_spec.lua",
    "security/sanitizer_spec.lua",
    "security/validator_spec.lua",
    "security/escape_spec.lua",
    "introspection/converter_spec.lua",
}

print("=== Jade ORM Test Suite ===")
print("Running " .. #test_files .. " test files...\n")

for _, file in ipairs(test_files) do
    local full_path = dir .. file
    local ok, err = pcall(dofile, full_path)
    if not ok then
        print("\27[31mFailed to load: " .. file .. "\27[0m")
        print("  " .. tostring(err))
    end
end

print("\n=== Results ===")
print(string.format("\27[32mPassed: %d\27[0m", M.passed))
if M.failed > 0 then
    print(string.format("\27[31mFailed: %d\27[0m", M.failed))
    print("\nFailed tests:")
    for _, e in ipairs(M.errors) do
        print("  - " .. e.test)
        print("    " .. e.error)
    end
else
    print("\27[32mAll tests passed!\27[0m")
end

os.exit(M.failed > 0 and 1 or 0)
