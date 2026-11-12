local _, ns = ...

-- What it takes to put something up for auction.
--
-- Listing takes a deposit. It comes back with the proceeds when the
-- auction sells, and it's gone when the auction runs out or is cancelled.
-- So it isn't a fee on every sale. It's a stake, lost only on the ones
-- that don't sell.
--
-- The game works a deposit out from what a vendor would pay for the lot
-- and how long the auction runs, and never asks for less than a set
-- minimum. Blizzard has already announced a change to that minimum once,
-- from a silver to a copper, so nothing here is taken on trust. Each time
-- the auction house opens, Goldwise asks the game what the things in the
-- player's bags would cost to list and works the rule back out of the
-- answers. Until it has done that for a market, it assumes the figures
-- below.

local Deposit = {}
ns.Deposit = Deposit

-- Auction lengths are numbered 1 to 3. On Forever that's 2, 8 and 24 hours.
local SHORTEST = 1
local LONGEST = 3

-- The minimum we measured ourselves on 11 November 2026, and Classic's
-- shares of vendor value for each length. Goblins have always asked for
-- five times as much.
local ASSUMED_FLOOR = 100
local ASSUMED_RATES = {
    faction = { 0.05, 0.20, 0.60 },
    neutral = { 0.25, 1.00, 3.00 },
}

-- How many different items to ask about. A handful settles it.
local SAMPLE = 20

-- Seconds after the auction house opens before asking. It answers
-- nonsense for a moment while it's still setting itself up.
local OPEN_DELAY = 1

local function Saved()
    if type(ns.db.deposits) ~= "table" then
        ns.db.deposits = {}
    end
    return ns.db.deposits
end

local function AssumedRates(marketKey)
    return marketKey:match("%-Neutral$") and ASSUMED_RATES.neutral or ASSUMED_RATES.faction
end

-- The least any listing costs in a market, as far as is known.
local function KnownFloor(marketKey)
    local rule = Saved()[marketKey]
    return rule and rule.floor or ASSUMED_FLOOR
end

--- An estimate of the deposit for listing a lot.
---@param vendorValue number   what a vendor would pay for the whole lot, in copper
---@param marketKey string
---@param duration number|nil  1 to 3; the longest if left out, which is
---        the most that could be at stake
---@return number copper
function Deposit.Estimate(vendorValue, marketKey, duration)
    duration = duration or LONGEST

    local rule = Saved()[marketKey]
    local rate = rule and rule.rates[duration] or AssumedRates(marketKey)[duration]

    return math.max(KnownFloor(marketKey), math.floor(vendorValue * rate + 0.5))
end

-- Measuring ---------------------------------------------------------------------

-- What the game would ask to list some of an item, or nil if it won't say.
local function Ask(location, itemID, isCommodity, duration, quantity)
    local ok, deposit
    if isCommodity then
        ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, quantity)
    else
        ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, location, duration, quantity)
    end

    if ok and type(deposit) == "number" then
        return deposit
    end
    return nil
end

local function IsCommodity(location)
    local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
    return ok and status == Enum.ItemCommodityStatus.Commodity
end

local function CanBeListed(location)
    local ok, valid = pcall(C_AuctionHouse.IsSellItemValid, location, false)
    return ok and valid
end

-- Works the minimum out of what the game asked for one of each thing.
-- Each answer is the minimum or the item's own share of vendor value,
-- whichever is more, and it doesn't say which. So an answer is only taken
-- for the minimum when something vouches for it: the item has no vendor
-- value, so it can only be the minimum; or another item with a different
-- vendor value was asked the very same. Shares of different values don't
-- come out equal by chance.
local function FloorAmong(answers)
    local floor

    for index, answer in ipairs(answers) do
        local vouched = answer.vendorPrice == 0
        for other, second in ipairs(answers) do
            vouched = vouched
                or (
                    other ~= index
                    and second.least == answer.least
                    and second.vendorPrice ~= answer.vendorPrice
                )
        end

        if vouched and (not floor or answer.least < floor) then
            floor = answer.least
        end
    end
    return floor
end

local function Measure(marketKey)
    -- What the game asks for one of each thing, for the shortest time.
    local answers = {}

    -- For the share of vendor value, the most valuable lot gives the most
    -- exact answer, because deposits are rounded to the copper.
    local biggest = {}

    local seen, asked = {}, 0

    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and not item.isBound and not seen[item.itemID] and asked < SAMPLE then
                seen[item.itemID] = true

                local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if CanBeListed(location) then
                    asked = asked + 1
                    local isCommodity = IsCommodity(location)
                    local vendorPrice = select(11, C_Item.GetItemInfo(item.itemID)) or 0

                    -- Nothing costs nothing to list. An answer of zero is
                    -- the auction house not being ready to give one.
                    local least = Ask(location, item.itemID, isCommodity, SHORTEST, 1)
                    if least and least > 0 then
                        table.insert(answers, { least = least, vendorPrice = vendorPrice })
                    end

                    local value = vendorPrice * item.stackCount
                    for duration = SHORTEST, LONGEST do
                        local best = biggest[duration]
                        if value > 0 and (not best or value > best.value) then
                            local deposit =
                                Ask(location, item.itemID, isCommodity, duration, item.stackCount)
                            if deposit and deposit > 0 then
                                biggest[duration] = { value = value, deposit = deposit }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Nothing in the bags could be asked about. What's known stands.
    if #answers == 0 and next(biggest) == nil then
        return
    end

    local saved = Saved()
    local rule = saved[marketKey] or { rates = {} }
    local before = KnownFloor(marketKey)

    -- With nothing to vouch for a minimum this time, it stays what it was.
    local floor = FloorAmong(answers)
    if floor then
        rule.floor = floor
        rule.at = time()
    else
        rule.floor = before
    end

    for duration = SHORTEST, LONGEST do
        -- A lot that only costs the minimum says nothing about the share.
        local best = biggest[duration]
        if best and best.deposit > rule.floor then
            rule.rates[duration] = best.deposit / best.value
        end
    end
    saved[marketKey] = rule

    -- The advice moves with the minimum: a lower one makes cheap things
    -- worth listing that weren't before. Anything showing advice redraws.
    if rule.floor ~= before then
        ns.Log(
            "deposit: the least a listing costs on %s is now %s (was %s)",
            marketKey,
            ns.Money(rule.floor),
            ns.Money(before)
        )
        ns.Publish("PRICES_CHANGED", marketKey)
    end
end

ns.Subscribe("AUCTION_HOUSE_OPENED", function(marketKey)
    C_Timer.After(OPEN_DELAY, function()
        if ns.Market.IsOpen() and ns.Market.Current() == marketKey then
            Measure(marketKey)
        end
    end)
end)
