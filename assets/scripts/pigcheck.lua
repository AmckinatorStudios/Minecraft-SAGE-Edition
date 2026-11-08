-- ---------------------------------------------------------------------------
-- pigcheck.lua — самопроверка свиньи (--gencheck, строка PIGCHECK): на
-- площадке над игроком проверяются физика, урон и паника, смерть и дроп,
-- поросёнок без дропа, рост, размножение, приманка морковью, путь в обход
-- воды, еда и печь. Площадка и свиньи после проверки убираются.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local Pig = require "pig"
local AI = require "pigai"

local PC = {}

local function run(p, P, n)
    for _ = 1, n do
        if not Pig.tick(p, P) then return false end
    end
    return true
end

function PC.selfCheck(P)
    local bx, bz = math.floor(P.pos.x) - 6, math.floor(P.pos.z) - 6
    local by = math.min(W.HEIGHT - 8, math.floor(P.pos.y) + 20)
    local stone, water = B.byName.stone.id, B.byName.water.id
    local cells = {}
    local function set(x, y, z, id)
        cells[#cells + 1] = {x, y, z}
        W.setId(x, y, z, id)
    end
    -- Площадка 13×13 из камня; посередине — ров воды по z = 6 с мостом в x = 10.
    for x = 0, 12 do
        for z = 0, 12 do
            set(bx + x, by, bz + z, stone)
            for y = 1, 3 do set(bx + x, by + y, bz + z, 0) end
        end
    end
    for x = 0, 12 do
        if x ~= 10 then set(bx + x, by, bz + 6, water) end
    end
    local saveSpawn, drops = require("drops").spawn, {}
    require("drops").spawn = function(id, n) drops[#drops + 1] = {id = id, n = n} end
    local saveXp = require("hud").addXp
    require("hud").addXp = function() end
    local keep = {}
    for _, o in ipairs(Pig.list) do keep[o] = true end
    local far = {pos = {x = P.pos.x + 1000, y = P.pos.y, z = P.pos.z}, EYE = P.EYE}
    local res = {}

    -- 1. Падение на площадку: стоит на камне.
    local p = Pig.spawn(bx + 2.5, by + 3, bz + 2.5, 0, 0)
    run(p, far, 40)
    res.fall = p.onGround and math.abs(p.y - (by + 1)) < 1e-6

    -- 2. Удар рукой: 1 урон, вспышка 10 тиков, неуязвимость, отбрасывание, паника.
    local src = {x = p.x - 1, z = p.z, player = true}
    Pig.damage(p, 1, src)
    local again = Pig.damage(p, 1, src)
    res.hurt = p.health == 9 and p.hurtTime == 10 and not again and p.mx > 0 and p.my > 0
    -- Паника — бег со скоростью 1.25 (в воздухе после отбрасывания пути нет:
    -- задача пробует снова на следующих пересмотрах, как у оригинала).
    for _ = 1, 30 do
        run(p, far, 1)
        if AI.running(p, "panic") and p.ai.path and p.ai.speed == 1.25 then res.panic = true; break end
    end
    -- Урон по таблице: рука 1, деревянный меч 5, алмазный 8, железный топор 6.
    local dmg = function(n) return Pig.attackDamage({id = B.byName[n].id}) end
    res.table = Pig.attackDamage(nil) == 1 and dmg("wood_sword") == 5 and dmg("diamond_sword") == 8
        and dmg("iron_axe") == 6 and dmg("stone_pickaxe") == 4 and dmg("diamond_shovel") == 5

    -- 3. Смерть: 20 тиков завала, потом исчезает; дроп 1–3 сырой свинины.
    Pig.damage(p, 50, src)
    local alive = true
    for i = 1, 25 do
        alive = Pig.tick(p, far)
        if not alive then res.deathTicks = i; break end
    end
    res.death = p.dead and not alive and res.deathTicks == 20
    res.drop = #drops == 1 and drops[1].id == B.byName.porkchop_raw.id and drops[1].n >= 1 and drops[1].n <= 3
    -- Горящая — жареная.
    local q = Pig.spawn(bx + 2.5, by + 1, bz + 2.5, 0, 0)
    q.burning = true
    Pig.damage(q, 50, nil)
    res.cooked = #drops == 2 and drops[2].id == B.byName.porkchop_cooked.id

    -- 4. Поросёнок: без дропа; растёт через 24000 тиков (размер 0.45 → 0.9).
    local c = Pig.spawn(bx + 2.5, by + 1, bz + 2.5, 0, -24000)
    local w0 = Pig.size(c)
    c.age = -1
    run(c, far, 1)
    local w1 = Pig.size(c)
    res.grow = w0 == 0.45 and w1 == 0.9 and c.age == 0
    local d = Pig.spawn(bx + 3.5, by + 1, bz + 2.5, 0, -24000)
    Pig.damage(d, 50, src)
    res.babyDrop = #drops == 2

    -- 5. Морковь: взрослой с возрастом 0 — любовь 600; поросёнку и
    -- влюблённой — нет; картошки в игре нет, другая еда не годится.
    local carrot = {id = B.byName.carrot.id}
    local m1 = Pig.spawn(bx + 2.5, by + 1, bz + 9.5, 0, 0)
    local m2 = Pig.spawn(bx + 4.5, by + 1, bz + 9.5, 0, 0)
    local fed = Pig.interact(m1, carrot) and m1.love == 600 and not Pig.interact(m1, carrot)
        and not Pig.interact(m1, {id = B.byName.apple.id}) and Pig.interact(m2, carrot)
    res.feed = fed
    -- Пара сходится и через 60 тиков рядом даёт поросёнка; родителям — 6000.
    local before = #Pig.list
    for _ = 1, 200 do
        run(m1, far, 1); run(m2, far, 1)
        if #Pig.list > before then break end
    end
    local baby = Pig.list[#Pig.list]
    res.breed = #Pig.list == before + 1 and baby.age <= -23990 and m1.age > 5800 and m2.age > 5800
        and m1.love == 0 and m2.love == 0

    -- 6. Приманка: игрок в 10 блоках с морковью — свинья идёт к нему.
    local Inv = require "inventory"
    local savedSlot = Inv.slots[Inv.selected]
    Inv.slots[Inv.selected] = {id = B.byName.carrot.id, n = 1}
    local t = Pig.spawn(bx + 2.5, by + 1, bz + 2.5, 0, 0)
    local near = {pos = {x = bx + 9.5, y = by + 1, z = bz + 2.5}, EYE = P.EYE}
    run(t, near, 6)
    res.tempt = AI.running(t, "tempt_carrot") and t.ai.path ~= nil
    Inv.slots[Inv.selected] = savedSlot

    -- 7. Путь через ров — только по мосту: ни одной клетки воды.
    local s = Pig.spawn(bx + 2.5, by + 1, bz + 2.5, 0, 0)
    local path = AI.findPath(s, bx + 2, by + 1, bz + 10, 16, true)
    local wet, reached = false, false
    if path then
        for _, n in ipairs(path) do
            if B.drawKind[W.get(n[1], n[2], n[3])] == 4 or B.drawKind[W.get(n[1], n[2] - 1, n[3])] == 4 then wet = true end
        end
        local e = path[#path]
        reached = e[1] == bx + 2 and e[3] == bz + 10
    end
    res.path = reached and not wet

    -- 8. Сохранение: здоровье, возраст, любовь, повороты — после загрузки те же.
    local keepList = Pig.list
    local sv = Pig.spawn(bx + 5.5, by + 1, bz + 2.5, 33, -100)
    sv.health, sv.love, sv.headYaw = 7, 0, 40
    Pig.list = {sv}
    local data = Pig.serialize()
    Pig.list = {}
    Pig.load(data)
    local ld = Pig.list[1]
    res.save = #Pig.list == 1 and ld.health == 7 and ld.age == -100 and ld.yaw == 33 and ld.headYaw == 40
        and math.abs(ld.x - sv.x) < 1e-9
    while #Pig.list > 0 do Pig.remove(#Pig.list) end
    Pig.list = keepList
    Pig.list[#Pig.list + 1] = sv

    -- 9. Еда и печь.
    local raw, cooked = B.byName.porkchop_raw, B.byName.porkchop_cooked
    res.food = raw.food == 3 and raw.sat == 0.3 and cooked.food == 8 and cooked.sat == 0.8
        and raw.stack == 64 and cooked.stack == 64 and raw.use == "eat"
        and require("crafting").SMELT[raw.id] == cooked.id

    -- Убрать за собой.
    require("drops").spawn, require("hud").addXp = saveSpawn, saveXp
    for i = #Pig.list, 1, -1 do
        if not keep[Pig.list[i]] then Pig.remove(i) end
    end
    for i = #cells, 1, -1 do local c3 = cells[i]; W.setId(c3[1], c3[2], c3[3], 0) end
    for _, c3 in ipairs(cells) do W.markDirty(c3[1], c3[2], c3[3]) end

    local keys = {"fall", "hurt", "panic", "table", "death", "drop", "cooked", "grow", "babyDrop", "feed", "breed",
                  "tempt", "path", "save", "food"}
    local ok, parts = true, {}
    for _, k in ipairs(keys) do
        if not res[k] then ok = false end
        parts[#parts + 1] = k .. "=" .. tostring(res[k] and true or false)
    end
    return "PIGCHECK: " .. (ok and "PASS " or "FAIL ") .. table.concat(parts, " ")
end

return PC
