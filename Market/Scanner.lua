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
--     record those too.
--   * Our scan must never trample a search the player is looking at. We
--     scan once, just after the window opens, and give up the moment
--     anyone else searches.

local Scanner = {}
ns.Scanner = Scanner

-- Wait this long after the window opens before scanning, so Blizzard's own
-- opening searches go first.
local OPEN_DELAY = 1.5

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

-- Telling searches apart -------------------------------------------------------

-- A post-hook sees every search after it has been sent, whoever sent it,
-- and can't interfere with it.
hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
    local ours = scan ~= nil and scan.sending == true
    NoteSearch({ ours = ours, wholeMarket = IsWholeMarket(query) })

    if scan and not ours then
        Stop("Someone else started a search, so the scan stepped aside.")
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
                Stop("Someone else started a search, so the scan stepped aside.")
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

local function OnOverheardResults(rows, complete)
    -- Record a search when its first page arrives and again when it has
    -- all of them. A search typed by hand usually stops after one page and
    -- never becomes complete, and its prices are still worth having.
    if heardEverything or (heardFirstPage and not complete) then
        return
    end
    heardFirstPage = true
    heardEverything = complete

    -- Only a finished search with no filters counts as a full snapshot.
    local wholeMarket = complete and lastSearch ~= nil and lastSearch.wholeMarket
    ns.Log("overheard %d rows%s", #rows, wholeMarket and " (whole market)" or "")
    ns.Ledger.RecordScan(ns.Market.Current(), rows, wholeMarket)
end

local function OnBrowseResults()
    local rows = C_AuctionHouse.GetBrowseResults()
    local complete = C_AuctionHouse.HasFullBrowseResults()

    if scan and scan.sent then
        OnOwnResults(rows, complete)
    elseif lastSearch and lastSearch.ours then
        -- A straggling event from a scan of ours that already finished.
        return
    else
        OnOverheardResults(rows, complete)
    end
end

ns.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseResults)
ns.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseResults)

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
        if stillHere and not someoneSearched then
            Scanner.Start()
        end
    end

    C_Timer.After(OPEN_DELAY, function()
        if not ns.Market.IsOpen() or visit ~= thisVisit then
            return
        end

        -- Prefer the deep scan when its cooldown allows. It doesn't touch
        -- the browse list, so it's welcome even mid-search. If it turns
        -- out to be on a cooldown we didn't know about, fall back.
        if ns.DeepScan.IsAvailable() then
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
