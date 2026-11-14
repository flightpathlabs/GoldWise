local _, ns = ...

-- What killing a creature is worth: its coin, what it drops and, for those
-- who skin, its hide. Worked out from what the player's own looting has
-- taught Profile\Drops.
--
-- Everything is in copper per kill. Drops are valued the way Goldwise
-- would sell them: what the auction house pays after its cut if that's
-- the advice, otherwise what a vendor pays. A creature killed only once
-- or twice says too little on its own, so until there are a few kills,
-- the figures are borrowed from creatures like it: the same type, a
-- level or two either side.

local MobValue = {}
ns.MobValue = MobValue

-- Fewer kills than this and the figures come from similar creatures.
local FEW_KILLS = 3

-- Kills needed before an estimate is shown without a "~".
local CONFIDENT_KILLS = 10

-- How far apart in level two creatures can be and still be alike.
local LEVEL_SPREAD = 2

-- The band around an estimate is this wide at most, either side. It
-- narrows as kills mount up, the way an average settles.
local WIDEST_MARGIN = 0.5

-- Seconds an answer is kept before being worked out again. Prices and
-- drops say when they change; this catches what doesn't, such as an
-- item's vendor price arriving.
local CACHE_FOR = 60

-- Drops are sold by the stack, not one at a time, so that's how they're
-- judged: the deposit on one linen cloth would rule it out, and twenty
-- of them sell happily. Twenty is the largest stack of most drops.
local LARGEST_LOT = 20

-- What one of each item is worth: [itemID] = { at, value, vendor }.
local itemValues = {}

-- Estimates from a creature's own kills, by npcID, and those borrowed
-- from similar creatures, by npcID, level and type. Each is { at,
-- estimate }, where estimate is false when there was nothing to go on.
local estimates = {}
local guesses = {}

-- Kinds of creature on record by type, [type] = list of npcIDs, for
-- finding similar ones. Made when first needed.
local byType

-- Items ---------------------------------------------------------------------

-- What one of an item fetches, and what a vendor would pay for it.
local function ItemValue(itemID)
    local now = GetTime()
    local known = itemValues[itemID]
    if known and now - known.at < CACHE_FOR then
        return known.value, known.vendor
    end

    local _, _, _, _, _, _, _, stackCount, _, _, sellPrice = C_Item.GetItemInfo(itemID)
    if sellPrice == nil then
        -- Asked for. The estimates are worked out again when it arrives.
        ns.LoadItem(itemID)
    end
    local vendor = sellPrice or 0
    local value = vendor

    local marketKey = ns.Market.Home()
    local price = ns.Ledger.Price(marketKey, itemID)
    if price then
        local lot = math.max(1, math.min(stackCount or 1, LARGEST_LOT))
        local advice = ns.Advice.ForHolding({
            count = lot,
            price = price,
            vendorPrice = sellPrice,
            cut = ns.Market.Cut(marketKey),
            deposit = ns.Deposit.Estimate(vendor * lot, marketKey),
        })
        -- Only a sale is valued at what the auction house pays. Holding
        -- for a better price would mean an againstUsual, which isn't
        -- given, so a hold here is always that listing isn't worth its
        -- deposit and no vendor wants it: the drop is worth nothing, and
        -- vendor is already 0.
        if advice.verb == ns.Advice.SELL and advice.proceeds then
            value = advice.proceeds / lot
        end
    end

    itemValues[itemID] = { at = now, value = value, vendor = vendor }
    return value, vendor
end

-- Biggest earners first: how often it drops, how many, and what each is
-- worth, all taken together.
local function ByWorth(a, b)
    local worthA = a.chance * a.quantity * a.each
    local worthB = b.chance * b.quantity * b.each
    if worthA ~= worthB then
        return worthA > worthB
    end
    return a.itemID < b.itemID
end

-- Turns tallies of { times, quantity } into the list an estimate carries,
-- and what the list comes to per opening, at Goldwise's prices and at a
-- vendor's.
local function List(tallies, openings)
    local list, worth, vendorWorth = {}, 0, 0
    if openings <= 0 then
        return list, worth, vendorWorth
    end

    for itemID, tally in pairs(tallies) do
        local times, quantity = tally[1] or 0, tally[2] or 0
        if times > 0 then
            local each, vendor = ItemValue(itemID)
            local drop = {
                itemID = itemID,
                chance = math.min(1, times / openings),
                quantity = quantity / times,
                each = each,
            }
            table.insert(list, drop)
            worth = worth + drop.chance * drop.quantity * each
            vendorWorth = vendorWorth + drop.chance * drop.quantity * vendor
        end
    end

    table.sort(list, ByWorth)
    return list, worth, vendorWorth
end

-- Pooling --------------------------------------------------------------------

-- Adds one creature's tallies into another set of tallies.
local function AddTallies(into, from)
    for itemID, tally in pairs(from or {}) do
        local sum = into[itemID]
        if not sum then
            sum = { 0, 0 }
            into[itemID] = sum
        end
        sum[1] = sum[1] + (tally[1] or 0)
        sum[2] = sum[2] + (tally[2] or 0)
    end
end

local function NewPool()
    return { kills = 0, skins = 0, copper = 0, items = {}, skinned = {}, kinds = 0 }
end

local function AddToPool(pool, drops)
    pool.kills = pool.kills + (drops.kills or 0)
    pool.skins = pool.skins + (drops.skins or 0)
    pool.copper = pool.copper + (drops.copper or 0)
    AddTallies(pool.items, drops.items)
    AddTallies(pool.skinned, drops.skinned)
    pool.kinds = pool.kinds + 1
end

local function TypeIndex()
    if not byType then
        byType = {}
        for npcID, drops in pairs(ns.Drops.All()) do
            if type(drops) == "table" and drops.type then
                byType[drops.type] = byType[drops.type] or {}
                table.insert(byType[drops.type], npcID)
            end
        end
    end
    return byType
end

-- Creatures of the same type within a couple of levels, pooled, leaving
-- out the one asked about. Nil when there are none with kills.
local function Similar(npcID, level, creatureType)
    if not level or not creatureType then
        return nil
    end

    local pool
    for _, otherID in ipairs(TypeIndex()[creatureType] or {}) do
        local other = otherID ~= npcID and ns.Drops.Get(otherID)
        if
            other
            and (other.kills or 0) > 0
            and other.level
            and math.abs(other.level - level) <= LEVEL_SPREAD
        then
            pool = pool or NewPool()
            AddToPool(pool, other)
        end
    end
    return pool
end

-- The sums ---------------------------------------------------------------------

-- An estimate from a pool of kills. own is the creature's own record, if
-- it has one, for the kills and skins the estimate reports.
local function Estimate(pool, own, guess)
    if pool.kills <= 0 then
        return nil
    end

    local copper = pool.copper / pool.kills
    local drops, dropWorth, dropVendor = List(pool.items, pool.kills)
    local skinned, skinWorth, skinVendor = List(pool.skinned, pool.skins)

    -- A creature the player has skinned can be skinned every time, so the
    -- hide counts in full. Borrowed figures can't promise that: the hide
    -- counts as often as similar corpses were skinned.
    local skinShare = 0
    if pool.skins > 0 then
        skinShare = guess and math.min(1, pool.skins / pool.kills) or 1
    end

    local value = copper + dropWorth + skinWorth * skinShare
    local vendorOnly = copper + dropVendor + skinVendor * skinShare

    -- What's listed is only ever the creature's own. Similar creatures
    -- can lend a rough worth, but not their drops: a zebra doesn't drop a
    -- plainstrider's beak because the two are beasts of a level.
    if guess then
        local kills, skins = own and own.kills or 0, own and own.skins or 0
        drops = List(own and own.items or {}, kills)
        skinned = List(own and own.skinned or {}, skins)
        copper = kills > 0 and own.copper / kills or 0
    end

    -- The low end is everything sold to a vendor; the high end is the
    -- estimate itself. Both are widened by how unsure a handful of kills
    -- leaves us, which falls away with the square root of the kills, as
    -- an average's error does.
    local margin = guess and WIDEST_MARGIN or math.min(WIDEST_MARGIN, 1 / math.sqrt(pool.kills))
    local low = math.min(value, vendorOnly) * (1 - margin)
    local high = value * (1 + margin)

    return {
        value = math.floor(value + 0.5),
        low = math.floor(low),
        high = math.ceil(high),
        kills = own and own.kills or 0,
        skins = own and own.skins or 0,
        guess = guess,
        copper = math.floor(copper + 0.5),
        drops = drops,
        skinned = skinned,
    }
end

-- Keeps an answer for a while, false standing for none.
local function Keep(cache, key, estimate)
    cache[key] = { at = GetTime(), estimate = estimate or false }
    return estimate
end

local function Kept(cache, key)
    local kept = cache[key]
    if kept and GetTime() - kept.at < CACHE_FOR then
        return true, kept.estimate or nil
    end
    return false
end

--- What killing a kind of creature is worth.
---@param npcID number
---@param level number|nil         the creature's level, for finding similar
---        ones when this one has few kills; its last seen level if left out
---@param creatureType string|nil  as UnitCreatureType gives it
---@return table|nil estimate  { value, low, high, kills, skins, guess,
---        copper, drops, skinned }, all money in copper per kill. drops and
---        skinned are lists of { itemID, chance, quantity, each }, biggest
---        earners first: chance runs from 0 to 1, quantity is how many
---        when it drops, and each is what one is worth. skinned is per
---        corpse skinned. kills and skins are this creature's own, even
---        when guess is true and value, low and high are borrowed; copper,
---        drops and skinned are always its own, and empty for a creature
---        never looted. Nil when there's nothing to go on.
function MobValue.For(npcID, level, creatureType)
    if not npcID or not ns.db then
        return nil
    end

    local own = ns.Drops.Get(npcID)
    local kills = own and own.kills or 0

    if kills >= FEW_KILLS then
        local found, estimate = Kept(estimates, npcID)
        if found then
            return estimate
        end
        local pool = NewPool()
        AddToPool(pool, own)
        return Keep(estimates, npcID, Estimate(pool, own, false))
    end

    if not level or level <= 0 then
        level = own and own.level
    end
    creatureType = creatureType or (own and own.type)

    local key = ("%d:%s:%s"):format(npcID, tostring(level), tostring(creatureType))
    local found, estimate = Kept(guesses, key)
    if found then
        return estimate
    end

    local pool = Similar(npcID, level, creatureType)
    local guess = pool ~= nil
    pool = pool or NewPool()
    if own then
        AddToPool(pool, own)
    end
    return Keep(guesses, key, Estimate(pool, own, guess))
end

--- What killing a unit is worth, if it's a creature the player could
--- fight. Nil for players, friendly creatures and anything unknown.
---@param unit string  a unit token: "target", "mouseover", "nameplate3"
---@return table|nil estimate  as from MobValue.For
function MobValue.ForUnit(unit)
    if not UnitExists(unit) or not UnitCanAttack("player", unit) then
        return nil
    end

    local npcID = ns.Drops.NpcID(UnitGUID(unit))
    if not npcID then
        return nil
    end

    local level = UnitLevel(unit)
    local creatureType = UnitCreatureType(unit)
    if issecretvalue and (issecretvalue(level) or issecretvalue(creatureType)) then
        level, creatureType = nil, nil
    end
    return MobValue.For(npcID, level, creatureType)
end

--- Whether an estimate rests on enough of the creature's own kills to be
--- shown as it is, without a "~" in front.
---@param estimate table|nil  from MobValue.For
---@return boolean
function MobValue.Confident(estimate)
    return estimate ~= nil and not estimate.guess and estimate.kills >= CONFIDENT_KILLS
end

-- Forgetting -----------------------------------------------------------------

-- One creature's drops changed: its own estimate goes, and so do all the
-- borrowed ones, since any of them might have borrowed from it. A new
-- kind, or a type only now seen, has to find its way into the index.
ns.Subscribe("DROPS_CHANGED", function(npcID)
    estimates[npcID] = nil
    wipe(guesses)
    byType = nil
end)

local function ForgetAll()
    wipe(itemValues)
    wipe(estimates)
    wipe(guesses)
end

ns.Subscribe("PRICES_CHANGED", ForgetAll)

-- Vendor prices the sums were missing have arrived.
ns.Subscribe("ITEM_NAMES_LOADED", ForgetAll)
