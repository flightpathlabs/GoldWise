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
--
-- Each book also keeps what was traded of each item, by day, for a month:
-- how many were bought and for how much, how many sold and what they
-- brought in. A purchase is often only named a moment after its coin has
-- gone, so it's added to those then, once. The last two days of those are
-- kept one by one as well, with the time of each, so a session can be
-- added up from when it began rather than from midnight.

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
    if type(book.items) ~= "table" then
        book.items = {}
    end
    if type(book.itemsByName) ~= "table" then
        book.itemsByName = {}
    end
    if type(book.listed) ~= "table" then
        book.listed = {}
    end
    return book
end

-- This character's own record: days, recent and items, as the account's
-- are, and two things the account doesn't keep: latest, their trades of
-- the last two days one by one, and bids, the bids they have open.
local OWN_FIELDS = { "days", "recent", "hours", "items", "itemsByName", "latest", "bids" }

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
                and {
                    days = CopyTable(book.days),
                    recent = CopyTable(book.recent),
                    items = CopyTable(book.items),
                    itemsByName = CopyTable(book.itemsByName),
                }
            or {}
        book.characters[key] = own
    end
    for _, field in ipairs(OWN_FIELDS) do
        if type(own[field]) ~= "table" then
            own[field] = {}
        end
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
        return { days = {}, recent = {}, items = {}, itemsByName = {}, latest = {} }
    end
    return {
        days = theirs.days or {},
        recent = theirs.recent or {},
        hours = theirs.hours or {},
        hoursFrom = theirs.hoursFrom,
        items = theirs.items or {},
        itemsByName = theirs.itemsByName or {},
        latest = theirs.latest or {},
    }
end

-- The trades of the last two days to read back, as a list of lists:
-- everyone's for the account, which keeps none of its own.
local function LatestFor(whose)
    if whose ~= true then
        return { BookFor(whose).latest }
    end
    local lists = {}
    for _, own in pairs(Book().characters or {}) do
        if type(own) == "table" and type(own.latest) == "table" then
            table.insert(lists, own.latest)
        end
    end
    return lists
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
    book.hoursFrom = book.hoursFrom or now
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

-- The prices paid by name: [name] = itemID, made when first needed. Let
-- go of whenever the prices paid change, so it's made again.
local paidByName

-- Names the player's own listings were posted under, kept as long as the
-- item totals are: [name] = { itemID, at }.
local KEEP_LISTED_DAYS = 30

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
        paidByName = nil

        local oldestListed = GetServerTime() - KEEP_LISTED_DAYS * ns.SECONDS_PER_DAY
        local listed = Book().listed
        for name, listing in pairs(listed) do
            if type(listing) ~= "table" or (listing[2] or 0) < oldestListed then
                listed[name] = nil
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

-- Item totals are kept a month, as the hours are, and never longer than
-- the days.
local KEEP_ITEM_DAYS = 30

-- What was traded of one thing on one day, in a book: { bought, paid,
-- sold, brought, deposits }. bought and sold are how many; paid is the
-- copper spent on them, brought what their sales came to after the cut
-- and without the deposit handed back. deposits is what was paid to list
-- it, less what came back with a sale, and so can be less than nothing on
-- a day something listed earlier sold.
--
-- Kept by item ID in items, and in itemsByName by the name a sale's
-- letter gave, for a sale of something that couldn't be put to an ID.
local function ItemRecord(book, day, key, byName)
    local field = byName and "itemsByName" or "items"
    if type(book[field]) ~= "table" then
        book[field] = {}
    end
    local days = book[field]
    if not days[day] then
        -- A new day is as good a moment as any to drop the oldest.
        ns.Ledger.ForgetOldDays(days, math.min(KEEP_ITEM_DAYS, ns.settings.historyDays))
        days[day] = {}
    end

    local record = days[day][key]
    if not record then
        record = { bought = 0, paid = 0, sold = 0, brought = 0, deposits = 0 }
        days[day][key] = record
    end
    return record
end

-- Trades are kept one by one for this long, for periods that don't start
-- at midnight.
local KEEP_EXACT = 48 * 60 * 60

-- Lets go of trades more than two days gone.
local function TrimLatest(list)
    local oldest = GetServerTime() - KEEP_EXACT
    local kept = 0
    for index = 1, #list do
        local entry = list[index]
        if type(entry) == "table" and (entry[1] or 0) >= oldest then
            kept = kept + 1
            list[kept] = entry
        end
    end
    for index = #list, kept + 1, -1 do
        list[index] = nil
    end
end

-- One trade of one thing, for this character's last two days: { at, key,
-- bought, paid, sold, brought, deposits }, the figures as an item's day
-- has them. key is the item's ID, or the name a sale's letter gave when
-- that couldn't be put to one. Mostly in the order they happened, though
-- a bid that won is put down at the time it was placed.
local function NoteLatest(at, key, bought, paid, sold, brought, deposits)
    local latest = OwnBook().latest
    table.insert(latest, { at, key, bought, paid, sold, brought, deposits })
    TrimLatest(latest)
end

-- So many of something bought, for so much, at the time the coin went.
-- Each purchase must come through here once and no more: what calls it
-- makes sure of that.
local function CountBought(itemID, count, paid, at)
    local day = ns.Ledger.DayOf(at)
    for _, book in ipairs({ Book(), OwnBook() }) do
        local record = ItemRecord(book, day, itemID)
        record.bought = record.bought + count
        record.paid = record.paid + paid
    end
    NoteLatest(at, itemID, count, paid, 0, 0, 0)
end

-- Buyouts and bids the player placed, and pool purchases they confirmed,
-- put on record and waiting for the game to say they went through:
-- { entries, amount, itemID, auctionID, pool, done, counted, paidAt,
-- openBid, at }. entries are the account's and this character's copies on
-- the list; itemID is what we were told it was for, if anything;
-- auctionID is the auction bid on; pool marks a purchase from a pool;
-- done marks a buyout the game has said went through, still waiting to
-- hear what it was; counted marks one already in the item totals, and
-- paidAt is the server time its coin went. openBid is a bid's place among
-- the bids kept open, until it turns out to have been a buyout. Only these are
-- ever named from the game's word: coin that left without being asked
-- for is left as it is.
--
-- The game says a buyout went through by its auction, and what was bought
-- by its item, in two separate words that can come in either order, and
-- either before or after the coin. A bid that wasn't a buyout gets
-- neither, and stays a bid.
local awaiting = {}

-- What the game has said before the coin for it was put on record:
-- auctions bought out, [auctionID] = when; items bought from auctions and
-- from pools, { itemID, count, at }.
local boughtOut = {}
local heardItems = {}
local heardPools = {}

-- Buyouts settled already knowing their item, whose own word from the
-- game hasn't come yet: { itemID, at }. When it comes, it's theirs, and
-- mustn't be taken for word of another.
local namedItems = {}

-- Purchases from pools just settled: { itemID, at }. The game may yet say
-- "item purchased" for one, and that isn't word of a buyout.
local settledPools = {}

-- Seconds either waits for the other.
local PURCHASE_WAIT = 10

local function DropOld(list)
    local now = GetTime()
    while list[1] and now - list[1].at > PURCHASE_WAIT do
        table.remove(list, 1)
    end
end

-- A purchase from a pool has been settled. The game's "item purchased"
-- for it can still be on its way.
local function SettledPool(itemID)
    DropOld(settledPools)
    table.insert(settledPools, { itemID = itemID, at = GetTime() })
end

-- Notes what one of something was last bought for, at the auction house
-- or from a vendor, so a sale of it later can say what it cost.
-- Prices paid are kept as long as price history is, like the days.
--
-- count is how many that purchase was for, so the Assets tab can weigh
-- only as many as were bought against what they'd fetch, not a whole
-- farmed stack beside one bought. A purchase can be noted from more than
-- one place as the game's word comes in, so each noting replaces the
-- last rather than adding to it.
local function NotePaid(itemID, each, from, count)
    local paid = Book().paid
    paid[itemID] = {
        each = each,
        count = count or 1,
        at = GetServerTime(),
        name = ns.ItemName(itemID) or C_Item.GetItemNameByID(itemID),
        from = from,
    }
    local oldest = GetServerTime() - ns.settings.historyDays * ns.SECONDS_PER_DAY
    for other, record in pairs(paid) do
        if (record.at or 0) < oldest then
            paid[other] = nil
        end
    end
    paidByName = nil
end

-- What was last paid for something, found by its name, which is all a
-- sale's letter gives: { each, at, name }, and its item ID.
local function PaidFor(name)
    if not name then
        return nil
    end
    local index = paidByName
    if not index then
        -- Kept only when every name was known. One the client hasn't
        -- loaded yet would otherwise stay missing from it.
        index = {}
        local complete = true
        for itemID, record in pairs(Book().paid) do
            local known = record.name or C_Item.GetItemNameByID(itemID)
            if known then
                index[known] = itemID
            else
                complete = false
            end
        end
        paidByName = complete and index or nil
    end
    local itemID = index[name]
    if itemID and Book().paid[itemID] then
        return Book().paid[itemID], itemID
    end
end

-- Names from sales' letters already put to an item this session, and
-- names that couldn't be. Those are tried again once the client has
-- loaded more names, though not more than once a minute: searching the
-- names written down for each of them isn't free.
local namedIDs, unnamed = {}, {}
local RETRY_NAMES_EVERY = 60
local namesTriedAt, retryPending = 0, false

local function RetryNames()
    retryPending = false
    namesTriedAt = GetTime()
    wipe(unnamed)
end

ns.Subscribe("ITEM_NAMES_LOADED", function()
    if retryPending or not next(unnamed) then
        return
    end
    local wait = namesTriedAt + RETRY_NAMES_EVERY - GetTime()
    if wait <= 0 then
        RetryNames()
    else
        retryPending = true
        C_Timer.After(wait, RetryNames)
    end
end)

-- The player's own listing of something, under the name its sale's
-- letter will give, so the sale lands with its deposit.
local function RememberListed(itemID, name)
    name = name or (itemID and ns.ItemName(itemID))
    if not itemID or not name then
        return
    end
    Book().listed[name] = { itemID, GetServerTime() }
    namedIDs[name] = itemID
    unnamed[name] = nil
end

-- Listings read at the auction house carry their names too, which covers
-- those posted before the names were kept, or from another addon's
-- window.
ns.Subscribe("LISTINGS_READ", function(_, auctions)
    for _, auction in pairs(auctions or {}) do
        if auction.itemID and auction.name then
            RememberListed(auction.itemID, auction.name)
        end
    end
end)

-- The one item the names written down give this name to, if only one.
-- Two things can share a name, and then it isn't for us to pick.
local function OnlyItemNamed(name)
    local lowered, found = name:lower(), nil
    for _, match in ipairs(ns.Names.Search(name)) do
        if match.name and match.name:lower() == lowered then
            if found then
                return nil
            end
            found = match.itemID
        end
    end
    return found
end

-- The item a sale's letter means, which gives only its name. Something
-- the player listed under that name is the likeliest, then something
-- bought; otherwise any name Goldwise has written down.
local function ItemNamed(name)
    if not name or unnamed[name] then
        return nil
    end
    if namedIDs[name] then
        return namedIDs[name]
    end

    local listing = Book().listed[name]
    local itemID = type(listing) == "table" and listing[1] or nil
    if not itemID then
        local _, paidID = PaidFor(name)
        itemID = paidID or OnlyItemNamed(name)
    end
    if itemID then
        namedIDs[name] = itemID
    else
        unnamed[name] = true
    end
    return itemID
end

-- Bids the player has open, in their own book: { at, amount, itemID },
-- where at is the server time the coin went. A bid that wins is only
-- known to have when the letter with the item in it is opened, perhaps
-- days later, so it's kept until then, or until its coin comes back or
-- it's too old to be waiting still.
local BID_KEPT = 3 * ns.SECONDS_PER_DAY

local function OpenBids()
    local bids = OwnBook().bids
    local oldest = GetServerTime() - BID_KEPT
    for index = #bids, 1, -1 do
        local bid = bids[index]
        if type(bid) ~= "table" or (bid.at or 0) < oldest then
            table.remove(bids, index)
        end
    end
    return bids
end

local function ForgetBid(bid)
    local bids = OwnBook().bids
    for index, open in ipairs(bids) do
        if open == bid then
            table.remove(bids, index)
            return
        end
    end
end

-- What was on record as a bid was a buyout after all. The day's totals
-- already count the coin as spent either way. It's no longer an open
-- bid, so the letter its item comes in won't count it a second time.
local function MarkBought(waiting)
    for _, entry in ipairs(waiting.entries) do
        entry.kind = Trade.PURCHASE
    end
    if waiting.openBid then
        ForgetBid(waiting.openBid)
        waiting.openBid = nil
    end
end

-- The game has said a purchase went through: it was for this, so many
-- of them.
--
-- This is where a purchase named after its coin is added to the item
-- totals. Every caller has taken the waiting purchase off the list first,
-- or never put it there, so nothing settles twice; and one already counted
-- when its coin was filed, because the asking named it, says so.
local function Settle(waiting, itemID, count)
    count = count or 1
    MarkBought(waiting)
    for _, entry in ipairs(waiting.entries) do
        entry.itemID = itemID
        entry.count = count
    end
    if count > 0 then
        NotePaid(itemID, waiting.amount / count, "auction", count)
        if not waiting.counted then
            waiting.counted = true
            CountBought(itemID, count, waiting.amount, waiting.paidAt)
        end
    end
end

-- Takes the oldest word heard of an item, or of any item if itemID is nil.
local function TakeHeard(list, itemID)
    DropOld(list)
    for index, heard in ipairs(list) do
        if not itemID or heard.itemID == itemID then
            return table.remove(list, index)
        end
    end
end

local function Wait(waiting)
    DropOld(awaiting)
    table.insert(awaiting, waiting)
end

-- A buyout has gone through. If we know what it was for, that's settled;
-- if not, the game's word on its item may already be here, or may yet
-- come.
local function BoughtOut(waiting)
    if waiting.itemID then
        Settle(waiting, waiting.itemID, 1)
        if not waiting.heard and not TakeHeard(heardItems, waiting.itemID) then
            DropOld(namedItems)
            table.insert(namedItems, { itemID = waiting.itemID, at = GetTime() })
        end
        return
    end
    local heard = TakeHeard(heardItems)
    if heard then
        Settle(waiting, heard.itemID, 1)
    else
        MarkBought(waiting)
        waiting.done = true
        -- Put back as the newest, so it's let go in its turn.
        waiting.at = GetTime()
        Wait(waiting)
    end
end

-- Buying from a vendor is a cost too: something bought to sell on at
-- auction should say so when it sells. Noted once the coin has left, so a
-- purchase that didn't go through (full bags, too little coin) isn't.
local vendorBuys = {}

hooksecurefunc("BuyMerchantItem", function(index, quantity)
    local itemID = GetMerchantItemID(index)
    local info = itemID and C_MerchantFrame.GetItemInfo(index)
    if info and not info.hasExtendedCost and (info.price or 0) > 0 then
        local each = info.price / math.max(info.stackCount or 1, 1)
        local count = math.max(1, tonumber(quantity) or info.stackCount or 1)
        table.insert(
            vendorBuys,
            { itemID = itemID, each = each, count = count, total = each * count, at = GetTime() }
        )
    end
end)

ns.Subscribe("MONEY_MOVED", function(delta, category)
    if delta >= 0 or #vendorBuys == 0 or (category ~= "vendor" and category ~= "other") then
        return
    end
    DropOld(vendorBuys)
    for index, buy in ipairs(vendorBuys) do
        if math.abs(-delta - buy.total) <= 1 then
            table.remove(vendorBuys, index)
            NotePaid(buy.itemID, buy.each, "vendor", buy.count)
            CountBought(buy.itemID, buy.count, -delta, GetServerTime())
            return
        end
    end
end)

-- Puts one movement of coin on record, now that it has happened, in the
-- account's book and this character's.
local function File(kind, amount, expected)
    expected = expected or {}
    local now = GetServerTime()
    local today = ns.Ledger.DayOf(now)

    -- What a sale was of, by its name, for the item totals: put to an
    -- item once, here, and kept by that name when it can't be.
    local soldID = kind == Trade.SALE and ItemNamed(expected.name)
    local returned = kind == Trade.SALE and math.min(expected.deposit or 0, amount) or 0

    local soldKey = kind == Trade.SALE and (soldID or expected.name) or nil

    if soldKey then
        local brought = amount - returned
        NoteLatest(now, soldKey, 0, 0, expected.count or 1, brought, -returned)
    elseif kind == Trade.DEPOSIT and expected.itemID then
        NoteLatest(now, expected.itemID, 0, 0, 0, 0, amount)
    elseif kind == Trade.REFUND then
        -- A bid handed back is no longer open. Which one isn't said, so
        -- it's the oldest for as much.
        local bids = OpenBids()
        for index, bid in ipairs(bids) do
            if bid.amount == amount then
                table.remove(bids, index)
                break
            end
        end
    end

    for _, book in ipairs({ Book(), OwnBook() }) do
        local day = TodayIn(book)
        if kind == Trade.SALE then
            -- A sale's letter holds the price less the auction house's
            -- cut, and the deposit handed back. That deposit was never
            -- spent, so it comes off what deposits cost rather than
            -- counting as something sold.
            day.sold = day.sold + amount - returned
            day.returned = (day.returned or 0) + returned
            day.sales = day.sales + 1
            day.cut = day.cut + (expected.cut or 0)

            if soldKey then
                local item = ItemRecord(book, today, soldKey, not soldID)
                item.sold = item.sold + (expected.count or 1)
                item.brought = item.brought + amount - returned
                item.deposits = item.deposits - returned
            end
        elseif kind == Trade.REFUND then
            day.refunds = day.refunds + amount
        elseif kind == Trade.DEPOSIT then
            day.deposits = day.deposits + amount
            if expected.itemID then
                local item = ItemRecord(book, today, expected.itemID)
                item.deposits = item.deposits + amount
            end
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
    -- Named already, it goes into the item totals now, and the game's word
    -- on it later mustn't add it again.
    local counted = false
    if kind == Trade.PURCHASE and expected.itemID and (expected.count or 0) > 0 then
        NotePaid(expected.itemID, amount / expected.count, "auction", expected.count)
        CountBought(expected.itemID, expected.count, amount, now)
        counted = true
    end

    -- Deposits are left off the list: one for every listing would bury
    -- the sales it's there to show. Each entry says whose it was, for
    -- the account's list.
    if kind ~= Trade.DEPOSIT then
        local entry = {
            at = now,
            kind = kind,
            amount = amount,
            itemID = expected.itemID,
            name = expected.name,
            count = expected.count,
            who = UnitName("player"),
        }

        -- A sale of something bought earlier says what that cost, and so
        -- what was left over: what the letter held, less the deposit
        -- handed back with it, less what was paid.
        if kind == Trade.SALE then
            local paid, itemID = PaidFor(expected.name)
            entry.itemID = entry.itemID or soldID or itemID
            entry.deposit = math.min(expected.deposit or 0, amount)
            if paid and paid.each then
                entry.cost = math.floor(paid.each * (expected.count or 1) + 0.5)
                entry.profit = amount - entry.deposit - entry.cost
            end
        end
        local own = CopyTable(entry)
        RememberIn(Book(), entry)
        RememberIn(OwnBook(), own)

        -- Something the player asked to buy: the game says what went
        -- through, just before the coin or just after. Its word settles
        -- what it was, and whether a bid was a buyout.
        if expected.asked and (kind == Trade.PURCHASE or kind == Trade.BID) then
            local waiting = {
                entries = { entry, own },
                amount = amount,
                itemID = expected.itemID,
                auctionID = expected.auctionID,
                pool = expected.pool,
                heard = expected.heard,
                -- Known to be a bid and not a buyout: the game said what
                -- the buyout was, and this wasn't it. Word of a buyout on
                -- the same auction is never this one's.
                bid = kind == Trade.BID and expected.itemID ~= nil,
                -- Whether it's in the item totals yet, and when the coin
                -- went, which is when it goes under once it is.
                counted = counted,
                paidAt = now,
                at = GetTime(),
            }
            if kind == Trade.BID then
                -- Kept open until it's known to have been a buyout, it's
                -- handed back, or its item arrives by post.
                local bid = { at = now, amount = amount, itemID = expected.itemID }
                table.insert(OpenBids(), bid)
                waiting.openBid = bid
            end
            if waiting.pool then
                local heard = TakeHeard(heardPools, waiting.itemID)
                if heard then
                    Settle(waiting, heard.itemID, heard.count)
                    SettledPool(heard.itemID)
                else
                    Wait(waiting)
                end
            else
                local saidAt = waiting.auctionID and boughtOut[waiting.auctionID]
                if waiting.auctionID then
                    boughtOut[waiting.auctionID] = nil
                end
                if saidAt and GetTime() - saidAt <= PURCHASE_WAIT then
                    BoughtOut(waiting)
                else
                    Wait(waiting)
                end
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

-- Puts the copies of a bid on the latest list down as a purchase.
local function MarkWon(bid, itemID, count)
    for _, book in ipairs({ Book(), OwnBook() }) do
        for _, entry in ipairs(book.recent) do
            if entry.kind == Trade.BID and entry.at == bid.at and entry.amount == bid.amount then
                entry.kind = Trade.PURCHASE
                entry.itemID = entry.itemID or itemID
                entry.count = count
                break
            end
        end
    end
end

-- The player, or an addon on their behalf, has asked for what's in a
-- letter. A letter from the auction house with something they won in it
-- is the only word there is that a bid won, so that's when the bid is
-- put down as bought, at the time its coin went. Only a bid still open
-- will do. A buyout comes in such a letter too, but it was counted when
-- it went through and is no longer open, so it isn't counted again.
local function OnItemAskedFor(index, attachment)
    local bids = OpenBids()
    if #bids == 0 then
        return
    end
    local invoice, _, _, paid, _, _, _, _, _, _, count = GetInboxInvoiceInfo(index)
    if invoice ~= "buyer" or not paid or paid <= 0 then
        return
    end
    local _, attachedID, _, attached = GetInboxItem(index, attachment or 1)

    for position, bid in ipairs(bids) do
        local sameItem = not bid.itemID or not attachedID or bid.itemID == attachedID
        if bid.amount == paid and sameItem then
            table.remove(bids, position)
            local itemID = bid.itemID or attachedID
            count = count or attached or 1
            if itemID and count > 0 then
                NotePaid(itemID, paid / count, "auction", count)
                CountBought(itemID, count, paid, bid.at)
            end
            MarkWon(bid, itemID, count)
            ns.Publish("TRADE_CHANGED")
            return
        end
    end
end

for _, name in ipairs({ "TakeInboxItem", "AutoLootMailItem" }) do
    if _G[name] then
        hooksecurefunc(name, OnItemAskedFor)
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
    RememberListed(itemID)
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
            asked = true,
            auctionID = auctionID,
        })
    end,

    -- So many of something that's sold from a pool. The price is settled
    -- by the auction house, so there's no amount to match on.
    ConfirmCommoditiesPurchase = function(itemID, quantity)
        Expect(leaving, {
            kind = Trade.PURCHASE,
            itemID = itemID,
            count = quantity,
            asked = true,
            pool = true,
        })
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

-- Finds and takes a waiting purchase that fits: the oldest, or with
-- newest set, the latest.
local function TakeWaiting(fits, newest)
    DropOld(awaiting)
    local from, to, step = 1, #awaiting, 1
    if newest then
        from, to, step = #awaiting, 1, -1
    end
    for index = from, to, step do
        if fits(awaiting[index]) then
            return table.remove(awaiting, index)
        end
    end
end

-- Whether something was just bought from a pool, by the player's asking
-- or the game's word. The game may also say "item purchased" for it,
-- which is no word of a buyout.
local function FromPool(itemID)
    for _, list in ipairs({ awaiting, heardPools, settledPools }) do
        DropOld(list)
        for _, entry in ipairs(list) do
            if entry.itemID == itemID and (list ~= awaiting or entry.pool) then
                return true
            end
        end
    end
    for _, expected in ipairs(leaving) do
        if expected.pool and expected.itemID == itemID then
            return true
        end
    end
    return false
end

-- A buyout went through, by its auction.
ns.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    -- A bid and then a buyout on one auction share its ID. The buyout is
    -- the later.
    local waiting = TakeWaiting(function(candidate)
        return not candidate.pool and not candidate.bid and candidate.auctionID == auctionID
    end, true)
    if waiting then
        BoughtOut(waiting)
        ns.Publish("TRADE_CHANGED")
    else
        -- Kept for its coin, a moment away; older ones are let go.
        local now = GetTime()
        for other, at in pairs(boughtOut) do
            if now - at > PURCHASE_WAIT then
                boughtOut[other] = nil
            end
        end
        boughtOut[auctionID] = now
    end
end)

-- What a buyout was for. It goes to one already said to have gone through
-- and still unnamed; otherwise it's kept for the buyout it belongs to.
ns.OnEvent("ITEM_PURCHASED", function(itemID)
    if FromPool(itemID) then
        return
    end

    -- The word for a buyout already settled knowing its item.
    if TakeHeard(namedItems, itemID) then
        return
    end

    -- Or for one we know the item of, still waiting to hear it went
    -- through, or whose coin hasn't come yet.
    DropOld(awaiting)
    for _, candidate in ipairs(awaiting) do
        if
            not candidate.pool
            and not candidate.bid
            and not candidate.done
            and candidate.itemID == itemID
        then
            candidate.heard = true
            return
        end
    end
    for _, expected in ipairs(leaving) do
        if
            expected.asked
            and not expected.pool
            and expected.kind ~= Trade.BID
            and expected.itemID == itemID
            and not expected.heard
        then
            expected.heard = true
            return
        end
    end

    local waiting = TakeWaiting(function(candidate)
        return candidate.done and not candidate.itemID
    end)
    if waiting then
        Settle(waiting, itemID, 1)
        ns.Publish("TRADE_CHANGED")
    else
        DropOld(heardItems)
        table.insert(heardItems, { itemID = itemID, at = GetTime() })
    end
end)

-- So many of something bought from a pool.
ns.OnEvent("COMMODITY_PURCHASED", function(itemID, quantity)
    local waiting = TakeWaiting(function(candidate)
        return candidate.pool and candidate.itemID == itemID
    end)
    if waiting then
        Settle(waiting, itemID, quantity)
        SettledPool(itemID)
        ns.Publish("TRADE_CHANGED")
    else
        DropOld(heardPools)
        table.insert(heardPools, { itemID = itemID, count = quantity, at = GetTime() })
    end
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

--- From when the auction house's trades are complete hour by hour, where
--- days on record go back further than that: a version before 0.5.0 kept
--- only days. Nil when the hours miss nothing the days have.
---@param whose boolean|string|nil  as for Daily
---@return number|nil hour  hours since the epoch
function Trade.HourlySince(whose)
    local book = BookFor(whose)
    local firstDay
    for day in pairs(book.days or {}) do
        if not firstDay or day < firstDay then
            firstDay = day
        end
    end
    if not firstDay then
        return nil
    end

    local since = book.hoursFrom
    for hour in pairs(book.hours or {}) do
        if not since or hour < since then
            since = hour
        end
    end
    since = since or math.floor(GetServerTime() / SECONDS_PER_HOUR)

    if firstDay < ns.Purse.StretchOf(since, 24) then
        return since
    end
    return nil
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

--- What the player last paid for an item, at auction or from a vendor.
---@param itemID number
---@return number|nil each  copper per unit; nil if they haven't bought
---        any on record
---@return number|nil at    server time of the purchase
---@return string|nil from  "auction" or "vendor", where the game said
---@return number|nil count  how many that purchase was for; nil for
---        purchases noted before it was kept
function Trade.LastPaid(itemID)
    local paid = Book().paid[itemID]
    if paid then
        return paid.each, paid.at, paid.from, paid.count
    end
end

--- The latest sales, purchases, bids and returned bids, newest first.
---@param whose boolean|string|nil  true for the whole account, a character's
---        key for theirs, nothing for the one being played
---@return table entries  list of { at, kind, amount, itemID, name, count,
---        who, deposit, cost, profit }. who is the character's name, on
---        entries since it was kept. at is server time; itemID and name
---        are each there only when the game gave them. A sale of something
---        whose price paid is known has cost, what was paid for it, and
---        profit, what was left after that and the deposit handed back.
function Trade.Recent(whose)
    local recent = BookFor(whose).recent
    local entries = {}
    for index = #recent, 1, -1 do
        local entry = recent[index]
        -- A sale put on record before costs were kept, of something whose
        -- price was noted before it sold, can say what it cost now.
        -- What the deposit handed back with it was isn't known for those,
        -- so they say what it cost but not what was left.
        if entry.kind == Trade.SALE and not entry.cost then
            local paid, itemID = PaidFor(entry.name)
            if paid and paid.each and (paid.at or 0) <= (entry.at or 0) then
                entry.itemID = entry.itemID or itemID
                entry.cost = math.floor(paid.each * (entry.count or 1) + 0.5)
                if entry.deposit then
                    entry.profit = entry.amount - entry.deposit - entry.cost
                end
            end
        end
        table.insert(entries, entry)
    end
    return entries
end

-- How many of an item there are to hand. For the one being played, their
-- bags and banks as Bank.Held counts them; for the account, every other
-- character's bags as well, as of their last login. Nil for another
-- character on their own: their bags are kept by name, not by key.
local function HeldBy(whose, itemID)
    if whose == true then
        local held = ns.Bank.Held(itemID)
        for _, holder in ipairs(ns.Characters.HoldersOf(itemID)) do
            held = held + holder.count
        end
        return held
    end
    if not whose or whose == ns.Characters.CurrentKey() then
        return ns.Bank.Held(itemID)
    end
end

local ITEM_FIELDS = { "bought", "paid", "sold", "brought", "deposits" }

-- Adds one record of an item to its running total: a day's, or one
-- trade's from the last two days, whose figures are in ITEM_FIELDS' order
-- after its time and key.
local function AddUp(totals, key, record, offset)
    local total = totals[key]
    if not total then
        total = { bought = 0, paid = 0, sold = 0, brought = 0, deposits = 0 }
        totals[key] = total
    end
    for index, field in ipairs(ITEM_FIELDS) do
        local value = offset and record[offset + index] or record[field]
        total[field] = total[field] + (value or 0)
    end
    return total
end

-- Whether a period can be added up trade by trade: it began within the
-- last two days, and since trades were kept that way.
local function Exact(sinceTime)
    local from = Book().latestFrom
    return sinceTime ~= nil
        and from ~= nil
        and sinceTime >= from
        and GetServerTime() - sinceTime <= KEEP_EXACT
end

--- What was traded of each item over a stretch: bought at auction or from
--- a vendor, and sold at auction. A stretch that began in the last two
--- days is counted from sinceTime to the second. Further back it's kept by
--- day, so the stretch starts at the beginning of the day sinceTime falls
--- on, and goes back a month at most.
---@param sinceTime number|nil  server time; everything kept if left out
---@param whose boolean|string|nil  as for Daily
---@return table items  list of { itemID, name, bought, paid, sold,
---        brought, lost, cost, profit, held }, biggest profit or loss
---        first. bought and sold are how many; paid, brought, lost, cost
---        and profit are copper. brought is what sales came to after the
---        cut, less lost: the deposits paid to list it that weren't handed
---        back, which includes any on listings still up. cost is what the
---        ones sold cost: at the stretch's average price paid for as many
---        as were bought in it, and for any more, what was last paid for
---        one before the stretch began. Something never bought cost
---        nothing. profit is brought less cost. held is how many there are
---        now, as for the current character's bags and banks or, for the
---        account, everyone's bags too; nil for another character. A sale
---        whose letter's name couldn't be put to an item has no itemID or
---        held. name can be missing until the client has loaded the item.
function Trade.Items(sinceTime, whose)
    local byID, byName = {}, {}

    -- A sale kept by name may be put to an item now, from what's been
    -- listed, bought or seen since.
    local function Count(key, record, offset)
        if type(key) == "number" then
            AddUp(byID, key, record, offset)
            return
        end
        local itemID = ItemNamed(key)
        local total = itemID and AddUp(byID, itemID, record, offset)
            or AddUp(byName, key, record, offset)
        total.name = total.name or key
    end

    -- When the stretch began, for what was paid before it.
    local from
    if Exact(sinceTime) then
        from = sinceTime
        for _, list in ipairs(LatestFor(whose)) do
            for _, entry in ipairs(list) do
                if (entry[1] or 0) >= sinceTime and entry[2] then
                    Count(entry[2], entry, 2)
                end
            end
        end
    else
        local book = BookFor(whose)
        local firstDay = ns.Ledger.DayOf(sinceTime or 0)
        local earliest = ns.Ledger.Today()
        for _, field in ipairs({ "items", "itemsByName" }) do
            for day, records in pairs(book[field] or {}) do
                if day >= firstDay then
                    earliest = math.min(earliest, day)
                    for key, record in pairs(records) do
                        Count(key, record)
                    end
                end
            end
        end
        from = (sinceTime and firstDay or earliest) * ns.SECONDS_PER_DAY - ns.ClockOffset()
    end

    local list = {}
    local function Add(itemID, name, total)
        -- deposits is what listing it cost in the stretch, less what came
        -- back with its sales. A sale can hand back the deposit on a
        -- listing posted before the stretch began, and which listing a
        -- sale was isn't kept, so that comes off deposits paid within the
        -- stretch as well and can hide one lost. It's never let make lost
        -- less than nothing.
        local lost = math.max(0, total.deposits)
        if total.bought == 0 and total.sold == 0 and lost == 0 then
            return
        end

        local brought = total.brought - lost
        local cost = 0
        if total.bought > 0 then
            cost = total.paid / total.bought * math.min(total.sold, total.bought)
        end
        -- More sold than were bought in the stretch: the rest were bought
        -- before it, or farmed. What was last paid says which, as long as
        -- that was before the stretch, and so isn't one of those above.
        local beyond = total.sold - total.bought
        if itemID and beyond > 0 then
            local each, paidAt = Trade.LastPaid(itemID)
            if each and paidAt and paidAt < from then
                cost = cost + each * beyond
            end
        end

        table.insert(list, {
            itemID = itemID,
            name = name,
            bought = total.bought,
            paid = total.paid,
            sold = total.sold,
            brought = brought,
            lost = lost,
            cost = math.floor(cost + 0.5),
            profit = math.floor(brought - cost + 0.5),
            held = itemID and HeldBy(whose, itemID) or nil,
        })
    end

    for itemID, total in pairs(byID) do
        Add(itemID, ns.ItemName(itemID) or ns.Names.Get(itemID) or total.name, total)
    end
    for name, total in pairs(byName) do
        Add(nil, name, total)
    end

    table.sort(list, function(a, b)
        local aSize, bSize = math.abs(a.profit), math.abs(b.profit)
        if aSize ~= bSize then
            return aSize > bSize
        end
        if (a.name or "") ~= (b.name or "") then
            return (a.name or "") < (b.name or "")
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)
    return list
end

-- Trades kept one by one are only added up from when this was first
-- loaded. Other characters' are let go here as they age, since they're
-- only trimmed otherwise as their own trades are put down.
ns.Subscribe("DATABASE_READY", function()
    local book = Book()
    book.latestFrom = book.latestFrom or GetServerTime()
    for _, own in pairs(book.characters or {}) do
        if type(own) == "table" and type(own.latest) == "table" then
            TrimLatest(own.latest)
        end
    end
end)
