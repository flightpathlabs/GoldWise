local _, ns = ...

-- What class training is going to cost.
--
-- Nobody ships a reliable table of Forever's training prices, so we learn
-- them the honest way: whenever the player opens their class trainer, we
-- note every skill on offer, what it costs and the level it needs. That is
-- enough to say "level 30 will cost you 3g 40s" well before level 30.
--
-- What we know is only what the trainer window showed. If the player has
-- the "unavailable" filter switched off there, skills above their level
-- aren't listed and we can't see them.
--
-- Two things are remembered. Prices are kept per class, so an alt of the
-- same class starts out knowing them. Which skills are still to be bought
-- is kept per character, because that's the part that differs: a skill
-- only counts against a character once we know they don't have it.

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

-- Reading it back -------------------------------------------------------------------

--- Whether any training prices are known for this character's class.
---@return boolean
function Training.HasPrices()
    return next(ClassBook()) ~= nil
end

--- Class training the player hasn't bought yet, added up by level.
---@param playerLevel number
---@return table levels  list of { level, cost, skills }, lowest level first.
---        An entry at or below playerLevel is training they could buy now.
function Training.Outstanding(playerLevel)
    local unlearned = Unlearned()
    local byLevel = {}

    for key, skill in pairs(ClassBook()) do
        if unlearned[key] then
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
ns.OnEvent("PLAYER_LOGIN", NoteWhatLiesAhead)

if BuyTrainerService then
    hooksecurefunc("BuyTrainerService", OnBuy)
end
