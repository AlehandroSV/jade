-- Tests for Jade.loadModels security + Lua 5.1 iteration (#180)

local Jade = require("jade")

local TMP_ROOT = "spec_tmp_load_models_180"

local function rm_rf(path)
    local ok_lfs, lfs = pcall(require, "lfs")
    if not ok_lfs then
        os.remove(path)
        return
    end
    local attr = lfs.attributes(path)
    if not attr then return end
    if attr.mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                rm_rf(path .. "/" .. entry)
            end
        end
        lfs.rmdir(path)
    else
        os.remove(path)
    end
end

local function mkdir_p(path)
    local ok_lfs, lfs = pcall(require, "lfs")
    if ok_lfs then
        lfs.mkdir(path)
        return
    end
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '"')
    end
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then
        error("failed to write " .. path .. ": " .. tostring(err))
    end
    f:write(content)
    f:close()
end

local function model_file(table_name)
    return string.format([[
local Jade = require("jade")
return Jade.Entity("%s", {})
]], table_name)
end

local function setup_fixtures()
    rm_rf(TMP_ROOT)
    mkdir_p(TMP_ROOT)
    write_file(TMP_ROOT .. "/User.lua", model_file("users"))
    write_file(TMP_ROOT .. "/Post.lua", model_file("posts"))
    write_file(TMP_ROOT .. "/not_a_model.txt", "ignored")
    write_file(TMP_ROOT .. "/bad name.lua", model_file("bad"))
end

local function teardown_fixtures()
    rm_rf(TMP_ROOT)
    os.remove("spec_tmp_pwned_180.txt")
    os.remove("spec_tmp_pwned_180_win.txt")
end

describe("Jade.loadModels", function()
    local context = require("jade.util.context")

    before_each(function()
        context.set("driver", nil)
        teardown_fixtures()
        setup_fixtures()
    end)

    describe("directory listing without shell injection (#180)", function()
        it("does not execute shell metacharacters in dir", function()
            local canary = "spec_tmp_pwned_180.txt"
            os.remove(canary)

            local ok, models = pcall(Jade.loadModels, '"; echo pwned > ' .. canary .. '; echo "')
            assert.is_true(ok, "loadModels must not raise on malicious dir")
            assert.is_not_nil(models)
            assert.is_nil(io.open(canary, "r"), "shell must not run from dir interpolation")
        end)

        it("does not execute cmd metacharacters on Windows-style dir", function()
            local canary = "spec_tmp_pwned_180_win.txt"
            os.remove(canary)

            local ok, models = pcall(Jade.loadModels, 'jade\\generated& echo pwned>' .. canary)
            assert.is_true(ok)
            assert.is_not_nil(models)
            assert.is_nil(io.open(canary, "r"))
        end)

        it("prefers lfs over io.popen for listing", function()
            local file = io.open("src/jade/init.lua", "r")
            assert.is_truthy(file)
            local content = file:read("*a")
            file:close()

            assert.is_truthy(content:find('pcall(require, "lfs")', 1, true), "loadModels should prefer lfs")
            -- Old combined unsanitized shell must be gone
            assert.is_nil(content:find([[ls "' .. dir .. '" 2>/dev/null || dir /b]], 1, true),
                "old combined unsanitized io.popen pattern must be removed")
        end)

        it("rejects unsafe characters before any shell fallback", function()
            local file = io.open("src/jade/init.lua", "r")
            assert.is_truthy(file)
            local content = file:read("*a")
            file:close()

            local gate = content:find("isSafeShellPath", 1, true)
            assert.is_truthy(gate, "isSafeShellPath gate should exist")
            local popen = content:find("io.popen", 1, true)
            assert.is_truthy(popen, "shell fallback may still exist for missing lfs")
            assert.is_true(gate < popen, "isSafeShellPath must be defined/used before io.popen")
            -- Runtime: unsafe path must not reach shell
            local models = Jade.loadModels('"; id; echo "')
            assert.is_not_nil(models)
            assert.are.equal(0, #models:modelNames())
        end)
    end)

    describe("listing models", function()
        it("loads valid model files on demand", function()
            local models = Jade.loadModels(TMP_ROOT)
            local User = models.User
            assert.is_not_nil(User)
            assert.are.equal("users", User._table)
            assert.are.equal("posts", models.Post._table)
        end)

        it("ignores non-lua files and unsafe model filenames", function()
            local models = Jade.loadModels(TMP_ROOT)
            assert.is_nil(models.not_a_model)
            assert.is_nil(models["bad name"])
        end)

        it("returns empty proxy for missing directory", function()
            local models = Jade.loadModels(TMP_ROOT .. "/does_not_exist")
            assert.is_not_nil(models)
            assert.are.equal(0, #models:modelNames())
        end)
    end)

    describe("Lua 5.1-compatible iteration (#180)", function()
        it("exposes modelNames() as a sorted list", function()
            local models = Jade.loadModels(TMP_ROOT)
            local names = models:modelNames()
            assert.are.equal(2, #names)
            assert.are.equal("Post", names[1])
            assert.are.equal("User", names[2])
        end)

        it("iterates loaded models via :each()", function()
            local models = Jade.loadModels(TMP_ROOT)
            local seen = {}
            local count = 0
            for name, model in models:each() do
                seen[name] = model
                count = count + 1
            end
            assert.are.equal(2, count)
            assert.is_not_nil(seen.User)
            assert.is_not_nil(seen.Post)
            assert.are.equal("users", seen.User._table)
            assert.are.equal("posts", seen.Post._table)
        end)

        it("does not rely on __pairs for iteration API", function()
            local file = io.open("src/jade/init.lua", "r")
            assert.is_truthy(file)
            local content = file:read("*a")
            file:close()

            -- Explicit methods must exist; __pairs may remain as 5.2+ nicety
            assert.is_truthy(content:find("function proxy:modelNames", 1, true)
                or content:find("modelNames = function", 1, true)
                or content:find(":modelNames", 1, true))
            assert.is_truthy(content:find(":each", 1, true) or content:find("each = function", 1, true))
        end)

        it("caches models across access and clears on reload", function()
            local models = Jade.loadModels(TMP_ROOT)
            local a = models.User
            local b = models.User
            assert.are.equal(tostring(a), tostring(b))

            models:reload("User")
            local c = models.User
            assert.is_not_nil(c)
            assert.are.equal("users", c._table)
        end)
    end)
end)

teardown_fixtures()
