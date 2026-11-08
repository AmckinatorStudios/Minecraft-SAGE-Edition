-- ---------------------------------------------------------------------------
-- player.lua — тело игрока в мире из клеток: ходьба, прыжок, присед, бег,
-- плавание, полёт; столкновения коробкой 0.6×1.8 с глухими клетками.
--
-- Столкновения — свои, по клеткам, а не физикой движка: мир — это таблица
-- чисел, и строить из неё коллайдеры на каждую правку дороже, чем проверить
-- десяток клеток вокруг коробки. Движение раскладывается по осям (сначала
-- Y, потом X, потом Z): так игрок скользит вдоль стены, а не застревает.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local P = {}

-- Коробка в приседе НЕ ниже (1.7.10): глаза опускаются на 0.08, тело — нет.
P.WIDTH, P.HEIGHT, P.EYE, P.EYE_SNEAK = 0.6, 1.8, 1.62, 1.54
P.pos = {x = 0.5, y = 80, z = 0.5}
P.vel = {x = 0, y = 0, z = 0}
P.yaw, P.pitch = 0, 0
P.onGround = false
P.flying = false
P.sneaking = false
P.sprinting = false
P.inWater = false
P.headInWater = false
P.walkDist = 0          -- пройденный путь: им качается камера и шагают ноги
P.fallStart = nil

local GRAVITY = 32
local JUMP = 9.0
-- Скорости Minecraft, блоков в секунду: шаг 4.317, бег 5.612, присед
-- 1.31, полёт 10.92.
local WALK, SPRINT, SNEAK, FLY = 4.317, 5.612, 1.31, 10.92
local solid = B.solid

local function blocked(x, y, z)
    return solid[W.get(x, y, z)]
end

-- Пересекает ли коробка игрока (ноги в x, y, z) хоть одну твёрдую клетку.
local function collides(x, y, z)
    local h = P.WIDTH / 2
    local x0, x1 = math.floor(x - h), math.floor(x + h - 1e-4)
    local y0, y1 = math.floor(y), math.floor(y + P.HEIGHT - 1e-4)
    local z0, z1 = math.floor(z - h), math.floor(z + h - 1e-4)
    for by = y0, y1 do
        for bz = z0, z1 do
            for bx = x0, x1 do
                if blocked(bx, by, bz) then return true end
            end
        end
    end
    return false
end
P.collides = collides

-- Сдвиг по одной оси с остановкой у препятствия (шагами не больше 0.45,
-- чтобы на рывке кадра не проскочить клетку насквозь).
local function moveAxis(axis, d)
    local steps = math.max(1, math.ceil(math.abs(d) / 0.45))
    local step = d / steps
    for _ = 1, steps do
        local p = P.pos
        local nx, ny, nz = p.x, p.y, p.z
        if axis == "x" then nx = nx + step elseif axis == "y" then ny = ny + step else nz = nz + step end
        if collides(nx, ny, nz) then return false end
        -- Присед не даёт сойти с края: шаг, после которого под ногами пусто, отменяется.
        if P.sneaking and P.onGround and axis ~= "y" and not P.flying then
            if not collides(nx, ny - 0.6, nz) then return false end
        end
        p.x, p.y, p.z = nx, ny, nz
    end
    return true
end

function P.spawnAt(x, y, z)
    P.pos.x, P.pos.y, P.pos.z = x, y, z
    P.vel.x, P.vel.y, P.vel.z = 0, 0, 0
    -- Если точка внутри породы — вверх до воздуха.
    while collides(P.pos.x, P.pos.y, P.pos.z) and P.pos.y < W.HEIGHT do P.pos.y = P.pos.y + 1 end
end

local function liquidAt(x, y, z) return B.drawKind[W.get(math.floor(x), math.floor(y), math.floor(z))] == 4 end

-- input: forward, strafe (−1..1), jump, sneak, sprintPressed (нажали Ctrl
-- в этом кадре); dt — шаг.
--
-- Бег — как в Minecraft: Ctrl НАЖИМАЮТ, а не держат. Нажатие при движении
-- вперёд включает бег, и он держится сам, пока игрок идёт вперёд; сбивают его
-- остановка (отпустили «вперёд»), присед и упор в стену.
-- Возвращает высоту падения, если игрок только что приземлился (для урона).
function P.update(input, dt)
    local p, v = P.pos, P.vel
    P.inWater = liquidAt(p.x, p.y + 0.4, p.z)
    P.headInWater = liquidAt(p.x, p.y + (P.sneaking and P.EYE_SNEAK or P.EYE), p.z)
    P.sneaking = input.sneak and not P.flying
    if input.sprintPressed and input.forward > 0 then P.sprinting = true end
    -- В воде не бегают (как в Minecraft 1.7): плывут шагом.
    if input.forward <= 0 or P.sneaking or (P.inWater and not P.flying) then P.sprinting = false end

    local speed = P.flying and FLY or (P.sneaking and SNEAK or (P.sprinting and SPRINT or WALK))
    if P.inWater and not P.flying then speed = speed * 0.55 end
    if P.flying and P.sprinting then speed = speed * 2 end

    local sy, cy = math.sin(math.rad(P.yaw)), math.cos(math.rad(P.yaw))
    -- Вперёд — к −Z при yaw = 0 (так смотрит камера движка).
    local wx = -sy * input.forward + cy * input.strafe
    local wz = -cy * input.forward - sy * input.strafe
    local len = math.sqrt(wx * wx + wz * wz)
    if len > 1 then wx, wz = wx / len, wz / len end

    -- Разгон и торможение: на земле — резко, в воздухе — вяло (как и
    -- положено телу без опоры), в полёте — мягко.
    local accel = P.onGround and 18 or (P.flying and 10 or 3.5)
    local k = math.min(1, accel * dt)
    v.x = v.x + (wx * speed - v.x) * k
    v.z = v.z + (wz * speed - v.z) * k

    if P.flying then
        local vy = 0
        if input.jump then vy = vy + speed * 0.8 end
        if input.descend then vy = vy - speed * 0.8 end
        v.y = v.y + (vy - v.y) * math.min(1, 8 * dt)
    elseif P.inWater then
        v.y = v.y - GRAVITY * 0.12 * dt
        if input.jump then v.y = math.min(v.y + 22 * dt, 3.2) end
        v.y = math.max(v.y, -3.5)
    else
        v.y = v.y - GRAVITY * dt
        v.y = math.max(v.y, -60)
        if input.jump and P.onGround then v.y = JUMP end
    end

    local wasGround = P.onGround
    local beforeX, beforeZ = p.x, p.z
    local yOk = moveAxis("y", v.y * dt)
    if not yOk then
        P.onGround = v.y < 0
        v.y = 0
    else
        P.onGround = false
    end
    local blocked = false
    if not moveAxis("x", v.x * dt) then
        -- Шаг на блок вверх в воде (выбраться на берег).
        if P.inWater and moveAxis("y", 1.05) and moveAxis("x", v.x * dt) then else v.x = 0; blocked = true end
    end
    if not moveAxis("z", v.z * dt) then
        if P.inWater and moveAxis("y", 1.05) and moveAxis("z", v.z * dt) then else v.z = 0; blocked = true end
    end
    -- Упёрся в стену — бег сбит (как в Minecraft).
    P.blocked = blocked
    if blocked and P.sprinting and not P.flying then P.sprinting = false end
    if P.flying and P.onGround then P.flying = false end

    local dx, dz = p.x - beforeX, p.z - beforeZ
    -- Путь в приседе на земле не копится (Entity.moveEntity): нет шагов и
    -- покачивания — присед в оригинале бесшумный.
    if P.onGround and not P.sneaking then P.walkDist = P.walkDist + math.sqrt(dx * dx + dz * dz) end

    -- Высота падения: от верхней точки полёта до приземления.
    local landed = nil
    if not P.onGround and not P.flying and not P.inWater then
        if not P.fallStart or p.y > P.fallStart then P.fallStart = p.y end
    else
        if P.onGround and not wasGround and P.fallStart then landed = P.fallStart - p.y end
        P.fallStart = nil
    end
    return landed
end

function P.eye()
    return P.pos.x, P.pos.y + (P.sneaking and P.EYE_SNEAK or P.EYE), P.pos.z
end

-- Обзор мышью. Договорённость движка (docs/scripting.md, GetMouseDelta):
-- dx > 0 — мышь вправо, dy > 0 — мышь ОТ СЕБЯ (вверх). Здесь: рыскание
-- растёт против часовой (вид сверху), наклон > 0 — взгляд вверх (lookDir().y
-- = sin(наклона)). Значит, мышь вправо — yaw уменьшается, мышь от себя —
-- pitch растёт. Раньше здесь стоял минус у dy — обзор был перевёрнут.
-- Самопроверка автопилота сверяет знаки (Auto.checkLook).
function P.look(dx, dy, sens)
    P.yaw = (P.yaw - dx * sens) % 360
    P.pitch = math.max(-89.9, math.min(89.9, P.pitch + dy * sens))
end

function P.lookDir()
    local yr, pr = math.rad(P.yaw), math.rad(P.pitch)
    return -math.sin(yr) * math.cos(pr), math.sin(pr), -math.cos(yr) * math.cos(pr)
end

-- Луч по клеткам (шаги от грани к грани, Amanatides–Woo): первая клетка, в
-- которую можно попасть (не воздух и не жидкость), и грань, через которую
-- луч в неё вошёл.
function P.raycast(maxDist)
    local ox, oy, oz = P.eye()
    local dx, dy, dz = P.lookDir()
    local x, y, z = math.floor(ox), math.floor(oy), math.floor(oz)
    local sx = dx > 0 and 1 or -1
    local sy = dy > 0 and 1 or -1
    local sz = dz > 0 and 1 or -1
    local function first(o, d, cell)
        if d == 0 then return math.huge end
        local edge = d > 0 and (cell + 1) or cell
        return (edge - o) / d
    end
    local tx, ty, tz = first(ox, dx, x), first(oy, dy, y), first(oz, dz, z)
    local ddx = dx ~= 0 and math.abs(1 / dx) or math.huge
    local ddy = dy ~= 0 and math.abs(1 / dy) or math.huge
    local ddz = dz ~= 0 and math.abs(1 / dz) or math.huge
    local nx, ny, nz = 0, 0, 0
    local t = 0
    while t <= maxDist do
        local id = W.get(x, y, z)
        if id ~= 0 and B.drawKind[id] ~= 4 then
            if B.drawKind[id] ~= 5 then
                return {x = x, y = y, z = z, id = id, nx = nx, ny = ny, nz = nz, dist = t}
            end
            -- Факел: попадание — только в его рамку выбора (луч и рамка,
            -- slab-метод), грань — та, через которую луч вошёл в рамку.
            local box = require("torch").bounds(W.meta(x, y, z))
            local tmin, tmax, fn = -math.huge, math.huge, {0, 0, 0}
            local hit = true
            local O, D, Cc = {ox, oy, oz}, {dx, dy, dz}, {x, y, z}
            for axis = 1, 3 do
                local o, d = O[axis], D[axis]
                local lo, hi = Cc[axis] + box[axis], Cc[axis] + box[axis + 3]
                if math.abs(d) < 1e-9 then
                    if o < lo or o > hi then hit = false end
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
            if hit and tmin <= tmax and tmax >= 0 and tmin <= maxDist then
                return {x = x, y = y, z = z, id = id, nx = fn[1], ny = fn[2], nz = fn[3], dist = math.max(0, tmin), box = box}
            end
        end
        if tx < ty and tx < tz then
            x = x + sx; t = tx; tx = tx + ddx; nx, ny, nz = -sx, 0, 0
        elseif ty < tz then
            y = y + sy; t = ty; ty = ty + ddy; nx, ny, nz = 0, -sy, 0
        else
            z = z + sz; t = tz; tz = tz + ddz; nx, ny, nz = 0, 0, -sz
        end
    end
    return nil
end

-- Можно ли поставить блок в клетку: не внутрь игрока (растение и факел — можно).
function P.canPlace(x, y, z, id)
    if not B.solid[id] then return true end
    local h = P.WIDTH / 2
    local p = P.pos
    return not (x + 1 > p.x - h and x < p.x + h and y + 1 > p.y and y < p.y + P.HEIGHT
                and z + 1 > p.z - h and z < p.z + h)
end

return P
