local _, ns = ...

-- A small public window onto Goldwise's prices, for other addons.
--
-- Everything else in Goldwise hangs off its private namespace, which other
-- addons can't and shouldn't reach into. This is the one exception: a
-- read-only global with a version number, so an addon such as Creel (the
-- fishing log) can show what a catch fetches at auction without scanning
-- the auction house itself or reading Goldwise's saved data.
--
-- The answer is the same one Goldwise's own screens give: the freshest of
-- the player's own scans, other Goldwise players' prices, the price feed
-- and Auctionator's reading, for the player's home market.
--
-- Callers should check `GoldwiseAPI.version` and call through pcall: the
-- table is only there when Goldwise is loaded, and prices can be missing.

local API = {
    -- Raised only when something here changes in a way an existing caller
    -- would notice. Adding a function doesn't raise it.
    version = 1,
}

--- What one of an item sells for at auction in the player's home market.
---@param itemID number
---@return number|nil copper   nil when Goldwise has no price for it
---@return number|nil seenAt   when the price was seen, as time()
---@return string|nil source   "own", "players", "feed" or "auctionator"
function API.Price(itemID)
    if type(itemID) ~= "number" or not ns.db then
        return nil
    end
    local price, _, seenAt, source = ns.Ledger.Price(ns.Market.Home(), itemID)
    return price, seenAt, source
end

--- Opens Goldwise's window on an item's crafting tree: what it's made from
--- and what it goes into, with prices.
---@param itemID number
---@return boolean opened
function API.ShowCraftTree(itemID)
    if type(itemID) ~= "number" or not ns.db or not ns.ShowCraftTree then
        return false
    end
    ns.ShowCraftTree(itemID)
    return true
end

--- Opens Goldwise's window on an item's price history.
---@param itemID number
---@return boolean opened
function API.ShowItemHistory(itemID)
    if type(itemID) ~= "number" or not ns.db or not ns.ShowItemHistory then
        return false
    end
    ns.ShowItemHistory(itemID)
    return true
end

GoldwiseAPI = API
