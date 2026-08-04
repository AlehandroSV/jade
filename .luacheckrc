-- Luacheck configuration for Jade ORM
-- https://luacheck.readthedocs.io/

std = "min"

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
    "212",   -- unused argument (common in callbacks)
    "213",   -- unused loop variable
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
