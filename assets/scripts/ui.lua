-- ---------------------------------------------------------------------------
-- ui.lua — маленькие строители элементов игры поверх интерфейса движка
-- (ui.screen{}, ui.image{}, ui.text{} — docs/ui.md движка).
--
-- Экран игры — элементы с якорем в центре или внизу экрана и размерами в
-- пикселях интерфейса. Ячейки предметов — картинка из листа иконок (спрайт)
-- и число в углу. Каждый строитель возвращает ЭЛЕМЕНТ движка: свойства —
-- присваиванием (el.text = "...", el.visible = false), место — el.place.
-- ---------------------------------------------------------------------------
local A = require "atlas"

local U = {}

-- Шрифт и масштаб: окна интерфейса (картинки набора текстур) рисуются
-- в WIN экранных пикселей на пиксель раскладки 256×256, панель — в HUD.
-- Шрифт — картинка ascii.png набора (сетка 16×16, ширины символов — по
-- пикселям, как у FontRenderer); порядок символов — ascii.chars рядом.
-- Движок держит шрифт-картинку на её пиксельной сетке: строка 16 становится
-- 18 (9 пикселей шрифта × 2), символ — ровно 8 × 2.
U.FONT = "assets/fonts/ascii.png"
U.WIN = 3
U.HUD = 2

U.TEXT = Vec4(0.97, 0.97, 0.95, 1)
U.MUTED = Vec4(0.66, 0.69, 0.74, 1)

-- Экран: корень во весь экран; order — кто поверх.
function U.screen(name, order)
    return ui.screen{name = name, order = order or 0}
end

-- Невидимый элемент-место (держит детей, двигается целиком).
function U.base(parent, name, anchor, x, y, w, h)
    return ui.group{parent = parent, name = name, anchor = anchor or "center", x = x, y = y, w = w, h = h}
end

-- Картинка из листа: кусок piece картинки path (описание — path.sagesheet).
function U.sprite(parent, name, anchor, x, y, w, h, path, piece)
    return ui.image{parent = parent, name = name, anchor = anchor or "center", x = x, y = y, w = w, h = h,
                    image = path, sprite = piece}
end

-- Плоская заливка без картинки (затемнение, полосы).
function U.fill(parent, name, anchor, x, y, w, h, color)
    return ui.panel{parent = parent, name = name, anchor = anchor or "center", x = x, y = y, w = w, h = h,
                    color = color}
end

-- Надпись шрифтом игры: без сглаживания, с тенью в пиксель шрифта.
-- scale — во сколько раз крупнее обычной строки (16 экранных пикселей).
function U.label(parent, name, anchor, x, y, w, h, text, scale, centered)
    return ui.text{parent = parent, name = name, anchor = anchor or "center", x = x, y = y, w = w, h = h,
                   text = text or "", font = U.FONT, size = 16 * (scale or 1),
                   align = centered and "center" or "left", pad = 8,
                   text_color = U.TEXT, shadow_offset = 2, shadow_color = Vec4(0.16, 0.16, 0.16, 1)}
end

-- Ячейка предмета: невидимая основа (рамку рисует картинка окна), иконка, число.
function U.slot(parent, name, anchor, x, y, size)
    local bg = U.base(parent, name, anchor, x, y, size, size)
    local icon = ui.image{parent = bg, name = name .. " Icon", anchor = "center", w = size, h = size,
                          image = A.ICONS, color = Vec4(1, 1, 1, 0)}
    -- Число — в правом нижнем углу САМОЙ ячейки, выровнено по её краю: рамка
    -- шире ячейки с текстом от левого края уводила его на соседнюю ячейку.
    local count = U.label(bg, name .. " Count", "center", 0, 0, size, size, "", 1, false)
    count.align, count.valign, count.pad = "right", "bottom", 0
    return {bg = bg, icon = icon, count = count, shown = -1, size = size}
end

-- Показать в ячейке стопку {id, n} (или пусто).
function U.setSlot(s, stack)
    local id = stack and stack.id or 0
    local n = stack and stack.n or 0
    local key = id * 1000 + n
    if s.shown == key then return end
    s.shown = key
    if id == 0 then
        s.icon.color = Vec4(1, 1, 1, 0)
        s.count.text = ""
        return
    end
    local x, y, w, h = A.iconRect(id)
    if x then s.icon.sprite = {x, y, w, h} end
    s.icon.color = Vec4(1, 1, 1, 1)
    s.count.text = n > 1 and tostring(n) or ""
end

-- Спрятать целиком, с детьми.
function U.show(el, on)
    if el then el.visible = on end
end

return U
