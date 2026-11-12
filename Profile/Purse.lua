local _, ns = ...

-- Where the gold comes from and where it goes.
--
-- The game says when the player's money changes but not why. So we keep
-- track of what they're doing (talking to a vendor, a trainer, the
-- mailbox) and file each change under that. It's the same approach
-- Blizzard's own receipt code takes.
--
-- Totals are kept per day for a month, across the whole account.

local Purse = {}
ns.Purse = Purse

local KEEP_DAYS = 30

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

local function Book()
    if type(ns.db.purse) ~= "table" then
        ns.db.purse = { days = {} }
    end
    return ns.db.purse
end

-- Recording --------------------------------------------------------------------

local function Record(delta)
    local days = Book().days
    local today = ns.Ledger.Today()

    local day = days[today]
    if not day then
        day = { income = {}, spending = {} }
        days[today] = day

        -- A new day is as good a moment as any to drop the oldest.
        for recorded in pairs(days) do
            if recorded <= today - KEEP_DAYS then
                days[recorded] = nil
            end
        end
    end

    local side = delta > 0 and day.income or day.spending
    side[context] = (side[context] or 0) + math.abs(delta)

    -- For anything that wants to look closer at one kind of money than a
    -- daily total (see Trade.lua).
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

--- Average income and spending over the days the player was active.
---@param numDays number  how far back to look, counting today
---@return number income       copper per active day
---@return number spending     copper per active day
---@return number activeDays   how many days in the window had any activity
---@return string|nil biggest  the spending category that cost the most
function Purse.Averages(numDays)
    local days = Book().days
    local today = ns.Ledger.Today()
    local income, spending, activeDays = 0, 0, 0
    local byCategory = {}

    for day = today - numDays + 1, today do
        local record = days[day]
        if record then
            activeDays = activeDays + 1
            for _, amount in pairs(record.income) do
                income = income + amount
            end
            for category, amount in pairs(record.spending) do
                spending = spending + amount
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

--- Income and spending for each day the player was active, for charting.
---@param numDays number  how far back to look, counting today
---@return table days       list of { day, income, spending } in copper,
---        oldest first. Days with nothing recorded are left out.
---@return number firstDay  the first day of the window
---@return number lastDay   the last: today
function Purse.Daily(numDays)
    local recorded = Book().days
    local today = ns.Ledger.Today()
    local firstDay = today - numDays + 1
    local days = {}

    for day = firstDay, today do
        local record = recorded[day]
        if record then
            local income, spending = 0, 0
            for _, amount in pairs(record.income) do
                income = income + amount
            end
            for _, amount in pairs(record.spending) do
                spending = spending + amount
            end
            table.insert(days, { day = day, income = income, spending = spending })
        end
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
