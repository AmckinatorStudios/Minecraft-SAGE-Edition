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

-- Ячейка предмета: невидимая основа (рамку рисует картинка окна), иконка, число
-- и полоска прочности.
function U.slot(parent, name, anchor, x, y, size)
    local bg = U.base(parent, name, anchor, x, y, size, size)
    local icon = ui.image{parent = bg, name = name .. " Icon", anchor = "center", w = size, h = size,
                          image = A.ICONS, color = Vec4(1, 1, 1, 0)}
    -- Число — в правом нижнем углу САМОЙ ячейки, выровнено по её краю: рамка
    -- шире ячейки с текстом от левого края уводила его на соседнюю ячейку.
    local count = U.label(bg, name .. " Count", "center", 0, 0, size, size, "", 1, false)
    count.align, count.valign, count.pad = "right", "bottom", 0
    -- Полоска прочности (RenderItem.renderItemOverlayIntoGUI) — поверх числа, в
    -- пикселях иконки 16×16: чёрная подложка 13×2 в (2, 13), тёмная полоса
    -- 12×1 и цветная длиной j поверх неё.
    local px = size / 16
    local function quad(nm, w, h)
        local q = U.fill(bg, name .. " " .. nm, "top_left", 2 * px, 13 * px, w * px, h * px, Vec4(0, 0, 0, 1))
        q.visible = false
        return q
    end
    local barBack = quad("Durability Back", 13, 2)
    local barTrack = quad("Durability Track", 12, 1)
    local barFill = quad("Durability", 13, 1)
    return {bg = bg, icon = icon, count = count, shown = -1, size = size, px = px,
            barBack = barBack, barTrack = barTrack, barFill = barFill}
end

-- Полоска прочности оригинала по износу damage из maxDamage:
-- j = round(13 − damage·13/max) пикселей, k = round(255 − damage·255/max);
-- цвет полосы — (255 − k, k, 0): от зелёного через жёлтый к красному;
-- дорожка под ней — ((255 − k)/4, 63, 0). Пусто (nil), если предмет цел.
function U.durability(damage, maxDamage)
    if not damage or damage <= 0 or not maxDamage or maxDamage <= 0 then return nil end
    local function round(v) return math.floor(v + 0.5) end
    local j = round(13 - damage * 13 / maxDamage)
    local k = round(255 - damage * 255 / maxDamage)
    return j, Vec4((255 - k) / 255, k / 255, 0, 1), Vec4(((255 - k) // 4) / 255, 63 / 255, 0, 1)
end

-- Самопроверка (--gencheck, строка DURABILITYCHECK): числа оригинала — у
-- деревянной кирки (maxDamage 59) после 30 ударов полоса 6 пикселей цвета
-- (130, 125, 0) на дорожке (32, 63, 0); новая — без полосы; на последнем
-- издыхании — красная.
function U.durabilitySelfCheck()
    local j, c, t = U.durability(30, 59)
    local mid = j == 6 and math.floor(c.x * 255 + 0.5) == 130 and math.floor(c.y * 255 + 0.5) == 125
        and math.floor(t.x * 255 + 0.5) == 32 and math.floor(t.y * 255 + 0.5) == 63
    local fresh = U.durability(0, 59) == nil
    local j2, c2 = U.durability(58, 59)
    local worn = j2 == 0 and math.floor(c2.x * 255 + 0.5) == 251 and math.floor(c2.y * 255 + 0.5) == 4
    local j3, c3 = U.durability(1, 59)
    local new = j3 == 13 and c3.y > 0.98
    local ok = mid and fresh and worn and new
    return string.format("DURABILITYCHECK: %s середина=%s цела=%s изношена=%s новая=%s", ok and "PASS" or "FAIL",
        tostring(mid), tostring(fresh), tostring(worn), tostring(new))
end

-- Показать в ячейке стопку {id, n, wear} (или пусто).
function U.setSlot(s, stack)
    local id = stack and stack.id or 0
    local n = stack and stack.n or 0
    local wear = stack and stack.wear or 0
    local key = id * 1000 + n + wear * 1000000
    if s.shown == key then return end
    s.shown = key
    -- Износ: у предмета uses — сколько раз он служит; maxDamage оригинала на
    -- единицу меньше (ломается, когда урон его превысил).
    local d = id ~= 0 and require("blocks").byId[id]
    local j, color, track = U.durability(wear, d and d.uses and d.uses - 1)
    s.barBack.visible, s.barTrack.visible, s.barFill.visible = j ~= nil, j ~= nil, j ~= nil and j > 0
    if j then
        s.barTrack.color = track
        s.barFill.color = color
        if j > 0 then s.barFill.place(2 * s.px, 13 * s.px, j * s.px, s.px) end
    end
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
