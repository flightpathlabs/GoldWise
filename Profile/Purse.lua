local _, ns = ...

-- Where the gold comes from and where it goes.
--
-- The game says when the player's money changes but not why. So we keep
-- track of what they're doing (talking to a vendor, a trainer, the
-- mailbox) and file each change under that. It's the same approach
-- Blizzard's own receipt code takes.
--
-- Totals are kept per hour for a month, across the whole account. An hour
-- is fine enough to show how an evening went, and from hours any longer
-- stretch can be added up: six of them, twelve, or a day.

local Purse = {}
ns.Purse = Purse

local KEEP_DAYS = 30

local SECONDS_PER_HOUR = 3600

-- What money changing hands right now is most likely about.
local OTHER = "other"
local context = OTHER

local CONTEXT_FOR_WINDOW = {
    [Enum.PlayerInteractionType.Merchant] = "vendor",
    [Enum.PlayerInteractionType.Trainer] = "training",
    [Enum.PlayerInteractionType.Auctioneer] = "auction",
    [Enum.PlayerInteractionType.MailInfo] = "mail",
}

-- How each kind of spending reads in a sentence: "mostly ...".
Purse.SPENDING_LABELS = {
    vendor = "repairs and supplies",
    training = "training",
    auction = "the auction house",
    mail = "postage",
    travel = "flights",
    other = "everything else",
}

local lastMoney

-- Seconds after the flight map closes in which a payment is still a fare.
local FARE_DELAY = 2

local flightMapOpen = false

-- Whether a merchant's window is open. Tracked on its own rather than read
-- from the context above, because the two are set by different events and
-- nothing promises which arrives first.
local atMerchant = false

-- The saved record: hours = { [hour] = { income, spending, coin } }, with
-- hours numbered from 1970 in UTC. income and spending are copper by what
-- the money was about, and coin is what the whole account held at the
-- last moment of that hour we saw.
local function Book()
    if type(ns.db.purse) ~= "table" then
        ns.db.purse = {}
    end

    local book = ns.db.purse
    if type(book.hours) ~= "table" then
        book.hours = {}
    end

    -- Before hours there were days, and UTC ones. When in such a day the
    -- coin moved wasn't kept, so each is put down at the hour the day
    -- began. That's the evening before in the Americas, the small hours
    -- in Europe and the morning in Asia and Australia: for each, the
    -- local day that someone who plays of an evening was playing in.
    if type(book.days) == "table" then
        for day, record in pairs(book.days) do
            local hour = day * 24
            if not book.hours[hour] and type(record) == "table" then
                book.hours[hour] = {
                    income = record.income or {},
                    spending = record.spending or {},
                }
            end
        end
        book.days = nil
    end

    return book
end

-- Recording --------------------------------------------------------------------

-- This hour's record, made if it isn't there yet.
local function ThisHour()
    local hours = Book().hours
    local now = math.floor(GetServerTime() / SECONDS_PER_HOUR)

    local hour = hours[now]
    if not hour then
        hour = { income = {}, spending = {} }
        hours[now] = hour

        -- A new hour is as good a moment as any to drop the oldest.
        local oldest = now - KEEP_DAYS * 24
        for at in pairs(hours) do
            if at <= oldest then
                hours[at] = nil
            end
        end
    end
    return hour
end

-- Notes what the account holds at this moment, for the line of coin over
-- time. This character's purse is read now, and the others' as they were
-- when each was last played.
local function NoteCoin()
    ThisHour().coin = ns.Characters.TotalMoney()
end

local function Record(delta)
    local hour = ThisHour()
    local side = delta > 0 and hour.income or hour.spending
    side[context] = (side[context] or 0) + math.abs(delta)
    NoteCoin()

    -- For anything that wants to look closer at one kind of money than a
    -- total (see Trade.lua).
    ns.Publish("MONEY_MOVED", delta, context)
end

ns.OnEvent("PLAYER_MONEY", function()
    local money = GetMoney()
    -- The first reading after login has nothing to be compared with.
    if lastMoney and money ~= lastMoney then
        Record(money - lastMoney)
        ns.Publish("PURSE_CHANGED")
    end
    lastMoney = money
end)

ns.OnEvent("PLAYER_LOGIN", function()
    lastMoney = GetMoney()

    -- A point on the line for today even if no coin moves.
    NoteCoin()
end)

ns.OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(window)
    context = CONTEXT_FOR_WINDOW[window] or context
end)

ns.OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(window)
    if CONTEXT_FOR_WINDOW[window] == context then
        context = OTHER
    end
end)

-- Flight masters don't go through the interaction manager.
ns.OnEvent("TAXIMAP_OPENED", function()
    flightMapOpen = true
    context = "travel"
end)

ns.OnEvent("TAXIMAP_CLOSED", function()
    flightMapOpen = false

    -- Picking a destination closes the map, and the fare is taken a moment
    -- later. Keep filing under travel just long enough to catch it.
    C_Timer.After(FARE_DELAY, function()
        if context == "travel" and not flightMapOpen then
            context = OTHER
        end
    end)
end)

-- Reading it back -----------------------------------------------------------------

-- Time is cut into stretches of so many hours, numbered so that a stretch
-- of 24 is a day as Ledger.Today counts them: midnight to midnight on the
-- player's clock, with the shorter ones dividing that evenly.

-- Which stretch an hour of the record falls in.
local function StretchOf(hour, hoursEach)
    return math.floor((hour * SECONDS_PER_HOUR + ns.ClockOffset()) / (hoursEach * SECONDS_PER_HOUR))
end

-- Adds the record up by stretch, over the last `count` of them.
-- Returns [stretch] = { income, spending, byCategory, coin }, the first
-- stretch of the window and the last, which is the one we're in.
local function AddUp(hoursEach, count)
    local last = StretchOf(math.floor(GetServerTime() / SECONDS_PER_HOUR), hoursEach)
    local first = last - count + 1
    local stretches = {}

    for hour, record in pairs(Book().hours) do
        local at = StretchOf(hour, hoursEach)
        if at >= first and at <= last then
            local stretch = stretches[at]
            if not stretch then
                stretch = { income = 0, spending = 0, byCategory = {} }
                stretches[at] = stretch
            end

            for _, amount in pairs(record.income or {}) do
                stretch.income = stretch.income + amount
            end
            for category, amount in pairs(record.spending or {}) do
                stretch.spending = stretch.spending + amount
                stretch.byCategory[category] = (stretch.byCategory[category] or 0) + amount
            end

            -- What was held at the end of a stretch is what its last hour
            -- on record says.
            if record.coin and (not stretch.coinHour or hour > stretch.coinHour) then
                stretch.coin, stretch.coinHour = record.coin, hour
            end
        end
    end

    return stretches, first, last
end

--- The moment a stretch starts.
---@param stretch number    as Purse.Flow and Purse.Coin number them
---@param hoursEach number  how long each stretch is
---@return number day  that moment in days, counted as Ledger.Today counts
---        them, so 12.5 is noon on day 12
function Purse.StartOf(stretch, hoursEach)
    return stretch * hoursEach / 24
end

--- Income and spending over a run of equal stretches of time, for
--- charting.
---@param hoursEach number  how long each stretch is: 24 for a day
---@param count number      how many stretches back to look, counting
---        the one we're in
---@return table flow     list of { at, income, spending } in copper,
---        oldest first, where at is the stretch's number. Stretches in
---        which no coin moved are left out.
---@return number first   the first stretch of the window
---@return number last    the last: the one we're in
function Purse.Flow(hoursEach, count)
    local stretches, first, last = AddUp(hoursEach, count)

    local flow = {}
    for at = first, last do
        local stretch = stretches[at]
        if stretch and stretch.income + stretch.spending > 0 then
            table.insert(flow, { at = at, income = stretch.income, spending = stretch.spending })
        end
    end
    return flow, first, last
end

--- What the account held at the end of each of a run of stretches.
---
--- Starts at the first stretch there's a figure for, not at the start of
--- the window: before that nothing is known. A stretch with no figure of
--- its own carries the last one forward.
---@param hoursEach number
---@param count number
---@return table coin         list of copper, one for each stretch from
---        first to last; empty if nothing is on record in the window
---@return number|nil first   the stretch the list starts on
---@return number last        the one we're in
function Purse.Coin(hoursEach, count)
    local stretches, windowStart, last = AddUp(hoursEach, count)

    local coin, first, held = {}, nil, nil
    for at = windowStart, last do
        held = stretches[at] and stretches[at].coin or held
        if held then
            first = first or at
            table.insert(coin, held)
        end
    end
    return coin, first, last
end

--- Average income and spending over the days the player was active.
---@param numDays number  how far back to look, counting today
---@return number income       copper per active day
---@return number spending     copper per active day
---@return number activeDays   how many days in the window had any activity
---@return string|nil biggest  the spending category that cost the most
function Purse.Averages(numDays)
    local income, spending, activeDays = 0, 0, 0
    local byCategory = {}

    for _, day in pairs((AddUp(24, numDays))) do
        if day.income + day.spending > 0 then
            activeDays = activeDays + 1
            income = income + day.income
            spending = spending + day.spending
            for category, amount in pairs(day.byCategory) do
                byCategory[category] = (byCategory[category] or 0) + amount
            end
        end
    end

    local biggest, biggestAmount
    for category, amount in pairs(byCategory) do
        if not biggestAmount or amount > biggestAmount then
            biggest, biggestAmount = category, amount
        end
    end

    if activeDays == 0 then
        return 0, 0, 0, nil
    end
    return income / activeDays, spending / activeDays, activeDays, biggest
end

--- Income and spending for each day the player was active.
---@param numDays number  how far back to look, counting today
---@return table days       list of { day, income, spending } in copper,
---        oldest first. Days with nothing recorded are left out.
---@return number firstDay  the first day of the window
---@return number lastDay   the last: today
function Purse.Daily(numDays)
    local flow, firstDay, today = Purse.Flow(24, numDays)

    local days = {}
    for index, day in ipairs(flow) do
        days[index] = { day = day.at, income = day.income, spending = day.spending }
    end
    return days, firstDay, today
end

-- Repairs ------------------------------------------------------------------------------

--- How worn the player's gear is, as a whole.
---@return number|nil percent  100 is pristine; nil if nothing worn has durability
function Purse.Durability()
    local current, maximum = 0, 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local slotCurrent, slotMaximum = GetInventoryItemDurability(slot)
        if slotCurrent and slotMaximum then
            current = current + slotCurrent
            maximum = maximum + slotMaximum
        end
    end

    if maximum == 0 then
        return nil
    end
    return current / maximum * 100
end

-- The game works out what each worn item would cost to mend and carries
-- the figure with the item's tooltip, wherever the player happens to be.
-- Added up, that's the repair bill before any reputation discount.
--
-- It only changes when the gear does, so it's worked out once and kept.
local gearBill
local gearBillStale = true

local function GearRepairBill()
    if not gearBillStale then
        return gearBill
    end

    local total = 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local data = C_TooltipInfo.GetInventoryItem("player", slot)
        local cost = data and data.repairCost
        -- In restricted content the client can hand over a figure we
        -- aren't allowed to do sums with.
        local usable = type(cost) == "number" and not (issecretvalue and issecretvalue(cost))
        if usable then
            total = total + cost
        end
    end

    gearBill = total
    gearBillStale = false
    return total
end

--- What a full repair would cost.
---
--- Standing at a merchant who repairs, it's that merchant's price, discount
--- and all. Anywhere else it's what the game says each worn item costs to
--- mend. Should the game not say, it's an estimate from what repairs cost
--- per point of wear the last time we saw a real bill.
---@return number|nil cost   copper; nil if there's nothing to go on
---@return boolean exact     false when the figure is the estimate
function Purse.RepairCost()
    local durability = Purse.Durability()
    if not durability then
        return nil, false
    end
    local wear = 100 - durability

    if atMerchant and CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost > 0 and wear > 0 then
            Book().repairRate = cost / wear
        end
        return cost or 0, true
    end

    -- A bill of nothing for gear that's plainly worn means the game kept
    -- the figures to itself, not that repairs are free.
    local bill = GearRepairBill()
    if bill > 0 or wear == 0 then
        return bill, true
    end

    local rate = Book().repairRate
    if not rate then
        return nil, false
    end
    return rate * wear, false
end

-- Opening a repairing merchant is our chance to learn what repairs cost.
ns.OnEvent("MERCHANT_SHOW", function()
    atMerchant = true
    Purse.RepairCost()
    ns.Publish("PURSE_CHANGED")
end)

ns.OnEvent("MERCHANT_CLOSED", function()
    atMerchant = false
    ns.Publish("PURSE_CHANGED")
end)

local function OnGearChanged()
    gearBillStale = true
    ns.Publish("PURSE_CHANGED")
end

ns.OnEvent("UPDATE_INVENTORY_DURABILITY", OnGearChanged)
ns.OnEvent("PLAYER_EQUIPMENT_CHANGED", OnGearChanged)
