-- ---------------------------------------------------------------------------
-- genjob.lua — генерация участка в фоновой задаче движка (tasks.run).
--
-- Исполняется в состоянии Lua воркера, а не в игре: здесь свои экземпляры
-- world и gen, мир воркера пуст. Участок строится тем же G.generate, что и
-- на главном потоке (результат тот же — шум и хэш у воркера те же), и
-- отдаётся копией: верхняя секция и массивы секций 0..top (по 4096 чисел).
-- Сам участок у воркера сразу забывается — память не копится.
-- ---------------------------------------------------------------------------
local W = require "world"
local G = require "gen"

local J = {}
local seeded

function J.build(seed, cx, cz)
    if seeded ~= seed then
        G.init(seed)
        seeded = seed
    end
    local c = W.newChunk(cx, cz)
    G.generate(c)
    W.chunks[W.ckey(cx, cz)] = nil
    local secs = {}
    for sy = 0, c.top do secs[sy + 1] = c.sec[sy] end
    return c.top, secs
end

return J
