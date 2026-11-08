-- ---------------------------------------------------------------------------
-- particles.lua — осколки блоков: EffectRenderer и EntityDiggingFX 1.7.10.
--
-- Два эффекта с разными условиями, а не один «взрыв крошек»:
--   destroy(...) — блок разрушен (addBlockDestroyEffects): ровно 64 осколка
--                  сеткой 4×4×4 по объёму блока, скорость — от центра наружу;
--   hit(...)     — удар по блоку (addBlockHitEffects, каждый тик добычи): один
--                  маленький осколок у грани удара, на 0.1 от поверхности.
-- Трещины на самом блоке — не здесь (interact.lua, Breaking Overlay).
--
-- Осколок — квадрат, повёрнутый к камере (sprite.vert), с кусочком 4×4
-- пикселя текстуры стороны блока из атласа блоков (слой 1 EffectRenderer).
-- Материал прозрачный: проверка глубины есть, записи глубины нет, смешение
-- SRC_ALPHA, ONE_MINUS_SRC_ALPHA. Физика — по игровым тикам (20 в секунду),
-- положение на экране — между двумя тиками (иначе при 60 FPS дёргается).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local A = require "atlas"
local Bo = require "bounds"
local Light = require "lightmap"

local Pt = {}

local MAT = "assets/materials/particle_digging.sagemat"
local TICK = 1 / 20
local list = {}
local acc = 0
local meshes = {}
local rnd = math.random

-- Сторона 0..5 (вниз, вверх, Z−, Z+, X−, X+) — плитка блока этой стороны.
local function tileOfSide(id, side)
    local t = A.blockTiles[id]
    if not t then return nil end
    if side == 0 then return t.bottom or t.side end
    if side == 1 then return t.top or t.side end
    return t.side
end
Pt.tileOfSide = tileOfSide

-- Сторона по нормали грани удара.
function Pt.sideOf(nx, ny, nz)
    if ny < 0 then return 0 elseif ny > 0 then return 1
    elseif nz < 0 then return 2 elseif nz > 0 then return 3
    elseif nx < 0 then return 4 end
    return 5
end

-- Квадрат с кусочком плитки: 4×4 пикселя из 16 со сдвигом (jx, jy) пикселей
-- от левого верхнего угла (particleTextureJitterX/Y · 4). Квадраты общие —
-- по плитке и сдвигу.
local function quad(tile, jx, jy)
    local key = tile * 256 + jx * 16 + jy
    if meshes[key] then return meshes[key] end
    local tu, tv, ts = A.tileOrigin(tile)
    local u0 = tu + jx / 16 * ts
    local u1 = u0 + ts / 4
    local v1 = tv + ts - jy / 16 * ts       -- атлас: v растёт вверх
    local v0 = v1 - ts / 4
    local m = mesh()
    m.arrays{position = {-1, 0, -1, 1, 0, -1, 1, 0, 1, -1, 0, 1}, uv = {u0, v0, u1, v0, u1, v1, u0, v1},
             index = {1, 2, 3, 1, 3, 4}}
    meshes[key] = m
    return m
end

-- EntityFX(world, x, y, z, vx, vy, vz) + EntityDiggingFX: скорость — заданная
-- плюс случайная, приведённая к длине (rand + rand + 1)·0.15·0.4, вверх ещё
-- 0.1; жизнь 4/(rand·0.9 + 0.1) тиков; размер (rand·0.5 + 0.5)·2, у осколка
-- вдвое меньше; серый 0.6; тяжесть блока 1.
local function spawn(id, side, x, y, z, vx, vy, vz)
    local tile = tileOfSide(id, side)
    if not tile then return nil end
    local mx = vx + (rnd() * 2 - 1) * 0.4
    local my = vy + (rnd() * 2 - 1) * 0.4
    local mz = vz + (rnd() * 2 - 1) * 0.4
    local f = (rnd() + rnd() + 1) * 0.15
    local len = math.sqrt(mx * mx + my * my + mz * mz)
    if len < 1e-6 then len = 1 end
    mx, my, mz = mx / len * f * 0.4, my / len * f * 0.4 + 0.1, mz / len * f * 0.4
    local p = {
        x = x, y = y, z = z, px = x, py = y, pz = z,
        vx = mx, vy = my, vz = mz,
        age = 0, maxAge = math.floor(4 / (rnd() * 0.9 + 0.1)),
        scale = (rnd() * 0.5 + 0.5) * 2 / 2,
        gravity = 1, half = 0.1,
        tile = tile, jx = math.floor(rnd() * 3 * 4), jy = math.floor(rnd() * 3 * 4),
    }
    p.obj = SpawnObject("Digging FX")
    quad(p.tile, p.jx, p.jy).apply(p.obj)
    SetMaterial(p.obj, MAT)
    list[#list + 1] = p
    return p
end

-- Блок разрушен: 4×4×4 осколка, центры в (i + 0.5)/4 по каждой оси, скорость
-- — от центра блока к осколку; сторона текстуры — случайная.
function Pt.destroy(id, meta, x, y, z)
    if B.drawKind[id] == 4 or not A.blockTiles[id] then return 0 end
    local n = 0
    for i = 0, 3 do
        for j = 0, 3 do
            for k = 0, 3 do
                local px, py, pz = x + (i + 0.5) / 4, y + (j + 0.5) / 4, z + (k + 0.5) / 4
                if spawn(id, rnd(0, 5), px, py, pz, px - x - 0.5, py - y - 0.5, pz - z - 0.5) then n = n + 1 end
            end
        end
    end
    return n
end

-- Удар по грани side: точка — случайная внутри границ блока (без полосы 0.1 у
-- краёв), по оси грани — на 0.1 снаружи поверхности; скорость ×0.2
-- (multiplyVelocity: по вертикали (v − 0.1)·0.2 + 0.1), размер ×0.6.
function Pt.hit(id, meta, x, y, z, side)
    if B.drawKind[id] == 4 then return nil end
    local b = Bo.render(id, meta)
    local f = 0.1
    local px = x + rnd() * (b[4] - b[1] - f * 2) + f + b[1]
    local py = y + rnd() * (b[5] - b[2] - f * 2) + f + b[2]
    local pz = z + rnd() * (b[6] - b[3] - f * 2) + f + b[3]
    if side == 0 then py = y + b[2] - f
    elseif side == 1 then py = y + b[5] + f
    elseif side == 2 then pz = z + b[3] - f
    elseif side == 3 then pz = z + b[6] + f
    elseif side == 4 then px = x + b[1] - f
    elseif side == 5 then px = x + b[4] + f end
    local p = spawn(id, side, px, py, pz, 0, 0, 0)
    if not p then return nil end
    p.vx, p.vy, p.vz = p.vx * 0.2, (p.vy - 0.1) * 0.2 + 0.1, p.vz * 0.2
    p.scale = p.scale * 0.6
    p.half = 0.1 * 0.6
    return p
end

-- Пересекает ли коробка осколка блоки (их коробки столкновения).
local function blocked(x0, y0, z0, x1, y1, z1)
    for by = math.floor(y0) - 1, math.floor(y1) do
        for bz = math.floor(z0), math.floor(z1) do
            for bx = math.floor(x0), math.floor(x1) do
                local id = W.get(bx, by, bz)
                if id ~= 0 and Bo.overlaps(id, W.meta(bx, by, bz), bx, by, bz, x0, y0, z0, x1, y1, z1) then
                    return true
                end
            end
        end
    end
    return false
end

-- Entity.moveEntity: оси по очереди (Y, X, Z); упёрся — скорость по оси в 0.
local function move(p)
    local h = p.half
    p.onGround = false
    if p.vy ~= 0 then
        local ny = p.y + p.vy
        if blocked(p.x - h, ny - h, p.z - h, p.x + h, ny + h, p.z + h) then
            if p.vy < 0 then p.onGround = true end
            p.vy = 0
        else p.y = ny end
    end
    if p.vx ~= 0 then
        local nx = p.x + p.vx
        if blocked(nx - h, p.y - h, p.z - h, nx + h, p.y + h, p.z + h) then p.vx = 0 else p.x = nx end
    end
    if p.vz ~= 0 then
        local nz = p.z + p.vz
        if blocked(p.x - h, p.y - h, nz - h, p.x + h, p.y + h, nz + h) then p.vz = 0 else p.z = nz end
    end
end

-- EntityFX.onUpdate: тяжесть 0.04 за тик, сопротивление 0.98, на земле по
-- горизонтали ещё 0.7; срок вышел — осколок убран.
local function tick()
    local i = 1
    while i <= #list do
        local p = list[i]
        p.px, p.py, p.pz = p.x, p.y, p.z
        p.age = p.age + 1
        if p.age >= p.maxAge then
            DestroyObject(p.obj)
            table.remove(list, i)
        else
            p.vy = p.vy - 0.04 * p.gravity
            move(p)
            p.vx, p.vy, p.vz = p.vx * 0.98, p.vy * 0.98, p.vz * 0.98
            if p.onGround then p.vx, p.vz = p.vx * 0.7, p.vz * 0.7 end
            i = i + 1
        end
    end
end

function Pt.update(dt)
    local d = Pt.demo
    if d then
        d.t = d.t - dt
        if d.t <= 0 then
            d.t = 0.4
            Pt.destroy(B.byName.dirt.id, 0, d.x, d.y, d.z)
            for _ = 1, 3 do Pt.hit(B.byName.stone.id, 0, d.x + 1, d.y - 1, d.z, 1) end
        end
    end
    acc = acc + dt
    local n = 0
    while acc >= TICK and n < 5 do
        acc, n = acc - TICK, n + 1
        tick()
    end
    if n == 5 then acc = 0 end
    -- Между тиками: положение — от прошлого тика к текущему (renderPartialTicks).
    local a = acc / TICK
    for _, p in ipairs(list) do
        local x = p.px + (p.x - p.px) * a
        local y = p.py + (p.y - p.py) * a
        local z = p.pz + (p.z - p.pz) * a
        local s = 0.1 * p.scale
        p.obj.Transform.Position = Vec3(x, y, z)
        p.obj.Transform.Scale = Vec3(s, s, s)
        Light.applyLevels(p.obj, Light.levels(x, y, z))
    end
end

function Pt.count() return #list end

-- Самопроверка (--gencheck, строка PARTICLECHECK): 64 осколка сеткой 4×4×4,
-- скорость от центра, удар — один осколок в 0.1 от грани, всё исчезает.
function Pt.selfCheck()
    local before = #list
    local x, y, z = 40, 200, 40
    local stone = B.byName.stone.id
    local made = Pt.destroy(stone, 0, x, y, z)
    local grid, outward, outwardSum = true, true, 0
    local seen = {}
    for k = before + 1, #list do
        local p = list[k]
        local gi, gj, gk = (p.x - x) * 4 - 0.5, (p.y - y) * 4 - 0.5, (p.z - z) * 4 - 0.5
        if math.abs(gi - math.floor(gi + 0.5)) > 1e-6 or math.abs(gj - math.floor(gj + 0.5)) > 1e-6 then grid = false end
        seen[math.floor(gi + 0.5) * 16 + math.floor(gj + 0.5) * 4 + math.floor(gk + 0.5)] = true
        -- В среднем скорость смотрит от центра (у внутренних осколков случайная
        -- добавка ±0.4 сильнее смещения ±0.125 — у оригинала так же).
        outwardSum = outwardSum + (p.x - x - 0.5) * p.vx + (p.z - z - 0.5) * p.vz
    end
    outward = outwardSum > 0
    local cells = 0
    for _ in pairs(seen) do cells = cells + 1 end
    local h = Pt.hit(stone, 0, x, y, z, 1)
    local hitOk = h and math.abs(h.y - (y + 1.1)) < 1e-6 and h.x >= x + 0.1 and h.x <= x + 0.9
    for _ = 1, 100 do tick() end
    local gone = #list == before
    local ok = made == 64 and cells == 64 and grid and outward and hitOk and gone
    return string.format("PARTICLECHECK: %s осколков=%d клеток=%d сетка=%s наружу=%s удар=%s исчезли=%s",
        ok and "PASS" or "FAIL", made, cells, tostring(grid), tostring(outward), tostring(hitOk), tostring(gone))
end

return Pt
