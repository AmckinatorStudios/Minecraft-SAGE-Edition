-- ---------------------------------------------------------------------------
-- menutest.lua — сквозная проверка меню и миров (--menutest=1, строка
-- MENUCHECK в логе). Две половины, между ними — настоящий выход в меню с
-- перезапуском сцены (состояние проверки — в слоте сохранения):
--   1) титульный экран: мира нет (ни одного участка) — генерация не шла;
--      Create New World «Menu Test» -> мир строится -> ставим блок, кладём
--      алмазы, сдвигаемся -> Save and Quit to Title;
--   2) после перезапуска: мир в списке (имя, дата, превью) -> Play -> блок,
--      алмазы и место игрока на месте -> мир удаляется, игра выходит.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local P = require "player"
local Inv = require "inventory"
local Menu = require "menu"
local Worlds = require "worlds"

local T = {}
local STATE = "menutest_state"
local NAME = "Menu Test"
local state, timer, phase, openWorld
local frames = 0

local function finish(ok, why)
    log("MENUCHECK: " .. (ok and "PASS" or "FAIL") .. " " .. why)
    if not LaunchFlag("keep") then
        for _, w in ipairs(Worlds.list()) do if w.name == NAME then Worlds.delete(w) end end
    end
    DeleteSave(STATE)
    game.Quit()
end

function T.start(open)
    openWorld = open
    T.active = true
    state = HasSave(STATE) and LoadGame(STATE) or {stage = 1}
    timer, phase = 0, "title"
end

-- Каждый кадр (и в меню, и в мире).
function T.update(dt, worldOpen, loading)
    if not T.active then return end
    timer = timer + dt
    frames = frames + 1
    if state.stage == 1 then
        if phase == "title" then
            -- Полсекунды на титульном экране: участков быть не должно.
            if timer > 0.5 then
                local chunks = 0
                for _ in pairs(W.chunks) do chunks = chunks + 1 end
                if chunks > 0 then return finish(false, "мир строился до создания: участков=" .. chunks) end
                for _, w in ipairs(Worlds.list()) do if w.name == NAME then Worlds.delete(w) end end
                Menu.go("select")
                Menu.go("create")
                local cs = Menu.screens.create
                cs.field.e.Text = NAME
                phase, timer = "creating", 0
            end
        elseif phase == "creating" and timer > 0.3 then
            Menu.screens.create.confirm()
            phase, timer = "loading", 0
        elseif phase == "loading" and worldOpen and not loading and timer > 3 then
            local x, y, z = math.floor(P.pos.x) + 2, math.floor(P.pos.y), math.floor(P.pos.z)
            require("interact").setBlock(x, y, z, B.byName.cobblestone.id)
            Inv.add(B.byName.diamond.id, 3)
            P.pos.x = P.pos.x + 0.25
            state = {stage = 2, bx = x, by = y, bz = z, px = P.pos.x, py = P.pos.y, pz = P.pos.z}
            SaveGame(STATE, state, 1)
            Menu.onQuitToTitle()
            phase = "quitting"
        end
    elseif state.stage == 2 then
        if phase == "title" and timer > 0.5 then
            local found
            for _, w in ipairs(Worlds.list()) do if w.name == NAME then found = w end end
            if not found then return finish(false, "мира нет в списке после выхода") end
            if not found.preview then return finish(false, "у мира нет превью") end
            if (found.savedAt or 0) <= 0 then return finish(false, "у мира нет даты") end
            state.date = Worlds.dateText(found.savedAt)
            openWorld(found)
            phase, timer = "loading", 0
        elseif phase == "loading" and worldOpen and not loading and timer > 1 then
            local block = W.get(state.bx, state.by, state.bz) == B.byName.cobblestone.id
            local dist = math.abs(P.pos.x - state.px) + math.abs(P.pos.z - state.pz)
            local diamonds = Inv.count(B.byName.diamond.id)
            local ok = block and dist < 0.01 and diamonds >= 3
            finish(ok, string.format("блок=%s сдвиг=%.3f алмазов=%d дата=%s", tostring(block), dist, diamonds,
                                     state.date or "?"))
        end
    end
end

return T
