-- ---------------------------------------------------------------------------
-- chestcheck.lua — самопроверка сундука (--gencheck, строка CHESTCHECK):
-- постановка (лицом к игроку, пара, запрет тройных и связок через угол),
-- общая сторона пары, окно на 27 и 54 (порядок половин), запрет открытия
-- под глухим кубом, крышка по тикам (+0.1 до 1, −0.1 до 0) и звуки — по
-- одному открытию и закрытию, формула угла, Shift+ЛКМ туда и обратно,
-- цифры панели, высыпание без потерь и удвоения, сохранение ячеек,
-- раскладка окна generic_54 и звуки пшеницы и свиньи.
-- Площадка после проверки убирается.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Ch = require "chest"
local CM = require "chestmodel"

local CC = {}

function CC.selfCheck(P)
    local Act = require "interact"
    local Inv = require "inventory"
    local Snd = require "sounds"
    local bx, bz = math.floor(P.pos.x) - 30, math.floor(P.pos.z) + 25
    local by = math.min(W.HEIGHT - 12, math.floor(P.pos.y) + 30)
    local touched = {}
    for x = 0, 12 do
        for z = 0, 8 do
            touched[#touched + 1] = {bx + x, by, bz + z}
            W.setId(bx + x, by, bz + z, B.byName.stone.id)
            for y = 1, 3 do
                touched[#touched + 1] = {bx + x, by + y, bz + z}
                W.setId(bx + x, by + y, bz + z, 0)
            end
        end
    end
    local y = by + 1
    local function place(x, z, yaw)
        if not Ch.canPlace(bx + x, y, bz + z) then return false end
        local meta, pair = Ch.placeMeta(bx + x, y, bz + z, yaw)
        Act.setBlock(bx + x, y, bz + z, Ch.ID, meta)
        Ch.placed(bx + x, y, bz + z, meta, pair, Act.setBlock)
        return true
    end
    local res = {}

    -- 1. Сторона к игроку: взгляд на −Z (yaw 0) — лицо на юг (+Z, 3); на +Z — 2;
    -- на −X (yaw 90) — 5; на +X — 4.
    res.facing = Ch.facingFor(0) == 3 and Ch.facingFor(180) == 2 and Ch.facingFor(90) == 5 and Ch.facingFor(-90) == 4

    -- 2. Пара по X: второй смотрит туда же; третий рядом — нельзя; по
    -- диагонали — можно (это не пара); рядом с одиночным по Z с несовместимым
    -- взглядом — сторона пары поперёк её оси, общая.
    local a = place(1, 1, 0)
    local b = place(2, 1, 0)
    local third = place(3, 1, 0)
    local side = place(1, 2, 0)                 -- к первому по Z — у него уже пара
    local diag = place(3, 2, 0)                 -- по диагонали ко второму
    local pairOk = a and b and not third and not side and diag
        and W.meta(bx + 1, y, bz + 1) == 3 and W.meta(bx + 2, y, bz + 1) == 3
        and Ch.partner(bx + 3, y, bz + 2) == nil
    -- Пара по Z при взгляде вдоль Z — сторона общая и поперёк оси (4 или 5).
    local zA = place(6, 1, 90)                  -- одиночный лицом на восток (5)
    local zB = place(6, 2, 0)                   -- взгляд на −Z не годится для пары по Z
    local mA, mB = W.meta(bx + 6, y, bz + 1), W.meta(bx + 6, y, bz + 2)
    res.pairs = pairOk and zA and zB and mA == mB and (mA == 4 or mA == 5)

    -- 3. Окна: одиночный — 27 ячеек «Chest», пара — 54 «Large Chest», сверху
    -- половина с меньшей X; запись в ячейку 28 попадает во вторую половину.
    local g1 = Ch.group(bx + 3, y, bz + 2)
    local g2 = Ch.group(bx + 2, y, bz + 1)
    local v2 = Ch.view(g2)
    v2[28] = {id = B.byName.stick.id, n = 5}
    res.view = #g1 == 1 and #g2 == 2 and g2[1].x == bx + 1 and g2[2].x == bx + 2
        and Ch.at(bx + 2, y, bz + 1).slots[1] and Ch.at(bx + 2, y, bz + 1).slots[1].n == 5
        and v2[28].n == 5 and v2[1] == nil
    v2[28] = nil

    -- 4. Глухой куб над сундуком или над его парой — не открывается; стекло — открывается.
    Act.setBlock(bx + 2, y + 1, bz + 1, B.byName.stone.id)
    local blockedPair = not Ch.canOpen(bx + 1, y, bz + 1)
    Act.setBlock(bx + 2, y + 1, bz + 1, B.byName.glass.id)
    local glassOk = Ch.canOpen(bx + 1, y, bz + 1)
    Act.setBlock(bx + 2, y + 1, bz + 1, 0)
    res.blocked = blockedPair and glassOk

    -- 5. Крышка и звуки: открыт — 10 тиков до 1, звук открытия один раз (у
    -- главной половины); закрыт — 10 тиков до 0, звук закрытия один раз.
    local played = {}
    local saveEvent = Snd.event
    Snd.event = function(name, sx, sy, sz) played[#played + 1] = {name, sx, sz}; return true end
    local c1, c2 = Ch.at(bx + 1, y, bz + 1), Ch.at(bx + 2, y, bz + 1)
    c1.users, c2.users = 1, 1
    local ticks = 0
    for _ = 1, 30 do
        Ch.tickOne(c1); Ch.tickOne(c2)
        ticks = ticks + 1
        if c1.lid >= 1 then break end
    end
    local opened = ticks == 10 and math.abs(c2.lid - 1) < 1e-9 and #played == 1 and played[1][1] == "random.chestopen"
        and math.abs(played[1][2] - (bx + 2)) < 1e-9     -- середина пары по X
    for _ = 1, 5 do Ch.tickOne(c1); Ch.tickOne(c2) end
    local steady = #played == 1
    c1.users, c2.users = 0, 0
    ticks = 0
    for _ = 1, 30 do
        Ch.tickOne(c1); Ch.tickOne(c2)
        ticks = ticks + 1
        if c1.lid <= 0 then break end
    end
    for _ = 1, 5 do Ch.tickOne(c1); Ch.tickOne(c2) end
    local closed = ticks == 10 and c1.lid == 0 and #played == 2 and played[2][1] == "random.chestclosed"
    Snd.event = saveEvent
    -- Угол отрисовки: 1 − (1 − a)³, ×(−π/2); середина — без скачка.
    local ang = math.abs(CM.lidAngle(1) + math.pi / 2) < 1e-9 and CM.lidAngle(0) == 0
        and math.abs(CM.lidAngle(0.5) + (1 - 0.125) * math.pi / 2) < 1e-9
    res.lid = opened and steady and closed and ang

    -- 6. Shift+ЛКМ: из сундука — в рюкзак (сначала к такой же стопке, затем в
    -- пустую с конца — с панели), из рюкзака — в сундук с первой ячейки.
    local savedSlots = {}
    for i = 1, Inv.SIZE do savedSlots[i] = Inv.slots[i]; Inv.slots[i] = nil end
    local savedChest = Inv.chest
    local view = {group = {Ch.at(bx + 3, y, bz + 2)}, rows = 3, slots = Ch.at(bx + 3, y, bz + 2).slots, title = "Chest"}
    Inv.chest = view
    local cobble = B.byName.cobblestone.id
    view.slots[4] = {id = cobble, n = 40}
    Inv.slots[20] = {id = cobble, n = 50}
    Inv.shiftChest(view.slots, 4, "chest")
    local toInv = view.slots[4] == nil and Inv.slots[20].n == 64 and Inv.slots[9] and Inv.slots[9].n == 26
    Inv.shiftChest(Inv.slots, 20, "inv")
    local toChest = Inv.slots[20] == nil and view.slots[1] and view.slots[1].n == 64

    -- 7. Цифра над ячейкой сундука: пустая панель — стопка в панель; занятая —
    -- стопка в панель, бывшая — в рюкзак.
    local reg = {kind = "chest", index = 1}
    Inv.slots[3] = nil
    Inv.hotbarSwap(reg, 3)
    local k1 = Inv.slots[3] and Inv.slots[3].n == 64 and view.slots[1] == nil
    view.slots[1] = {id = B.byName.diamond.id, n = 2}
    Inv.hotbarSwap(reg, 3)
    local diamondsOk = Inv.slots[3].id == B.byName.diamond.id and view.slots[1] == nil
    local cobbleBack = 0
    for i = 1, Inv.SIZE do local q = Inv.slots[i]; if q and q.id == cobble then cobbleBack = cobbleBack + q.n end end
    res.shift = toInv and toChest
    res.hotbar = k1 and diamondsOk and cobbleBack == 64 + 26
    for i = 1, Inv.SIZE do Inv.slots[i] = savedSlots[i] end
    Inv.chest = savedChest

    -- 8. Поломка: всё содержимое выпадает кусками 10..30, сумма — ровно та же;
    -- хранилище удалено, второй раз ничего не выпадает.
    local c = Ch.at(bx + 3, y, bz + 2)
    for i = 1, 27 do c.slots[i] = {id = cobble, n = 64} end
    local drops = {}
    local Drops = require "drops"
    local saveSpawn = Drops.spawn
    Drops.spawn = function(id, n) drops[#drops + 1] = {id = id, n = n} end
    local spilled = Ch.broken(bx + 3, y, bz + 2)
    local again = Ch.broken(bx + 3, y, bz + 2)
    Drops.spawn = saveSpawn
    local sum, sizes = 0, true
    for _, d in ipairs(drops) do
        sum = sum + d.n
        if d.n > 30 then sizes = false end
    end
    res.spill = spilled == 27 * 64 and sum == 27 * 64 and again == 0 and sizes

    -- 9. Сохранение: номер ячейки, предмет, число, износ — те же после загрузки.
    local keep = Ch.list
    local cs = Ch.at(bx + 6, y, bz + 1)
    cs.slots[7] = {id = B.byName.iron_pickaxe.id, n = 1, wear = 33}
    cs.slots[27] = {id = cobble, n = 17}
    Ch.list = {[bx + 6 .. "," .. y .. "," .. bz + 1] = cs}
    local data = Ch.serialize()
    Ch.list = {}
    Ch.load(data)
    local ld = Ch.list[bx + 6 .. "," .. y .. "," .. bz + 1]
    res.save = ld ~= nil and ld.slots[7] and ld.slots[7].wear == 33 and ld.slots[27].n == 17 and ld.slots[1] == nil
    for _, v in pairs(Ch.list) do CM.destroy(v.model) end
    Ch.list = keep

    -- 10. Окно: 176 × (114 + rows·18) — 168 и 222.
    res.gui = Inv.chestHeight(3) == 168 and Inv.chestHeight(6) == 222

    -- 11. Звуки — события 1.7.10 и их файлы: сундук (block), свинья, пшеница.
    local function ev(name, pat)
        local f = Snd.eventFile(name)
        return f ~= nil and f:match(pat) ~= nil
    end
    res.sounds = ev("random.chestopen", "random/chestopen%.ogg$") and ev("random.chestclosed", "random/chestclosed%.ogg$")
        and ev("mob.pig.say", "mob/pig/say[1-3]%.ogg$") and ev("mob.pig.death", "mob/pig/death%.ogg$")
        and ev("mob.pig.step", "mob/pig/step[1-5]%.ogg$") and ev("step.grass", "step/grass[1-6]%.ogg$")
        and ev("step.gravel", "step/gravel[1-4]%.ogg$") and ev("dig.grass", "dig/grass[1-4]%.ogg$")
        and Snd.EVENTS["random.chestopen"][3] == "block"
        and select(1, Snd.kindOf(B.byName.wheat_crop.id)) == "grass"
        and select(1, Snd.kindOf(B.byName.farmland.id)) == "gravel"

    -- Убрать за собой.
    for _, k in ipairs({{1, 1}, {2, 1}, {3, 2}, {6, 1}, {6, 2}}) do
        local cc = Ch.list[bx + k[1] .. "," .. y .. "," .. bz + k[2]]
        if cc then CM.destroy(cc.model) end
        Ch.list[bx + k[1] .. "," .. y .. "," .. bz + k[2]] = nil
    end
    local C = require "chunks"
    for i = #touched, 1, -1 do
        local t = touched[i]
        W.setId(t[1], t[2], t[3], 0)
        W.markDirty(t[1], t[2], t[3])
        local ed = C.edits[W.ckey(t[1] // 16, t[3] // 16)]
        if ed then ed[(t[1] & 15) + (t[3] & 15) * 16 + t[2] * 256] = nil end
    end
    local keys = {"facing", "pairs", "view", "blocked", "lid", "shift", "hotbar", "spill", "save", "gui", "sounds"}
    local all, parts = true, {}
    for _, k in ipairs(keys) do
        if not res[k] then all = false end
        parts[#parts + 1] = k .. "=" .. tostring(res[k] and true or false)
    end
    return "CHESTCHECK: " .. (all and "PASS " or "FAIL ") .. table.concat(parts, " ")
end

return CC
