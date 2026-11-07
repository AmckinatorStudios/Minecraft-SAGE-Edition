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
local Furn   = require "furnace"
local Menu   = require "menu"
local Fall   = require "falling"
local Music  = require "music"
local Snd    = require "sounds"
local Anim   = require "anim"
local Arrows = require "arrows"
local Map    = require "map"
local Mat    = require "mat"

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
    BindAction("Screenshot", "F2")
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
    inp.sprintPressed = WasActionPressed("Sprint")
    -- Проверка снимками: присед и ходьба без рук.
    if LaunchFlag("sneak") then inp.sneak = true; inp.descend = true end
    if LaunchFlag("walk") then inp.forward = 1 end
    return inp
end

local function placeCamera()
    local ex, ey, ez = P.eye()
    -- Глаза в приседе ниже на 0.08 — плавно, по доле приседа.
    ey = P.pos.y + P.EYE + (P.EYE_SNEAK - P.EYE) * Anim.sneak
    playerObj.Transform.Position = Vec3(P.pos.x, P.pos.y, P.pos.z)
    playerObj.Transform.Rotation = Vec3(0, P.yaw, 0)
    local cam = cameraObj.Transform
    -- Покачивание при ходьбе (setupViewBobbing) — то же, что у руки: мир
    -- рисуется с ним, значит камера стоит с обратным ему.
    local bobInv = Mat.inverseRigid(Hand.bobMatrix())
    -- Проверка снимками: камера по кругу у игрока (--orbit=градусы, 90 — справа).
    local orbit = tonumber(LaunchArg("orbit") or "")
    if orbit and thirdPerson ~= 0 then
        local m = Mat.identity()
        local r = math.rad(orbit)
        Mat.translate(m, math.sin(r) * 3.2, 1.1, math.cos(r) * 3.2)
        Mat.rotate(m, orbit, 0, 1, 0)
        Mat.rotate(m, -6, 1, 0, 0)
        Mat.applyTo(cameraObj, m)
        return
    end
    if thirdPerson == 0 then
        local m = Mat.identity()
        Mat.translate(m, 0, ey - P.pos.y, 0)
        Mat.rotate(m, P.pitch, 1, 0, 0)
        Mat.applyTo(cameraObj, Mat.mul(m, bobInv))
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
        local m = Mat.identity()
        Mat.translate(m, cx, ey - P.pos.y + ly, cz)
        if thirdPerson == 1 then Mat.rotate(m, P.pitch, 1, 0, 0)
        else Mat.rotate(m, 180, 0, 1, 0); Mat.rotate(m, -P.pitch, 1, 0, 0) end
        Mat.applyTo(cameraObj, Mat.mul(m, bobInv))
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
    A.build()
    -- Проверка генерации без игры: --gencheck (итог — строка GENCHECK в логе).
    if LaunchFlag("gencheck") then
        log(G.selfCheck())
        log(Anim.selfCheck())
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
            -- Печь: 2 руды и уголь — два слитка через 20 с; пока огонь —
            -- горящая печь, уголь (80 с) прогорел — снова обычная.
            local fx, fy, fz = 4, W.surface(4, 4) + 1, 4
            Act.setBlock(fx, fy, fz, B.byName.furnace.id)
            local f = Furn.at(fx, fy, fz)
            f.slots[1] = {id = B.byName.iron_ore.id, n = 2}
            f.slots[2] = {id = B.byName.coal.id, n = 1}
            Furn.update(0.5)
            local litOk = W.get(fx, fy, fz) == B.byName.lit_furnace.id
            for _ = 1, 50 do Furn.update(0.5) end
            local out = f.slots[3]
            local smeltOk = out and out.id == B.byName.iron_ingot.id and out.n == 2 and not f.slots[1] and not f.slots[2]
            for _ = 1, 140 do Furn.update(0.5) end
            local outOk = W.get(fx, fy, fz) == B.byName.furnace.id
            log(string.format("FURNACECHECK: %s горит=%s слитков=%d погасла=%s",
                (litOk and smeltOk and outOk) and "PASS" or "FAIL", tostring(litOk), out and out.n or 0, tostring(outOk)))
            -- Падение: столб из двух песков в 6 клетках над землёй (под ним
            -- пусто) летит вниз телом и ложится на землю; за первые 5 тиков —
            -- ровно столько, сколько даёт физика Minecraft (разгон, не скачок).
            local sx, sz = 12, 12
            local ground = W.surface(sx, sz)
            local top = ground + 7
            local sand = B.byName.sand.id
            Act.setBlock(sx, top, sz, sand)
            Act.setBlock(sx, top + 1, sz, sand)
            Act.settle(sx, top - 1, sz)
            local inFlight = Fall.count() == 2 and W.get(sx, top, sz) == 0
            local expect, vy = 0, 0
            for _ = 1, 5 do vy = (vy - 0.04) * 0.98; expect = expect + vy end
            for _ = 1, 5 do Fall.update(0.05) end
            local smooth = inFlight and Fall.count() == 2
            for _ = 1, 200 do Fall.update(0.05) end
            local landed = Fall.count() == 0 and W.get(sx, ground + 1, sz) == sand and W.get(sx, ground + 2, sz) == sand
            log(string.format("FALLCHECK: %s в_полёте=%s за_5_тиков=%.3f лёг=%s",
                (inFlight and smooth and landed) and "PASS" or "FAIL", tostring(inFlight), expect, tostring(landed)))
        end
        W.chunks = {}
        local miss = Inv.checkLayout()
        log(string.format("UICHECK: %s клеток_мимо=%d", miss == 0 and "PASS" or "FAIL", miss))
    end
    Inv.init(loaded and loaded.inventory)
    C.edits = loaded and loaded.edits or {}
    Furn.load(loaded and loaded.furnaces)
    Map.load(loaded and loaded.maps)
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
    -- Для проверки анимаций: меч, лук со стрелами, еда, вода, карта, блок.
    if LaunchFlag("animkit") then
        for _, k in ipairs({{"diamond_sword", 1}, {"bow", 1}, {"apple", 16}, {"potion", 1}, {"empty_map", 1},
                            {"cobblestone", 64}, {"iron_pickaxe", 1}, {"stick", 16}, {"arrow", 64}}) do
            Inv.add(B.byName[k[1]].id, k[2])
        end
    end
    if LaunchFlag("kit") then
        for _, n in ipairs({"torch", "glowstone", "planks", "diamond_sword", "stone_pickaxe", "cobblestone", "log", "stick", "iron_pickaxe"}) do
            Inv.add(B.byName[n].id, B.byName[n].stack)
        end
    end
    Sky.init()
    Clouds.init(seed)
    Hud.init()
    Menu.init()
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

-- F2 — снимок экрана, как в Minecraft: файл по времени в screenshots/
-- каталога игры, в чат — его имя (со следующего кадра, в снимок не попадает).
local shotDemo = nil
local shotAt = nil
local useFor = nil
local quitAfterShot = nil
function takeScreenshot()
    local path = game.screenshot()
    Hud.chat("Saved screenshot as " .. (path:match("[^/\\]+$") or path))
    log("Screenshot: " .. path)
end

function OnUpdate(entity, dt)
    if failed then return end
    if not started then
        started = true
        local ok, err = pcall(startGame)
        if not ok then
            failed = true
            local hint = ""
            if tostring(err):find("attempt to call a nil value") then
                hint = " The player is older than the game: it lacks an engine function —"
                    .. " download the latest SAGE Craft release or build the player from SAGE Engine main."
            end
            logError("SAGE Craft failed to start: " .. tostring(err) .. "." .. hint)
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
            -- Для проверки F2: снимок через 3 с, ещё через 2 с — кадр с надписью в чате.
            if LaunchFlag("shotdemo") then shotDemo = 0 end
            if (LaunchArg("shotat") or "") ~= "" then shotAt = {t = 0, at = tonumber(LaunchArg("shotat"))} end
            if (LaunchArg("hold") or "") ~= "" and B.byName[LaunchArg("hold")] then
                for i = 1, 36 do
                    local s = Inv.slots[i]
                    if s and s.id == B.byName[LaunchArg("hold")].id and i <= 9 then Inv.select(i) end
                end
            end
            Act.forcePlace = LaunchFlag("forceuse")
            -- Держать ПКМ столько секунд и отпустить (выстрел из лука).
            useFor = tonumber(LaunchArg("usefor") or "")
            if useFor then Act.forcePlace = true end
            Act.forceSwing = LaunchFlag("forceswing")
            if LaunchArg("slot") and LaunchArg("slot") ~= "" then Inv.select(tonumber(LaunchArg("slot"))) end
            -- Для снимков: печь рядом — руда плавится, уголь горит, окно открыто.
            if LaunchFlag("furnacedemo") then
                local dx, _, dz = P.lookDir()
                local x, z = math.floor(P.pos.x + dx * 2.5), math.floor(P.pos.z + dz * 2.5)
                local y = W.surface(x, z) + 1
                Act.setBlock(x, y, z, B.byName.furnace.id)
                local f = Furn.at(x, y, z)
                f.slots[1] = {id = B.byName.iron_ore.id, n = 5}
                f.slots[2] = {id = B.byName.coal.id, n = 3}
                f.slots[3] = {id = B.byName.iron_ingot.id, n = 2}
                f.burn, f.burnMax, f.cook = 50, 80, 6
                Inv.openFurnace(f)
            end
            -- Главное меню — после загрузки, поверх живого мира. Прогоны и
            -- снимки (у них своя цель) его пропускают.
            local snapshot = LaunchFlag("openinv") or LaunchFlag("craftdemo") or LaunchFlag("dropdemo")
                or LaunchFlag("furnacedemo") or (LaunchArg("crack") or "") ~= ""
            if not (Auto.active or LaunchFlag("nomenu") or snapshot) then Menu.open() end
            local n = 0
            for _ in pairs(W.chunks) do n = n + 1 end
            log(string.format("SAGE Craft: world ready, %d chunks (generation %.2f s, light %.2f s, meshes %.2f s)",
                n, C.stats.gen, C.stats.light, C.stats.mesh))
        end
        Sky.update(dt, P)
        placeCamera()
        return
    end

    if useFor then
        useFor = useFor - dt
        if useFor <= 0 then Act.forcePlace = false; useFor = nil end
    end
    if shotAt then
        shotAt.t = shotAt.t + dt
        if shotAt.t >= shotAt.at then
            game.screenshot("screenshots/" .. (LaunchArg("shotname") or "shot") .. ".png")
            shotAt = nil
            if LaunchFlag("quit") then quitAfterShot = 3 end
        end
    end
    if quitAfterShot then quitAfterShot = quitAfterShot - 1; if quitAfterShot <= 0 then game.Quit() end end
    if shotDemo then
        local was = shotDemo
        shotDemo = shotDemo + dt
        if was < 3 and shotDemo >= 3 then takeScreenshot() end
        if was < 5 and shotDemo >= 5 then game.screenshot("screenshots/shotdemo_chat.png"); shotDemo = nil end
    end

    -- Музыка меню — только на титульном экране (не в паузе по Esc).
    Music.update(dt, Menu.active and not Menu.started)
    if Menu.active then
        -- За меню — мир с медленно вращающейся камерой; игра стоит.
        Menu.update(dt)
        P.yaw = (P.yaw + dt * 3) % 360
        P.pitch = 8
        C.update(P.pos.x, P.pos.z, C.budgetMs)
        Fall.update(dt)
        Furn.update(dt)
        Sky.update(dt, P)
        Clouds.update(dt, P)
        Hand.update(dt, false, 0, P.walkDist, 0)
        -- Вид глазами: голову персонажа спрятать, иначе камера смотрит
        -- изнутри неё (во время загрузки аватар ещё не обновлялся).
        Avatar.update(dt, P, false, 0)
        placeCamera()
        return
    end

    if WasActionPressed("Inventory") then Inv.toggleScreen() end
    if WasActionPressed("Pause") then
        if Inv.screenOpen then Inv.toggleScreen() else Menu.open() end
    end
    if Act.openTable then
        Act.openTable = false
        if not Inv.screenOpen then Inv.toggleScreen(3) end
    end
    if Act.openFurnace then
        local p = Act.openFurnace
        Act.openFurnace = nil
        Inv.openFurnace(Furn.at(p.x, p.y, p.z))
    end
    if WasActionPressed("View") then thirdPerson = (thirdPerson + 1) % 3 end
    if WasActionPressed("Debug") then Hud.toggleDebug() end
    -- F2 — снимок экрана, как в Minecraft: файл по времени в screenshots/
    -- каталога игры, в чат — его имя.
    if WasActionPressed("Screenshot") then takeScreenshot() end
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

    -- Пока предмет используется (едят, пьют, натягивают лук, держат блок),
    -- шаг ×0.2 и бег сбит (EntityPlayerSP.onLivingUpdate).
    if Anim.use then
        inp.forward, inp.strafe = inp.forward * 0.2, inp.strafe * 0.2
        inp.sprintPressed = false
        P.sprinting = false
    end
    local walkedBefore = P.walkDist
    local fall = P.update(inp, dt)
    local heldNow = Inv.current()
    Anim.update(dt, P, heldNow and heldNow.id or 0, Inv.selected)
    -- Шаги — как у 1.7.10: путь по земле копится с множителем 0.6, звук —
    -- при каждом переходе через целое (то есть раз в 1/0.6 блока); в воде
    -- и в полёте тихо. Материал — у блока под ногами.
    if P.onGround and not P.flying and not P.inWater then
        local before, after = math.floor(walkedBefore * 0.6), math.floor(P.walkDist * 0.6)
        if after > before then
            local fx, fy, fz = math.floor(P.pos.x), math.floor(P.pos.y - 0.2), math.floor(P.pos.z)
            Snd.step(W.get(fx, fy, fz), P.pos.x, P.pos.y, P.pos.z)
        end
    end
    if fall and fall > 3.5 then Hud.damage(math.floor(fall - 3)) end

    C.update(P.pos.x, P.pos.z, C.budgetMs)

    if not Inv.screenOpen then Act.update(dt, Auto.active and Auto.actions() or nil) end
    Drops.update(dt)
    Fall.update(dt)
    Furn.update(dt)
    Sky.update(dt, P)
    Clouds.update(dt, P)
    Arrows.update(dt, P)
    local held = Inv.current()
    local heldId = held and held.id or 0
    Map.heldNumber = held and held.id == B.byName.filled_map.id and held.wear or nil
    Avatar.update(dt, P, thirdPerson ~= 0, heldId)
    Avatar.updatePreview()
    Hand.update(dt, thirdPerson == 0, P, heldId)
    placeCamera()
    Hud.update(dt)
    Inv.update(dt)
    Save.tick(dt)
    Auto.update(dt)
end
