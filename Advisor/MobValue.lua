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

-- Green and better items mostly drop from anything of about the right
-- level, not from one kind of creature. One found in a handful of kills
-- says nothing about how often that creature drops it: a crocolisk that
-- happened to drop two greens in nine kills isn't worth eight times the
-- next one. So an item this good, found on fewer corpses of a kind than
-- this, is put down as a world drop. How often world drops turn up, and
-- what a typical one is worth, come from every kill around that level.
local WORLD_QUALITY = Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2
local OWN_DROP_TIMES = 3

-- A creature's own run of luck with world drops is weighed against the
-- rate around its level as if that rate came from this many kills of its
-- own. A few kills lean on the rate around; hundreds speak for themselves.
local PRIOR_KILLS = 10

-- Drops are sold by the stack, not one at a time, so that's how they're
-- judged: the deposit on one linen cloth would rule it out, and twenty
-- of them sell happily. Twenty is the largest stack of most drops.
local LARGEST_LOT = 20

-- What one of each item is worth: [itemID] = { at, value, vendor, quality }.
local itemValues = {}

-- World drops around each level and type: [key] = { at, chance, each,
-- vendor }.
local worldDrops = {}

-- Estimates from a creature's own kills, by npcID, and those borrowed
-- from similar creatures, by npcID, level and type. Each is { at,
-- estimate }, where estimate is false when there was nothing to go on.
local estimates = {}
local guesses = {}

-- Kinds of creature on record by type, [type] = list of npcIDs, for
-- finding similar ones. Made when first needed.
local byType

-- Items ---------------------------------------------------------------------

-- What one of an item fetches, what a vendor would pay for it, and its
-- quality (nil until the client has it).
local function ItemValue(itemID)
    local now = GetTime()
    local known = itemValues[itemID]
    if known and now - known.at < CACHE_FOR then
        return known.value, known.vendor, known.quality
    end

    local _, _, quality, _, _, _, _, stackCount, _, _, sellPrice = C_Item.GetItemInfo(itemID)
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

    itemValues[itemID] = { at = now, value = value, vendor = vendor, quality = quality }
    return value, vendor, quality
end

-- Whether a tally of { times, quantity } is a world drop rather than the
-- creature's own: green or better, and found on only a corpse or two.
local function IsWorldDrop(itemID, tally)
    if (tally[1] or 0) >= OWN_DROP_TIMES then
        return false
    end
    local _, _, quality = ItemValue(itemID)
    return quality ~= nil and quality >= WORLD_QUALITY
end

local function Median(list)
    if #list == 0 then
        return 0
    end
    table.sort(list)
    local middle = (#list + 1) / 2
    return (list[math.floor(middle)] + list[math.ceil(middle)]) / 2
end

local function NewFinds()
    return { finds = 0, values = {}, vendors = {} }
end

-- Splits one creature's tallies into its own drops, which are returned,
-- and the world drops found on it, which are added to finds: how many,
-- and what each find was worth, both ways. A world drop is judged by the
-- one creature's tally, never a pooled one, so three beasts that each
-- dropped the same green once are three world drops, not a drop of one.
local function Split(tallies, finds)
    local own = {}
    for itemID, tally in pairs(tallies or {}) do
        local times = tally[1] or 0
        if times > 0 and IsWorldDrop(itemID, tally) then
            local each, vendor = ItemValue(itemID)
            local perFind = (tally[2] or times) / times
            finds.finds = finds.finds + times
            for _ = 1, times do
                table.insert(finds.values, each * perFind)
                table.insert(finds.vendors, vendor * perFind)
            end
        elseif times > 0 then
            own[itemID] = tally
        end
    end
    return own
end

-- Every creature on record, kills and world drops added up by level and
-- type: [level][type] = { kills, finds }. Made in one pass over the
-- records and kept until they change, so a screen full of nameplates
-- doesn't each go through them all again.
local bands

local function Bands()
    if bands and GetTime() - bands.at < CACHE_FOR then
        return bands
    end
    local byLevel = {}
    for _, drops in pairs(ns.Drops.All()) do
        if type(drops) == "table" and (drops.kills or 0) > 0 and drops.level then
            local kinds = byLevel[drops.level] or {}
            byLevel[drops.level] = kinds
            local kind = drops.type or "?"
            local band = kinds[kind] or { kills = 0, finds = NewFinds() }
            kinds[kind] = band
            band.kills = band.kills + drops.kills
            Split(drops.items, band.finds)
        end
    end
    bands = { at = GetTime(), byLevel = byLevel }
    return bands
end

-- How often a world drop turns up per kill around a level, and what a
-- typical one fetches, both ways. The median rather than the average, so
-- one dear blue doesn't speak for every green. Creatures of the same type
-- only, when the type is known: beasts and humanoids don't drop alike.
-- The creature being judged is left out of how often, so its own luck
-- isn't counted twice. Nil when nothing else like it around that level
-- has been killed.
local function WorldDrops(level, creatureType, exceptID)
    if not level or level <= 0 then
        return nil
    end
    level = math.floor(level)

    local key = ("%d:%s"):format(level, tostring(creatureType))
    local around = worldDrops[key]
    if not around or GetTime() - around.at >= CACHE_FOR then
        local kills, finds, values, vendors = 0, 0, {}, {}
        local byLevel = Bands().byLevel
        for near = level - LEVEL_SPREAD, level + LEVEL_SPREAD do
            for kind, band in pairs(byLevel[near] or {}) do
                if not creatureType or kind == creatureType then
                    kills = kills + band.kills
                    finds = finds + band.finds.finds
                    for index, value in ipairs(band.finds.values) do
                        table.insert(values, value)
                        table.insert(vendors, band.finds.vendors[index])
                    end
                end
            end
        end
        around = {
            at = GetTime(),
            kills = kills,
            finds = finds,
            each = Median(values),
            vendor = Median(vendors),
        }
        worldDrops[key] = around
    end

    local kills, finds = around.kills, around.finds
    local own = exceptID and ns.Drops.Get(exceptID)
    if
        own
        and own.level
        and math.abs(own.level - level) <= LEVEL_SPREAD
        and (not creatureType or (own.type or "?") == creatureType)
    then
        local ownFinds = NewFinds()
        Split(own.items, ownFinds)
        kills = kills - (own.kills or 0)
        finds = finds - ownFinds.finds
    end
    if kills <= 0 then
        return nil
    end
    return {
        chance = math.min(1, math.max(0, finds) / kills),
        each = around.each,
        vendor = around.vendor,
    }
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
--
-- With finds, from Split, the world drops stand as one entry in the list,
-- { world = true }: how often, from these finds weighed against the rate
-- around the level, and what a typical one fetches there. npcID is the
-- creature's, left out of that rate.
local function List(tallies, openings, finds, level, creatureType, npcID)
    local list, worth, vendorWorth = {}, 0, 0
    if openings <= 0 then
        return list, worth, vendorWorth
    end

    for itemID, tally in pairs(tallies) do
        local times = tally[1] or 0
        local quantity = tally[2] or times
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

    if finds then
        local around = WorldDrops(level, creatureType, npcID)
        local world
        if around and (around.chance > 0 or finds.finds > 0) then
            -- Weighed against the rate around, even when that's none: a
            -- green from a kind that rarely drops one is the luckier for
            -- it. What one fetches is a typical one's price around here,
            -- or the creature's own if none have dropped around here.
            local typical = around.chance > 0
            world = {
                chance = math.min(
                    1,
                    (finds.finds + PRIOR_KILLS * around.chance) / (openings + PRIOR_KILLS)
                ),
                each = typical and around.each or Median(finds.values),
                vendor = typical and around.vendor or Median(finds.vendors),
            }
        elseif not around and finds.finds > 0 then
            world = {
                chance = math.min(1, finds.finds / openings),
                each = Median(finds.values),
                vendor = Median(finds.vendors),
            }
        end
        if world then
            table.insert(list, {
                itemID = 0,
                world = true,
                chance = world.chance,
                quantity = 1,
                each = world.each,
            })
            worth = worth + world.chance * world.each
            vendorWorth = vendorWorth + world.chance * world.vendor
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
    return {
        kills = 0,
        skins = 0,
        copper = 0,
        items = {},
        finds = NewFinds(),
        skinned = {},
        kinds = 0,
    }
end

-- items keeps each creature's own drops; its world drops go to finds.
local function AddToPool(pool, drops)
    pool.kills = pool.kills + (drops.kills or 0)
    pool.skins = pool.skins + (drops.skins or 0)
    pool.copper = pool.copper + (drops.copper or 0)
    AddTallies(pool.items, Split(drops.items, pool.finds))
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
-- it has one, for the kills and skins the estimate reports. level and
-- creatureType are the creature's, and npcID which it is, for weighing
-- its world drops.
local function Estimate(pool, own, guess, level, creatureType, npcID)
    if pool.kills <= 0 then
        return nil
    end

    local copper = pool.copper / pool.kills
    local drops, dropWorth, dropVendor =
        List(pool.items, pool.kills, pool.finds, level, creatureType, npcID)
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
        local finds = NewFinds()
        local items = Split(own and own.items, finds)
        drops = List(items, kills, finds, level, creatureType, npcID)
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
---        when it drops, and each is what one is worth. One entry in drops
---        may be { world = true } in place of an item: the green and
---        better world drops, taken together, with itemID 0. skinned is per
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
        -- Its own record's level and type, or failing those, the unit's:
        -- kills looted without ever pointing at the creature leave none.
        local ownLevel = own.level or (level and level > 0 and level) or nil
        return Keep(
            estimates,
            npcID,
            Estimate(pool, own, false, ownLevel, own.type or creatureType, npcID)
        )
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
    return Keep(guesses, key, Estimate(pool, own, guess, level, creatureType, npcID))
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

-- One creature's drops changed. Every estimate goes: the borrowed ones
-- might have borrowed from it, and any around its level lean on the world
-- drops it adds to. A new kind, or a type only now seen, has to find its
-- way into the index.
ns.Subscribe("DROPS_CHANGED", function()
    wipe(estimates)
    wipe(worldDrops)
    wipe(guesses)
    bands = nil
    byType = nil
end)

local function ForgetAll()
    wipe(itemValues)
    wipe(worldDrops)
    bands = nil
    wipe(estimates)
    wipe(guesses)
end

ns.Subscribe("PRICES_CHANGED", ForgetAll)

-- Vendor prices the sums were missing have arrived.
ns.Subscribe("ITEM_NAMES_LOADED", ForgetAll)
