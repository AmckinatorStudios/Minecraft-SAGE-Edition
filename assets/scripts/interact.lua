-- ---------------------------------------------------------------------------
-- interact.lua — добыча и постройка.
--
-- ЛКМ держат — блок трескается и ломается за время, зависящее от прочности
-- блока и инструмента в руке: «своим» инструментом нужного уровня — быстро и
-- с добычей, чужим или руками — медленно, а руда без кирки нужного уровня
-- не роняет ничего. ПКМ — поставить блок из выбранной ячейки к грани, в
-- которую смотрит прицел. Средняя — взять в руку такой же блок, если он есть
-- в рюкзаке.
--
-- Рамка выбранного блока — 12 тонких брусков, трещины — куб чуть больше
-- блока с плиткой стадии из атласа.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local A = require "atlas"
local L = require "light"
local P = require "player"
local Inv = require "inventory"
local C = require "chunks"

local Act = {}

Act.REACH = 5
Act.swing = 0               -- 0..1 — фаза взмаха руки (её читает аватар)
Act.stats = {broken = 0, placed = 0, picked = 0}
local target
local mining = nil          -- {x, y, z, t}
local outline, crack
local placeCooldown = 0
local breakCooldown = 0

local function outlineMesh()
    local m = mesh()
    local e = 0.002
    local t = 0.012
    local lo, hi = -e, 1 + e
    local function bar(x0, y0, z0, x1, y1, z1)
        local b = box(x1 - x0, y1 - y0, z1 - z0)
        b.move((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        m.add(b)
    end
    for _, a in ipairs({lo, hi}) do
        for _, b in ipairs({lo, hi}) do
            bar(lo, a - t, b - t, hi, a + t, b + t)
            bar(a - t, lo, b - t, a + t, hi, b + t)
            bar(a - t, b - t, lo, a + t, b + t, hi)
        end
    end
    return m
end

local function crackMesh(stage)
    local tu, tv, ts = A.tileOrigin(A.destroyTile[stage])
    local pos, nrm, uv, uv2, idx = {}, {}, {}, {}, {}
    local e = 0.004
    local faces = {
        {{0,1,0},{0,1,1},{1,1,1},{1,1,0}, n = {0,1,0}},
        {{0,0,0},{1,0,0},{1,0,1},{0,0,1}, n = {0,-1,0}},
        {{1,0,0},{1,1,0},{1,1,1},{1,0,1}, n = {1,0,0}},
        {{0,0,0},{0,0,1},{0,1,1},{0,1,0}, n = {-1,0,0}},
        {{0,0,1},{1,0,1},{1,1,1},{0,1,1}, n = {0,0,1}},
        {{0,0,0},{0,1,0},{1,1,0},{1,0,0}, n = {0,0,-1}},
    }
    local quv = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}
    local nv = 0
    for _, f in ipairs(faces) do
        for k = 1, 4 do
            local p = f[k]
            for a = 1, 3 do pos[#pos + 1] = p[a] * (1 + 2 * e) - e end
            for a = 1, 3 do nrm[#nrm + 1] = f.n[a] end
            uv[#uv + 1] = tu + quv[k][1] * ts; uv[#uv + 1] = tv + quv[k][2] * ts
            uv2[#uv2 + 1] = 15; uv2[#uv2 + 1] = 15
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do idx[#idx + 1] = nv + i end
        nv = nv + 4
    end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, uv2 = uv2, index = idx}
    return m
end

local crackMeshes = {}

function Act.init()
    outline = SpawnObject("Block Outline")
    outlineMesh().apply(outline)
    material("sagecraft_outline", {color = rgb(0.02, 0.02, 0.02), unlit = true})
    SetMaterial(outline, "sagecraft_outline")
    outline.Transform.Position = Vec3(0, -100, 0)
    crack = SpawnObject("Block Crack")
    for s = 0, 9 do crackMeshes[s] = crackMesh(s) end
    crackMeshes[0].apply(crack)
    SetMaterial(crack, "assets/materials/crack.sagemat")
    crack.Transform.Position = Vec3(0, -100, 0)
end

-- Время добычи блока id инструментом из выбранной ячейки; и упадёт ли что-то.
function Act.breakTime(id)
    local d = B.byId[id]
    if not d or d.hard < 0 then return math.huge, false end
    if d.hard == 0 then return 0.05, true end
    local held = Inv.current()
    -- Инструмент — только предмет: у БЛОКА поле tool значит «чем его ломать»,
    -- и блок в руке не должен считаться лопатой без уровня.
    local tool = held and B.byId[held.id]
    if tool and tool.isBlock then tool = nil end
    local speed, tier = 1, 0
    if tool and tool.tool and tool.tool == d.tool then speed, tier = tool.speed, tool.tier end
    if tool and tool.tool == "sword" and (d.name == "leaves" or d.name == "birch_leaves") then speed = 1.5 end
    local ok = (d.need or 0) <= tier
    -- Неподходящим инструментом (или руками по камню) — втрое дольше.
    local t = d.hard * (ok and 1.5 or 5) / speed
    return math.max(0.05, t), ok
end

-- Падение песка и гравия: всё, что висит над пустотой, опускается.
local function settle(x, y, z)
    for yy = y + 1, W.HEIGHT - 1 do
        local id = W.get(x, yy, z)
        if not (B.byId[id] and B.byId[id].falls) then break end
        local below = yy - 1
        while below > 0 and (W.get(x, below - 1, z) == 0 or B.drawKind[W.get(x, below - 1, z)] == 4) do below = below - 1 end
        if W.get(x, below, z) == 0 or B.drawKind[W.get(x, below, z)] == 4 then
            Act.setBlock(x, yy, z, 0)
            Act.setBlock(x, below, z, id)
        end
    end
end

-- Поставить блок в мир: клетка, свет, пересборка, запись правки.
function Act.setBlock(x, y, z, id)
    if not W.setId(x, y, z, id) then return false end
    C.recordEdit(x, y, z, id)
    L.update(x, y, z)
    W.markDirty(x, y, z)
    return true
end

local function breakBlock(t)
    local id = t.id
    Act.stats.broken = Act.stats.broken + 1
    local _, ok = Act.breakTime(id)
    Act.setBlock(t.x, t.y, t.z, 0)
    -- Растение над сломанным блоком падает вместе с опорой.
    local above = W.get(t.x, t.y + 1, t.z)
    if B.drawKind[above] == 3 or B.drawKind[above] == 5 then Act.setBlock(t.x, t.y + 1, t.z, 0) end
    -- Соседняя вода затекает в дыру (одна клетка — без настоящего течения).
    for _, d in ipairs({{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}}) do
        if W.get(t.x + d[1], t.y + d[2], t.z + d[3]) == 11 then Act.setBlock(t.x, t.y, t.z, 11); break end
    end
    local Drops = require "drops"
    if ok then
        local drop = B.dropOf(id)
        if drop then Drops.spawn(drop, 1, t.x + 0.5, t.y + 0.5, t.z + 0.5) end
        if B.byId[id].xp then require("hud").addXp(B.byId[id].xp) end
        local d = B.byId[id]
        if d.apple and math.random() < d.apple then Drops.spawn(B.byName.apple.id, 1, t.x + 0.5, t.y + 0.5, t.z + 0.5) end
        if d.flint and math.random() < d.flint then Drops.spawn(B.byName.flint.id, 1, t.x + 0.5, t.y + 0.5, t.z + 0.5) end
    end
    Drops.burst(id, t.x + 0.5, t.y + 0.5, t.z + 0.5)
    Inv.wearTool()
    settle(t.x, t.y, t.z)
end

local function place(t)
    -- Верстак открывается ПКМ (с Shift — ставим блок рядом, как обычно).
    if t.id == B.byName.crafting_table.id and not IsActionDown("Sneak") then
        Act.openTable = true
        return
    end
    local held = Inv.current()
    if not held then return end
    local d = B.byId[held.id]
    -- Еда: ПКМ — съесть.
    if d.food then
        if require("hud").eat(d.food) then Inv.useOne(); Act.swing = 1 end
        return
    end
    if not d or not d.isBlock then return end
    local x, y, z = t.x + t.nx, t.y + t.ny, t.z + t.nz
    -- В траву ставится поверх (трава заменяется).
    if B.drawKind[t.id] == 3 then x, y, z = t.x, t.y, t.z end
    local cur = W.get(x, y, z)
    if cur ~= 0 and B.drawKind[cur] ~= 4 and B.drawKind[cur] ~= 3 then return end
    if y < 0 or y >= W.HEIGHT or not P.canPlace(x, y, z, held.id) then return end
    -- Растение и факел — только на твёрдую опору.
    if (d.draw == "cross" or d.draw == "torch") and not B.opaque[W.get(x, y - 1, z)] then return end
    if Act.setBlock(x, y, z, held.id) then
        Act.stats.placed = Act.stats.placed + 1
        Inv.useOne()
        Act.swing = 1
        settle(x, y - 1, z)
    end
end

-- actions — для автопрогона: {breaking = bool, place = bool}.
function Act.update(dt, actions)
    target = P.raycast(Act.REACH)
    local breaking = actions and actions.breaking or IsActionDown("Break")
    local placing = actions and actions.place or IsActionDown("Place")
    placeCooldown = math.max(0, placeCooldown - dt)
    breakCooldown = math.max(0, breakCooldown - dt)
    Act.swing = math.max(0, Act.swing - dt * 3.5)

    if Act.forceCrack and target then
        -- Отладка снимков: показать трещину этой стадии на блоке под прицелом.
        crackMeshes[Act.forceCrack].apply(crack)
        SetMaterial(crack, "assets/materials/crack.sagemat")
        crack.Transform.Position = Vec3(target.x, target.y, target.z)
    end
    if target then
        outline.Transform.Position = Vec3(target.x, target.y, target.z)
    else
        outline.Transform.Position = Vec3(0, -100, 0)
    end

    if breaking and target and breakCooldown == 0 then
        if Act.swing < 0.3 then Act.swing = 1 end
        if not mining or mining.x ~= target.x or mining.y ~= target.y or mining.z ~= target.z then
            mining = {x = target.x, y = target.y, z = target.z, t = 0}
        end
        mining.t = mining.t + dt
        local need = Act.breakTime(target.id)
        local stage = math.min(9, math.floor(mining.t / need * 10))
        if stage ~= mining.stage then
            mining.stage = stage
            crackMeshes[stage].apply(crack)
            SetMaterial(crack, "assets/materials/crack.sagemat")
        end
        crack.Transform.Position = Vec3(target.x, target.y, target.z)
        if mining.t >= need then
            breakBlock(target)
            mining = nil
            breakCooldown = 0.15
            crack.Transform.Position = Vec3(0, -100, 0)
        end
    else
        mining = nil
        crack.Transform.Position = Vec3(0, -100, 0)
    end

    if placing and target and placeCooldown == 0 then
        place(target)
        placeCooldown = 0.22
    end
    if not placing then placeCooldown = 0 end

    if WasActionPressed("Pick") and target then
        for i = 1, 9 do
            local s = Inv.slots[i]
            if s and s.id == target.id then Inv.select(i); return end
        end
    end
    if WasActionPressed("Drop") then
        local s = Inv.current()
        if s then
            require("drops").throwFromPlayer(s.id, 1, s.wear)
            Inv.useOne()
        end
    end
end

Act.target = function() return target end

return Act
