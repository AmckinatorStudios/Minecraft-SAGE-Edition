-- ---------------------------------------------------------------------------
-- shadows.lua — круглые тени под существами (Render.renderShadow 1.7.10).
--
-- Не тень от солнца, а пятно shadow.png под ногами: на каждой верхней грани
-- полного блока в квадрате ±shadowSize вокруг существа и до shadowSize ниже
-- его ног — свой квадрат на 1/64 блока выше грани (без мерцания с ней).
-- Боковых граней тень не касается. Прозрачность квадрата —
--   (прозрачность − высота над гранью / 2) · 0.5 · яркость клетки над гранью,
-- где прозрачность = (1 − d² / 256) · shadowOpaque, d — расстояние до камеры
-- (квадрат расстояния, как getDistanceToCamera оригинала: тень гаснет к 16
-- блокам). Клетка темнее уровня 4 тени не получает. Только в Fancy-графике.
-- UV: (центр − край) / 2 / размер + 0.5 — пятно не тянется по граням, а
-- вырезается из одного круга радиуса shadowSize.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Light = require "lightmap"

local Sh = {}
Sh.fancy = true
local MAT = "assets/materials/shadow.sagemat"
local LIFT = 0.015625

-- Полный куб (renderAsNormalBlock): глухие блоки, листва, лёд — не стекло,
-- не кактус и не растения.
local function fullCube(id)
    if id == 0 then return false end
    if B.opaque[id] then return true end
    local d = B.byId[id]
    return d and d.draw == "cutout" and not d.inset and d.name ~= "glass"
end

-- Новая тень (объект под пятно).
function Sh.new(name)
    local o = SpawnObject(name or "Shadow")
    return {obj = o, shown = false}
end

local function hide(sh)
    if sh.shown then
        sh.obj.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
        sh.shown = false
    end
end
Sh.hide = hide

-- Поставить тень существа: (x, y, z) — ноги, size — shadowSize (у
-- детёнышей — вдвое меньше), opaque — shadowOpaque, cam — положение камеры.
function Sh.place(sh, x, y, z, size, opaque, cx, cy, cz)
    if not Sh.fancy or size <= 0 then return hide(sh) end
    local dx, dy, dz = x - cx, y - cy, z - cz
    local alpha = (1 - (dx * dx + dy * dy + dz * dz) / 256) * opaque
    if alpha <= 0 then return hide(sh) end
    local Sky = require "sky"
    local sub = Sky.skylightSubtracted(Sky.angle or 0, Sky.rain or 0, Sky.thunder or 0)
    local pos, uv, uv2, idx = {}, {}, {}, {}
    local n = 0
    for bx = math.floor(x - size), math.floor(x + size) do
        for by = math.floor(y - size), math.floor(y) do
            for bz = math.floor(z - size), math.floor(z + size) do
                local below = W.get(bx, by - 1, bz)
                if fullCube(below) then
                    local level = math.max((W.sky(bx, by, bz) or 15) - sub, W.blockLight(bx, by, bz) or 0)
                    if level > 3 then
                        local a = (alpha - (y - by) / 2) * 0.5 * Light.TABLE[math.max(0, level)]
                        if a >= 0 then
                            if a > 1 then a = 1 end
                            local x0, x1, z0, z1 = bx, bx + 1, bz, bz + 1
                            local top = by + LIFT
                            local u0, u1 = (x - x0) / 2 / size + 0.5, (x - x1) / 2 / size + 0.5
                            local v0, v1 = (z - z0) / 2 / size + 0.5, (z - z1) / 2 / size + 0.5
                            for _, c in ipairs({{x0, z0, u0, v0}, {x0, z1, u0, v1}, {x1, z1, u1, v1}, {x1, z0, u1, v0}}) do
                                pos[#pos + 1] = c[1]; pos[#pos + 1] = top; pos[#pos + 1] = c[2]
                                uv[#uv + 1] = c[3]; uv[#uv + 1] = c[4]
                                uv2[#uv2 + 1] = a; uv2[#uv2 + 1] = 0
                            end
                            idx[#idx + 1] = n + 1; idx[#idx + 1] = n + 2; idx[#idx + 1] = n + 3
                            idx[#idx + 1] = n + 1; idx[#idx + 1] = n + 3; idx[#idx + 1] = n + 4
                            n = n + 4
                        end
                    end
                end
            end
        end
    end
    if n == 0 then return hide(sh) end
    local m = mesh()
    m.arrays{position = pos, uv = uv, uv2 = uv2, index = idx}
    m.apply(sh.obj)
    SetMaterial(sh.obj, MAT)
    sh.obj.Transform.Position = Vec3(0, 0, 0)
    sh.obj.Transform.Scale = Vec3(1, 1, 1)
    sh.shown = true
end

-- Положение камеры для затухания тени по расстоянию.
local camObj
function Sh.camera()
    camObj = camObj or FindObject("Player Camera")
    if not camObj then return 0, 0, 0 end
    local p = camObj:WorldPosition()
    return p.x, p.y, p.z
end

function Sh.destroy(sh)
    if sh and sh.obj then DestroyObject(sh.obj) end
end

return Sh
