-- ---------------------------------------------------------------------------
-- inventory.lua — рюкзак, панель быстрого доступа и мастерская.
--
-- Рюкзак — 36 ячеек; первые девять — панель внизу экрана (1–9 и колесо).
-- В ячейке — стопка {id, n}: блоки и материалы складываются до 64, инструменты
-- не складываются (у каждого свой износ). Подобранное сначала доливается в
-- уже начатые стопки того же предмета, потом занимает пустую ячейку.
--
-- Экран рюкзака (E): ЛКМ — взять/положить/поменять стопку, ПКМ — взять
-- половину или положить одну, Shift+ЛКМ — перекинуть между панелью и
-- рюкзаком. Справа — мастерская: рецепты, на которые хватает материалов
-- (часть требует верстака рядом); щелчок — сделать.
-- ---------------------------------------------------------------------------
local B = require "blocks"
local U = require "ui"
local W = require "world"

local Inv = {}

Inv.SIZE = 36
Inv.slots = {}
Inv.selected = 1
Inv.screenOpen = false
Inv.held = nil                 -- стопка «в руке» на экране рюкзака

local hotbar = {}              -- ячейки панели
local grid = {}                -- ячейки экрана рюкзака
local recipeRows = {}
local hudRoot, screenRoot, heldSlot, titleLabel, tipLabel, selFrame
local SLOT, GAP = 46, 4

-- Рецепты мастерской: что нужно (имя -> число) и что получится.
local RECIPES = {
    {out = "planks", n = 4, need = {log = 1}},
    {out = "birch_planks", n = 4, need = {birch_log = 1}},
    {out = "stick", n = 4, need = {planks = 2}},
    {out = "stick", n = 4, need = {birch_planks = 2}},
    {out = "crafting_table", n = 1, need = {planks = 4}},
    {out = "torch", n = 4, need = {coal = 1, stick = 1}},
    {out = "furnace", n = 1, need = {cobblestone = 8}, table = true},
    {out = "wood_pickaxe", n = 1, need = {planks = 3, stick = 2}, table = true},
    {out = "wood_shovel", n = 1, need = {planks = 1, stick = 2}, table = true},
    {out = "wood_axe", n = 1, need = {planks = 3, stick = 2}, table = true},
    {out = "wood_sword", n = 1, need = {planks = 2, stick = 1}, table = true},
    {out = "stone_pickaxe", n = 1, need = {cobblestone = 3, stick = 2}, table = true},
    {out = "stone_shovel", n = 1, need = {cobblestone = 1, stick = 2}, table = true},
    {out = "stone_axe", n = 1, need = {cobblestone = 3, stick = 2}, table = true},
    {out = "stone_sword", n = 1, need = {cobblestone = 2, stick = 1}, table = true},
    {out = "iron_pickaxe", n = 1, need = {iron_ingot = 3, stick = 2}, table = true},
    {out = "iron_shovel", n = 1, need = {iron_ingot = 1, stick = 2}, table = true},
    {out = "iron_axe", n = 1, need = {iron_ingot = 3, stick = 2}, table = true},
    {out = "iron_sword", n = 1, need = {iron_ingot = 2, stick = 1}, table = true},
    {out = "diamond_pickaxe", n = 1, need = {diamond = 3, stick = 2}, table = true},
    {out = "diamond_shovel", n = 1, need = {diamond = 1, stick = 2}, table = true},
    {out = "diamond_axe", n = 1, need = {diamond = 3, stick = 2}, table = true},
    {out = "diamond_sword", n = 1, need = {diamond = 2, stick = 1}, table = true},
    {out = "iron_ingot", n = 1, need = {iron_ore = 1, coal = 1}, furnace = true},
    {out = "gold_ingot", n = 1, need = {gold_ore = 1, coal = 1}, furnace = true},
    {out = "glass", n = 1, need = {sand = 1, coal = 1}, furnace = true},
    {out = "stone", n = 1, need = {cobblestone = 1, coal = 1}, furnace = true},
    {out = "stonebrick", n = 4, need = {stone = 4}, table = true},
    {out = "sandstone", n = 1, need = {sand = 4}},
    {out = "bookshelf", n = 1, need = {planks = 6}, table = true},
    {out = "brick", n = 1, need = {clay = 1, coal = 1}, furnace = true},
    {out = "glowstone", n = 1, need = {gold_ingot = 1, torch = 4}, table = true},
    {out = "iron_block", n = 1, need = {iron_ingot = 9}, table = true},
    {out = "gold_block", n = 1, need = {gold_ingot = 9}, table = true},
    {out = "diamond_block", n = 1, need = {diamond = 9}, table = true},
    {out = "coal_block", n = 1, need = {coal = 9}, table = true},
}

-- --- Данные -----------------------------------------------------------------

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
    for i = 1, Inv.SIZE do
        local s = Inv.slots[i]
        if s then out[tostring(i)] = {id = s.id, n = s.n, wear = s.wear} end
    end
    return out
end

-- --- Мастерская ------------------------------------------------------------

local function nearBlock(id)
    local P = require "player"
    local px, py, pz = math.floor(P.pos.x), math.floor(P.pos.y), math.floor(P.pos.z)
    for dy = -2, 3 do
        for dz = -4, 4 do
            for dx = -4, 4 do
                if W.get(px + dx, py + dy, pz + dz) == id then return true end
            end
        end
    end
    return false
end

local function canCraft(r, hasTable, hasFurnace)
    if r.table and not hasTable then return false end
    if r.furnace and not hasFurnace then return false end
    for name, n in pairs(r.need) do
        if Inv.count(B.byName[name].id) < n then return false end
    end
    return true
end

function Inv.craft(r)
    for name, n in pairs(r.need) do Inv.take(B.byName[name].id, n) end
    local left = Inv.add(B.byName[r.out].id, r.n)
    if left > 0 then require("drops").spawnAtPlayer(B.byName[r.out].id, left) end
end

local function needText(r)
    local parts = {}
    for name, n in pairs(r.need) do parts[#parts + 1] = n .. " " .. B.byName[name].title end
    table.sort(parts)
    local where = r.furnace and "  [печь]" or (r.table and "  [верстак]" or "")
    return table.concat(parts, ", ") .. where
end

-- --- Экран -----------------------------------------------------------------

function Inv.buildHud()
    hudRoot = U.screen("Hotbar", 5)
    local total = 9 * SLOT + 8 * GAP
    -- У нижнего якоря Position.y — отступ НИЖНЕГО края элемента от низа
    -- экрана (вверх), x — смещение центра от середины.
    local rowY = 12
    Inv.rowY = rowY
    local back = U.panel(hudRoot, "Hotbar Back", UIAnchor.BottomCenter, 0, rowY - 6, total + 12, SLOT + 12, U.INK)
    for i = 1, 9 do
        local x = -total / 2 + (i - 1) * (SLOT + GAP) + SLOT / 2
        hotbar[i] = U.slot(hudRoot, "Hotbar " .. i, UIAnchor.BottomCenter, x, rowY, SLOT)
    end
    local _, se = U.panel(hudRoot, "Hotbar Select", UIAnchor.BottomCenter, 0, rowY - 3, SLOT + 6, SLOT + 6, Vec4(0, 0, 0, 0))
    se.BorderThickness = 3
    se.BorderColor = U.SLOT_HI
    selFrame = se
    local _, te = U.label(hudRoot, "Hotbar Title", UIAnchor.BottomCenter, 0, rowY + SLOT + 34, 400, 22, "", 1.3, true)
    titleLabel = te
    Inv.titleTimer = 0
    Inv.lastSelected = 0
end

function Inv.buildScreen()
    screenRoot = U.screen("Backpack", 20)
    local _, dim = U.panel(screenRoot, "Backpack Dim", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0, 0, 0, 0.45))
    dim.Stretch = UIStretch.Both
    local cols, rows = 9, 4
    local gw = cols * SLOT + (cols - 1) * GAP
    local gh = rows * SLOT + (rows - 1) * GAP + 14
    U.panel(screenRoot, "Backpack Panel", UIAnchor.Center, -170, 0, gw + 28, gh + 70, U.INK)
    local _, t = U.label(screenRoot, "Backpack Title", UIAnchor.Center, -170, -gh / 2 - 14, gw, 24, "Рюкзак", 1.5, true)
    t.TextColor = U.TEXT
    Inv.gridOrigin = {-170 - gw / 2 + SLOT / 2, -gh / 2 + SLOT / 2 + 12}
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            -- Нижний ряд экрана — это панель (ячейки 1–9), над ней — рюкзак.
            local idx = r == rows - 1 and (c + 1) or (10 + r * 9 + c)
            local x = Inv.gridOrigin[1] + c * (SLOT + GAP)
            local y = Inv.gridOrigin[2] + r * (SLOT + GAP) + (r == rows - 1 and 14 or 0)
            local s = U.slot(screenRoot, "Pack " .. idx, UIAnchor.Center, x, y, SLOT)
            s.index = idx
            s.cx, s.cy = x, y
            grid[#grid + 1] = s
        end
    end
    -- Мастерская.
    local mw, mh = 330, gh + 70
    U.panel(screenRoot, "Workshop Panel", UIAnchor.Center, gw / 2 + 50, 0, mw, mh, U.INK)
    local _, wt = U.label(screenRoot, "Workshop Title", UIAnchor.Center, gw / 2 + 50, -mh / 2 + 18, mw - 20, 24, "Мастерская", 1.5, true)
    wt.TextColor = U.TEXT
    for i = 1, 8 do
        local y = -mh / 2 + 44 + (i - 1) * 32
        local row = {}
        row.x, row.y, row.w, row.h = gw / 2 + 50, y + 12, mw - 16, 30
        row.bg, row.bge = U.panel(screenRoot, "Recipe " .. i, UIAnchor.Center, row.x, row.y, row.w, row.h, U.SLOT)
        row.slot = U.slot(screenRoot, "Recipe Icon " .. i, UIAnchor.Center, row.x - row.w / 2 + 16, row.y, 28)
        row.slot.bge.Color = Vec4(0, 0, 0, 0)
        row.slot.bge.BorderThickness = 0
        local _, le = U.label(screenRoot, "Recipe Text " .. i, UIAnchor.Center, row.x + 16, row.y - 6, row.w - 40, 14, "", 1.0)
        local _, ne = U.label(screenRoot, "Recipe Need " .. i, UIAnchor.Center, row.x + 16, row.y + 7, row.w - 40, 14, "", 0.85)
        ne.TextColor = U.MUTED
        row.title, row.need = le, ne
        recipeRows[i] = row
    end
    local _, te = U.label(screenRoot, "Backpack Tip", UIAnchor.Center, -170, gh / 2 + 22, gw, 18,
        "ЛКМ — взять/положить   ПКМ — половину/одну   Shift+ЛКМ — перекинуть", 0.9, true)
    te.TextColor = U.MUTED
    tipLabel = te
    heldSlot = U.slot(screenRoot, "Held", UIAnchor.TopLeft, 0, 0, SLOT)
    heldSlot.bge.Color = Vec4(0, 0, 0, 0)
    heldSlot.bge.BorderThickness = 0
    U.show(screenRoot, false)
    for _, s in ipairs(grid) do U.show(s.bg, false) end
end

function Inv.toggleScreen()
    Inv.screenOpen = not Inv.screenOpen
    U.show(screenRoot, Inv.screenOpen)
    SetMouseCaptured(not Inv.screenOpen)
    input.ReleaseAll()
    if not Inv.screenOpen and Inv.held then
        local left = Inv.add(Inv.held.id, Inv.held.n)
        if left > 0 then require("drops").spawnAtPlayer(Inv.held.id, left) end
        Inv.held = nil
    end
    Inv.recipeScroll = 0
end

-- Ячейка рюкзака или строка мастерской под курсором (координаты от центра).
local function hit(mx, my)
    for _, s in ipairs(grid) do
        if math.abs(mx - s.cx) <= SLOT / 2 and math.abs(my - s.cy) <= SLOT / 2 then return "slot", s.index end
    end
    for i, row in ipairs(recipeRows) do
        if row.recipe and math.abs(mx - row.x) <= row.w / 2 and math.abs(my - row.y) <= row.h / 2 then
            return "recipe", i
        end
    end
    return nil
end

local function clickSlot(idx, right, shift)
    local s = Inv.slots[idx]
    local h = Inv.held
    if shift and not right then
        if not s then return end
        -- Перекинуть: из панели — в рюкзак, из рюкзака — в панель.
        local from, to = 10, Inv.SIZE
        if idx >= 10 then from, to = 1, 9 end
        Inv.slots[idx] = nil
        local n = s.n
        for pass = 1, 2 do
            for i = from, to do
                local t = Inv.slots[i]
                if pass == 1 and t and t.id == s.id and t.n < stackMax(s.id) then
                    local k = math.min(n, stackMax(s.id) - t.n); t.n = t.n + k; n = n - k
                elseif pass == 2 and not t and n > 0 then
                    Inv.slots[i] = {id = s.id, n = n, wear = s.wear}; n = 0
                end
                if n == 0 then return end
            end
        end
        s.n = n
        Inv.slots[idx] = s
        return
    end
    if not right then
        if h and s and h.id == s.id and not s.wear then
            local k = math.min(h.n, stackMax(s.id) - s.n)
            s.n = s.n + k
            h.n = h.n - k
            if h.n == 0 then Inv.held = nil end
        else
            Inv.slots[idx], Inv.held = h, s
        end
    else
        if not h and s then
            local half = math.ceil(s.n / 2)
            Inv.held = {id = s.id, n = half, wear = s.wear}
            s.n = s.n - half
            if s.n == 0 then Inv.slots[idx] = nil end
        elseif h and not s then
            Inv.slots[idx] = {id = h.id, n = 1, wear = h.wear}
            h.n = h.n - 1
            if h.n == 0 then Inv.held = nil end
        elseif h and s and s.id == h.id and s.n < stackMax(s.id) then
            s.n = s.n + 1
            h.n = h.n - 1
            if h.n == 0 then Inv.held = nil end
        end
    end
end

function Inv.update(dt)
    for i = 1, 9 do U.setSlot(hotbar[i], Inv.slots[i]) end
    local total = 9 * SLOT + 8 * GAP
    selFrame.Position = Vec2(-total / 2 + (Inv.selected - 1) * (SLOT + GAP) + SLOT / 2, Inv.rowY - 3)
    -- Название предмета над панелью — на пару секунд после смены ячейки.
    local cur = Inv.slots[Inv.selected]
    local curId = cur and cur.id or 0
    if Inv.selected ~= Inv.lastSelected or curId ~= Inv.lastId then
        Inv.lastSelected, Inv.lastId = Inv.selected, curId
        Inv.titleTimer = curId ~= 0 and 2.0 or 0
        titleLabel.Text = curId ~= 0 and B.title(curId) or ""
    end
    Inv.titleTimer = math.max(0, Inv.titleTimer - dt)
    titleLabel.TextColor = Vec4(1, 1, 1, math.min(1, Inv.titleTimer))

    if not Inv.screenOpen then return end
    for _, s in ipairs(grid) do
        U.show(s.bg, true)
        U.setSlot(s, Inv.slots[s.index])
    end
    -- Мастерская: только то, что можно сделать сейчас.
    local hasTable = nearBlock(25)
    local hasFurnace = nearBlock(26)
    local list = {}
    for _, r in ipairs(RECIPES) do
        if canCraft(r, hasTable, hasFurnace) then list[#list + 1] = r end
    end
    local wheel = GetScrollDelta()
    Inv.recipeScroll = math.max(0, math.min(math.max(0, #list - #recipeRows), (Inv.recipeScroll or 0) - (wheel > 0 and 1 or (wheel < 0 and -1 or 0))))
    for i, row in ipairs(recipeRows) do
        local r = list[i + Inv.recipeScroll]
        row.recipe = r
        U.show(row.bg, r ~= nil)
        if r then
            local id = B.byName[r.out].id
            U.setSlot(row.slot, {id = id, n = r.n})
            row.title.Text = B.title(id) .. (r.n > 1 and (" ×" .. r.n) or "")
            row.need.Text = needText(r)
        else
            U.setSlot(row.slot, nil)
            row.title.Text = #list == 0 and i == 1 and "Не из чего делать" or ""
            row.need.Text = ""
        end
    end

    local cur2 = UICursor()
    local size = UIScreenSize()
    local mx, my = cur2.x - size.x / 2, cur2.y - size.y / 2
    local left = Input.is_mouse_pressed("left")
    local right = Input.is_mouse_pressed("right")
    local shift = Input.is_key_down("LeftShift") or Input.is_key_down("Shift")
    if left or right then
        local kind, idx = hit(mx, my)
        if kind == "slot" then clickSlot(idx, right, shift)
        elseif kind == "recipe" and left and recipeRows[idx].recipe then Inv.craft(recipeRows[idx].recipe)
        elseif not kind and Inv.held then
            -- Мимо окна — выбросить.
            require("drops").throwFromPlayer(Inv.held.id, right and 1 or Inv.held.n)
            if right then
                Inv.held.n = Inv.held.n - 1
                if Inv.held.n == 0 then Inv.held = nil end
            else
                Inv.held = nil
            end
        end
    end
    U.setSlot(heldSlot, Inv.held)
    heldSlot.bge.Position = Vec2(cur2.x - SLOT / 2, cur2.y - SLOT / 2)
end

return Inv
