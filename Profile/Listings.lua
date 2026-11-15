local _, ns = ...

-- What the player has up for auction.
--
-- Something listed hasn't been sold. It's still the player's until it
-- sells or comes back, so the session tracker counts it along with the
-- bags rather than as gone the moment it's posted.
--
-- The game only says what's listed while an auction house is open, and
-- only that house's listings, so each house's list is read while it's
-- open and remembered, like the bank. Between visits it keeps itself
-- roughly right: an auction is let go when its time runs out or it's
-- cancelled, and when the letter for a sale is opened, that much of the
-- item goes with it.

local Listings = {}
ns.Listings = Listings

-- How long a listing is taken to run when the game doesn't say at all:
-- the longest an auction can.
local LONGEST_AUCTION = 48 * 3600

-- Listing comes in bursts, so the list is asked for again once things
-- have been quiet for this long.
local SETTLE_DELAY = 1

-- How often to look again, and how many times, when the auction house is
-- too busy to be asked. Our own scans go first; this can wait.
local RETRY_DELAY = 1
local MOST_TRIES = 10

-- The order Blizzard's own Auctions tab asks for, so asking ourselves
-- doesn't reshuffle what the player is looking at there.
local SORTS = {
    { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
}

-- Saved listings, by character key: { markets }, where markets is
-- [marketKey] = { seenAt, auctions } for each auction house visited, and
-- auctions is [auctionID] = { itemID, name, count, endsAt, sold }. sold
-- marks one that has sold but whose letter hasn't been opened yet; it's
-- no longer counted, but kept so its letter is matched to it and not to
-- another listing of the same thing. Times are server time.
local function Saved()
    if type(ns.db.listings) ~= "table" then
        ns.db.listings = {}
    end
    return ns.db.listings
end

local function Markets()
    local key = ns.Characters.CurrentKey()
    local mine = Saved()[key]
    if type(mine) ~= "table" or type(mine.markets) ~= "table" then
        mine = { markets = {} }
        Saved()[key] = mine
    end
    return mine.markets
end

-- The auction house open now, by market key, or nil.
local openMarket
local askPending = false

-- Reading ---------------------------------------------------------------------

-- How long an auction has left: to the second where the game says, the
-- longest of its band where it only says roughly.
local function SecondsLeft(info)
    if info.timeLeftSeconds then
        return info.timeLeftSeconds
    end
    if info.timeLeft and C_AuctionHouse.GetTimeLeftBandInfo then
        local ok, _, longest = pcall(C_AuctionHouse.GetTimeLeftBandInfo, info.timeLeft)
        if ok and longest then
            return longest
        end
    end
    return LONGEST_AUCTION
end

local function Read()
    -- Only a whole list will do: part of one would look like the rest
    -- had sold.
    if not openMarket or not C_AuctionHouse.HasFullOwnedAuctionResults() then
        return
    end

    local now = GetServerTime()
    local auctions = {}
    for index = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
        local itemID = info and info.itemKey and info.itemKey.itemID
        if itemID then
            local name = info.itemLink and info.itemLink:match("%[(.-)%]")
            auctions[info.auctionID] = {
                itemID = itemID,
                name = name or ns.ItemName(itemID),
                count = info.quantity or 1,
                endsAt = now + SecondsLeft(info),
                sold = info.status == Enum.AuctionStatus.Sold or nil,
            }
        end
    end

    Markets()[openMarket] = { seenAt = now, auctions = auctions }
    ns.Publish("BAGS_CHANGED")
    ns.Publish("LISTINGS_READ", openMarket, auctions)
end

-- Whether Blizzard's Auctions tab is showing. It asks for the list itself,
-- and we hear the answer; asking as well would clear what the player has
-- selected there.
local function AuctionsTabShown()
    local frame = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    return frame ~= nil and frame:IsShown()
end

-- Asks the auction house for the player's auctions when it's free. Not
-- through the queue our scans use: this is small, and they come first.
local function Ask(tries)
    askPending = false
    if not openMarket or AuctionsTabShown() then
        return
    end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        if (tries or 0) < MOST_TRIES then
            C_Timer.After(RETRY_DELAY, function()
                Ask((tries or 0) + 1)
            end)
        end
        return
    end
    C_AuctionHouse.QueryOwnedAuctions(SORTS)
end

local function AskSoon()
    if openMarket and not askPending then
        askPending = true
        C_Timer.After(SETTLE_DELAY, function()
            Ask(0)
        end)
    end
end

ns.Subscribe("AUCTION_HOUSE_OPENED", function(marketKey)
    openMarket = marketKey
    AskSoon()
end)

ns.Subscribe("AUCTION_HOUSE_CLOSED", function()
    openMarket = nil
    askPending = false
end)

ns.OnEvent("OWNED_AUCTIONS_UPDATED", Read)
ns.OnEvent("AUCTION_HOUSE_AUCTION_CREATED", AskSoon)

-- A cancelled auction goes back to the player by mail. It's let go at
-- once, by its ID, rather than waiting on the list to be read again.
ns.OnEvent("AUCTION_CANCELED", function(auctionID)
    for _, market in pairs(Markets()) do
        if market.auctions and market.auctions[auctionID] then
            market.auctions[auctionID] = nil
            ns.Publish("BAGS_CHANGED")
            return
        end
    end
end)

-- Between visits ----------------------------------------------------------------

-- An auction's name, for matching it to a letter, which names the item.
local function NameOf(auction)
    return auction.name or C_Item.GetItemNameByID(auction.itemID)
end

-- Whether one listing is a better match for a sale's letter than another:
-- one already seen to have sold first, then the same number as the
-- letter, then the one ending soonest.
local function BetterMatch(auction, best, count)
    if not best then
        return true
    end
    if (auction.sold == true) ~= (best.sold == true) then
        return auction.sold == true
    end
    local exact, bestExact = auction.count == count, best.count == count
    if exact ~= bestExact then
        return exact
    end
    return (auction.endsAt or 0) < (best.endsAt or 0)
end

-- A sale's letter has been opened: that much of the item has gone. The
-- letter names the item and how many, not the auction or the house, so
-- the likeliest listing is chosen. One whose time has run out can't have
-- sold. Part of a larger listing can sell on its own, and then only that
-- part goes.
ns.Subscribe("TRADE_CHANGED", function(kind, _, name, count)
    if kind ~= ns.Trade.SALE or not name then
        return
    end

    local now = GetServerTime()
    local best, bestIn, bestID
    for _, market in pairs(Markets()) do
        for auctionID, auction in pairs(market.auctions or {}) do
            local stillUp = auction.sold or (auction.endsAt or 0) > now
            if stillUp and NameOf(auction) == name and BetterMatch(auction, best, count) then
                best, bestIn, bestID = auction, market.auctions, auctionID
            end
        end
    end
    if not bestID then
        return
    end

    if count and count < best.count and not best.sold then
        best.count = best.count - count
    else
        bestIn[bestID] = nil
    end
    ns.Publish("BAGS_CHANGED")
end)

-- Reading it back ---------------------------------------------------------------

local function Add(byItem, list, auctions, now)
    for _, auction in pairs(auctions or {}) do
        if not auction.sold and (auction.endsAt or 0) > now then
            local holding = byItem[auction.itemID]
            if not holding then
                holding = { itemID = auction.itemID, name = auction.name, count = 0 }
                byItem[auction.itemID] = holding
                table.insert(list, holding)
            end
            holding.count = holding.count + auction.count
        end
    end
end

--- What the player has up for auction and not yet sold, at every house
--- they've listed at, or at one, as a list shaped like Bags.Holdings():
--- { itemID, name, count }. Listings past their time are left out;
--- they're on their way back by mail.
---@param marketKey string|nil  one auction house only
---@return table holdings
function Listings.Holdings(marketKey)
    local now = GetServerTime()
    local byItem, list = {}, {}
    for key, market in pairs(Markets()) do
        if not marketKey or key == marketKey then
            Add(byItem, list, market.auctions, now)
        end
    end
    return list
end

--- The auction houses whose listings have been read, as [marketKey] = true.
---@return table
function Listings.Seen()
    local seen = {}
    for key, market in pairs(Markets()) do
        if market.seenAt then
            seen[key] = true
        end
    end
    return seen
end
