local _, ns = ...

-- What this sitting at the game has brought in or cost, for the session
-- tracker (UI\SessionTracker.lua).
--
-- A session is one stretch of play on one character. A reload, or coming
-- back within a few minutes of logging out, carries on the same one: the
-- game doesn't say why the addon started again, and a reload in the
-- middle of an evening isn't the end of it.
--
-- Two things are followed. The coin, from every change to the purse
-- (Purse.lua tells us). And what's in the bags, valued the way Goldwise
-- would have the player sell it: at auction, less the cut, for what it
-- says to sell or hold, and at a vendor's price for what it says to
-- vendor. Loot is earning too, before it's sold.

local Session = {}
ns.Session = Session

-- How long a character can be away before coming back starts afresh.
local CARRY_ON_SECONDS = 15 * 60

-- How often a session notes that it's still going, so that one cut short
-- by a crash or a lost connection still knows roughly when play stopped.
local HEARTBEAT_SECONDS = 60

-- Bags change in bursts (looting a stack, selling a page to a vendor), so
-- they're valued once things have been quiet for this long.
local SETTLE_SECONDS = 1

-- The saved sessions, one per character, by character key:
-- { startedAt, seenAt, earned, spent, income, spending, bagsAtStart,
-- carriedAtStart, banksSeen }, where income and spending split the coin
-- by what it was for, as { [category] = copper } with Purse.lua's
-- categories. bagsAtStart is what was in the bags and bank then, and
-- carriedAtStart the bags alone, each { [itemID] = count }; banksSeen
-- says which banks had been read by then (see AddNewlySeenBanks). Times
-- are server time; money is copper.
local function Sessions()
    if type(ns.db.sessions) ~= "table" then
        ns.db.sessions = {}
    end
    return ns.db.sessions
end

-- This character's session, once logged in.
local current

-- The bags as last valued: { auction, vendor, unpriced, auctionAtStart,
-- vendorAtStart }. unpriced counts the kinds of thing with no auction
-- price, which are taken at a vendor's price if a vendor will have them.
-- The two "at start" are what was in them when the session began, at the
-- same prices.
local bags

-- Whether the bags have been read since login. Until they have, they look
-- empty, and that's not a figure to start a session from.
local bagsRead = false

local valuePending = false

-- Whether anything is showing the figures. Valuing the bags means
-- assessing everything in them, so it's only done when someone's looking,
-- and once at the start of each session.
local watched = false

local function Fresh()
    local now = GetServerTime()
    return { startedAt = now, seenAt = now, earned = 0, spent = 0, income = {}, spending = {} }
end

-- What's in the bags, and the bank too if withBank, as { [itemID] =
-- count }. The bank is counted as it was at the last visit, this
-- character's own and the one the account shares. Counting it means
-- putting something in the bank is neither a gain nor a loss, which it
-- isn't; leaving it out means that's counted as things leaving.
local function Contents(withBank, withoutListings)
    local counts = {}
    local function Add(holdings)
        for _, holding in ipairs(holdings) do
            counts[holding.itemID] = (counts[holding.itemID] or 0) + holding.count
        end
    end
    Add(ns.Bags.Holdings())
    -- What's up for auction is still the player's until it sells.
    if not withoutListings then
        Add((ns.Listings.Holdings()))
    end
    if withBank then
        Add((ns.Bank.Holdings()))
        Add((ns.Bank.AccountHoldings()))
    end
    return counts
end

-- Whether the player wants the bank counted along with the bags.
local function WithBank()
    return ns.settings and ns.settings.sessionTrackerBank or false
end

-- A list of holdings, as Assets.SaleValue wants them, from counts.
local function AsHoldings(counts)
    local holdings = {}
    for itemID, count in pairs(counts) do
        table.insert(holdings, { itemID = itemID, count = count })
    end
    return holdings
end

-- Whether each bank has ever been read: this character's, then the
-- account's.
local function BanksSeen()
    local _, ownSeenAt = ns.Bank.Holdings()
    local _, accountSeenAt = ns.Bank.AccountHoldings()
    return ownSeenAt ~= nil, accountSeenAt ~= nil
end

-- What the start was worth, { auction, vendor }, kept until prices,
-- settings or the start itself change. It's the same answer every time
-- otherwise, and working it out means assessing everything held.
local startValue

-- Takes what's held now as the start: the bags and bank together in
-- bagsAtStart, and the bags alone in carriedAtStart, so the bank can be
-- switched in and out without starting again.
local function SetStart()
    current.bagsAtStart = Contents(true)
    current.carriedAtStart = Contents(false)
    local own, account = BanksSeen()
    current.banksSeen = { own = own, account = account, listed = ns.Listings.Seen() }
    startValue = nil
end

-- A bank that had never been read when the session began wasn't in the
-- start, so the first time it is read, what's in it joins the start
-- rather than showing up as gained. The bank is read as it opens, before
-- anything can be moved in or out.
local function AddNewlySeenBanks()
    if
        not current
        or type(current.bagsAtStart) ~= "table"
        or type(current.banksSeen) ~= "table"
    then
        return
    end
    local own, account = BanksSeen()
    local function FoldInto(start, holdings)
        for _, holding in ipairs(holdings) do
            start[holding.itemID] = (start[holding.itemID] or 0) + holding.count
        end
        startValue = nil
    end
    local function Fold(holdings)
        FoldInto(current.bagsAtStart, holdings)
    end
    if own and not current.banksSeen.own then
        Fold((ns.Bank.Holdings()))
        current.banksSeen.own = true
    end
    if account and not current.banksSeen.account then
        Fold((ns.Bank.AccountHoldings()))
        current.banksSeen.account = true
    end
    -- The same for each auction house's listings, which are read the
    -- moment it opens. They count with the bags as well as the bank, so
    -- they join both starts. A session saved before listings were kept
    -- has no word on them, and is taken not to have seen any.
    if type(current.banksSeen.listed) ~= "table" then
        current.banksSeen.listed = {}
    end
    for marketKey in pairs(ns.Listings.Seen()) do
        if not current.banksSeen.listed[marketKey] then
            local holdings = ns.Listings.Holdings(marketKey)
            FoldInto(current.bagsAtStart, holdings)
            if type(current.carriedAtStart) == "table" then
                FoldInto(current.carriedAtStart, holdings)
            end
            current.banksSeen.listed[marketKey] = true
        end
    end
end

-- The bags are compared with what was in them when the session began,
-- both valued at today's prices. Comparing with what they were worth then
-- would count every change in the market as something gained or lost.
local function Value()
    valuePending = false
    if not current or not bagsRead then
        return
    end

    -- A session begun before the bank was counted started from the bags
    -- alone. Counting the bank against that would show all of it as
    -- gained, so it starts again from what's held now.
    if
        type(current.bagsAtStart) ~= "table"
        or type(current.carriedAtStart) ~= "table"
        or type(current.banksSeen) ~= "table"
    then
        SetStart()
    end

    local withBank = WithBank()
    local start = withBank and current.bagsAtStart or current.carriedAtStart
    local market = ns.Market.Home()

    -- What's held and what's listed are valued apart, so the tracker can
    -- show them apart; together they're what's compared with the start.
    local heldAuction, heldVendor, unpriced =
        ns.Assets.SaleValue(AsHoldings(Contents(withBank, true)), market)
    local listedAuction, listedVendor = ns.Assets.SaleValue(ns.Listings.Holdings(), market)
    local auction, vendor = heldAuction + listedAuction, heldVendor + listedVendor
    if not startValue then
        local auctionBefore, vendorBefore = ns.Assets.SaleValue(AsHoldings(start), market)
        startValue = { auction = auctionBefore, vendor = vendorBefore }
    end
    local auctionBefore, vendorBefore = startValue.auction, startValue.vendor

    bags = {
        auction = auction,
        vendor = vendor,
        heldAuction = heldAuction,
        heldVendor = heldVendor,
        listed = listedAuction + listedVendor,
        unpriced = unpriced,
        auctionAtStart = auctionBefore,
        vendorAtStart = vendorBefore,
    }
    ns.Publish("SESSION_CHANGED")
end

local function ValueSoon()
    if valuePending then
        return
    end
    -- After the first valuation, only bother while someone's looking.
    if current and current.bagsAtStart and not watched then
        return
    end
    valuePending = true
    C_Timer.After(SETTLE_SECONDS, Value)
end

ns.OnEvent("PLAYER_LOGIN", function()
    local key = ns.Characters.CurrentKey()
    local saved = Sessions()[key]
    local now = GetServerTime()

    if type(saved) ~= "table" or now - (saved.seenAt or 0) > CARRY_ON_SECONDS then
        saved = Fresh()
        Sessions()[key] = saved
    end
    saved.seenAt = now
    -- Sessions saved before coin was kept by kind.
    saved.income = type(saved.income) == "table" and saved.income or {}
    saved.spending = type(saved.spending) == "table" and saved.spending or {}
    current = saved

    C_Timer.NewTicker(HEARTBEAT_SECONDS, function()
        current.seenAt = GetServerTime()
    end)
end)

ns.OnEvent("PLAYER_LOGOUT", function()
    if current then
        current.seenAt = GetServerTime()
    end
end)

-- Coin from the auction house that Trade.lua has just put on record and
-- that's about to arrive here. The auction house pays by letter, so it
-- lands in the purse as mail; this is how it's told apart from coin an
-- alt sent. Trade.lua loads first, so it hears of each change to the
-- purse first, in the same moment.
local fromAuction = 0

ns.Subscribe("TRADE_CHANGED", function(kind, amount)
    if (kind == ns.Trade.SALE or kind == ns.Trade.REFUND) and amount then
        fromAuction = fromAuction + amount
    end
end)

local function Add(side, category, amount)
    side[category] = (side[category] or 0) + amount
end

ns.Subscribe("MONEY_MOVED", function(delta, category)
    local auctionPart = 0
    if delta > 0 then
        auctionPart = math.min(fromAuction, delta)
    end
    fromAuction = 0

    if not current then
        return
    end
    if delta > 0 then
        current.earned = current.earned + delta
        if auctionPart > 0 then
            Add(current.income, "auction", auctionPart)
        end
        if delta > auctionPart then
            Add(current.income, category or "other", delta - auctionPart)
        end
    else
        current.spent = current.spent - delta
        Add(current.spending, category or "other", -delta)
    end
    ns.Publish("SESSION_CHANGED")
end)

ns.Subscribe("BAGS_CHANGED", function()
    bagsRead = true
    AddNewlySeenBanks()
    ValueSoon()
end)

-- New prices, marking something as kept, or switching to auditor mode
-- change what the start would be sold for, as well as what's held now.
local function Revalue()
    startValue = nil
    ValueSoon()
end
ns.Subscribe("PRICES_CHANGED", Revalue)
ns.Subscribe("SETTINGS_CHANGED", Revalue)

--- Says whether anything is showing the session, so the bags are kept
--- valued while it is and left alone while it isn't.
---@param showing boolean
function Session.SetWatched(showing)
    watched = showing
    if showing then
        ValueSoon()
    end
end

--- Starts the session again from now, with the bags as they are.
function Session.Restart()
    if not current then
        return
    end
    local fresh = Fresh()
    for field, value in pairs(fresh) do
        current[field] = value
    end
    current.bagsAtStart = nil
    current.carriedAtStart = nil
    current.banksSeen = nil
    startValue = nil
    if bagsRead then
        SetStart()
    end

    -- The last valuation was against the old start.
    bags = nil
    ns.Publish("SESSION_CHANGED")
    ValueSoon()
end

--- How the session stands.
---@return table|nil summary  nil before login. Otherwise { seconds, earned,
---        spent, income, spending, coin, bags, auction, vendor, unpriced,
---        auctionChange, vendorChange, goods, overall, withBank,
---        bankSeenAt, heldAuction, heldVendor, listed }. heldAuction and
---        heldVendor are what's held fetches each way, leaving out what's
---        up for auction, which listed is. seconds
---        is how long the session has run, and unpriced how many kinds of
---        thing held have no auction price. income and spending are
---        { [category] = copper }, by Purse.lua's categories, and the rest
---        are copper. coin is what came in less what went out. "Held" is
---        the bags, and the bank too when withBank, the bank as of
---        bankSeenAt, the last visit (nil if never). auctionChange and
---        vendorChange are how much more what's held would fetch each way
---        than what was held at the start, both at today's prices; goods is
---        the two together, and overall is coin and goods together. bags
---        and the fields after it are nil until the bags have been valued.
function Session.Summary()
    if not current then
        return nil
    end

    local summary = {
        seconds = GetServerTime() - current.startedAt,
        earned = current.earned,
        spent = current.spent,
        income = current.income,
        spending = current.spending,
        coin = current.earned - current.spent,
    }
    if bags then
        summary.auction = bags.auction
        summary.vendor = bags.vendor
        summary.heldAuction = bags.heldAuction
        summary.heldVendor = bags.heldVendor
        summary.listed = bags.listed
        summary.unpriced = bags.unpriced
        summary.bags = bags.auction + bags.vendor
        summary.auctionChange = bags.auction - bags.auctionAtStart
        summary.vendorChange = bags.vendor - bags.vendorAtStart
        summary.goods = summary.auctionChange + summary.vendorChange
        summary.overall = summary.coin + summary.goods
        -- The bank, when it's counted, is as it was last seen, which the
        -- tracker says.
        summary.withBank = WithBank()
        if summary.withBank then
            summary.bankSeenAt = select(2, ns.Bank.Holdings())
        end
    end
    return summary
end
