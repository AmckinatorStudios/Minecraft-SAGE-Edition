-- ---------------------------------------------------------------------------
-- plants.lua — листва, саженцы и мелкие растения по правилам Minecraft 1.7.10.
--
-- ЛИСТВА (BlockLeaves). Сломали бревно — листва в кубе ±4 вокруг помечается
-- «проверить» (бит 8 метаданных оригинала), сломали листву — в кубе ±1.
-- Помеченная листва при случайном тике (3 клетки на секцию 16³ за тик —
-- шанс 3/4096 у каждой) ищет бревно: волна от брёвен по шести
-- направлениям через листву, не дальше 4 шагов. Не нашла — опадает
-- (выпадение как при поломке), нашла — пометка снимается. Поставленная
-- игроком листва (бит 4) не опадает никогда. Природная, пока её не тронули,
-- не проверяется вовсе — поэтому крона опадает постепенно, а не разом.
--
-- ВЫПАДЕНИЕ (dropBlockAsItemWithChance): саженец своей породы — 1/20,
-- у тропической листвы — 1/40; яблоко — 1/200 у дуба (и у тёмного дуба —
-- BlockNewLeaf). Ножницы — сам блок листвы. Трава — семена 1/8, ножницами —
-- трава; цветы и саженцы — сами. Палок нет (их добавили позже).
--
-- САЖЕНЦЫ (BlockSapling). Случайный тик: при свете ≥ 9 над саженцем и 1/7 —
-- стадия; на второй стадии — дерево (trees.lua). Ель, тропическое и тёмный
-- дуб из квадрата 2×2 — большое дерево; тёмный дуб одиночкой не растёт.
-- Не хватило места — саженцы остаются. Костная мука — 45% на стадию,
-- тратится всегда, зелёные искры (happyVillager).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local P = {}

local check, placed, saplings, stage = {}, {}, {}, {}
P.stats = {decayed = 0, grown = 0}

local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function unkey(k)
    local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
    return tonumber(x), tonumber(y), tonumber(z)
end
local function id(name) return B.byName[name].id end

local function act() return require "interact" end
local function rnd(n) return math.random(0, n - 1) end

-- --- Выпадение ---------------------------------------------------------------

local SAPLING_OF = {leaves = "oak_sapling", birch_leaves = "birch_sapling", spruce_leaves = "spruce_sapling",
                    jungle_leaves = "jungle_sapling", acacia_leaves = "acacia_sapling",
                    dark_oak_leaves = "dark_oak_sapling"}

-- Что выпадает из растения или листвы при поломке (shears — в руке ножницы).
-- nil — блок не из этих (обычные правила blocks.lua).
function P.dropsOf(blockId, shears)
    local d = B.byId[blockId]
    if not d then return nil end
    if B.isLeaves[blockId] then
        if shears then return {{blockId, 1}} end
        local out = {}
        local chance = d.name == "jungle_leaves" and 40 or 20
        if rnd(chance) == 0 then out[#out + 1] = {id(SAPLING_OF[d.name]), 1} end
        if (d.name == "leaves" or d.name == "dark_oak_leaves") and rnd(200) == 0 then
            out[#out + 1] = {id("apple"), 1}
        end
        return out
    end
    if d.name == "tallgrass" then
        if shears then return {{blockId, 1}} end
        if rnd(8) == 0 then return {{id("wheat_seeds"), 1}} end
        return {}
    end
    return nil
end

local function spill(list, x, y, z)
    local Drops = require "drops"
    for _, it in ipairs(list) do Drops.spawn(it[1], it[2], x + 0.5, y + 0.5, z + 0.5) end
end
P.spill = spill

-- --- Пометки листвы -----------------------------------------------------------

local function mark(x, y, z, r)
    for dx = -r, r do
        for dy = -r, r do
            for dz = -r, r do
                if B.isLeaves[W.get(x + dx, y + dy, z + dz)] then check[key(x + dx, y + dy, z + dz)] = true end
            end
        end
    end
end

-- Блок сломан (до или после — неважно: смотрим на соседей).
function P.onBreak(blockId, x, y, z)
    local k = key(x, y, z)
    if B.isLog[blockId] then mark(x, y, z, 4)
    elseif B.isLeaves[blockId] then
        check[k], placed[k] = nil, nil
        mark(x, y, z, 1)
    elseif B.isSapling[blockId] then
        saplings[k], stage[k] = nil, nil
    end
end

-- Блок поставлен игроком.
function P.onPlace(blockId, x, y, z)
    local k = key(x, y, z)
    if B.isLeaves[blockId] then placed[k] = true; check[k] = nil
    elseif B.isSapling[blockId] then saplings[k] = true; stage[k] = nil end
end

-- На чём растут трава, цветы и саженцы (BlockBush.canPlaceBlockOn).
function P.soil(blockId) return blockId == id("grass") or blockId == id("dirt") end

-- Свет клетки с учётом времени суток (World.getBlockLightValue).
local function lightAt(x, y, z)
    local Sky = require "sky"
    local sub = Sky.skylightSubtracted(Sky.angle or 0, Sky.rain or 0, Sky.thunder or 0)
    return math.max((W.sky(x, y, z) or 15) - sub, W.blockLight(x, y, z) or 0)
end

-- Листва без опоры опадает (removeLeaves).
local function removeLeaves(x, y, z)
    local b = W.get(x, y, z)
    act().setBlock(x, y, z, 0)
    P.onBreak(b, x, y, z)
    spill(P.dropsOf(b, false) or {}, x, y, z)
    P.stats.decayed = P.stats.decayed + 1
end

-- BlockLeaves.updateTick: волна от брёвен на 4 шага по листве.
local dist = {}
function P.decayTick(x, y, z)
    local k = key(x, y, z)
    if placed[k] or not B.isLeaves[W.get(x, y, z)] then check[k] = nil; return end
    local R, S = 4, 9
    local function idx(a, b, c) return (a + R) * S * S + (b + R) * S + (c + R) end
    for a = -R, R do
        for b = -R, R do
            for c = -R, R do
                local blk = W.get(x + a, y + b, z + c)
                dist[idx(a, b, c)] = B.isLog[blk] and 0 or (B.isLeaves[blk] and -2 or -1)
            end
        end
    end
    for step = 1, 4 do
        for a = -R, R do
            for b = -R, R do
                for c = -R, R do
                    if dist[idx(a, b, c)] == step - 1 then
                        for _, n in ipairs({{-1, 0, 0}, {1, 0, 0}, {0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}}) do
                            local na, nb, nc = a + n[1], b + n[2], c + n[3]
                            if na >= -R and na <= R and nb >= -R and nb <= R and nc >= -R and nc <= R
                                and dist[idx(na, nb, nc)] == -2 then
                                dist[idx(na, nb, nc)] = step
                            end
                        end
                    end
                end
            end
        end
    end
    if dist[idx(0, 0, 0)] >= 0 then check[k] = nil else removeLeaves(x, y, z) end
end

-- --- Саженцы -------------------------------------------------------------------

local function growTree(x, y, z)
    local sid = W.get(x, y, z)
    local kind = B.sapling[sid]
    if not kind then return false end
    local O = require "ores"
    local rand = O.Random(math.random(0, 0x7FFFFFFF))
    -- Квадрат 2×2 одинаковых саженцев (func_149880_a) — для ели,
    -- тропического и тёмного дуба.
    local ox, oz, two = 0, 0, false
    if kind == "spruce" or kind == "jungle" or kind == "dark_oak" then
        for i1 = 0, -1, -1 do
            for j1 = 0, -1, -1 do
                if not two and W.get(x + i1, y, z + j1) == sid and W.get(x + i1 + 1, y, z + j1) == sid
                    and W.get(x + i1, y, z + j1 + 1) == sid and W.get(x + i1 + 1, y, z + j1 + 1) == sid then
                    ox, oz, two = i1, j1, true
                end
            end
        end
        if kind == "dark_oak" and not two then return false end
    end
    local cells = two and {{0, 0}, {1, 0}, {0, 1}, {1, 1}} or {{0, 0}}
    local before = {}
    for _, c in ipairs(cells) do
        local cx, cz = x + ox + c[1], z + oz + c[2]
        before[#before + 1] = {cx, cz, stage[key(cx, y, cz)]}
        W.setId(cx, y, cz, 0)   -- место под ствол — без пересборки: её сделает setBlock
    end
    local placedNow = {}
    local function set(a, b, c, v)
        act().setBlock(a, b, c, v)
        local k = key(a, b, c)
        placed[k], check[k] = nil, nil
        placedNow[#placedNow + 1] = k
    end
    local ok = require("trees").grow(kind, rand, x + ox, y, z + oz, two, W.get, set)
    if not ok then
        -- Не выросло — саженцы на место, со своей стадией.
        for _, c in ipairs(before) do
            W.setId(c[1], y, c[2], sid)
            stage[key(c[1], y, c[2])] = c[3]
        end
        return false
    end
    for _, c in ipairs(before) do
        local k = key(c[1], y, c[2])
        -- Клетка саженца, которую дерево не заняло: убрать и с экрана
        -- (setBlock не пересобирает меш, если номер блока не изменился).
        if W.get(c[1], y, c[2]) == 0 then
            W.setId(c[1], y, c[2], sid)
            act().setBlock(c[1], y, c[2], 0)
        end
        saplings[k], stage[k] = nil, nil
    end
    P.stats.grown = P.stats.grown + 1
    return true
end
P.growTree = growTree

-- func_149879_c: первая стадия — пометка, вторая — дерево.
local function advance(x, y, z)
    local k = key(x, y, z)
    if not stage[k] then stage[k] = true; return end
    growTree(x, y, z)
end
P.advance = advance

-- BlockSapling.updateTick.
function P.saplingTick(x, y, z)
    local k = key(x, y, z)
    local sid = W.get(x, y, z)
    if not B.isSapling[sid] then saplings[k], stage[k] = nil, nil; return end
    -- canBlockStay: почва под ним и свет ≥ 8 (или открытое небо).
    if not P.soil(W.get(x, y - 1, z)) or (lightAt(x, y, z) < 8 and (W.sky(x, y, z) or 0) < 15) then
        act().setBlock(x, y, z, 0)
        saplings[k], stage[k] = nil, nil
        spill({{sid, 1}}, x, y, z)
        return
    end
    if lightAt(x, y + 1, z) >= 9 and rnd(7) == 0 then advance(x, y, z) end
end

-- --- Костная мука --------------------------------------------------------------

-- ItemDye.func_150918_a: 15 искр в клетке, скорость — гаусс·0.02. Искры —
-- частицы движка (pfx.lua, вид «happy»).
local function happy(x, y, z, maxY)
    local function g() local u, v = math.random(), math.random(); return math.sqrt(-2 * math.log(u + 1e-9)) * math.cos(2 * math.pi * v) end
    local list = {}
    for i = 1, 15 do
        list[i] = {x = x + math.random(), y = y + math.random() * maxY, z = z + math.random(),
                   vx = g() * 0.02, vy = g() * 0.02, vz = g() * 0.02,
                   life = 20 / (math.random() * 0.8 + 0.2), size = 0.1 * (math.random() * 0.5 + 0.5) * 0.75 * 2}
    end
    require("pfx").spawn("happy", list)
end

P.happy = happy

-- Костная мука по блоку (x, y, z): true — мука потрачена.
function P.boneMeal(x, y, z)
    if not B.isSapling[W.get(x, y, z)] then return false end
    saplings[key(x, y, z)] = true
    if math.random() < 0.45 then advance(x, y, z) end
    happy(x, y, z, 0.8)
    return true
end

-- --- Каждый кадр ------------------------------------------------------------

local acc = 0
local CHANCE = 3 / 4096    -- случайный тик клетки за игровой тик
local function keysOf(t) local out = {}; for k in pairs(t) do out[#out + 1] = k end; return out end

-- Обход — по снимку ключей: опадание и рост дерева сами добавляют и убирают
-- клетки этих таблиц, а новый ключ посреди обхода pairs ломает next
-- («invalid key to 'next'» — игра падала после рубки дерева).
-- Выбор клеток тика — без копии всего набора: прежде каждый тик (20 раз в
-- секунду) строился массив ВСЕХ отмеченных клеток, и чем больше деревьев
-- срублено за игру, тем больше мусора на кадр. Теперь в список попадают
-- только выпавшие по шансу; обрабатываются после обхода (обработка меняет
-- набор, а менять таблицу во время pairs нельзя).
local picked = {}
local function pick(set)
    local n = 0
    local rnd = math.random
    for k in pairs(set) do
        if rnd() < CHANCE then n = n + 1; picked[n] = k end
    end
    return n
end

local function tick()
    local n = pick(check)
    for i = 1, n do
        local k = picked[i]
        picked[i] = nil
        local x, y, z = unkey(k)
        if W.chunk(x // 16, z // 16) then P.decayTick(x, y, z) end
    end
    n = pick(saplings)
    for i = 1, n do
        local k = picked[i]
        picked[i] = nil
        if saplings[k] then
            local x, y, z = unkey(k)
            if W.chunk(x // 16, z // 16) then P.saplingTick(x, y, z) end
        end
    end
end

function P.update(dt)
    acc = acc + dt
    local n = 0
    while acc >= 0.05 and n < 10 do
        acc = acc - 0.05
        n = n + 1
        tick()
    end
end

-- --- Сохранение -------------------------------------------------------------

local function keys(t) local out = {}; for k in pairs(t) do out[#out + 1] = k end; return out end
local function set(list) local t = {}; for _, k in ipairs(list or {}) do t[k] = true end; return t end

function P.save() return {check = keys(check), placed = keys(placed), saplings = keys(saplings), stage = keys(stage)} end

function P.load(t)
    t = type(t) == "table" and t or {}
    check, placed, saplings, stage = set(t.check), set(t.placed), set(t.saplings), set(t.stage)
end

-- Самопроверка (--gencheck, строка PLANTCHECK): деревья всех пород,
-- одиночный тёмный дуб, распад кроны после вырубки, шансы выпадения.
function P.selfCheck()
    local Act = act()
    local grass, ok, notes = id("grass"), true, {}
    -- Площадка: столб воздуха над травой в (x, base, z).
    local function plot(x, z)
        local base = W.surface(x, z)
        for dx = -6, 7 do
            for dz = -6, 7 do
                for yy = base + 1, math.min(W.HEIGHT - 1, base + 40) do W.setId(x + dx, yy, z + dz, 0) end
                W.setId(x + dx, base, z + dz, grass)
            end
        end
        return base + 1
    end
    local x0 = 40
    for i, kind in ipairs({"oak", "birch", "spruce", "jungle", "acacia"}) do
        local x, z = 20 + i * 14, 40
        local y = plot(x, z)
        Act.setBlock(x, y, z, id(kind .. "_sapling"))
        P.onPlace(id(kind .. "_sapling"), x, y, z)
        local grew = false
        for _ = 1, 20 do if growTree(x, y, z) then grew = true; break end end
        local trunk = B.isLog[W.get(x, y, z)] == true
        notes[#notes + 1] = kind .. "=" .. tostring(grew and trunk)
        ok = ok and grew and trunk
    end
    -- Тёмный дуб: одиночный не растёт и остаётся; 2×2 — растёт.
    local x, z = x0, 80
    local y = plot(x, z)
    local dark = id("dark_oak_sapling")
    Act.setBlock(x, y, z, dark)
    local single = not growTree(x, y, z) and W.get(x, y, z) == dark
    for _, d in ipairs({{1, 0}, {0, 1}, {1, 1}}) do Act.setBlock(x + d[1], y, z + d[2], dark) end
    local quad = growTree(x + 1, y, z + 1) and B.isLog[W.get(x, y, z)] == true
    notes[#notes + 1] = "тёмный_одиночка=" .. tostring(single) .. " тёмный_2×2=" .. tostring(quad)
    ok = ok and single and quad
    -- Вырубка: дуб без ствола — вся крона опадает, понемногу.
    local tx, tz = 20 + 14, 40
    local ty = W.surface(tx, tz)   -- верх ствола — от земли вверх
    local base = ty
    while not B.isLog[W.get(tx, base, tz)] and base > 0 do base = base - 1 end
    while B.isLog[W.get(tx, base - 1, tz)] do base = base - 1 end
    local by = base
    while B.isLog[W.get(tx, by, tz)] do
        Act.setBlock(tx, by, tz, 0)
        P.onBreak(id("log"), tx, by, tz)
        by = by + 1
    end
    local before = P.stats.decayed
    for _ = 1, 200 do
        local any = false
        for k in pairs(check) do any = true; local a, b, c = unkey(k); P.decayTick(a, b, c) end
        if not any then break end
    end
    local left = 0
    for dx = -3, 3 do for dy = 0, 12 do for dz = -3, 3 do
        if W.get(tx + dx, base + dy, tz + dz) == id("leaves") then left = left + 1 end
    end end end
    notes[#notes + 1] = "опало=" .. (P.stats.decayed - before) .. " осталось=" .. left
    ok = ok and left == 0 and P.stats.decayed > before
    -- Шансы: семена 1/8, саженец дуба 1/20, у тропической 1/40.
    local N, seeds, sap, jsap = 40000, 0, 0, 0
    for _ = 1, N do
        local a = P.dropsOf(id("tallgrass"), false); if a[1] then seeds = seeds + 1 end
        for _, it in ipairs(P.dropsOf(id("leaves"), false)) do if it[1] == id("oak_sapling") then sap = sap + 1 end end
        for _, it in ipairs(P.dropsOf(id("jungle_leaves"), false)) do if it[1] == id("jungle_sapling") then jsap = jsap + 1 end end
    end
    local fs, fo, fj = seeds / N, sap / N, jsap / N
    local chances = math.abs(fs - 1 / 8) < 0.01 and math.abs(fo - 1 / 20) < 0.005 and math.abs(fj - 1 / 40) < 0.004
    local shear = P.dropsOf(id("leaves"), true)[1][1] == id("leaves")
    notes[#notes + 1] = string.format("семена=%.3f саженец=%.3f тропич=%.3f ножницы=%s", fs, fo, fj, tostring(shear))
    ok = ok and chances and shear
    return "PLANTCHECK: " .. (ok and "PASS " or "FAIL ") .. table.concat(notes, " ")
end

-- Для проверок.
function P.isMarked(x, y, z) return check[key(x, y, z)] == true end
function P.stageOf(x, y, z) return stage[key(x, y, z)] and 1 or 0 end

return P
