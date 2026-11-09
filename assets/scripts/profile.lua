-- ---------------------------------------------------------------------------
-- profile.lua — профилировщик игры: сколько миллисекунд кадра съедает каждая
-- система (участки, свиньи, растения, сундуки, интерфейс…).
--
-- Каждый участок кадра оборачивается Prof.run("имя", функция, …) или парой
-- Prof.begin/Prof.finish. Время — Time.clock() (секунды), копится за кадр,
-- сглаживается по последним кадрам (экспонента 0.05) и держит максимум за
-- последние 2 секунды — так видно и постоянную нагрузку, и рывки.
--
-- Показ: F3 (отладочный экран) — строки «имя  среднее / пик мс»; с флагом
-- --profile=1 раз в 5 секунд сводка уходит в журнал (sage_player.log), чтобы
-- по журналу игрока было видно, что тормозит. Выключенный профилировщик
-- стоит один вызов функции на участок.
-- ---------------------------------------------------------------------------
local Prof = {}

Prof.enabled = true
local sections = {}      -- имя -> {avg, peak, peakAt, frame, calls}
local order = {}
local stack = {}
local clock = Time.clock
local frameStart = 0
Prof.frameMs, Prof.frameAvg, Prof.framePeak = 0, 0, 0
local logTimer = 0
local now = 0

local function sec(name)
    local s = sections[name]
    if not s then
        s = {avg = 0, peak = 0, peakAt = 0, frame = 0, calls = 0}
        sections[name] = s
        order[#order + 1] = name
    end
    return s
end

function Prof.begin(name)
    if not Prof.enabled then return end
    stack[#stack + 1] = {name, clock()}
end

function Prof.finish()
    if not Prof.enabled then return end
    local top = table.remove(stack)
    if not top then return end
    local s = sec(top[1])
    s.frame = s.frame + (clock() - top[2]) * 1000
    s.calls = s.calls + 1
end

-- Участок вокруг вызова f(…); возвращает её результаты.
function Prof.run(name, f, ...)
    if not Prof.enabled then return f(...) end
    local t0 = clock()
    -- Участок — и в профилировщик движка (profile.*), если он включён: там
    -- он встаёт рядом с проходами рендера, системами и временем GPU.
    local eng = Prof.engine
    if eng then profile.push(name) end
    local a, b, c = f(...)
    if eng then profile.pop() end
    local s = sec(name)
    s.frame = s.frame + (clock() - t0) * 1000
    s.calls = s.calls + 1
    return a, b, c
end

-- Начало кадра (до всех участков) и его конец.
function Prof.frameBegin()
    frameStart = clock()
    if Prof.engine == nil and profile and profile.set_enabled then
        -- --profile=1 включает и профилировщик движка (как SAGE_PROFILE=1).
        if LaunchFlag("profile") then profile.set_enabled(true) end
    end
    Prof.engine = profile ~= nil and profile.enabled ~= nil and profile.enabled() or false
end

-- Участки движка (рендер, системы, GPU) — для F3: строки «имя cpu / gpu мс».
function Prof.engineLines(n)
    if not Prof.engine then return {} end
    local out = {}
    for _, s in ipairs(profile.sections()) do
        if s.depth <= 1 then
            out[#out + 1] = string.format("%s%-14s %5.2f / %5.2f ms", string.rep(" ", s.depth * 2), s.name, s.cpu, s.gpu)
            if #out >= (n or 8) then break end
        end
    end
    return out
end

function Prof.frameEnd(dt)
    now = now + dt
    local ms = (clock() - frameStart) * 1000
    Prof.frameMs = ms
    Prof.frameAvg = Prof.frameAvg + (ms - Prof.frameAvg) * 0.05
    if ms > Prof.framePeak or now - (Prof.framePeakAt or 0) > 2 then Prof.framePeak, Prof.framePeakAt = ms, now end
    for _, name in ipairs(order) do
        local s = sections[name]
        s.avg = s.avg + (s.frame - s.avg) * 0.05
        if s.frame > s.peak or now - s.peakAt > 2 then s.peak, s.peakAt = s.frame, now end
        s.frame = 0
    end
    if LaunchFlag("profile") then
        logTimer = logTimer + dt
        if logTimer >= 5 then
            logTimer = 0
            log(Prof.report(12))
        end
    end
end

-- Сводка: самые дорогие участки (по среднему), не больше n строк.
function Prof.lines(n)
    local list = {}
    for _, name in ipairs(order) do list[#list + 1] = name end
    table.sort(list, function(a, b) return sections[a].avg > sections[b].avg end)
    local out = {}
    for i = 1, math.min(n or 10, #list) do
        local s = sections[list[i]]
        out[#out + 1] = string.format("%-12s %5.2f / %5.2f ms", list[i], s.avg, s.peak)
    end
    return out
end

-- Счётчики созданного скриптами: объектов сцены и мешей (создано − удалено
-- объектов; мешей — сколько раз собрано). Рост за время игры — утечка.
Prof.spawned, Prof.destroyed, Prof.meshes = 0, 0, 0
do
    local spawn, destroy, newMesh = SpawnObject, DestroyObject, mesh
    if spawn then SpawnObject = function(...) Prof.spawned = Prof.spawned + 1; return spawn(...) end end
    if destroy then DestroyObject = function(...) Prof.destroyed = Prof.destroyed + 1; return destroy(...) end end
    if newMesh then mesh = function(...) Prof.meshes = Prof.meshes + 1; return newMesh(...) end end
end

function Prof.report(n)
    local lines = Prof.lines(n)
    local mem = collectgarbage("count") / 1024
    local engine = ""
    if profile and profile.memory_mb then engine = string.format(", процесс %.0f МБ", profile.memory_mb()) end
    return string.format("PROFILE: кадр %.2f мс (пик %.2f), Lua %.1f МБ%s, объектов +%d −%d, мешей %d | ",
        Prof.frameAvg, Prof.framePeak, mem, engine, Prof.spawned, Prof.destroyed, Prof.meshes)
        .. table.concat(lines, " | ")
end

function Prof.section(name) return sections[name] end

return Prof
