local _, ns = ...

-- Recipes the player could still buy from a vendor, for the professions
-- they have.
--
-- Which vendors sell which recipes isn't something the game will say. The
-- list in Data\Recipes is the one What's Training? keeps, brought in with
-- its author's licence. What's worked out here is the part that depends on
-- the player: which of those recipes they haven't learned, which they're
-- skilled enough for, and whether one is on sale where they're standing.

local Recipes = {}
ns.Recipes = Recipes

-- How far short of a recipe's skill the player can be and still be told,
-- unasked, that it's for sale nearby. Close enough to be worth buying
-- ahead; not so far that it's noise.
local WITHIN_REACH = 25

local function IsLearned(spellID)
    return C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)
end

-- Whether the player's reputation is good enough to be sold a recipe.
-- `standing` is pairs of faction and standing, any one of which will do
-- (there's usually one pair for each side). Returns false and a few words
-- on what's missing when it isn't.
local function MeetsStanding(standing)
    if not standing then
        return true
    end

    local missing
    for index = 1, #standing, 2 do
        local faction = C_Reputation.GetFactionDataByID(standing[index])
        -- The other side's faction is one this character will never meet.
        if faction then
            local needed = standing[index + 1]
            if faction.reaction >= needed then
                return true
            end
            missing = ("Needs %s with %s"):format(
                _G["FACTION_STANDING_LABEL" .. needed] or "better standing",
                faction.name
            )
        end
    end
    return false, missing or "Needs a reputation you haven't begun"
end

-- The vendors who'll sell a recipe to the player's side, as { npc, area,
-- zone }, and the one among them in the zone the player is standing in.
local function VendorsFor(recipe, side, zoneHere)
    local vendors, here = {}, nil

    for _, vendor in ipairs(recipe.vendors) do
        if not vendor[3] or vendor[3] == side then
            local entry = {
                npc = vendor[1],
                area = vendor[2],
                zone = C_Map.GetAreaInfo(vendor[2]),
            }
            table.insert(vendors, entry)
            if entry.zone and entry.zone == zoneHere then
                here = here or entry
            end
        end
    end
    return vendors, here
end

--- Every vendor recipe the player hasn't learned, for the professions they
--- have. Recipes on sale in the zone they're in come first, then the ones
--- they can use now, then the rest by skill.
---@return table recipes  list of:
---   item        the recipe's item ID
---   spell       the spell it teaches
---   profession  the profession's name
---   needed      skill it takes to learn
---   skill       the player's skill
---   ready       true if they're skilled enough now
---   bound       true if it binds when bought
---   favor       its price in Merchant's Favor, if it isn't sold for coin
---   locked      what reputation is missing, if they can't be sold it yet
---   vendors     { npc, area, zone } for each vendor who'll deal with them
---   here        the vendor in the zone they're standing in, if there is one
function Recipes.Unlearned()
    local side = UnitFactionGroup("player")
    local zoneHere = GetRealZoneText()
    local list = {}

    for profession, recipes in pairs(ns.RecipeData) do
        local skill = ns.Professions.SkillByName(profession)

        for _, recipe in ipairs(skill and recipes or {}) do
            local item, spell, needed = recipe[1], recipe[2], recipe[3]

            if not IsLearned(spell) then
                local vendors, here = VendorsFor(recipe, side, zoneHere)

                if #vendors > 0 then
                    local allowed, missing = MeetsStanding(recipe.standing)
                    table.insert(list, {
                        item = item,
                        spell = spell,
                        profession = profession,
                        needed = needed,
                        skill = skill,
                        ready = skill >= needed,
                        bound = recipe.bound == true,
                        favor = recipe.favor,
                        locked = not allowed and missing or nil,
                        vendors = vendors,
                        here = here,
                    })
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if (a.here ~= nil) ~= (b.here ~= nil) then
            return a.here ~= nil
        end

        local usableA = a.ready and not a.locked
        local usableB = b.ready and not b.locked
        if usableA ~= usableB then
            return usableA
        elseif a.needed ~= b.needed then
            return a.needed < b.needed
        end
        return a.item < b.item
    end)
    return list
end

--- The recipes worth mentioning unasked: on sale in the zone the player is
--- in, within reach of their skill, and not held back by reputation.
---@return table recipes  as from Recipes.Unlearned
function Recipes.ForSaleHere()
    local forSale = {}
    for _, recipe in ipairs(Recipes.Unlearned()) do
        local withinReach = recipe.needed <= recipe.skill + WITHIN_REACH
        if recipe.here and withinReach and not recipe.locked then
            table.insert(forSale, recipe)
        end
    end
    return forSale
end

--- A spot on the map for one of a recipe's vendors, where one can be
--- placed. That takes Questie; without it we know the zone and no more.
---@param recipe table  one entry from Recipes.Unlearned
---@param zone string|nil  only a vendor in this zone will do: for a plan
---        about one zone, a pin in another would mislead
---@return table|nil spot    { mapID, x, y, name }
---@return table|nil vendor  the vendor it belongs to
function Recipes.VendorSpot(recipe, zone)
    if zone then
        for _, vendor in ipairs(recipe.vendors) do
            local spot = vendor.zone == zone and ns.Directory.FindNPC(vendor.npc)
            if spot then
                return spot, vendor
            end
        end
        return nil
    end

    -- The one in this zone first, if there is one.
    if recipe.here then
        local spot = ns.Directory.FindNPC(recipe.here.npc)
        if spot then
            return spot, recipe.here
        end
    end

    for _, vendor in ipairs(recipe.vendors) do
        local spot = ns.Directory.FindNPC(vendor.npc)
        if spot then
            return spot, vendor
        end
    end
end

-- Buying to sell on -------------------------------------------------------------------

-- A recipe that doesn't bind can be bought from its vendor and sold at the
-- auction house, and plenty of players never find the vendor. Where the
-- auction price is well above what the vendor asks, that's coin for
-- anyone, whatever their professions.

-- A vendor usually asks four times what they'd pay for the same thing.
-- That's our guess at a price until the player has seen the real one.
local BUY_TO_SELL_RATIO = 4

-- The profit has to be worth the walk and the risk of it not selling:
-- at least this share of what was paid, and never less than a deposit.
local WORTHWHILE_SHARE = 0.25

-- What vendors actually charge, learned by looking at their wares:
-- [itemID] = { price, stock, at }. stock is how many were left when it's
-- limited, and nil when it isn't.
local function VendorPrices()
    if type(ns.db.vendorPrices) ~= "table" then
        ns.db.vendorPrices = {}
    end
    return ns.db.vendorPrices
end

-- Items we've asked the client to load so we can price them.
local costRequested = {}

-- Every recipe item we know a vendor sells, built on first use.
local recipeItems

local function IsRecipeItem(itemID)
    if not recipeItems then
        recipeItems = {}
        for _, recipes in pairs(ns.RecipeData) do
            for _, recipe in ipairs(recipes) do
                recipeItems[recipe[1]] = true
            end
        end
    end
    return recipeItems[itemID] == true
end

-- Notes the price and stock of every recipe a merchant has on show.
local function ReadMerchant()
    local prices = VendorPrices()
    local learned = false

    for index = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(index)
        local info = itemID and IsRecipeItem(itemID) and C_MerchantFrame.GetItemInfo(index)

        -- Things sold for tokens or favor have no price in coin.
        if info and not info.hasExtendedCost and info.price > 0 then
            prices[itemID] = {
                price = info.price / math.max(info.stackCount, 1),
                stock = info.numAvailable >= 0 and info.numAvailable or nil,
                at = GetServerTime(),
            }
            learned = true
        end
    end

    if learned then
        ns.Publish("PRICES_CHANGED", ns.Market.Current())
    end
end

ns.OnEvent("MERCHANT_SHOW", ReadMerchant)
ns.OnEvent("MERCHANT_UPDATE", ReadMerchant)

-- What a vendor asks for a recipe: the real figure if we've seen it, a
-- guess from its sale value otherwise, or nothing if the client hasn't
-- loaded the item yet.
local function VendorCost(itemID)
    local seen = VendorPrices()[itemID]
    if seen then
        return seen.price, true, seen.stock
    end

    local sellsFor = select(11, C_Item.GetItemInfo(itemID))
    if sellsFor and sellsFor > 0 then
        return sellsFor * BUY_TO_SELL_RATIO, false
    end
end

--- Vendor recipes worth buying to sell at the auction house, most
--- profitable first.
---@param marketKey string
---@return table deals  list of:
---   item        the recipe's item ID
---   profession  the profession it belongs to
---   cost        what the vendor asks, in copper
---   costIsSeen  true if that's from the vendor's own window, false if
---               it's our guess
---   stock       how many the vendor had left, where the supply is limited
---   price       the lowest auction price
---   listed      how many are up for auction: the competition
---   profit      what's left after the vendor's price and the auction cut
---   vendors     { npc, area, zone } for each vendor who'll deal with them
---   here        the vendor in the zone they're standing in, if there is one
---@return number unpriced  recipes left out because the client hasn't yet
---        told us what they're worth to a vendor
function Recipes.Resale(marketKey)
    local side = UnitFactionGroup("player")
    local zoneHere = GetRealZoneText()
    local cut = ns.Market.Cut(marketKey)
    local deals, unpriced = {}, 0

    for profession, recipes in pairs(ns.RecipeData) do
        for _, recipe in ipairs(recipes) do
            local item = recipe[1]
            -- Sold for coin, tradeable once bought, and sold to this player.
            local tradeable = not recipe.bound and not recipe.favor
            local price, listed = nil, nil
            if tradeable and MeetsStanding(recipe.standing) then
                price, listed = ns.Ledger.Price(marketKey, item)
            end

            if price then
                local cost, costIsSeen, stock = VendorCost(item)
                if not cost then
                    unpriced = unpriced + 1
                    -- Asked for once. If the client can't load an item,
                    -- asking again on every look would never end.
                    if not costRequested[item] then
                        costRequested[item] = true
                        C_Item.RequestLoadItemDataByID(item)
                    end
                else
                    local profit = price * (1 - cut) - cost
                    if profit >= math.max(ns.MIN_DEPOSIT, cost * WORTHWHILE_SHARE) then
                        local vendors, here = VendorsFor(recipe, side, zoneHere)

                        if #vendors > 0 then
                            table.insert(deals, {
                                item = item,
                                profession = profession,
                                cost = cost,
                                costIsSeen = costIsSeen,
                                stock = stock,
                                price = price,
                                listed = listed,
                                profit = profit,
                                vendors = vendors,
                                here = here,
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(deals, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.item < b.item
    end)
    return deals, unpriced
end
