local _, ns = ...

-- Where the player's class trainers stand, map by map.
--
-- There are two ways of knowing.
--
-- The player's own visits. Wherever they were standing when they opened a
-- class trainer, there's a class trainer. These are saved, shared by every
-- character of the class, and trusted first: it's the trainer they chose.
--
-- Questie, when it's installed. Its database lists every NPC in the game
-- and where each one stands, class trainers among them. We read that once
-- a session, so a city the player has never trained in can still be
-- pinned. Nothing of Questie's is copied or saved; without it, the first
-- visit to a city's trainer is what teaches us.
--
-- One spot is kept per map. Where two peoples' trainers share a city, as
-- the dwarves and gnomes do in Ironforge, it's whichever we came across.

local TrainerSpots = {}
ns.TrainerSpots = TrainerSpots

-- Seconds after login before we go looking for Questie, and between tries
-- while its database is still loading.
local QUESTIE_DELAY = 10
local QUESTIE_RETRIES = 6

-- NPCs looked at per frame. Questie knows tens of thousands, and reading
-- them all at once would be felt as a stutter.
local NPCS_PER_FRAME = 400

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

-- What Questie told us this session: [mapID] = { x, y, name }.
local fromQuestie = {}

-- From the player's visits -------------------------------------------------------------

local function Visited()
    if type(ns.db.trainerSpots) ~= "table" then
        ns.db.trainerSpots = {}
    end

    local _, class = UnitClass("player")
    class = class or "UNKNOWN"
    if type(ns.db.trainerSpots[class]) ~= "table" then
        ns.db.trainerSpots[class] = {}
    end
    return ns.db.trainerSpots[class]
end

--- Remembers that one of the player's class trainers is where they're
--- standing now.
function TrainerSpots.NoteHere()
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position then
        local x, y = position:GetXY()
        Visited()[mapID] = { x = x, y = y }
    end
end

--- Where to find one of the player's class trainers on a map.
---@param mapID number
---@return table|nil spot  { x, y } as fractions of the map, with the
---        trainer's name when Questie supplied it; nil if we don't know
function TrainerSpots.On(mapID)
    return Visited()[mapID] or fromQuestie[mapID]
end

-- From Questie -------------------------------------------------------------------------

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
        and npcs.npcFlags
        and npcs.npcFlags.TRAINER
        and zones.GetUiMapIdByAreaId

    if usable then
        return npcs, zones
    end
end

-- Goes through Questie's NPCs a few hundred a frame, keeping the trainers
-- of the player's class who'll speak to their side.
local function ReadQuestie(npcs, zones)
    local _, class = UnitClass("player")
    local title = ENGLISH_CLASS_NAMES[class]
    if not title then
        return
    end
    title = title:lower() .. " trainer"

    -- Questie marks who an NPC is friendly to with "A", "H" or "AH".
    local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local trainerFlag = npcs.npcFlags.TRAINER

    -- In ID order, so that where a map has several trainers we settle on
    -- the same one every session.
    local ids = {}
    for npcID in pairs(npcs.NPCPointers) do
        table.insert(ids, npcID)
    end
    table.sort(ids)

    local function Consider(npcID)
        local flags = npcs.QueryNPCSingle(npcID, "npcFlags") or 0
        if bit.band(flags, trainerFlag) == 0 then
            return
        end

        local subName = npcs.QueryNPCSingle(npcID, "subName") or ""
        if not subName:lower():find(title, 1, true) then
            return
        end

        local friendlyTo = npcs.QueryNPCSingle(npcID, "friendlyToFaction")
        if friendlyTo and not friendlyTo:find(side, 1, true) then
            return
        end

        -- Spawns are { [areaID] = { { x, y }, ... } }, in hundredths of
        -- the zone's map.
        local name = npcs.QueryNPCSingle(npcID, "name")
        for areaID, points in pairs(npcs.QueryNPCSingle(npcID, "spawns") or {}) do
            local mapID = zones:GetUiMapIdByAreaId(areaID)
            local point = points[1]
            if mapID and not fromQuestie[mapID] and point and point[1] and point[1] >= 0 then
                fromQuestie[mapID] = { x = point[1] / 100, y = point[2] / 100, name = name }
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
            ns.Log("trainers: gave up reading Questie (%s)", tostring(problem))
        elseif ids[index] then
            C_Timer.After(0, Step)
        else
            local maps = 0
            for _ in pairs(fromQuestie) do
                maps = maps + 1
            end
            ns.Log("trainers: Questie knows %s on %d maps", title .. "s", maps)
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
