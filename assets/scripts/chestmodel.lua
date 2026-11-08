-- ---------------------------------------------------------------------------
-- chestmodel.lua — модель сундука из присланных Blockbench-моделей
-- (art/chest/Chest.gltf, Double_Chest_Left.gltf, Double_Chest_Right.gltf;
-- геометрия — chestmesh.lua, его пишет tools/gltf_chest.py).
--
-- Модели повторяют ModelChest 1.7.10: корпус 14×10×14, крышка 14×5×14,
-- защёлка 2×4×1 (единица — 1/16 блока). Двойной сундук — две половины, каждая
-- рисуется СВОЕЙ клеткой: левая (шов у −X модели) и правая (шов у +X), без
-- внутренних граней шва; вместе они — ModelLargeChest 30×10×14 на
-- normal_double.png (UV половин — его развёртка). Одиночный — normal.png.
--
-- Части: корпус (Base), крышка (Lid) и защёлка (Lock) — дочерняя крышки,
-- поэтому они двигаются вместе. Крышка вращается вокруг X в точке
-- lid_pivot (задний верхний край корпуса): угол 1 − (1 − a)³ от 0 до 90°
-- (TileEntityChestRenderer: rotateAngleX = −(1 − (1 − a)³)·π/2).
-- Перед модели смотрит на −Z; сторона блока поворачивает её вокруг Y:
-- 2 (север) — 0°, 3 (юг) — 180°, 4 (запад) — 90°, 5 (восток) — −90°.
-- ---------------------------------------------------------------------------
local Mat = require "mat"
local DATA = require "chestmesh"

local CM = {}

CM.MAT = "assets/materials/chest.sagemat"
CM.MAT_DOUBLE = "assets/materials/chest_double.sagemat"
CM.DATA = DATA

local SIDE_ANGLE = {[2] = 0, [3] = 180, [4] = 90, [5] = -90}
CM.SIDE_ANGLE = SIDE_ANGLE

local meshes = {}
local function meshesOf(kind)
    if meshes[kind] then return meshes[kind] end
    local d = DATA[kind]
    local out = {}
    for _, part in ipairs({"base", "lid", "knob"}) do
        local p = d[part]
        local uv2 = {}
        for i = 1, #p.position // 3 do uv2[i * 2 - 1] = 15; uv2[i * 2] = 0 end
        local m = mesh()
        m.arrays{position = p.position, normal = p.normal, uv = p.uv, uv2 = uv2, index = p.index}
        out[part] = m
    end
    meshes[kind] = out
    return out
end

-- Половина пары: сосед в стороне (dx, dz) мира, сундук смотрит на meta.
-- В координатах модели (перед — −Z) сосед слева по X (−X) — «left» (шов
-- модели у −X), справа — «right».
function CM.halfFor(meta, dx, dz)
    local a = math.rad(-(SIDE_ANGLE[meta] or 0))
    local lx = dx * math.cos(a) + dz * math.sin(a)
    return lx < 0 and "left" or "right"
end

-- Матрица корня: середина низа клетки, поворот по стороне.
function CM.rootMatrix(x, y, z, meta)
    local m = Mat.identity()
    Mat.translate(m, x + 0.5, y, z + 0.5)
    Mat.rotate(m, SIDE_ANGLE[meta] or 0, 0, 1, 0)
    return m
end

-- Новая модель kind ("single" | "left" | "right").
function CM.create(kind)
    local ms = meshesOf(kind)
    local mat = kind == "single" and CM.MAT or CM.MAT_DOUBLE
    local r = {kind = kind}
    r.root = SpawnObject(kind == "single" and "Chest" or "Large Chest " .. kind)
    local function part(name, parent, m)
        local o = SpawnObject(name)
        o:SetParent(parent)
        m.apply(o)
        SetMaterial(o, mat)
        return o
    end
    r.base = part("Chest Base", r.root, ms.base)
    r.lid = part("Chest Lid", r.root, ms.lid)
    r.knob = part("Chest Lock", r.lid, ms.knob)
    local pv = DATA[kind].pivot
    r.lid.Transform.Position = Vec3(pv[1], pv[2], pv[3])
    r.parts = {r.base, r.lid, r.knob}
    return r
end

function CM.destroy(r)
    if not r then return end
    DestroyObject(r.knob); DestroyObject(r.lid); DestroyObject(r.base); DestroyObject(r.root)
end

-- Угол крышки оригинала (радианы, ≤ 0): a — доля открытия между тиками.
function CM.lidAngle(a)
    local f = 1 - a
    f = 1 - f * f * f
    return -(f * math.pi / 2)
end

-- Матрица крышки относительно корня: поворот вокруг X в точке вращения.
-- Перед крышки (−Z) поднимается: поворот на +угол (угол оригинала — со
-- знаком минус в его отражённой системе координат).
function CM.lidMatrix(kind, a)
    local pv = DATA[kind].pivot
    local m = Mat.identity()
    Mat.translate(m, pv[1], pv[2], pv[3])
    Mat.rotate(m, -math.deg(CM.lidAngle(a)), 1, 0, 0)
    return m
end

-- Поза: клетка (x, y, z), сторона meta, a — открытие 0..1, свет {небо, блоки}.
function CM.pose(r, x, y, z, meta, a, light)
    Mat.applyTo(r.root, CM.rootMatrix(x, y, z, meta))
    Mat.applyTo(r.lid, CM.lidMatrix(r.kind, a))
    if light then
        local Light = require "lightmap"
        for _, o in ipairs(r.parts) do Light.applyLevels(o, light[1], light[2]) end
    end
end

return CM
