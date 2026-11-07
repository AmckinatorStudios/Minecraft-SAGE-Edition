-- ---------------------------------------------------------------------------
-- worlds.lua — список миров одиночной игры (экран Select World).
--
-- Мир — слот сохранения движка («w_<папка>»); в метке слота (SaveGame,
-- meta) — то, что показывает список, без чтения самого мира: название,
-- папка, режим и путь к превью. Папка — как у Minecraft 1.7.10
-- (GuiCreateWorld.func_146317_a): запрещённые символы — «_», занятая —
-- дописывается «-», пока не станет свободной. Сохранение прежних версий
-- игры (слот «world») показывается как мир «World».
--
-- Превью — снимок кадра без интерфейса (game.screenshot) при выходе в меню,
-- в каталоге игры: previews/<слот>.png.
-- ---------------------------------------------------------------------------
local Worlds = {}

local PREFIX = "w_"
local LEGACY = "world"

-- Символы, запрещённые в имени папки (ChatAllowedCharacters 1.7.10).
local BAD = {["/"] = true, ["\n"] = true, ["\r"] = true, ["\t"] = true, ["\0"] = true, ["\f"] = true,
             ["`"] = true, ["?"] = true, ["*"] = true, ["\\"] = true, ["<"] = true, [">"] = true,
             ["|"] = true, ['"'] = true, [":"] = true}
local RESERVED = {CON = true, COM = true, PRN = true, AUX = true, CLOCK = true, NUL = true}

local function slotOf(folder)
    -- Имя файла слота: латиница, цифры, «-», «_»; остальное — «_» (SafeSlot
    -- движка сделал бы то же самое, здесь — чтобы знать имя заранее).
    return PREFIX .. folder:gsub("[^%w%-_\128-\255]", "_")
end

local function exists(folder)
    for _, w in ipairs(Worlds.list()) do
        if w.folder == folder or w.slot == slotOf(folder) then return true end
    end
    return false
end

-- Папка нового мира по его имени.
function Worlds.folderFor(name)
    local f = name:gsub(".", function(c) return BAD[c] and "_" or c end)
    if f == "" then f = "World" end
    if RESERVED[f:upper()] then f = "_" .. f .. "_" end
    while exists(f) do f = f .. "-" end
    return f
end

-- Все миры: {slot, name, folder, mode, savedAt, preview}, свежие сверху.
function Worlds.list()
    local out = {}
    for _, s in ipairs(SaveSlots()) do
        local m = type(s.meta) == "table" and s.meta or {}
        if s.name:sub(1, #PREFIX) == PREFIX or s.name == LEGACY then
            out[#out + 1] = {
                slot = s.name,
                name = m.name or (s.name == LEGACY and "World" or s.name:sub(#PREFIX + 1)),
                folder = m.folder or (s.name == LEGACY and "World" or s.name:sub(#PREFIX + 1)),
                mode = "Survival",
                savedAt = s.savedAt or 0,
                preview = m.preview,
                broken = s.broken,
            }
        end
    end
    table.sort(out, function(a, b) return a.savedAt > b.savedAt end)
    return out
end

-- Новый мир: слот и метка (сам мир строится при входе, не здесь).
function Worlds.create(name)
    local folder = Worlds.folderFor(name)
    return {slot = slotOf(folder), name = name, folder = folder, mode = "Survival", new = true}
end

function Worlds.delete(w)
    DeleteSave(w.slot)
end

-- Переименовать: меняется только название (папка остаётся, как у оригинала).
function Worlds.rename(w, name)
    local ok, data = pcall(LoadGame, w.slot)
    if not ok or type(data) ~= "table" then return false end
    w.name = name
    SaveGame(w.slot, data, {version = 1, meta = Worlds.meta(w)})
    return true
end

function Worlds.meta(w)
    return {name = w.name, folder = w.folder, mode = "Survival", preview = w.preview, kind = "world"}
end

-- Дата как у SimpleDateFormat по умолчанию в 1.7.10: «11/7/26 7:53 AM».
function Worlds.dateText(unix)
    if not unix or unix <= 0 then return "" end
    local d = time.local_date(unix)
    local h = d.hour % 12
    if h == 0 then h = 12 end
    return string.format("%d/%d/%02d %d:%02d %s", d.month, d.day, d.year % 100, h, d.minute,
                         d.hour < 12 and "AM" or "PM")
end

return Worlds
