-- ---------------------------------------------------------------------------
-- drops.lua — выпавшие предметы и крошки от сломанного блока.
--
-- Выпавший блок — маленький кубик с гранями из атласа, предмет — плоская
-- картинка из листа иконок. Оба вращаются, падают, лежат на земле и
-- притягиваются к игроку, если в рюкзаке есть место. Одинаковые предметы
-- рядом сливаются в одну стопку — иначе на месте вырубленного леса лежали бы
-- сотни объектов.
-- ---------------------------------------------------------------------------
local W = require "world"
local B = require "blocks"
local A = require "atlas"

local D = {}

local list = {}
local bits = {}
local meshCache = {}
local ICON_MAT = "sagecraft_icon_mat"
local CHUNK_MAT = "assets/materials/chunk.sagemat"

function D.init()
    material(ICON_MAT, {texture = A.ICONS, unlit = true, cutoff = 0.5, double_sided = true, nearest = true})
end

local FACES = {
    {{0,1,0},{0,1,1},{1,1,1},{1,1,0}, n = {0,1,0}, t = "top"},
    {{0,0,0},{1,0,0},{1,0,1},{0,0,1}, n = {0,-1,0}, t = "bottom"},
    {{1,0,0},{1,1,0},{1,1,1},{1,0,1}, n = {1,0,0}, t = "side"},
    {{0,0,0},{0,0,1},{0,1,1},{0,1,0}, n = {-1,0,0}, t = "side"},
    {{0,0,1},{1,0,1},{1,1,1},{0,1,1}, n = {0,0,1}, t = "front"},
    {{0,0,0},{0,1,0},{1,1,0},{1,0,0}, n = {0,0,-1}, t = "side"},
}
local QUV = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}

-- Кубик с центром в нуле: size — сторона; sub — доля плитки (крошки берут
-- кусочек текстуры, а не всю).
local function cubeMesh(id, size, sub, su, sv)
    local tiles = A.blockTiles[id]
    local pos, nrm, uv, uv2, idx = {}, {}, {}, {}, {}
    local nv = 0
    for _, f in ipairs(FACES) do
        local tu, tv, ts = A.tileOrigin(tiles[f.t])
        for k = 1, 4 do
            local p = f[k]
            for a = 1, 3 do pos[#pos + 1] = (p[a] - 0.5) * size end
            for a = 1, 3 do nrm[#nrm + 1] = f.n[a] end
            uv[#uv + 1] = tu + (su + QUV[k][1] * sub) * ts
            uv[#uv + 1] = tv + (sv + QUV[k][2] * sub) * ts
            uv2[#uv2 + 1] = 15; uv2[#uv2 + 1] = 0
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do idx[#idx + 1] = nv + i end
        nv = nv + 4
    end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, uv2 = uv2, index = idx}
    return m
end

local function iconMesh(id, size)
    local x, y, w, h = A.iconRect(id)
    local W_, H_ = A.ICON * A.ICON_COLS, A.iconSheetHeight
    -- Прямоугольник иконки считается от верха листа, UV — от низа.
    local u0, u1 = x / W_, (x + w) / W_
    local v1 = 1 - y / H_
    local v0 = 1 - (y + h) / H_
    local s = size / 2
    local m = mesh()
    m.arrays{
        position = {-s, -s, 0,  s, -s, 0,  s, s, 0,  -s, s, 0},
        normal = {0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1},
        uv = {u0, v0, u1, v0, u1, v1, u0, v1},
        index = {1, 2, 3, 1, 3, 4},
    }
    return m
end

D.cubeMesh = function(id, size) return cubeMesh(id, size, 1, 0, 0) end
D.iconMesh = iconMesh

local function isCube(id)
    local d = B.byId[id]
    return d and d.isBlock and d.draw ~= "cross" and d.draw ~= "torch"
end

local function spawnObject(id)
    local o = SpawnObject("Drop " .. id)
    if isCube(id) then
        meshCache[id] = meshCache[id] or cubeMesh(id, 0.25, 1, 0, 0)
        meshCache[id].apply(o)
        SetMaterial(o, CHUNK_MAT)
    else
        local key = "icon" .. id
        meshCache[key] = meshCache[key] or iconMesh(id, 0.42)
        meshCache[key].apply(o)
        SetMaterial(o, ICON_MAT)
    end
    return o
end

function D.spawn(id, n, x, y, z, vx, vy, vz, wear)
    local e = {id = id, n = n, wear = wear, x = x, y = y, z = z,
               vx = vx or (math.random() - 0.5) * 2, vy = vy or 3.5, vz = vz or (math.random() - 0.5) * 2,
               age = 0, spin = math.random() * 360, obj = spawnObject(id)}
    list[#list + 1] = e
    return e
end

function D.spawnAtPlayer(id, n)
    local P = require "player"
    D.spawn(id, n, P.pos.x, P.pos.y + 1, P.pos.z, 0, 2, 0)
end

-- Бросок вперёд по взгляду; брошенное не подбирается сразу обратно.
function D.throwFromPlayer(id, n, wear)
    local P = require "player"
    local ex, ey, ez = P.eye()
    local dx, dy, dz = P.lookDir()
    local e = D.spawn(id, n, ex + dx * 0.4, ey - 0.3, ez + dz * 0.4, dx * 6, dy * 6 + 1.5, dz * 6, wear)
    e.age = -1.2
end

-- Крошки: кусочки текстуры блока разлетаются и пропадают.
function D.burst(id, x, y, z)
    if not isCube(id) then return end
    for i = 1, 8 do
        local o = SpawnObject("Bit")
        cubeMesh(id, 0.09, 0.2, math.random() * 0.8, math.random() * 0.8).apply(o)
        SetMaterial(o, CHUNK_MAT)
        bits[#bits + 1] = {obj = o, x = x + (math.random() - 0.5) * 0.6, y = y + (math.random() - 0.5) * 0.6,
                           z = z + (math.random() - 0.5) * 0.6, vx = (math.random() - 0.5) * 3,
                           vy = math.random() * 3 + 1, vz = (math.random() - 0.5) * 3, life = 0.5 + math.random() * 0.4}
    end
end

local function solidAt(x, y, z) return B.solid[W.get(math.floor(x), math.floor(y), math.floor(z))] end

local function physics(e, dt, radius)
    e.vy = e.vy - 18 * dt
    local nx, ny, nz = e.x + e.vx * dt, e.y + e.vy * dt, e.z + e.vz * dt
    if solidAt(nx, e.y, e.z) then e.vx = -e.vx * 0.3; nx = e.x end
    if solidAt(nx, e.y, nz) then e.vz = -e.vz * 0.3; nz = e.z end
    if solidAt(nx, ny - radius, nz) then
        ny = math.floor(ny - radius) + 1 + radius
        e.vy = 0
        e.vx, e.vz = e.vx * (1 - math.min(1, 8 * dt)), e.vz * (1 - math.min(1, 8 * dt))
    elseif solidAt(nx, ny + radius, nz) then
        e.vy = 0
        ny = e.y
    end
    e.x, e.y, e.z = nx, ny, nz
end

function D.update(dt)
    local P = require "player"
    local Inv = require "inventory"
    local px, py, pz = P.pos.x, P.pos.y + 0.9, P.pos.z
    local i = 1
    while i <= #list do
        local e = list[i]
        e.age = e.age + dt
        physics(e, dt, 0.13)
        local dx, dy, dz = px - e.x, py - e.y, pz - e.z
        local d2 = dx * dx + dy * dy + dz * dz
        local removed = false
        -- Радиус притяжения больше роста: предмет из ямки под ногами (на
        -- полтора-два блока ниже центра игрока) должен долетать сам.
        if e.age > 0.6 and d2 < 7.5 then
            -- Притягиваются, а у самого игрока — в рюкзак.
            local d = math.sqrt(d2)
            e.x, e.y, e.z = e.x + dx / d * 7 * dt, e.y + dy / d * 7 * dt, e.z + dz / d * 7 * dt
            if d < 0.9 then
                local left
                if e.wear then
                    left = Inv.add(e.id, e.n)
                    if left == 0 then
                        for k = 1, Inv.SIZE do
                            local s = Inv.slots[k]
                            if s and s.id == e.id and s.wear == 0 then s.wear = e.wear; break end
                        end
                    end
                else
                    left = Inv.add(e.id, e.n)
                end
                if left < e.n then require("interact").stats.picked = require("interact").stats.picked + (e.n - left) end
                e.n = left
                if left == 0 then removed = true end
            end
        end
        -- Слияние с соседом того же вида.
        if not removed and not e.wear then
            for j = i + 1, #list do
                local o = list[j]
                if o.id == e.id and not o.wear and math.abs(o.x - e.x) + math.abs(o.y - e.y) + math.abs(o.z - e.z) < 0.8
                    and e.n + o.n <= B.maxStack(e.id) then
                    o.n = o.n + e.n
                    removed = true
                    break
                end
            end
        end
        if e.age > 300 or e.y < -10 then removed = true end
        if removed then
            DestroyObject(e.obj)
            table.remove(list, i)
        else
            e.spin = (e.spin + dt * 70) % 360
            local bob = math.sin(e.age * 2.5) * 0.06 + 0.1
            e.obj.Transform.Position = Vec3(e.x, e.y + bob, e.z)
            e.obj.Transform.Rotation = Vec3(0, e.spin, 0)
            i = i + 1
        end
    end
    i = 1
    while i <= #bits do
        local b = bits[i]
        b.life = b.life - dt
        physics(b, dt, 0.045)
        if b.life <= 0 then
            DestroyObject(b.obj)
            table.remove(bits, i)
        else
            b.obj.Transform.Position = Vec3(b.x, b.y, b.z)
            i = i + 1
        end
    end
end

function D.count() return #list end

return D
