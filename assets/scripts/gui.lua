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
-- который рисует левую и правую половины). Вид при наведении и недоступная
-- кнопка — виды состояний движка (hover, disabled): движок сам меняет кусок
-- листа и цвет надписи, скрипт только спрашивает, нажали ли (el.clicked).
-- Поле ввода — ui.field движка (символы, курсор, фокус).
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

-- Тень надписи — тот же цвет вчетверо темнее (как у FontRenderer).
local function shade(c) return Vec4(c.x * 0.25, c.y * 0.25, c.z * 0.25, c.w) end

-- Размер экрана в пикселях интерфейса — с округлением ВВЕРХ: при нечётном
-- размере окна последний пиксель интерфейса виден наполовину, и фон «во
-- весь экран», посчитанный вниз, оставлял у края полосу в пиксель.
function Gui.size()
    local s = ui.size()
    return math.ceil(s.x / S), math.ceil(s.y / S)
end

-- Поставить элемент в пиксели интерфейса от левого верхнего угла.
local function place(el, x, y, w, h)
    el.anchor = "top_left"
    el.place(x * S, y * S, w * S, h * S)
end
Gui.place = place

-- Надпись. align: "left" | "center" | "right"; у center/right x — точка
-- центра/правого края (как drawCenteredString).
function Gui.label(parent, text, align, color)
    local el = U.label(parent, "Gui Text", "top_left", 0, 0, 10, 10, text, 1, align == "center")
    el.text_color = color or Gui.WHITE
    el.shadow_color = shade(el.text_color)
    if align == "right" then el.align = "right" end
    local l = {el = el, align = align or "left"}
    function l.place(x, y, w)
        w = w or 400
        local left = x
        if l.align == "center" then left = x - w / 2 elseif l.align == "right" then left = x - w end
        place(el, left, y, w, 9)
    end
    function l.set(t) el.text = t end
    function l.color(c)
        el.text_color = c
        el.shadow_color = shade(c)
    end
    return l
end

-- Кнопка 1.7.10: 20 пикселей в высоту, верх букв — на 6-м пикселе
-- (drawCenteredString с y + (20 - 8) / 2). Движок ставит по центру тело букв
-- (7 пикселей шрифта), поэтому снизу снят один экранный пиксель: буквы
-- встают ровно туда, где их рисует оригинал. Девятина: края 2×2 пикселя
-- оригинала (×2 у набора 32×) — в листе у куска; пиксель набора — 1 экранный
-- (S / 2).
local function widget(parent, name, text, normal, hover)
    return ui.button{parent = parent, name = name, w = 200 * S, h = 20 * S,
        image = WIDGETS, sprite = normal, pixel = S / 2,
        hover = {sprite = hover}, pressed = {sprite = hover}, disabled = {sprite = "button_disabled"},
        text = text, font = U.FONT, size = 16, text_color = Gui.BUTTON, shadow_offset = 2,
        hover_text_color = Gui.HOVER, disabled_text_color = Gui.GRAY, text_margin = {0, 0, 0, 2}}
end

function Gui.button(parent, text, onClick)
    local el = widget(parent, "Gui Button", text, "button", "button_hover")
    local b = {el = el, enabled = true, onClick = onClick}
    function b.place(x, y, w, h) place(el, x, y, w, h or 20) end
    function b.set(t) el.text = t end
    function b.enable(on)
        b.enabled = on
        el.enabled = on
    end
    function b.update()
        if b.enabled and el.clicked and b.onClick then
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
    local el = ui.field{parent = parent, name = "Gui Field", w = 200 * S, h = 20 * S,
        color = Vec4(0, 0, 0, 1), border = 1 * S, border_color = Gui.GRAY,
        text = text or "", max = maxLen or 32, font = U.FONT, size = 16, text_color = Gui.BUTTON,
        shadow_offset = 2, shadow_color = Vec4(0.22, 0.22, 0.22, 1), pad = 4 * S}
    local f = {el = el}
    function f.place(x, y, w, h) place(el, x, y, w, h or 20) end
    function f.text() return el.text end
    function f.focus() el.focused = true end
    return f
end

-- Ползунок (GuiOptionSlider): тёмная полоса и бегунок 8 пикселей, значение
-- 0..1, подпись — от format(value). Полоса — та же кнопка без смены вида,
-- бегунок — кусок «button» под надписью.
function Gui.slider(parent, value, format, onChange)
    local el = widget(parent, "Gui Slider", "", "button_disabled", "button_disabled")
    local knob = ui.image{parent = el, name = "Gui Slider Knob", w = 8 * S, h = 20 * S,
        image = WIDGETS, sprite = "button", pixel = S / 2, order = -1}
    local s = {el = el, value = value, dragging = false}
    function s.place(x, y, w)
        s.x, s.y, s.w = x, y, w
        place(el, x, y, w, 20)
        s.refresh()
    end
    function s.refresh()
        knob.place(math.floor(s.value * ((s.w or 150) - 8)) * S, 0, 8 * S, 20 * S)
        el.text = format(s.value)
    end
    function s.update()
        local mx = ui.cursor().x / S
        if el.pressed or (s.dragging and ui.mouse_down()) then
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
        el.text_color = s.dragging and Gui.HOVER or Gui.BUTTON
    end
    s.refresh()
    return s
end

-- Земляной фон экранов без мира (drawBackground): плитка 32 пикселя
-- интерфейса, затемнённая до 0x404040.
function Gui.dirt(parent, shade)
    local k = shade or 0x40 / 255
    -- Плитка своего размера: картинка 32× пикселя — 32 пикселя интерфейса
    -- (×S на экране), как у оригинала.
    local el = ui.image{parent = parent, name = "Gui Dirt", image = DIRT, fit = "tile", pixel = S,
        color = Vec4(k, k, k, 1)}
    local d = {el = el}
    function d.place(x, y, w, h) place(el, x, y, w, h) end
    return d
end

-- Сплошной прямоугольник (с градиентом сверху вниз, если задан bottom).
function Gui.rect(parent, top, bottom)
    local el = ui.panel{parent = parent, name = "Gui Rect", color = top, gradient = bottom}
    local r = {el = el}
    function r.place(x, y, w, h) place(el, x, y, w, h) end
    return r
end

-- Картинка (превью мира).
function Gui.image(parent)
    local el = ui.image{parent = parent, name = "Gui Image", w = 32, h = 32, visible = false}
    local i = {el = el}
    function i.place(x, y, w, h) place(el, x, y, w, h) end
    function i.set(name)
        if name then el.image = name; el.visible = true else el.visible = false end
    end
    return i
end

return Gui
