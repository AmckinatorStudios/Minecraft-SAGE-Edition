-- ---------------------------------------------------------------------------
-- gen.lua — генерация участка по зерну.
--
-- Рельеф — сумма двух шумов: пологие холмы и редкие горные гряды (ridged),
-- их доля — по третьему, медленному шуму «материковости». Климат (жарко /
-- холодно, сухо / влажно) — ещё два медленных шума; из них — покров:
-- дёрн, песок пустыни, снег. Пещеры — «червоточины» из двух 3D-шумов: клетка
-- пустая, где оба шума близки к нулю (пересечение двух поверхностей даёт
-- длинные извилистые ходы, а не пузыри). Руда — гнёзда по хэшу.
--
-- Всё детерминировано по зерну: один и тот же участок всегда одинаков, поэтому
-- в сохранение пишутся только ИЗМЕНЁННЫЕ клетки, а не весь мир.
-- ---------------------------------------------------------------------------
local W = require "world"

local G = {}

local hills, ridges, continent, temp, wet, caveA, caveB, detail

function G.init(seed)
    G.seed = seed
    hills     = noise{kind = "simplex", seed = seed,       octaves = 4, scale = 1 / 96}
    ridges    = noise{kind = "simplex", seed = seed + 11,  octaves = 4, scale = 1 / 220}
    continent = noise{kind = "simplex", seed = seed + 23,  octaves = 2, scale = 1 / 420}
    temp      = noise{kind = "simplex", seed = seed + 37,  octaves = 2, scale = 1 / 360}
    wet       = noise{kind = "simplex", seed = seed + 41,  octaves = 2, scale = 1 / 300}
    caveA     = noise{kind = "simplex", seed = seed + 53,  octaves = 1, scale = 1 / 30}
    caveB     = noise{kind = "simplex", seed = seed + 59,  octaves = 1, scale = 1 / 30}
    detail    = noise{kind = "value",   seed = seed + 71,  octaves = 1, scale = 1 / 5}
end

local SEA = W.SEA

-- Высота и климат по значениям шумов — одна формула и для точки (поиск
-- спавна), и для сетки участка.
local function shape(hv, rv, cv, tv, wv)
    local c = cv * 0.5 + 0.5
    local h = SEA + 2 + hv * 9
    local r = 1 - math.abs(rv)
    local mount = math.max(0, c - 0.55) / 0.45
    h = h + (r * r * r) * 46 * mount
    h = h - math.max(0, 0.35 - c) * 30
    local biome
    if tv > 0.32 and wv < 0.1 then biome = "desert"
    elseif tv < -0.38 then biome = "snow"
    elseif wv > 0.18 then biome = "forest"
    else biome = "plains" end
    return math.floor(h), biome
end

-- Высота поверхности и климат точки — без участка: ими ищется спавн и корень
-- дерева соседа. Шум берётся в ТОЙ ЖЕ плоскости y = 0, что и сетка участка
-- (n.grid(bx, 0, bz, ...)): двумерный n(x, z) — другое поле, и точка
-- расходилась с рельефом — спавн оказывался в толще земли или в кроне.
function G.column(x, z)
    return shape(hills(x, 0, z), ridges.raw(x, 0, z), continent(x, 0, z), temp(x, 0, z), wet(x, 0, z))
end

-- Хэш клетки 0..1: руда, деревья, трава — не по шуму, а по хэшу, чтобы
-- разброс был ровным и не собирался в полосы.
local function rnd(x, y, z, salt)
    -- hash движка уже даёт 0..1 (docs: «детерминированное число 0..1»). Здесь
    -- стояло (hash % 100000) / 100000 — от дробного числа это сотые доли
    -- процента: каждый камень проходил порог угля, трава росла везде, а
    -- деревья вставали в каждую клетку сетки без сдвига.
    return hash(x, y, z, G.seed + salt)
end
G.rnd = rnd

local AIR, STONE, GRASS, DIRT, SAND, GRAVEL, BEDROCK, WATER = 0, 1, 2, 3, 8, 9, 10, 11
local COAL, IRON, GOLD, DIAMOND, SANDSTONE, SNOW, ICE, CLAY = 13, 14, 15, 16, 21, 28, 29, 30
local LOG, LEAVES, BLOG, BLEAVES, TALLGRASS, ROSE, DANDELION, CACTUS = 6, 7, 31, 32, 22, 23, 24, 41

local function put(c, x, y, z, id)
    -- Запись в свой участок по локальным координатам, без проверок мира.
    local s = W.section(c, y >> 4, true)
    local i = x + z * 16 + (y & 15) * 256 + 1
    s[i] = (s[i] & ~W.ID_MASK) | id
end

local function getLocal(c, x, y, z)
    local s = c.sec[y >> 4]
    if not s then return 0 end
    return s[x + z * 16 + (y & 15) * 256 + 1] & W.ID_MASK
end

-- ДЕРЕВЬЯ — по мировой сетке, а не по участку. Клетка сетки TREE_CELL×TREE_CELL
-- даёт не больше одного дерева, ствол сдвинут внутри неё на 0..TREE_JITTER:
-- соседние стволы стоят не ближе TREE_CELL - TREE_JITTER = 6 клеток, а
-- крона радиуса 2 занимает 5 — между кронами всегда есть просвет, лес не
-- слипается в сплошной полог. Решение
-- «есть ли дерево и какое» зависит только от зерна и точки, поэтому каждый
-- участок сам дорисовывает свою часть дерева соседа: граница участка дерево
-- не режет, порядок генерации ни на что не влияет.
local TREE_CELL, TREE_JITTER, CROWN = 8, 2, 2
G.TREE_CELL = TREE_CELL

-- Срезала ли пещера клетку (x, y, z) столба высоты h — та же формула, что в
-- generate, но для одной точки (дерево соседа не видит его сетку шумов).
local function carved(x, y, z, h)
    if y <= 4 or y >= h - 1 + (h > SEA + 2 and 2 or -3) then return false end
    local a, b = caveA.raw(x, y, z), caveB.raw(x, y, z)
    return a * a + b * b < 0.012
end

-- Дерево клетки сетки (gx, gz): x, y корня (первая клетка ствола), z, высота
-- ствола, берёза ли. nil — в этой клетке дерева нет.
function G.treeIn(gx, gz)
    local x = gx * TREE_CELL + math.floor(rnd(gx, 0, gz, 12) * (TREE_JITTER + 1))
    local z = gz * TREE_CELL + math.floor(rnd(gx, 1, gz, 12) * (TREE_JITTER + 1))
    local h, b = G.column(x, z)
    if h > W.HEIGHT - 8 then h = W.HEIGHT - 8 end
    -- Только на дёрне: не пляж (h <= SEA + 1 — песок), не пустыня, не снег.
    if b == "desert" or b == "snow" or h <= SEA + 1 or h + 10 >= W.HEIGHT then return nil end
    local chance = b == "forest" and 0.85 or 0.2
    if rnd(gx, 2, gz, 13) >= chance then return nil end
    if carved(x, h, z, h) or carved(x, h - 1, z, h) then return nil end
    local birch = b == "forest" and rnd(gx, 3, gz, 6) < 0.3
    local trunk = (birch and 5 or 4) + math.floor(rnd(gx, 4, gz, 5) * 3)
    return x, h + 1, z, trunk, birch
end

-- Есть ли ствол ближе r клеток к точке (x, z) — спавн не ставит игрока в крону.
function G.treeNear(x, z, r)
    for gx = (x - r - TREE_JITTER) // TREE_CELL, (x + r) // TREE_CELL do
        for gz = (z - r - TREE_JITTER) // TREE_CELL, (z + r) // TREE_CELL do
            local tx, _, tz = G.treeIn(gx, gz)
            if tx and math.abs(tx - x) <= r and math.abs(tz - z) <= r then return true end
        end
    end
    return false
end

-- Часть дерева, попавшая в участок c (мировые координаты дерева).
local function tree(c, x, y, z, h, birch)
    local bx, bz = c.cx * 16, c.cz * 16
    local log, leaves = birch and BLOG or LOG, birch and BLEAVES or LEAVES
    local function inside(wx, wz) return wx >= bx and wx < bx + 16 and wz >= bz and wz < bz + 16 end
    -- Крона: два широких слоя (углы — через раз), над ними узкий и «крест»
    -- на макушке. Листва только в пустоту: не съедает рельеф и соседей.
    for dy = h - 2, h + 1 do
        local rad = dy >= h and 1 or 2
        for dx = -rad, rad do
            for dz = -rad, rad do
                local wx, wy, wz = x + dx, y + dy, z + dz
                local corner = math.abs(dx) == rad and math.abs(dz) == rad
                local keep
                if dy == h + 1 then keep = dx == 0 or dz == 0
                elseif corner then keep = rnd(wx, wy, wz, 9) < (rad == 2 and 0.4 or 0.25)
                else keep = true end
                if keep and wy < W.HEIGHT and inside(wx, wz) and getLocal(c, wx - bx, wy, wz - bz) == AIR then
                    put(c, wx - bx, wy, wz - bz, leaves)
                end
            end
        end
    end
    if inside(x, z) then
        for dy = 0, h - 1 do put(c, x - bx, y + dy, z - bz, log) end
        put(c, x - bx, y - 1, z - bz, DIRT)
    end
end

function G.generate(c)
    local bx, bz = c.cx * 16, c.cz * 16
    local heights, biomes = {}, {}
    local maxH = SEA
    -- Шумы участка — сетками 16×16 (одна строка по y): один вызов на шум.
    local H = hills.grid(bx, 0, bz, 16, 1, 16)
    local R = ridges.grid(bx, 0, bz, 16, 1, 16, 1, "raw")
    local CN = continent.grid(bx, 0, bz, 16, 1, 16)
    local T = temp.grid(bx, 0, bz, 16, 1, 16)
    local WT = wet.grid(bx, 0, bz, 16, 1, 16)
    local DT = detail.grid(bx, 0, bz, 16, 1, 16)
    for lz = 0, 15 do
        for lx = 0, 15 do
            local i = lx + lz * 16 + 1
            local h, b = shape(H[i], R[i], CN[i], T[i], WT[i])
            if h > W.HEIGHT - 8 then h = W.HEIGHT - 8 end
            heights[lx + lz * 16] = h
            biomes[lx + lz * 16] = b
            if h > maxH then maxH = h end
        end
    end
    -- Поле пещер — две 3D-сетки на высоту участка.
    local caveTop = math.min(W.HEIGHT - 1, maxH)
    local CA = caveA.grid(bx, 0, bz, 16, caveTop + 1, 16, 1, "raw")
    local CB = caveB.grid(bx, 0, bz, 16, caveTop + 1, 16, 1, "raw")
    local ny = caveTop + 1
    -- Секции до самой высокой точки (плюс запас под деревья) — сразу.
    W.section(c, math.min(W.SECTIONS - 1, (maxH + 8) >> 4), true)

    for lz = 0, 15 do
        for lx = 0, 15 do
            local x, z = bx + lx, bz + lz
            local h, b = heights[lx + lz * 16], biomes[lx + lz * 16]
            local beach = h <= SEA + 1 and h >= SEA - 3
            local top, filler = GRASS, DIRT
            if b == "desert" or beach then top, filler = SAND, SAND end
            if b == "snow" then top = SNOW end
            if h < SEA - 3 then top, filler = (rnd(x, 0, z, 3) < 0.3) and CLAY or GRAVEL, DIRT end
            local fillDepth = 3 + math.floor(DT[lx + lz * 16 + 1] * 1.5 + 1.5)
            -- Секция под рукой на 16 клеток высоты: искать её на каждую клетку
            -- (put) стоило генерации заметной доли времени.
            local sec, secY = nil, -1
            local col = lx + lz * 16 + 1
            for y = 0, math.max(h, SEA) do
                local id
                if y == 0 or (y < 4 and rnd(x, y, z, 1) < (4 - y) / 4) then id = BEDROCK
                elseif y > h then id = (y == SEA and b == "snow") and ICE or WATER
                elseif y == h then id = top
                elseif y > h - fillDepth then id = (filler == SAND and y < h - 2) and SANDSTONE or filler
                else id = STONE end

                -- Пещеры не режут дно моря и воду: иначе океан вытек бы в дыру
                -- (жидкость в мире стоит, а не течёт).
                if id ~= BEDROCK and id ~= WATER and id ~= ICE and y < h - 1 + (h > SEA + 2 and 2 or -3) and y > 4 then
                    local ci = lx + y * 16 + lz * 16 * ny + 1
                    local a, bb = CA[ci], CB[ci]
                    if a * a + bb * bb < 0.012 then id = AIR end
                end

                if id == STONE then
                    local r = rnd(x, y, z, 2)
                    if r < 0.012 then id = COAL
                    elseif r < 0.019 and y < 64 then id = IRON
                    elseif r < 0.021 and y < 32 then id = GOLD
                    elseif r < 0.0222 and y < 16 then id = DIAMOND
                    elseif r < 0.03 and y < 80 then id = GRAVEL end
                end
                if id ~= AIR then
                    if (y >> 4) ~= secY then secY = y >> 4; sec = W.section(c, secY, true) end
                    local i = col + (y & 15) * 256
                    sec[i] = (sec[i] & ~W.ID_MASK) | id
                end
            end
        end
    end

    -- Деревья — все клетки сетки, чья крона задевает участок (свои и соседей).
    local reach = CROWN + TREE_JITTER
    for gx = (bx - reach) // TREE_CELL, (bx + 15 + CROWN) // TREE_CELL do
        for gz = (bz - reach) // TREE_CELL, (bz + 15 + CROWN) // TREE_CELL do
            local x, y, z, h, birch = G.treeIn(gx, gz)
            if x and x + CROWN >= bx and x - CROWN < bx + 16 and z + CROWN >= bz and z - CROWN < bz + 16 then
                tree(c, x, y, z, h, birch)
            end
        end
    end

    -- Трава, цветы, кактусы — по всему участку, до самого края: иначе по
    -- границам участков тянулись голые полосы.
    for lz = 0, 15 do
        for lx = 0, 15 do
            local x, z = bx + lx, bz + lz
            local h, b = heights[lx + lz * 16], biomes[lx + lz * 16]
            local ground = getLocal(c, lx, h, lz)
            if ground == GRASS and h > SEA and h + 1 < W.HEIGHT and getLocal(c, lx, h + 1, lz) == AIR then
                local g = rnd(x, h + 1, z, 7)
                local grass = b == "forest" and 0.2 or 0.14
                if g < grass then put(c, lx, h + 1, lz, TALLGRASS)
                elseif g < grass + 0.015 then put(c, lx, h + 1, lz, ROSE)
                elseif g < grass + 0.03 then put(c, lx, h + 1, lz, DANDELION) end
            elseif ground == SAND and b == "desert" and h > SEA + 1 and rnd(x, h, z, 4) < 0.006 then
                for dy = 1, 1 + math.floor(rnd(x, 1, z, 8) * 3) do put(c, lx, h + dy, lz, CACTUS) end
            end
        end
    end
    c.generated = true
end

-- Самопроверка генерации (--gencheck): участки вокруг нуля строятся заново и
-- проверяется то, что ломалось. 1) Высота столба по точке = высоте по сетке
-- (на этом держатся спавн и деревья соседей), и мир по мировым координатам
-- читает ту же клетку, что участок, — и при отрицательных координатах. 2) Ствол каждого дерева стоит
-- целиком, а крона есть и по ту сторону границы участка. 3) Стволы не ближе
-- TREE_CELL - TREE_JITTER клеток — кроны не слипаются. 4) Трава доходит до края участка.
function G.selfCheck()
    local R = 5
    local cells = {}
    for cx = -R, R do
        for cz = -R, R do
            local c = W.newChunk(cx, cz)
            G.generate(c)
        end
    end
    local heightBad, worldBad, n = 0, 0, 0
    -- Доля руды в толще: камня должно быть подавляюще больше, чем угля.
    -- (Хэш, понятый как целое, давал уголь вместо всего камня.)
    local stone, coal, iron = 0, 0, 0
    for cx = -1, 1 do
        for cz = -1, 1 do
            local c = W.chunk(cx, cz)
            for y = 5, 40 do
                for lz = 0, 15 do
                    for lx = 0, 15 do
                        local id = getLocal(c, lx, y, lz)
                        if id == STONE then stone = stone + 1
                        elseif id == COAL then coal = coal + 1
                        elseif id == IRON then iron = iron + 1 end
                    end
                end
            end
        end
    end
    local borderGrass, innerGrass = 0, 0
    for cx = -R, R do
        for cz = -R, R do
            local c = W.chunk(cx, cz)
            for lz = 0, 15 do
                for lx = 0, 15 do
                    local x, z = cx * 16 + lx, cz * 16 + lz
                    local h = G.column(x, z)
                    if h > W.HEIGHT - 8 then h = W.HEIGHT - 8 end
                    n = n + 1
                    local g = getLocal(c, lx, h + 1, lz) == TALLGRASS
                    -- Мир по мировым координатам = участок (отрицательные тоже).
                    if W.get(x, h, z) ~= getLocal(c, lx, h, lz) then worldBad = worldBad + 1 end
                    if getLocal(c, lx, h, lz) == AIR and getLocal(c, lx, h - 1, lz) == AIR and h > SEA + 3 then
                        -- столб, срезанный пещерой, высоту не проверяет
                    elseif getLocal(c, lx, h + 1, lz) == STONE or getLocal(c, lx, h + 1, lz) == GRASS then
                        heightBad = heightBad + 1
                    end
                    if g then
                        if lx < 2 or lx > 13 or lz < 2 or lz > 13 then borderGrass = borderGrass + 1
                        else innerGrass = innerGrass + 1 end
                    end
                end
            end
        end
    end
    local trees, broken, crossed, cut, close = {}, 0, 0, 0, 0
    local lo, hi = -R * 16 // TREE_CELL + 1, (R * 16 + 15) // TREE_CELL - 1
    for gx = lo, hi do
        for gz = lo, hi do
            local x, y, z, h, birch = G.treeIn(gx, gz)
            if x then
                trees[#trees + 1] = {x, z}
                local log = birch and BLOG or LOG
                for dy = 0, h - 1 do
                    if W.get(x, y + dy, z) ~= log then broken = broken + 1; break end
                end
                -- Крона по ту сторону границы участка.
                local lx = x & 15
                local side = lx >= 14 and 1 or (lx <= 1 and -1 or 0)
                if side ~= 0 then
                    if W.get(x + side * 2, y + h - 1, z) ~= AIR then crossed = crossed + 1 else cut = cut + 1 end
                end
            end
        end
    end
    for i = 1, #trees do
        for j = i + 1, #trees do
            local dx, dz = trees[i][1] - trees[j][1], trees[i][2] - trees[j][2]
            if math.max(math.abs(dx), math.abs(dz)) < TREE_CELL - TREE_JITTER then close = close + 1 end
        end
    end
    local coalShare = coal / math.max(1, stone + coal)
    local ok = coalShare < 0.05 and stone > 0 and iron > 0 and heightBad == 0 and worldBad == 0 and broken == 0 and cut == 0 and crossed > 0 and close == 0 and borderGrass > 0 and #trees > 0
    return string.format("GENCHECK: %s столбов=%d высота_мимо=%d мир_мимо=%d деревьев=%d сломано=%d тесно=%d через_границу=%d срезано=%d трава_у_края=%d трава_внутри=%d угля=%.1f%% железа=%d",
        ok and "PASS" or "FAIL", n, heightBad, worldBad, #trees, broken, close, crossed, cut, borderGrass, innerGrass, coalShare * 100, iron)
end

-- Точка спавна: ближайший к нулю сухой столб над уровнем моря, не под деревом.
function G.spawnPoint()
    for r = 0, 400, 8 do
        for _, p in ipairs({{r, 0}, {-r, 0}, {0, r}, {0, -r}, {r, r}, {-r, -r}}) do
            local h, b = G.column(p[1], p[2])
            if h > SEA + 1 and b ~= "desert" and not G.treeNear(p[1], p[2], 3) then
                return p[1] + 0.5, h + 1, p[2] + 0.5
            end
        end
    end
    return 0.5, SEA + 10, 0.5
end

return G
