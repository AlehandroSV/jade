describe("Security - Validator", function()
    local validator = require("jade.security.validator")

    local function capture(fn)
        local ok, err = pcall(fn)
        return ok, err
    end

    it("validates column names", function()
        assert.is_true(validator.validateColumnName("users"))
        assert.is_true(validator.validateColumnName("user_name"))
        assert.is_true(validator.validateColumnName("_id"))
    end)

    it("rejects invalid column names with J5001", function()
        local ok, err = capture(function() validator.validateColumnName("user-name") end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5001", err.code)
        assert.is_truthy(tostring(err))

        ok, err = capture(function() validator.validateColumnName("user name") end)
        assert.is_false(ok)
        assert.are.equal("J5001", err.code)

        ok, err = capture(function() validator.validateColumnName("123users") end)
        assert.is_false(ok)
        assert.are.equal("J5001", err.code)
    end)

    it("validates table names", function()
        assert.is_true(validator.validateTableName("users"))
        assert.is_true(validator.validateTableName("user_posts"))
    end)

    it("rejects invalid table names with J5001", function()
        local ok, err = capture(function() validator.validateTableName("user-table") end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5001", err.code)

        ok, err = capture(function() validator.validateTableName("123table") end)
        assert.is_false(ok)
        assert.are.equal("J5001", err.code)
    end)

    it("validates order direction", function()
        assert.is_true(validator.validateOrderDirection("ASC"))
        assert.is_true(validator.validateOrderDirection("DESC"))
        assert.is_true(validator.validateOrderDirection("asc"))
        assert.is_true(validator.validateOrderDirection("desc"))
    end)

    it("rejects invalid order direction with J5004", function()
        local ok, err = capture(function() validator.validateOrderDirection("UP") end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5004", err.code)

        ok, err = capture(function() validator.validateOrderDirection("DOWN") end)
        assert.is_false(ok)
        assert.are.equal("J5004", err.code)
    end)

    it("validates pagination", function()
        assert.is_true(validator.validatePagination(1, 20))
        assert.is_true(validator.validatePagination(5, 100))
    end)

    it("rejects invalid pagination with J5004", function()
        local ok, err = capture(function() validator.validatePagination(0, 20) end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5004", err.code)

        ok, err = capture(function() validator.validatePagination(-1, 20) end)
        assert.is_false(ok)
        assert.are.equal("J5004", err.code)

        ok, err = capture(function() validator.validatePagination(1, 0) end)
        assert.is_false(ok)
        assert.are.equal("J5004", err.code)

        ok, err = capture(function() validator.validatePagination(1, 2000) end)
        assert.is_false(ok)
        assert.are.equal("J5004", err.code)
    end)

    it("validates query length", function()
        assert.is_true(validator.validateQueryLength("SELECT * FROM users"))
    end)

    it("rejects long queries with J5002", function()
        local long_query = string.rep("a", 200000)
        local ok, err = capture(function() validator.validateQueryLength(long_query) end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5002", err.code)
    end)

    it("validates parameter count", function()
        assert.is_true(validator.validateParameterCount({1, 2, 3}))
    end)

    it("rejects too many parameters with J5003", function()
        local many_params = {}
        for i = 1, 2000 do
            many_params[i] = i
        end
        local ok, err = capture(function() validator.validateParameterCount(many_params) end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5003", err.code)
    end)

    it("rejects SELECT injection patterns with J5000", function()
        local ok, err = capture(function() validator.validateSelectItem("id; DROP TABLE users") end)
        assert.is_false(ok)
        assert.are.equal("table", type(err))
        assert.are.equal("J5000", err.code)
    end)
end)
