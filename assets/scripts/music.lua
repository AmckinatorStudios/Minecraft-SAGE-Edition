-- ---------------------------------------------------------------------------
-- music.lua — музыка главного меню, как в Minecraft 1.7 (MusicTicker).
--
-- На титульном экране играет случайный трек меню — один раз, без повтора.
-- Кончился — пауза случайной длины (20…600 тиков, то есть 1…30 с) и
-- следующий случайный трек, не тот же самый подряд. Нажали «Singleplayer» —
-- музыка меню уходит (плавно, за полторы секунды, а не обрывом). Меню паузы
-- (Esc в игре) музыку меню не включает — в Minecraft так же: это пауза
-- игры, а не титульный экран.
--
-- Движок даёт только инструменты (PlayMusic/IsMusicPlaying/FadeOutMusic);
-- плейлист, паузы и правила — здесь, в игре.
-- ---------------------------------------------------------------------------
local Music = {}

local TRACKS = {"assets/music/menu1.ogg", "assets/music/menu2.ogg",
                "assets/music/menu3.ogg", "assets/music/menu4.ogg"}
-- Трек — громкостью 1 (MusicTicker), регулятор «Music» — громкость шины
-- «music» движка, общая — сверху: на нуле музыки не слышно вовсе.
local VOLUME = 1.0
local volume = 1      -- «Music» в настройках, 0..1

function Music.setVolume(v)
    volume = v
    audio.set_bus_volume("music", v)
end
local TICK = 1 / 20
local MIN_DELAY, MAX_DELAY = 20, 600       -- тиков между треками (как у меню 1.7)

local playingMenu = false
local wait = 0.5                            -- первый трек — почти сразу
local last = 0

local function nextTrack()
    local i = math.random(#TRACKS)
    if #TRACKS > 1 and i == last then i = i % #TRACKS + 1 end
    last = i
    return TRACKS[i]
end

-- wantMenu — сейчас титульный экран (а не игра и не пауза).
function Music.update(dt, wantMenu)
    if wantMenu then
        if IsMusicPlaying() then return end
        if playingMenu then
            -- Трек доиграл: новая пауза до следующего.
            playingMenu = false
            wait = (MIN_DELAY + math.random() * (MAX_DELAY - MIN_DELAY)) * TICK
        end
        wait = wait - dt
        if wait <= 0 then
            if volume > 0 then PlayMusic(nextTrack(), VOLUME, false, 0, "music") end
            playingMenu = true
        end
    elseif playingMenu then
        FadeOutMusic(1.5)
        playingMenu = false
        wait = 0.5
    end
end

return Music
