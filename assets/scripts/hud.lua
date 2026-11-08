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
Hud.HUNGER = true
-- FoodStats 1.7.10: сытость 0..20, насыщение (сначала тратится оно), усталость.
Hud.saturation = 5
Hud.exhaustion = 0
local foodTimer = 0
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
        U.sprite(root, "Heart Back " .. i, "bottom", hx, y, 9 * S, 9 * S, ICONS, "heart_empty")
        local h = U.sprite(root, "Heart " .. i, "bottom", hx, y, 9 * S, 9 * S, ICONS, "heart_full")
        hearts[i] = {el = h, shown = ""}
        if Hud.HUNGER then
            U.sprite(root, "Food Back " .. i, "bottom", fx, y, 9 * S, 9 * S, ICONS, "food_empty")
            local f = U.sprite(root, "Food " .. i, "bottom", fx, y, 9 * S, 9 * S, ICONS, "food_full")
            foods[i] = {el = f, shown = ""}
        end
    end
    U.sprite(root, "XP Back", "bottom", 0, 22 * S + 1 * S, 182 * S, 5 * S, ICONS, "xp_back")
    xpFill = U.sprite(root, "XP Fill", "bottom", 0, 22 * S + 1 * S, 182 * S, 5 * S, ICONS, "xp_fill")
    local xl = U.label(root, "XP Level", "bottom", 0, 22 * S + 4 * S, 60, 18, "", 1, true)
    xl.text_color = Vec4(0.5, 1, 0.13, 1)
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
            if piece == "" then it.el.visible = false
            else
                it.el.visible = true
                it.el.sprite = prefix .. piece
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

-- Еда (FoodStats.addStats): сытость + n, насыщение + n·модификатор·2, но
-- не больше сытости. Есть можно, только пока не сыт (canEat).
function Hud.eat(n, satMod)
    if not Hud.HUNGER or Hud.food >= 20 then return false end
    Hud.food = math.min(20, Hud.food + n)
    Hud.saturation = math.min(Hud.saturation + n * (satMod or 0.3) * 2, Hud.food)
    return true
end

-- Усталость (addExhaustion): бег 0.1 на блок, ходьба 0.01, прыжок 0.2,
-- прыжок с разбега 0.8, удар 0.3, поломка блока 0.025; предел 40.
function Hud.addExhaustion(x)
    Hud.exhaustion = math.min(Hud.exhaustion + x, 40)
end

-- FoodStats.onUpdate — раз в игровой тик: усталость больше 4 съедает
-- насыщение, а когда его нет — сытость; сытость от 18 лечит сердце раз в
-- 80 тиков (ценой 3 усталости), на нуле — ранит раз в 80 тиков (Normal: до
-- последнего сердца).
function Hud.foodTick()
    if Hud.exhaustion > 4 then
        Hud.exhaustion = Hud.exhaustion - 4
        if Hud.saturation > 0 then Hud.saturation = math.max(Hud.saturation - 1, 0)
        else Hud.food = math.max(Hud.food - 1, 0) end
    end
    if Hud.food >= 18 and Hud.health > 0 and Hud.health < 20 then
        foodTimer = foodTimer + 1
        if foodTimer >= 80 then
            Hud.health = Hud.health + 1
            Hud.addExhaustion(3)
            foodTimer = 0
        end
    elseif Hud.food <= 0 then
        foodTimer = foodTimer + 1
        if foodTimer >= 80 then
            if Hud.health > 1 then Hud.damage(1) end
            foodTimer = 0
        end
    else
        foodTimer = 0
    end
end

-- Сохранение и загрузка сытости.
function Hud.saveFood()
    return {health = Hud.health, food = Hud.food, saturation = Hud.saturation, exhaustion = Hud.exhaustion}
end
function Hud.loadFood(t)
    if type(t) ~= "table" then return end
    Hud.health = t.health or Hud.health
    Hud.food = t.food or Hud.food
    Hud.saturation = t.saturation or Hud.saturation
    Hud.exhaustion = t.exhaustion or Hud.exhaustion
end
Hud.debug = false
local fps, fpsTimer, frames = 0, 0, 0
local flashTimer = 0

-- Чат — chat.lua (GuiNewChat/GuiChat); здесь — только вход для сообщений.
function Hud.chat(text) require("chat").add(text) end

function Hud.init()
    root = U.screen("HUD", 4)
    -- Прицел инвертирует то, что под ним (как в Minecraft 1.7.10:
    -- ONE_MINUS_DST_COLOR / ONE_MINUS_SRC_COLOR) — тёмный на небе, светлый
    -- в пещере, виден на любой поверхности.
    local cross = U.sprite(root, "Crosshair", "center", 0, 0, 15 * U.HUD, 15 * U.HUD, ICONS, "crosshair")
    cross.blend = "invert"

    Hud.buildIcons()
    flash = U.fill(root, "Damage Flash", "top_left", 0, 0, 10, 10, Vec4(0.8, 0, 0, 0))
    flash.stretch = "both"


    debugLabel = U.label(root, "Debug", "top_left", 8, 8, 600, 160, "", 1.1)
    debugLabel.visible = false

    local lp = U.screen("Loading", 50)
    local bg = U.fill(lp, "Loading Back", "top_left", 0, 0, 10, 10, Vec4(0.10, 0.11, 0.13, 1))
    bg.stretch = "both"
    U.label(lp, "Loading Title", "center", 0, -20, 500, 40, "SAGE Craft", 2.6, true)
    local sub = U.label(lp, "Loading Text", "center", 0, 24, 500, 24, "Generating world…", 1.3, true)
    sub.text_color = U.MUTED
    loadPanel = lp
end

-- Прятать полоски и прицел, пока открыто главное меню.
function Hud.setVisible(on)
    if root then U.show(root, on) end
end

function Hud.loading(on)
    if loadPanel then U.show(loadPanel, on) end
end

function Hud.toggleDebug()
    Hud.debug = not Hud.debug
    debugLabel.visible = Hud.debug
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
    -- Сытость и лечение — по игровым тикам (FoodStats.onUpdate).
    Hud.foodAcc = (Hud.foodAcc or 0) + dt
    local n = 0
    while Hud.foodAcc >= 0.05 and n < 5 do
        Hud.foodAcc, n = Hud.foodAcc - 0.05, n + 1
        Hud.foodTick()
    end
    setRow(hearts, Hud.health, "heart")
    if Hud.HUNGER then setRow(foods, Hud.food, "food") end
    local need = 10 + Hud.level * 2
    -- Заливка — кусок картинки той же ширины, что доля опыта.
    local frac = Hud.xp / need
    local w = math.max(1, math.floor(182 * frac))
    xpFill.place((-182 + w) / 2 * U.HUD, 22 * U.HUD + 1 * U.HUD, w * U.HUD, 5 * U.HUD)
    xpFill.sprite = {0, 138, w * 2, 10}
    xpLabel.text = Hud.level > 0 and tostring(Hud.level) or ""
    flashTimer = math.max(0, flashTimer - dt)
    flash.color = Vec4(0.8, 0, 0, flashTimer)

    if Hud.debug then
        local P = require "player"
        local Sky = require "sky"
        local C = require "chunks"
        local n, secs = 0, 0
        for _ in pairs(W.chunks) do n = n + 1 end
        for _ in pairs(C.objects) do secs = secs + 1 end
        local bx, by, bz = math.floor(P.pos.x), math.floor(P.pos.y), math.floor(P.pos.z)
        debugLabel.text = string.format(
            "SAGE Craft   %.0f fps\nXYZ: %.2f / %.2f / %.2f\nBlock: %d %d %d   chunk %d %d\n" ..
            "Light: sky %d, block %d   day %.2f\nFacing: %.1f / %.1f\nChunks %d, sections %d, view %d\nTime of day %.3f\nBiome: %s",
            fps, P.pos.x, P.pos.y, P.pos.z, bx, by, bz, bx // 16, bz // 16,
            W.sky(bx, by + 1, bz), W.blockLight(bx, by + 1, bz), Sky.daylight,
            P.yaw, P.pitch, n, secs, C.radius, Sky.time, select(2, require("gen").column(bx, bz)))
    end
end

return Hud
