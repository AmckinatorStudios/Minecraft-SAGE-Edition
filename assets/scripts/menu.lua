-- ---------------------------------------------------------------------------
-- menu.lua — экраны одиночной игры, как в Minecraft Java 1.7.10.
--
--   title    — GuiMainMenu: панорама, логотип, жёлтая надпись, Singleplayer /
--              Options... / Quit Game, версия и копирайт внизу;
--   select   — GuiSelectWorld: список миров (превью, имя, папка и дата,
--              режим), Play Selected World / Create New World / Rename /
--              Delete / Cancel;
--   create   — GuiCreateWorld: имя мира, папка, режим (только выживание);
--   rename   — GuiRenameWorld; delete — GuiYesNo;
--   options  — GuiOptions: поле зрения, дальность, громкость, мышь;
--   pause    — GuiIngameMenu: Back to Game / Options... / Save and Quit to Title;
--   loading / saving — экраны «Loading world» и «Saving world».
--
-- Раскладка — числа из initGui оригинала (пиксели интерфейса, см. gui.lua).
-- Переход между экранами — короткое растворение (0.15 с) прозрачностью
-- корня экрана. Сам мир здесь не строится: экран сообщает игре, ЧТО открыть
-- (Menu.onOpenWorld), а строит её game.lua — только после выбора.
-- ---------------------------------------------------------------------------
local U = require "ui"
local Gui = require "gui"
local Worlds = require "worlds"
local Pano = require "panorama"

local Menu = {}
local S = Gui.S
local FADE = 0.15

Menu.active = false       -- открыт любой экран (игра стоит или её ещё нет)
Menu.phase = "title"      -- "title" (мира нет), "game" (мир идёт)
Menu.screen = nil
Menu.onOpenWorld = nil    -- function(world) — из game.lua
Menu.onQuitToTitle = nil
Menu.onResume = nil
Menu.options = {fov = 70, render = 6, master = 1, music = 1, sensitivity = 0.5, gamma = 0, fancy = true}

local screens = {}
local lastW, lastH = 0, 0
local t = 0
local fadeIn, fadeOut = nil, nil

local SPLASHES = {"Made with SAGE!", "Now with furnaces!", "Cubes everywhere!", "Torches shine at 14!",
                  "Emeralds in the hills!", "Lapis at fifteen!", "Iron found!", "No garbage!",
                  "Also try Minecraft!", "100% Lua!", "Survival only!", "Press F2!"}

-- --- Каркас экрана ----------------------------------------------------------

local function newScreen(name, order)
    local root, re = U.screen("Screen " .. name, order or 70)
    local s = {name = name, root = root, re = re, items = {}, buttons = {}}
    function s.add(item) s.items[#s.items + 1] = item; return item end
    function s.button(text, onClick)
        local b = Gui.button(root, text, onClick)
        s.buttons[#s.buttons + 1] = b
        return b
    end
    U.show(root, false)
    screens[name] = s
    return s
end

local function show(s, on, alpha)
    U.show(s.root, on)
    s.re.Alpha = alpha or 1
end

-- Перейти на экран (с растворением). name == nil — закрыть все.
function Menu.go(name)
    local next = name and screens[name] or nil
    local cur = Menu.screen
    if cur == next then return end
    -- Экран, ещё не догасший с прошлого перехода, — убрать сразу: иначе при
    -- двух переходах подряд он оставался бы на экране навсегда.
    if fadeOut and fadeOut.s ~= next then show(fadeOut.s, false) end
    fadeOut = nil
    if cur then fadeOut = {s = cur, t = 0} end
    Menu.screen = next
    if next then
        if next.onOpen then next.onOpen() end
        show(next, true, 0)
        fadeIn = {s = next, t = 0}
        lastW = -1      -- раскладка заново
    end
    Menu.active = next ~= nil
end

-- Фон экрана без мира — земля; в мире — затемнение поверх игры
-- (drawDefaultBackground: 0xC0101010 -> 0xD0101010).
local function backdrop(s)
    s.dirt = Gui.dirt(s.root)
    s.dim = Gui.rect(s.root, Vec4(0.063, 0.063, 0.063, 0.75), Vec4(0.063, 0.063, 0.063, 0.82))
    s.layoutBack = function(W, H)
        s.dirt.place(0, 0, W, H)
        s.dim.place(0, 0, W, H)
        U.show(s.dirt.obj, Menu.phase ~= "game")
        U.show(s.dim.obj, Menu.phase == "game")
    end
end

-- --- Титульный экран --------------------------------------------------------

local function buildTitle()
    local s = newScreen("title", 70)
    -- Светлый верх и тёмный низ поверх размытой панорамы (renderSkybox).
    local top = Gui.rect(s.root, Vec4(1, 1, 1, 0.5), Vec4(1, 1, 1, 0))
    local bottom = Gui.rect(s.root, Vec4(0, 0, 0, 0), Vec4(0, 0, 0, 0.5))
    local lo, le = U.base(s.root, "Title Logo", UIAnchor.TopLeft, 0, 0, 274, 45)
    le.Type = UIKind.Image
    le.Color = Gui.WHITE
    SetUIImage(lo, "assets/ui/title.png", false)
    local _, sp = U.label(s.root, "Title Splash", UIAnchor.TopLeft, 0, 0, 300, 20, "", 1, true)
    sp.TextColor = Gui.YELLOW
    sp.TextShadowColor = Vec4(0.25, 0.25, 0, 1)
    sp.TextVAlign = "center"
    sp.Rotation = -20
    s.splash = sp
    s.splashText = SPLASHES[math.random(#SPLASHES)]
    sp.Text = s.splashText
    local single = s.button("Singleplayer", function() Menu.go("select") end)
    local options = s.button("Options...", function() Menu.optionsBack = "title"; Menu.go("options") end)
    local quit = s.button("Quit Game", function() game.Quit() end)
    local version = Gui.label(s.root, "SAGE Craft " .. (Menu.version or "0.1.0"), "left")
    local copy = Gui.label(s.root, "Copyright Amckinator Studios. Do not distribute!", "right")
    function s.layout(W, H)
        top.place(0, 0, W, H)
        bottom.place(0, 0, W, H)
        -- Логотип — 274 пикселя в ширину на высоте 30 (как два куска minecraft.png).
        Gui.place(le, W / 2 - 137, 30, 274, 274 * 166 / 1003)
        local j = math.floor(H / 4) + 48
        single.place(W / 2 - 100, j, 200)
        -- Ряд Options/Quit — на 12 ниже следующей строки кнопок (у оригинала
        -- между ними ещё Multiplayer и Realms — их в игре нет).
        options.place(W / 2 - 100, j + 24 + 12, 98)
        quit.place(W / 2 + 2, j + 24 + 12, 98)
        version.place(2, H - 10, 300)
        copy.place(W - 2, H - 10, 400)
    end
    function s.tick()
        -- Надпись: (1.8 − |sin(мс % 1000 / 1000 · 2π)| · 0.1) · 100 / (ширина + 32),
        -- центр — на (W/2 + 90, 70), поворот −20°.
        local W = Gui.size()
        local f = 1.8 - math.abs(math.sin((t % 1) * math.pi * 2) * 0.1)
        f = f * 100 / (#s.splashText * 6 + 32)
        -- Размер — масштаб текста: 2 — обычные 8 пикселей интерфейса (масштаб
        -- надписи движка по умолчанию), надпись крупнее в f раз (glScalef).
        sp.TextScale = 2 * f
        Gui.place(sp, W / 2 + 90 - 150, 70 - 20, 300, 40)
    end
    return s
end

-- --- Список миров -----------------------------------------------------------

local previews = {}
-- Превью мира: середина снимка квадратом 64×64.
local function previewOf(w)
    if not w.preview then return nil end
    if previews[w.slot] ~= nil then return previews[w.slot] or nil end
    local ok, src = pcall(texture.load, w.preview, "shot:" .. w.slot)
    if not ok or not src or src.width < 8 then previews[w.slot] = false; return nil end
    local name = "sagecraft_preview_" .. w.slot
    local img = texture(name, 64, 64)
    local side = math.min(src.width, src.height)
    local ox, oy = (src.width - side) // 2, (src.height - side) // 2
    for y = 0, 63 do
        for x = 0, 63 do
            img.set(x, y, src.get(ox + x * side // 64, oy + y * side // 64))
        end
    end
    img.apply()
    previews[w.slot] = name
    return name
end

local function buildSelect()
    local s = newScreen("select", 70)
    local back = Gui.dirt(s.root, 0x20 / 255)
    local clipObj, clip = U.base(s.root, "World List", UIAnchor.TopLeft, 0, 0, 10, 10)
    clip.Color = Vec4(0, 0, 0, 0)
    clip.ClipChildren = true
    local bandTop, bandBottom = Gui.dirt(s.root), Gui.dirt(s.root)
    local shadeTop = Gui.rect(s.root, Vec4(0, 0, 0, 1), Vec4(0, 0, 0, 0))
    local shadeBottom = Gui.rect(s.root, Vec4(0, 0, 0, 0), Vec4(0, 0, 0, 1))
    local track = Gui.rect(s.root, Vec4(0, 0, 0, 1))
    local thumb = Gui.rect(s.root, Gui.DARK)
    local thumbHi = Gui.rect(s.root, Vec4(0xC0 / 255, 0xC0 / 255, 0xC0 / 255, 1))
    local title = Gui.label(s.root, "Select World", "center")
    local play = s.button("Play Selected World", function() Menu.play() end)
    local create = s.button("Create New World", function() Menu.go("create") end)
    local rename = s.button("Rename", function() Menu.go("rename") end)
    local delete = s.button("Delete", function() Menu.go("delete") end)
    local cancel = s.button("Cancel", function() Menu.go("title") end)
    s.rows = {}
    s.scroll = 0
    s.selected = nil
    local SLOT = 36

    local function rowFor(i)
        local r = s.rows[i]
        if r then return r end
        local o, e = U.base(clipObj, "World Row " .. i, UIAnchor.TopLeft, 0, 0, 220, SLOT)
        e.Color = Vec4(0, 0, 0, 0)
        r = {obj = o, e = e}
        r.box = Gui.rect(o, Gui.DARK)
        r.inner = Gui.rect(o, Vec4(0, 0, 0, 1))
        r.icon = Gui.image(o)
        r.name = Gui.label(o, "", "left", Gui.WHITE)
        r.info = Gui.label(o, "", "left", Gui.DARK)
        r.mode = Gui.label(o, "", "left", Gui.DARK)
        s.rows[i] = r
        return r
    end

    function s.onOpen()
        s.worlds = Worlds.list()
        s.selected = nil
        s.scroll = 0
        for i, r in ipairs(s.rows) do U.show(r.obj, false) end
        for i, w in ipairs(s.worlds) do
            local r = rowFor(i)
            U.show(r.obj, true)
            r.name.set(w.name)
            r.info.set(w.folder .. " (" .. Worlds.dateText(w.savedAt) .. ")")
            r.mode.set(w.broken and "Damaged save" or "Survival Mode")
            r.icon.set(previewOf(w))
        end
    end

    function s.layout(W, H)
        s.W, s.H = W, H
        s.top, s.bottom = 32, H - 64
        back.place(0, 0, W, H)
        Gui.place(clip, 0, s.top, W, s.bottom - s.top)
        bandTop.place(0, 0, W, s.top)
        bandBottom.place(0, s.bottom, W, H - s.bottom)
        shadeTop.place(0, s.top, W, 4)
        shadeBottom.place(0, s.bottom - 4, W, 4)
        title.place(W / 2, 20)
        play.place(W / 2 - 154, H - 52, 150)
        create.place(W / 2 + 4, H - 52, 150)
        rename.place(W / 2 - 154, H - 28, 72)
        delete.place(W / 2 - 76, H - 28, 72)
        cancel.place(W / 2 + 82, H - 28, 72)
    end

    local lastClick, lastIndex = -1, nil
    function s.tick(dt)
        local W, H = s.W or Gui.size(), s.H
        local n = s.worlds and #s.worlds or 0
        local area = s.bottom - s.top
        local maxScroll = math.max(0, n * SLOT - (area - 4))
        local wheel = GetScrollDelta()
        if wheel ~= 0 then s.scroll = s.scroll - wheel * SLOT / 2 end
        s.scroll = math.max(0, math.min(maxScroll, s.scroll))
        local left = W / 2 - 110
        for i = 1, n do
            local r = s.rows[i]
            local y = 4 + (i - 1) * SLOT - s.scroll
            Gui.place(r.e, left, y - 2, 220, SLOT)
            local sel = s.selected == i
            U.show(r.box.obj, sel)
            U.show(r.inner.obj, sel)
            r.box.place(0, 0, 220, SLOT)
            r.inner.place(1, 1, 218, SLOT - 2)
            -- Превью 32×32 слева, текст — правее (иконка мира, как в новых
            -- версиях; строки и цвета — как у 1.7.10).
            r.icon.place(2, 2, 32, 32)
            r.name.place(2 + 36, 3, 180)
            r.info.place(2 + 36, 14, 180)
            r.mode.place(2 + 36, 24, 180)
        end
        -- Полоса прокрутки (x = W/2 + 124, ширина 6).
        local showBar = maxScroll > 0
        U.show(track.obj, showBar); U.show(thumb.obj, showBar); U.show(thumbHi.obj, showBar)
        if showBar then
            local h = math.max(32, math.min(area - 8, area * area / (n * SLOT)))
            local y = s.scroll * (area - h) / maxScroll + s.top
            track.place(W / 2 + 124, s.top, 6, area)
            thumb.place(W / 2 + 124, y, 6, h)
            thumbHi.place(W / 2 + 124, y, 5, h - 1)
        end
        -- Выбор строки щелчком; двойной щелчок (≤ 0.25 с) — играть.
        if Input.is_mouse_pressed("left") then
            local c = UICursor()
            local mx, my = c.x / S, c.y / S
            if my >= s.top and my < s.bottom and mx >= left and mx <= left + 220 then
                local i = math.floor((my - s.top - 4 + s.scroll + 2) / SLOT) + 1
                if i >= 1 and i <= n then
                    if lastIndex == i and t - lastClick < 0.25 then Menu.play() return end
                    s.selected, lastIndex, lastClick = i, i, t
                end
            end
        end
        local has = s.selected ~= nil
        play.enable(has); rename.enable(has); delete.enable(has)
    end
    return s
end

Menu.screens = screens

function Menu.selectedWorld()
    local s = screens.select
    return s and s.selected and s.worlds[s.selected] or nil
end

function Menu.play()
    local w = Menu.selectedWorld()
    if w and Menu.onOpenWorld then Menu.onOpenWorld(w) end
end

-- --- Создание, переименование, удаление ------------------------------------

local function buildCreate()
    local s = newScreen("create", 70)
    backdrop(s)
    local title = Gui.label(s.root, "Create New World", "center")
    local nameLabel = Gui.label(s.root, "World Name", "left", Gui.GRAY)
    local field = Gui.field(s.root, "New World", 32)
    s.field = field
    local folder = Gui.label(s.root, "", "left", Gui.GRAY)
    -- Режим — только выживание: кнопка показывает его, другого нет.
    local mode = s.button("Game Mode: Survival", function() end)
    local desc1 = Gui.label(s.root, "Search for resources, crafting, gain", "left", Gui.GRAY)
    local desc2 = Gui.label(s.root, "levels, health and hunger", "left", Gui.GRAY)
    local create = s.button("Create New World", function()
        local name = field.text():gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" and Menu.onOpenWorld then Menu.onOpenWorld(Worlds.create(name)) end
    end)
    local cancel = s.button("Cancel", function() Menu.go("select") end)
    s.confirm = function() create.onClick() end
    function s.onOpen()
        field.e.Text = "New World"
        field.focus()
    end
    function s.layout(W, H)
        s.layoutBack(W, H)
        title.place(W / 2, 20)
        nameLabel.place(W / 2 - 100, 47)
        field.place(W / 2 - 100, 60, 200, 20)
        folder.place(W / 2 - 100, 85, 300)
        mode.place(W / 2 - 75, 115, 150)
        desc1.place(W / 2 - 100, 137, 300)
        desc2.place(W / 2 - 100, 149, 300)
        create.place(W / 2 - 155, H - 28, 150)
        cancel.place(W / 2 + 5, H - 28, 150)
    end
    function s.tick()
        local name = field.text()
        folder.set("Will be saved in: " .. Worlds.folderFor(name))
        create.enable((name:gsub("%s", "")) ~= "")
    end
    return s
end

local function buildRename()
    local s = newScreen("rename", 70)
    backdrop(s)
    local title = Gui.label(s.root, "Rename World", "center")
    local label = Gui.label(s.root, "Enter Name", "left", Gui.GRAY)
    local field = Gui.field(s.root, "", 32)
    local ok = s.button("Rename", function()
        local w = Menu.selectedWorld()
        local name = field.text():gsub("^%s+", ""):gsub("%s+$", "")
        if w and name ~= "" then Worlds.rename(w, name) end
        Menu.go("select")
    end)
    local cancel = s.button("Cancel", function() Menu.go("select") end)
    s.confirm = function() ok.onClick() end
    function s.onOpen()
        local w = Menu.selectedWorld()
        field.e.Text = w and w.name or ""
        field.focus()
    end
    function s.layout(W, H)
        s.layoutBack(W, H)
        title.place(W / 2, 20)
        label.place(W / 2 - 100, 47)
        field.place(W / 2 - 100, 60, 200, 20)
        ok.place(W / 2 - 100, H / 4 + 96 + 12, 200)
        cancel.place(W / 2 - 100, H / 4 + 120 + 12, 200)
    end
    function s.tick() ok.enable((field.text():gsub("%s", "")) ~= "") end
    return s
end

local function buildDelete()
    local s = newScreen("delete", 70)
    backdrop(s)
    local q = Gui.label(s.root, "Are you sure you want to delete this world?", "center")
    local m = Gui.label(s.root, "", "center")
    local yes = s.button("Delete", function()
        local w = Menu.selectedWorld()
        if w then Worlds.delete(w) end
        Menu.go("select")
    end)
    local no = s.button("Cancel", function() Menu.go("select") end)
    function s.onOpen()
        local w = Menu.selectedWorld()
        m.set("'" .. (w and w.name or "") .. "' will be lost forever! (A long time!)")
    end
    function s.layout(W, H)
        s.layoutBack(W, H)
        q.place(W / 2, 70)
        m.place(W / 2, 90)
        yes.place(W / 2 - 155, H / 6 + 96, 150)
        no.place(W / 2 + 5, H / 6 + 96, 150)
    end
    return s
end

-- --- Настройки --------------------------------------------------------------

local function saveOptions() SaveGame("options", Menu.options, 1) end

function Menu.loadOptions()
    if HasSave("options") then
        local ok, data = pcall(LoadGame, "options")
        if ok and type(data) == "table" then
            for k, v in pairs(data) do Menu.options[k] = v end
        end
    end
end

local function buildOptions()
    local s = newScreen("options", 72)
    backdrop(s)
    local o = Menu.options
    local title = Gui.label(s.root, "Options", "center")
    local function apply() if Menu.onOptions then Menu.onOptions(o) end end
    local sliders = {
        Gui.slider(s.root, (o.fov - 30) / 80, function(v)
            local f = math.floor(30 + v * 80 + 0.5)
            return "FOV: " .. (f == 70 and "Normal" or (f == 110 and "Quake Pro" or tostring(f)))
        end, function(v) o.fov = math.floor(30 + v * 80 + 0.5); apply() end),
        Gui.slider(s.root, (o.render - 2) / 14, function(v)
            return "Render Distance: " .. math.floor(2 + v * 14 + 0.5) .. " chunks"
        end, function(v) o.render = math.floor(2 + v * 14 + 0.5); apply() end),
        Gui.slider(s.root, o.master, function(v)
            return "Master Volume: " .. (v == 0 and "OFF" or (math.floor(v * 100 + 0.5) .. "%"))
        end, function(v) o.master = v; apply() end),
        Gui.slider(s.root, o.music, function(v)
            return "Music: " .. (v == 0 and "OFF" or (math.floor(v * 100 + 0.5) .. "%"))
        end, function(v) o.music = v; apply() end),
        Gui.slider(s.root, o.sensitivity, function(v)
            local p = math.floor(v * 200 + 0.5)
            return "Sensitivity: " .. (p == 0 and "*yawn*" or (p == 200 and "HYPERSPEED!!!" or (p .. "%")))
        end, function(v) o.sensitivity = v; apply() end),
        -- Brightness (gammaSetting): 0 — Moody, 1 — Bright, между — +N%.
        Gui.slider(s.root, o.gamma or 0, function(v)
            local p = math.floor(v * 100 + 0.5)
            return "Brightness: " .. (p == 0 and "Moody" or (p == 100 and "Bright" or ("+" .. p .. "%")))
        end, function(v) o.gamma = v; apply() end),
    }
    -- Graphics: Fancy/Fast (fancyGraphics) — тени под существами только в Fancy.
    local function graphicsText() return "Graphics: " .. (o.fancy == false and "Fast" or "Fancy") end
    local graphics
    graphics = s.button(graphicsText(), function()
        o.fancy = o.fancy == false
        graphics.set(graphicsText())
        apply()
    end)
    local done = s.button("Done", function()
        saveOptions()
        Menu.go(Menu.optionsBack or "title")
    end)
    s.sliders = sliders
    function s.layout(W, H)
        s.layoutBack(W, H)
        title.place(W / 2, 15)
        for i, sl in ipairs(sliders) do
            local k = i - 1
            sl.place(W / 2 - 155 + (k % 2) * 160, H / 6 - 12 + 24 * (k // 2), 150)
        end
        graphics.place(W / 2 - 155 + (#sliders % 2) * 160, H / 6 - 12 + 24 * (#sliders // 2), 150)
        done.place(W / 2 - 100, H / 6 + 168, 200)
    end
    function s.tick() for _, sl in ipairs(sliders) do sl.update() end end
    return s
end

-- --- Пауза, загрузка, сохранение ---------------------------------------------

local function buildPause()
    local s = newScreen("pause", 70)
    backdrop(s)
    local title = Gui.label(s.root, "Game menu", "center")
    local back = s.button("Back to Game", function() Menu.resume() end)
    local options = s.button("Options...", function() Menu.optionsBack = "pause"; Menu.go("options") end)
    local quit = s.button("Save and Quit to Title", function()
        if Menu.onQuitToTitle then Menu.onQuitToTitle() end
    end)
    function s.layout(W, H)
        s.layoutBack(W, H)
        title.place(W / 2, 40)
        back.place(W / 2 - 100, H / 4 + 24 - 16, 200)
        options.place(W / 2 - 100, H / 4 + 96 - 16, 200)
        quit.place(W / 2 - 100, H / 4 + 120 - 16, 200)
    end
    return s
end

-- Экран «Loading world / Building terrain» с полосой (LoadingScreenRenderer).
local function buildWorking(name, titleText)
    local s = newScreen(name, 75)
    local dirt = Gui.dirt(s.root)
    local title = Gui.label(s.root, titleText, "center")
    local msg = Gui.label(s.root, "", "center")
    local bar = Gui.rect(s.root, Gui.DARK)
    local fill = Gui.rect(s.root, Vec4(0.5, 1, 0.5, 1))
    s.progress = nil
    function s.set(text, progress) msg.set(text or ""); s.progress = progress end
    function s.layout(W, H)
        dirt.place(0, 0, W, H)
        title.place(W / 2, H / 2 - 4 - 16)
        msg.place(W / 2, H / 2 - 4 + 8)
        s.W, s.H = W, H
    end
    function s.tick()
        local p = s.progress
        U.show(bar.obj, p ~= nil); U.show(fill.obj, p ~= nil)
        if p and s.W then
            bar.place(s.W / 2 - 50, s.H / 2 + 16, 100, 2)
            fill.place(s.W / 2 - 50, s.H / 2 + 16, math.max(0, math.min(100, p * 100)), 2)
        end
    end
    return s
end

-- --- Общее ------------------------------------------------------------------

function Menu.init(opts)
    Menu.version = opts and opts.version
    Menu.loadOptions()
    buildTitle()
    buildSelect()
    buildCreate()
    buildRename()
    buildDelete()
    buildOptions()
    buildPause()
    buildWorking("loading", "Loading world")
    buildWorking("saving", "Saving world")
end

function Menu.openTitle()
    Menu.phase = "title"
    Pano.show(true)
    SetMouseCaptured(false)
    require("hud").setVisible(false)
    Menu.go("title")
end

function Menu.loading(text, progress)
    if Menu.screen ~= screens.loading then Menu.go("loading") end
    screens.loading.set(text, progress)
end

function Menu.saving()
    Menu.go("saving")
end

-- Пауза (Esc в игре).
function Menu.open()
    Menu.phase = "game"
    SetMouseCaptured(false)
    Menu.go("pause")
end

function Menu.resume()
    Menu.go(nil)
    SetMouseCaptured(true)
    input.ReleaseAll()
    if Menu.onResume then Menu.onResume() end
end

-- Закрыть меню и уйти в мир (после загрузки).
function Menu.enterGame()
    Menu.phase = "game"
    Pano.show(false)
    Menu.go(nil)
    SetMouseCaptured(true)
    input.ReleaseAll()
end

-- Догасает ли ещё экран (после входа в мир — экран загрузки).
function Menu.fading() return fadeOut ~= nil end

function Menu.update(dt)
    t = t + dt
    Pano.update(dt)
    local W, H = Gui.size()
    -- Растворение экранов.
    if fadeIn then
        fadeIn.t = fadeIn.t + dt
        fadeIn.s.re.Alpha = math.min(1, fadeIn.t / FADE)
        if fadeIn.t >= FADE then fadeIn = nil end
    end
    if fadeOut then
        fadeOut.t = fadeOut.t + dt
        fadeOut.s.re.Alpha = math.max(0, 1 - fadeOut.t / FADE)
        if fadeOut.t >= FADE then
            if fadeOut.s ~= Menu.screen then show(fadeOut.s, false) end
            fadeOut = nil
        end
    end
    local s = Menu.screen
    if not s then return end
    if W ~= lastW or H ~= lastH then
        lastW, lastH = W, H
        if s.layout then s.layout(W, H) end
    end
    if s.tick then s.tick(dt) end
    -- Кнопки — после tick (он включает и выключает их).
    if not fadeIn then
        for _, b in ipairs(s.buttons) do
            if b.update() then return end
        end
    end
    -- Enter — главное действие экрана, Esc — назад (как у оригинала).
    if WasActionPressed("MenuConfirm") and s.confirm then s.confirm() end
    if WasActionPressed("Pause") then
        if s.name == "pause" then Menu.resume()
        elseif s.name == "options" then Menu.go(Menu.optionsBack or "title")
        elseif s.name == "select" then Menu.go("title")
        elseif s.name == "create" or s.name == "rename" or s.name == "delete" then Menu.go("select") end
    end
end

return Menu
