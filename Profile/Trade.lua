local _, ns = ...

-- What the auction house has made the player, and cost them.
--
-- Purse.lua knows that money arrived at the mailbox or left at the
-- auction house, and no more than that. This looks closer. Coin from the
-- mailbox is only a sale if the letter it came in was an auction's
-- invoice, and coin spent at the auction house is either the price of
-- something or the deposit on a listing.
--
-- The game never says "that was a sale". What it does is let us see the
-- player ask for something: take the money out of this letter, bid on
-- that auction, post this item. So each time they ask, we note what coin
-- to expect and why, and when the coin moves we match it up. Money that
-- moves with nothing expected is left to the Purse's plain totals.
--
-- Kept by day for as long as price history is, across the whole account,
-- with a short list of the latest sales and purchases.

local Trade = {}
ns.Trade = Trade

Trade.SALE = "sale"
Trade.PURCHASE = "purchase"
Trade.DEPOSIT = "deposit"
Trade.REFUND = "refund"

-- Seconds an expected payment is waited for. The mailbox and the auction
-- house both answer within a moment or two, when they answer at all.
local EXPECT_FOR = 15

-- The latest sales and purchases kept for the list on the Profit tab.
local RECENT_KEPT = 80

-- Who auction letters come from: "Alliance Auction House" and its like.
-- English, as the rest of what Goldwise knows about the mailbox is.
local AUCTION_SENDER = "Auction House"

-- Coin we've been given reason to expect, oldest first:
-- { kind, amount, at, itemID, name, count, cut }. Two queues, because
-- what's on its way in can't be confused with what's on its way out.
local arriving, leaving = {}, {}

local function Book()
    if type(ns.db.trade) ~= "table" then
        ns.db.trade = {}
    end
    local book = ns.db.trade
    if type(book.days) ~= "table" then
        book.days = {}
    end
    if type(book.recent) ~= "table" then
        book.recent = {}
    end
    return book
end

-- Recording --------------------------------------------------------------------

-- Today's totals: sold, bought, deposits, refunds and cut in copper, and
-- how many sales.
local function Today()
    local days = Book().days
    local today = ns.Ledger.Today()

    if not days[today] then
        days[today] = { sold = 0, bought = 0, deposits = 0, refunds = 0, cut = 0, sales = 0 }

        -- A new day is as good a moment as any to drop the oldest.
        for recorded in pairs(days) do
            if recorded <= today - ns.settings.historyDays then
                days[recorded] = nil
            end
        end
    end
    return days[today]
end

local function Remember(entry)
    local recent = Book().recent
    table.insert(recent, entry)
    while #recent > RECENT_KEPT do
        table.remove(recent, 1)
    end
end

-- Puts one movement of coin on record, now that it has happened.
local function File(kind, amount, expected)
    local day = Today()
    expected = expected or {}

    if kind == Trade.SALE then
        day.sold = day.sold + amount
        day.sales = day.sales + 1
        day.cut = day.cut + (expected.cut or 0)
    elseif kind == Trade.REFUND then
        day.refunds = day.refunds + amount
    elseif kind == Trade.DEPOSIT then
        day.deposits = day.deposits + amount
    else
        day.bought = day.bought + amount
    end

    -- Deposits are left off the list: one for every listing would bury
    -- the sales it's there to show.
    if kind ~= Trade.DEPOSIT then
        Remember({
            at = GetServerTime(),
            kind = kind,
            amount = amount,
            itemID = expected.itemID,
            name = expected.name,
            count = expected.count,
        })
    end

    ns.Publish("TRADE_CHANGED")
end

-- Expecting ----------------------------------------------------------------------

local function Expect(queue, expected)
    expected.at = GetTime()
    table.insert(queue, expected)
end

-- Throws out what was expected and never came: a letter that couldn't be
-- emptied, a bid the auction house turned down.
local function DropStale(queue)
    local now = GetTime()
    while queue[1] and now - queue[1].at > EXPECT_FOR do
        table.remove(queue, 1)
    end
end

-- The player, or an addon on their behalf, has asked for the money in a
-- letter. If it's from the auction house, that money has a meaning.
local function OnMoneyAskedFor(index)
    local _, _, sender, subject, money = GetInboxHeaderInfo(index)
    if not money or money <= 0 then
        return
    end

    local invoice, itemName, _, _, _, _, cut, _, _, _, count = GetInboxInvoiceInfo(index)
    if invoice == "seller" then
        Expect(arriving, {
            kind = Trade.SALE,
            amount = money,
            name = itemName,
            count = count,
            cut = cut,
        })
    elseif sender and sender:find(AUCTION_SENDER, 1, true) then
        -- No invoice, but money, from the auction house: a bid handed
        -- back because someone bid higher or the seller withdrew.
        Expect(arriving, { kind = Trade.REFUND, amount = money, name = subject })
    end
end

-- Opening a letter's money by hand, and the "open all" button, go through
-- these two. Hooked after the fact: the letter still has its money in it
-- until the mailbox answers.
for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
    if _G[name] then
        hooksecurefunc(name, OnMoneyAskedFor)
    end
end

-- The item an auction is for, if the game will say.
local function ItemOfAuction(auctionID)
    if not C_AuctionHouse.GetAuctionInfoByID then
        return nil
    end

    local ok, info = pcall(C_AuctionHouse.GetAuctionInfoByID, auctionID)
    return ok and info and info.itemKey and info.itemKey.itemID or nil
end

-- A listing has been posted. Takes what asking the game for its deposit
-- came back with: whether it answered, and the figure. A listing that
-- costs nothing to post moves no coin, and so there's nothing to expect.
local function ExpectDeposit(answered, deposit)
    if not answered or not deposit then
        -- The game wouldn't say. A deposit is coming all the same.
        Expect(leaving, { kind = Trade.DEPOSIT })
    elseif deposit > 0 then
        Expect(leaving, { kind = Trade.DEPOSIT, amount = deposit })
    end
end

-- What the auction house lets a player ask of it, and what each will
-- cost them. Whatever isn't on this client is skipped.
local ASKS = {
    -- A bid, or a buyout, on one auction.
    PlaceBid = function(auctionID, amount)
        Expect(leaving, {
            kind = Trade.PURCHASE,
            amount = amount,
            itemID = ItemOfAuction(auctionID),
            count = 1,
        })
    end,

    -- So many of something that's sold from a pool. The price is settled
    -- by the auction house, so there's no amount to match on.
    ConfirmCommoditiesPurchase = function(itemID, quantity)
        Expect(leaving, { kind = Trade.PURCHASE, itemID = itemID, count = quantity })
    end,

    PostItem = function(location, duration, quantity)
        ExpectDeposit(pcall(C_AuctionHouse.CalculateItemDeposit, location, duration, quantity))
    end,

    PostCommodity = function(location, duration, quantity)
        ExpectDeposit(pcall(function()
            local itemID = C_Item.GetItemID(location)
            return C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity)
        end))
    end,
}

for name, onAsk in pairs(ASKS) do
    if C_AuctionHouse[name] then
        hooksecurefunc(C_AuctionHouse, name, onAsk)
    end
end

-- Matching ------------------------------------------------------------------------

-- Coin has arrived. Letters emptied one after another can land as one
-- sum, so take as many expected payments, oldest first, as it covers.
local function OnCoinArrived(amount)
    DropStale(arriving)

    while arriving[1] and arriving[1].amount <= amount do
        local expected = table.remove(arriving, 1)
        amount = amount - expected.amount
        File(expected.kind, expected.amount, expected)
    end
end

-- Coin has gone at the auction house. Whatever was asked for that costs
-- exactly this is the reason. Failing that, the oldest thing asked for
-- without a price; failing that, the oldest thing asked for at all, since
-- the figure we worked out may be a copper or two off. With nothing asked
-- for, it was a purchase made some way we don't watch, and still a
-- purchase.
local function OnCoinSpent(amount)
    DropStale(leaving)

    local match
    for index, expected in ipairs(leaving) do
        if expected.amount == amount then
            match = index
            break
        end
    end
    if not match then
        for index, expected in ipairs(leaving) do
            if not expected.amount then
                match = index
                break
            end
        end
    end
    if not match and leaving[1] then
        match = 1
    end

    local expected = match and table.remove(leaving, match) or nil
    File(expected and expected.kind or Trade.PURCHASE, amount, expected)
end

ns.Subscribe("MONEY_MOVED", function(delta, context)
    if delta > 0 then
        OnCoinArrived(delta)
    elseif context == "auction" then
        OnCoinSpent(-delta)
    end
end)

-- Reading it back -----------------------------------------------------------------

-- What a day came to. Sales arrive with the cut already taken and the
-- deposit handed back, so the only things to take off are what was bought
-- (less any bids returned) and what was paid in deposits.
local function Net(day)
    return day.sold - (day.bought - day.refunds) - day.deposits
end

--- What the auction house brought in and cost, for each day of a stretch.
---@param numDays number  how far back to look, counting today
---@return table days       list, oldest first and with every day present,
---        of { day, sold, bought, deposits, net } in copper. bought is
---        less any bids that were returned.
---@return number firstDay  the first day of the stretch
---@return number lastDay   the last: today
function Trade.Daily(numDays)
    local recorded = Book().days
    local today = ns.Ledger.Today()
    local firstDay = today - numDays + 1
    local days = {}

    for day = firstDay, today do
        local record = recorded[day]
        table.insert(days, {
            day = day,
            sold = record and record.sold or 0,
            bought = record and (record.bought - record.refunds) or 0,
            deposits = record and record.deposits or 0,
            net = record and Net(record) or 0,
        })
    end
    return days, firstDay, today
end

--- The same stretch, added up.
---@param numDays number
---@return table totals  { sold, bought, deposits, cut, net, sales }; bought
---        is less any bids that were returned
function Trade.Totals(numDays)
    local recorded = Book().days
    local today = ns.Ledger.Today()
    local totals = { sold = 0, bought = 0, deposits = 0, cut = 0, net = 0, sales = 0 }

    for day = today - numDays + 1, today do
        local record = recorded[day]
        if record then
            totals.sold = totals.sold + record.sold
            totals.bought = totals.bought + record.bought - record.refunds
            totals.deposits = totals.deposits + record.deposits
            totals.cut = totals.cut + record.cut
            totals.net = totals.net + Net(record)
            totals.sales = totals.sales + record.sales
        end
    end
    return totals
end

--- The latest sales, purchases and returned bids, newest first.
---@return table entries  list of { at, kind, amount, itemID, name, count }.
---        at is server time; itemID and name are each there only when
---        the game gave them.
function Trade.Recent()
    local recent = Book().recent
    local entries = {}
    for index = #recent, 1, -1 do
        table.insert(entries, recent[index])
    end
    return entries
end
