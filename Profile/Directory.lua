local _, ns = ...

-- Where things are: trainers, auction houses, repairers, banks, flight
-- masters and inns, and which of each is nearest.
--
-- There are two ways of knowing.
--
-- The player's own visits. Wherever they were standing when a trainer's
-- window, a bank or a flight map opened, there's one of those. These are
-- saved, shared across the account, and trusted first: it's the one they
-- chose to use.
--
-- Questie, when it's installed. Its database lists every NPC in the game,
-- what they do and where they stand. We read it once a session, so places
-- the player has never been can still be found. Nothing of Questie's is
-- copied or saved; without it, the directory fills in as the player goes
-- about their business.

local Directory = {}
ns.Directory = Directory

-- Kinds of place ------------------------------------------------------------------

Directory.AUCTION = "auction"
Directory.REPAIR = "repair"
Directory.BANK = "bank"
Directory.FLIGHT = "flight"
Directory.INN = "inn"
Directory.STABLE = "stable"

-- The professions, in the order they're listed. `name` is what the game
-- calls each in English. `titles` are the fragments that pick its trainers
-- out by their title: "Expert Blacksmith", "Herbalism Trainer" and so on.
Directory.PROFESSIONS = {
    { key = "alchemy", name = "Alchemy", titles = { "alchem" } },
    { key = "blacksmithing", name = "Blacksmithing", titles = { "blacksmith" } },
    { key = "enchanting", name = "Enchanting", titles = { "enchant" } },
    { key = "engineering", name = "Engineering", titles = { "engineer" } },
    { key = "herbalism", name = "Herbalism", titles = { "herbalis" } },
    { key = "leatherworking", name = "Leatherworking", titles = { "leatherwork" } },
    { key = "mining", name = "Mining", titles = { "mining", "miner" } },
    { key = "skinning", name = "Skinning", titles = { "skinn" } },
    { key = "tailoring", name = "Tailoring", titles = { "tailor" } },
    { key = "cooking", name = "Cooking", titles = { "cook" } },
    { key = "firstaid", name = "First Aid", titles = { "first aid", "physician", "surgeon" } },
    { key = "fishing", name = "Fishing", titles = { "fishing", "fisherman" } },
}

-- Titles that mark a trainer of one branch of a profession, who won't
-- teach the profession itself.
local SPECIALIST_TITLES = { "gnomish", "goblin", "dragonscale", "tribal", "elemental" }

-- The classes' English names. Questie words a trainer's title in English
-- ("Warrior Trainer") whatever language the game is in.
local ENGLISH_CLASS_NAMES = {
    DRUID = "Druid",
    HUNTER = "Hunter",
    MAGE = "Mage",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
}

--- The kind for trainers of a profession.
---@param profession table  an entry of Directory.PROFESSIONS
---@return string
function Directory.ProfessionKind(profession)
    return "profession:" .. profession.key
end

--- The kind for trainers of the player's own class.
---@return string
function Directory.ClassTrainerKind()
    local _, class = UnitClass("player")
    return "class:" .. (class or "UNKNOWN")
end

-- What we know --------------------------------------------------------------------

-- Seconds after login before we go looking for Questie, and between tries
-- while its database is still loading.
local QUESTIE_DELAY = 10
local QUESTIE_RETRIES = 6

-- NPCs looked at per frame. Questie knows tens of thousands, and reading
-- them all at once would be felt as a stutter.
local NPCS_PER_FRAME = 400

-- What Questie told us this session: [kind] = list of spots. A spot is
-- { mapID, x, y, name, title }, x and y as fractions of the map.
local fromQuestie = {}

-- Places the player has been: [kind] = { [mapID] = spot }. One per map is
-- enough to find the way back.
local function Visited(kind)
    if type(ns.db.directory) ~= "table" then
        ns.db.directory = {}
    end
    if type(ns.db.directory[kind]) ~= "table" then
        ns.db.directory[kind] = {}
    end
    return ns.db.directory[kind]
end

--- Remembers that there's a place of this kind where the player is
--- standing, run by whoever they're talking to.
---@param kind string
function Directory.NoteHere(kind)
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return
    end

    local x, y = position:GetXY()
    Visited(kind)[mapID] = { mapID = mapID, x = x, y = y, name = UnitName("npc") }
    ns.Publish("PLACES_CHANGED")
end

--- A place of some kind on a given map.
---@param kind string
---@param mapID number
---@return table|nil spot  { mapID, x, y, name, title }
function Directory.On(kind, mapID)
    local visited = Visited(kind)[mapID]
    if visited then
        return visited
    end

    for _, spot in ipairs(fromQuestie[kind] or {}) do
        if spot.mapID == mapID then
            return spot
        end
    end
end

-- How far ---------------------------------------------------------------------------

-- Map positions are fractions of a map, and maps come in all sizes. To
-- compare places on different maps they're turned into the world's own
-- yards, on whichever continent they belong to.
local function WorldPosition(mapID, x, y)
    local continent, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if position then
        local worldX, worldY = position:GetXY()
        return continent, worldX, worldY
    end
end

-- A spot's place in the world never changes, so it's worked out once.
local function Locate(spot)
    if spot.located == nil then
        spot.continent, spot.worldX, spot.worldY = WorldPosition(spot.mapID, spot.x, spot.y)
        spot.located = spot.continent ~= nil
    end
    return spot.located
end

--- The nearest place of a kind to where the player is standing.
---
--- "Nearest" is as the crow flies, and only among places on the player's
--- own continent. If there are none there, or the player is somewhere
--- that can't be measured from (inside a dungeon, say), a known place is
--- still returned, just without a distance.
---@param kind string
---@return table|nil spot   { mapID, x, y, name, title }
---@return number|nil yards
function Directory.Nearest(kind)
    local hereContinent, hereX, hereY
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position then
        hereContinent, hereX, hereY = WorldPosition(mapID, position:GetXY())
    end

    local nearest, nearestSquared, fallback

    local function Consider(spot)
        fallback = fallback or spot
        if hereContinent and Locate(spot) and spot.continent == hereContinent then
            local squared = (spot.worldX - hereX) ^ 2 + (spot.worldY - hereY) ^ 2
            if not nearestSquared or squared < nearestSquared then
                nearest, nearestSquared = spot, squared
            end
        end
    end

    -- Visited places first, so they win a tie and are the fallback.
    for _, spot in pairs(Visited(kind)) do
        Consider(spot)
    end
    for _, spot in ipairs(fromQuestie[kind] or {}) do
        Consider(spot)
    end

    if nearest then
        return nearest, math.sqrt(nearestSquared)
    end
    return fallback, nil
end

--- Whether Questie's database has been read this session.
---@return boolean
function Directory.HasQuestie()
    return next(fromQuestie) ~= nil
end

-- Learning from visits -------------------------------------------------------------

ns.Subscribe("AUCTION_HOUSE_OPENED", function()
    Directory.NoteHere(Directory.AUCTION)
end)

ns.OnEvent("MERCHANT_SHOW", function()
    if CanMerchantRepair() then
        Directory.NoteHere(Directory.REPAIR)
    end
end)

ns.OnEvent("BANKFRAME_OPENED", function()
    Directory.NoteHere(Directory.BANK)
end)

ns.OnEvent("TAXIMAP_OPENED", function()
    Directory.NoteHere(Directory.FLIGHT)
end)

-- A profession trainer says which profession they teach with everything
-- they sell. Class trainers are noted from Training.lua, which is in a
-- position to tell them from weapon masters.
ns.OnEvent("TRAINER_SHOW", function()
    if not IsTradeskillTrainer() or GetNumTrainerServices() == 0 then
        return
    end

    local teaches = GetTrainerServiceSkillLine(1)
    for _, profession in ipairs(Directory.PROFESSIONS) do
        if profession.name == teaches then
            Directory.NoteHere(Directory.ProfessionKind(profession))
            return
        end
    end
end)

-- Reading Questie ----------------------------------------------------------------------

-- Questie's NPC database and its table of zones, once they've loaded.
-- These are Questie's own modules, not an interface it promises to keep,
-- so everything that touches them is prepared for them to be different.
local function QuestieModules()
    local loader = QuestieLoader
    if type(loader) ~= "table" or not loader.ImportModule then
        return nil
    end

    local gotNPCs, npcs = pcall(loader.ImportModule, loader, "QuestieDB")
    local gotZones, zones = pcall(loader.ImportModule, loader, "ZoneDB")
    local usable = gotNPCs
        and gotZones
        and type(npcs) == "table"
        and type(zones) == "table"
        and npcs.NPCPointers
        and npcs.QueryNPCSingle
        and type(npcs.npcFlags) == "table"
        and npcs.npcFlags.TRAINER
        and zones.GetUiMapIdByAreaId

    if usable then
        return npcs, zones
    end
end

local function ContainsAny(text, fragments)
    for _, fragment in ipairs(fragments) do
        if text:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

-- The kinds of place a trainer with this title stands for.
local function TrainerKinds(title, classTitle)
    if classTitle and title:find(classTitle, 1, true) then
        return { Directory.ClassTrainerKind() }
    end

    if ContainsAny(title, SPECIALIST_TITLES) then
        return {}
    end

    for _, profession in ipairs(Directory.PROFESSIONS) do
        if ContainsAny(title, profession.titles) then
            return { Directory.ProfessionKind(profession) }
        end
    end
    return {}
end

-- Goes through Questie's NPCs a few hundred a frame, sorting those who
-- provide a service to the player's side into kinds.
local function ReadQuestie(npcs, zones)
    local flags = npcs.npcFlags

    -- Services that are simply a flag on the NPC.
    local flagKinds = {
        [Directory.AUCTION] = flags.AUCTIONEER,
        [Directory.REPAIR] = flags.REPAIR,
        [Directory.BANK] = flags.BANKER,
        [Directory.FLIGHT] = flags.FLIGHT_MASTER,
        [Directory.INN] = flags.INNKEEPER,
        [Directory.STABLE] = flags.STABLEMASTER,
    }

    local _, class = UnitClass("player")
    local classTitle = ENGLISH_CLASS_NAMES[class]
    classTitle = classTitle and (classTitle:lower() .. " trainer")

    -- Questie marks who an NPC is friendly to with "A", "H" or "AH".
    local side = UnitFactionGroup("player") == "Horde" and "H" or "A"

    -- In ID order, so the same places turn up in the same order every
    -- session.
    local ids = {}
    for npcID in pairs(npcs.NPCPointers) do
        table.insert(ids, npcID)
    end
    table.sort(ids)

    local read = {}
    local found = 0

    local function Consider(npcID)
        local npcFlags = npcs.QueryNPCSingle(npcID, "npcFlags") or 0
        if npcFlags == 0 then
            return
        end

        local title = npcs.QueryNPCSingle(npcID, "subName")
        local kinds = {}

        if bit.band(npcFlags, flags.TRAINER) ~= 0 and title then
            kinds = TrainerKinds(title:lower(), classTitle)
        end
        for kind, flag in pairs(flagKinds) do
            if flag and bit.band(npcFlags, flag) ~= 0 then
                table.insert(kinds, kind)
            end
        end
        if #kinds == 0 then
            return
        end

        local friendlyTo = npcs.QueryNPCSingle(npcID, "friendlyToFaction")
        if friendlyTo and not friendlyTo:find(side, 1, true) then
            return
        end

        -- Spawns are { [areaID] = { { x, y }, ... } }, in hundredths of
        -- the zone's map. Someone who walks a route has every step of it
        -- listed; the first is as good a place to look as any.
        local name = npcs.QueryNPCSingle(npcID, "name")
        for areaID, points in pairs(npcs.QueryNPCSingle(npcID, "spawns") or {}) do
            local mapID = zones:GetUiMapIdByAreaId(areaID)
            local point = points[1]
            if mapID and point and point[1] and point[1] >= 0 then
                for _, kind in ipairs(kinds) do
                    read[kind] = read[kind] or {}
                    table.insert(read[kind], {
                        mapID = mapID,
                        x = point[1] / 100,
                        y = point[2] / 100,
                        name = name,
                        title = title,
                    })
                    found = found + 1
                end
            end
        end
    end

    local index = 0
    local function Step()
        local ok, problem = pcall(function()
            for _ = 1, NPCS_PER_FRAME do
                index = index + 1
                if not ids[index] then
                    break
                end
                Consider(ids[index])
            end
        end)

        if not ok then
            ns.Log("directory: gave up reading Questie (%s)", tostring(problem))
        elseif ids[index] then
            C_Timer.After(0, Step)
        else
            -- Only now, so nobody is shown half a directory.
            fromQuestie = read
            ns.Log("directory: Questie supplied %d places from %d NPCs", found, #ids)
            ns.Publish("PLACES_CHANGED")
        end
    end
    Step()
end

local function LookForQuestie(triesLeft)
    local npcs, zones = QuestieModules()
    if npcs then
        ReadQuestie(npcs, zones)
    elseif QuestieLoader and triesLeft > 0 then
        -- Installed, but still unpacking its database.
        C_Timer.After(QUESTIE_DELAY, function()
            LookForQuestie(triesLeft - 1)
        end)
    end
end

ns.OnEvent("PLAYER_LOGIN", function()
    C_Timer.After(QUESTIE_DELAY, function()
        LookForQuestie(QUESTIE_RETRIES)
    end)
end)
