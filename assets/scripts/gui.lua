-- ---------------------------------------------------------------------------
-- gui.lua — элементы экранов в стиле Minecraft Java 1.7.10 на интерфейсе
-- движка: кнопка (GuiButton), поле ввода (GuiTextField), ползунок
-- (GuiOptionSlider), надписи, земляной фон (drawBackground), список со
-- прокруткой (GuiSlot).
--
-- Координаты — как в коде оригинала: пиксели интерфейса от левого верхнего
-- угла (ширина и высота экрана — W, H в этих пикселях); на экран — ×S.
-- Каждый элемент помнит, как ставить себя (place), и экран переставляет
-- всё при смене размера окна.
--
-- Кнопка — кусок widgets.png девятиной (края не тянутся, как у оригинала,
-- который рисует левую и правую половины), подсветка и нажатие — флагами
-- интерфейса движка (Interactive, Hovered, Clicked). Поле ввода — элемент
-- Input движка (символы, курсор, фокус).
-- ---------------------------------------------------------------------------
local U = require "ui"

local Gui = {}

local S = U.HUD
Gui.S = S
local WIDGETS = "assets/ui/widgets.png"
local DIRT = "assets/ui/options_background.png"
Gui.WHITE = Vec4(1, 1, 1, 1)
Gui.GRAY = Vec4(0xA0 / 255, 0xA0 / 255, 0xA0 / 255, 1)       -- подписи (10526880)
Gui.DARK = Vec4(0x80 / 255, 0x80 / 255, 0x80 / 255, 1)       -- вторые строки списка (8421504)
Gui.BUTTON = Vec4(0xE0 / 255, 0xE0 / 255, 0xE0 / 255, 1)     -- текст кнопки (14737632)
Gui.HOVER = Vec4(1, 1, 0xA0 / 255, 1)                         -- под курсором (16777120)
Gui.YELLOW = Vec4(1, 1, 0, 1)

-- Размер экрана в пикселях интерфейса.
function Gui.size()
    local s = UIScreenSize()
    return math.floor(s.x / S), math.floor(s.y / S)
end

local function place(e, x, y, w, h)
    e.Anchor = UIAnchor.TopLeft
    e.Pivot = Vec2(0, 0)
    e.Position = Vec2(x * S, y * S)
    e.Size = Vec2(w * S, h * S)
end
Gui.place = place

-- Надпись. align: "left" | "center" | "right"; у center/right x — точка
-- центра/правого края (как drawCenteredString).
function Gui.label(parent, text, align, color)
    local obj, e = U.label(parent, "Gui Text", UIAnchor.TopLeft, 0, 0, 10, 10, text, 1, align == "center")
    e.TextColor = color or Gui.WHITE
    e.TextShadowColor = Vec4(e.TextColor.x * 0.25, e.TextColor.y * 0.25, e.TextColor.z * 0.25, e.TextColor.w)
    if align == "right" then e.TextAlign = "end" end
    local l = {obj = obj, e = e, align = align or "left"}
    function l.place(x, y, w)
        w = w or 400
        local left = x
        if l.align == "center" then left = x - w / 2 elseif l.align == "right" then left = x - w end
        place(e, left, y, w, 9)
    end
    function l.set(t) e.Text = t end
    function l.color(c)
        e.TextColor = c
        e.TextShadowColor = Vec4(c.x * 0.25, c.y * 0.25, c.z * 0.25, c.w)
    end
    return l
end

-- Кнопка 1.7.10: 20 пикселей в высоту, надпись по центру.
function Gui.button(parent, text, onClick)
    local obj, e = U.base(parent, "Gui Button", UIAnchor.TopLeft, 0, 0, 200, 20)
    e.Type = UIKind.Image
    e.Color = Gui.WHITE
    SetUISpriteNamed(obj, WIDGETS, "button", true)
    -- Девятина: края 2×2 пикселя оригинала (×2 у набора 32×), пиксель набора — 1 экранный.
    SetUISlice(obj, 4, 4, 4, 6, S / 2)
    e.Interactive = true
    local _, le = U.label(obj, "Gui Button Text", UIAnchor.Center, 0, 0, 200, 20, text, 1, true)
    le.TextVAlign = "center"
    le.TextColor = Gui.BUTTON
    local b = {obj = obj, e = e, label = le, enabled = true, onClick = onClick, hover = nil}
    function b.place(x, y, w, h)
        place(e, x, y, w, h or 20)
        le.Anchor = UIAnchor.Center
        le.Position = Vec2(0, -1 * S)
        le.Size = Vec2(w * S, (h or 20) * S)
    end
    function b.set(t) le.Text = t end
    function b.enable(on)
        b.enabled = on
        e.Enabled = on
        b.hover = nil
    end
    function b.update()
        local over = b.enabled and e.Hovered
        if over ~= b.hover then
            b.hover = over
            SetUISpriteNamed(obj, WIDGETS, not b.enabled and "button_disabled" or (over and "button_hover" or "button"), true)
            SetUISlice(obj, 4, 4, 4, 6, S / 2)
            le.TextColor = not b.enabled and Gui.GRAY or (over and Gui.HOVER or Gui.BUTTON)
        end
        if b.enabled and e.Clicked and b.onClick then
            require("sounds").click()
            b.onClick()
            return true
        end
        return false
    end
    return b
end

-- Поле ввода (GuiTextField): чёрное с серой рамкой в пиксель, текст E0E0E0.
function Gui.field(parent, text, maxLen)
    local obj, e = U.base(parent, "Gui Field", UIAnchor.TopLeft, 0, 0, 200, 20)
    e.Type = UIKind.Input
    e.Color = Vec4(0, 0, 0, 1)
    e.Rounding = 0
    e.BorderThickness = 1 * S
    e.BorderColor = Gui.GRAY
    e.Text = text or ""
    e.MaxLength = maxLen or 32
    e.Font = U.FONT
    e.FontFilter = "nearest"
    e.FontPixelHeight = 18
    e.TextColor = Gui.BUTTON
    e.TextShadowOffset = Vec2(2, 2)
    e.TextShadowColor = Vec4(0.22, 0.22, 0.22, 1)
    e.TextVAlign = "center"
    e.PadX = 4 * S
    e.Interactive = true
    local f = {obj = obj, e = e}
    function f.place(x, y, w, h) place(e, x, y, w, h or 20) end
    function f.text() return e.Text end
    function f.focus() e.Focused = true end
    return f
end

-- Ползунок (GuiOptionSlider): тёмная полоса и бегунок 8 пикселей, значение
-- 0..1, подпись — от format(value).
function Gui.slider(parent, value, format, onChange)
    local obj, e = U.base(parent, "Gui Slider", UIAnchor.TopLeft, 0, 0, 150, 20)
    e.Type = UIKind.Image
    e.Color = Gui.WHITE
    SetUISpriteNamed(obj, WIDGETS, "button_disabled", true)
    SetUISlice(obj, 4, 4, 4, 6, S / 2)
    e.Interactive = true
    local ho, he = U.base(obj, "Gui Slider Knob", UIAnchor.TopLeft, 0, 0, 8, 20)
    he.Type = UIKind.Image
    he.Color = Gui.WHITE
    SetUISpriteNamed(ho, WIDGETS, "button", true)
    SetUISlice(ho, 4, 4, 4, 6, S / 2)
    local _, le = U.label(obj, "Gui Slider Text", UIAnchor.Center, 0, 0, 150, 20, "", 1, true)
    le.TextVAlign = "center"
    le.TextColor = Gui.BUTTON
    local s = {obj = obj, e = e, value = value, dragging = false}
    function s.place(x, y, w)
        s.x, s.y, s.w = x, y, w
        place(e, x, y, w, 20)
        le.Size = Vec2(w * S, 20 * S)
        le.Position = Vec2(0, -1 * S)
        s.refresh()
    end
    function s.refresh()
        he.Anchor = UIAnchor.TopLeft
        he.Pivot = Vec2(0, 0)
        he.Position = Vec2(math.floor(s.value * ((s.w or 150) - 8)) * S, 0)
        he.Size = Vec2(8 * S, 20 * S)
        le.Text = format(s.value)
    end
    function s.update()
        local c = UICursor()
        local mx = c.x / S
        if e.Pressed or (s.dragging and UIMouseDown()) then
            if not s.dragging then require("sounds").click() end
            s.dragging = true
            local v = math.max(0, math.min(1, (mx - s.x - 4) / (s.w - 8)))
            if v ~= s.value then
                s.value = v
                s.refresh()
                if onChange then onChange(v) end
            end
        else
            s.dragging = false
        end
        le.TextColor = (e.Hovered or s.dragging) and Gui.HOVER or Gui.BUTTON
    end
    return s
end

-- Земляной фон экранов без мира (drawBackground): плитка 32 пикселя
-- интерфейса, затемнённая до 0x404040.
function Gui.dirt(parent, shade)
    local obj, e = U.base(parent, "Gui Dirt", UIAnchor.TopLeft, 0, 0, 10, 10)
    e.Type = UIKind.Image
    SetUIImage(obj, DIRT, true)
    -- Плитка своего размера: картинка 32× пикселя — 32 пикселя интерфейса
    -- (×S на экране), как у оригинала.
    e.Fit = "tile"
    e.PixelScale = S
    local k = shade or 0x40 / 255
    e.Color = Vec4(k, k, k, 1)
    local d = {obj = obj, e = e}
    function d.place(x, y, w, h) place(e, x, y, w, h) end
    return d
end

-- Сплошной прямоугольник (с градиентом сверху вниз, если задан bottom).
function Gui.rect(parent, top, bottom)
    local obj, e = U.fill(parent, "Gui Rect", UIAnchor.TopLeft, 0, 0, 10, 10, top)
    if bottom then e.GradientColor = bottom end
    local r = {obj = obj, e = e}
    function r.place(x, y, w, h) place(e, x, y, w, h) end
    return r
end

-- Картинка (превью мира).
function Gui.image(parent)
    local obj, e = U.base(parent, "Gui Image", UIAnchor.TopLeft, 0, 0, 32, 32)
    e.Type = UIKind.Image
    e.Color = Gui.WHITE
    local i = {obj = obj, e = e}
    function i.place(x, y, w, h) place(e, x, y, w, h) end
    function i.set(name) if name then SetUIImage(obj, name, true); U.show(obj, true) else U.show(obj, false) end end
    return i
end

return Gui
