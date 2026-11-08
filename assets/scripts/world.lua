-- ---------------------------------------------------------------------------
-- world.lua — хранилище мира: участки 16×16 по горизонтали, высота HEIGHT,
-- по вертикали разрезаны на секции 16×16×16.
--
-- Почему секции, а не столбец целиком: секция — единица пересборки меша.
-- Поставили блок — пересобирается одна секция (и соседняя, если блок на
-- границе), а не столб высотой в 128 блоков. И память: пустая секция — nil,
-- небо над горами не занимает ничего.
--
-- В секции одна таблица чисел на 4096 клеток: номер блока в младших 10 битах,
-- свет неба — биты 10..13, свет блоков — 14..17. Одно число на клетку, а не
-- три таблицы: Lua хранит каждое число в 16 байтах, и мир на дальности 8
-- участков в трёх таблицах не помещался бы в разумную память.
-- ---------------------------------------------------------------------------
local W = {}

W.SIZE = 16
W.HEIGHT = 128
W.SECTIONS = W.HEIGHT // 16
W.SEA = 62

local ID_MASK = 0x3FF
local SKY_SHIFT, BLK_SHIFT = 10, 14
-- Метаданные блока (4 бита, как у Minecraft): ориентация факела и т.п.
local META_SHIFT = 18
local META_MASK = 15 << META_SHIFT

W.chunks = {}      -- [ключ участка] = участок
W.dirty = {}       -- [ключ секции] = true — меш секции нужно пересобрать

local function ckey(cx, cz) return (cx + 32768) * 65536 + (cz + 32768) end
W.ckey = ckey

-- Ключ секции: участок и номер секции по высоте в одном числе.
local function skey(cx, sy, cz) return ckey(cx, cz) * 16 + sy end
W.skey = skey

function W.chunk(cx, cz) return W.chunks[ckey(cx, cz)] end

-- Новый пустой участок. Пустая секция над поверхностью — nil, и читается как
-- «воздух под открытым небом» (свет неба 15). Это верно, пока над ней нет
-- блоков, — поэтому секции ниже самой высокой непустой создаются всегда.
function W.newChunk(cx, cz)
    local c = {cx = cx, cz = cz, sec = {}, top = -1, generated = false, lit = false}
    W.chunks[ckey(cx, cz)] = c
    return c
end

local function newSection()
    local t = {}
    local v = 15 << SKY_SHIFT
    for i = 1, 4096 do t[i] = v end
    return t
end
W.newSection = newSection

-- Секция участка, при нужде создаётся (вместе со всеми секциями ниже).
function W.section(c, sy, create)
    local s = c.sec[sy]
    if s or not create then return s end
    for y = 0, sy do
        if not c.sec[y] then c.sec[y] = newSection() end
    end
    if sy > c.top then c.top = sy end
    return c.sec[sy]
end

local floor = math.floor

-- Клетка мира целиком (число) или nil вне загруженного мира.
-- Ниже нуля — «коренная порода без света», выше потолка — воздух под небом.
function W.raw(x, y, z)
    if y < 0 then return 10 end
    if y >= W.HEIGHT then return 15 << SKY_SHIFT end
    local cx, cz = x // 16, z // 16
    local c = W.chunks[ckey(cx, cz)]
    if not c then return nil end
    local s = c.sec[y >> 4]
    if not s then return 15 << SKY_SHIFT end
    return s[(x & 15) + (z & 15) * 16 + (y & 15) * 256 + 1]
end

function W.get(x, y, z)
    local v = W.raw(x, y, z)
    if v == nil then return 0 end
    return v & ID_MASK
end

function W.unpack(v) return v & ID_MASK, (v >> SKY_SHIFT) & 15, (v >> BLK_SHIFT) & 15 end

-- Записать клетку целиком (без света: свет пересчитывает light.lua).
function W.setRaw(x, y, z, v)
    if y < 0 or y >= W.HEIGHT then return false end
    local c = W.chunks[ckey(x // 16, z // 16)]
    if not c then return false end
    local s = W.section(c, y >> 4, true)
    s[(x & 15) + (z & 15) * 16 + (y & 15) * 256 + 1] = v
    return true
end

function W.setId(x, y, z, id)
    local v = W.raw(x, y, z)
    if v == nil then return false end
    -- Новый блок — с чистыми метаданными (ориентация старого ему не нужна).
    return W.setRaw(x, y, z, (v & ~(ID_MASK | META_MASK)) | id)
end

W.META_SHIFT = META_SHIFT
function W.meta(x, y, z)
    local v = W.raw(x, y, z)
    if v == nil then return 0 end
    return (v >> META_SHIFT) & 15
end

function W.setMeta(x, y, z, m)
    local v = W.raw(x, y, z)
    if v == nil then return false end
    return W.setRaw(x, y, z, (v & ~META_MASK) | ((m & 15) << META_SHIFT))
end

function W.sky(x, y, z)
    local v = W.raw(x, y, z)
    if v == nil then return 15 end
    return (v >> SKY_SHIFT) & 15
end

function W.blockLight(x, y, z)
    local v = W.raw(x, y, z)
    if v == nil then return 0 end
    return (v >> BLK_SHIFT) & 15
end

function W.setLight(x, y, z, sky, blk)
    local v = W.raw(x, y, z)
    if v == nil or y < 0 or y >= W.HEIGHT then return end
    W.setRaw(x, y, z, (v & ID_MASK) | (sky << SKY_SHIFT) | (blk << BLK_SHIFT))
end

-- Пометить секцию (и соседей, если клетка на её границе) на пересборку меша.
function W.markDirty(x, y, z)
    local cx, cz, sy = x // 16, z // 16, y >> 4
    local lx, ly, lz = x & 15, y & 15, z & 15
    local function mark(a, b, c)
        if b < 0 or b >= W.SECTIONS then return end
        if W.chunks[ckey(a, c)] then W.dirty[skey(a, b, c)] = true end
    end
    mark(cx, sy, cz)
    if lx == 0 then mark(cx - 1, sy, cz) elseif lx == 15 then mark(cx + 1, sy, cz) end
    if lz == 0 then mark(cx, sy, cz - 1) elseif lz == 15 then mark(cx, sy, cz + 1) end
    if ly == 0 then mark(cx, sy - 1, cz) elseif ly == 15 then mark(cx, sy + 1, cz) end
end

function W.markSectionDirty(cx, sy, cz)
    if sy >= 0 and sy < W.SECTIONS and W.chunks[ckey(cx, cz)] then W.dirty[skey(cx, sy, cz)] = true end
end

-- Высота самого верхнего непрозрачного для света блока столба (для неба и
-- спавна). -1 — столб пуст.
function W.surface(x, z)
    local c = W.chunks[ckey(x // 16, z // 16)]
    if not c then return -1 end
    for y = (c.top + 1) * 16 - 1, 0, -1 do
        local id = W.get(x, y, z)
        if id ~= 0 and id ~= 22 and id ~= 23 and id ~= 24 and id ~= 20 then return y end
    end
    return -1
end

W.ID_MASK, W.SKY_SHIFT, W.BLK_SHIFT = ID_MASK, SKY_SHIFT, BLK_SHIFT
W.floor = floor

return W
