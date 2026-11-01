-- ---------------------------------------------------------------------------
-- sky.lua — время суток, купол неба, солнце и луна.
--
-- Сутки — DAY секунд. Время задаёт одно число 0..1 (0 — восход, 0.25 —
-- полдень, 0.5 — закат, 0.75 — полночь). Из него — направление на солнце,
-- цвета неба, сила дневного света для шейдера участков и цвет тумана: туман
-- обязан совпадать с горизонтом, иначе край мира виден как стена.
-- ---------------------------------------------------------------------------
local Sky = {}

Sky.DAY = 1200
Sky.time = 0.04
Sky.daylight = 1

local dome, sun, moon
local MAT_CHUNK = "assets/materials/chunk.sagemat"
local MAT_WATER = "assets/materials/water.sagemat"
local MAT_SKY = "assets/materials/sky.sagemat"
local MAT_CLOUD = "assets/materials/clouds.sagemat"

local function quad(u0, v0, u1, v1)
    local m = mesh()
    m.arrays{
        position = {-1, 0, -1,  1, 0, -1,  1, 0, 1,  -1, 0, 1},
        normal = {0, -1, 0,  0, -1, 0,  0, -1, 0,  0, -1, 0},
        uv = {u0, v0, u1, v0, u1, v1, u0, v1},
        index = {1, 2, 3, 1, 3, 4},
    }
    return m
end

local function mixc(a, b, t) return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t} end
local function v3(c) return Vec3(c[1], c[2], c[3]) end

local DAY_ZENITH, DAY_HORIZON = {0.40, 0.60, 1.00}, {0.70, 0.82, 1.00}
local NIGHT_ZENITH, NIGHT_HORIZON = {0.008, 0.01, 0.03}, {0.03, 0.04, 0.08}
local GLOW = {1.00, 0.48, 0.20}

Sky.moonPhase = -1

function Sky.init()
    dome = SpawnObject("Sky Dome")
    local s = sphere(220, 32, 16)
    s.apply(dome)
    SetMaterial(dome, MAT_SKY)

    sun = SpawnObject("Sun")
    quad(0, 0, 1, 1).apply(sun)
    SetMaterial(sun, "assets/materials/sun.sagemat")
    moon = SpawnObject("Moon")
    SetMaterial(moon, "assets/materials/moon.sagemat")
    Sky.update(0, nil)
end

-- Сколько видно неба: 0.15 ночью (луна) … 1 днём, с плавными сумерками.
local function daylightOf(sunH)
    return math.max(0.15, math.min(1, 0.45 + sunH * 2.2))
end

function Sky.update(dt, P)
    Sky.time = (Sky.time + dt / Sky.DAY) % 1
    local a = Sky.time * 2 * math.pi
    -- Солнце ходит по дуге восток -> верх -> запад с небольшим наклоном.
    local sdx, sdy, sdz = math.cos(a), math.sin(a), 0.25
    local len = math.sqrt(sdx * sdx + sdy * sdy + sdz * sdz)
    sdx, sdy, sdz = sdx / len, sdy / len, sdz / len
    Sky.sunDir = {sdx, sdy, sdz}
    Sky.daylight = daylightOf(sdy)

    local day = math.max(0, math.min(1, (sdy + 0.12) / 0.4))
    local zen = mixc(NIGHT_ZENITH, DAY_ZENITH, day)
    local hor = mixc(NIGHT_HORIZON, DAY_HORIZON, day)
    -- Зарево — когда солнце у горизонта (с любой стороны).
    local glow = math.max(0, 1 - math.abs(sdy) / 0.35)
    Sky.fog = mixc(hor, GLOW, glow * 0.35 * math.max(0, sdx * sdx))

    local view = require("chunks").radius * 16
    SetMaterialParam(MAT_SKY, "uZenith", v3(zen))
    SetMaterialParam(MAT_SKY, "uHorizon", v3(hor))
    SetMaterialParam(MAT_SKY, "uGlow", v3(GLOW))
    SetMaterialParam(MAT_SKY, "uGlowAmount", glow * 0.85)
    SetMaterialParam(MAT_SKY, "uSunDir", Vec3(sdx, sdy, sdz))
    SetMaterialParam(MAT_SKY, "uStars", math.max(0, 1 - day * 1.6))
    for _, m in ipairs({MAT_CHUNK, MAT_WATER, MAT_CLOUD}) do
        SetMaterialParam(m, "uDaylight", Sky.daylight)
        SetMaterialParam(m, "uFogColor", v3(Sky.fog))
        SetMaterialParam(m, "uFogStart", view * 0.62)
        SetMaterialParam(m, "uFogEnd", view * 0.98)
    end

    if not P or not dome then return end
    local ex, ey, ez = P.eye()
    dome.Transform.Position = Vec3(ex, ey, ez)
    local d = 180
    -- Квад светила лежит в плоскости XZ лицом вниз; поворачиваем его так,
    -- чтобы он смотрел на камеру с направления солнца.
    local angle = math.deg(a)
    sun.Transform.Position = Vec3(ex + sdx * d, ey + sdy * d, ez + sdz * d)
    sun.Transform.Rotation = Vec3(0, 0, angle - 90)
    sun.Transform.Scale = Vec3(20, 20, 20)
    moon.Transform.Position = Vec3(ex - sdx * d, ey - sdy * d, ez - sdz * d)
    moon.Transform.Rotation = Vec3(0, 0, angle + 90)
    moon.Transform.Scale = Vec3(14, 14, 14)

    -- Фаза луны меняется раз в сутки: лист 4×2 кадра.
    Sky.days = (Sky.days or 0)
    local phase = math.floor(Sky.days) % 8
    if phase ~= Sky.moonPhase then
        Sky.moonPhase = phase
        local col, row = phase % 4, phase // 4
        quad(col / 4, 1 - (row + 1) / 2, (col + 1) / 4, 1 - row / 2).apply(moon)
        SetMaterial(moon, "assets/materials/moon.sagemat")
    end
    if Sky.time < (Sky._last or 0) then Sky.days = Sky.days + 1 end
    Sky._last = Sky.time
end

return Sky
