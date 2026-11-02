-- ---------------------------------------------------------------------------
-- blocks.lua — реестр блоков и предметов SAGE Craft.
--
-- Всё, что игра знает о блоке, — в одной записи: текстуры граней, как он
-- рисуется (глухой, вырез по альфе, полупрозрачный, крест), сколько света
-- даёт, чем и как долго ломается, что выпадает. Движок ничего из этого не
-- знает: для него это просто меши, текстура атласа и свой шейдер.
--
-- Номер блока — его место в мире (одно число в таблице участка), поэтому
-- номера не переставляются: сохранение мира хранит номера, а не имена.
-- ---------------------------------------------------------------------------
local B = {}

B.AIR = 0

-- draw: "solid" — глухой куб; "cutout" — куб с дырами (листва, стекло):
-- соседние грани не прячутся за ним; "cross" — два скрещённых квадрата
-- (трава, цветы); "liquid" — полупрозрачная жидкость, своя пачка рисования;
-- "torch" — тонкий столбик.
-- tool: чем ломать быстрее ("pickaxe", "shovel", "axe"); need — без какого
-- уровня инструмента блок НИЧЕГО не роняет (руда без кирки).
local defs = {
    {id = 1,  name = "stone",        title = "Камень",            tex = "stone", hard = 1.5, tool = "pickaxe", need = 1, drop = "cobblestone"},
    {id = 2,  name = "grass",        title = "Дёрн",              top = "grass_top!", side = "grass_side", bottom = "dirt", hard = 0.6, tool = "shovel", drop = "dirt"},
    {id = 3,  name = "dirt",         title = "Земля",             tex = "dirt", hard = 0.5, tool = "shovel"},
    {id = 4,  name = "cobblestone",  title = "Булыжник",          tex = "cobblestone", hard = 2.0, tool = "pickaxe", need = 1},
    {id = 5,  name = "planks",       title = "Доски",             tex = "planks_oak", hard = 2.0, tool = "axe"},
    {id = 6,  name = "log",          title = "Бревно",            top = "log_oak_top", side = "log_oak", hard = 2.0, tool = "axe"},
    {id = 7,  name = "leaves",       title = "Листва",            tex = "leaves_oak!", draw = "cutout", hard = 0.2, drop = "none", apple = 0.03, opacityLight = 1},
    {id = 8,  name = "sand",         title = "Песок",             tex = "sand", hard = 0.5, tool = "shovel", falls = true},
    {id = 9,  name = "gravel",       title = "Гравий",            tex = "gravel", hard = 0.6, tool = "shovel", falls = true, flint = 0.1},
    {id = 10, name = "bedrock",      title = "Коренная порода",   tex = "bedrock", hard = -1},
    {id = 11, name = "water",        title = "Вода",              tex = "water_still", draw = "liquid", hard = -1, opacityLight = 2, solid = false},
    {id = 12, name = "glass",        title = "Стекло",            tex = "glass", draw = "cutout", hard = 0.3, drop = "none", opacityLight = 0},
    {id = 13, name = "coal_ore",     title = "Угольная руда",     tex = "coal_ore", hard = 3.0, tool = "pickaxe", need = 1, drop = "coal", xp = 1},
    {id = 14, name = "iron_ore",     title = "Железная руда",     tex = "iron_ore", hard = 3.0, tool = "pickaxe", need = 2},
    {id = 15, name = "gold_ore",     title = "Золотая руда",      tex = "gold_ore", hard = 3.0, tool = "pickaxe", need = 3},
    {id = 16, name = "diamond_ore",  title = "Алмазная руда",     tex = "diamond_ore", hard = 3.0, tool = "pickaxe", need = 3, drop = "diamond", xp = 5},
    {id = 17, name = "brick",        title = "Кирпич",            tex = "brick", hard = 2.0, tool = "pickaxe", need = 1},
    {id = 18, name = "stonebrick",   title = "Каменный кирпич",   tex = "stonebrick", hard = 1.5, tool = "pickaxe", need = 1},
    {id = 19, name = "glowstone",    title = "Светокамень",       tex = "glowstone", hard = 0.3, light = 15},
    {id = 20, name = "torch",        title = "Факел",             tex = "torch_on", draw = "torch", hard = 0, light = 14, solid = false, opacityLight = 0},
    {id = 21, name = "sandstone",    title = "Песчаник",          top = "sandstone_top", side = "sandstone_normal", bottom = "sandstone_bottom", hard = 0.8, tool = "pickaxe", need = 1},
    {id = 22, name = "tallgrass",    title = "Высокая трава",     tex = "tallgrass!", draw = "cross", hard = 0, solid = false, opacityLight = 0, drop = "none"},
    {id = 23, name = "rose",         title = "Роза",              tex = "flower_rose", draw = "cross", hard = 0, solid = false, opacityLight = 0},
    {id = 24, name = "dandelion",    title = "Одуванчик",         tex = "flower_dandelion", draw = "cross", hard = 0, solid = false, opacityLight = 0},
    {id = 25, name = "crafting_table", title = "Верстак",         top = "crafting_table_top", side = "crafting_table_side", front = "crafting_table_front", bottom = "planks_oak", hard = 2.5, tool = "axe"},
    {id = 26, name = "furnace",      title = "Печь",              top = "furnace_top", side = "furnace_side", front = "furnace_front_off", bottom = "furnace_top", hard = 3.5, tool = "pickaxe", need = 1},
    {id = 27, name = "obsidian",     title = "Обсидиан",          tex = "obsidian", hard = 50, tool = "pickaxe", need = 4},
    {id = 28, name = "snow",         title = "Снег",              tex = "snow", hard = 0.2, tool = "shovel"},
    {id = 29, name = "ice",          title = "Лёд",               tex = "ice", draw = "cutout", hard = 0.5, tool = "pickaxe", drop = "none", opacityLight = 2},
    {id = 30, name = "clay",         title = "Глина",             tex = "clay", hard = 0.6, tool = "shovel"},
    {id = 31, name = "birch_log",    title = "Берёзовое бревно",  top = "log_birch_top", side = "log_birch", hard = 2.0, tool = "axe"},
    {id = 32, name = "birch_leaves", title = "Берёзовая листва",  tex = "leaves_birch!", draw = "cutout", hard = 0.2, drop = "none", opacityLight = 1},
    {id = 33, name = "birch_planks", title = "Берёзовые доски",   tex = "planks_birch", hard = 2.0, tool = "axe"},
    {id = 34, name = "bookshelf",    title = "Книжный шкаф",      top = "planks_oak", side = "bookshelf", hard = 1.5, tool = "axe"},
    {id = 35, name = "wool",         title = "Шерсть",            tex = "wool_colored_white", hard = 0.8},
    {id = 36, name = "red_wool",     title = "Красная шерсть",    tex = "wool_colored_red", hard = 0.8},
    {id = 37, name = "blue_wool",    title = "Синяя шерсть",      tex = "wool_colored_blue", hard = 0.8},
    {id = 38, name = "yellow_wool",  title = "Жёлтая шерсть",     tex = "wool_colored_yellow", hard = 0.8},
    {id = 39, name = "green_wool",   title = "Зелёная шерсть",    tex = "wool_colored_green", hard = 0.8},
    {id = 40, name = "mossy_cobblestone", title = "Замшелый булыжник", tex = "cobblestone_mossy", hard = 2.0, tool = "pickaxe", need = 1},
    {id = 41, name = "cactus",       title = "Кактус",            top = "cactus_top", side = "cactus_side", bottom = "cactus_bottom", draw = "cutout", hard = 0.4, inset = 1 / 16, opacityLight = 0},
    {id = 42, name = "pumpkin",      title = "Тыква",             top = "pumpkin_top", side = "pumpkin_side", front = "pumpkin_face_off", bottom = "pumpkin_top", hard = 1.0, tool = "axe"},
    {id = 43, name = "coal_block",   title = "Угольный блок",     tex = "coal_block", hard = 5.0, tool = "pickaxe", need = 1},
    {id = 44, name = "iron_block",   title = "Железный блок",     tex = "iron_block", hard = 5.0, tool = "pickaxe", need = 2},
    {id = 45, name = "gold_block",   title = "Золотой блок",      tex = "gold_block", hard = 3.0, tool = "pickaxe", need = 3},
    {id = 46, name = "diamond_block", title = "Алмазный блок",    tex = "diamond_block", hard = 5.0, tool = "pickaxe", need = 3},
    -- Горящая печь: та же печь, пока в ней огонь (furnace.lua меняет блок
    -- туда и обратно). Светит и роняет обычную печь.
    {id = 47, name = "lit_furnace",  title = "Печь",              top = "furnace_top", side = "furnace_side", front = "furnace_front_on", bottom = "furnace_top", hard = 3.5, tool = "pickaxe", need = 1, light = 13, drop = "furnace"},
}

-- Предметы, которые не ставятся в мир. Номера — с 256, чтобы не пересечься с
-- блоками: в ячейке инвентаря лежит просто число.
-- tool — вид инструмента, tier — уровень (1 дерево … 4 алмаз), speed — во
-- сколько раз быстрее рук на «своём» блоке.
local items = {
    {id = 256, name = "stick",           title = "Палка",              tex = "stick"},
    {id = 257, name = "coal",            title = "Уголь",              tex = "coal"},
    {id = 258, name = "diamond",         title = "Алмаз",              tex = "diamond"},
    {id = 259, name = "iron_ingot",      title = "Железный слиток",    tex = "iron_ingot"},
    {id = 260, name = "gold_ingot",      title = "Золотой слиток",     tex = "gold_ingot"},
    {id = 261, name = "apple",           title = "Яблоко",             tex = "apple", food = 4},
    {id = 262, name = "flint",           title = "Кремень",            tex = "flint"},
    {id = 270, name = "wood_pickaxe",    title = "Деревянная кирка",   tex = "wood_pickaxe",    tool = "pickaxe", tier = 1, speed = 2,  uses = 60},
    {id = 271, name = "stone_pickaxe",   title = "Каменная кирка",     tex = "stone_pickaxe",   tool = "pickaxe", tier = 2, speed = 4,  uses = 132},
    {id = 272, name = "iron_pickaxe",    title = "Железная кирка",     tex = "iron_pickaxe",    tool = "pickaxe", tier = 3, speed = 6,  uses = 251},
    {id = 273, name = "diamond_pickaxe", title = "Алмазная кирка",     tex = "diamond_pickaxe", tool = "pickaxe", tier = 4, speed = 8,  uses = 1562},
    {id = 274, name = "wood_shovel",     title = "Деревянная лопата",  tex = "wood_shovel",     tool = "shovel",  tier = 1, speed = 2,  uses = 60},
    {id = 275, name = "stone_shovel",    title = "Каменная лопата",    tex = "stone_shovel",    tool = "shovel",  tier = 2, speed = 4,  uses = 132},
    {id = 276, name = "iron_shovel",     title = "Железная лопата",    tex = "iron_shovel",     tool = "shovel",  tier = 3, speed = 6,  uses = 251},
    {id = 277, name = "diamond_shovel",  title = "Алмазная лопата",    tex = "diamond_shovel",  tool = "shovel",  tier = 4, speed = 8,  uses = 1562},
    {id = 278, name = "wood_axe",        title = "Деревянный топор",   tex = "wood_axe",        tool = "axe",     tier = 1, speed = 2,  uses = 60},
    {id = 279, name = "stone_axe",       title = "Каменный топор",     tex = "stone_axe",       tool = "axe",     tier = 2, speed = 4,  uses = 132},
    {id = 280, name = "iron_axe",        title = "Железный топор",     tex = "iron_axe",        tool = "axe",     tier = 3, speed = 6,  uses = 251},
    {id = 281, name = "diamond_axe",     title = "Алмазный топор",     tex = "diamond_axe",     tool = "axe",     tier = 4, speed = 8,  uses = 1562},
    {id = 282, name = "wood_sword",      title = "Деревянный меч",     tex = "wood_sword",      tool = "sword",   tier = 1, speed = 1.5, uses = 60},
    {id = 283, name = "stone_sword",     title = "Каменный меч",       tex = "stone_sword",     tool = "sword",   tier = 2, speed = 1.5, uses = 132},
    {id = 284, name = "iron_sword",      title = "Железный меч",       tex = "iron_sword",      tool = "sword",   tier = 3, speed = 1.5, uses = 251},
    {id = 285, name = "diamond_sword",   title = "Алмазный меч",       tex = "diamond_sword",   tool = "sword",   tier = 4, speed = 1.5, uses = 1562},
}

B.byId = {}
B.byName = {}
B.list = {}        -- блоки по порядку номеров (для каталога и иконок)
B.itemList = {}

-- Быстрые таблицы по номеру: их читает построитель мешей и свет в самых
-- горячих циклах, поэтому это плоские массивы чисел/булевых, а не поля записей.
B.opaque = {}      -- глухой куб: прячет соседние грани и не пропускает свет
B.solid = {}       -- твёрдый для ходьбы
B.drawKind = {}    -- 0 нет, 1 куб, 2 вырез, 3 крест, 4 жидкость, 5 факел
B.emit = {}        -- свет блока 0..15
B.absorb = {}      -- сколько свет теряет, проходя сквозь (1 — воздух)
B.faceTile = {}    -- [id] = {верх, низ, север, юг, запад, восток} — номера плиток атласа

local KIND = {solid = 1, cutout = 2, cross = 3, liquid = 4, torch = 5}

for i = 0, 1023 do
    B.opaque[i] = false
    B.solid[i] = false
    B.drawKind[i] = 0
    B.emit[i] = 0
    B.absorb[i] = 1
end

for _, d in ipairs(defs) do
    d.draw = d.draw or "solid"
    d.isBlock = true
    d.stack = 64
    B.byId[d.id] = d
    B.byName[d.name] = d
    B.list[#B.list + 1] = d
    B.drawKind[d.id] = KIND[d.draw]
    B.opaque[d.id] = d.draw == "solid"
    B.solid[d.id] = d.solid ~= false and d.draw ~= "cross"
    B.emit[d.id] = d.light or 0
    if d.draw == "solid" then B.absorb[d.id] = 15
    else B.absorb[d.id] = 1 + (d.opacityLight or 0) end
end

for _, it in ipairs(items) do
    it.isBlock = false
    it.stack = it.tool and 1 or 64
    B.byId[it.id] = it
    B.byName[it.name] = it
    B.itemList[#B.itemList + 1] = it
end

-- Что выпадает: имя предмета/блока или "none". По умолчанию — сам блок.
function B.dropOf(id)
    local d = B.byId[id]
    if not d then return nil end
    if d.drop == "none" then return nil end
    if d.drop then return B.byName[d.drop].id end
    return id
end

-- Имена текстур граней. "!" в конце имени — плитку красит цвет растительности
-- (серые в паке трава и листва окрашиваются при сборке атласа).
function B.faceNames(d)
    local side = d.side or d.tex
    return {
        top = d.top or d.tex,
        bottom = d.bottom or d.top or d.tex,
        side = side,
        front = d.front or side,
    }
end

function B.title(id)
    local d = B.byId[id]
    return d and d.title or "?"
end

function B.maxStack(id)
    local d = B.byId[id]
    return d and d.stack or 64
end

return B
