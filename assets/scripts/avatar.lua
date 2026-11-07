-- ---------------------------------------------------------------------------
-- avatar.lua — модель игрока (assets/models/player.gltf) и её движения.
--
-- В модели нет клипов анимации — только кости (голова, тело, руки, ноги).
-- Поза — формулы ModelBiped 1.7.10 (ходьба, покой, присед, взмах, предмет,
-- лук, защита мечом) по числам из anim.lua; предмет в руке — как
-- RenderPlayer.renderEquippedItems.
--
-- СКИНЫ. Скин — картинка 64×64 по развёртке модели (или старая 64×32 —
-- она переводится в 64×64, как ImageBufferDownload Minecraft 1.8: левые рука
-- и нога — зеркала правых). Встроенный — assets/skins/default.png. Свои
-- скины игрок кладёт в пользовательскую папку игры «skins» (движок:
-- user_folder, рядом с собранной игрой; в Play-режиме — в папке данных
-- игры): новые файлы подхватываются на лету. K — следующий скин, выбор —
-- в настройках (Skin: …) и запоминается для всех миров.
-- ---------------------------------------------------------------------------
local Avatar = {}

local MODEL = "assets/models/player.gltf"
local obj
local joints = {}
local skins = {}
Avatar.skinIndex = 1
local phase, amount = 0, 0
local headYaw = 0

-- 64×32 -> 64×64 (ImageBufferDownload.parseUserSkin 1.8): прямоугольники
-- {dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2}; dx1 > dx2 — зеркально по X.
local LEGACY = {
    {24, 48, 20, 52, 4, 16, 8, 20}, {28, 48, 24, 52, 8, 16, 12, 20}, {20, 52, 16, 64, 8, 20, 12, 32},
    {24, 52, 20, 64, 4, 20, 8, 32}, {28, 52, 24, 64, 0, 20, 4, 32}, {32, 52, 28, 64, 12, 20, 16, 32},
    {40, 48, 36, 52, 44, 16, 48, 20}, {44, 48, 40, 52, 48, 16, 52, 20}, {36, 52, 32, 64, 48, 20, 52, 32},
    {40, 52, 36, 64, 44, 20, 48, 32}, {44, 52, 40, 64, 40, 20, 44, 32}, {48, 52, 44, 64, 52, 20, 56, 32},
}
local function upgradeLegacy(src, name)
    local out = texture(name, 64, 64)
    -- Строки холста — снизу вверх: строка картинки r — y = высота − 1 − r.
    local function getP(x, r) return src.get(x, 31 - r) end
    local function setP(x, r, c) out.set(x, 63 - r, c) end
    for r = 0, 63 do
        for x = 0, 63 do setP(x, r, r < 32 and getP(x, r) or Vec4(0, 0, 0, 0)) end
    end
    for _, q in ipairs(LEGACY) do
        local dx1, dy1, dx2, dy2, sx1, sy1 = q[1], q[2], q[3], q[4], q[5], q[6]
        local w, h = math.abs(dx2 - dx1), dy2 - dy1
        for yy = 0, h - 1 do
            for xx = 0, w - 1 do
                local dx = dx1 < dx2 and dx1 + xx or dx1 - 1 - xx
                setP(dx, dy1 + yy, getP(sx1 + xx, sy1 + yy))
            end
        end
    end
    return out
end

-- Добавить скин из файла path (key — как его помнить; title — подпись).
local function addSkin(path, key, title, stamp)
    local name = "skin:" .. key .. (stamp and (":" .. stamp) or "")
    local ok, tex = pcall(texture.load, path, name)
    if not ok or not tex or tex.width ~= 64 or (tex.height ~= 64 and tex.height ~= 32) then
        if ok and tex then log("Skin skipped (needs 64x64 or 64x32): " .. path) end
        return
    end
    if tex.height == 32 then
        name = name .. ":64"
        tex = upgradeLegacy(tex, name)
    end
    tex.nearest = true
    tex.apply()
    skins[#skins + 1] = {path = path, key = key, name = name, title = title}
end

local function hasUserFolder()
    return user_folder ~= nil and pcall(user_folder.path, "skins")
end

local function loadSkins()
    skins = {}
    local arg = LaunchArg("skin")
    if arg and arg ~= "" then addSkin(arg, arg, arg:match("([^/\\]+)$") or arg) end
    addSkin("assets/skins/default.png", "assets/skins/default.png", "Default")
    if hasUserFolder() then
        for _, f in ipairs(user_folder.list("skins")) do
            addSkin(f.path, "user:" .. f.relative, f.name:gsub("%.[^.]+$", ""), math.floor(f.modified))
        end
        user_folder.changed("skins")   -- отпечаток «как сейчас»: дальше — только новые правки
    end
    log("Skins: " .. #skins .. (hasUserFolder() and (" (own skins folder: " .. user_folder.path("skins") .. ")") or ""))
end

-- Выбрать скин по ключу (не нашёлся — первый).
local function selectKey(key)
    Avatar.skinIndex = 1
    for i, s in ipairs(skins) do if s.key == key then Avatar.skinIndex = i end end
end

Avatar.skins = function() return skins end

-- Список скинов без модели (настройки на титульном экране).
function Avatar.prepareSkins()
    if #skins == 0 then
        loadSkins()
        selectKey(require("menu").options.skin)
    end
end
function Avatar.skinTitle() local s = skins[Avatar.skinIndex]; return s and s.title or "-" end

-- Открыть папку своих скинов в проводнике.
function Avatar.openSkinsFolder()
    if hasUserFolder() then return user_folder.open("skins") end
    return false
end

-- Папка поменялась (положили, убрали, перезаписали файл) — перечитать,
-- оставив выбранный скин, если он ещё есть.
local checkTimer = 0
function Avatar.watchSkins(dt)
    checkTimer = checkTimer + dt
    if checkTimer < 1 or not hasUserFolder() then return end
    checkTimer = 0
    if not user_folder.changed("skins") then return end
    local key = skins[Avatar.skinIndex] and skins[Avatar.skinIndex].key
    loadSkins()
    selectKey(key)
    if Avatar._applied then Avatar.applySkin() end
    log("Skins reloaded: " .. #skins)
end

function Avatar.applySkin()
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
    Avatar.skinPath = s.key
    Avatar._lr = nil            -- новый материал — свет заново
    Avatar._applied = true
end
local applySkin = Avatar.applySkin

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
    -- Номера костей — когда модель загрузится (см. resolveJoints).
    for _, name in ipairs({"Head", "Right Arm", "Left Arm"}) do
        if (previewJoints[name] or -1) < 0 then previewJoints[name] = JointIndex(o, name) end
    end
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
    initPreview()
    loadSkins()
    -- Выбор — общий для всех миров (настройки), у старых сохранений — свой.
    local Save = require "save"
    local arg = LaunchArg("skin")
    local want = (arg ~= nil and arg ~= "") and arg or require("menu").options.skin or (Save.data and Save.data.skin)
    selectKey(want)
    applySkin()
end

function Avatar.nextSkin()
    if #skins == 0 then loadSkins() end
    if #skins == 0 then return end
    Avatar.skinIndex = Avatar.skinIndex % #skins + 1
    require("menu").options.skin = skins[Avatar.skinIndex].key
    applySkin()
    log("Skin: " .. skins[Avatar.skinIndex].key)
end

-- --- Поза ModelBiped 1.7.10 -------------------------------------------------
--
-- Углы считаются в модели Minecraft (Y вниз, лицо к −Z, правая рука на
-- x = −5 пикселей, радианы) — формулы ModelBiped.setRotationAngles слово в
-- слово. Модель игры — Y вверх, правая рука на +X: переход — поворот на 180°
-- вокруг Z (D = diag(−1, −1, 1)). Поворот кости в модели игры = D·R·D⁻¹, то
-- есть углы X и Y меняют знак; сдвиг точки вращения — (−dx, −dy, dz)/16.
-- Порядок поворотов ModelRenderer — Z, затем Y, затем X; движок ставит свои
-- углы (Ry·Rx·Rz), поэтому поворот переводится через матрицу (mat.lua).
local M = require "mat"
local Anim = require "anim"
local B = require "blocks"
local PI = math.pi
local sin, cos, sqrt = math.sin, math.cos, math.sqrt

-- Номер кости. Модель грузится не сразу (асинхронно): пока её нет, номер
-- −1, и его надо спросить снова, а не запомнить навсегда.
local JOINTS = {"Head", "Body", "Right Arm", "Left Arm", "Right Leg", "Left Leg", "Waist"}
local function resolveJoints()
    if joints.ready then return true end
    local ok = true
    for _, name in ipairs(JOINTS) do
        joints[name] = JointIndex(obj, name)
        if joints[name] < 0 then ok = false end
    end
    joints.ready = ok
    return ok
end

local function pose(name, x, y, z)
    local j = joints[name]
    if not j or j < 0 then return end
    local ex, ey, ez = M.eulerOf(M.modelRotation(-x, -y, z))
    SetJointRotation(obj, j, ex, ey, ez)
end

-- Точка вращения кости: сдвиг от её места в модели, в пикселях Minecraft.
local function shift(name, dx, dy, dz)
    local j = joints[name]
    if j and j >= 0 then SetJointOffset(obj, j, -dx / 16, -dy / 16, dz / 16) end
end

-- Как держит предмет: 0 — ничего, 1 — предмет, 3 — защита (heldItemRight).
-- aim — лук натянут (aimedBow).
local function bipedAngles(limb, amount, age, headYaw, headPitch, sw, sneak, held, aim)
    local a = {}
    a.headY, a.headX = math.rad(headYaw), math.rad(headPitch)
    a.rArmX = cos(limb * 0.6662 + PI) * 2 * amount * 0.5
    a.lArmX = cos(limb * 0.6662) * 2 * amount * 0.5
    a.rArmZ, a.lArmZ = 0, 0
    a.rLegX = cos(limb * 0.6662) * 1.4 * amount
    a.lLegX = cos(limb * 0.6662 + PI) * 1.4 * amount
    if held ~= 0 then a.rArmX = a.rArmX * 0.5 - PI / 10 * held end
    a.rArmY, a.lArmY = 0, 0
    -- Взмах (onGround — доля взмаха 0..1).
    a.bodyY = sin(sqrt(sw) * PI * 2) * 0.2
    a.rArmPX, a.rArmPZ = -cos(a.bodyY) * 5, sin(a.bodyY) * 5
    a.lArmPX, a.lArmPZ = cos(a.bodyY) * 5, -sin(a.bodyY) * 5
    a.rArmY = a.rArmY + a.bodyY
    a.lArmY = a.lArmY + a.bodyY
    a.lArmX = a.lArmX + a.bodyY
    local f6 = 1 - sw
    f6 = f6 * f6; f6 = f6 * f6; f6 = 1 - f6
    local f7 = sin(f6 * PI)
    local f8 = sin(sw * PI) * -(a.headX - 0.7) * 0.75
    a.rArmX = a.rArmX - (f7 * 1.2 + f8)
    a.rArmY = a.rArmY + a.bodyY * 2
    a.rArmZ = sin(sw * PI) * -0.4
    -- Присед: тело на 0.5 рад вперёд, руки +0.4, ноги назад и вверх, голова
    -- ниже на пиксель (sneak — доля перехода 0..1).
    a.bodyX = 0.5 * sneak
    a.rArmX = a.rArmX + 0.4 * sneak
    a.lArmX = a.lArmX + 0.4 * sneak
    a.legPZ = 0.1 + 3.9 * sneak
    a.legPY = 12 - 3 * sneak
    a.headPY = 1 * sneak
    -- Покачивание рук на месте.
    a.rArmZ = a.rArmZ + cos(age * 0.09) * 0.05 + 0.05
    a.lArmZ = a.lArmZ - cos(age * 0.09) * 0.05 - 0.05
    a.rArmX = a.rArmX + sin(age * 0.067) * 0.05
    a.lArmX = a.lArmX - sin(age * 0.067) * 0.05
    if aim then
        a.rArmZ, a.lArmZ = 0, 0
        a.rArmY = -0.1 + a.headY
        a.lArmY = 0.1 + a.headY + 0.4
        a.rArmX = -PI / 2 + a.headX
        a.lArmX = -PI / 2 + a.headX
        a.rArmZ = a.rArmZ + cos(age * 0.09) * 0.05 + 0.05
        a.lArmZ = a.lArmZ - cos(age * 0.09) * 0.05 - 0.05
        a.rArmX = a.rArmX + sin(age * 0.067) * 0.05
        a.lArmX = a.lArmX - sin(age * 0.067) * 0.05
    end
    return a
end
Avatar.bipedAngles = bipedAngles

-- Предмет в правой руке (RenderPlayer.renderEquippedItems): матрица в модели
-- Minecraft, начиная с точки вращения руки.
local function heldItemMatrix(a, id, action)
    local Hand = require "hand"
    local m = M.identity()
    -- bipedRightArm.postRender(0.0625)
    M.translate(m, a.rArmPX / 16, 2 / 16, a.rArmPZ / 16)
    M.rotate(m, math.deg(a.rArmZ), 0, 0, 1)
    M.rotate(m, math.deg(a.rArmY), 0, 1, 0)
    M.rotate(m, math.deg(a.rArmX), 1, 0, 0)
    M.translate(m, -0.0625, 0.4375, 0.0625)
    local d = B.byId[id]
    if Hand.isCube(id) then
        local f2 = 0.5 * 0.75
        M.translate(m, 0, 0.1875, -0.3125)
        M.rotate(m, 20, 1, 0, 0)
        M.rotate(m, 45, 0, 1, 0)
        M.scale(m, -f2, -f2, f2)
    elseif d.bow then
        local f2 = 0.625
        M.translate(m, 0, 0.125, 0.3125)
        M.rotate(m, -20, 0, 1, 0)
        M.scale(m, f2, -f2, f2)
        M.rotate(m, -100, 1, 0, 0)
        M.rotate(m, 45, 0, 1, 0)
    elseif d.full3d then
        local f2 = 0.625
        if action == "block" then
            M.translate(m, 0.05, 0, -0.1)
            M.rotate(m, -50, 0, 1, 0)
            M.rotate(m, -10, 1, 0, 0)
            M.rotate(m, -60, 0, 0, 1)
        end
        M.translate(m, 0, 0.1875, 0)
        M.scale(m, f2, -f2, f2)
        M.rotate(m, -100, 1, 0, 0)
        M.rotate(m, 45, 0, 1, 0)
    else
        local f2 = 0.375
        M.translate(m, 0.25, 0.1875, -0.1875)
        M.scale(m, f2)
        M.rotate(m, 60, 0, 0, 1)
        M.rotate(m, -90, 1, 0, 0)
        M.rotate(m, 20, 0, 0, 1)
    end
    Hand.itemTransform(m, id)
    -- Из модели Minecraft в модель игры: начало — на высоте 1.5 (24 пикселя),
    -- оси X и Y наоборот.
    local base = M.identity()
    M.translate(base, 0, 1.5, 0)
    M.scale(base, -1, -1, 1)
    return M.mul(base, m)
end

local heldObj, heldKey

-- Свет модели — цвет световой карты (lightmap.lua) при уровнях клетки, где
-- она стоит (Entity.getBrightnessForRender: ноги + рост 1.8 × 0.66). Каждый
-- кадр и без ступенек округления: карта сама плавно меняется со временем
-- суток, погодой и мерцанием факелов. Тот же материал у рук от первого лица.
function Avatar.light(P)
    if not Avatar.material then return end
    local Light = require "lightmap"
    local s, b = Light.levels(P.pos.x, P.pos.y + 1.8 * 0.66, P.pos.z)
    local r, g, bl = Light.at(s, b)
    if r ~= Avatar._lr or g ~= Avatar._lg or bl ~= Avatar._lb then
        Avatar._lr, Avatar._lg, Avatar._lb = r, g, bl
        material.Set(Avatar.material, "albedo", Vec3(r, g, bl))
    end
    if heldObj then Light.applyLevels(heldObj, s, b) end
end

-- visible — вид от третьего лица; heldId — что в руке.
function Avatar.update(dt, P, visible, heldId)
    if not obj then return end
    Avatar.watchSkins(dt)
    Avatar.light(P)   -- и без вида от третьего лица: этот материал у рук от первого лица
    obj.Transform.Scale = visible and Vec3(1, 1, 1) or Vec3(0.0001, 0.0001, 0.0001)
    if not heldObj then
        heldObj = SpawnObject("Held Item")
        heldObj:SetParent(obj)
    end
    -- Тень игрока (RenderPlayer: shadowSize 0.5) — только когда модель видна.
    local Sh = require "shadows"
    Avatar.shadow = Avatar.shadow or Sh.new("Player Shadow")
    if not visible then
        heldObj.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
        Sh.hide(Avatar.shadow)
        return
    end
    Sh.place(Avatar.shadow, P.pos.x, P.pos.y, P.pos.z, 0.5, 1, Sh.camera())

    -- Тело повёрнуто по renderYawOffset; голова — на разность со взглядом.
    -- Рыскание Minecraft идёт в обратную сторону, наклон вниз — плюс.
    local body = Anim.bodyYaw()
    obj.Transform.Rotation = Vec3(0, body - Anim.viewYaw(), 0)
    local limb, amount = Anim.limbs()
    local held = heldId or 0
    local u = Anim.use
    local action = u and u.id == held and u.action or nil
    local a = bipedAngles(limb, amount, Anim.age(), -(Anim.viewYaw() - body), -P.pitch,
                          Anim.swingProgress(), Anim.sneak,
                          held == 0 and 0 or (action == "block" and 3 or 1), action == "bow")

    resolveJoints()
    pose("Head", a.headX, a.headY, 0)
    shift("Head", 0, a.headPY, 0)
    pose("Body", a.bodyX, a.bodyY, 0)
    pose("Right Arm", a.rArmX, a.rArmY, a.rArmZ)
    pose("Left Arm", a.lArmX, a.lArmY, a.lArmZ)
    shift("Right Arm", a.rArmPX + 5, 0, a.rArmPZ)
    shift("Left Arm", a.lArmPX - 5, 0, a.lArmPZ)
    pose("Right Leg", a.rLegX, 0, 0)
    pose("Left Leg", a.lLegX, 0, 0)
    shift("Right Leg", 0, a.legPY - 12, a.legPZ)
    shift("Left Leg", 0, a.legPY - 12, a.legPZ)
    -- Присед поднимает ноги на 3 пикселя модели (rotationPointY 12 -> 9), и
    -- без сдвига всей модели вниз ступни висели над землёй — «игрок в
    -- воздухе». Модель опускается ровно на подъём ног: ступни на блоке.
    obj.Transform.Position = Vec3(0, -(12 - a.legPY) / 16, 0)

    if held == 0 then
        heldObj.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
        heldKey = nil
    else
        local Hand = require "hand"
        local want = held
        local d = B.byId[held]
        if d and d.bow and action == "bow" then
            local j = Anim.useTicks()
            want = j >= 18 and B.byName.bow_pulling_2.id or (j > 13 and B.byName.bow_pulling_1.id
                or (j > 0 and B.byName.bow_pulling_0.id or held))
        end
        if heldKey ~= want then heldKey = want; Hand.setItemMesh(heldObj, want) end
        M.applyTo(heldObj, heldItemMatrix(a, held, action))
    end
end

return Avatar
