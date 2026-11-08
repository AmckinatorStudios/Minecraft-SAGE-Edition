-- ---------------------------------------------------------------------------
-- hurtcheck.lua — самопроверка урона от падения (--gencheck, строка
-- HURTCHECK): ceil(высота − 3) и пороги 3 / 4 / 7 / 8 блоков, звук fallsmall
-- до 4 HP и fallbig выше, звук поверхности ×0.5 / ×0.75, одно срабатывание
-- на приземление при настоящем падении физикой (любой шаг кадра), сброс в
-- воде, hurtTime 10 тиков и неуязвимость 20 (во второй половине — только
-- больший удар разницей), наклон камеры sin(f⁴π)·14 с долей тика, красная
-- модель, моргание сердец; трещины на сундуке не ломают кадр.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local H = require "hurt"

local HC = {}

function HC.selfCheck(P)
    local Hud = require "hud"
    local Snd = require "sounds"
    local res = {}
    local savedHealth, savedEvent, savedLand = Hud.health, Snd.event, Snd.land
    local events, lands = {}, {}
    Snd.event = function(name, x, y, z, v, p) events[#events + 1] = {name, v, p}; return true end
    Snd.land = function(id) lands[#lands + 1] = id end
    local function fresh() H.reset(); Hud.health = 20; events, lands = {}, {} end

    -- 1. Формула и звуки (EntityLivingBase.fall).
    local ok = true
    local dbg = ""
    for _, c in ipairs({{3.0, 0}, {2.9, 0}, {3.01, 1}, {4.0, 1}, {7.0, 4}, {7.5, 5}, {8.0, 5}, {22.0, 19}}) do
        fresh()
        local got = H.fall(c[1])
        local hp = 20 - c[2]
        local snd
        for _, e in ipairs(events) do if e[1]:match("^damage%.fall") then snd = e[1] end end
        local want = nil
        if c[2] > 0 then want = c[2] > 4 and "damage.fallbig" or "damage.fallsmall" end
        if got ~= c[2] or snd ~= want then ok = false; dbg = dbg .. " f" .. c[1] .. ":" .. tostring(got) .. tostring(snd) end
        if c[2] > 0 and (Hud.health ~= hp or #lands ~= 1) then ok = false; dbg = dbg .. " h" .. c[1] .. ":" .. Hud.health .. "/" .. #lands end
        if c[2] == 0 and (#events ~= 0 or #lands ~= 0) then ok = false; dbg = dbg .. " z" .. c[1] end
    end
    res.formula = ok

    -- 2. Удар: hurtTime 10, звук game.player.hurt; неуязвимость 20 тиков, во
    -- второй половине тот же урон не проходит, больший — разницей; hurtTime
    -- за 10 тиков — 0.
    fresh()
    local a1 = H.attack("fall", 2)
    local sameAgain = H.attack("fall", 2)
    local bigger = H.attack("fall", 5)
    local afterBig = Hud.health
    local hurtSnd = 0
    for _, e in ipairs(events) do if e[1] == "game.player.hurt" then hurtSnd = hurtSnd + 1 end end
    local t10 = H.hurtTime == 10 and H.resist == 20 and H.red()
    for _ = 1, 10 do H.tick() end
    local t0 = H.hurtTime == 0 and H.resist == 10 and not H.red()
    for _ = 1, 10 do H.tick() end
    local again = H.attack("fall", 1) and H.hurtTime == 10
    res.hurt = a1 and not sameAgain and bigger and afterBig == 15 and hurtSnd == 1 and t10 and t0 and again

    -- 3. Наклон: f = (hurtTime − доля)/10, −sin(f⁴π)·14; в начале и конце — 0.
    fresh()
    H.hurtTime = 10
    local r0 = H.roll(0)
    H.hurtTime = 8
    local r8 = H.roll(0.5)
    local f = 7.5 / 10
    H.hurtTime = 0
    local rEnd = H.roll(0.3)
    res.roll = math.abs(r0) < 1e-9 and math.abs(r8 + math.sin(f ^ 4 * math.pi) * 14) < 1e-9 and rEnd == 0

    -- 4. Падение физикой: площадка высоко, игрок над ней на h; кадры разной
    -- длины. Ровно одно приземление, высота — ровно h; 4 блока — 1 HP.
    local bx, bz = math.floor(P.pos.x) + 40, math.floor(P.pos.z) - 40
    local by = W.HEIGHT - 16
    local cells = {}
    for x = -1, 1 do
        for z = -1, 1 do
            for yy = by, W.HEIGHT - 1 do
                cells[#cells + 1] = {bx + x, yy, bz + z}
                W.setId(bx + x, yy, bz + z, yy == by and B.byName.stone.id or 0)
            end
        end
    end
    local seen = {}
    local saved = {x = P.pos.x, y = P.pos.y, z = P.pos.z, vx = P.vel.x, vy = P.vel.y, vz = P.vel.z,
                   g = P.onGround, fly = P.flying, fd = P.fallDistance, spr = P.sprinting}
    local function drop(h, dt, water)
        P.pos.x, P.pos.y, P.pos.z = bx + 0.5, by + 1 + h, bz + 0.5
        P.vel.x, P.vel.y, P.vel.z = 0, 0, 0
        P.onGround, P.flying, P.fallDistance, P.sprinting = false, false, 0, false
        if water then W.setId(bx, by + 2, bz, 11) end
        local landings, last = 0, nil
        seen = {}
        for _ = 1, 400 do
            local l = P.update({forward = 0, strafe = 0}, dt)
            if l then landings = landings + 1; last = l; seen[#seen + 1] = string.format("%.3f@%.2f", l, P.pos.y - by) end
            if P.onGround and landings > 0 then break end
        end
        if water then W.setId(bx, by + 2, bz, 0) end
        -- Ещё несколько кадров на земле — повторных приземлений нет.
        for _ = 1, 5 do if P.update({forward = 0, strafe = 0}, dt) then landings = landings + 1 end end
        return landings, last
    end
    local phys = true
    local function info() return table.concat(seen, ",") end
    for _, dt in ipairs({1 / 20, 1 / 60, 1 / 144, 1 / 33}) do
        local n4, h4 = drop(4, dt)
        local n10, h10 = drop(10, dt)
        if n4 ~= 1 or math.ceil(h4 - 3) ~= 1 or math.abs(h4 - 4) > 1e-6 then phys = false; dbg = dbg .. string.format(" p4@%.3f:%d/%s", dt, n4, tostring(h4)) .. "[" .. info() .. "]" end
        if n10 ~= 1 or math.ceil(h10 - 3) ~= 7 then phys = false; dbg = dbg .. string.format(" p10@%.3f:%d/%s", dt, n10, tostring(h10)) end
    end
    -- Вода на пути (клетка над площадкой) — высота сбрасывается: урона нет.
    local _, hw = drop(10, 1 / 60, true)
    local waterOk = hw == nil or math.ceil(hw - 3) <= 0
    if not waterOk then dbg = dbg .. " вода:" .. tostring(hw) end
    res.physics = phys and waterOk
    P.pos.x, P.pos.y, P.pos.z = saved.x, saved.y, saved.z
    P.vel.x, P.vel.y, P.vel.z = saved.vx, saved.vy, saved.vz
    P.onGround, P.flying, P.fallDistance, P.sprinting = saved.g, saved.fly, saved.fd, saved.spr
    for _, c in ipairs(cells) do W.setId(c[1], c[2], c[3], 0) end

    -- 5. Сердца: после удара — моргание (неуязвимость ≥ 10, по 3 тика).
    fresh()
    H.attack("fall", 3)
    H.resist = 18     -- 18 // 3 = 6 — чётное: обычные
    local plain = not ((H.resist >= 10) and (H.resist // 3) % 2 == 1)
    H.resist = 16     -- 16 // 3 = 5 — нечётное: белые рамки
    local white = (H.resist >= 10) and (H.resist // 3) % 2 == 1
    Hud.blinkHearts()
    res.hearts = plain and white

    -- 6. Трещины на сундуке (модель без меша участка) — без ошибки кадра.
    local okCrack = pcall(require("interact").showCrack, 5, {x = 0, y = -50, z = 0, id = B.byName.chest.id, meta = 3})
    res.crack = okCrack

    Snd.event, Snd.land = savedEvent, savedLand
    H.reset()
    Hud.health = savedHealth
    local keys = {"formula", "hurt", "roll", "physics", "hearts", "crack"}
    local all, parts = true, {}
    for _, k in ipairs(keys) do
        if not res[k] then all = false end
        parts[#parts + 1] = k .. "=" .. tostring(res[k] and true or false)
    end
    return "HURTCHECK: " .. (all and "PASS " or "FAIL ") .. table.concat(parts, " ") .. dbg
end

return HC
