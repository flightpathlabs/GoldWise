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
-- Prices are remembered per class, so an alt of the same class starts out
-- knowing them.

local Training = {}
ns.Training = Training

-- Trainer updates come in bursts while the list fills in.
local SETTLE_DELAY = 0.3

local scanPending = false

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
    -- One row is a "step" marker rather than a skill. Blizzard's own list
    -- skips it the same way.
    local stepRow = GetTrainerServiceStepIndex and GetTrainerServiceStepIndex()

    for index = 1, GetNumTrainerServices() do
        if index ~= stepRow then
            local name, status, _, requiredLevel, rank = GetTrainerServiceInfo(index)
            local cost = GetTrainerServiceCost(index)

            if name then
                -- "Raptor Strike" comes in several ranks, each sold separately.
                local key = rank and rank ~= "" and (name .. " (" .. rank .. ")") or name

                if status == "used" then
                    -- Already learned on this character. On another of
                    -- the same class it will be seen as unlearned again.
                    book[key] = nil
                elseif cost and cost > 0 then
                    book[key] = { cost = cost, level = requiredLevel or 0 }
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

--- Class training the player hasn't bought yet, added up by level.
---@param playerLevel number
---@return table levels  list of { level, cost, skills }, lowest level first.
---        An entry at or below playerLevel is training they could buy now.
function Training.Outstanding(playerLevel)
    local byLevel = {}
    for _, skill in pairs(ClassBook()) do
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
