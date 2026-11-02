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
    if LaunchFlag("fileskin") then return end   -- проверка: материал из самого файла модели
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
    require("hand").setMaterial(mat)
    -- Превью в рюкзаке — свой материал: ровный свет, а не свет клетки.
    material("sagecraft_skin_preview", {texture = s.name, nearest = true, cutoff = 0.05, double_sided = true, unlit = true})
    if Avatar.previewObj then SetMaterial(Avatar.previewObj, "sagecraft_skin_preview") end
    Avatar.skinPath = s.path
end

-- Персонаж для рюкзака: копия модели вдали от мира и съёмка её в текстуру
-- (AddRenderTexture). Снимается каждый кадр, только пока рюкзак открыт.
local PREVIEW_AT = Vec3(0, -400, 0)
Avatar.previewTexture = "sagecraft_preview"
local previewCam
local previewJoints = {}

local function initPreview()
    local o = SpawnObject("Preview Model")
    o.Transform.Position = PREVIEW_AT
    AddAnimatedModel(o, MODEL)
    for _, name in ipairs({"Head", "Right Arm", "Left Arm"}) do previewJoints[name] = JointIndex(o, name) end
    Avatar.previewObj = o
    previewCam = SpawnObject("Preview Camera")
    -- Модель смотрит на −Z: камера стоит перед ней.
    previewCam.Transform.Position = Vec3(PREVIEW_AT.x, PREVIEW_AT.y + 1.05, PREVIEW_AT.z - 3.1)
    AddRenderTexture(previewCam, {name = Avatar.previewTexture, width = 256, height = 384, fov = 38,
                                  look = Vec3(PREVIEW_AT.x, PREVIEW_AT.y + 0.95, PREVIEW_AT.z),
                                  studio = true, ambient = 0.9, continuous = false, clear = Vec4(0, 0, 0, 0)})
end

function Avatar.setPreview(on)
    Avatar.previewOn = on
    if previewCam then AddRenderTexture(previewCam, {continuous = on}) end
end

-- Превью смотрит на курсор: голова и тело поворачиваются за мышью.
function Avatar.updatePreview()
    if not Avatar.previewOn or not Avatar.previewObj then return end
    local c, size = UICursor(), UIScreenSize()
    local dx = (c.x - size.x / 2) / size.x
    local dy = (c.y - size.y / 2) / size.y
    local o = Avatar.previewObj
    o.Transform.Rotation = Vec3(0, dx * 40, 0)
    local j = previewJoints["Head"]
    if j and j >= 0 then SetJointRotation(o, j, dy * 40, dx * 50, 0) end
    local t = Time.total()
    local ra, la = previewJoints["Right Arm"], previewJoints["Left Arm"]
    if ra and ra >= 0 then SetJointRotation(o, ra, math.sin(t * 1.3) * 3, 0, 4) end
    if la and la >= 0 then SetJointRotation(o, la, -math.sin(t * 1.3) * 3, 0, -4) end
end

function Avatar.init(playerObj)
    obj = SpawnObject("Player Model")
    obj:SetParent(playerObj)
    obj.Transform.Position = Vec3(0, 0, 0)
    -- Лицо модели — на −Z (грань с лицом в развёртке), туда же смотрит
    -- игрок и камера движка: поворачивать не нужно.
    obj.Transform.Rotation = Vec3(0, 0, 0)
    AddAnimatedModel(obj, MODEL)
    for _, name in ipairs({"Head", "Body", "Right Arm", "Left Arm", "Right Leg", "Left Leg", "Waist"}) do
        joints[name] = JointIndex(obj, name)
    end
    initPreview()
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
    log("Skin: " .. skins[Avatar.skinIndex].path)
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
