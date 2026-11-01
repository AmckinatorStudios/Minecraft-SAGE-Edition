-- ---------------------------------------------------------------------------
-- crafting.lua — рецепты сеткой: игрок сам раскладывает материалы.
--
-- Рецепт — узор из строк («MMM», " S ", " S ") и ключи узора. Узор
-- сравнивается с ОБРЕЗАННОЙ раскладкой (пустые края сетки отбрасываются),
-- поэтому неважно, в каком углу сетки 3×3 лежит палка из двух досок; и в
-- зеркальном виде — тоже. Бесформенный рецепт (shapeless) смотрит только на
-- набор предметов.
--
-- size = 3 — только на верстаке; size = 2 — и в рюкзаке. Рецепты печи
-- (furnace = true) работают на верстаке, если рядом стоит печь.
-- ---------------------------------------------------------------------------
local B = require "blocks"

local R = {}

local list = {}

local function id(name) return B.byName[name].id end

local function shaped(out, n, rows, keys, opts)
    local r = {out = id(out), n = n, rows = rows, keys = {}, size = 2}
    for k, v in pairs(keys) do r.keys[k] = type(v) == "table" and v or {v} end
    local w = 0
    for _, row in ipairs(rows) do w = math.max(w, #row) end
    if #rows > 2 or w > 2 then r.size = 3 end
    if opts then for k, v in pairs(opts) do r[k] = v end end
    list[#list + 1] = r
end

local function shapeless(out, n, items, opts)
    local r = {out = id(out), n = n, items = items, size = #items > 4 and 3 or 2}
    if opts then for k, v in pairs(opts) do r[k] = v end end
    list[#list + 1] = r
end

local PLANKS = {"planks", "birch_planks"}

shapeless("planks", 4, {"log"})
shapeless("birch_planks", 4, {"birch_log"})
shaped("stick", 4, {"P", "P"}, {P = PLANKS})
shaped("crafting_table", 1, {"PP", "PP"}, {P = PLANKS})
shaped("torch", 4, {"C", "S"}, {C = "coal", S = "stick"})
shaped("furnace", 1, {"CCC", "C C", "CCC"}, {C = "cobblestone"})
shaped("sandstone", 1, {"ss", "ss"}, {s = "sand"})
shaped("stonebrick", 4, {"tt", "tt"}, {t = "stone"})
shaped("bookshelf", 1, {"PPP", "PPP", "PPP"}, {P = PLANKS})
shaped("glowstone", 1, {"TTT", "TGT", "TTT"}, {T = "torch", G = "gold_ingot"})
for _, m in ipairs({"coal", "iron_ingot", "gold_ingot", "diamond"}) do
    local block = ({coal = "coal_block", iron_ingot = "iron_block", gold_ingot = "gold_block", diamond = "diamond_block"})[m]
    shaped(block, 1, {"MMM", "MMM", "MMM"}, {M = m})
    shapeless(m, 9, {block})
end

-- Инструменты: материал головки по уровню.
local TIERS = {
    {prefix = "wood", mat = PLANKS},
    {prefix = "stone", mat = {"cobblestone"}},
    {prefix = "iron", mat = {"iron_ingot"}},
    {prefix = "diamond", mat = {"diamond"}},
}
for _, t in ipairs(TIERS) do
    shaped(t.prefix .. "_pickaxe", 1, {"MMM", " S ", " S "}, {M = t.mat, S = "stick"})
    shaped(t.prefix .. "_axe", 1, {"MM", "MS", " S"}, {M = t.mat, S = "stick"})
    shaped(t.prefix .. "_shovel", 1, {"M", "S", "S"}, {M = t.mat, S = "stick"})
    shaped(t.prefix .. "_sword", 1, {"M", "M", "S"}, {M = t.mat, S = "stick"})
end

-- Переплавка — у печи: руда (или песок, глина, булыжник) над углём.
for ore, out in pairs({iron_ore = "iron_ingot", gold_ore = "gold_ingot", sand = "glass",
                       cobblestone = "stone", clay = "brick"}) do
    shaped(out, 1, {"O", "C"}, {O = ore, C = "coal"}, {furnace = true})
end

-- Раскладка сетки -> обрезанная таблица строк имён (или nil — пусто).
local function trim(grid, size)
    local minR, maxR, minC, maxC = size, -1, size, -1
    for r = 0, size - 1 do
        for c = 0, size - 1 do
            if grid[r * size + c + 1] then
                minR, maxR = math.min(minR, r), math.max(maxR, r)
                minC, maxC = math.min(minC, c), math.max(maxC, c)
            end
        end
    end
    if maxR < 0 then return nil end
    local out = {}
    for r = minR, maxR do
        local row = {}
        for c = minC, maxC do
            local s = grid[r * size + c + 1]
            row[#row + 1] = s and B.byId[s.id].name or false
        end
        out[#out + 1] = row
    end
    return out
end

local function keyMatches(key, name)
    if key == nil then return name == false end
    if name == false then return false end
    for _, n in ipairs(key) do if n == name then return true end end
    return false
end

local function shapeMatches(r, cells, mirror)
    if #cells ~= #r.rows then return false end
    for i, row in ipairs(r.rows) do
        if #cells[i] ~= #row then return false end
        for j = 1, #row do
            local ch = row:sub(j, j)
            local name = cells[i][mirror and (#row - j + 1) or j]
            if ch == " " then
                if name then return false end
            elseif not keyMatches(r.keys[ch], name) then
                return false
            end
        end
    end
    return true
end

local function shapelessMatches(r, grid, size)
    local need = {}
    for _, n in ipairs(r.items) do need[n] = (need[n] or 0) + 1 end
    local count = 0
    for i = 1, size * size do
        local s = grid[i]
        if s then
            local n = B.byId[s.id].name
            if not need[n] or need[n] == 0 then return false end
            need[n] = need[n] - 1
            count = count + 1
        end
    end
    return count == #r.items
end

-- Что получится из раскладки. ctx = {size = 2|3, furnace = bool}.
function R.match(grid, ctx)
    local cells = trim(grid, ctx.size)
    if not cells then return nil end
    for _, r in ipairs(list) do
        if r.size <= ctx.size and (not r.furnace or ctx.furnace) then
            if r.rows then
                if shapeMatches(r, cells, false) or shapeMatches(r, cells, true) then return r end
            elseif shapelessMatches(r, grid, ctx.size) then
                return r
            end
        end
    end
    return nil
end

R.list = list

return R
