-- ---------------------------------------------------------------------------
-- avatar.lua — модель игрока (assets/models/player.gltf) и её движения.
--
-- В модели нет клипов анимации — только кости (голова, тело, руки, ноги).
-- Движения считаются здесь каждый кадр и ставятся поворотами костей:
-- ноги и руки качаются в противофазе с частотой шага, амплитуда растёт со
-- скоростью; присед наклоняет тело; голова смотрит туда же, куда камера;
-- удар/постройка — взмах правой руки.
--
-- СКИНЫ. Скин — картинка 64×64 по развёртке модели. Игра ищет картинки в
-- assets/skins: default.png (скин из модели), custom.png и skin1..skin9.png,
-- а ещё путь из параметра запуска --skin=<путь>. K — следующий скин; выбор
-- запоминается в сохранении. Свой скин — положить PNG в assets/skins.
-- ---------------------------------------------------------------------------
local Avatar = {}

local MODEL = "assets/models/player.gltf"
local obj
local joints = {}
local skins = {}
Avatar.skinIndex = 1
local phase, amount = 0, 0
local headYaw = 0

local function loadSkins()
    skins = {}
    local candidates = {"assets/skins/default.png", "assets/skins/custom.png"}
    for i = 1, 9 do candidates[#candidates + 1] = "assets/skins/skin" .. i .. ".png" end
    local arg = LaunchArg("skin")
    if arg and arg ~= "" then table.insert(candidates, 1, arg) end
    for _, path in ipairs(candidates) do
        local ok, tex = pcall(texture.load, path, "skin:" .. path)
        if ok and tex.width >= 64 and (tex.height == 64 or tex.height == 32) then
            tex.nearest = true
            tex.apply()
            skins[#skins + 1] = {path = path, name = "skin:" .. path}
        end
    end
end

local function applySkin()
    local s = skins[Avatar.skinIndex]
    if not s or not obj then return end
    local mat = "sagecraft_skin_" .. Avatar.skinIndex
    -- Без освещения движка: яркость модели — свет клетки, где стоит игрок
    -- (тот же, что у блоков вокруг), её задаёт Avatar.update цветом материала.
    material(mat, {texture = s.name, nearest = true, cutoff = 0.05, double_sided = true, unlit = true})
    Avatar.material = mat
    local parts = SubmeshCount(obj)
    if parts and parts > 0 then
        for i = 0, parts - 1 do SetSubmeshMaterial(obj, i, mat) end
    end
    SetMaterial(obj, mat)
    Avatar.skinPath = s.path
end

function Avatar.init(playerObj)
    obj = SpawnObject("Player Model")
    obj:SetParent(playerObj)
    obj.Transform.Position = Vec3(0, 0, 0)
    -- Модель смотрит на +Z, игрок — на −Z (так смотрит камера).
    obj.Transform.Rotation = Vec3(0, 180, 0)
    AddAnimatedModel(obj, MODEL)
    for _, name in ipairs({"Head", "Body", "Right Arm", "Left Arm", "Right Leg", "Left Leg", "Waist"}) do
        joints[name] = JointIndex(obj, name)
    end
    loadSkins()
    local Save = require "save"
    local want = Save.data and Save.data.skin
    for i, s in ipairs(skins) do if s.path == want then Avatar.skinIndex = i end end
    applySkin()
end

function Avatar.nextSkin()
    if #skins == 0 then return end
    Avatar.skinIndex = Avatar.skinIndex % #skins + 1
    applySkin()
    log("Скин: " .. skins[Avatar.skinIndex].path)
end

local function rot(name, x, y, z)
    local j = joints[name]
    if j and j >= 0 then SetJointRotation(obj, j, x, y or 0, z or 0) end
end

-- visible — вид от третьего лица; swing — 0..1 фаза взмаха правой руки.
function Avatar.update(dt, P, visible, swing)
    if not obj then return end
    obj.Transform.Scale = visible and Vec3(1, 1, 1) or Vec3(0.0001, 0.0001, 0.0001)
    if visible and Avatar.material then
        local W = require "world"
        local Sky = require "sky"
        local bx, by, bz = math.floor(P.pos.x), math.floor(P.pos.y + 1), math.floor(P.pos.z)
        -- Та же кривая, что в шейдере участка: уровни 0..15 -> яркость.
        local function curve(l) return (l / 15) ^ 2.65 end
        local sky = curve(W.sky(bx, by, bz)) * Sky.daylight
        local blk = curve(W.blockLight(bx, by, bz))
        local k = math.max(0.05, sky, blk)
        local key = math.floor(k * 50)
        if key ~= Avatar._lightKey then
            Avatar._lightKey = key
            material.Set(Avatar.material, "albedo", Vec3(k, k, k * (blk > sky and 0.85 or 1)))
        end
    end
    local speed = math.sqrt(P.vel.x * P.vel.x + P.vel.z * P.vel.z)
    if not P.onGround and not P.inWater then speed = speed * 0.3 end
    local target = math.min(1, speed / 4.3)
    amount = amount + (target - amount) * math.min(1, dt * 10)
    phase = phase + dt * speed * 2.1

    local legSwing = math.sin(phase) * 50 * amount
    local armSwing = math.sin(phase) * 40 * amount
    local sneak = P.sneaking and 1 or 0
    local idle = math.sin(Time.total() * 1.3) * 3

    rot("Right Leg", legSwing, 0, 0)
    rot("Left Leg", -legSwing, 0, 0)
    local swingAngle = 0
    if swing and swing > 0 then swingAngle = -math.sin((1 - swing) * math.pi) * 80 end
    rot("Right Arm", -armSwing + swingAngle - sneak * 10, 0, 4 + idle)
    rot("Left Arm", armSwing - sneak * 10, 0, -4 - idle)
    rot("Body", sneak * 28, 0, 0)

    -- Голова — за взглядом камеры; тело доворачивается, если голова ушла
    -- далеко (тело модели повёрнуто вместе с игроком на P.yaw).
    headYaw = 0
    rot("Head", -P.pitch, headYaw, 0)
    if P.flying then rot("Waist", 0, 0, 0) end
end

return Avatar
