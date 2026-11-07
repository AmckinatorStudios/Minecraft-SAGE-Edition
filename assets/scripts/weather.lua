-- ---------------------------------------------------------------------------
-- weather.lua — дождь, гроза и молнии по правилам Minecraft 1.7.10.
--
-- World.updateWeather: у дождя и грозы — свои счётчики тиков. Счётчик дошёл
-- до нуля — состояние переключается, новый срок случайный: ясно —
-- 12000..180000 тиков, дождь — 12000..24000, гроза — 3600..15600. Сила
-- (0..1) догоняет состояние на 0.01 за тик, между тиками — по доле тика.
-- Гроза в цветах неба весит thunder·rain (getWeightedThunderStrength).
--
-- Молния (EntityLightningBolt): в грозу (сила > 0.9 при дожде > 0.2) каждый
-- загруженный участок раз в 100000 тиков. Пока у вспышки lightningState ≥ 0,
-- lastLightningBolt = 2; он убывает на 1 за тик — это и есть вспышка неба.
-- ---------------------------------------------------------------------------
local Weather = {}

Weather.raining, Weather.thundering = false, false
Weather.rainTime, Weather.thunderTime = 0, 0
Weather.rain, Weather.prevRain = 0, 0
Weather.thunder, Weather.prevThunder = 0, 0
Weather.lastBolt = 0
local bolts = {}

local function rand(n) return math.random(0, n - 1) end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

function Weather.rainStrength(partial)
    return Weather.prevRain + (Weather.rain - Weather.prevRain) * partial
end

function Weather.thunderStrength(partial)
    local t = Weather.prevThunder + (Weather.thunder - Weather.prevThunder) * partial
    return t * Weather.rainStrength(partial)
end

-- Вспышка неба 0..0.45 (getSkyColor: lastLightningBolt − доля тика, ×0.45).
function Weather.flash(partial)
    if Weather.lastBolt <= 0 then return 0 end
    return math.min(1, Weather.lastBolt - partial) * 0.45
end

local function strike()
    bolts[#bolts + 1] = {state = 2, living = rand(3) + 1}
end
Weather.strike = strike

-- Один игровой тик. chunks — сколько участков загружено.
function Weather.tick(chunks)
    if Weather.lastBolt > 0 then Weather.lastBolt = Weather.lastBolt - 1 end

    if Weather.thunderTime <= 0 then
        Weather.thunderTime = Weather.thundering and rand(12000) + 3600 or rand(168000) + 12000
    else
        Weather.thunderTime = Weather.thunderTime - 1
        if Weather.thunderTime <= 0 then Weather.thundering = not Weather.thundering end
    end
    Weather.prevThunder = Weather.thunder
    Weather.thunder = clamp01(Weather.thunder + (Weather.thundering and 0.01 or -0.01))

    if Weather.rainTime <= 0 then
        Weather.rainTime = Weather.raining and rand(12000) + 12000 or rand(168000) + 12000
    else
        Weather.rainTime = Weather.rainTime - 1
        if Weather.rainTime <= 0 then Weather.raining = not Weather.raining end
    end
    Weather.prevRain = Weather.rain
    Weather.rain = clamp01(Weather.rain + (Weather.raining and 0.01 or -0.01))

    -- isThundering / isRaining; по участку — шанс 1/100000 за тик.
    if Weather.thunderStrength(1) > 0.9 and Weather.rainStrength(1) > 0.2 then
        for _ = 1, chunks do
            if rand(100000) == 0 then strike() end
        end
    end

    -- EntityLightningBolt.onUpdate: вспышка мигает 1–3 раза.
    for i = #bolts, 1, -1 do
        local b = bolts[i]
        b.state = b.state - 1
        if b.state < 0 then
            if b.living == 0 then
                table.remove(bolts, i)
                b = nil
            elseif b.state < -rand(10) then
                b.living = b.living - 1
                b.state = 1
            end
        end
        if b and b.state >= 0 then Weather.lastBolt = 2 end
    end
end

-- Сразу поставить погоду (проверка снимками, команда): сила — сразу полная.
function Weather.set(kind)
    Weather.raining = kind == "rain" or kind == "thunder"
    Weather.thundering = kind == "thunder"
    Weather.rain = Weather.raining and 1 or 0
    Weather.thunder = Weather.thundering and 1 or 0
    Weather.prevRain, Weather.prevThunder = Weather.rain, Weather.thunder
    Weather.rainTime = Weather.raining and rand(12000) + 12000 or rand(168000) + 12000
    Weather.thunderTime = Weather.thundering and rand(12000) + 3600 or rand(168000) + 12000
end

function Weather.save()
    return {raining = Weather.raining, thundering = Weather.thundering, rainTime = Weather.rainTime,
            thunderTime = Weather.thunderTime, rain = Weather.rain, thunder = Weather.thunder}
end

function Weather.load(t)
    if type(t) ~= "table" then return end
    Weather.raining, Weather.thundering = t.raining == true, t.thundering == true
    Weather.rainTime, Weather.thunderTime = t.rainTime or 0, t.thunderTime or 0
    Weather.rain, Weather.thunder = t.rain or 0, t.thunder or 0
    Weather.prevRain, Weather.prevThunder = Weather.rain, Weather.thunder
end

return Weather
