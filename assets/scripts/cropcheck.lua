-- ---------------------------------------------------------------------------
-- cropcheck.lua — самопроверка пшеницы (--gencheck, строка CROPCHECK): на
-- площадке над игроком — мотыга (земля, трава, не камень, не под блоком, не
-- снизу), влажность от воды и дождя и высыхание, обратная земля, посадка,
-- скорость роста func_149864_n, шанс роста, свет, предел стадии 7, выпадение
-- (семя до зрелости, пшеница и 0..3 семени — 8/15 каждое), поломка вместе с
-- грядкой, костная мука, вытаптывание, рецепты и сохранение клеток.
-- Площадка после проверки убирается.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Cr = require "crops"

local CC = {}

function CC.selfCheck(P)
    local Act = require "interact"
    local Inv = require "inventory"
    local bx, bz = math.floor(P.pos.x) + 20, math.floor(P.pos.z) + 20
    local by = math.min(W.HEIGHT - 12, math.floor(P.pos.y) + 30)
    local dirt, grass, stone = B.byName.dirt.id, B.byName.grass.id, B.byName.stone.id
    local F, Wh = Cr.FARMLAND, Cr.WHEAT
    local seeds, wheat = B.byName.wheat_seeds.id, B.byName.wheat.id
    local touched = {}
    local function set(x, y, z, id, meta)
        touched[#touched + 1] = {x, y, z}
        Act.setBlock(x, y, z, id, meta)
    end
    -- Площадка 20×20 земли, над ней воздух — напрямую в мир (без пересчёта
    -- света на каждую клетку: проверке нужен только свет над посевами).
    for x = 0, 19 do
        for z = 0, 19 do
            touched[#touched + 1] = {bx + x, by, bz + z}
            W.setId(bx + x, by, bz + z, dirt)
            for y = 1, 3 do
                touched[#touched + 1] = {bx + x, by + y, bz + z}
                W.setId(bx + x, by + y, bz + z, 0)
                W.setLight(bx + x, by + y, bz + z, 15, 0)
            end
        end
    end
    local drops = {}
    local Drops = require "drops"
    local saveSpawn = Drops.spawn
    Drops.spawn = function(id, n) drops[#drops + 1] = {id = id, n = n} end
    local Weather = require "weather"
    local savedRain = {Weather.rain, Weather.prevRain, Weather.raining}
    Weather.rain, Weather.prevRain = 0, 0
    local res = {}
    local function T(x, z, ny, id) return {x = bx + x, y = by, z = bz + z, nx = 0, ny = ny or 1, nz = 0, id = id or W.get(bx + x, by, bz + z)} end

    -- 1. Мотыга: земля и трава — грядка (влажность 0), износ 1; камень, блок
    -- сверху и нижняя грань — нет.
    local savedSlot = Inv.slots[Inv.selected]
    Inv.slots[Inv.selected] = {id = B.byName.wood_hoe.id, n = 1, wear = 0}
    local ok1 = Cr.use(T(1, 1), Inv.current()) and W.get(bx + 1, by, bz + 1) == F and W.meta(bx + 1, by, bz + 1) == 0
        and Inv.current().wear == 1
    set(bx + 2, by, bz + 1, grass)
    local ok2 = Cr.use(T(2, 1), Inv.current()) and W.get(bx + 2, by, bz + 1) == F
    set(bx + 3, by, bz + 1, stone)
    local ok3 = not Cr.use(T(3, 1), Inv.current())
    set(bx + 4, by + 1, bz + 1, stone)
    local ok4 = not Cr.use(T(4, 1), Inv.current())
    local ok5 = not Cr.use(T(5, 1, -1), Inv.current())
    res.hoe = ok1 and ok2 and ok3 and ok4 and ok5 and Inv.current().wear == 2
    Inv.slots[Inv.selected] = savedSlot

    -- 2. Влажность: вода в 4 клетках — 7; без воды — убывает, сухая пустая
    -- грядка — снова земля; сухая под пшеницей — остаётся.
    set(bx + 10, by, bz + 10, F, 0)
    set(bx + 14, by + 1, bz + 10, 11)            -- вода в 4 по x и на блок выше
    Cr.farmlandTick(bx + 10, by, bz + 10)
    local wet = W.meta(bx + 10, by, bz + 10) == 7
    set(bx + 14, by + 1, bz + 10, 0)
    set(bx + 15, by, bz + 10, 11)                -- в 5 клетках — уже не считается
    Cr.farmlandTick(bx + 10, by, bz + 10)
    local drying = W.meta(bx + 10, by, bz + 10) == 6
    set(bx + 15, by, bz + 10, dirt)
    for _ = 1, 6 do Cr.farmlandTick(bx + 10, by, bz + 10) end
    local dry = W.meta(bx + 10, by, bz + 10) == 0 and W.get(bx + 10, by, bz + 10) == F
    Cr.farmlandTick(bx + 10, by, bz + 10)
    local reverted = W.get(bx + 10, by, bz + 10) == dirt
    set(bx + 10, by, bz + 12, F, 0)
    set(bx + 10, by + 1, bz + 12, Wh, 0)
    Cr.farmlandTick(bx + 10, by, bz + 12)
    local kept = W.get(bx + 10, by, bz + 12) == F
    res.moisture = wet and drying and dry and reverted and kept
    -- Дождь над открытой грядкой — 7 (если биом с дождём).
    set(bx + 12, by, bz + 14, F, 0)
    Weather.rain, Weather.prevRain = 1, 1
    local _, biome = require("gen").column(bx + 12, bz + 14)
    Cr.farmlandTick(bx + 12, by, bz + 14)
    local rained = W.meta(bx + 12, by, bz + 14) == ((biome == "desert" or biome == "snow") and 0 or 7)
    -- Под крышей дождь не мочит.
    set(bx + 12, by + 3, bz + 16, stone)
    set(bx + 12, by, bz + 16, F, 0)
    Cr.farmlandTick(bx + 12, by, bz + 16)
    local roofed = W.get(bx + 12, by, bz + 16) == dirt
    Weather.rain, Weather.prevRain = 0, 0
    res.rain = rained and roofed

    -- 3. Посадка: только верх грядки, семя тратится; на землю — нельзя.
    set(bx + 6, by, bz + 6, F, 7)
    Inv.slots[Inv.selected] = {id = seeds, n = 3}
    local p1 = Cr.use(T(6, 6), Inv.current()) and W.get(bx + 6, by + 1, bz + 6) == Wh and Inv.current().n == 2
    local p2 = not Cr.use(T(6, 6), Inv.current())                 -- место занято
    local p3 = not Cr.use(T(7, 6, 1, dirt), Inv.current())        -- не грядка
    local p4 = not Cr.use(T(6, 6, 0), Inv.current())              -- боковая грань
    res.plant = p1 and p2 and p3 and p4 and Inv.current().n == 2
    Inv.slots[Inv.selected] = savedSlot

    -- 4. Скорость роста (func_149864_n): одна пшеница на сухой — 2, на
    -- влажной — 4; поле 3×3 влажное — 1 + 3 + 8·0.75 = 10, но с соседями по
    -- диагонали — пополам (5); ряд вдоль одной оси — не пополам.
    local function field(cx, cz, wetMeta, crops)
        for dx = -1, 1 do
            for dz = -1, 1 do
                set(bx + cx + dx, by, bz + cz + dz, F, wetMeta)
                set(bx + cx + dx, by + 1, bz + cz + dz, 0)
            end
        end
        for _, c in ipairs(crops) do set(bx + cx + c[1], by + 1, bz + cz + c[2], Wh, 0) end
    end
    set(bx + 2, by, bz + 16, F, 0); set(bx + 2, by + 1, bz + 16, Wh, 0)
    local r1 = Cr.growthRate(bx + 2, by + 1, bz + 16)
    set(bx + 2, by, bz + 16, F, 7)
    local r2 = Cr.growthRate(bx + 2, by + 1, bz + 16)
    field(16, 3, 7, {{0, 0}})
    local r3 = Cr.growthRate(bx + 16, by + 1, bz + 3)
    field(16, 7, 7, {{0, 0}, {1, 1}})
    local r4 = Cr.growthRate(bx + 16, by + 1, bz + 7)
    field(16, 11, 7, {{0, 0}, {-1, 0}, {1, 0}})
    local r5 = Cr.growthRate(bx + 16, by + 1, bz + 11)
    field(16, 15, 7, {{0, 0}, {1, 0}, {0, 1}})
    local r6 = Cr.growthRate(bx + 16, by + 1, bz + 15)
    res.rate = r1 == 2 and r2 == 4 and r3 == 10 and r4 == 5 and r5 == 10 and r6 == 5
    -- Граница броска: (int)(25 / f) + 1 — 13 у 2, 7 у 4, 3 у 10, 6 у 5.
    res.bound = Cr.growBound(2) == 13 and Cr.growBound(4) == 7 and Cr.growBound(10) == 3 and Cr.growBound(5) == 6

    -- 5. Рост тиками: при свете растёт до 7 и не выше; доля удачных бросков
    -- близка к 1/(граница) (поле 3×3 влажное, f = 10 → 1/3).
    local gx, gy, gz = bx + 16, by + 1, bz + 3
    W.setLight(gx, gy + 1, gz, 15, 15)
    local tries, ups = 0, 0
    for _ = 1, 3000 do
        Cr.setMeta(gx, gy, gz, 0)
        Cr.cropTick(gx, gy, gz)
        tries = tries + 1
        if W.meta(gx, gy, gz) == 1 then ups = ups + 1 end
    end
    local share = ups / tries
    Cr.setMeta(gx, gy, gz, 6)
    for _ = 1, 200 do Cr.cropTick(gx, gy, gz) end
    res.grow = math.abs(share - 1 / 3) < 0.04 and W.meta(gx, gy, gz) == 7

    -- 6. Темнота: свет над растением < 9 — не растёт; < 8 без неба — ломается.
    local savedSky, savedBlk = W.sky(gx, gy + 1, gz), W.blockLight(gx, gy + 1, gz)
    local savedOwn = W.sky(gx, gy, gz)
    Cr.setMeta(gx, gy, gz, 3)
    set(gx, gy + 3, gz, stone)                   -- крыша: неба нет
    W.setLight(gx, gy + 1, gz, 5, 0)
    W.setLight(gx, gy, gz, 8, 0)
    for _ = 1, 200 do Cr.cropTick(gx, gy, gz) end
    local dark = W.meta(gx, gy, gz) == 3 and W.get(gx, gy, gz) == Wh
    W.setLight(gx, gy, gz, 7, 0)
    drops = {}
    Cr.cropTick(gx, gy, gz)
    local fell = W.get(gx, gy, gz) == 0 and #drops == 1 and drops[1].id == seeds
    W.setLight(gx, gy + 1, gz, savedSky or 15, savedBlk or 0)
    W.setLight(gx, gy, gz, savedOwn or 15, 0)
    res.light = dark and fell

    -- 7. Выпадение: до зрелости — ровно одно семя; зрелая — одна пшеница и
    -- 0..3 семени, в среднем 3·8/15 = 1.6.
    local early = true
    for st = 0, 6 do
        local d = Cr.dropsOf(st)
        if #d ~= 1 or d[1][1] ~= seeds or d[1][2] ~= 1 then early = false end
    end
    local total, maxSeeds, wheatOk, N = 0, 0, true, 6000
    local hist = {[0] = 0, 0, 0, 0}
    for _ = 1, N do
        local d = Cr.dropsOf(7)
        local w, s = 0, 0
        for _, it in ipairs(d) do
            if it[1] == wheat then w = w + it[2] else s = s + it[2] end
        end
        if w ~= 1 then wheatOk = false end
        total = total + s
        maxSeeds = math.max(maxSeeds, s)
        hist[s] = (hist[s] or 0) + 1
    end
    local mean = total / N
    res.drops = early and wheatOk and maxSeeds == 3 and math.abs(mean - 1.6) < 0.08 and hist[0] > 0

    -- 8. Сломали грядку или она стала землёй — пшеница выпадает (зрелая — пшеницей).
    set(bx + 4, by, bz + 18, F, 7); set(bx + 4, by + 1, bz + 18, Wh, 7)
    drops = {}
    Act.setBlock(bx + 4, by, bz + 18, dirt)
    local hasWheat = false
    for _, it in ipairs(drops) do if it.id == wheat then hasWheat = true end end
    local gone1 = W.get(bx + 4, by + 1, bz + 18) == 0 and hasWheat
    set(bx + 6, by, bz + 18, F, 7); set(bx + 6, by + 1, bz + 18, Wh, 2)
    drops = {}
    Act.setBlock(bx + 6, by, bz + 18, 0)
    local gone2 = W.get(bx + 6, by + 1, bz + 18) == 0 and #drops == 1 and drops[1].id == seeds
    -- Твёрдый блок на грядку — грядка становится землёй.
    set(bx + 8, by, bz + 18, F, 7)
    set(bx + 8, by + 1, bz + 18, stone)
    local covered = W.get(bx + 8, by, bz + 18) == dirt
    res.support = gone1 and gone2 and covered

    -- 9. Костная мука: +2..5, не выше 7; на зрелой — не тратится.
    set(bx + 10, by, bz + 18, F, 7); set(bx + 10, by + 1, bz + 18, Wh, 0)
    local bm = Cr.boneMeal(bx + 10, by + 1, bz + 18)
    local st = W.meta(bx + 10, by + 1, bz + 18)
    Cr.setMeta(bx + 10, by + 1, bz + 18, 7)
    res.bonemeal = bm and st >= 2 and st <= 5 and not Cr.boneMeal(bx + 10, by + 1, bz + 18)

    -- 10. Вытаптывание: падение 0.5 — никогда, 1.5 — всегда.
    set(bx + 12, by, bz + 18, F, 7)
    local never = true
    for _ = 1, 50 do if Cr.fallenUpon(bx + 12, by, bz + 18, 0.5) then never = false end end
    local always = Cr.fallenUpon(bx + 12, by, bz + 18, 1.5) and W.get(bx + 12, by, bz + 18) == dirt
    res.trample = never and always

    -- 11. Рецепты мотыг (5 материалов) и предметы: семена и пшеница по 64,
    -- мотыга — 1, прочность по материалу.
    local R = require "crafting"
    local function crafted(mat, out)
        local m = B.byName[mat].id
        local g = {{id = m, n = 1}, {id = m, n = 1}, nil, nil, {id = B.byName.stick.id, n = 1}, nil, nil,
                   {id = B.byName.stick.id, n = 1}, nil}
        local r = R.match(g, {size = 3})
        return r and r.out == B.byName[out].id
    end
    res.items = crafted("planks", "wood_hoe") and crafted("cobblestone", "stone_hoe") and crafted("iron_ingot", "iron_hoe")
        and crafted("gold_ingot", "gold_hoe") and crafted("diamond", "diamond_hoe")
        and B.byName.wheat_seeds.stack == 64 and B.byName.wheat.stack == 64 and B.byName.iron_hoe.stack == 1
        and B.byName.wood_hoe.uses == 60 and B.byName.gold_hoe.uses == 33 and B.byName.diamond_hoe.uses == 1562
        and not B.solid[Wh] and B.drawKind[Wh] == 10

    -- 12. Сохранение: клетки — в списке, стадия и влажность — в правке участка.
    set(bx + 14, by, bz + 18, F, 5); set(bx + 14, by + 1, bz + 18, Wh, 6)
    local saved = Cr.save()
    Cr.load(saved)
    local C = require "chunks"
    local e = C.edits[W.ckey((bx + 14) // 16, (bz + 18) // 16)]
    local idx = ((bx + 14) & 15) + ((bz + 18) & 15) * 16 + (by + 1) * 256
    res.save = Cr.tracked(bx + 14, by, bz + 18) and Cr.tracked(bx + 14, by + 1, bz + 18) and e ~= nil
        and e[idx] == (Wh | (6 << 10))

    -- Убрать за собой: сначала верхние слои.
    Drops.spawn = saveSpawn
    Weather.rain, Weather.prevRain, Weather.raining = savedRain[1], savedRain[2], savedRain[3]
    for i = #touched, 1, -1 do
        local c = touched[i]
        if c[2] > by then W.setId(c[1], c[2], c[3], 0) end
    end
    for i = #touched, 1, -1 do
        local c = touched[i]
        W.setId(c[1], c[2], c[3], 0)
        W.markDirty(c[1], c[2], c[3])
    end
    for _, c in ipairs(touched) do Cr.randomTick(c[1], c[2], c[3]) end
    -- Правки проверки в сохранение не идут.
    local C = require "chunks"
    for _, c in ipairs(touched) do
        local ed = C.edits[W.ckey(c[1] // 16, c[3] // 16)]
        if ed then ed[(c[1] & 15) + (c[3] & 15) * 16 + c[2] * 256] = nil end
    end
    local keys = {"hoe", "moisture", "rain", "plant", "rate", "bound", "grow", "light", "drops", "support", "bonemeal",
                  "trample", "items", "save"}
    local all, parts = true, {}
    for _, k in ipairs(keys) do
        if not res[k] then all = false end
        parts[#parts + 1] = k .. "=" .. tostring(res[k] and true or false)
    end
    return "CROPCHECK: " .. (all and "PASS " or "FAIL ") .. table.concat(parts, " ")
        .. string.format(" доля=%.3f семян=%.2f", share, mean)
end

return CC
