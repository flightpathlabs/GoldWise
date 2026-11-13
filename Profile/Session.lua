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
-- { startedAt, seenAt, earned, spent, income, spending, bagsAtStart },
-- where income and spending split the coin by what it was for, as
-- { [category] = copper } with Purse.lua's categories, and bagsAtStart
-- is what was in the bags then, { [itemID] = count }. Times are server
-- time; money is copper.
local function Sessions()
    if type(ns.db.sessions) ~= "table" then
        ns.db.sessions = {}
    end
    return ns.db.sessions
end

-- This character's session, once logged in.
local current

-- The bags as last valued: { auction, vendor, unpriced, atStart }. unpriced counts
-- the kinds of thing with no auction price, which are taken at a
-- vendor's price if a vendor will have them. atStart is what was in
-- them when the session began, at the same prices.
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

-- What's in the bags, as { [itemID] = count }.
local function Contents()
    local counts = {}
    for _, holding in ipairs(ns.Bags.Holdings()) do
        counts[holding.itemID] = (counts[holding.itemID] or 0) + holding.count
    end
    return counts
end

-- What a list of holdings would fetch, each sold the way Goldwise advises.
local function Worth(holdings, marketKey)
    local auction, vendor, unpriced = 0, 0, 0
    for _, holding in ipairs(holdings) do
        local asset = ns.Assets.Describe(holding, marketKey)
        local advice = asset.advice
        local verb = advice.verb
        if verb == ns.Advice.SELL or verb == ns.Advice.HOLD then
            auction = auction + (advice.proceeds or 0)
        elseif verb == ns.Advice.VENDOR then
            vendor = vendor + (advice.fromVendor or 0)
        elseif verb == ns.Advice.UNKNOWN then
            unpriced = unpriced + 1
            vendor = vendor + (asset.vendorPrice or 0) * asset.count
        end
        -- What the player keeps isn't for sale, so it isn't counted.
    end
    return auction, vendor, unpriced
end

-- The bags are compared with what was in them when the session began,
-- both valued at today's prices. Comparing with what they were worth then
-- would count every change in the market as something gained or lost.
local function Value()
    valuePending = false
    if not current or not bagsRead then
        return
    end

    if type(current.bagsAtStart) ~= "table" then
        current.bagsAtStart = Contents()
    end

    local market = ns.Market.Home()
    local auction, vendor, unpriced = Worth(ns.Bags.Holdings(), market)

    local before = {}
    for itemID, count in pairs(current.bagsAtStart) do
        table.insert(before, { itemID = itemID, count = count })
    end
    local auctionBefore, vendorBefore = Worth(before, market)

    bags = {
        auction = auction,
        vendor = vendor,
        unpriced = unpriced,
        atStart = auctionBefore + vendorBefore,
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
-- alt sent. Trade hears of the coin first, in the same moment.
local fromAuction = 0

ns.Subscribe("TRADE_CHANGED", function(kind, amount)
    if (kind == ns.Trade.SALE or kind == ns.Trade.REFUND) and amount then
        fromAuction = fromAuction + amount
    end
end)

local function Add(side, category, amount)
    side[category] = (side[category] or 0) + amount
end

ns.Subscribe("MONEY_MOVED", function(delta, context)
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
            Add(current.income, context or "other", delta - auctionPart)
        end
    else
        current.spent = current.spent - delta
        Add(current.spending, context or "other", -delta)
    end
    ns.Publish("SESSION_CHANGED")
end)

ns.Subscribe("BAGS_CHANGED", function()
    bagsRead = true
    ValueSoon()
end)

ns.Subscribe("PRICES_CHANGED", ValueSoon)

-- Marking something as kept, or switching to auditor mode, changes what
-- it would be sold for.
ns.Subscribe("SETTINGS_CHANGED", ValueSoon)

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
    current.bagsAtStart = bagsRead and Contents() or nil

    -- The last valuation was against the old start.
    bags = nil
    ns.Publish("SESSION_CHANGED")
    ValueSoon()
end

--- How the session stands.
---@return table|nil summary  nil before login. Otherwise { seconds, earned,
---        spent, income, spending, coin, bags, auction, vendor, unpriced,
---        goods, overall }, where income and spending are { [category] =
---        copper }, by Purse.lua's categories, and the rest are
---        copper. coin is what came in less what went out;
---        goods is how much more the bags are worth than what was in them
---        at the start, both at today's prices;
---        overall is the two together. bags and the fields after it are
---        nil until the bags have been valued.
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
        summary.unpriced = bags.unpriced
        summary.bags = bags.auction + bags.vendor
        summary.goods = summary.bags - bags.atStart
        summary.overall = summary.coin + summary.goods
    end
    return summary
end
