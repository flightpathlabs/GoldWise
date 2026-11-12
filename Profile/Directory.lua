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
-- `graded` marks the crafts, whose trainers each teach only one stretch of
-- the profession (see the grades below). Anyone who teaches gathering,
-- cooking, first aid or fishing teaches all of it.
Directory.PROFESSIONS = {
    { key = "alchemy", name = "Alchemy", titles = { "alchem" }, graded = true },
    { key = "blacksmithing", name = "Blacksmithing", titles = { "blacksmith" }, graded = true },
    { key = "enchanting", name = "Enchanting", titles = { "enchant" }, graded = true },
    { key = "engineering", name = "Engineering", titles = { "engineer" }, graded = true },
    { key = "herbalism", name = "Herbalism", titles = { "herbalis" } },
    { key = "leatherworking", name = "Leatherworking", titles = { "leatherwork" }, graded = true },
    { key = "mining", name = "Mining", titles = { "mining", "miner" } },
    { key = "skinning", name = "Skinning", titles = { "skinn" } },
    { key = "tailoring", name = "Tailoring", titles = { "tailor" }, graded = true },
    { key = "cooking", name = "Cooking", titles = { "cook" } },
    { key = "firstaid", name = "First Aid", titles = { "first aid", "physician", "surgeon" } },
    { key = "fishing", name = "Fishing", titles = { "fishing", "fisherman" } },
}

-- Titles that mark a trainer of one branch of a profession, who won't
-- teach the profession itself.
local SPECIALIST_TITLES = { "gnomish", "goblin", "dragonscale", "tribal", "elemental" }

-- A craft's trainers come in grades, and the grade is in the title, one
-- step ahead of what's taught: a Journeyman Tailor takes a beginner to 75,
-- and it's an Expert Tailor who makes a journeyman of them. Each has
-- something to teach from the skill given here until the next grade takes
-- over. These are the figures a Forever guide gives for tailoring; the
-- other crafts are taken to work the same way.
local GRADES = {
    { word = "journeyman", needs = "a Journeyman", from = 0 },
    { word = "expert", needs = "an Expert", from = 50 },
    { word = "artisan", needs = "an Artisan", from = 125 },
    { word = "master", needs = "a Master", from = 200 },
}

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

-- What the game writes under the name of whoever the player is talking
-- to: "Expert Tailor". Nil if they have no title.
local function TitleOfNPC()
    if not C_TooltipInfo or not C_TooltipInfo.GetUnit then
        return nil
    end

    local ok, tooltip = pcall(C_TooltipInfo.GetUnit, "npc")
    local line = ok and tooltip and tooltip.lines and tooltip.lines[2]
    local text = line and line.leftText

    -- Someone without a title has their level on that line instead.
    if text and text ~= "" and not text:find("%d") then
        return text
    end
end

--- Remembers that there's a place of this kind where the player is
--- standing, run by whoever they're talking to.
---@param kind string
---@param eachPerson boolean|nil  true to remember everyone of this kind on
---        a map separately, with their title. A city can have three
---        tailors, and they aren't interchangeable.
function Directory.NoteHere(kind, eachPerson)
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return
    end

    local visited = Visited(kind)
    local name = UnitName("npc")
    local key = mapID

    if eachPerson and name then
        key = mapID .. ":" .. name
        -- Before they were told apart, whoever was visited last had the
        -- map to themselves.
        if visited[mapID] and visited[mapID].name == name then
            visited[mapID] = nil
        end
    end

    local x, y = position:GetXY()
    visited[key] = {
        mapID = mapID,
        x = x,
        y = y,
        name = name,
        title = eachPerson and TitleOfNPC() or nil,
        -- Visits are shared by the whole account, and a Horde alt's
        -- auctioneer is no use to an Alliance character.
        side = UnitFactionGroup("player"),
    }
    ns.Publish("PLACES_CHANGED")
end

-- Whether a place the account has visited is one this character can use.
-- Places noted before sides were recorded are given the benefit of the
-- doubt.
local function IsForUs(spot)
    return spot.side == nil or spot.side == UnitFactionGroup("player")
end

--- A place of some kind on a given map.
---@param kind string
---@param mapID number
---@param suits (fun(spot: table): boolean)|nil  only places this accepts
---@return table|nil spot  { mapID, x, y, name, title }
function Directory.On(kind, mapID, suits)
    local function Fits(spot)
        return spot.mapID == mapID and (not suits or suits(spot))
    end

    for _, spot in pairs(Visited(kind)) do
        if IsForUs(spot) and Fits(spot) then
            return spot
        end
    end
    for _, spot in ipairs(fromQuestie[kind] or {}) do
        if Fits(spot) then
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

-- A spot's place in the world never changes, so it's worked out once a
-- session and kept here: [spot] = { continent, x, y }, or false if the
-- game couldn't say. Kept apart from the spots themselves, some of which
-- are saved data that a passing failure shouldn't be written into.
local located = setmetatable({}, { __mode = "k" })

local function Locate(spot)
    if located[spot] == nil then
        local continent, worldX, worldY = WorldPosition(spot.mapID, spot.x, spot.y)
        located[spot] = continent and { continent, worldX, worldY } or false
    end
    return located[spot]
end

--- The nearest place of a kind to where the player is standing.
---
--- "Nearest" is as the crow flies, and only among places on the player's
--- own continent. If there are none there, or the player is somewhere
--- that can't be measured from (inside a dungeon, say), a known place is
--- still returned, just without a distance.
---@param kind string
---@param suits (fun(spot: table): boolean)|nil  only places this accepts
---@return table|nil spot   { mapID, x, y, name, title }
---@return number|nil yards
function Directory.Nearest(kind, suits)
    local hereContinent, hereX, hereY
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position then
        hereContinent, hereX, hereY = WorldPosition(mapID, position:GetXY())
    end

    local nearest, nearestSquared, fallback

    local function Consider(spot)
        if suits and not suits(spot) then
            return
        end

        fallback = fallback or spot
        local world = hereContinent and Locate(spot)
        if world and world[1] == hereContinent then
            local squared = (world[2] - hereX) ^ 2 + (world[3] - hereY) ^ 2
            if not nearestSquared or squared < nearestSquared then
                nearest, nearestSquared = spot, squared
            end
        end
    end

    -- Visited places first, so they win a tie and are the fallback.
    for _, spot in pairs(Visited(kind)) do
        if IsForUs(spot) then
            Consider(spot)
        end
    end
    for _, spot in ipairs(fromQuestie[kind] or {}) do
        Consider(spot)
    end

    if nearest then
        return nearest, math.sqrt(nearestSquared)
    end
    return fallback, nil
end

--- How many profession trainers the account has visited, for "/gw check".
---@return number
function Directory.VisitedTrainers()
    local count = 0
    for kind, spots in pairs(type(ns.db.directory) == "table" and ns.db.directory or {}) do
        if kind:find("profession:", 1, true) == 1 then
            for _ in pairs(spots) do
                count = count + 1
            end
        end
    end
    return count
end

--- Whether Questie's database has been read this session.
---@return boolean
function Directory.HasQuestie()
    return next(fromQuestie) ~= nil
end

-- The right trainer -----------------------------------------------------------------

-- A trainer's title. A visit made before titles were noted has none of
-- its own, but Questie may know the same person.
local function TitleOf(kind, spot)
    if spot.title then
        return spot.title
    end
    for _, known in ipairs(fromQuestie[kind] or {}) do
        if known.name == spot.name then
            return known.title
        end
    end
end

-- Which grade a title belongs to, as a place in GRADES. Nil for a title
-- with no grade in it, and for no title at all.
local function GradeOf(title)
    title = title and title:lower()
    for index, grade in ipairs(GRADES) do
        if title and title:find(grade.word, 1, true) then
            return index
        end
    end
end

-- The grade of trainer someone with this much skill has to see next.
local function GradeFor(skill)
    local wanted = 1
    for index, grade in ipairs(GRADES) do
        if skill >= grade.from then
            wanted = index
        end
    end
    return wanted
end

-- A test for trainers worth sending this player to, and the grade it
-- looks for. Nil for a profession anyone can teach all of.
local function RightTrainer(profession, skill)
    if not profession.graded then
        return nil
    end

    local kind = Directory.ProfessionKind(profession)
    local wanted = GradeFor(skill or 0)

    local function Suits(spot)
        -- Someone whose grade we can't tell is better shown than hidden.
        local grade = GradeOf(TitleOf(kind, spot))
        return grade == nil or grade == wanted
    end
    return Suits, wanted
end

--- The nearest trainer of a profession who has something to teach a
--- player of this skill. The trainer round the corner is no use to a
--- tailor who has outgrown them.
---@param profession table   an entry of Directory.PROFESSIONS
---@param skill number|nil   the player's skill; nil if they've yet to
---        take the profession up
---@return table|nil spot    { mapID, x, y, name, title }
---@return number|nil yards
---@return string|nil needs  when trainers are known but none is of the
---        grade wanted: that grade, worded to follow "you need", as in
---        "an Artisan"
function Directory.NearestTrainer(profession, skill)
    local kind = Directory.ProfessionKind(profession)
    local suits, wanted = RightTrainer(profession, skill)

    local spot, yards = Directory.Nearest(kind, suits)
    if spot or not suits then
        return spot, yards
    end

    if Directory.Nearest(kind) then
        return nil, nil, GRADES[wanted].needs
    end
end

--- A trainer on a given map who has something to teach a player of this
--- skill.
---@param profession table  an entry of Directory.PROFESSIONS
---@param skill number|nil
---@param mapID number
---@return table|nil spot   { mapID, x, y, name, title }
function Directory.TrainerOn(profession, skill, mapID)
    local suits = RightTrainer(profession, skill)
    return Directory.On(Directory.ProfessionKind(profession), mapID, suits)
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
            Directory.NoteHere(Directory.ProfessionKind(profession), true)
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

-- Questie's modules, kept once found, for looking up the odd NPC later.
local questieNPCs, questieZones

-- NPCs already looked up: [npcID] = spot, or false if Questie can't say.
local foundNPCs = {}

--- Where one particular NPC stands, if Questie is there to say.
---@param npcID number
---@return table|nil spot  { mapID, x, y, name }
function Directory.FindNPC(npcID)
    if not questieNPCs then
        return nil
    end

    if foundNPCs[npcID] == nil then
        local ok, spot = pcall(function()
            local name = questieNPCs.QueryNPCSingle(npcID, "name")
            for areaID, points in pairs(questieNPCs.QueryNPCSingle(npcID, "spawns") or {}) do
                local mapID = questieZones:GetUiMapIdByAreaId(areaID)
                local point = points[1]
                if mapID and point and point[1] and point[1] >= 0 then
                    return { mapID = mapID, x = point[1] / 100, y = point[2] / 100, name = name }
                end
            end
        end)
        foundNPCs[npcID] = ok and spot or false
    end
    return foundNPCs[npcID] or nil
end

local function LookForQuestie(triesLeft)
    local npcs, zones = QuestieModules()
    if npcs then
        questieNPCs, questieZones = npcs, zones
        ReadQuestie(npcs, zones)
    elseif QuestieLoader and triesLeft > 0 then
        -- Installed, but still unpacking its database.
        C_Timer.After(QUESTIE_DELAY, function()
            LookForQuestie(triesLeft - 1)
        end)
    end
end

ns.OnEvent("PLAYER_LOGIN", function()
    -- An earlier version kept its working-out inside the saved places.
    for _, places in pairs(type(ns.db.directory) == "table" and ns.db.directory or {}) do
        for _, spot in pairs(places) do
            spot.located, spot.continent, spot.worldX, spot.worldY = nil, nil, nil, nil
        end
    end

    C_Timer.After(QUESTIE_DELAY, function()
        LookForQuestie(QUESTIE_RETRIES)
    end)
end)
