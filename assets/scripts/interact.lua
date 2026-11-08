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

local Act = {}

Act.REACH = 5
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

-- Трещина освещена как сам блок: свет каждой грани — из клетки перед ней
-- (тот же, что у грани участка). С постоянным 15/15 она светилась в тёмной
-- пещере белым узором поверх чёрного камня.
local function crackMesh(stage, bx, by, bz)
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
        local sky, blk = 15, 15
        if bx then
            local v = W.raw(bx + f.n[1], by + f.n[2], bz + f.n[3])
            if v then sky, blk = (v >> W.SKY_SHIFT) & 15, (v >> W.BLK_SHIFT) & 15 end
        end
        for k = 1, 4 do
            local p = f[k]
            for a = 1, 3 do pos[#pos + 1] = p[a] * (1 + 2 * e) - e end
            for a = 1, 3 do nrm[#nrm + 1] = f.n[a] end
            uv[#uv + 1] = tu + quv[k][1] * ts; uv[#uv + 1] = tv + quv[k][2] * ts
            uv2[#uv2 + 1] = sky; uv2[#uv2 + 1] = blk
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do idx[#idx + 1] = nv + i end
        nv = nv + 4
    end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, uv2 = uv2, index = idx}
    return m
end

-- Меш трещины пересобирается, только когда сменились стадия или блок.
local crackKey
local function showCrack(stage, t)
    local key = stage .. ":" .. t.x .. ":" .. t.y .. ":" .. t.z
    if key ~= crackKey then
        crackKey = key
        crackMesh(stage, t.x, t.y, t.z).apply(crack)
        SetMaterial(crack, "assets/materials/crack.sagemat")
    end
    crack.Transform.Position = Vec3(t.x, t.y, t.z)
end

function Act.init()
    outline = SpawnObject("Block Outline")
    outlineMesh().apply(outline)
    material("sagecraft_outline", {color = rgb(0.02, 0.02, 0.02), unlit = true})
    SetMaterial(outline, "sagecraft_outline")
    outline.Transform.Position = Vec3(0, -100, 0)
    crack = SpawnObject("Block Crack")
    crackMesh(0).apply(crack)
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
    Act.setBlock(t.x, t.y, t.z, 0)
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
    -- Соседняя вода затекает в дыру (одна клетка — без настоящего течения).
    for _, d in ipairs({{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}}) do
        if W.get(t.x + d[1], t.y + d[2], t.z + d[3]) == 11 then Act.setBlock(t.x, t.y, t.z, 11); break end
    end
    local Drops = require "drops"
    local heldNow = Inv.current()
    local special = Plants.dropsOf(id, heldNow and B.byId[heldNow.id] and B.byId[heldNow.id].shears)
    if special then
        -- Листва и трава: свои шансы (саженцы, яблоки, семена; ножницами — блок).
        Plants.spill(special, t.x, t.y, t.z)
    elseif ok then
        local drop = B.dropOf(id)
        if drop then Drops.spawn(drop, B.dropCount(id), t.x + 0.5, t.y + 0.5, t.z + 0.5) end
        local xp = B.xpOf(id)
        if xp > 0 then require("hud").addXp(xp) end
        local d = B.byId[id]
        if d.flint and math.random() < d.flint then Drops.spawn(B.byName.flint.id, 1, t.x + 0.5, t.y + 0.5, t.z + 0.5) end
    end
    Drops.burst(id, t.x + 0.5, t.y + 0.5, t.z + 0.5)
    Inv.wearTool()
    settle(t.x, t.y, t.z)
end

-- Блок, который открывается по ПКМ (печь, верстак), — с Shift нет.
local function activates(t)
    if not t or IsActionDown("Sneak") then return false end
    return require("furnace").isFurnace(t.id) or t.id == B.byName.crafting_table.id
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
    local held = Inv.current()
    if not held then return end
    local d = B.byId[held.id]
    if not d or not d.isBlock then return end
    local x, y, z = t.x + t.nx, t.y + t.ny, t.z + t.nz
    -- В траву ставится поверх (трава заменяется: isReplaceable — только у
    -- высокой травы, не у цветов и саженцев).
    local tall = B.byName.tallgrass.id
    if t.id == tall then x, y, z = t.x, t.y, t.z end
    local cur = W.get(x, y, z)
    if cur ~= 0 and B.drawKind[cur] ~= 4 and cur ~= tall then return end
    if y < 0 or y >= W.HEIGHT or not P.canPlace(x, y, z, held.id) then return end
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
    elseif d.draw == "cross" and not B.opaque[below] then return end
    if Act.setBlock(x, y, z, held.id, meta) then
        Act.stats.placed = Act.stats.placed + 1
        Snd.place(held.id, x, y, z)
        Plants.onPlace(held.id, x, y, z)
        Inv.useOne()
        Anim.swingItem()
        settle(x, y - 1, z)
        Torch.checkAround(x, y, z)
    end
end

-- actions — для автопрогона: {breaking = bool, place = bool}.
function Act.update(dt, actions)
    target = P.raycast(Act.REACH)
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
        -- Рамка — по границам блока (у факела — его рамка выбора).
        local bx = target.box or {0, 0, 0, 1, 1, 1}
        outline.Transform.Position = Vec3(target.x + bx[1], target.y + bx[2], target.z + bx[3])
        outline.Transform.Scale = Vec3(bx[4] - bx[1], bx[5] - bx[2], bx[6] - bx[3])
    else
        outline.Transform.Position = Vec3(0, -100, 0)
    end

    -- Удар по воздуху — один взмах на нажатие; по блоку — непрерывно
    -- (swingItem каждый тик, новый взмах — с середины прошлого).
    if (actions and actions.breaking) == nil and WasActionPressed("Break") then Anim.swingItem() end
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
        local need = Act.breakTime(target.id)
        local stage = math.min(9, math.floor(mining.t / need * 10))
        mining.stage = stage
        showCrack(stage, target)
        if mining.t >= need then
            breakBlock(target)
            mining = nil
            -- Пауза перед следующим блоком — 5 тиков, как у 1.7.10.
            breakCooldown = 5 / 20
            crack.Transform.Position = Vec3(0, -100, 0)
        end
    else
        mining = nil
        -- Принудительная стадия (снимки) держится на блоке и без удара.
        if not (Act.forceCrack and target) then crack.Transform.Position = Vec3(0, -100, 0) end
    end

    -- ПКМ (как в 1.7.10): блок, который открывается, — открыть; предмет с
    -- действием (еда, питьё, лук, меч) — использовать, пока держат кнопку;
    -- иначе — поставить блок. Отпустили — использование кончилось (лук стреляет).
    local held = Inv.current()
    local hd = held and B.byId[held.id]
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
            end
            placeCooldown = 0.22
        elseif placeCooldown == 0 and hd and not hd.isBlock and not activates(target) then
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
            if s and s.id == target.id then Inv.select(i); return end
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
            Hud.eat(d.food)
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
