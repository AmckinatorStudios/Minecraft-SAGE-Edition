-- ---------------------------------------------------------------------------
-- ores.lua — руды по правилам Minecraft Java 1.7.10.
--
-- Повторены BiomeDecorator.generateOres и WorldGenMinable:
--   * у каждого участка своё случайное число из зерна мира — тем же способом,
--     что ChunkProviderGenerate.populate (java.util.Random, ниже — его точная
--     копия на целых Lua);
--   * на каждую руду — заданное число ПОПЫТОК: X и Z — случайно в участке,
--     Y — по правилу руды; попытка может не поставить ничего;
--   * жила — вытянутый отрезок длиной ~размер/4 со случайным направлением,
--     концы гуляют по высоте на 0..2, вдоль отрезка — шарики, чей радиус растёт
--     к середине (синус) и случаен на каждом шаге;
--   * заменяется ТОЛЬКО камень: воздух, земля, гравий, вода, коренная порода и
--     другая руда остаются как были. Поэтому размер жилы — предел, а не число.
--
-- Как в оригинале, жила начинается со смещением +8 и задевает соседние
-- участки. Здесь участок строится один, поэтому каждый участок прогоняет руды
-- своих соседей слева и сверху (их жилы могут дотянуться) и ставит только то,
-- что попало к нему. Итог не зависит от порядка генерации участков.
--
-- Изумруд — не жила: в Extreme Hills (и Edge) 3..8 попыток, Y 4..31, один
-- блок, если там камень.
-- ---------------------------------------------------------------------------
local W = require "world"

local O = {}

local STONE, DIRT, GRAVEL = 1, 3, 9
local COAL, IRON, GOLD, DIAMOND = 13, 14, 15, 16
local REDSTONE, LAPIS, EMERALD = 48, 49, 50
O.ID = {coal = COAL, iron = IRON, gold = GOLD, diamond = DIAMOND, redstone = REDSTONE,
        lapis = LAPIS, emerald = EMERALD, dirt = DIRT, gravel = GRAVEL}

-- --- java.util.Random -------------------------------------------------------
local MASK48 = (1 << 48) - 1
local MULT, ADD = 0x5DEECE66D, 0xB

local Random = {}
Random.__index = Random

local function newRandom(seed)
    return setmetatable({s = (seed ~ MULT) & MASK48}, Random)
end
O.Random = newRandom

function Random:setSeed(seed) self.s = (seed ~ MULT) & MASK48 end

-- next(bits): (int)(seed >>> (48 - bits)); для 32 бит — со знаком.
function Random:next(bits)
    self.s = (self.s * MULT + ADD) & MASK48
    local r = self.s >> (48 - bits)
    if bits == 32 and r >= 0x80000000 then r = r - 0x100000000 end
    return r
end

function Random:nextInt(n)
    if n & -n == n then                          -- степень двойки
        return (n * self:next(31)) >> 31
    end
    while true do
        local bits = self:next(31)
        local val = bits % n
        -- Отказ, если bits - val + (n - 1) переполнил бы int: так в Java.
        if bits - val + (n - 1) < 0x80000000 then return val end
    end
end

function Random:nextLong()
    return (self:next(32) << 32) + self:next(32)  -- целые Lua — 64 бита, как long
end

function Random:nextFloat() return self:next(24) / (1 << 24) end

function Random:nextDouble()
    return ((self:next(26) << 27) + self:next(27)) * (1.0 / (1 << 53))
end

-- Деление long на 2 в Java отбрасывает дробь к нулю (а // в Lua — вниз).
local function half(v) return v >= 0 and v // 2 or -((-v) // 2) end

-- Случайное число участка — ChunkProviderGenerate.populate:
--   rand.setSeed(seed); a = nextLong()/2*2+1; b = nextLong()/2*2+1;
--   rand.setSeed(cx*a + cz*b ^ seed)
function O.chunkRandom(seed, cx, cz)
    local r = newRandom(seed)
    local a = half(r:nextLong()) * 2 + 1
    local b = half(r:nextLong()) * 2 + 1
    r:setSeed((cx * a + cz * b) ~ seed)
    return r
end

-- MathHelper.sin — по таблице из 65536 значений, как в игре.
local TWO_PI = math.pi * 2
local function msin(f) return math.sin(((math.floor(f * 10430.378) & 65535)) * TWO_PI / 65536) end
local function mcos(f) return math.sin(((math.floor(f * 10430.378 + 16384.0) & 65535)) * TWO_PI / 65536) end

-- --- WorldGenMinable --------------------------------------------------------
-- Жила из n блоков в точке (x, y, z) мира. place(wx, wy, wz) зовётся для
-- каждой клетки жилы внутри окна [x0..x1]×[z0..z1] (участок, который строится);
-- случайные числа тратятся ВСЕ, даже если окно жилу не задевает, — иначе
-- следующие жилы участка разошлись бы с оригиналом.
local floor = math.floor
local function minable(rand, n, x, y, z, x0, x1, z0, z1, place)
    local f = rand:nextFloat() * math.pi
    local s, c = msin(f) * n / 8.0, mcos(f) * n / 8.0
    local ax, bx = x + 8 + s, x + 8 - s
    local az, bz = z + 8 + c, z + 8 - c
    local ay = y + rand:nextInt(3) - 2
    local by = y + rand:nextInt(3) - 2
    for l = 0, n do
        local cxp = ax + (bx - ax) * l / n
        local cyp = ay + (by - ay) * l / n
        local czp = az + (bz - az) * l / n
        local d9 = rand:nextDouble() * n / 16.0
        local r = (msin(l * math.pi / n) + 1.0) * d9 + 1.0   -- поперёк (и по высоте — то же)
        local hr = r / 2.0
        local i1, l1 = floor(cxp - hr), floor(cxp + hr)
        local j1, i2 = floor(cyp - hr), floor(cyp + hr)
        local k1, j2 = floor(czp - hr), floor(czp + hr)
        if l1 >= x0 and i1 <= x1 and j2 >= z0 and k1 <= z1 then
            for k2 = math.max(i1, x0), math.min(l1, x1) do
                local dx = (k2 + 0.5 - cxp) / hr
                if dx * dx < 1.0 then
                    for l2 = j1, i2 do
                        local dy = (l2 + 0.5 - cyp) / hr
                        if dx * dx + dy * dy < 1.0 then
                            for i3 = math.max(k1, z0), math.min(j2, z1) do
                                local dz = (i3 + 0.5 - czp) / hr
                                if dx * dx + dy * dy + dz * dz < 1.0 then place(k2, l2, i3) end
                            end
                        end
                    end
                end
            end
        end
    end
end
O.minable = minable

-- Порядок и правила BiomeDecorator.generateOres (1.7.10):
--   {блок, попыток, размер жилы, minY, maxY} — Y = nextInt(maxY - minY) + minY;
--   лазурит — genStandardOre2(1, 16, 16): Y = nextInt(16) + nextInt(16) + 0.
-- Земля и гравий — те же жилы того же декоратора; они стоят в оригинальном
-- порядке, иначе руды получили бы другие случайные числа.
O.RULES = {
    {DIRT,     20, 32, 0, 256},
    {GRAVEL,   10, 32, 0, 256},
    {COAL,     20, 16, 0, 128},
    {IRON,     20,  8, 0,  64},
    {GOLD,      2,  8, 0,  32},
    {REDSTONE,  8,  7, 0,  16},
    {DIAMOND,   1,  7, 0,  16},
    {LAPIS,     1,  6, "triangle", 16},
}

-- Руды участка-источника (scx, scz): все попытки по порядку, клетки — в окно.
local function decorate(rand, scx, scz, x0, x1, z0, z1, place)
    local bx, bz = scx * 16, scz * 16
    for _, rule in ipairs(O.RULES) do
        local id, count, size, minY, maxY = rule[1], rule[2], rule[3], rule[4], rule[5]
        for _ = 1, count do
            local x = bx + rand:nextInt(16)
            local y
            if minY == "triangle" then
                -- genStandardOre2: сумма двух nextInt(16) — 0..30, чаще всего около 15.
                y = rand:nextInt(maxY) + rand:nextInt(maxY)   -- центр 16 - разброс 16 = 0
            else
                y = rand:nextInt(maxY - minY) + minY
            end
            local z = bz + rand:nextInt(16)
            minable(rand, size, x, y, z, x0, x1, z0, z1, function(wx, wy, wz) place(id, wx, wy, wz) end)
        end
    end
end

-- Извлечение блока участка по локальным координатам.
local function getLocal(c, x, y, z)
    local s = c.sec[y >> 4]
    if not s then return 0 end
    return s[x + z * 16 + (y & 15) * 256 + 1] & W.ID_MASK
end

local function setLocal(c, x, y, z, id)
    local s = c.sec[y >> 4]
    local i = x + z * 16 + (y & 15) * 256 + 1
    s[i] = (s[i] & ~W.ID_MASK) | id
end

-- Руды в участке c (после рельефа и пещер). biomeOf(x, z) — биом точки мира.
-- stats (необязательно) — счётчики для самопроверки.
function O.generate(c, seed, biomeOf, stats)
    seed = math.tointeger(seed) or math.floor(seed)
    local bx, bz = c.cx * 16, c.cz * 16
    local x0, x1, z0, z1 = bx, bx + 15, bz, bz + 15
    local function place(id, wx, wy, wz)
        if wy < 0 or wy >= W.HEIGHT then return end
        local lx, lz = wx - bx, wz - bz
        -- Только камень: ни воздух, ни земля, ни гравий, ни уже стоящая руда.
        if getLocal(c, lx, wy, lz) ~= STONE then return end
        setLocal(c, lx, wy, lz, id)
        if stats then
            local s = stats[id] or {n = 0, minY = 999, maxY = -1}
            stats[id] = s
            s.n, s.minY, s.maxY = s.n + 1, math.min(s.minY, wy), math.max(s.maxY, wy)
        end
    end
    -- Жилы участка начинаются в [bx+8, bx+23] и дотягиваются не дальше чем на
    -- 2 + 3 клетки: до участка дотягиваются только он сам и соседи с меньшими
    -- номерами. Порядок фиксирован — результат один при любом порядке загрузки.
    local own
    for dz = -1, 0 do
        for dx = -1, 0 do
            local rand = O.chunkRandom(seed, c.cx + dx, c.cz + dz)
            decorate(rand, c.cx + dx, c.cz + dz, x0, x1, z0, z1, place)
            if dx == 0 and dz == 0 then own = rand end
        end
    end
    -- Изумруд (BiomeGenHills.decorate): биом участка — в точке (x+16, z+16),
    -- как populate; 3 + nextInt(6) попыток, X/Z — в самом участке (без +8),
    -- Y = nextInt(28) + 4, один блок и только вместо камня.
    local b = biomeOf(bx + 16, bz + 16)
    if b == "extreme_hills" or b == "extreme_hills_edge" then
        local tries = 3 + own:nextInt(6)
        for _ = 1, tries do
            local x = bx + own:nextInt(16)
            local y = own:nextInt(28) + 4
            local z = bz + own:nextInt(16)
            place(EMERALD, x, y, z)
        end
        if stats then stats.emeraldChunks = (stats.emeraldChunks or 0) + 1 end
    end
end

-- Самопроверка копии java.util.Random — числа сняты с настоящей Java:
--   new Random(42).nextInt(100) = 30, затем 63; new Random(0).nextLong() = -4962768465676381896;
--   new Random(1).nextFloat() = 0.7308782, nextDouble() = 0.7308781907032909;
--   случайное участка (-3, 5) при зерне 1337 (как populate): nextInt(16) = 9,
--   nextInt(256) = 198, nextFloat() = 0.5350245, nextDouble() = 0.9142619662875251, nextInt(3) = 1.
function O.selfCheckRandom()
    local r = newRandom(42)
    local a, b = r:nextInt(100), r:nextInt(100)
    local l = newRandom(0):nextLong()
    local f = newRandom(1):nextFloat()
    local d = newRandom(1):nextDouble()
    local c = O.chunkRandom(1337, -3, 5)
    local c1, c2, c3, c4, c5 = c:nextInt(16), c:nextInt(256), c:nextFloat(), c:nextDouble(), c:nextInt(3)
    local ok = a == 30 and b == 63 and l == -4962768465676381896 and math.abs(f - 0.7308782) < 1e-6
        and math.abs(d - 0.7308781907032909) < 1e-15 and c1 == 9 and c2 == 198
        and math.abs(c3 - 0.5350245) < 1e-6 and math.abs(c4 - 0.9142619662875251) < 1e-15 and c5 == 1
    return ok, string.format("java_random=%s", ok and "ok" or string.format("MIMO(%d %d %d %d %d)", a, b, c1, c2, c5))
end

return O
