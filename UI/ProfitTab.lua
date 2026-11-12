local _, ns = ...

-- The Profit tab: whether the player is coming out ahead. A chart that
-- can show how each day went, how the days added up, or what the player
-- is worth, with what was sold and bought at the auction house above it
-- and the latest of those sales and purchases below.
--
-- The Purse tab is about what's coming and whether there's coin for it.
-- This one looks back.

local ProfitTab = {}
ns.ProfitTab = ProfitTab

local Theme = ns.Theme

-- A month, which is as far back as the purse remembers.
local DAYS = 30

local CHART_TOP = 112
local CHART_HEIGHT = 170

-- How far down the tab the list of sales and purchases starts.
local LIST_TOP = CHART_TOP + CHART_HEIGHT + 30

local ROW_HEIGHT = 26

-- The three things the chart can show, in the order the menu lists them.
-- Each day on its own shows the good days and the bad. Added up as they
-- go, the same figures show whether the month is going anywhere. And what
-- the player is worth is where it has all got to.
local EACH_DAY, RUNNING, WORTH = 1, 2, 3

-- What the two profit views need saying about them.
local HOW_PROFIT_COUNTS = "Sales count when you take the coin from your mailbox. "
    .. "Everything bought at auction counts, whatever it was for."

local VIEWS = {
    [EACH_DAY] = {
        label = "Each day",
        about = "What you came out ahead or behind by, each day for 30 days",
        footer = HOW_PROFIT_COUNTS,
    },
    [RUNNING] = {
        label = "Running total",
        about = "What you're up or down over the last 30 days, as it added up",
        footer = HOW_PROFIT_COUNTS,
    },
    [WORTH] = {
        label = "What you're worth",
        about = "Your coin and your goods, on this side's characters",
        footer = "Goods are counted at their cheapest listing, as though all of them "
            .. "would sell. Take that part as the most they could fetch.",
    },
}

-- The list ---------------------------------------------------------------------------

local function CreateRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row.When = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.When:SetPoint("LEFT", 8, 0)
    row.When:SetWidth(70)
    row.When:SetJustifyH("LEFT")
    row.When:SetTextColor(unpack(Theme.MUTED))

    row.Amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Amount:SetPoint("RIGHT", -10, 0)
    row.Amount:SetJustifyH("RIGHT")

    row.What = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.What:SetPoint("LEFT", row.When, "RIGHT", 8, 0)
    row.What:SetPoint("RIGHT", row.Amount, "LEFT", -12, 0)
    row.What:SetJustifyH("LEFT")
    row.What:SetWordWrap(false)
end

-- "Sold 20 Linen Cloth", "Bought 5 Silk Cloth", "Bid returned".
local function WhatText(entry)
    local name = entry.name or (entry.itemID and ns.ItemName(entry.itemID))

    if entry.kind == ns.Trade.REFUND then
        -- The letter's own subject says which auction it was.
        return name and ("Bid returned: %s"):format(name) or "Bid returned"
    end

    local verb = entry.kind == ns.Trade.SALE and "Sold"
        or entry.kind == ns.Trade.BID and "Bid on"
        or "Bought"
    if not name then
        return entry.kind == ns.Trade.BID and "Bid at auction" or (verb .. " at auction")
    elseif (entry.count or 1) > 1 then
        return ("%s %d %s"):format(verb, entry.count, name)
    end
    return ("%s %s"):format(verb, name)
end

local function FillRow(row, entry)
    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.When:SetText(date("%d %b", entry.at))
    row.What:SetText(WhatText(entry))

    local spent = entry.kind == ns.Trade.PURCHASE or entry.kind == ns.Trade.BID
    local text, color = Theme.SignedCoins(spent and -entry.amount or entry.amount)
    row.Amount:SetText(text)
    row.Amount:SetTextColor(unpack(color))
end

-- The lines ----------------------------------------------------------------------------

-- Turns a figure for each day into a running total.
local function RunningTotal(values)
    local total, totals = 0, {}
    for index, value in ipairs(values) do
        total = total + value
        totals[index] = total
    end
    return totals
end

-- Everything in less everything out, for each day of the stretch. The
-- purse leaves out days with nothing on record, and a line needs them all.
local function OverallByDay(firstDay, lastDay)
    local byDay = {}
    for _, day in ipairs((ns.Purse.Daily(DAYS))) do
        byDay[day.day] = day.income - day.spending
    end

    local values = {}
    for day = firstDay, lastDay do
        table.insert(values, byDay[day] or 0)
    end
    return values
end

-- The tab ------------------------------------------------------------------------------

--- Creates the Profit tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh()
function ProfitTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    local heading = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Profit")

    local about = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))

    local showing = EACH_DAY

    local pick = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    pick:SetSize(150, 20)
    pick:SetPoint("TOPRIGHT", -24, -6)
    pick:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Show...")
            for index, view in ipairs(VIEWS) do
                root:CreateRadio(view.label, function()
                    return showing == index
                end, function()
                    showing = index
                    -- The window takes its footer from the tab, so it has
                    -- to be the one to redraw.
                    ns.Publish("COURSE_CHANGED")
                end)
            end
        end)
    end)

    local sold = Theme.CreateTile(tab, "Sold at auction")
    sold:SetPoint("TOPLEFT", 12, -34)

    local bought = Theme.CreateTile(tab, "Spent at auction")
    bought:SetPoint("LEFT", sold, "RIGHT", 13, 0)

    local net = Theme.CreateTile(tab, "Auction house profit")
    net:SetPoint("LEFT", bought, "RIGHT", 13, 0)

    local chart = ns.Chart.CreateLines(tab, 746, CHART_HEIGHT)
    chart:SetPoint("TOPLEFT", 12, -CHART_TOP)

    local listHeading = tab:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    listHeading:SetPoint("TOPLEFT", 14, -(LIST_TOP - 16))
    listHeading:SetText("LATEST SALES AND PURCHASES")

    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -LIST_TOP)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", function(row, entry)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, entry)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local empty = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("TOP", scrollBox, "TOP", 0, -30)
    empty:SetWidth(560)
    empty:SetTextColor(unpack(Theme.MUTED))
    empty:SetText(
        "Nothing sold or bought on record yet. Sales are counted when you take "
            .. "the coin out of your mailbox, and purchases as you make them."
    )

    -- Draws what the player is worth: one line for everything, and one
    -- for the coin alone, so the gap between them is the goods.
    local function DrawWorth()
        local days, firstDay, lastDay = ns.Worth.Daily(DAYS)

        local everything, coin = {}, {}
        for index, day in ipairs(days) do
            everything[index] = day.coin + day.goods
            coin[index] = day.coin
        end

        chart:SetSeries(
            {
                { label = "Coin and goods", color = Theme.COIN, values = everything },
                { label = "Coin alone", color = Theme.CHART_USUAL, values = coin },
            },
            firstDay or lastDay,
            lastDay,
            #days == 1 and "One day on record so far. The line starts tomorrow."
                or "Nothing on record yet. Goldwise notes what you're worth as you play."
        )
    end

    -- Draws how each day went, or how the days added up.
    local function DrawProfit(running)
        local trade, firstDay, lastDay = ns.Trade.Daily(DAYS)
        local atAuction = {}
        for index, day in ipairs(trade) do
            atAuction[index] = day.net
        end
        local overall = OverallByDay(firstDay, lastDay)

        if running then
            atAuction, overall = RunningTotal(atAuction), RunningTotal(overall)
        end

        chart:SetSeries(
            {
                { label = "Everything", color = Theme.COIN, values = overall },
                {
                    label = "The auction house alone",
                    color = Theme.CHART_USUAL,
                    values = atAuction,
                },
            },
            firstDay,
            lastDay,
            "Nothing earned or spent on record yet. It starts with your next coin."
        )
    end

    --- Rebuilds the tab from what's on record.
    ---@return string footer  a line about what's on show, for the window
    function tab:Refresh()
        local totals = ns.Trade.Totals(DAYS)

        sold.Figure:SetText(Theme.Coins(totals.sold))
        if totals.sales == 0 then
            sold.Note:SetText("Nothing collected from the mailbox yet.")
        else
            sold.Note:SetText(
                ("%d %s, after %s went to the auction house."):format(
                    totals.sales,
                    totals.sales == 1 and "sale" or "sales",
                    ns.Money(totals.cut)
                )
            )
        end

        bought.Figure:SetText(Theme.Coins(totals.bought + totals.deposits))
        bought.Note:SetText(
            ("%s on purchases, %s in deposits."):format(
                ns.Money(totals.bought),
                ns.Money(totals.deposits)
            )
        )

        local text, color = Theme.SignedCoins(totals.net)
        net.Figure:SetText(text)
        net.Figure:SetTextColor(unpack(color))
        net.Note:SetText("Sold, less what you spent there.")

        local chosen = VIEWS[showing]
        if showing == WORTH then
            DrawWorth()
        else
            DrawProfit(showing == RUNNING)
        end
        about:SetText(chosen.about)
        pick:SetText(chosen.label)

        local recent = ns.Trade.Recent()
        empty:SetShown(#recent == 0)
        scrollBox:SetDataProvider(
            CreateDataProvider(recent),
            ScrollBoxConstants.RetainScrollPosition
        )
        return chosen.footer
    end

    return tab
end
