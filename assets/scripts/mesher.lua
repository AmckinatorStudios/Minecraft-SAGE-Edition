-- ---------------------------------------------------------------------------
-- mesher.lua — меш секции 16×16×16 из клеток мира.
--
-- Рисуются только грани, смотрящие в непрозрачное-не-глухое: внутренность
-- горы не стоит ни одного треугольника. Свет вершины — среднее четырёх клеток
-- перед гранью у этого угла (сглаженный свет), затенение угла — по трём
-- соседям (два ребра и угол): это то самое мягкое затемнение в стыках блоков.
--
-- Вершина несёт во втором UV-канале (uv2) два уровня света 0..15: неба и
-- блоков, уже умноженные на затенение угла. Сторону грани (верх светлее
-- боков) шейдер берёт из нормали. Так один и тот же меш верен и днём, и ночью.
--
-- Результат — массивы для m.arrays{...}: один вызов на секцию вместо тысяч
-- вызовов по вершине.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local A = require "atlas"

local M = {}

local ID_MASK, SKY, BLK = W.ID_MASK, W.SKY_SHIFT, W.BLK_SHIFT
local opaque, drawKind = B.opaque, B.drawKind
local raw = W.raw

-- Грани: нормаль, четыре угла (против часовой снаружи), направления «вдоль u»
-- и «вдоль v» в плоскости грани (для выборки соседей сглаженного света).
local FACES = {
    {n = {0, 1, 0},  c = {{0,1,0},{0,1,1},{1,1,1},{1,1,0}}, tile = "top"},
    {n = {0, -1, 0}, c = {{0,0,0},{1,0,0},{1,0,1},{0,0,1}}, tile = "bottom"},
    {n = {1, 0, 0},  c = {{1,0,0},{1,1,0},{1,1,1},{1,0,1}}, tile = "side"},
    {n = {-1, 0, 0}, c = {{0,0,0},{0,0,1},{0,1,1},{0,1,0}}, tile = "side"},
    {n = {0, 0, 1},  c = {{0,0,1},{1,0,1},{1,1,1},{0,1,1}}, tile = "front"},
    {n = {0, 0, -1}, c = {{0,0,0},{0,1,0},{1,1,0},{1,0,0}}, tile = "side"},
}

-- UV угла по его координатам: картинка стоит прямо, если смотреть на грань
-- снаружи (на боковых гранях v — это высота, u — «вправо» для смотрящего).
local function faceUV(f, p)
    if f == 1 then return p[1], 1 - p[3]
    elseif f == 2 then return p[1], p[3]
    elseif f == 3 then return 1 - p[3], p[2]
    elseif f == 4 then return p[3], p[2]
    elseif f == 5 then return p[1], p[2]
    else return 1 - p[1], p[2] end
end

-- Заранее: для каждой грани и угла — смещения трёх соседей (ребро, ребро,
-- угол) относительно клетки ПЕРЕД гранью.
for fi, f in ipairs(FACES) do
    f.uv = {}
    f.nb = {}
    for k = 1, 4 do
        local p = f.c[k]
        local u, v = faceUV(fi, p)
        f.uv[k] = {u, v}
        local s = {}
        for axis = 1, 3 do
            if f.n[axis] == 0 then s[#s + 1] = {axis, p[axis] == 0 and -1 or 1} end
        end
        local e1 = {0, 0, 0}; e1[s[1][1]] = s[1][2]
        local e2 = {0, 0, 0}; e2[s[2][1]] = s[2][2]
        f.nb[k] = {e1, e2, {e1[1] + e2[1], e1[2] + e2[2], e1[3] + e2[3]}}
    end
end

local AO = {0.45, 0.62, 0.8, 1.0}

-- Окно 18×18×18 вокруг секции: клетки самой секции и слой соседей. Читать
-- соседей через мир на каждой грани было бы втрое дороже — здесь одна
-- выборка на клетку.
local PAD = 18
local win = {}
local function widx(x, y, z) return (x + 1) + (z + 1) * PAD + (y + 1) * PAD * PAD + 1 end

local function fillWindow(cx, sy, cz)
    local bx, by, bz = cx * 16, sy * 16, cz * 16
    local c = W.chunk(cx, cz)
    local s = c and c.sec[sy]
    local SKYFULL = 15 << SKY
    for y = -1, 16 do
        for z = -1, 16 do
            for x = -1, 16 do
                local v
                if s and x >= 0 and x < 16 and z >= 0 and z < 16 and y >= 0 and y < 16 then
                    v = s[x + z * 16 + y * 256 + 1]
                elseif not s and x >= 0 and x < 16 and z >= 0 and z < 16 and y >= 0 and y < 16 then
                    v = SKYFULL
                else
                    v = raw(bx + x, by + y, bz + z) or SKYFULL
                end
                win[(x + 1) + (z + 1) * PAD + (y + 1) * PAD * PAD + 1] = v
            end
        end
    end
end

-- Новый набор массивов (одна пачка рисования).
local function batch()
    return {position = {}, normal = {}, uv = {}, uv2 = {}, index = {}, n = 0}
end

local function addQuad(b, ox, oy, oz, corners, nrm, uvs, lights, tile, flip)
    local pos, nor, uv, uv2, idx = b.position, b.normal, b.uv, b.uv2, b.index
    local base = b.n
    local tu, tv, ts = A.tileOrigin(tile)
    for k = 1, 4 do
        local p = corners[k]
        local pi = (base + k - 1) * 3
        pos[pi + 1] = ox + p[1]; pos[pi + 2] = oy + p[2]; pos[pi + 3] = oz + p[3]
        nor[pi + 1] = nrm[1]; nor[pi + 2] = nrm[2]; nor[pi + 3] = nrm[3]
        local ui = (base + k - 1) * 2
        local q = uvs[k]
        uv[ui + 1] = tu + q[1] * ts; uv[ui + 2] = tv + q[2] * ts
        local l = lights[k]
        uv2[ui + 1] = l[1]; uv2[ui + 2] = l[2]
    end
    local ii = #idx
    -- Диагональ квада — та, вдоль которой свет меняется меньше: иначе на
    -- тёмном углу проступает полоса (известная анизотропия затенения).
    if flip then
        idx[ii + 1] = base + 2; idx[ii + 2] = base + 3; idx[ii + 3] = base + 4
        idx[ii + 4] = base + 2; idx[ii + 5] = base + 4; idx[ii + 6] = base + 1
    else
        idx[ii + 1] = base + 1; idx[ii + 2] = base + 2; idx[ii + 3] = base + 3
        idx[ii + 4] = base + 1; idx[ii + 5] = base + 3; idx[ii + 6] = base + 4
    end
    b.n = base + 4
end

local function cellLight(v) return (v >> SKY) & 15, (v >> BLK) & 15 end

-- Свет четырёх углов грани: среднее по прозрачным из четырёх клеток и
-- затенение угла.
local function cornerLights(f, x, y, z)
    local fx, fy, fz = x + f.n[1], y + f.n[2], z + f.n[3]
    local front = win[widx(fx, fy, fz)]
    local s0, b0 = cellLight(front)
    local out = {}
    local aoSum = {}
    for k = 1, 4 do
        local nb = f.nb[k]
        local e1, e2, cn = nb[1], nb[2], nb[3]
        local v1 = win[widx(fx + e1[1], fy + e1[2], fz + e1[3])]
        local v2 = win[widx(fx + e2[1], fy + e2[2], fz + e2[3])]
        local vc = win[widx(fx + cn[1], fy + cn[2], fz + cn[3])]
        local o1, o2, oc = opaque[v1 & ID_MASK], opaque[v2 & ID_MASK], opaque[vc & ID_MASK]
        local sky, blk, n = s0, b0, 1
        if not o1 then local a, b = cellLight(v1); sky = sky + a; blk = blk + b; n = n + 1 end
        if not o2 then local a, b = cellLight(v2); sky = sky + a; blk = blk + b; n = n + 1 end
        if not oc and not (o1 and o2) then local a, b = cellLight(vc); sky = sky + a; blk = blk + b; n = n + 1 end
        local level
        if o1 and o2 then level = 0
        else level = 3 - ((o1 and 1 or 0) + (o2 and 1 or 0) + (oc and 1 or 0)) end
        local ao = AO[level + 1]
        out[k] = {sky / n * ao, blk / n * ao}
        aoSum[k] = out[k][1] + out[k][2]
    end
    local flip = aoSum[1] + aoSum[3] < aoSum[2] + aoSum[4]
    return out, flip
end

-- Должна ли грань блока id рисоваться против соседа nid.
local function faceVisible(id, kind, nid)
    if nid == 0 then return true end
    if opaque[nid] then return false end
    local nk = drawKind[nid]
    if kind == 4 then return nk ~= 4 and nid ~= 29 end      -- вода: только к не-воде
    if nk == 3 or nk == 5 or nk == 4 then return true      -- рядом растение, факел, вода
    end
    if kind == 2 and nid == id and B.byId[id].name ~= "leaves" and B.byId[id].name ~= "birch_leaves" then
        return false                                       -- стекло к стеклу — без стыка
    end
    return true
end

local CROSS = {
    {{0.15,0,0.15},{0.85,0,0.85},{0.85,1,0.85},{0.15,1,0.15}},
    {{0.15,0,0.85},{0.85,0,0.15},{0.85,1,0.15},{0.15,1,0.85}},
}
local CROSS_UV = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}

-- Факел — столбик 2/16 × 10/16, текстура — его середина.
local T0, T1, TH = 7 / 16, 9 / 16, 10 / 16

local function emitCross(b, x, y, z, v, tile)
    local s, l = cellLight(v)
    local lt = {{s, l}, {s, l}, {s, l}, {s, l}}
    for _, q in ipairs(CROSS) do
        addQuad(b, x, y, z, q, {0, 1, 0}, CROSS_UV, lt, tile, false)
        -- Обратная сторона — своими треугольниками: материал с отсечением
        -- задних граней общий для всего участка.
        addQuad(b, x, y, z, {q[4], q[3], q[2], q[1]}, {0, 1, 0}, {CROSS_UV[4], CROSS_UV[3], CROSS_UV[2], CROSS_UV[1]}, lt, tile, false)
    end
end

local function emitTorch(b, x, y, z, v, tile)
    local s, l = cellLight(v)
    local lt = {{s, l}, {s, l}, {s, l}, {s, l}}
    for fi = 1, 6 do
        local f = FACES[fi]
        if fi ~= 2 then
            local corners, uvs = {}, {}
            for k = 1, 4 do
                local p = f.c[k]
                local px = T0 + p[1] * (T1 - T0)
                local pz = T0 + p[3] * (T1 - T0)
                local py = p[2] * TH
                corners[k] = {px, py, pz}
                if fi == 1 then uvs[k] = {px, 0.5 + p[3] * 0.125}
                else
                    local u = (fi == 3 or fi == 4) and pz or px
                    uvs[k] = {u, py}
                end
            end
            addQuad(b, x, y, z, corners, f.n, uvs, lt, tile, false)
        end
    end
end

-- Меш секции: две пачки — глухое+вырез (один материал с отбрасыванием по
-- альфе) и жидкость (полупрозрачный материал).
function M.build(cx, sy, cz)
    fillWindow(cx, sy, cz)
    local solid, liquid = batch(), batch()
    local P2 = PAD * PAD
    for y = 0, 15 do
        for z = 0, 15 do
            local rowBase = (z + 1) * PAD + (y + 1) * P2 + 1
            for x = 0, 15 do
                local v = win[rowBase + x + 1]
                local id = v & ID_MASK
                if id ~= 0 then
                    local kind = drawKind[id]
                    local tiles = A.blockTiles[id]
                    if kind == 3 then
                        emitCross(solid, x, y, z, v, tiles.side)
                    elseif kind == 5 then
                        emitTorch(solid, x, y, z, v, tiles.side)
                    elseif kind ~= 0 then
                        local b = kind == 4 and liquid or solid
                        local inset = B.byId[id].inset
                        for fi = 1, 6 do
                            local f = FACES[fi]
                            local nv = win[widx(x + f.n[1], y + f.n[2], z + f.n[3])]
                            local nid = nv & ID_MASK
                            local show = faceVisible(id, kind, nid)
                            if inset and fi > 2 then show = true end
                            if show then
                                local lights, flip = cornerLights(f, x, y, z)
                                local corners = f.c
                                if kind == 4 and fi == 1 and (win[widx(x, y + 1, z)] & ID_MASK) ~= id then
                                    -- Гладь чуть ниже края блока — так вода читается водой.
                                    corners = {}
                                    for k = 1, 4 do local p = f.c[k]; corners[k] = {p[1], 0.875, p[3]} end
                                elseif inset and fi > 2 then
                                    corners = {}
                                    for k = 1, 4 do
                                        local p = f.c[k]
                                        local q = {p[1], p[2], p[3]}
                                        for a = 1, 3 do
                                            if f.n[a] ~= 0 then q[a] = q[a] - f.n[a] * inset end
                                        end
                                        corners[k] = q
                                    end
                                end
                                addQuad(b, x, y, z, corners, f.n, f.uv, lights, tiles[f.tile], flip)
                            end
                        end
                    end
                end
            end
        end
    end
    return solid, liquid
end

return M
