-- ---------------------------------------------------------------------------
-- game.lua — точка входа SAGE Craft. Висит на сущности «Game» в main.sage.
--
-- Порядок в кадре: ввод -> игрок (движется) -> мир (догружается вокруг
-- НОВОЙ позиции) -> взаимодействие с блоками -> небо и облака -> экран.
-- Модули — обычные require: общее состояние мира одно на все скрипты.
-- ---------------------------------------------------------------------------
local W      = require "world"
local B      = require "blocks"
local G      = require "gen"
local A      = require "atlas"
local C      = require "chunks"
local L      = require "light"
local P      = require "player"
local Sky    = require "sky"
local Clouds = require "clouds"
local Inv    = require "inventory"
local Hud    = require "hud"
local Act    = require "interact"
local Drops  = require "drops"
local Avatar = require "avatar"
local Hand   = require "hand"
local Save   = require "save"
local Auto   = require "autopilot"

local playerObj, cameraObj
local started = false
local loading = true
local thirdPerson = 0          -- 0 — глазами, 1 — сзади, 2 — спереди
local MOUSE_SENS = 0.12

local function bindControls()
    BindAction("Forward",   {"W", "UP"})
    BindAction("Back",      {"S", "DOWN"})
    BindAction("Left",      {"A", "LEFT"})
    BindAction("Right",     {"D", "RIGHT"})
    BindAction("Jump",      "SPACE")
    BindAction("Sneak",     "LEFT_SHIFT")
    BindAction("Sprint",    "LEFT_CONTROL")
    BindAction("Break",     "MOUSE_LEFT")
    BindAction("Place",     "MOUSE_RIGHT")
    BindAction("Pick",      "MOUSE_MIDDLE")
    BindAction("Inventory", "E")
    BindAction("Drop",      "Q")
    BindAction("View",      "F5")
    BindAction("Debug",     "F3")
    BindAction("Fly",       "F")
    BindAction("Skin",      "K")
    BindAction("Pause",     "ESCAPE")
    for i = 1, 9 do BindAction("Slot " .. i, tostring(i)) end
end

local function readInput()
    local inp = {forward = 0, strafe = 0}
    if IsActionDown("Forward") then inp.forward = inp.forward + 1 end
    if IsActionDown("Back") then inp.forward = inp.forward - 1 end
    if IsActionDown("Right") then inp.strafe = inp.strafe + 1 end
    if IsActionDown("Left") then inp.strafe = inp.strafe - 1 end
    inp.jump = IsActionDown("Jump")
    inp.sneak = IsActionDown("Sneak")
    inp.descend = inp.sneak
    inp.sprint = IsActionDown("Sprint")
    return inp
end

local function placeCamera()
    local ex, ey, ez = P.eye()
    -- Покачивание при ходьбе — от пройденного пути, а не от времени: стоя на
    -- месте, камера не качается.
    local bob = (P.onGround and not P.flying) and math.sin(P.walkDist * 2.2) * 0.04 or 0
    playerObj.Transform.Position = Vec3(P.pos.x, P.pos.y, P.pos.z)
    playerObj.Transform.Rotation = Vec3(0, P.yaw, 0)
    local cam = cameraObj.Transform
    if thirdPerson == 0 then
        cam.Position = Vec3(0, ey - P.pos.y + math.abs(bob), 0)
        cam.Rotation = Vec3(P.pitch, 0, bob * 20)
    else
        -- Камера отходит назад (или вперёд) по лучу взгляда, но не сквозь стену.
        local dx, dy, dz = P.lookDir()
        local sign = thirdPerson == 1 and -1 or 1
        local dist = 4
        for t = 0.2, 4, 0.1 do
            local x, y, z = ex + dx * t * sign, ey + dy * t * sign, ez + dz * t * sign
            if B.opaque[W.get(math.floor(x), math.floor(y), math.floor(z))] then dist = t - 0.3; break end
        end
        local lx, ly, lz = dx * dist * sign, dy * dist * sign, dz * dist * sign
        -- Камера — дочерняя у игрока (повёрнутого на yaw): смещение в его осях.
        local yr = math.rad(P.yaw)
        local cx = lx * math.cos(yr) - lz * math.sin(yr)
        local cz = lx * math.sin(yr) + lz * math.cos(yr)
        cam.Position = Vec3(cx, ey - P.pos.y + ly, cz)
        if thirdPerson == 1 then cam.Rotation = Vec3(P.pitch, 0, 0)
        else cam.Rotation = Vec3(-P.pitch, 180, 0) end
    end
end

local function startGame()
    bindControls()
    playerObj = FindObject("Player")
    cameraObj = FindObject("Player Camera")

    local seed = tonumber(LaunchArg("seed") or "") or 1337
    local loaded = Save.load()
    if loaded and loaded.seed then seed = loaded.seed end
    G.init(seed)
    -- Проверка генерации без игры: --gencheck (итог — строка GENCHECK в логе).
    if LaunchFlag("gencheck") then
        log(G.selfCheck())
        -- Свет факела в открытом воздухе: 14, 13, … — по одному за клетку.
        -- (Очередь волны с дырой обрывала свет через три клетки.)
        do
            local c = W.chunk(0, 0)
            L.lightChunk(c)
            local x, z = 8, 8
            local y = W.surface(x, z) + 2
            W.setId(x, y, z, B.byName.torch.id)
            L.update(x, y, z)
            local bad = 0
            for d = 0, 10 do if W.blockLight(x, y + d, z) ~= 14 - d then bad = bad + 1 end end
            log(string.format("LIGHTCHECK: %s мимо=%d (на 6 клеток выше факела %d)",
                bad == 0 and "PASS" or "FAIL", bad, W.blockLight(x, y + 6, z)))
        end
        W.chunks = {}
        local miss = Inv.checkLayout()
        log(string.format("UICHECK: %s клеток_мимо=%d", miss == 0 and "PASS" or "FAIL", miss))
    end
    A.build()
    Inv.init(loaded and loaded.inventory)
    C.edits = loaded and loaded.edits or {}
    C.radius = tonumber(LaunchArg("view") or "") or C.radius

    local sx, sy, sz = G.spawnPoint()
    if loaded and loaded.player then
        sx, sy, sz = loaded.player.x, loaded.player.y, loaded.player.z
        P.yaw, P.pitch = loaded.player.yaw or 0, loaded.player.pitch or 0
        Sky.time = loaded.time or Sky.time
    end
    P.pos.x, P.pos.y, P.pos.z = sx, sy, sz
    -- Параметры для снимков и проверки: время суток, вид, взгляд.
    if LaunchArg("time") ~= "" and LaunchArg("time") then Sky.time = tonumber(LaunchArg("time")) or Sky.time end
    thirdPerson = tonumber(LaunchArg("third") or "") or 0
    P.yaw = tonumber(LaunchArg("yaw") or "") or P.yaw
    P.pitch = tonumber(LaunchArg("pitch") or "") or P.pitch
    if LaunchFlag("kit") then
        for _, n in ipairs({"torch", "glowstone", "planks", "diamond_sword", "stone_pickaxe", "cobblestone", "log", "stick", "iron_pickaxe"}) do
            Inv.add(B.byName[n].id, B.byName[n].stack)
        end
    end
    Sky.init()
    Clouds.init(seed)
    Hud.init()
    Hand.init(cameraObj)
    Avatar.init(playerObj)
    Drops.init()
    Act.init()
    Auto.init()
    SetMouseCaptured(true)
end

function OnStart(entity)
end

-- Запуск не удался — одна понятная ошибка, а не поток следствий: без
-- интерфейса и рук каждый кадр падал бы на nil в другом модуле, а движок
-- снимал бы скрипт целиком, не сказав причины.
local failed = false

function OnUpdate(entity, dt)
    if failed then return end
    if not started then
        started = true
        local ok, err = pcall(startGame)
        if not ok then
            failed = true
            local hint = ""
            if tostring(err):find("attempt to call a nil value") then
                hint = " Плеер старше игры: нужна функция движка, которой в нём нет —"
                    .. " скачайте свежий выпуск SAGE Craft или соберите плеер из main SAGE Engine."
            end
            logError("SAGE Craft не запустился: " .. tostring(err) .. "." .. hint)
            return
        end
    end
    dt = math.min(dt, 0.1)

    if loading then
        -- Мир вокруг спавна строится до того, как игрок упадёт в пустоту.
        local busy = C.update(P.pos.x, P.pos.z, 40)
        Hud.loading(true)
        if not busy then
            loading = false
            Hud.loading(false)
            P.spawnAt(P.pos.x, P.pos.y, P.pos.z)
            -- Для снимков ночного света: факелы кольцом вокруг игрока.
            if LaunchFlag("torches") then
                for _, d in ipairs({{3, 0}, {-3, 2}, {0, -4}, {2, 4}}) do
                    local x, z = math.floor(P.pos.x) + d[1], math.floor(P.pos.z) + d[2]
                    local y = W.surface(x, z) + 1
                    Act.setBlock(x, y, z, B.byName.torch.id)
                end
            end
            if LaunchFlag("openinv") then Inv.toggleScreen(LaunchFlag("opentable") and 3 or 2) end
            -- Для снимков: рецепт кирки в сетке верстака и трещина нужной стадии.
            if LaunchFlag("craftdemo") then
                local pl, st = B.byName.planks.id, B.byName.stick.id
                Inv.grid = {{id = pl, n = 1}, {id = pl, n = 1}, {id = pl, n = 1}, nil, {id = st, n = 1}, nil, nil, {id = st, n = 1}}
            end
            if LaunchArg("crack") and LaunchArg("crack") ~= "" then Act.forceCrack = tonumber(LaunchArg("crack")) end
            -- Для снимков: выпавшее бревно и кирка перед игроком.
            if LaunchFlag("dropdemo") then
                local dx, _, dz = P.lookDir()
                local x, z = P.pos.x + dx * 3.5, P.pos.z + dz * 3.5
                Drops.spawn(B.byName.log.id, 1, x, P.pos.y + 0.6, z, 0, 0, 0)
                Drops.spawn(B.byName.stone_pickaxe.id, 1, x + dz * 0.5, P.pos.y + 0.6, z - dx * 0.5, 0, 0, 0)
            end
            if LaunchArg("slot") and LaunchArg("slot") ~= "" then Inv.select(tonumber(LaunchArg("slot"))) end
            local n = 0
            for _ in pairs(W.chunks) do n = n + 1 end
            log(string.format("SAGE Craft: мир готов, участков %d (генерация %.2f с, свет %.2f с, меши %.2f с)",
                n, C.stats.gen, C.stats.light, C.stats.mesh))
        end
        Sky.update(dt, P)
        placeCamera()
        return
    end

    if WasActionPressed("Inventory") then Inv.toggleScreen() end
    if WasActionPressed("Pause") and Inv.screenOpen then Inv.toggleScreen() end
    if Act.openTable then
        Act.openTable = false
        if not Inv.screenOpen then Inv.toggleScreen(3) end
    end
    if WasActionPressed("View") then thirdPerson = (thirdPerson + 1) % 3 end
    if WasActionPressed("Debug") then Hud.toggleDebug() end
    if WasActionPressed("Fly") then P.flying = not P.flying; P.vel.y = 0 end
    if WasActionPressed("Skin") then Avatar.nextSkin() end

    local inp
    if Inv.screenOpen then
        inp = {forward = 0, strafe = 0}
    else
        inp = Auto.active and Auto.input(dt) or readInput()
        local look = GetMouseDelta()
        if IsMouseCaptured() then P.look(look.x, look.y, MOUSE_SENS) end
        for i = 1, 9 do
            if WasActionPressed("Slot " .. i) then Inv.select(i) end
        end
        local wheel = GetScrollDelta()
        if wheel ~= 0 then Inv.select(((Inv.selected - 1 - (wheel > 0 and 1 or -1)) % 9) + 1) end
    end

    local fall = P.update(inp, dt)
    if fall and fall > 3.5 then Hud.damage(math.floor(fall - 3)) end

    C.update(P.pos.x, P.pos.z, C.budgetMs)

    if not Inv.screenOpen then Act.update(dt, Auto.active and Auto.actions() or nil) end
    Drops.update(dt)
    Sky.update(dt, P)
    Clouds.update(dt, P)
    Avatar.update(dt, P, thirdPerson ~= 0, Act.swing)
    Avatar.updatePreview()
    local held = Inv.current()
    Hand.update(dt, thirdPerson == 0, Act.swing, P.walkDist, held and held.id or 0)
    placeCamera()
    Hud.update(dt)
    Inv.update(dt)
    Save.tick(dt)
    Auto.update(dt)
end
