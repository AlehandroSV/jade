describe("Database", function()
    local Database = require("jade.database")

    before_each(function()
        Database.clear()
    end)

    ----------------------------------------------------------------
    -- Registration
    ----------------------------------------------------------------

    describe("register", function()
        it("registers a named connection", function()
            Database.register("primary", { driver = "postgresql", host = "localhost" })
            local config = Database.getConfig("primary")
            assert.are.equal("postgresql", config.driver)
            assert.are.equal("localhost", config.host)
        end)

        it("overwrites existing registration", function()
            Database.register("primary", { driver = "postgresql" })
            Database.register("primary", { driver = "mysql" })
            local config = Database.getConfig("primary")
            assert.are.equal("mysql", config.driver)
        end)
    end)

    ----------------------------------------------------------------
    -- Configuration
    ----------------------------------------------------------------

    describe("configure", function()
        it("registers multiple databases at once", function()
            Database.configure({
                primary = { driver = "postgresql", host = "localhost" },
                analytics = { driver = "mysql", host = "localhost" },
            })
            local names = Database.getNames()
            assert.are.equal(2, #names)
            assert.is_true(names[1] == "analytics" or names[2] == "analytics")
            assert.is_true(names[1] == "primary" or names[2] == "primary")
        end)

        it("sets first connection as default when no default exists", function()
            Database.configure({
                primary = { driver = "postgresql" },
                secondary = { driver = "mysql" },
            })
            local default = Database.getDefault()
            assert.is_not_nil(default)
            assert.is_true(default == "primary" or default == "secondary")
        end)

        it("does not overwrite existing default", function()
            Database.register("first", { driver = "postgresql" })
            Database.setDefault("first")
            Database.configure({
                second = { driver = "mysql" },
            })
            assert.are.equal("first", Database.getDefault())
        end)
    end)

    ----------------------------------------------------------------
    -- Default connection
    ----------------------------------------------------------------

    describe("setDefault / getDefault", function()
        it("sets and gets default connection", function()
            Database.setDefault("primary")
            assert.are.equal("primary", Database.getDefault())
        end)

        it("returns nil when no default set", function()
            assert.is_nil(Database.getDefault())
        end)
    end)

    ----------------------------------------------------------------
    -- Connection management
    ----------------------------------------------------------------

    describe("getNames", function()
        it("returns sorted list of connection names", function()
            Database.register("zebra", { driver = "postgresql" })
            Database.register("alpha", { driver = "mysql" })
            Database.register("middle", { driver = "sqlite" })
            local names = Database.getNames()
            assert.are.equal(3, #names)
            assert.are.equal("alpha", names[1])
            assert.are.equal("middle", names[2])
            assert.are.equal("zebra", names[3])
        end)

        it("returns empty list when no connections", function()
            local names = Database.getNames()
            assert.are.equal(0, #names)
        end)
    end)

    describe("getConfig", function()
        it("returns config for registered connection", function()
            Database.register("primary", { driver = "postgresql", host = "localhost" })
            local config = Database.getConfig("primary")
            assert.are.equal("postgresql", config.driver)
        end)

        it("returns nil for unregistered connection", function()
            assert.is_nil(Database.getConfig("nonexistent"))
        end)
    end)

    describe("remove", function()
        it("removes a connection", function()
            Database.register("primary", { driver = "postgresql" })
            Database.remove("primary")
            assert.is_nil(Database.getConfig("primary"))
        end)

        it("does not error when removing nonexistent connection", function()
            Database.remove("nonexistent")
        end)
    end)

    ----------------------------------------------------------------
    -- Connect
    ----------------------------------------------------------------

    describe("connect", function()
        it("errors when connection not registered", function()
            assert.has_error(function()
                Database.connect("nonexistent")
            end, "Database 'nonexistent' not registered. Use jade.database.register() first.")
        end)

        -- Note: Actual connection tests require real drivers
        -- These would be integration tests
    end)

    ----------------------------------------------------------------
    -- Read replicas
    ----------------------------------------------------------------

    describe("addReplicas / getReplica", function()
        it("registers read replicas for primary", function()
            Database.register("primary", { driver = "postgresql" })
            Database.addReplicas("primary", {
                { driver = "postgresql", host = "replica1" },
                { driver = "postgresql", host = "replica2" },
            })
            local replicas = Database.getReplicas("primary")
            assert.are.equal(2, #replicas)
        end)

        it("returns empty list when no replicas", function()
            local replicas = Database.getReplicas("primary")
            assert.are.equal(0, #replicas)
        end)

        -- Note: getReplica round-robin tests require real drivers
    end)

    ----------------------------------------------------------------
    -- Transaction helper
    ----------------------------------------------------------------

    describe("transaction", function()
        -- Note: Actual transaction tests require real drivers
        -- These would be integration tests
        it("exists as a function", function()
            assert.is_function(Database.transaction)
        end)
    end)

    ----------------------------------------------------------------
    -- Execute helper
    ----------------------------------------------------------------

    describe("execute", function()
        -- Note: Actual execute tests require real drivers
        -- These would be integration tests
        it("exists as a function", function()
            assert.is_function(Database.execute)
        end)
    end)

    ----------------------------------------------------------------
    -- Health check
    ----------------------------------------------------------------

    describe("healthCheck", function()
        -- Note: Actual health check tests require real drivers
        -- These would be integration tests
        it("exists as a function", function()
            assert.is_function(Database.healthCheck)
        end)
    end)

    ----------------------------------------------------------------
    -- State management
    ----------------------------------------------------------------

    describe("clear", function()
        it("clears all connections and default", function()
            Database.register("primary", { driver = "postgresql" })
            Database.setDefault("primary")
            Database.clear()
            assert.is_nil(Database.getConfig("primary"))
            assert.is_nil(Database.getDefault())
            assert.are.equal(0, #Database.getNames())
        end)
    end)
end)
