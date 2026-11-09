-- ---------------------------------------------------------------------------
-- iconjob.lua — иконка предмета 128×128 из пикселей картинок: чистая функция
-- для фонового потока движка (tasks.run) и для главного потока, если задач
-- нет. Пиксели — массивы 0xRRGGBBAA (texture.read) по строкам снизу вверх;
-- результат — такой же массив S×S для texture.write.
--
-- Прежде иконка считалась попиксельно на главном потоке через get/set
-- холста — 16 тысяч вызовов и цветов-объектов на иконку, сотни миллисекунд:
-- меню и первые секунды в мире дёргались, пока шёл лист иконок.
-- ---------------------------------------------------------------------------
local J = {}

local floor, min, max = math.floor, math.min, math.max

local function byte(v)
    v = floor(v + 0.5)
    if v < 0 then return 0 elseif v > 255 then return 255 end
    return v
end

local function pack(r, g, b, a) return (r << 24) | (g << 16) | (b << 8) | a end

-- Пиксель (x, y) картинки src = {px, w, h}; за краем — прозрачный.
local function at(src, x, y)
    if x < 0 or y < 0 or x >= src.w or y >= src.h then return 0 end
    return src.px[y * src.w + x + 1] or 0
end

-- Плоская иконка: картинка во всю клетку, кадр frame полосы (0 — верхний),
-- tint — множители цвета, почти прозрачное (< 0.1) — пусто.
function J.flat(S, src, tint, frame)
    local out = {}
    local w = src.w
    local sy0 = src.h - w * ((frame or 0) + 1)
    local i = 1
    for py = 0, S - 1 do
        for px = 0, S - 1 do
            local c = at(src, px * w // S, sy0 + py * w // S)
            local r, g, b, a = (c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255, c & 255
            if a < 25.5 then
                out[i] = 0
            else
                if tint then r, g, b = byte(r * tint[1]), byte(g * tint[2]), byte(b * tint[3]) end
                out[i] = pack(r, g, b, a)
            end
            i = i + 1
        end
    end
    return out
end

-- Выборка грани: u, v — доли 0..1 (v снизу вверх), кадр — верхний квадрат.
local function sample(src, tint, u, v)
    local w = src.w
    local x = min(w - 1, floor(u * w))
    local y = min(w - 1, floor(v * w))
    local c = at(src, x, src.h - w + y)
    local r, g, b, a = ((c >> 24) & 255) / 255, ((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255
    if tint then return r * tint[1], g * tint[2], b * tint[3], a end
    return r, g, b, a
end

-- Изометрическая иконка куба: верх, правый бок (+X, тень 0.6) и левый (+Z,
-- 0.8), как в мире. faces = {top = {src, tint}, right = …, left = …};
-- box — коробка предмета {x0, y0, z0, x1, y1, z1} (люк — плита).
function J.cube(S, faces, box)
    local out = {}
    local by0, by1 = box and box[2] or 0, box and box[5] or 1
    local s = S * 0.47
    local k = 0.866 * s
    local cxp, base = S / 2, S * 0.04
    local i = 1
    for py = 0, S - 1 do
        for px = 0, S - 1 do
            local fx, fy = px + 0.5, py + 0.5
            local a = (fx - cxp) / k
            local r, g, b, al, shade = 0, 0, 0, 0, 1
            local bsum = 2 - (fy + (1 - by1) * s - base - s) / (0.5 * s)
            local X, Z = (a + bsum) / 2, (bsum - a) / 2
            if X >= 0 and X <= 1 and Z >= 0 and Z <= 1 then
                r, g, b, al = sample(faces.top[1], faces.top[2], X, 1 - Z)
            else
                local Y, u, face
                if a >= 0 then
                    local z = 1 - a
                    Y = (fy - base - (1 - z) * 0.5 * s) / s
                    u, face, shade = 1 - z, faces.right, 0.6
                else
                    local x = a + 1
                    Y = (fy - base - (1 - x) * 0.5 * s) / s
                    u, face, shade = x, faces.left, 0.8
                end
                if Y >= by0 and Y <= by1 and u >= 0 and u <= 1 then
                    r, g, b, al = sample(face[1], face[2], u, Y)
                end
            end
            if al > 0.5 then
                out[i] = pack(byte(r * shade * 255), byte(g * shade * 255), byte(b * shade * 255), 255)
            else
                out[i] = 0
            end
            i = i + 1
        end
    end
    return out
end

-- Задача целиком: job = {kind = "flat"|"cube", ...} (см. atlas.lua).
function J.build(S, job)
    if job.kind == "flat" then return J.flat(S, job.src, job.tint, job.frame) end
    return J.cube(S, job.faces, job.box)
end

return J
