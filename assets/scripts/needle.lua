-- ---------------------------------------------------------------------------
-- needle.lua — стрелки компаса и часов (TextureCompass, TextureClock 1.7.10).
--
-- Картинки предметов — полосы кадров: compass.png — 32 кадра 16×16,
-- clock.png — 64. Кадр выбирается по углу стрелки, а угол догоняет цель с
-- инерцией — каждый игровой тик (20 в секунду), как у оригинала:
--   d = цель − угол (в пределах ±полоборота, не больше 1 по модулю),
--   скорость += d·0.1, скорость ×= 0.8, угол += скорость.
-- Компас смотрит на точку появления мира: цель =
--   −((yaw − 90)·π/180 − atan2(spawnZ − z, spawnX − x)),
-- часы — на угол небесной сферы (0 — полдень). Вне обычного мира (его в игре
-- пока нет) обе стрелки крутились бы случайно.
-- ---------------------------------------------------------------------------
local B = require "blocks"

local N = {}

local TICK = 1 / 20
local PI2 = math.pi * 2
local acc = 0
N.compass = {angle = 0, delta = 0, primed = false}
N.clock = {angle = 0, delta = 0, primed = false}

-- Точка появления мира (gen.lua) — задаёт игра при открытии мира.
N.spawnX, N.spawnZ = 0, 0

local function chase(s, target, half)
    if not s.primed then
        s.angle, s.delta, s.primed = target, 0, true
        return
    end
    local d = target - s.angle
    while d < -half do d = d + 2 * half end
    while d >= half do d = d - 2 * half end
    if d < -1 then d = -1 elseif d > 1 then d = 1 end
    s.delta = (s.delta + d * 0.1) * 0.8
    s.angle = s.angle + s.delta
end

-- Цель компаса для игрока в (x, z) с нашим поворотом yaw (у оригинала
-- rotationYaw = 180 − yaw).
function N.compassTarget(x, z, yaw)
    local mc = (180 - yaw) % 360
    return -((mc - 90) * math.pi / 180 - math.atan(N.spawnZ - z, N.spawnX - x))
end

local function tick(P)
    chase(N.compass, N.compassTarget(P.pos.x, P.pos.z, P.yaw), math.pi)
    chase(N.clock, require("sky").celestialAngle(require("sky").ticks), 0.5)
end

function N.update(dt, P)
    if not P then return end
    acc = acc + dt
    local n = 0
    while acc >= TICK and n < 5 do
        acc, n = acc - TICK, n + 1
        tick(P)
    end
    if n == 5 then acc = 0 end
end

-- Номер кадра предмета id (nil — у предмета нет кадров).
function N.frame(id)
    local d = B.byId[id]
    if not d or not d.frames then return nil end
    local f = d.frames
    local i
    if d.name == "compass" then
        i = math.floor((N.compass.angle / PI2 + 1) * f) % f
    else
        i = math.floor((N.clock.angle + 1) * f) % f
    end
    return i
end

-- Самопроверка (--gencheck, строка NEEDLECHECK): компас на точку появления —
-- кадр 0 у стрелки, глядящей вперёд; часы в полдень — кадр 0, в полночь —
-- середина полосы; стрелка догоняет цель плавно, а не скачком.
function N.selfCheck()
    local saved = {N.spawnX, N.spawnZ, N.compass.angle, N.compass.delta, N.compass.primed,
                   N.clock.angle, N.clock.delta, N.clock.primed}
    local compass, clock = B.byName.compass.id, B.byName.clock.id
    -- Точка появления прямо по взгляду игрока (наш yaw 0 — на −Z).
    N.spawnX, N.spawnZ = 0, -100
    local t = N.compassTarget(0, 0, 0)
    N.compass.angle, N.compass.delta, N.compass.primed = t, 0, true
    local ahead = N.frame(compass)
    -- Цель позади: за один тик стрелка сдвигается на 0.08 (d = 1 → ·0.1·0.8).
    chase(N.compass, t + 3, math.pi)
    local smooth = math.abs(N.compass.angle - t - 0.08) < 1e-6
    N.clock.angle, N.clock.primed = 0, true
    local noon = N.frame(clock)
    N.clock.angle = 0.5
    local midnight = N.frame(clock)
    -- Кадр 16 полосы compass.png — красная стрелка вверх (на цель).
    local ok = ahead == 16 and smooth and noon == 0 and midnight == 32
    N.spawnX, N.spawnZ, N.compass.angle, N.compass.delta, N.compass.primed,
        N.clock.angle, N.clock.delta, N.clock.primed = table.unpack(saved)
    return string.format("NEEDLECHECK: %s компас_вперёд=%s плавно=%s полдень=%s полночь=%s", ok and "PASS" or "FAIL",
        tostring(ahead), tostring(smooth), tostring(noon), tostring(midnight))
end

return N
