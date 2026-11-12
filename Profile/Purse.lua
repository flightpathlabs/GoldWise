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
    context = "travel"
end)

ns.OnEvent("TAXIMAP_CLOSED", function()
    if context == "travel" then
        context = OTHER
    end
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

--- What a full repair would cost.
---
--- Standing at a merchant who repairs, this is the exact figure. Anywhere
--- else it's an estimate, worked out from what repairs cost per point of
--- wear the last time we saw a real bill.
---@return number|nil cost   copper; nil if we've never seen a repair bill
---@return boolean exact
function Purse.RepairCost()
    local durability = Purse.Durability()
    if not durability then
        return nil, false
    end
    local wear = 100 - durability

    if context == "vendor" and CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost > 0 and wear > 0 then
            Book().repairRate = cost / wear
        end
        return cost or 0, true
    end

    local rate = Book().repairRate
    if not rate then
        return nil, false
    end
    return rate * wear, false
end

-- Opening a repairing merchant is our chance to learn what repairs cost.
ns.OnEvent("MERCHANT_SHOW", function()
    Purse.RepairCost()
    ns.Publish("PURSE_CHANGED")
end)

ns.OnEvent("UPDATE_INVENTORY_DURABILITY", function()
    ns.Publish("PURSE_CHANGED")
end)
