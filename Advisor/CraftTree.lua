local _, ns = ...

-- What an item is made from, and what it can be made into, with the sums
-- at every step.
--
-- Conversions answers one question about each recipe: is it worth making?
-- This lays the whole chain out for one item. A robe is made from bolts,
-- and the bolts from cloth; the bolts also go into bags. At each step
-- there's a choice between buying the thing and making it, and each has a
-- price. Going down the tree, the cheaper of the two is carried upward, so
-- the cost at the top is the least the item can be had for.
--
-- Only recipes this character knows are followed. A step the player
-- can't make is a thing to buy, and the tree stops there.

local CraftTree = {}
ns.CraftTree = CraftTree

-- Steps followed below the item asked about. Chains in the game are
-- rarely longer, and something has to stop a recipe that feeds itself.
local DEEPEST = 4

-- Things an item goes into, listed before the rest are left off. Cloth
-- goes into half of tailoring.
local MOST_INTO = 20

-- Recipes by what they make and by what they use: [itemID] = list of
-- recipes. Rebuilt when the player's recipes are read again.
local makers, users

local function Index()
    if makers then
        return
    end

    makers, users = {}, {}
    for _, recipe in ipairs(ns.Crafts.Known()) do
        makers[recipe.item] = makers[recipe.item] or {}
        table.insert(makers[recipe.item], recipe)

        for _, need in ipairs(recipe.needs) do
            users[need.itemID] = users[need.itemID] or {}
            table.insert(users[need.itemID], recipe)
        end
    end
end

ns.Subscribe("CRAFTS_CHANGED", function()
    makers, users = nil, nil
end)

-- The sums -------------------------------------------------------------------------

-- What one of something costs to buy, and whether that's a guess at a
-- vendor's price. The auction price if it has one; failing that, it's
-- taken to come from a vendor.
local function BuyingPrice(itemID, auctionPrice)
    if auctionPrice then
        return auctionPrice, false
    end

    local fromVendor = ns.VendorGuess(itemID)
    if fromVendor then
        return fromVendor, true
    end
end

-- Defined below. A step and its ingredients each need the other.
local Step

-- Works one recipe through for a given number of the thing it makes.
-- Returns its ingredients as steps, and what they come to at their
-- cheapest: nil if any of them can't be priced.
local function Ingredients(recipe, quantity, marketKey, depth, path)
    local crafts = quantity / recipe.makes
    local parts, cost = {}, 0

    for index, need in ipairs(recipe.needs) do
        local part = Step(need.itemID, need.count * crafts, marketKey, depth + 1, path)
        parts[index] = part
        cost = cost and part.best and (cost + part.best) or nil
    end
    return parts, cost
end

-- One step of the tree: so many of an item, what they'd cost bought, and
-- what they'd cost made, if the player can make them.
--
-- `path` holds the items above this one, so that two recipes which turn
-- into each other don't go round for ever.
function Step(itemID, quantity, marketKey, depth, path)
    local price, listed = ns.Ledger.Price(marketKey, itemID)
    local each, fromVendor = BuyingPrice(itemID, price)

    local step = {
        itemID = itemID,
        quantity = quantity,
        depth = depth,
        price = price,
        listed = listed,
        fromVendor = fromVendor,
        buy = each and each * quantity or nil,
    }

    if depth < DEEPEST and not path[itemID] then
        path[itemID] = true

        -- Where more than one recipe makes it, the cheapest one counts. A
        -- recipe that can be priced beats one that can't.
        for _, recipe in ipairs(makers[itemID] or {}) do
            local parts, cost = Ingredients(recipe, quantity, marketKey, depth, path)
            local better = not step.recipe
                or (cost and not step.make)
                or (cost and step.make and cost < step.make)

            if better then
                step.recipe, step.parts, step.make = recipe, parts, cost
            end
        end

        path[itemID] = nil
    end

    -- The cheaper way to come by it, which is what the step above pays.
    if step.buy and step.make then
        step.best = math.min(step.buy, step.make)
    else
        step.best = step.buy or step.make
    end
    return step
end

-- Reading it back -------------------------------------------------------------------

--- Whether an item is part of anything the player can make: either they
--- can make it, or it goes into something they can.
---@param itemID number
---@return boolean
function CraftTree.Has(itemID)
    Index()
    return makers[itemID] ~= nil or users[itemID] ~= nil
end

--- The tree for one item.
---@param itemID number
---@return table tree
---   root      the item itself, as a step: { itemID, quantity, depth, price,
---             listed, fromVendor, buy, make, best, recipe, parts }. buy,
---             make and best are for the whole quantity; parts is a list of
---             steps shaped the same way, and is nil for something the
---             player can't make.
---   sells     what the root's quantity brings in at auction after the
---             cut; nil with no auction price
---   materials what the root's own ingredients cost if every one is
---             bought; nil if it can't be made or one can't be priced
---   into      list of what it goes into, most profitable first:
---             { recipe, itemID, makes, price, listed, cost, sells, profit,
---               onward }, where cost is the materials at their cheapest,
---             and onward counts the recipes the product goes into in turn
---   intoMore  how many more it goes into than are listed
---   cut       the auction house's share of a sale on this market
---   known     false if no recipes have been read for this character yet
function CraftTree.For(itemID)
    Index()

    local marketKey = ns.Market.Home()
    local cut = ns.Market.Cut(marketKey)

    -- Laid out for one, unless the recipe makes several at a time: half a
    -- bar of ore helps nobody.
    local root = Step(itemID, 1, marketKey, 0, {})
    if root.recipe and root.recipe.makes > 1 then
        root = Step(itemID, root.recipe.makes, marketKey, 0, {})
    end

    local materials
    if root.parts then
        materials = 0
        for _, part in ipairs(root.parts) do
            materials = materials and part.buy and (materials + part.buy) or nil
        end
    end

    local into = {}
    for _, recipe in ipairs(users[itemID] or {}) do
        local price, listed = ns.Ledger.Price(marketKey, recipe.item)
        local _, cost = Ingredients(recipe, recipe.makes, marketKey, 0, { [recipe.item] = true })
        local sells = price and price * recipe.makes * (1 - cut) or nil

        table.insert(into, {
            recipe = recipe,
            itemID = recipe.item,
            makes = recipe.makes,
            price = price,
            listed = listed,
            cost = cost,
            sells = sells,
            profit = sells and cost and (sells - cost) or nil,
            onward = #(users[recipe.item] or {}),
        })
    end

    -- What can't be worked out goes to the bottom.
    table.sort(into, function(a, b)
        if (a.profit ~= nil) ~= (b.profit ~= nil) then
            return a.profit ~= nil
        elseif a.profit and a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.itemID < b.itemID
    end)

    local intoMore = math.max(0, #into - MOST_INTO)
    for index = #into, MOST_INTO + 1, -1 do
        into[index] = nil
    end

    return {
        root = root,
        sells = root.price and root.price * root.quantity * (1 - cut) or nil,
        materials = materials,
        into = into,
        intoMore = intoMore,
        cut = cut,
        known = next(makers) ~= nil,
    }
end
