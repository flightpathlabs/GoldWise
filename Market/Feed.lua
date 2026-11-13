local _, ns = ...

-- The price feed: recent prices for every auction house, delivered as a
-- companion addon (Goldwise Prices) that the player's addon manager keeps
-- up to date.
--
-- It exists so a new install isn't empty. Before the player has been near
-- an auction house, the feed already knows what things cost and how the
-- price has moved over the last month. Once they have scanned for
-- themselves, their own readings come first and the feed only fills in
-- the days they weren't there.
--
-- The feed's data comes from Blizzard's Game Data API. Blizzard's terms
-- ask that this is made plain wherever the data is shown, so anything
-- built on a feed price says where it came from. Feed.SOURCE is the
-- wording to use.
--
-- Goldwise works without the feed. When it isn't installed, every lookup
-- here comes back empty.

local Feed = {}
ns.Feed = Feed

Feed.SOURCE = "Blizzard's Game Data API"

-- Which feed house serves which market.
--
-- Blizzard numbers the houses the same way in every region, and doesn't
-- say which ruleset each belongs to. These are the ones we've confirmed
-- ourselves, by matching an in-game scan.
local KNOWN_HOUSES = {
    ["US-PvE-Alliance"] = "US-111",
    ["US-PvE-Horde"] = "US-114",
    ["US-PvE-Neutral"] = "US-117",
}

-- And these rest on what other people have confirmed and published, by
-- comparing a house's prices with what they saw in game: a PvP house in
-- America and one in Europe, and Europe's PvE Horde house. The rest of
-- each row follows from Blizzard's numbering, which runs PvP then PvE
-- within each faction. Oceanic players are in the American region and
-- share its houses.
--
-- Being second-hand, they only stand until the player's own scan has
-- picked a house (see Learn below), and that pick wins if it differs.
--
-- Not here: the roleplay and roleplay-PvP houses (119 to 121 and 123 to
-- 125; nobody has published which set is which), and Korea and Taiwan,
-- where nobody has checked a house against the game. Those are worked
-- out on the player's machine after their first scan.
local REPORTED_HOUSES = {
    ["US-PvP-Alliance"] = "US-110",
    ["US-PvP-Horde"] = "US-113",
    ["US-PvP-Neutral"] = "US-116",
    ["EU-PvE-Alliance"] = "EU-111",
    ["EU-PvE-Horde"] = "EU-114",
    ["EU-PvE-Neutral"] = "EU-117",
    ["EU-PvP-Alliance"] = "EU-110",
    ["EU-PvP-Horde"] = "EU-113",
    ["EU-PvP-Neutral"] = "EU-116",
}

-- How alike a feed house and our own scan must be before we believe
-- they're the same market: this share of the house's busiest items priced
-- within PRICE_TOLERANCE of ours, and clear of the next best by a margin.
--
-- The tolerance has to be tight. Rulesets of the same faction price most
-- things within a third of each other, so a loose one can't tell them
-- apart; at 15% a neighbouring house scores about half what the right
-- one does.
local MATCH_NEEDED = 0.6
local MATCH_MARGIN = 0.15
local PRICE_TOLERANCE = 0.15

-- House addons that refused to load, so we only try once.
local unavailable = {}

--- Whether the companion addon is present in a format we understand.
---@return boolean
function Feed.IsInstalled()
    return type(GoldwisePricesIndex) == "table" and GoldwisePricesIndex.format == 1
end

local function HouseKeyFor(marketKey)
    -- A house we've confirmed ourselves outranks one worked out on the
    -- fly, and that outranks one we only have somebody's word for.
    local learned = ns.db.feedHouses and ns.db.feedHouses[marketKey]
    return KNOWN_HOUSES[marketKey] or learned or REPORTED_HOUSES[marketKey]
end

-- The feed's data for a market, loading its addon if this is the first
-- time it's been asked for. Each house is a separate load-on-demand addon,
-- so a player only ever pays for the one or two they use.
local function HouseData(marketKey)
    if not Feed.IsInstalled() then
        return nil
    end

    local houseKey = HouseKeyFor(marketKey)
    local entry = houseKey and GoldwisePricesIndex.houses[houseKey]
    if not entry or unavailable[houseKey] then
        return nil
    end

    if not (GoldwisePricesData and GoldwisePricesData[houseKey]) then
        if not C_AddOns.LoadAddOn(entry.addon) then
            unavailable[houseKey] = true
            ns.Log("feed: could not load %s", entry.addon)
            return nil
        end
    end
    return GoldwisePricesData and GoldwisePricesData[houseKey]
end

-- Reading one item ------------------------------------------------------------

-- An item in the feed is ",<itemID>:<price>.<price>...:<quantity>": one
-- price slot per day from the house's firstDay to its lastDay, empty where
-- there was no reading, then how many are listed now.

local function FindItem(data, itemID)
    local marker = "," .. itemID .. ":"
    for _, chunk in ipairs(data.items) do
        local _, markerEnd = chunk:find(marker, 1, true)
        if markerEnd then
            local series, quantity = chunk:match("^([%d%.]*):(%d+)", markerEnd + 1)
            return series, tonumber(quantity)
        end
    end
end

-- The same item is asked about many times in a row (a tooltip redraws
-- several times a second), so keep the last answer.
local cache = {}

local function Lookup(marketKey, itemID)
    if cache.marketKey == marketKey and cache.itemID == itemID then
        return cache
    end

    cache.marketKey = marketKey
    cache.itemID = itemID
    cache.days = nil
    cache.newestDay = nil
    cache.quantity = nil
    cache.updated = nil

    local data = HouseData(marketKey)
    local series, quantity
    if data then
        series, quantity = FindItem(data, itemID)
    end
    if not series then
        return cache
    end

    local days = {}
    local day = data.firstDay
    -- The trailing dot makes every slot, including the last, end in one.
    for value in (series .. "."):gmatch("(%d*)%.") do
        if value ~= "" then
            days[day] = tonumber(value)
            cache.newestDay = day
        end
        day = day + 1
    end

    cache.days = days
    cache.quantity = quantity

    -- The feed goes on carrying an item's last price for a while after it
    -- stops being listed. That price is as old as the day it was read,
    -- not as new as the feed.
    if cache.newestDay and cache.newestDay < data.lastDay then
        cache.updated = (cache.newestDay + 1) * ns.SECONDS_PER_DAY - 1
    else
        cache.updated = data.updated
    end
    return cache
end

--- The feed's prices for an item, by day.
---@param marketKey string
---@param itemID number
---@return table|nil days  [day] = lowest price that day, or nil if the
---        feed has nothing for this item
function Feed.Days(marketKey, itemID)
    return Lookup(marketKey, itemID).days
end

--- The feed's newest price for an item.
---@param marketKey string
---@param itemID number
---@return number|nil price     lowest buyout per unit, in copper
---@return number|nil quantity  how many were listed when the feed last read
---@return number|nil updated   server time the price dates from
function Feed.Price(marketKey, itemID)
    local found = Lookup(marketKey, itemID)
    if not found.days then
        return nil
    end
    return found.days[found.newestDay], found.quantity, found.updated
end

--- When the feed last read this market.
---@param marketKey string
---@return number|nil serverTime  nil if the feed doesn't cover it
function Feed.UpdatedAt(marketKey)
    local data = HouseData(marketKey)
    return data and data.updated
end

-- Working out which house is ours ---------------------------------------------

-- The feed lists every house in the region but can't say which ruleset
-- each belongs to. We don't need it to: after a full scan we know what
-- our own market looks like, and each house in the index comes with its
-- busiest items and their prices. The house that agrees with us is ours.

local function Resemblance(entry, marketKey)
    local agree, total = 0, 0
    for itemID, price in entry.fingerprint:gmatch(",(%d+):(%d+):%d+") do
        total = total + 1
        local ours = ns.Ledger.LocalPrice(marketKey, tonumber(itemID))
        if ours and math.abs(ours / tonumber(price) - 1) <= PRICE_TOLERANCE then
            agree = agree + 1
        end
    end
    return total > 0 and agree / total or 0
end

local function Learn()
    if not Feed.IsInstalled() then
        return
    end

    local marketKey = ns.Market.Current()
    local faction = marketKey:match("([^-]+)$")

    local best, bestScore, nextScore = nil, 0, 0
    for houseKey, entry in pairs(GoldwisePricesIndex.houses) do
        if entry.faction == faction then
            local score = Resemblance(entry, marketKey)
            if score > bestScore then
                best, bestScore, nextScore = houseKey, score, bestScore
            elseif score > nextScore then
                nextScore = score
            end
        end
    end

    ns.Log(
        "feed: best match for %s is %s (%.2f, next %.2f)",
        marketKey,
        tostring(best),
        bestScore,
        nextScore
    )

    if best and bestScore >= MATCH_NEEDED and bestScore - nextScore >= MATCH_MARGIN then
        ns.db.feedHouses = ns.db.feedHouses or {}
        if ns.db.feedHouses[marketKey] ~= best then
            ns.db.feedHouses[marketKey] = best
            cache.itemID = nil
            ns.Publish("PRICES_CHANGED", marketKey)
        end
    end
end

-- A finished scan of either kind has just covered the whole market.
ns.Subscribe("SCAN_FINISHED", Learn)

-- Load the home market's house a few seconds after login, so the cost of
-- reading it isn't paid on the first tooltip the player hovers.
ns.OnEvent("PLAYER_LOGIN", function()
    C_Timer.After(5, function()
        HouseData(ns.Market.Home())
    end)
end)
