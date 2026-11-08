-- ---------------------------------------------------------------------------
-- furnace.lua — печи в мире: переплавка, топливо, огонь.
--
-- У каждой поставленной печи — три ячейки (1 — что плавить, 2 — топливо,
-- 3 — результат) и состояние огня. Работают все загруженные печи, а не только
-- открытая: положил руду, ушёл — вернулся к слиткам. Как в Minecraft: огонь
-- зажигается от топлива, только когда есть что плавить и куда класть
-- результат; горит, пока не кончится (даже если плавить уже нечего);
-- предмет плавится R.COOK секунд, без огня прогресс сбрасывается.
--
-- Пока огонь горит, блок печи — «горящая печь» (светит, передняя грань с
-- огнём); погасла — снова обычная.
-- ---------------------------------------------------------------------------
local B = require "blocks"
local W = require "world"
local R = require "crafting"

local F = {}

F.COOK = 10            -- секунд на один предмет
F.list = {}            -- [ключ] = печь

local OFF, ON = B.byName.furnace.id, B.byName.lit_furnace.id

local function key(x, y, z) return x .. "," .. y .. "," .. z end

-- Печь в клетке (создаётся при первом обращении, если там стоит печь).
function F.at(x, y, z)
    local k = key(x, y, z)
    local f = F.list[k]
    if not f then
        f = {x = x, y = y, z = z, slots = {}, burn = 0, burnMax = 0, cook = 0}
        F.list[k] = f
    end
    return f
end

function F.isFurnace(id) return id == OFF or id == ON end

local function canSmelt(f)
    local input = f.slots[1]
    if not input then return false end
    local out = R.SMELT[input.id]
    if not out then return false end
    local res = f.slots[3]
    return not res or (res.id == out and res.n < B.maxStack(out))
end

-- Сменить вид блока (горит / не горит) — с записью правки и светом.
local function setLit(f, lit)
    local id = W.get(f.x, f.y, f.z)
    if not F.isFurnace(id) then return end
    local want = lit and ON or OFF
    -- Горящая и холодная печь — разные блоки; лицо (метаданные) сохраняется
    -- (BlockFurnace.updateFurnaceBlockState: setBlockMetadataWithNotify).
    if id ~= want then require("interact").setBlock(f.x, f.y, f.z, want, W.meta(f.x, f.y, f.z)) end
end

function F.update(dt)
    -- По снимку ключей: смена горящей/холодной печи ставит блок, а это может
    -- менять список печей посреди обхода.
    local ks = {}
    for k in pairs(F.list) do ks[#ks + 1] = k end
    for _, k in ipairs(ks) do
        local f = F.list[k]
        if not f then goto continue end
        local id = W.get(f.x, f.y, f.z)
        local loaded = W.chunk(f.x // 16, f.z // 16) ~= nil
        if loaded and not F.isFurnace(id) then
            F.list[k] = nil                      -- печь сломали
        elseif loaded then
            local wasBurning = f.burn > 0
            if f.burn > 0 then f.burn = math.max(0, f.burn - dt) end
            local smelt = canSmelt(f)
            if f.burn <= 0 and smelt then
                local fuel = f.slots[2]
                local sec = fuel and R.FUEL[fuel.id]
                if sec then
                    f.burn, f.burnMax = sec, sec
                    fuel.n = fuel.n - 1
                    if fuel.n <= 0 then f.slots[2] = nil end
                end
            end
            if f.burn > 0 and smelt then
                f.cook = f.cook + dt
                if f.cook >= F.COOK then
                    f.cook = 0
                    local input = f.slots[1]
                    local out = R.SMELT[input.id]
                    input.n = input.n - 1
                    if input.n <= 0 then f.slots[1] = nil end
                    local res = f.slots[3]
                    if res then res.n = res.n + 1 else f.slots[3] = {id = out, n = 1} end
                end
            else
                f.cook = 0
            end
            local burning = f.burn > 0
            if burning ~= wasBurning or (burning and id ~= ON) or (not burning and id ~= OFF) then
                setLit(f, burning)
            end
        end
        ::continue::
    end
end

-- Доли для полос окна: огонь 0..1 (сколько осталось), стрелка 0..1.
function F.progress(f)
    local flame = f.burnMax > 0 and f.burn / f.burnMax or 0
    return flame, f.cook / F.COOK
end

-- Печь сломали: содержимое — на землю.
function F.broken(x, y, z)
    local k = key(x, y, z)
    local f = F.list[k]
    if not f then return end
    local Drops = require "drops"
    for i = 1, 3 do
        local s = f.slots[i]
        if s then Drops.spawn(s.id, s.n, x + 0.5, y + 0.5, z + 0.5) end
    end
    F.list[k] = nil
end

-- Для сохранения: только печи, где что-то есть или горит.
function F.serialize()
    local out = {}
    for _, f in pairs(F.list) do
        if next(f.slots) or f.burn > 0 then
            local slots = {}
            for i = 1, 3 do
                local s = f.slots[i]
                slots[i] = s and {id = s.id, n = s.n} or false
            end
            out[#out + 1] = {x = f.x, y = f.y, z = f.z, slots = slots, burn = f.burn, burnMax = f.burnMax, cook = f.cook}
        end
    end
    return out
end

function F.load(data)
    F.list = {}
    for _, d in ipairs(data or {}) do
        local f = F.at(d.x, d.y, d.z)
        for i = 1, 3 do
            local s = d.slots and d.slots[i]
            if s and s ~= false and s.id then f.slots[i] = {id = s.id, n = s.n} end
        end
        f.burn, f.burnMax, f.cook = d.burn or 0, d.burnMax or 0, d.cook or 0
    end
end

return F
