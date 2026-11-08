-- ---------------------------------------------------------------------------
-- hand.lua — рука и предмет при виде от первого лица, как в Minecraft 1.7.10
-- (ItemRenderer.renderItemInFirstPerson).
--
-- Позы — те же цепочки glTranslatef/glRotatef, что в оригинале, числа в
-- числа (mat.lua собирает их в матрицу). Отсюда всё поведение оригинала:
--   * пустая рука — правая рука модели, взмах вперёд-вниз (6 тиков);
--   * предмет — без руки, взмах дугой, при смене ячейки опускается и
--     поднимается (equippedProgress);
--   * еда и питьё — к лицу, с подрагиванием каждые 4 тика;
--   * меч на ПКМ — защитная поза, лук — натяжение по времени удержания;
--   * карта — двумя руками, по высоте зависит от наклона взгляда;
--   * рука чуть отстаёт от поворота взгляда (renderArmPitch/Yaw).
-- Покачивание при ходьбе — общее с камерой (EntityRenderer.setupViewBobbing):
-- рука рисуется в пространстве глаза с тем же покачиванием, что и мир.
--
-- Рука — коробка ModelBiped (4×12×4 пикселя, развёртка скина с 40,16;
-- верхний слой — с 40,32) в координатах модели Minecraft (Y вниз); предмет —
-- плоский, выдавленный по пикселям как renderItemIn2D (толщина 1/16, x = 0 у
-- правого края иконки), блок — куб 1×1×1 с центром в нуле.
-- ---------------------------------------------------------------------------
local B = require "blocks"
local Atl = require "atlas"
local M = require "mat"
local Anim = require "anim"

local Hand = {}

local arms = {}
local item, mapObj
local itemKey = nil
local HAND_BLOCK = "assets/materials/hand_block.sagemat"
local HAND_ITEM = "assets/materials/hand_item.sagemat"
local HIDDEN = Vec3(0.0001, 0.0001, 0.0001)
local PI = math.pi
local sin, cos, sqrt, abs = math.sin, math.cos, math.sqrt, math.abs

-- --- Меши -------------------------------------------------------------------

-- Коробка ModelBox: угол (x1,y1,z1), размер (dx,dy,dz) в пикселях, развёртка
-- с (tu, tv), раздута на grow пикселей. Порядок граней и UV — как в ModelBox
-- и TexturedQuad 1.7.10.
local function boxInto(pos, nrm, uv, idx, x1, y1, z1, dx, dy, dz, tu, tv, grow)
    local x2, y2, z2 = x1 + dx + grow, y1 + dy + grow, z1 + dz + grow
    x1, y1, z1 = x1 - grow, y1 - grow, z1 - grow
    local v = {
        [0] = {x1, y1, z1}, {x2, y1, z1}, {x2, y2, z1}, {x1, y2, z1},
        {x1, y1, z2}, {x2, y1, z2}, {x2, y2, z2}, {x1, y2, z2},
    }
    local quads = {
        {{5, 1, 2, 6}, tu + dz + dx, tv + dz, tu + dz + dx + dz, tv + dz + dy},
        {{0, 4, 7, 3}, tu, tv + dz, tu + dz, tv + dz + dy},
        {{5, 4, 0, 1}, tu + dz, tv, tu + dz + dx, tv + dz},
        {{2, 3, 7, 6}, tu + dz + dx, tv + dz, tu + dz + dx + dx, tv},
        {{1, 0, 3, 2}, tu + dz, tv + dz, tu + dz + dx, tv + dz + dy},
        {{4, 5, 6, 7}, tu + dz + dx + dz, tv + dz, tu + dz + dx + dz + dx, tv + dz + dy},
    }
    for _, q in ipairs(quads) do
        local vs, u1, v1, u2, v2 = q[1], q[2], q[3], q[4], q[5]
        local tex = {{u2, v1}, {u1, v1}, {u1, v2}, {u2, v2}}
        local a, b, c = v[vs[1]], v[vs[2]], v[vs[3]]
        -- Нормаль — как TexturedQuad: (v1 − v2) × (v1 − v0).
        local e1 = {b[1] - c[1], b[2] - c[2], b[3] - c[3]}
        local e2 = {b[1] - a[1], b[2] - a[2], b[3] - a[3]}
        local nx, ny, nz = e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3], e1[1] * e2[2] - e1[2] * e2[1]
        local l = math.max(1e-6, sqrt(nx * nx + ny * ny + nz * nz))
        local base = #pos // 3
        for k = 1, 4 do
            local p = v[vs[k]]
            pos[#pos + 1] = p[1] / 16; pos[#pos + 1] = p[2] / 16; pos[#pos + 1] = p[3] / 16
            nrm[#nrm + 1] = nx / l; nrm[#nrm + 1] = ny / l; nrm[#nrm + 1] = nz / l
            -- Холст скина в движке — строками снизу вверх.
            uv[#uv + 1] = tex[k][1] / 64; uv[#uv + 1] = 1 - tex[k][2] / 64
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do idx[#idx + 1] = base + i end
    end
end

-- Правая рука ModelBiped: коробка (-3,-2,-2) 4×12×4 от точки вращения,
-- верхний слой (рукав) — на 0.25 пикселя шире.
local function armMesh()
    local pos, nrm, uv, idx = {}, {}, {}, {}
    boxInto(pos, nrm, uv, idx, -3, -2, -2, 4, 12, 4, 40, 16, 0)
    boxInto(pos, nrm, uv, idx, -3, -2, -2, 4, 12, 4, 40, 32, 0.25)
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, index = idx}
    return m
end
Hand.armMesh = armMesh

-- Плоский предмет, как renderItemIn2D: квадрат 1×1 при z от −1/16 до 0, по
-- пикселю — бока там, где сосед прозрачный. x = 0 — ПРАВЫЙ край иконки,
-- y = 0 — нижний (так рисует оригинал, и его повороты рассчитаны на это).
local flatCache = {}
function Hand.flatItemMesh(id, frame)
    local cacheKey = id * 1000 + (frame or 0)
    if flatCache[cacheKey] then return flatCache[cacheKey] end
    local ix, iy, w, h = Atl.iconRect(id, frame)
    local canvas = Atl.iconCanvas
    local W_, H_ = Atl.ICON * Atl.ICON_COLS, Atl.iconSheetHeight
    local T = 1 / 16
    -- Сетка — пиксели картинки предмета (16×16), а не ячейки листа (128):
    -- бока на каждый пиксель ячейки давали меш в десятки раз тяжелее, а кадр
    -- компаса или часов строит его заново.
    local cell = w // 16
    local solid = {}
    for r = 0, 15 do
        for c = 0, 15 do
            local px, py = ix + c * cell + cell // 2, iy + r * cell + cell // 2
            if canvas.get(px, H_ - 1 - py).w >= 0.5 then solid[r * 16 + c] = true end
        end
    end
    local iw, ih = w, h
    w, h = 16, 16
    local function at(c, r) return c >= 0 and r >= 0 and c < w and r < h and solid[r * w + c] end
    local pos, nrm, uv, uv2, idx = {}, {}, {}, {}, {}
    local function quad(p, n, t)
        local base = #pos // 3
        for k = 1, 4 do
            pos[#pos + 1] = p[k][1]; pos[#pos + 1] = p[k][2]; pos[#pos + 1] = p[k][3]
            nrm[#nrm + 1] = n[1]; nrm[#nrm + 1] = n[2]; nrm[#nrm + 1] = n[3]
            uv[#uv + 1] = t[k][1]; uv[#uv + 1] = t[k][2]
            uv2[#uv2 + 1] = 15; uv2[#uv2 + 1] = 0
        end
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do idx[#idx + 1] = base + i end
    end
    -- Лицевая и тыльная стороны — целым квадратом (прозрачное отсекает шейдер).
    local u0, u1 = ix / W_, (ix + iw) / W_
    local vTop, vBot = 1 - iy / H_, 1 - (iy + ih) / H_
    quad({{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}}, {0, 0, 1}, {{u1, vBot}, {u0, vBot}, {u0, vTop}, {u1, vTop}})
    quad({{0, 1, -T}, {1, 1, -T}, {1, 0, -T}, {0, 0, -T}}, {0, 0, -1}, {{u1, vTop}, {u0, vTop}, {u0, vBot}, {u1, vBot}})
    -- Бока по пикселям.
    for r = 0, h - 1 do
        for c = 0, w - 1 do
            if solid[r * w + c] then
                local x0, x1 = (w - c - 1) / w, (w - c) / w
                local y0, y1 = (h - r - 1) / h, (h - r) / h
                local pu0, pu1 = (ix + c * cell) / W_, (ix + (c + 1) * cell) / W_
                local pv1, pv0 = 1 - (iy + r * cell) / H_, 1 - (iy + (r + 1) * cell) / H_
                local t = {{pu0, pv0}, {pu1, pv0}, {pu1, pv1}, {pu0, pv1}}
                if not at(c - 1, r) then quad({{x1, y0, 0}, {x1, y0, -T}, {x1, y1, -T}, {x1, y1, 0}}, {1, 0, 0}, t) end
                if not at(c + 1, r) then quad({{x0, y0, -T}, {x0, y0, 0}, {x0, y1, 0}, {x0, y1, -T}}, {-1, 0, 0}, t) end
                if not at(c, r - 1) then quad({{x0, y1, 0}, {x1, y1, 0}, {x1, y1, -T}, {x0, y1, -T}}, {0, 1, 0}, t) end
                if not at(c, r + 1) then quad({{x0, y0, -T}, {x1, y0, -T}, {x1, y0, 0}, {x0, y0, 0}}, {0, -1, 0}, t) end
            end
        end
    end
    local m = mesh()
    m.arrays{position = pos, normal = nrm, uv = uv, uv2 = uv2, index = idx}
    -- Пока лист иконок дорисовывается порциями, меш не запоминается: иначе
    -- осталась бы пустая модель предмета.
    if Atl.iconsReady then flatCache[cacheKey] = m end
    return m
end

-- Блок ли рисуется кубом (RenderBlocks.renderItemIn3d): трава, цветы,
-- факел, тростник — плоской иконкой.
function Hand.isCube(id)
    local d = B.byId[id]
    return d and d.isBlock and d.draw ~= "cross" and d.draw ~= "torch" and d.draw ~= "ladder"
end

-- Поставить объекту меш предмета id (куб или плоский) и его материал.
local cubeCache = {}
function Hand.setItemMesh(obj, id)
    if Hand.isCube(id) then
        cubeCache[id] = cubeCache[id] or require("drops").cubeMesh(id, 1)
        cubeCache[id].apply(obj)
        SetMaterial(obj, HAND_BLOCK)
    else
        Hand.flatItemMesh(id, require("needle").frame(id)).apply(obj)
        SetMaterial(obj, HAND_ITEM)
    end
end

-- Ключ меша предмета: номер и кадр стрелки (компас, часы) — меш меняется,
-- когда стрелка перешла на другой кадр.
function Hand.meshKey(id)
    return id * 1000 + (require("needle").frame(id) or 0)
end

-- Как ItemRenderer.renderItem ставит предмет (общая часть первого и третьего
-- лица): блок — как есть, плоский — сдвиг, ×1.5 и два поворота.
function Hand.itemTransform(m, id)
    if Hand.isCube(id) then return m end
    M.translate(m, 0, -0.3, 0)
    M.scale(m, 1.5)
    M.rotate(m, 50, 0, 1, 0)
    M.rotate(m, 335, 0, 0, 1)
    M.translate(m, -0.9375, -0.0625, 0)
    return m
end

-- --- Объекты ----------------------------------------------------------------

-- Рука, предмет и карта от первого лица — свой слой: камера рисует его
-- отдельным проходом после мира со сброшенной глубиной (game.lua), поэтому
-- рука не уходит в блоки, как и у оригинала (renderHand после мира).
Hand.LAYER = "viewmodel"

function Hand.init(cameraObj)
    for i = 1, 2 do
        arms[i] = SpawnObject("First Person Arm " .. i)
        arms[i]:SetParent(cameraObj)
        armMesh().apply(arms[i])
        arms[i]:GetRenderer().Layer = Hand.LAYER
        arms[i].Transform.Scale = HIDDEN
    end
    item = SpawnObject("First Person Item")
    item:SetParent(cameraObj)
    item.Transform.Scale = HIDDEN
    mapObj = SpawnObject("First Person Map")
    mapObj:SetParent(cameraObj)
    mapObj.Transform.Scale = HIDDEN
end

function Hand.setMaterial(mat)
    for _, a in ipairs(arms) do SetMaterial(a, mat) end
end

-- Покачивание (EntityRenderer.setupViewBobbing) — матрица пространства глаза.
function Hand.bobMatrix()
    local f2, f3, f4 = Anim.bobbing()
    local m = M.identity()
    M.translate(m, sin(f2 * PI) * f3 * 0.5, -abs(cos(f2 * PI) * f3), 0)
    M.rotate(m, sin(f2 * PI) * f3 * 3, 0, 0, 1)
    M.rotate(m, abs(cos(f2 * PI - 0.2) * f3) * 5, 1, 0, 0)
    M.rotate(m, f4, 1, 0, 0)
    return m
end

-- Правая рука модели в позе renderFirstPersonArm: точка вращения (-5, 2, 0),
-- покачивание покоя даёт ей наклон 0.1 рад по Z.
local function armModel(m)
    M.translate(m, -5 / 16, 2 / 16, 0)
    M.rotate(m, math.deg(0.1), 0, 0, 1)
    return m
end

local function hide(o) o.Transform.Scale = HIDDEN end

-- Карта двумя руками (ветка filled_map). heldPitch — наклон взгляда Minecraft.
local function drawMap(base, sw, eq, mcPitch, mapTex)
    local m = M.copy(base)
    local f13 = 0.8
    local f6, f7 = sin(sw * PI), sin(sqrt(sw) * PI)
    M.translate(m, -f7 * 0.4, sin(sqrt(sw) * PI * 2) * 0.2, -f6 * 0.2)
    local f5 = 1 - mcPitch / 45 + 0.1
    f5 = math.max(0, math.min(1, f5))
    f5 = -cos(f5 * PI) * 0.5 + 0.5
    M.translate(m, 0, 0 * f13 - (1 - eq) * 1.2 - f5 * 0.5 + 0.04, -0.9 * f13)
    M.rotate(m, 90, 0, 1, 0)
    M.rotate(m, f5 * -85, 0, 0, 1)
    for i = 0, 1 do
        local j = i * 2 - 1
        local a = M.copy(m)
        M.translate(a, -0, -0.6, 1.1 * j)
        M.rotate(a, -45 * j, 1, 0, 0)
        M.rotate(a, -90, 0, 0, 1)
        M.rotate(a, 59, 0, 0, 1)
        M.rotate(a, -65 * j, 0, 1, 0)
        M.applyTo(arms[i + 1], armModel(a))
    end
    local f6b, f8 = sin(sw * sw * PI), sin(sqrt(sw) * PI)
    M.rotate(m, -f6b * 20, 0, 1, 0)
    M.rotate(m, -f8 * 30, 0, 0, 1)
    M.rotate(m, -f8 * 80, 1, 0, 0)
    M.scale(m, 0.38)
    M.rotate(m, 90, 0, 1, 0)
    M.rotate(m, 180, 0, 0, 1)
    M.translate(m, -1, -1, 0)
    M.scale(m, 0.015625)
    -- Сама карта: подложка от −7 до 135 пикселей карты (меш карты — в map.lua).
    require("map").placeInHand(mapObj, m, nil, Hand.LAYER)
end

-- Каждый кадр. visible — вид глазами; heldId — что в руке (0 — пусто).
function Hand.update(dt, visible, P, heldId)
    if not item then return end
    if not visible then
        hide(arms[1]); hide(arms[2]); hide(item); hide(mapObj)
        return
    end
    local eq, shown = Anim.equip()
    local sw = Anim.swingProgress()
    -- Свет руки и предмета — клетки глаз игрока (renderItemInFirstPerson:
    -- getLightBrightnessForSkyBlocks у posY игрока); рука — материалом скина
    -- (avatar.lua), предмет — уровнями в цвете объекта, карта — цветом карты.
    local Light = require "lightmap"
    local ex, ey, ez = P.eye()
    local ls, lb = Light.levels(ex, ey, ez)
    Light.applyLevels(item, ls, lb)
    Hand.lightLevels = {ls, lb}
    local base = Hand.bobMatrix()
    -- Отставание руки от взгляда: (взгляд − отставший)·0.1 (знаки Minecraft:
    -- наклон вниз — плюс, рыскание — в другую сторону, чем у игры).
    local lagPitch, lagYaw = Anim.armLag()
    M.rotate(base, (lagPitch - P.pitch) * 0.1, 1, 0, 0)
    M.rotate(base, (lagYaw - Anim.viewYaw()) * 0.1, 0, 1, 0)

    local d = shown ~= 0 and B.byId[shown] or nil
    if d and d.map then
        hide(item)
        drawMap(base, sw, eq, -P.pitch)
        return
    end
    hide(mapObj)

    if not d then
        -- Пустая рука.
        hide(item); hide(arms[2])
        local m = M.copy(base)
        local f13 = 0.8
        local f6, f7 = sin(sw * PI), sin(sqrt(sw) * PI)
        M.translate(m, -f7 * 0.3, sin(sqrt(sw) * PI * 2) * 0.4, -f6 * 0.4)
        M.translate(m, 0.8 * f13, -0.75 * f13 - (1 - eq) * 0.6, -0.9 * f13)
        M.rotate(m, 45, 0, 1, 0)
        local f6b = sin(sw * sw * PI)
        M.rotate(m, f7 * 70, 0, 1, 0)
        M.rotate(m, -f6b * 20, 0, 0, 1)
        M.translate(m, -1, 3.6, 3.5)
        M.rotate(m, 120, 0, 0, 1)
        M.rotate(m, 200, 1, 0, 0)
        M.rotate(m, -135, 0, 1, 0)
        M.translate(m, 5.6, 0, 0)
        M.applyTo(arms[1], armModel(m))
        return
    end

    -- Предмет в руке (руки не видно).
    hide(arms[1]); hide(arms[2])
    if itemKey ~= Hand.meshKey(shown) then
        itemKey = Hand.meshKey(shown)
        Hand.setItemMesh(item, Hand.meshIdOf(shown))
        item:GetRenderer().Layer = Hand.LAYER
    end
    local u = Anim.use
    local action = u and u.id == shown and u.action or nil
    -- Лук меняет картинку по времени натяжения (ItemBow.getItemIconForUseDuration).
    if d.bow then
        local want = shown
        if action == "bow" then
            local j = Anim.useTicks()
            want = j >= 18 and B.byName.bow_pulling_2.id or (j > 13 and B.byName.bow_pulling_1.id
                or (j > 0 and B.byName.bow_pulling_0.id or shown))
        end
        if itemKey ~= Hand.meshKey(want) then itemKey = Hand.meshKey(want); Hand.setItemMesh(item, want); item:GetRenderer().Layer = Hand.LAYER end
    end

    local m = M.copy(base)
    local f13 = 0.8
    if action == "eat" or action == "drink" then
        local f6 = u.count - Anim.partial + 1
        local f7 = 1 - f6 / u.max
        local f8 = 1 - f7
        f8 = f8 * f8 * f8; f8 = f8 * f8 * f8; f8 = f8 * f8 * f8
        local f9 = 1 - f8
        M.translate(m, 0, abs(cos(f6 / 4 * PI) * 0.1) * (f7 > 0.2 and 1 or 0), 0)
        M.translate(m, f9 * 0.6, -f9 * 0.5, 0)
        M.rotate(m, f9 * 90, 0, 1, 0)
        M.rotate(m, f9 * 10, 1, 0, 0)
        M.rotate(m, f9 * 30, 0, 0, 1)
    else
        local f6, f7 = sin(sw * PI), sin(sqrt(sw) * PI)
        M.translate(m, -f7 * 0.4, sin(sqrt(sw) * PI * 2) * 0.2, -f6 * 0.2)
    end
    M.translate(m, 0.7 * f13, -0.65 * f13 - (1 - eq) * 0.6, -0.9 * f13)
    M.rotate(m, 45, 0, 1, 0)
    local f6, f7 = sin(sw * sw * PI), sin(sqrt(sw) * PI)
    M.rotate(m, -f6 * 20, 0, 1, 0)
    M.rotate(m, -f7 * 20, 0, 0, 1)
    M.rotate(m, -f7 * 80, 1, 0, 0)
    M.scale(m, 0.4)
    if action == "block" then
        M.translate(m, -0.5, 0.2, 0)
        M.rotate(m, 30, 0, 1, 0)
        M.rotate(m, -80, 1, 0, 0)
        M.rotate(m, 60, 0, 1, 0)
    elseif action == "bow" then
        M.rotate(m, -18, 0, 0, 1)
        M.rotate(m, -12, 0, 1, 0)
        M.rotate(m, -8, 1, 0, 0)
        M.translate(m, -0.9, 0.2, 0)
        local f10 = Anim.useTicks()
        local f11 = f10 / 20
        f11 = math.min(1, (f11 * f11 + f11 * 2) / 3)
        if f11 > 0.1 then M.translate(m, 0, sin((f10 - 0.1) * 1.3) * 0.01 * (f11 - 0.1), 0) end
        M.translate(m, 0, 0, f11 * 0.1)
        -- Растяжение лука вдоль Z (×(1 + 0.2·натяжение)) объект с поворотами
        -- после него не передаёт без перекоса; оно в пределах 20 % и опущено.
        M.rotate(m, -335, 0, 0, 1)
        M.rotate(m, -50, 0, 1, 0)
        M.rotate(m, 50, 0, 1, 0)
        M.rotate(m, 335, 0, 0, 1)
    end
    Hand.itemTransform(m, shown)
    M.applyTo(item, m)
end

-- Какой меш у предмета в руке (лук в покое — свой).
function Hand.meshIdOf(id) return id end

return Hand
