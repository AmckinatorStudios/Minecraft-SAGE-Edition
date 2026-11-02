-- ---------------------------------------------------------------------------
-- falling.lua — падающие блоки (песок, гравий).
--
-- Блок без опоры не переставляется вниз мгновенно, а становится телом и
-- падает с физикой Minecraft: 20 тиков в секунду, за тик скорость −0.04
-- блока, затем сопротивление ×0.98 (плавный разгон, предел около 2 блоков за
-- тик). Между тиками положение сглаживается, поэтому падение плавное при любой
-- частоте кадров. Коснулся опоры — снова блок в мире; клетку с растением
-- занимает, вытесняя его.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local F = {}

local TICK = 1 / 20
local GRAVITY, DRAG = 0.04, 0.98
local list = {}

-- Можно ли пролететь сквозь клетку: воздух, жидкость, растение, факел.
local function passable(id)
    local k = B.drawKind[id]
    return id == 0 or k == 4 or k == 3 or k == 5
end
F.passable = passable

-- Блок (x, y, z) уже снят из мира: запустить его падение.
function F.spawn(id, x, y, z)
    local o = SpawnObject("Falling " .. id)
    -- Кубик — тот же, что у выпавшего блока, но во всю клетку.
    require("drops").cubeMesh(id, 1.0).apply(o)
    SetMaterial(o, "assets/materials/chunk.sagemat")
    local e = {id = id, x = x, z = z, y = y, prevY = y, vy = 0, acc = 0, obj = o}
    o.Transform.Position = Vec3(x + 0.5, y + 0.5, z + 0.5)
    list[#list + 1] = e
end

-- Приземлился: блок в клетку y (растение и факел там вытесняются).
local function land(e, y)
    local Act = require "interact"
    Act.setBlock(e.x, y, e.z, e.id)
    DestroyObject(e.obj)
end

function F.update(dt)
    local i = 1
    while i <= #list do
        local e = list[i]
        local done = false
        e.acc = e.acc + dt
        while e.acc >= TICK and not done do
            e.acc = e.acc - TICK
            e.prevY = e.y
            e.vy = (e.vy - GRAVITY) * DRAG
            local ny = e.y + e.vy
            -- Клетки, которые тело проходит за тик, — сверху вниз: опора
            -- может оказаться на любой из них, а не только в конечной.
            for cy = math.floor(e.y) - 1, math.floor(ny), -1 do
                if cy < 0 or not passable(W.get(e.x, cy, e.z)) then
                    land(e, cy + 1)
                    done = true
                    break
                end
            end
            if not done then e.y = ny end
        end
        if done then
            table.remove(list, i)
        else
            local y = e.prevY + (e.y - e.prevY) * (e.acc / TICK)
            e.obj.Transform.Position = Vec3(e.x + 0.5, y + 0.5, e.z + 0.5)
            i = i + 1
        end
    end
end

-- Сколько тел сейчас в полёте (для проверок).
function F.count() return #list end

return F
