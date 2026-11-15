local _, ns = ...

-- Recipes the player bought from a vendor to sell at auction, and how
-- each one went: what was really paid, what it really sold for, and what
-- was left over.
--
-- Nothing has to be marked. A recipe that can be sold on is noted when
-- it's bought from a vendor, by the coin that left the purse. Posting it
-- is seen as it happens, and the auction the game makes for it is that
-- copy's, with the deposit paid on it. When the letter for its sale is
-- opened it's sold, for what the letter held less the deposit handed
-- back with it. A listing that runs out or is cancelled loses its
-- deposit, which comes off the profit, and the recipe waits to be listed
-- again.
--
-- A recipe the player bought without knowing it, and has since learned,
-- is no resale, and is left out.

local Resales = {}
ns.Resales = Resales

-- Seconds a purchase waits for the coin that pays for it, and a posting
-- for the auction the game makes from it.
local PAYMENT_WAIT = 5
local POSTING_WAIT = 30

-- Sold recipes kept. Enough for a long while of reselling.
local MOST_KEPT = 200

-- A recipe held this long since it was bought or last listed is let go:
-- sold some way Goldwise can't follow, given away, or forgotten.
local HELD_DAYS = 60

-- What becomes of a recipe.
Resales.BOUGHT = "bought"
Resales.LISTED = "listed"
Resales.SOLD = "sold"

-- Saved: a list of lots, one per recipe bought, oldest first. Each is
-- { item, spell, name, who, paid, boughtAt, knewIt, state, market,
-- auctionID, deposit, listedAt, soldSeen, gone, lost, received, soldAt }.
--
--   paid, received  what really changed hands, in copper
--   knewIt          whether the buyer already knew the recipe
--   lister          the character who listed it last, who may not be
--                   the buyer: a recipe can be mailed to another to sell
--   deposit         the deposit on the listing up now, if known
--   soldSeen        its auction was seen to have sold; the letter's to come
--   gone            its auction left the list without being seen to sell,
--                   so its deposit is counted lost, until a letter says
--                   it sold after all
--   lost            deposits lost on listings that didn't sell
--
-- Times are server time. who is the character key.
local function Lots()
    if type(ns.db.resales) ~= "table" then
        ns.db.resales = {}
    end
    return ns.db.resales
end

local function Me()
    return ns.Characters.CurrentKey()
end

-- Finds a lot, this character's first and then anyone's: a recipe can be
-- mailed to another character to sell. wanted says which will do.
local function FindLot(wanted)
    local me = Me()
    for _, mine in ipairs({ true, false }) do
        for _, lot in ipairs(Lots()) do
            if (lot.who == me) == mine and wanted(lot) then
                return lot
            end
        end
    end
end

-- Buying -----------------------------------------------------------------------

-- Purchases waiting for their coin to leave: { item, spell, name, count,
-- each, at }.
local buying = {}

hooksecurefunc("BuyMerchantItem", function(index, quantity)
    local itemID = GetMerchantItemID(index)
    local spell = itemID and ns.Recipes.Tradeable(itemID)
    if not spell then
        return
    end
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info or info.hasExtendedCost or (info.price or 0) <= 0 then
        return
    end
    table.insert(buying, {
        item = itemID,
        spell = spell,
        name = info.name,
        count = quantity or 1,
        each = info.price / math.max(info.stackCount or 1, 1),
        at = GetTime(),
    })
end)

-- The coin for a purchase has left: one lot for each recipe bought, at
-- its share of what really went.
local function Bought(purchase, paid)
    local now = GetServerTime()
    local knewIt = ns.Recipes.IsLearned(purchase.spell)
    for _ = 1, purchase.count do
        table.insert(Lots(), {
            item = purchase.item,
            spell = purchase.spell,
            name = purchase.name,
            who = Me(),
            paid = paid / purchase.count,
            boughtAt = now,
            knewIt = knewIt,
            state = Resales.BOUGHT,
            lost = 0,
        })
    end
    ns.Publish("RESALES_CHANGED")
end

-- The coin is filed as the vendor's while the merchant is open, and as
-- something else if the window closed before it left.
ns.Subscribe("MONEY_MOVED", function(delta, category)
    if delta >= 0 or #buying == 0 or (category ~= "vendor" and category ~= "other") then
        return
    end
    local now = GetTime()
    for index = #buying, 1, -1 do
        local purchase = buying[index]
        if now - purchase.at > PAYMENT_WAIT then
            table.remove(buying, index)
        elseif math.abs(-delta - purchase.each * purchase.count) <= purchase.count then
            table.remove(buying, index)
            Bought(purchase, -delta)
            return
        end
    end
end)

-- Listing ------------------------------------------------------------------------

-- Everything posted lately, waiting for the auction the game makes from
-- each: { item, market, at }, oldest first, one for each copy posted.
-- Not just recipes: the game makes the auctions in the order they were
-- posted, and keeping every posting in the queue keeps the two in step.
-- It's only a first guess. The auctions themselves are checked against
-- the list when it's next read (see LISTINGS_READ).
local posting = {}

-- Deposits paid lately for recipes, waiting for their lot: { item,
-- amount, at }, oldest first. The deposit can come before or after the
-- auction does.
local deposits = {}

-- How many copies the latest posting of each item was for, so a deposit
-- paid on several at once can be shared out.
local postedCopies = {}

-- Auctions made this session, by ID: { at, market }. Any that turn out
-- to be a recipe we're holding are claimed when the list is read.
local created = {}

for _, name in ipairs({ "PostItem", "PostCommodity" }) do
    if C_AuctionHouse[name] then
        hooksecurefunc(C_AuctionHouse, name, function(location, _, quantity)
            local ok, itemID = pcall(C_Item.GetItemID, location)
            itemID = ok and itemID or nil
            -- Unstackable things posted several at once make an auction
            -- each. A pool of commodities makes one.
            local copies = name == "PostItem" and math.max(1, tonumber(quantity) or 1) or 1
            local now = GetTime()
            for _ = 1, copies do
                table.insert(posting, { item = itemID, market = ns.Market.Current(), at = now })
            end
            if itemID then
                postedCopies[itemID] = copies
            end
        end)
    end
end

-- A posting that didn't go through makes no auction. Letting its place in
-- the queue go keeps the next one right.
local function PostingFailed()
    table.remove(posting)
end
ns.OnEvent("AUCTION_HOUSE_SHOW_ERROR", PostingFailed)
ns.OnEvent("AUCTION_MULTISELL_FAILURE", PostingFailed)

local function LotFor(auctionID)
    for _, lot in ipairs(Lots()) do
        if lot.auctionID == auctionID then
            return lot
        end
    end
end

-- Lets go of deposits waiting too long for their lot: paid on a recipe
-- bought before Goldwise kept these, or from the auction house.
local function DropStaleDeposits()
    local now = GetTime()
    while deposits[1] and now - deposits[1].at > POSTING_WAIT do
        table.remove(deposits, 1)
    end
end

-- Takes the oldest deposit waiting for an item.
local function TakeDeposit(itemID)
    DropStaleDeposits()
    for index, deposit in ipairs(deposits) do
        if deposit.item == itemID then
            table.remove(deposits, index)
            return deposit.amount
        end
    end
end

-- Gives an auction to a copy of its recipe held to sell: one never listed
-- first, then one whose listing ran out.
local function Claim(auctionID, itemID, market)
    if LotFor(auctionID) or not ns.Recipes.Tradeable(itemID) then
        return false
    end
    local lot = FindLot(function(candidate)
        return candidate.state == Resales.BOUGHT and candidate.item == itemID and not candidate.gone
    end) or FindLot(function(candidate)
        return candidate.state == Resales.BOUGHT and candidate.item == itemID
    end)
    if not lot then
        return false
    end

    lot.state = Resales.LISTED
    lot.lister = Me()
    lot.market = market
    lot.auctionID = auctionID
    lot.listedAt = GetServerTime()
    lot.gone, lot.soldSeen = nil, nil
    lot.deposit = TakeDeposit(itemID)
    lot.awaitingDeposit = lot.deposit == nil
    return true
end

-- The game has made an auction. If a recipe was posted just before, it's
-- that recipe's.
ns.OnEvent("AUCTION_HOUSE_AUCTION_CREATED", function(auctionID)
    local now = GetTime()
    while posting[1] and now - posting[1].at > POSTING_WAIT do
        table.remove(posting, 1)
    end
    local post = table.remove(posting, 1)
    created[auctionID] = { at = now, market = post and post.market or ns.Market.Current() }
    if post and post.item and Claim(auctionID, post.item, post.market) then
        ns.Publish("RESALES_CHANGED")
    end
end)

ns.Subscribe("TRADE_CHANGED", function(kind, amount, _, _, _, itemID)
    if kind ~= ns.Trade.DEPOSIT or not amount or not itemID then
        return
    end
    if not ns.Recipes.Tradeable(itemID) then
        return
    end

    -- A deposit on several copies at once is theirs to share.
    local copies = postedCopies[itemID] or 1
    postedCopies[itemID] = nil
    local each = amount / copies

    local me = Me()
    local changed = false
    for _ = 1, copies do
        -- A listing of ours already made and waiting for its deposit
        -- takes it; otherwise it waits for the listing.
        local lot = FindLot(function(candidate)
            return candidate.awaitingDeposit and candidate.lister == me and candidate.item == itemID
        end)
        if lot then
            lot.deposit = each
            lot.awaitingDeposit = nil
            changed = true
        else
            table.insert(deposits, { item = itemID, amount = each, at = GetTime() })
        end
    end
    if changed then
        ns.Publish("RESALES_CHANGED")
    end
end)

-- A listing has gone without being seen to sell. Its deposit is counted
-- lost, and the recipe is back in hand to list again. sure is false when
-- it might yet turn out to have sold: an auction that sells leaves the
-- list an hour or so before its letter comes.
local function Unlisted(lot, sure)
    lot.state = Resales.BOUGHT
    lot.lost = (lot.lost or 0) + (lot.deposit or 0)
    lot.gone = not sure and (lot.deposit or 0) or nil
    lot.auctionID, lot.market, lot.deposit, lot.awaitingDeposit = nil, nil, nil, nil
end

-- A listing this new may have been made after the list now arriving was
-- asked for, so its absence from it means nothing yet.
local JUST_LISTED = 30

-- The whole of the player's auctions at one house, read while it's open:
-- which of ours have sold, which have gone, and which recipes made this
-- session went unclaimed.
ns.Subscribe("LISTINGS_READ", function(marketKey, auctions)
    local me = Me()
    local now = GetServerTime()
    local changed = false

    for _, lot in ipairs(Lots()) do
        if lot.state == Resales.LISTED and lot.market == marketKey and lot.lister == me then
            local auction = lot.auctionID and auctions[lot.auctionID]
            if auction and auction.itemID ~= lot.item then
                -- Put down to the wrong posting. The recipe was never
                -- listed this time, so nothing was lost.
                lot.state = Resales.BOUGHT
                lot.auctionID, lot.market, lot.deposit, lot.awaitingDeposit = nil, nil, nil, nil
                changed = true
            elseif auction and auction.sold and not lot.soldSeen then
                lot.soldSeen = true
                changed = true
            elseif not auction and not lot.soldSeen and now - (lot.listedAt or 0) > JUST_LISTED then
                Unlisted(lot, false)
                changed = true
            end
        end
    end

    -- Auctions made this session that are a recipe we're holding, by what
    -- they really are rather than what the queue guessed.
    for auctionID, made in pairs(created) do
        local auction = auctions[auctionID]
        if auction and not auction.sold and made.market == marketKey then
            if Claim(auctionID, auction.itemID, marketKey) then
                changed = true
            end
            created[auctionID] = nil
        end
    end

    if changed then
        ns.Publish("RESALES_CHANGED")
    end
end)

-- A cancelled auction certainly didn't sell.
ns.OnEvent("AUCTION_CANCELED", function(auctionID)
    local lot = LotFor(auctionID)
    if lot and lot.state == Resales.LISTED then
        Unlisted(lot, true)
        ns.Publish("RESALES_CHANGED")
    end
end)

-- Selling --------------------------------------------------------------------------

local function NameOf(lot)
    return lot.name or C_Item.GetItemNameByID(lot.item)
end

-- Lets go of the oldest sold lots once there are too many, and of
-- recipes held so long they've surely gone some other way.
local function Trim()
    local lots = Lots()
    local now = GetServerTime()
    local sold = 0
    for index = #lots, 1, -1 do
        local lot = lots[index]
        if lot.state == Resales.SOLD then
            sold = sold + 1
            if sold > MOST_KEPT then
                table.remove(lots, index)
            end
        elseif
            lot.state == Resales.BOUGHT
            and now - (lot.listedAt or lot.boughtAt or now) > HELD_DAYS * ns.SECONDS_PER_DAY
        then
            table.remove(lots, index)
        end
    end
end

-- A sale's letter has been opened. It names the item, not the auction,
-- so it goes to the likeliest copy: one seen to have sold, then one whose
-- listing went without a word, then one still listed, then one held.
ns.Subscribe("TRADE_CHANGED", function(kind, amount, name, _, deposit)
    if kind ~= ns.Trade.SALE or not name or not amount then
        return
    end

    local found
    for _, likely in ipairs({
        function(lot)
            return lot.state == Resales.LISTED and lot.soldSeen
        end,
        function(lot)
            return lot.state == Resales.BOUGHT and lot.gone ~= nil
        end,
        function(lot)
            return lot.state == Resales.LISTED
        end,
        function(lot)
            return lot.state == Resales.BOUGHT
        end,
    }) do
        found = FindLot(function(lot)
            return likely(lot) and NameOf(lot) == name
        end)
        if found then
            break
        end
    end
    if not found then
        return
    end

    -- A listing that left the list because it sold, not because it ran
    -- out: its deposit wasn't lost after all.
    if found.gone then
        found.lost = math.max(0, (found.lost or 0) - found.gone)
    end

    found.state = Resales.SOLD
    found.received = amount - (deposit or 0)
    found.soldAt = GetServerTime()
    found.gone, found.soldSeen, found.deposit, found.awaitingDeposit = nil, nil, nil, nil
    found.auctionID = nil
    Trim()
    ns.Publish("RESALES_CHANGED")
end)

ns.Subscribe("DATABASE_READY", Trim)

-- Reading it back ------------------------------------------------------------------

--- The recipes bought to sell, newest first: sold, listed and held. A
--- recipe its buyer didn't know when they bought it, and has learned
--- since, is left out: that was buying to learn.
---@return table lots  each as saved (see Lots), plus profit for one sold:
---        what it sold for less what it cost and any deposits lost
---@return table totals  { sold, profit, held }: how many have sold and
---        what they made between them, and how many are still to sell
function Resales.All()
    local list = {}
    local totals = { sold = 0, profit = 0, held = 0 }
    local me = Me()

    for index = #Lots(), 1, -1 do
        local lot = Lots()[index]
        local learned = lot.state == Resales.BOUGHT
            and lot.who == me
            and not lot.knewIt
            and ns.Recipes.IsLearned(lot.spell)
        if not learned then
            if lot.state == Resales.SOLD then
                lot.profit = (lot.received or 0) - (lot.paid or 0) - (lot.lost or 0)
                totals.sold = totals.sold + 1
                totals.profit = totals.profit + lot.profit
            else
                lot.profit = nil
                totals.held = totals.held + 1
            end
            table.insert(list, lot)
        end
    end
    return list, totals
end
