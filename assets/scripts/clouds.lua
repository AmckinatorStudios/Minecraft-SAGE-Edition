-- ---------------------------------------------------------------------------
-- clouds.lua — объёмные облака: поле клеток CELL×CELL, каждая занятая клетка —
-- коробка высотой THICK. Между соседними занятыми клетками стенок нет, поэтому
-- облако — цельное тело с верхом, низом и боками, а не набор кубиков.
--
-- Узор — свой шум по зерну мира, повторяется с периодом PERIOD клеток.
-- Ветер сносит поле по X; меш строится на окно вокруг игрока и
-- пересобирается, только когда поле уехало на целую клетку (или игрок ушёл
-- далеко) — между этим объект просто сдвигается.
-- ---------------------------------------------------------------------------
local Clouds = {}

local CELL, THICK, HEIGHT = 12, 4, 120
local PERIOD = 64
local RANGE = 22              -- клеток от центра окна в каждую сторону
local WIND = 1.2              -- блоков в секунду
local MAT = "assets/materials/clouds.sagemat"

local field = {}
local obj
local shift = 0               -- накопленный снос ветром, блоков
local builtAt                 -- клетка, вокруг которой построен меш

local function filled(i, j)
    return field[(i % PERIOD) + (j % PERIOD) * PERIOD] == true
end

function Clouds.init(seed)
    local n = noise{kind = "simplex", seed = seed + 101, octaves = 3, scale = 1 / 9}
    for j = 0, PERIOD - 1 do
        for i = 0, PERIOD - 1 do
            -- Шум на торе: поле бесшовно повторяется по обеим осям.
            local a, b = i / PERIOD * 2 * math.pi, j / PERIOD * 2 * math.pi
            local v = n(math.cos(a) * 10, math.sin(a) * 10, math.cos(b) * 10 + math.sin(b) * 7)
            field[i + j * PERIOD] = v > 0.18
        end
    end
    obj = SpawnObject("Clouds")
end

local function build(ci, cj)
    local pos, nrm, idx = {}, {}, {}
    local nv = 0
    local function face(corners, n)
        for k = 1, 4 do
            local p = corners[k]
            pos[#pos + 1] = p[1]; pos[#pos + 1] = p[2]; pos[#pos + 1] = p[3]
            nrm[#nrm + 1] = n[1]; nrm[#nrm + 1] = n[2]; nrm[#nrm + 1] = n[3]
        end
        idx[#idx + 1] = nv + 1; idx[#idx + 1] = nv + 2; idx[#idx + 1] = nv + 3
        idx[#idx + 1] = nv + 1; idx[#idx + 1] = nv + 3; idx[#idx + 1] = nv + 4
        nv = nv + 4
    end
    for j = cj - RANGE, cj + RANGE do
        for i = ci - RANGE, ci + RANGE do
            if filled(i, j) then
                local x0, x1 = i * CELL, (i + 1) * CELL
                local z0, z1 = j * CELL, (j + 1) * CELL
                local y0, y1 = 0, THICK
                face({{x0,y1,z0},{x0,y1,z1},{x1,y1,z1},{x1,y1,z0}}, {0, 1, 0})
                face({{x0,y0,z0},{x1,y0,z0},{x1,y0,z1},{x0,y0,z1}}, {0, -1, 0})
                if not filled(i + 1, j) then face({{x1,y0,z0},{x1,y1,z0},{x1,y1,z1},{x1,y0,z1}}, {1, 0, 0}) end
                if not filled(i - 1, j) then face({{x0,y0,z0},{x0,y0,z1},{x0,y1,z1},{x0,y1,z0}}, {-1, 0, 0}) end
                if not filled(i, j + 1) then face({{x0,y0,z1},{x1,y0,z1},{x1,y1,z1},{x0,y1,z1}}, {0, 0, 1}) end
                if not filled(i, j - 1) then face({{x0,y0,z0},{x0,y1,z0},{x1,y1,z0},{x1,y0,z0}}, {0, 0, -1}) end
            end
        end
    end
    if nv == 0 then return end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, index = idx}
    m.apply(obj)
    SetMaterial(obj, MAT)
    builtAt = {ci, cj}
end

function Clouds.update(dt, P)
    if not obj then return end
    shift = shift + WIND * dt
    -- Клетка поля под игроком с учётом сноса: поле уехало на shift вправо,
    -- значит игрок «стоит» на клетке левее.
    local ci = math.floor((P.pos.x - shift) / CELL)
    local cj = math.floor(P.pos.z / CELL)
    if not builtAt or math.abs(ci - builtAt[1]) > 4 or math.abs(cj - builtAt[2]) > 4 then build(ci, cj) end
    obj.Transform.Position = Vec3(shift, HEIGHT, 0)
    -- Снизу облака видны лицом вниз, изнутри — тоже: отсечение задних граней
    -- выключаем, когда камера внутри слоя (иначе облако исчезает изнутри).
    local _, ey = P.eye()
    local inside = ey > HEIGHT and ey < HEIGHT + THICK
    if inside ~= Clouds._inside then
        Clouds._inside = inside
        SetMaterialParam(MAT, "uCloudColor", inside and Vec3(0.9, 0.9, 0.92) or Vec3(1, 1, 1))
    end
end

return Clouds
