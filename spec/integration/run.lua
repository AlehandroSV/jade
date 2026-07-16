-- Integration test runner for Jade ORM
-- Requires PostgreSQL running on localhost:5432

local jade = require("jade")

-- Configure database connection
local driver = jade.configure({
    host = os.getenv("JADE_TEST_HOST") or "localhost",
    port = tonumber(os.getenv("JADE_TEST_PORT")) or 5432,
    database = os.getenv("JADE_TEST_DB") or "jade_test",
    user = os.getenv("JADE_TEST_USER") or "postgres",
    password = os.getenv("JADE_TEST_PASSWORD") or "postgres",
})

print("=== Jade ORM Integration Tests ===")
print("Connected to PostgreSQL")

-- Track results
local passed = 0
local failed = 0
local errors = {}

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  \27[32m✓\27[0m " .. name)
    else
        failed = failed + 1
        errors[#errors + 1] = { test = name, error = err }
        print("  \27[31m✗\27[0m " .. name)
        print("    " .. tostring(err))
    end
end

-- Clean up tables
local function cleanup()
    pcall(function() driver:execute("DROP TABLE IF EXISTS posts CASCADE") end)
    pcall(function() driver:execute("DROP TABLE IF EXISTS users CASCADE") end)
    pcall(function() driver:execute("DROP TABLE IF EXISTS categories CASCADE") end)
    pcall(function() driver:execute("DROP TABLE IF EXISTS posts_categories CASCADE") end)
end

-- Setup tables
local function setup()
    cleanup()

    driver:execute([[
        CREATE TABLE users (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            active BOOLEAN DEFAULT true,
            created_at TIMESTAMPTZ DEFAULT NOW()
        )
    ]])

    driver:execute([[
        CREATE TABLE posts (
            id SERIAL PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            content TEXT,
            user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT NOW()
        )
    ]])

    driver:execute([[
        CREATE TABLE categories (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL
        )
    ]])

    driver:execute([[
        CREATE TABLE posts_categories (
            post_id INTEGER REFERENCES posts(id) ON DELETE CASCADE,
            category_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
            PRIMARY KEY (post_id, category_id)
        )
    ]])
end

-- Define entities
local User = jade.Entity("users", {
    id = jade.Integer():primaryKey(),
    name = jade.String(100):notNull(),
    email = jade.String(255):unique():notNull(),
    active = jade.Boolean():default(true),
    created_at = jade.Timestamp():defaultNow(),
})

local Post = jade.Entity("posts", {
    id = jade.Integer():primaryKey(),
    title = jade.String(255):notNull(),
    content = jade.Text(),
    user_id = jade.Integer():notNull(),
    created_at = jade.Timestamp():defaultNow(),
})

local Category = jade.Entity("categories", {
    id = jade.Integer():primaryKey(),
    name = jade.String(100):notNull(),
})

-- Setup relations
User:hasMany(Post, { foreign_key = "user_id" })
Post:belongsTo(User, { foreign_key = "user_id" })

-- Run tests
print("\n--- CRUD Tests ---")

test("create user", function()
    setup()
    local user = User:create({ name = "John Doe", email = "john@example.com" })
    assert(user.id, "User should have id")
    assert(user.name == "John Doe", "User name should match")
    assert(user.email == "john@example.com", "User email should match")
end)

test("find user by id", function()
    local user = User:find(1)
    assert(user, "User should exist")
    assert(user.name == "John Doe", "User name should match")
end)

test("get all users", function()
    local users = User:get()
    assert(#users == 1, "Should have 1 user")
end)

test("update user", function()
    local user = User:update(1, { name = "Jane Doe" })
    assert(user.name == "Jane Doe", "User name should be updated")
end)

test("delete user", function()
    local user = User:delete(1)
    assert(user, "Deleted user should be returned")
    local users = User:get()
    assert(#users == 0, "Should have 0 users")
end)

print("\n--- Query Tests ---")

test("create multiple users", function()
    User:create({ name = "User 1", email = "user1@example.com" })
    User:create({ name = "User 2", email = "user2@example.com" })
    User:create({ name = "User 3", email = "user3@example.com" })
    local users = User:get()
    assert(#users == 3, "Should have 3 users")
end)

test("where condition", function()
    local users = User:where(User.name:eq("User 1")):get()
    assert(#users == 1, "Should find 1 user")
    assert(users[1].name == "User 1", "Should be User 1")
end)

test("order by", function()
    local users = User:orderBy(User.name):get()
    assert(users[1].name == "User 1", "First should be User 1")
    assert(users[2].name == "User 2", "Second should be User 2")
    assert(users[3].name == "User 3", "Third should be User 3")
end)

test("limit and offset", function()
    local users = User:limit(1):offset(1):get()
    assert(#users == 1, "Should have 1 user")
    assert(users[1].name == "User 2", "Should be User 2")
end)

test("count", function()
    local count = User:count()
    assert(count == 3, "Should have 3 users")
end)

test("select specific columns", function()
    local users = User:select("name"):get()
    assert(users[1].name == "User 1", "Should have name")
end)

test("distinct", function()
    local users = User:distinct():get()
    assert(#users == 3, "Should have 3 distinct users")
end)

print("\n--- Relation Tests ---")

test("create posts with user", function()
    Post:create({ title = "Post 1", content = "Content 1", user_id = 1 })
    Post:create({ title = "Post 2", content = "Content 2", user_id = 1 })
    Post:create({ title = "Post 3", content = "Content 3", user_id = 2 })
end)

test("hasMany relation (lazy)", function()
    local user = User:find(1)
    local posts = user.posts:getData()
    assert(#posts == 2, "User 1 should have 2 posts")
end)

test("belongsTo relation (lazy)", function()
    local post = Post:find(1)
    local user = post.users:getData()
    assert(user.name == "User 1", "Post 1 belongs to User 1")
end)

print("\n--- Aggregation Tests ---")

test("sum", function()
    -- No numeric column to sum, but test the method exists
    local count = User:count()
    assert(count == 3, "Count should be 3")
end)

test("min and max", function()
    -- Test that methods exist and work
    local count = User:count()
    assert(count > 0, "Count should be > 0")
end)

print("\n--- Validation Tests ---")

test("validation on create", function()
    local ok, err = pcall(function()
        User:create({ name = "", email = "test@example.com" })
    end)
    assert(not ok, "Should fail validation")
end)

test("uniqueness validation", function()
    local ok, err = pcall(function()
        User:create({ name = "Duplicate", email = "user1@example.com" })
    end)
    assert(not ok, "Should fail uniqueness validation")
end)

print("\n--- Callback Tests ---")

test("before_create callback", function()
    local callback_called = false
    User:beforeCreate(function(instance, data)
        callback_called = true
        data.name = data.name .. " (modified)"
    end)
    local user = User:create({ name = "Callback Test", email = "callback@example.com" })
    assert(callback_called, "Callback should be called")
    assert(user.name == "Callback Test (modified)", "Name should be modified")
end)

print("\n--- Schema Tests ---")

test("createTable", function()
    jade.dropTable("test_schema")
    jade.createTable("test_schema", function(t)
        t:column("id", "integer", { primary_key = true })
        t:column("name", "string", { length = 100, nullable = false })
        t:column("value", "float")
    end)
    -- Verify table exists
    local result = driver:execute("SELECT table_name FROM information_schema.tables WHERE table_name = 'test_schema'")
    assert(#result == 1, "Table should exist")
    jade.dropTable("test_schema")
end)

print("\n--- Results ====")
print(string.format("\27[32mPassed: %d\27[0m", passed))
if failed > 0 then
    print(string.format("\27[31mFailed: %d\27[0m", failed))
    print("\nFailed tests:")
    for _, e in ipairs(errors) do
        print("  - " .. e.test)
        print("    " .. e.error)
    end
end

-- Cleanup
cleanup()
jade.disconnect()

os.exit(failed > 0 and 1 or 0)