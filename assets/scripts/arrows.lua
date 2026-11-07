-- ---------------------------------------------------------------------------
-- arrows.lua — стрелы из лука, как EntityArrow 1.7.10.
--
-- Выстрел (ItemBow.onPlayerStoppedUsing): сила f = j/20, f = (f² + 2f)/3, не
-- больше 1; меньше 0.1 — выстрела нет. Скорость — f·3 блока за тик, вылет —
-- из глаз со сдвигом на 0.16 вбок и 0.1 вниз, разброс ±0.0075·гаусс.
-- Полёт по тикам: шаг, сопротивление ×0.99 (в воде ×0.8), падение −0.05.
-- Попала в блок — застревает; игрок рядом подбирает её обратно.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local M = require "mat"

local Ar = {}
local list = {}
local acc = 0

local function gauss()
    local u, v = math.max(1e-9, math.random()), math.random()
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
end

-- Сила выстрела по тикам натяжения; nil — слишком слабо.
function Ar.power(ticks)
    local f = ticks / 20
    f = (f * f + f * 2) / 3
    if f < 0.1 then return nil end
    return math.min(1, f)
end

function Ar.fire(P, power)
    local Hand = require "hand"
    local yr = math.rad(P.yaw)
    local ex, ey, ez = P.eye()
    -- Вправо (к правой руке) на 0.16 и вниз на 0.1 (EntityArrow(world, shooter, speed)).
    local rx, rz = math.cos(yr), -math.sin(yr)
    local x, y, z = ex + rx * 0.16, ey - 0.1, ez + rz * 0.16
    local dx, dy, dz = P.lookDir()
    local speed = power * 2 * 1.5
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / l + gauss() * 0.0075, dy / l + gauss() * 0.0075, dz / l + gauss() * 0.0075
    local obj = SpawnObject("Arrow")
    Hand.setItemMesh(obj, B.byName.arrow.id)
    list[#list + 1] = {x = x, y = y, z = z, vx = dx * speed, vy = dy * speed, vz = dz * speed,
                       obj = obj, stuck = false, age = 0}
end

local function solid(x, y, z)
    return B.solid[W.get(math.floor(x), math.floor(y), math.floor(z))]
end

local function tick(P)
    for i = #list, 1, -1 do
        local a = list[i]
        a.age = a.age + 1
        if a.stuck then
            -- Подбор: игрок ближе блока (коробка игрока задевает стрелу).
            local dx, dy, dz = P.pos.x - a.x, P.pos.y + 0.9 - a.y, P.pos.z - a.z
            if dx * dx + dz * dz < 1.0 and math.abs(dy) < 1.4 and a.age > 10 then
                require("inventory").add(B.byName.arrow.id, 1)
                DestroyObject(a.obj)
                table.remove(list, i)
            elseif a.age > 1200 * 20 then
                DestroyObject(a.obj)
                table.remove(list, i)
            end
        else
            -- Шаг луча мелкими долями: стрела в полной силе пролетает 3 блока за тик.
            local steps = math.max(1, math.ceil(math.sqrt(a.vx * a.vx + a.vy * a.vy + a.vz * a.vz) / 0.25))
            for _ = 1, steps do
                local nx, ny, nz = a.x + a.vx / steps, a.y + a.vy / steps, a.z + a.vz / steps
                if solid(nx, ny, nz) then a.stuck = true; a.age = 0; break end
                a.x, a.y, a.z = nx, ny, nz
            end
            if not a.stuck then
                local inWater = W.get(math.floor(a.x), math.floor(a.y), math.floor(a.z)) == 11
                local drag = inWater and 0.8 or 0.99
                a.vx, a.vy, a.vz = a.vx * drag, a.vy * drag - 0.05, a.vz * drag
                if a.y < -10 then a.stuck = true end
            end
        end
    end
end

function Ar.update(dt, P)
    acc = acc + math.min(dt, 0.25)
    while acc >= 0.05 do
        acc = acc - 0.05
        tick(P)
    end
    for _, a in ipairs(list) do
        -- Наконечник иконки — правый верхний угол; в меше «как Minecraft» это
        -- направление (−1, 1, 0): поворачиваем его вдоль полёта.
        local vx, vy, vz = a.vx, a.vy, a.vz
        if a.stuck then vx, vy, vz = a.lx or vx, a.ly or vy, a.lz or vz else a.lx, a.ly, a.lz = vx, vy, vz end
        local h = math.sqrt(vx * vx + vz * vz)
        local yaw = math.deg(math.atan(-vx, -vz))
        local pitch = math.deg(math.atan(vy, math.max(h, 1e-6)))
        local m = M.identity()
        M.translate(m, a.x, a.y, a.z)
        M.rotate(m, yaw, 0, 1, 0)
        M.rotate(m, pitch, 1, 0, 0)
        M.rotate(m, -90, 0, 1, 0)
        M.rotate(m, 45, 0, 0, 1)
        M.scale(m, 0.7)
        M.translate(m, -0.5, -0.5, 1 / 32)
        M.applyTo(a.obj, m)
    end
end

return Ar
