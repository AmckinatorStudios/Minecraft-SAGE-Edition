-- ---------------------------------------------------------------------------
-- hud.lua — то, что поверх мира: прицел, здоровье, экран загрузки, отладка (F3).
-- ---------------------------------------------------------------------------
local U = require "ui"
local W = require "world"

local Hud = {}

local root, cross1, cross2, loadPanel, debugLabel, flash
local hearts, foods, xpFill, xpLabel = {}, {}, nil, nil
local ICONS = "assets/ui/icons.png"
Hud.health = 20
Hud.food = 20
-- Голод выключен, пока в игре почти нечего есть: без полоски еды, сытость
-- не тратится, здоровье восстанавливается само. Включить — true.
Hud.HUNGER = false
Hud.xp, Hud.level = 0, 0

-- Сердца и еда — значки набора текстур (icons.png): пустая ячейка снизу и
-- полный/половинный значок поверх.
function Hud.buildIcons()
    local S = U.HUD
    local half = 91 * S
    for i = 1, 10 do
        local hx = -half + (i - 1) * 8 * S + 4.5 * S
        local fx = half - (i - 1) * 8 * S - 4.5 * S
        local y = 22 * S + 6 * S
        U.sprite(root, "Heart Back " .. i, UIAnchor.BottomCenter, hx, y, 9 * S, 9 * S, ICONS, "heart_empty")
        local h = U.sprite(root, "Heart " .. i, UIAnchor.BottomCenter, hx, y, 9 * S, 9 * S, ICONS, "heart_full")
        hearts[i] = {obj = h, shown = ""}
        if Hud.HUNGER then
            U.sprite(root, "Food Back " .. i, UIAnchor.BottomCenter, fx, y, 9 * S, 9 * S, ICONS, "food_empty")
            local f = U.sprite(root, "Food " .. i, UIAnchor.BottomCenter, fx, y, 9 * S, 9 * S, ICONS, "food_full")
            foods[i] = {obj = f, shown = ""}
        end
    end
    U.sprite(root, "XP Back", UIAnchor.BottomCenter, 0, 22 * S + 1 * S, 182 * S, 5 * S, ICONS, "xp_back")
    local xfo, xf = U.sprite(root, "XP Fill", UIAnchor.BottomCenter, 0, 22 * S + 1 * S, 182 * S, 5 * S, ICONS, "xp_fill")
    xpFill = xf
    Hud.xpFillObj = xfo
    local _, xl = U.label(root, "XP Level", UIAnchor.BottomCenter, 0, 22 * S + 4 * S, 60, 18, "", 1, true)
    xl.TextColor = Vec4(0.5, 1, 0.13, 1)
    xpLabel = xl
    Hud.xpWidth = 182 * S
end

-- Значок ряда i (1..10) при значении value (0..20): полный, половина, нет.
local function setRow(row, value, prefix)
    for i = 1, 10 do
        local v = value - (i - 1) * 2
        local piece = v >= 2 and "_full" or (v == 1 and "_half" or "")
        local it = row[i]
        if it.shown ~= piece then
            it.shown = piece
            local e = it.obj:GetUI()
            if piece == "" then e.Visible = false
            else
                e.Visible = true
                SetUISpriteNamed(it.obj, ICONS, prefix .. piece, true)
            end
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
    if not Hud.HUNGER or Hud.food >= 20 then return false end
    Hud.food = math.min(20, Hud.food + n)
    return true
end
Hud.debug = false
local fps, fpsTimer, frames = 0, 0, 0
local flashTimer = 0

function Hud.init()
    root = U.screen("HUD", 4)
    U.sprite(root, "Crosshair", UIAnchor.Center, 0, 0, 15 * U.HUD, 15 * U.HUD, ICONS, "crosshair")

    Hud.buildIcons()
    local _, fl = U.fill(root, "Damage Flash", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0.8, 0, 0, 0))
    fl.Stretch = UIStretch.Both
    flash = fl

    local _, de = U.label(root, "Debug", UIAnchor.TopLeft, 8, 8, 600, 140, "", 1.1)
    de.Visible = false
    debugLabel = de

    local lp = U.screen("Loading", 50)
    local _, bg = U.fill(lp, "Loading Back", UIAnchor.TopLeft, 0, 0, 10, 10, Vec4(0.10, 0.11, 0.13, 1))
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
    if Hud.HUNGER then
        local speed = math.sqrt(P.vel.x * P.vel.x + P.vel.z * P.vel.z)
        Hud.exhaust = (Hud.exhaust or 0) + dt * (0.01 + speed * (P.sprinting and 0.03 or 0.012))
        if Hud.exhaust >= 1 then Hud.exhaust = 0; Hud.food = math.max(0, Hud.food - 1) end
    end
    Hud.regen = (Hud.regen or 0) + dt
    if Hud.regen > 4 then
        Hud.regen = 0
        local fed = not Hud.HUNGER or Hud.food >= 18
        if fed and Hud.health < 20 then Hud.health = Hud.health + 1
        elseif Hud.HUNGER and Hud.food == 0 and Hud.health > 1 then Hud.damage(1) end
    end
    setRow(hearts, Hud.health, "heart")
    if Hud.HUNGER then setRow(foods, Hud.food, "food") end
    local need = 10 + Hud.level * 2
    -- Заливка — кусок картинки той же ширины, что доля опыта.
    local frac = Hud.xp / need
    local w = math.max(1, math.floor(182 * frac))
    xpFill.Size = Vec2(w * U.HUD, 5 * U.HUD)
    xpFill.Position = Vec2((-182 + w) / 2 * U.HUD, 22 * U.HUD + 1 * U.HUD)
    SetUISprite(Hud.xpFillObj, 0, 138, w * 2, 10)
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
            fps, P.pos.x, P.pos.y, P.pos.z, bx, by, bz, bx // 16, bz // 16,
            W.sky(bx, by + 1, bz), W.blockLight(bx, by + 1, bz), Sky.daylight,
            P.yaw, P.pitch, n, secs, C.radius, Sky.time)
    end
end

return Hud
