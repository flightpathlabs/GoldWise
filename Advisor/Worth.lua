local _, ns = ...

-- What the player is worth, day by day: the coin on their characters, and
-- the goods they hold at what those are listed for. Only the characters
-- who trade in this one's auction house are counted, for both.
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

local function Days()
    if type(ns.db.worth) ~= "table" then
        ns.db.worth = {}
    end
    if type(ns.db.worth.days) ~= "table" then
        ns.db.worth.days = {}
    end
    return ns.db.worth.days
end

local function Count()
    countPending = false

    local days = Days()
    local today = ns.Ledger.Today()

    if not days[today] then
        -- A new day is as good a moment as any to drop the oldest.
        ns.Ledger.ForgetOldDays(days, ns.settings.historyDays)
    end

    -- Coin and goods are counted over the same characters: this one and
    -- the others on its market. A character on the other side trades in a
    -- different auction house, and their goods can't be priced in this
    -- one, so their coin is left out as well.
    local home = ns.Market.Home()
    local coin = GetMoney()
    for _, character in ipairs(ns.Characters.Others(home)) do
        coin = coin + (character.money or 0)
    end

    local _, goods = ns.Assets.WorthOfEverything(home)
    days[today] = { coin, goods }
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
---@return table days       list of { day, coin, goods } in copper, oldest
---        first; empty if nothing is on record in the stretch
---@return number|nil firstDay  the day the list starts on
---@return number lastDay       today
function Worth.Daily(numDays)
    local recorded = Days()
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
