-- ---------------------------------------------------------------------------
-- light.lua — освещение по вокселям: два уровня 0..15 в каждой клетке.
--
-- СВЕТ НЕБА идёт сверху вниз без потерь, пока над клеткой только прозрачное,
-- а вбок и под навесы — с потерей 1 на клетку. СВЕТ БЛОКОВ (факел,
-- светокамень) — от источника во все стороны с потерей 1 на клетку. Листва и
-- вода гасят свет сильнее воздуха (B.absorb).
--
-- Распространение — волна по очереди (BFS). Правка блока — две волны: сначала
-- «снятие» света, который держался на изменённой клетке (он гаснет везде, куда
-- дотянулся только через неё), потом «заливка» от всех уцелевших краёв.
-- Пересчитывать весь участок на каждую правку было бы на два порядка дороже.
--
-- Время суток здесь НЕ участвует: в клетке лежит «сколько неба видно», а
-- день это или ночь, решает шейдер одним множителем. Поэтому закат не
-- пересобирает ни одного меша.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local L = {}

local ID_MASK, SKY, BLK = W.ID_MASK, W.SKY_SHIFT, W.BLK_SHIFT
local absorb, emit = B.absorb, B.emit
local raw, setRaw = W.raw, W.setRaw

-- Клетка очереди одним числом: x, z — со сдвигом в положительные, y — 8 бит.
local OFF = 1 << 20
local function pack(x, y, z) return ((x + OFF) << 29) | ((z + OFF) << 8) | y end
local function unpackXYZ(p)
    return ((p >> 29) & 0x1FFFFF) - OFF, p & 0xFF, ((p >> 8) & 0x1FFFFF) - OFF
end

local DIRS = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}

L.markDirty = true   -- во время первичного освещения меши ещё не построены

local function setChannel(x, y, z, v, shift, level)
    local nv = (v & ~(15 << shift)) | (level << shift)
    setRaw(x, y, z, nv)
    if L.markDirty then W.markDirty(x, y, z) end
end

-- Заливка: из каждой клетки очереди свет течёт в соседей, где его меньше.
-- Конец очереди — явный счётчик tail, а не #queue: обработанные клетки
-- освобождаются (queue[head] = nil), и длина таблицы с дырой в начале в Lua
-- не определена — волна обрывалась через пару клеток (факел светил на три
-- блока вместо четырнадцати).
local function spread(queue, shift, isSky)
    local head, tail = 1, #queue
    while head <= tail do
        local x, y, z = unpackXYZ(queue[head])
        queue[head] = nil
        head = head + 1
        local v = raw(x, y, z)
        if v then
            local level = (v >> shift) & 15
            if level > 1 then
                for d = 1, 6 do
                    local dir = DIRS[d]
                    local nx, ny, nz = x + dir[1], y + dir[2], z + dir[3]
                    if ny >= 0 and ny < W.HEIGHT then
                        local nv = raw(nx, ny, nz)
                        if nv then
                            local a = absorb[nv & ID_MASK]
                            if a < 15 then
                                local nl
                                if isSky and d == 4 and level == 15 and a == 1 then nl = 15
                                else nl = level - a end
                                if nl > ((nv >> shift) & 15) then
                                    setChannel(nx, ny, nz, nv, shift, nl)
                                    tail = tail + 1
                                    queue[tail] = pack(nx, ny, nz)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Снятие: гасим всё, что держалось на клетках очереди; более яркие соседи
-- (у них свой источник) идут в очередь заливки.
local function unspread(removeQ, refillQ, shift, isSky)
    local head, tail = 1, #removeQ
    while head <= tail do
        local p = removeQ[head]
        removeQ[head] = nil
        local level = removeQ.levels[head]
        removeQ.levels[head] = nil
        head = head + 1
        local x, y, z = unpackXYZ(p)
        for d = 1, 6 do
            local dir = DIRS[d]
            local nx, ny, nz = x + dir[1], y + dir[2], z + dir[3]
            if ny >= 0 and ny < W.HEIGHT then
                local nv = raw(nx, ny, nz)
                if nv then
                    local nl = (nv >> shift) & 15
                    if nl > 0 then
                        local fromAbove = isSky and d == 4 and level == 15 and nl == 15
                        if nl < level or fromAbove then
                            setChannel(nx, ny, nz, nv, shift, 0)
                            tail = tail + 1
                            removeQ[tail] = pack(nx, ny, nz)
                            removeQ.levels[tail] = nl
                        else
                            refillQ[#refillQ + 1] = pack(nx, ny, nz)
                        end
                    end
                end
            end
        end
    end
end

-- Первичный свет участка: столбы неба сверху вниз и источники, затем волна
-- внутри участка и через его края (в обе стороны: свет соседа заходит внутрь).
function L.lightChunk(c)
    local bx, bz = c.cx * 16, c.cz * 16
    local topY = (c.top + 1) * 16 - 1
    local skyQ, blkQ = {}, {}
    for lz = 0, 15 do
        for lx = 0, 15 do
            local level = 15
            for y = topY, 0, -1 do
                local s = c.sec[y >> 4]
                local i = lx + lz * 16 + (y & 15) * 256 + 1
                local v = s[i]
                local id = v & ID_MASK
                local a = absorb[id]
                if a >= 15 then level = 0
                elseif a > 1 then level = math.max(0, level - a) end
                local e = emit[id]
                s[i] = id | (level << SKY) | (e << BLK)
                if e > 0 then blkQ[#blkQ + 1] = pack(bx + lx, y, bz + lz) end
            end
        end
    end
    -- Волна неба: в очередь — клетки неба рядом с тёмными (края навесов, входы
    -- пещер, вода). Проверять каждую — дешевле, чем гнать волну от всех.
    for lz = 0, 15 do
        for lx = 0, 15 do
            for y = 0, topY do
                local v = c.sec[y >> 4][lx + lz * 16 + (y & 15) * 256 + 1]
                local level = (v >> SKY) & 15
                if level > 1 then
                    local x, z = bx + lx, bz + lz
                    for d = 1, 6 do
                        if d ~= 3 then
                            local dir = DIRS[d]
                            local nv = raw(x + dir[1], y + dir[2], z + dir[3])
                            if nv and ((nv >> SKY) & 15) < level - 1 and absorb[nv & ID_MASK] < 15 then
                                skyQ[#skyQ + 1] = pack(x, y, z)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    -- Свет соседних, уже освещённых участков заходит внутрь через общий край.
    for _, n in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
        local nc = W.chunk(c.cx + n[1], c.cz + n[2])
        if nc and nc.lit then
            local nTop = (math.max(nc.top, c.top) + 1) * 16 - 1
            for t = 0, 15 do
                local x, z
                if n[1] == -1 then x, z = bx - 1, bz + t
                elseif n[1] == 1 then x, z = bx + 16, bz + t
                elseif n[2] == -1 then x, z = bx + t, bz - 1
                else x, z = bx + t, bz + 16 end
                for y = 0, nTop do
                    local v = raw(x, y, z)
                    if v then
                        if ((v >> SKY) & 15) > 1 then skyQ[#skyQ + 1] = pack(x, y, z) end
                        if ((v >> BLK) & 15) > 1 then blkQ[#blkQ + 1] = pack(x, y, z) end
                    end
                end
            end
        end
    end
    local old = L.markDirty
    L.markDirty = false
    spread(skyQ, SKY, true)
    spread(blkQ, BLK, false)
    L.markDirty = old
    c.lit = true
end

-- Правка клетки: id уже записан в мир. Снимаем свет с неё, затем заливаем
-- заново от соседей и от неё самой (если она светится).
function L.update(x, y, z)
    local v = raw(x, y, z)
    if not v then return end
    local id = v & ID_MASK
    for _, ch in ipairs({{SKY, true}, {BLK, false}}) do
        local shift, isSky = ch[1], ch[2]
        local removeQ, refillQ = {levels = {}}, {}
        local level = (v >> shift) & 15
        v = raw(x, y, z)
        setChannel(x, y, z, v, shift, 0)
        removeQ[1] = pack(x, y, z)
        removeQ.levels[1] = level
        unspread(removeQ, refillQ, shift, isSky)
        -- Источник в самой клетке.
        if not isSky and emit[id] > 0 then
            setChannel(x, y, z, raw(x, y, z), shift, emit[id])
            refillQ[#refillQ + 1] = pack(x, y, z)
        end
        -- Прозрачная клетка под открытым небом снова получает 15 сверху.
        if absorb[id] < 15 then
            for d = 1, 6 do
                local dir = DIRS[d]
                local nx, ny, nz = x + dir[1], y + dir[2], z + dir[3]
                local nv = raw(nx, ny, nz)
                if nv and ((nv >> shift) & 15) > 0 then refillQ[#refillQ + 1] = pack(nx, ny, nz) end
            end
            if isSky and y + 1 >= W.HEIGHT then
                setChannel(x, y, z, raw(x, y, z), shift, 15)
                refillQ[#refillQ + 1] = pack(x, y, z)
            end
        end
        spread(refillQ, shift, isSky)
        v = raw(x, y, z)
    end
end

-- Для проверки: свет точки заново, полным пересчётом участка, — им самопроверка
-- сверяет результат пошаговых правок.
L.pack, L.unpackXYZ = pack, unpackXYZ

return L
