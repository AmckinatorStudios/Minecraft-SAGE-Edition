-- ---------------------------------------------------------------------------
-- lightmap.lua — световая карта Minecraft Java 1.7.10 (EntityRenderer.updateLightmap).
--
-- Два канала света по 16 уровней: небо (0..15, из открытого неба, гаснет под
-- листвой, в постройках, в пещерах) и блоки (факелы, светокамень). Они
-- распространяются по миру раздельно (light.lua) и сходятся только здесь:
-- текстура 16×16, по X — уровень блоков, по Y — уровень неба, в ячейке — цвет
-- освещения поверхности с таким светом. Каждая поверхность мира (участки,
-- предметы, рука, модель игрока) берёт цвет из этой карты по СВОИМ уровням —
-- поэтому ночь гасит открытое небо, но не факел, и общего затемняющего
-- фильтра поверх кадра нет.
--
--   яркость уровня (lightBrightnessTable): a = 1 − l/15, (1 − a) / (3a + 1)
--   небо: таблица[небо] · (sunBrightness · 0.95 + 0.05), во вспышку молнии — таблица
--   блоки: таблица[блоки] · (torchFlicker · 0.1 + 1.5)
--   R = небо·(sun·0.65 + 0.35) + блоки
--   G = небо·(sun·0.65 + 0.35) + блоки·((блоки·0.6 + 0.4)·0.6 + 0.4)
--   B = небо + блоки·(блоки²·0.6 + 0.4)
--   ×0.96 + 0.03, до 1; гамма: 1 − (1 − c)⁴ с весом настройки; ×0.96 + 0.03.
--
-- Отсюда и характер суток: днём небо белое, к ночи красный и зелёный гаснут
-- быстрее синего (холодный остаточный свет), а свет блоков — тёплый
-- (зелёный и синий у него с меньшим весом).
-- ---------------------------------------------------------------------------
local L = {}

L.NAME = "sagecraft_lightmap"
L.gamma = 0              -- настройка Brightness: 0 — Moody, 1 — Bright

local tex
local TABLE = {}
for i = 0, 15 do
    local a = 1 - i / 15
    TABLE[i] = (1 - a) / (a * 3 + 1)
end
L.TABLE = TABLE

local flicker, flickerDX = 0, 0
local colors = {}         -- colors[небо * 16 + блоки + 1] = {r, g, b}
for i = 1, 256 do colors[i] = {1, 1, 1} end

-- Мерцание факелов (updateTorchFlicker): случайный толчок, затухание 0.9 за тик.
function L.tick()
    flickerDX = flickerDX + (math.random() - math.random()) * math.random() * math.random()
    flickerDX = flickerDX * 0.9
    flicker = flicker + (flickerDX - flicker) * 1.0
end

local function finish(c, gamma)
    c = c * 0.96 + 0.03
    if c > 1 then c = 1 end
    local g = 1 - c
    g = 1 - g * g * g * g
    c = c * (1 - gamma) + g * gamma
    c = c * 0.96 + 0.03
    return c < 0 and 0 or (c > 1 and 1 or c)
end

-- Цвет ячейки (уровни неба и блоков — целые 0..15).
function L.compute(sky, blk, sun, flash, gamma)
    local f1 = sun * 0.95 + 0.05
    local s = flash and TABLE[sky] or TABLE[sky] * f1
    local b = TABLE[blk] * (flicker * 0.1 + 1.5)
    local r = s * (sun * 0.65 + 0.35) + b
    local g = s * (sun * 0.65 + 0.35) + b * ((b * 0.6 + 0.4) * 0.6 + 0.4)
    local bl = s + b * (b * b * 0.6 + 0.4)
    return finish(r, gamma), finish(g, gamma), finish(bl, gamma)
end

function L.init()
    tex = texture(L.NAME, 16, 16)
    tex.nearest = false   -- как у оригинала (GL_LINEAR): дробный свет углов плавный
    tex.fill(function() return Vec4(1, 1, 1, 1) end)
    tex.apply()
end

-- Пересчитать карту: sun — getSunBrightness с долей тика, flash — идёт молния.
-- Пересчёт — только когда входы поменялись (мерцание факелов меняется раз в
-- тик, солнце — плавно): 256 точек и выгрузка текстуры каждый кадр стоили
-- миллисекунды кадра впустую.
local lastSun, lastFlash, lastGamma, lastFlicker
function L.update(sun, flash)
    if not tex then L.init() end
    local gamma = L.gamma
    if lastSun and math.abs(sun - lastSun) < 1e-4 and flash == lastFlash and gamma == lastGamma
        and flicker == lastFlicker then
        return
    end
    lastSun, lastFlash, lastGamma, lastFlicker = sun, flash, gamma, flicker
    for sky = 0, 15 do
        for blk = 0, 15 do
            local r, g, b = L.compute(sky, blk, sun, flash, gamma)
            local c = colors[sky * 16 + blk + 1]
            c[1], c[2], c[3] = r, g, b
            tex.set(blk, sky, Vec4(r, g, b, 1))
        end
    end
    tex.apply()
end

-- Цвет освещения при уровнях (sky, blk) — для объектов на движковом материале.
function L.at(sky, blk)
    local c = colors[math.max(0, math.min(15, sky)) * 16 + math.max(0, math.min(15, blk)) + 1]
    return c[1], c[2], c[3]
end

-- Свет объекта (Entity.getBrightnessForRender): уровни клетки, где он стоит.
function L.levels(x, y, z)
    local W = require "world"
    local bx, by, bz = math.floor(x), math.floor(y), math.floor(z)
    return W.sky(bx, by, bz) or 15, W.blockLight(bx, by, bz) or 0
end

-- Поставить объекту свет его клетки. Материал на шейдере участка
-- (uEntityLight = 1) читает уровни из цвета объекта; движковый материал
-- (unlit) — получает готовый цвет карты.
function L.applyLevels(obj, sky, blk)
    local r = obj:GetRenderer()
    if r then r.Color = Vec3(sky / 15, blk / 15, 1) end
end

function L.applyColor(obj, sky, blk)
    local r = obj:GetRenderer()
    if r then r.Color = Vec3(L.at(sky, blk)) end
end

-- Самопроверка (--gencheck, строка LIGHTMAPCHECK): числа updateLightmap.
function L.selfCheck()
    local function near(a, b) return math.abs(a - b) < 1e-3 end
    local tbl = TABLE[0] == 0 and TABLE[15] == 1 and near(TABLE[7], (1 - 8 / 15) / ((8 / 15) * 3 + 1))
    local saved = flicker
    flicker = 0
    -- Полдень, открытое небо: (1·0.96 + 0.03)·0.96 + 0.03.
    local dr, dg, db = L.compute(15, 0, 1, false, 0)
    local day = near(dr, 0.9804) and near(dg, 0.9804) and near(db, 0.9804)
    -- Ночь (sunBrightness 0.2): небо холодное — синего больше красного.
    local nr, ng, nb = L.compute(15, 0, 0.2, false, 0)
    local night = nb > nr and nr > 0.1 and nr < 0.2
    -- Свет факела в нескольких блоках от него (уровень 9) ночью — тёплый:
    -- красного больше зелёного, зелёного больше синего (вплотную, 14, он
    -- упирается в белый — так и у оригинала).
    local tr, tg, tb = L.compute(0, 9, 0.2, false, 0)
    local torch = tr > tg and tg > tb and tr > 0.3
    -- Гамма Bright поднимает тёмное.
    local gr = L.compute(5, 0, 1, false, 1)
    local gamma = gr > L.compute(5, 0, 1, false, 0)
    flicker = saved
    local ok = tbl and day and night and torch and gamma
    return string.format("LIGHTMAPCHECK: %s таблица=%s день=%.4f ночь=%.3f/%.3f/%.3f факел=%.3f/%.3f/%.3f гамма=%s",
        ok and "PASS" or "FAIL", tostring(tbl), dr, nr, ng, nb, tr, tg, tb, tostring(gamma))
end

return L
