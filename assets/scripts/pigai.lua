-- ---------------------------------------------------------------------------
-- pigai.lua — задачи AI свиньи 1.7.10 (EntityAITasks) и их помощники:
-- PathNavigate + PathFinder (поиск пути по клеткам, вода обходится),
-- EntityMoveHelper (поворот ≤ 30° за тик, прыжок на ступень),
-- EntityLookHelper (голова 10°/тик, наклон 40), EntityBodyHelper (тело за
-- головой), RandomPositionGenerator (случайная цель с весом травы и света).
--
-- Задачи свиньи (EntityPig), приоритет — меньше важнее; биты — mutex:
--   0 Swim (4) · 1 Panic 1.25 (1) · 3 Mate 1.0 (3) · 4 Tempt 1.2 морковь на
--   удочке (3) · 4 Tempt 1.2 морковь (3) · 5 FollowParent 1.1 (0) ·
--   6 Wander 1.0 (1) · 7 WatchClosest игрок 6 (2) · 8 LookIdle (3).
-- Седла в игре нет — задачи ControlledByPlayer нет.
-- Пересмотр задач — каждый 3-й тик, выполнение — каждый тик.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Pig = require "pig"

local AI = {}
local rnd = math.random
local wrap = Pig.wrap

-- --- Взгляд, движение, тело -------------------------------------------------

local function approach(cur, target, maxStep)
    local d = wrap(target - cur)
    if d > maxStep then d = maxStep elseif d < -maxStep then d = -maxStep end
    return cur + d
end

-- EntityLookHelper.setLookPosition.
local function lookAt(p, x, y, z, dYaw, dPitch)
    local a = p.ai
    a.lookX, a.lookY, a.lookZ, a.lookYaw, a.lookPitch, a.looking = x, y, z, dYaw, dPitch, true
end

local function lookUpdate(p)
    local a = p.ai
    p.pitch = 0
    if a.looking then
        a.looking = false
        local dx, dy, dz = a.lookX - p.x, a.lookY - (p.y + Pig.eyeHeight(p)), a.lookZ - p.z
        local h = math.sqrt(dx * dx + dz * dz)
        local yaw = math.deg(math.atan(dz, dx)) - 90
        local pitch = -math.deg(math.atan(dy, h))
        p.pitch = approach(p.pitch, pitch, a.lookPitch)
        p.headYaw = approach(p.headYaw, yaw, a.lookYaw)
    else
        p.headYaw = approach(p.headYaw, p.body, 10)
    end
    local f = wrap(p.headYaw - p.body)
    if a.path then
        if f < -75 then p.headYaw = p.body - 75 end
        if f > 75 then p.headYaw = p.body + 75 end
    end
end

-- EntityMoveHelper: вперёд — 0, пока цель не задана в этом тике.
local function moveTo(p, x, y, z, speed)
    local a = p.ai
    a.moveX, a.moveY, a.moveZ, a.moveSpeed, a.moving = x, y, z, speed, true
end

local function moveUpdate(p)
    local a = p.ai
    p.forward = 0
    if not a.moving then return end
    a.moving = false
    local dx, dz = a.moveX - p.x, a.moveZ - p.z
    local dy = a.moveY - math.floor(p.y + 0.5)
    if dx * dx + dy * dy + dz * dz < 2.500000277905201e-7 then return end
    p.yaw = wrap(approach(p.yaw, math.deg(math.atan(dz, dx)) - 90, 30))
    p.moveSpeed = a.moveSpeed * Pig.SPEED
    p.forward = p.moveSpeed
    if dy > 0 and dx * dx + dz * dz < 1 then p.jumping = true end
end

-- EntityBodyHelper: в движении тело — по курсу, стоя — догоняет голову,
-- через 10 тиков без поворота головы допуск сужается от 75° к 0 за 10 тиков.
local function bound(a, b, max)
    local f = wrap(a - b)
    if f < -max then f = -max elseif f > max then f = max end
    return a - f
end

local function bodyUpdate(p)
    local a = p.ai
    local dx, dz = p.x - p.px, p.z - p.pz
    if dx * dx + dz * dz > 2.500000277905201e-7 then
        p.body = p.yaw
        p.headYaw = bound(p.body, p.headYaw, 75)
        a.prevHead, a.rotTicks = p.headYaw, 0
    else
        local f = 75
        if math.abs(p.headYaw - a.prevHead) > 15 then
            a.rotTicks, a.prevHead = 0, p.headYaw
        else
            a.rotTicks = a.rotTicks + 1
            if a.rotTicks > 10 then f = math.max(1 - (a.rotTicks - 10) / 10, 0) * 75 end
        end
        p.body = bound(p.headYaw, p.body, f)
    end
    p.body, p.headYaw = wrap(p.body), wrap(p.headYaw)
end

-- --- Поиск пути (PathFinder) --------------------------------------------------

local function isWater(id) return B.drawKind[id] == 4 end

-- Свободна ли клетка для коробки свиньи с ногами на y.
local function free(p, x, y, z)
    local w, h = Pig.size(p)
    local cx, cz = x + 0.5, z + 0.5
    return not Pig.blocked(cx - w / 2, y, cz - w / 2, cx + w / 2, y + h, cz + w / 2)
end

-- Точка пути на (x, z) рядом с высотой y (getSafePoint): шаг вверх на 1,
-- падение не больше чем на 3; вода — если разрешена.
local function safePoint(p, x, y, z, canStepUp, allowWater)
    local function ok(yy)
        local id = W.get(x, yy, z)
        if isWater(id) then return allowWater and "water" or false end
        if isWater(W.get(x, yy + 1, z)) and not allowWater then return false end
        return free(p, x, yy, z)
    end
    local r = ok(y)
    if r == false then
        if not canStepUp then return nil end
        r = ok(y + 1)
        if r == false then return nil end
        y = y + 1
    end
    if r == "water" then return y end
    -- Опора: падаем вниз, пока под ногами пусто.
    local fall = 0
    while y > 0 do
        local below = W.get(x, y - 1, z)
        if isWater(below) then
            if not allowWater then return nil end
            return y - 1
        end
        if not free(p, x, y - 1, z) then return y end
        fall = fall + 1
        if fall > 3 then return nil end
        y = y - 1
    end
    return nil
end

local DIRS = {{0, 1}, {-1, 0}, {1, 0}, {0, -1}}

-- A* по клеткам до (tx, ty, tz), не дальше range от старта. Путь — список
-- клеток {x, y, z}; если цели не достать — путь к ближайшей достигнутой.
function AI.findPath(p, tx, ty, tz, range, avoidWater)
    local sx, sy, sz = math.floor(p.x), math.floor(p.y + 0.5), math.floor(p.z)
    local allowWater = not avoidWater or p.inWater
    if p.inWater then
        -- В воде путь начинается с поверхности (getPathableYPos).
        while sy < W.HEIGHT - 1 and isWater(W.get(sx, sy, sz)) do sy = sy + 1 end
        sy = sy - 1
    end
    local function key(x, y, z) return (x * 4096 + z) * 256 + y end
    local function dist(ax, ay, az, bx, by, bz)
        local dx, dy, dz = ax - bx, ay - by, az - bz
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    local nodes = {}
    local start = {x = sx, y = sy, z = sz, g = 0}
    start.h = dist(sx, sy, sz, tx, ty, tz)
    start.f = start.h
    nodes[key(sx, sy, sz)] = start
    -- Открытый список — двоичная куча по f (Path.addPoint/dequeue оригинала):
    -- выбор лучшего за log n, а не перебором — поиск пути стоил до 300 мс.
    local heap = {start}
    start.hi = 1
    local function siftUp(i)
        local nd = heap[i]
        while i > 1 do
            local p = i // 2
            if heap[p].f <= nd.f then break end
            heap[i] = heap[p]; heap[i].hi = i
            i = p
        end
        heap[i] = nd; nd.hi = i
    end
    local function pop()
        local top = heap[1]
        local last = table.remove(heap)
        if #heap > 0 then
            local i, n = 1, #heap
            while true do
                local l, r = i * 2, i * 2 + 1
                local m = i
                local mf = last.f
                if l <= n and heap[l].f < mf then m, mf = l, heap[l].f end
                if r <= n and heap[r].f < mf then m = r end
                if m == i then break end
                heap[i] = heap[m]; heap[i].hi = i
                i = m
            end
            heap[i] = last; last.hi = i
        end
        top.hi = nil
        return top
    end
    local best = start
    local budget = 600
    while #heap > 0 and budget > 0 do
        budget = budget - 1
        local n = pop()
        n.closed = true
        if n.x == tx and n.y == ty and n.z == tz then best = n; break end
        if n.h < best.h then best = n end
        -- Шаг вверх — если над головой есть место.
        local up = free(p, n.x, n.y + 1, n.z)
        for _, d in ipairs(DIRS) do
            local nx, nz = n.x + d[1], n.z + d[2]
            local ny = safePoint(p, nx, n.y, nz, up, allowWater)
            if ny and dist(nx, ny, nz, sx, sy, sz) < range then
                local k = key(nx, ny, nz)
                local m = nodes[k]
                local g = n.g + dist(nx, ny, nz, n.x, n.y, n.z)
                if not m then
                    m = {x = nx, y = ny, z = nz, g = g, parent = n}
                    m.h = dist(nx, ny, nz, tx, ty, tz)
                    m.f = g + m.h
                    nodes[k] = m
                    heap[#heap + 1] = m
                    siftUp(#heap)
                elseif not m.closed and g < m.g then
                    m.g, m.f, m.parent = g, g + m.h, n
                    if m.hi then siftUp(m.hi) end
                end
            end
        end
    end
    if best == start then return nil end
    local path = {}
    local n = best
    while n do table.insert(path, 1, {n.x, n.y, n.z}); n = n.parent end
    return path
end

-- --- PathNavigate -------------------------------------------------------------

local function clearPath(p) p.ai.path = nil end
AI.clearPath = clearPath

local function canNavigate(p) return p.onGround or p.inWater end

-- tryMoveToXYZ: путь найден — следовать со скоростью speed.
local function tryMoveTo(p, x, y, z, speed)
    if not canNavigate(p) then return false end
    local path = AI.findPath(p, math.floor(x), math.floor(y), math.floor(z), 16, p.ai.avoidWater)
    if not path or #path < 2 then p.ai.path = nil; return false end
    local a = p.ai
    a.path, a.pathIndex, a.speed = path, 2, speed
    a.lastCheck, a.lastX, a.lastY, a.lastZ = a.totalTicks, p.x, p.y, p.z
    return true
end
AI.tryMoveTo = tryMoveTo

local function nodePos(n) return n[1] + 0.5, n[2], n[3] + 0.5 end

-- Прямой проход между точками на одной высоте (isDirectPathBetweenPoints).
local function direct(p, x0, z0, x1, z1, y)
    local dx, dz = x1 - x0, z1 - z0
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 1e-6 then return true end
    local steps = math.ceil(len / 0.5)
    for i = 1, steps do
        local x, z = x0 + dx * i / steps, z0 + dz * i / steps
        local bx, bz = math.floor(x), math.floor(z)
        if not free(p, bx, y, bz) or free(p, bx, y - 1, bz) then return false end
        local id = W.get(bx, y, bz)
        if isWater(id) or isWater(W.get(bx, y - 1, bz)) then return false end
    end
    return true
end

local function navUpdate(p)
    local a = p.ai
    a.totalTicks = a.totalTicks + 1
    local path = a.path
    if not path then return end
    if canNavigate(p) then
        local ey = math.floor(p.y + 0.5)
        local last = #path + 1
        for j = a.pathIndex, #path do
            if path[j][2] ~= ey then last = j; break end
        end
        local w = Pig.size(p)
        local f = w * w
        for k = a.pathIndex, last - 1 do
            local x, y, z = nodePos(path[k])
            local dx, dy, dz = x - p.x, y - ey, z - p.z
            if dx * dx + dy * dy + dz * dz < f then a.pathIndex = k + 1 end
        end
        for k = last - 1, a.pathIndex, -1 do
            local x, _, z = nodePos(path[k])
            if direct(p, p.x, p.z, x, z, ey) then a.pathIndex = k; break end
        end
        -- Застрял: за 100 тиков не сдвинулся на 1.5 — путь бросается.
        if a.totalTicks - a.lastCheck > 100 then
            local dx, dy, dz = p.x - a.lastX, p.y - a.lastY, p.z - a.lastZ
            if dx * dx + dy * dy + dz * dz < 2.25 then clearPath(p); return end
            a.lastCheck, a.lastX, a.lastY, a.lastZ = a.totalTicks, p.x, p.y, p.z
        end
    end
    if a.pathIndex > #path then clearPath(p); return end
    local x, y, z = nodePos(path[a.pathIndex])
    moveTo(p, x, y, z, a.speed)
end

-- --- Случайная цель (RandomPositionGenerator.findRandomTarget) ----------------

-- Вес клетки (EntityAnimal.getBlockPathWeight): трава под ногами — 10,
-- иначе яркость − 0.5.
local function pathWeight(x, y, z)
    if W.get(x, y - 1, z) == B.byName.grass.id then return 10 end
    local Sky = require "sky"
    local sub = Sky.skylightSubtracted(Sky.angle or 0, Sky.rain or 0, Sky.thunder or 0)
    local lvl = math.max((W.sky(x, y, z) or 15) - sub, W.blockLight(x, y, z) or 0)
    return require("lightmap").TABLE[math.max(0, math.min(15, lvl))] - 0.5
end

function AI.randomTarget(p, xz, yr)
    local bx, by, bz = math.floor(p.x), math.floor(p.y), math.floor(p.z)
    local found, best = nil, -99999
    for _ = 1, 10 do
        local x = bx + rnd(0, 2 * xz) - xz
        local y = by + rnd(0, 2 * yr) - yr
        local z = bz + rnd(0, 2 * xz) - xz
        local wgt = pathWeight(x, y, z)
        if wgt > best then best, found = wgt, {x, y, z} end
    end
    return found
end

-- --- Задачи -------------------------------------------------------------------

local function playerHolds(P, name)
    local s = require("inventory").current()
    return s and B.byId[s.id] and B.byId[s.id].name == name
end

local function playerDist2(p, P)
    local dx, dy, dz = P.pos.x - p.x, P.pos.y - p.y, P.pos.z - p.z
    return dx * dx + dy * dy + dz * dz
end

local function newTasks()
    local T = {}
    -- 0. Плавание: в воде — прыжок с вероятностью 0.8 за тик.
    T[#T + 1] = {name = "swim", prio = 0, mutex = 4,
        should = function(p) return p.inWater end,
        update = function(p) if rnd() < 0.8 then p.jumping = true end end}
    -- 1. Паника: после удара — бег к случайной точке 5×4 со скоростью 1.25.
    T[#T + 1] = {name = "panic", prio = 1, mutex = 1,
        should = function(p, _, t)
            if not p.revenge and not p.burning then return false end
            t.target = AI.randomTarget(p, 5, 4)
            return t.target ~= nil
        end,
        start = function(p, _, t) tryMoveTo(p, t.target[1], t.target[2], t.target[3], 1.25) end,
        continue = function(p) return p.ai.path ~= nil end}
    -- 3. Размножение: к влюблённой паре в 8 блоках, через 60 тиков рядом — поросёнок.
    T[#T + 1] = {name = "mate", prio = 3, mutex = 3,
        should = function(p, _, t)
            if p.love <= 0 then return false end
            t.mate = AI.nearbyMate(p)
            return t.mate ~= nil
        end,
        continue = function(p, _, t)
            return t.mate and not t.mate.dead and t.mate.love > 0 and (t.delay or 0) < 60 and p.love > 0
        end,
        reset = function(_, _, t) t.mate, t.delay = nil, 0 end,
        update = function(p, _, t)
            local m = t.mate
            lookAt(p, m.x, m.y + Pig.eyeHeight(m), m.z, 10, 40)
            tryMoveTo(p, m.x, m.y, m.z, 1.0)
            t.delay = (t.delay or 0) + 1
            local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
            if t.delay >= 60 and dx * dx + dy * dy + dz * dz < 9 then AI.spawnBaby(p, m) end
        end}
    -- 4. Приманка: игрок в 10 блоках с морковью (на удочке) в руке.
    for _, item in ipairs({"carrot_on_a_stick", "carrot"}) do
        T[#T + 1] = {name = "tempt_" .. item, prio = 4, mutex = 3, delay = 0,
            should = function(_, P, t)
                if t.delay > 0 then t.delay = t.delay - 1; return false end
                if not P or playerDist2(_, P) > 100 then return false end
                return playerHolds(P, item)
            end,
            start = function(p, _, t) t.saved = p.ai.avoidWater; p.ai.avoidWater = false end,
            reset = function(p, _, t) clearPath(p); t.delay = 100; p.ai.avoidWater = t.saved end,
            update = function(p, P)
                lookAt(p, P.pos.x, P.pos.y + P.EYE, P.pos.z, 30, 40)
                if playerDist2(p, P) < 6.25 then clearPath(p)
                else tryMoveTo(p, P.pos.x, P.pos.y, P.pos.z, 1.2) end
            end}
        local t = T[#T]
        t.continue = t.should
    end
    -- 5. Поросёнок — за ближайшим взрослым в 8×4×8 (9 ≤ d² ≤ 256), путь раз в 10 тиков.
    T[#T + 1] = {name = "follow", prio = 5, mutex = 0,
        should = function(p, _, t)
            if p.age >= 0 then return false end
            local best, bd
            for _, o in ipairs(Pig.list) do
                if o ~= p and not o.dead and o.age >= 0 and math.abs(o.x - p.x) <= 8 and math.abs(o.y - p.y) <= 4
                    and math.abs(o.z - p.z) <= 8 then
                    local dx, dy, dz = o.x - p.x, o.y - p.y, o.z - p.z
                    local d = dx * dx + dy * dy + dz * dz
                    if not bd or d < bd then best, bd = o, d end
                end
            end
            if not best or bd < 9 then return false end
            t.parent = best
            return true
        end,
        continue = function(p, _, t)
            local o = t.parent
            if p.age >= 0 or not o or o.dead then return false end
            local dx, dy, dz = o.x - p.x, o.y - p.y, o.z - p.z
            local d = dx * dx + dy * dy + dz * dz
            return d >= 9 and d <= 256
        end,
        start = function(_, _, t) t.delay = 0 end,
        reset = function(_, _, t) t.parent = nil end,
        update = function(p, _, t)
            t.delay = t.delay - 1
            if t.delay <= 0 then
                t.delay = 10
                tryMoveTo(p, t.parent.x, t.parent.y, t.parent.z, 1.1)
            end
        end}
    -- 6. Прогулка: пока рядом игрок (бездействие < 100), шанс 1/120 за проверку.
    T[#T + 1] = {name = "wander", prio = 6, mutex = 1,
        should = function(p, _, t)
            if p.entityAge >= 100 or rnd(0, 119) ~= 0 then return false end
            t.target = AI.randomTarget(p, 10, 7)
            return t.target ~= nil
        end,
        start = function(p, _, t) tryMoveTo(p, t.target[1], t.target[2], t.target[3], 1.0) end,
        continue = function(p) return p.ai.path ~= nil end}
    -- 7. Взгляд на игрока в 6 блоках: шанс 0.02, 40–79 тиков.
    T[#T + 1] = {name = "watch", prio = 7, mutex = 2,
        should = function(p, P) return rnd() < 0.02 and P ~= nil and playerDist2(p, P) <= 36 end,
        continue = function(p, P, t) return P ~= nil and playerDist2(p, P) <= 36 and t.time > 0 end,
        start = function(_, _, t) t.time = 40 + rnd(0, 39) end,
        update = function(p, P, t)
            lookAt(p, P.pos.x, P.pos.y + P.EYE, P.pos.z, 10, 40)
            t.time = t.time - 1
        end}
    -- 8. Оглядывание: шанс 0.02, 20–39 тиков в случайную сторону.
    T[#T + 1] = {name = "idle", prio = 8, mutex = 3,
        should = function() return rnd() < 0.02 end,
        continue = function(_, _, t) return t.time >= 0 end,
        start = function(_, _, t)
            local d = math.pi * 2 * rnd()
            t.lx, t.lz, t.time = math.cos(d), math.sin(d), 20 + rnd(0, 19)
        end,
        update = function(p, _, t)
            t.time = t.time - 1
            lookAt(p, p.x + t.lx, p.y + Pig.eyeHeight(p), p.z + t.lz, 10, 40)
        end}
    return T
end

-- Можно ли задаче работать рядом с уже идущими (EntityAITasks.canUse):
-- более важная или равная несовместимая (общие биты) — мешает.
local function canUse(tasks, t)
    for _, o in ipairs(tasks) do
        if o ~= t and o.running and t.prio >= o.prio and (t.mutex & o.mutex) ~= 0 then return false end
    end
    return true
end

local function stop(p, P, t)
    t.running = false
    if t.reset then t.reset(p, P, t) end
end

local function tasksUpdate(p, P)
    local a = p.ai
    a.tick = a.tick + 1
    local T = a.tasks
    if a.tick % 3 == 0 then
        for _, t in ipairs(T) do
            if t.running then
                if not canUse(T, t) or not (t.continue or t.should)(p, P, t) then stop(p, P, t) end
            elseif canUse(T, t) and t.should(p, P, t) then
                t.running = true
                if t.start then t.start(p, P, t) end
            end
        end
    else
        for _, t in ipairs(T) do
            if t.running and not (t.continue or t.should)(p, P, t) then stop(p, P, t) end
        end
    end
    for _, t in ipairs(T) do
        if t.running and t.update then t.update(p, P, t) end
    end
end

-- --- Размножение ----------------------------------------------------------------

function AI.nearbyMate(p)
    local best, bd
    for _, o in ipairs(Pig.list) do
        if o ~= p and not o.dead and o.love > 0 and math.abs(o.x - p.x) <= 8 and math.abs(o.y - p.y) <= 8
            and math.abs(o.z - p.z) <= 8 then
            local dx, dy, dz = o.x - p.x, o.y - p.y, o.z - p.z
            local d = dx * dx + dy * dy + dz * dz
            if not bd or d < bd then best, bd = o, d end
        end
    end
    return best
end

-- spawnBaby: родителям возраст 6000 и конец любви, поросёнку −24000, опыт 1–7, сердечки.
function AI.spawnBaby(p, m)
    p.age, m.age, p.love, m.love = 6000, 6000, 0, 0
    local baby = Pig.spawn(p.x, p.y, p.z, p.yaw, -24000)
    require("hud").addXp(rnd(1, 7))
    for _ = 1, 7 do Pig.heart(p) end
    return baby
end

-- --- Вход ------------------------------------------------------------------------

function AI.init(p)
    p.ai = {tasks = newTasks(), tick = rnd(0, 2), totalTicks = 0, avoidWater = true,
            prevHead = p.headYaw, rotTicks = 0, lastCheck = 0, lastX = p.x, lastY = p.y, lastZ = p.z}
end

-- Тик (EntityLiving.updateAITasks): задачи, навигация, движение, взгляд;
-- после физики — тело (AI.body вызывает pig.lua).
function AI.tick(p, P)
    p.jumping = false
    tasksUpdate(p, P)
    navUpdate(p)
    moveUpdate(p)
    lookUpdate(p)
end
AI.body = bodyUpdate

function AI.running(p, name)
    for _, t in ipairs(p.ai.tasks) do if t.name == name then return t.running end end
    return false
end

return AI
