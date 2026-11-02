-- ---------------------------------------------------------------------------
-- menu.lua — главное меню: заголовок, жёлтая надпись, две кнопки.
--
-- Раскладка — как у титульного экрана 1.7 в пикселях интерфейса (×S):
-- заголовок сверху, надпись под углом у его правого края, кнопки 200×20 по
-- центру. Кнопки — картинки набора текстур (widgets.png: обычная и под
-- курсором), без своих рисунков. За меню — живой мир с медленно
-- вращающейся камерой (game.lua).
--
-- Заголовок «SAGE CRAFT» собирается кодом в стиле каменных букв: каждый
-- «пиксель» буквы — кусок текстуры камня набора, с тёмным торцом вниз-вправо
-- и чёрным контуром. Логотип Minecraft из набора (gui/title/minecraft.png) —
-- чужой товарный знак, в игру он не ставится.
-- ---------------------------------------------------------------------------
local U = require "ui"

local Menu = {}

Menu.active = false
Menu.started = false            -- игра уже шла: первая кнопка — «Back to Game»

local WIDGETS = "assets/ui/widgets.png"
local S = 2                     -- пикселей экрана на пиксель интерфейса
local root, buttons, splash
local t = 0

local SPLASHES = {"Now with furnaces!", "Made with SAGE!", "Cubes everywhere!", "Iron found!",
                  "Torches shine at 14!", "No garbage!"}

-- Буквы 5×7 (сверху вниз). Только те, что нужны заголовку.
local GLYPHS = {
    S = {".####", "#....", "#....", ".###.", "....#", "....#", "####."},
    A = {".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"},
    G = {".####", "#....", "#....", "#.###", "#...#", "#...#", ".###."},
    E = {"#####", "#....", "#....", "####.", "#....", "#....", "#####"},
    C = {".####", "#....", "#....", "#....", "#....", "#....", ".####"},
    R = {"####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"},
    F = {"#####", "#....", "#....", "####.", "#....", "#....", "#...."},
    T = {"#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."},
    [" "] = {".....", ".....", ".....", ".....", ".....", ".....", "....."},
}

-- Текстура заголовка: CELL пикселей на клетку буквы, торец DEPTH.
local CELL, DEPTH = 6, 3
local function buildLogo(text)
    local stone = texture.load("assets/textures/blocks/stone.png", "menu_stone")
    local cols = #text * 6 - 1
    local W, H = cols * CELL + DEPTH + 2, 7 * CELL + DEPTH + 2
    local img = texture("sagecraft_logo", W, H)
    img.nearest = true
    img.fill(function() return Vec4(0, 0, 0, 0) end)
    local filled = {}
    local function put(x, y, c)               -- y — сверху вниз
        img.set(x, H - 1 - y, c)
        filled[y * W + x] = true
    end
    local sw, sh = stone.width, stone.height
    local function stoneAt(x, y, k)
        local c = stone.get(x % sw, (sh - 1) - (y % sh))
        return Vec4(math.min(1, c.x * k), math.min(1, c.y * k), math.min(1, c.z * k), 1)
    end
    local cells = {}
    for i = 1, #text do
        local g = GLYPHS[text:sub(i, i)] or GLYPHS[" "]
        for r = 1, 7 do
            for c = 1, 5 do
                if g[r]:sub(c, c) == "#" then cells[#cells + 1] = {(i - 1) * 6 + c - 1, r - 1} end
            end
        end
    end
    -- Торцы — сначала, лицевая сторона ложится поверх.
    for d = DEPTH, 1, -1 do
        for _, cell in ipairs(cells) do
            local x0, y0 = 1 + cell[1] * CELL + d, 1 + cell[2] * CELL + d
            for y = 0, CELL - 1 do
                for x = 0, CELL - 1 do put(x0 + x, y0 + y, stoneAt(x0 + x, y0 + y, 0.42)) end
            end
        end
    end
    for _, cell in ipairs(cells) do
        local x0, y0 = 1 + cell[1] * CELL, 1 + cell[2] * CELL
        for y = 0, CELL - 1 do
            for x = 0, CELL - 1 do
                -- Сверху светлее, к низу темнее: камень освещён сверху.
                local k = 1.25 - 0.35 * ((cell[2] * CELL + y) / (7 * CELL))
                put(x0 + x, y0 + y, stoneAt(x0 + x, y0 + y, k))
            end
        end
    end
    -- Чёрный контур по краю всей фигуры.
    local edge = {}
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            if not filled[y * W + x] then
                for _, o in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                    local nx, ny = x + o[1], y + o[2]
                    if nx >= 0 and ny >= 0 and nx < W and ny < H and filled[ny * W + nx] then
                        edge[#edge + 1] = {x, y}
                        break
                    end
                end
            end
        end
    end
    for _, e in ipairs(edge) do img.set(e[1], H - 1 - e[2], Vec4(0, 0, 0, 1)) end
    img.apply()
    return "sagecraft_logo", W, H
end

local function button(name, y, text, onClick)
    local obj, e = U.sprite(root, "Menu " .. name, UIAnchor.Center, 0, y * S, 200 * S, 20 * S, WIDGETS, "button")
    local _, le = U.label(obj, "Menu " .. name .. " Text", UIAnchor.Center, 0, -1, 200 * S, 20 * S, text, 1, true)
    le.TextVAlign = "center"
    local b = {obj = obj, e = e, label = le, x = 0, y = y * S, w = 200 * S, h = 20 * S, onClick = onClick, hover = false}
    buttons[#buttons + 1] = b
    return b
end

function Menu.init()
    root = U.screen("Main Menu", 60)
    local _, dim = U.fill(root, "Menu Dim", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0, 0, 0, 0.3))
    dim.Stretch = UIStretch.Both
    local logo, w, h = buildLogo("SAGE CRAFT")
    -- Заголовок шириной как у оригинала (~274 пикселя интерфейса).
    local scale = 274 / w
    local lo, le = U.base(root, "Menu Logo", UIAnchor.TopCenter, 0, 30 * S, w * scale * S, h * scale * S)
    le.Type = UIKind.Image
    le.Color = Vec4(1, 1, 1, 1)
    SetUIImage(lo, logo, true)
    local _, sp = U.label(root, "Menu Splash", UIAnchor.TopCenter, 105 * S, 64 * S, 160 * S, 20 * S,
                          SPLASHES[math.random(#SPLASHES)], 1.6, true)
    sp.TextVAlign = "center"
    sp.TextColor = Vec4(1, 1, 0, 1)
    sp.TextShadowColor = Vec4(0.25, 0.25, 0, 1)
    sp.Rotation = -20
    splash = sp
    Menu.splashScale = sp.TextScale
    buttons = {}
    -- Ряды кнопок — через 24 пикселя, как у оригинала (лишние ряды убраны).
    Menu.play = button("Play", -24, "Singleplayer", function() Menu.close() end)
    button("Quit", 0, "Quit Game", function() game.Quit() end)
    U.show(root, false)
end

function Menu.open()
    Menu.active = true
    U.show(root, true)
    Menu.play.label.Text = Menu.started and "Back to Game" or "Singleplayer"
    SetMouseCaptured(false)
    require("hud").setVisible(false)
    require("inventory").setHudVisible(false)
end

function Menu.close()
    Menu.active = false
    Menu.started = true
    U.show(root, false)
    SetMouseCaptured(true)
    input.ReleaseAll()
    require("hud").setVisible(true)
    require("inventory").setHudVisible(true)
end

function Menu.update(dt)
    t = t + dt
    -- Надпись «дышит», как у оригинала.
    splash.TextScale = Menu.splashScale * (1 + math.abs(math.sin(t * 6)) * 0.08)
    local cursor = UICursor()
    local size = UIScreenSize()
    local mx, my = cursor.x - size.x / 2, cursor.y - size.y / 2
    local click = Input.is_mouse_pressed("left")
    for _, b in ipairs(buttons) do
        local over = math.abs(mx - b.x) <= b.w / 2 and math.abs(my - b.y) <= b.h / 2
        if over ~= b.hover then
            b.hover = over
            SetUISpriteNamed(b.obj, WIDGETS, over and "button_hover" or "button", true)
            b.label.TextColor = over and Vec4(1, 1, 0.63, 1) or U.TEXT
        end
        if over and click then b.onClick(); return end
    end
end

return Menu
