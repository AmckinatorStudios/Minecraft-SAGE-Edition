-- ---------------------------------------------------------------------------
-- map.lua — карта (filled_map), как в Minecraft 1.7.10.
--
-- Пустая карта по ПКМ становится картой участка 128×128 блоков масштаба 0
-- (блок = пиксель) с центром round(x / 128)·128 (ItemEmptyMap). Номер карты —
-- «повреждение» стопки, как у оригинала; в сохранении — только центры, сами
-- пиксели снова считаются по миру (он восстанавливается из зерна и правок).
--
-- Цвет пикселя — цвет материала верхнего блока (MapColor), яркость — по
-- высоте соседа к северу: выше — светлее, ниже — темнее (×180/220/255).
-- Пока карту держат, она дорисовывается по 8 строк за кадр — так видно и
-- новые постройки, и подгруженные позже участки.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local M = require "mat"

local Map = {}
Map.maps = {}     -- [номер] = {x = центр, z = центр}

local TEX = "sagecraft_map_"
local BG_TEX = "assets/textures/map/map_background.png"

-- MapColor 1.7.10 по материалу блока.
local function rgb(h) return {((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255} end
local COLORS = {
    grass = rgb(0x7FB238), sand = rgb(0xF7E9A3), cloth = rgb(0xA7A7A7), stone = rgb(0x707070),
    water = rgb(0x4040FF), wood = rgb(0x685133), foliage = rgb(0x007C00), snow = rgb(0xFFFFFF),
    ice = rgb(0xA0A0FF), clay = rgb(0xA4A8B8), dirt = rgb(0xB76A2F), tnt = rgb(0xFF0000),
    iron = rgb(0xA7A7A7), plant = rgb(0x007C00),
}
local MATERIAL = {
    grass = "grass", dirt = "dirt", stone = "stone", cobblestone = "stone", sand = "sand", gravel = "stone",
    sandstone = "sand", water = "water", log = "wood", birch_log = "wood", planks = "wood", birch_planks = "wood",
    leaves = "foliage", birch_leaves = "foliage", tallgrass = "plant", rose = "plant", dandelion = "plant",
    reeds = "plant", cactus = "plant", snow = "snow", ice = "ice", clay = "clay", bedrock = "stone",
    crafting_table = "wood", bookshelf = "wood", pumpkin = "plant",
}
local function colorOf(id)
    local d = B.byId[id]
    local mat = d and MATERIAL[d.name]
    if not mat and d and d.name:find("wool") then mat = "cloth" end
    return COLORS[mat or "stone"]
end

-- Верхний не-воздух столба и его высота (nil — участок не загружен).
local function top(x, z)
    if not W.chunk(x >> 4, z >> 4) then return nil end
    for y = W.HEIGHT - 1, 1, -1 do
        local id = W.get(x, y, z)
        if id ~= 0 then return id, y end
    end
    return 0, 0
end

-- Новая карта у точки (x, z): номер для стопки.
function Map.create(x, z)
    local n = #Map.maps + 1
    Map.maps[n] = {x = math.floor(x / 128 + 0.5) * 128, z = math.floor(z / 128 + 0.5) * 128}
    return n
end

local canvases = {}
local function canvas(n)
    local c = canvases[n]
    if c then return c end
    local tex = texture(TEX .. n, 128, 128)
    tex.nearest = true
    tex.fill(function() return Vec4(0, 0, 0, 0) end)
    c = {tex = tex, row = 0, mat = "sagecraft_map_mat_" .. n}
    canvases[n] = c
    tex.apply()
    material(c.mat, {texture = TEX .. n, nearest = true, cutoff = 0.05, double_sided = true, unlit = true})
    return c
end

-- Дорисовать rows строк карты n (по кругу).
function Map.refresh(n, rows)
    local info = Map.maps[n]
    if not info then return end
    local c = canvas(n)
    local x0, z0 = info.x - 64, info.z - 64
    for _ = 1, rows do
        local pz = c.row
        local wz = z0 + pz
        local _, prevH = top(x0, wz - 1)
        for px = 0, 127 do
            local wx = x0 + px
            local id, h = top(wx, wz)
            local col
            if id then
                local base = colorOf(id)
                local _, north = top(wx, wz - 1)
                local k = 220
                if north then k = h > north and 255 or (h < north and 180 or 220) end
                if id == 11 then
                    -- Вода: темнее с глубиной (как у MapData — по числу клеток воды).
                    local depth = 0
                    while depth < 10 and W.get(wx, h - depth - 1, wz) == 11 do depth = depth + 1 end
                    k = depth > 6 and 180 or (depth > 2 and 220 or 255)
                end
                col = Vec4(base[1] * k / 255, base[2] * k / 255, base[3] * k / 255, 1)
            else
                col = Vec4(0, 0, 0, 0)
            end
            -- Строка 0 карты — север (верх картинки); холст считает снизу.
            c.tex.set(px, 127 - pz, col)
        end
        c.row = (c.row + 1) % 128
    end
    c.tex.apply()
end

-- Подложка и рисунок карты в руке: m — матрица ItemRenderer после
-- glScalef(1/64) (единица — пиксель карты, подложка от −7 до 135).
local inHand = {}
function Map.placeInHand(obj, m, n, layer)
    if not inHand.bg then
        material("sagecraft_map_bg", {texture = BG_TEX, nearest = true, cutoff = 0.05, double_sided = true, unlit = true})
        inHand.bg = SpawnObject("Map Background")
        inHand.bg:SetParent(obj)
        local b = mesh()
        -- Вершины и UV — как у ItemRenderer (v в Minecraft сверху, у холста — снизу).
        b.arrays{position = {-7, 135, 0,  135, 135, 0,  135, -7, 0,  -7, -7, 0},
                 normal = {0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1},
                 uv = {0, 0,  1, 0,  1, 1,  0, 1}, index = {1, 2, 3, 1, 3, 4}}
        b.apply(inHand.bg)
        SetMaterial(inHand.bg, "sagecraft_map_bg")
        inHand.fg = SpawnObject("Map Picture")
        inHand.fg:SetParent(obj)
        local f = mesh()
        f.arrays{position = {0, 128, -0.01,  128, 128, -0.01,  128, 0, -0.01,  0, 0, -0.01},
                 normal = {0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1},
                 uv = {0, 0,  1, 0,  1, 1,  0, 1}, index = {1, 2, 3, 1, 3, 4}}
        f.apply(inHand.fg)
        inHand.bg:GetRenderer().Layer = layer or ""
        inHand.fg:GetRenderer().Layer = layer or ""
    end
    M.applyTo(obj, m)
    n = n or Map.heldNumber
    if n and Map.maps[n] then
        local c = canvas(n)
        SetMaterial(inHand.fg, c.mat)
        inHand.fg.Transform.Scale = Vec3(1, 1, 1)
        Map.refresh(n, 8)
    else
        inHand.fg.Transform.Scale = Vec3(0.0001, 0.0001, 0.0001)
    end
end

function Map.serialize() return Map.maps end
function Map.load(data)
    Map.maps = {}
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do Map.maps[tonumber(k)] = {x = v.x, z = v.z} end
end

return Map
