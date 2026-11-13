local _, ns = ...

-- "/gw check": asks the game and Goldwise a few questions and prints the
-- answers.
--
-- Goldwise leans on parts of the game that differ from one client to the
-- next, and on things it has to be shown before it knows them: the bank,
-- the profession windows, a trainer or two. When something doesn't work,
-- the first question is always whether the game offers what's needed and
-- whether Goldwise has seen what it needs to. This answers both in one
-- go, so the lines can be sent back with a report.
--
-- It changes nothing.

local function Say(text, ...)
    ns.Print(text, ...)
    ns.Log("check: " .. text, ...)
end

-- What the newer parts of Goldwise need from the game, by the name of
-- the part. Each is a function that says whether the game has it.
local NEEDS = {
    {
        "The crafting tree's click on an item",
        function()
            return HandleModifiedItemClick ~= nil
        end,
    },
    {
        "Reading recipes from a profession window",
        function()
            return C_TradeSkillUI ~= nil and C_TradeSkillUI.GetRecipeSchematic ~= nil
        end,
    },
    {
        "Telling auction sales apart in the mailbox",
        function()
            return GetInboxInvoiceInfo ~= nil and TakeInboxMoney ~= nil
        end,
    },
    {
        "Noticing purchases and deposits at the auction house",
        function()
            local house = C_AuctionHouse
            return house.PlaceBid ~= nil
                and house.ConfirmCommoditiesPurchase ~= nil
                and house.PostItem ~= nil
                and house.PostCommodity ~= nil
        end,
    },
    {
        "Asking what a listing's deposit will be",
        function()
            return C_AuctionHouse.CalculateItemDeposit ~= nil
                and C_AuctionHouse.CalculateCommodityDeposit ~= nil
        end,
    },
    {
        "Reading a trainer's title",
        function()
            return C_TooltipInfo ~= nil and C_TooltipInfo.GetUnit ~= nil
        end,
    },
    {
        "The Shortcuts page in the options",
        function()
            return Settings.RegisterCanvasLayoutSubcategory ~= nil
        end,
    },
    {
        "Reading the bank",
        function()
            return C_Bank ~= nil and C_Bank.FetchPurchasedBankTabIDs ~= nil
        end,
    },
}

-- How many entries a table has, whatever its keys.
local function CountOf(list)
    local count = 0
    for _ in pairs(list) do
        count = count + 1
    end
    return count
end

--- Runs the check and prints what it finds.
function ns.RunCheck()
    Say("Goldwise %s. What the game offers:", C_AddOns.GetAddOnMetadata(ns.name, "Version") or "?")

    local missing = 0
    for _, need in ipairs(NEEDS) do
        local ok, has = pcall(need[2])
        if not (ok and has) then
            missing = missing + 1
            Say("  MISSING: %s", need[1])
        end
    end
    if missing == 0 then
        Say("  Everything Goldwise asks for is there (%d things).", #NEEDS)
    end

    Say("What Goldwise has seen:")

    local marketKey = ns.Market.Home()
    local lastScan = ns.Ledger.LastScan(marketKey)
    Say(
        "  Prices: %s, on %d days.",
        lastScan and ("read " .. ns.Ago(GetServerTime() - lastScan)) or "never read",
        ns.Ledger.DaysRecorded(marketKey)
    )

    local recipes, professions = 0, {}
    for _, recipe in ipairs(ns.Crafts.Known()) do
        recipes = recipes + 1
        professions[recipe.profession] = true
    end
    Say("  Recipes: %d, from %d professions.", recipes, CountOf(professions))

    local _, bankSeenAt = ns.Bank.Holdings()
    Say(
        "  Bank: %s.",
        bankSeenAt and ("seen " .. ns.Ago(GetServerTime() - bankSeenAt)) or "never opened"
    )

    local totals = ns.Trade.Totals(30, true)
    Say(
        "  Auction record, 30 days: %d sales, %s sold, %s bought, %s in deposits.",
        totals.sales,
        ns.Money(totals.sold),
        ns.Money(totals.bought),
        ns.Money(totals.deposits)
    )

    Say(
        "  Places: %s. Trainers visited: %d.",
        ns.Directory.HasQuestie() and "Questie's list is loaded" or "only what you've visited",
        ns.Directory.VisitedTrainers()
    )

    Say("  Crafting tree click: %s.", ns.Shortcuts.TreeClickHint() or "off")

    Say("Done. If something isn't working, send these lines with /gw report.")
end
