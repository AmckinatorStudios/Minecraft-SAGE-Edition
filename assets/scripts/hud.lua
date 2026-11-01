-- ---------------------------------------------------------------------------
-- hud.lua — то, что поверх мира: прицел, здоровье, экран загрузки, отладка (F3).
-- ---------------------------------------------------------------------------
local U = require "ui"
local W = require "world"

local Hud = {}

local root, cross1, cross2, loadPanel, debugLabel, healthBar, flash
Hud.health = 20
Hud.debug = false
local fps, fpsTimer, frames = 0, 0, 0
local flashTimer = 0

function Hud.init()
    root = U.screen("HUD", 4)
    local _, a = U.panel(root, "Cross H", UIAnchor.Center, 0, 0, 18, 2, Vec4(1, 1, 1, 0.85))
    local _, b = U.panel(root, "Cross V", UIAnchor.Center, 0, 0, 2, 18, Vec4(1, 1, 1, 0.85))
    a.Rounding, b.Rounding = 0, 0
    cross1, cross2 = a, b

    local hp, hpe = U.base(root, "Health", UIAnchor.BottomCenter, -110, 72, 226, 10)
    hpe.Type = UIKind.Bar
    hpe.Color = Vec4(0.1, 0.05, 0.05, 0.8)
    hpe.BarFillColor = Vec4(0.86, 0.2, 0.22, 1)
    hpe.MinValue = 0
    hpe.MaxValue = 20
    hpe.Value = 20
    healthBar = hp

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
    -- Здоровье восстанавливается само, медленно.
    Hud.regen = (Hud.regen or 0) + dt
    if Hud.regen > 4 and Hud.health < 20 then Hud.health = Hud.health + 1; Hud.regen = 0 end
    healthBar:GetUI().Value = Hud.health
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
