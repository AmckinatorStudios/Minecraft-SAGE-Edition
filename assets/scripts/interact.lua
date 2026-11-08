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
local Snd = require "sounds"
local Plants = require "plants"
local Torch = require "torch"
local B = require "blocks"
local A = require "atlas"
local L = require "light"
local P = require "player"
local Inv = require "inventory"
local C = require "chunks"
local Anim = require "anim"
local Bo = require "bounds"
local Door = require "door"

local Act = {}

Act.REACH = 5
Act.stats = {broken = 0, placed = 0, picked = 0}
local target
local mining = nil          -- {x, y, z, t}
local outline = {}          -- {obj, th}
local crack
local placeCooldown = 0
local breakCooldown = 0

-- Рамка выбора (RenderGlobal.drawSelectionBox): рёбра коробки выбора,
-- расширенной на 0.002 (иначе рамка спорит с гранью за глубину), чёрные с
-- прозрачностью 0.4, толщиной около 2 экранных пикселей (glLineWidth(2)).
-- Линий в движке нет — рёбра брусками, толщина которых пересчитывается по
-- расстоянию до рамки, полю зрения и высоте экрана: на экране она остаётся
-- те же 2 пикселя и вблизи, и вдали.
local OUTLINE_GROW = 0.002
local OUTLINE_PX = 2
local function outlineMesh(b, t)
    local m = mesh()
    local g = OUTLINE_GROW
    local x0, y0, z0, x1, y1, z1 = b[1] - g, b[2] - g, b[3] - g, b[4] + g, b[5] + g, b[6] + g
    local function bar(ax, ay, az, bx, by, bz)
        local w = box(math.abs(bx - ax) + t, math.abs(by - ay) + t, math.abs(bz - az) + t)
        w.move((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2)
        m.add(w)
    end
    for _, a in ipairs({y0, y1}) do
        for _, c in ipairs({z0, z1}) do bar(x0, a, c, x1, a, c) end
        for _, c in ipairs({x0, x1}) do bar(c, a, z0, c, a, z1) end
    end
    for _, a in ipairs({x0, x1}) do
        for _, c in ipairs({z0, z1}) do bar(a, y0, c, a, y1, c) end
    end
    return m
end

-- Толщина бруска рамки в блоках для OUTLINE_PX пикселей на расстоянии d.
local function outlineThickness(d)
    local cam = FindObject("Player Camera")
    local c = cam and cam:GetCamera()
    local fov = c and c.Fov or 70
    local size = UIScreenSize()
    local hpx = (size and size.y and size.y > 0) and size.y or 720
    return OUTLINE_PX * 2 * math.max(d, 0.05) * math.tan(math.rad(fov) / 2) / hpx
end

local outlineKey
local function showOutline(t)
    if not outline.obj then return end     -- до Act.init (самопроверки)
    local b = t.box or {0, 0, 0, 1, 1, 1}
    local ex, ey, ez = P.eye()
    local cx, cy, cz = t.x + (b[1] + b[4]) / 2, t.y + (b[2] + b[5]) / 2, t.z + (b[3] + b[6]) / 2
    local d = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2 + (cz - ez) ^ 2)
    local th = outlineThickness(d)
    -- Пересборка — когда сменилась коробка или толщина ушла больше чем на 8 %.
    local key = table.concat(b, ",")
    if key ~= outlineKey or not outline.th or math.abs(th - outline.th) > outline.th * 0.08 then
        outlineKey, outline.th = key, th
        outlineMesh(b, th).apply(outline.obj)
        SetMaterial(outline.obj, "sagecraft_outline")
    end
    outline.obj.Transform.Position = Vec3(t.x, t.y, t.z)
end

-- Трещины (RenderGlobal.drawBlockDamageTexture): та же геометрия блока
-- (Render Bounds: у факела — его плоскости, у растения — крест) с плиткой
-- стадии destroy_stage_N; смешение GL_DST_COLOR, GL_SRC_COLOR и смещение
-- глубины −3 — в материале crack.sagemat. Меш пересобирается, только когда
-- сменились стадия, блок или его метаданные; новая стадия заменяет прежнюю.
local crackKey
local function showCrack(stage, t)
    if not crack then return end
    local key = stage .. ":" .. t.x .. ":" .. t.y .. ":" .. t.z .. ":" .. t.id .. ":" .. (t.meta or 0)
    if key ~= crackKey then
        crackKey = key
        local m = mesh()
        m.arrays(require("mesher").single(t.id, t.meta or 0, A.destroyTile[stage], t.x, t.y, t.z))
        m.apply(crack)
        SetMaterial(crack, "assets/materials/crack.sagemat")
    end
    crack.Transform.Position = Vec3(t.x, t.y, t.z)
end

local function hideCrack()
    if not crack then return end
    crack.Transform.Position = Vec3(0, -100, 0)
    crackKey = nil
end

function Act.init()
    outline.obj = SpawnObject("Block Outline")
    -- Чёрный с альфой 0.4 оригинала: он смешивает в sRGB (фон × 0.6), кадр
    -- движка линейный — там то же затемнение даёт альфа 1 − 0.6^2.2 ≈ 0.675.
    material("sagecraft_outline", {color = rgb(0, 0, 0), unlit = true, opacity = 0.675})
    outlineMesh(Bo.FULL, 0.01).apply(outline.obj)
    SetMaterial(outline.obj, "sagecraft_outline")
    outline.obj.Transform.Position = Vec3(0, -100, 0)
    crack = SpawnObject("Block Crack")
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
    if tool and tool.tool == "sword" and B.isLeaves[id] then speed = 1.5 end
    -- Ножницы (ItemShears.func_150893_a): листва — 15, шерсть — 5.
    if tool and tool.shears then
        if B.isLeaves[id] then speed = 15 elseif d.name:find("wool") then speed = 5 end
    end
    local ok = (d.need or 0) <= tier
    -- Неподходящим инструментом (или руками по камню) — втрое дольше.
    local t = d.hard * (ok and 1.5 or 5) / speed
    return math.max(0.05, t), ok
end

-- Песок и гравий над пустотой падают: каждый блок столба над (x, y, z)
-- становится падающим телом (falling.lua) — снизу вверх, и столб летит вниз
-- целиком, как в Minecraft.
local function settle(x, y, z)
    local Fall = require "falling"
    if not Fall.passable(W.get(x, y, z)) then return end
    for yy = y + 1, W.HEIGHT - 1 do
        local id = W.get(x, yy, z)
        if not (B.byId[id] and B.byId[id].falls) then break end
        Act.setBlock(x, yy, z, 0)
        Fall.spawn(id, x, yy, z)
    end
end
Act.settle = settle

-- Поставить блок в мир: клетка, свет, пересборка, запись правки.
function Act.setBlock(x, y, z, id, meta)
    if not W.setId(x, y, z, id) then return false end
    if meta then W.setMeta(x, y, z, meta) end
    C.recordEdit(x, y, z, id, meta)
    L.update(x, y, z)
    W.markDirty(x, y, z)
    -- Грядка и пшеница: учёт клеток и соседи (onNeighborBlockChange).
    require("crops").onSet(x, y, z, id)
    return true
end

local function breakBlock(t)
    local id = t.id
    Act.stats.broken = Act.stats.broken + 1
    local _, ok = Act.breakTime(id)
    -- Звук поломки — до того, как клетка опустеет (материал — у блока).
    Snd.dig(id, t.x, t.y, t.z)
    -- Содержимое печи — на землю, как в Minecraft.
    if require("furnace").isFurnace(id) then require("furnace").broken(t.x, t.y, t.z) end
    -- Сундук (BlockChest.breakBlock): содержимое высыпается, хранилище удаляется.
    if require("chest").isChest(id) then require("chest").broken(t.x, t.y, t.z) end
    Act.setBlock(t.x, t.y, t.z, 0)
    -- Дверь: вторая половина уходит следом, предмет — один, из нижней клетки.
    local dropX, dropY, dropZ = t.x, t.y, t.z
    if Door.isDoor(id) then dropX, dropY, dropZ = Door.onBreak(Act.setBlock, t.x, t.y, t.z, t.meta or W.meta(t.x, t.y, t.z)) end
    Plants.onBreak(id, t.x, t.y, t.z)
    -- Растение над сломанным блоком без опоры ломается само (checkAndDropBlock)
    -- и роняет то же, что при поломке рукой.
    local above = W.get(t.x, t.y + 1, t.z)
    if B.drawKind[above] == 3 then   -- факел — Torch.checkAround (у него своя опора)
        Act.setBlock(t.x, t.y + 1, t.z, 0)
        Plants.onBreak(above, t.x, t.y + 1, t.z)
        Plants.spill(Plants.dropsOf(above, false) or {{B.dropOf(above), 1}}, t.x, t.y + 1, t.z)
    end
    -- Факелы, державшиеся за этот блок, падают предметом.
    Torch.checkAround(t.x, t.y, t.z)
    -- Люки, державшиеся за этот блок, падают предметом.
    require("trapdoor").checkAround(Act.setBlock, t.x, t.y, t.z)
    -- Лестницы, державшиеся за этот блок, падают предметом.
    require("ladder").checkAround(Act.setBlock, t.x, t.y, t.z)
    -- Дверь, стоявшая на этом блоке, выпадает предметом.
    Door.checkSupport(Act.setBlock, t.x, t.y, t.z)
    -- Соседняя вода затекает в дыру (одна клетка — без настоящего течения).
    for _, d in ipairs({{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}}) do
        if W.get(t.x + d[1], t.y + d[2], t.z + d[3]) == 11 then Act.setBlock(t.x, t.y, t.z, 11); break end
    end
    local Drops = require "drops"
    local heldNow = Inv.current()
    local special = Plants.dropsOf(id, heldNow and B.byId[heldNow.id] and B.byId[heldNow.id].shears)
    -- Пшеница: семя, а зрелая — пшеница и до трёх семян (BlockCrops).
    if require("crops").isCrop(id) then special = require("crops").dropsOf(t.meta or 0) end
    if special then
        -- Листва и трава: свои шансы (саженцы, яблоки, семена; ножницами — блок).
        Plants.spill(special, t.x, t.y, t.z)
    elseif ok then
        local drop = Act.harvestDrop(id, math.random())
        if drop then Drops.spawn(drop, B.dropCount(id), dropX + 0.5, dropY + 0.5, dropZ + 0.5) end
        local xp = B.xpOf(id)
        if xp > 0 then require("hud").addXp(xp) end
    end
    -- Усталость за поломку блока (Block.harvestBlock: 0.025).
    require("hud").addExhaustion(0.025)
    -- 64 осколка сеткой 4×4×4 (addBlockDestroyEffects) — из метаданных до поломки.
    require("particles").destroy(id, t.meta or 0, t.x, t.y, t.z)
    -- Мотыга от поломки блоков не изнашивается (у ItemHoe нет onBlockDestroyed).
    local hd = heldNow and B.byId[heldNow.id]
    if not (hd and hd.tool == "hoe") then Inv.wearTool() end
    settle(t.x, t.y, t.z)
end

-- Блок, который открывается по ПКМ (печь, верстак), — с Shift нет.
local function activates(t)
    if not t or IsActionDown("Sneak") then return false end
    return require("furnace").isFurnace(t.id) or t.id == B.byName.crafting_table.id or Door.isDoor(t.id)
        or require("chest").isChest(t.id)
        or require("trapdoor").isTrapdoor(t.id)
end

local function place(t)
    if require("furnace").isFurnace(t.id) and activates(t) then
        Act.openFurnace = {x = t.x, y = t.y, z = t.z}
        return
    end
    if t.id == B.byName.crafting_table.id and activates(t) then
        Act.openTable = true
        return
    end
    -- Сундук (onBlockActivated): окно, если сверху не глухой куб; иначе
    -- ничего (и блок на сундук не ставится — ПКМ ушёл на сундук).
    if require("chest").isChest(t.id) and activates(t) then
        require("chest").open(t.x, t.y, t.z)
        return
    end
    -- Дверь (onBlockActivated): ПКМ по любой половине — открыть/закрыть всю.
    if Door.isDoor(t.id) and activates(t) then
        Door.toggle(Act.setBlock, t.x, t.y, t.z)
        Anim.swingItem()
        return
    end
    -- Люк (onBlockActivated): ПКМ — открыть/закрыть.
    if require("trapdoor").isTrapdoor(t.id) and activates(t) then
        require("trapdoor").toggle(Act.setBlock, t.x, t.y, t.z)
        Anim.swingItem()
        return
    end
    local held = Inv.current()
    if not held then return end
    local d = B.byId[held.id]
    -- Предмет «дверь» (ItemDoor): только на верх блока, две половины сразу.
    if d and d.places == "door_wood" then
        if t.ny ~= 1 then return end
        if Door.place(Act.setBlock, t.x, t.y + 1, t.z, P.yaw) then
            Act.stats.placed = Act.stats.placed + 1
            Inv.useOne()
            Anim.swingItem()
        end
        return
    end
    if not d or not d.isBlock then return end
    local x, y, z = t.x + t.nx, t.y + t.ny, t.z + t.nz
    -- В траву ставится поверх (трава заменяется: isReplaceable — только у
    -- высокой травы, не у цветов и саженцев).
    local tall = B.byName.tallgrass.id
    if t.id == tall then x, y, z = t.x, t.y, t.z end
    local cur = W.get(x, y, z)
    if cur ~= 0 and B.drawKind[cur] ~= 4 and cur ~= tall then return end
    if y < 0 or y >= W.HEIGHT then return end
    -- Трава, цветы, саженцы — на траву или землю (BlockBush.canPlaceBlockOn);
    -- тростник и факел — на твёрдую опору.
    local below = W.get(x, y - 1, z)
    local meta
    if d.draw == "cross" and d.name ~= "reeds" then
        if not Plants.soil(below) then return end
    elseif d.draw == "torch" then
        -- Факел: ориентация — по грани клика (на стену или на пол), опора
        -- обязана держать этой стороной.
        meta = Torch.metaFor(x, y, z, t.nx, t.ny, t.nz)
        if not meta then return end
    elseif d.draw == "cross" and not B.opaque[below] then return
    elseif d.draw == "trapdoor" then
        -- Люк (onBlockPlaced): только боковая грань; вверху клетки — если
        -- попали в верхнюю половину грани (hitY оригинала).
        local _, ey = P.eye()
        local _, ly = P.lookDir()
        local hitY = ey + ly * t.dist - t.y
        meta = require("trapdoor").metaFor(x, y, z, require("particles").sideOf(t.nx, t.ny, t.nz), hitY)
        if not meta then return end
    elseif d.draw == "ladder" then
        -- Лестница (onBlockPlaced): сторона — по грани клика, опора сзади.
        meta = require("ladder").metaFor(x, y, z, require("particles").sideOf(t.nx, t.ny, t.nz))
        if not meta then return end
    elseif d.facing then
        -- Печь, тыква — лицом к игроку (onBlockPlacedBy).
        meta = B.placeMeta(held.id, P.yaw)
    end
    -- Сундук: не больше одного соседа-сундука без своей пары; сторона — к
    -- игроку и общая с парой.
    local chestPair
    if require("chest").isChest(held.id) then
        if not require("chest").canPlace(x, y, z) then return end
        meta, chestPair = require("chest").placeMeta(x, y, z, P.yaw)
    end
    -- Внутрь игрока — нельзя, но мешает только НАСТОЯЩАЯ коробка столкновения
    -- блока с его метаданными (canPlaceEntityOnSide): лестница — пластина у
    -- стены, факел и растение — ничего. Раньше проверка шла до расчёта
    -- стороны, и лестница считалась полным кубом: у соседней стены не ставилась.
    if not P.canPlace(x, y, z, held.id, meta) then return end
    if Act.setBlock(x, y, z, held.id, meta) then
        Act.stats.placed = Act.stats.placed + 1
        Snd.place(held.id, x, y, z)
        Plants.onPlace(held.id, x, y, z)
        if require("chest").isChest(held.id) then require("chest").placed(x, y, z, meta, chestPair, Act.setBlock) end
        Inv.useOne()
        Anim.swingItem()
        settle(x, y - 1, z)
        Torch.checkAround(x, y, z)
    end
end

-- Что роняет блок id при броске roll (0..1). Гравий (BlockGravel.
-- getItemDropped): с шансом 1/10 кремень ВМЕСТО себя, а не вдобавок —
-- иначе каждый блок возвращал и гравий, и кремень (бесконечный кремень).
function Act.harvestDrop(id, roll)
    local d = B.byId[id]
    if d and d.flint and roll < d.flint then return B.byName.flint.id end
    return B.dropOf(id)
end

-- ПКМ с предметом — «использовать» (еда, лук, карта), а не ставить блок.
-- Предмет, который ставит блок (дверь: places), — постановка.
function Act.isUseItem(d)
    return d ~= nil and not d.isBlock and not d.places
end

-- actions — для автопрогона: {breaking = bool, place = bool}.
function Act.update(dt, actions)
    target = P.raycast(Act.REACH)
    -- Существо под прицелом (getMouseOver): ближе блока и не дальше 3 блоков
    -- в выживании — тогда блок не выбран, ЛКМ бьёт, ПКМ — взаимодействие.
    local Pig = require "pig"
    do
        local ox, oy, oz = P.eye()
        local dx, dy, dz = P.lookDir()
        Act.pig = Pig.raycast(ox, oy, oz, dx, dy, dz, math.min(3, target and target.dist or 3))
        if Act.pig then target = nil end
    end
    local breaking = actions and actions.breaking or IsActionDown("Break")
    local placing = actions and actions.place or IsActionDown("Place") or Act.forcePlace
    if Act.forceSwing then Anim.swingItem() end
    placeCooldown = math.max(0, placeCooldown - dt)
    breakCooldown = math.max(0, breakCooldown - dt)

    if Act.forceCrack and target then
        -- Отладка снимков: показать трещину этой стадии на блоке под прицелом.
        showCrack(Act.forceCrack, target)
    end
    if target then
        -- Рамка — по коробке выбора блока (bounds.lua), а не по клетке.
        showOutline(target)
    elseif outline.obj then
        outline.obj.Transform.Position = Vec3(0, -100, 0)
    end

    -- Удар по воздуху — один взмах на нажатие; по блоку — непрерывно
    -- (swingItem каждый тик, новый взмах — с середины прошлого).
    if (actions and actions.breaking) == nil and WasActionPressed("Break") then Anim.swingItem() end
    -- Удар существа — один на нажатие (clickMouse → attackEntity).
    if Act.pig and (actions and actions.breaking) == nil and WasActionPressed("Break") then
        Pig.attack(Act.pig, P, Inv.current())
    end
    if breaking and target and breakCooldown == 0 then
        Anim.swingItem()
        -- Другой блок под прицелом — прогресс и счёт ударов заново (1.7.10).
        if not mining or mining.x ~= target.x or mining.y ~= target.y or mining.z ~= target.z then
            mining = {x = target.x, y = target.y, z = target.z, t = 0, nextHit = 0}
        end
        mining.t = mining.t + dt
        -- Удар — каждые 4 игровых тика (0.2 с), первый — сразу.
        while mining.t >= mining.nextHit do
            Snd.hit(target.id, target.x, target.y, target.z)
            mining.nextHit = mining.nextHit + 4 / 20
        end
        -- Осколок у грани удара — каждый тик добычи (addBlockHitEffects).
        mining.nextFx = mining.nextFx or 0
        while mining.t >= mining.nextFx do
            local Pt = require "particles"
            Pt.hit(target.id, target.meta or 0, target.x, target.y, target.z, Pt.sideOf(target.nx, target.ny, target.nz))
            mining.nextFx = mining.nextFx + 1 / 20
        end
        local need = Act.breakTime(target.id)
        local stage = math.min(9, math.floor(mining.t / need * 10))
        mining.stage = stage
        showCrack(stage, target)
        if mining.t >= need then
            breakBlock(target)
            mining = nil
            -- Пауза перед следующим блоком — 5 тиков, как у 1.7.10.
            breakCooldown = 5 / 20
            hideCrack()
        end
    else
        mining = nil
        -- Принудительная стадия (снимки) держится на блоке и без удара.
        if not (Act.forceCrack and target) then hideCrack() end
    end

    -- ПКМ (как в 1.7.10): блок, который открывается, — открыть; предмет с
    -- действием (еда, питьё, лук, меч) — использовать, пока держат кнопку;
    -- иначе — поставить блок. Отпустили — использование кончилось (лук стреляет).
    local held = Inv.current()
    local hd = held and B.byId[held.id]
    -- ПКМ по существу (interactWithEntitySending): морковь свинье — любовь;
    -- не взяла — предмет используется как обычно (морковь съедается).
    if placing and Act.pig and not Anim.use and placeCooldown == 0 and Pig.interact(Act.pig, held) then
        Inv.useOne()
        placeCooldown = 0.22
        placing = false
        held = Inv.current()
    end
    if placing then
        if Anim.use then
            -- уже используется
        elseif placeCooldown == 0 and hd and hd.use and not activates(target) then
            Act.startUse(held, hd)
            placeCooldown = 0.22
        elseif placeCooldown == 0 and hd and hd.name == "bone_meal" and target then
            -- Костная мука по саженцу (ItemDye.applyBonemeal): тратится одна.
            if Plants.boneMeal(target.x, target.y, target.z) then
                Inv.useOne()
                Anim.swingItem()
            elseif require("crops").boneMeal(target.x, target.y, target.z) then
                -- Пшеница (IGrowable): мука тратится, искры по высоте блока.
                Plants.happy(target.x, target.y, target.z, 0.25)
                Inv.useOne()
                Anim.swingItem()
            end
            placeCooldown = 0.22
        -- Мотыга и семена (ItemHoe/ItemSeeds.onItemUse) — по блоку под прицелом.
        elseif placeCooldown == 0 and hd and (hd.tool == "hoe" or hd.plants) and target and not activates(target) then
            if require("crops").use(target, held) then Anim.swingItem() end
            placeCooldown = 0.22
        -- Предмет, который ставит блок (дверь), — не «использование», а постановка:
        -- раньше ПКМ с дверью уходила сюда, и дверь не ставилась вовсе.
        elseif placeCooldown == 0 and hd and Act.isUseItem(hd) and not activates(target) then
            Act.useItem(held, hd)
            placeCooldown = 0.22
        elseif target and placeCooldown == 0 then
            place(target)
            placeCooldown = 0.22
        end
    else
        placeCooldown = 0
        local u = Anim.use
        if u then
            Anim.stopUse()
            if u.action == "bow" then Act.releaseBow(u) end
        end
    end

    if WasActionPressed("Pick") and target then
        for i = 1, 9 do
            local s = Inv.slots[i]
            -- Дверь в мире — блок, в руке — предмет (Block.getItem).
            local want = B.byId[target.id] and B.byId[target.id].item and B.byName[B.byId[target.id].item].id or target.id
            if s and s.id == want then Inv.select(i); return end
        end
    end
    -- Q — один предмет из выбранной ячейки, Ctrl+Q — всю стопку
    -- (dropOneItem(GuiScreen.isCtrlKeyDown())).
    if WasActionPressed("Drop") then
        local s = Inv.current()
        if s then
            local all = Input.is_key_down("LeftControl") or Input.is_key_down("Control")
            local n = all and s.n or 1
            require("drops").throwFromPlayer(s.id, n, s.wear)
            if all then Inv.slots[Inv.selected] = nil else Inv.useOne() end
        end
    end
end

-- --- Использование предметов (ПКМ) ----------------------------------------

-- Звук еды или питья у игрока (EntityPlayer.updateItemUse).
local function useSound(kind)
    local x, y, z = require("player").eye()
    if kind == "eat" then Snd.eat(x, y, z) else Snd.drink(x, y, z) end
end

-- Каждый тик использования: звук, когда до конца осталось не больше 25
-- тиков и их число кратно 4 (EntityPlayer.onUpdate) — при 32 тиках это
-- 24, 20, 16, 12, 8, 4 и ещё один в конце (onItemUseFinish).
local function useTick(kind)
    return function(u)
        if u.count <= 25 and u.count % 4 == 0 then useSound(kind) end
    end
end

-- Начать использовать: еда и питьё — 32 тика, лук и меч — пока держат.
function Act.startUse(stack, d)
    if d.use == "eat" then
        local Hud = require "hud"
        -- Сытый не ест (canEat); без голода в игре — ест всегда.
        if Hud.HUNGER and Hud.food >= 20 then return end
        Anim.startUse(stack.id, "eat", 32, function()
            -- onItemUseFinish: ещё один звук еды, затем onEaten — отрыжка.
            useSound("eat")
            Hud.eat(d.food, d.sat)
            Inv.useOne()
            local x, y, z = require("player").eye()
            Snd.burp(x, y, z)
        end, useTick("eat"))
    elseif d.use == "drink" then
        Anim.startUse(stack.id, "drink", 32, function()
            useSound("drink")
            -- Выпитая бутылка с водой — пустая бутылка (ItemPotion.onEaten).
            Inv.useOne()
            if Inv.current() then Inv.add(B.byName.glass_bottle.id, 1)
            else Inv.slots[Inv.selected] = {id = B.byName.glass_bottle.id, n = 1} end
        end, useTick("drink"))
    elseif d.use == "block" then
        Anim.startUse(stack.id, "block", 72000)
    elseif d.use == "bow" then
        -- Без стрел лук не натягивается (ItemBow.onItemRightClick).
        if Inv.count(B.byName.arrow.id) > 0 or Act.creative then Anim.startUse(stack.id, "bow", 72000) end
    end
end

-- Выстрел при отпускании (ItemBow.onPlayerStoppedUsing).
function Act.releaseBow(u)
    local Ar = require "arrows"
    local power = Ar.power(u.max - u.count)
    if not power then return end
    Ar.fire(P, power)
    if not Act.creative then Inv.take(B.byName.arrow.id, 1) end
end

-- Предметы без «использования», но с действием по ПКМ.
function Act.useItem(stack, d)
    if d.name == "glass_bottle" then
        -- Бутылка набирает воду, если взгляд упирается в воду (ItemGlassBottle).
        local ex, ey, ez = P.eye()
        local dx, dy, dz = P.lookDir()
        for i = 1, 50 do
            local t = i * 0.1
            local x, y, z = math.floor(ex + dx * t), math.floor(ey + dy * t), math.floor(ez + dz * t)
            local id = W.get(x, y, z)
            if id == 11 then
                Inv.useOne()
                local potion = B.byName.potion.id
                if Inv.current() then Inv.add(potion, 1) else Inv.slots[Inv.selected] = {id = potion, n = 1} end
                return
            end
            if B.solid[id] then return end
        end
    elseif d.name == "empty_map" then
        -- Пустая карта — карта этого места (ItemEmptyMap.onItemRightClick).
        local n = require("map").create(P.pos.x, P.pos.z)
        Inv.useOne()
        local s = {id = B.byName.filled_map.id, n = 1, wear = n}
        if Inv.current() then
            for i = 1, Inv.SIZE do if not Inv.slots[i] then Inv.slots[i] = s; return end end
            require("drops").spawnAtPlayer(s.id, 1)
        else
            Inv.slots[Inv.selected] = s
        end
    end
end

Act.target = function() return target end

return Act
