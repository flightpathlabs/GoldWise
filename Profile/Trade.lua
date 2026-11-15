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
-- to expect and why, and when the coin moves we match it up. Coin that
-- arrives with nothing expected is left to the Purse's plain totals. Coin
-- that leaves at the auction house is always something bought or a
-- deposit paid, so it's filed as a purchase even when we can't say of
-- what.
--
-- Kept by day for as long as price history is, with a short list of the
-- latest sales and purchases: once for the whole account, and once for
-- each character on their own. What was last paid for each item is kept
-- for the account only; it's a price, and any character can use it.

local Trade = {}
ns.Trade = Trade

Trade.SALE = "sale"
Trade.PURCHASE = "purchase"
Trade.DEPOSIT = "deposit"
Trade.REFUND = "refund"

-- Coin put down on an auction that may yet be outbid. It has left the
-- purse like a purchase, but nothing has been bought until it's won.
Trade.BID = "bid"

-- Seconds an expected payment is waited for. The mailbox and the auction
-- house both answer within a moment or two, when they answer at all.
local EXPECT_FOR = 15

-- A deposit we worked out can be a little off what the auction house
-- takes. Coin that left is put down to it when the two are within this
-- share of each other, and never further apart than a few copper on a
-- small one.
local DEPOSIT_TOLERANCE = 0.1
local DEPOSIT_TOLERANCE_LEAST = 10

-- The latest sales and purchases kept for the list on the Profit tab.
local RECENT_KEPT = 80

-- Who auction letters come from: "Alliance Auction House" and its like.
-- That's the English, and the game has no list of what they're called in
-- other languages.
local AUCTION_SENDER = "Auction House"

-- What it does have is how it words the subject of a letter handing a bid
-- back, in whatever language it's running: "Outbid on %s", and "Auction
-- cancelled: %s" when the seller withdrew.
local REFUND_SUBJECTS = { "AUCTION_OUTBID_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT" }

-- Those wordings as patterns to hold a subject against. Made on first use.
local refundPatterns

local function IsRefundSubject(subject)
    if not refundPatterns then
        refundPatterns = {}
        for _, name in ipairs(REFUND_SUBJECTS) do
            local wording = _G[name]
            if type(wording) == "string" and wording ~= "" then
                -- Mark where the item's name goes, make everything else
                -- literal, then let the name be anything.
                local pattern = wording:gsub("%%%d?%$?s", "\001")
                pattern = pattern:gsub("%p", "%%%0"):gsub("\001", ".+")
                table.insert(refundPatterns, "^" .. pattern .. "$")
            end
        end
    end

    for _, pattern in ipairs(refundPatterns) do
        if subject:find(pattern) then
            return true
        end
    end
    return false
end

-- Whether a letter with money in it and no invoice is the auction house
-- handing a bid back.
local function IsRefund(sender, subject)
    if sender and sender:find(AUCTION_SENDER, 1, true) then
        return true
    end
    return subject ~= nil and IsRefundSubject(subject)
end

-- Coin we've been given reason to expect, oldest first:
-- { kind, amount, at, itemID, name, count, cut, deposit }. Two queues,
-- because what's on its way in can't be confused with what's on its way
-- out.
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
    if type(book.paid) ~= "table" then
        book.paid = {}
    end
    return book
end

-- This character's own record: days and recent, as the account's are.
local function OwnBook()
    local book = Book()
    if type(book.characters) ~= "table" then
        book.characters = {}
    end

    local key = ns.Characters.CurrentKey()
    local own = book.characters[key]
    if type(own) ~= "table" then
        -- Before characters were kept apart there was only the account's
        -- record. On an account with one character, all of it is theirs.
        own = ns.Characters.IsOnlyOne()
                and { days = CopyTable(book.days), recent = CopyTable(book.recent) }
            or {}
        book.characters[key] = own
    end
    if type(own.days) ~= "table" then
        own.days = {}
    end
    if type(own.recent) ~= "table" then
        own.recent = {}
    end
    if type(own.hours) ~= "table" then
        own.hours = {}
    end
    return own
end

-- The record to read back. whose is true for the whole account, a
-- character's key for theirs, or nothing for the one being played.
-- Reading another character's never makes them a record.
local function BookFor(whose)
    if whose == true then
        return Book()
    end
    if not whose or whose == ns.Characters.CurrentKey() then
        return OwnBook()
    end
    local characters = Book().characters
    local theirs = characters and characters[whose]
    if type(theirs) ~= "table" then
        return { days = {}, recent = {} }
    end
    return { days = theirs.days or {}, recent = theirs.recent or {}, hours = theirs.hours or {} }
end

-- Recording -------------------------------------------------------------------

local SECONDS_PER_HOUR = 3600

-- Hours are kept as long as days are kept for the purse: a month.
local KEEP_HOURS = 30 * 24

-- What the auction house came to in this hour, in a book: [hour] = net
-- copper, where hour counts from the epoch. Finer than days, for charting
-- a short stretch of play. Kept from the version that brought it in, so
-- days go further back.
local function AddToHour(book, net)
    if type(book.hours) ~= "table" then
        book.hours = {}
    end
    local now = math.floor(GetServerTime() / SECONDS_PER_HOUR)
    if not book.hours[now] then
        -- A new hour is as good a moment as any to drop the oldest.
        for hour in pairs(book.hours) do
            if hour <= now - KEEP_HOURS then
                book.hours[hour] = nil
            end
        end
    end
    book.hours[now] = (book.hours[now] or 0) + net
end

-- Today's totals in a book: sold, bought, deposits, refunds and cut in
-- copper, and how many sales.
local function TodayIn(book)
    local days = book.days
    local today = ns.Ledger.Today()

    if not days[today] then
        days[today] = { sold = 0, bought = 0, deposits = 0, refunds = 0, cut = 0, sales = 0 }

        -- A new day is as good a moment as any to drop the oldest, and
        -- with it any note of what was paid for something that long ago.
        ns.Ledger.ForgetOldDays(days, ns.settings.historyDays)

        local oldest = GetServerTime() - ns.settings.historyDays * ns.SECONDS_PER_DAY
        local paid = Book().paid
        for itemID, last in pairs(paid) do
            if last.at < oldest then
                paid[itemID] = nil
            end
        end
    end
    return days[today]
end

local function RememberIn(book, entry)
    local recent = book.recent
    table.insert(recent, entry)
    while #recent > RECENT_KEPT do
        table.remove(recent, 1)
    end
end

-- Purchases put on record without word of what was bought: { entries,
-- amount, at }, where entries are the account's and this character's
-- copies on the list. The game may say what it was a moment later.
local unnamed = {}

-- What the game has said was just bought, before the coin for it was put
-- on record: { itemID, count, at }.
local justBought = {}

-- Purchases put on record already knowing what they were for: { itemID,
-- at }. The game's word on these is old news, and mustn't be taken for
-- word of another.
local alreadyNamed = {}

-- Seconds either waits for the other.
local PURCHASE_WAIT = 10

local function DropOld(list)
    local now = GetTime()
    while list[1] and now - list[1].at > PURCHASE_WAIT do
        table.remove(list, 1)
    end
end

-- Says what a purchase was for, on the list and as the price last paid.
local function Name(entries, amount, itemID, count)
    for _, entry in ipairs(entries) do
        entry.itemID = itemID
        entry.count = count
    end
    if count and count > 0 then
        Book().paid[itemID] = { each = amount / count, at = GetServerTime() }
    end
end

-- Puts one movement of coin on record, now that it has happened, in the
-- account's book and this character's.
local function File(kind, amount, expected)
    expected = expected or {}

    for _, book in ipairs({ Book(), OwnBook() }) do
        local day = TodayIn(book)
        if kind == Trade.SALE then
            -- A sale's letter holds the price less the auction house's
            -- cut, and the deposit handed back. That deposit was never
            -- spent, so it comes off what deposits cost rather than
            -- counting as something sold.
            local returned = math.min(expected.deposit or 0, amount)
            day.sold = day.sold + amount - returned
            day.returned = (day.returned or 0) + returned
            day.sales = day.sales + 1
            day.cut = day.cut + (expected.cut or 0)
        elseif kind == Trade.REFUND then
            day.refunds = day.refunds + amount
        elseif kind == Trade.DEPOSIT then
            day.deposits = day.deposits + amount
        else
            -- A purchase or a bid. Either way the coin has gone.
            day.bought = day.bought + amount
        end

        -- Coin in from a sale or a returned bid, out for the rest.
        local coming = kind == Trade.SALE or kind == Trade.REFUND
        AddToHour(book, coming and amount or -amount)
    end

    -- What the player paid for a thing is worth knowing the next time they
    -- wonder whether to sell it. Only where the game said what was bought
    -- and how many, and only once it's theirs: a bid can still come back.
    if kind == Trade.PURCHASE and expected.itemID and (expected.count or 0) > 0 then
        Book().paid[expected.itemID] = {
            each = amount / expected.count,
            at = GetServerTime(),
        }
    end

    -- Deposits are left off the list: one for every listing would bury
    -- the sales it's there to show. Each entry says whose it was, for
    -- the account's list.
    if kind ~= Trade.DEPOSIT then
        local entry = {
            at = GetServerTime(),
            kind = kind,
            amount = amount,
            itemID = expected.itemID,
            name = expected.name,
            count = expected.count,
            who = UnitName("player"),
        }
        local own = CopyTable(entry)
        RememberIn(Book(), entry)
        RememberIn(OwnBook(), own)

        if kind == Trade.PURCHASE and expected.itemID then
            -- Already known; the game's word on it, before or after, is
            -- no news.
            DropOld(justBought)
            local heard = false
            for index, bought in ipairs(justBought) do
                if bought.itemID == expected.itemID then
                    table.remove(justBought, index)
                    heard = true
                    break
                end
            end
            if not heard then
                DropOld(alreadyNamed)
                table.insert(alreadyNamed, { itemID = expected.itemID, at = GetTime() })
            end
        elseif kind == Trade.PURCHASE then
            -- No word of what it was for: the game may have said just
            -- before, or may say just after.
            DropOld(justBought)
            local bought = table.remove(justBought, 1)
            if bought then
                Name({ entry, own }, amount, bought.itemID, bought.count)
            else
                DropOld(unnamed)
                table.insert(unnamed, { entries = { entry, own }, amount = amount, at = GetTime() })
            end
        end
    end

    ns.Publish(
        "TRADE_CHANGED",
        kind,
        amount,
        expected.name,
        expected.count,
        expected.deposit,
        expected.itemID
    )
end

-- Expecting -------------------------------------------------------------------

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

    local invoice, itemName, _, _, _, deposit, cut, _, _, _, count = GetInboxInvoiceInfo(index)
    if invoice == "seller" then
        Expect(arriving, {
            kind = Trade.SALE,
            amount = money,
            name = itemName,
            count = count,
            cut = cut,
            deposit = deposit,
        })
    elseif IsRefund(sender, subject) then
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

-- The item an auction is for, and what buying it outright costs, if
-- the game will say.
local function AuctionDetails(auctionID)
    if not C_AuctionHouse.GetAuctionInfoByID then
        return nil
    end

    local ok, info = pcall(C_AuctionHouse.GetAuctionInfoByID, auctionID)
    if ok and info then
        return info.itemKey and info.itemKey.itemID, info.buyoutAmount
    end
end

-- A listing has been posted. Takes what asking the game for its deposit
-- came back with: whether it answered, and the figure. A listing that
-- costs nothing to post moves no coin, and so there's nothing to expect.
local function ExpectDeposit(itemID, answered, deposit)
    if not answered or not deposit then
        -- The game wouldn't say. A deposit is coming all the same.
        Expect(leaving, { kind = Trade.DEPOSIT, itemID = itemID })
    elseif deposit > 0 then
        Expect(leaving, { kind = Trade.DEPOSIT, amount = deposit, itemID = itemID })
    end
end

-- The item in a bag slot being posted, if the game will say.
local function PostedItem(location)
    local ok, itemID = pcall(C_Item.GetItemID, location)
    return ok and itemID or nil
end

-- What the auction house lets a player ask of it, and what each will
-- cost them. Whatever isn't on this client is skipped.
local ASKS = {
    -- A bid, or a buyout, on one auction. Both are placed the same way,
    -- and it's only a purchase when the sum is the buyout price. Where
    -- the game won't say what that is, it's taken for a bid: calling a
    -- purchase a bid costs a word, and the other way round puts a price
    -- paid on record for something never bought.
    PlaceBid = function(auctionID, amount)
        local itemID, buyout = AuctionDetails(auctionID)
        Expect(leaving, {
            kind = buyout == amount and Trade.PURCHASE or Trade.BID,
            amount = amount,
            itemID = itemID,
            count = 1,
        })
    end,

    -- So many of something that's sold from a pool. The price is settled
    -- by the auction house, so there's no amount to match on.
    ConfirmCommoditiesPurchase = function(itemID, quantity)
        Expect(leaving, { kind = Trade.PURCHASE, itemID = itemID, count = quantity })
    end,

    PostItem = function(location, duration, quantity)
        ExpectDeposit(
            PostedItem(location),
            pcall(C_AuctionHouse.CalculateItemDeposit, location, duration, quantity)
        )
    end,

    PostCommodity = function(location, duration, quantity)
        local itemID = PostedItem(location)
        ExpectDeposit(
            itemID,
            pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, quantity)
        )
    end,
}

for name, onAsk in pairs(ASKS) do
    if C_AuctionHouse[name] then
        hooksecurefunc(C_AuctionHouse, name, onAsk)
    end
end

-- The game says what was bought once a purchase goes through: one item
-- from an auction, or so many of something sold from a pool. Where the
-- coin for it was put on record without saying, it says so now.
local function Purchased(itemID, count)
    if not itemID then
        return
    end
    DropOld(alreadyNamed)
    for index, named in ipairs(alreadyNamed) do
        if named.itemID == itemID then
            table.remove(alreadyNamed, index)
            return
        end
    end
    DropOld(unnamed)
    local waiting = table.remove(unnamed, 1)
    if waiting then
        Name(waiting.entries, waiting.amount, itemID, count)
        ns.Publish("TRADE_CHANGED")
    else
        DropOld(justBought)
        table.insert(justBought, { itemID = itemID, count = count, at = GetTime() })
    end
end

ns.OnEvent("ITEM_PURCHASED", function(itemID)
    Purchased(itemID, 1)
end)
ns.OnEvent("COMMODITY_PURCHASED", function(itemID, quantity)
    Purchased(itemID, quantity)
end)

-- Matching --------------------------------------------------------------------

-- Coin has arrived at the mailbox. It's only ours to file when it's
-- exactly what a letter was expected to hold: the sum of one letter, or
-- of the oldest few together, since letters emptied one after another
-- can land as one. Anything else (a friend's gift between two sales, a
-- letter we were never told about) is left alone, and what was expected
-- waits its turn or goes stale.
local function OnCoinArrived(amount)
    DropStale(arriving)

    for index, expected in ipairs(arriving) do
        if expected.amount == amount then
            table.remove(arriving, index)
            File(expected.kind, expected.amount, expected)
            return
        end
    end

    local together, letters = 0, 0
    for index, expected in ipairs(arriving) do
        together = together + expected.amount
        if together >= amount then
            letters = together == amount and index or 0
            break
        end
    end
    for _ = 1, letters do
        local expected = table.remove(arriving, 1)
        File(expected.kind, expected.amount, expected)
    end
end

-- Coin has gone at the auction house. Whatever was asked for that costs
-- exactly this is the reason. Failing that, a deposit we worked out to
-- within a little of it. Failing that, the oldest thing asked for
-- without a price. And with none of those, it was a purchase made some
-- way we don't watch: still a purchase, of we don't know what.
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
        local near = math.max(DEPOSIT_TOLERANCE_LEAST, amount * DEPOSIT_TOLERANCE)
        for index, expected in ipairs(leaving) do
            local isDeposit = expected.kind == Trade.DEPOSIT and expected.amount ~= nil
            if isDeposit and math.abs(expected.amount - amount) <= near then
                match = index
                break
            end
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

    local expected = match and table.remove(leaving, match) or nil
    File(expected and expected.kind or Trade.PURCHASE, amount, expected)
end

ns.Subscribe("MONEY_MOVED", function(delta, category)
    -- Coin from a letter can land a moment after the mailbox is closed,
    -- so what matters is whether a letter's coin is expected, not where
    -- the player is standing. Only an exact sum is ever taken for it.
    if delta > 0 then
        OnCoinArrived(delta)
    elseif delta < 0 and category == "auction" then
        OnCoinSpent(-delta)
    end
end)

-- Reading it back -------------------------------------------------------------

-- What a day came to. Sales arrive with the cut already taken, so the
-- things to take off are what was bought (less any bids returned) and
-- what was paid in deposits (less any handed back with a sale).
--
-- Days from before handed-back deposits were kept apart have none on
-- record: their sales still include them, which comes to the same net.
local function Net(day)
    return day.sold + (day.returned or 0) - (day.bought - day.refunds) - day.deposits
end

-- What buying came to, less the bids that came back. A bid placed
-- before the stretch being looked at and returned within it would make
-- this less than nothing, which is true of the coin but nonsense as a
-- figure for "bought".
local function Bought(bought, refunds)
    return math.max(0, bought - refunds)
end

-- What deposits came to, less the ones handed back with a sale. Kept
-- from going below nothing for the same reason: a listing posted before
-- the stretch and sold within it.
local function Deposits(paid, returned)
    return math.max(0, paid - (returned or 0))
end

--- What the auction house brought in and cost, for each day of a stretch.
---@param numDays number  how far back to look, counting today
---@param whose boolean|string|nil  true for the whole account, a character's
---        key for theirs, nothing for the one being played
---@return table days       list, oldest first and with every day present,
---        of { day, sold, bought, deposits, net } in copper. sold is what
---        sales brought in after the cut; bought is less any bids that
---        were returned, and deposits less any handed back with a sale.
---@return number firstDay  the first day of the stretch
---@return number lastDay   the last: today
function Trade.Daily(numDays, whose)
    local recorded = BookFor(whose).days
    local today = ns.Ledger.Today()
    local firstDay = today - numDays + 1
    local days = {}

    for day = firstDay, today do
        local record = recorded[day]
        table.insert(days, {
            day = day,
            sold = record and record.sold or 0,
            bought = record and Bought(record.bought, record.refunds) or 0,
            deposits = record and Deposits(record.deposits, record.returned) or 0,
            net = record and Net(record) or 0,
        })
    end
    return days, firstDay, today
end

--- What the auction house came to over a run of equal stretches of time,
--- numbered as Purse.Flow numbers them. Stretches of a day go back as far
--- as the days do; shorter ones only as far as hours have been kept.
---@param hoursEach number  how long each stretch is: 24 for a day
---@param count number      how many stretches back, counting this one
---@param whose boolean|string|nil  as for Daily
---@return table values  net copper, one for each stretch from first to last
---@return number first
---@return number last
function Trade.Flow(hoursEach, count, whose)
    local nowHour = math.floor(GetServerTime() / SECONDS_PER_HOUR)
    local last = ns.Purse.StretchOf(nowHour, hoursEach)
    local first = last - count + 1
    local byStretch = {}

    if hoursEach == 24 then
        for day, record in pairs(BookFor(whose).days) do
            byStretch[day] = Net(record)
        end
    else
        local book = BookFor(whose)
        for hour, net in pairs(book.hours or {}) do
            local at = ns.Purse.StretchOf(hour, hoursEach)
            byStretch[at] = (byStretch[at] or 0) + net
        end
    end

    local values = {}
    for at = first, last do
        table.insert(values, byStretch[at] or 0)
    end
    return values, first, last
end

--- The same stretch, added up.
---@param numDays number
---@param whose boolean|string|nil  as for Daily
---@return table totals  { sold, bought, deposits, cut, net, sales }, with
---        bought and deposits less what came back of them, as for Daily
function Trade.Totals(numDays, whose)
    local recorded = BookFor(whose).days
    local today = ns.Ledger.Today()
    local totals = { sold = 0, bought = 0, deposits = 0, cut = 0, net = 0, sales = 0 }

    -- Bids and what came back of them are added up over the whole
    -- stretch before one is taken from the other: a bid on Monday that
    -- comes back on Tuesday was never spent. Likewise a deposit paid on
    -- Monday for something that sold on Tuesday.
    local bought, refunds = 0, 0
    local paid, returned = 0, 0

    for day = today - numDays + 1, today do
        local record = recorded[day]
        if record then
            totals.sold = totals.sold + record.sold
            bought, refunds = bought + record.bought, refunds + record.refunds
            paid, returned = paid + record.deposits, returned + (record.returned or 0)
            totals.cut = totals.cut + record.cut
            totals.net = totals.net + Net(record)
            totals.sales = totals.sales + record.sales
        end
    end

    totals.bought = Bought(bought, refunds)
    totals.deposits = Deposits(paid, returned)
    return totals
end

--- What the player last paid for an item at auction.
---@param itemID number
---@return number|nil each  copper per unit; nil if they haven't bought
---        any on record
---@return number|nil at    server time of the purchase
function Trade.LastPaid(itemID)
    local paid = Book().paid[itemID]
    if paid then
        return paid.each, paid.at
    end
end

--- The latest sales, purchases, bids and returned bids, newest first.
---@param whose boolean|string|nil  true for the whole account, a character's
---        key for theirs, nothing for the one being played
---@return table entries  list of { at, kind, amount, itemID, name, count,
---        who }. who is the character's name, on entries since it was kept.
---        at is server time; itemID and name are each there only when
---        the game gave them.
function Trade.Recent(whose)
    local recent = BookFor(whose).recent
    local entries = {}
    for index = #recent, 1, -1 do
        table.insert(entries, recent[index])
    end
    return entries
end
