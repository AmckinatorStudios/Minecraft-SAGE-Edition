-- ---------------------------------------------------------------------------
-- mat.lua — аффинные матрицы 3×4 для поз «как в Minecraft».
--
-- Рендер Minecraft 1.7.10 ставит руку, предмет и камеру цепочками
-- glTranslatef / glRotatef / glScalef. Повторить их числами можно, только
-- собирая ту же цепочку: каждый вызов умножает текущую матрицу СПРАВА (как
-- OpenGL). Готовая матрица раскладывается в то, что понимает объект движка:
-- положение, углы Эйлера движка (R = Ry·Rx·Rz) и масштаб — с зеркалом, если
-- цепочка отражает (glScalef(-1, ...)).
--
-- Матрица — таблица из 12 чисел по строкам: {a11 a12 a13 tx, a21 ... ty, ...}.
-- ---------------------------------------------------------------------------
local M = {}

local sin, cos, rad, deg, sqrt = math.sin, math.cos, math.rad, math.deg, math.sqrt

function M.identity()
    return {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0}
end

function M.copy(m)
    return {m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12]}
end

-- a·b (оба 3×4, четвёртая строка подразумевается 0 0 0 1).
function M.mul(a, b)
    local r = {}
    for i = 0, 2 do
        local a1, a2, a3, a4 = a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3], a[i * 4 + 4]
        r[i * 4 + 1] = a1 * b[1] + a2 * b[5] + a3 * b[9]
        r[i * 4 + 2] = a1 * b[2] + a2 * b[6] + a3 * b[10]
        r[i * 4 + 3] = a1 * b[3] + a2 * b[7] + a3 * b[11]
        r[i * 4 + 4] = a1 * b[4] + a2 * b[8] + a3 * b[12] + a4
    end
    return r
end

-- glTranslatef: m = m · T
function M.translate(m, x, y, z)
    m[4] = m[4] + m[1] * x + m[2] * y + m[3] * z
    m[8] = m[8] + m[5] * x + m[6] * y + m[7] * z
    m[12] = m[12] + m[9] * x + m[10] * y + m[11] * z
    return m
end

-- glScalef: m = m · S
function M.scale(m, x, y, z)
    y, z = y or x, z or x
    m[1], m[5], m[9] = m[1] * x, m[5] * x, m[9] * x
    m[2], m[6], m[10] = m[2] * y, m[6] * y, m[10] * y
    m[3], m[7], m[11] = m[3] * z, m[7] * z, m[11] * z
    return m
end

-- Матрица поворота на a градусов вокруг оси (x, y, z), правило правой руки
-- (как glRotatef).
local function rotation(a, x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    x, y, z = x / l, y / l, z / l
    local c, s = cos(rad(a)), sin(rad(a))
    local t = 1 - c
    return {
        t * x * x + c,     t * x * y - s * z, t * x * z + s * y, 0,
        t * x * y + s * z, t * y * y + c,     t * y * z - s * x, 0,
        t * x * z - s * y, t * y * z + s * x, t * z * z + c,     0,
    }
end
M.rotation = rotation

-- glRotatef: m = m · R
function M.rotate(m, a, x, y, z)
    if a == 0 then return m end
    local r = M.mul(m, rotation(a, x, y, z))
    for i = 1, 12 do m[i] = r[i] end
    return m
end

-- Точка через матрицу.
function M.apply(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z + m[4],
           m[5] * x + m[6] * y + m[7] * z + m[8],
           m[9] * x + m[10] * y + m[11] * z + m[12]
end

-- Обратная к матрице «поворот + перенос» (без масштаба).
function M.inverseRigid(m)
    local r = {m[1], m[5], m[9], 0,  m[2], m[6], m[10], 0,  m[3], m[7], m[11], 0}
    local x, y, z = m[4], m[8], m[12]
    r[4] = -(r[1] * x + r[2] * y + r[3] * z)
    r[8] = -(r[5] * x + r[6] * y + r[7] * z)
    r[12] = -(r[9] * x + r[10] * y + r[11] * z)
    return r
end

-- Углы Эйлера движка (градусы) из чистого поворота — то же, что
-- EulerDegreesFromRotationMatrix движка: R = Ry·Rx·Rz.
local function euler(r11, r12, r13, r21, r22, r23, r31, r32, r33)
    local sx = math.max(-1, math.min(1, -r23))
    local cx = sqrt(math.max(0, 1 - sx * sx))
    local x, y, z = math.asin(sx), 0, 0
    if cx > 1e-6 then
        y = math.atan(r13, r33)
        z = math.atan(r21, r22)
    else
        y = math.atan(-r31, r11)
    end
    return deg(x), deg(y), deg(z)
end

-- Углы движка для поворота-матрицы m (масштаба нет).
function M.eulerOf(m)
    return euler(m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11])
end

-- Разложить m в положение, углы и масштаб объекта движка (T·R·S).
-- Отражение (определитель < 0) уходит в знак масштаба по X.
function M.decompose(m)
    local sx = sqrt(m[1] * m[1] + m[5] * m[5] + m[9] * m[9])
    local sy = sqrt(m[2] * m[2] + m[6] * m[6] + m[10] * m[10])
    local sz = sqrt(m[3] * m[3] + m[7] * m[7] + m[11] * m[11])
    local det = m[1] * (m[6] * m[11] - m[7] * m[10]) - m[2] * (m[5] * m[11] - m[7] * m[9])
        + m[3] * (m[5] * m[10] - m[6] * m[9])
    if det < 0 then sx = -sx end
    local ex, ey, ez = euler(m[1] / sx, m[2] / sy, m[3] / sz, m[5] / sx, m[6] / sy, m[7] / sz,
                             m[9] / sx, m[10] / sy, m[11] / sz)
    return m[4], m[8], m[12], ex, ey, ez, sx, sy, sz
end

-- Поставить объекту трансформ из матрицы (относительно его родителя).
function M.applyTo(obj, m)
    local x, y, z, ex, ey, ez, sx, sy, sz = M.decompose(m)
    local t = obj.Transform
    t.Position = Vec3(x, y, z)
    t.Rotation = Vec3(ex, ey, ez)
    t.Scale = Vec3(sx, sy, sz)
end

-- Поворот модели Minecraft (ModelRenderer: сначала Z, потом Y, потом X —
-- glRotatef в этом порядке), радианы.
function M.modelRotation(rx, ry, rz)
    local m = M.identity()
    M.rotate(m, deg(rz), 0, 0, 1)
    M.rotate(m, deg(ry), 0, 1, 0)
    M.rotate(m, deg(rx), 1, 0, 0)
    return m
end

return M
