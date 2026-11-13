local _, ns = ...

-- What the player is worth, day by day: their coin, and the goods they
-- hold at what those are listed for. There's a record for each character
-- and one for the account, which counts only the characters who trade in
-- this one's auction house.
--
-- Profit says how each day went. This says where it has all got to, which
-- is the figure that tells someone whether a month of playing the market
-- has left them better off. One figure is kept per day, the last one seen
-- that day, for as long as price history is.
--
-- The goods half is generous by nature. It prices everything at the
-- cheapest listing, as though it would all sell, and at that price.
-- Anything that shows it should say so.

local Worth = {}
ns.Worth = Worth

-- Seconds to let things settle before counting. Bags, coin and prices all
-- change in bursts, and one count at the end of a burst is enough.
local SETTLE_DELAY = 5

-- Positions in a day's record, kept as a plain pair to keep the saved
-- file small.
local COIN, GOODS = 1, 2

local countPending = false

local function Book()
    if type(ns.db.worth) ~= "table" then
        ns.db.worth = {}
    end
    return ns.db.worth
end

-- The days on record. whose is true for the whole account, a character's
-- key for theirs, or nothing for the one being played. Each character's
-- own were first kept a while after the account's, so there can be fewer
-- of them. Reading another character's never makes them a record.
local function Days(whose)
    local book = Book()
    if type(book.days) ~= "table" then
        book.days = {}
    end
    if whose == true then
        return book.days
    end

    if type(book.characters) ~= "table" then
        book.characters = {}
    end
    local current = ns.Characters.CurrentKey()
    if whose and whose ~= current then
        return type(book.characters[whose]) == "table" and book.characters[whose] or {}
    end

    if type(book.characters[current]) ~= "table" then
        -- Not copied from the account even when there is only one
        -- character: the account's goods take in the shared bank and a
        -- character's own don't, so the line would drop on the first day.
        book.characters[current] = {}
    end
    return book.characters[current]
end

local function Count()
    countPending = false

    local today = ns.Ledger.Today()
    for _, whose in ipairs({ true, false }) do
        local days = Days(whose)
        if not days[today] then
            -- A new day is as good a moment as any to drop the oldest.
            ns.Ledger.ForgetOldDays(days, ns.settings.historyDays)
        end
    end

    -- For the account, coin and goods are counted over the same
    -- characters: this one and the others on its market. A character on
    -- the other side trades in a different auction house, and their goods
    -- can't be priced in this one, so their coin is left out as well.
    local home = ns.Market.Home()
    local coin = GetMoney()
    for _, character in ipairs(ns.Characters.Others(home)) do
        coin = coin + (character.money or 0)
    end

    local mine, goods = ns.Assets.WorthOfEverything(home)
    Days(true)[today] = { coin, goods }
    Days(false)[today] = { GetMoney(), mine }
end

local function CountSoon()
    if not countPending then
        countPending = true
        C_Timer.After(SETTLE_DELAY, Count)
    end
end

ns.OnEvent("PLAYER_LOGIN", CountSoon)
ns.Subscribe("MONEY_MOVED", CountSoon)
ns.Subscribe("BAGS_CHANGED", CountSoon)
ns.Subscribe("PRICES_CHANGED", CountSoon)

--- What the player was worth on each day of a stretch.
---
--- Starts at the first day there's a record for, not at the start of the
--- stretch: before that nothing is known, which isn't the same as having
--- nothing. A day with no record of its own carries the last one forward.
---@param numDays number  how far back to look, counting today
---@param whose boolean|string|nil  true for every character on this market
---        and the shared bank; a character's key for their coin, bags and
---        bank; nothing for the one being played
---@return table days       list of { day, coin, goods } in copper, oldest
---        first; empty if nothing is on record in the stretch
---@return number|nil firstDay  the day the list starts on
---@return number lastDay       today
function Worth.Daily(numDays, whose)
    local recorded = Days(whose)
    local today = ns.Ledger.Today()

    local firstDay
    for day = today - numDays + 1, today do
        if recorded[day] then
            firstDay = day
            break
        end
    end

    local days = {}
    local last
    for day = firstDay or today + 1, today do
        last = recorded[day] or last
        table.insert(days, { day = day, coin = last[COIN], goods = last[GOODS] })
    end
    return days, firstDay, today
end
