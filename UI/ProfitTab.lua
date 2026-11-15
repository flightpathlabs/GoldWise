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

-- How finely the chart can cut up time, in the order the menu lists them,
-- after "Fits what's on record". About thirty points is as many as stay
-- readable, so the finer the cut, the shorter the time on show.
local SCALES = {
    { label = "30 days, a day at a time", short = "A day at a time", hours = 24, count = 30 },
    { label = "2 weeks, 12 hours at a time", short = "12 hours at a time", hours = 12, count = 28 },
    { label = "A week, 6 hours at a time", short = "6 hours at a time", hours = 6, count = 28 },
    { label = "A day, an hour at a time", short = "An hour at a time", hours = 1, count = 24 },
}

-- Stretch lengths the chart can choose for itself, finest first.
local FITTING_HOURS = { 1, 2, 3, 6, 12, 24 }
local MOST_POINTS = 30

-- The cut that fills the chart from the first thing on record to now:
-- by the hour early on, then wider as the record grows, until a day at a
-- time covers the month.
local function FittingScale(whose)
    local nowHour = math.floor(GetServerTime() / 3600)
    local firstHour = ns.Purse.FirstHour(whose) or nowHour
    for _, hours in ipairs(FITTING_HOURS) do
        local last = ns.Purse.StretchOf(nowHour, hours)
        local count = last - ns.Purse.StretchOf(firstHour, hours) + 1
        if count <= MOST_POINTS or hours == 24 then
            return { hours = hours, count = math.max(2, math.min(count, MOST_POINTS)) }
        end
    end
end

local function ChosenScale(whose)
    return SCALES[ns.settings.profitScale] or FittingScale(whose)
end

-- What one point on the chart stands for: "hour", "6-hour stretch", "day".
local function StretchName(hours)
    if hours == 24 then
        return "day"
    elseif hours == 1 then
        return "hour"
    end
    return ("%d-hour stretch"):format(hours)
end

-- The same, so many at a time: "an hour", "6 hours", "a day".
local function AtATime(hours)
    if hours == 24 then
        return "a day"
    elseif hours == 1 then
        return "an hour"
    end
    return ("%d hours"):format(hours)
end

-- "the last 9 hours", "the last 5 days".
local function SpanText(scale)
    local total = scale.hours * scale.count
    if total < 48 then
        return ("the last %d hours"):format(total)
    end
    return ("the last %d days"):format(math.floor(total / 24 + 0.5))
end

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
        label = "One at a time",
        about = "How each %s went for %s, over %s",
        footer = HOW_PROFIT_COUNTS,
    },
    [RUNNING] = {
        label = "Running total",
        about = "How %s added up for %s, %s at a time",
        footer = HOW_PROFIT_COUNTS,
    },
    [WORTH] = {
        label = "What you're worth",
        about = "The coin and goods held by %s",
        aboutAccount = "The coin and goods held by your characters on this side",
        footer = "Goods are counted at their cheapest listing, as though all of them "
            .. "would sell. Take that part as the most they could fetch.",
    },
}

-- What the list of sales and purchases says when there's nothing in it.
local NO_TRADE = "Nothing sold or bought on record yet. Sales are counted when you take "
    .. "the coin out of your mailbox, and purchases as you make them."

-- The list --------------------------------------------------------------------

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

    -- A sale or purchase of something the game named has the menu every
    -- item in the window has. Left-clicks do nothing here, as before.
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnClick", function(self)
        local entry = self:GetElementData()
        ns.ItemMenu.Open(self, entry.itemID, entry.link)
    end)
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

    -- Across the account, whose sale or purchase it was, where that was
    -- noted. Entries from before it was are left as they are.
    local what = WhatText(entry)

    -- A sale of something bought earlier: what it cost, and what was left.
    if entry.kind == ns.Trade.SALE and entry.cost then
        local profit, color = Theme.SignedCoins(entry.profit or 0)
        what = ("%s  %s %s"):format(
            what,
            Theme.Aside(("paid %s,"):format(ns.Money(entry.cost))),
            CreateColor(unpack(color)):WrapTextInColorCode(profit .. " profit")
        )
    end

    if ns.settings.moneyAccountWide and entry.who then
        what = ("%s  %s"):format(what, Theme.Aside(entry.who))
    end
    row.What:SetText(what)

    local spent = entry.kind == ns.Trade.PURCHASE or entry.kind == ns.Trade.BID
    local text, color = Theme.SignedCoins(spent and -entry.amount or entry.amount)
    row.Amount:SetText(text)
    row.Amount:SetTextColor(unpack(color))

    -- Only entries that know which item it was have a menu. The rest let
    -- the mouse through.
    row:EnableMouse(entry.itemID ~= nil)
end

-- The lines -------------------------------------------------------------------

-- Turns a figure for each day into a running total.
local function RunningTotal(values)
    local total, totals = 0, {}
    for index, value in ipairs(values) do
        total = total + value
        totals[index] = total
    end
    return totals
end

-- Everything in less everything out, for each stretch of the chart. The
-- purse leaves out stretches with nothing on record, and a line needs
-- them all.
local function Overall(scale, whose)
    local flow, first, last = ns.Purse.Flow(scale.hours, scale.count, whose)
    local byStretch = {}
    for _, stretch in ipairs(flow) do
        byStretch[stretch.at] = stretch.income - stretch.spending
    end

    local values = {}
    for at = first, last do
        table.insert(values, byStretch[at] or 0)
    end
    return values
end

-- The tab ---------------------------------------------------------------------

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

    -- How finely time is cut up, beside it.
    local scaleButton = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    scaleButton:SetSize(150, 20)
    scaleButton:SetPoint("RIGHT", pick, "LEFT", -6, 0)
    scaleButton:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Time")
            root:CreateRadio("Fit to what's on record", function()
                return not SCALES[ns.settings.profitScale]
            end, function()
                ns.settings.profitScale = 0
                ns.Publish("COURSE_CHANGED")
            end)
            for index, scale in ipairs(SCALES) do
                root:CreateRadio(scale.label, function()
                    return ns.settings.profitScale == index
                end, function()
                    ns.settings.profitScale = index
                    ns.Publish("COURSE_CHANGED")
                end)
            end
        end)
    end)

    -- Whose money the whole tab is about, beside that.
    local whose = Theme.CreateMoneyScopeButton(tab)
    whose:SetPoint("RIGHT", scaleButton, "LEFT", -6, 0)

    -- The line beside the heading stops short of the buttons.
    about:SetPoint("RIGHT", whose, "LEFT", -10, 0)
    about:SetJustifyH("LEFT")
    about:SetWordWrap(false)

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
    view:SetElementInitializer("Button", function(row, entry)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, entry)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- What to say when there's nothing to show: the usual words across the
    -- account, and for a character, why their own record may be empty.
    local function Nothing(usual)
        if ns.settings.moneyAccountWide then
            return usual
        end
        return Theme.MoneyEmptyText() or usual
    end

    local empty = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("TOP", scrollBox, "TOP", 0, -30)
    empty:SetWidth(560)
    empty:SetTextColor(unpack(Theme.MUTED))

    -- Draws what the player is worth: one line for everything, and one
    -- for the coin alone, so the gap between them is the goods.
    local function DrawWorth()
        local days, firstDay, lastDay = ns.Worth.Daily(DAYS, Theme.MoneyWhose())

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
                or Nothing("Nothing on record yet. Goldwise notes what you're worth as you play.")
        )
    end

    -- Draws how each stretch went, or how they added up.
    local function DrawProfit(running, scale)
        local scope = Theme.MoneyWhose()
        local atAuction, first, last = ns.Trade.Flow(scale.hours, scale.count, scope)
        local overall = Overall(scale, scope)

        if running then
            atAuction, overall = RunningTotal(atAuction), RunningTotal(overall)
        end

        local byHour = scale.hours < 24
        local function Label(stretch)
            return ns.Chart.Label(ns.Purse.StartOf(stretch, scale.hours), byHour)
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
            first,
            last,
            Nothing("Nothing earned or spent on record yet. It starts with your next coin."),
            { firstLabel = Label(first), lastLabel = Label(last) }
        )
    end

    --- Rebuilds the tab from what's on record.
    ---@return string footer  a line about what's on show, for the window
    function tab:Refresh()
        whose:Update()
        local scope = Theme.MoneyWhose()
        local totals = ns.Trade.Totals(DAYS, scope)

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
            ("%s on purchases, %s in deposits not handed back."):format(
                ns.Money(totals.bought),
                ns.Money(totals.deposits)
            )
        )

        local text, color = Theme.SignedCoins(totals.net)
        net.Figure:SetText(text)
        net.Figure:SetTextColor(unpack(color))
        net.Note:SetText("Sold, less what you spent there.")

        local chosen = VIEWS[showing]
        local scale = ChosenScale(scope)
        local owner = Theme.MoneyOwner()
        if showing == WORTH then
            -- What the player is worth is noted a day at a time.
            DrawWorth()
            local words = ns.settings.moneyAccountWide and chosen.aboutAccount or chosen.about
            about:SetText(words:format(owner))
        else
            DrawProfit(showing == RUNNING, scale)
            if showing == RUNNING then
                about:SetText(chosen.about:format(SpanText(scale), owner, AtATime(scale.hours)))
            else
                about:SetText(chosen.about:format(StretchName(scale.hours), owner, SpanText(scale)))
            end
        end
        pick:SetText(chosen.label)
        scaleButton:SetShown(showing ~= WORTH)
        local fixed = SCALES[ns.settings.profitScale]
        scaleButton:SetText(fixed and fixed.short or "Fit to the record")

        local recent = ns.Trade.Recent(scope)
        empty:SetText(Nothing(NO_TRADE))
        empty:SetShown(#recent == 0)
        scrollBox:SetDataProvider(
            CreateDataProvider(recent),
            ScrollBoxConstants.RetainScrollPosition
        )
        return chosen.footer
    end

    return tab
end
