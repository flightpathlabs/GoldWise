local _, ns = ...

-- What class training is going to cost.
--
-- The game won't quote a trainer's prices unless the player is standing in
-- front of one. So we have three places to look, best first.
--
-- If the player has What's Training? installed, we ask it. It keeps track
-- of which skills the player knows and which they've chosen to skip.
--
-- Failing that, there's the price table in Data\Training. It's that same
-- addon's table, brought in with its author's licence, checked against the
-- player's own spellbook. Everyone has this, so the Purse tab is complete
-- from the first login.
--
-- And for a class the table doesn't cover, we learn the honest way:
-- whenever the player opens their class trainer, we note every skill on
-- offer, what it costs and the level it needs. What we know then is only
-- what the trainer window showed. If the player has the "unavailable"
-- filter switched off there, skills above their level aren't listed and
-- we can't see them.
--
-- Two things are remembered from trainer visits. Prices are kept per
-- class, so an alt of the same class starts out knowing them. Which
-- skills are still to be bought is kept per character, because that's the
-- part that differs: a skill only counts against a character once we know
-- they don't have it.

local Training = {}
ns.Training = Training

-- Trainer updates come in bursts while the list fills in.
local SETTLE_DELAY = 0.3

-- After a purchase the list can go on showing the skill for a moment.
-- For this many seconds, don't take its word that the skill is unlearned.
local PURCHASE_GRACE = 10

local scanPending = false

-- Skills bought this session, and when: [key] = GetTime().
local boughtAt = {}

-- What we've learned ----------------------------------------------------------

-- Prices for this character's class: [key] = { cost, level }.
local function ClassBook()
    if type(ns.db.training) ~= "table" then
        ns.db.training = {}
    end

    local _, class = UnitClass("player")
    class = class or "UNKNOWN"
    if type(ns.db.training[class]) ~= "table" then
        ns.db.training[class] = {}
    end
    return ns.db.training[class]
end

-- The skills this character is known not to have yet: [key] = true.
local function Unlearned()
    if type(ns.db.unlearned) ~= "table" then
        ns.db.unlearned = {}
    end

    local character = ns.Characters.CurrentKey()
    if type(ns.db.unlearned[character]) ~= "table" then
        ns.db.unlearned[character] = {}
    end
    return ns.db.unlearned[character]
end

-- "Raptor Strike" comes in several ranks, each sold separately.
local function SkillKey(name, rank)
    return rank and rank ~= "" and (name .. " (" .. rank .. ")") or name
end

-- A skill that needs a higher level than this character has can't have
-- been learned yet, whichever character's trainer visit told us about it.
-- Noting that now means it's still on the list after they level past it.
local function NoteWhatLiesAhead()
    local level = UnitLevel("player")
    local unlearned = Unlearned()

    for key, skill in pairs(ClassBook()) do
        if skill.level > level then
            unlearned[key] = true
        end
    end
end

-- Reading the trainer window --------------------------------------------------

local function IsClassTrainer()
    -- Pet trainers charge training points rather than money, and
    -- profession trainers are Directory.lua's business, not ours.
    return C_Trainer.GetTrainerType() == Enum.TrainerType.General and not IsTradeskillTrainer()
end

-- Defined further down, with the rest of what we know about where
-- trainers are.
local NoteTrainerSpot

local function Scan()
    scanPending = false
    if not IsClassTrainer() then
        return
    end

    local book = ClassBook()
    local unlearned = Unlearned()
    local now = GetTime()

    -- The names of everything on offer, to tell what kind of trainer this is.
    local offered = {}

    -- One row is a "step" marker rather than a skill. Blizzard's own list
    -- skips it the same way.
    local stepRow = GetTrainerServiceStepIndex and GetTrainerServiceStepIndex()

    for index = 1, GetNumTrainerServices() do
        if index ~= stepRow then
            local name, status, _, requiredLevel, rank = GetTrainerServiceInfo(index)
            local cost = GetTrainerServiceCost(index)

            if name then
                offered[name] = true

                local key = SkillKey(name, rank)
                local justBought = boughtAt[key] and now - boughtAt[key] < PURCHASE_GRACE

                if status == "used" then
                    unlearned[key] = nil
                elseif cost and cost > 0 then
                    book[key] = { cost = cost, level = requiredLevel or 0 }
                    if not justBought then
                        unlearned[key] = true
                    end
                end
            end
        end
    end

    NoteTrainerSpot(offered)
    ns.Publish("PURSE_CHANGED")
end

local function ScanSoon()
    if not scanPending then
        scanPending = true
        C_Timer.After(SETTLE_DELAY, Scan)
    end
end

-- The trainer window normally hides skills the player already knows, so a
-- skill that's just been bought simply drops off the list. The purchase
-- itself is the one moment we can see it go.
local function OnBuy(index)
    local name, status, _, _, rank = GetTrainerServiceInfo(index)
    local cost = GetTrainerServiceCost(index)

    -- The game will refuse a skill that isn't available or can't be paid
    -- for. Should we be wrong anyway, the next look at the list puts the
    -- skill back.
    if name and status == "available" and cost and GetMoney() >= cost then
        local key = SkillKey(name, rank)
        boughtAt[key] = GetTime()
        Unlearned()[key] = nil
        ns.Publish("PURSE_CHANGED")
    end
end

-- Asking What's Training? -----------------------------------------------------

-- Everything goes through that addon's public interface, WT_API. Nothing
-- of its data is copied into Goldwise.

-- Its names for the states of a skill that is still to be paid for:
-- trainable now, waiting on an earlier rank, or waiting on a level.
local OWED_STATES = { "AVAILABLE", "MISSINGREQS", "NEXTLEVEL", "NOTLEVEL" }

-- The addon's interface, once it has finished working out what the player
-- knows. Nil if it isn't installed or isn't ready yet.
local function WhatsTraining()
    local api = WT_API
    if type(api) ~= "table" or not api.IsReady or not api.GetSpells then
        return nil
    end

    -- Asked on every redraw of the Purse tab, and not ours to trust.
    local ok, ready = pcall(api.IsReady)
    if ok and ready then
        return api
    end
end

-- The skills still to be bought, as { level, cost }, or nil if What's
-- Training? can't tell us.
local function SkillsFromWhatsTraining()
    local api = WhatsTraining()
    if not api then
        return nil
    end

    -- Another addon's code is outside our control. If it stumbles, or has
    -- nothing for this class, carry on with what we've learned ourselves.
    local ok, spells = pcall(api.GetSpells)
    if not ok or type(spells) ~= "table" or #spells == 0 then
        return nil
    end

    local owed = {}
    for _, name in ipairs(OWED_STATES) do
        local state = api.Status and api.Status[name]
        if state then
            owed[state] = true
        end
    end

    local skills = {}
    for _, spell in ipairs(spells) do
        -- Quest rewards are free, and tomes are bought from a vendor
        -- rather than trained.
        local trained = not spell.quest and not spell.isItem
        -- Its "cost" already has a reputation discount taken off. We want
        -- the price before that, and work the discounts out ourselves.
        local cost = spell.baseCost or spell.cost or 0
        if owed[spell.status] and trained and cost > 0 then
            table.insert(skills, { level = spell.level or 0, cost = cost })
        end
    end
    return skills
end

-- The price table -------------------------------------------------------------

-- The answer from the table, kept until the player's spells change. Working
-- it out means asking the spellbook about every skill their class has.
local fromTable
local fromTableStale = true

-- [spell ID] = the run of ranks it belongs to, for the ranks that replace
-- one another. Built the first time it's needed.
local rankGroups

local function ClassTable()
    local _, class = UnitClass("player")
    return class and ns.TrainingData[class]
end

local function InSpellbook(spellID)
    local bank = Enum.SpellBookSpellBank.Player
    return C_SpellBook.IsSpellInSpellBook(spellID, bank, false)
        or C_SpellBook.IsSpellKnown(spellID, bank)
end

local function HasLearned(spellID)
    if InSpellbook(spellID) then
        return true
    end

    -- Some ranks take the place of the one before. If a later rank is in
    -- the spellbook, this one was learned on the way to it.
    local reached = false
    for _, rank in ipairs(rankGroups[spellID] or {}) do
        if reached and InSpellbook(rank) then
            return true
        end
        reached = reached or rank == spellID
    end
    return false
end

-- The skills still to be bought, as { level, cost }, or nil if the table
-- has nothing for this class.
local function SkillsFromTable()
    local data = ClassTable()
    if not data then
        return nil
    end
    if not fromTableStale then
        return fromTable
    end

    if not rankGroups then
        rankGroups = {}
        for _, group in ipairs(data.replaces) do
            for _, spellID in ipairs(group) do
                rankGroups[spellID] = group
            end
        end
    end

    local faction = UnitFactionGroup("player")
    local _, _, race = UnitRace("player")
    local skills = {}

    for _, skill in ipairs(data.skills) do
        local spellID, level, cost = skill[1], skill[2], skill[3]

        local forUs = (not skill.faction or skill.faction == faction)
            and (not skill.race or skill.race == race)
        -- A skill that builds on a talent only matters to those who took it.
        local open = not skill.talent or HasLearned(skill.talent)

        if forUs and open and not HasLearned(spellID) then
            table.insert(skills, { level = level, cost = cost })
        end
    end

    fromTable = skills
    fromTableStale = false
    return skills
end

local function OnSpellsChanged()
    fromTableStale = true
    ns.Publish("PURSE_CHANGED")
end

-- The same list, from what trainer visits have taught us.
local function SkillsFromTrainerVisits()
    local unlearned = Unlearned()
    local skills = {}

    for key, skill in pairs(ClassBook()) do
        if unlearned[key] then
            table.insert(skills, skill)
        end
    end
    return skills
end

-- Reading it back -------------------------------------------------------------

--- Whether any training prices are known for this character's class.
---@return boolean
function Training.HasPrices()
    return WhatsTraining() ~= nil or ClassTable() ~= nil or next(ClassBook()) ~= nil
end

--- Class training the player hasn't bought yet, added up by level.
---@param playerLevel number
---@return table levels  list of { level, cost, skills }, lowest level first.
---        An entry at or below playerLevel is training they could buy now.
function Training.Outstanding(playerLevel)
    local byLevel = {}

    local skills = SkillsFromWhatsTraining() or SkillsFromTable() or SkillsFromTrainerVisits()

    for _, skill in ipairs(skills) do
        -- Everything affordable now is one lump: "waiting at your trainer".
        local level = math.max(skill.level, playerLevel)
        local entry = byLevel[level]
        if not entry then
            entry = { level = level, cost = 0, skills = 0 }
            byLevel[level] = entry
        end
        entry.cost = entry.cost + skill.cost
        entry.skills = entry.skills + 1
    end

    local levels = {}
    for _, entry in pairs(byLevel) do
        table.insert(levels, entry)
    end
    table.sort(levels, function(a, b)
        return a.level < b.level
    end)
    return levels
end

-- Where to train --------------------------------------------------------------

-- A trainer charges less to those their people think well of. On Forever
-- that's nothing off at Friendly and a tenth off at Honored, as measured
-- by the author of What's Training?. Revered and Exalted haven't been
-- checked, and are taken to earn the same.
local DISCOUNT_STANDING = 6 -- Honored
local REPUTATION_DISCOUNT = 0.10

Training.REPUTATION_DISCOUNT = REPUTATION_DISCOUNT

-- The map each reputation's trainers are found on, by faction ID. Two can
-- share a city: the gnomes teach in Ironforge, the Darkspear in Orgrimmar.
local TRAINER_MAPS = {
    [72] = 1453, -- Stormwind
    [47] = 1455, -- Ironforge
    [54] = 1455, -- Gnomeregan Exiles, in Ironforge
    [69] = 1457, -- Darnassus
    [76] = 1454, -- Orgrimmar
    [530] = 1454, -- Darkspear Trolls, in Orgrimmar
    [81] = 1456, -- Thunder Bluff
    [68] = 1458, -- Undercity
    [21] = 1434, -- Booty Bay, in Stranglethorn Vale
    [609] = 1450, -- Cenarion Circle, in Moonglade
}

local function StandingLabel(standing)
    return _G["FACTION_STANDING_LABEL" .. standing] or ""
end

-- Called with the names of the skills a trainer has on offer. If they're
-- this class's, the trainer's whereabouts are worth remembering.
NoteTrainerSpot = function(offered)
    -- Weapon masters and their like open the same window. Only someone
    -- selling this class's own skills marks the spot.
    local data = ClassTable()
    if data then
        local teachesClass = false
        for _, skill in ipairs(data.skills) do
            local name = C_Spell.GetSpellName(skill[1])
            if name and offered[name] then
                teachesClass = true
                break
            end
        end
        if not teachesClass then
            return
        end
    end

    ns.Directory.NoteHere(ns.Directory.ClassTrainerKind())
end

--- Whose trainers teach this character's class, where they are, and what
--- the player's standing with each is worth. Prices everywhere else in
--- this file are before any of these discounts.
---
--- Capital cities are always listed. Out-of-the-way trainers only when
--- they'd actually be cheaper.
---@return table places  list, cheapest first, of:
---   city              the place's name, in the player's language
---   faction           whose trainers they are, where that isn't the city's
---                     own people (the gnomes in Ironforge, say)
---   standing          the player's standing with them, as the game words it
---   discount          as a fraction: 0.1 is 10% off
---   capital           true for a capital city's trainers
---   shortBy           reputation still needed, for someone one standing
---                     short of a discount
---   discountStanding  the name of the standing that earns the discount
---   mapID             the map they're on, if we know it
---   spot              a trainer on that map, as Directory.On gives it,
---                     if we know of one
--- Empty when we don't know this class's trainers.
function Training.Places()
    local data = ClassTable()
    local factions = data and data.trainers[UnitFactionGroup("player")]
    local places = {}

    for _, factionID in ipairs(factions or {}) do
        -- The game has nothing to say about a faction the character has
        -- yet to meet.
        local faction = C_Reputation.GetFactionDataByID(factionID)
        if faction then
            local discount = faction.reaction >= DISCOUNT_STANDING and REPUTATION_DISCOUNT or 0
            local nearly = faction.reaction == DISCOUNT_STANDING - 1

            local mapID = TRAINER_MAPS[factionID]
            local map = mapID and C_Map.GetMapInfo(mapID)
            local city = map and map.name or faction.name

            if data.capitals[factionID] or discount > 0 then
                table.insert(places, {
                    city = city,
                    faction = city ~= faction.name and faction.name or nil,
                    standing = StandingLabel(faction.reaction),
                    discount = discount,
                    capital = data.capitals[factionID] == true,
                    shortBy = nearly and (faction.nextReactionThreshold - faction.currentStanding)
                        or nil,
                    discountStanding = StandingLabel(DISCOUNT_STANDING),
                    mapID = map and mapID or nil,
                    spot = map and ns.Directory.On(ns.Directory.ClassTrainerKind(), mapID) or nil,
                })
            end
        end
    end

    table.sort(places, function(a, b)
        if a.discount ~= b.discount then
            return a.discount > b.discount
        elseif a.capital ~= b.capital then
            return a.capital
        elseif a.city ~= b.city then
            return a.city < b.city
        end
        -- A city's own trainers before the guests who teach there.
        return a.faction == nil and b.faction ~= nil
    end)
    return places
end

ns.OnEvent("TRAINER_SHOW", ScanSoon)
ns.OnEvent("TRAINER_UPDATE", ScanSoon)

-- Reputation earned may have just bought a discount.
ns.OnEvent("UPDATE_FACTION", function()
    ns.Publish("PURSE_CHANGED")
end)

-- Learning a skill, or taking a talent that opens some up, changes what's
-- owed. The client doesn't have all of these events on every version; the
-- ones it lacks are quietly skipped.
ns.OnEvent("SPELLS_CHANGED", OnSpellsChanged)
ns.OnEvent("LEARNED_SPELL_IN_SKILL_LINE", OnSpellsChanged)
ns.OnEvent("CHARACTER_POINTS_CHANGED", OnSpellsChanged)

ns.OnEvent("PLAYER_LOGIN", function()
    NoteWhatLiesAhead()

    -- Every class's prices were loaded, and the player is only one of them.
    local _, class = UnitClass("player")
    if class then
        ns.TrainingData = { [class] = ns.TrainingData[class] }
    end

    -- What's Training? says when its picture of the player changes: once
    -- it has finished loading, and again whenever they train or level.
    local api = WT_API
    if type(api) == "table" and api.RegisterCallback then
        for _, event in ipairs({ "Ready", "SpellsChanged", "LevelChanged" }) do
            pcall(api.RegisterCallback, Training, event, function()
                ns.Publish("PURSE_CHANGED")
            end)
        end
    end
end)

if BuyTrainerService then
    hooksecurefunc("BuyTrainerService", OnBuy)
end
