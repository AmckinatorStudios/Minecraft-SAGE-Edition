-- ---------------------------------------------------------------------------
-- chestmodel.lua — модель сундука 1.7.10: ModelChest и ModelLargeChest,
-- поза — TileEntityChestRenderer.
--
-- Три части (как узлы body / lid_pivot присланной модели Chest_1.gltf, где
-- корпус и крышка — кости одного меша): корпус (Base), крышка (Lid) и
-- защёлка (Lock) — дочерний объект крышки, поэтому они поворачиваются
-- вместе. Коробки ModelBox (единица модели = 1/16 блока), развёртка — как у
-- ModelBox/TexturedQuad 1.7.10 на normal.png (64×64) и normal_double.png
-- (128×64):
--   обычный:   корпус (0, 19) 0, 0, 0   14×10×14, центр (1, 6, 1);
--              крышка (0, 0)  0, −5, −14 14×5×14, центр (1, 7, 15);
--              защёлка (0, 0) −1, −2, −15 2×4×1, центр (8, 7, 15);
--   большой:   корпус 30×10×14, крышка 30×5×14, защёлка — центр (16, 7, 15).
-- Перевод в мир (renderTileEntityAt): translate(x, y + 1, z + 1),
-- scale(1, −1, −1), translate(½), [сдвиг большого], rotate(угол стороны, Y),
-- translate(−½). scale(1, −1, −1) — это поворот на 180° вокруг X: он запечён
-- в вершины (y и z со знаком минус), а повороты сопряжены с ним — так
-- нормали частей смотрят верно (оттенок стороны шейдер берёт по ним).
-- Крышка: rotateAngleX = −(1 − (1 − a)³)·π/2, a — угол между тиками.
-- ---------------------------------------------------------------------------
local Mat = require "mat"

local CM = {}

CM.MAT = "assets/materials/chest.sagemat"
CM.MAT_DOUBLE = "assets/materials/chest_double.sagemat"

-- Коробка ModelBox с запечённым scale(1, −1, −1): точка модели (x, y, z) →
-- (x, −y, −z)/16, нормаль (nx, ny, nz) → (nx, −ny, −nz).
local function addBox(b, tw, th, x, y, z, w, h, d, u, v)
    local x1, y1, z1 = x + w, y + h, z + d
    local P = {
        [7] = {x, y, z}, [0] = {x1, y, z}, [1] = {x1, y1, z}, [2] = {x, y1, z},
        [3] = {x, y, z1}, [4] = {x1, y, z1}, [5] = {x1, y1, z1}, [6] = {x, y1, z1},
    }
    local quads = {
        {{4, 0, 1, 5}, u + d + w, v + d, u + d + w + d, v + d + h, {1, 0, 0}},
        {{7, 3, 6, 2}, u, v + d, u + d, v + d + h, {-1, 0, 0}},
        {{4, 3, 7, 0}, u + d, v, u + d + w, v + d, {0, -1, 0}},
        {{1, 2, 6, 5}, u + d + w, v + d, u + d + w + w, v, {0, 1, 0}},
        {{0, 7, 2, 1}, u + d, v + d, u + d + w, v + d + h, {0, 0, -1}},
        {{3, 4, 5, 6}, u + d + w + d, v + d, u + d + w + d + w, v + d + h, {0, 0, 1}},
    }
    for _, q in ipairs(quads) do
        local u1, v1, u2, v2 = q[2], q[3], q[4], q[5]
        local uvs = {{u2, v1}, {u1, v1}, {u1, v2}, {u2, v2}}
        local n = q[6]
        local base = b.n
        for k = 1, 4 do
            local p = P[q[1][k]]
            b.pos[#b.pos + 1] = p[1] / 16; b.pos[#b.pos + 1] = -p[2] / 16; b.pos[#b.pos + 1] = -p[3] / 16
            b.nrm[#b.nrm + 1] = n[1]; b.nrm[#b.nrm + 1] = -n[2]; b.nrm[#b.nrm + 1] = -n[3]
            b.uv[#b.uv + 1] = uvs[k][1] / tw; b.uv[#b.uv + 1] = 1 - uvs[k][2] / th
            b.uv2[#b.uv2 + 1] = 15; b.uv2[#b.uv2 + 1] = 0
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do b.idx[#b.idx + 1] = base + i end
        b.n = base + 4
    end
end

local function boxMesh(tw, th, ...)
    local b = {pos = {}, nrm = {}, uv = {}, uv2 = {}, idx = {}, n = 0}
    addBox(b, tw, th, ...)
    local m = mesh()
    m.arrays{position = b.pos, normal = b.nrm, uv = b.uv, uv2 = b.uv2, index = b.idx}
    return m
end

-- Описание моделей: размеры и центры частей (единицы модели).
CM.SPEC = {
    single = {tw = 64, th = 64, mat = CM.MAT, width = 14, knob = {8, 7, 15}},
    double = {tw = 128, th = 64, mat = CM.MAT_DOUBLE, width = 30, knob = {16, 7, 15}},
}
CM.BASE_PIVOT, CM.LID_PIVOT = {1, 6, 1}, {1, 7, 15}

local meshes = {}
local function meshesOf(kind)
    if meshes[kind] then return meshes[kind] end
    local s = CM.SPEC[kind]
    meshes[kind] = {
        base = boxMesh(s.tw, s.th, 0, 0, 0, s.width, 10, 14, 0, 19),
        lid = boxMesh(s.tw, s.th, 0, -5, -14, s.width, 5, 14, 0, 0),
        knob = boxMesh(s.tw, s.th, -1, -2, -15, 2, 4, 1, 0, 0),
    }
    return meshes[kind]
end

-- Точка модели после scale(1, −1, −1), в блоках.
local function S(p) return p[1] / 16, -p[2] / 16, -p[3] / 16 end

-- Новая модель kind ("single" | "double"): корень, корпус, крышка, защёлка на крышке.
function CM.create(kind)
    local s, ms = CM.SPEC[kind], meshesOf(kind)
    local r = {kind = kind}
    r.root = SpawnObject(kind == "double" and "Large Chest" or "Chest")
    local function part(name, parent, m)
        local o = SpawnObject(name)
        o:SetParent(parent)
        m.apply(o)
        SetMaterial(o, s.mat)
        return o
    end
    r.base = part("Chest Base", r.root, ms.base)
    r.lid = part("Chest Lid", r.root, ms.lid)
    r.knob = part("Chest Lock", r.lid, ms.knob)
    r.base.Transform.Position = Vec3(S(CM.BASE_PIVOT))
    -- Защёлка — от центра крышки к своему центру (ось поворота у них общая).
    local k = s.knob
    r.knob.Transform.Position = Vec3(S({k[1] - CM.LID_PIVOT[1], k[2] - CM.LID_PIVOT[2], k[3] - CM.LID_PIVOT[3]}))
    r.parts = {r.base, r.lid, r.knob}
    return r
end

function CM.destroy(r)
    if not r then return end
    DestroyObject(r.knob); DestroyObject(r.lid); DestroyObject(r.base); DestroyObject(r.root)
end

-- Угол стороны (renderTileEntityAt): 2 → 180, 3 → 0, 4 → 90, 5 → −90.
local SIDE_ANGLE = {[2] = 180, [3] = 0, [4] = 90, [5] = -90}

-- Угол крышки для отрисовки: a — доля открытия между тиками (0..1).
function CM.lidAngle(a)
    local f = 1 - a
    f = 1 - f * f * f
    return -(f * math.pi / 2)
end

-- Поза: клетка (x, y, z), сторона meta, a — открытие 0..1, второй сундук
-- (xPos — сосед по +X, zPos — по +Z), свет {небо, блоки}.
function CM.pose(r, x, y, z, meta, a, xPos, zPos, light)
    local m = Mat.identity()
    -- translate(x, y + 1, z + 1) · scale(1, −1, −1) · translate(½) — с
    -- запечённым scale: дальше всё сопряжено с ним (y, z — со знаком минус).
    Mat.translate(m, x, y + 1, z + 1)
    Mat.translate(m, 0.5, -0.5, -0.5)
    if meta == 2 and xPos then Mat.translate(m, 1, 0, 0) end
    if meta == 5 and zPos then Mat.translate(m, 0, 0, 1) end
    Mat.rotate(m, -(SIDE_ANGLE[meta] or 0), 0, 1, 0)
    Mat.translate(m, -0.5, 0.5, 0.5)
    Mat.applyTo(r.root, m)
    local lm = Mat.identity()
    Mat.translate(lm, S(CM.LID_PIVOT))
    Mat.rotate(lm, math.deg(CM.lidAngle(a)), 1, 0, 0)
    Mat.applyTo(r.lid, lm)
    if light then
        local Light = require "lightmap"
        for _, o in ipairs(r.parts) do Light.applyLevels(o, light[1], light[2]) end
    end
end

return CM
