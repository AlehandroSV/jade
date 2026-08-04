-- Luacheck configuration for Jade ORM
-- https://luacheck.readthedocs.io/

std = "lua54"

-- Global objects defined by the project
globals = {
    "jade",
}

-- Read-only globals
read_globals = {
    "vim",  -- Neovim integration
}

-- Ignore specific warnings
ignore = {
    "211",   -- unused local variable
    "212",   -- unused argument (common in callbacks)
    "213",   -- unused loop variable
    "214",   -- used variable with unused hint
    "311",   -- value of local variable is unused
    "411",   -- variable was previously defined
    "412",   -- variable was previously defined as argument
    "421",   -- shadowing definition of variable
    "422",   -- shadowing definition of argument
    "431",   -- shadowing upvalue
}

-- Files to check
include_files = {
    "src/",
    "spec/",
}

-- Exclude files
exclude_files = {
    "src/jade/_VERSION.lua",  -- Auto-generated
}

-- Per-file overrides
files["src/jade/init.lua"] = {
    ignore = {
        "111",  -- setting non-standard global variable
    }
}

files["spec/**/*.lua"] = {
    globals = {
        "describe",
        "it",
        "before_each",
        "after_each",
        "pending",
        "assert",
    }
}
