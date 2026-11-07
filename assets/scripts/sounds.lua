-- ---------------------------------------------------------------------------
-- sounds.lua — звуки блоков, как в Minecraft 1.7.10.
--
-- У каждого блока — материал звука (soundType): stone, wood, gravel, grass,
-- sand, snow, cloth. Файлы — assets/sounds/step/<материал>N.ogg (шаги и удары
-- при добыче) и assets/sounds/dig/<материал>N.ogg (поломка и установка);
-- вариант берётся случайно, как в Minecraft.
--
-- Громкость и высота — правила 1.7.10 (у всех материалов громкость 1, тон 1,
-- у металла тон 1.5):
--   удар при добыче (каждые 4 тика, с позиции блока) — step, (v + 1) / 8, p * 0.5
--   поломка блока                                      — dig,  (v + 1) / 2, p * 0.8
--   установка блока                                    — dig,  (v + 1) / 2, p * 0.8
--   шаг                                                — step, v * 0.15,    p
-- ---------------------------------------------------------------------------
local B = require "blocks"

local S = {}

local VARIANTS = {
    step = {stone = 6, wood = 6, gravel = 4, grass = 6, sand = 5, snow = 4, cloth = 4},
    dig  = {stone = 4, wood = 4, gravel = 4, grass = 4, sand = 4, snow = 4, cloth = 4},
}

-- Материал звука блока (как Block.stepSound в 1.7.10). Чего нет в таблице —
-- камень. Земля в Minecraft звучит гравием — это не опечатка.
local KIND = {
    grass = "grass", leaves = "grass", birch_leaves = "grass", tallgrass = "grass",
    rose = "grass", dandelion = "grass",
    dirt = "gravel", gravel = "gravel", clay = "gravel",
    sand = "sand",
    snow = "snow",
    planks = "wood", log = "wood", birch_log = "wood", birch_planks = "wood",
    crafting_table = "wood", bookshelf = "wood", pumpkin = "wood", torch = "wood",
    wool = "cloth", red_wool = "cloth", blue_wool = "cloth", yellow_wool = "cloth",
    green_wool = "cloth", cactus = "cloth",
}
-- Металл — звуки камня тоном выше (soundTypeMetal).
local PITCH = {iron_block = 1.5, gold_block = 1.5, diamond_block = 1.5}

local function info(id)
    local d = B.byId[id]
    if not d or id == 0 or B.drawKind[id] == 4 then return nil end
    return KIND[d.name] or "stone", PITCH[d.name] or 1.0
end

local function file(group, kind)
    local n = VARIANTS[group][kind] or 1
    return string.format("assets/sounds/%s/%s%d.ogg", group, kind, math.random(n))
end

-- Сколько раз прозвучал каждый вид — для проверки автопилотом.
S.count = {hit = 0, dig = 0, step = 0}

local function at(x, y, z) return Vec3(x + 0.5, y + 0.5, z + 0.5) end

-- Удар по блоку при добыче (каждые 4 тика, пока держат кнопку).
function S.hit(id, x, y, z)
    local kind, pitch = info(id)
    if kind then
        PlaySound3D(file("step", kind), at(x, y, z), (1 + 1) / 8, pitch * 0.5)
        S.count.hit = S.count.hit + 1
    end
end

-- Блок разрушен.
function S.dig(id, x, y, z)
    local kind, pitch = info(id)
    if kind then
        PlaySound3D(file("dig", kind), at(x, y, z), (1 + 1) / 2, pitch * 0.8)
        S.count.dig = S.count.dig + 1
    end
end

-- Блок поставлен — тот же звук, что у поломки (как в 1.7.10).
S.place = S.dig

-- Шаг по блоку id под ногами.
function S.step(id, x, y, z)
    local kind, pitch = info(id)
    if kind then
        PlaySound3D(file("step", kind), Vec3(x, y, z), 0.15, pitch)
        S.count.step = S.count.step + 1
    end
end

-- --- Звуки random.* (assets/sounds/random) ----------------------------------

local R = "assets/sounds/random/"
local rnd = math.random
S.count.eat, S.count.drink, S.count.burp, S.count.pop, S.count.click = 0, 0, 0, 0, 0

-- random.eat (EntityPlayer.updateItemUse): громкость 0.5 или 1, тон ±0.2.
function S.eat(x, y, z)
    PlaySound3D(R .. "eat" .. rnd(3) .. ".ogg", Vec3(x, y, z), 0.5 + 0.5 * rnd(0, 1), (rnd() - rnd()) * 0.2 + 1)
    S.count.eat = S.count.eat + 1
end

-- random.drink: громкость 0.5, тон 0.9..1.
function S.drink(x, y, z)
    PlaySound3D(R .. "drink.ogg", Vec3(x, y, z), 0.5, rnd() * 0.1 + 0.9)
    S.count.drink = S.count.drink + 1
end

-- random.burp (ItemFood.onEaten): громкость 0.5, тон 0.9..1.
function S.burp(x, y, z)
    PlaySound3D(R .. "burp.ogg", Vec3(x, y, z), 0.5, rnd() * 0.1 + 0.9)
    S.count.burp = S.count.burp + 1
end

-- random.pop (EntityItem.onCollideWithPlayer): 0.2, ((r − r)·0.7 + 1)·2.
function S.pop(x, y, z)
    PlaySound3D(R .. "pop.ogg", Vec3(x, y, z), 0.2, ((rnd() - rnd()) * 0.7 + 1) * 2)
    S.count.pop = S.count.pop + 1
end

-- random.click — нажатие кнопки интерфейса (GuiButton.func_146113_a): 0.25, тон 1.
function S.click()
    PlaySound(R .. "click.ogg", 0.25, 1)
    S.count.click = S.count.click + 1
end

-- Приземление с высоты на блок id (EntityLivingBase.fall): звук шага его
-- материала, громкость ×0.5, тон ×0.75.
function S.land(id, x, y, z)
    local kind, pitch = info(id)
    if kind then
        PlaySound3D(file("step", kind), Vec3(x, y, z), 0.5, pitch * 0.75)
        S.count.land = (S.count.land or 0) + 1
    end
end

-- Сколько вариантов у материала — для проверки, что файлы на месте.
S.VARIANTS = VARIANTS
S.kindOf = info

return S
