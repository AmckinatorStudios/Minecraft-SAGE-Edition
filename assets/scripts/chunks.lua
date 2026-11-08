-- ---------------------------------------------------------------------------
-- chunks.lua — какие участки есть в мире и какие секции видны.
--
-- Участок проходит три ступени: СГЕНЕРИРОВАН -> ОСВЕЩЁН -> ПОСТРОЕН (меши
-- секций). Свет участка ставится, только когда сгенерированы все соседи
-- (свет течёт через края), меш — когда освещены все соседи (сглаженный свет
-- и затенение углов читают клетку соседа). Поэтому вокруг видимого мира
-- всегда есть кольцо «сгенерированных, но не нарисованных» участков.
--
-- Работа делится по кадрам бюджетом в миллисекундах: ближние участки первыми,
-- чтобы под ногами мир появлялся раньше горизонта.
-- ---------------------------------------------------------------------------
local W = require "world"
local G = require "gen"
local L = require "light"
local M = require "mesher"

local C = {}

C.radius = 6                 -- участков вокруг игрока (видимость)
C.budgetMs = 6               -- миллисекунд на кадр для генерации и мешей
C.objects = {}               -- [ключ секции] = {solid=объект, liquid=объект}
C.stats = {gen = 0, light = 0, mesh = 0}   -- секунды по ступеням (отладка, F3)
C.edits = {}                 -- [ключ участка] = {[индекс клетки] = id} — что поменял игрок

local MAT_SOLID = "assets/materials/chunk.sagemat"
local MAT_LIQUID = "assets/materials/water.sagemat"

local function now() return Time.clock() end

local function neighborsReady(cx, cz, field)
    for dx = -1, 1 do
        for dz = -1, 1 do
            local c = W.chunk(cx + dx, cz + dz)
            if not c or not c[field] then return false end
        end
    end
    return true
end

local function applyEdits(c)
    local e = C.edits[W.ckey(c.cx, c.cz)]
    if not e then return end
    for idx, v in pairs(e) do
        local lx, lz, y = idx % 16, (idx // 16) % 16, idx // 256
        local x, z = c.cx * 16 + lx, c.cz * 16 + lz
        -- Правка = номер блока + метаданные × 1024 (ориентация факела).
        W.setId(x, y, z, v & 0x3FF)
        if v >= 1024 then W.setMeta(x, y, z, v >> 10) end
    end
end

-- Запомнить правку игрока (её и только её пишет сохранение).
function C.recordEdit(x, y, z, id, meta)
    if meta and meta > 0 then id = id | (meta << 10) end
    local key = W.ckey(x // 16, z // 16)
    local e = C.edits[key]
    if not e then e = {}; C.edits[key] = e end
    e[(x & 15) + (z & 15) * 16 + y * 256] = id
end

local function placeObject(cx, sy, cz, kind, arrays, material)
    local key = W.skey(cx, sy, cz)
    local slot = C.objects[key]
    if not slot then slot = {}; C.objects[key] = slot end
    local obj = slot[kind]
    if arrays.n == 0 then
        if obj then DestroyObject(obj); slot[kind] = nil end
        return
    end
    if not obj then
        obj = SpawnObject(string.format("Section %d %d %d %s", cx, sy, cz, kind))
        obj.Transform.Position = Vec3(cx * 16, sy * 16, cz * 16)
        slot[kind] = obj
    end
    local m = mesh()
    m.arrays(arrays)
    m.apply(obj)
    SetMaterial(obj, material)
end

function C.buildSection(cx, sy, cz)
    local solid, liquid = M.build(cx, sy, cz)
    placeObject(cx, sy, cz, "solid", solid, MAT_SOLID)
    placeObject(cx, sy, cz, "liquid", liquid, MAT_LIQUID)
    W.dirty[W.skey(cx, sy, cz)] = nil
end

-- Меш участка — по секции за раз: целиком участок строится десятки
-- миллисекунд, и при ходьбе каждый новый участок был заметным рывком кадра.
-- true — участок готов.
local function buildChunkStep(c, overBudget)
    local sy = c.nextSec or 0
    while sy < W.SECTIONS do
        if c.sec[sy] then C.buildSection(c.cx, sy, c.cz) end
        sy = sy + 1
        c.nextSec = sy
        if sy < W.SECTIONS and overBudget() then return false end
    end
    c.built = true
    c.nextSec = nil
    return true
end

local function unloadChunk(c)
    for sy = 0, W.SECTIONS - 1 do
        local key = W.skey(c.cx, sy, c.cz)
        local slot = C.objects[key]
        if slot then
            for _, o in pairs(slot) do DestroyObject(o) end
            C.objects[key] = nil
        end
        W.dirty[key] = nil
    end
    W.chunks[W.ckey(c.cx, c.cz)] = nil
end

-- --- Генерация в фоновых задачах ------------------------------------------------
--
-- Участок строит genjob.lua в потоке воркера движка (tasks.run): главный поток
-- только ставит задачи (ближние — первыми) и забирает готовые секции. Задач в
-- полёте — по две на воркер: больше — лишняя память и устаревшие участки,
-- если игрок быстро улетел; меньше — воркеры простаивают.
C.pending = {}       -- [ключ участка] = номер задачи
C.inFlight = 0
C.orphans = {}
C.stats.genAsync = 0

function C.asyncGen()
    if C.forceSync or LaunchFlag("syncgen") then return false end
    return tasks ~= nil and tasks.run ~= nil and require("gen").seed ~= nil
end

function C.maxInFlight() return math.max(2, (tasks.workers() or 1) * 2) end

function C.requestGenerate(cx, cz)
    local id = tasks.run("genjob", "build", require("gen").seed, cx, cz)
    C.pending[W.ckey(cx, cz)] = {id = id, cx = cx, cz = cz, seed = require("gen").seed}
    C.inFlight = C.inFlight + 1
end

-- Забрать готовые участки (не больше нескольких за кадр — у каждого копия
-- секций). Участок, от которого игрок уже далеко, или из старого мира
-- (другое зерно), — выбрасывается.
function C.collectGenerated(pcx, pcz, r)
    local got = false
    local taken = 0
    for i = #C.orphans, 1, -1 do
        if tasks.result(C.orphans[i]) ~= nil then table.remove(C.orphans, i) end
    end
    local keys = {}
    for k in pairs(C.pending) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
        local p = C.pending[k]
        local ok, top, secs = tasks.result(p.id)
        if ok ~= nil then
            C.pending[k] = nil
            C.inFlight = C.inFlight - 1
            local dx, dz = p.cx - pcx, p.cz - pcz
            if ok and p.seed == require("gen").seed and dx * dx + dz * dz <= (r + 3) * (r + 3)
                and not W.chunk(p.cx, p.cz) then
                local t = now()
                local c = W.newChunk(p.cx, p.cz)
                c.top = top
                for sy = 0, top do c.sec[sy] = secs[sy + 1] end
                c.generated = true
                applyEdits(c)
                C.stats.gen = C.stats.gen + (now() - t)
                C.stats.genAsync = C.stats.genAsync + 1
                got = true
                taken = taken + 1
            elseif not ok then
                logError("SAGE Craft: chunk generation task failed: " .. tostring(top))
                C.forceSync = true
            end
            if taken >= 4 then break end
        end
    end
    return got
end

-- Порядок обхода — кольцами от центра.
local order = {}
local function buildOrder(r)
    order = {}
    for dx = -r, r do
        for dz = -r, r do order[#order + 1] = {dx, dz, dx * dx + dz * dz} end
    end
    table.sort(order, function(a, b) return a[3] < b[3] end)
end

-- Один шаг загрузки мира вокруг (px, pz); false — всё готово.
-- budget — миллисекунды (nil — без ограничения: загрузка до старта игры).
function C.update(px, pz, budget)
    local r = C.radius
    if #order == 0 or C._r ~= r then buildOrder(r + 2); C._r = r; C._settled = nil end
    local pcx, pcz = math.floor(px) // 16, math.floor(pz) // 16
    local t0 = now()
    local busy = false
    -- Мир вокруг уже готов, игрок в том же участке и правок нет — обходить
    -- сотни участков ради «делать нечего» каждый кадр незачем.
    if C._settled == W.ckey(pcx, pcz) and next(W.dirty) == nil then return false end
    local function overBudget()
        return budget and (now() - t0) * 1000 > budget
    end
    -- Выгрузка далёких — ДО работы по бюджету: стояла в конце, и пока игрок
    -- летит, бюджет кадра всегда кончался раньше (return true выше по
    -- тексту) — участки не выгружались вовсе, память и обходы росли без
    -- конца («чем дальше играть, тем хуже»). Правки игрока — в C.edits.
    local far = (r + 3) * (r + 3)
    for _, c in pairs(W.chunks) do
        local dx, dz = c.cx - pcx, c.cz - pcz
        if dx * dx + dz * dz > far then unloadChunk(c) end
    end

    -- Генерация: в фоновых задачах движка (tasks — свои потоки, по участку на
    -- задачу), если они есть; иначе — здесь же, по бюджету.
    if C.asyncGen() then
        if C.collectGenerated(pcx, pcz, r) then busy = true end
        local free = C.maxInFlight() - C.inFlight
        for _, o in ipairs(order) do
            if free <= 0 then break end
            local cx, cz, d2 = pcx + o[1], pcz + o[2], o[3]
            if d2 <= (r + 2) * (r + 2) and not W.chunk(cx, cz) and not C.pending[W.ckey(cx, cz)] then
                C.requestGenerate(cx, cz)
                free = free - 1
                busy = true
            end
        end
        if C.inFlight > 0 then busy = true end
    else
        for _, o in ipairs(order) do
            local cx, cz, d2 = pcx + o[1], pcz + o[2], o[3]
            if d2 <= (r + 2) * (r + 2) then
                local c = W.chunk(cx, cz)
                if not c then
                    local t = now()
                    c = W.newChunk(cx, cz)
                    G.generate(c)
                    applyEdits(c)
                    C.stats.gen = C.stats.gen + (now() - t)
                    busy = true
                    if overBudget() then return true end
                end
            end
        end
    end
    for _, o in ipairs(order) do
        local cx, cz, d2 = pcx + o[1], pcz + o[2], o[3]
        if d2 <= (r + 1) * (r + 1) then
            local c = W.chunk(cx, cz)
            if c and not c.lit and neighborsReady(cx, cz, "generated") then
                local t = now()
                L.lightChunk(c)
                -- Животные при первом создании участка (performWorldGenSpawning).
                require("pig").chunkReady(cx, cz)
                C.stats.light = C.stats.light + (now() - t)
                busy = true
                if overBudget() then return true end
            end
        end
    end
    for _, o in ipairs(order) do
        local cx, cz, d2 = pcx + o[1], pcz + o[2], o[3]
        if d2 <= r * r then
            local c = W.chunk(cx, cz)
            if c and c.lit and not c.built and neighborsReady(cx, cz, "lit") then
                local t = now()
                local done = buildChunkStep(c, overBudget)
                C.stats.mesh = C.stats.mesh + (now() - t)
                busy = true
                if not done or overBudget() then return true end
            end
        end
    end
    -- Изменённые секции (правки игрока, свет) — сразу, не в очередь: игрок
    -- должен видеть результат удара в тот же кадр.
    -- По снимку ключей: пересборка может пометить соседние секции.
    local dirtyKeys = {}
    for key in pairs(W.dirty) do dirtyKeys[#dirtyKeys + 1] = key end
    for _, key in ipairs(dirtyKeys) do
        local sy = key % 16
        local ck = key // 16
        local cx, cz = ck // 65536 - 32768, ck % 65536 - 32768
        local c = W.chunk(cx, cz)
        if c and c.built then
            C.buildSection(cx, sy, cz)
            C.stats.rebuilt = (C.stats.rebuilt or 0) + 1
        else
            W.dirty[key] = nil
        end
    end
    C._settled = (not busy) and W.ckey(pcx, pcz) or nil
    return busy
end

function C.clear()
    C._settled = nil
    -- Задачи старого мира досчитаются, но их результат не нужен: номера — в
    -- сироты, их забирают и выбрасывают (иначе копии копились бы в движке).
    for _, p in pairs(C.pending) do C.orphans[#C.orphans + 1] = p.id end
    C.pending, C.inFlight = {}, 0
    for _, c in pairs(W.chunks) do unloadChunk(c) end
    W.chunks = {}
    W.dirty = {}
end

return C
