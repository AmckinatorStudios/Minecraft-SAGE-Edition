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
P.fallDistance = 0        -- накопленная высота падения (Entity.fallDistance)

local GRAVITY = 32
local JUMP = 9.0
-- Скорости Minecraft, блоков в секунду: шаг 4.317, бег 5.612, присед
-- 1.31, полёт 10.92.
local WALK, SPRINT, SNEAK, FLY = 4.317, 5.612, 1.31, 10.92
local LADDER_TICK = 0.15   -- предел скорости на лестнице, блоков за тик
-- Пересекает ли коробка игрока (ноги в x, y, z) коробки столкновения блоков
-- (bounds.lua: у кактуса — уже клетки, у факела и растений — никакой).
-- Клетки берутся и на одну ниже: коробка столкновения может торчать вверх
-- из своей клетки (забор у оригинала — 1.5 блока).
local Bounds = require "bounds"
local function collides(x, y, z)
    local h = P.WIDTH / 2
    local ax0, ax1, ay0, ay1, az0, az1 = x - h, x + h, y, y + P.HEIGHT, z - h, z + h
    local x0, x1 = math.floor(ax0), math.floor(ax1 - 1e-4)
    local y0, y1 = math.floor(ay0) - 1, math.floor(ay1 - 1e-4)
    local z0, z1 = math.floor(az0), math.floor(az1 - 1e-4)
    for by = y0, y1 do
        for bz = z0, z1 do
            for bx = x0, x1 do
                local id = W.get(bx, by, bz)
                if id ~= 0 and Bounds.overlaps(id, W.meta(bx, by, bz), bx, by, bz, ax0, ay0, az0, ax1, ay1, az1) then
                    return true
                end
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
        if collides(nx, ny, nz) then
            -- Упёрлись: доходим вплотную (Entity.moveEntity обрезает сдвиг по
            -- коробкам столкновения), а не стоим в зазоре до длины шага. Иначе
            -- игрок «приземлялся» в воздухе на десятые доли блока выше пола,
            -- падал снова — и падение засчитывалось дважды, а его высота
            -- выходила меньше настоящей.
            local lo, hi = 0, 1
            for _ = 1, 20 do
                local mid = (lo + hi) / 2
                local tx, ty, tz = p.x, p.y, p.z
                if axis == "x" then tx = tx + step * mid elseif axis == "y" then ty = ty + step * mid else tz = tz + step * mid end
                if collides(tx, ty, tz) then hi = mid else lo = mid end
            end
            local tx, ty, tz = p.x, p.y, p.z
            if axis == "x" then tx = tx + step * lo elseif axis == "y" then ty = ty + step * lo else tz = tz + step * lo end
            -- Пол и потолок коробок — на сетке 1/16: дотягиваем высоту до неё.
            local function snap(v) return math.floor(v * 16 + 0.5) / 16 end
            if axis == "y" and math.abs(snap(ty) - ty) < 1e-4 and not collides(tx, snap(ty), tz) then ty = snap(ty) end
            p.x, p.y, p.z = tx, ty, tz
            return false
        end
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
    P.fallDistance = 0
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
    -- Бег (EntityPlayerSP.onLivingUpdate): двойное нажатие «вперёд» на земле
    -- (второе — за 7 тиков после первого) или «вперёд» при зажатом Ctrl.
    -- Нельзя, если сытость 6 и меньше (кроме полёта), при использовании
    -- предмета и в приседе (moveForward < 0.8); упёрся в стену — бег сбит.
    local Hud = require "hud"
    local using = require("anim").use ~= nil
    local fwd = input.forward > 0 and not P.sneaking and not using
    local canSprint = (not Hud.HUNGER or Hud.food > 6 or P.flying)
    P.sprintTimer = math.max(0, (P.sprintTimer or 0) - dt)
    if P.onGround and input.forwardPressed and fwd and not P.sprinting and canSprint then
        if P.sprintTimer <= 0 and not input.sprintDown then P.sprintTimer = 7 / 20
        else P.sprinting = true end
    end
    if not P.sprinting and fwd and canSprint and (input.sprintDown or input.sprintPressed) then P.sprinting = true end
    -- В воде не бегают (как в Minecraft 1.7): плывут шагом.
    if not fwd or not canSprint or (P.inWater and not P.flying) then P.sprinting = false end

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
        if input.jump and P.onGround then
            v.y = JUMP
            -- Прыжок с разбега (EntityLivingBase.jump): +0.2 блока за тик по
            -- взгляду; усталость — 0.8 за такой прыжок, 0.2 за обычный.
            local Hud = require "hud"
            if P.sprinting then
                local yr = math.rad(P.yaw)
                v.x, v.z = v.x - math.sin(yr) * 0.2 * 20, v.z - math.cos(yr) * 0.2 * 20
                Hud.addExhaustion(0.8)
            else
                Hud.addExhaustion(0.2)
            end
        end
    end

    -- Лестница (EntityLivingBase.isOnLadder: клетка ног — лестница;
    -- moveEntityWithHeading): по горизонтали не быстрее 0.15 за тик, вниз —
    -- не быстрее 0.15 за тик, в приседе не съезжают, падение не копится.
    local ladder = not P.flying and B.drawKind[W.get(math.floor(p.x), math.floor(p.y), math.floor(p.z))] == 7
    P.onLadder = ladder
    if ladder then
        local lim = LADDER_TICK * 20
        v.x = math.max(-lim, math.min(lim, v.x))
        v.z = math.max(-lim, math.min(lim, v.z))
        v.y = math.max(v.y, -lim)
        if P.sneaking and v.y < 0 then v.y = 0 end
        P.fallDistance = 0
    end

    local wasGround = P.onGround
    local beforeY = p.y
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
    -- Упёрся в стену на лестнице — лезет вверх: motionY = 0.2, затем тяжесть
    -- тика (−0.08, ×0.98) — 0.1176 блока за тик, 2.35 блока в секунду. Тяжесть
    -- следующего кадра вычтется сама — она прибавлена заранее.
    if ladder and blocked then v.y = (0.2 - 0.08) * 0.98 * 20 + GRAVITY * dt end
    if blocked and P.sprinting and not P.flying then P.sprinting = false end
    if P.flying and P.onGround then P.flying = false end

    local dx, dz = p.x - beforeX, p.z - beforeZ
    -- Путь в приседе на земле не копится (Entity.moveEntity): нет шагов и
    -- покачивания — присед в оригинале бесшумный.
    if P.onGround and not P.sneaking then P.walkDist = P.walkDist + math.sqrt(dx * dx + dz * dz) end
    -- Усталость от пути (EntityPlayer.addMovementStat): в воде 0.015 на блок,
    -- на земле бегом 0.1, шагом 0.01.
    local moved = math.sqrt(dx * dx + dz * dz)
    if not P.flying and moved > 0 then
        local Hud = require "hud"
        if P.inWater then Hud.addExhaustion(0.015 * moved)
        elseif P.onGround then Hud.addExhaustion((P.sprinting and 0.1 or 0.01) * moved) end
    end

    -- Высота падения (Entity.updateFallState): fallDistance копит каждое
    -- фактическое снижение (подъём её не уменьшает); в воде, на лестнице и в
    -- полёте — ноль. Приземлились — отдаём её один раз и обнуляем. Округление
    -- до миллионных: сумма шагов кадров даёт 4.0000000001 вместо 4, и
    -- ceil(высота − 3) прибавлял бы лишнее сердце.
    local landed = nil
    local dy = p.y - beforeY
    if P.flying or P.inWater or ladder then
        P.fallDistance = 0
    elseif not P.onGround then
        if dy < 0 then P.fallDistance = P.fallDistance - dy end
    else
        if dy < 0 then P.fallDistance = P.fallDistance - dy end
        if P.fallDistance > 0 then
            landed = math.floor(P.fallDistance * 1e6 + 0.5) / 1e6
        end
        P.fallDistance = 0
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
        if id ~= 0 then
            local meta = W.meta(x, y, z)
            local box = Bounds.selected(id, meta, x, y, z)
            if box == Bounds.FULL then
                return {x = x, y = y, z = z, id = id, meta = meta, nx = nx, ny = ny, nz = nz, dist = t, box = box}
            elseif box then
                -- Неполный блок (факел, растение, кактус): попадание — только
                -- в его коробку выбора, грань — та, через которую луч вошёл.
                local tHit, fn = Bounds.rayBox(box, x, y, z, ox, oy, oz, dx, dy, dz, maxDist)
                if tHit then
                    return {x = x, y = y, z = z, id = id, meta = meta, nx = fn[1], ny = fn[2], nz = fn[3],
                            dist = tHit, box = box}
                end
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
function P.canPlace(x, y, z, id, meta)
    local h = P.WIDTH / 2
    local p = P.pos
    -- Мешает только коробка СТОЛКНОВЕНИЯ нового блока (World.canPlaceEntityOnSide).
    return not Bounds.overlaps(id, meta or 0, x, y, z, p.x - h, p.y, p.z - h, p.x + h, p.y + P.HEIGHT, p.z + h)
end

-- Самопроверка (--gencheck, строка SPRINTCHECK): двойное «вперёд» за 7 тиков
-- включает бег, одиночное — нет; Ctrl при «вперёд» — тоже; на голодной
-- сытости (6) бега нет; прыжок с разбега — толчок вперёд и усталость 0.8;
-- кремень из гравия — вместо гравия.
function P.sprintSelfCheck()
    local Hud = require "hud"
    local save = {x = P.pos.x, y = P.pos.y, z = P.pos.z, yaw = P.yaw, food = Hud.food, ex = Hud.exhaustion,
                  fly = P.flying, ground = P.onGround, vx = P.vel.x, vy = P.vel.y, vz = P.vel.z}
    local function reset()
        P.sprinting, P.sprintTimer, P.onGround, P.flying = false, 0, true, false
        P.vel.x, P.vel.y, P.vel.z = 0, 0, 0
        P.pos.y = 300                       -- в воздухе над миром: ничего не мешает
    end
    local function step(inp) inp.forward = inp.forward or 0; inp.strafe = 0; P.onGround = true; P.update(inp, 0.05) end
    reset(); Hud.food = 20
    step({forward = 1, forwardPressed = true})
    local single = not P.sprinting
    step({forward = 0}); step({forward = 1, forwardPressed = true})
    local double = P.sprinting
    reset()
    step({forward = 1, sprintDown = true})
    local ctrl = P.sprinting
    reset(); Hud.food = 6
    step({forward = 1, sprintDown = true})
    local hungry = not P.sprinting
    reset(); Hud.food = 20; Hud.exhaustion = 0; P.yaw = 0
    P.sprinting = true
    P.update({forward = 1, strafe = 0, jump = true, sprintDown = true}, 0.0001)
    local boost = P.vel.z < -3.5 and Hud.exhaustion >= 0.8 - 1e-6
    local Act = require "interact"
    local gravel = B.byName.gravel.id
    local flint = Act.harvestDrop(gravel, 0.05) == B.byName.flint.id and Act.harvestDrop(gravel, 0.5) == gravel
    P.pos.x, P.pos.y, P.pos.z, P.yaw = save.x, save.y, save.z, save.yaw
    Hud.food, Hud.exhaustion, P.flying, P.onGround = save.food, save.ex, save.fly, save.ground
    P.vel.x, P.vel.y, P.vel.z, P.sprinting = save.vx, save.vy, save.vz, false
    local ok = single and double and ctrl and hungry and boost and flint
    return string.format("SPRINTCHECK: %s одно_нажатие=%s двойное=%s ctrl=%s голод=%s разбег=%s кремень=%s",
        ok and "PASS" or "FAIL", tostring(single), tostring(double), tostring(ctrl), tostring(hungry),
        tostring(boost), tostring(flint))
end

return P
