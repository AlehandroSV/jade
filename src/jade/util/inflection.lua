local M = {}

function M.snake_to_camel(str)
    return str:gsub("_(%w)", function(c)
        return c:upper()
    end)
end

function M.camel_to_snake(str)
    return str:gsub("(%u)", function(c)
        return "_" .. c:lower()
    end):gsub("^_", "")
end

-- Common irregular plurals
local irregulars = {
    person = "people",
    man = "men",
    woman = "women",
    child = "children",
    mouse = "mice",
    goose = "geese",
    ox = "oxen",
    tooth = "teeth",
    foot = "feet",
    datum = "data",
    medium = "media",
    criterion = "criteria",
    phenomenon = "phenomena",
    index = "indices",
    matrix = "matrices",
    vertex = "vertices",
    axis = "axes",
}

-- Words that don't change
local uncountable = {
    sheep = true, deer = true, fish = true, moose = true,
    aircraft = true, spacecraft = true,
    data = true, metadata = true,
    info = true, information = true,
    equipment = true, furniture = true,
}

function M.pluralize(str)
    local lower = str:lower()

    -- Check uncountable
    if uncountable[lower] then
        return str
    end

    -- Check irregular
    if irregulars[lower] then
        local result = irregulars[lower]
        -- Preserve case of original
        if str:sub(1, 1) == str:sub(1, 1):upper() then
            return result:sub(1, 1):upper() .. result:sub(2)
        end
        return result
    end

    -- Words ending in 'us' (but not 'us' itself) -> 'i' (cactus->cacti, but bus->buses)
    if lower:match("us$") and #lower > 2 and not lower:match("us$") then
        -- Most -us words -> -i (Latin plurals), but common words -> -es
        if lower:match("bus$") or lower:match("plus$") or lower:match("virus$") then
            return str .. "es"
        end
        return str:sub(1, -3) .. "i"
    end

    -- Words ending in 'is' -> 'es' (analysis->analyses, crisis->crises)
    if lower:match("is$") then
        return str:sub(1, -3) .. "es"
    end

    -- Words ending in 'on' -> 'a' (criterion->criteria, phenomenon->phenomena)
    if lower:match("on$") and #lower > 2 then
        return str:sub(1, -3) .. "a"
    end

    -- Words ending in 'um' -> 'a' (datum->data, medium->media)
    if lower:match("um$") and #lower > 2 then
        return str:sub(1, -3) .. "a"
    end

    -- Words ending in 'x' -> 'ices' (index->indices, matrix->matrices)
    if lower:match("x$") and #lower > 2 then
        return str:sub(1, -2) .. "ices"
    end

    -- Words ending in 'y' preceded by consonant -> 'ies'
    if lower:match("[^aeiou]y$") then
        return str:sub(1, -2) .. "ies"
    end

    -- Words ending in 's', 'x', 'z', 'sh', 'ch' -> 'es'
    if lower:match("[sxz]$") or lower:match("sh$") or lower:match("ch$") then
        return str .. "es"
    end

    -- Default: add 's'
    return str .. "s"
end

function M.singularize(str)
    local lower = str:lower()

    -- Check irregular (reverse lookup)
    for singular, plural in pairs(irregulars) do
        if lower == plural then
            local result = singular
            if str:sub(1, 1) == str:sub(1, 1):upper() then
                return result:sub(1, 1):upper() .. result:sub(2)
            end
            return result
        end
    end

    -- Check uncountable
    if uncountable[lower] then
        return str
    end

    -- 'ies' -> 'y'
    if lower:match("ies$") then
        return str:sub(1, -4) .. "y"
    end

    -- 'ices' -> 'x'
    if lower:match("ices$") then
        return str:sub(1, -5) .. "x"
    end

    -- 'a' ending (from 'on' plurals) -> 'on'
    if lower:match("a$") and #lower > 2 and not lower:match("ma$") then
        return str:sub(1, -2) .. "on"
    end

    -- 'es' ending
    if lower:match("es$") then
        -- 'ses'/'xes'/'zes'/'shes'/'ches' -> remove 'es'
        if lower:match("[sxz]es$") or lower:match("shes$") or lower:match("ches$") then
            return str:sub(1, -3)
        end
        -- 'ies' -> already handled above
        -- 'ves' -> 'f' or 'fe'
        if lower:match("ves$") then
            return str:sub(1, -4) .. "f"
        end
        -- Other 'es' -> remove 's'
        return str:sub(1, -2)
    end

    -- 's' ending (not 'ss')
    if lower:match("s$") and not lower:match("ss$") then
        return str:sub(1, -2)
    end

    return str
end

return M
