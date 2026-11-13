-- ---------------------------------------------------------------------------
-- particles.lua — осколки блоков: EffectRenderer и EntityDiggingFX 1.7.10.
--
-- Два эффекта с разными условиями, а не один «взрыв крошек»:
--   destroy(...) — блок разрушен (addBlockDestroyEffects): ровно 64 осколка
--                  сеткой 4×4×4 по объёму блока, скорость — от центра наружу;
--   hit(...)     — удар по блоку (addBlockHitEffects, каждый тик добычи): один
--                  маленький осколок у грани удара, на 0.1 от поверхности.
-- Трещины на самом блоке — не здесь (interact.lua, Breaking Overlay).
--
-- Осколок — частица ДВИЖКА (pfx.lua, вид «dig»): квадрат к камере с
-- кусочком текстуры стороны блока из атласа блоков. Полёт, тяжесть,
-- сопротивление и удары о блоки считает система частиц движка (столкновение
-- с миром — по коллайдерам colliders.lua); здесь — только где и каким осколок
-- рождается, числами EntityDiggingFX. Свет — клетки рождения (серый 0.6 ×
-- карта света): за секунду жизни осколок далеко не улетает.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local A = require "atlas"
local Bo = require "bounds"
local Light = require "lightmap"

local Pf = require "pfx"

local Pt = {}

local rnd = math.random

-- Сторона 0..5 (вниз, вверх, Z−, Z+, X−, X+) — плитка блока этой стороны
-- (getIcon(side, meta): у пшеницы — картинка стадии, у грядки — влажный верх).
local curMeta = 0
local function tileOfSide(id, side)
    local t = A.blockTiles[id]
    if not t then return nil end
    if t.particle then return t.particle end
    if t.stages then return t.stages[math.min(7, curMeta) + 1] end
    if side == 1 and t.wet and curMeta > 0 then return t.wet end
    if side == 0 then return t.bottom or t.side end
    if side == 1 then return t.top or t.side end
    return t.side
end
Pt.tileOfSide = tileOfSide

-- Сторона по нормали грани удара.
function Pt.sideOf(nx, ny, nz)
    if ny < 0 then return 0 elseif ny > 0 then return 1
    elseif nz < 0 then return 2 elseif nz > 0 then return 3
    elseif nx < 0 then return 4 end
    return 5
end

-- Кадр листа движка для кусочка плитки tile: атлас 16×16 плиток, плитка —
-- 4×4 кусочка, значит лист 64×64 кадра. (jx, jy) — сдвиг кусочка 0..2 от
-- левого верхнего угла плитки (particleTextureJitter: у оригинала сдвиг
-- дробный, 0..3 четверти плитки; здесь — целые четверти, на глаз то же).
-- Кадры движка считаются слева направо, СВЕРХУ вниз; плитки атласа лежат
-- снизу вверх.
local function frameOf(tile, jx, jy)
    local tx, ty = tile % 16, tile // 16
    local col = tx * 4 + jx
    local rowFromBottom = ty * 4 + 3 - jy
    return (63 - rowFromBottom) * 64 + col
end
Pt.frameOf = frameOf

-- EntityFX(world, x, y, z, vx, vy, vz) + EntityDiggingFX: скорость — заданная
-- плюс случайная, приведённая к длине (rand + rand + 1)·0.15·0.4, вверх ещё
-- 0.1; жизнь 4/(rand·0.9 + 0.1) тиков; размер (rand·0.5 + 0.5)·2, у осколка
-- вдвое меньше; серый 0.6; тяжесть блока 1.
-- Возвращает описание частицы для pfx (ещё не рождённой): удар правит его.
local function make(id, side, x, y, z, vx, vy, vz)
    local tile = tileOfSide(id, side)
    if not tile then return nil end
    local mx = vx + (rnd() * 2 - 1) * 0.4
    local my = vy + (rnd() * 2 - 1) * 0.4
    local mz = vz + (rnd() * 2 - 1) * 0.4
    local f = (rnd() + rnd() + 1) * 0.15
    local len = math.sqrt(mx * mx + my * my + mz * mz)
    if len < 1e-6 then len = 1 end
    mx, my, mz = mx / len * f * 0.4, my / len * f * 0.4 + 0.1, mz / len * f * 0.4
    local scale = (rnd() * 0.5 + 0.5) * 2 / 2
    -- Свет клетки: серый 0.6 × цвет карты света (уровни неба и блоков).
    local lr, lg, lb = Light.at(Light.levels(x, y, z))
    return {
        x = x, y = y, z = z, vx = mx, vy = my, vz = mz,
        life = math.floor(4 / (rnd() * 0.9 + 0.1)),
        scale = scale, size = 0.2 * scale,
        r = 0.6 * lr, g = 0.6 * lg, b = 0.6 * lb,
        frame = frameOf(tile, math.floor(rnd() * 3), math.floor(rnd() * 3)),
    }
end

-- Блок разрушен: 4×4×4 осколка, центры в (i + 0.5)/4 по каждой оси, скорость
-- — от центра блока к осколку; сторона текстуры — случайная.
-- Возвращает число родившихся и их описания (для самопроверки).
function Pt.destroy(id, meta, x, y, z)
    if B.drawKind[id] == 4 or not A.blockTiles[id] then return 0, {} end
    curMeta = meta or 0
    local list = {}
    for i = 0, 3 do
        for j = 0, 3 do
            for k = 0, 3 do
                local px, py, pz = x + (i + 0.5) / 4, y + (j + 0.5) / 4, z + (k + 0.5) / 4
                local p = make(id, rnd(0, 5), px, py, pz, px - x - 0.5, py - y - 0.5, pz - z - 0.5)
                if p then list[#list + 1] = p end
            end
        end
    end
    return Pf.spawn("dig", list), list
end

-- Удар по грани side: точка — случайная внутри границ блока (без полосы 0.1 у
-- краёв), по оси грани — на 0.1 снаружи поверхности; скорость ×0.2
-- (multiplyVelocity: по вертикали (v − 0.1)·0.2 + 0.1), размер ×0.6.
function Pt.hit(id, meta, x, y, z, side)
    if B.drawKind[id] == 4 then return nil end
    curMeta = meta or 0
    local b = Bo.render(id, meta, x, y, z)
    local f = 0.1
    local px = x + rnd() * (b[4] - b[1] - f * 2) + f + b[1]
    local py = y + rnd() * (b[5] - b[2] - f * 2) + f + b[2]
    local pz = z + rnd() * (b[6] - b[3] - f * 2) + f + b[3]
    if side == 0 then py = y + b[2] - f
    elseif side == 1 then py = y + b[5] + f
    elseif side == 2 then pz = z + b[3] - f
    elseif side == 3 then pz = z + b[6] + f
    elseif side == 4 then px = x + b[1] - f
    elseif side == 5 then px = x + b[4] + f end
    local p = make(id, side, px, py, pz, 0, 0, 0)
    if not p then return nil end
    p.vx, p.vy, p.vz = p.vx * 0.2, (p.vy - 0.1) * 0.2 + 0.1, p.vz * 0.2
    p.size = p.size * 0.6
    Pf.spawn("dig", {p})
    return p
end

function Pt.update(dt)
    local d = Pt.demo
    if d then
        d.t = d.t - dt
        if d.t <= 0 then
            d.t = 0.4
            Pt.destroy(B.byName.dirt.id, 0, d.x, d.y, d.z)
            for _ = 1, 3 do Pt.hit(B.byName.stone.id, 0, d.x + 1, d.y - 1, d.z, 1) end
        end
    end
end

function Pt.count() return Pf.count("dig") end

-- Самопроверка (--gencheck, строка PARTICLECHECK): 64 осколка сеткой 4×4×4,
-- скорость от центра, удар — один осколок в 0.1 от грани; все 65 родились
-- в струе движка; кадр листа — тот кусок атласа, где лежит плитка.
function Pt.selfCheck()
    local before = Pt.count()
    local x, y, z = 40, 200, 40
    local stone = B.byName.stone.id
    local made, list = Pt.destroy(stone, 0, x, y, z)
    local grid, outwardSum = true, 0
    local seen = {}
    for _, p in ipairs(list) do
        local gi, gj, gk = (p.x - x) * 4 - 0.5, (p.y - y) * 4 - 0.5, (p.z - z) * 4 - 0.5
        if math.abs(gi - math.floor(gi + 0.5)) > 1e-6 or math.abs(gj - math.floor(gj + 0.5)) > 1e-6 then grid = false end
        seen[math.floor(gi + 0.5) * 16 + math.floor(gj + 0.5) * 4 + math.floor(gk + 0.5)] = true
        -- В среднем скорость смотрит от центра (у внутренних осколков случайная
        -- добавка ±0.4 сильнее смещения ±0.125 — у оригинала так же).
        outwardSum = outwardSum + (p.x - x - 0.5) * p.vx + (p.z - z - 0.5) * p.vz
    end
    local outward = outwardSum > 0
    local cells = 0
    for _ in pairs(seen) do cells = cells + 1 end
    local h = Pt.hit(stone, 0, x, y, z, 1)
    local hitOk = h and math.abs(h.y - (y + 1.1)) < 1e-6 and h.x >= x + 0.1 and h.x <= x + 0.9
    local alive = Pt.count() - before
    -- Кадр: плитка 0 (левый нижний угол атласа), кусочек (0, 0) — левый
    -- верхний её угол: столбец 0, строка 60 сверху из 64.
    local frameOk = frameOf(0, 0, 0) == 60 * 64 and frameOf(17, 2, 1) == (63 - (4 + 2)) * 64 + 6
    local ok = made == 64 and cells == 64 and grid and outward and hitOk and alive == 65 and frameOk
    return string.format("PARTICLECHECK: %s осколков=%d клеток=%d сетка=%s наружу=%s удар=%s в_движке=%d кадр=%s",
        ok and "PASS" or "FAIL", made, cells, tostring(grid), tostring(outward), tostring(hitOk), alive, tostring(frameOk))
end

return Pt
