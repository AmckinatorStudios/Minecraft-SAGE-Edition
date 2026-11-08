-- ---------------------------------------------------------------------------
-- inventory.lua — рюкзак, панель быстрого доступа и ручной крафт.
--
-- Рюкзак — 36 ячеек; первые девять — панель внизу экрана (1–9 и колесо),
-- 37–40 — снаряжение. В ячейке — стопка {id, n}: блоки и материалы
-- складываются до 64, инструменты не складываются (у каждого свой износ).
--
-- Экран рюкзака (E): слева снаряжение и сам персонаж, справа сетка крафта
-- 2×2; у верстака (ПКМ по нему) — сетка 3×3. Материалы игрок раскладывает
-- сам, результат появляется в ячейке справа от стрелки. ЛКМ — взять/
-- положить/поменять стопку, ПКМ — половину или одну, Shift+ЛКМ — перекинуть
-- между панелью и рюкзаком (по результату — сделать сколько хватит).
-- ---------------------------------------------------------------------------
local B = require "blocks"
local U = require "ui"
local W = require "world"
local R = require "crafting"

local Inv = {}

Inv.SIZE = 36
Inv.ARMOR = 37                 -- 37..40 — снаряжение
Inv.slots = {}
Inv.selected = 1
Inv.screenOpen = false
Inv.held = nil                 -- стопка «в руке» на экране рюкзака
Inv.grid = {}                  -- сетка крафта: 1..size*size
Inv.gridSize = 2

local hotbar = {}              -- ячейки панели
local regions = {}             -- всё, во что попадает мышь на экране рюкзака
local hudRoot, screenRoot, heldSlot, titleLabel, selFrame

local function stackMax(id) return B.maxStack(id) end

local function newStack(id, n)
    local s = {id = id, n = n}
    local d = B.byId[id]
    if d and d.uses then s.wear = 0 end
    return s
end

-- Положить n штук id; вернёт, сколько не поместилось.
function Inv.add(id, n)
    local max = stackMax(id)
    for pass = 1, 2 do
        for i = 1, Inv.SIZE do
            local s = Inv.slots[i]
            if pass == 1 and s and s.id == id and s.n < max then
                local k = math.min(n, max - s.n)
                s.n = s.n + k
                n = n - k
            elseif pass == 2 and not s then
                local k = math.min(n, max)
                Inv.slots[i] = newStack(id, k)
                n = n - k
            end
            if n == 0 then return 0 end
        end
    end
    return n
end

function Inv.count(id)
    local total = 0
    for i = 1, Inv.SIZE do
        local s = Inv.slots[i]
        if s and s.id == id then total = total + s.n end
    end
    return total
end

-- Забрать n штук (сначала с конца рюкзака, чтобы панель пустела последней).
function Inv.take(id, n)
    for i = Inv.SIZE, 1, -1 do
        local s = Inv.slots[i]
        if s and s.id == id then
            local k = math.min(n, s.n)
            s.n = s.n - k
            n = n - k
            if s.n == 0 then Inv.slots[i] = nil end
            if n == 0 then return true end
        end
    end
    return n == 0
end

function Inv.current() return Inv.slots[Inv.selected] end

-- Израсходовать одну штуку из выбранной ячейки (поставили блок).
function Inv.useOne()
    local s = Inv.slots[Inv.selected]
    if not s then return end
    s.n = s.n - 1
    if s.n <= 0 then Inv.slots[Inv.selected] = nil end
end

-- Износ инструмента в руке; сломался — исчезает.
function Inv.wearTool()
    local s = Inv.slots[Inv.selected]
    if not s or not s.wear then return end
    s.wear = s.wear + 1
    if s.wear >= B.byId[s.id].uses then Inv.slots[Inv.selected] = nil end
end

function Inv.select(i) Inv.selected = i end

function Inv.init(saved)
    Inv.slots = {}
    if saved then
        for i, s in pairs(saved) do
            local idx = tonumber(i)
            if idx and s.id and B.byId[s.id] then Inv.slots[idx] = {id = s.id, n = s.n, wear = s.wear} end
        end
    end
    Inv.buildHud()
    Inv.buildScreen()
end

function Inv.serialize()
    local out = {}
    for i = 1, Inv.SIZE + 4 do
        local s = Inv.slots[i]
        if s then out[tostring(i)] = {id = s.id, n = s.n, wear = s.wear} end
    end
    return out
end

-- --- Крафт ----------------------------------------------------------------

-- Что лежит в ячейке результата сейчас.
function Inv.result()
    local r = R.match(Inv.grid, {size = Inv.gridSize})
    return r
end

-- Забрать результат: по одной штуке из каждой непустой клетки сетки.
local function takeResult(r)
    for i = 1, Inv.gridSize * Inv.gridSize do
        local s = Inv.grid[i]
        if s then
            s.n = s.n - 1
            if s.n <= 0 then Inv.grid[i] = nil end
        end
    end
    local Act = require "interact"
    Act.stats.crafted = (Act.stats.crafted or 0) + r.n
end

local function giveBack(stack)
    if not stack then return end
    local left = Inv.add(stack.id, stack.n)
    if left > 0 then require("drops").spawnAtPlayer(stack.id, left) end
end

-- --- Экран -----------------------------------------------------------------

-- Раскладка окон набора текстур (в пикселях раскладки 256×256): где стоит
-- 16×16 внутренность каждой ячейки.
-- Клетки — ровно те, что нарисованы на картинках набора (раскладка 1.7:
-- сетка рюкзака с 88,26, результат 144,36). Координаты из более новых версий
-- (98,18 / 154,28) клали предметы между клетками.
local LAYOUT = {
    -- preview — кадр персонажа (avatar.lua: ноги в 51,75, 30 пикселей на блок).
    inventory = {armor = {8, 8}, craft = {88, 26}, result = {144, 36}, preview = {21, 5, 60, 80}},
    table = {craft = {30, 17}, result = {124, 35}},
    -- Печь (1.7): вход, топливо, результат; огонь и стрелка — куски справа
    -- той же картинки, ложатся на свои места окна по мере горения и плавки.
    furnace = {input = {56, 17}, fuel = {56, 53}, result = {116, 35}, flame = {56, 36, 14, 14},
               arrow = {79, 34, 24, 17}, flameSrc = {176, 0}, arrowSrc = {176, 14}},
    rows = 84, hotbar = 142, W = 176, H = 166,
}

-- Сверка раскладки с картинками окон: в левом верхнем углу каждой клетки
-- (внутри рамки) картинка темнее фона окна. Клетки, взятые из раскладки
-- другой версии, попадают на фон — так предметы лежали между клетками.
-- Возвращает число промахов (0 — всё на месте).
function Inv.checkLayout()
    local miss = 0
    local function probe(img, x, y)
        local k = img.width / 256
        local c = img.get(math.floor((x + 1) * k), img.height - 1 - math.floor((y + 1) * k))
        local panel = img.get(math.floor(4 * k), img.height - 1 - math.floor(4 * k))
        if not (c.x < panel.x - 0.1) then miss = miss + 1 end
    end
    for _, w in ipairs({{"inventory", LAYOUT.inventory, 2}, {"table", LAYOUT.table, 3}}) do
        local img = texture.load(w[1] == "table" and "assets/ui/crafting_table.png" or "assets/ui/inventory.png")
        local L, n = w[2], w[3]
        for r = 0, n - 1 do
            for c = 0, n - 1 do probe(img, L.craft[1] + c * 18, L.craft[2] + r * 18) end
        end
        probe(img, L.result[1], L.result[2])
        for c = 0, 8 do probe(img, 8 + c * 18, LAYOUT.rows); probe(img, 8 + c * 18, LAYOUT.hotbar) end
        if L.armor then for i = 0, 3 do probe(img, L.armor[1], L.armor[2] + i * 18) end end
    end
    return miss
end

function Inv.setHudVisible(on)
    if hudRoot then U.show(hudRoot, on) end
end

function Inv.buildHud()
    hudRoot = U.screen("Hotbar", 5)
    local S = U.HUD
    Inv.rowY = 0
    U.sprite(hudRoot, "Hotbar Back", "bottom", 0, 0, 182 * S, 22 * S, "assets/ui/widgets.png", "hotbar")
    for i = 1, 9 do
        local x = (-91 + 3 + (i - 1) * 20 + 8) * S
        hotbar[i] = U.slot(hudRoot, "Hotbar " .. i, "bottom", x, 3 * S, 16 * S)
    end
    selFrame = U.sprite(hudRoot, "Hotbar Select", "bottom", 0, -1 * S, 24 * S, 24 * S,
                        "assets/ui/widgets.png", "hotbar_select")
    titleLabel = U.label(hudRoot, "Hotbar Title", "bottom", 0, 22 * S + 46, 400, 22, "", 1, true)
    Inv.titleTimer = 0
    Inv.lastSelected = 0
end

local function addRegion(kind, index, x, y, s)
    s.kind, s.index, s.cx, s.cy = kind, index, x, y
    regions[#regions + 1] = s
    return s
end

-- Надпись окна: x, y — левый верх в пикселях окна (x = nil — по центру
-- окна, как у печи). Цвет 0x404040 без тени — так оригинал пишет заголовки.
local function title(parent, text, x, y, H)
    H = H or LAYOUT.H
    local S = U.WIN
    local centered = x == nil
    local el = U.label(parent, "Window Title " .. text, "center", 0, 0, 10, 10, text, S / 2, centered)
    el.pad = 0
    el.text_color = Vec4(0x40 / 255, 0x40 / 255, 0x40 / 255, 1)
    el.shadow_color = Vec4(0, 0, 0, 0)
    -- Место — центром (якорь center): ящик надписи от (x, y) шириной w и
    -- высотой строки 9.
    local w = centered and 176 or 120
    local left = centered and 0 or x
    el.place((left + w / 2 - 88) * S, (y + 4.5 - H / 2) * S, w * S, 9 * S)
    return el
end

-- Окно: картинка набора и ячейки на её клетках. which: "inventory" | "table".
local windows = {}
local highlight
local function buildWindow(which)
    local S = U.WIN
    local w, h = LAYOUT.W * S, LAYOUT.H * S
    local path = ({table = "assets/ui/crafting_table.png", furnace = "assets/ui/furnace.png"})[which]
        or "assets/ui/inventory.png"
    local win = U.sprite(screenRoot, "Window Image " .. which, "center", 0, 0, w, h, path, "window")
    -- Центр ячейки раскладки (x, y — левый верх 16×16) в координатах от
    -- центра экрана, как у U.base с якорем Center.
    local function at(x, y) return (x + 8 - LAYOUT.W / 2) * S, (y + 8 - LAYOUT.H / 2) * S end
    local list = {win = win, slots = {}}
    local function slot(kind, index, x, y)
        local cx, cy = at(x, y)
        local sl = U.slot(screenRoot, which .. " " .. kind .. " " .. index, "center", cx, cy, 16 * S)
        sl.window = which
        addRegion(kind, index, cx, cy, sl)
        list.slots[#list.slots + 1] = sl
        return sl
    end
    for r = 0, 2 do
        for c = 0, 8 do slot("inv", 10 + r * 9 + c, 8 + c * 18, LAYOUT.rows + r * 18) end
    end
    for c = 0, 8 do slot("inv", c + 1, 8 + c * 18, LAYOUT.hotbar) end
    if which == "furnace" then
        local L = LAYOUT.furnace
        slot("furnace", 1, L.input[1], L.input[2])
        slot("furnace", 2, L.fuel[1], L.fuel[2])
        slot("furnace", 3, L.result[1], L.result[2]).size = 24 * S
        -- Полосы: элемент с левым верхним углом на месте полосы; видимая
        -- часть задаётся куском картинки (Inv.update).
        local function bar(name, r)
            local el = ui.image{parent = screenRoot, name = "Furnace " .. name, anchor = "center",
                                w = r[3] * S, h = r[4] * S, image = path}
            list.slots[#list.slots + 1] = {bg = el}
            return {el = el, x = r[1], y = r[2], w = r[3], h = r[4]}
        end
        list.title = title(screenRoot, "Furnace", nil, 6)
        list.title2 = title(screenRoot, "Inventory", 8, LAYOUT.H - 96 + 2)
        list.flame = bar("Flame", L.flame)
        list.arrow = bar("Arrow", L.arrow)
        windows[which] = list
        return
    end
    local L = which == "table" and LAYOUT.table or LAYOUT.inventory
    local n = which == "table" and 3 or 2
    -- Заголовки (drawGuiContainerForegroundLayer): цвет 0x404040, без тени.
    if which == "inventory" then
        list.title = title(screenRoot, "Crafting", 86, 16)        -- container.crafting
    else
        list.title = title(screenRoot, "Crafting", 28, 6)
        list.title2 = title(screenRoot, "Inventory", 8, LAYOUT.H - 96 + 2)
    end
    for r = 0, n - 1 do
        for c = 0, n - 1 do slot("craft", r * 3 + c + 1, L.craft[1] + c * 18, L.craft[2] + r * 18) end
    end
    local rs = slot("result", 1, L.result[1], L.result[2])
    rs.size = 24 * S
    list.result = rs
    if which == "inventory" then
        -- Броня: пустая ячейка показывает силуэт своей части (SlotArmor ->
        -- items/empty_armor_slot_*.png), сверху вниз — шлем, нагрудник,
        -- поножи, ботинки.
        list.armorIcons = {}
        for i, part in ipairs({"helmet", "chestplate", "leggings", "boots"}) do
            local x, y = LAYOUT.inventory.armor[1], LAYOUT.inventory.armor[2] + (i - 1) * 18
            local cx, cy = at(x, y)
            local io = ui.image{parent = screenRoot, name = "Armor Silhouette " .. part, anchor = "center",
                                x = cx, y = cy, w = 16 * S, h = 16 * S,
                                image = "assets/textures/items/empty_armor_slot_" .. part .. ".png"}
            list.armorIcons[i] = io
            list.slots[#list.slots + 1] = {bg = io}
        end
        for i = 0, 3 do slot("inv", Inv.ARMOR + i, LAYOUT.inventory.armor[1], LAYOUT.inventory.armor[2] + i * 18) end
        local p = LAYOUT.inventory.preview
        local px, py = (p[1] + p[3] / 2 - LAYOUT.W / 2) * S, (p[2] + p[4] / 2 - LAYOUT.H / 2) * S
        list.preview = ui.image{parent = screenRoot, name = "Preview", anchor = "center", x = px, y = py,
                                w = p[3] * S, h = p[4] * S, color = Vec4(1, 1, 1, 0)}
    end
    windows[which] = list
end

-- Окно сундука (GuiChest 1.7.10): одна картинка generic_54.png (256×256) —
-- верх окна с rows рядами (0, 0, 176, rows·18 + 17) и низ с рюкзаком
-- (0, 126, 176, 96) под ним; высота окна 114 + rows·18 (168 и 222).
-- Ячейки (ContainerChest): сундук — (8 + c·18, 18 + r·18), рюкзак —
-- (8 + c·18, 103 + r·18 + i), панель — (8 + c·18, 161 + i), i = (rows − 4)·18.
local CHEST_IMG = "assets/ui/generic_54.png"
function Inv.chestHeight(rows) return 114 + rows * 18 end
local function buildChestWindow(rows)
    local S = U.WIN
    local which = "chest" .. rows
    local H = Inv.chestHeight(rows)
    local topH = rows * 18 + 17
    local win = ui.image{parent = screenRoot, name = "Window Image " .. which, anchor = "center", x = 0,
                         y = (-H / 2 + topH / 2) * S, w = 176 * S, h = topH * S, image = CHEST_IMG}
    win.sprite = {0, 0, 176, topH}
    local win2 = ui.image{parent = screenRoot, name = "Window Image " .. which .. " Inventory", anchor = "center",
                          x = 0, y = (-H / 2 + topH + 48) * S, w = 176 * S, h = 96 * S, image = CHEST_IMG}
    win2.sprite = {0, 126, 176, 96}
    local list = {win = win, win2 = win2, slots = {}, H = H, rows = rows}
    local function slot(kind, index, x, y)
        local cx, cy = (x + 8 - 88) * S, (y + 8 - H / 2) * S
        local sl = U.slot(screenRoot, which .. " " .. kind .. " " .. index, "center", cx, cy, 16 * S)
        sl.window = which
        addRegion(kind, index, cx, cy, sl)
        list.slots[#list.slots + 1] = sl
        return sl
    end
    for r = 0, rows - 1 do
        for c = 0, 8 do slot("chest", r * 9 + c + 1, 8 + c * 18, 18 + r * 18) end
    end
    local i = (rows - 4) * 18
    for r = 0, 2 do
        for c = 0, 8 do slot("inv", 10 + r * 9 + c, 8 + c * 18, 103 + r * 18 + i) end
    end
    for c = 0, 8 do slot("inv", c + 1, 8 + c * 18, 161 + i) end
    -- Заголовки (drawGuiContainerForegroundLayer): имя хранилища в (8, 6),
    -- «Inventory» в (8, ySize − 96 + 2), цвет 0x404040.
    list.title = title(screenRoot, rows == 6 and "Large Chest" or "Chest", 8, 6, H)
    list.title2 = title(screenRoot, "Inventory", 8, H - 96 + 2, H)
    windows[which] = list
end

function Inv.buildScreen()
    screenRoot = U.screen("Backpack", 20)
    local dim = U.fill(screenRoot, "Backpack Dim", "top_left", 0, 0, 10, 10, Vec4(0, 0, 0, 0.55))
    dim.stretch = "both"
    buildWindow("inventory")
    buildWindow("table")
    buildWindow("furnace")
    buildChestWindow(3)
    buildChestWindow(6)
    -- Подсветка ячейки под курсором (GuiContainer): белый 0x80FFFFFF поверх
    -- внутренних 16×16 — и поверх предмета, рамка ячейки не меняется.
    highlight = U.fill(screenRoot, "Slot Highlight", "center", 0, 0, 16 * U.WIN, 16 * U.WIN,
                       Vec4(1, 1, 1, 128 / 255))
    U.show(highlight, false)
    heldSlot = U.slot(screenRoot, "Held", "top_left", 0, 0, 16 * U.WIN)
    U.show(screenRoot, false)
end

local function showWindow(which)
    for name, w in pairs(windows) do
        local on = name == which
        U.show(w.win, on)
        if w.win2 then U.show(w.win2, on) end
        for _, s in ipairs(w.slots) do U.show(s.bg, on) end
        if w.preview then U.show(w.preview, on) end
        if w.title then U.show(w.title, on) end
        if w.title2 then U.show(w.title2, on) end
    end
    Inv.window = which
    Inv.winH = windows[which].H or LAYOUT.H
end

-- size: 2 — рюкзак, 3 — верстак. nil — закрыть/открыть рюкзак.
-- Печь — Inv.openFurnace.
function Inv.toggleScreen(size)
    Inv.screenOpen = not Inv.screenOpen
    U.show(screenRoot, Inv.screenOpen)
    SetMouseCaptured(not Inv.screenOpen)
    input.ReleaseAll()
    if Inv.screenOpen and Inv.chest then
        Inv.gridSize = 2
        showWindow("chest" .. Inv.chest.rows)
    elseif Inv.screenOpen and Inv.furnace then
        Inv.gridSize = 2
        showWindow("furnace")
    elseif Inv.screenOpen then
        Inv.gridSize = size or 2
        showWindow(Inv.gridSize == 3 and "table" or "inventory")
        local A = require "avatar"
        if A.previewTexture and windows.inventory.preview then
            windows.inventory.preview.image = "rt:" .. A.previewTexture
            windows.inventory.preview.color = Vec4(1, 1, 1, 1)
            A.setPreview(Inv.gridSize == 2)
        end
    else
        for i = 1, 9 do giveBack(Inv.grid[i]); Inv.grid[i] = nil end
        giveBack(Inv.held)
        Inv.held = nil
        Inv.furnace = nil
        -- Сундук: игрок перестал им пользоваться (closeInventory) — крышка закрывается.
        if Inv.chest then require("chest").closed(Inv.chest) end
        Inv.chest = nil
        require("avatar").setPreview(false)
    end
end

-- Окно печи f (furnace.lua): её ячейки и полосы огня и плавки.
function Inv.openFurnace(f)
    if Inv.screenOpen then return end
    Inv.furnace = f
    Inv.toggleScreen()
end

-- Окно сундука view (chest.lua: группа, ряды, ячейки, заголовок).
function Inv.openChest(view)
    if Inv.screenOpen then require("chest").closed(view); return end
    Inv.chest = view
    Inv.toggleScreen()
end

local function hit(mx, my)
    for _, s in ipairs(regions) do
        if s.window == Inv.window then
            local half = (s.size or 16 * U.WIN) / 2
            if math.abs(mx - s.cx) <= half and math.abs(my - s.cy) <= half then return s end
        end
    end
    return nil
end

-- Ячейка-хранилище по виду и номеру: рюкзак или сетка крафта.
local function store(kind)
    if kind == "craft" then return Inv.grid end
    if kind == "furnace" then return Inv.furnace.slots end
    if kind == "chest" then return Inv.chest.slots end
    return Inv.slots
end

-- Shift+ЛКМ из рюкзака при открытой печи: что плавится — во вход, топливо —
-- в нижнюю ячейку (как в Minecraft). true — предмет ушёл (весь или часть).
local function shiftIntoFurnace(t, idx)
    local s = t[idx]
    local fs = Inv.furnace.slots
    local to = R.SMELT[s.id] and 1 or (R.FUEL[s.id] and 2) or nil
    if not to then return false end
    local q = fs[to]
    if not q then
        fs[to] = s
        t[idx] = nil
    elseif q.id == s.id and not q.wear then
        local k = math.min(s.n, stackMax(s.id) - q.n)
        q.n = q.n + k
        s.n = s.n - k
        if s.n == 0 then t[idx] = nil end
    end
    return true
end

-- Результат печи только забирают: положить в него ничего нельзя.
local function clickFurnaceOut(right, shift)
    local fs = Inv.furnace.slots
    local s = fs[3]
    if not s then return end
    local h = Inv.held
    if shift then
        local left = Inv.add(s.id, s.n)
        if left == 0 then fs[3] = nil else s.n = left end
    elseif not h then
        local n = right and math.ceil(s.n / 2) or s.n
        Inv.held = newStack(s.id, n)
        s.n = s.n - n
        if s.n == 0 then fs[3] = nil end
    elseif h.id == s.id then
        local k = math.min(s.n, stackMax(s.id) - h.n)
        h.n = h.n + k
        s.n = s.n - k
        if s.n == 0 then fs[3] = nil end
    end
end

local function gridIndex(region)
    if region.kind ~= "craft" then return region.index end
    -- Сетка хранится плотно (size*size), а ячейки экрана — 3×3.
    local r, c = (region.index - 1) // 3, (region.index - 1) % 3
    return r * Inv.gridSize + c + 1
end

-- Container.mergeItemStack: сначала в такие же стопки (по порядку ячеек),
-- остаток — в первую пустую. cells — список {таблица, номер}. Возвращает
-- остаток (0 — ушло всё).
local function merge(stack, cells)
    local n = stack.n
    local max = stackMax(stack.id)
    if not stack.wear and max > 1 then
        for _, c in ipairs(cells) do
            local q = c[1][c[2]]
            if q and q.id == stack.id and not q.wear and q.n < max then
                local k = math.min(n, max - q.n)
                q.n = q.n + k
                n = n - k
                if n == 0 then return 0 end
            end
        end
    end
    for _, c in ipairs(cells) do
        if not c[1][c[2]] then
            c[1][c[2]] = {id = stack.id, n = n, wear = stack.wear}
            return 0
        end
    end
    return n
end
Inv.merge = merge

-- Ячейки рюкзака в порядке окна сундука (ряды 10..36, затем панель 1..9);
-- reverse — с конца (transferStackInSlot из сундука: mergeItemStack(…, true)).
local function playerCells(reverse)
    local out = {}
    for i = 10, 36 do out[#out + 1] = {Inv.slots, i} end
    for i = 1, 9 do out[#out + 1] = {Inv.slots, i} end
    if reverse then
        local r = {}
        for i = #out, 1, -1 do r[#r + 1] = out[i] end
        return r
    end
    return out
end

-- Shift+ЛКМ в окне сундука (ContainerChest.transferStackInSlot): из сундука —
-- в рюкзак с конца, из рюкзака — в сундук с начала.
local function shiftChest(t, idx, kind)
    local s = t[idx]
    if not s then return end
    local cells
    if kind == "chest" then
        cells = playerCells(true)
    else
        cells = {}
        for i = 1, Inv.chest.rows * 9 do cells[#cells + 1] = {Inv.chest.slots, i} end
    end
    local left = merge(s, cells)
    if left == 0 then t[idx] = nil else s.n = left end
end
Inv.shiftChest = shiftChest

local function clickStore(t, idx, right, shift, kind)
    local s = t[idx]
    local h = Inv.held
    if shift and not right and Inv.chest and (kind == "chest" or kind == "inv") then
        shiftChest(t, idx, kind)
        return
    end
    if shift and not right and kind == "furnace" then
        if s then
            local left = Inv.add(s.id, s.n)
            if left == 0 then t[idx] = nil else s.n = left end
        end
        return
    end
    if shift and not right and kind == "inv" then
        if not s then return end
        if Inv.window == "furnace" and shiftIntoFurnace(t, idx) then return end
        local from, to = 10, Inv.SIZE
        if idx >= 10 then from, to = 1, 9 end
        t[idx] = nil
        local n = s.n
        for pass = 1, 2 do
            for i = from, to do
                local q = Inv.slots[i]
                if pass == 1 and q and q.id == s.id and not q.wear and q.n < stackMax(s.id) then
                    local k = math.min(n, stackMax(s.id) - q.n); q.n = q.n + k; n = n - k
                elseif pass == 2 and not q and n > 0 then
                    Inv.slots[i] = {id = s.id, n = n, wear = s.wear}; n = 0
                end
                if n == 0 then return end
            end
        end
        s.n = n
        t[idx] = s
        return
    end
    if not right then
        if h and s and h.id == s.id and not s.wear then
            local k = math.min(h.n, stackMax(s.id) - s.n)
            s.n = s.n + k
            h.n = h.n - k
            if h.n == 0 then Inv.held = nil end
        else
            t[idx], Inv.held = h, s
        end
    else
        if not h and s then
            local half = math.ceil(s.n / 2)
            Inv.held = {id = s.id, n = half, wear = s.wear}
            s.n = s.n - half
            if s.n == 0 then t[idx] = nil end
        elseif h and not s then
            t[idx] = {id = h.id, n = 1, wear = h.wear}
            h.n = h.n - 1
            if h.n == 0 then Inv.held = nil end
        elseif h and s and s.id == h.id and not s.wear and s.n < stackMax(s.id) then
            s.n = s.n + 1
            h.n = h.n - 1
            if h.n == 0 then Inv.held = nil end
        end
    end
end

local function clickResult(shift)
    local r = Inv.result()
    if not r then return end
    if shift then
        -- Сколько хватит материалов и места: по одному результату за раз.
        for _ = 1, 64 do
            r = Inv.result()
            if not r then break end
            local left = Inv.add(r.out, r.n)
            takeResult(r)
            if left > 0 then require("drops").spawnAtPlayer(r.out, left); break end
        end
        return
    end
    local h = Inv.held
    if h and (h.id ~= r.out or h.n + r.n > stackMax(r.out)) then return end
    if h then h.n = h.n + r.n else Inv.held = newStack(r.out, r.n) end
    takeResult(r)
end

-- Полосы печи: огонь сгорает сверху вниз (видна нижняя часть), стрелка
-- растёт слева направо. Кусок картинки — в пикселях её листа (512 = 2×256).
function Inv.updateFurnaceBars()
    local w = windows.furnace
    local flame, cook = require("furnace").progress(Inv.furnace)
    local S, K = U.WIN, 2
    local L = LAYOUT.furnace
    local function place(bar, x, y, bw, bh)
        bar.el.place((x + bw / 2 - LAYOUT.W / 2) * S, (y + bh / 2 - LAYOUT.H / 2) * S, bw * S, bh * S)
    end
    -- Огонь: высота 1..14 по оставшемуся топливу (0 — не горит, не видно).
    local fh = flame > 0 and math.max(1, math.ceil(flame * w.flame.h)) or 0
    U.show(w.flame.el, fh > 0)
    if fh > 0 then
        local top = w.flame.h - fh
        w.flame.el.sprite = {L.flameSrc[1] * K, (L.flameSrc[2] + top) * K, w.flame.w * K, fh * K}
        place(w.flame, w.flame.x, w.flame.y + top, w.flame.w, fh)
    end
    local aw = math.floor(cook * (w.arrow.w + 1))
    U.show(w.arrow.el, aw > 0)
    if aw > 0 then
        aw = math.min(aw, w.arrow.w)
        w.arrow.el.sprite = {L.arrowSrc[1] * K, L.arrowSrc[2] * K, aw * K, w.arrow.h * K}
        place(w.arrow, w.arrow.x, w.arrow.y, aw, w.arrow.h)
    end
end

-- --- Перетаскивание, сбор, выброс из ячейки ---------------------------------

local drag, lastClick

-- Можно ли положить стопку из руки в ячейку при перетаскивании
-- (func_94527_a): пусто или тот же предмет с местом. Результат — нельзя.
local function canDragInto(region)
    if region.kind == "result" or (region.kind == "furnace" and region.index == 3) then return false end
    local h = Inv.held
    if not h then return false end
    local s = store(region.kind)[gridIndex(region)]
    return s == nil or (s.id == h.id and not s.wear and not h.wear and s.n < stackMax(s.id))
end

-- Разложить стопку руки по ячейкам: поровну (ЛКМ) или по одному (ПКМ);
-- остаток — в руке.
local function spread(set, right)
    local h = Inv.held
    local each = right and 1 or math.floor(h.n / #set)
    if each < 1 then return end
    for _, r in ipairs(set) do
        local t, idx = store(r.kind), gridIndex(r)
        local s = t[idx]
        local room = s and (stackMax(h.id) - s.n) or stackMax(h.id)
        local k = math.min(each, room, h.n)
        if k > 0 then
            if s then s.n = s.n + k else t[idx] = {id = h.id, n = k, wear = h.wear} end
            h.n = h.n - k
        end
    end
    if h.n <= 0 then Inv.held = nil end
end

-- Что окажется в ячейках и в руке, если отпустить кнопку сейчас: тот же
-- расчёт, что у spread, но без изменений (GuiContainer.func_146980_g —
-- предпросмотр перетаскивания: ячейки показывают будущие стопки, рука —
-- остаток, пока кнопка ещё зажата). Возвращает {[ячейка] = стопка}, остаток.
local function spreadPreview(set, right)
    local h = Inv.held
    local out = {}
    if not h then return out, 0 end
    local left = h.n
    local each = right and 1 or math.floor(h.n / #set)
    for _, r in ipairs(set) do
        local s = store(r.kind)[gridIndex(r)]
        local have = s and s.n or 0
        local k = math.max(0, math.min(each, stackMax(h.id) - have, left))
        out[r] = {id = h.id, n = have + k, wear = h.wear}
        left = left - k
    end
    return out, left
end
Inv.spreadPreview = spreadPreview

-- Собрать в руку такие же предметы (рюкзак, сетка крафта), пока есть место.
local function gather()
    local h = Inv.held
    if not h or h.wear then return end
    local function take(t, n)
        for i = 1, n do
            local s = t[i]
            if h.n >= stackMax(h.id) then return end
            if s and s.id == h.id and not s.wear then
                local k = math.min(s.n, stackMax(h.id) - h.n)
                h.n = h.n + k
                s.n = s.n - k
                if s.n == 0 then t[i] = nil end
            end
        end
    end
    if Inv.chest then take(Inv.chest.slots, Inv.chest.rows * 9) end
    take(Inv.grid, 9)
    take(Inv.slots, Inv.SIZE)
end

-- Цифра k над ячейкой region (Container.slotClick, режим 2): ячейка рюкзака —
-- обмен с ячейкой панели; ячейка чужого хранилища (сундук, печь, сетка) —
-- её стопка уходит в панель, а стопка панели — в первое свободное место
-- рюкзака (нет места — ничего); пустая ячейка — забирает стопку панели.
-- Результат крафта и выход печи стопку панели не принимают.
function Inv.hotbarSwap(region, k)
    if region.kind == "result" then return end
    local t, idx = store(region.kind), gridIndex(region)
    local s, hot = t[idx], Inv.slots[k]
    if region.kind == "inv" and idx == k then return end
    local accepts = not (region.kind == "furnace" and idx == 3)
    if region.kind == "inv" then
        t[idx], Inv.slots[k] = hot, s
        return
    end
    if s then
        if not hot then
            Inv.slots[k], t[idx] = s, nil
        else
            -- getFirstEmptyStack: без свободной ячейки обмена нет; стопка
            -- панели — addItemStackToInventory (к таким же, затем в пустую).
            local free = false
            for i = 1, Inv.SIZE do if not Inv.slots[i] then free = true; break end end
            if not free then return end
            Inv.slots[k], t[idx] = s, nil
            local cells = {}
            for i = 1, Inv.SIZE do cells[#cells + 1] = {Inv.slots, i} end
            merge(hot, cells)
        end
    elseif hot and accepts then
        t[idx], Inv.slots[k] = hot, nil
    end
end

-- Выбросить из ячейки один предмет или всю стопку (Q / Ctrl+Q).
local function dropFromSlot(region, all)
    if region.kind == "result" then return end
    local t, idx = store(region.kind), gridIndex(region)
    local s = t[idx]
    if not s then return end
    local n = all and s.n or 1
    require("drops").throwFromPlayer(s.id, n, s.wear)
    s.n = s.n - n
    if s.n <= 0 then t[idx] = nil end
end

function Inv.update(dt)
    for i = 1, 9 do U.setSlot(hotbar[i], Inv.slots[i]) end
    selFrame.place((-91 - 1 + (Inv.selected - 1) * 20 + 12) * U.HUD, -1 * U.HUD)
    -- Название предмета над панелью — на пару секунд после смены ячейки.
    local cur = Inv.slots[Inv.selected]
    local curId = cur and cur.id or 0
    if Inv.selected ~= Inv.lastSelected or curId ~= Inv.lastId then
        Inv.lastSelected, Inv.lastId = Inv.selected, curId
        Inv.titleTimer = curId ~= 0 and 2.0 or 0
        titleLabel.text = curId ~= 0 and B.title(curId) or ""
    end
    Inv.titleTimer = math.max(0, Inv.titleTimer - dt)
    titleLabel.text_color = Vec4(1, 1, 1, math.min(1, Inv.titleTimer))

    if not Inv.screenOpen then return end
    for _, s in ipairs(regions) do
        if s.window == Inv.window then
            if s.kind == "inv" then
                U.setSlot(s, Inv.slots[s.index])
                local icons = windows[Inv.window].armorIcons
                if icons and s.index >= Inv.ARMOR then
                    local io = icons[s.index - Inv.ARMOR + 1]
                    if io then U.show(io, Inv.slots[s.index] == nil) end
                end
            elseif s.kind == "craft" then U.setSlot(s, Inv.grid[gridIndex(s)])
            elseif s.kind == "furnace" then U.setSlot(s, Inv.furnace.slots[s.index])
            elseif s.kind == "chest" then U.setSlot(s, Inv.chest.slots[s.index]) end
        end
    end
    if Inv.window == "furnace" then
        Inv.updateFurnaceBars()
    elseif Inv.chest then
        -- Сундук сломан, ушёл далеко или стал парой — окно закрывается
        -- (isUseableByPlayer), предметы остаются в его ячейках.
        if not require("chest").usable(Inv.chest, require("player")) then
            Inv.toggleScreen()
            return
        end
    else
        local r = Inv.result()
        U.setSlot(windows[Inv.window].result, r and {id = r.out, n = r.n} or nil)
    end

    local cursor = ui.cursor()
    local size = ui.size()
    local mx, my = cursor.x - size.x / 2, cursor.y - size.y / 2
    local left = Input.is_mouse_pressed("left")
    local right = Input.is_mouse_pressed("right")
    local shift = Input.is_key_down("LeftShift") or Input.is_key_down("Shift")
    local region = hit(mx, my)
    -- Курсор за пределами окна 176×166 (GuiContainer: слот −999).
    local outside = math.abs(mx) >= LAYOUT.W / 2 * U.WIN or math.abs(my) >= (Inv.winH or LAYOUT.H) / 2 * U.WIN

    -- Подсветка ячейки под курсором.
    if highlight then
        U.show(highlight, region ~= nil)
        if region then highlight.place(region.cx, region.cy) end
    end

    -- Перетаскивание стопки по ячейкам (func_146977_a): ЛКМ — поровну,
    -- ПКМ — по одному в каждую. Решается при отпускании: одна ячейка —
    -- обычный клик.
    if drag then
        local down = Input.is_mouse_down(drag.right and "right" or "left")
        if down and region and canDragInto(region) and not drag.seen[region] and Inv.held
            and #drag.set < Inv.held.n then
            drag.seen[region] = true
            drag.set[#drag.set + 1] = region
        end
        if not down then
            local d = drag
            drag = nil
            if #d.set == 1 then
                clickStore(store(d.set[1].kind), gridIndex(d.set[1]), d.right, false, d.set[1].kind)
            elseif #d.set > 1 and Inv.held then
                spread(d.set, d.right)
            end
        end
    elseif left or right then
        if region and region.kind == "result" then
            clickResult(shift)
        elseif region and region.kind == "furnace" and region.index == 3 then
            clickFurnaceOut(right, shift)
        elseif region and Inv.held and not shift and canDragInto(region) then
            drag = {right = right, set = {region}, seen = {[region] = true}}
        elseif region then
            local now = Time.total()
            local idx = gridIndex(region)
            -- Двойной клик ЛКМ по ячейке со стопкой в руке — собрать в руку
            -- такие же предметы со всего окна (func_146983_a).
            if left and not shift and lastClick and lastClick.region == region and now - lastClick.t < 0.25
                and Inv.held then
                gather()
            else
                clickStore(store(region.kind), idx, right, shift, region.kind)
            end
            lastClick = {region = region, t = now}
        elseif Inv.held and outside then
            -- За окном — выбросить: ЛКМ — всю стопку, ПКМ — один предмет.
            require("drops").throwFromPlayer(Inv.held.id, right and 1 or Inv.held.n, Inv.held.wear)
            if right then
                Inv.held.n = Inv.held.n - 1
                if Inv.held.n == 0 then Inv.held = nil end
            else
                Inv.held = nil
            end
        end
    end

    -- Цифра 1..9 над ячейкой — обмен с ячейкой панели (slotClick, режим 2).
    if region and not drag and not Inv.held then
        for k = 1, 9 do
            if WasActionPressed("Slot " .. k) then Inv.hotbarSwap(region, k) end
        end
    end
    -- Q над ячейкой — выбросить предмет из неё, Ctrl+Q — всю стопку
    -- (GuiContainer.keyTyped -> handleMouseClick(…, 4)).
    if WasActionPressed("Drop") and region and not Inv.held then
        local ctrl = Input.is_key_down("LeftControl") or Input.is_key_down("Control")
        dropFromSlot(region, ctrl)
    end
    -- Перетаскивание идёт: ячейки показывают будущие стопки сразу, как курсор
    -- зашёл в них, рука — остаток; сами стопки меняются только при отпускании.
    if drag and Inv.held then
        local preview, left = spreadPreview(drag.set, drag.right)
        for r, st in pairs(preview) do U.setSlot(r, st) end
        U.setSlot(heldSlot, left > 0 and {id = Inv.held.id, n = left, wear = Inv.held.wear} or nil)
    else
        U.setSlot(heldSlot, Inv.held)
    end
    heldSlot.bg.place(cursor.x - 8 * U.WIN, cursor.y - 8 * U.WIN)
end

-- Самопроверка (--gencheck, строка INVCHECK): правила окна без мыши.
function Inv.selfCheck()
    local D = require "drops"
    local savedSlots, savedHeld, savedThrow = Inv.slots, Inv.held, D.throwFromPlayer
    local thrown = 0
    D.throwFromPlayer = function(_, n) thrown = thrown + n end
    Inv.slots = {}
    local stone = B.byName.cobblestone.id
    local function reg(i) return {kind = "inv", index = i} end
    -- Перетаскивание ЛКМ: 64 по трём ячейкам — по 21, 1 остаётся в руке.
    Inv.held = {id = stone, n = 64}
    spread({reg(10), reg(11), reg(12)}, false)
    local even = Inv.slots[10].n == 21 and Inv.slots[12].n == 21 and Inv.held and Inv.held.n == 1
    -- ПКМ: по одному в каждую. Предпросмотр во время перетаскивания —
    -- ровно то, что получится после отпускания, и ничего не меняет.
    Inv.held = {id = stone, n = 5}
    Inv.slots[14] = {id = stone, n = 2}
    local set = {reg(13), reg(14)}
    local pv, left = spreadPreview(set, true)
    local untouched = Inv.slots[13] == nil and Inv.slots[14].n == 2 and Inv.held.n == 5
    spread(set, true)
    local ones = Inv.slots[13].n == 1 and Inv.slots[14].n == 3 and Inv.held.n == 3
    local preview = untouched and pv[set[1]].n == 1 and pv[set[2]].n == 3 and left == 3
    -- В ячейку с другим предметом перетаскивать нельзя.
    Inv.slots[15] = {id = B.byName.dirt.id, n = 1}
    local blocked = not canDragInto(reg(15)) and canDragInto(reg(16))
    -- Двойной клик: собрать такие же в руку (до 64).
    Inv.held = {id = stone, n = 1}
    gather()
    local gathered = Inv.held.n == 64 and Inv.slots[10] == nil
    -- Q — один, Ctrl+Q — вся стопка.
    Inv.slots[20] = {id = stone, n = 10}
    dropFromSlot(reg(20), false)
    local q1 = Inv.slots[20].n == 9 and thrown == 1
    dropFromSlot(reg(20), true)
    local q2 = Inv.slots[20] == nil and thrown == 10
    Inv.slots, Inv.held, D.throwFromPlayer = savedSlots, savedHeld, savedThrow
    local ok = even and ones and preview and blocked and gathered and q1 and q2
    return string.format("INVCHECK: %s поровну=%s по_одному=%s предпросмотр=%s чужая=%s сбор=%s Q=%s CtrlQ=%s",
        ok and "PASS" or "FAIL", tostring(even), tostring(ones), tostring(preview), tostring(blocked),
        tostring(gathered), tostring(q1), tostring(q2))
end

return Inv
