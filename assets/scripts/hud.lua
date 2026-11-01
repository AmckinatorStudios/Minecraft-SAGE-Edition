-- ---------------------------------------------------------------------------
-- hud.lua — то, что поверх мира: прицел, здоровье, экран загрузки, отладка (F3).
-- ---------------------------------------------------------------------------
local U = require "ui"
local W = require "world"

local Hud = {}

local root, cross1, cross2, loadPanel, debugLabel, flash
local hearts, foods, xpFill, xpLabel = {}, {}, nil, nil
Hud.health = 20
Hud.food = 20
Hud.xp, Hud.level = 0, 0
local SHEET = "sagecraft_hud"
local ICON = 18

-- Значки здоровья и сытости — свой пиксель-арт 9×9, нарисованный кодом
-- (буквы узора: # — цвет, o — контур, h — блик). Три вида: полный, половина,
-- пустой; половина — левая часть цветом, правая пустой.
local HEART = {
    ".oo...oo.",
    "o##o.o##o",
    "o#h#o###o",
    "o#######o",
    ".o#####o.",
    "..o###o..",
    "...o#o...",
    "....o....",
    ".........",
}
local FOOD = {
    "...oo....",
    "..o##o...",
    ".o#h##o..",
    "o######o.",
    "o######o.",
    ".o####o..",
    "..oooo...",
    "...o.....",
    "...o.....",
}

local function drawIcon(tex, cell, pattern, fill, part)
    local ox = cell * 16
    for y = 1, 9 do
        local row = pattern[y]
        for x = 1, 9 do
            local ch = row:sub(x, x)
            local c = Vec4(0, 0, 0, 0)
            local empty = part == "empty" or (part == "half" and x > 5)
            if ch == "o" then c = Vec4(0.08, 0.04, 0.04, 1)
            elseif ch == "#" then c = empty and Vec4(0.22, 0.2, 0.22, 1) or Vec4(fill[1], fill[2], fill[3], 1)
            elseif ch == "h" then c = empty and Vec4(0.3, 0.28, 0.3, 1) or Vec4(1, 0.9, 0.9, 1) end
            -- Строки холста — снизу вверх: верх узора кладётся в верхние строки.
            tex.set(ox + 3 + x, 14 - y, c)
        end
    end
end

function Hud.buildIcons()
    local tex = texture(SHEET, 96, 16)
    tex.nearest = true
    tex.fill(function() return Vec4(0, 0, 0, 0) end)
    local red, gold = {0.86, 0.12, 0.14}, {0.78, 0.48, 0.16}
    drawIcon(tex, 0, HEART, red, "full"); drawIcon(tex, 1, HEART, red, "half"); drawIcon(tex, 2, HEART, red, "empty")
    drawIcon(tex, 3, FOOD, gold, "full"); drawIcon(tex, 4, FOOD, gold, "half"); drawIcon(tex, 5, FOOD, gold, "empty")
    tex.apply()
    local Inv = require "inventory"
    local W2 = 9 * 46 + 8 * 4
    for i = 1, 10 do
        local h, he = U.base(root, "Heart " .. i, UIAnchor.BottomCenter, -W2 / 2 + (i - 1) * (ICON - 1) + ICON / 2, 70, ICON, ICON)
        he.Type = UIKind.Image
        he.Color = Vec4(1, 1, 1, 1)
        SetUIImage(h, SHEET, true)
        hearts[i] = {obj = h, shown = -1}
        local f, fe = U.base(root, "Food " .. i, UIAnchor.BottomCenter, W2 / 2 - (i - 1) * (ICON - 1) - ICON / 2, 70, ICON, ICON)
        fe.Type = UIKind.Image
        fe.Color = Vec4(1, 1, 1, 1)
        SetUIImage(f, SHEET, true)
        foods[i] = {obj = f, shown = -1}
    end
    local _, xb = U.panel(root, "XP Back", UIAnchor.BottomCenter, 0, 62, W2, 5, Vec4(0.05, 0.06, 0.05, 0.85))
    xb.Rounding = 1
    local _, xf = U.panel(root, "XP Fill", UIAnchor.BottomCenter, 0, 62, W2, 5, Vec4(0.5, 0.9, 0.3, 1))
    xf.Rounding = 1
    xpFill = xf
    local _, xl = U.label(root, "XP Level", UIAnchor.BottomCenter, 0, 64, 60, 18, "", 1.15, true)
    xl.TextColor = Vec4(0.6, 1, 0.4, 1)
    xpLabel = xl
    Hud.xpWidth = W2
end

-- Значок ряда i (1..10) при значении value (0..20): полный, половина, пустой.
local function setRow(row, value, base)
    for i = 1, 10 do
        local v = value - (i - 1) * 2
        local cell = v >= 2 and 0 or (v == 1 and 1 or 2)
        local it = row[i]
        if it.shown ~= cell then
            it.shown = cell
            -- Спрайт — в пикселях от левого верхнего угла листа.
            SetUISprite(it.obj, (base + cell) * 16 + 3, 2, 11, 11)
        end
    end
end

-- Опыт: за добычу руды. Уровень — каждые 10 + 2·уровень очков.
function Hud.addXp(n)
    Hud.xp = Hud.xp + n
    while Hud.xp >= 10 + Hud.level * 2 do
        Hud.xp = Hud.xp - (10 + Hud.level * 2)
        Hud.level = Hud.level + 1
    end
end

-- Еда: восстанавливает сытость.
function Hud.eat(n)
    if Hud.food >= 20 then return false end
    Hud.food = math.min(20, Hud.food + n)
    return true
end
Hud.debug = false
local fps, fpsTimer, frames = 0, 0, 0
local flashTimer = 0

function Hud.init()
    root = U.screen("HUD", 4)
    local _, a = U.panel(root, "Cross H", UIAnchor.Center, 0, 0, 18, 2, Vec4(1, 1, 1, 0.85))
    local _, b = U.panel(root, "Cross V", UIAnchor.Center, 0, 0, 2, 18, Vec4(1, 1, 1, 0.85))
    a.Rounding, b.Rounding = 0, 0
    cross1, cross2 = a, b

    Hud.buildIcons()
    local _, fl = U.panel(root, "Damage Flash", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0.8, 0, 0, 0))
    fl.Stretch = UIStretch.Both
    flash = fl

    local _, de = U.label(root, "Debug", UIAnchor.TopLeft, 8, 8, 600, 140, "", 1.1)
    de.Visible = false
    debugLabel = de

    local lp = U.screen("Loading", 50)
    local _, bg = U.panel(lp, "Loading Back", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0.10, 0.11, 0.13, 1))
    bg.Stretch = UIStretch.Both
    bg.Rounding = 0
    U.label(lp, "Loading Title", UIAnchor.Center, 0, -20, 500, 40, "SAGE Craft", 2.6, true)
    local _, sub = U.label(lp, "Loading Text", UIAnchor.Center, 0, 24, 500, 24, "Строим мир…", 1.3, true)
    sub.TextColor = U.MUTED
    loadPanel = lp
end

function Hud.loading(on)
    if loadPanel then U.show(loadPanel, on) end
end

function Hud.toggleDebug()
    Hud.debug = not Hud.debug
    debugLabel.Visible = Hud.debug
end

function Hud.damage(n)
    Hud.health = math.max(0, Hud.health - n)
    flashTimer = 0.35
    if Hud.health == 0 then
        -- Падение насмерть — возвращение на точку появления, рюкзак цел:
        -- в песочнице наказание за ошибку не должно стоить часа работы.
        local P = require "player"
        local G = require "gen"
        local x, y, z = G.spawnPoint()
        P.spawnAt(x, y + 1, z)
        Hud.health = 20
    end
end

function Hud.update(dt)
    frames = frames + 1
    fpsTimer = fpsTimer + dt
    if fpsTimer >= 0.5 then
        fps = frames / fpsTimer
        frames, fpsTimer = 0, 0
    end
    -- Сытость тратится на движение (бег и прыжки — больше), здоровье
    -- восстанавливается, только пока игрок сыт; голод отнимает здоровье.
    local P = require "player"
    local speed = math.sqrt(P.vel.x * P.vel.x + P.vel.z * P.vel.z)
    Hud.exhaust = (Hud.exhaust or 0) + dt * (0.01 + speed * (P.sprinting and 0.03 or 0.012))
    if Hud.exhaust >= 1 then Hud.exhaust = 0; Hud.food = math.max(0, Hud.food - 1) end
    Hud.regen = (Hud.regen or 0) + dt
    if Hud.regen > 4 then
        Hud.regen = 0
        if Hud.food >= 18 and Hud.health < 20 then Hud.health = Hud.health + 1
        elseif Hud.food == 0 and Hud.health > 1 then Hud.damage(1) end
    end
    setRow(hearts, Hud.health, 0)
    setRow(foods, Hud.food, 3)
    local need = 10 + Hud.level * 2
    xpFill.Size = Vec2(math.max(1, Hud.xpWidth * Hud.xp / need), 5)
    xpFill.Position = Vec2(-Hud.xpWidth / 2 + Hud.xpWidth * Hud.xp / need / 2, 62)
    xpLabel.Text = Hud.level > 0 and tostring(Hud.level) or ""
    flashTimer = math.max(0, flashTimer - dt)
    flash.Color = Vec4(0.8, 0, 0, flashTimer)

    if Hud.debug then
        local P = require "player"
        local Sky = require "sky"
        local C = require "chunks"
        local n, secs = 0, 0
        for _ in pairs(W.chunks) do n = n + 1 end
        for _ in pairs(C.objects) do secs = secs + 1 end
        local bx, by, bz = math.floor(P.pos.x), math.floor(P.pos.y), math.floor(P.pos.z)
        debugLabel.Text = string.format(
            "SAGE Craft   %.0f кадр/с\nXYZ: %.2f / %.2f / %.2f\nБлок: %d %d %d   участок %d %d\n" ..
            "Свет: небо %d, блоки %d   день %.2f\nВзгляд: %.1f / %.1f\nУчастков %d, секций %d, дальность %d\nВремя суток %.3f",
            fps, P.pos.x, P.pos.y, P.pos.z, bx, by, bz, bx >> 4, bz >> 4,
            W.sky(bx, by + 1, bz), W.blockLight(bx, by + 1, bz), Sky.daylight,
            P.yaw, P.pitch, n, secs, C.radius, Sky.time)
    end
end

return Hud
