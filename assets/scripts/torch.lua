-- ---------------------------------------------------------------------------
-- torch.lua — факел Minecraft 1.7.10 (BlockTorch): на полу и на стене.
--
-- Ориентация — метаданные блока: 1 — опора по X− (факел на её восточной
-- стороне), 2 — опора по X+, 3 — по Z−, 4 — по Z+, 5 — стоит на полу.
-- Ставится только на сторону, которая держит (isSideSolid: глухой блок; пол
-- — ещё и стекло, func_150107_m). Опору убрали — факел выпадает предметом.
--
-- Модель (RenderBlocks.renderTorchAtAngle) — мешер; здесь: рамка выбора
-- (setBlockBoundsBasedOnState — коллизии у факела нет), направление опоры и
-- частицы: огонь и дым у вершины (randomDisplayTick: (0.5, 0.7, 0.5), у
-- настенного — ещё +0.22 вверх и 0.27 от стены). Как у оригинала, частицы
-- рождаются у случайных клеток вокруг игрока: 1000 проб за тик, смещение
-- по каждой оси rand(16) − rand(16) (WorldClient.doVoidFogParticles).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local T = {}

local function torchId() return B.byName.torch.id end
T.FLOOR = 5

-- Клетка опоры для ориентации meta (dx, dy, dz от факела).
local SUPPORT = {[1] = {-1, 0, 0}, [2] = {1, 0, 0}, [3] = {0, 0, -1}, [4] = {0, 0, 1}, [5] = {0, -1, 0}}
T.SUPPORT = SUPPORT

-- Держит ли блок id факел этой стороной.
local function holds(id, floor)
    if B.opaque[id] then return true end
    return floor and B.byId[id] and B.byId[id].name == "glass" or false
end

-- Держится ли факел (x, y, z) с ориентацией meta.
function T.supported(x, y, z, meta)
    local s = SUPPORT[meta] or SUPPORT[5]
    return holds(W.get(x + s[1], y + s[2], z + s[3]), meta == 5 or SUPPORT[meta] == nil)
end

-- BlockTorch.onBlockPlaced по грани n клика (нормаль от блока к факелу);
-- нижняя грань — первая подходящая (onBlockAdded). nil — ставить некуда.
function T.metaFor(x, y, z, nx, ny, nz)
    local want
    if ny == 1 then want = 5
    elseif nx == 1 then want = 1
    elseif nx == -1 then want = 2
    elseif nz == 1 then want = 3
    elseif nz == -1 then want = 4 end
    if want and T.supported(x, y, z, want) then return want end
    for _, m in ipairs({1, 2, 3, 4, 5}) do
        if T.supported(x, y, z, m) then return m end
    end
    return nil
end

-- Рамка выбора в долях клетки: {x0, y0, z0, x1, y1, z1}.
function T.bounds(meta)
    local f = 0.15
    if meta == 1 then return {0, 0.2, 0.5 - f, f * 2, 0.8, 0.5 + f}
    elseif meta == 2 then return {1 - f * 2, 0.2, 0.5 - f, 1, 0.8, 0.5 + f}
    elseif meta == 3 then return {0.5 - f, 0.2, 0, 0.5 + f, 0.8, f * 2}
    elseif meta == 4 then return {0.5 - f, 0.2, 1 - f * 2, 0.5 + f, 0.8, 1} end
    f = 0.1
    return {0.5 - f, 0, 0.5 - f, 0.5 + f, 0.6, 0.5 + f}
end

-- Соседи клетки (x, y, z) поменялись: факелы, державшиеся за неё, падают
-- предметом (onNeighborBlockChange -> func_150108_b).
function T.checkAround(x, y, z)
    for meta, s in pairs(SUPPORT) do
        -- Факел, чья опора — эта клетка, стоит по другую сторону от неё.
        local tx, ty, tz = x - s[1], y - s[2], z - s[3]
        if W.get(tx, ty, tz) == torchId() then
            local m = W.meta(tx, ty, tz)
            if m == 0 then m = 5 end
            if m == meta and not T.supported(tx, ty, tz, m) then
                require("interact").setBlock(tx, ty, tz, 0)
                require("drops").spawn(torchId(), 1, tx + 0.5, ty + 0.5, tz + 0.5)
            end
        end
    end
end

-- --- Частицы ---------------------------------------------------------------

-- Огонёк и дым — частицы движка (pfx.lua, виды «flame» и «smoke»): полёт,
-- кадры дыма и таяние огня считает система частиц, здесь — числа рождения.
local Pf = require "pfx"

local function spawn(kind, x, y, z)
    local r = math.random
    if kind == "flame" then
        -- EntityFlameFX: скорость почти ноль, 8/(r·0.8+0.2)+4 тиков, тает.
        Pf.spawn("flame", {{x = x, y = y, z = z,
            vx = (r() * 2 - 1) * 0.01 * 0.2, vy = (r() * 2 - 1) * 0.01 * 0.2, vz = (r() * 2 - 1) * 0.01 * 0.2,
            life = math.floor(8 / (r() * 0.8 + 0.2)) + 4,
            size = (r() * 0.5 + 0.5) * 2 * 0.1 * 2}})
    else
        -- EntitySmokeFX: всплывает (+0.004 за тик), кадры 7..0, серый
        -- (particleRed = G = B = rand·0.3).
        local g = r() * 0.3
        Pf.spawn("smoke", {{x = x, y = y, z = z,
            vx = (r() * 2 - 1) * 0.1 * 0.1, vy = (r() * 2 - 1) * 0.1 * 0.1, vz = (r() * 2 - 1) * 0.1 * 0.1,
            life = math.floor(8 / (r() * 0.8 + 0.2)),
            size = (r() * 0.5 + 0.5) * 2 * 0.1 * 0.75 * 2,
            r = g, g = g, b = g}})
    end
end

-- randomDisplayTick факела в (x, y, z).
local function display(x, y, z)
    local m = W.meta(x, y, z)
    local d0, d1, d2 = x + 0.5, y + 0.7, z + 0.5
    local d3, d4 = 0.22, 0.27
    if m == 1 then d0, d1 = d0 - d4, d1 + d3
    elseif m == 2 then d0, d1 = d0 + d4, d1 + d3
    elseif m == 3 then d2, d1 = d2 - d4, d1 + d3
    elseif m == 4 then d2, d1 = d2 + d4, d1 + d3 end
    spawn("smoke", d0, d1, d2)
    spawn("flame", d0, d1, d2)
end

local acc = 0
function T.update(dt, P)
    acc = acc + dt
    local id = torchId()
    local n = 0
    while acc >= 0.05 and n < 4 do
        acc, n = acc - 0.05, n + 1
        if P then
            local px, py, pz = math.floor(P.pos.x), math.floor(P.pos.y), math.floor(P.pos.z)
            local rnd = math.random
            for _ = 1, 1000 do
                local x = px + rnd(0, 15) - rnd(0, 15)
                local y = py + rnd(0, 15) - rnd(0, 15)
                local z = pz + rnd(0, 15) - rnd(0, 15)
                if W.get(x, y, z) == id then display(x, y, z) end
            end
        end
    end
end

-- Сколько частиц сейчас (для проверок).
function T.count() return Pf.count("flame") + Pf.count("smoke") end
T.display = display

-- Самопроверка (--gencheck, строка TORCHCHECK): ориентация по грани,
-- опора, падение без опоры, рамка выбора.
function T.selfCheck()
    local Act = require "interact"
    local x, z = 60, 60
    local y = W.surface(x, z) + 1
    local stone = B.byName.stone.id
    for yy = y, y + 3 do for dx = -1, 3 do W.setId(x + dx, yy, z, 0) end end
    Act.setBlock(x + 1, y + 1, z, stone)                  -- стена
    -- Клик по грани X− стены (нормаль −X): факел в x, опора по X+ — meta 2.
    local m = T.metaFor(x, y + 1, z, -1, 0, 0)
    local onWall = m == 2
    Act.setBlock(x, y + 1, z, torchId(), m)
    local stays = W.get(x, y + 1, z) == torchId() and W.meta(x, y + 1, z) == 2
    -- В воздухе (нет опоры ни с одной стороны) — ставить некуда.
    local nowhere = T.metaFor(x - 1, y + 3, z, 0, 1, 0) == nil
    -- Убрали стену — факел падает предметом.
    Act.setBlock(x + 1, y + 1, z, 0)
    T.checkAround(x + 1, y + 1, z)
    local dropped = W.get(x, y + 1, z) == 0
    local b = T.bounds(2)
    local box = math.abs(b[1] - 0.7) < 1e-6 and b[4] == 1 and b[2] == 0.2 and b[5] == 0.8
    local ok = onWall and stays and nowhere and dropped and box
    return string.format("TORCHCHECK: %s на_стену=%s держится=%s в_воздухе=%s падает=%s рамка=%s",
        ok and "PASS" or "FAIL", tostring(onWall), tostring(stays), tostring(nowhere), tostring(dropped), tostring(box))
end

return T
