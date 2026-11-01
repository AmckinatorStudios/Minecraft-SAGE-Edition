-- ---------------------------------------------------------------------------
-- autopilot.lua — прогон без рук для проверки игры (--autopilot=1).
--
-- Игрок идёт вперёд, прыгает, оглядывается, ломает блок под прицелом,
-- ставит его обратно, открывает рюкзак — то есть проходит все системы игры
-- по разу. --quit=1 — выйти по окончании; итог — строка AUTOPILOT в логе.
-- ---------------------------------------------------------------------------
local Auto = {}

Auto.active = false
local t = 0
local stage = 1
local broken, placed, collected = 0, 0, 0
local acts = {}

function Auto.init()
    Auto.active = LaunchFlag("autopilot")
    if Auto.active then log("AUTOPILOT: старт") end
end

-- Сценарий: {секунды, ввод, действия}.
local SCRIPT = {
    {2.0, {forward = 1, strafe = 0}, {}},
    {1.0, {forward = 1, strafe = 0, jump = true}, {}},
    {1.5, {forward = 0, strafe = 1}, {}},
    {0.1, {forward = 0, strafe = 0}, {look = -60}},
    {3.0, {forward = 0, strafe = 0}, {breaking = true}},
    {0.5, {forward = 0, strafe = 0}, {}},
    {0.3, {forward = 0, strafe = 0}, {place = true}},
    {2.0, {forward = -1, strafe = 0}, {}},
}

function Auto.input(dt)
    local s = SCRIPT[stage]
    if not s then return {forward = 0, strafe = 0} end
    local inp = {}
    for k, v in pairs(s[2]) do inp[k] = v end
    return inp
end

function Auto.actions()
    local s = SCRIPT[stage]
    return s and s[3] or {}
end

function Auto.update(dt)
    if not Auto.active then return end
    local P = require "player"
    local s = SCRIPT[stage]
    if s and s[3].look and t == 0 then P.pitch = s[3].look end
    t = t + dt
    if s and t >= s[1] then
        t = 0
        stage = stage + 1
        if not SCRIPT[stage] then
            local W = require "world"
            local Act = require "interact"
            local chunks = 0
            for _ in pairs(W.chunks) do chunks = chunks + 1 end
            local st = Act.stats
            -- Прогон считается пройденным, только если игра реально сделала
            -- всё по разу: сломала, подобрала, поставила, и мир вокруг есть.
            local ok = st.broken >= 1 and st.picked >= 1 and st.placed >= 1 and chunks > 0
            log(string.format("AUTOPILOT: %s участков=%d сломано=%d подобрано=%d поставлено=%d позиция=%.1f,%.1f,%.1f",
                ok and "PASS" or "FAIL", chunks, st.broken, st.picked, st.placed, P.pos.x, P.pos.y, P.pos.z))
            if LaunchFlag("quit") then game.Quit() end
            Auto.active = false
        end
    end
end

return Auto
