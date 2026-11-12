local _, ns = ...

-- The deep scan: every individual auction, not one summary row per item.
--
-- The game calls this "replicating" the auction house. It answers in about
-- fifteen seconds with a couple of hundred thousand auctions, and it leaves
-- Blizzard's browse list alone, so it can run even while the player is
-- looking at search results. The price is a cooldown: once per fifteen
-- minutes for the whole account.
--
-- What it adds over the ordinary scan is depth. For items the player
-- follows we can say how many are listed at each of the lowest prices,
-- which is the difference between "the lowest is 81c" and "the cheapest
-- 1,200 are all 81c".
--
-- Other addons use the same cooldown. If one of them asks first, ours is
-- spent, but the answer is the game's and any addon may read it. So when
-- a list arrives that we didn't ask for, we read it all the same. Whoever
-- gets there first, the player's prices end up fresh.

local DeepScan = {}
ns.DeepScan = DeepScan

-- The game enforces this per account. We keep our own note of it so we
-- don't ask when the answer would be silence.
local COOLDOWN = 15 * 60

-- Give up waiting for the auction list after this long. It answered in
-- under fifteen seconds when we measured it.
local ANSWER_TIMEOUT = 30

-- Auctions examined per frame. Small enough not to stutter, large enough
-- to finish a full house in a second or two.
local BATCH_SIZE = 4000

-- Price levels kept per tracked item.
local DEPTH_LEVELS = 5

-- The run in progress, or nil:
--   marketKey  the market being read
--   startedAt  when we asked
--   onNoAnswer what to do instead if the auction house gives us nothing
--   sent       true once the request has actually gone out
--   total      auctions to examine, once the list has arrived
--   nextIndex  the next auction to look at (they're numbered from zero)
--   prices     [itemID] = { lowest unit price, total quantity }
--   lots       [itemID] = { price, quantity, price, quantity, ... } for
--              tracked items only
--   borrowed   true if another addon asked for the list and we're reading
--              over its shoulder
local run

-- The list we last read: how many auctions it held and when. The game
-- announces the same list again whenever more of its item details load,
-- and we only want to read each list once.
local lastRead

--- Whether a deep scan is running right now.
---@return boolean
function DeepScan.IsRunning()
    return run ~= nil
end

--- Whether a deep scan could start: the auction house is open, nothing
--- else is scanning, the player hasn't switched it off, and the cooldown
--- has passed.
---@return boolean
function DeepScan.IsAvailable()
    if not ns.settings.deepScan or not ns.Market.IsOpen() or ns.Scanner.IsScanning() then
        return false
    end

    local lastAsked = ns.db.lastDeepScan
    return not lastAsked or GetServerTime() - lastAsked >= COOLDOWN
end

local function Stop(reason)
    ns.Log("deep scan stopped: %s", reason)
    run = nil
    ns.Publish("SCAN_STOPPED", reason)
end

-- For when the auction house gave us nothing to work with: stop, then let
-- whoever started us try something else.
local function GiveUp(reason)
    local fallback = run.onNoAnswer
    Stop(reason)
    if fallback then
        fallback()
    end
end

-- Working through the list -----------------------------------------------------

-- Turns an item's individual lots into its few cheapest price levels.
local function SummariseLots(lots)
    -- Add up the quantity at each distinct price.
    local atPrice, prices = {}, {}
    for index = 1, #lots, 2 do
        local price, quantity = lots[index], lots[index + 1]
        if not atPrice[price] then
            atPrice[price] = 0
            table.insert(prices, price)
        end
        atPrice[price] = atPrice[price] + quantity
    end
    table.sort(prices)

    local levels, higher = {}, 0
    for index, price in ipairs(prices) do
        if index <= DEPTH_LEVELS then
            levels[index] = { price, atPrice[price] }
        else
            higher = higher + atPrice[price]
        end
    end
    return levels, higher
end

local function Finish()
    local finished = run
    run = nil

    local items = 0
    for _ in pairs(finished.prices) do
        items = items + 1
    end

    local seconds = GetTime() - finished.startedAt
    lastRead = { total = finished.total, at = GetTime() }
    ns.Log(
        "deep scan finished%s: %d auctions, %d items, %.1fs",
        finished.borrowed and " (another addon's list)" or "",
        finished.total,
        items,
        seconds
    )

    local depths = {}
    for itemID, lots in pairs(finished.lots) do
        local levels, higher = SummariseLots(lots)
        depths[itemID] = { levels = levels, higher = higher }
    end
    ns.Ledger.SetDepths(finished.marketKey, depths)
    ns.Ledger.RecordPrices(finished.marketKey, finished.prices, true)
    ns.Publish("SCAN_FINISHED", items, seconds, finished.borrowed)
end

local function ExamineBatch()
    -- The auction house may have closed, or the run been abandoned,
    -- between frames.
    if not run then
        return
    end

    local market = ns.MarketData(run.marketKey)
    local last = math.min(run.nextIndex + BATCH_SIZE, run.total) - 1

    for index = run.nextIndex, last do
        -- Of the eighteen values this returns we want three: the stack
        -- size (3rd), the buyout for the whole stack (10th) and the item
        -- (17th).
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
            C_AuctionHouse.GetReplicateItemInfo(index)

        -- No buyout means a bid-only auction, which tells us nothing about
        -- what the item goes for.
        if itemID and itemID > 0 and count and count > 0 and buyout and buyout > 0 then
            local unitPrice = math.max(1, math.floor(buyout / count))

            local entry = run.prices[itemID]
            if entry then
                entry[1] = math.min(entry[1], unitPrice)
                entry[2] = entry[2] + count
            else
                run.prices[itemID] = { unitPrice, count }
            end

            if market.tracked[itemID] then
                local lots = run.lots[itemID]
                if not lots then
                    lots = {}
                    run.lots[itemID] = lots
                end
                lots[#lots + 1] = unitPrice
                lots[#lots + 1] = count
            end
        end
    end

    run.nextIndex = last + 1
    if run.nextIndex >= run.total then
        Finish()
    else
        ns.Publish("SCAN_PROGRESS", run.nextIndex, run.total)
        C_Timer.After(0, ExamineBatch)
    end
end

-- Whether a list that arrived unasked is one we've already been through.
local function AlreadyRead(total)
    return lastRead ~= nil and lastRead.total == total and GetTime() - lastRead.at < COOLDOWN
end

-- Starts reading a list another addon asked for.
local function ReadOverShoulder(total)
    run = {
        marketKey = ns.Market.Current(),
        startedAt = GetTime(),
        prices = {},
        lots = {},
        borrowed = true,
        sent = true,
        total = total,
        nextIndex = 0,
    }

    -- The cooldown is the account's, not the addon's. Somebody has just
    -- used it, so there's no point in our asking for a while either.
    ns.db.lastDeepScan = GetServerTime()

    ns.Log("deep scan: reading %d auctions another addon asked for", total)
    ns.Publish("SCAN_STARTED")
    ExamineBatch()
end

ns.OnEvent("REPLICATE_ITEM_LIST_UPDATE", function()
    -- This fires for our own request, for another addon's, and again
    -- whenever more item details load for either. The prices are all there
    -- from the first.
    local total = C_AuctionHouse.GetNumReplicateItems()

    if not run then
        local worthReading = total > 0 and not AlreadyRead(total)
        if worthReading and ns.settings.autoScan and ns.Market.IsOpen() then
            ReadOverShoulder(total)
        end
        return
    end

    -- Our own run: only the first answer after the request matters.
    if not run.sent or run.total then
        return
    end

    run.total = total
    run.nextIndex = 0
    ns.Log("deep scan answered with %d auctions", run.total)

    if run.total == 0 then
        GiveUp("The auction house returned an empty list.")
        return
    end
    ExamineBatch()
end)

-- Starting ---------------------------------------------------------------------------

--- Starts a deep scan, if one is available.
---@param onNoAnswer fun()|nil  called if the auction house never replies,
---        which is what a cooldown we didn't know about looks like
function DeepScan.Start(onNoAnswer)
    if not DeepScan.IsAvailable() then
        return
    end

    local thisRun = {
        marketKey = ns.Market.Current(),
        startedAt = GetTime(),
        onNoAnswer = onNoAnswer,
        prices = {},
        lots = {},
    }
    run = thisRun

    -- Noted when we ask, not when we're answered. Another addon may have
    -- used the cooldown already, and asking again every visit would only
    -- waste a minute each time.
    ns.db.lastDeepScan = GetServerTime()

    ns.Log("deep scan started")
    ns.Publish("SCAN_STARTED")

    ns.Throttle.WhenReady(function()
        if run ~= thisRun then
            return false
        end

        run.sent = true
        C_AuctionHouse.ReplicateItems()

        -- The clock starts when the request leaves, not when it joined
        -- the queue behind someone else's.
        C_Timer.After(ANSWER_TIMEOUT, function()
            if run == thisRun and not run.total then
                GiveUp("The full read didn't answer. It can only run once every 15 minutes.")
            end
        end)
        return true
    end)
end

ns.Subscribe("AUCTION_HOUSE_CLOSED", function()
    if run then
        Stop("The auction house closed before the full read finished.")
    end
end)
