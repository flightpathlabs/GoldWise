local _, ns = ...

-- Plans a trip to a zone: what to see to before leaving, what's worth
-- picking up while there, and where things are once the player arrives.
--
-- "I want to quest in Redridge" is a decision the player has already
-- made. This doesn't second-guess it. It answers the question that comes
-- next: given that I'm going, what should I do on the way and while I'm
-- there to come back better off?
--
-- Nothing here is new knowledge. It gathers what the rest of Goldwise
-- already knows (bags, repairs, training, what can be gathered, what the
-- vendors sell, who's standing where) and puts it in the order a player
-- would act on it.

local Trip = {}
ns.Trip = Trip

-- Bags have to hold at least this much in sellable goods before selling
-- first is worth a step of its own.
local WORTH_SELLING_FIRST = 2000

-- Below this, gear is worn enough to see to before setting out.
local REPAIR_BELOW = 70

-- With fewer free bag slots than this, a gathering trip is cut short.
local ROOM_NEEDED = 8

-- What a full stack holds, for saying what one would sell for.
local STACK = 20

-- How many gatherables and recipes a plan lists before it stops.
local MOST_GATHERABLES = 8
local MOST_RECIPES = 6

-- How far above the player a zone can be before it's worth a warning, and
-- how far below before there's little left in it for them.
local TOO_HIGH = 3
local TOO_LOW = 8

local function FreeBagSlots()
    local free = 0
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        free = free + C_Container.GetContainerNumFreeSlots(bag)
    end
    return free
end

-- A button that puts a place on the map, or nil if there's nowhere to put.
local function MapAction(spot)
    if not spot then
        return nil
    end
    return {
        label = "Map",
        onClick = function()
            ns.MapMarks.ShowPoint(spot.mapID, spot.x, spot.y)
        end,
    }
end

-- The sections ------------------------------------------------------------------------

-- Each returns a list of steps: { title, detail, amount, amountLabel,
-- action }. amount is in copper, and action is { label, onClick }.

local function BeforeLeaving(zone, level)
    local steps = {}

    -- Said first, because it may change the player's mind about going.
    if zone.minLevel > level + TOO_HIGH then
        table.insert(steps, {
            title = "Mind your level",
            detail = ("This zone runs from level %d to %d, and you're %d."):format(
                zone.minLevel,
                zone.maxLevel,
                level
            ),
        })
    elseif zone.maxLevel < level - TOO_LOW then
        table.insert(steps, {
            title = "You've outgrown it",
            detail = ("This zone runs from level %d to %d. Little there will still pay."):format(
                zone.minLevel,
                zone.maxLevel
            ),
        })
    end

    local _, sellable = ns.Assets.InBags(ns.Market.Home())
    if sellable >= WORTH_SELLING_FIRST then
        local auction = ns.Directory.Nearest(ns.Directory.AUCTION)
        table.insert(steps, {
            title = "Sell what's marked Sell",
            detail = "At the auction house, so you leave with coin and empty bags.",
            amount = sellable,
            amountLabel = "about",
            action = MapAction(auction),
        })
    end

    local durability = ns.Purse.Durability()
    if durability and durability < REPAIR_BELOW then
        local cost = ns.Purse.RepairCost()
        table.insert(steps, {
            title = "Repair",
            detail = ("Your gear is at %d%%."):format(durability),
            amount = cost,
            amountLabel = "costs",
            action = MapAction(ns.Directory.Nearest(ns.Directory.REPAIR)),
        })
    end

    local waiting = ns.Training.Outstanding(level)[1]
    if waiting and waiting.level <= level then
        table.insert(steps, {
            title = "Train",
            detail = waiting.skills == 1 and "1 skill is waiting at your trainer."
                or ("%d skills are waiting at your trainer."):format(waiting.skills),
            amount = waiting.cost,
            amountLabel = "costs",
            action = MapAction(ns.Directory.Nearest(ns.Directory.ClassTrainerKind())),
        })
    end

    local free = FreeBagSlots()
    if free < ROOM_NEEDED then
        table.insert(steps, {
            title = "Make room",
            detail = free == 1 and "You have 1 bag slot free. Sell, bank or mail what you can."
                or ("You have %d bag slots free. Sell, bank or mail what you can."):format(free),
        })
    end

    return steps
end

local function WhileThere(zone, profile, marketKey)
    local steps = {}
    local cut = ns.Market.Cut(marketKey)

    local gatherable = ns.Prospects.InZone(zone, profile, function(itemID)
        return ns.Ledger.Price(marketKey, itemID)
    end)

    for index = 1, math.min(MOST_GATHERABLES, #gatherable) do
        local prospect = gatherable[index]
        table.insert(steps, {
            itemID = prospect.itemID,
            title = ("%s (%s)"):format(prospect.name, prospect.kind),
            detail = prospect.how,
            -- What a stack would actually put in the purse.
            amount = prospect.price * STACK * (1 - cut),
            amountLabel = ("%d sell for"):format(STACK),
        })
    end

    if #steps == 0 then
        table.insert(steps, {
            title = "Nothing with a price yet",
            detail = "Goldwise has no price for anything you could gather here. "
                .. "A visit to the auction house will fix that.",
        })
    end
    return steps
end

local function ForSaleThere(zoneName, marketKey)
    local steps = {}

    for _, recipe in ipairs(ns.Recipes.Unlearned()) do
        local soldHere = false
        for _, vendor in ipairs(recipe.vendors) do
            soldHere = soldHere or vendor.zone == zoneName
        end

        if soldHere and not recipe.locked and #steps < MOST_RECIPES then
            local detail = ("%s %d"):format(recipe.profession, recipe.needed)
            if not recipe.ready then
                detail = ("%s (you're at %d)"):format(detail, recipe.skill)
            end

            -- A recipe that doesn't bind can be bought to sell on.
            local price = not recipe.bound and ns.Ledger.Price(marketKey, recipe.item) or nil

            table.insert(steps, {
                itemID = recipe.item,
                title = C_Item.GetItemNameByID(recipe.item) or "Recipe",
                detail = detail,
                amount = price,
                amountLabel = "sells for",
                action = MapAction(ns.Recipes.VendorSpot(recipe)),
            })
        end
    end
    return steps
end

local function OnTheSpot(mapID)
    local Directory = ns.Directory
    local steps = {}

    local function Add(label, kind)
        local spot = Directory.On(kind, mapID)
        if spot then
            table.insert(steps, {
                title = label,
                detail = spot.name or "",
                action = MapAction(spot),
            })
        end
    end

    Add("Flight master", Directory.FLIGHT)
    Add("Innkeeper", Directory.INN)
    Add("Repairs", Directory.REPAIR)
    Add("Your class trainer", Directory.ClassTrainerKind())
    for _, profession in ipairs(Directory.PROFESSIONS) do
        if ns.Professions.SkillByName(profession.name) then
            Add(profession.name .. " trainer", Directory.ProfessionKind(profession))
        end
    end
    return steps
end

-- The plan ------------------------------------------------------------------------------

--- Plans a trip to a zone.
---@param zone table  an entry of Gathering.ZONES
---@return table sections  list of { heading, steps, numbered }, in the
---        order to act on them. Sections with nothing in them are left
---        out. `numbered` is true for things to do, false for things to
---        know.
function Trip.Plan(zone)
    local level = UnitLevel("player")
    local marketKey = ns.Market.Home()
    local zoneName = ns.MapMarks.ZoneName(zone.mapID)

    local profile = {
        level = level,
        faction = UnitFactionGroup("player"),
        skills = {
            skinning = ns.Professions.Skill("skinning"),
            mining = ns.Professions.Skill("mining"),
            herbalism = ns.Professions.Skill("herbalism"),
        },
    }

    local sections = {}
    local function Add(heading, steps, numbered)
        if #steps > 0 then
            table.insert(sections, { heading = heading, steps = steps, numbered = numbered })
        end
    end

    Add("Before you set out", BeforeLeaving(zone, level), true)
    Add("While you're in " .. zoneName, WhileThere(zone, profile, marketKey), true)
    Add("For sale there", ForSaleThere(zoneName, marketKey), true)
    Add("On the spot", OnTheSpot(zone.mapID), false)
    return sections
end
