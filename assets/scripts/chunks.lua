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
    for idx, id in pairs(e) do
        local lx, lz, y = idx % 16, (idx // 16) % 16, idx // 256
        W.setId(c.cx * 16 + lx, y, c.cz * 16 + lz, id)
    end
end

-- Запомнить правку игрока (её и только её пишет сохранение).
function C.recordEdit(x, y, z, id)
    local key = W.ckey(x >> 4, z >> 4)
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

local function buildChunk(c)
    for sy = 0, W.SECTIONS - 1 do
        if c.sec[sy] then C.buildSection(c.cx, sy, c.cz) end
    end
    c.built = true
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
    if #order == 0 or C._r ~= r then buildOrder(r + 2); C._r = r end
    local pcx, pcz = math.floor(px) >> 4, math.floor(pz) >> 4
    local t0 = now()
    local busy = false
    local function overBudget()
        return budget and (now() - t0) * 1000 > budget
    end

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
    for _, o in ipairs(order) do
        local cx, cz, d2 = pcx + o[1], pcz + o[2], o[3]
        if d2 <= (r + 1) * (r + 1) then
            local c = W.chunk(cx, cz)
            if c and not c.lit and neighborsReady(cx, cz, "generated") then
                local t = now()
                L.lightChunk(c)
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
                buildChunk(c)
                C.stats.mesh = C.stats.mesh + (now() - t)
                busy = true
                if overBudget() then return true end
            end
        end
    end
    -- Изменённые секции (правки игрока, свет) — сразу, не в очередь: игрок
    -- должен видеть результат удара в тот же кадр.
    for key in pairs(W.dirty) do
        local sy = key % 16
        local ck = key // 16
        local cx, cz = ck // 65536 - 32768, ck % 65536 - 32768
        local c = W.chunk(cx, cz)
        if c and c.built then C.buildSection(cx, sy, cz) else W.dirty[key] = nil end
    end
    -- Выгрузка далёких: правки игрока сохранены в C.edits и вернутся.
    local far = (r + 4) * (r + 4)
    for key, c in pairs(W.chunks) do
        local dx, dz = c.cx - pcx, c.cz - pcz
        if dx * dx + dz * dz > far then unloadChunk(c) end
    end
    return busy
end

function C.clear()
    for _, c in pairs(W.chunks) do unloadChunk(c) end
    W.chunks = {}
    W.dirty = {}
end

return C
