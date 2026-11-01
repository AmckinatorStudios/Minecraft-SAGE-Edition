-- ---------------------------------------------------------------------------
-- hand.lua — правая рука и предмет в ней при виде от первого лица.
--
-- Рука — те же грани, что у правой руки модели игрока (внутренний и верхний
-- слой скина, UV из assets/models/player.gltf), отдельным мешем у камеры:
-- модель целиком при виде глазами спрятана, а руку видно всегда. Красится
-- материалом скина, поэтому смена скина меняет и руку.
--
-- Взмах при ударе и постройке — от Act.swing, покачивание при ходьбе — от
-- пройденного пути (как у камеры).
-- ---------------------------------------------------------------------------
local B = require "blocks"
local A = require "atlas"

local Hand = {}

local arm, item
local itemId = -1
local CHUNK_MAT = "assets/materials/chunk.sagemat"
local ICON_MAT = "sagecraft_icon_mat"

-- Грани руки: нормаль, четыре угла (порядок как в файле модели) и UV в
-- пикселях скина 64×64 (v — от верха картинки, как в glTF).
local FACES = {
    {{1,0,0},  {{.5,.75,.125},{.5,.75,-.125},{.5,0,.125},{.5,0,-.125}},     {{40,20},{44,20},{40,32},{44,32}}},
    {{-1,0,0}, {{.25,.75,-.125},{.25,.75,.125},{.25,0,-.125},{.25,0,.125}}, {{48,20},{52,20},{48,32},{52,32}}},
    {{0,1,0},  {{.25,.75,-.125},{.5,.75,-.125},{.25,.75,.125},{.5,.75,.125}}, {{48,20},{44,20},{48,16},{44,16}}},
    {{0,-1,0}, {{.25,0,.125},{.5,0,.125},{.25,0,-.125},{.5,0,-.125}},       {{52,16},{48,16},{52,20},{48,20}}},
    {{0,0,1},  {{.25,.75,.125},{.5,.75,.125},{.25,0,.125},{.5,0,.125}},     {{52,20},{56,20},{52,32},{56,32}}},
    {{0,0,-1}, {{.5,.75,-.125},{.25,.75,-.125},{.5,0,-.125},{.25,0,-.125}}, {{44,20},{48,20},{44,32},{48,32}}},
}

local function armMesh()
    local pos, nrm, uv, idx = {}, {}, {}, {}
    local nv = 0
    -- Внутренний слой и верхний (на 1/64 шире, UV на 16 пикселей ниже).
    for layer = 0, 1 do
        local grow = layer == 1 and 0.016 or 0
        for _, f in ipairs(FACES) do
            local n = f[1]
            for k = 1, 4 do
                local p = f[2][k]
                -- Плечо — в нуле: рука висит вниз от него.
                local x, y, z = p[1] - 0.375, p[2] - 0.75, p[3]
                x = x + (x > 0 and grow or -grow)
                y = y + (y > -0.375 and grow or -grow)
                z = z + (z > 0 and grow or -grow)
                pos[#pos + 1] = x; pos[#pos + 1] = y; pos[#pos + 1] = z
                nrm[#nrm + 1] = n[1]; nrm[#nrm + 1] = n[2]; nrm[#nrm + 1] = n[3]
                local t = f[3][k]
                -- Строки холста скина — снизу вверх: v = 1 − v(glTF).
                uv[#uv + 1] = t[1] / 64
                uv[#uv + 1] = 1 - (t[2] + layer * 16) / 64
            end
            for _, i in ipairs({1, 3, 2, 2, 3, 4}) do idx[#idx + 1] = nv + i end
            nv = nv + 4
        end
    end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, index = idx}
    return m
end

function Hand.init(cameraObj)
    arm = SpawnObject("First Person Arm")
    arm:SetParent(cameraObj)
    armMesh().apply(arm)
    item = SpawnObject("First Person Item")
    item:SetParent(cameraObj)
end

function Hand.setMaterial(mat)
    if arm then SetMaterial(arm, mat) end
end

local function rebuildItem(id)
    itemId = id
    if id == 0 then
        item.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
        return
    end
    item.Transform.Scale = Vec3(1, 1, 1)
    local d = B.byId[id]
    local Drops = require "drops"
    if d.isBlock and d.draw ~= "cross" and d.draw ~= "torch" then
        Drops.cubeMesh(id, 0.22).apply(item)
        SetMaterial(item, CHUNK_MAT)
    else
        Drops.itemMesh(id, 0.3).apply(item)
        SetMaterial(item, Drops.ITEM_MAT)
    end
end

-- visible — вид глазами; swing — 0..1; walk — пройденный путь; heldId — что в руке.
function Hand.update(dt, visible, swing, walk, heldId)
    if not arm then return end
    if not visible then
        arm.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
        item.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
        itemId = -1
        return
    end
    -- Взмах: рука идёт вперёд-вниз и возвращается; при ходьбе — лёгкая
    -- восьмёрка.
    local s = math.sin((1 - swing) * math.pi) * (swing > 0 and 1 or 0)
    local bx = math.sin(walk * 2.2) * 0.02
    local by = -math.abs(math.cos(walk * 2.2)) * 0.02
    local held = heldId or 0
    if held ~= itemId then rebuildItem(held) end
    if held == 0 then
        arm.Transform.Scale = Vec3(1, 1, 1)
        arm.Transform.Position = Vec3(0.62 + bx - s * 0.12, -0.40 + by + s * 0.08, -0.72 - s * 0.18)
        arm.Transform.Rotation = Vec3(78 + s * 30, 14 + s * 18, 12)
    else
        -- С предметом рука прячется ниже: виден в основном сам предмет.
        arm.Transform.Scale = Vec3(1, 1, 1)
        arm.Transform.Position = Vec3(0.62 + bx - s * 0.12, -0.70 + by + s * 0.08, -0.62 - s * 0.18)
        arm.Transform.Rotation = Vec3(70 + s * 30, 8 + s * 18, 10)
        local d = B.byId[held]
        if d.isBlock and d.draw ~= "cross" and d.draw ~= "torch" then
            item.Transform.Position = Vec3(0.36 + bx - s * 0.14, -0.30 + by + s * 0.06, -0.66 - s * 0.2)
            item.Transform.Rotation = Vec3(-s * 45, 45, 0)
        else
            item.Transform.Position = Vec3(0.34 + bx - s * 0.14, -0.26 + by + s * 0.06, -0.62 - s * 0.2)
            item.Transform.Rotation = Vec3(-s * 60, -70, 20)
        end
    end
end

return Hand
