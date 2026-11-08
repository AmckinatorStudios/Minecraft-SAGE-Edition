-- ---------------------------------------------------------------------------
-- ladder.lua — лестница Minecraft 1.7.10 (BlockLadder).
--
-- Плоская картинка на стене, не ступени и не объём. Метаданные 2..5 —
-- сторона, куда лестница смотрит (опора — с противоположной стороны):
--   2 — опора по +Z, 3 — по −Z, 4 — по +X, 5 — по −X.
-- Коробка — пластина 2/16 у опоры (setBlockBoundsBasedOnState, f = 0.125):
-- она же столкновение и выбор. Рисуется одной плоскостью в 0.05 от стены
-- (RenderBlocks.renderBlockLadder) — mesher.lua.
-- Подъём (EntityLivingBase.isOnLadder и moveEntityWithHeading) — player.lua.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local L = {}

local F = 0.125
-- Клетка опоры для метаданных (dx, dz от лестницы).
local SUPPORT = {[2] = {0, 1}, [3] = {0, -1}, [4] = {1, 0}, [5] = {-1, 0}}
L.SUPPORT = SUPPORT

local function ladderId() return B.byName.ladder.id end
function L.isLadder(id) return id == ladderId() end

-- Коробка пластины по метаданным.
function L.box(meta)
    if meta == 2 then return {0, 0, 1 - F, 1, 1, 1}
    elseif meta == 3 then return {0, 0, 0, 1, 1, F}
    elseif meta == 4 then return {1 - F, 0, 0, 1, 1, 1}
    elseif meta == 5 then return {0, 0, 0, F, 1, 1} end
    return {0, 0, 0, 1, 1, 1}
end

-- Держит ли блок лестницу сбоку (isSideSolid: глухой куб).
local function solid(x, y, z) return B.opaque[W.get(x, y, z)] == true end

-- onBlockPlaced: по грани клика side (2..5 — сторона оригинала: −Z, +Z, −X,
-- +X), иначе первая сторона, у которой есть опора. nil — ставить некуда
-- (canPlaceBlockAt: хоть один глухой сосед сбоку).
function L.metaFor(x, y, z, side)
    local m = 0
    if (m == 0 or side == 2) and solid(x, y, z + 1) then m = 2 end
    if (m == 0 or side == 3) and solid(x, y, z - 1) then m = 3 end
    if (m == 0 or side == 4) and solid(x + 1, y, z) then m = 4 end
    if (m == 0 or side == 5) and solid(x - 1, y, z) then m = 5 end
    if m == 0 then return nil end
    return m
end

-- Держится ли лестница (x, y, z) с метаданными meta.
function L.supported(x, y, z, meta)
    local s = SUPPORT[meta]
    return s ~= nil and solid(x + s[1], y, z + s[2])
end

-- onNeighborBlockChange: соседи клетки (x, y, z) поменялись — лестницы, что
-- держались за неё, падают предметом.
function L.checkAround(setBlock, x, y, z)
    local id = ladderId()
    for meta, s in pairs(SUPPORT) do
        local lx, lz = x - s[1], z - s[2]
        if W.get(lx, y, lz) == id and W.meta(lx, y, lz) == meta and not L.supported(lx, y, lz, meta) then
            setBlock(lx, y, lz, 0)
            require("drops").spawn(id, 1, lx + 0.5, y + 0.5, lz + 0.5)
        end
    end
end

-- Самопроверка (--gencheck, строка LADDERCHECK): ориентация по грани клика,
-- коробка у стены, поломка без опоры.
function L.selfCheck()
    local Act = require "interact"
    local set = Act.setBlock
    local Pn = require("player").pos
    local x, z = math.floor(Pn.x) - 6, math.floor(Pn.z) + 6
    local y = W.surface(x, z) + 1
    for yy = y, y + 2 do for dx = -1, 1 do for dz = -1, 1 do W.setId(x + dx, yy, z + dz, 0) end end end
    set(x, y, z - 1, B.byName.stone.id)                  -- стена с севера (−Z)
    -- Клик по южной грани стены (сторона 3) — лестница в (x, y, z), опора −Z.
    local m = L.metaFor(x, y, z, 3)
    local metaOk = m == 3 and L.metaFor(x, y + 2, z, 3) == nil
    set(x, y, z, ladderId(), m)
    local b = L.box(W.meta(x, y, z))
    local boxOk = b[3] == 0 and b[6] == F and b[4] == 1
    set(x, y, z - 1, 0)
    L.checkAround(set, x, y, z - 1)
    local dropped = W.get(x, y, z) == 0
    -- Подъём: столб лестниц у стены, игрок упирается в неё — лезет вверх
    -- со скоростью оригинала (0.1176 блока за тик ≈ 2.35 в секунду); в
    -- приседе не съезжает.
    local P = require "player"
    local save = {x = P.pos.x, y = P.pos.y, z = P.pos.z, vx = P.vel.x, vy = P.vel.y, vz = P.vel.z,
                  yaw = P.yaw, flying = P.flying, onGround = P.onGround}
    for yy = y, y + 6 do
        set(x, yy, z - 1, B.byName.stone.id)
        set(x, yy, z, ladderId(), 3)
    end
    P.flying = false
    P.pos.x, P.pos.y, P.pos.z = x + 0.5, y + 0.01, z + F + P.WIDTH / 2 + 0.01
    P.vel.x, P.vel.y, P.vel.z = 0, 0, 0
    P.yaw = 0
    local y0 = P.pos.y
    for _ = 1, 20 do P.update({forward = 1, strafe = 0}, 0.05) end
    local rise = P.pos.y - y0
    local climbOk = rise > 1.9 and rise < 2.6
    local y1 = P.pos.y
    for _ = 1, 20 do P.update({forward = 0, strafe = 0, sneak = true}, 0.05) end
    local holdOk = P.pos.y >= y1 - 0.01   -- не съезжает (вверх ещё донесёт разгон)
    for yy = y, y + 6 do set(x, yy, z, 0); set(x, yy, z - 1, 0) end
    P.pos.x, P.pos.y, P.pos.z = save.x, save.y, save.z
    P.vel.x, P.vel.y, P.vel.z = save.vx, save.vy, save.vz
    P.yaw, P.flying, P.onGround, P.sneaking = save.yaw, save.flying, save.onGround, false
    local ok = metaOk and boxOk and dropped and climbOk and holdOk
    return string.format("LADDERCHECK: %s ориентация=%s коробка=%s падает=%s подъём=%.2f присед=%s",
        ok and "PASS" or "FAIL", tostring(metaOk), tostring(boxOk), tostring(dropped), rise, tostring(holdOk))
end

return L
