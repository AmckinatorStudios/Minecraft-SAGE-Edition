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

-- Знаки обзора: мышь от себя — взгляд вверх, мышь вправо — поворот вправо
-- (взгляд вдоль -Z, правая рука — +X). Такая ошибка не видна ни одному
-- тесту мира, а играть с ней нельзя.
function Auto.checkLook()
    local P = require "player"
    local yaw, pitch = P.yaw, P.pitch
    P.yaw, P.pitch = 0, 0
    local _, y0 = P.lookDir()
    P.look(0, 10, 1)
    local _, y1 = P.lookDir()
    P.yaw, P.pitch = 0, 0
    P.look(10, 0, 1)
    local x2 = P.lookDir()
    P.yaw, P.pitch = yaw, pitch
    return y1 > y0 and x2 > 0
end

function Auto.init()
    Auto.active = LaunchFlag("autopilot")
    if Auto.active then
        Auto.lookOk = Auto.checkLook()
        log("AUTOPILOT: старт")
    end
end

-- Сценарий: {секунды, ввод, действия}.
local SCRIPT = {
    {2.0, {forward = 1, strafe = 0}, {}},
    {1.0, {forward = 1, strafe = 0, jump = true}, {}},
    {1.5, {forward = 0, strafe = 1}, {}},
    {0.1, {forward = 0, strafe = 0}, {look = -60}},
    {3.0, {forward = 0, strafe = 0}, {breaking = true}},
    -- Шаг к яме: добытое падает в неё и иначе остаётся вне радиуса притяжения
    -- (так прогон проваливался или проходил в зависимости от рельефа спавна).
    {1.5, {forward = 1, strafe = 0}, {}},
    -- Назад из ямы: в клетку, где стоит сам игрок, блок не ставится.
    {1.2, {forward = -1, strafe = 0, jump = true}, {}},
    {0.1, {forward = 0, strafe = 0}, {look = -60}},
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
    Auto.frames = (Auto.frames or 0) + 1
    Auto.time = (Auto.time or 0) + dt
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
            -- Правка видна, только если её секцию пересобрали: мир мог
            -- поменяться, а экран — нет (так было при отрицательных координатах).
            local rebuilt = require("chunks").stats.rebuilt or 0
            local ok = st.broken >= 1 and st.picked >= 1 and st.placed >= 1 and chunks > 0 and Auto.lookOk
                and rebuilt >= st.broken + st.placed
            log(string.format("AUTOPILOT: %s участков=%d сломано=%d подобрано=%d поставлено=%d пересобрано=%d кадров_в_с=%.0f обзор=%s позиция=%.1f,%.1f,%.1f",
                ok and "PASS" or "FAIL", chunks, st.broken, st.picked, st.placed, rebuilt, Auto.frames / math.max(Auto.time, 0.001), Auto.lookOk and "верно" or "ПЕРЕВЁРНУТ", P.pos.x, P.pos.y, P.pos.z))
            if LaunchFlag("quit") then game.Quit() end
            Auto.active = false
        end
    end
end

return Auto
