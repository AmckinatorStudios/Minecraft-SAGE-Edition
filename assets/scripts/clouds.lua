-- ---------------------------------------------------------------------------
-- clouds.lua — облака Minecraft 1.7.10 (RenderGlobal.renderCloudsFancy).
--
-- Узор — текстура clouds.png 256×256: пиксель — клетка 12×12 блоков,
-- непрозрачный — облако. Слой — на высоте 128.33, толщиной 4 блока. Ветер —
-- 0.03 блока за тик облаков к западу (−X): поле сдвигается по своему
-- счётчику тиков, а не по времени мира.
--
-- Оригинал строит облака каждый кадр вокруг глаза: 8×8 кусков по 8×8 клеток
-- (от −24 до +40 клеток от клетки глаза — несимметрично, как у него),
-- верх и низ куска — одним квадратом, стенки — на каждой границе клеток,
-- лишнее отрезает альфа текстуры. Здесь меш тот же, но построен один раз в
-- клетках относительно клетки глаза: объект стоит в мире со сдвигом на долю
-- клетки, а какая клетка текстуры под гранью — сдвиг UV в шейдере.
-- Цвет — Sky.cloudColor (getCloudColour), туман — как у мира (sky.lua).
-- ---------------------------------------------------------------------------
local Clouds = {}

local CELL, THICK, HEIGHT = 12, 4, 128
local EPS = 1 / 1024
local MAT = "assets/materials/clouds.sagemat"

local obj

local function build()
    local pos, nrm, uv, idx = {}, {}, {}, {}
    local nv = 0
    local function quad(corners, n, uvs)
        for k = 1, 4 do
            local p, t = corners[k], uvs[k]
            pos[#pos + 1] = p[1]; pos[#pos + 1] = p[2]; pos[#pos + 1] = p[3]
            nrm[#nrm + 1] = n[1]; nrm[#nrm + 1] = n[2]; nrm[#nrm + 1] = n[3]
            uv[#uv + 1] = t[1] / 256; uv[#uv + 1] = t[2] / 256
        end
        idx[#idx + 1] = nv + 1; idx[#idx + 1] = nv + 2; idx[#idx + 1] = nv + 3
        idx[#idx + 1] = nv + 1; idx[#idx + 1] = nv + 3; idx[#idx + 1] = nv + 4
        nv = nv + 4
    end
    local B = 8
    for l = -3, 4 do
        for i1 = -3, 4 do
            local x0, z0 = l * B, i1 * B
            local x1, z1 = x0 + B, z0 + B
            local flat = {{x0, z0}, {x1, z0}, {x1, z1}, {x0, z1}}
            quad({{x0, 0, z0}, {x1, 0, z0}, {x1, 0, z1}, {x0, 0, z1}}, {0, -1, 0}, flat)
            local top = THICK - EPS
            quad({{x0, top, z0}, {x1, top, z0}, {x1, top, z1}, {x0, top, z1}}, {0, 1, 0}, flat)
            for j = 0, B - 1 do
                local uc = x0 + j + 0.5
                local vc = z0 + j + 0.5
                if l > -1 then
                    local x = x0 + j
                    quad({{x, 0, z0}, {x, THICK, z0}, {x, THICK, z1}, {x, 0, z1}}, {-1, 0, 0},
                         {{uc, z0}, {uc, z0}, {uc, z1}, {uc, z1}})
                end
                if l <= 1 then
                    local x = x0 + j + 1 - EPS
                    quad({{x, 0, z0}, {x, THICK, z0}, {x, THICK, z1}, {x, 0, z1}}, {1, 0, 0},
                         {{uc, z0}, {uc, z0}, {uc, z1}, {uc, z1}})
                end
                if i1 > -1 then
                    local z = z0 + j
                    quad({{x0, 0, z}, {x0, THICK, z}, {x1, THICK, z}, {x1, 0, z}}, {0, 0, -1},
                         {{x0, vc}, {x0, vc}, {x1, vc}, {x1, vc}})
                end
                if i1 <= 1 then
                    local z = z0 + j + 1 - EPS
                    quad({{x0, 0, z}, {x0, THICK, z}, {x1, THICK, z}, {x1, 0, z}}, {0, 0, 1},
                         {{x0, vc}, {x0, vc}, {x1, vc}, {x1, vc}})
                end
            end
        end
    end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, index = idx}
    m.apply(obj)
    SetMaterial(obj, MAT)
end

function Clouds.init()
    obj = SpawnObject("Clouds")
    build()
end

function Clouds.update(dt, P)
    if not obj then return end
    local Sky = require "sky"
    local ex, ey, ez = P.eye()
    local t = Sky.cloudTicks + Sky.partial
    local d1 = (ex + t * 0.03) / CELL
    local d2 = ez / CELL + 0.33
    d1 = d1 - math.floor(d1 / 2048) * 2048
    d2 = d2 - math.floor(d2 / 2048) * 2048
    local c1, c2 = math.floor(d1), math.floor(d2)
    obj.Transform.Position = Vec3(ex - (d1 - c1) * CELL, HEIGHT + 0.33, ez - (d2 - c2) * CELL)
    obj.Transform.Scale = Vec3(CELL, 1, CELL)
    SetMaterialParam(MAT, "uOffset", Vec2((c1 % 256) / 256, (c2 % 256) / 256))
    -- Низ виден снизу и изнутри слоя, верх — сверху и изнутри (f4 оригинала).
    local f4 = HEIGHT - ey + 0.33
    SetMaterialParam(MAT, "uShowBottom", f4 > -THICK - 1 and 1 or 0)
    SetMaterialParam(MAT, "uShowTop", f4 <= THICK + 1 and 1 or 0)
end

return Clouds
