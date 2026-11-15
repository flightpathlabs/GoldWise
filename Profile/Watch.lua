local _, ns = ...

-- Things the player has asked to keep an eye on at the auction house,
-- whether or not they hold any.
--
-- Goldwise already follows the price of everything the player carries. A
-- watched item is followed the same way at every scan, held or not, and
-- has its own list on the Assets tab.

local Watch = {}
ns.Watch = Watch

-- Saved for the whole account: [itemID] = server time it was added.
local function Watched()
    if type(ns.db.watched) ~= "table" then
        ns.db.watched = {}
    end
    return ns.db.watched
end

-- Makes sure a watched item's price is followed in a market. Following is
-- dropped for things with nothing on record for a long while, so this is
-- done again at each login and at each auction house.
local function Follow(itemID, marketKey)
    if marketKey then
        ns.Ledger.Track(marketKey, itemID)
    end
end

--- Whether the player is watching an item.
---@param itemID number
---@return boolean
function Watch.IsWatched(itemID)
    return ns.db ~= nil and Watched()[itemID] ~= nil
end

--- Starts or stops watching an item.
---@param itemID number
---@return boolean watching  whether it's watched now
function Watch.Toggle(itemID)
    local watched = Watched()
    if watched[itemID] then
        watched[itemID] = nil
    else
        watched[itemID] = GetServerTime()
        Follow(itemID, ns.Market.Home())
        Follow(itemID, ns.Market.Current())
        -- Its name and icon, for the list.
        ns.LoadItem(itemID)
    end
    ns.Publish("WATCH_CHANGED", itemID)
    return watched[itemID] ~= nil
end

--- The watched items, oldest added first.
---@return table itemIDs
function Watch.All()
    local list = {}
    for itemID in pairs(Watched()) do
        table.insert(list, itemID)
    end
    table.sort(list, function(a, b)
        return Watched()[a] < Watched()[b]
    end)
    return list
end

-- After the price history is tidied at login, and at any auction house,
-- watched items are followed there.
ns.OnEvent("PLAYER_LOGIN", function()
    if not ns.db then
        return
    end
    for itemID in pairs(Watched()) do
        Follow(itemID, ns.Market.Home())
        ns.LoadItem(itemID)
    end
end)

ns.Subscribe("AUCTION_HOUSE_OPENED", function(marketKey)
    for itemID in pairs(Watched()) do
        Follow(itemID, marketKey)
    end
end)
