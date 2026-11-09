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
A.frameIcons = {}          -- [id] = {[кадр] = номер иконки} — у предметов с кадрами
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

-- Грани сундука для иконки, руки и выпавшего предмета: у 1.7.10 предмет
-- рисуется моделью (ChestItemRenderHelper), а не кубом из плиток блока,
-- поэтому плитки собираются из той же развёртки normal.png (64×64): верх —
-- верх крышки, перед — перед крышки над передом корпуса и защёлка, бок —
-- бок крышки над боком корпуса. Высота модели — 14/16 (коробка предмета),
-- поэтому верхние два ряда плитки пусты. Ширина 14 растянута до 16.
local CHEST_SRC = "assets/textures/entity/chest/normal.png"
local function chestFaces()
    local src = sources[CHEST_SRC] or texture.load(CHEST_SRC, "src_chest_normal")
    sources[CHEST_SRC] = src
    local function px(u, v) return src.get(u, src.height - 1 - v) end
    local function face(name, fill)
        local c = texture("chest_face_" .. name, 16, 16)
        c.nearest = true
        c.fill(function() return Vec4(0, 0, 0, 0) end)
        for r = 0, 15 do
            for x = 0, 15 do
                local col = fill(x, r)
                if col then c.set(x, 15 - r, col) end
            end
        end
        sources["chest_" .. name] = c
        return "chest_" .. name
    end
    local function sx(x) return math.floor(x * 14 / 16) end
    -- Ряды 2..6 — бок крышки (v 14..18), 7..15 — корпус без верхнего ряда,
    -- который крышка перекрывает (v 34..42).
    local function side(u0, knob)
        return function(x, r)
            if knob and x >= 7 and x <= 8 and r >= 5 and r <= 8 then return px(1 + (x - 7), 1 + (r - 5)) end
            if r >= 2 and r <= 6 then return px(u0 + sx(x), 14 + (r - 2)) end
            if r >= 7 then return px(u0 + sx(x), 34 + (r - 7)) end
            return nil
        end
    end
    return {
        top = face("top", function(x, r) return px(14 + sx(x), sx(r)) end),
        bottom = face("bottom", function(x, r) return px(28 + sx(x), 19 + sx(r)) end),
        front = face("front", side(14, true)),
        side = face("side", side(28, false)),
    }
end

function A.build()
    local atlas = texture(A.TEXTURE, SIZE, SIZE)
    atlas.nearest = true
    atlas.fill(function() return Vec4(0, 0, 0, 0) end)

    local count = #B.list + #B.itemList
    for _, it in ipairs(B.itemList) do count = count + (it.frames or 0) end
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
        local names = d.chestFaces and chestFaces() or B.faceNames(d)
        local t = {}
        local faceSrc = {}
        for face, nm in pairs(names) do
            local name, tint = tintOf(d, nm)
            t[face] = tileFor(atlas, name, tint)
            faceSrc[face] = {name, tint}
        end
        -- Вторая картинка блока (верхняя половина двери).
        if d.upper then t.upper = tileFor(atlas, d.upper) end
        -- Осколки сундука — доски (BlockChest.registerBlockIcons: planks_oak).
        if d.chestFaces then t.particle = tileFor(atlas, d.tex) end
        -- Влажная грядка — вторая картинка верха; пшеница — картинка стадии.
        if d.wet then t.wet = tileFor(atlas, d.wet) end
        if d.stages then
            t.stages = {}
            for i, nm in ipairs(d.stages) do t.stages[i] = tileFor(atlas, nm) end
        end
        A.blockTiles[d.id] = t
        A.icon[d.id] = slot
        local s0 = slot
        if d.draw == "cross" or d.draw == "torch" or d.draw == "ladder" or d.draw == "crops" then
            jobs[#jobs + 1] = {slot = s0, kind = "flat", src = faceSrc.side[1], tint = faceSrc.side[2]}
        else
            jobs[#jobs + 1] = {slot = s0, kind = "cube", box = d.itemBox,
                               faces = {top = faceSrc.top, right = faceSrc.side, left = faceSrc.front}}
        end
        slot = slot + 1
    end
    for _, it in ipairs(B.itemList) do
        local srcName = "item_" .. it.name
        sources[srcName] = sources[srcName] or texture.load("assets/textures/items/" .. it.tex .. ".png", srcName)
        A.icon[it.id] = slot
        local s0 = slot
        jobs[#jobs + 1] = {slot = s0, kind = "flat", src = srcName}
        slot = slot + 1
        -- Кадры полосы (компас, часы) — свои ячейки листа.
        if it.frames then
            A.frameIcons[it.id] = {}
            for f = 0, it.frames - 1 do
                local sf = slot
                A.frameIcons[it.id][f] = sf
                jobs[#jobs + 1] = {slot = sf, kind = "flat", src = srcName, frame = f}
                slot = slot + 1
            end
        end
    end
    for i = 0, 9 do A.destroyTile[i] = tileFor(atlas, "destroy_stage_" .. i) end
    atlas.apply()
    A.iconCanvas = icons
    A.iconSheetHeight = A.ICON * rows
    A.iconJobs = jobs
    A.iconsReady = false
end

-- Иконки 128×128 считает iconjob.lua — в фоновых потоках движка (tasks),
-- по задаче на иконку; главный поток только ставит задачи и кладёт готовые
-- пиксели в лист одним texture.write. Без задач — здесь же, по бюджету
-- времени. Лист уходит в видеокарту не каждый кадр, а раз в 0.25 с и в
-- конце. Прежде иконка считалась попиксельно на главном потоке (get/set на
-- каждый пиксель) — ~300 мс на иконку: меню и первые секунды в мире
-- дёргались. true — все готовы.
local IJ = require "iconjob"
local pixelCache = {}      -- имя картинки -> {px, w, h} (texture.read)
local inFlight = {}        -- номер задачи -> слот
local nInFlight = 0
local lastApply = 0

local function pixels(name)
    local p = pixelCache[name]
    if not p then
        local src = sources[name]
        p = {px = src.read(0, 0, src.width, src.height), w = src.width, h = src.height}
        pixelCache[name] = p
    end
    return p
end

-- Задача с пикселями вместо имён картинок — то, что уходит в поток.
local function payload(j)
    if j.kind == "flat" then return {kind = "flat", src = pixels(j.src), tint = j.tint, frame = j.frame} end
    local f = j.faces
    return {kind = "cube", box = j.box, faces = {
        top = {pixels(f.top[1]), f.top[2]}, right = {pixels(f.right[1]), f.right[2]},
        left = {pixels(f.left[1]), f.left[2]}}}
end

local function put(slot, px)
    local S = A.ICON
    A.iconCanvas.write((slot % A.ICON_COLS) * S, (slot // A.ICON_COLS) * S, S, S, px)
end

local function useTasks() return tasks ~= nil and tasks.run ~= nil and not LaunchFlag("syncgen") end

function A.stepIcons(budgetMs)
    local jobs = A.iconJobs
    if not jobs or A.iconsReady then return true end
    local clock = Time.clock
    local t0 = clock()
    local limit = (budgetMs or 2) / 1000
    if useTasks() then
        -- Готовые — в лист.
        for id, slot in pairs(inFlight) do
            local ok, px = tasks.result(id)
            if ok ~= nil then
                inFlight[id] = nil
                nInFlight = nInFlight - 1
                if ok then put(slot, px) else logError("icon " .. slot .. ": " .. tostring(px)) end
            end
        end
        -- Новые — пока есть место у воркеров и время кадра.
        local cap = math.max(2, (tasks.workers() or 1) * 2)
        while nInFlight < cap and #jobs > 0 and clock() - t0 < limit do
            local j = table.remove(jobs, 1)
            inFlight[tasks.run("iconjob", "build", A.ICON, payload(j))] = j.slot
            nInFlight = nInFlight + 1
        end
    else
        repeat
            local j = table.remove(jobs, 1)
            if not j then break end
            put(j.slot, IJ.build(A.ICON, payload(j)))
        until clock() - t0 >= limit
    end
    if #jobs == 0 and nInFlight == 0 then A.iconsReady = true end
    if A.iconsReady or t0 - lastApply >= 0.25 then
        A.iconCanvas.apply()
        lastApply = t0
    end
    return A.iconsReady
end

-- Прямоугольник иконки в листе — в пикселях от ЛЕВОГО ВЕРХНЕГО угла
-- картинки (так спрайт задаёт интерфейс), а холст считает строки снизу.
function A.iconRect(id, frame)
    local slot = A.icon[id]
    if frame and A.frameIcons[id] and A.frameIcons[id][frame] then slot = A.frameIcons[id][frame] end
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
