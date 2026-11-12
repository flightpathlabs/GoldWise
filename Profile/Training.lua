local _, ns = ...

-- What class training is going to cost.
--
-- The game won't quote a trainer's prices unless the player is standing in
-- front of one. There are two ways round that.
--
-- If the player has What's Training? installed, we ask it. That addon
-- carries a full table of Forever's class skills and prices and keeps
-- track of which ones the player knows, so the answer is complete from
-- the first login.
--
-- Otherwise we learn the honest way: whenever the player opens their
-- class trainer, we note every skill on offer, what it costs and the
-- level it needs. That is enough to say "level 30 will cost you 3g 40s"
-- well before level 30. What we know then is only what the trainer window
-- showed. If the player has the "unavailable" filter switched off there,
-- skills above their level aren't listed and we can't see them.
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

-- What we've learned ---------------------------------------------------------------

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

-- Reading the trainer window ---------------------------------------------------------

local function IsClassTrainer()
    -- Pet trainers charge training points rather than money, and
    -- profession trainers are a different question for another day.
    return C_Trainer.GetTrainerType() == Enum.TrainerType.General and not IsTradeskillTrainer()
end

local function Scan()
    scanPending = false
    if not IsClassTrainer() then
        return
    end

    local book = ClassBook()
    local unlearned = Unlearned()
    local now = GetTime()

    -- One row is a "step" marker rather than a skill. Blizzard's own list
    -- skips it the same way.
    local stepRow = GetTrainerServiceStepIndex and GetTrainerServiceStepIndex()

    for index = 1, GetNumTrainerServices() do
        if index ~= stepRow then
            local name, status, _, requiredLevel, rank = GetTrainerServiceInfo(index)
            local cost = GetTrainerServiceCost(index)

            if name then
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

-- Asking What's Training? -----------------------------------------------------------

-- Everything goes through that addon's public interface, WT_API. Nothing
-- of its data is copied into Goldwise.

-- Its names for the states of a skill that is still to be paid for:
-- trainable now, waiting on an earlier rank, or waiting on a level.
local OWED_STATES = { "AVAILABLE", "MISSINGREQS", "NEXTLEVEL", "NOTLEVEL" }

-- The addon's interface, once it has finished working out what the player
-- knows. Nil if it isn't installed or isn't ready yet.
local function WhatsTraining()
    local api = WT_API
    if type(api) == "table" and api.IsReady and api.GetSpells and api.IsReady() then
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
        if owed[spell.status] and trained and (spell.cost or 0) > 0 then
            table.insert(skills, { level = spell.level or 0, cost = spell.cost })
        end
    end
    return skills
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

-- Reading it back -------------------------------------------------------------------

--- Whether any training prices are known for this character's class.
---@return boolean
function Training.HasPrices()
    return WhatsTraining() ~= nil or next(ClassBook()) ~= nil
end

--- Class training the player hasn't bought yet, added up by level.
---@param playerLevel number
---@return table levels  list of { level, cost, skills }, lowest level first.
---        An entry at or below playerLevel is training they could buy now.
function Training.Outstanding(playerLevel)
    local byLevel = {}

    for _, skill in ipairs(SkillsFromWhatsTraining() or SkillsFromTrainerVisits()) do
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

ns.OnEvent("TRAINER_SHOW", ScanSoon)
ns.OnEvent("TRAINER_UPDATE", ScanSoon)
ns.OnEvent("PLAYER_LOGIN", function()
    NoteWhatLiesAhead()

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
