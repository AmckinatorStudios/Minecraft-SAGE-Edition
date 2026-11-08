-- ---------------------------------------------------------------------------
-- door.lua — деревянная дверь Minecraft 1.7.10 (BlockDoor, ItemDoor).
--
-- Дверь — два блока друг над другом. Метаданные (4 бита):
--   нижняя половина — направление 0..3 (биты 0–1) и «открыта» (бит 2);
--   верхняя — флаг «верх» (бит 3) и сторона петель (бит 0: справа).
-- Полное состояние (func_150012_g) собирается из обеих половин:
--   направление | открыта·4 | верх·8 | петли_справа·16.
-- Из него — коробка полотна толщиной 3/16 (func_150011_b): она же
-- столкновение, выбор и геометрия (mesher.lua — renderBlockDoor). Модели и
-- шарнира нет: открытая дверь — та же коробка у другой стороны клетки.
--
-- Половины — одна дверь: ПКМ по любой переключает бит «открыта» нижней
-- (onBlockActivated), поломка одной убирает и вторую, а выпадает одна
-- дверь (предмет роняет только нижняя половина). Без опоры под нижней
-- половиной дверь выпадает предметом (onNeighborBlockChange).
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"

local D = {}

local F = 3 / 16   -- толщина полотна (0.1875)
D.THICK = F

local function doorId() return B.byName.door_wood.id end
D.id = doorId

function D.isDoor(id) return id == doorId() end

-- func_150012_g: полное состояние двери по клетке любой половины.
function D.fullMeta(x, y, z)
    local m = W.meta(x, y, z)
    local top = (m & 8) ~= 0
    local lower, upper
    if top then
        lower, upper = W.meta(x, y - 1, z), m
    else
        lower, upper = m, W.meta(x, y + 1, z)
    end
    local hinge = (upper & 1) ~= 0
    return (lower & 7) | (top and 8 or 0) | (hinge and 16 or 0)
end

-- То же по уже прочитанным метаданным половины и соседней (выше или ниже).
function D.fullMetaOf(m, other)
    local top = (m & 8) ~= 0
    local lower, upper = m, other
    if top then lower, upper = other, m end
    return (lower & 7) | (top and 8 or 0) | (((upper & 1) ~= 0) and 16 or 0)
end

-- func_150011_b: коробка половины по полному состоянию.
function D.box(full)
    local j = full & 3
    local open = (full & 4) ~= 0
    local hinge = (full & 16) ~= 0
    if j == 0 then
        if open then
            if not hinge then return {0, 0, 0, 1, 1, F} end
            return {0, 0, 1 - F, 1, 1, 1}
        end
        return {0, 0, 0, F, 1, 1}
    elseif j == 1 then
        if open then
            if not hinge then return {1 - F, 0, 0, 1, 1, 1} end
            return {0, 0, 0, F, 1, 1}
        end
        return {0, 0, 0, 1, 1, F}
    elseif j == 2 then
        if open then
            if not hinge then return {0, 0, 1 - F, 1, 1, 1} end
            return {0, 0, 0, 1, 1, F}
        end
        return {1 - F, 0, 0, 1, 1, 1}
    end
    if open then
        if not hinge then return {0, 0, 0, F, 1, 1} end
        return {1 - F, 0, 0, 1, 1, 1}
    end
    return {0, 0, 1 - F, 1, 1, 1}
end

-- Зеркалить ли картинку стороны side (2..5) — BlockDoor.getIcon(world, …).
function D.flipped(full, side)
    local j = full & 3
    local flip = false
    if (full & 4) ~= 0 then
        if (j == 0 and side == 2) or (j == 1 and side == 5) or (j == 2 and side == 3) or (j == 3 and side == 4) then
            flip = not flip
        end
    else
        if (j == 0 and side == 5) or (j == 1 and side == 3) or (j == 2 and side == 4) or (j == 3 and side == 2) then
            flip = not flip
        end
        if (full & 16) ~= 0 then flip = not flip end
    end
    return flip
end

-- Опора под нижней половиной (World.doesBlockHaveSolidTopSurface): глухой куб.
local function supports(id) return B.opaque[id] == true end

-- Клетка, куда можно ставить половину (Block.canPlaceBlockAt: заменяемая).
local function replaceable(id)
    return id == 0 or B.drawKind[id] == 4 or id == B.byName.tallgrass.id
end

-- Направление двери по повороту игрока: у оригинала
-- floor((rotationYaw + 180)·4/360 − 0.5) & 3, где rotationYaw = 180 − наш yaw
-- (наш 0 смотрит в −Z, у оригинала 0 — в +Z).
function D.facingFromYaw(yaw)
    local mc = 180 - yaw
    return math.floor((mc + 180) * 4 / 360 - 0.5) & 3
end

-- ItemDoor.onItemUse + placeDoorBlock: дверь ставится только на верх блока
-- (side 1) в клетку над ним. Петли — справа, если дверь уже стоит слева и не
-- справа, или справа больше глухих блоков, чем слева. Возвращает клетку
-- нижней половины или nil.
function D.place(setBlock, x, y, z, yaw)
    if y < 1 or y + 1 >= W.HEIGHT then return nil end
    if not replaceable(W.get(x, y, z)) or not replaceable(W.get(x, y + 1, z)) then return nil end
    if not supports(W.get(x, y - 1, z)) then return nil end
    local dir = D.facingFromYaw(yaw)
    local b0, b1 = 0, 0
    if dir == 0 then b1 = 1 elseif dir == 1 then b0 = -1 elseif dir == 2 then b1 = -1 else b0 = 1 end
    local function cube(xx, yy, zz) return B.opaque[W.get(xx, yy, zz)] and 1 or 0 end
    local left = cube(x - b0, y, z - b1) + cube(x - b0, y + 1, z - b1)
    local right = cube(x + b0, y, z + b1) + cube(x + b0, y + 1, z + b1)
    local id = doorId()
    local doorLeft = W.get(x - b0, y, z - b1) == id or W.get(x - b0, y + 1, z - b1) == id
    local doorRight = W.get(x + b0, y, z + b1) == id or W.get(x + b0, y + 1, z + b1) == id
    local hinge = false
    if doorLeft and not doorRight then hinge = true
    elseif right > left then hinge = true end
    setBlock(x, y, z, id, dir)
    setBlock(x, y + 1, z, id, 8 | (hinge and 1 or 0))
    return x, y, z
end

-- Клетка нижней половины по любой.
function D.lowerOf(x, y, z)
    if (W.meta(x, y, z) & 8) ~= 0 then return x, y - 1, z end
    return x, y, z
end

-- Звук переключения — один раз на нажатие: открыть — door_open, закрыть —
-- door_close (громкость 1, высота rand·0.1 + 0.9 оригинала).
local function sound(open, x, y, z)
    local f = open and "assets/sounds/random/door_open.ogg" or "assets/sounds/random/door_close.ogg"
    PlaySound3D(f, Vec3(x + 0.5, y + 0.5, z + 0.5), 1.0, math.random() * 0.1 + 0.9)
end
D.sound = sound

-- onBlockActivated: бит «открыта» нижней половины меняется, обе половины
-- перестраиваются (верхняя рисуется по метаданным нижней). true — открыта.
function D.toggle(setBlock, x, y, z)
    local lx, ly, lz = D.lowerOf(x, y, z)
    local m = W.meta(lx, ly, lz) ~ 4
    setBlock(lx, ly, lz, doorId(), m)
    W.markDirty(lx, ly + 1, lz)
    local open = (m & 4) ~= 0
    sound(open, lx, ly, lz)
    return open
end

-- Поломка половины (x, y, z): вторая убирается (у оригинала — через
-- onNeighborBlockChange), выпадает одна дверь — за нижнюю половину.
-- Возвращает клетку, где ронять предмет.
function D.onBreak(setBlock, x, y, z, meta)
    local id = doorId()
    if (meta & 8) ~= 0 then
        if W.get(x, y - 1, z) == id then setBlock(x, y - 1, z, 0) end
        return x, y - 1, z
    end
    if W.get(x, y + 1, z) == id then setBlock(x, y + 1, z, 0) end
    return x, y, z
end

-- Под клеткой (x, y, z) что-то поменялось: нижняя половина над ней без опоры
-- выпадает предметом вместе с верхней. true — дверь сломалась.
function D.checkSupport(setBlock, x, y, z)
    local id = doorId()
    if W.get(x, y + 1, z) ~= id or (W.meta(x, y + 1, z) & 8) ~= 0 then return false end
    if supports(W.get(x, y, z)) then return false end
    setBlock(x, y + 1, z, 0)
    if W.get(x, y + 2, z) == id then setBlock(x, y + 2, z, 0) end
    require("drops").spawn(B.byName.wooden_door.id, 1, x + 0.5, y + 1.5, z + 0.5)
    return true
end

-- Самопроверка (--gencheck, строка DOORCHECK): постановка, петли, коробки
-- закрытой и открытой двери, переключение с любой половины, поломка.
function D.selfCheck()
    local Act = require "interact"
    local set = Act.setBlock
    local x, z = 70, 70
    local y = W.surface(x, z) + 1
    for yy = y, y + 3 do for dx = -2, 2 do for dz = -2, 2 do W.setId(x + dx, yy, z + dz, 0) end end end
    for dx = -2, 2 do for dz = -2, 2 do set(x + dx, y - 1, z + dz, B.byName.stone.id) end end
    -- Игрок смотрит на восток (+X): наш yaw −90 → направление 0.
    local facingOk = D.facingFromYaw(-90) == 0 and D.facingFromYaw(0) == 3 and D.facingFromYaw(90) == 2
        and D.facingFromYaw(180) == 1
    D.place(set, x, y, z, -90)
    local placed = W.get(x, y, z) == doorId() and W.get(x, y + 1, z) == doorId()
        and W.meta(x, y, z) == 0 and (W.meta(x, y + 1, z) & 8) ~= 0
    local closed = D.box(D.fullMeta(x, y, z))
    local closedOk = closed[1] == 0 and math.abs(closed[4] - F) < 1e-9 and closed[6] == 1
    -- Переключение с ВЕРХНЕЙ половины открывает всю дверь.
    D.toggle(set, x, y + 1, z)
    local openFull = D.fullMeta(x, y + 1, z)
    local open = D.box(openFull)
    local openOk = (W.meta(x, y, z) & 4) ~= 0 and (openFull & 8) ~= 0 and math.abs(open[6] - F) < 1e-9
        and open[4] == 1
    -- Петли справа: у справа стоящей стены (z + 1 у направления 0) — бит 1 верха.
    set(x + 2, y, z + 1, B.byName.stone.id); set(x + 2, y + 1, z + 1, B.byName.stone.id)
    D.place(set, x + 2, y, z, -90)
    local hingeOk = (W.meta(x + 2, y + 1, z) & 1) == 1
    -- Поломка верхней половины убирает и нижнюю.
    local bx, by, bz = D.onBreak(set, x, y + 1, z, W.meta(x, y + 1, z))
    set(x, y + 1, z, 0)
    local brokeOk = W.get(x, y, z) == 0 and by == y and bx == x and bz == z
    local ok = facingOk and placed and closedOk and openOk and hingeOk and brokeOk
    return string.format("DOORCHECK: %s направление=%s поставлена=%s закрыта=%s открыта=%s петли=%s поломка=%s",
        ok and "PASS" or "FAIL", tostring(facingOk), tostring(placed), tostring(closedOk), tostring(openOk),
        tostring(hingeOk), tostring(brokeOk))
end

return D
