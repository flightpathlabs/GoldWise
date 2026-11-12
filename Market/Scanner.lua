local _, ns = ...

-- Reads prices from the auction house.
--
-- The main source is a browse search with no text and no filters, which
-- returns one row per item: its lowest price and how many are listed. On
-- Forever's US house that was about 13,000 rows in 16 seconds when we
-- measured it.
--
-- Browse results are shared. Blizzard's window, other addons and Goldwise
-- all read the same list, and whoever searches next replaces it. That cuts
-- both ways:
--
--   * Results from searches we didn't send are still real prices, so we
--     record those too. When another addon reads the whole market before
--     we can, that counts as our scan.
--   * Our scan must never trample a search the player is looking at. We
--     scan once, just after the window opens, and give up the moment
--     anyone else searches.

local Scanner = {}
ns.Scanner = Scanner

-- Wait this long after the window opens before scanning, so Blizzard's own
-- opening searches go first.
local OPEN_DELAY = 1.5

-- Wait this long instead when another addon here reads the market on
-- opening. One read serves us both, so let it go first and read along.
local COMPANION_HEAD_START = 4

-- How often to look again while another addon's full read is awaited.
local AWAIT_STEP = 1

-- Give up on a scan that produces nothing for this long.
local STALL_TIMEOUT = 20

-- How many times one scan will resend a request the auction house dropped.
local MAX_RETRIES = 3

-- Our scan in progress, or nil:
--   startedAt    when it began
--   rows         how many rows we had at the last page
--   sending      true only while our own query is being sent
--   sent         true once it has gone out
--   lastRequest  the request we're waiting on an answer to
--   queued       true while that request hasn't gone out yet
--   retries      how many times we've resent since the last progress
local scan

-- The most recent browse-type search anyone started:
--   ours         whether Goldwise sent it
--   wholeMarket  whether it had no text and no filters
--   automatic    whether Blizzard's window sent it unprompted
local lastSearch

-- Whether we've already recorded the first page of the search we're
-- currently overhearing, and whether we've recorded all of it.
local heardFirstPage = false
local heardEverything = false

-- Bumped each time the auction house opens, so a timer set on one visit
-- can tell it has outlived it.
local visit = 0

local function IsWholeMarket(query)
    return query.searchString == ""
        and (query.minLevel or 0) == 0
        and (query.maxLevel or 0) == 0
        and (not query.filters or #query.filters == 0)
        and (not query.itemClassFilters or #query.itemClassFilters == 0)
end

local function Stop(reason)
    ns.Log("scan stopped after %d rows: %s", scan and math.max(scan.rows, 0) or 0, reason)
    scan = nil
    ns.Publish("SCAN_STOPPED", reason)
end

-- Whether anyone other than us has deliberately searched since the window
-- opened. Once they have, the results on screen are theirs, and an
-- automatic scan would wipe them out.
local someoneSearched = false

local function NoteSearch(search)
    lastSearch = search
    ns.Log(
        "search seen: %s%s%s",
        search.ours and "ours" or "someone else's",
        search.wholeMarket and ", whole market" or "",
        search.automatic and ", automatic" or ""
    )

    if not search.ours then
        heardFirstPage = false
        heardEverything = false
        if not search.automatic then
            someoneSearched = true
        end
    end
end

--- Whether a scan of either kind is running right now.
---@return boolean
function Scanner.IsScanning()
    return scan ~= nil or ns.DeepScan.IsRunning()
end

--- Gives up the ordinary scan, if one is running, because the same prices
--- are arriving another way.
---@param reason string  fit to show the player
function Scanner.StandAside(reason)
    if scan then
        Stop(reason)
    end
end

-- Telling searches apart -------------------------------------------------------

-- A post-hook sees every search after it has been sent, whoever sent it,
-- and can't interfere with it.
hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
    local ours = scan ~= nil and scan.sending == true
    NoteSearch({ ours = ours, wholeMarket = IsWholeMarket(query) })

    if scan and not ours then
        Stop("Another search started, so Goldwise is reading along with that one.")
    end
end)

-- These produce the same result events without going through
-- SendBrowseQuery. Blizzard's window runs the favourites one by itself
-- whenever it opens.
for _, name in ipairs({ "SearchForFavorites", "SearchForItemKeys" }) do
    if C_AuctionHouse[name] then
        hooksecurefunc(C_AuctionHouse, name, function()
            NoteSearch({
                ours = false,
                wholeMarket = false,
                -- The window fires this by itself on opening, so it isn't
                -- a sign the player is looking at anything.
                automatic = name == "SearchForFavorites",
            })

            if scan then
                Stop("Another search started, so Goldwise is reading along with that one.")
            end
        end)
    end
end

-- Our own scan -------------------------------------------------------------------

-- Gives up on a scan that has stopped making progress. Called again after
-- every page, so a slow but steady scan is left alone.
local function WatchForStall()
    local watched, rows = scan, scan.rows
    C_Timer.After(STALL_TIMEOUT, function()
        if scan == watched and scan.rows == rows then
            Stop("The auction house stopped answering.")
        end
    end)
end

-- Queues a request on behalf of the current scan, and remembers it in case
-- it has to be sent again.
local function Send(request)
    local current = scan
    current.lastRequest = request
    -- True while the request is still waiting its turn. A drop in that
    -- time was somebody else's, and ours is still on its way.
    current.queued = true

    ns.Throttle.WhenReady(function()
        if scan ~= current then
            return false
        end
        current.queued = false
        request()
        return true
    end)
end

local function SendWholeMarketQuery()
    -- Hold on to the scan: if the auction house rejects the query on the
    -- spot, the scan may already be gone by the time the call returns.
    local current = scan

    current.sending = true
    C_AuctionHouse.SendBrowseQuery({
        searchString = "",
        sorts = {},
        filters = {},
        itemClassFilters = {},
    })
    current.sending = false
    current.sent = true
end

local function OnOwnResults(rows, complete)
    -- The "updated" and "added" events can both fire for one page. Only
    -- act when rows actually arrived.
    if #rows == scan.rows and not complete then
        return
    end
    scan.rows = #rows

    -- Progress means whatever was dropped has been made good. Start the
    -- allowance afresh, so a long scan beside a chatty addon isn't ended
    -- by three unrelated hiccups spread across its whole length.
    scan.retries = 0

    if complete then
        -- A finished search with nothing in it is the auction house
        -- failing to answer, not a market with nothing for sale. Filing
        -- it would mark everything the player follows as sold out.
        if #rows == 0 then
            Stop("The auction house returned an empty list.")
            return
        end

        local seconds = GetTime() - scan.startedAt
        ns.Log("scan finished: %d rows in %.1fs", #rows, seconds)
        scan = nil
        ns.Ledger.RecordScan(ns.Market.Current(), rows, true)
        ns.Publish("SCAN_FINISHED", #rows, seconds)
        return
    end

    ns.Publish("SCAN_PROGRESS", #rows)
    WatchForStall()
    Send(C_AuctionHouse.RequestMoreBrowseResults)
end

--- Starts a whole-market scan. Does nothing unless the auction house is
--- open and no scan is already running.
function Scanner.Start()
    if Scanner.IsScanning() or not ns.Market.IsOpen() then
        return
    end

    scan = { startedAt = GetTime(), rows = -1, retries = 0 }
    ns.Log("scan started")
    ns.Publish("SCAN_STARTED")
    WatchForStall()
    Send(SendWholeMarketQuery)
end

-- The auction house accepts one request at a time from everyone put
-- together: Blizzard's window, other addons and us. If two go out in the
-- same instant, one is dropped, and the client doesn't say whose. So when
-- anything is dropped mid-scan, ask again. Asking twice for a page is
-- harmless; never getting it stalls the scan.
ns.OnEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if not scan or not scan.lastRequest or scan.queued then
        return
    end

    if scan.retries >= MAX_RETRIES then
        Stop("The auction house is too busy just now. Try again in a moment.")
        return
    end

    scan.retries = scan.retries + 1
    ns.Log("a request was dropped at %d rows; resending (%d)", scan.rows, scan.retries)
    Send(scan.lastRequest)
end)

-- Other people's searches ----------------------------------------------------------

local function OnOverheardResults(complete)
    -- Record a search when its first page arrives and again when it has
    -- all of them. A search typed by hand usually stops after one page and
    -- never becomes complete, and its prices are still worth having.
    if heardEverything or (heardFirstPage and not complete) then
        return
    end
    heardFirstPage = true
    heardEverything = complete

    -- Fetched only now that we know we want it. Another addon's scan of
    -- the whole market arrives a page at a time, and asking for the list
    -- so far on every page would mean building it dozens of times over.
    local rows = C_AuctionHouse.GetBrowseResults()

    -- Only a finished search with no filters counts as a full snapshot,
    -- and only if it found something (see OnOwnResults).
    local wholeMarket = complete and #rows > 0 and lastSearch ~= nil and lastSearch.wholeMarket
    ns.Log("overheard %d rows%s", #rows, wholeMarket and " (whole market)" or "")
    ns.Ledger.RecordScan(ns.Market.Current(), rows, wholeMarket)

    -- Another addon has read the whole market for us. That's as good as
    -- having done it ourselves, and everything that waits on a finished
    -- scan should hear about it.
    if wholeMarket then
        ns.Publish("SCAN_FINISHED", #rows, 0, true)
    end
end

local function OnBrowseResults()
    local complete = C_AuctionHouse.HasFullBrowseResults()

    if scan and scan.sent then
        OnOwnResults(C_AuctionHouse.GetBrowseResults(), complete)
    elseif lastSearch and lastSearch.ours then
        -- A straggling event from a scan of ours that already finished.
        return
    else
        OnOverheardResults(complete)
    end
end

ns.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseResults)
ns.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseResults)

-- Looking at one item ------------------------------------------------------------------

-- When anyone opens a single item's listings (the player clicking a row,
-- or another addon checking what a material costs) the game hands back
-- that item's auctions. It's the most exact price there is for it, so
-- it's worth keeping whoever asked.

-- Listings looked through for the cheapest buyout. They usually arrive
-- cheapest first, but whoever asked chooses the order.
local LISTINGS_CHECKED = 50

-- An addon pricing a recipe can ask about dozens of items in a second, so
-- what we learn is gathered up and filed in one go.
local FILE_AFTER = 0.5
local learned, filing = {}, false

local function Learn(itemID, price, quantity)
    if not price or price <= 0 or not ns.Market.IsOpen() then
        return
    end
    learned[itemID] = { price, quantity or 0 }

    if not filing then
        filing = true
        C_Timer.After(FILE_AFTER, function()
            filing = false
            local prices = learned
            learned = {}
            if ns.Market.IsOpen() then
                ns.Ledger.RecordPrices(ns.Market.Current(), prices, false)
            end
        end)
    end
end

-- Stackable goods: one pooled list, always cheapest first.
ns.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    local cheapest = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if cheapest then
        Learn(itemID, cheapest.unitPrice, C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID))
    end
end)

-- Everything else: one listing per auction.
ns.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    -- Gear with a random suffix is several items under one ID, and we
    -- keep the cheapest of them all. One variant's listings would replace
    -- that with its own, so leave those to the market scans.
    if (itemKey.itemSuffix or 0) ~= 0 then
        return
    end

    local lowest
    local count = math.min(C_AuctionHouse.GetNumItemSearchResults(itemKey), LISTINGS_CHECKED)
    for index = 1, count do
        local listing = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        local buyout = listing and listing.buyoutAmount
        if buyout and buyout > 0 and (not lowest or buyout < lowest) then
            lowest = buyout
        end
    end

    Learn(itemKey.itemID, lowest, C_AuctionHouse.GetItemSearchResultsQuantity(itemKey))
end)

ns.OnEvent("AUCTION_HOUSE_BROWSE_FAILURE", function()
    if scan and scan.sent then
        Stop("The auction house turned the search down.")
    end
end)

-- Opening and closing ----------------------------------------------------------------

local function ScannedRecently(marketKey)
    local lastScan = ns.Ledger.LastScan(marketKey)
    return lastScan ~= nil and GetServerTime() - lastScan < ns.settings.scanInterval
end

ns.Subscribe("AUCTION_HOUSE_OPENED", function(marketKey)
    visit = visit + 1
    heardFirstPage = false
    heardEverything = false

    ns.Log("auction house opened: %s", marketKey)

    if not ns.settings.autoScan or ScannedRecently(marketKey) then
        return
    end

    local thisVisit = visit

    -- The ordinary scan replaces whatever is in Blizzard's browse list. If
    -- the player has already searched for something, leave their results
    -- alone; we'll catch the market on the next visit.
    local function BrowseUnlessBusy()
        local stillHere = ns.Market.IsOpen() and visit == thisVisit
        if not stillHere or someoneSearched then
            return
        end

        -- Another addon has asked for every auction. Its answer is ours to
        -- read too, so wait for it. If it never comes, the wait runs out
        -- and we read the market ourselves after all.
        if ns.DeepScan.IsExpected() then
            C_Timer.After(AWAIT_STEP, BrowseUnlessBusy)
            return
        end

        -- It came, or another addon's search covered the whole market
        -- while we held back.
        if ns.DeepScan.IsRunning() or ScannedRecently(marketKey) then
            return
        end

        Scanner.Start()
    end

    local delay = ns.Companions.ReadsOnOpening() and COMPANION_HEAD_START or OPEN_DELAY

    C_Timer.After(delay, function()
        if not ns.Market.IsOpen() or visit ~= thisVisit then
            return
        end

        -- Prefer the deep scan when its cooldown allows. It doesn't touch
        -- the browse list, so it's welcome even mid-search. If it turns
        -- out to be on a cooldown we didn't know about, fall back.
        --
        -- That cooldown belongs to the whole account, though. If another
        -- addon the player has makes full reads of its own, spending it
        -- unasked would leave their button dead for a quarter of an hour.
        -- Their reads are ours to share anyway (see DeepScan).
        if ns.DeepScan.IsAvailable() and not ns.Companions.MakesFullReads() then
            ns.DeepScan.Start(BrowseUnlessBusy)
        else
            BrowseUnlessBusy()
        end
    end)
end)

--- Reads prices now, because the player asked. Uses the deep scan when it's
--- available and the ordinary one otherwise.
function Scanner.ReadPrices()
    if not ns.DeepScan.IsAvailable() then
        Scanner.Start()
        return
    end

    -- If the deep scan turns out to be unavailable after all, fall back to
    -- the ordinary one, unless the player has started a search of their
    -- own in the meantime. Their results matter more than our retry.
    local searchWhenAsked = lastSearch
    ns.DeepScan.Start(function()
        if lastSearch == searchWhenAsked then
            Scanner.Start()
        end
    end)
end

ns.Subscribe("AUCTION_HOUSE_CLOSED", function()
    -- Reset here rather than on opening, so it doesn't matter whether
    -- Blizzard's window or Goldwise hears about the next opening first.
    someoneSearched = false

    if scan then
        Stop("The auction house closed before the scan finished.")
    end
end)
