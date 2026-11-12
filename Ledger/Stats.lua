local _, ns = ...

-- Small sums over a price history, as returned by Ledger.History.
-- Nothing in here touches the game: it's plain arithmetic, which keeps it
-- easy to reason about and to test outside the client.

local Stats = {}
ns.Stats = Stats

-- How many earlier days we want before calling anything "usual". With
-- fewer, one odd day would swing the answer.
local MIN_DAYS_FOR_USUAL = 3

-- How far back "usual" looks. Everything that talks about a usual price
-- should take its history from this many days, so the list and the chart
-- can't disagree.
Stats.USUAL_DAYS = 14

--- The typical price over the days before the newest one.
---@param history table  from Ledger.History
---@return number|nil usual  nil when there isn't enough history to say
function Stats.UsualPrice(history)
    local earlier = #history - 1
    if earlier < MIN_DAYS_FOR_USUAL then
        return nil
    end

    local total = 0
    for index = 1, earlier do
        total = total + history[index].last
    end
    return total / earlier
end

--- How a price compares with the usual one.
---@param history table
---@param price number|nil  the price to judge. Defaults to the newest in the
---        history, but the price on show can come from somewhere the
---        history doesn't cover (another player, say), and whatever is said
---        about a price should be about the one the player is looking at.
---@return number|nil difference  0.18 means 18% above usual, -0.1 means 10% below
function Stats.AgainstUsual(history, price)
    local usual = Stats.UsualPrice(history)
    if not usual or usual == 0 then
        return nil
    end
    return (price or history[#history].last) / usual - 1
end

--- The lowest and highest prices seen across a history.
---@param history table
---@return number|nil low
---@return number|nil high
function Stats.Range(history)
    local low, high
    for _, day in ipairs(history) do
        low = math.min(low or day.low, day.low)
        high = math.max(high or day.high, day.high)
    end
    return low, high
end
