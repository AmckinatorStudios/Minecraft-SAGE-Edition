-- ---------------------------------------------------------------------------
-- save.lua — сохранение мира: зерно, ПРАВКИ игрока (не весь мир — он
-- восстанавливается из зерна), рюкзак, место игрока, время суток, скин.
-- Пишется раз в SAVE_EVERY секунд и при выходе через --quit автопрогона.
-- --fresh=1 — начать новый мир, не читая сохранение.
-- ---------------------------------------------------------------------------
local S = {}

local SLOT = "world"
local SAVE_EVERY = 30
local timer = 0

function S.load()
    if LaunchFlag("fresh") then return nil end
    if not HasSave(SLOT) then return nil end
    local ok, data = pcall(LoadGame, SLOT)
    if not ok or type(data) ~= "table" then return nil end
    -- Ключи правок пишутся строками (JSON), обратно — числами.
    local edits = {}
    for k, cells in pairs(data.edits or {}) do
        local e = {}
        for idx, id in pairs(cells) do e[tonumber(idx)] = id end
        edits[tonumber(k)] = e
    end
    data.edits = edits
    S.data = data
    return data
end

function S.write()
    local P = require "player"
    local C = require "chunks"
    local Inv = require "inventory"
    local Sky = require "sky"
    local G = require "gen"
    local Avatar = require "avatar"
    local edits = {}
    for k, cells in pairs(C.edits) do
        local e = {}
        for idx, id in pairs(cells) do e[tostring(idx)] = id end
        edits[tostring(k)] = e
    end
    SaveGame(SLOT, {
        seed = G.seed,
        edits = edits,
        inventory = Inv.serialize(),
        player = {x = P.pos.x, y = P.pos.y, z = P.pos.z, yaw = P.yaw, pitch = P.pitch},
        time = Sky.time,
        skin = Avatar.skinPath,
    })
end

function S.tick(dt)
    if LaunchFlag("nosave") then return end
    timer = timer + dt
    if timer >= SAVE_EVERY then
        timer = 0
        S.write()
    end
end

return S
