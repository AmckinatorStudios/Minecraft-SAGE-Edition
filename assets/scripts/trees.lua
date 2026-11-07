-- ---------------------------------------------------------------------------
-- trees.lua — деревья из саженцев, как генераторы Minecraft 1.7.10:
--   дуб       — WorldGenTrees (высота 4–6), 1 из 10 — WorldGenBigTree;
--   берёза    — WorldGenForest (5–7);
--   ель       — WorldGenTaiga2; 2×2 саженца — WorldGenMegaPineTree;
--   тропическое — WorldGenTrees (4–10, без лиан); 2×2 — WorldGenMegaJungle;
--   акация    — WorldGenSavannaTree (кривой ствол, плоские кроны);
--   тёмный дуб — только 2×2: WorldGenCanopyTree.
-- Случайные числа — Random Java (ores.lua), в том же порядке вызовов, что у
-- оригинала. Генератор сам проверяет место; не хватило — возвращает false и
-- ничего не ставит (тогда саженцы возвращаются на место, plants.lua).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local T = {}

local function id(name) return B.byName[name].id end
local AIR = 0

-- Мир для генератора: чтение и запись через переданные функции (запись —
-- Act.setBlock: правка сохраняется, свет и меш обновляются).
local get, set

local function isLeaves(b) return B.isLeaves[b] == true end
local function isLog(b) return B.isLog[b] == true end
local function airOrLeaves(b) return b == AIR or isLeaves(b) end

-- WorldGenAbstractTree.func_150523_a: через что дерево может расти.
local function replaceable(b)
    return b == AIR or isLeaves(b) or b == id("grass") or b == id("dirt") or isLog(b) or B.isSapling[b] == true
end

local function soil(b) return b == id("grass") or b == id("dirt") end

-- Direction.offsetX / offsetZ.
local OX, OZ = {0, -1, 0, 1}, {1, 0, -1, 0}

-- --- Дуб, берёза, тропическое (WorldGenTrees / WorldGenForest) ---------------
local function smallTree(rand, x, y, z, height, log, leaves)
    local l = height
    if y < 1 or y + l + 1 > W.HEIGHT then return false end
    for i1 = y, y + 1 + l do
        local b0 = 1
        if i1 == y then b0 = 0 end
        if i1 >= y + 1 + l - 2 then b0 = 2 end
        for j1 = x - b0, x + b0 do
            for k1 = z - b0, z + b0 do
                if i1 < 0 or i1 >= W.HEIGHT or not replaceable(get(j1, i1, k1)) then return false end
            end
        end
    end
    if not soil(get(x, y - 1, z)) or y >= W.HEIGHT - l - 1 then return false end
    set(x, y - 1, z, id("dirt"))
    local b0, b1 = 3, 0
    for k1 = y - b0 + l, y + l do
        local i3 = k1 - (y + l)
        -- i3 / 2 в Java — деление с отбрасыванием к нулю.
        local l1 = b1 + 1 - (i3 >= 0 and i3 // 2 or -((-i3) // 2))
        for i2 = x - l1, x + l1 do
            local j2 = i2 - x
            for k2 = z - l1, z + l1 do
                local l2 = k2 - z
                if math.abs(j2) ~= l1 or math.abs(l2) ~= l1 or (rand:nextInt(2) ~= 0 and i3 ~= 0) then
                    if airOrLeaves(get(i2, k1, k2)) then set(i2, k1, k2, leaves) end
                end
            end
        end
    end
    for k1 = 0, l - 1 do
        if airOrLeaves(get(x, y + k1, z)) then set(x, y + k1, z, log) end
    end
    return true
end

-- --- Ель (WorldGenTaiga2) ---------------------------------------------------
local function spruce(rand, x, y, z)
    local log, leaves = id("spruce_log"), id("spruce_leaves")
    local l = rand:nextInt(4) + 6
    local i1 = 1 + rand:nextInt(2)
    local j1 = l - i1
    local k1 = 2 + rand:nextInt(2)
    if y < 1 or y + l + 1 > W.HEIGHT then return false end
    for l1 = y, y + 1 + l do
        local i2 = (l1 - y < i1) and 0 or k1
        for j2 = x - i2, x + i2 do
            for k2 = z - i2, z + i2 do
                if l1 < 0 or l1 >= W.HEIGHT then return false end
                local b = get(j2, l1, k2)
                if b ~= AIR and not isLeaves(b) then return false end
            end
        end
    end
    if not soil(get(x, y - 1, z)) or y >= W.HEIGHT - l - 1 then return false end
    set(x, y - 1, z, id("dirt"))
    local i3 = rand:nextInt(2)
    local j3, b0 = 1, 0
    for k3 = 0, j1 do
        local l3 = y + l - k3
        for i2 = x - i3, x + i3 do
            local j4 = i2 - x
            for k2 = z - i3, z + i3 do
                local l2 = k2 - z
                if (math.abs(j4) ~= i3 or math.abs(l2) ~= i3 or i3 <= 0) and not B.opaque[get(i2, l3, k2)] then
                    set(i2, l3, k2, leaves)
                end
            end
        end
        if i3 >= j3 then
            i3 = b0
            b0 = 1
            j3 = j3 + 1
            if j3 > k1 then j3 = k1 end
        else
            i3 = i3 + 1
        end
    end
    local k3 = rand:nextInt(3)
    for l3 = 0, l - k3 - 1 do
        if airOrLeaves(get(x, y + l3, z)) then set(x, y + l3, z, log) end
    end
    return true
end

-- --- Большие деревья 2×2 (WorldGenHugeTrees) --------------------------------
local function hugeHeight(rand, base, variation)
    local i = rand:nextInt(3) + base
    if variation > 1 then i = i + rand:nextInt(variation) end
    return i
end

-- func_150537_a: место и почва под 2×2.
local function hugeFits(x, y, z, l)
    if y < 1 or y + l + 1 > W.HEIGHT then return false end
    for i1 = y, y + 1 + l do
        local b0 = 2
        if i1 == y then b0 = 1 end
        if i1 >= y + 1 + l - 2 then b0 = 2 end
        for j1 = x - b0, x + b0 do
            for k1 = z - b0, z + b0 do
                if i1 < 0 or i1 >= W.HEIGHT or not replaceable(get(j1, i1, k1)) then return false end
            end
        end
    end
    if not soil(get(x, y - 1, z)) or y >= W.HEIGHT - l - 1 then return false end
    for _, d in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do set(x + d[1], y - 1, z + d[2], id("dirt")) end
    return true
end

-- func_150535_a: круг листвы вокруг ствола 2×2.
local function hugeLayer(x, y, z, r, leaves)
    local k1 = r * r
    for l1 = x - r, x + r + 1 do
        local i2 = l1 - x
        for j2 = z - r, z + r + 1 do
            local k2 = j2 - z
            local l2, i3 = i2 - 1, k2 - 1
            if i2 * i2 + k2 * k2 <= k1 or l2 * l2 + i3 * i3 <= k1 or i2 * i2 + i3 * i3 <= k1 or l2 * l2 + k2 * k2 <= k1 then
                if airOrLeaves(get(l1, y, j2)) then set(l1, y, j2, leaves) end
            end
        end
    end
end

local function hugeTrunk(x, y, z, l, log)
    for i1 = 0, l - 1 do
        local yy = y + i1
        if airOrLeaves(get(x, yy, z)) then set(x, yy, z, log) end
        if i1 < l - 1 then
            for _, d in ipairs({{1, 0}, {1, 1}, {0, 1}}) do
                if airOrLeaves(get(x + d[1], yy, z + d[2])) then set(x + d[1], yy, z + d[2], log) end
            end
        end
    end
end

-- WorldGenMegaPineTree(false, useBaseHeight): база 13, разброс 15.
local function megaSpruce(rand, x, y, z, useBase)
    local log, leaves = id("spruce_log"), id("spruce_leaves")
    local l = hugeHeight(rand, 13, 15)
    if not hugeFits(x, y, z, l) then return false end
    -- func_150541_c: конус кроны от вершины.
    local top = y + l
    local i1 = rand:nextInt(5) + (useBase and 13 or 3)
    local j1 = 0
    for k1 = top - i1, top do
        local l1 = top - k1
        local i2 = math.floor(l1 / i1 * 3.5)
        hugeLayer(x, k1, z, i2 + ((l1 > 0 and i2 == j1 and (k1 & 1) == 0) and 1 or 0), leaves)
        j1 = i2
    end
    hugeTrunk(x, y, z, l, log)
    return true
end

-- WorldGenMegaJungle(true, 10, 20, 3, 3) — без лиан.
local function megaJungle(rand, x, y, z)
    local log, leaves = id("jungle_log"), id("jungle_leaves")
    local l = hugeHeight(rand, 10, 20)
    if not hugeFits(x, y, z, l) then return false end
    local top = y + l
    for k1 = top - 2, top do hugeLayer(x, k1, z, 2 + 1 - (top - k1), leaves) end
    local i1 = y + l - 2 - rand:nextInt(4)
    while i1 > y + l // 2 do
        local f = rand:nextFloat() * math.pi * 2
        local k1, l1
        for i2 = 0, 4 do
            k1 = x + math.floor(1.5 + math.cos(f) * i2)
            l1 = z + math.floor(1.5 + math.sin(f) * i2)
            set(k1, i1 - 3 + i2 // 2, l1, log)
        end
        local i2 = 1 + rand:nextInt(2)
        for j2 = i1 - i2, i1 do
            hugeLayer(k1, j2, l1, 1 - (j2 - i1), leaves)
        end
        i1 = i1 - (2 + rand:nextInt(4))
    end
    hugeTrunk(x, y, z, l, log)
    return true
end

-- --- Акация (WorldGenSavannaTree) ------------------------------------------
local function acacia(rand, x, y, z)
    local log, leaves = id("acacia_log"), id("acacia_leaves")
    local function leaf(a, b, c) if airOrLeaves(get(a, b, c)) then set(a, b, c, leaves) end end
    local l = rand:nextInt(3) + rand:nextInt(3) + 5
    if y < 1 or y + l + 1 > W.HEIGHT then return false end
    for i1 = y, y + 1 + l do
        local b0 = 1
        if i1 == y then b0 = 0 end
        if i1 >= y + 1 + l - 2 then b0 = 2 end
        for j1 = x - b0, x + b0 do
            for k1 = z - b0, z + b0 do
                if i1 < 0 or i1 >= W.HEIGHT or not replaceable(get(j1, i1, k1)) then return false end
            end
        end
    end
    if not soil(get(x, y - 1, z)) or y >= W.HEIGHT - l - 1 then return false end
    set(x, y - 1, z, id("dirt"))
    local j3 = rand:nextInt(4)
    local k1 = l - rand:nextInt(4) - 1
    local k3 = 3 - rand:nextInt(3)
    local l1, i2, j2 = x, z, 0
    for l3 = 0, l - 1 do
        local k2 = y + l3
        if l3 >= k1 and k3 > 0 then
            l1, i2 = l1 + OX[j3 + 1], i2 + OZ[j3 + 1]
            k3 = k3 - 1
        end
        if airOrLeaves(get(l1, k2, i2)) then set(l1, k2, i2, log); j2 = k2 end
    end
    for a = -1, 1 do for c = -1, 1 do leaf(l1 + a, j2 + 1, i2 + c) end end
    leaf(l1 + 2, j2 + 1, i2); leaf(l1 - 2, j2 + 1, i2); leaf(l1, j2 + 1, i2 + 2); leaf(l1, j2 + 1, i2 - 2)
    for a = -3, 3 do
        for c = -3, 3 do
            if math.abs(a) ~= 3 or math.abs(c) ~= 3 then leaf(l1 + a, j2, i2 + c) end
        end
    end
    l1, i2 = x, z
    local l3 = rand:nextInt(4)
    if l3 ~= j3 then
        local k2 = k1 - rand:nextInt(2) - 1
        local k4 = 1 + rand:nextInt(3)
        j2 = 0
        local i5 = k2
        while i5 < l and k4 > 0 do
            if i5 >= 1 then
                local l4 = y + i5
                l1, i2 = l1 + OX[l3 + 1], i2 + OZ[l3 + 1]
                if airOrLeaves(get(l1, l4, i2)) then set(l1, l4, i2, log); j2 = l4 end
            end
            i5 = i5 + 1
            k4 = k4 - 1
        end
        if j2 > 0 then
            for a = -1, 1 do for c = -1, 1 do leaf(l1 + a, j2 + 1, i2 + c) end end
            for a = -2, 2 do
                for c = -2, 2 do
                    if math.abs(a) ~= 2 or math.abs(c) ~= 2 then leaf(l1 + a, j2, i2 + c) end
                end
            end
        end
    end
    return true
end

-- --- Тёмный дуб (WorldGenCanopyTree), ствол 2×2 ------------------------------
local function darkOak(rand, x, y, z)
    local log, leaves = id("dark_oak_log"), id("dark_oak_leaves")
    local function leaf(a, b, c) if get(a, b, c) == AIR then set(a, b, c, leaves) end end
    local l = rand:nextInt(3) + rand:nextInt(2) + 6
    if y < 1 or y + l + 1 > W.HEIGHT then return false end
    if not soil(get(x, y - 1, z)) or y >= W.HEIGHT - l - 1 then return false end
    -- func_150490_a: место вокруг будущего ствола.
    for i1 = 0, l + 1 do
        local b0 = 1
        if i1 == 0 then b0 = 0 end
        if i1 >= l - 1 then b0 = 2 end
        for j1 = -b0, b0 do
            for k1 = -b0, b0 do
                if not replaceable(get(x + j1, y + i1, z + k1)) then return false end
            end
        end
    end
    for _, d in ipairs({{0, 0}, {1, 0}, {1, 1}, {0, 1}}) do set(x + d[1], y - 1, z + d[2], id("dirt")) end
    local i1 = rand:nextInt(4)
    local j1 = l - rand:nextInt(4)
    local k1 = 2 - rand:nextInt(3)
    local l1, i2, j2 = x, z, 0
    for k2 = 0, l - 1 do
        local l2 = y + k2
        if k2 >= j1 and k1 > 0 then
            l1, i2 = l1 + OX[i1 + 1], i2 + OZ[i1 + 1]
            k1 = k1 - 1
        end
        if airOrLeaves(get(l1, l2, i2)) then
            set(l1, l2, i2, log); set(l1 + 1, l2, i2, log); set(l1, l2, i2 + 1, log); set(l1 + 1, l2, i2 + 1, log)
            j2 = l2
        end
    end
    for k2 = -2, 0 do
        for l2 = -2, 0 do
            local b0 = -1
            leaf(l1 + k2, j2 + b0, i2 + l2); leaf(1 + l1 - k2, j2 + b0, i2 + l2)
            leaf(l1 + k2, j2 + b0, 1 + i2 - l2); leaf(1 + l1 - k2, j2 + b0, 1 + i2 - l2)
            if (k2 > -2 or l2 > -1) and (k2 ~= -1 or l2 ~= -2) then
                b0 = 1
                leaf(l1 + k2, j2 + b0, i2 + l2); leaf(1 + l1 - k2, j2 + b0, i2 + l2)
                leaf(l1 + k2, j2 + b0, 1 + i2 - l2); leaf(1 + l1 - k2, j2 + b0, 1 + i2 - l2)
            end
        end
    end
    if rand:nextInt(2) == 1 then   -- nextBoolean
        leaf(l1, j2 + 2, i2); leaf(l1 + 1, j2 + 2, i2); leaf(l1 + 1, j2 + 2, i2 + 1); leaf(l1, j2 + 2, i2 + 1)
    end
    for k2 = -3, 4 do
        for l2 = -3, 4 do
            if (k2 ~= -3 or l2 ~= -3) and (k2 ~= -3 or l2 ~= 4) and (k2 ~= 4 or l2 ~= -3) and (k2 ~= 4 or l2 ~= 4)
                and (math.abs(k2) < 3 or math.abs(l2) < 3) then
                leaf(l1 + k2, j2, i2 + l2)
            end
        end
    end
    for k2 = -1, 2 do
        for l2 = -1, 2 do
            if (k2 < 0 or k2 > 1 or l2 < 0 or l2 > 1) and rand:nextInt(3) <= 0 then
                local i3 = rand:nextInt(3) + 2
                for j3 = 0, i3 - 1 do set(x + k2, j2 - j3 - 1, z + l2, log) end
                for j3 = -1, 1 do for k3 = -1, 1 do leaf(l1 + k2 + j3, j2, l2 + i2 + k3) end end
                for j3 = -2, 2 do
                    for k3 = -2, 2 do
                        if math.abs(j3) ~= 2 or math.abs(k3) ~= 2 then leaf(l1 + k2 + j3, j2 - 1, l2 + i2 + k3) end
                    end
                end
            end
        end
    end
    return true
end

-- --- Большой дуб (WorldGenBigTree) -----------------------------------------
local PAIRS = {2, 0, 0, 1, 2, 1}   -- otherCoordPairs (оси с нуля)

local function bigOak(outer, x, y, z)
    local O = require "ores"
    local rand = O.Random(0)
    rand:setSeed(outer:nextLong())
    local log, leaves = id("log"), id("leaves")
    local base = {x, y, z}
    local heightLimit = 5 + rand:nextInt(12)
    local height
    local leafDistanceLimit = 4

    local function stepLine(a, b, place)
        local d = {b[1] - a[1], b[2] - a[2], b[3] - a[3]}
        local b1 = 0
        for i = 0, 2 do if math.abs(d[i + 1]) > math.abs(d[b1 + 1]) then b1 = i end end
        if d[b1 + 1] == 0 then return -1 end
        local b2, b3 = PAIRS[b1 + 1], PAIRS[b1 + 4]
        local b4 = d[b1 + 1] > 0 and 1 or -1
        local d0, d1 = d[b2 + 1] / d[b1 + 1], d[b3 + 1] / d[b1 + 1]
        local i, j = 0, d[b1 + 1] + b4
        local c = {0, 0, 0}
        while i ~= j do
            c[b1 + 1] = math.floor(a[b1 + 1] + i + 0.5)
            c[b2 + 1] = math.floor(a[b2 + 1] + i * d0 + 0.5)
            c[b3 + 1] = math.floor(a[b3 + 1] + i * d1 + 0.5)
            if place then set(c[1], c[2], c[3], log)
            elseif not replaceable(get(c[1], c[2], c[3])) then break end
            i = i + b4
        end
        if place then return -1 end
        return i == j and -1 or math.abs(i)
    end

    -- validTreeLocation
    if not soil(get(x, y - 1, z)) then return false end
    local hit = stepLine(base, {x, y + heightLimit - 1, z})
    if hit ~= -1 then
        if hit < 6 then return false end
        heightLimit = hit
    end

    local function layerSize(i)
        if i < heightLimit * 0.3 then return -1.618 end
        local f = heightLimit / 2
        local f1 = heightLimit / 2 - i
        local f2
        if f1 == 0 then f2 = f
        elseif math.abs(f1) >= f then f2 = 0
        else f2 = math.sqrt(f * f - f1 * f1) end
        return f2 * 0.5
    end

    -- generateLeafNodeList
    height = math.floor(heightLimit * 0.618)
    if height >= heightLimit then height = heightLimit - 1 end
    local per = math.floor(1.382 + (heightLimit / 13) ^ 2)
    if per < 1 then per = 1 end
    local nodes = {}
    local j = y + heightLimit - leafDistanceLimit
    local l = y + height
    local i1 = j - y
    nodes[1] = {x, j, z, l}
    j = j - 1
    while i1 >= 0 do
        local f = layerSize(i1)
        if f >= 0 then
            for _ = 1, per do
                local d1 = f * (rand:nextFloat() + 0.328)
                local d2 = rand:nextFloat() * 2 * math.pi
                local k1 = math.floor(d1 * math.sin(d2) + x + 0.5)
                local l1 = math.floor(d1 * math.cos(d2) + z + 0.5)
                local a1 = {k1, j, l1}
                if stepLine(a1, {k1, j + leafDistanceLimit, l1}) == -1 then
                    local d3 = math.sqrt((x - k1) ^ 2 + (z - l1) ^ 2)
                    local d4 = d3 * 0.381
                    local by = (j - d4 > l) and l or math.floor(j - d4)
                    if stepLine({x, by, z}, a1) == -1 then nodes[#nodes + 1] = {k1, j, l1, by} end
                end
            end
        end
        j = j - 1
        i1 = i1 - 1
    end

    local function layer(cx, cy, cz, radius)
        local r = math.floor(radius + 0.618)
        for i = -r, r do
            for k = -r, r do
                if (math.abs(i) + 0.5) ^ 2 + (math.abs(k) + 0.5) ^ 2 <= radius * radius then
                    if airOrLeaves(get(cx + i, cy, cz + k)) then set(cx + i, cy, cz + k, leaves) end
                end
            end
        end
    end
    for _, n in ipairs(nodes) do
        for ly = n[2], n[2] + leafDistanceLimit - 1 do
            local s = ly - n[2]
            local f = (s == 0 or s == leafDistanceLimit - 1) and 2 or 3
            layer(n[1], ly, n[3], f)
        end
    end
    stepLine({x, y, z}, {x, y + height, z}, true)
    for _, n in ipairs(nodes) do
        if n[4] - y >= heightLimit * 0.2 then stepLine({x, n[4], z}, {n[1], n[2], n[3]}, true) end
    end
    return true
end

-- Вырастить дерево вида kind в (x, y, z) (у 2×2 — северо-западный угол).
-- rand — Random Java; getF/setF — чтение и запись мира. two — саженцы 2×2.
function T.grow(kind, rand, x, y, z, two, getF, setF)
    get, set = getF, setF
    -- BlockSapling.func_149878_d: выбор большого дуба — первым, у любого вида.
    local big = rand:nextInt(10) == 0
    if kind == "oak" then
        if big then return bigOak(rand, x, y, z) end
        return smallTree(rand, x, y, z, rand:nextInt(3) + 4, id("log"), id("leaves"))
    elseif kind == "birch" then
        return smallTree(rand, x, y, z, rand:nextInt(3) + 5, id("birch_log"), id("birch_leaves"))
    elseif kind == "spruce" then
        if two then return megaSpruce(rand, x, y, z, rand:nextInt(2) == 1) end
        return spruce(rand, x, y, z)
    elseif kind == "jungle" then
        if two then return megaJungle(rand, x, y, z) end
        local minH = 4 + rand:nextInt(7)   -- new WorldGenTrees(true, 4 + nextInt(7), …)
        return smallTree(rand, x, y, z, rand:nextInt(3) + minH, id("jungle_log"), id("jungle_leaves"))
    elseif kind == "acacia" then
        return acacia(rand, x, y, z)
    elseif kind == "dark_oak" then
        if two then return darkOak(rand, x, y, z) end
        return false
    end
    return false
end

return T
