-- ---------------------------------------------------------------------------
-- pig.lua — свинья Minecraft 1.7.10 (EntityPig : EntityAnimal : EntityAgeable
-- : EntityCreature : EntityLiving : EntityLivingBase).
--
-- Здесь — тело: здоровье 10, скорость 0.25, размер 0.9 × 0.9 (поросёнок —
-- вдвое меньше), физика по игровым тикам в единицах оригинала (блоки за тик),
-- урон с неуязвимостью 20 тиков, отбрасывание, красная вспышка 10 тиков,
-- смерть с завалом на бок 20 тиков и облачком, дроп 1–3 свинины (жареной —
-- если горела), возраст (поросёнок растёт 24000 тиков), любовь, звуки,
-- сохранение. Задачи AI — в pigai.lua, модель — в pigmodel.lua.
--
-- Углы — как у оригинала: yaw 0 смотрит на +Z (наш поворот = 180 − yaw).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Bo = require "bounds"
local PM = require "pigmodel"

local Pig = {}
Pig.list = {}

local TICK = 1 / 20
local acc = 0
local rnd = math.random
local SND = "assets/sounds/mob/pig/"

Pig.MAX_HEALTH = 10
Pig.SPEED = 0.25
Pig.WIDTH, Pig.HEIGHT = 0.9, 0.9

local function wrap(a)
    a = a % 360
    if a >= 180 then a = a - 360 end
    return a
end
Pig.wrap = wrap

-- --- Создание ---------------------------------------------------------------

function Pig.spawn(x, y, z, yaw, age)
    local p = {
        x = x, y = y, z = z, px = x, py = y, pz = z,
        mx = 0, my = 0, mz = 0,
        yaw = yaw or rnd() * 360, pitch = 0, headYaw = yaw or 0, body = yaw or 0,
        pyaw = 0, phead = 0, pbody = 0, ppitch = 0,
        health = Pig.MAX_HEALTH, age = age or 0, love = 0,
        hurtTime = 0, hurtResist = 0, lastDamage = 0, deathTime = 0, dead = false,
        swing = 0, amount = 0, pswing = 0, pamount = 0,
        onGround = false, inWater = false, collidedH = false, fall = 0, air = 300,
        stepDist = 0, nextStep = 1, livingSound = 0, entityAge = 0,
        forward = 0, strafe = 0, moveSpeed = 0, jumping = false,
        revenge = nil, revengeTimer = 0, burning = false, ticks = 0,
    }
    p.yaw = wrap(p.yaw)
    p.headYaw, p.body = p.yaw, p.yaw
    p.model = PM.create()
    p.shadow = require("shadows").new("Pig Shadow")
    require("pigai").init(p)
    Pig.list[#Pig.list + 1] = p
    return p
end

function Pig.isChild(p) return p.age < 0 end
function Pig.size(p)
    if p.age < 0 then return Pig.WIDTH * 0.5, Pig.HEIGHT * 0.5 end
    return Pig.WIDTH, Pig.HEIGHT
end
function Pig.eyeHeight(p) local _, h = Pig.size(p); return h * 0.85 end

function Pig.loaded(p)
    local c = W.chunk(math.floor(p.x) // 16, math.floor(p.z) // 16)
    return c ~= nil and c.lit == true
end

local function remove(i)
    local p = Pig.list[i]
    PM.destroy(p.model)
    require("shadows").destroy(p.shadow)
    table.remove(Pig.list, i)
end
Pig.remove = remove

-- --- Столкновения с миром (Entity.moveEntity) -------------------------------

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
Pig.blocked = blocked

local function boxAt(p, x, y, z)
    local w, h = Pig.size(p)
    return x - w / 2, y, z - w / 2, x + w / 2, y + h, z + w / 2
end

-- Сдвиг по осям Y, X, Z (как у оригинала); упёрся — скорость по оси в 0.
-- Шаг на полблока вверх (stepHeight 0.5) при упоре на земле.
local function move(p, dx, dy, dz)
    local ox, oy, oz = p.x, p.y, p.z
    p.collidedH = false
    local wasGround = p.onGround
    p.onGround = false
    local function try(nx, ny, nz) return not blocked(boxAt(p, nx, ny, nz)) end
    -- Вертикаль — шагами не больше 0.4, чтобы падение не проскочило блок.
    local steps = math.max(1, math.ceil(math.abs(dy) / 0.4))
    for _ = 1, steps do
        local ny = p.y + dy / steps
        if try(p.x, ny, p.z) then p.y = ny
        else
            if dy < 0 then
                p.onGround = true
                -- Прижать к верху опоры.
                local fl = math.floor(p.y + 1e-6)
                if try(p.x, fl, p.z) then p.y = fl end
            end
            p.my = 0
            break
        end
    end
    local function horiz(axis, d)
        if d == 0 then return end
        local nx, nz = p.x, p.z
        if axis == "x" then nx = nx + d else nz = nz + d end
        if try(nx, p.y, nz) then p.x, p.z = nx, nz; return end
        -- stepHeight 0.5: на полблока выше — если там свободно.
        if (p.onGround or wasGround) and try(nx, p.y + 0.5, nz) and try(p.x, p.y + 0.5, p.z) then
            local sy = p.y + 0.5
            local fy = math.floor(sy)
            if try(nx, fy, nz) then sy = fy end
            p.x, p.z, p.y = nx, nz, sy
            return
        end
        p.collidedH = true
        if axis == "x" then p.mx = 0 else p.mz = 0 end
    end
    horiz("x", dx)
    horiz("z", dz)
    -- Шаги (Entity.moveEntity): путь ×0.6, звук на каждом целом.
    local mx, my, mz = p.x - ox, p.y - oy, p.z - oz
    if p.onGround and not p.inWater then
        p.stepDist = p.stepDist + math.sqrt(mx * mx + mz * mz) * 0.6
        if p.stepDist > p.nextStep then
            p.nextStep = math.floor(p.stepDist) + 1
            local below = W.get(math.floor(p.x), math.floor(p.y - 0.2), math.floor(p.z))
            if below ~= 0 then
                PlaySound3D(SND .. "step" .. rnd(5) .. ".ogg", Vec3(p.x, p.y, p.z), 0.15, 1.0, "neutral")
            end
        end
    end
    -- Падение (updateFallState): копится, на земле — урон за всё выше 3.
    if p.onGround then
        if p.fall > 3 then Pig.damage(p, math.ceil(p.fall - 3), nil, "fall") end
        p.fall = 0
    elseif my < 0 then
        p.fall = p.fall - my
    end
end

-- moveFlying: прибавка скорости по взгляду (strafe, forward) с трением f.
local function moveFlying(p, strafe, forward, f)
    local s = strafe * strafe + forward * forward
    if s < 1e-4 then return end
    s = math.sqrt(s)
    if s < 1 then s = 1 end
    s = f / s
    strafe, forward = strafe * s, forward * s
    local r = math.rad(p.yaw)
    local sn, cs = math.sin(r), math.cos(r)
    p.mx = p.mx + strafe * cs - forward * sn
    p.mz = p.mz + forward * cs + strafe * sn
end

-- EntityLivingBase.moveEntityWithHeading.
local function physics(p)
    if p.inWater then
        local y0 = p.y
        moveFlying(p, p.strafe, p.forward, 0.02)
        move(p, p.mx, p.my, p.mz)
        p.mx, p.my, p.mz = p.mx * 0.8, p.my * 0.8, p.mz * 0.8
        p.my = p.my - 0.02
        -- Упёрся в берег — выпрыгнуть (isOffsetPositionInLiquid).
        if p.collidedH and not blocked(boxAt(p, p.x + p.mx, p.y + 0.6 - p.y + y0 + p.my, p.z + p.mz)) then
            p.my = 0.3
        end
    else
        local f4 = p.onGround and 0.6 * 0.91 or 0.91
        local f5 = 0.16277136 / (f4 * f4 * f4)
        local f = p.onGround and p.moveSpeed * f5 or 0.02
        moveFlying(p, p.strafe, p.forward, f)
        move(p, p.mx, p.my, p.mz)
        p.my = (p.my - 0.08) * 0.98
        p.mx, p.mz = p.mx * f4, p.mz * f4
    end
end

-- --- Урон, смерть -----------------------------------------------------------

-- EntityLivingBase.attackEntityFrom: неуязвимость 20 тиков (во второй
-- половине проходит только больший удар — разница), отбрасывание от
-- источника, вспышка 10 тиков, звук; от удара игрока — паника (месть).
-- src — {x, z, player = true} или nil (падение, утопление).
function Pig.damage(p, amount, src, kind)
    if p.dead or amount <= 0 then return false end
    -- EntityAnimal.attackEntityFrom: удар гасит любовь.
    p.love = 0
    local hit
    if p.hurtResist > 10 then
        if amount <= p.lastDamage then return false end
        hit = amount - p.lastDamage
        p.lastDamage = amount
        p.health = p.health - hit
    else
        p.lastDamage = amount
        p.hurtResist = 20
        p.health = p.health - amount
        p.hurtTime = 10
        if src then
            local dx, dz = src.x - p.x, src.z - p.z
            while dx * dx + dz * dz < 1e-4 do dx, dz = (rnd() - rnd()) * 0.01, (rnd() - rnd()) * 0.01 end
            Pig.knockBack(p, dx, dz)
        end
        if src and src.player then
            p.revenge, p.revengeTimer = src, p.ticks
        end
        if p.health > 0 then
            PlaySound3D(SND .. "say" .. rnd(3) .. ".ogg", Vec3(p.x, p.y, p.z), 1.0, Pig.pitch(p), "neutral")
        end
    end
    if p.health <= 0 then Pig.die(p, src) end
    return true
end

-- knockBack: скорость пополам, от источника 0.4, вверх до 0.4.
function Pig.knockBack(p, dx, dz)
    local d = math.sqrt(dx * dx + dz * dz)
    p.mx, p.my, p.mz = p.mx / 2, p.my / 2, p.mz / 2
    p.mx, p.mz = p.mx - dx / d * 0.4, p.mz - dz / d * 0.4
    p.my = math.min(p.my + 0.4, 0.4)
end

-- Высота звука: (rand − rand)·0.2 + 1, у поросёнка ещё +0.5.
function Pig.pitch(p)
    return (rnd() - rnd()) * 0.2 + (p.age < 0 and 1.5 or 1.0)
end

-- onDeath: звук смерти; взрослый роняет 1–3 сырой (жареной — если горел)
-- свинины одной стопкой у ног; опыт 1–3 за убийство игроком.
function Pig.die(p, src)
    if p.dead then return end
    p.dead = true
    p.health = 0
    PlaySound3D(SND .. "death.ogg", Vec3(p.x, p.y, p.z), 1.0, Pig.pitch(p), "neutral")
    if p.age >= 0 then
        local n = rnd(3)
        local id = p.burning and B.byName.porkchop_cooked.id or B.byName.porkchop_raw.id
        require("drops").spawn(id, n, p.x, p.y + 0.5, p.z)
        if src and src.player then require("hud").addXp(1 + rnd(0, 2)) end
    end
end

-- --- Каждый тик ---------------------------------------------------------------

local function inWaterAt(p)
    local w, h = Pig.size(p)
    for _, oy in ipairs({0.1, h * 0.5}) do
        if B.drawKind[W.get(math.floor(p.x), math.floor(p.y + oy), math.floor(p.z))] == 4 then return true end
    end
    return false
end

local function tick(p, P)
    p.ticks = p.ticks + 1
    p.px, p.py, p.pz = p.x, p.y, p.z
    p.pyaw, p.phead, p.pbody, p.ppitch = p.yaw, p.headYaw, p.body, p.pitch
    p.pswing, p.pamount = p.swing, p.amount

    if p.dead then
        -- onDeathUpdate: 20 тиков завала, затем облачко и удаление.
        p.deathTime = p.deathTime + 1
        if p.hurtTime > 0 then p.hurtTime = p.hurtTime - 1 end
        if p.deathTime >= 20 then
            Pig.poof(p)
            return false
        end
        physics(p)
        return true
    end

    if p.hurtTime > 0 then p.hurtTime = p.hurtTime - 1 end
    if p.hurtResist > 0 then p.hurtResist = p.hurtResist - 1 end
    -- Месть забывается через 100 тиков (getAITarget).
    if p.revenge and p.ticks - p.revengeTimer > 100 then p.revenge = nil end

    p.inWater = inWaterAt(p)
    if p.inWater then p.fall = 0 end
    -- Воздух под водой (300 тиков), потом урон 2 за каждые 20.
    local _, h = Pig.size(p)
    if B.drawKind[W.get(math.floor(p.x), math.floor(p.y + Pig.eyeHeight(p)), math.floor(p.z))] == 4 then
        p.air = p.air - 1
        if p.air <= -20 then p.air = 0; Pig.damage(p, 2, nil, "drown") end
    else
        p.air = 300
    end
    local _ = h

    -- Возраст (EntityAgeable): поросёнок растёт к 0, после размножения — 6000 вниз.
    if p.age < 0 then p.age = p.age + 1 elseif p.age > 0 then p.age = p.age - 1 end
    -- Любовь (EntityAnimal): только при возрасте 0, тает по тику, сердечки раз в 10.
    if p.age ~= 0 then p.love = 0 end
    if p.love > 0 then
        p.love = p.love - 1
        if p.love % 10 == 0 then Pig.heart(p) end
    end

    -- Звук жизни (onEntityUpdate): rand(1000) < счётчик — хрюк и −80.
    if rnd(0, 999) < p.livingSound then
        p.livingSound = -80
        PlaySound3D(SND .. "say" .. rnd(3) .. ".ogg", Vec3(p.x, p.y, p.z), 1.0, Pig.pitch(p), "neutral")
    else
        p.livingSound = p.livingSound + 1
    end

    -- Не исчезают, но счётчик бездействия сбрасывается рядом с игроком (32 блока).
    p.entityAge = p.entityAge + 1
    if P then
        local dx, dy, dz = P.pos.x - p.x, P.pos.y - p.y, P.pos.z - p.z
        if dx * dx + dy * dy + dz * dz < 1024 then p.entityAge = 0 end
    end

    -- Задачи AI, навигация, взгляд, движение.
    require("pigai").tick(p, P)
    if p.jumping then
        if p.inWater then p.my = p.my + 0.04
        elseif p.onGround then p.my = 0.42 end
    end
    physics(p)
    require("pigai").body(p)

    -- Ноги (onUpdate): limbSwingAmount к min(путь·4, 1) на 0.4, swing += amount.
    local dx, dz = p.x - p.px, p.z - p.pz
    local f = math.sqrt(dx * dx + dz * dz) * 4
    if f > 1 then f = 1 end
    p.amount = p.amount + (f - p.amount) * 0.4
    p.swing = p.swing + p.amount
    return true
end

-- Столкновения существ (applyEntityCollision): расталкиваются на 0.05.
local function pushApart(P)
    local list = Pig.list
    for i = 1, #list do
        local a = list[i]
        if not a.dead then
            for j = i + 1, #list do
                local b = list[j]
                if not b.dead then
                    local dx, dz = b.x - a.x, b.z - a.z
                    local wa, ha = Pig.size(a)
                    local wb = Pig.size(b)
                    local r = (wa + wb) / 2
                    if math.abs(dx) < r and math.abs(dz) < r and math.abs(b.y - a.y) < ha then
                        local d = math.max(math.abs(dx), math.abs(dz))
                        if d >= 0.01 then
                            d = math.sqrt(d)
                            dx, dz = dx / d, dz / d
                            local k = math.min(1, 1 / d) * 0.05
                            a.mx, a.mz = a.mx - dx * k, a.mz - dz * k
                            b.mx, b.mz = b.mx + dx * k, b.mz + dz * k
                        end
                    end
                end
            end
            if P then
                local dx, dz = P.pos.x - a.x, P.pos.z - a.z
                local wa, ha = Pig.size(a)
                local r = (wa + P.WIDTH) / 2
                if math.abs(dx) < r and math.abs(dz) < r and P.pos.y < a.y + ha and P.pos.y + P.HEIGHT > a.y then
                    local d = math.max(math.abs(dx), math.abs(dz))
                    if d >= 0.01 then
                        d = math.sqrt(d)
                        dx, dz = dx / d, dz / d
                        local k = math.min(1, 1 / d) * 0.05
                        a.mx, a.mz = a.mx - dx * k, a.mz - dz * k
                        P.vel.x, P.vel.z = P.vel.x + dx * k * 20, P.vel.z + dz * k * 20
                    end
                end
            end
        end
    end
end

-- --- Частицы: сердечки любви и облачко смерти (particles.png) -----------------

local fx = {}
local fxMeshes = {}
local function fxQuad(i)
    if fxMeshes[i] then return fxMeshes[i] end
    local u0, v0 = (i % 16) / 16, 1 - ((i // 16) + 1) / 16
    local m = mesh()
    m.arrays{position = {-1, 0, -1, 1, 0, -1, 1, 0, 1, -1, 0, 1},
             uv = {u0, v0, u0 + 1 / 16, v0, u0 + 1 / 16, v0 + 1 / 16, u0, v0 + 1 / 16}, index = {1, 2, 3, 1, 3, 4}}
    fxMeshes[i] = m
    return m
end
local function spawnFx(kind, x, y, z, vx, vy, vz)
    local o = SpawnObject(kind == "heart" and "Heart" or "Explode")
    local e = {obj = o, kind = kind, x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, age = 0}
    if kind == "heart" then
        -- EntityHeartFX: значок 80, масштаб ×0.75·2, живёт 16 тиков, всплывает.
        e.life, e.scale, e.frame = 16, (rnd() * 0.5 + 0.5) * 2 * 0.75 * 0.1, 80
        fxQuad(80).apply(o)
        SetMaterial(o, "assets/materials/particle_flame.sagemat")
    else
        -- EntityExplodeFX: дымка 7…0, серая 0.7–1, 16/(rand·0.8 + 0.2) + 2 тиков.
        e.life = math.floor(16 / (rnd() * 0.8 + 0.2)) + 2
        e.scale, e.frame = (rnd() * 0.5 + 0.5) * 2 * 0.1, 7
        e.gray = rnd() * 0.3 + 0.7
        fxQuad(7).apply(o)
        SetMaterial(o, "assets/materials/particle_smoke.sagemat")
        o:GetRenderer().Color = Vec3(e.gray, e.gray, e.gray)
    end
    fx[#fx + 1] = e
end

function Pig.heart(p)
    local w, h = Pig.size(p)
    local g = function() return (rnd() + rnd() + rnd() - 1.5) * 0.02 end
    spawnFx("heart", p.x + (rnd() * w * 2 - w), p.y + 0.5 + rnd() * h, p.z + (rnd() * w * 2 - w), g(), g(), g())
end

-- Облачко смерти: 20 дымков в объёме тела.
function Pig.poof(p)
    local w, h = Pig.size(p)
    local g = function() return (rnd() + rnd() + rnd() - 1.5) * 0.02 end
    for _ = 1, 20 do
        spawnFx("explode", p.x + (rnd() * w * 2 - w), p.y + rnd() * h, p.z + (rnd() * w * 2 - w), g(), g(), g())
    end
end

local function fxTick()
    local i = 1
    while i <= #fx do
        local e = fx[i]
        e.age = e.age + 1
        if e.age >= e.life then
            DestroyObject(e.obj)
            table.remove(fx, i)
        else
            if e.kind == "heart" then
                e.x, e.y, e.z = e.x + e.vx, e.y + e.vy, e.z + e.vz
                e.vx, e.vy, e.vz = e.vx * 0.86, e.vy * 0.86, e.vz * 0.86
            else
                e.vy = e.vy + 0.004
                e.x, e.y, e.z = e.x + e.vx, e.y + e.vy, e.z + e.vz
                e.vx, e.vy, e.vz = e.vx * 0.9, e.vy * 0.9, e.vz * 0.9
                local f = 7 - math.floor(e.age * 8 / e.life)
                if f ~= e.frame and f >= 0 then
                    e.frame = f
                    fxQuad(f).apply(e.obj)
                    SetMaterial(e.obj, "assets/materials/particle_smoke.sagemat")
                    e.obj:GetRenderer().Color = Vec3(e.gray, e.gray, e.gray)
                end
            end
            i = i + 1
        end
    end
end

-- --- Кадр -------------------------------------------------------------------

local function lerpAngle(a, b, t) return a + wrap(b - a) * t end

local function render(p, t, cam)
    local x = p.px + (p.x - p.px) * t
    local y = p.py + (p.y - p.py) * t
    local z = p.pz + (p.z - p.pz) * t
    local body = lerpAngle(p.pbody, p.body, t)
    local head = lerpAngle(p.phead, p.headYaw, t)
    local Light = require "lightmap"
    local s, b = Light.levels(x, y + Pig.eyeHeight(p) * 0.66, z)
    local death = 0
    if p.dead then
        local f = math.sqrt(math.max(0, (p.deathTime + t - 1) / 20 * 1.6))
        death = math.min(f, 1) * 90
    end
    PM.pose(p.model, {
        x = x, y = y, z = z, yaw = 180 - body,
        -- Голова относительно тела: у оригинала yaw растёт по часовой, у нас — против.
        headYaw = -wrap(head - body), pitch = p.ppitch + (p.pitch - p.ppitch) * t,
        swing = p.pswing + (p.swing - p.pswing) * t, amount = p.pamount + (p.amount - p.pamount) * t,
        child = p.age < 0, death = death, hurt = p.hurtTime > 0 or p.dead, light = {s, b},
    })
    -- Тень (Render.doRenderShadow): 0.7, у поросёнка вдвое меньше.
    local Sh = require "shadows"
    Sh.place(p.shadow, x, y, z, p.age < 0 and 0.35 or 0.7, 1.0, cam[1], cam[2], cam[3])
end

function Pig.update(dt, P)
    acc = acc + dt
    local n = 0
    while acc >= TICK and n < 5 do
        acc, n = acc - TICK, n + 1
        local i = 1
        while i <= #Pig.list do
            local p = Pig.list[i]
            -- Участок не загружен (не построен или выгружен) — существо стоит,
            -- как сущности выгруженных участков у оригинала.
            p.frozen = not Pig.loaded(p)
            if p.frozen or tick(p, P) then i = i + 1 else remove(i) end
        end
        pushApart(P)
        fxTick()
    end
    if n == 5 then acc = 0 end
    local t = acc / TICK
    local cx, cy, cz = require("shadows").camera()
    for _, p in ipairs(Pig.list) do
        if p.frozen then
            if not p.hidden then
                p.model.root.Transform.Position = Vec3(0, -1000, 0)
                require("shadows").hide(p.shadow)
                p.hidden = true
            end
        else
            p.hidden = false
            render(p, p.ticks == 0 and 1 or t, {cx, cy, cz})
        end
    end
    for _, e in ipairs(fx) do
        e.obj.Transform.Position = Vec3(e.x, e.y, e.z)
        e.obj.Transform.Scale = Vec3(e.scale, e.scale, e.scale)
    end
end

-- --- Игрок: удар и кормление ------------------------------------------------

-- Луч (o + d·t) и коробки свиней (+0.1 — collisionBorderSize): ближайшая.
function Pig.raycast(ox, oy, oz, dx, dy, dz, maxDist)
    local best, bestT
    for _, p in ipairs(Pig.list) do
        if not p.dead then
            local w, h = Pig.size(p)
            local box = {p.x - w / 2 - 0.1, p.y - 0.1, p.z - w / 2 - 0.1, p.x + w / 2 + 0.1, p.y + h + 0.1, p.z + w / 2 + 0.1}
            local tmin, tmax = 0, maxDist
            local O, D = {ox, oy, oz}, {dx, dy, dz}
            local hit = true
            for a = 1, 3 do
                if math.abs(D[a]) < 1e-9 then
                    if O[a] < box[a] or O[a] > box[a + 3] then hit = false end
                else
                    local t1, t2 = (box[a] - O[a]) / D[a], (box[a + 3] - O[a]) / D[a]
                    if t1 > t2 then t1, t2 = t2, t1 end
                    tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
                end
            end
            if hit and tmin <= tmax and (not bestT or tmin < bestT) then best, bestT = p, tmin end
        end
    end
    return best, bestT
end

-- Сила удара (SharedMonsterAttributes.attackDamage): рука 1; меч 4 + материал,
-- топор 3 + материал, кирка 2 + материал, лопата 1 + материал (+1 базовая).
local TOOL_BASE = {sword = 4, axe = 3, pickaxe = 2, shovel = 1}
function Pig.attackDamage(held)
    local d = held and B.byId[held.id]
    if d and d.tool and TOOL_BASE[d.tool] then return 1 + TOOL_BASE[d.tool] + ((d.tier or 1) - 1) end
    return 1
end

-- Удар игрока (attackTargetEntityWithCurrentItem): крит в падении ×1.5,
-- удар с разбега — ещё отбрасывание; меч тратит 1 прочности, инструмент — 2.
function Pig.attack(p, P, held)
    local dmg = Pig.attackDamage(held)
    local crit = not P.onGround and P.vel.y < 0 and not P.inWater and not P.onLadder and not P.flying
    if crit then dmg = dmg * 1.5 end
    local hit = Pig.damage(p, dmg, {x = P.pos.x, z = P.pos.z, player = true})
    if hit and P.sprinting then
        local r = math.rad(180 - P.yaw)
        p.mx, p.my, p.mz = p.mx - math.sin(r) * 0.5, p.my + 0.1, p.mz + math.cos(r) * 0.5
        P.sprinting = false
    end
    local Hud = require "hud"
    Hud.addExhaustion(0.3)
    local d = held and B.byId[held.id]
    if hit and d and d.tool then
        local Inv = require "inventory"
        Inv.wearTool()
        if d.tool ~= "sword" then Inv.wearTool() end
    end
    return hit
end

-- ПКМ по свинье (EntityAnimal.interact): морковь взрослой с возрастом 0 не
-- в любви — любовь 600 тиков, сердечки, морковь тратится. true — съедено.
function Pig.interact(p, held)
    if p.dead or not held or held.id ~= B.byName.carrot.id then return false end
    if p.age ~= 0 or p.love > 0 then return false end
    p.love = 600
    for _ = 1, 7 do Pig.heart(p) end
    return true
end

-- --- Сохранение -------------------------------------------------------------

function Pig.serialize()
    local out = {}
    for _, p in ipairs(Pig.list) do
        if not p.dead then
            out[#out + 1] = {x = p.x, y = p.y, z = p.z, yaw = p.yaw, head = p.headYaw, pitch = p.pitch, body = p.body,
                             health = p.health, age = p.age, love = p.love, mx = p.mx, my = p.my, mz = p.mz,
                             air = p.air, fall = p.fall}
        end
    end
    return out
end

function Pig.clear()
    while #Pig.list > 0 do remove(#Pig.list) end
    for _, e in ipairs(fx) do DestroyObject(e.obj) end
    fx = {}
end

function Pig.load(data)
    Pig.clear()
    if type(data) ~= "table" then return end
    for _, d in pairs(data) do
        local p = Pig.spawn(d.x, d.y, d.z, d.yaw, d.age or 0)
        p.headYaw, p.pitch, p.body = d.head or p.yaw, d.pitch or 0, d.body or p.yaw
        p.health, p.love = d.health or Pig.MAX_HEALTH, d.love or 0
        p.mx, p.my, p.mz, p.air, p.fall = d.mx or 0, d.my or 0, d.mz or 0, d.air or 300, d.fall or 0
        p.px, p.py, p.pz, p.pyaw, p.phead, p.pbody = p.x, p.y, p.z, p.yaw, p.headYaw, p.body
    end
end

-- --- Появление при создании мира (SpawnerAnimals.performWorldGenSpawning) ------

-- Биомы без животных: океан, пляж, пустыня (как у 1.7.10).
local function biomeAllows(x, z)
    local h, b = require("gen").column(x, z)
    if b == "desert" then return false end
    if h < W.SEA - 3 or (h <= W.SEA + 1 and h >= W.SEA - 3) then return false end
    return true
end

-- Клетка (x, y, z) годится существу (canCreatureTypeSpawnAtLocation): под ногами
-- глухой блок не из бедрока, в клетке и над ней — не твёрдое и не жидкость.
local function spawnable(x, y, z)
    local below = W.get(x, y - 1, z)
    if not B.opaque[below] or below == B.byName.bedrock.id then return false end
    for dy = 0, 1 do
        local id = W.get(x, y + dy, z)
        if B.solid[id] or B.drawKind[id] == 4 or B.opaque[id] then return false end
    end
    return true
end

-- Верх: первый сверху твёрдый или жидкий блок, клетка над ним (getTopSolidOrLiquidBlock).
local function topY(x, z)
    for y = W.HEIGHT - 2, 1, -1 do
        local id = W.get(x, y, z)
        if id ~= 0 and (B.solid[id] or B.drawKind[id] == 4) and not B.isLeaves[id] then return y + 1 end
    end
    return nil
end

-- Участок (cx, cz) впервые построен: пока rand < 0.1 (getSpawningChance), группа.
-- Из списка существ биома (овца 12, свинья 10, курица 10, корова 8) в игре
-- есть только свинья — группа выбирается с её долей 10/40, иначе пропускается.
-- Группа — 4 свиньи у случайной точки участка со сдвигами rand(5) − rand(5).
Pig.spawnedChunks = {}
function Pig.chunkReady(cx, cz)
    local key = cx .. "," .. cz
    if Pig.spawnedChunks[key] then return 0 end
    Pig.spawnedChunks[key] = true
    local x0, z0 = cx * 16, cz * 16
    if not biomeAllows(x0 + 8, z0 + 8) then return 0 end
    local made = 0
    while rnd() < 0.1 do
        if rnd(1, 40) <= 10 then
            local x, z = x0 + rnd(0, 15), z0 + rnd(0, 15)
            local sx, sz = x, z
            for _ = 1, 4 do
                local ok = false
                for _ = 1, 4 do
                    if ok then break end
                    local y = topY(x, z)
                    if y and spawnable(x, y, z) then
                        Pig.spawn(x + 0.5, y, z + 0.5, rnd() * 360, 0)
                        made = made + 1
                        ok = true
                    end
                    x, z = x + rnd(0, 4) - rnd(0, 4), z + rnd(0, 4) - rnd(0, 4)
                    local guard = 0
                    while (x < x0 or x >= x0 + 16 or z < z0 or z >= z0 + 16) and guard < 20 do
                        x, z = sx + rnd(0, 4) - rnd(0, 4), sz + rnd(0, 4) - rnd(0, 4)
                        guard = guard + 1
                    end
                end
            end
        end
    end
    return made
end

function Pig.saveChunks()
    local out = {}
    for k in pairs(Pig.spawnedChunks) do out[#out + 1] = k end
    return out
end
function Pig.loadChunks(list)
    Pig.spawnedChunks = {}
    if type(list) ~= "table" then return end
    for _, k in pairs(list) do Pig.spawnedChunks[k] = true end
end

Pig.tick = tick
return Pig
