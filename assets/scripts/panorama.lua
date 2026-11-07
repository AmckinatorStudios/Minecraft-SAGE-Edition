-- ---------------------------------------------------------------------------
-- panorama.lua — вращающаяся панорама титульного экрана (GuiMainMenu 1.7.10).
--
-- Куб из шести картинок (assets/ui/panorama/panorama_0..5.png) вокруг камеры.
-- Повороты — как в drawPanorama: наклон sin(t/400)·25 + 20 градусов, рыскание
-- −t·0.1 (t — тики, 20 в секунду, с долей тика), грани 1–5 повёрнуты на
-- 90/180/−90 по Y и ±90 по X. Оригинал рисует куб в квадрат 256×256 с полем
-- зрения 120° и растягивает его на экран, вырезая середину: по высоте видно
-- 2·atan(tg 60° · 0.9375 · h/w) — это поле зрения камеры здесь. Размытие
-- (64 сдвинутых прохода и rotateAndBlurSkybox) — звено Blur камеры, светлый
-- верх и тёмный низ — две полосы-градиента интерфейса (menu.lua).
-- ---------------------------------------------------------------------------
local M = require "mat"

local Pano = {}
local faces = {}
local cam
local ticks = 0
local savedFov
Pano.active = false

-- Квад грани в пространстве Minecraft: z = 1, от (−1,−1) до (1,1); v
-- оригинала — сверху, у холста движка — снизу.
local function faceMesh()
    local m = mesh()
    m.arrays{position = {-1, -1, 1,  1, -1, 1,  1, 1, 1,  -1, 1, 1},
             normal = {0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1},
             uv = {0, 1,  1, 1,  1, 0,  0, 0},
             index = {1, 2, 3, 1, 3, 4}}
    return m
end

function Pano.init(cameraObj)
    cam = cameraObj
    for k = 0, 5 do
        local tex = "assets/ui/panorama/panorama_" .. k .. ".png"
        material("sagecraft_pano_" .. k, {texture = tex, unlit = true, double_sided = true})
        local o = SpawnObject("Panorama " .. k)
        o:SetParent(cameraObj)
        faceMesh().apply(o)
        SetMaterial(o, "sagecraft_pano_" .. k)
        faces[k] = o
    end
    Pano.show(false)
end

function Pano.show(on)
    Pano.active = on
    for _, o in pairs(faces) do
        if not on then o.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001) end
    end
    local c = cam and cam:GetCamera()
    if c then
        if on then
            savedFov = savedFov or c.Fov
        elseif savedFov then
            c.Fov = savedFov
            savedFov = nil
        end
    end
    -- Размытие — только у панорамы; в игре кадр резкий.
    if on then
        post.set("blur", {intensity = 1, radius = 10})
    elseif post.has("blur") then
        post.remove("blur")
    end
end

function Pano.update(dt)
    if not Pano.active then return end
    ticks = ticks + dt * 20
    local size = UIScreenSize()
    local w, h = math.max(1, size.x), math.max(1, size.y)
    local c = cam:GetCamera()
    if c then
        -- Видимая часть квадрата 120° (renderSkybox): по большей стороне — 120/256·256.
        local k = 120 / math.max(w, h) * 2 / 256
        c.Fov = math.deg(2 * math.atan(math.tan(math.rad(60)) * k * h))
    end
    local base = M.identity()
    M.rotate(base, 180, 1, 0, 0)
    M.rotate(base, math.sin(ticks / 400) * 25 + 20, 1, 0, 0)
    M.rotate(base, -ticks * 0.1, 0, 1, 0)
    for k = 0, 5 do
        local m = M.copy(base)
        if k == 1 then M.rotate(m, 90, 0, 1, 0)
        elseif k == 2 then M.rotate(m, 180, 0, 1, 0)
        elseif k == 3 then M.rotate(m, -90, 0, 1, 0)
        elseif k == 4 then M.rotate(m, 90, 1, 0, 0)
        elseif k == 5 then M.rotate(m, -90, 1, 0, 0) end
        M.applyTo(faces[k], m)
    end
end

return Pano
