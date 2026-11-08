-- ---------------------------------------------------------------------------
-- crops.lua — пшеница и грядки по правилам Minecraft 1.7.10.
--
-- МОТЫГА (ItemHoe.onItemUse): ПКМ по любой грани, кроме нижней, земли или
-- травы, над которой воздух, — грядка с влажностью 0, звук шага гравия
-- (громкость 1, тон 0.8), износ мотыги на 1.
--
-- ГРЯДКА (BlockFarmland). Метаданные — влажность 0..7. Случайный тик: вода
-- в квадрате 9×9 на той же высоте или на блок выше, или дождь над клеткой
-- (canLightningStrikeAt) — влажность 7; иначе влажность − 1, а сухая
-- (0) без посевов сверху — снова земля. Твёрдый блок сверху — тоже земля.
-- Падение на грядку: шанс fallDistance − 0.5 вытоптать (onFallenUpon).
--
-- ПШЕНИЦА (BlockCrops). Метаданные — стадия 0..7. Случайный тик: сначала
-- canBlockStay (грядка под ней, свет ≥ 8 или открытое небо) — нет, ломается
-- с выпадением; затем при свете ≥ 9 над растением и стадии < 7 —
-- rand((int)(25 / f) + 1) == 0 → стадия + 1, где f — func_149864_n:
-- 1 + грядка под собой (сухая 1, влажная 3) + грядки 3×3 вокруг по четверти,
-- и пополам, если пшеница стоит по диагонали или с двух перпендикулярных
-- сторон сразу. Выпадение: стадия < 7 — одно семя; 7 — пшеница и три
-- попытки семени по 8/15 (rand(15) ≤ 7). Костная мука — +2..5 стадий.
--
-- Случайный тик — как у мира 1.7.10: 3 клетки на секцию 16³ за игровой тик
-- (шанс 3/4096 у клетки). Клетки грядок и посевов помнятся списком (их
-- ставит только игрок), состояние — в метаданных клетки (правки участка).
-- Звуки: вспашка — step.gravel, посадка — step.grass, сбор — dig.grass,
-- шаги по грядке — гравий; у роста звука нет (у 1.7.10 его нет).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local Cr = {}

local cells = {}
Cr.stats = {grown = 0, dried = 0, wetted = 0, reverted = 0}

local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function unkey(k)
    local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
    return tonumber(x), tonumber(y), tonumber(z)
end
local function rnd(n) return math.random(0, n - 1) end
local function act() return require "interact" end

Cr.FARMLAND = B.byName.farmland.id
Cr.WHEAT = B.byName.wheat_crop.id
local DIRT, GRASS = B.byName.dirt.id, B.byName.grass.id

function Cr.isFarmland(id) return id == Cr.FARMLAND end
function Cr.isCrop(id) return id == Cr.WHEAT end

-- Метаданные без перестройки света (у роста и влажности свет тот же).
local function setMeta(x, y, z, m)
    W.setMeta(x, y, z, m)
    require("chunks").recordEdit(x, y, z, W.get(x, y, z), m)
    W.markDirty(x, y, z)
end
Cr.setMeta = setMeta

-- Свет клетки с учётом времени суток (World.getBlockLightValue) и без него
-- (getFullBlockLightValue).
local function lightAt(x, y, z)
    local Sky = require "sky"
    local sub = Sky.skylightSubtracted(Sky.angle or 0, Sky.rain or 0, Sky.thunder or 0)
    return math.max((W.sky(x, y, z) or 15) - sub, W.blockLight(x, y, z) or 0)
end
local function fullLight(x, y, z) return math.max(W.sky(x, y, z) or 15, W.blockLight(x, y, z) or 0) end

-- Над клеткой нет ничего твёрдого и жидкого до неба (canBlockSeeTheSky и
-- getPrecipitationHeight разом).
local function openSky(x, y, z)
    for yy = y, W.HEIGHT - 1 do
        local id = W.get(x, yy, z)
        if id ~= 0 and (B.solid[id] or B.drawKind[id] == 4 or B.opaque[id]) then return false end
    end
    return true
end
Cr.openSky = openSky

-- Идёт ли дождь в клетке (World.canLightningStrikeAt): дождь, открытое небо,
-- биом с дождём (не пустыня и не снег).
function Cr.rainAt(x, y, z)
    if require("weather").rainStrength(1) <= 0.2 then return false end
    if not openSky(x, y, z) then return false end
    local _, biome = require("gen").column(x, z)
    return biome ~= "desert" and biome ~= "snow"
end

-- func_149874_m: вода в x ± 4, z ± 4 на высоте клетки или на 1 выше.
function Cr.waterNear(x, y, z)
    for wx = x - 4, x + 4 do
        for wy = y, y + 1 do
            for wz = z - 4, z + 4 do
                if B.drawKind[W.get(wx, wy, wz)] == 4 then return true end
            end
        end
    end
    return false
end

-- --- Учёт клеток -------------------------------------------------------------

local function track(x, y, z) cells[key(x, y, z)] = true end

-- Пшеница ломается с выпадением (checkAndDropBlock → dropBlockAsItem).
function Cr.dropsOf(stage)
    local seeds, wheat = B.byName.wheat_seeds.id, B.byName.wheat.id
    if stage < 7 then return {{seeds, 1}} end
    local out = {{wheat, 1}}
    for _ = 1, 3 do
        if rnd(15) <= stage then out[#out + 1] = {seeds, 1} end
    end
    return out
end

local function breakCrop(x, y, z)
    local stage = W.meta(x, y, z)
    act().setBlock(x, y, z, 0)
    require("plants").spill(Cr.dropsOf(stage), x, y, z)
end
Cr.breakCrop = breakCrop

-- Клетка (x, y, z) стала блоком id (Act.setBlock): учёт и соседи —
-- onNeighborBlockChange грядки (твёрдое сверху — земля) и пшеницы (нет
-- грядки снизу — ломается).
function Cr.onSet(x, y, z, id)
    if id == Cr.FARMLAND or id == Cr.WHEAT then track(x, y, z) end
    if W.get(x, y - 1, z) == Cr.FARMLAND and id ~= 0 and B.solid[id] then
        act().setBlock(x, y - 1, z, DIRT)
    end
    if W.get(x, y + 1, z) == Cr.WHEAT and id ~= Cr.FARMLAND then breakCrop(x, y + 1, z) end
end

-- --- Случайные тики ----------------------------------------------------------

-- BlockFarmland.updateTick.
function Cr.farmlandTick(x, y, z)
    if Cr.waterNear(x, y, z) or Cr.rainAt(x, y + 1, z) then
        if W.meta(x, y, z) ~= 7 then Cr.stats.wetted = Cr.stats.wetted + 1 end
        setMeta(x, y, z, 7)
        return
    end
    local m = W.meta(x, y, z)
    if m > 0 then
        setMeta(x, y, z, m - 1)
        Cr.stats.dried = Cr.stats.dried + 1
    elseif W.get(x, y + 1, z) ~= Cr.WHEAT then
        act().setBlock(x, y, z, DIRT)
        Cr.stats.reverted = Cr.stats.reverted + 1
    end
end

-- func_149864_n — скорость роста пшеницы в (x, y, z).
function Cr.growthRate(x, y, z)
    local f = 1.0
    local w = Cr.WHEAT
    local zN, zS = W.get(x, y, z - 1), W.get(x, y, z + 1)
    local xW, xE = W.get(x - 1, y, z), W.get(x + 1, y, z)
    local d1, d2 = W.get(x - 1, y, z - 1), W.get(x + 1, y, z - 1)
    local d3, d4 = W.get(x + 1, y, z + 1), W.get(x - 1, y, z + 1)
    local alongX = xW == w or xE == w
    local alongZ = zN == w or zS == w
    local diag = d1 == w or d2 == w or d3 == w or d4 == w
    for gx = x - 1, x + 1 do
        for gz = z - 1, z + 1 do
            local f1 = 0
            if W.get(gx, y - 1, gz) == Cr.FARMLAND then
                f1 = 1
                if W.meta(gx, y - 1, gz) > 0 then f1 = 3 end
            end
            if gx ~= x or gz ~= z then f1 = f1 / 4 end
            f = f + f1
        end
    end
    if diag or (alongX and alongZ) then f = f / 2 end
    return f
end

-- Граница броска: rand(bound) == 0 — рост. (int)(25 / f) — отбрасывание дроби.
function Cr.growBound(f) return math.floor(25 / f) + 1 end

-- canBlockStay: грядка под ней, свет ≥ 8 или открытое небо.
function Cr.canStay(x, y, z)
    if W.get(x, y - 1, z) ~= Cr.FARMLAND then return false end
    return fullLight(x, y, z) >= 8 or openSky(x, y + 1, z)
end

-- BlockCrops.updateTick.
function Cr.cropTick(x, y, z)
    if not Cr.canStay(x, y, z) then breakCrop(x, y, z); return end
    if lightAt(x, y + 1, z) < 9 then return end
    local m = W.meta(x, y, z)
    if m >= 7 then return end
    if rnd(Cr.growBound(Cr.growthRate(x, y, z))) == 0 then
        setMeta(x, y, z, m + 1)
        Cr.stats.grown = Cr.stats.grown + 1
    end
end

-- Случайный тик клетки (если там всё ещё грядка или пшеница).
function Cr.randomTick(x, y, z)
    local id = W.get(x, y, z)
    if id == Cr.FARMLAND then Cr.farmlandTick(x, y, z)
    elseif id == Cr.WHEAT then Cr.cropTick(x, y, z)
    else cells[key(x, y, z)] = nil end
end

local CHANCE = 3 / 4096
local acc = 0
local function tick()
    local list = {}
    for k in pairs(cells) do list[#list + 1] = k end
    for _, k in ipairs(list) do
        if math.random() < CHANCE then
            local x, y, z = unkey(k)
            local c = W.chunk(x // 16, z // 16)
            if c and c.lit then Cr.randomTick(x, y, z) end
        end
    end
end

function Cr.update(dt)
    acc = acc + dt
    local n = 0
    while acc >= 0.05 and n < 10 do
        acc, n = acc - 0.05, n + 1
        tick()
    end
end

-- --- Игрок --------------------------------------------------------------------

-- Мотыга по клетке t (цель прицела). true — вспахано.
function Cr.till(t)
    if t.ny == -1 then return false end
    if t.id ~= DIRT and t.id ~= GRASS then return false end
    if W.get(t.x, t.y + 1, t.z) ~= 0 then return false end
    act().setBlock(t.x, t.y, t.z, Cr.FARMLAND, 0)
    require("sounds").till(t.x, t.y, t.z)
    return true
end

-- Семена (ItemSeeds.onItemUse): только верх грядки, над ней — воздух.
function Cr.plant(t)
    if t.ny ~= 1 or t.id ~= Cr.FARMLAND then return false end
    if W.get(t.x, t.y + 1, t.z) ~= 0 then return false end
    act().setBlock(t.x, t.y + 1, t.z, Cr.WHEAT, 0)
    require("sounds").plant(t.x, t.y + 1, t.z)
    return true
end

-- ПКМ предметом held по цели t: мотыга или семена. true — сработало
-- (предмет потрачен или изношен, рука махнула).
function Cr.use(t, held)
    local d = held and B.byId[held.id]
    if not d or not t then return false end
    local Inv = require "inventory"
    if d.tool == "hoe" then
        if Cr.till(t) then Inv.wearTool(); return true end
        return false
    end
    if d.plants then
        if Cr.plant(t) then Inv.useOne(); return true end
    end
    return false
end

-- Костная мука по пшенице (BlockCrops.func_149853_b): + rand(2..5), не выше 7.
function Cr.boneMeal(x, y, z)
    if W.get(x, y, z) ~= Cr.WHEAT then return false end
    local m = W.meta(x, y, z)
    if m >= 7 then return false end
    setMeta(x, y, z, math.min(7, m + 2 + rnd(4)))
    return true
end

-- Вытаптывание (BlockFarmland.onFallenUpon): rand < высота падения − 0.5.
function Cr.fallenUpon(x, y, z, fall)
    if W.get(x, y, z) ~= Cr.FARMLAND then return false end
    if math.random() < fall - 0.5 then
        act().setBlock(x, y, z, DIRT)
        return true
    end
    return false
end

-- --- Сохранение -----------------------------------------------------------------

function Cr.save()
    local out = {}
    for k in pairs(cells) do out[#out + 1] = k end
    return out
end

function Cr.load(list)
    cells = {}
    if type(list) ~= "table" then return end
    for _, k in pairs(list) do cells[k] = true end
end

function Cr.tracked(x, y, z) return cells[key(x, y, z)] == true end

return Cr
