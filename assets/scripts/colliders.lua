-- ---------------------------------------------------------------------------
-- colliders.lua — блоки мира в ФИЗИКЕ ДВИЖКА (Jolt): сетки столкновений
-- секций вокруг игрока.
--
-- ЗАЧЕМ. Луч прицела и столкновения частиц идут через движок (Raycast,
-- частицы со столкновением «world»), а не своим обходом клеток: игра —
-- проверка движка, и то, что движок умеет, она у него и берёт. Физике для
-- этого нужна геометрия блоков.
--
-- ЧТО СТРОИТСЯ. Секция 16×16×16 — до трёх неподвижных тел, по слою на каждое:
--   SOLID  — полные кубы: в них целятся, о них бьются частицы;
--   SELECT — коробки ВЫБОРА неполных блоков (факел, растение, дверь, сундук):
--            только для луча прицела;
--   SHAPE  — коробки СТОЛКНОВЕНИЯ неполных блоков (дверь, сундук, кактус):
--            только для частиц. У растения и факела их нет — сквозь них летят.
-- Жидкости и воздух в сетки не входят (луч прицела сквозь воду, как в 1.7.10).
-- У полных кубов — только грани, открытые не-кубу: внутренних граней нет.
--
-- ГДЕ. Только секции в RADIUS блоков от игрока (до руки 5 блоков, осколки
-- падают рядом): 8–27 секций, а не весь мир. Сборка — по одной секции за
-- кадр, ближние первыми; правка блока помечает секцию (W.colDirty), и она
-- пересобирается. Ушедшие далеко — удаляются.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Bo = require "bounds"

local Col = {}

Col.SOLID, Col.SELECT, Col.SHAPE, Col.MOB = 2, 4, 16, 8
Col.TARGET = Col.SOLID | Col.SELECT      -- маска луча прицела по блокам
Col.PARTICLES = Col.SOLID | Col.SHAPE    -- маска столкновений частиц
Col.RADIUS = 8

local secs = {}        -- [ключ секции] = {cx, sy, cz, solid = объект, select = …, shape = …}
local count = 0
Col.built = 0          -- сколько секций собрано за игру (для профиля)

local ID_MASK = 0x3FF

-- Полный куб столкновения (быстрый путь): по id, считается один раз.
local fullCache = {}
local function isFull(id)
    local f = fullCache[id]
    if f == nil then
        f = id ~= 0 and Bo.isFullCollision(id) and Bo.selected(id, 0) == Bo.FULL or false
        fullCache[id] = f
    end
    return f
end

-- Коробка {x0, y0, z0, x1, y1, z1} (мировая) — шесть граней в массивы меша.
local function addBox(P, N, I, x0, y0, z0, x1, y1, z1)
    local function quad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, nx, ny, nz)
        local base = #P // 3
        local p, n, i = #P, #N, #I
        P[p + 1], P[p + 2], P[p + 3] = ax, ay, az
        P[p + 4], P[p + 5], P[p + 6] = bx, by, bz
        P[p + 7], P[p + 8], P[p + 9] = cx, cy, cz
        P[p + 10], P[p + 11], P[p + 12] = dx, dy, dz
        for k = 0, 3 do N[n + k * 3 + 1], N[n + k * 3 + 2], N[n + k * 3 + 3] = nx, ny, nz end
        I[i + 1], I[i + 2], I[i + 3], I[i + 4], I[i + 5], I[i + 6] = base + 1, base + 2, base + 3, base + 1, base + 3, base + 4
    end
    quad(x0, y0, z0, x1, y0, z0, x1, y0, z1, x0, y0, z1, 0, -1, 0)
    quad(x0, y1, z0, x0, y1, z1, x1, y1, z1, x1, y1, z0, 0, 1, 0)
    quad(x0, y0, z0, x0, y1, z0, x1, y1, z0, x1, y0, z0, 0, 0, -1)
    quad(x0, y0, z1, x1, y0, z1, x1, y1, z1, x0, y1, z1, 0, 0, 1)
    quad(x0, y0, z0, x0, y0, z1, x0, y1, z1, x0, y1, z0, -1, 0, 0)
    quad(x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1, 1, 0, 0)
end

-- Одна грань полного куба клетки (x, y, z) со стороны (nx, ny, nz).
local function addFace(P, N, I, x, y, z, nx, ny, nz)
    local base = #P // 3
    local p, n, i = #P, #N, #I
    local ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz
    if ny == -1 then ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = x, y, z, x + 1, y, z, x + 1, y, z + 1, x, y, z + 1
    elseif ny == 1 then ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = x, y + 1, z, x, y + 1, z + 1, x + 1, y + 1, z + 1, x + 1, y + 1, z
    elseif nz == -1 then ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = x, y, z, x, y + 1, z, x + 1, y + 1, z, x + 1, y, z
    elseif nz == 1 then ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = x, y, z + 1, x + 1, y, z + 1, x + 1, y + 1, z + 1, x, y + 1, z + 1
    elseif nx == -1 then ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = x, y, z, x, y, z + 1, x, y + 1, z + 1, x, y + 1, z
    else ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz = x + 1, y, z, x + 1, y + 1, z, x + 1, y + 1, z + 1, x + 1, y, z + 1 end
    P[p + 1], P[p + 2], P[p + 3] = ax, ay, az
    P[p + 4], P[p + 5], P[p + 6] = bx, by, bz
    P[p + 7], P[p + 8], P[p + 9] = cx, cy, cz
    P[p + 10], P[p + 11], P[p + 12] = dx, dy, dz
    for k = 0, 3 do N[n + k * 3 + 1], N[n + k * 3 + 2], N[n + k * 3 + 3] = nx, ny, nz end
    I[i + 1], I[i + 2], I[i + 3], I[i + 4], I[i + 5], I[i + 6] = base + 1, base + 2, base + 3, base + 1, base + 3, base + 4
end

-- Геометрия секции: три набора массивов (solid, select, shape).
-- Открыто для самопроверки.
function Col.geometry(cx, sy, cz)
    local c = W.chunk(cx, cz)
    local s = c and c.sec[sy]
    local sol = {P = {}, N = {}, I = {}}
    local sel = {P = {}, N = {}, I = {}}
    local shp = {P = {}, N = {}, I = {}}
    if not s then return sol, sel, shp end
    local x0, y0, z0 = cx * 16, sy * 16, cz * 16
    local get = W.get
    -- Сосед клетки: внутри секции — прямо из массива, на границе — через мир.
    local function full(lx, ly, lz)
        if lx >= 0 and lx < 16 and ly >= 0 and ly < 16 and lz >= 0 and lz < 16 then
            return isFull(s[lx + lz * 16 + ly * 256 + 1] & ID_MASK)
        end
        return isFull(get(x0 + lx, y0 + ly, z0 + lz))
    end
    local i = 0
    for ly = 0, 15 do
        for lz = 0, 15 do
            for lx = 0, 15 do
                i = i + 1
                local id = s[i] & ID_MASK
                if id ~= 0 then
                    local x, y, z = x0 + lx, y0 + ly, z0 + lz
                    if isFull(id) then
                        local P, N, I = sol.P, sol.N, sol.I
                        if not full(lx, ly - 1, lz) then addFace(P, N, I, x, y, z, 0, -1, 0) end
                        if not full(lx, ly + 1, lz) then addFace(P, N, I, x, y, z, 0, 1, 0) end
                        if not full(lx, ly, lz - 1) then addFace(P, N, I, x, y, z, 0, 0, -1) end
                        if not full(lx, ly, lz + 1) then addFace(P, N, I, x, y, z, 0, 0, 1) end
                        if not full(lx - 1, ly, lz) then addFace(P, N, I, x, y, z, -1, 0, 0) end
                        if not full(lx + 1, ly, lz) then addFace(P, N, I, x, y, z, 1, 0, 0) end
                    elseif B.drawKind[id] ~= 4 then
                        local meta = W.meta(x, y, z)
                        local b = Bo.selected(id, meta, x, y, z)
                        if b then addBox(sel.P, sel.N, sel.I, x + b[1], y + b[2], z + b[3], x + b[4], y + b[5], z + b[6]) end
                        for _, cb in ipairs(Bo.collision(id, meta, x, y, z)) do
                            addBox(shp.P, shp.N, shp.I, x + cb[1], y + cb[2], z + cb[3], x + cb[4], y + cb[5], z + cb[6])
                        end
                    end
                end
            end
        end
    end
    return sol, sel, shp
end

-- Поставить (или снять) тело слоя: объект заводится при первой геометрии.
local function apply(rec, field, g, layer)
    local obj = rec[field]
    if #g.I == 0 then
        if obj then DestroyObject(obj); rec[field] = nil end
        return
    end
    if not obj then
        obj = SpawnObject("Block Collider")
        rec[field] = obj
    end
    local m = mesh()
    m.arrays{position = g.P, normal = g.N, index = g.I}
    m.collider(obj, layer)
end

local function build(rec)
    local sol, sel, shp = Col.geometry(rec.cx, rec.sy, rec.cz)
    apply(rec, "solid", sol, Col.SOLID)
    apply(rec, "select", sel, Col.SELECT)
    apply(rec, "shape", shp, Col.SHAPE)
    rec.ready = true
    Col.built = Col.built + 1
end

local function drop(key)
    local rec = secs[key]
    if not rec then return end
    for _, f in ipairs({"solid", "select", "shape"}) do
        if rec[f] then DestroyObject(rec[f]) end
    end
    secs[key] = nil
    count = count - 1
end

-- Раз в кадр: какие секции нужны у точки (px, py, pz); за вызов собирается
-- не больше budget секций (по умолчанию одна), ближние первыми.
-- true — всё нужное собрано.
function Col.update(px, py, pz, budget)
    local r = Col.RADIUS
    local floor = math.floor
    local cx0, cx1 = floor(px - r) // 16, floor(px + r) // 16
    local cz0, cz1 = floor(pz - r) // 16, floor(pz + r) // 16
    local sy0, sy1 = math.max(0, floor(py - r) // 16), math.min(W.SECTIONS - 1, floor(py + r + 2) // 16)
    -- Ушедшие из области (с запасом в секцию, чтобы не пересобирать на границе).
    for key, rec in pairs(secs) do
        if rec.cx < cx0 - 1 or rec.cx > cx1 + 1 or rec.cz < cz0 - 1 or rec.cz > cz1 + 1
            or rec.sy < sy0 - 1 or rec.sy > sy1 + 1 or not W.chunk(rec.cx, rec.cz) then
            drop(key)
        end
    end
    -- Пометки правок вне области не копятся.
    for key in pairs(W.colDirty) do
        if not secs[key] then W.colDirty[key] = nil end
    end
    for cx = cx0, cx1 do
        for cz = cz0, cz1 do
            local c = W.chunk(cx, cz)
            if c and c.generated then
                for sy = sy0, sy1 do
                    local key = W.skey(cx, sy, cz)
                    if not secs[key] then
                        secs[key] = {cx = cx, sy = sy, cz = cz}
                        count = count + 1
                    end
                end
            end
        end
    end
    for _ = 1, budget or 1 do
        -- Новая или помеченная правкой — ближайшая к игроку первой.
        local best, bestD
        for key, rec in pairs(secs) do
            if not rec.ready or W.colDirty[key] then
                local dx, dy, dz = rec.cx * 16 + 8 - px, rec.sy * 16 + 8 - py, rec.cz * 16 + 8 - pz
                local d = dx * dx + dy * dy + dz * dz
                if not bestD or d < bestD then best, bestD = key, d end
            end
        end
        if not best then return true end
        W.colDirty[best] = nil
        build(secs[best])
    end
    for key, rec in pairs(secs) do
        if not rec.ready or W.colDirty[key] then return false end
    end
    return true
end

-- Собрана ли секция клетки (луч туда уже видит блоки).
function Col.ready(x, y, z)
    local rec = secs[W.skey(x // 16, y >> 4, z // 16)]
    return rec ~= nil and rec.ready == true and not W.colDirty[W.skey(x // 16, y >> 4, z // 16)]
end

function Col.count() return count end

function Col.clear()
    for key in pairs(secs) do drop(key) end
    secs, count = {}, 0
end

-- Самопроверка (--gencheck, строка RAYCHECK): луч движка по коллайдерам и
-- прежний обход клеток (эталон, player.raycastGrid) из глаз игрока в 300
-- случайных направлений называют одну и ту же клетку и грань. nil — коллайдеры
-- вокруг ещё собираются (проверка повторится в следующем кадре).
local settle = 0
function Col.selfCheck(P)
    if not Col.update(P.pos.x, P.pos.y, P.pos.z, 8) then settle = 0; return nil end
    -- Тела появляются в физике на её следующем шаге — два кадра на это.
    settle = settle + 1
    if settle < 3 then return nil end
    local ox, oy, oz = P.eye()
    local rnd = math.random
    local same, total, missBoth, diff = 0, 0, 0, nil
    for _ = 1, 300 do
        local dx, dy, dz = rnd() * 2 - 1, rnd() * 2 - 1, rnd() * 2 - 1
        local l = math.sqrt(dx * dx + dy * dy + dz * dz)
        if l > 0.1 then
            dx, dy, dz = dx / l, dy / l, dz / l
            total = total + 1
            local a = P.raycastFrom(ox, oy, oz, dx, dy, dz, 5)
            local b = P.raycastGrid(5, ox, oy, oz, dx, dy, dz)
            if not a and not b then
                same, missBoth = same + 1, missBoth + 1
            elseif a and b and a.x == b.x and a.y == b.y and a.z == b.z
                and a.nx == b.nx and a.ny == b.ny and a.nz == b.nz then
                same = same + 1
            elseif not diff then
                diff = string.format("движок=%s сетка=%s",
                    a and (a.x .. "," .. a.y .. "," .. a.z .. " n" .. a.nx .. a.ny .. a.nz) or "нет",
                    b and (b.x .. "," .. b.y .. "," .. b.z .. " n" .. b.nx .. b.ny .. b.nz) or "нет")
            end
        end
    end
    -- Допуск — лучи точно по ребру/углу клетки: там два ответа одинаково верны.
    local ok = same >= total - 2 and missBoth < total
    return string.format("RAYCHECK: %s совпало=%d/%d мимо_обоих=%d секций=%d%s", ok and "PASS" or "FAIL",
        same, total, missBoth, count, diff and (" первое_расхождение: " .. diff) or "")
end

return Col
