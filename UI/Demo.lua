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

-- Prices ------------------------------------------------------------------------------

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

-- The purse ---------------------------------------------------------------------------

-- Income and spending for someone of the player's level, over a run of
-- stretches of time, with the odd one off.
local function InventedFlow(hoursEach, count)
    -- Only the real answer knows which stretches the window covers.
    local _, first, last = real.Flow(hoursEach, count)
    local scale = math.max(UnitLevel("player"), 5) * 900 * hoursEach / 24
    local random = Wobble(count * 104729 + hoursEach)

    local flow = {}
    for at = first, last do
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
-- what's really there now.
local function InventedCoin(hoursEach, count)
    local flow, first, last = InventedFlow(hoursEach, count)

    local change = {}
    for _, stretch in ipairs(flow) do
        change[stretch.at] = stretch.income - stretch.spending
    end

    local coin, held = {}, ns.Characters.TotalMoney()
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

-- Switching ---------------------------------------------------------------------------

local function Redraw()
    ns.Publish("PRICES_CHANGED", ns.Market.Current())
    ns.Publish("PURSE_CHANGED")
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

        ns.Print(
            "Demo data is on: charts are drawn from invented history, for screenshots. "
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

        ns.Print("Demo data is off. Charts are back to your real history.")
    end

    Redraw()
end
