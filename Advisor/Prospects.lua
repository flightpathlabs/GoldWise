local _, ns = ...

-- Works out what the player could go and gather for gold, given their
-- level and professions, and ranks it by what it sells for today.
--
-- Like the rest of Advisor, this takes facts in and hands a list back. It
-- doesn't ask the game anything itself.
--
-- It ranks by price per unit, because that's what we can measure. It can't
-- yet say how fast something drops or how quickly it sells, so the top row
-- is "worth the most each", not "the most gold per hour". The tab says so.

local Prospects = {}
ns.Prospects = Prospects

local Gathering = ns.Gathering

-- How far above their own level a player can comfortably farm, and how far
-- below before it stops being worth their time.
local LEVELS_ABOVE = 2
local LEVELS_BELOW = 8

-- Zones named per prospect.
local MAX_ZONES = 3

local function Overlaps(minA, maxA, minB, maxB)
    return minA <= maxB and minB <= maxA
end

-- The zones where a player of this level would find something that lives
-- in the given level range, closest to their own level first.
local function ZonesFor(source, level, faction)
    local low, high = level - LEVELS_BELOW, level + LEVELS_ABOVE
    local zones = {}

    for _, zone in ipairs(Gathering.ZONES) do
        local welcome = not zone.faction or zone.faction == faction
        local suitsPlayer = Overlaps(zone.minLevel, zone.maxLevel, low, high)
        local hasSource = Overlaps(zone.minLevel, zone.maxLevel, source.minLevel, source.maxLevel)
        if welcome and suitsPlayer and hasSource then
            table.insert(zones, zone)
        end
    end

    -- Nearest the player's own level first, judged by the zone's midpoint.
    -- Ties go by map ID, purely so the order is the same every time.
    table.sort(zones, function(a, b)
        local distanceA = math.abs((a.minLevel + a.maxLevel) / 2 - level)
        local distanceB = math.abs((b.minLevel + b.maxLevel) / 2 - level)
        if distanceA ~= distanceB then
            return distanceA < distanceB
        end
        return a.mapID < b.mapID
    end)

    local mapIDs = {}
    for index = 1, math.min(MAX_ZONES, #zones) do
        mapIDs[index] = zones[index].mapID
    end
    return mapIDs
end

-- Calls visit(source, kind, how) for everything the player is able to
-- gather with the skills they have, whatever level it's found at.
local function ForEachSource(skills, visit)
    for _, source in ipairs(Gathering.CLOTH) do
        visit(source, "Cloth", "Drops from humanoids around level %d to %d.")
    end

    if skills.skinning then
        for _, source in ipairs(Gathering.SKINNING) do
            visit(source, "Skinning", "Skinned from beasts around level %d to %d.")
        end
    end

    local function VisitNodes(sources, kind, skill, how)
        if not skill then
            return
        end
        for _, source in ipairs(sources) do
            if skill >= source.skill then
                visit(source, kind, how)
            end
        end
    end

    VisitNodes(Gathering.MINING, "Mining", skills.mining, "Mined in zones around level %d to %d.")
    VisitNodes(
        Gathering.HERBALISM,
        "Herbalism",
        skills.herbalism,
        "Picked in zones around level %d to %d."
    )
end

local function DearestFirst(a, b)
    if a.price ~= b.price then
        return a.price > b.price
    end
    return a.name < b.name
end

-- One row of either list. Returns nil for something with no known price.
local function Describe(source, kind, how, priceOf)
    local price, listed, seenAt, priceSource = priceOf(source.itemID)
    if not price then
        return nil
    end

    return {
        itemID = source.itemID,
        name = source.name,
        kind = kind,
        how = how:format(source.minLevel, source.maxLevel),
        price = price,
        listed = listed,
        -- Carried along so the item's page can say how old the price is
        -- and who it came from.
        seenAt = seenAt,
        source = priceSource,
    }
end

--- Lists what's worth gathering at the player's level.
---@param profile table with:
---   level    the player's level
---   faction  "Alliance" or "Horde"
---   skills   { skinning = n, mining = n, herbalism = n }, absent if untrained
---@param priceOf fun(itemID: number): number|nil, number|nil, number|nil, string|nil
---        returns what Ledger.Price does: the price per unit, the quantity
---        listed, when that was read and where it came from
---@return table prospects  list of { itemID, name, kind, how, price, listed,
---        seenAt, source, mapIDs }, dearest first. Items with no known price
---        are left out.
function Prospects.For(profile, priceOf)
    local level = profile.level
    local low, high = level - LEVELS_BELOW, level + LEVELS_ABOVE
    local prospects = {}

    ForEachSource(profile.skills, function(source, kind, how)
        -- Only things found among creatures or zones near the player's level.
        if Overlaps(source.minLevel, source.maxLevel, low, high) then
            local prospect = Describe(source, kind, how, priceOf)
            if prospect then
                prospect.mapIDs = ZonesFor(source, level, profile.faction)
                table.insert(prospects, prospect)
            end
        end
    end)

    table.sort(prospects, DearestFirst)
    return prospects
end

--- Lists what the player could gather in one particular zone.
---@param zone table  an entry of Gathering.ZONES
---@param profile table  as for Prospects.For
---@param priceOf function  as for Prospects.For
---@return table prospects  as from Prospects.For, without mapIDs
function Prospects.InZone(zone, profile, priceOf)
    local prospects = {}

    ForEachSource(profile.skills, function(source, kind, how)
        if Overlaps(source.minLevel, source.maxLevel, zone.minLevel, zone.maxLevel) then
            local prospect = Describe(source, kind, how, priceOf)
            if prospect then
                table.insert(prospects, prospect)
            end
        end
    end)

    table.sort(prospects, DearestFirst)
    return prospects
end

--- The zones the player's side can travel in, for choosing between.
---@param faction string  "Alliance" or "Horde"
---@return table zones  entries of Gathering.ZONES, lowest level first
function Prospects.Zones(faction)
    local zones = {}
    for _, zone in ipairs(Gathering.ZONES) do
        if not zone.faction or zone.faction == faction then
            table.insert(zones, zone)
        end
    end

    table.sort(zones, function(a, b)
        if a.minLevel ~= b.minLevel then
            return a.minLevel < b.minLevel
        end
        return a.mapID < b.mapID
    end)
    return zones
end
