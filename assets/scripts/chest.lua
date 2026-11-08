-- ---------------------------------------------------------------------------
-- chest.lua — сундук Minecraft 1.7.10: BlockChest + TileEntityChest +
-- InventoryLargeChest.
--
-- Блок: метаданные — сторона лица 2..5 (север, юг, запад, восток). Ставится
-- лицом к игроку (onBlockPlacedBy: floor(yaw·4/360 + 0.5) & 3 → 2, 5, 3, 4).
-- Соседом может быть не больше одного сундука, и у того не должно быть
-- второго соседа (canPlaceBlockAt) — тройных и угловых связок нет, по
-- диагонали сундуки не соединяются. Пара по оси X смотрит на север или юг,
-- по оси Z — на запад или восток: обе половины получают одну сторону
-- (onBlockPlacedBy / func_149954_e).
--
-- Хранилище: 27 ячеек у каждой половины; пара — одно окно на 54
-- (InventoryLargeChest «Large Chest»): сверху половина с меньшей X (или Z).
-- Открыть нельзя, если над сундуком (или над его парой) глухой куб.
-- Сломали — каждая стопка высыпается кусками по 10–30 (breakBlock).
--
-- Крышка (updateEntity): prev = угол; открыт кем-то — угол + 0.1 до 1,
-- никем — − 0.1 до 0. Звук random.chestopen — когда открыт, а угол ещё 0;
-- random.chestclosed — когда угол переходит через 0.5 вниз. Звучит одна
-- половина пары (у которой нет соседа по −X и −Z), из середины пары:
-- громкость 0.5, тон 0.9..1, категория «блоки».
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local CM = require "chestmodel"

local Ch = {}

Ch.ID = B.byName.chest.id
Ch.SIZE = 27
Ch.list = {}          -- [ключ] = {x, y, z, slots, lid, plid, users, model}

local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function rnd(n) return math.random(0, n - 1) end

function Ch.isChest(id) return id == Ch.ID end

-- Хранилище сундука в клетке (создаётся, если блок — сундук).
function Ch.at(x, y, z)
    local k = key(x, y, z)
    local c = Ch.list[k]
    if not c and W.get(x, y, z) == Ch.ID then
        c = {x = x, y = y, z = z, slots = {}, lid = 0, plid = 0, users = 0}
        Ch.list[k] = c
    end
    return c
end

local function isChestAt(x, y, z) return W.get(x, y, z) == Ch.ID end

-- Соседний сундук пары (только по сторонам, не по диагонали): dx, dz или nil.
local SIDES = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
function Ch.partner(x, y, z)
    for _, d in ipairs(SIDES) do
        if isChestAt(x + d[1], y, z + d[2]) then return x + d[1], y, z + d[2] end
    end
    return nil
end

-- func_149952_n: в клетке сундук, у которого уже есть сосед-сундук.
local function hasPair(x, y, z)
    if not isChestAt(x, y, z) then return false end
    for _, d in ipairs(SIDES) do
        if isChestAt(x + d[1], y, z + d[2]) then return true end
    end
    return false
end

-- canPlaceBlockAt: рядом не больше одного сундука и он ещё без пары.
function Ch.canPlace(x, y, z)
    local n = 0
    for _, d in ipairs(SIDES) do
        if isChestAt(x + d[1], y, z + d[2]) then n = n + 1 end
    end
    if n > 1 then return false end
    for _, d in ipairs(SIDES) do
        if hasPair(x + d[1], y, z + d[2]) then return false end
    end
    return true
end

-- Сторона лица к игроку: yaw — наш поворот (0 — на −Z), у оригинала
-- rotationYaw = 180 − yaw.
local FACING = {[0] = 2, [1] = 5, [2] = 3, [3] = 4}
function Ch.facingFor(yaw)
    return FACING[math.floor((180 - yaw) * 4 / 360 + 0.5) & 3]
end

-- Сторона нового сундука в (x, y, z) при взгляде yaw — и сторона пары.
-- Пара по X — лицом на север/юг (2/3), по Z — на запад/восток (4/5):
-- подходит взгляд игрока — по нему, иначе — как у соседа, иначе юг/восток
-- (а если перед ним глухой блок, а сзади нет — наоборот, func_149954_e).
function Ch.placeMeta(x, y, z, yaw)
    local b0 = Ch.facingFor(yaw)
    local px, _, pz = Ch.partner(x, y, z)
    if not px then return b0, nil end
    local alongX = px ~= x
    local ok = alongX and (b0 == 2 or b0 == 3) or (not alongX and (b0 == 4 or b0 == 5))
    if ok then return b0, {px, y, pz} end
    local nm = W.meta(px, y, pz)
    if alongX and (nm == 2 or nm == 3) then return nm, {px, y, pz} end
    if not alongX and (nm == 4 or nm == 5) then return nm, {px, y, pz} end
    local function blocked(dx, dz) return B.opaque[W.get(x + dx, y, z + dz)] or B.opaque[W.get(px + dx, y, pz + dz)] end
    if alongX then
        if blocked(0, 1) and not blocked(0, -1) then return 2, {px, y, pz} end
        return 3, {px, y, pz}
    end
    if blocked(1, 0) and not blocked(-1, 0) then return 4, {px, y, pz} end
    return 5, {px, y, pz}
end

-- Сундук поставлен (уже в мире, с метаданными meta): хранилище и сторона пары.
function Ch.placed(x, y, z, meta, pair, setBlock)
    -- Новый блок — новое пустое хранилище (новый TileEntityChest): старое с
    -- этой клетки не всплывает.
    local old = Ch.list[key(x, y, z)]
    if old then CM.destroy(old.model) end
    Ch.list[key(x, y, z)] = nil
    Ch.at(x, y, z)
    if pair and W.meta(pair[1], pair[2], pair[3]) ~= meta then
        setBlock(pair[1], pair[2], pair[3], Ch.ID, meta)
    end
end

-- Пара сундука: {первая, вторая} — сверху окна та, что с меньшей X или Z
-- (func_149951_m), сундук без пары — {он}.
function Ch.group(x, y, z)
    local c = Ch.at(x, y, z)
    if not c then return nil end
    local px, py, pz = Ch.partner(x, y, z)
    if not px then return {c} end
    local o = Ch.at(px, py, pz)
    if px < x or pz < z then return {o, c} end
    return {c, o}
end

-- Можно ли открыть (func_149951_m): над сундуком и над парой — не глухой куб.
function Ch.canOpen(x, y, z)
    if not isChestAt(x, y, z) then return false end
    if B.opaque[W.get(x, y + 1, z)] then return false end
    local px, py, pz = Ch.partner(x, y, z)
    if px and B.opaque[W.get(px, py + 1, pz)] then return false end
    return true
end

-- Ячейки окна: пара — 54 ячейки подряд (сначала первая половина), одиночный —
-- его 27. Таблица-посредник: индекс окна → ячейка нужной половины.
function Ch.view(group)
    if #group == 1 then return group[1].slots end
    local a, b = group[1].slots, group[2].slots
    return setmetatable({}, {
        __index = function(_, i) if i <= Ch.SIZE then return a[i] end return b[i - Ch.SIZE] end,
        __newindex = function(_, i, v) if i <= Ch.SIZE then a[i] = v else b[i - Ch.SIZE] = v end end,
    })
end

-- Открыть окно сундука (onBlockActivated). true — окно открыто.
function Ch.open(x, y, z)
    if not Ch.canOpen(x, y, z) then return false end
    local g = Ch.group(x, y, z)
    -- openInventory: игрок пользуется обеими половинами.
    for _, c in ipairs(g) do c.users = c.users + 1 end
    require("inventory").openChest({
        group = g, rows = #g * 3, slots = Ch.view(g), title = #g == 2 and "Large Chest" or "Chest",
        x = x, y = y, z = z,
    })
    return true
end

-- Окно закрыто (closeInventory): половины — минус пользователь.
function Ch.closed(view)
    for _, c in ipairs(view.group) do c.users = math.max(0, c.users - 1) end
end

-- Окно ещё можно держать открытым (isUseableByPlayer): сундук на месте и
-- игрок не дальше 8 блоков от центра.
function Ch.usable(view, P)
    for _, c in ipairs(view.group) do
        if not isChestAt(c.x, c.y, c.z) or Ch.list[key(c.x, c.y, c.z)] ~= c then return false end
        local dx, dy, dz = P.pos.x - (c.x + 0.5), P.pos.y - (c.y + 0.5), P.pos.z - (c.z + 0.5)
        if dx * dx + dy * dy + dz * dz > 64 then return false end
    end
    -- Пара могла измениться (поставили второй сундук рядом с одиночным).
    return #view.group == #Ch.group(view.group[1].x, view.group[1].y, view.group[1].z)
end

-- Сундук сломан (breakBlock): стопки высыпаются кусками rand(21) + 10 из
-- случайной точки клетки со скоростью гаусс·0.05 (вверх + 0.2). Хранилище
-- удаляется — ничего не остаётся и не удваивается.
local function gauss()
    local u, v = math.random(), math.random()
    return math.sqrt(-2 * math.log(u + 1e-12)) * math.cos(2 * math.pi * v)
end
function Ch.broken(x, y, z)
    local k = key(x, y, z)
    local c = Ch.list[k]
    if not c then return 0 end
    local Drops = require "drops"
    local spawned = 0
    for i = 1, Ch.SIZE do
        local s = c.slots[i]
        if s then
            local left = s.n
            while left > 0 do
                local n = math.min(left, rnd(21) + 10)
                left = left - n
                local px, py, pz = x + math.random() * 0.8 + 0.1, y + math.random() * 0.8 + 0.1, z + math.random() * 0.8 + 0.1
                -- Скорость у оригинала — блоков за тик; у выпавших предметов — за секунду.
                Drops.spawn(s.id, n, px, py, pz, gauss() * 0.05 * 20, (gauss() * 0.05 + 0.2) * 20, gauss() * 0.05 * 20, s.wear)
                spawned = spawned + n
            end
            c.slots[i] = nil
        end
    end
    CM.destroy(c.model)
    Ch.list[k] = nil
    return spawned
end

-- Клетка сменила блок (Act.setBlock): был сундук, стал не сундук — как
-- BlockContainer.breakBlock при любой замене: содержимое высыпается.
function Ch.replaced(x, y, z, prev, id)
    if prev == Ch.ID and id ~= Ch.ID then return Ch.broken(x, y, z) end
    return 0
end

-- --- Крышка и звуки (TileEntityChest.updateEntity) ----------------------------

local function sound(c, name)
    local sx, sz = c.x + 0.5, c.z + 0.5
    local px, _, pz = Ch.partner(c.x, c.y, c.z)
    if px and px > c.x then sx = sx + 0.5 end
    if pz and pz > c.z then sz = sz + 0.5 end
    require("sounds").event(name, sx, c.y + 0.5, sz, 0.5, math.random() * 0.1 + 0.9)
end

-- «Главная» половина: без соседа по −X и −Z — она звучит и рисует пару.
local function isMaster(c)
    return not isChestAt(c.x - 1, c.y, c.z) and not isChestAt(c.x, c.y, c.z - 1)
end
Ch.isMaster = isMaster

function Ch.tickOne(c)
    c.plid = c.lid
    local f = 0.1
    if c.users > 0 and c.lid == 0 and isMaster(c) then sound(c, "random.chestopen") end
    if (c.users == 0 and c.lid > 0) or (c.users > 0 and c.lid < 1) then
        local before = c.lid
        if c.users > 0 then c.lid = c.lid + f else c.lid = c.lid - f end
        -- Шаг 0.1 в float оригинала доходит до 1 ровно за 10 тиков; в double
        -- сумма десяти 0.1 — 0.999…, поэтому угол держится на сотых долях.
        c.lid = math.floor(c.lid * 1000 + 0.5) / 1000
        if c.lid > 1 then c.lid = 1 end
        if c.lid < 0.5 and before >= 0.5 and isMaster(c) then sound(c, "random.chestclosed") end
        if c.lid < 0 then c.lid = 0 end
    end
end

local acc = 0
local TICK = 1 / 20

-- Модель: каждая клетка рисует себя — одиночный сундук или свою половину
-- пары (левую или правую по стороне соседа). Угол крышки у обеих половин —
-- больший из двух (renderTileEntityAt), поэтому они двигаются как одна.
function Ch.modelKind(c)
    local px, _, pz = Ch.partner(c.x, c.y, c.z)
    if not px then return "single" end
    return CM.halfFor(W.meta(c.x, c.y, c.z), px - c.x, pz - c.z)
end

function Ch.lidOf(c, t)
    local a = c.plid + (c.lid - c.plid) * t
    local px, py, pz = Ch.partner(c.x, c.y, c.z)
    local o = px and Ch.list[key(px, py, pz)]
    if o then a = math.max(a, o.plid + (o.lid - o.plid) * t) end
    return a
end

local function render(c, t)
    local loaded = W.chunk(c.x // 16, c.z // 16)
    if not (loaded and loaded.built) or not isChestAt(c.x, c.y, c.z) then
        if c.model then CM.destroy(c.model); c.model = nil end
        return
    end
    local kind = Ch.modelKind(c)
    if c.model and c.model.kind ~= kind then CM.destroy(c.model); c.model = nil end
    c.model = c.model or CM.create(kind)
    local Light = require "lightmap"
    local s, b = Light.levels(c.x + 0.5, c.y + 0.5, c.z + 0.5)
    CM.pose(c.model, c.x, c.y, c.z, W.meta(c.x, c.y, c.z), Ch.lidOf(c, t), {s, b})
end

function Ch.update(dt)
    acc = acc + dt
    local n = 0
    while acc >= TICK and n < 5 do
        acc, n = acc - TICK, n + 1
        for _, c in pairs(Ch.list) do Ch.tickOne(c) end
    end
    if n == 5 then acc = 0 end
    local t = acc / TICK
    for _, c in pairs(Ch.list) do render(c, t) end
end

-- --- Сохранение (TileEntityChest.writeToNBT: Items — Slot, id, Count, Damage) --

function Ch.serialize()
    local out = {}
    for _, c in pairs(Ch.list) do
        if isChestAt(c.x, c.y, c.z) then
            local items = {}
            for i = 1, Ch.SIZE do
                local s = c.slots[i]
                if s then items[#items + 1] = {slot = i, id = s.id, n = s.n, wear = s.wear} end
            end
            out[#out + 1] = {x = c.x, y = c.y, z = c.z, items = items}
        end
    end
    return out
end

function Ch.clear()
    for _, c in pairs(Ch.list) do CM.destroy(c.model) end
    Ch.list = {}
end

function Ch.load(data)
    Ch.clear()
    if type(data) ~= "table" then return end
    for _, d in pairs(data) do
        local c = {x = d.x, y = d.y, z = d.z, slots = {}, lid = 0, plid = 0, users = 0}
        for _, it in pairs(d.items or {}) do
            if it.slot and it.slot >= 1 and it.slot <= Ch.SIZE and it.id and (it.n or 0) > 0 then
                c.slots[it.slot] = {id = it.id, n = it.n, wear = it.wear}
            end
        end
        Ch.list[key(d.x, d.y, d.z)] = c
    end
end

return Ch
