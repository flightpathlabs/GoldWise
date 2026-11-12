local _, ns = ...

-- Turning one thing into another for more coin.
--
-- A stack of ore can be sold as ore or smelted and sold as bars. Which
-- pays better changes with the market, and working it out means looking
-- up half a dozen prices and doing sums nobody wants to do at a forge.
-- This does them, for every recipe the player knows.
--
-- The comparison is always against selling the ingredients as they are.
-- Ore the player already holds isn't free: using it costs what it would
-- have sold for. So "worth making" means the finished thing sells for
-- more than its ingredients would, after the auction house's cut on both.
--
-- Each line stands alone. If two recipes want the same ore, both are
-- worked out as though they had all of it.

local Conversions = {}
ns.Conversions = Conversions

-- A vendor usually asks four times what they'd pay for the same thing.
-- Used for ingredients nobody auctions because a vendor sells them.
local BUY_TO_SELL_RATIO = 4

-- Making something has to beat selling the ingredients by this share of
-- their value before it's worth the bother, and never by less than a
-- listing deposit.
local WORTHWHILE_SHARE = 0.10

-- For buying the ingredients in, the bar is higher: that's coin put at
-- risk, not just time spent.
local WORTH_BUYING_SHARE = 0.25

-- How many lines each part of the plan lists.
local MOST_FROM_HOLDINGS = 10
local MOST_TO_BUY_FOR = 8
local MOST_NOT_WORTH = 4

-- Ingredients named per line before the rest are counted.
local INGREDIENTS_NAMED = 3

-- The sums -------------------------------------------------------------------------

local function Held(itemID)
    return (ns.Bags.Counts()[itemID] or 0) + ns.Bank.Count(itemID)
end

local function NameOf(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return name or ("item " .. itemID)
end

-- What one of an ingredient is worth to the player, and whether that's an
-- auction price. Something with an auction price costs what it would
-- have fetched. Something without is taken to come from a vendor.
local function IngredientValue(itemID, marketKey, cut)
    local price = ns.Ledger.Price(marketKey, itemID)
    if price then
        return price * (1 - cut), true
    end

    local sellsFor = select(11, C_Item.GetItemInfo(itemID))
    if sellsFor and sellsFor > 0 then
        return sellsFor * BUY_TO_SELL_RATIO, false
    end
end

-- Works one recipe through. Returns nil if anything in it can't be priced.
local function Assess(recipe, marketKey, cut)
    local sellsFor = ns.Ledger.Price(marketKey, recipe.item)
    if not sellsFor then
        return nil
    end

    local cost, outlay, batches = 0, 0, math.huge
    for _, need in ipairs(recipe.needs) do
        local value, auctioned = IngredientValue(need.itemID, marketKey, cut)
        if not value then
            return nil
        end
        cost = cost + value * need.count
        -- Buying at auction costs the full price: the cut comes out of
        -- the seller's side, not the buyer's.
        outlay = outlay + (auctioned and value / (1 - cut) or value) * need.count

        -- Only what has to be found limits how many can be made. A
        -- vendor's goods can always be bought.
        if auctioned then
            batches = math.min(batches, math.floor(Held(need.itemID) / need.count))
        end
    end

    -- Made entirely of vendor goods: one batch, bought in.
    if batches == math.huge then
        batches = 0
    end

    local earns = sellsFor * recipe.makes * (1 - cut)
    return {
        recipe = recipe,
        cost = cost, -- per batch: what the ingredients would sell for as they are
        outlay = outlay, -- per batch: what buying the ingredients in would cost
        earns = earns, -- per batch: what the result brings in
        gain = earns - cost, -- over selling ingredients already held
        profit = earns - outlay, -- over buying the ingredients in
        batches = batches,
    }
end

-- Saying it ------------------------------------------------------------------------

-- "20 Copper Ore, 2 Coarse Stone", for however many batches.
local function IngredientsText(recipe, batches)
    local parts = {}
    for index, need in ipairs(recipe.needs) do
        if index > INGREDIENTS_NAMED then
            table.insert(parts, ("%d more"):format(#recipe.needs - INGREDIENTS_NAMED))
            break
        end
        table.insert(parts, ("%d %s"):format(need.count * batches, NameOf(need.itemID)))
    end
    return table.concat(parts, ", ")
end

local function FromHoldingsStep(assessed)
    local recipe, batches = assessed.recipe, assessed.batches
    return {
        itemID = recipe.item,
        title = ("Make %d %s"):format(recipe.makes * batches, NameOf(recipe.item)),
        detail = ("Uses %s. Sold as they are: %s. Made up: %s."):format(
            IngredientsText(recipe, batches),
            ns.Money(assessed.cost * batches),
            ns.Money(assessed.earns * batches)
        ),
        amount = assessed.gain * batches,
        amountLabel = "gains",
    }
end

local function BuyForStep(assessed)
    local recipe = assessed.recipe
    return {
        itemID = recipe.item,
        title = ("%s (%s)"):format(NameOf(recipe.item), recipe.profession),
        detail = ("Takes %s, about %s to buy. Brings in %s."):format(
            IngredientsText(recipe, 1),
            ns.Money(assessed.outlay),
            ns.Money(assessed.earns)
        ),
        amount = assessed.profit,
        amountLabel = "profit each",
    }
end

local function NotWorthStep(assessed)
    local recipe, batches = assessed.recipe, assessed.batches
    return {
        itemID = recipe.item,
        title = ("Don't make %s"):format(NameOf(recipe.item)),
        detail = ("%s sells for %s as it is, and only %s made up."):format(
            IngredientsText(recipe, batches),
            ns.Money(assessed.cost * batches),
            ns.Money(assessed.earns * batches)
        ),
        amount = -assessed.gain * batches,
        amountLabel = "would lose",
    }
end

-- The plan ------------------------------------------------------------------------------

--- Lays out what's worth making, from what the player holds and from
--- what they could buy.
---@return table sections  list of { heading, steps, numbered }, shaped
---        like Trip.Plan's
function Conversions.Plan()
    local marketKey = ns.Market.Home()
    local cut = ns.Market.Cut(marketKey)
    local known = ns.Crafts.Known()

    if #known == 0 then
        return {
            {
                heading = "Goldwise hasn't seen your recipes yet",
                numbered = false,
                steps = {
                    {
                        title = "Open each of your profession windows once",
                        detail = "It reads what you know how to make and what goes into it, "
                            .. "then works out what's worth making.",
                    },
                },
            },
        }
    end

    local fromHoldings, toBuyFor, notWorth = {}, {}, {}
    for _, recipe in ipairs(known) do
        local assessed = Assess(recipe, marketKey, cut)
        if assessed then
            local bar = math.max(ns.MIN_DEPOSIT, assessed.cost * WORTHWHILE_SHARE)

            if assessed.batches > 0 and assessed.gain >= bar then
                table.insert(fromHoldings, assessed)
            elseif assessed.batches > 0 and assessed.gain < 0 then
                table.insert(notWorth, assessed)
            elseif assessed.batches == 0 then
                local worthIt = math.max(ns.MIN_DEPOSIT, assessed.outlay * WORTH_BUYING_SHARE)
                if assessed.profit >= worthIt then
                    table.insert(toBuyFor, assessed)
                end
            end
        end
    end

    -- Each list by what's at stake: the most to gain, or to lose, first.
    table.sort(fromHoldings, function(a, b)
        return a.gain * a.batches > b.gain * b.batches
    end)
    table.sort(toBuyFor, function(a, b)
        return a.profit > b.profit
    end)
    table.sort(notWorth, function(a, b)
        return a.gain * a.batches < b.gain * b.batches
    end)

    local sections = {}
    local function Add(heading, assessments, most, describe, numbered)
        local steps = {}
        for index = 1, math.min(most, #assessments) do
            steps[index] = describe(assessments[index])
        end
        if #steps > 0 then
            table.insert(sections, { heading = heading, steps = steps, numbered = numbered })
        end
    end

    Add("Worth making from what you hold", fromHoldings, MOST_FROM_HOLDINGS, FromHoldingsStep, true)
    Add("Worth buying the materials for", toBuyFor, MOST_TO_BUY_FOR, BuyForStep, true)
    Add("Better sold as they are", notWorth, MOST_NOT_WORTH, NotWorthStep, false)

    if #sections == 0 then
        table.insert(sections, {
            heading = "Nothing worth making just now",
            numbered = false,
            steps = {
                {
                    title = "Your materials are worth most as they are",
                    detail = ns.Ledger.LastScan(marketKey)
                            and "Nothing you can make sells for enough more than its ingredients."
                        or "This needs auction prices. Visit an auction house first.",
                },
            },
        })
    end
    return sections
end
