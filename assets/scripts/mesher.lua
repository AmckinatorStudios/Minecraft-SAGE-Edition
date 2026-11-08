-- ---------------------------------------------------------------------------
-- mesher.lua — меш секции 16×16×16 из клеток мира.
--
-- Рисуются только грани, смотрящие в непрозрачное-не-глухое: внутренность
-- горы не стоит ни одного треугольника. Сглаженный свет — как у
-- renderStandardBlockWithAmbientOcclusion 1.7.10: у каждого угла грани четыре
-- клетки (перед гранью, два ребра, диагональ). Яркость угла — их среднее,
-- причём глухая или совсем тёмная клетка берёт значение клетки перед гранью
-- (getAoBrightness); оба ребра глухие — диагональ не видна, вместо неё
-- ребро. Затенение угла — среднее их getAmbientOcclusionLightValue: 0.2 у
-- глухого блока, 1.0 у остальных.
--
-- Вершина несёт во втором UV-канале (uv2) два уровня света 0..15: неба и
-- блоков (дробные — среднее). Затенение угла — длина нормали: нормаль грани
-- одна на все четыре угла, и её длина между ними меняется ровно линейно, как
-- цвет вершины у оригинала. Сторону грани (верх 1, низ 0.5, X 0.6, Z 0.8)
-- шейдер берёт из направления нормали. Так один и тот же меш верен и днём,
-- и ночью: дневной свет — в световой карте (lightmap.lua).
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

-- Сторона оригинала (0 низ, 1 верх, 2 −Z, 3 +Z, 4 −X, 5 +X) у грани FACES.
local FACE_SIDE = {1, 0, 5, 4, 3, 2}

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


-- Смещения в окне (см. widx) одним числом: соседа клетки ищем сложением
-- индексов, а не вызовом функции с тремя координатами — это внутренний цикл
-- мешера, он идёт по каждой видимой грани.
local PADc = 18
local function delta(dx, dy, dz) return dx + dz * PADc + dy * PADc * PADc end
for _, f in ipairs(FACES) do
    f.dn = delta(f.n[1], f.n[2], f.n[3])
    f.dnb = {}
    for k = 1, 4 do
        local nb = f.nb[k]
        f.dnb[k] = {delta(nb[1][1], nb[1][2], nb[1][3]), delta(nb[2][1], nb[2][2], nb[2][3]),
                    delta(nb[3][1], nb[3][2], nb[3][3])}
    end
end

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

local function addQuad(b, ox, oy, oz, corners, nrm, uvs, L, tile, flip, ao)
    local pos, nor, uv, uv2, idx = b.position, b.normal, b.uv, b.uv2, b.index
    local base = b.n
    local tu, tv, ts = A.tileOrigin(tile)
    local nx, ny, nz = nrm[1], nrm[2], nrm[3]
    for k = 1, 4 do
        local p = corners[k]
        local pi = (base + k - 1) * 3
        pos[pi + 1] = ox + p[1]; pos[pi + 2] = oy + p[2]; pos[pi + 3] = oz + p[3]
        local a = ao and ao[k] or 1
        nor[pi + 1] = nx * a; nor[pi + 2] = ny * a; nor[pi + 3] = nz * a
        local ui = (base + k - 1) * 2
        local q = uvs[k]
        uv[ui + 1] = tu + q[1] * ts; uv[ui + 2] = tv + q[2] * ts
        uv2[ui + 1] = L[k * 2 - 1]; uv2[ui + 2] = L[k * 2]
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

-- Свет и затенение четырёх углов грани — в общие буферы LB (небо, блоки —
-- по углам подряд) и AOB: новая таблица на каждую грань стоила бы мешеру
-- сборщика мусора больше, чем сам подсчёт.
local LB = {0, 0, 0, 0, 0, 0, 0, 0}
local AOB = {1, 1, 1, 1}
-- Свет клетки для угла: глухая клетка света не несёт (0), а нулевая
-- яркость заменяется клеткой перед гранью — так у оригинала (getAoBrightness).
local function lightOr(v, solid, s0, b0)
    local s, b = (v >> SKY) & 15, (v >> BLK) & 15
    if solid or (s == 0 and b == 0) then return s0, b0 end
    return s, b
end

local function cornerLights(f, wi)
    local fi = wi + f.dn
    local front = win[fi]
    local s0, b0 = (front >> SKY) & 15, (front >> BLK) & 15
    local aoF = opaque[front & ID_MASK] and 0.2 or 1
    local dnb = f.dnb
    for k = 1, 4 do
        local d = dnb[k]
        local v1, v2, vc = win[fi + d[1]], win[fi + d[2]], win[fi + d[3]]
        local o1, o2, oc = opaque[v1 & ID_MASK], opaque[v2 & ID_MASK], opaque[vc & ID_MASK]
        -- Оба ребра глухие — угол закрыт, вместо диагонали берётся ребро.
        if o1 and o2 then vc, oc = v1, o1 end
        local s1, b1 = lightOr(v1, o1, s0, b0)
        local s2, b2 = lightOr(v2, o2, s0, b0)
        local sc, bc = lightOr(vc, oc, s0, b0)
        local sky, blk = s0 + s1 + s2 + sc, b0 + b1 + b2 + bc
        LB[k * 2 - 1] = sky / 4
        LB[k * 2] = blk / 4
        AOB[k] = (aoF + (o1 and 0.2 or 1) + (o2 and 0.2 or 1) + (oc and 0.2 or 1)) / 4
    end
    local a = (LB[1] + LB[2]) * AOB[1] + (LB[5] + LB[6]) * AOB[3]
    local c = (LB[3] + LB[4]) * AOB[2] + (LB[7] + LB[8]) * AOB[4]
    return a < c
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

local LT = {0, 0, 0, 0, 0, 0, 0, 0}
local function flatLight(v)
    local s, l = cellLight(v)
    for k = 1, 4 do LT[k * 2 - 1] = s; LT[k * 2] = l end
    return LT
end

local function emitCross(b, x, y, z, v, tile)
    local lt = flatLight(v)
    for _, q in ipairs(CROSS) do
        addQuad(b, x, y, z, q, {0, 1, 0}, CROSS_UV, lt, tile, false)
        -- Обратная сторона — своими треугольниками: материал с отсечением
        -- задних граней общий для всего участка.
        addQuad(b, x, y, z, {q[4], q[3], q[2], q[1]}, {0, 1, 0}, {CROSS_UV[4], CROSS_UV[3], CROSS_UV[2], CROSS_UV[1]}, lt, tile, false)
    end
end

-- Факел — RenderBlocks.renderTorchAtAngle 1.7.10. Четыре плоскости картинки
-- во всю клетку на ±1/16 от оси (палочка — середина картинки, остальное
-- отрезает альфа), низ сдвинут на (dx, dz): у настенного факела основание
-- у стены, верх наклонён наружу. Верх палочки — квадрат 2×2 пикселя
-- картинки (u 7..9, v 6..8) на высоте 0.625, низ — (u 7..9, v 13..15).
-- Метаданные: 1 — опора X−, 2 — X+, 3 — Z−, 4 — Z+, 5 (и 0) — пол:
-- настенный — от (0.5 ∓ 0.1, 0.2, 0.5) с наклоном 0.4.
local function torchQuad(b, x, y, z, corners, uvs, out, lt, tile)
    -- Обход вершин — против часовой снаружи (лицом к out): так плоскость
    -- видна со своей стороны при отсечении задних граней.
    local a, c, d = corners[1], corners[2], corners[3]
    local e1 = {c[1] - a[1], c[2] - a[2], c[3] - a[3]}
    local e2 = {d[1] - a[1], d[2] - a[2], d[3] - a[3]}
    local n = {e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1]}
    if n[1] * out[1] + n[2] * out[2] + n[3] * out[3] < 0 then
        corners = {corners[4], corners[3], corners[2], corners[1]}
        uvs = {uvs[4], uvs[3], uvs[2], uvs[1]}
    end
    -- Нормаль — «вверх» (факел без оттенка стороны: renderBlockTorch — цвет 1),
    -- но с долей настоящей нормали грани: движок разворачивает треугольник,
    -- чья нормаль вершин смотрит против геометрической (Mesh FixWinding), и
    -- наклонные плоскости настенного факела с чистым «вверх» вставали к
    -- камере спиной — палочка пропадала. Длина ≥ 1: затенения угла нет.
    -- Низ (грань вниз) так не согласовать — ему нормаль грани.
    local len = math.sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
    local f = {n[1] / len, n[2] / len, n[3] / len}
    if f[1] * out[1] + f[2] * out[2] + f[3] * out[3] < 0 then f = {-f[1], -f[2], -f[3]} end
    local nrm = f[2] < -0.5 and f or {f[1] * 0.6, 1.2 + f[2] * 0.6, f[3] * 0.6}
    addQuad(b, x, y, z, corners, nrm, uvs, lt, tile, false)
end

local function emitTorch(b, x, y, z, v, tile)
    local lt = flatLight(v)
    local meta = (v >> W.META_SHIFT) & 15
    local d0, d1, d2 = 0.4, 0.1, 0.2
    local ox, oy, oz, dx, dz = 0, 0, 0, 0, 0
    if meta == 1 then ox, oy, dx = -d1, d2, -d0
    elseif meta == 2 then ox, oy, dx = d1, d2, d0
    elseif meta == 3 then oz, oy, dz = -d1, d2, -d0
    elseif meta == 4 then oz, oy, dz = d1, d2, d0 end
    local cx, cz = 0.5 + ox, 0.5 + oz
    local e = 0.0625
    local h = 0.625
    -- v картинки — сверху (как у оригинала); у плитки атласа — снизу.
    local function V(px) return 1 - px / 16 end
    local u7, u9 = 7 / 16, 9 / 16
    -- Верх.
    local tx, tz = cx + dx * (1 - h), cz + dz * (1 - h)
    torchQuad(b, x, y, z, {{tx - e, oy + h, tz - e}, {tx - e, oy + h, tz + e}, {tx + e, oy + h, tz + e}, {tx + e, oy + h, tz - e}},
              {{u7, V(6)}, {u7, V(8)}, {u9, V(8)}, {u9, V(6)}}, {0, 1, 0}, lt, tile)
    -- Низ.
    torchQuad(b, x, y, z, {{cx + e + dx, oy, cz - e + dz}, {cx + e + dx, oy, cz + e + dz}, {cx - e + dx, oy, cz + e + dz}, {cx - e + dx, oy, cz - e + dz}},
              {{u9, V(13)}, {u9, V(15)}, {u7, V(15)}, {u7, V(13)}}, {0, -1, 0}, lt, tile)
    -- Четыре боковые плоскости во всю картинку.
    local z0, z1, x0, x1 = cz - 0.5, cz + 0.5, cx - 0.5, cx + 0.5
    local full = {{0, 1}, {0, 0}, {1, 0}, {1, 1}}
    torchQuad(b, x, y, z, {{cx - e, oy + 1, z0}, {cx - e + dx, oy, z0 + dz}, {cx - e + dx, oy, z1 + dz}, {cx - e, oy + 1, z1}},
              full, {-1, 0, 0}, lt, tile)
    torchQuad(b, x, y, z, {{cx + e, oy + 1, z1}, {cx + e + dx, oy, z1 + dz}, {cx + e + dx, oy, z0 + dz}, {cx + e, oy + 1, z0}},
              full, {1, 0, 0}, lt, tile)
    torchQuad(b, x, y, z, {{x0, oy + 1, cz + e}, {x0 + dx, oy, cz + e + dz}, {x1 + dx, oy, cz + e + dz}, {x1, oy + 1, cz + e}},
              full, {0, 0, 1}, lt, tile)
    torchQuad(b, x, y, z, {{x1, oy + 1, cz - e}, {x1 + dx, oy, cz - e + dz}, {x0 + dx, oy, cz - e + dz}, {x0, oy + 1, cz - e}},
              full, {0, 0, -1}, lt, tile)
end

-- Дверь — RenderBlocks.renderBlockDoor 1.7.10: шесть граней коробки полотна
-- (door.lua: 3/16 у стороны клетки по состоянию обеих половин). Развёртка —
-- по границам коробки, как у renderFace*: верх и низ — полоска нижней
-- картинки, бока — u по своей оси (у «обратных» граней — в обратную сторону),
-- v = 16 − y·16; зеркальная картинка (IconFlipped) — u → 16 − u. Бока
-- верхней половины — верхняя картинка. Свет грани на границе клетки — из
-- соседней клетки, внутри — из своей; оттенок стороны — по нормали.
-- Сторона оригинала 0..5 → грань FACES (её соседняя клетка).
local DOOR_FACE = {[0] = 2, [1] = 1, [2] = 6, [3] = 5, [4] = 4, [5] = 3}
local function doorLT(v)
    local s, l = cellLight(v)
    return {s, l, s, l, s, l, s, l}
end
-- Коробка блока шестью гранями, как RenderBlocks.renderStandardBlock /
-- renderFace*: развёртка по границам коробки. pick(side) → плитка и
-- зеркалить ли её (IconFlipped); lightOf(side, на_границе) → свет грани.
local function emitBox(b, x, y, z, bx, pick, lightOf)
    local x0, y0, z0, x1, y1, z1 = bx[1], bx[2], bx[3], bx[4], bx[5], bx[6]
    local P = 16
    -- Грань: углы (в долях клетки) и (U, V) оригинала в пикселях 0..16.
    local faces = {
        [0] = {{0, -1, 0}, {{x0, y0, z1}, {x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}},
               {{x0 * P, z1 * P}, {x0 * P, z0 * P}, {x1 * P, z0 * P}, {x1 * P, z1 * P}}, y0 <= 0},
        [1] = {{0, 1, 0}, {{x1, y1, z1}, {x1, y1, z0}, {x0, y1, z0}, {x0, y1, z1}},
               {{x1 * P, z1 * P}, {x1 * P, z0 * P}, {x0 * P, z0 * P}, {x0 * P, z1 * P}}, y1 >= 1},
        [2] = {{0, 0, -1}, {{x0, y1, z0}, {x1, y1, z0}, {x1, y0, z0}, {x0, y0, z0}},
               {{x1 * P, P - y1 * P}, {x0 * P, P - y1 * P}, {x0 * P, P - y0 * P}, {x1 * P, P - y0 * P}}, z0 <= 0},
        [3] = {{0, 0, 1}, {{x0, y1, z1}, {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}},
               {{x0 * P, P - y1 * P}, {x0 * P, P - y0 * P}, {x1 * P, P - y0 * P}, {x1 * P, P - y1 * P}}, z1 >= 1},
        [4] = {{-1, 0, 0}, {{x0, y1, z1}, {x0, y1, z0}, {x0, y0, z0}, {x0, y0, z1}},
               {{z1 * P, P - y1 * P}, {z0 * P, P - y1 * P}, {z0 * P, P - y0 * P}, {z1 * P, P - y0 * P}}, x0 <= 0},
        [5] = {{1, 0, 0}, {{x1, y0, z1}, {x1, y0, z0}, {x1, y1, z0}, {x1, y1, z1}},
               {{z0 * P, P - y0 * P}, {z1 * P, P - y0 * P}, {z1 * P, P - y1 * P}, {z0 * P, P - y1 * P}}, x1 >= 1},
    }
    for side = 0, 5 do
        local f = faces[side]
        local tile, flip = pick(side)
        local uvs = {}
        for k = 1, 4 do
            local u, vv = f[3][k][1], f[3][k][2]
            if flip then u = P - u end
            uvs[k] = {u / P, 1 - vv / P}
        end
        addQuad(b, x, y, z, f[2], f[1], uvs, lightOf(side, f[4]), tile, false)
    end
end

local function emitDoor(b, x, y, z, full, tiles, override, lightOf)
    local D = require "door"
    local top = (full & 8) ~= 0
    emitBox(b, x, y, z, D.box(full), function(side)
        if override then return override, false end
        if side <= 1 then return tiles.side, false end
        return top and tiles.upper or tiles.side, D.flipped(full, side)
    end, lightOf)
end
M.emitDoor = emitDoor

-- Люк (BlockTrapDoor): та же стандартная коробка по метаданным (trapdoor.lua),
-- одна картинка на все грани.
local function emitTrapdoor(b, x, y, z, meta, tile, lightOf)
    emitBox(b, x, y, z, require("trapdoor").box(meta), function() return tile, false end, lightOf)
end

-- Лестница — RenderBlocks.renderBlockLadder 1.7.10: одна плоскость
-- картинки в 0.05 от опоры (f4), во всю клетку, лицом от стены; свет — своей
-- клетки, оттенок 1 (нормаль «вверх» с долей настоящей — см. torchQuad:
-- движок разворачивает треугольник, чья нормаль против геометрической).
local function emitLadder(b, x, y, z, v, tile, lt)
    local meta = (v >> W.META_SHIFT) & 15
    local f4 = 0.05
    local c, uv, n
    -- (u, v) оригинала: min — 0, max — 1 по плитке; v атласа — снизу.
    local u0, u1, vt, vb = 0, 1, 1, 0
    if meta == 5 then
        c = {{f4, 1, 1}, {f4, 0, 1}, {f4, 0, 0}, {f4, 1, 0}}
        uv = {{u0, vt}, {u0, vb}, {u1, vb}, {u1, vt}}; n = {1, 0, 0}
    elseif meta == 4 then
        c = {{1 - f4, 0, 1}, {1 - f4, 1, 1}, {1 - f4, 1, 0}, {1 - f4, 0, 0}}
        uv = {{u1, vb}, {u1, vt}, {u0, vt}, {u0, vb}}; n = {-1, 0, 0}
    elseif meta == 3 then
        c = {{1, 0, f4}, {1, 1, f4}, {0, 1, f4}, {0, 0, f4}}
        uv = {{u1, vb}, {u1, vt}, {u0, vt}, {u0, vb}}; n = {0, 0, 1}
    else
        c = {{1, 1, 1 - f4}, {1, 0, 1 - f4}, {0, 0, 1 - f4}, {0, 1, 1 - f4}}
        uv = {{u0, vt}, {u0, vb}, {u1, vb}, {u1, vt}}; n = {0, 0, -1}
    end
    addQuad(b, x, y, z, c, {n[1] * 0.6, 1.2, n[3] * 0.6}, uv, lt or flatLight(v), tile, false)
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
                    elseif kind == 7 then
                        emitLadder(solid, x, y, z, v, tiles.side)
                    elseif kind == 8 then
                        local wi = rowBase + x + 1
                        emitTrapdoor(solid, x, y, z, (v >> W.META_SHIFT) & 15, tiles.side, function(side, border)
                            return doorLT(border and win[wi + FACES[DOOR_FACE[side]].dn] or v)
                        end)
                    elseif kind == 6 then
                        -- Дверь рисуется, только если на месте вторая половина.
                        local wi = rowBase + x + 1
                        local m = (v >> W.META_SHIFT) & 15
                        local otherV = win[wi + FACES[(m & 8) ~= 0 and 2 or 1].dn]
                        if (otherV & ID_MASK) == id then
                            local full = require("door").fullMetaOf(m, (otherV >> W.META_SHIFT) & 15)
                            emitDoor(solid, x, y, z, full, tiles, nil, function(side, border)
                                return doorLT(border and win[wi + FACES[DOOR_FACE[side]].dn] or v)
                            end)
                        end
                    elseif kind ~= 0 then
                        local b = kind == 4 and liquid or solid
                        local inset = B.byId[id].inset
                        local wi = rowBase + x + 1
                        for fi = 1, 6 do
                            local f = FACES[fi]
                            local nid = win[wi + f.dn] & ID_MASK
                            local show
                            if nid == 0 then show = true
                            elseif opaque[nid] then show = false
                            else show = faceVisible(id, kind, nid) end
                            if inset and fi > 2 then show = true end
                            if show then
                                local flip = cornerLights(f, wi)
                                local corners = f.c
                                if kind == 4 and fi == 1 and (win[wi + FACES[1].dn] & ID_MASK) ~= id then
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
                                local tileKey = f.tile
                                -- Лицо печи и тыквы — по метаданным, а не на одной
                                -- стороне (BlockFurnace/BlockPumpkin.getIcon).
                                local front = B.facing[id] and B.frontSide(id, (v >> W.META_SHIFT) & 15)
                                if front then
                                    if FACE_SIDE[fi] == front then tileKey = "front"
                                    elseif fi > 2 then tileKey = "side" end
                                end
                                addQuad(b, x, y, z, corners, f.n, f.uv, LB, tiles[tileKey], flip, AOB)
                            end
                        end
                    end
                end
            end
        end
    end
    return solid, liquid
end

-- Один блок в начале координат с чужой плиткой (трещины —
-- RenderBlocks.renderBlockUsingTexture): та же форма, что в участке (Render
-- Bounds: крест у растений, плоскости у факела, сужение у кактуса), все шесть
-- граней куба (renderAllFaces). Возвращает пачку для mesh.arrays.
local ZERO_LT = {0, 0, 0, 0, 0, 0, 0, 0}
function M.single(id, meta, tile, wx, wy, wz)
    local b = batch()
    local kind = drawKind[id]
    local v = id | ((meta or 0) << W.META_SHIFT)
    if kind == 3 then
        emitCross(b, 0, 0, 0, v, tile)
    elseif kind == 5 then
        emitTorch(b, 0, 0, 0, v, tile)
    elseif kind == 7 then
        emitLadder(b, 0, 0, 0, v, tile, ZERO_LT)
    elseif kind == 8 then
        emitTrapdoor(b, 0, 0, 0, meta or 0, tile, function() return ZERO_LT end)
    elseif kind == 6 then
        local full = wx and require("door").fullMeta(wx, wy, wz) or (meta or 0)
        emitDoor(b, 0, 0, 0, full, nil, tile, function() return ZERO_LT end)
    elseif kind ~= 0 and kind ~= 4 then
        local inset = B.byId[id].inset
        for fi = 1, 6 do
            local f = FACES[fi]
            local corners = f.c
            if inset and fi > 2 then
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
            addQuad(b, 0, 0, 0, corners, f.n, f.uv, ZERO_LT, tile, false)
        end
    end
    return b
end

-- Грани с развёрткой — для всех, кто строит кубик блока вне мира (выпавший
-- блок, крошки): та же раскладка UV, что у граней участка.
M.FACES = FACES
M.faceUV = faceUV

return M
