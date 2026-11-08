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
-- Пикселей на иконку: 128. Плоская иконка из картинки 16×16 — ровно 8×8 на
-- пиксель, и на экране 48 (окна, 16 × 3) и 32 (панель, 16 × 2) каждый её
-- пиксель ложится в целые 3 и 2 экранных пикселя. Объёмная (куб) считается
-- по пикселю ячейки — чем крупнее ячейка, тем ровнее рёбра при уменьшении.
A.ICON = 128
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
    -- снизу вверх, поэтому верхний кадр — последние w строк. Картинка 16×16
    -- (дверь из набора 1.7.10) ложится в плитку 32×32 ближайшим пикселем —
    -- каждый пиксель ровно 2×2.
    local w = src.width
    local sy0 = src.height - w
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local c = src.get(x * w // TILE, sy0 + y * w // TILE)
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
    -- Кадр — верхний квадрат w×w картинки любого размера (16 у набора 1.7.10,
    -- 32 у прежнего): раньше шаг считался от 32, и картинка 16×16 давала
    -- пустую иконку.
    local w = src.width
    local px = math.min(w - 1, math.floor(u * w))
    local py = math.min(w - 1, math.floor(v * w))
    local c = src.get(px, src.height - w + py)
    if tint then return c.x * tint[1], c.y * tint[2], c.z * tint[3], c.w end
    return c.x, c.y, c.z, c.w
end

-- Изометрическая иконка куба: верх, правый бок (+X) и левый (+Z), с тем же
-- затемнением сторон, что и в мире (шейдер участка).
-- box — коробка предмета (setBlockBoundsForItemRender: люк — плита по
-- высоте 0.406..0.594); без неё — полный куб.
local function cubeIcon(icons, slot, faces, box)
    local by0, by1 = box and box[2] or 0, box and box[5] or 1
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
            -- Верх коробки ниже верха куба на (1 − by1)·s пикселей.
            local bsum = 2 - (fy + (1 - by1) * s - base - s) / (0.5 * s)
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
                if Y >= by0 and Y <= by1 and u >= 0 and u <= 1 then
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
    -- Пустой лист — сразу: интерфейс обращается к нему с первого кадра, а
    -- иконки дорисовываются порциями (A.stepIcons).
    icons.apply()

    local slot = 0
    local jobs = {}
    for _, d in ipairs(B.list) do
        local names = B.faceNames(d)
        local t = {}
        local faceSrc = {}
        for face, nm in pairs(names) do
            local name, tint = tintOf(d, nm)
            t[face] = tileFor(atlas, name, tint)
            faceSrc[face] = {name, tint}
        end
        -- Вторая картинка блока (верхняя половина двери).
        if d.upper then t.upper = tileFor(atlas, d.upper) end
        A.blockTiles[d.id] = t
        A.icon[d.id] = slot
        local s0 = slot
        if d.draw == "cross" or d.draw == "torch" or d.draw == "ladder" then
            jobs[#jobs + 1] = function() flatIcon(icons, s0, sources[faceSrc.side[1]], faceSrc.side[2]) end
        else
            jobs[#jobs + 1] = function()
                cubeIcon(icons, s0, {top = faceSrc.top, right = faceSrc.side, left = faceSrc.front}, d.itemBox)
            end
        end
        slot = slot + 1
    end
    for _, it in ipairs(B.itemList) do
        local src = texture.load("assets/textures/items/" .. it.tex .. ".png", "item_" .. it.name)
        A.icon[it.id] = slot
        local s0 = slot
        jobs[#jobs + 1] = function() flatIcon(icons, s0, src) end
        slot = slot + 1
    end
    for i = 0, 9 do A.destroyTile[i] = tileFor(atlas, "destroy_stage_" .. i) end
    atlas.apply()
    A.iconCanvas = icons
    A.iconSheetHeight = A.ICON * rows
    A.iconJobs = jobs
    A.iconsReady = false
end

-- Иконки 128×128 считаются попиксельно — все сразу это секунды в одном
-- вызове скрипта (и предел его времени). Поэтому по нескольку за кадр
-- (A.stepIcons из OnUpdate): лист выгружается после каждой порции, иконки
-- появляются по мере готовности. true — все готовы.
function A.stepIcons(n)
    local jobs = A.iconJobs
    if not jobs or A.iconsReady then return true end
    for _ = 1, n or 4 do
        local j = table.remove(jobs, 1)
        if not j then break end
        j()
    end
    A.iconCanvas.apply()
    if #jobs == 0 then A.iconsReady = true end
    return A.iconsReady
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

-- Самопроверка (--gencheck, строка ICONCHECK): у каждого блока и предмета
-- иконка не пустая (в ячейке есть непрозрачные пиксели). Пустая была у
-- картинок 16×16 в объёмной иконке (печь, люк).
function A.selfCheck()
    local empty = {}
    local S = A.ICON
    local function filled(slot)
        local ox, oy = (slot % A.ICON_COLS) * S, (slot // A.ICON_COLS) * S
        for py = 0, S - 1, 4 do
            for px = 0, S - 1, 4 do
                if A.iconCanvas.get(ox + px, oy + py).w > 0.5 then return true end
            end
        end
        return false
    end
    local n = 0
    for id, slot in pairs(A.icon) do
        n = n + 1
        if not filled(slot) then empty[#empty + 1] = B.byId[id] and B.byId[id].name or tostring(id) end
    end
    table.sort(empty)
    return string.format("ICONCHECK: %s иконок=%d размер=%d пустые=%s", #empty == 0 and "PASS" or "FAIL", n, S,
        #empty == 0 and "нет" or table.concat(empty, ","))
end

return A
