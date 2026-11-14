local _, ns = ...

-- "/gw demo": made-up history, for taking screenshots.
--
-- Goldwise's charts fill in over weeks of play, which is no help to
-- someone who wants to show what it looks like today. With demo data on,
-- every chart is drawn from a month or three of invented history: prices
-- that wander around what the item really costs now, and a purse with
-- money coming and going each day.
--
-- Nothing is saved and nothing real is changed. The inventing is done at
-- the moment something asks for history, in place of the real answer,
-- and stops when demo data is switched off or the interface is reloaded.
-- Today's prices, the player's bags and everything else stay real.

local on = false

-- The real functions, kept while the invented ones stand in for them.
local real = {}

-- A repeatable source of "random" numbers, so the same item draws the
-- same chart every time and a screenshot can be retaken.
local function Wobble(seed)
    local state = seed % 2147483647
    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end

-- Prices ----------------------------------------------------------------------

-- A history that ends at the item's real price, having wandered there: a
-- slow swell and a daily jitter.
local function InventedHistory(marketKey, itemID, numDays)
    local today = ns.Ledger.Today()
    local price = ns.Ledger.Price(marketKey, itemID) or 100
    local random = Wobble(itemID * 7919 + 13)

    local swell = 0.10 + random() * 0.15
    local period = 6 + random() * 9
    local phase = random() * 6.28
    local drift = (random() - 0.5) * 0.4

    local history = {}
    for age = numDays - 1, 0, -1 do
        -- How far this day sits from today's price. Zero on the last day,
        -- so the chart ends where the real price is.
        local away = swell * math.sin(age / period + phase)
            - swell * math.sin(phase)
            + drift * age / numDays
            + (age > 0 and (random() - 0.5) * 0.08 or 0)
        local last = math.max(1, math.floor(price * (1 + away) + 0.5))

        table.insert(history, {
            day = today - age,
            low = math.max(1, math.floor(last * 0.96)),
            high = math.floor(last * 1.05 + 0.5),
            last = last,
            quantity = math.floor(40 + random() * 400),
        })
    end
    return history
end

-- Separate readings for the same stretch: four a day, wandering a little
-- about that day's price, and ending on the real one.
local READINGS_A_DAY = 4

local function InventedReadings(marketKey, itemID, numDays)
    local random = Wobble(itemID * 104729 + numDays)
    local now = (GetServerTime() + ns.ClockOffset()) / ns.SECONDS_PER_DAY

    local readings = {}
    for _, day in ipairs(InventedHistory(marketKey, itemID, numDays)) do
        for part = 1, READINGS_A_DAY do
            local at = day.day + (part - 0.5) / READINGS_A_DAY
            if at < now then
                local price = math.max(1, math.floor(day.last * (0.94 + random() * 0.12) + 0.5))
                table.insert(readings, {
                    day = at,
                    low = price,
                    high = price,
                    last = price,
                    quantity = day.quantity,
                })
            end
        end
    end

    -- The last word goes to the price the page is quoting.
    if #readings > 0 then
        local newest = readings[#readings]
        local price = ns.Ledger.Price(marketKey, itemID) or newest.last
        newest.low, newest.high, newest.last = price, price, price
    end
    return readings
end

-- The purse -------------------------------------------------------------------

-- Income and spending for someone of the player's level, over a run of
-- stretches of time, with the odd one off.
local function InventedFlow(hoursEach, count)
    -- Only the real answer knows which stretches the window covers.
    local _, first, last = real.Flow(hoursEach, count)
    local scale = math.max(UnitLevel("player"), 5) * 900 * hoursEach / 24
    local random = Wobble(count * 104729 + hoursEach)

    local flow = {}
    for at = first, last do
        -- All three are drawn every time, so a day's figures don't depend
        -- on which days before it were left out.
        local played = random() > 0.15
        local income = math.floor(scale * (0.4 + random() * 1.4))
        local spending = math.floor(scale * (0.15 + random() * 0.9))
        if played then
            table.insert(flow, { at = at, income = income, spending = spending })
        end
    end
    return flow, first, last
end

-- What that income and spending would have left in the purse, ending at
-- what's really there now: on the character shown, or across the account.
local function InventedCoin(hoursEach, count, whose)
    local flow, first, last = InventedFlow(hoursEach, count)

    local change = {}
    for _, stretch in ipairs(flow) do
        change[stretch.at] = stretch.income - stretch.spending
    end

    local held = whose == true and ns.Characters.TotalMoney() or ns.Characters.MoneyOf(whose)
    local coin = {}
    for at = last, first, -1 do
        coin[at - first + 1] = math.max(held, 0)
        held = held - (change[at] or 0)
    end
    return coin, first, last
end

local function InventedDays(numDays)
    local flow, firstDay, today = InventedFlow(24, numDays)

    local days = {}
    for index, day in ipairs(flow) do
        days[index] = { day = day.at, income = day.income, spending = day.spending }
    end
    return days, firstDay, today
end

local function InventedAverages(numDays)
    local days = InventedDays(numDays)
    local income, spending = 0, 0
    for _, day in ipairs(days) do
        income = income + day.income
        spending = spending + day.spending
    end

    if #days == 0 then
        return 0, 0, 0, nil
    end
    return income / #days, spending / #days, #days, "vendor"
end

-- The auction house ---------------------------------------------------------

-- Things anyone levelling might trade, for the latest sales and purchases.
-- Real items, so the names are the game's own: linen, wool and silk cloth,
-- light and medium leather, copper and tin ore, and five common herbs.
local TRADE_GOODS = { 2589, 2592, 4306, 2318, 2319, 2770, 2771, 2447, 765, 785, 2449, 3820 }

-- What a stack of something might fetch, when there's no real price for it.
local FALLBACK_EACH = 60

-- Selling and buying at auction for each day of a stretch, every day
-- present. Some days see no trading, as real ones do.
local function InventedTradeDays(numDays)
    local today = ns.Ledger.Today()
    local first = today - numDays + 1
    local scale = math.max(UnitLevel("player"), 5) * 600
    local random = Wobble(numDays * 7349 + 3)

    local days = {}
    for day = first, today do
        -- All four are drawn every time, as for the purse.
        local traded = random() > 0.35
        local sold = math.floor(scale * (0.5 + random() * 2))
        local bought = math.floor(scale * random() * 0.8)
        local deposits = math.floor(scale * 0.05 * random())
        if not traded then
            sold, bought, deposits = 0, 0, 0
        end
        table.insert(days, {
            day = day,
            sold = sold,
            bought = bought,
            deposits = deposits,
            net = sold - bought - deposits,
        })
    end
    return days, first, today
end

local function InventedTradeTotals(numDays)
    local totals = { sold = 0, bought = 0, deposits = 0, cut = 0, net = 0, sales = 0 }
    for _, day in ipairs((InventedTradeDays(numDays))) do
        totals.sold = totals.sold + day.sold
        totals.bought = totals.bought + day.bought
        totals.deposits = totals.deposits + day.deposits
        totals.net = totals.net + day.net
        if day.sold > 0 then
            totals.sales = totals.sales + 3
        end
    end
    -- Sales arrive with the cut already taken: 5% of the full price.
    totals.cut = math.floor(totals.sold / 0.95 * 0.05)
    return totals
end

-- The latest sales and purchases: mostly sales, newest first as the real
-- list is, over the last few days.
local RECENT_SHOWN = 14

local function InventedRecent()
    local random = Wobble(RECENT_SHOWN * 31337)
    local market = ns.Market.Home()
    local now = GetServerTime()

    local entries = {}
    local at = now
    for _ = 1, RECENT_SHOWN do
        at = at - math.floor(1800 + random() * 6 * 3600)
        local itemID = TRADE_GOODS[1 + math.floor(random() * #TRADE_GOODS)]
        local count = 5 * (1 + math.floor(random() * 4))
        local each = ns.Ledger.Price(market, itemID) or FALLBACK_EACH
        local sold = random() > 0.3
        table.insert(entries, {
            at = at,
            kind = sold and ns.Trade.SALE or ns.Trade.PURCHASE,
            amount = math.floor(each * count * (sold and 0.95 or 1)),
            itemID = itemID,
            name = C_Item.GetItemNameByID(itemID),
            count = count,
            who = UnitName("player"),
        })
    end
    return entries
end

-- What the player was worth, day by day, ending at what they really hold:
-- coin and goods climbing unevenly over the month.
local function InventedWorth(numDays, whose)
    local today = ns.Ledger.Today()
    local first = today - numDays + 1
    local random = Wobble(numDays * 9973 + 7)

    local mine, everything = ns.Assets.WorthOfEverything(ns.Market.Home())
    local coin = whose == true and ns.Characters.TotalMoney() or ns.Characters.MoneyOf(whose)
    local goods = whose == true and everything or mine
    local step = math.max(UnitLevel("player"), 5) * 450

    local days = {}
    for day = today, first, -1 do
        days[day - first + 1] = { day = day, coin = math.max(coin, 0), goods = math.max(goods, 0) }
        coin = coin - math.floor(step * (random() * 1.6 - 0.3))
        goods = goods - math.floor(step * (random() * 1.2 - 0.4))
    end
    return days, first, today
end

-- The session ---------------------------------------------------------------

-- An hour and a half of farming and trading, for the session panel. The
-- figures are scaled to the player's level and given odd ends, so they
-- read like real ones.
local function InventedSession()
    local scale = math.max(UnitLevel("player"), 5) * 400
    local function Some(share, odd)
        return math.floor(scale * share) + odd
    end

    local income = {
        loot = Some(1.6, 37),
        auction = Some(1.2, 85),
        vendor = Some(0.9, 12),
        quest = Some(0.7, 40),
    }
    local spending = {
        repair = Some(0.35, 63),
        vendor = Some(0.25, 9),
        travel = Some(0.08, 0),
    }

    local earned, spent = 0, 0
    for _, amount in pairs(income) do
        earned = earned + amount
    end
    for _, amount in pairs(spending) do
        spent = spent + amount
    end

    local summary = {
        seconds = 84 * 60,
        earned = earned,
        spent = spent,
        income = income,
        spending = spending,
        coin = earned - spent,
        auction = Some(9, 74),
        vendor = Some(2.4, 31),
        auctionChange = Some(1.8, 52),
        vendorChange = Some(0.4, 18),
        unpriced = 0,
    }
    summary.bags = summary.auction + summary.vendor
    summary.goods = summary.auctionChange + summary.vendorChange
    summary.overall = summary.coin + summary.goods
    return summary
end

-- Switching -------------------------------------------------------------------

local function Redraw()
    ns.Publish("PRICES_CHANGED", ns.Market.Current())
    ns.Publish("PURSE_CHANGED")
    ns.Publish("TRADE_CHANGED")
    ns.Publish("SESSION_CHANGED")
end

--- Switches the invented history on or off.
function ns.ToggleDemo()
    on = not on

    if on then
        real.History = ns.Ledger.History
        real.Readings = ns.Ledger.Readings
        real.DaysRecorded = ns.Ledger.DaysRecorded
        real.Daily = ns.Purse.Daily
        real.Averages = ns.Purse.Averages
        real.Flow = ns.Purse.Flow
        real.Coin = ns.Purse.Coin
        real.TradeDaily = ns.Trade.Daily
        real.TradeTotals = ns.Trade.Totals
        real.TradeRecent = ns.Trade.Recent
        real.WorthDaily = ns.Worth.Daily
        real.Summary = ns.Session.Summary

        ns.Ledger.History = InventedHistory
        ns.Ledger.Readings = InventedReadings
        -- A full month on the books, so nothing says "day 2 of your history".
        ns.Ledger.DaysRecorded = function()
            return 30
        end
        ns.Purse.Daily = InventedDays
        ns.Purse.Averages = InventedAverages
        ns.Purse.Flow = InventedFlow
        ns.Purse.Coin = InventedCoin
        ns.Trade.Daily = InventedTradeDays
        ns.Trade.Totals = InventedTradeTotals
        ns.Trade.Recent = InventedRecent
        ns.Worth.Daily = InventedWorth
        ns.Session.Summary = InventedSession
        for _, itemID in ipairs(TRADE_GOODS) do
            ns.LoadItem(itemID)
        end

        ns.Print(
            "Demo data is on: charts, the Profit tab and the session tracker show invented "
                .. "figures, for screenshots. "
                .. "Nothing is saved. Type /gw demo again, or reload, to switch it off."
        )
    else
        ns.Ledger.History = real.History
        ns.Ledger.Readings = real.Readings
        ns.Ledger.DaysRecorded = real.DaysRecorded
        ns.Purse.Daily = real.Daily
        ns.Purse.Averages = real.Averages
        ns.Purse.Flow = real.Flow
        ns.Purse.Coin = real.Coin
        ns.Trade.Daily = real.TradeDaily
        ns.Trade.Totals = real.TradeTotals
        ns.Trade.Recent = real.TradeRecent
        ns.Worth.Daily = real.WorthDaily
        ns.Session.Summary = real.Summary

        ns.Print("Demo data is off. Charts are back to your real history.")
    end

    Redraw()
end
