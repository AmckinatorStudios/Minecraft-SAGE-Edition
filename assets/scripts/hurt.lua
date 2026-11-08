-- ---------------------------------------------------------------------------
-- hurt.lua — урон игроку по правилам Minecraft 1.7.10 (пока источник один —
-- падение, DamageSource.fall).
--
-- ПАДЕНИЕ (EntityLivingBase.fall): fallDistance копится всё снижение
-- (player.lua), в момент приземления — один раз:
--   урон i = ceil(fallDistance − 3); i > 0 — звук damage.fallbig (i > 4) или
--   damage.fallsmall (громкость 1, тон 1), урон через attackEntityFrom(fall)
--   и звук шага блока под ногами (posY − 0.2): громкость ×0.5, тон ×0.75.
-- Урон от падения броню не учитывает (setDamageBypassesArmor), отбрасывания
-- и направления удара нет (attackedAtYaw = 0).
--
-- УДАР (attackEntityFrom): неуязвимость 20 тиков; во второй её половине
-- проходит только больший удар — разница. Новый удар: hurtTime =
-- maxHurtTime = 10, звук game.player.hurt (damage/hit1–3, тон ±0.2),
-- limbSwingAmount = 1.5 (handleHealthUpdate), усталость 0.3.
--
-- КАМЕРА (EntityRenderer.hurtCameraEffect): f = (hurtTime − доля тика) /
-- maxHurtTime, наклон вокруг оси взгляда −sin(f⁴·π)·14°. Тот же наклон —
-- у руки от первого лица (renderHand зовёт тот же эффект) и у камеры от
-- третьего лица. Модель от третьего лица — красная, пока hurtTime > 0
-- (RendererLivingEntity), без заваливания.
-- ---------------------------------------------------------------------------
local H = {}

H.MAX_HURT_TIME = 10
H.MAX_RESIST = 20
H.hurtTime = 0
H.resist = 0          -- hurtResistantTime
H.lastDamage = 0
H.stats = {hits = 0, falls = 0}

local TICK = 1 / 20
local acc = 0

-- Урон по количеству HP (attackEntityFrom). true — удар прошёл.
function H.attack(source, amount)
    local Hud = require "hud"
    if amount <= 0 or Hud.health <= 0 then return false end
    local fresh
    if H.resist > H.MAX_RESIST / 2 then
        if amount <= H.lastDamage then return false end
        Hud.damage(amount - H.lastDamage)
        H.lastDamage = amount
        fresh = false
    else
        H.lastDamage = amount
        H.resist = H.MAX_RESIST
        Hud.damage(amount)
        H.hurtTime = H.MAX_HURT_TIME
        fresh = true
    end
    -- damageEntity: усталость source.getHungerDamage() = 0.3.
    Hud.addExhaustion(0.3)
    H.stats.hits = H.stats.hits + 1
    H.lastSource = source
    if fresh then
        local P = require "player"
        -- handleHealthUpdate(2): ноги модели вздрагивают, звук удара игрока.
        require("anim").hurtLimbs()
        require("sounds").event("game.player.hurt", P.pos.x, P.pos.y, P.pos.z, 1.0, (math.random() - math.random()) * 0.2 + 1)
    end
    return true
end

-- Приземление после падения с высоты distance (EntityLivingBase.fall).
-- Возвращает нанесённый урон (0 — без урона).
function H.fall(distance)
    local i = math.ceil(distance - 3)
    if i <= 0 then return 0 end
    local P = require "player"
    local Snd = require "sounds"
    Snd.event(i > 4 and "damage.fallbig" or "damage.fallsmall", P.pos.x, P.pos.y, P.pos.z, 1.0, 1.0)
    H.attack("fall", i)
    -- Звук поверхности: шаг блока под ногами, громкость ×0.5, тон ×0.75.
    local W = require "world"
    local id = W.get(math.floor(P.pos.x), math.floor(P.pos.y - 0.2), math.floor(P.pos.z))
    if id ~= 0 then Snd.land(id, P.pos.x, P.pos.y, P.pos.z) end
    H.stats.falls = H.stats.falls + 1
    return i
end

-- Тик (onEntityUpdate): hurtTime и неуязвимость убывают.
function H.tick()
    if H.hurtTime > 0 then H.hurtTime = H.hurtTime - 1 end
    if H.resist > 0 then H.resist = H.resist - 1 end
end

function H.update(dt)
    -- Для снимков (--hurtpose=1): удар застыл на самом сильном наклоне
    -- (f⁴ = 0.5, hurtTime ≈ 8.4).
    if LaunchFlag("hurtpose") then
        H.hurtTime, H.resist, acc = 9, 19, 0.6 * TICK
        return
    end
    acc = acc + dt
    local n = 0
    while acc >= TICK and n < 5 do
        acc, n = acc - TICK, n + 1
        H.tick()
    end
    if n == 5 then acc = 0 end
end

-- Доля тика для отрисовки.
function H.partial() return acc / TICK end

-- Наклон камеры (градусы вокруг оси взгляда, как glRotatef(−f·14, 0, 0, 1)).
function H.roll(partial)
    local f = H.hurtTime - (partial or H.partial())
    if f < 0 then return 0 end
    f = f / H.MAX_HURT_TIME
    return -math.sin(f * f * f * f * math.pi) * 14
end

-- Модель красная (RendererLivingEntity: hurtTime > 0).
function H.red() return H.hurtTime > 0 end

function H.reset()
    H.hurtTime, H.resist, H.lastDamage, acc = 0, 0, 0, 0
end

return H
