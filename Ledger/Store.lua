local _, ns = ...

-- The price ledger: everything Goldwise knows about what things cost, and
-- what they used to cost.
--
-- A whole-market scan returns around thirteen thousand items. Keeping a
-- rich history for all of them would make the saved file enormous, so there
-- are two tiers:
--
--   Tracked items are the ones the player holds or has chosen to follow.
--   Each keeps a daily low, high, last price and quantity for as long as
--   the player has chosen (three months, unless they change it), plus its
--   most recent individual readings.
--
--   Everything else is kept as one compact snapshot per day for a short
--   while. That's enough to price a random drop, and to give an item some
--   history the moment it becomes tracked.
--
-- All of it is filed per market. See Market/Identity.lua.

local Ledger = {}
ns.Ledger = Ledger

-- Individual readings kept per tracked item, newest last.
local RECENT_LIMIT = 40

-- Positions in a tracked item's day record. Stored as a plain list because
-- there can be thousands of these in the saved file.
local LOW, HIGH, LAST, QUANTITY = 1, 2, 3, 4

-- Newest known price of every item, per market, held in memory only:
--   latest[marketKey][itemID] = { price, quantity }
-- Rebuilt from the most recent saved snapshot the first time it's needed.
local latest = {}

--- Today as a whole number of days. Server time, so it doesn't depend on
--- the player's clock or time zone.
---@return number day
function Ledger.Today()
    return math.floor(GetServerTime() / ns.SECONDS_PER_DAY)
end

-- Snapshots ----------------------------------------------------------------

-- A snapshot is one long string: ",itemID:price:quantity" for every item.
-- The comma in front of every entry, including the first, means a single
-- item can be found with a plain text search instead of decoding the lot.

local function EncodeSnapshot(prices)
    local parts = {}
    for itemID, entry in pairs(prices) do
        -- %.0f rather than %d: the client's %d is limited to 32 bits.
        parts[#parts + 1] = ("%.0f:%.0f:%.0f"):format(itemID, entry[1], entry[2])
    end
    return "," .. table.concat(parts, ",")
end

local function DecodeSnapshot(snapshot)
    local prices = {}
    for itemID, price, quantity in snapshot:gmatch(",(%d+):(%d+):(%d+)") do
        prices[tonumber(itemID)] = { tonumber(price), tonumber(quantity) }
    end
    return prices
end

local function FindInSnapshot(snapshot, itemID)
    -- A plain-text search for the item's marker, then a pattern anchored
    -- right after it. Letting the pattern do the searching is far slower
    -- on a string this long.
    local _, markerEnd = snapshot:find("," .. itemID .. ":", 1, true)
    if not markerEnd then
        return nil
    end

    local price, quantity = snapshot:match("^(%d+):(%d+)", markerEnd + 1)
    return tonumber(price), tonumber(quantity)
end

local function NewestDay(market)
    local newest
    for day in pairs(market.daily) do
        if not newest or day > newest then
            newest = day
        end
    end
    return newest
end

local function LatestPrices(marketKey)
    if not latest[marketKey] then
        local market = ns.MarketData(marketKey)
        local day = NewestDay(market)
        latest[marketKey] = day and DecodeSnapshot(market.daily[day]) or {}
    end
    return latest[marketKey]
end

-- Tracked items --------------------------------------------------------------

local function AddReading(record, day, now, price, quantity)
    local today = record.days[day]
    if today then
        today[LOW] = math.min(today[LOW], price)
        today[HIGH] = math.max(today[HIGH], price)
        today[LAST] = price
        today[QUANTITY] = quantity
    else
        record.days[day] = { price, price, price, quantity }
    end

    table.insert(record.recent, { now, price, quantity })
    while #record.recent > RECENT_LIMIT do
        table.remove(record.recent, 1)
    end
end

---@param marketKey string
---@param itemID number
---@return boolean
function Ledger.IsTracked(marketKey, itemID)
    return ns.MarketData(marketKey).tracked[itemID] ~= nil
end

--- Starts keeping full history for an item.
--- Whatever the daily snapshots already know about it is copied in, so a
--- newly tracked item doesn't start with an empty chart.
---@param marketKey string
---@param itemID number
function Ledger.Track(marketKey, itemID)
    local market = ns.MarketData(marketKey)
    if market.tracked[itemID] then
        return
    end

    local record = { days = {}, recent = {} }
    for day, snapshot in pairs(market.daily) do
        local price, quantity = FindInSnapshot(snapshot, itemID)
        if price then
            record.days[day] = { price, price, price, quantity }
        end
    end
    market.tracked[itemID] = record
end

-- Recording ------------------------------------------------------------------

-- Browse results come back one row per item variant, so gear with random
-- suffixes shows up several times under one item ID. We keep the cheapest
-- and add up the quantities. Telling the variants apart is a job for later.
local function CollapseRows(rows)
    local prices = {}
    for _, row in ipairs(rows) do
        local itemID = row.itemKey.itemID
        local price = row.minPrice

        -- A price of zero means bid-only listings with no buyout. Nothing
        -- useful to learn from those.
        if price and price > 0 then
            local entry = prices[itemID]
            if not entry then
                prices[itemID] = { price, row.totalQuantity }
            else
                entry[1] = math.min(entry[1], price)
                entry[2] = entry[2] + row.totalQuantity
            end
        end
    end
    return prices
end

local function DropOldSnapshots(market, today)
    local oldest = today - ns.settings.marketDays
    for day in pairs(market.daily) do
        if day <= oldest then
            market.daily[day] = nil
        end
    end
end

--- Files the results of an auction house browse search.
---@param marketKey string
---@param rows table  BrowseResultInfo[] from C_AuctionHouse.GetBrowseResults
---@param wholeMarket boolean  true if the search covered every item, in
---        which case it also becomes today's snapshot
function Ledger.RecordScan(marketKey, rows, wholeMarket)
    Ledger.RecordPrices(marketKey, CollapseRows(rows), wholeMarket)
end

--- Files a set of prices, however they were gathered.
---@param marketKey string
---@param prices table  [itemID] = { price, quantity }
---@param wholeMarket boolean  true if this covers every item on the market
function Ledger.RecordPrices(marketKey, prices, wholeMarket)
    local market = ns.MarketData(marketKey)
    local now = GetServerTime()
    local today = Ledger.Today()

    if wholeMarket then
        latest[marketKey] = prices
        market.daily[today] = EncodeSnapshot(prices)
        market.lastScan = now
        DropOldSnapshots(market, today)
    else
        local known = LatestPrices(marketKey)
        for itemID, entry in pairs(prices) do
            known[itemID] = entry
        end
    end

    for itemID, record in pairs(market.tracked) do
        local entry = prices[itemID]
        if entry then
            AddReading(record, today, now, entry[1], entry[2])
        end
    end

    ns.Publish("PRICES_CHANGED", marketKey)
end

-- Price depth ------------------------------------------------------------------

-- A deep scan sees every auction, so for tracked items it can say how many
-- are listed at each of the cheapest prices. Only the latest is kept.

--- Replaces the price depth of every tracked item in a market with what a
--- deep scan just saw. Items the scan found none of lose theirs: an old
--- picture of the order book is worse than none.
---@param marketKey string
---@param depths table  [itemID] = { levels = { { price, quantity }, ... },
---        higher = how many more are listed above those prices }
function Ledger.SetDepths(marketKey, depths)
    local now = GetServerTime()

    for itemID, record in pairs(ns.MarketData(marketKey).tracked) do
        local depth = depths[itemID]
        if depth then
            record.depth = { at = now, levels = depth.levels, higher = depth.higher }
        else
            record.depth = nil
        end
    end
end

--- What a deep scan last saw of an item's cheapest listings.
---@param marketKey string
---@param itemID number
---@return table|nil depth  { at, levels = { { price, quantity }, ... }, higher }
function Ledger.Depth(marketKey, itemID)
    local record = ns.MarketData(marketKey).tracked[itemID]
    return record and record.depth
end

-- Reading ----------------------------------------------------------------------

-- Where a price came from, for anything that wants to say so.
Ledger.OWN = "own" -- the player's own game read it at the auction house
Ledger.PLAYERS = "players" -- another Goldwise player's game did
Ledger.FEED = "feed" -- the companion prices addon

--- The newest price we have for an item, from whichever source has one.
---
--- The player's own readings come first, unless another player has told us
--- something more recent. The feed answers when nobody has anything, or
--- when what we have is more than a day staler than what it has.
---@param marketKey string
---@param itemID number
---@return number|nil price     lowest buyout per unit, in copper
---@return number|nil quantity  how many were listed
---@return number|nil seenAt    server time of the reading
---@return string|nil source    Ledger.OWN, Ledger.PLAYERS or Ledger.FEED
function Ledger.Price(marketKey, itemID)
    local price, quantity, seenAt = Ledger.LocalPrice(marketKey, itemID)
    local source = price and Ledger.OWN

    local heard, heardQuantity, heardAt = ns.Network.Price(marketKey, itemID)
    if heard and (not price or heardAt > (seenAt or 0)) then
        price, quantity, seenAt, source = heard, heardQuantity, heardAt, Ledger.PLAYERS
    end

    -- A reading taken in the game is first-hand, so it wins a close call.
    -- But a price from last week shouldn't stand while the feed has
    -- today's.
    local fed, fedQuantity, fedAt = ns.Feed.Price(marketKey, itemID)
    if fed and (not price or fedAt - (seenAt or 0) > ns.SECONDS_PER_DAY) then
        return fed, fedQuantity, fedAt, Ledger.FEED
    end

    return price, quantity, seenAt, source
end

--- The newest price from the player's own scans only.
---@param marketKey string
---@param itemID number
---@return number|nil price
---@return number|nil quantity
---@return number|nil seenAt
function Ledger.LocalPrice(marketKey, itemID)
    local market = ns.MarketData(marketKey)

    local record = market.tracked[itemID]
    local reading = record and record.recent[#record.recent]
    if reading then
        -- If a later whole-market scan didn't find the item at all, the
        -- old price is still the best guide we have, but nobody is
        -- selling any right now.
        local soldOut = market.lastScan
            and market.lastScan > reading[1]
            and not LatestPrices(marketKey)[itemID]

        return reading[2], soldOut and 0 or reading[3], reading[1]
    end

    local entry = LatestPrices(marketKey)[itemID]
    if entry then
        return entry[1], entry[2], market.lastScan
    end

    -- Followed, absent from the latest scan, and with no reading of its
    -- own yet: all we have is what older snapshots said when we started
    -- following it. Treat that like any other sold-out item.
    if record then
        local newest
        for day in pairs(record.days) do
            if not newest or day > newest then
                newest = day
            end
        end
        if newest then
            return record.days[newest][LAST], 0, newest * ns.SECONDS_PER_DAY
        end
    end
end

--- Daily prices for an item, oldest first. Days with no data are left out.
---@param marketKey string
---@param itemID number
---@param numDays number  how far back to look, counting today
---@return table history  list of { day, low, high, last, quantity }
function Ledger.History(marketKey, itemID, numDays)
    local market = ns.MarketData(marketKey)
    local record = market.tracked[itemID]
    local feedDays = ns.Feed.Days(marketKey, itemID)
    local today = Ledger.Today()
    local history = {}

    -- A day known only as a single price.
    local function AddFlatDay(day, price, quantity, fromFeed)
        table.insert(history, {
            day = day,
            low = price,
            high = price,
            last = price,
            quantity = quantity,
            fromFeed = fromFeed,
        })
    end

    for day = today - numDays + 1, today do
        -- The player's own readings come first: a tracked item's daily
        -- record, or failing that a whole-market snapshot from that day.
        local entry = record and record.days[day]
        local price, quantity
        if not entry and not record and market.daily[day] then
            price, quantity = FindInSnapshot(market.daily[day], itemID)
        end

        if entry then
            table.insert(history, {
                day = day,
                low = entry[LOW],
                high = entry[HIGH],
                last = entry[LAST],
                quantity = entry[QUANTITY],
            })
        elseif price then
            AddFlatDay(day, price, quantity)
        elseif feedDays and feedDays[day] then
            -- A day they weren't at the auction house. The feed was.
            AddFlatDay(day, feedDays[day], 0, true)
        end
    end

    return history
end

--- When the given market last had a whole-market scan.
---@param marketKey string
---@return number|nil serverTime
function Ledger.LastScan(marketKey)
    return ns.MarketData(marketKey).lastScan
end

-- Housekeeping -----------------------------------------------------------------

-- Once per login, drop tracked history older than the player wants kept.
-- Only at login, and not the moment the setting changes, so a slip of the
-- mouse in the options can't throw away months of prices.
ns.OnEvent("PLAYER_LOGIN", function()
    local oldestDay = Ledger.Today() - ns.settings.historyDays
    local oldestTime = GetServerTime() - ns.settings.historyDays * ns.SECONDS_PER_DAY

    for _, market in pairs(ns.db.markets) do
        for _, record in pairs(market.tracked or {}) do
            for day in pairs(record.days) do
                if day <= oldestDay then
                    record.days[day] = nil
                end
            end

            -- Individual readings are newest last, so the stale ones are
            -- at the front.
            while record.recent[1] and record.recent[1][1] < oldestTime do
                table.remove(record.recent, 1)
            end
        end
    end
end)
