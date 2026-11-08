-- ---------------------------------------------------------------------------
-- pigmodel.lua — модель свиньи 1.7.10: ModelPig, наследник ModelQuadruped(6).
--
-- Коробки ModelBox с развёрткой текстуры 64×32 (pig.png), в единицах модели
-- (16 = блок; ось y модели — вниз, перед — к −z):
--   голова  (0, 0)   −4, −4, −8  8×8×8,  центр поворота (0, 12, −6);
--   рыло    (16, 16) −2,  0, −9  4×3×1  — часть головы;
--   тело    (28, 8)  −5, −10, −7 10×16×8, центр (0, 11, 2), повёрнуто на 90°
--                     вокруг x (rotateAngleX = π/2);
--   ноги    (0, 16)  −2, 0, −2   4×6×4,  центры (∓3, 18, 7) и (∓3, 18, −5).
-- Перевод в мир — как RendererLivingEntity: поворот на 180 − yaw, scale(−1,
-- −1, 1) и сдвиг на 1.5 блока вниз: точка модели (x, y, z) → (−x, 1.5 − y, z)/16.
-- Поворот части a вокруг оси x или y модели после отражения — поворот на −a.
--
-- Поросёнок (ModelQuadruped.render с isChild): голова НЕ уменьшается, но
-- сдвигается на (0, 4, 4) (у свиньи field_78145_g = 4); тело и ноги — вдвое
-- меньше и на 24 единицы вниз (glScalef(1/2), glTranslatef(0, 24·f5, 0)).
-- ---------------------------------------------------------------------------
local Mat = require "mat"

local PM = {}

local TW, TH = 64, 32
PM.MAT = "assets/materials/pig.sagemat"
PM.MAT_HURT = "assets/materials/pig_hurt.sagemat"

-- Точка модели → координаты объекта (отражение x и y, 1/16).
local function L(x, y, z) return -x / 16, -y / 16, z / 16 end

-- Коробка ModelBox: (x, y, z) — угол, w, h, d — размеры, (u, v) — смещение
-- текстуры; rot(x, y, z) — необязательный постоянный поворот вершин (тело).
-- Развёртка и порядок вершин — как в ModelBox/TexturedQuad 1.7.10.
local function addBox(b, x, y, z, w, h, d, u, v, rot)
    local x1, y1, z1 = x + w, y + h, z + d
    local P = {
        [7] = {x, y, z}, [0] = {x1, y, z}, [1] = {x1, y1, z}, [2] = {x, y1, z},
        [3] = {x, y, z1}, [4] = {x1, y, z1}, [5] = {x1, y1, z1}, [6] = {x, y1, z1},
    }
    -- quadList: вершины и прямоугольник текстуры (u1, v1, u2, v2), нормаль модели.
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
        -- TexturedQuad: вершина 0 — (u2, v1), 1 — (u1, v1), 2 — (u1, v2), 3 — (u2, v2).
        local uvs = {{u2, v1}, {u1, v1}, {u1, v2}, {u2, v2}}
        local n = q[6]
        if rot then n = rot(n[1], n[2], n[3], true) end
        local nx, ny, nz = -n[1], -n[2], n[3]
        local base = b.n
        for k = 1, 4 do
            local p = P[q[1][k]]
            local px, py, pz = p[1], p[2], p[3]
            if rot then px, py, pz = table.unpack(rot(px, py, pz)) end
            local lx, ly, lz = L(px, py, pz)
            b.pos[#b.pos + 1] = lx; b.pos[#b.pos + 1] = ly; b.pos[#b.pos + 1] = lz
            b.nrm[#b.nrm + 1] = nx; b.nrm[#b.nrm + 1] = ny; b.nrm[#b.nrm + 1] = nz
            -- v картинки — сверху, у текстуры-файла — снизу.
            b.uv[#b.uv + 1] = uvs[k][1] / TW; b.uv[#b.uv + 1] = 1 - uvs[k][2] / TH
            b.uv2[#b.uv2 + 1] = 15; b.uv2[#b.uv2 + 1] = 0
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do b.idx[#b.idx + 1] = base + i end
        b.n = base + 4
    end
end

local function newBatch() return {pos = {}, nrm = {}, uv = {}, uv2 = {}, idx = {}, n = 0} end
local function toMesh(b)
    local m = mesh()
    m.arrays{position = b.pos, normal = b.nrm, uv = b.uv, uv2 = b.uv2, index = b.idx}
    return m
end

-- Тело: rotateAngleX = π/2 постоянен — вершины повёрнуты заранее, тогда и
-- нормали граней верные (освещение стороны берёт нормаль меша).
local function bodyRot(x, y, z, isNormal)
    -- Поворот вокруг x модели на +90°: y' = −z, z' = y (glRotatef в модели).
    local c, s = 0, 1
    local ny, nz = y * c - z * s, y * s + z * c
    if isNormal then return {x, ny, nz} end
    return {x, ny, nz}
end

local meshes
local function buildMeshes()
    if meshes then return meshes end
    meshes = {}
    local h = newBatch()
    addBox(h, -4, -4, -8, 8, 8, 8, 0, 0)
    addBox(h, -2, 0, -9, 4, 3, 1, 16, 16)
    meshes.head = toMesh(h)
    local b = newBatch()
    addBox(b, -5, -10, -7, 10, 16, 8, 28, 8, bodyRot)
    meshes.body = toMesh(b)
    local l = newBatch()
    addBox(l, -2, 0, -2, 4, 6, 4, 0, 16)
    meshes.leg = toMesh(l)
    return meshes
end

PM.LEG_PIVOTS = {{-3, 18, 7}, {3, 18, 7}, {-3, 18, -5}, {3, 18, -5}}

local function part(name, parent, m)
    local o = SpawnObject(name)
    o:SetParent(parent)
    m.apply(o)
    SetMaterial(o, PM.MAT)
    return o
end

-- Новая модель: корень и части.
function PM.create()
    local ms = buildMeshes()
    local r = {}
    r.root = SpawnObject("Pig")
    r.headGroup = SpawnObject("Pig Head Group"); r.headGroup:SetParent(r.root)
    r.bodyGroup = SpawnObject("Pig Body Group"); r.bodyGroup:SetParent(r.root)
    r.head = part("Pig Head", r.headGroup, ms.head)
    r.body = part("Pig Body", r.bodyGroup, ms.body)
    r.legs = {}
    for i = 1, 4 do r.legs[i] = part("Pig Leg " .. i, r.bodyGroup, ms.leg) end
    r.parts = {r.head, r.body, r.legs[1], r.legs[2], r.legs[3], r.legs[4]}
    r.mat = PM.MAT
    return r
end

function PM.destroy(r)
    -- Корнем — вся модель разом (части — его потомки), см. chestmodel.destroy.
    DestroyObject(r.root)
end

-- Поза кадра. s: x, y, z — ноги; yaw — тело (наш поворот: 0 — на −Z);
-- headYaw — голова относительно тела (наш), pitch — наклон головы
-- (оригинала: плюс — вниз); swing, amount — limbSwing и limbSwingAmount;
-- child; death — угол завала (deathTime); hurt — красный; light — {небо, блоки}.
function PM.pose(r, s)
    local m = Mat.identity()
    Mat.translate(m, s.x, s.y, s.z)
    Mat.rotate(m, s.yaw, 0, 1, 0)
    -- Смерть (rotateCorpse): завал на бок до 90° вокруг оси взгляда.
    if s.death and s.death > 0 then Mat.rotate(m, s.death, 0, 0, 1) end
    Mat.applyTo(r.root, m)

    -- Группы: взрослая — точка модели на 1.5 блока выше ног; поросёнок —
    -- голова на (0, 4, 4) единиц модели, тело и ноги — вдвое меньше.
    if s.child then
        r.headGroup.Transform.Position = Vec3(0, 1.5 - 4 / 16, 4 / 16)
        r.bodyGroup.Transform.Position = Vec3(0, 0.75, 0)
        r.bodyGroup.Transform.Scale = Vec3(0.5, 0.5, 0.5)
    else
        r.headGroup.Transform.Position = Vec3(0, 1.5, 0)
        r.bodyGroup.Transform.Position = Vec3(0, 1.5, 0)
        r.bodyGroup.Transform.Scale = Vec3(1, 1, 1)
    end

    -- Голова: head.rotateAngleY = yaw головы, rotateAngleX = pitch (порядок
    -- ModelRenderer: Z, Y, X), после отражения — с обратным знаком.
    local hm = Mat.identity()
    Mat.translate(hm, L(0, 12, -6))
    Mat.rotate(hm, s.headYaw or 0, 0, 1, 0)
    Mat.rotate(hm, -(s.pitch or 0), 1, 0, 0)
    Mat.applyTo(r.head, hm)
    r.body.Transform.Position = Vec3(L(0, 11, 2))

    -- Ноги (ModelQuadruped.setRotationAngles): cos(swing·0.6662 [+π])·1.4·amount;
    -- 1 и 4 — в одной фазе, 2 и 3 — в противоположной (диагональные пары).
    local sw, am = s.swing or 0, s.amount or 0
    local a1 = math.cos(sw * 0.6662) * 1.4 * am
    local a2 = math.cos(sw * 0.6662 + math.pi) * 1.4 * am
    local angles = {a1, a2, a2, a1}
    for i = 1, 4 do
        local lm = Mat.identity()
        local p = PM.LEG_PIVOTS[i]
        Mat.translate(lm, L(p[1], p[2], p[3]))
        Mat.rotate(lm, -math.deg(angles[i]), 1, 0, 0)
        Mat.applyTo(r.legs[i], lm)
    end

    local want = s.hurt and PM.MAT_HURT or PM.MAT
    if r.mat ~= want then
        r.mat = want
        for _, o in ipairs(r.parts) do SetMaterial(o, want) end
    end
    if s.light then
        local Light = require "lightmap"
        for _, o in ipairs(r.parts) do Light.applyLevels(o, s.light[1], s.light[2]) end
    end
end

-- Самопроверка (--gencheck, строка PIGMODELCHECK): размеры частей и ноги в
-- противофазе по диагоналям.
function PM.selfCheck()
    local ms = buildMeshes()
    local ok = ms.head ~= nil and ms.body ~= nil and ms.leg ~= nil
    local sw = 1.3
    local a1 = math.cos(sw * 0.6662) * 1.4
    local a2 = math.cos(sw * 0.6662 + math.pi) * 1.4
    local phases = math.abs(a1 + a2) < 1e-9
    -- Нижняя грань ноги взрослой — на земле: y модели 18 + 6 = 24 → 0 блоков.
    local _, groundY = L(0, 24, 0)
    local grounded = math.abs(1.5 + groundY) < 1e-9
    local all = ok and phases and grounded
    return string.format("PIGMODELCHECK: %s меши=%s фазы=%s ноги_на_земле=%s", all and "PASS" or "FAIL", tostring(ok),
        tostring(phases), tostring(grounded))
end

return PM
