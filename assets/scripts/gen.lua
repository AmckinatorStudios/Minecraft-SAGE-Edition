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

-- Высота поверхности и климат точки — без участка: ими же ищется спавн.
function G.column(x, z)
    return shape(hills(x, z), ridges.raw(x, z), continent(x, z), temp(x, z), wet(x, z))
end

-- Хэш клетки 0..1: руда, деревья, трава — не по шуму, а по хэшу, чтобы
-- разброс был ровным и не собирался в полосы.
local function rnd(x, y, z, salt)
    return (hash(x, y, z, G.seed + salt) % 100000) / 100000
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

-- Дерево целиком внутри участка (корень отступает от края на 2) — так дерево
-- никогда не режется границей участка и не зависит от порядка генерации.
local function tree(c, x, y, z, birch)
    local h = 4 + math.floor(rnd(c.cx * 16 + x, y, c.cz * 16 + z, 5) * 3)
    local log, leaves = birch and BLOG or LOG, birch and BLEAVES or LEAVES
    for dy = h - 3, h do
        local rad = dy >= h - 1 and 1 or 2
        for dx = -rad, rad do
            for dz = -rad, rad do
                local corner = math.abs(dx) == rad and math.abs(dz) == rad
                if not corner or rnd(c.cx * 16 + x + dx, y + dy, c.cz * 16 + z + dz, 9) < 0.45 then
                    if dy < h or (dx == 0 or dz == 0) then
                        if y + dy < W.HEIGHT and getLocal(c, x + dx, y + dy, z + dz) == AIR then
                            put(c, x + dx, y + dy, z + dz, leaves)
                        end
                    end
                end
            end
        end
    end
    for dy = 0, h - 1 do put(c, x, y + dy, z, log) end
    put(c, x, y - 1, z, DIRT)
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
                if id ~= AIR then put(c, lx, y, lz, id) end
            end
        end
    end

    -- Растения и деревья — после рельефа: им нужен уже готовый верх.
    for lz = 2, 13 do
        for lx = 2, 13 do
            local x, z = bx + lx, bz + lz
            local h, b = heights[lx + lz * 16], biomes[lx + lz * 16]
            local ground = getLocal(c, lx, h, lz)
            local r = rnd(x, h, z, 4)
            if ground == GRASS and h > SEA then
                local density = b == "forest" and 0.022 or 0.004
                if r < density and h + 8 < W.HEIGHT then
                    tree(c, lx, h + 1, lz, b == "forest" and rnd(x, 0, z, 6) < 0.3)
                elseif getLocal(c, lx, h + 1, lz) == AIR then
                    local g = rnd(x, h + 1, z, 7)
                    if g < 0.14 then put(c, lx, h + 1, lz, TALLGRASS)
                    elseif g < 0.155 then put(c, lx, h + 1, lz, ROSE)
                    elseif g < 0.17 then put(c, lx, h + 1, lz, DANDELION) end
                end
            elseif ground == SAND and b == "desert" and h > SEA + 1 and r < 0.006 then
                for dy = 1, 1 + math.floor(rnd(x, 1, z, 8) * 3) do put(c, lx, h + dy, lz, CACTUS) end
            end
        end
    end
    c.generated = true
end

-- Точка спавна: ближайший к нулю сухой столб над уровнем моря.
function G.spawnPoint()
    for r = 0, 400, 8 do
        for _, p in ipairs({{r, 0}, {-r, 0}, {0, r}, {0, -r}, {r, r}, {-r, -r}}) do
            local h, b = G.column(p[1], p[2])
            if h > SEA + 1 and b ~= "desert" then return p[1] + 0.5, h + 1, p[2] + 0.5 end
        end
    end
    return 0.5, SEA + 10, 0.5
end

return G
