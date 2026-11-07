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
    {id = 1,  name = "stone",        title = "Stone",            tex = "stone", hard = 1.5, tool = "pickaxe", need = 1, drop = "cobblestone"},
    {id = 2,  name = "grass",        title = "Grass Block",              top = "grass_top!", side = "grass_side", bottom = "dirt", hard = 0.6, tool = "shovel", drop = "dirt"},
    {id = 3,  name = "dirt",         title = "Dirt",             tex = "dirt", hard = 0.5, tool = "shovel"},
    {id = 4,  name = "cobblestone",  title = "Cobblestone",          tex = "cobblestone", hard = 2.0, tool = "pickaxe", need = 1},
    {id = 5,  name = "planks",       title = "Oak Planks",             tex = "planks_oak", hard = 2.0, tool = "axe"},
    {id = 6,  name = "log",          title = "Oak Log",            top = "log_oak_top", side = "log_oak", hard = 2.0, tool = "axe"},
    {id = 7,  name = "leaves",       title = "Oak Leaves",            tex = "leaves_oak!", draw = "cutout", hard = 0.2, drop = "none", apple = 0.03, opacityLight = 1},
    {id = 8,  name = "sand",         title = "Sand",             tex = "sand", hard = 0.5, tool = "shovel", falls = true},
    {id = 9,  name = "gravel",       title = "Gravel",            tex = "gravel", hard = 0.6, tool = "shovel", falls = true, flint = 0.1},
    {id = 10, name = "bedrock",      title = "Bedrock",   tex = "bedrock", hard = -1},
    {id = 11, name = "water",        title = "Water",              tex = "water_still", draw = "liquid", hard = -1, opacityLight = 2, solid = false},
    {id = 12, name = "glass",        title = "Glass",            tex = "glass", draw = "cutout", hard = 0.3, drop = "none", opacityLight = 0},
    {id = 13, name = "coal_ore",     title = "Coal Ore",     tex = "coal_ore", hard = 3.0, tool = "pickaxe", need = 1, drop = "coal", xp = {0, 2}},
    {id = 14, name = "iron_ore",     title = "Iron Ore",     tex = "iron_ore", hard = 3.0, tool = "pickaxe", need = 2},
    {id = 15, name = "gold_ore",     title = "Gold Ore",      tex = "gold_ore", hard = 3.0, tool = "pickaxe", need = 3},
    {id = 16, name = "diamond_ore",  title = "Diamond Ore",     tex = "diamond_ore", hard = 3.0, tool = "pickaxe", need = 3, drop = "diamond", xp = {3, 7}},
    {id = 17, name = "brick",        title = "Bricks",            tex = "brick", hard = 2.0, tool = "pickaxe", need = 1},
    {id = 18, name = "stonebrick",   title = "Stone Bricks",   tex = "stonebrick", hard = 1.5, tool = "pickaxe", need = 1},
    {id = 19, name = "glowstone",    title = "Glowstone",       tex = "glowstone", hard = 0.3, light = 15},
    {id = 20, name = "torch",        title = "Torch",             tex = "torch_on", draw = "torch", hard = 0, light = 14, solid = false, opacityLight = 0},
    {id = 21, name = "sandstone",    title = "Sandstone",          top = "sandstone_top", side = "sandstone_normal", bottom = "sandstone_bottom", hard = 0.8, tool = "pickaxe", need = 1},
    {id = 22, name = "tallgrass",    title = "Tall Grass",     tex = "tallgrass!", draw = "cross", hard = 0, solid = false, opacityLight = 0, drop = "none"},
    {id = 23, name = "rose",         title = "Rose",              tex = "flower_rose", draw = "cross", hard = 0, solid = false, opacityLight = 0},
    {id = 24, name = "dandelion",    title = "Dandelion",         tex = "flower_dandelion", draw = "cross", hard = 0, solid = false, opacityLight = 0},
    {id = 25, name = "crafting_table", title = "Crafting Table",         top = "crafting_table_top", side = "crafting_table_side", front = "crafting_table_front", bottom = "planks_oak", hard = 2.5, tool = "axe"},
    {id = 26, name = "furnace",      title = "Furnace",              top = "furnace_top", side = "furnace_side", front = "furnace_front_off", bottom = "furnace_top", hard = 3.5, tool = "pickaxe", need = 1},
    {id = 27, name = "obsidian",     title = "Obsidian",          tex = "obsidian", hard = 50, tool = "pickaxe", need = 4},
    {id = 28, name = "snow",         title = "Snow",              tex = "snow", hard = 0.2, tool = "shovel"},
    {id = 29, name = "ice",          title = "Ice",               tex = "ice", draw = "cutout", hard = 0.5, tool = "pickaxe", drop = "none", opacityLight = 2},
    {id = 30, name = "clay",         title = "Clay",             tex = "clay", hard = 0.6, tool = "shovel"},
    {id = 31, name = "birch_log",    title = "Birch Log",  top = "log_birch_top", side = "log_birch", hard = 2.0, tool = "axe"},
    {id = 32, name = "birch_leaves", title = "Birch Leaves",  tex = "leaves_birch!", draw = "cutout", hard = 0.2, drop = "none", opacityLight = 1},
    {id = 33, name = "birch_planks", title = "Birch Planks",   tex = "planks_birch", hard = 2.0, tool = "axe"},
    {id = 34, name = "bookshelf",    title = "Bookshelf",      top = "planks_oak", side = "bookshelf", hard = 1.5, tool = "axe"},
    {id = 35, name = "wool",         title = "White Wool",            tex = "wool_colored_white", hard = 0.8},
    {id = 36, name = "red_wool",     title = "Red Wool",    tex = "wool_colored_red", hard = 0.8},
    {id = 37, name = "blue_wool",    title = "Blue Wool",      tex = "wool_colored_blue", hard = 0.8},
    {id = 38, name = "yellow_wool",  title = "Yellow Wool",     tex = "wool_colored_yellow", hard = 0.8},
    {id = 39, name = "green_wool",   title = "Green Wool",    tex = "wool_colored_green", hard = 0.8},
    {id = 40, name = "mossy_cobblestone", title = "Mossy Cobblestone", tex = "cobblestone_mossy", hard = 2.0, tool = "pickaxe", need = 1},
    {id = 41, name = "cactus",       title = "Cactus",            top = "cactus_top", side = "cactus_side", bottom = "cactus_bottom", draw = "cutout", hard = 0.4, inset = 1 / 16, opacityLight = 0},
    {id = 42, name = "pumpkin",      title = "Pumpkin",             top = "pumpkin_top", side = "pumpkin_side", front = "pumpkin_face_off", bottom = "pumpkin_top", hard = 1.0, tool = "axe"},
    {id = 43, name = "coal_block",   title = "Block of Coal",     tex = "coal_block", hard = 5.0, tool = "pickaxe", need = 1},
    {id = 44, name = "iron_block",   title = "Block of Iron",     tex = "iron_block", hard = 5.0, tool = "pickaxe", need = 2},
    {id = 45, name = "gold_block",   title = "Block of Gold",      tex = "gold_block", hard = 3.0, tool = "pickaxe", need = 3},
    {id = 46, name = "diamond_block", title = "Block of Diamond",    tex = "diamond_block", hard = 5.0, tool = "pickaxe", need = 3},
    -- Горящая печь: та же печь, пока в ней огонь (furnace.lua меняет блок
    -- туда и обратно). Светит и роняет обычную печь.
    -- Руды 1.7.10: красная пыль (4–5 штук), лазурит (4–8), изумруд (1).
    -- Опыт — случайно в пределах, как в оригинале.
    {id = 48, name = "redstone_ore", title = "Redstone Ore", tex = "redstone_ore", hard = 3.0, tool = "pickaxe", need = 3, drop = "redstone", count = {4, 5}, xp = {1, 5}},
    {id = 49, name = "lapis_ore",    title = "Lapis Lazuli Ore", tex = "lapis_ore", hard = 3.0, tool = "pickaxe", need = 2, drop = "lapis_lazuli", count = {4, 8}, xp = {2, 5}},
    {id = 50, name = "emerald_ore",  title = "Emerald Ore", tex = "emerald_ore", hard = 3.0, tool = "pickaxe", need = 3, drop = "emerald", xp = {3, 7}},
    -- Сахарный тростник (WorldGenReed): у воды, крестом; из него бумага.
    {id = 51, name = "reeds",        title = "Sugar Canes", tex = "reeds", draw = "cross", hard = 0, solid = false, opacityLight = 0},
    {id = 47, name = "lit_furnace",  title = "Furnace",              top = "furnace_top", side = "furnace_side", front = "furnace_front_on", bottom = "furnace_top", hard = 3.5, tool = "pickaxe", need = 1, light = 13, drop = "furnace"},
}

-- Предметы, которые не ставятся в мир. Номера — с 256, чтобы не пересечься с
-- блоками: в ячейке инвентаря лежит просто число.
-- tool — вид инструмента, tier — уровень (1 дерево … 4 алмаз), speed — во
-- сколько раз быстрее рук на «своём» блоке.
local items = {
    {id = 256, name = "stick",           title = "Stick",              tex = "stick"},
    {id = 257, name = "coal",            title = "Coal",              tex = "coal"},
    {id = 258, name = "diamond",         title = "Diamond",              tex = "diamond"},
    {id = 259, name = "iron_ingot",      title = "Iron Ingot",    tex = "iron_ingot"},
    {id = 260, name = "gold_ingot",      title = "Gold Ingot",     tex = "gold_ingot"},
    {id = 261, name = "apple",           title = "Apple",             tex = "apple", food = 4},
    {id = 262, name = "flint",           title = "Flint",            tex = "flint"},
    {id = 263, name = "redstone",        title = "Redstone",         tex = "redstone_dust"},
    {id = 264, name = "lapis_lazuli",    title = "Lapis Lazuli",     tex = "dye_powder_blue"},
    {id = 265, name = "emerald",         title = "Emerald",          tex = "emerald"},
    -- Использование (ПКМ, как в 1.7.10): еда и питьё — 32 тика, лук — натяжение,
    -- меч — защита. full3d — инструмент держится «как палка» (Item.isFull3D).
    {id = 266, name = "bow",             title = "Bow",              tex = "bow_standby", bow = true, stack = 1},
    {id = 267, name = "arrow",           title = "Arrow",            tex = "arrow"},
    {id = 268, name = "string",          title = "String",           tex = "string"},
    {id = 269, name = "glass_bottle",    title = "Glass Bottle",     tex = "potion_bottle_empty"},
    {id = 286, name = "potion",          title = "Water Bottle",     tex = "water_bottle", drink = true, stack = 1},
    {id = 287, name = "paper",           title = "Paper",            tex = "paper"},
    {id = 288, name = "compass",         title = "Compass",          tex = "compass"},
    {id = 289, name = "empty_map",       title = "Empty Map",        tex = "map_empty"},
    {id = 290, name = "filled_map",      title = "Map",              tex = "map_filled", map = true, stack = 1},
    -- Кадры натяжения лука (ItemBow.getItemIconForUseDuration) — только картинки.
    {id = 291, name = "bow_pulling_0",   title = "Bow", tex = "bow_pulling_0", hidden = true, stack = 1},
    {id = 292, name = "bow_pulling_1",   title = "Bow", tex = "bow_pulling_1", hidden = true, stack = 1},
    {id = 293, name = "bow_pulling_2",   title = "Bow", tex = "bow_pulling_2", hidden = true, stack = 1},
    {id = 270, name = "wood_pickaxe",    title = "Wooden Pickaxe",   tex = "wood_pickaxe",    tool = "pickaxe", tier = 1, speed = 2,  uses = 60},
    {id = 271, name = "stone_pickaxe",   title = "Stone Pickaxe",     tex = "stone_pickaxe",   tool = "pickaxe", tier = 2, speed = 4,  uses = 132},
    {id = 272, name = "iron_pickaxe",    title = "Iron Pickaxe",     tex = "iron_pickaxe",    tool = "pickaxe", tier = 3, speed = 6,  uses = 251},
    {id = 273, name = "diamond_pickaxe", title = "Diamond Pickaxe",     tex = "diamond_pickaxe", tool = "pickaxe", tier = 4, speed = 8,  uses = 1562},
    {id = 274, name = "wood_shovel",     title = "Wooden Shovel",  tex = "wood_shovel",     tool = "shovel",  tier = 1, speed = 2,  uses = 60},
    {id = 275, name = "stone_shovel",    title = "Stone Shovel",    tex = "stone_shovel",    tool = "shovel",  tier = 2, speed = 4,  uses = 132},
    {id = 276, name = "iron_shovel",     title = "Iron Shovel",    tex = "iron_shovel",     tool = "shovel",  tier = 3, speed = 6,  uses = 251},
    {id = 277, name = "diamond_shovel",  title = "Diamond Shovel",    tex = "diamond_shovel",  tool = "shovel",  tier = 4, speed = 8,  uses = 1562},
    {id = 278, name = "wood_axe",        title = "Wooden Axe",   tex = "wood_axe",        tool = "axe",     tier = 1, speed = 2,  uses = 60},
    {id = 279, name = "stone_axe",       title = "Stone Axe",     tex = "stone_axe",       tool = "axe",     tier = 2, speed = 4,  uses = 132},
    {id = 280, name = "iron_axe",        title = "Iron Axe",     tex = "iron_axe",        tool = "axe",     tier = 3, speed = 6,  uses = 251},
    {id = 281, name = "diamond_axe",     title = "Diamond Axe",     tex = "diamond_axe",     tool = "axe",     tier = 4, speed = 8,  uses = 1562},
    {id = 282, name = "wood_sword",      title = "Wooden Sword",     tex = "wood_sword",      tool = "sword",   tier = 1, speed = 1.5, uses = 60},
    {id = 283, name = "stone_sword",     title = "Stone Sword",       tex = "stone_sword",     tool = "sword",   tier = 2, speed = 1.5, uses = 132},
    {id = 284, name = "iron_sword",      title = "Iron Sword",       tex = "iron_sword",      tool = "sword",   tier = 3, speed = 1.5, uses = 251},
    {id = 285, name = "diamond_sword",   title = "Diamond Sword",       tex = "diamond_sword",   tool = "sword",   tier = 4, speed = 1.5, uses = 1562},
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
    it.stack = it.stack or (it.tool and 1 or 64)
    -- Как держится и что делает ПКМ (Item.isFull3D, getItemUseAction).
    it.full3d = it.tool ~= nil or it.name == "stick"
    if it.food then it.use = "eat"
    elseif it.drink then it.use = "drink"
    elseif it.tool == "sword" then it.use = "block"
    elseif it.bow then it.use = "bow" end
    B.byId[it.id] = it
    B.byName[it.name] = it
    B.itemList[#B.itemList + 1] = it
end

-- Что выпадает: имя предмета/блока или "none". По умолчанию — сам блок.
-- Сколько выпадает (count = {от, до}) и сколько опыта (xp — число или {от, до}).
local function roll(v)
    if type(v) == "table" then return v[1] + math.random(0, v[2] - v[1]) end
    return v or 0
end
function B.dropCount(id)
    local d = B.byId[id]
    return d and d.count and roll(d.count) or 1
end
function B.xpOf(id)
    local d = B.byId[id]
    return d and roll(d.xp) or 0
end

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
