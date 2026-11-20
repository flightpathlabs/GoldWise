local _, ns = ...

-- "/gw demo": made-up history, for taking screenshots.
--
-- Goldwise's charts fill in over weeks of play, which is no help to
-- someone who wants to show what it looks like today. With demo data on,
-- every chart is drawn from a month or three of invented history: prices
-- that wander around what the item really costs now, a purse with money
-- coming and going each day, and evenings spent hunting, gathering and
-- trading.
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

-- Shares out an amount among categories, in order. The last takes what's
-- left over from rounding, so the parts add up to the whole.
local function ShareOut(amount, shares)
    local parts, given = {}, 0
    for index, share in ipairs(shares) do
        local part = index == #shares and amount - given or math.floor(amount * share[2])
        parts[share[1]] = part
        given = given + part
    end
    return parts
end

-- What came in and went out over the last so many days, by category: the
-- same flow the chart is drawn from, shared out. Sales and the odd bid
-- handed back come by post, and the auction house's share of the spending
-- is what the trade book says was paid there, so the Money tab can split
-- them as it does real ones.
local function InventedByCategory(numDays)
    -- Cut as the Money tab cuts its chart: six hours a bar over a week,
    -- a day a bar over longer.
    local hoursEach = numDays <= 7 and 6 or 24
    local flow = InventedFlow(hoursEach, numDays * 24 / hoursEach)
    local cameIn, wentOut = 0, 0
    for _, stretch in ipairs(flow) do
        cameIn = cameIn + stretch.income
        wentOut = wentOut + stretch.spending
    end

    local trade = InventedTradeTotals(numDays)
    local returned = math.floor(trade.bought * 0.05)
    local mail = math.min(trade.sold + returned, math.floor(cameIn * 0.6))
    local paidThere = math.min(trade.bought + trade.deposits + returned, math.floor(wentOut * 0.5))

    local income = ShareOut(cameIn - mail, { { "loot", 0.5 }, { "vendor", 0.3 }, { "quest" } })
    income.mail = mail
    local spending = ShareOut(wentOut - paidThere, {
        { "repair", 0.35 },
        { "training", 0.3 },
        { "vendor", 0.25 },
        { "travel" },
    })
    spending.auction = paidThere
    return income, spending
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

-- About how long was spent playing since a moment: most of a session, and
-- an evening or so of each day over longer.
local function PlayedSince(sinceTime)
    local span = sinceTime and GetServerTime() - sinceTime or 30 * ns.SECONDS_PER_DAY
    return math.max(60, math.min(span * 0.9, 4 * 3600 + span * 0.07))
end

-- What was traded of each item, for What you traded: three things farmed
-- and sold, and four bought to sell on, which went well, barely paid,
-- lost money and haven't sold yet. For each, how many were bought and
-- sold in three hours of play, and what was paid for each as a share of
-- the price today. Everything sold went for today's price, less the cut.
local TRADED = {
    { itemID = 4306, sold = 20 }, -- Silk Cloth
    { itemID = 2772, sold = 12 }, -- Iron Ore
    { itemID = 4234, sold = 8 }, -- Heavy Leather
    { itemID = 3356, bought = 20, sold = 20, paid = 0.7 }, -- Kingsblood
    { itemID = 785, bought = 20, sold = 20, paid = 0.9 }, -- Mageroyal
    { itemID = 2592, bought = 30, sold = 20, paid = 1.1, lost = 0.3 }, -- Wool Cloth
    { itemID = 3821, bought = 20, sold = 0, paid = 0.8, lost = 0.2 }, -- Goldthorn
}

-- In stacks of five, as things are bought at auction.
local function Stack(count)
    return math.max(5, math.floor(count / 5 + 0.5) * 5)
end

local function InventedItems(sinceTime)
    local scale = PlayedSince(sinceTime) / (3 * 3600)
    local market = ns.Market.Home()

    local items = {}
    for _, traded in ipairs(TRADED) do
        local each = ns.Ledger.Price(market, traded.itemID) or FALLBACK_EACH
        local bought, sold = 0, math.max(1, math.floor(traded.sold * scale + 0.5))
        if traded.bought then
            bought = Stack(traded.bought * scale)
            sold = traded.sold > 0 and math.min(bought, Stack(traded.sold * scale)) or 0
        end

        -- Deposits lost on listings that didn't sell: a share of the
        -- price for each stack of five.
        local paid = math.floor(bought * each * (traded.paid or 0) + 0.5)
        local lost = math.floor(bought / 5 * each * (traded.lost or 0) + 0.5)
        local brought = math.floor(sold * each * 0.95 + 0.5) - lost
        local cost = bought > 0 and paid / bought * math.min(sold, bought) or 0

        table.insert(items, {
            itemID = traded.itemID,
            name = C_Item.GetItemNameByID(traded.itemID),
            bought = bought,
            paid = paid,
            sold = sold,
            brought = brought,
            lost = lost,
            profit = math.floor(brought - cost + 0.5),
            held = bought > 0 and bought - sold or math.floor(sold * 0.2),
        })
    end
    return items
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

-- What the player did ----------------------------------------------------------

-- An evening's worth of levelling in Stranglethorn and Arathi: the share
-- of the time each thing took, and how well it paid against the rest.
-- Questing and fishing pay least, and skinning was only tried for a bit.
local STRANGLETHORN, ARATHI = "Stranglethorn Vale", "Arathi Highlands"
local ACTIVITIES = {
    { kind = "kill", label = "Young Panther", where = STRANGLETHORN, time = 0.26, pays = 1.05 },
    { kind = "gather", label = "Mining", where = STRANGLETHORN, time = 0.17, pays = 1.55 },
    { kind = "kill", label = "Bloodscalp Warrior", where = STRANGLETHORN, time = 0.15, pays = 1.3 },
    { kind = "quest", label = "Questing", where = STRANGLETHORN, time = 0.14, pays = 0.55 },
    { kind = "fish", label = "Fishing", where = ARATHI, time = 0.12, pays = 0.6 },
    { kind = "gather", label = "Herbalism", where = ARATHI, time = 0.1, pays = 1.2 },
    { kind = "gather", label = "Skinning", where = "Badlands", time = 0.03, pays = 1.4 },
}

local function InventedActivities(sinceTime)
    local played = PlayedSince(sinceTime)
    -- Copper an hour, on average, for someone of the player's level.
    local rate = math.max(UnitLevel("player"), 5) * 600
    local random = Wobble(math.floor(played / 600) * 7 + 5)

    local activities = {}
    for index, activity in ipairs(ACTIVITIES) do
        local seconds = math.floor(played * activity.time * (0.9 + random() * 0.2))
        local earned = math.floor(seconds / 3600 * rate * activity.pays * (0.9 + random() * 0.2))
            + math.floor(random() * 100)
        table.insert(activities, {
            key = "demo:" .. index,
            kind = activity.kind,
            label = activity.label,
            where = activity.where,
            seconds = seconds,
            earned = earned,
            perHour = seconds > 0 and math.floor(earned * 3600 / seconds + 0.5) or 0,
        })
    end

    table.sort(activities, function(a, b)
        return a.seconds > b.seconds
    end)
    return activities
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
        real.ByCategory = ns.Purse.ByCategory
        real.TradeDaily = ns.Trade.Daily
        real.TradeTotals = ns.Trade.Totals
        real.TradeRecent = ns.Trade.Recent
        real.TradeItems = ns.Trade.Items
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
        ns.Purse.ByCategory = InventedByCategory
        ns.Trade.Daily = InventedTradeDays
        ns.Trade.Totals = InventedTradeTotals
        ns.Trade.Recent = InventedRecent
        ns.Trade.Items = InventedItems
        ns.Worth.Daily = InventedWorth
        ns.Session.Summary = InventedSession
        -- Activities are kept by a file an update adds, which isn't there
        -- until the game has been restarted.
        if ns.Activity then
            real.ActivitySummary = ns.Activity.Summary
            ns.Activity.Summary = InventedActivities
        end
        for _, itemID in ipairs(TRADE_GOODS) do
            ns.LoadItem(itemID)
        end
        for _, traded in ipairs(TRADED) do
            ns.LoadItem(traded.itemID)
        end

        ns.Print(
            "Demo data is on: charts, the Money tab and the session tracker show invented "
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
        ns.Purse.ByCategory = real.ByCategory
        ns.Trade.Daily = real.TradeDaily
        ns.Trade.Totals = real.TradeTotals
        ns.Trade.Recent = real.TradeRecent
        ns.Trade.Items = real.TradeItems
        ns.Worth.Daily = real.WorthDaily
        ns.Session.Summary = real.Summary
        if ns.Activity then
            ns.Activity.Summary = real.ActivitySummary
        end

        ns.Print("Demo data is off. Charts are back to your real history.")
    end

    Redraw()
end
