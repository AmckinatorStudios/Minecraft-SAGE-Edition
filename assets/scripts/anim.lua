-- ---------------------------------------------------------------------------
-- anim.lua — состояние анимаций игрока по правилам Minecraft Java 1.7.10.
--
-- В оригинале всё, что двигает руки, ноги, тело, предмет и камеру, — числа,
-- обновляемые 20 раз в секунду (тик), а кадр берёт их с долей тика (partial):
--   * взмах руки — 6 тиков (EntityLivingBase.updateArmSwingProgress);
--     повторный взмах начинается, только если прошлый прошёл половину;
--   * раскачка конечностей — limbSwing/limbSwingAmount по пройденному за тик
--     (×4, не больше 1, сглаживание 0.4) — у бега цикл быстрее сам собой;
--   * тело (renderYawOffset) — к направлению движения со сглаживанием 0.3,
--     не дальше 75° от взгляда; при взмахе — к взгляду;
--   * покачивание камеры — cameraYaw/cameraPitch и distanceWalkedModified
--     (EntityPlayer.onLivingUpdate, EntityRenderer.setupViewBobbing);
--   * отставание руки от взгляда — renderArmPitch/Yaw (×0.5 за тик);
--   * смена предмета — equippedProgress (±0.4 за тик: опускается, предмет
--     меняется ниже 0.1, поднимается);
--   * использование предмета — itemInUseCount (еда/питьё 32 тика, лук и
--     защита мечом — пока держат кнопку).
-- Присед в 1.7.10 включается мгновенно; здесь он плавно доходит до позы за
-- ~0.1 с (без скачка), а сами числа позы — оригинальные.
-- ---------------------------------------------------------------------------
local A = {}

local TICK = 1 / 20
local acc = 0
A.partial = 0
A.ticks = 0

-- Взмах
local swingInt, swinging = 0, false
local swingP, prevSwingP = 0, 0
-- Конечности
local limbSwing, limbAmt, prevLimbAmt = 0, 0, 0
-- Тело и взгляд (градусы, рыскание — в соглашении игры, без обрезки до 360)
local bodyYaw, prevBodyYaw = nil, nil
local lastYaw, yawUnwrapped = nil, 0
local tickX, tickY, tickZ
-- Камера
local walked, prevWalked = 0, 0
local camYaw, prevCamYaw, camPitch, prevCamPitch = 0, 0, 0, 0
-- Рука
local armPitch, prevArmPitch, armYaw, prevArmYaw = 0, 0, 0, 0
-- Предмет
local equipped, prevEquipped = 0, 0
local renderId, renderSlot = 0, -1
-- Использование
A.use = nil   -- {id, count, max, action, onFinish}
-- Присед (0..1)
A.sneak = 0

local function wrap(a)
    a = a % 360
    if a >= 180 then a = a - 360 end
    return a
end
A.wrap = wrap

function A.swingItem()
    -- EntityLivingBase.swingItem: новый взмах, если прошлый закончен или
    -- прошёл половину (6 / 2 тика).
    if not swinging or swingInt >= 3 or swingInt < 0 then
        swingInt = -1
        swinging = true
    end
end

-- Начать использовать предмет (ПКМ): action — "eat", "drink", "block", "bow".
-- max — сколько тиков до конца (еда — 32; лук и меч — 72000, «пока держат»).
function A.startUse(id, action, max, onFinish, onTick)
    A.use = {id = id, action = action, max = max, count = max, onFinish = onFinish, onTick = onTick}
end

function A.stopUse()
    local u = A.use
    A.use = nil
    return u
end

-- Сколько тиков предмет уже используется (с долей тика) — для лука.
function A.useTicks()
    local u = A.use
    if not u then return 0 end
    return u.max - (u.count - A.partial + 1)
end

local function tick(P, heldId, slot)
    A.ticks = A.ticks + 1
    -- Взмах
    prevSwingP = swingP
    if swinging then
        swingInt = swingInt + 1
        if swingInt >= 6 then swingInt = 0; swinging = false end
    else
        swingInt = 0
    end
    swingP = swingInt / 6

    -- Смещение за тик
    local dx, dy, dz = P.pos.x - tickX, P.pos.y - tickY, P.pos.z - tickZ
    tickX, tickY, tickZ = P.pos.x, P.pos.y, P.pos.z

    -- Конечности (EntityLivingBase.moveEntityWithHeading)
    prevLimbAmt = limbAmt
    local f6 = math.min(1, math.sqrt(dx * dx + dz * dz) * 4)
    limbAmt = limbAmt + (f6 - limbAmt) * 0.4
    limbSwing = limbSwing + limbAmt

    -- Тело (EntityLivingBase.onUpdate + func_110146_f)
    prevBodyYaw = bodyYaw
    local target = bodyYaw
    if dx * dx + dz * dz > 0.0025 then target = math.deg(math.atan(-dx, -dz)) end
    if swingP > 0 then target = yawUnwrapped end
    bodyYaw = bodyYaw + wrap(target - bodyYaw) * 0.3
    local f3 = wrap(yawUnwrapped - bodyYaw)
    if f3 < -75 then f3 = -75 end
    if f3 >= 75 then f3 = 75 end
    bodyYaw = yawUnwrapped - f3
    if f3 * f3 > 2500 then bodyYaw = bodyYaw + f3 * 0.2 end

    -- Камера (EntityPlayer.onLivingUpdate): сила покачивания и наклон от
    -- вертикальной скорости; путь (Entity.moveEntity, ×0.6) — не в приседе на земле.
    prevCamYaw, prevCamPitch = camYaw, camPitch
    local f = math.min(0.1, math.sqrt(dx * dx + dz * dz))
    local f1 = math.atan(-(P.vel.y * TICK) * 0.2) * 15
    if not P.onGround or P.flying then f = 0 end
    if P.onGround then f1 = 0 end
    camYaw = camYaw + (f - camYaw) * 0.4
    camPitch = camPitch + (f1 - camPitch) * 0.8
    prevWalked = walked
    if not (P.onGround and P.sneaking) then walked = walked + math.sqrt(dx * dx + dz * dz) * 0.6 end

    -- Отставание руки (EntityPlayerSP: renderArmPitch/Yaw += (взгляд − они)·0.5)
    prevArmPitch, prevArmYaw = armPitch, armYaw
    armPitch = armPitch + (P.pitch - armPitch) * 0.5
    armYaw = armYaw + (yawUnwrapped - armYaw) * 0.5

    -- Смена предмета (ItemRenderer.updateEquippedItem)
    prevEquipped = equipped
    local same = (heldId == renderId and slot == renderSlot) or (heldId == 0 and renderId == 0)
    if heldId == renderId and heldId ~= 0 then same = true; renderSlot = slot end
    local d = (same and 1 or 0) - equipped
    if d > 0.4 then d = 0.4 elseif d < -0.4 then d = -0.4 end
    equipped = equipped + d
    if equipped < 0.1 then renderId, renderSlot = heldId, slot end

    -- Использование (EntityPlayer.onUpdate): другой предмет в руке — бросить.
    local u = A.use
    if u then
        if heldId ~= u.id then
            A.use = nil
        else
            if u.onTick then u.onTick(u) end
            u.count = u.count - 1
            if u.count <= 0 then
                A.use = nil
                if u.onFinish then u.onFinish(u) end
            end
        end
    end
end

-- Каждый кадр: тики по 1/20 с, затем доля тика для плавности.
function A.update(dt, P, heldId, slot)
    if not tickX then
        tickX, tickY, tickZ = P.pos.x, P.pos.y, P.pos.z
        yawUnwrapped, lastYaw = P.yaw, P.yaw
        bodyYaw, prevBodyYaw = P.yaw, P.yaw
        armPitch, prevArmPitch, armYaw, prevArmYaw = P.pitch, P.pitch, P.yaw, P.yaw
        renderId, renderSlot = heldId, slot
        equipped, prevEquipped = 1, 1
    end
    -- Рыскание без скачка 359 -> 0: тело и рука догоняют по кратчайшей дуге.
    yawUnwrapped = yawUnwrapped + wrap(P.yaw - lastYaw)
    lastYaw = P.yaw
    acc = acc + math.min(dt, 0.25)
    while acc >= TICK do
        acc = acc - TICK
        tick(P, heldId or 0, slot or 0)
    end
    A.partial = acc / TICK
    -- Присед: к позе за ~0.1 с без рывка.
    local k = 1 - math.exp(-dt / 0.035)
    A.sneak = A.sneak + ((P.sneaking and 1 or 0) - A.sneak) * k
end

-- --- Значения с долей тика --------------------------------------------------
local function lerp(a, b, t) return a + (b - a) * t end

function A.swingProgress()
    local f = swingP - prevSwingP
    if f < 0 then f = f + 1 end
    return prevSwingP + f * A.partial
end

-- limbSwing и limbSwingAmount для модели (RendererLivingEntity.doRender).
function A.limbs()
    local amt = math.min(1, lerp(prevLimbAmt, limbAmt, A.partial))
    return limbSwing - limbAmt * (1 - A.partial), amt
end

function A.age() return A.ticks + A.partial end

-- Рыскание тела и взгляда (без обрезки до 360) — их разность и есть поворот головы.
function A.bodyYaw() return prevBodyYaw + wrap(bodyYaw - prevBodyYaw) * A.partial end
function A.viewYaw() return yawUnwrapped end

-- Покачивание камеры: путь (с долей тика), сила и наклон.
function A.bobbing()
    local w = walked + (walked - prevWalked) * A.partial
    return -w, lerp(prevCamYaw, camYaw, A.partial), lerp(prevCamPitch, camPitch, A.partial)
end

function A.armLag()
    return lerp(prevArmPitch, armPitch, A.partial), lerp(prevArmYaw, armYaw, A.partial)
end

function A.equip() return lerp(prevEquipped, equipped, A.partial), renderId end

-- Самопроверка (--gencheck, строка ANIMCHECK): числа 1.7.10 на ненастоящем
-- игроке — взмах (счётчик с −1 до 6: шесть шагов анимации, флаг снимается на
-- 7-м тике) не перезапускается в первой половине; ходьба
-- 4.317 блока/с даёт limbSwingAmount ≈ 0.86; смена предмета опускает его ниже
-- 0.1 за 3 тика и поднимает обратно за 3; еда кончается ровно на 32-м тике.
function A.selfCheck()
    local saved = {acc, swingInt, swinging, swingP, prevSwingP, limbSwing, limbAmt, prevLimbAmt, tickX}
    local P = {pos = {x = 0, y = 64, z = 0}, vel = {x = 0, y = 0, z = 0}, yaw = 0, pitch = 0,
               onGround = true, sneaking = false, flying = false}
    tickX = nil
    A.update(0, P, 0, 1)
    local T = 1 / 20
    -- Взмах
    A.swingItem()
    local swingTicks = 0
    A.update(T, P, 0, 1)
    A.swingItem()          -- вторая просьба в первой половине — не перезапуск
    swingTicks = 1
    while swinging and swingTicks < 20 do A.update(T, P, 0, 1); swingTicks = swingTicks + 1 end
    local swingOk = swingTicks == 7
    -- Ходьба
    for _ = 1, 40 do P.pos.z = P.pos.z - 4.317 * T; A.update(T, P, 0, 1) end
    local walkAmt = limbAmt
    local walkOk = math.abs(walkAmt - 0.8634) < 0.01
    -- Смена предмета: 1 -> ниже 0.1 за 3 тика (тогда меняется), снова 1 за 3.
    local downTicks, upTicks = 0, 0
    while renderId ~= 5 and downTicks < 10 do A.update(T, P, 5, 2); downTicks = downTicks + 1 end
    while equipped < 1 and upTicks < 10 do A.update(T, P, 5, 2); upTicks = upTicks + 1 end
    local equipOk = downTicks == 3 and upTicks == 3
    -- Еда: 32 тика.
    local finishedAt, ticks = nil, 0
    A.startUse(5, "eat", 32, function() finishedAt = ticks end)
    for t = 1, 40 do ticks = t; A.update(T, P, 5, 2) end
    local eatOk = finishedAt == 32
    -- Матрицы: поворот модели Z·Y·X переходит в углы движка и обратно без потерь.
    local M = require "mat"
    local m = M.modelRotation(0.4, -0.7, 0.2)
    local ex, ey, ez = M.eulerOf(m)
    local back = M.identity()
    M.rotate(back, ey, 0, 1, 0); M.rotate(back, ex, 1, 0, 0); M.rotate(back, ez, 0, 0, 1)
    local diff = 0
    for k = 1, 12 do diff = math.max(diff, math.abs(back[k] - m[k])) end
    local matOk = diff < 1e-6
    -- Присед ModelBiped: тело 0.5 рад, ноги на 4 пикселя назад и на 3 вверх.
    local a = require("avatar").bipedAngles(0, 0, 0, 0, 0, 0, 1, 0, false)
    local sneakOk = math.abs(a.bodyX - 0.5) < 1e-9 and math.abs(a.legPZ - 4) < 1e-9 and math.abs(a.legPY - 9) < 1e-9
    acc, swingInt, swinging, swingP, prevSwingP, limbSwing, limbAmt, prevLimbAmt, tickX = table.unpack(saved)
    A.use = nil
    local ok = swingOk and walkOk and equipOk and eatOk and matOk and sneakOk
    return string.format("ANIMCHECK: %s взмах=%d тиков ходьба=%.3f смена=%d+%d еда=%s матрица=%.1e присед=%s",
        ok and "PASS" or "FAIL", swingTicks, walkAmt, downTicks, upTicks, tostring(finishedAt), diff, tostring(sneakOk))
end

return A
