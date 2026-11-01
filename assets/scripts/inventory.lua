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
local hudRoot, screenRoot, heldSlot, titleLabel, selFrame, craftTitle
local craftSlots, resultSlot, previewImg
local SLOT, GAP = 40, 4
local HSLOT = 46               -- ячейка панели на экране игры

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

-- Что лежит в ячейке результата сейчас.
function Inv.result()
    local r = R.match(Inv.grid, {size = Inv.gridSize, furnace = Inv.gridSize == 3 and Inv.nearFurnace})
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

function Inv.buildHud()
    hudRoot = U.screen("Hotbar", 5)
    local total = 9 * HSLOT + 8 * GAP
    -- У нижнего якоря Position.y — отступ НИЖНЕГО края элемента от низа
    -- экрана (вверх), x — смещение центра от середины.
    local rowY = 8
    Inv.rowY = rowY
    Inv.hotbarWidth = total
    for i = 1, 9 do
        local x = -total / 2 + (i - 1) * (HSLOT + GAP) + HSLOT / 2
        hotbar[i] = U.slot(hudRoot, "Hotbar " .. i, UIAnchor.BottomCenter, x, rowY, HSLOT, "hotbar_slot")
    end
    local _, se = U.panel(hudRoot, "Hotbar Select", UIAnchor.BottomCenter, 0, rowY - 3, HSLOT + 6, HSLOT + 6, nil, "hotbar_select")
    selFrame = se
    local _, te = U.label(hudRoot, "Hotbar Title", UIAnchor.BottomCenter, 0, rowY + HSLOT + 52, 400, 22, "", 1.3, true)
    titleLabel = te
    Inv.titleTimer = 0
    Inv.lastSelected = 0
end

local function addRegion(kind, index, x, y, s)
    s.kind, s.index, s.cx, s.cy = kind, index, x, y
    regions[#regions + 1] = s
    return s
end

function Inv.buildScreen()
    screenRoot = U.screen("Backpack", 20)
    local _, dim = U.fill(screenRoot, "Backpack Dim", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0, 0, 0, 0.5))
    dim.Stretch = UIStretch.Both
    dim.Rounding = 0
    local C = SLOT + GAP
    local gw = 9 * C - GAP
    local topH = 4 * C - GAP
    local H = 18 + topH + 16 + 3 * C - GAP + 10 + SLOT + 18
    local top = -H / 2 + 18
    local left = -gw / 2
    U.panel(screenRoot, "Backpack Panel", UIAnchor.Center, 0, 0, gw + 28, H)

    -- Снаряжение: столбик из четырёх ячеек.
    for i = 0, 3 do
        local x, y = left + SLOT / 2, top + i * C + SLOT / 2
        local s = addRegion("inv", Inv.ARMOR + i, x, y, U.slot(screenRoot, "Armor " .. i, UIAnchor.Center, x, y, SLOT))
    end
    -- Персонаж: картинка со съёмки модели (см. avatar.lua, Avatar.preview).
    local pw = 2 * C + 18
    local px = left + C + pw / 2 + 2
    U.panel(screenRoot, "Preview Back", UIAnchor.Center, px, top + topH / 2, pw, topH, nil, "well")
    local pv, pve = U.base(screenRoot, "Preview", UIAnchor.Center, px, top + topH / 2, pw, topH)
    pve.Type = UIKind.Image
    pve.Color = Vec4(1, 1, 1, 1)
    previewImg = pv

    -- Крафт: сетка до 3×3 (лишние клетки прячутся в режиме 2×2), стрелка,
    -- результат.
    craftSlots = {}
    -- Сетка начинается сразу за превью; стрелка и результат — у правого края.
    local gx0 = left + 3 * C + 22
    Inv.craftOrigin = {gx0, top + 14}
    for r = 0, 2 do
        for c = 0, 2 do
            local i = r * 3 + c + 1
            local x, y = gx0 + c * C + SLOT / 2, top + 14 + r * C + SLOT / 2
            craftSlots[i] = addRegion("craft", i, x, y, U.slot(screenRoot, "Craft " .. i, UIAnchor.Center, x, y, SLOT))
        end
    end
    local _, ct = U.label(screenRoot, "Craft Title", UIAnchor.Center, gx0 + C + 20, top - 4, 3 * C, 18, "Создание", 1, false)
    ct.TextColor = Vec4(0.25, 0.24, 0.22, 1)
    ct.TextShadowColor = Vec4(0, 0, 0, 0)
    craftTitle = ct
    U.panel(screenRoot, "Craft Arrow", UIAnchor.Center, gx0 + 3 * C + 14, top + 14 + C + SLOT / 2, 22 * 2, 15 * 2, nil, "arrow")
    local rx, ry = left + gw - SLOT / 2, top + 14 + C + SLOT / 2
    resultSlot = addRegion("result", 1, rx, ry, U.slot(screenRoot, "Craft Result", UIAnchor.Center, rx, ry, SLOT + 6))
    resultSlot.size = SLOT + 6

    -- Рюкзак 3×9 и панель.
    local y0 = top + topH + 16
    for r = 0, 2 do
        for c = 0, 8 do
            local idx = 10 + r * 9 + c
            local x, y = left + c * C + SLOT / 2, y0 + r * C + SLOT / 2
            addRegion("inv", idx, x, y, U.slot(screenRoot, "Pack " .. idx, UIAnchor.Center, x, y, SLOT))
        end
    end
    for c = 0, 8 do
        local x, y = left + c * C + SLOT / 2, y0 + 3 * C + 10 + SLOT / 2 - GAP
        addRegion("inv", c + 1, x, y, U.slot(screenRoot, "Pack " .. (c + 1), UIAnchor.Center, x, y, SLOT))
    end
    heldSlot = U.slot(screenRoot, "Held", UIAnchor.TopLeft, 0, 0, SLOT)
    heldSlot.bge.Color = Vec4(1, 1, 1, 0)
    U.show(screenRoot, false)
end

-- size: 2 — рюкзак, 3 — верстак. nil — закрыть/открыть рюкзак.
function Inv.toggleScreen(size)
    Inv.screenOpen = not Inv.screenOpen
    U.show(screenRoot, Inv.screenOpen)
    SetMouseCaptured(not Inv.screenOpen)
    input.ReleaseAll()
    if Inv.screenOpen then
        Inv.gridSize = size or 2
        Inv.nearFurnace = nearBlock(26)
        for i, s in ipairs(craftSlots) do
            local r, c = (i - 1) // 3, (i - 1) % 3
            U.show(s.bg, r < Inv.gridSize and c < Inv.gridSize)
        end
        craftTitle.Text = Inv.gridSize == 3 and (Inv.nearFurnace and "Верстак и печь" or "Верстак") or "Создание"
        local A = require "avatar"
        if A.previewTexture then
            SetUIImage(previewImg, "rt:" .. A.previewTexture, true)
            A.setPreview(true)
        end
    else
        for i = 1, 9 do giveBack(Inv.grid[i]); Inv.grid[i] = nil end
        giveBack(Inv.held)
        Inv.held = nil
        require("avatar").setPreview(false)
    end
end

local function hit(mx, my)
    for _, s in ipairs(regions) do
        local half = (s.size or SLOT) / 2
        if math.abs(mx - s.cx) <= half and math.abs(my - s.cy) <= half then
            if s.kind ~= "craft" then return s end
            local r, c = (s.index - 1) // 3, (s.index - 1) % 3
            if r < Inv.gridSize and c < Inv.gridSize then return s end
        end
    end
    return nil
end

-- Ячейка-хранилище по виду и номеру: рюкзак или сетка крафта.
local function store(kind)
    if kind == "craft" then return Inv.grid end
    return Inv.slots
end

local function gridIndex(region)
    if region.kind ~= "craft" then return region.index end
    -- Сетка хранится плотно (size*size), а ячейки экрана — 3×3.
    local r, c = (region.index - 1) // 3, (region.index - 1) % 3
    return r * Inv.gridSize + c + 1
end

local function clickStore(t, idx, right, shift, kind)
    local s = t[idx]
    local h = Inv.held
    if shift and not right and kind == "inv" then
        if not s then return end
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

function Inv.update(dt)
    for i = 1, 9 do U.setSlot(hotbar[i], Inv.slots[i]) end
    selFrame.Position = Vec2(-Inv.hotbarWidth / 2 + (Inv.selected - 1) * (HSLOT + GAP) + HSLOT / 2, Inv.rowY - 3)
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
    for _, s in ipairs(regions) do
        if s.kind == "inv" then
            U.setSlot(s, Inv.slots[s.index])
        elseif s.kind == "craft" then
            local r, c = (s.index - 1) // 3, (s.index - 1) % 3
            if r < Inv.gridSize and c < Inv.gridSize then U.setSlot(s, Inv.grid[gridIndex(s)]) end
        end
    end
    local r = Inv.result()
    U.setSlot(resultSlot, r and {id = r.out, n = r.n} or nil)

    local cursor = UICursor()
    local size = UIScreenSize()
    local mx, my = cursor.x - size.x / 2, cursor.y - size.y / 2
    local left = Input.is_mouse_pressed("left")
    local right = Input.is_mouse_pressed("right")
    local shift = Input.is_key_down("LeftShift") or Input.is_key_down("Shift")
    if left or right then
        local region = hit(mx, my)
        if region and region.kind == "result" then
            clickResult(shift)
        elseif region then
            clickStore(store(region.kind), gridIndex(region), right, shift, region.kind)
        elseif Inv.held then
            -- Мимо окна — выбросить.
            require("drops").throwFromPlayer(Inv.held.id, right and 1 or Inv.held.n, Inv.held.wear)
            if right then
                Inv.held.n = Inv.held.n - 1
                if Inv.held.n == 0 then Inv.held = nil end
            else
                Inv.held = nil
            end
        end
    end
    U.setSlot(heldSlot, Inv.held)
    heldSlot.bge.Position = Vec2(cursor.x - SLOT / 2, cursor.y - SLOT / 2)
end

return Inv
