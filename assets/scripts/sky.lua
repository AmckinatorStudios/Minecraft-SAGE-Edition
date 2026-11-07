-- ---------------------------------------------------------------------------
-- sky.lua — небо обычного мира Minecraft Java 1.7.10: время суток, солнце,
-- луна с фазами, звёзды, заря, цвет неба и тумана, погода в цветах.
--
-- Время — тики мира (Sky.ticks, 20 в секунду, сутки — 24000; дробная часть —
-- доля тика, ею всё сглажено между тиками). Тик 0 — восход, 6000 — полдень,
-- 12000 — закат, 18000 — полночь. Угол небесной сферы — calculateCelestialAngle:
-- t/24000 − 0.25, сглаженный косинусом и смешанный с исходным 1:3 (день
-- чуть длиннее ночи, светило у горизонта медленнее).
--
-- Оси: +X — восток, −X — запад, −Z — север, +Y — верх. Солнце идёт по
-- плоскости X–Y (поворот вокруг Z): встаёт на востоке, садится на западе;
-- всё небо — с центром в глазу, отдельным проходом камеры (слои "sky" и
-- "sky_top", game.lua), до мира и с ДРУГОЙ дальностью — 100 блоков до
-- светил не ограничены дальностью прорисовки.
--
-- Формулы — из World.getSkyColor / getCloudColour / getStarBrightness /
-- getSunBrightness / calculateSkylightSubtracted, WorldProvider.getFogColor /
-- calcSunriseSunsetColors, EntityRenderer.updateFogColor / setupFog,
-- BiomeGenBase.getSkyColorByTemp, RenderGlobal.renderSky / renderStars.
-- ---------------------------------------------------------------------------
local Mat = require "mat"
local Weather = require "weather"

local Sky = {}

Sky.DAY = 24000
Sky.ticks = 0          -- время мира в тиках (с долей тика)
Sky.cloudTicks = 0     -- cloudTickCounter: облака идут по своему счётчику
Sky.time = 0           -- доля суток 0..1 (0 — восход) — для отладки и HUD
Sky.daylight = 1
Sky.angle = 0
Sky.partial = 0
Sky.flashFlag = false  -- --lightning: держать вспышку молнии (проверка снимком)

local root, dome, glow, celestial, sun, moon, stars
local glowSide
local moonPhase = -1
local fogBright, fogBrightPrev = 1, 1

local MAT_CHUNK = "assets/materials/chunk.sagemat"
local MAT_WATER = "assets/materials/water.sagemat"
local MAT_SKY = "assets/materials/sky.sagemat"
local MAT_GLOW = "assets/materials/glow.sagemat"
local MAT_SUN = "assets/materials/sun.sagemat"
local MAT_MOON = "assets/materials/moon.sagemat"
local MAT_STARS = "assets/materials/stars.sagemat"
local MAT_CLOUD = "assets/materials/clouds.sagemat"
local LIT = {MAT_CHUNK, MAT_WATER, "assets/materials/item.sagemat", "assets/materials/crack.sagemat"}

local PI, cos, sin, floor = math.pi, math.cos, math.sin, math.floor
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- --- Формулы 1.7.10 ---------------------------------------------------------

function Sky.celestialAngle(t)
    local j = floor(t) % Sky.DAY
    local f = (j + (t - floor(t))) / Sky.DAY - 0.25
    if f < 0 then f = f + 1 end
    if f > 1 then f = f - 1 end
    local raw = f
    f = 1 - (cos(f * PI) + 1) / 2
    return raw + (f - raw) / 3
end

-- java.awt.Color.HSBtoRGB, с округлением до байта.
local function hsb(h, s, v)
    h = (h - floor(h)) * 6
    local i = floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return floor(r * 255 + 0.5) / 255, floor(g * 255 + 0.5) / 255, floor(b * 255 + 0.5) / 255
end

function Sky.skyColorByTemp(temp)
    temp = temp / 3
    if temp < -1 then temp = -1 elseif temp > 1 then temp = 1 end
    return hsb(0.62222224 - temp * 0.05, 0.5 + temp * 0.1, 1)
end

-- Температуры биомов BiomeGenBase 1.7.10.
local TEMP = {plains = 0.8, desert = 2.0, forest = 0.7, extreme_hills = 0.2, extreme_hills_edge = 0.2,
              snow = 0.0, ocean = 0.5, beach = 0.8}

-- getFloatTemperature: выше 64 холоднее на 0.05 за 30 блоков (без шума).
local function temperatureAt(x, y, z)
    local _, biome = require("gen").column(floor(x), floor(z))
    local t = TEMP[biome] or 0.8
    if y > 64 then t = t - (y - 64) * 0.05 / 30 end
    return t
end

local function lum(r, g, b) return r * 0.3 + g * 0.59 + b * 0.11 end

local function toward(r, g, b, l, k) return r * k + l * (1 - k), g * k + l * (1 - k), b * k + l * (1 - k) end

function Sky.skyColor(angle, temp, rain, thunder, flash)
    local f = clamp01(cos(angle * PI * 2) * 2 + 0.5)
    local r, g, b = Sky.skyColorByTemp(temp)
    r, g, b = r * f, g * f, b * f
    if rain > 0 then r, g, b = toward(r, g, b, lum(r, g, b) * 0.6, 1 - rain * 0.75) end
    if thunder > 0 then r, g, b = toward(r, g, b, lum(r, g, b) * 0.2, 1 - thunder * 0.75) end
    if flash > 0 then
        r, g, b = r * (1 - flash) + 0.8 * flash, g * (1 - flash) + 0.8 * flash, b * (1 - flash) + flash
    end
    return r, g, b
end

function Sky.cloudColor(angle, rain, thunder)
    local f = clamp01(cos(angle * PI * 2) * 2 + 0.5)
    local r, g, b = 1, 1, 1
    if rain > 0 then r, g, b = toward(r, g, b, lum(r, g, b) * 0.6, 1 - rain * 0.95) end
    r, g, b = r * (f * 0.9 + 0.1), g * (f * 0.9 + 0.1), b * (f * 0.85 + 0.15)
    if thunder > 0 then r, g, b = toward(r, g, b, lum(r, g, b) * 0.2, 1 - thunder * 0.95) end
    return r, g, b
end

function Sky.fogColorBase(angle)
    local f = clamp01(cos(angle * PI * 2) * 2 + 0.5)
    return 0.7529412 * (f * 0.94 + 0.06), 0.84705883 * (f * 0.94 + 0.06), 1.0 * (f * 0.91 + 0.09)
end

-- Заря: {r, g, b, a} или nil, когда солнце далеко от горизонта.
function Sky.sunriseColors(angle)
    local c = cos(angle * PI * 2)
    if c < -0.4 or c > 0.4 then return nil end
    local f5 = c / 0.4 * 0.5 + 0.5
    local f6 = 1 - (1 - sin(f5 * PI)) * 0.99
    f6 = f6 * f6
    return f5 * 0.3 + 0.7, f5 * f5 * 0.7 + 0.2, 0.2, f6
end

function Sky.starBrightness(angle)
    local f = clamp01(1 - (cos(angle * PI * 2) * 2 + 0.25))
    return f * f * 0.5
end

function Sky.sunBrightness(angle, rain, thunder)
    local f = 1 - clamp01(1 - (cos(angle * PI * 2) * 2 + 0.2))
    f = f * (1 - rain * 5 / 16) * (1 - thunder * 5 / 16)
    return f * 0.8 + 0.2
end

function Sky.skylightSubtracted(angle, rain, thunder)
    local f = 1 - clamp01(1 - (cos(angle * PI * 2) * 2 + 0.5))
    f = f * (1 - rain * 5 / 16) * (1 - thunder * 5 / 16)
    return floor((1 - f) * 11)
end

-- lightBrightnessTable обычного мира.
local function brightness(level)
    local f = 1 - level / 15
    return (1 - f) / (f * 3 + 1)
end

-- --- Геометрия --------------------------------------------------------------

local function quadMesh(p, uv)
    local m = mesh()
    m.arrays{position = p, uv = uv, index = {1, 2, 3, 1, 3, 4}}
    return m
end

-- renderStars: 1500 попыток по Random(10842), квадраты размера 0.15..0.25
-- на сфере радиуса 100, каждый повёрнут на случайный угол.
local function starMesh()
    local rnd = require("ores").Random(10842)
    local pos, uv, idx = {}, {}, {}
    local n = 0
    for _ = 1, 1500 do
        local d0 = rnd:nextFloat() * 2 - 1
        local d1 = rnd:nextFloat() * 2 - 1
        local d2 = rnd:nextFloat() * 2 - 1
        local d3 = 0.15 + rnd:nextFloat() * 0.1
        local d4 = d0 * d0 + d1 * d1 + d2 * d2
        if d4 < 1 and d4 > 0.01 then
            d4 = 1 / math.sqrt(d4)
            d0, d1, d2 = d0 * d4, d1 * d4, d2 * d4
            local d5, d6, d7 = d0 * 100, d1 * 100, d2 * 100
            local d8 = math.atan(d0, d2)
            local d9, d10 = sin(d8), cos(d8)
            local d11 = math.atan(math.sqrt(d0 * d0 + d2 * d2), d1)
            local d12, d13 = sin(d11), cos(d11)
            local d14 = rnd:nextDouble() * PI * 2
            local d15, d16 = sin(d14), cos(d14)
            for j = 0, 3 do
                local d18 = ((j & 2) - 1) * d3
                local d19 = (((j + 1) & 2) - 1) * d3
                local d20 = d18 * d16 - d19 * d15
                local d21 = d19 * d16 + d18 * d15
                local d22 = d20 * d12
                local d23 = -d20 * d13
                local d24 = d23 * d9 - d21 * d10
                local d25 = d21 * d9 + d23 * d10
                pos[#pos + 1] = d5 + d24; pos[#pos + 1] = d6 + d22; pos[#pos + 1] = d7 + d25
                uv[#uv + 1] = 0; uv[#uv + 1] = 0
            end
            idx[#idx + 1] = n + 1; idx[#idx + 1] = n + 2; idx[#idx + 1] = n + 3
            idx[#idx + 1] = n + 1; idx[#idx + 1] = n + 3; idx[#idx + 1] = n + 4
            n = n + 4
        end
    end
    local m = mesh()
    m.arrays{position = pos, uv = uv, index = idx}
    return m
end

-- Веер зари (до поворотов): центр (0, 100, 0), кольцо из 17 точек радиуса 120;
-- z края — −cos·40·альфа, множитель альфы — в шейдере (второй UV).
local function glowMesh()
    local pos, uv, uv2, idx = {0, 100, 0}, {1, 0}, {0, 0}, {}
    for j = 0, 16 do
        local f = j * PI * 2 / 16
        pos[#pos + 1] = sin(f) * 120; pos[#pos + 1] = cos(f) * 120; pos[#pos + 1] = 0
        uv[#uv + 1] = 0; uv[#uv + 1] = 0
        uv2[#uv2 + 1] = 0; uv2[#uv2 + 1] = -cos(f) * 40
        if j > 0 then idx[#idx + 1] = 1; idx[#idx + 1] = j + 1; idx[#idx + 1] = j + 2 end
    end
    local m = mesh()
    m.arrays{position = pos, uv = uv, uv2 = uv2, index = idx}
    return m
end

-- Луна: кадр фазы из листа 4×2 (v оригинала — сверху, у движка — снизу).
local function moonMesh(phase)
    local l, i1 = phase % 4, (phase // 4) % 2
    local u0, v0, u1, v1 = l / 4, i1 / 2, (l + 1) / 4, (i1 + 1) / 2
    return quadMesh({-20, -100, 20,  20, -100, 20,  20, -100, -20,  -20, -100, -20},
                    {u1, 1 - v1,  u0, 1 - v1,  u0, 1 - v0,  u1, 1 - v0})
end

local function spawn(name, parent, layer, m, mat)
    local o = SpawnObject(name)
    if parent then o:SetParent(parent) end
    m.apply(o)
    SetMaterial(o, mat)
    o:GetRenderer().Layer = layer
    return o
end

function Sky.init()
    root = SpawnObject("Sky")
    dome = spawn("Sky Plane", root, "sky", sphere(500, 32, 16), MAT_SKY)
    glow = spawn("Sky Sunrise", root, "sky", glowMesh(), MAT_GLOW)
    celestial = SpawnObject("Sky Celestial")
    celestial:SetParent(root)
    sun = spawn("Sun", celestial, "sky_top",
        quadMesh({-30, 100, -30,  30, 100, -30,  30, 100, 30,  -30, 100, 30}, {0, 1,  1, 1,  1, 0,  0, 0}), MAT_SUN)
    moonPhase = -1
    moon = spawn("Moon", celestial, "sky_top", moonMesh(0), MAT_MOON)
    stars = spawn("Stars", celestial, "sky_top", starMesh(), MAT_STARS)
    glowSide = nil
    Sky.update(0, nil)
end

-- --- Сохранение -------------------------------------------------------------

function Sky.save() return {ticks = Sky.ticks, weather = Weather.save()} end

-- loaded — сохранение мира; у прежних версий там только time (доля суток).
function Sky.load(loaded)
    Sky.ticks, Sky.cloudTicks = 0, 0
    Weather.load({})
    if not loaded then return end
    if type(loaded.sky) == "table" then
        Sky.ticks = loaded.sky.ticks or 0
        Weather.load(loaded.sky.weather)
    elseif loaded.time then
        Sky.ticks = loaded.time * Sky.DAY
    end
end

-- Время из параметра запуска: до 1 — доля суток, больше — тики.
function Sky.setTime(v)
    if not v then return end
    Sky.ticks = v <= 1 and v * Sky.DAY or v
end

-- --- Кадр -------------------------------------------------------------------

local function v3(r, g, b) return Vec3(r, g, b) end
local function lin(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end

local function tick(P)
    local n = 0
    for _ in pairs(require("world").chunks) do n = n + 1 end
    Weather.tick(n)
    if Sky.flashFlag then Weather.lastBolt = 2 end
    Sky.cloudTicks = Sky.cloudTicks + 1
    -- updateRenderer: яркость тумана догоняет свет в глазу на 10% за тик.
    fogBrightPrev = fogBright
    if P then
        local W = require "world"
        local ex, ey, ez = P.eye()
        local x, y, z = floor(ex), floor(ey), floor(ez)
        local sub = Sky.skylightSubtracted(Sky.angle, Weather.rainStrength(1), Weather.thunderStrength(1))
        local level = math.max((W.sky(x, y, z) or 15) - sub, W.blockLight(x, y, z) or 0)
        local k = math.min(require("chunks").radius, 16) / 16
        fogBright = fogBright + (brightness(level) * (1 - k) + k - fogBright) * 0.1
    end
end

function Sky.update(dt, P)
    local before = floor(Sky.ticks)
    Sky.ticks = Sky.ticks + dt * 20
    local steps = math.min(floor(Sky.ticks) - before, 200)
    for _ = 1, steps do tick(P) end
    local partial = Sky.ticks - floor(Sky.ticks)
    Sky.partial = partial
    Sky.time = (Sky.ticks % Sky.DAY) / Sky.DAY

    local angle = Sky.celestialAngle(Sky.ticks)
    Sky.angle = angle
    local rain = Weather.rainStrength(partial)
    local thunder = Weather.thunderStrength(partial)
    local flash = Weather.flash(partial)
    Sky.rain, Sky.thunder = rain, thunder

    -- Свет неба для блоков (updateLightmap): getSunBrightness·0.95 + 0.05,
    -- во вспышку молнии — полный.
    Sky.daylight = Weather.lastBolt > 0 and 1 or Sky.sunBrightness(angle, rain, thunder) * 0.95 + 0.05

    local ex, ey, ez = 0, 64, 0
    if P then ex, ey, ez = P.eye() end
    local temp = P and temperatureAt(ex, ey, ez) or 0.8
    local sr, sg, sb = Sky.skyColor(angle, temp, rain, thunder, flash)
    Sky.skyRGB = {sr, sg, sb}

    -- updateFogColor.
    local radius = require("chunks").radius
    local far = radius * 16
    local fr, fg, fb = Sky.fogColorBase(angle)
    local k = 1 - (0.25 + 0.75 * radius / 16) ^ 0.25
    fr, fg, fb = fr + (sr - fr) * k, fg + (sg - fg) * k, fb + (sb - fb) * k
    local gr, gg, gb, ga = Sky.sunriseColors(angle)
    if radius >= 4 and gr and P then
        local lx = P.lookDir()
        -- Заря — с той стороны, где солнце: после полудня запад (−X), до — восток.
        local d = sin(angle * PI * 2) > 0 and -lx or lx
        if d > 0 then
            d = d * ga
            fr, fg, fb = fr * (1 - d) + gr * d, fg * (1 - d) + gg * d, fb * (1 - d) + gb * d
        end
    end
    if rain > 0 then fr, fg, fb = fr * (1 - rain * 0.5), fg * (1 - rain * 0.5), fb * (1 - rain * 0.4) end
    if thunder > 0 then local m = 1 - thunder * 0.5; fr, fg, fb = fr * m, fg * m, fb * m end
    local bright = fogBrightPrev + (fogBright - fogBrightPrev) * partial
    fr, fg, fb = fr * bright, fg * bright, fb * bright
    -- Ниже 32 туман темнеет к пустоте (getVoidFogYFactor = 1/32).
    local void = ey * 0.03125
    if void < 1 then
        void = math.max(0, void)
        void = void * void
        fr, fg, fb = fr * void, fg * void, fb * void
    end
    Sky.fog = {fr, fg, fb}

    SetMaterialParam(MAT_SKY, "uSkyColor", v3(sr, sg, sb))
    SetMaterialParam(MAT_SKY, "uFogColor", v3(fr, fg, fb))
    SetMaterialParam(MAT_SKY, "uVoidColor", v3(sr * 0.2 + 0.04, sg * 0.2 + 0.04, sb * 0.6 + 0.1))
    SetMaterialParam(MAT_SKY, "uFogEnd", far * 0.8)
    SetMaterialParam(MAT_SKY, "uEyeHeight", ey - 63)
    -- Мир освещается в линейном цвете (текстуры движок читает как sRGB), и
    -- туман для него — тоже линейный; небу и облакам — sRGB, как у оригинала.
    for _, m in ipairs(LIT) do
        SetMaterialParam(m, "uDaylight", Sky.daylight)
        SetMaterialParam(m, "uFogColor", v3(lin(fr), lin(fg), lin(fb)))
        SetMaterialParam(m, "uFogStart", far * 0.25)
        SetMaterialParam(m, "uFogEnd", far)
    end
    SetMaterialParam(MAT_CLOUD, "uFogColor", v3(fr, fg, fb))
    SetMaterialParam(MAT_CLOUD, "uFogStart", far * 0.25)
    SetMaterialParam(MAT_CLOUD, "uFogEnd", far)
    local cr, cg, cb = Sky.cloudColor(angle, rain, thunder)
    SetMaterialParam(MAT_CLOUD, "uCloudColor", v3(cr, cg, cb))

    -- Светила гаснут в дождь (1 − rain), звёзды — ещё и днём.
    SetMaterialParam(MAT_SUN, "uAlpha", 1 - rain)
    SetMaterialParam(MAT_MOON, "uAlpha", 1 - rain)
    local star = Sky.starBrightness(angle) * (1 - rain)
    SetMaterialParam(MAT_STARS, "uAlpha", star * star)

    if not root then return end

    -- Небесная сфера: glRotatef(−90, Y), glRotatef(угол·360, X).
    local m = Mat.identity()
    Mat.rotate(m, -90, 0, 1, 0)
    Mat.rotate(m, angle * 360, 1, 0, 0)
    Mat.applyTo(celestial, m)

    -- Заря: glRotatef(90, X), glRotatef(sin < 0 ? 180 : 0, Z), glRotatef(90, Z).
    if gr then
        local side = sin(angle * PI * 2) < 0 and 180 or 0
        if side ~= glowSide then
            glowSide = side
            local g = Mat.identity()
            Mat.rotate(g, 90, 1, 0, 0)
            Mat.rotate(g, side, 0, 0, 1)
            Mat.rotate(g, 90, 0, 0, 1)
            Mat.applyTo(glow, g)
        end
        SetMaterialParam(MAT_GLOW, "uGlow", Vec4(gr, gg, gb, ga))
    else
        SetMaterialParam(MAT_GLOW, "uGlow", Vec4(0, 0, 0, 0))
    end

    -- Фаза луны: (тики / 24000) mod 8.
    local phase = floor(Sky.ticks / Sky.DAY) % 8
    if phase ~= moonPhase then
        moonPhase = phase
        moonMesh(phase).apply(moon)
        SetMaterial(moon, MAT_MOON)
        moon:GetRenderer().Layer = "sky_top"
    end
end

-- Самопроверка (--gencheck, строка SKYCHECK): числа формул 1.7.10.
function Sky.selfCheck()
    local function near(a, b) return math.abs(a - b) < 1e-4 end
    local noon, mid = Sky.celestialAngle(6000), Sky.celestialAngle(18000)
    local r, g, b = Sky.skyColorByTemp(0.8)
    -- Равнина (0.8): ≈ #78A7FF; округление HSBtoRGB даёт 0x79 по красному.
    local function byte(v, want) return math.abs(floor(v * 255 + 0.5) - want) <= 1 end
    local plains = byte(r, 0x78) and byte(g, 0xA7) and byte(b, 0xFF)
    local noGlowAtNoon = Sky.sunriseColors(noon) == nil
    local glowAtDawn = Sky.sunriseColors(Sky.celestialAngle(0)) ~= nil
    local starsNight = near(Sky.starBrightness(mid), 0.5) and Sky.starBrightness(noon) == 0
    local fr, fg, fb = Sky.fogColorBase(noon)
    local fog = near(fr, 0.7529412) and near(fg, 0.84705883) and near(fb, 1)
    local stormy = select(1, Sky.skyColor(noon, 0.8, 1, 1, 0)) < 0.25
    local phase = floor(24000 * 3 / Sky.DAY) % 8 == 3
    local ok = near(noon, 0) and near(mid, 0.5) and plains and noGlowAtNoon and glowAtDawn and starsNight and fog
        and stormy and phase
    return string.format("SKYCHECK: %s полдень=%.4f полночь=%.4f равнина=%s заря=%s/%s звёзды=%s туман=%s гроза=%s",
        ok and "PASS" or "FAIL", noon, mid, tostring(plains), tostring(noGlowAtNoon), tostring(glowAtDawn),
        tostring(starsNight), tostring(fog), tostring(stormy))
end

-- Центр неба — глаз камеры (после её постановки в кадре: покачивание, вид
-- от третьего лица).
function Sky.follow(cameraObj)
    if root and cameraObj then root.Transform.Position = cameraObj:WorldPosition() end
end

return Sky
