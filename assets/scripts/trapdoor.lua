-- ---------------------------------------------------------------------------
-- trapdoor.lua — деревянный люк Minecraft 1.7.10 (BlockTrapDoor).
--
-- Метаданные: биты 0–1 — сторона петель (0 — опора по +Z, 1 — по −Z,
-- 2 — по +X, 3 — по −X), бит 2 — открыт, бит 3 — висит в верхней половине
-- клетки. Коробка (func_150117_e) — плита 3/16: закрытый люк лежит внизу
-- или вверху клетки, открытый стоит у опоры. Она же столкновение, выбор и
-- геометрия (mesher.lua — стандартная коробка с одной картинкой).
--
-- Ставится только на боковую грань блока (canPlaceBlockOnSide: не на верх и
-- не на низ), опора — глухой куб за ним; клик по верхней половине грани —
-- люк вверху клетки (onBlockPlaced: hitY > 0.5). ПКМ открывает и закрывает
-- (onBlockActivated: meta ^ 4) со звуком двери. Опору убрали — люк падает
-- предметом (onNeighborBlockChange).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local T = {}

local F = 0.1875
T.THICK = F
-- Клетка опоры по направлению (dx, dz от люка).
local SUPPORT = {[0] = {0, 1}, [1] = {0, -1}, [2] = {1, 0}, [3] = {-1, 0}}

local function trapId() return B.byName.trapdoor.id end
function T.isTrapdoor(id) return id == trapId() end
T.id = trapId

-- func_150117_e: коробка по метаданным.
function T.box(meta)
    local b
    if (meta & 8) ~= 0 then b = {0, 1 - F, 0, 1, 1, 1} else b = {0, 0, 0, 1, F, 1} end
    if (meta & 4) ~= 0 then
        local j = meta & 3
        if j == 0 then b = {0, 0, 1 - F, 1, 1, 1}
        elseif j == 1 then b = {0, 0, 0, 1, 1, F}
        elseif j == 2 then b = {1 - F, 0, 0, 1, 1, 1}
        else b = {0, 0, 0, F, 1, 1} end
    end
    return b
end

-- Держит ли блок люк (func_150119_a: глухой куб; у оригинала ещё светокамень,
-- плиты и ступени — их в игре нет).
local function holds(id) return B.opaque[id] == true or (B.byName.glowstone and id == B.byName.glowstone.id) end

-- onBlockPlaced: метаданные по стороне оригинала side (2..5 — грань клика
-- −Z, +Z, −X, +X) и высоте попадания hitY (0..1 в клетке). nil — нельзя:
-- верх и низ блока люк не принимают, опора должна держать.
function T.metaFor(x, y, z, side, hitY)
    if side < 2 or side > 5 then return nil end
    local j = side - 2
    local s = SUPPORT[j]
    if not holds(W.get(x + s[1], y, z + s[2])) then return nil end
    if hitY > 0.5 then j = j | 8 end
    return j
end

function T.supported(x, y, z, meta)
    local s = SUPPORT[meta & 3]
    return holds(W.get(x + s[1], y, z + s[2]))
end

-- ПКМ: открыть или закрыть, звук — один раз на переключение. true — открыт.
function T.toggle(setBlock, x, y, z)
    local m = W.meta(x, y, z) ~ 4
    setBlock(x, y, z, trapId(), m)
    local open = (m & 4) ~= 0
    require("door").sound(open, x, y, z)
    return open
end

-- Соседи клетки (x, y, z) поменялись: люки, державшиеся за неё, падают предметом.
function T.checkAround(setBlock, x, y, z)
    local id = trapId()
    for j, s in pairs(SUPPORT) do
        local tx, tz = x - s[1], z - s[2]
        if W.get(tx, y, tz) == id and (W.meta(tx, y, tz) & 3) == j and not T.supported(tx, y, tz, j) then
            setBlock(tx, y, tz, 0)
            require("drops").spawn(id, 1, tx + 0.5, y + 0.5, tz + 0.5)
        end
    end
end

-- Самопроверка (--gencheck, строка TRAPDOORCHECK): постановка на боковую
-- грань внизу и вверху, не на верх блока, коробки закрытого и открытого,
-- переключение, падение без опоры.
function T.selfCheck()
    local Act = require "interact"
    local set = Act.setBlock
    local Pn = require("player").pos
    local x, z = math.floor(Pn.x) + 6, math.floor(Pn.z) - 6
    local y = W.surface(x, z) + 2
    for yy = y - 1, y + 2 do for dx = -1, 1 do for dz = -1, 2 do W.setId(x + dx, yy, z + dz, 0) end end end
    set(x, y, z + 1, B.byName.stone.id)                  -- стена с юга (+Z)
    -- Клик по северной грани стены (сторона 2) — люк в (x, y, z), петли к +Z.
    local low = T.metaFor(x, y, z, 2, 0.3)
    local high = T.metaFor(x, y, z, 2, 0.8)
    local noTop = T.metaFor(x, y, z, 1, 0.5) == nil and T.metaFor(x, y + 2, z, 2, 0.3) == nil
    local metaOk = low == 0 and high == 8 and noTop
    set(x, y, z, trapId(), low)
    local closed = T.box(W.meta(x, y, z))
    local closedOk = closed[2] == 0 and closed[5] == F and closed[4] == 1
    T.toggle(set, x, y, z)
    local opened = T.box(W.meta(x, y, z))
    local openOk = (W.meta(x, y, z) & 4) ~= 0 and opened[3] == 1 - F and opened[6] == 1 and opened[5] == 1
    local hb = T.box(8)
    local highOk = hb[2] == 1 - F and hb[5] == 1
    set(x, y, z + 1, 0)
    T.checkAround(set, x, y, z + 1)
    local dropped = W.get(x, y, z) == 0
    -- Рецепты: 6 досок двумя столбцами по три — 3 двери, двумя рядами по
    -- три — 2 люка; дверь ставится ПКМ (не «использование» предмета).
    local R = require "crafting"
    local P = {id = B.byName.planks.id, n = 1}
    local door = R.match({P, P, nil, P, P, nil, P, P, nil}, {size = 3})
    local trap = R.match({P, P, P, P, P, P, nil, nil, nil}, {size = 3})
    local recipes = door and door.out == B.byName.wooden_door.id and door.n == 3
        and trap and trap.out == trapId() and trap.n == 2
    local placeable = not Act.isUseItem(B.byName.wooden_door) and Act.isUseItem(B.byName.bow)
    local ok = metaOk and closedOk and openOk and highOk and dropped and recipes and placeable
    return string.format("TRAPDOORCHECK: %s ориентация=%s закрыт=%s открыт=%s вверху=%s падает=%s рецепты=%s дверь_ставится=%s",
        ok and "PASS" or "FAIL", tostring(metaOk), tostring(closedOk), tostring(openOk), tostring(highOk),
        tostring(dropped), tostring(recipes), tostring(placeable))
end

return T
