-- ---------------------------------------------------------------------------
-- bounds.lua — границы блока (Block 1.7.10): три независимые системы.
--
--   collision(id, meta) — список коробок столкновения
--                         (getCollisionBoundingBoxFromPool / addCollisionBoxesToList:
--                         у сложных блоков — несколько коробок, у факела и
--                         растений — ни одной);
--   selected(id, meta)  — коробка выбора: в неё попадает прицел, по ней рисуется
--                         рамка (getSelectedBoundingBoxFromPool);
--   render(id, meta)    — границы геометрии (renderMinX…): по ним кладутся
--                         трещины и рождаются частицы удара.
--
-- Коробка — {minX, minY, minZ, maxX, maxY, maxZ} в долях клетки (0..1, может
-- выходить за клетку). Все три считаются по метаданным при каждом вызове:
-- поменялось состояние блока — поменялись и границы, кэша, который надо
-- сбрасывать, нет. Новая форма — запись в SHAPES, а не ветка в физике,
-- прицеле и рамке по отдельности.
-- ---------------------------------------------------------------------------
local B = require "blocks"

local Bo = {}

local FULL = {0, 0, 0, 1, 1, 1}
local NONE = {}
Bo.FULL = FULL

-- Растения (BlockBush.setBlockBounds(0.5 − f, 0, 0.5 − f, 0.5 + f, f·3, 0.5 + f)
-- у цветов f = 0.2; высокая трава и саженцы — 0.4 (0.8 в высоту); тростник —
-- 0.375 во всю высоту).
local function bush(f, h) return {0.5 - f, 0, 0.5 - f, 0.5 + f, h or f * 3, 0.5 + f} end

-- Форма блока: функции от meta. Нет записи — по виду отрисовки.
local SHAPES = {}

local function shape(name, s) SHAPES[B.byName[name].id] = s end

for _, n in ipairs({"rose", "dandelion"}) do
    shape(n, {selected = function() return bush(0.2) end, collision = function() return NONE end})
end
for _, n in ipairs({"tallgrass", "oak_sapling", "spruce_sapling", "birch_sapling", "jungle_sapling",
                    "acacia_sapling", "dark_oak_sapling"}) do
    shape(n, {selected = function() return bush(0.4, 0.8) end, collision = function() return NONE end})
end
shape("reeds", {selected = function() return bush(0.375, 1) end, collision = function() return NONE end})

-- Кактус (BlockCactus): столкновение на 1/16 уже и ниже (на нём стоят, но в
-- него «упираются» — урон от касания), выбор и вид — на 1/16 уже, во всю высоту.
local CI = 1 / 16
shape("cactus", {
    selected = function() return {CI, 0, CI, 1 - CI, 1, 1 - CI} end,
    collision = function() return {{CI, 0, CI, 1 - CI, 1 - CI, 1 - CI}} end,
    render = function() return {CI, 0, CI, 1 - CI, 1, 1 - CI} end,
})

-- Факел (BlockTorch): столкновения нет, выбор — по ориентации (torch.lua).
shape("torch", {
    selected = function(meta) return require("torch").bounds(meta) end,
    collision = function() return NONE end,
})

local function kind(id) return B.drawKind[id] end

-- Коробка выбора; nil — блок не выбирается (воздух, жидкость).
function Bo.selected(id, meta)
    if id == 0 or kind(id) == 4 then return nil end
    local s = SHAPES[id]
    if s and s.selected then return s.selected(meta or 0) end
    return FULL
end

-- Коробки столкновения (список; пустой — сквозь блок проходят).
function Bo.collision(id, meta)
    if id == 0 then return NONE end
    local s = SHAPES[id]
    if s and s.collision then return s.collision(meta or 0) end
    if not B.solid[id] then return NONE end
    return {FULL}
end

-- Границы геометрии: трещины, частицы удара. У растений и факела — их коробка
-- выбора (setBlockBoundsBasedOnState у оригинала задаёт одно и то же).
function Bo.render(id, meta)
    local s = SHAPES[id]
    if s and s.render then return s.render(meta or 0) end
    return Bo.selected(id, meta) or FULL
end

-- Полный куб столкновения без особой формы — быстрый путь физики.
function Bo.isFullCollision(id)
    return B.solid[id] and not SHAPES[id]
end

-- Пересекает ли коробка {x0, y0, z0, x1, y1, z1} (мировая) столкновения блока
-- в клетке (cx, cy, cz).
function Bo.overlaps(id, meta, cx, cy, cz, x0, y0, z0, x1, y1, z1)
    if Bo.isFullCollision(id) then
        return x1 > cx and x0 < cx + 1 and y1 > cy and y0 < cy + 1 and z1 > cz and z0 < cz + 1
    end
    for _, b in ipairs(Bo.collision(id, meta)) do
        if x1 > cx + b[1] and x0 < cx + b[4] and y1 > cy + b[2] and y0 < cy + b[5]
            and z1 > cz + b[3] and z0 < cz + b[6] then return true end
    end
    return false
end

-- Луч (o + d·t) и коробка в клетке (slab-метод): t входа и нормаль грани
-- входа; nil — мимо.
function Bo.rayBox(box, cx, cy, cz, ox, oy, oz, dx, dy, dz, maxDist)
    local tmin, tmax, fn = -math.huge, math.huge, {0, 0, 0}
    local O, D, C = {ox, oy, oz}, {dx, dy, dz}, {cx, cy, cz}
    for axis = 1, 3 do
        local o, d = O[axis], D[axis]
        local lo, hi = C[axis] + box[axis], C[axis] + box[axis + 3]
        if math.abs(d) < 1e-9 then
            if o < lo or o > hi then return nil end
        else
            local t1, t2 = (lo - o) / d, (hi - o) / d
            local n = -1
            if t1 > t2 then t1, t2, n = t2, t1, 1 end
            if t1 > tmin then
                tmin = t1
                fn = {0, 0, 0}
                fn[axis] = n
            end
            if t2 < tmax then tmax = t2 end
        end
    end
    if tmin <= tmax and tmax >= 0 and tmin <= maxDist then return math.max(0, tmin), fn end
    return nil
end

-- Самопроверка (--gencheck, строка BOUNDSCHECK): три системы независимы.
function Bo.selfCheck()
    local torch, rose, cactus, stone = B.byName.torch.id, B.byName.rose.id, B.byName.cactus.id, B.byName.stone.id
    local torchSel = Bo.selected(torch, 2)
    local torchOk = #Bo.collision(torch, 2) == 0 and torchSel[1] > 0.5 and Bo.selected(torch, 5)[5] < 0.7
    local roseOk = #Bo.collision(rose, 0) == 0 and math.abs(Bo.selected(rose, 0)[5] - 0.6) < 1e-6
    local cc, cs = Bo.collision(cactus, 0)[1], Bo.selected(cactus, 0)
    local cactusOk = cc[5] < 1 and cs[5] == 1 and cc[1] > 0
    local stoneOk = Bo.selected(stone, 0) == FULL and #Bo.collision(stone, 0) == 1
    local waterOk = Bo.selected(B.byName.water.id, 0) == nil and #Bo.collision(B.byName.water.id, 0) == 0
    local ok = torchOk and roseOk and cactusOk and stoneOk and waterOk
    return string.format("BOUNDSCHECK: %s факел=%s цветок=%s кактус=%s камень=%s вода=%s", ok and "PASS" or "FAIL",
        tostring(torchOk), tostring(roseOk), tostring(cactusOk), tostring(stoneOk), tostring(waterOk))
end

return Bo
