local _, ns = ...

-- Which auction house are we talking about?
--
-- Forever has no realms. Everyone in a region on the same ruleset shares a
-- world, and each faction in that world has its own auction house, plus a
-- neutral one in the goblin towns. A price only means something for one of
-- those markets, so every price Goldwise stores is filed under a key like
-- "US-PvE-Alliance".

local Market = {}
ns.Market = Market

-- Zones whose only auction house is the neutral one: Stranglethorn Vale
-- (Booty Bay), Tanaris (Gadgetzan) and Winterspring (Everlook).
local NEUTRAL_ZONES = {
    [1434] = true,
    [1446] = true,
    [1452] = true,
}

-- The market the open auction house belongs to, or nil when it's closed.
local openMarket

-- The API has no "which ruleset am I on" call, but the realm name ends
-- with it: "CAMWOW US1 Realm 1 PvE", "CAMWOW EU4 Realm 4 PvP". The part
-- before it changes from one cluster of servers to the next and means
-- nothing to the auction house.
--
-- A roleplay world ends "RP". A roleplay-PvP one is listed by Blizzard as
-- "RP PvP", two words, and has been seen written "RPPVP" and "RP-PvP".
-- The last word alone would file it with the PvP worlds, whose auction
-- house it doesn't share, so all three are read as one name.
local function Ruleset()
    local realm = GetRealmName() or ""
    local last = realm:match("(%S+)%s*$")
    if not last then
        return "Unknown"
    end

    local before = realm:match("(%S+)%s+%S+%s*$") or ""
    local joined = last:upper():gsub("%-", "")
    if joined == "RPPVP" or (joined == "PVP" and before:upper() == "RP") then
        return "RP-PvP"
    end
    return last
end

local function Key(faction)
    return ("%s-%s-%s"):format(GetCurrentRegionName() or "??", Ruleset(), faction)
end

--- The player's own faction market. This is the one that matters when
--- they're out in the world wondering what something is worth.
---@return string marketKey
function Market.Home()
    return Key(UnitFactionGroup("player") or "Neutral")
end

--- The market for the auction house at the player's current location.
---@return string marketKey
function Market.Here()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID and NEUTRAL_ZONES[mapID] then
        return Key("Neutral")
    end
    return Market.Home()
end

--- The market to read and write prices for right now: the open auction
--- house if there is one, otherwise home.
---@return string marketKey
function Market.Current()
    return openMarket or Market.Home()
end

--- Whether the auction house window is open.
---@return boolean
function Market.IsOpen()
    return openMarket ~= nil
end

--- A short label for the market, fit to show the player.
---@param marketKey string
---@return string  e.g. "Alliance, PvE, US"
function Market.Label(marketKey)
    -- Region first, faction last, and whatever sits between is the
    -- ruleset, which might itself contain a hyphen.
    local region, ruleset, faction = marketKey:match("^(.-)%-(.+)%-([^-]+)$")
    return ("%s, %s, %s"):format(faction or "?", ruleset or "?", region or "?")
end

--- The share of a sale this market's auction house keeps.
---@param marketKey string
---@return number cut  0.05 means five percent
function Market.Cut(marketKey)
    if marketKey:match("%-Neutral$") then
        return ns.NEUTRAL_AUCTION_CUT
    end
    return ns.AUCTION_CUT
end

ns.OnEvent("AUCTION_HOUSE_SHOW", function()
    openMarket = Market.Here()
    ns.Publish("AUCTION_HOUSE_OPENED", openMarket)
end)

ns.OnEvent("AUCTION_HOUSE_CLOSED", function()
    -- The client can fire this twice for one close.
    if not openMarket then
        return
    end

    openMarket = nil
    ns.Publish("AUCTION_HOUSE_CLOSED")
end)
