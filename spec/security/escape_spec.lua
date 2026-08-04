describe("Security - Escape Functions", function()
    local sanitizer = require("jade.security.sanitizer")

    it("escapes single quotes", function()
        local result = sanitizer.escapeString("O'Brien")
        assert.are.equal("'O''Brien'", result)
    end)

    it("escapes strings with SQL injection patterns", function()
        -- escapeString no longer throws on SQL injection patterns
        -- Values should be protected via prepared statements, not regex detection
        local result = sanitizer.escapeString("' OR '1'='1")
        assert.are.equal("'' OR ''1''=''1'", result)
    end)

    it("returns NULL for nil", function()
        local result = sanitizer.escapeString(nil)
        assert.are.equal("NULL", result)
    end)

    it("validates types correctly", function()
        assert.is_true(sanitizer.validateType("hello", "string"))
        assert.is_true(sanitizer.validateType(123, "integer"))
        assert.is_true(sanitizer.validateType(true, "boolean"))
        assert.is_true(sanitizer.validateType(nil, "string")) -- nil is valid
    end)

    it("rejects wrong types", function()
        assert.is_false(sanitizer.validateType(123, "string"))
        assert.is_false(sanitizer.validateType("hello", "integer"))
    end)

    it("sanitizes strings", function()
        local result = sanitizer.sanitizeString("  hello  ")
        assert.are.equal("hello", result)
    end)

    it("removes null bytes", function()
        local result = sanitizer.sanitizeString("hello\0world")
        assert.are.equal("helloworld", result)
    end)
end)
