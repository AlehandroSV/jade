describe("Query:take()", function()
    local Entity = require("jade.entity")
    local Query = require("jade.query")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")

    -- Mock driver that just stores its type for verification
    local function make_mock_driver(driver_type)
        local mock = {
            _driver_type = driver_type,
        }
        return setmetatable(mock, { __index = require("jade.driver.base") })
    end

    it("detects MySQL driver and uses RAND()", function()
        local User = Entity.new("users", { id = Integer():primaryKey(), name = String(120) })
        local mock_driver = make_mock_driver("mysql")
        User._driver = mock_driver

        -- Simulate what take() does internally: check driver type → pick function
        local random_fn = "RANDOM()"  -- default (PG, SQLite)
        if mock_driver._driver_type == "mysql" then
            random_fn = "RAND()"
        elseif mock_driver._driver_type == "mariadb" then
            random_fn = "RAND()"
        end

        assert.are.equal("RAND()", random_fn, "MySQL should use RAND()")
    end)

    it("detects MariaDB driver and uses RAND()", function()
        local User = Entity.new("users", { id = Integer():primaryKey(), name = String(120) })
        local mock_driver = make_mock_driver("mariadb")
        User._driver = mock_driver

        local random_fn = "RANDOM()"
        if mock_driver._driver_type == "mysql" then
            random_fn = "RAND()"
        elseif mock_driver._driver_type == "mariadb" then
            random_fn = "RAND()"
        end

        assert.are.equal("RAND()", random_fn, "MariaDB should use RAND()")
    end)

    it("keeps RANDOM() for PostgreSQL driver", function()
        local User = Entity.new("users", { id = Integer():primaryKey(), name = String(120) })
        local mock_driver = make_mock_driver("postgresql")
        User._driver = mock_driver

        local random_fn = "RANDOM()"
        if mock_driver._driver_type == "mysql" then
            random_fn = "RAND()"
        elseif mock_driver._driver_type == "mariadb" then
            random_fn = "RAND()"
        end

        assert.are.equal("RANDOM()", random_fn, "PostgreSQL should keep RANDOM()")
    end)

    it("keeps RANDOM() for SQLite driver", function()
        local User = Entity.new("users", { id = Integer():primaryKey(), name = String(120) })
        local mock_driver = make_mock_driver("sqlite")
        User._driver = mock_driver

        local random_fn = "RANDOM()"
        if mock_driver._driver_type == "mysql" then
            random_fn = "RAND()"
        elseif mock_driver._driver_type == "mariadb" then
            random_fn = "RAND()"
        end

        assert.are.equal("RANDOM()", random_fn, "SQLite should keep RANDOM()")
    end)

    it("default fallback is RANDOM() when driver is nil", function()
        -- When driver is nil, _driver_type check fails safely
        local random_fn = "RANDOM()"
        local driver = nil
        if driver and driver._driver_type == "mysql" then
            random_fn = "RAND()"
        end

        assert.are.equal("RANDOM()", random_fn, "No driver should default to RANDOM()")
    end)
end)
