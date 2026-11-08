-- ---------------------------------------------------------------------------
-- atlas.lua — атлас граней блоков и лист иконок, собранные при старте.
--
-- Картинки блоков лежат по одной в assets/textures/blocks (как их отдаёт
-- набор текстур). Видеокарте удобнее одна текстура: весь мир тогда рисуется
-- одним материалом, а грань выбирает свою плитку по UV. Атлас собирается из
-- картинок кодом (texture.load + get/set), поэтому замена любой картинки в
-- папке меняет игру без пересборки атласа руками.
--
-- Иконки блоков в инвентаре — объёмные: три видимые грани куба в изометрии,
-- с тем же затемнением сторон, что в мире. Они тоже рисуются здесь, пиксель
-- за пикселем, из тех же картинок: отдельного рендера в текстуру не нужно.
-- ---------------------------------------------------------------------------
local B = require "blocks"

local A = {}

local TILE = 32            -- пикселей на плитку (набор 32×32)
local GRID = 16            -- плиток по стороне атласа
local SIZE = TILE * GRID
local EPS = 0.25 / SIZE    -- отступ внутрь плитки: ближайшая выборка не цепляет соседку

A.TEXTURE = "sagecraft_atlas"
A.ICONS = "sagecraft_icons"
-- Пикселей на иконку: 96 делится нацело на оба размера показа — 48 в окнах
-- (16 × 3) и 32 на панели (16 × 2). Иконка 64 в 48 — дробный масштаб, и
-- ближайший пиксель то выбрасывал, то дублировал строки: «битые» пиксели.
A.ICON = 96
A.ICON_COLS = 16
A.blockTiles = {}          -- [id] = {top=, bottom=, side=, front=} номера плиток
A.icon = {}                -- [id] = номер иконки (с нуля)
A.destroyTile = {}         -- стадии трещин 0..9 -> плитка

-- Цвет растительности: серые трава и листва набора окрашиваются им.
local FOLIAGE = {0.50, 0.76, 0.33}
local BIRCH = {0.56, 0.70, 0.40}
-- Ель: постоянный цвет 0x619961 (ColorizerFoliage.getFoliageColorPine).
local PINE = {0x61 / 255, 0x99 / 255, 0x61 / 255}

local tiles = {}           -- имя картинки -> номер плитки
local sources = {}         -- имя картинки -> холст (для иконок)
local nextTile = 0

function A.tileOrigin(t)
    local tx, ty = t % GRID, t // GRID
    return tx / GRID + EPS, ty / GRID + EPS, 1 / GRID - 2 * EPS
end

-- Плитка с картинкой name (с "!" — окрашенной). Повтор имени — та же плитка.
local function tileFor(atlas, name, tint)
    local key = name .. (tint and "!" or "")
    if tiles[key] then return tiles[key] end
    local file = "assets/textures/blocks/" .. name .. ".png"
    local src = sources[name] or texture.load(file, "src_" .. name)
    sources[name] = src
    local t = nextTile
    nextTile = nextTile + 1
    local ox, oy = (t % GRID) * TILE, (t // GRID) * TILE
    -- Полоса кадров (вода — 32×1024): берём верхний кадр. Строки холста идут
    -- снизу вверх, поэтому верхний кадр — последние TILE строк.
    local sy0 = src.height - TILE
    local scale = src.width // TILE
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local c = src.get(x * scale, sy0 + y * scale)
            if tint then c = Vec4(c.x * tint[1], c.y * tint[2], c.z * tint[3], c.w) end
            atlas.set(ox + x, oy + y, c)
        end
    end
    tiles[key] = t
    return t
end

local function tintOf(d, name)
    if not name:find("!$") then return name, nil end
    name = name:sub(1, -2)
    return name, d.name:find("birch") and BIRCH or (d.name:find("spruce") and PINE or FOLIAGE)
end

-- Выборка картинки грани для иконки: u, v — доли 0..1 (v снизу вверх).
local function sample(name, tint, u, v)
    local src = sources[name]
    local px = math.min(TILE - 1, math.floor(u * TILE))
    local py = math.min(TILE - 1, math.floor(v * TILE))
    local scale = src.width // TILE
    local c = src.get(px * scale, src.height - TILE + py * scale)
    if tint then return c.x * tint[1], c.y * tint[2], c.z * tint[3], c.w end
    return c.x, c.y, c.z, c.w
end

-- Изометрическая иконка куба: верх, правый бок (+X) и левый (+Z), с тем же
-- затемнением сторон, что и в мире (шейдер участка).
local function cubeIcon(icons, slot, faces)
    local S = A.ICON
    local ox, oy = (slot % A.ICON_COLS) * S, (slot // A.ICON_COLS) * S
    local s = S * 0.47
    local k = 0.866 * s
    local cxp, base = S / 2, S * 0.04
    for py = 0, S - 1 do
        for px = 0, S - 1 do
            local fx, fy = px + 0.5, py + 0.5
            local a = (fx - cxp) / k
            local r, g, b, al, shade = 0, 0, 0, 0, 1
            -- Верх: Y = 1.
            local bsum = 2 - (fy - base - s) / (0.5 * s)
            local X, Z = (a + bsum) / 2, (bsum - a) / 2
            if X >= 0 and X <= 1 and Z >= 0 and Z <= 1 then
                r, g, b, al = sample(faces.top[1], faces.top[2], X, 1 - Z)
            else
                local Y, u, face
                if a >= 0 then
                    local z = 1 - a
                    Y = (fy - base - (1 - z) * 0.5 * s) / s
                    u, face, shade = 1 - z, faces.right, 0.6
                else
                    local x = a + 1
                    Y = (fy - base - (1 - x) * 0.5 * s) / s
                    u, face, shade = x, faces.left, 0.8
                end
                if Y >= 0 and Y <= 1 and u >= 0 and u <= 1 then
                    r, g, b, al = sample(face[1], face[2], u, Y)
                end
            end
            if al > 0.5 then
                icons.set(ox + px, oy + py, Vec4(r * shade, g * shade, b * shade, 1))
            else
                icons.set(ox + px, oy + py, Vec4(0, 0, 0, 0))
            end
        end
    end
end

-- Плоская иконка: картинка предмета или растения во всю клетку.
local function flatIcon(icons, slot, src, tint)
    local S = A.ICON
    local ox, oy = (slot % A.ICON_COLS) * S, (slot // A.ICON_COLS) * S
    local sy0 = src.height - src.width
    for py = 0, S - 1 do
        for px = 0, S - 1 do
            local c = src.get(px * src.width // S, sy0 + py * src.width // S)
            if tint then c = Vec4(c.x * tint[1], c.y * tint[2], c.z * tint[3], c.w) end
            if c.w < 0.1 then c = Vec4(0, 0, 0, 0) end
            icons.set(ox + px, oy + py, c)
        end
    end
end

function A.build()
    local atlas = texture(A.TEXTURE, SIZE, SIZE)
    atlas.nearest = true
    atlas.fill(function() return Vec4(0, 0, 0, 0) end)

    local count = #B.list + #B.itemList
    local rows = (count + A.ICON_COLS - 1) // A.ICON_COLS
    local icons = texture(A.ICONS, A.ICON * A.ICON_COLS, A.ICON * rows)
    icons.nearest = true
    A.iconRows = rows

    local slot = 0
    for _, d in ipairs(B.list) do
        local names = B.faceNames(d)
        local t = {}
        local faceSrc = {}
        for face, nm in pairs(names) do
            local name, tint = tintOf(d, nm)
            t[face] = tileFor(atlas, name, tint)
            faceSrc[face] = {name, tint}
        end
        A.blockTiles[d.id] = t
        A.icon[d.id] = slot
        if d.draw == "cross" or d.draw == "torch" then
            flatIcon(icons, slot, sources[faceSrc.side[1]], faceSrc.side[2])
        else
            cubeIcon(icons, slot, {top = faceSrc.top, right = faceSrc.side, left = faceSrc.front})
        end
        slot = slot + 1
    end
    for _, it in ipairs(B.itemList) do
        local src = texture.load("assets/textures/items/" .. it.tex .. ".png", "item_" .. it.name)
        A.icon[it.id] = slot
        flatIcon(icons, slot, src)
        slot = slot + 1
    end
    for i = 0, 9 do A.destroyTile[i] = tileFor(atlas, "destroy_stage_" .. i) end
    atlas.apply()
    icons.apply()
    A.iconCanvas = icons
    A.iconSheetHeight = A.ICON * rows
end

-- Прямоугольник иконки в листе — в пикселях от ЛЕВОГО ВЕРХНЕГО угла
-- картинки (так спрайт задаёт интерфейс), а холст считает строки снизу.
function A.iconRect(id)
    local slot = A.icon[id]
    if not slot then return nil end
    local S = A.ICON
    local x = (slot % A.ICON_COLS) * S
    local yUp = (slot // A.ICON_COLS) * S
    return x, A.iconSheetHeight - yUp - S, S, S
end

return A
