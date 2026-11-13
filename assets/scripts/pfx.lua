-- ---------------------------------------------------------------------------
-- pfx.lua — частицы игры на СИСТЕМЕ ЧАСТИЦ ДВИЖКА.
--
-- Прежде каждая частица была объектом сцены со своим мешем, а её полёт считал
-- Lua: 64 объекта на разбитый блок, по объекту на огонёк факела. Теперь вид
-- частицы — эффект движка (ParticleEffect): тяжесть, сопротивление,
-- столкновение с блоками (коллайдеры colliders.lua), кадры листа, кривая
-- размера; все частицы вида — одна струя и один вызов отрисовки. Игра только
-- говорит, ГДЕ и КАКОЙ частице родиться (fx.spawn) — числа 1.7.10: скорости
-- в блоках за тик, срок в тиках, как у EntityFX.
--
-- Перевод единиц: тик — 1/20 с. Скорость ×20, срок ×0.05. Тяжесть 0.04 за
-- тик² = 16 м/с². Множитель скорости k за тик — сопротивление движка
-- d = (1/k − 1)·20 (движок делит скорость на 1 + d·dt).
-- ---------------------------------------------------------------------------
local Col = require "colliders"

local Pf = {}

local TICK = 0.05
local SHEET = "assets/textures/particle/particles.png"
local ready = {}

local function drag(k) return (1 / k - 1) * 20 end

-- Лента из 8 кадров дыма В ОБРАТНОМ ПОРЯДКЕ (7…0, как у EntitySmokeFX):
-- движок листает кадры вперёд, поэтому лента собрана уже перевёрнутой —
-- кусками листа particles.png (texture.read / texture.write).
local SMOKE_STRIP = "sagecraft_smoke_strip"
local stripDone = false
local function smokeStrip()
    if stripDone then return SMOKE_STRIP end
    local src = texture.load(SHEET, "sagecraft_particles_src")
    local strip = texture(SMOKE_STRIP, 64, 8)
    strip.nearest = true
    for k = 0, 7 do
        -- Кадр i листа — верхний ряд, 8×8; строки холста идут снизу вверх.
        local i = 7 - k
        strip.write(k * 8, 0, 8, 8, src.read(i * 8, src.height - 8, 8, 8))
    end
    strip.apply()
    stripDone = true
    return SMOKE_STRIP
end

local function base()
    local e = ParticleEffect()
    e.RateOverTime = 0
    e.MaxParticles = 8192
    e.Space = "world"
    e.Shape = "point"
    e.StartSpeed = ParticleRange(0, 0)
    e.StartRotation = ParticleRange(0, 0)
    e.Filtering = "nearest"
    e.Blend = "alpha"
    e.UseForces = true
    return e
end

-- Кадр листа 16×16 по номеру значка 1.7.10 (setParticleTextureIndex).
local function sheet(e, index)
    e.Texture = SHEET
    e.TilesX, e.TilesY = 16, 16
    e.Flipbook = "fixed"
    e.StartFrame = index
end

local KINDS = {
    -- EntityDiggingFX: кусочек атласа блоков, тяжесть 1, ×0.98 за тик,
    -- на земле ещё ×0.7; о блоки бьётся (слои SOLID и SHAPE).
    dig = function()
        local e = base()
        e.Texture = require("atlas").TEXTURE
        e.TilesX, e.TilesY = 64, 64
        e.Flipbook = "random"
        e.GravityScale = 16 / 9.81
        e.Drag = drag(0.98)
        e.UseCollision = true
        e.Collision = "world"
        e.CollisionMask = Col.PARTICLES
        e.CollisionRadius = 0.05
        e.Bounce = 0
        e.Friction = 0.11
        return e
    end,
    -- EntityFlameFX: значок 48, ×0.96 за тик, тает: размер ×(1 − t²·0.5).
    flame = function()
        local e = base()
        sheet(e, 48)
        e.Drag = drag(0.96)
        e:SetSizeOverLifetime({{0, 1}, {0.25, 0.969}, {0.5, 0.875}, {0.75, 0.719}, {1, 0.5}})
        return e
    end,
    -- EntitySmokeFX: кадры 7…0 за жизнь, всплывает (+0.004 за тик²), ×0.96.
    smoke = function()
        local e = base()
        e.Texture = smokeStrip()
        e.TilesX, e.TilesY = 8, 1
        e.Flipbook = "overLifetime"
        e.Cycles = 1
        e.Force = Vec3(0, 0.004 * 400, 0)
        e.Drag = drag(0.96)
        e:SetSizeOverLifetime({{0, 0}, {1 / 32, 1}, {1, 1}})
        return e
    end,
    -- EntityHeartFX: значок 80, ×0.86 за тик.
    heart = function()
        local e = base()
        sheet(e, 80)
        e.Drag = drag(0.86)
        return e
    end,
    -- EntityExplodeFX: дымка 7…0, всплывает, ×0.9 за тик.
    explode = function()
        local e = base()
        e.Texture = smokeStrip()
        e.TilesX, e.TilesY = 8, 1
        e.Flipbook = "overLifetime"
        e.Cycles = 1
        e.Force = Vec3(0, 0.004 * 400, 0)
        e.Drag = drag(0.9)
        return e
    end,
    -- Искра костной муки (happy_villager.png): ×0.99 за тик.
    happy = function()
        local e = base()
        e.Texture = "assets/textures/particle/happy_villager.png"
        e.Drag = drag(0.99)
        return e
    end,
}

local function stream(kind)
    local id = "sagecraft_" .. kind
    if not ready[kind] then
        CreateParticleStream(id, KINDS[kind](), Vec3(0, 0, 0))
        ready[kind] = true
    end
    return id
end

-- Родить частицы вида kind. Каждая — {x, y, z, vx, vy, vz (блоков за тик),
-- life (тиков), size (сторона квадрата, блоков), r, g, b, frame}.
-- Возвращает, сколько родилось.
function Pf.spawn(kind, list)
    if #list == 0 then return 0 end
    local out = {}
    for i, p in ipairs(list) do
        out[i] = {
            pos = Vec3(p.x, p.y, p.z),
            velocity = Vec3((p.vx or 0) * 20, (p.vy or 0) * 20, (p.vz or 0) * 20),
            lifetime = math.max(1, p.life or 20) * TICK,
            size = p.size,
            color = Vec4(p.r or 1, p.g or 1, p.b or 1, 1),
            frame = p.frame,
            rotation = 0,
        }
    end
    return fx.spawn(stream(kind), out)
end

-- Сколько частиц вида живёт сейчас.
function Pf.count(kind)
    if not ready[kind] then return 0 end
    return fx.count("sagecraft_" .. kind)
end

return Pf
