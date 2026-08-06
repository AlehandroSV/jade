-- Tests for raw SQL condition validation in Query:where()
-- Addresses issue #86: raw() only blocked UNION SELECT, allowed destructive DDL/DML

local Jade = require("jade")
describe("Query:where() — raw SQL validation", function()
    local User = Jade.Entity("users", {
        id = Jade.Integer():primaryKey(),
        name = Jade.String(120),
        email = Jade.String(255),
    })

    -- Valid raw conditions should pass without error
    it("allows simple equality raw conditions", function()
        local q = User:where(Jade.raw("1=1"))
        assert.is_true(q ~= nil)
    end)

    it("allows raw conditions with bindings", function()
        local q = User:where(Jade.raw("age > ?", 18))
        assert.is_true(q ~= nil)
    end)

    it("allows raw conditions with multiple bindings", function()
        local q = User:where(Jade.raw("age > ? OR active = ?", 18, true))
        assert.is_true(q ~= nil)
    end)

    it("allows raw subquery EXISTS (not UNION)", function()
        local q = User:where(Jade.raw("1=1 OR EXISTS(SELECT 1 FROM admins WHERE password IS NOT NULL)"))
        assert.is_true(q ~= nil)
    end)

    it("allows raw LIKE conditions", function()
        local q = User:where(Jade.raw("name LIKE ?", "%admin%"))
        assert.is_true(q ~= nil)
    end)

    it("allows raw IN conditions", function()
        local q = User:where(Jade.raw("id IN (?, ?, ?)", 1, 2, 3))
        assert.is_true(q ~= nil)
    end)

    it("allows raw column names that look like SQL keywords", function()
        -- Column named 'update_count', 'delete_flag', etc. are valid identifiers
        local q = User:where(Jade.raw("update_count > 0"))
        assert.is_true(q ~= nil)
    end)

    -- Dangerous patterns must be blocked
    it("blocks DROP TABLE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; DROP TABLE users"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "DROP", 1, true) ~= nil)
    end)

    it("blocks DELETE FROM injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; DELETE FROM users"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "DELETE", 1, true) ~= nil)
    end)

    it("blocks UPDATE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; UPDATE users SET role='admin'"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "UPDATE", 1, true) ~= nil)
    end)

    it("blocks ALTER TABLE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; ALTER TABLE users ADD COLUMN rogue TEXT"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "ALTER", 1, true) ~= nil)
    end)

    it("blocks TRUNCATE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; TRUNCATE users"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "TRUNCATE", 1, true) ~= nil)
    end)

    it("blocks INSERT INTO injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; INSERT INTO users VALUES ('hacker','evil')"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "INSERT", 1, true) ~= nil)
    end)

    it("blocks CREATE TABLE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; CREATE TABLE backdoor (data TEXT)"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "CREATE", 1, true) ~= nil)
    end)

    it("blocks GRANT injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; GRANT ALL ON *.* TO 'hacker'@'%'"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "GRANT", 1, true) ~= nil)
    end)

    it("blocks EXECUTE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; EXECUTE xp_cmdshell('dir')"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "EXECUTE", 1, true) ~= nil)
    end)

    it("blocks REVOKE injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; REVOKE ALL FROM 'user'"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "REVOKE", 1, true) ~= nil)
    end)

    -- Case insensitivity
    it("blocks case-insensitive DROP pattern", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; drop table users"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "DROP", 1, true) ~= nil)
    end)

    it("blocks case-insensitive DELETE pattern", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("1=1; Delete From users"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "DELETE", 1, true) ~= nil)
    end)

    -- Backward compatibility: still blocks UNION SELECT
    it("still blocks UNION SELECT injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("SELECT * FROM users WHERE name='admin' UNION SELECT * FROM secrets"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "UNION", 1, true) ~= nil)
    end)

    it("still blocks UNION ALL SELECT injection", function()
        local ok, err = pcall(function()
            User:where(Jade.raw("SELECT 1 UNION ALL SELECT password FROM admins"))
        end)
        assert.is_false(ok)
        assert.is_true(string.find(err or "", "UNION", 1, true) ~= nil)
    end)
end)
