-- ---------------------------------------------------------------------------
-- chat.lua — чат Minecraft Java 1.7.10 (GuiNewChat + GuiChat), только текст.
--
-- Строки — снизу слева: GuiIngame сдвигает чат на (высота − 48), GuiNewChat
-- рисует от (2, 20) вверх по 9 пикселей: под каждой строкой — чёрная полоса
-- шириной chatWidth + 4 с альфой «непрозрачность / 2», текст белый с тенью.
--   ширина  = floor(280·chatWidth + 40)       (по умолчанию 320)
--   высота  = floor(160·chatHeight + 20)      (открыт 1.0 -> 180, 20 строк;
--             закрыт 0.44366196 -> 90, 10 строк); строк = высота / 9
-- Сообщение режется по ширине floor(ширина / chatScale) в пикселях шрифта
-- (ширины символов — по картинке ascii.png, как у FontRenderer): по
-- последнему пробелу, а длинное слово — по символам. Строка видна 200 тиков
-- закрытым чатом: непрозрачность ((1 − возраст/200)·10, до 1)², то есть
-- полная 180 тиков и гаснет за последние 20. Открытый чат — всё, без
-- таймера, с прокруткой. История — 100 сообщений и 100 строк.
--
-- Поле ввода (GuiChat): T, полоса 0x80000000 от (2, H−14) до (W−2, H−2),
-- текст с x = 4 без фона поля, мигающий «_», до 100 символов. Enter —
-- отправить (непустое) и закрыть, Esc — закрыть, ↑/↓ — отправленные раньше,
-- колесо и PageUp/PageDown — прокрутка. Команд нет — только переписка.
-- ---------------------------------------------------------------------------
local U = require "ui"

local C = {}

C.width = 1.0                 -- chatWidth
C.scale = 1.0                 -- chatScale
C.heightFocused = 1.0         -- chatHeightFocused
C.heightUnfocused = 0.44366196
C.opacity = 1.0               -- chatOpacity
C.name = "Player"             -- имя игрока в сообщениях: <имя> текст

local S = U.HUD
local MAX_LINES, MAX_INPUT = 100, 100
local drawn = {}              -- визуальные строки, [1] — самая новая (низ)
local messages = {}           -- исходные сообщения
local sent = {}               -- отправленное игроком (для ↑/↓)
local pending = {}
local counter, acc = 0, 0     -- updateCounter (тики)
local rows, bar, field, inputText = {}, nil, nil, nil
local open, scroll, histIdx, cursorTicks, justOpened = false, 0, 0, 0, false
local root

-- --- Ширина текста: символы шрифта-картинки ---------------------------------

local widths
local function loadWidths()
    widths = {}
    local ok, img = pcall(texture.load, U.FONT, "chat:font-widths")
    for code = 0, 255 do widths[code] = 6 end
    widths[32] = 4
    if not ok or not img or img.width < 16 then return end
    local cw = img.width // 16
    -- Строки холста — снизу вверх.
    for code = 33, 126 do
        local cx, cy = (code % 16) * cw, (code // 16) * cw
        local last = -1
        for x = cw - 1, 0, -1 do
            for y = 0, cw - 1 do
                if img.get(cx + x, img.height - 1 - (cy + y)).w > 0 then last = x; break end
            end
            if last >= 0 then break end
        end
        widths[code] = last < 0 and 0 or math.floor(0.5 + (last + 1) * 8 / cw) + 1
    end
end

function C.textWidth(s)
    if not widths then loadWidths() end
    local w = 0
    for i = 1, #s do w = w + (widths[s:byte(i)] or 6) end
    return w
end

-- listFormattedStringToWidth: по последнему пробелу, иначе по символам.
function C.wrap(s, maxw)
    if not widths then loadWidths() end
    local out = {}
    while #s > 0 do
        local w, cut, lastSpace = 0, #s, nil
        for i = 1, #s do
            local c = s:byte(i)
            if c == 32 then lastSpace = i end
            w = w + (widths[c] or 6)
            if w > maxw then cut = i - 1; break end
        end
        if cut >= #s then out[#out + 1] = s; break end
        if lastSpace and lastSpace <= cut + 1 and lastSpace > 1 then cut = lastSpace - 1 end
        if cut < 1 then cut = 1 end
        out[#out + 1] = s:sub(1, cut)
        s = s:sub(cut + 1)
        if s:sub(1, 1) == " " then s = s:sub(2) end
    end
    return out
end

-- --- Размеры ------------------------------------------------------------------

function C.widthPx() return math.floor(C.width * 280 + 40) end
local function heightPx(h) return math.floor(h * 160 + 20) end
function C.lineCount() return heightPx(open and C.heightFocused or C.heightUnfocused) // 9 end

-- --- Сообщения ----------------------------------------------------------------

-- Сообщение в чат (printChatMessage). Показывается со следующего кадра: снимок
-- экрана по F2 выходит без своей же надписи.
function C.add(text)
    pending[#pending + 1] = text
end

local function push(text)
    table.insert(messages, 1, text)
    if #messages > MAX_LINES then messages[#messages] = nil end
    local parts = C.wrap(text, math.floor(C.widthPx() / C.scale))
    for _, line in ipairs(parts) do
        table.insert(drawn, 1, {text = line, at = counter})
        -- Открытый и прокрученный чат держит место: новое не сбивает чтение.
        if open and scroll > 0 then scroll = scroll + 1 end
    end
    while #drawn > MAX_LINES do drawn[#drawn] = nil end
end

-- --- Построение -------------------------------------------------------------

function C.init()
    root = U.screen("Chat", 6)
    for i = 1, 20 do
        local bg = U.fill(root, "Chat Back " .. i, "top_left", 0, 0, 10, 10, Vec4(0, 0, 0, 0))
        local tx = U.label(root, "Chat " .. i, "top_left", 0, 0, 10, 10, "", 1)
        tx.pad = 0
        bg.visible, tx.visible = false, false
        rows[i] = {bg = bg, text = tx}
    end
    bar = U.fill(root, "Chat Input Back", "top_left", 0, 0, 10, 10, Vec4(0, 0, 0, 0x80 / 255))
    -- Поле — движка (символы, клавиши), но невидимое: текст с мигающим «_»
    -- рисует своя надпись, как GuiTextField без фона.
    field = ui.field{parent = root, name = "Chat Field", anchor = "top_left", w = 10, h = 10,
                     color = Vec4(0, 0, 0, 0), text = "", max = MAX_INPUT, font = U.FONT, size = 16,
                     text_color = Vec4(0, 0, 0, 0), shadow_color = Vec4(0, 0, 0, 0), pad = 0}
    inputText = U.label(root, "Chat Input", "top_left", 0, 0, 10, 10, "", 1)
    inputText.pad = 0
    inputText.text_color = Vec4(0xE0 / 255, 0xE0 / 255, 0xE0 / 255, 1)
    bar.visible, field.visible, inputText.visible = false, false, false
end

function C.isOpen() return open end

function C.openChat()
    if open then return end
    open, scroll, histIdx, cursorTicks, justOpened = true, 0, #sent + 1, 0, true
    field.text = ""
    field.visible, bar.visible, inputText.visible = true, true, true
    field.focused = true
    SetMouseCaptured(false)
    input.ReleaseAll()
end

local function close()
    open, scroll = false, 0
    C.justClosed = true          -- Esc этого кадра — чату, а не меню паузы
    field.focused = false
    field.text = ""
    field.visible, bar.visible, inputText.visible = false, false, false
    SetMouseCaptured(true)
    input.ReleaseAll()
end
C.close = close

local function send()
    local t = (field.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #t > 0 then
        sent[#sent + 1] = t
        if #sent > MAX_LINES then table.remove(sent, 1) end
        -- Формат — данными сообщения: «<имя> текст» собирает отправитель.
        C.add("<" .. C.name .. "> " .. t)
    end
    close()
end

local function scrollBy(n)
    local maxScroll = math.max(0, #drawn - C.lineCount())
    scroll = math.max(0, math.min(maxScroll, scroll + n))
end

-- Клавиши открытого чата; true — чат перехватил ввод.
local function keys()
    if justOpened then
        -- Буква T, которой открыли чат, в поле не попадает.
        justOpened = false
        field.text = ""
    end
    if Input.is_key_pressed("Escape") then close(); return end
    if Input.is_key_pressed("Enter") or Input.is_key_pressed("KP_Enter") then send(); return end
    if Input.is_key_pressed("Up") and histIdx > 1 then
        histIdx = histIdx - 1
        field.text = sent[histIdx]
    elseif Input.is_key_pressed("Down") and histIdx <= #sent then
        histIdx = histIdx + 1
        field.text = sent[histIdx] or ""
    end
    local page = C.lineCount() - 1
    if Input.is_key_pressed("PageUp") then scrollBy(page) end
    if Input.is_key_pressed("PageDown") then scrollBy(-page) end
    local wheel = GetScrollDelta()
    if wheel ~= 0 then
        local n = wheel > 0 and 1 or -1
        if not (Input.is_key_down("LeftShift") or Input.is_key_down("Shift")) then n = n * 7 end
        scrollBy(n)
    end
    if #(field.text or "") > MAX_INPUT then field.text = field.text:sub(1, MAX_INPUT) end
end

-- --- Каждый кадр --------------------------------------------------------------

function C.update(dt)
    if not root then return end
    C.justClosed = false
    acc = acc + dt
    while acc >= 0.05 do
        acc = acc - 0.05
        counter = counter + 1
        cursorTicks = cursorTicks + 1
    end
    for _, t in ipairs(pending) do push(t) end
    pending = {}
    if open then keys() end

    local Wsz = ui.size()
    local W, H = math.ceil(Wsz.x / S), math.ceil(Wsz.y / S)
    local width = math.ceil(C.widthPx() / C.scale)
    local opacity = C.opacity * 0.9 + 0.1
    local n = C.lineCount()
    local baseY = H - 48 + 20
    for i = 1, 20 do
        local row = rows[i]
        local line = drawn[i + scroll]
        local alpha = 0
        if line and i <= n then
            local age = counter - line.at
            if open then alpha = 1
            elseif age < 200 then
                local d = math.max(0, math.min(1, (1 - age / 200) * 10))
                alpha = d * d
            end
            alpha = alpha * opacity
        end
        local show = alpha * 255 > 3
        row.bg.visible, row.text.visible = show, show
        if show then
            local y = baseY - (i - 1) * 9
            row.bg.place(2 * S, (y - 9) * S, (width + 4) * S, 9 * S)
            row.bg.color = Vec4(0, 0, 0, alpha / 2)
            row.text.place(2 * S, (y - 8) * S, width * S, 9 * S)
            row.text.text = line.text
            row.text.text_color = Vec4(1, 1, 1, alpha)
            row.text.shadow_color = Vec4(0.25, 0.25, 0.25, alpha)
        end
    end
    if open then
        bar.place(2 * S, (H - 14) * S, (W - 4) * S, 12 * S)
        field.place(4 * S, (H - 12) * S, (W - 4) * S, 12 * S)
        -- Мигающий курсор «_» (cursorCounter / 6 % 2).
        local caret = (cursorTicks // 6) % 2 == 0 and "_" or ""
        inputText.text = (field.text or "") .. caret
        inputText.place(4 * S, (H - 10) * S, (W - 4) * S, 9 * S)
        field.focused = true
    end
end

-- Строки (для проверки): визуальные, сверху новые.
C.drawn = function() return drawn end

-- Самопроверка (--gencheck, строка CHATCHECK): перенос, размеры, затухание.
function C.selfCheck()
    local ok = C.widthPx() == 320 and heightPx(C.heightUnfocused) == 90 and heightPx(1) == 180
        and heightPx(C.heightUnfocused) // 9 == 10
    local wrapOk = true
    for _, line in ipairs(C.wrap(string.rep("word ", 39) .. "word", 320)) do
        if C.textWidth(line) > 320 or line:sub(-1) == " " or line:sub(1, 1) == " " then wrapOk = false end
    end
    local long = C.wrap(string.rep("W", 100), 320)
    local hard = #long >= 2 and C.textWidth(long[1]) <= 320 and table.concat(long) == string.rep("W", 100)
    local function fade(age) local d = math.max(0, math.min(1, (1 - age / 200) * 10)); return d * d end
    local timing = fade(179) == 1 and fade(190) < 1 and fade(190) > 0 and fade(200) == 0
    local all = ok and wrapOk and hard and timing
    return string.format("CHATCHECK: %s размеры=%s перенос=%s длинное_слово=%s затухание=%s",
        all and "PASS" or "FAIL", tostring(ok), tostring(wrapOk), tostring(hard), tostring(timing))
end

return C
