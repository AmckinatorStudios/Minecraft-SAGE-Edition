-- ---------------------------------------------------------------------------
-- ui.lua — маленькие строители элементов интерфейса поверх UI движка.
--
-- Экран игры — элементы с якорем в центре или внизу экрана и размерами в
-- пикселях интерфейса. Ячейки предметов — картинка из листа иконок (спрайт)
-- и число в углу.
-- ---------------------------------------------------------------------------
local A = require "atlas"

local U = {}

-- Шрифт и масштаб: окна интерфейса (картинки набора текстур) рисуются
-- в WIN экранных пикселей на пиксель раскладки 256×256, панель — в HUD.
U.FONT = "assets/fonts/Minecraftia-Regular.ttf"
U.WIN = 3
U.HUD = 2

U.INK = Vec4(0.06, 0.07, 0.09, 0.82)
U.SLOT = Vec4(0.16, 0.17, 0.20, 0.92)
U.SLOT_HI = Vec4(0.95, 0.95, 0.98, 1)
U.LINE = Vec4(0.36, 0.38, 0.44, 1)
U.TEXT = Vec4(0.97, 0.97, 0.95, 1)
U.MUTED = Vec4(0.66, 0.69, 0.74, 1)
U.ACCENT = Vec4(0.42, 0.86, 0.55, 1)

function U.screen(name, order)
    local obj = SpawnObject(name)
    local e = obj:AddUI()
    e.Anchor = UIAnchor.TopLeft
    e.Position = Vec2(0, 0)
    e.Stretch = UIStretch.Both
    e.Color = Vec4(0, 0, 0, 0)
    SetUICanvas(obj, {order = order or 0})
    return obj, e
end

function U.base(parent, name, anchor, x, y, w, h)
    local obj = SpawnObject(name)
    local e = obj:AddUI()
    e.Anchor = anchor or UIAnchor.Center
    e.Position = Vec2(x, y)
    e.Size = Vec2(w, h)
    if parent then obj:SetParent(parent) end
    return obj, e
end

-- Картинка из листа: кусок name картинки path (описание — path.sagesheet).
function U.sprite(parent, name, anchor, x, y, w, h, path, piece)
    local obj, e = U.base(parent, name, anchor, x, y, w, h)
    e.Type = UIKind.Image
    e.Color = Vec4(1, 1, 1, 1)
    SetUISpriteNamed(obj, path, piece, true)
    return obj, e
end

-- Плоская заливка без картинки (затемнение, полосы).
function U.fill(parent, name, anchor, x, y, w, h, color)
    local obj, e = U.base(parent, name, anchor, x, y, w, h)
    e.Type = UIKind.Panel
    e.Color = color
    e.Rounding = 0
    return obj, e
end

-- Надпись шрифтом игры: без сглаживания, с тенью в пиксель шрифта.
function U.label(parent, name, anchor, x, y, w, h, text, scale, centered)
    local obj, e = U.base(parent, name, anchor, x, y, w, h)
    e.Type = UIKind.Label
    e.Text = text or ""
    e.Font = U.FONT
    e.FontFilter = "nearest"
    e.FontPixelHeight = math.floor(8 * (scale or 1) + 0.5) * 2
    e.TextCentered = centered or false
    e.TextColor = U.TEXT
    e.TextShadowOffset = Vec2(2, 2)
    e.TextShadowColor = Vec4(0.16, 0.16, 0.16, 1)
    return obj, e
end

-- Ячейка предмета: подложка, иконка, число. Возвращает таблицу частей.
-- Ячейка предмета: невидимая основа (рамку рисует картинка окна), иконка, число.
function U.slot(parent, name, anchor, x, y, size)
    local bg, bge = U.base(parent, name, anchor, x, y, size, size)
    bge.Type = UIKind.Panel
    bge.Color = Vec4(1, 1, 1, 0)
    local ic, ice = U.base(bg, name .. " Icon", UIAnchor.Center, 0, 0, size, size)
    ice.Type = UIKind.Image
    ice.Color = Vec4(1, 1, 1, 1)
    SetUIImage(ic, A.ICONS, true)
    -- Число — в правом нижнем углу САМОЙ ячейки, выровнено по её краю: рамка
    -- шире ячейки с текстом от левого края уводила его на соседнюю ячейку.
    local cnt, cnte = U.label(bg, name .. " Count", UIAnchor.Center, 0, 0, size, size, "", 1, false)
    cnte.TextAlign = "end"
    cnte.TextVAlign = "end"
    cnte.PadX = 0
    local s = {bg = bg, bge = bge, icon = ic, icone = ice, count = cnt, counte = cnte, shown = -1, size = size}
    return s
end

-- Показать в ячейке стопку {id, n} (или пусто).
function U.setSlot(s, stack)
    local id = stack and stack.id or 0
    local n = stack and stack.n or 0
    local key = id * 1000 + n
    if s.shown == key then return end
    s.shown = key
    if id == 0 then
        s.icone.Color = Vec4(1, 1, 1, 0)
        s.counte.Text = ""
        return
    end
    local x, y, w, h = A.iconRect(id)
    if x then SetUISprite(s.icon, x, y, w, h) end
    s.icone.Color = Vec4(1, 1, 1, 1)
    s.counte.Text = n > 1 and tostring(n) or ""
end

-- Спрятать целиком, с детьми: Visible прячет только сам элемент (место в
-- раскладке он держит), Active выключает его вместе с поддеревом.
function U.show(obj, on)
    local e = obj:GetUI()
    if e then e.Active = on end
end

return U
