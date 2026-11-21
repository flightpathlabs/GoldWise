local _, ns = ...

-- The Money tab: three questions about the player's money. Are they
-- making any, what's worth their time, and can they afford what's next.
-- One bar across the top says whose money and over how long, and every
-- figure on the tab follows it.
--
-- It took over from the Purse and Profit tabs in 0.6.0. The "Coming up"
-- list with its Where buttons, the verdict under it, the cash flow chart
-- and the latest sales and purchases came across from those as they were.

local MoneyTab = {}
ns.MoneyTab = MoneyTab

local Theme = ns.Theme

-- The scrolling page inside the window's inset, which is 770 wide. The
-- scroll bar takes the rest.
local PAGE_WIDTH = 728
local COLUMN_GAP = 24
local COLUMN_WIDTH = (PAGE_WIDTH - COLUMN_GAP) / 2

-- Space between the three sections, and above a section's heading.
local SECTION_GAP = 14

local CHART_HEIGHT = 84

-- What the tab can look back over, in the order the bar lists them. days
-- counts today; a session has none, and is as long as it's been going.
-- hours and count cut the chart into about as many bars as stay readable,
-- and SessionBars does the same for a session.
local PERIODS = {
    {
        key = "session",
        label = "This session",
        over = "this session",
    },
    {
        key = "week",
        label = "7 days",
        over = "the last 7 days",
        heading = "LAST 7 DAYS, 6 HOURS A BAR",
        days = 7,
        hours = 6,
        count = 28,
    },
    {
        key = "month",
        label = "30 days",
        over = "the last 30 days",
        heading = "LAST 30 DAYS, A DAY A BAR",
        days = 30,
        hours = 24,
        count = 30,
    },
}

-- Days of income and spending the "Coming up" verdict is judged on, as
-- the Purse tab judged it, whatever the bar says.
local VERDICT_DAYS = 7

-- Upcoming training levels listed before we stop.
local LEVELS_SHOWN = 3

local COMING_ROW_HEIGHT = 30
local BAR_ROW_HEIGHT = 18
local TABLE_ROW_HEIGHT = 32
local TABLE_HEADER_HEIGHT = 22
local TRADE_ROW_HEIGHT = 26

-- Rows in either view of "What's worth your time?" before the rest are
-- left out, and lines of the latest trades on show before it scrolls.
local MOST_ROWS = 10
local TRADE_ROWS_SHOWN = 6

-- How an activity's earnings are judged. The yardstick is the player's
-- own overall rate: everything every activity in the list brought in,
-- over all the time spent on them.
--   Worth repeating: at least three quarters of that rate.
--   Barely pays:     more than nothing, but short of that.
--   Doesn't pay:     nothing at all.
-- An activity only counts what came in while doing it, never what was
-- spent, so none of them can lose money. Under ten minutes of anything is
-- too little to judge either way.
local WORTH_SHARE = 0.75
local LEAST_SECONDS = 10 * 60

-- A bought item whose sales cleared less than this share of what the ones
-- sold had cost barely paid for the trouble.
local THIN_MARGIN = 0.1

-- The colours verdicts are written in. Each is shown with its words, so
-- nothing depends on telling one from another.
local TONES = {
    good = Theme.INCOME,
    thin = Theme.VERB_COLORS.hold,
    bad = Theme.SPENDING,
    unsure = Theme.MUTED,
}

-- What the two views say about how they count.
local HOW_ACTIVITY_COUNTS = "Per hour is the coin you picked up and what new loot would "
    .. "sell for, from your own play. Worth repeating means at least three quarters of "
    .. "your rate across all of it, which is %s an hour."
local HOW_TRADE_COUNTS = "Brought in is after the auction house's cut and any lost "
    .. "deposits. Farmed things cost nothing but time; What you did shows that."

-- What the tab says when a part of it has nothing to show, and how to
-- fill it. Each takes the period, as "the last 7 days".
local NO_FLOW = "Nothing came in or went out over %s. It starts with your next coin."
local NO_ACTIVITY = "Nothing on record over %s. Kill, gather, fish or hand in quests, "
    .. "and each thing you do shows up here with what it earned an hour."
local NO_ITEMS = "Nothing bought or sold over %s. Buy or sell at the auction house, "
    .. "or buy from a vendor, and each item shows up here with what it made you."

-- The footers the window shows under each view.
local FOOTERS = {
    "Amounts are full price. Point at a training line to see where your reputation "
        .. "makes it cheaper.",
    "Sales count when you take the coin from your mailbox. "
        .. "Everything bought at auction counts, whatever it was for.",
}

local DID, TRADED = 1, 2
local VIEW_LABELS = { "What you did", "What you traded" }

-- The number columns of each view, from left to right. The verdict comes
-- after them, at the right-hand edge.
local COLUMNS = {
    [DID] = {
        { title = "Time", width = 70 },
        { title = "Per hour", width = 110 },
    },
    [TRADED] = {
        { title = "Cost you", width = 95 },
        { title = "Brought in", width = 95 },
        { title = "Profit", width = 95 },
        { title = "Still have", width = 62 },
    },
}
local VERDICT_WIDTH = 150

-- The purse's categories, as the lists name them and as a sentence does.
-- Over days the auction house's coin is split into sales, buying and
-- deposits (see SplitAuction); a session keeps its sales apart already.
local CAME_IN = {
    auction = { "Auction sales", "auction sales" },
    vendor = { "Selling to vendors", "selling to vendors" },
    loot = { "Looted coin", "looted coin" },
    quest = { "Quests", "quests" },
    mail = { "Mail", "mail" },
    travel = { "Flights", "flights" },
    training = { "Trainers", "trainers" },
    other = { "Everything else", "everything else" },
}
local WENT_OUT = {
    auction = { "At the auction house", "the auction house" },
    bought = { "Bought at auction", "buying at auction" },
    deposits = { "Auction deposits", "auction deposits" },
    vendor = { "Bought from vendors", "vendors" },
    repair = { "Repairs", "repairs" },
    training = { "Training", "training" },
    travel = { "Flights", "flights" },
    mail = { "Postage", "postage" },
    quest = { "Quests", "quests" },
    loot = { "Loot", "loot" },
    other = { "Everything else", "everything else" },
}

local function ChosenPeriod()
    for _, period in ipairs(PERIODS) do
        if period.key == ns.settings.moneyPeriod then
            return period
        end
    end
    -- 30 days, as a new player starts on.
    return PERIODS[3]
end

-- The session belongs to the character being played. Across the account
-- it's the same one, as nobody else is playing; anyone else has none.
local function SessionFor(whose)
    if whose ~= true and whose ~= ns.Characters.CurrentKey() then
        return nil
    end
    return ns.Session.Summary()
end

-- The moment the period starts, as server time: midnight on the first of
-- its days by the player's clock, or when the session began.
local function SinceTime(period, session)
    if period.days then
        return (ns.Ledger.Today() - period.days + 1) * ns.SECONDS_PER_DAY - ns.ClockOffset()
    end
    return GetServerTime() - (session and session.seconds or 0)
end

-- A session is charted an hour a bar for its first day, two hours a bar
-- into its second and six after that. Six hours a bar fits a week of it,
-- which is longer than anyone stays logged in.
local SESSION_MOST_BARS = 28

-- How long each bar of a session's chart is, and how many there are,
-- from the one it began in. They line up with the purse's own stretches,
-- which are counted on the player's clock.
local function SessionBars(seconds)
    local hours = seconds <= 24 * 3600 and 1 or seconds <= 48 * 3600 and 2 or 6
    local length = hours * 3600
    local now = GetServerTime() + ns.ClockOffset()
    local count = math.floor(now / length) - math.floor((now - seconds) / length) + 1
    return hours, math.max(2, math.min(SESSION_MOST_BARS, count))
end

local function Percent(fraction)
    return math.floor(fraction * 100 + 0.5)
end

-- "45 min", "2.3 h".
local function Duration(seconds)
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then
        return ("%d min"):format(math.max(1, minutes))
    end
    return ("%.1f h"):format(seconds / 3600)
end

-- "20 minutes played", "About 2.5 hours played".
local function PlayedText(seconds)
    if seconds < 3600 then
        local minutes = math.max(1, math.floor(seconds / 60))
        return ("%d %s played"):format(minutes, minutes == 1 and "minute" or "minutes")
    end
    local hours = seconds / 3600
    if hours < 1.05 then
        return "About an hour played"
    elseif hours < 10 then
        return ("About %.1f hours played"):format(hours)
    end
    return ("About %d hours played"):format(math.floor(hours + 0.5))
end

local function Muted(fontString)
    fontString:SetTextColor(unpack(Theme.MUTED))
    return fontString
end

-- A wrapped line's height. Measured with the tab on show, which is the
-- only time it's laid out.
local function Height(fontString)
    return fontString:IsShown() and fontString:GetStringHeight() or 0
end

-- A faint line across the page, above each section after the first.
local function AddRule(section)
    local rule = section:CreateTexture(nil, "BACKGROUND")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    rule:SetColorTexture(1, 1, 1, 0.08)
end

local function AddHeading(section, text, top)
    local heading = section:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 2, -top)
    heading:SetText(text)
    return heading
end

local function Place(region, parent, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- Section 1: where it came from and went ---------------------------------------

-- Over days, the purse files the auction house's coin by where it changed
-- hands: sales and returned bids arrive by post, and what's paid there is
-- one sum for buying and deposits. The trade book knows which was which,
-- so the lists can say. What came back by post (bids returned, deposits
-- handed back with a sale) is already taken off the trade book's buying
-- and deposits, so it's taken off the mail too, and the difference
-- between the two lists stays what it was.
local function SplitAuction(income, spending, trade)
    local paidThere = spending.auction or 0
    local mail = income.mail or 0
    if paidThere == 0 and mail == 0 then
        return
    end

    local bought = math.min(trade.bought, paidThere)
    local deposits = math.min(trade.deposits, paidThere - bought)
    local cameBack = paidThere - bought - deposits
    local sales = math.min(trade.sold, mail)

    income.auction = (income.auction or 0) + sales
    income.mail = math.max(0, mail - sales - cameBack)
    spending.auction = nil
    spending.bought = bought
    spending.deposits = deposits
end

-- A category's amounts as a list for the bars, biggest first.
local function Listed(amounts, names)
    local list, total = {}, 0
    for category, amount in pairs(amounts) do
        if amount > 0 then
            local name = names[category] or names.other
            table.insert(list, { label = name[1], phrase = name[2], amount = amount })
            total = total + amount
        end
    end
    table.sort(list, function(a, b)
        return a.amount > b.amount
    end)
    return list, total
end

-- What came in and went out over the period, by category. Nil when there's
-- nothing to go on: a session for someone who isn't being played.
local function Flows(period, whose, session)
    local income, spending
    if period.days then
        income, spending = ns.Purse.ByCategory(period.days, whose)
        SplitAuction(income, spending, ns.Trade.Totals(period.days, whose))
    elseif session then
        income, spending = session.income or {}, session.spending or {}
    else
        return nil
    end

    local cameIn, totalIn = Listed(income, CAME_IN)
    local wentOut, totalOut = Listed(spending, WENT_OUT)
    return cameIn, wentOut, totalIn, totalOut
end

-- The plain sentence under the headline figure.
local function FlowSentence(net, cameIn, wentOut)
    local lead = net > 0 and "You're up." or net < 0 and "You're down." or "You've broken even."
    local source, cost = cameIn[1], wentOut[1]
    if source and cost then
        return ("%s Most of it came from %s, and %s cost you the most."):format(
            lead,
            source.phrase,
            cost.phrase
        )
    elseif source then
        return ("%s Most of it came from %s, and nothing went out."):format(lead, source.phrase)
    end
    return ("%s Nothing came in, and %s cost you the most."):format(lead, cost.phrase)
end

-- One of the two short lists under the headline: a caption, then a thin
-- bar for each category, all to the scale of the biggest.
local function CreateFlowList(parent, caption, color)
    local list = CreateFrame("Frame", nil, parent)
    list:SetWidth(COLUMN_WIDTH)
    list.rows = {}

    local title = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    title:SetPoint("TOPLEFT", 2, 0)
    title:SetText(caption:upper())

    local none = Muted(list:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    none:SetPoint("TOPLEFT", 2, -18)
    none:SetText("Nothing yet.")

    local function CreateBarRow()
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(COLUMN_WIDTH, BAR_ROW_HEIGHT)

        row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Label:SetPoint("LEFT", 2, 0)
        row.Label:SetWidth(128)
        row.Label:SetJustifyH("LEFT")
        row.Label:SetWordWrap(false)

        row.Amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Amount:SetPoint("RIGHT", -2, 0)
        row.Amount:SetWidth(104)
        row.Amount:SetJustifyH("RIGHT")

        -- The game's own bar texture, tinted, on a dark track.
        row.Bar = CreateFrame("StatusBar", nil, row)
        row.Bar:SetPoint("LEFT", row.Label, "RIGHT", 6, 0)
        row.Bar:SetPoint("RIGHT", row.Amount, "LEFT", -8, 0)
        row.Bar:SetHeight(8)
        row.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.Bar:SetStatusBarColor(color[1], color[2], color[3])
        row.Bar:SetMinMaxValues(0, 1)

        local track = row.Bar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0, 0, 0, 0.5)

        return row
    end

    --- Fills the list, and says how tall it came out.
    function list:SetEntries(entries)
        local biggest = entries[1] and entries[1].amount or 0
        for index, entry in ipairs(entries) do
            local row = self.rows[index] or CreateBarRow()
            self.rows[index] = row
            row:SetPoint("TOPLEFT", 0, -(16 + (index - 1) * BAR_ROW_HEIGHT))
            row.Label:SetText(entry.label)
            row.Amount:SetText(Theme.Coins(entry.amount))
            -- Anything at all gets a sliver, so a little isn't read as none.
            row.Bar:SetValue(math.max(entry.amount / biggest, 0.02))
            row:Show()
        end
        for index = #entries + 1, #self.rows do
            self.rows[index]:Hide()
        end
        none:SetShown(#entries == 0)

        local height = 16 + math.max(#entries, 1) * BAR_ROW_HEIGHT
        self:SetHeight(height)
        return height
    end

    return list
end

-- Section 2: what's worth the time ---------------------------------------------

-- An activity's name as the row puts it.
local function ActivityName(activity)
    local label = activity.label or "Something"
    if activity.kind == "kill" then
        return ("Killing %s"):format(label)
    end
    return label
end

local KIND_WORDS = {
    kill = "Hunting",
    gather = "Gathering",
    fish = "Fishing",
    quest = "Questing",
}

local function BelowMaxLevel()
    local most = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
    return (UnitLevel("player") or 0) < most
end

-- The verdict on an activity, and its tone. See WORTH_SHARE.
local function ActivityVerdict(activity, overallRate)
    local levels = activity.kind == "quest" and BelowMaxLevel()
    if (activity.seconds or 0) < LEAST_SECONDS then
        return "Too soon to say", "unsure"
    elseif (activity.earned or 0) <= 0 then
        if levels then
            return "Doesn't pay, but levels you", "thin"
        end
        return "Doesn't pay", "bad"
    end

    local rate = activity.perHour or 0
    if rate > 0 and rate >= overallRate * WORTH_SHARE then
        return "Worth repeating", "good"
    elseif levels then
        return "Barely pays, but levels you", "thin"
    end
    return "Barely pays", "thin"
end

-- The verdict on an item traded, and its tone. profit counts only the
-- ones sold, at what they cost, so a loss is a real one.
local function ItemVerdict(item)
    local profit = item.profit or 0
    if (item.sold or 0) == 0 then
        return "Not sold yet", "unsure"
    elseif profit < 0 then
        return "Sold at a loss", "bad"
    elseif (item.paid or 0) == 0 then
        return "Keep selling", "good"
    end

    local cost = (item.brought or 0) - profit
    if cost > 0 and profit / cost < THIN_MARGIN then
        return "Barely pays", "thin"
    end
    return "Worth reselling", "good"
end

-- What rides on an item: what it made or lost, or what was paid for the
-- ones not sold yet, whichever is more. A stack bought and still waiting
-- to sell has no profit to show, but it's as much at stake as one sold.
local function AtStake(item)
    local bought = item.bought or 0
    local unsold = 0
    if bought > 0 then
        unsold = (item.paid or 0) / bought * math.max(0, bought - (item.sold or 0))
    end
    return math.max(math.abs(item.profit or 0), unsold)
end

local function SortByStake(items)
    local stakes = {}
    for _, item in ipairs(items) do
        stakes[item] = AtStake(item)
    end
    table.sort(items, function(a, b)
        if stakes[a] ~= stakes[b] then
            return stakes[a] > stakes[b]
        end
        return (a.name or "") < (b.name or "")
    end)
end

-- Puts a header's or a row's number cells in their columns, from the
-- right-hand edge in, for the view on show.
local function PlaceCells(frame, cells, verdict, view)
    verdict:ClearAllPoints()
    verdict:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    verdict:SetWidth(VERDICT_WIDTH)

    local columns = COLUMNS[view]
    local right = 8 + VERDICT_WIDTH + 12
    for index = #cells, 1, -1 do
        local cell = cells[index]
        local column = columns[index]
        cell:SetShown(column ~= nil)
        if column then
            cell:ClearAllPoints()
            cell:SetPoint("RIGHT", frame, "RIGHT", -right, 0)
            cell:SetWidth(column.width)
            right = right + column.width + 10
        end
    end
    return right
end

local function CreateTableRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(TABLE_ROW_HEIGHT)

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(24, 24)
    row.Icon:SetPoint("LEFT", 6, 0)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Sub = Muted(row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    row.Sub:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -3)
    row.Sub:SetPoint("RIGHT", row.Name, "RIGHT")
    row.Sub:SetJustifyH("LEFT")
    row.Sub:SetWordWrap(false)

    row.Cells = {}
    for index = 1, 4 do
        local cell = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cell:SetJustifyH("RIGHT")
        cell:SetWordWrap(false)
        row.Cells[index] = cell
    end

    row.Verdict = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Verdict:SetJustifyH("LEFT")
    row.Verdict:SetWordWrap(false)

    -- Items have the menu every item in the window has, and their
    -- tooltip. Activities let the mouse through.
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnClick", function(self)
        if self.itemID then
            ns.ItemMenu.Open(self, self.itemID)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

-- Sets a row's name, with or without an icon before it, clear of the
-- number columns.
local function SetRowName(row, nameRight, icon)
    row.Icon:SetShown(icon ~= nil)
    if icon then
        row.Icon:SetTexture(icon)
    end
    row.Name:ClearAllPoints()
    row.Name:SetPoint("TOPLEFT", row, "TOPLEFT", icon and 38 or 10, -4)
    row.Name:SetPoint("RIGHT", row, "RIGHT", -nameRight, 0)
end

local function SetVerdict(row, text, tone)
    row.Verdict:SetText(text)
    row.Verdict:SetTextColor(unpack(TONES[tone]))
end

local function FillActivity(row, activity, overallRate, nameRight)
    row.itemID = nil
    row:EnableMouse(false)
    SetRowName(row, nameRight, nil)
    row.Name:SetText(ActivityName(activity))

    local kind = KIND_WORDS[activity.kind] or "Playing"
    row.Sub:SetText(activity.where and ("%s in %s"):format(kind, activity.where) or kind)

    row.Cells[1]:SetText(Duration(activity.seconds or 0))
    row.Cells[1]:SetTextColor(1, 1, 1)
    local perHour, color = Theme.SignedCoins(activity.perHour or 0)
    row.Cells[2]:SetText(perHour)
    row.Cells[2]:SetTextColor(unpack((activity.perHour or 0) < 0 and color or { 1, 1, 1 }))

    SetVerdict(row, ActivityVerdict(activity, overallRate))
end

local function FillItem(row, item, nameRight)
    local itemID = item.itemID
    row.itemID = itemID
    row:EnableMouse(itemID ~= nil)

    local icon = itemID and C_Item.GetItemIconByID(itemID) or 134400 -- the question mark
    SetRowName(row, nameRight, icon)
    local name = item.name or (itemID and ns.ItemName(itemID)) or "Something sold at auction"
    row.Name:SetText(Theme.ItemName(name, itemID and C_Item.GetItemQualityByID(itemID)))

    local farmed = (item.bought or 0) == 0 and (item.paid or 0) == 0
    if farmed then
        row.Sub:SetText(("farmed, %d sold"):format(item.sold or 0))
    else
        row.Sub:SetText(("%d bought, %d sold"):format(item.bought or 0, item.sold or 0))
    end

    local white = { 1, 1, 1 }
    local cost, brought, profit, have = unpack(row.Cells)
    cost:SetText(farmed and "farmed" or Theme.Coins(item.paid or 0))
    cost:SetTextColor(unpack(farmed and Theme.MUTED or white))
    brought:SetText((item.sold or 0) > 0 and Theme.Coins(item.brought or 0) or "-")
    brought:SetTextColor(unpack(white))
    local text, color = Theme.SignedCoins(item.profit or 0)
    profit:SetText(text)
    profit:SetTextColor(unpack(color))
    have:SetText(item.held and item.held > 0 and FormatLargeNumber(item.held) or "-")
    have:SetTextColor(unpack(white))

    SetVerdict(row, ItemVerdict(item))
end

-- The latest sales and purchases, as the Profit tab listed them ------------------

-- What the list says when there's nothing in it.
local NO_TRADE = "Nothing sold or bought on record yet. Sales are counted when you take "
    .. "the coin out of your mailbox, and purchases as you make them."

-- "Sold 20 Linen Cloth", "Bought 5 Silk Cloth", "Bid returned".
local function TradeText(entry)
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

local function CreateTradeRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row.When = Muted(row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    row.When:SetPoint("LEFT", 8, 0)
    row.When:SetWidth(70)
    row.When:SetJustifyH("LEFT")

    row.Amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Amount:SetPoint("RIGHT", -10, 0)
    row.Amount:SetJustifyH("RIGHT")

    row.What = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.What:SetPoint("LEFT", row.When, "RIGHT", 8, 0)
    row.What:SetPoint("RIGHT", row.Amount, "LEFT", -12, 0)
    row.What:SetJustifyH("LEFT")
    row.What:SetWordWrap(false)

    -- A sale or purchase of something the game named has the menu every
    -- item in the window has. Left-clicks do nothing here.
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnClick", function(self)
        local entry = self:GetElementData()
        ns.ItemMenu.Open(self, entry.itemID, entry.link)
    end)
end

local function FillTradeRow(row, entry)
    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.When:SetText(date("%d %b", entry.at))

    local what = TradeText(entry)

    -- A sale of something bought earlier: what it cost, and what was left,
    -- where that's known.
    if entry.kind == ns.Trade.SALE and entry.cost then
        if entry.profit then
            local profit, color = Theme.SignedCoins(entry.profit)
            what = ("%s  %s %s"):format(
                what,
                Theme.Aside(("paid %s,"):format(ns.Money(entry.cost))),
                CreateColor(unpack(color)):WrapTextInColorCode(profit .. " profit")
            )
        else
            what = ("%s  %s"):format(what, Theme.Aside(("paid %s"):format(ns.Money(entry.cost))))
        end
    end

    -- Across the account, whose sale or purchase it was, where that was
    -- noted.
    if ns.settings.moneyAccountWide and entry.who then
        what = ("%s  %s"):format(what, Theme.Aside(entry.who))
    end
    row.What:SetText(what)

    local spent = entry.kind == ns.Trade.PURCHASE or entry.kind == ns.Trade.BID
    local text, color = Theme.SignedCoins(spent and -entry.amount or entry.amount)
    row.Amount:SetText(text)
    row.Amount:SetTextColor(unpack(color))

    -- Only entries that know which item it was have a menu.
    row:EnableMouse(entry.itemID ~= nil)
end

-- Section 3: what's coming up, from the Purse tab ------------------------------

-- One line of the "Coming up" list: when, what, how much.
local function CreateComingRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PAGE_WIDTH, COMING_ROW_HEIGHT)

    row.When = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.When:SetPoint("LEFT", 4, 0)
    row.When:SetWidth(120)
    row.When:SetJustifyH("LEFT")

    -- A button at the far end, for the lines that can point at a map. The
    -- amounts keep clear of it on every line, so they stay in a column.
    row.Where = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Where:SetSize(64, 22)
    row.Where:SetPoint("RIGHT", -4, 0)
    row.Where:SetText("Where")
    row.Where:Hide()
    row.Where:SetScript("OnClick", function(self)
        local line = self:GetParent()
        if line.pickPlace then
            line.pickPlace(line, self)
        end
    end)

    row.Amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Amount:SetPoint("RIGHT", row.Where, "LEFT", -10, 0)
    row.Amount:SetJustifyH("RIGHT")

    row.What = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.What:SetPoint("LEFT", row.When, "RIGHT", 8, 0)
    row.What:SetPoint("RIGHT", row.Amount, "LEFT", -12, 0)
    row.What:SetJustifyH("LEFT")
    row.What:SetWordWrap(false)

    local rule = row:CreateTexture(nil, "BACKGROUND")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetColorTexture(1, 1, 1, 0.08)

    -- Some lines have more to say when pointed at. Those light up, so the
    -- player can tell which.
    row.Glow = row:CreateTexture(nil, "BACKGROUND")
    row.Glow:SetAllPoints()
    row.Glow:SetColorTexture(1, 1, 1, 0.05)
    row.Glow:Hide()

    row:SetScript("OnEnter", function(self)
        if self.showMore then
            self.Glow:Show()
            self.showMore(self)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.Glow:Hide()
        GameTooltip:Hide()
    end)

    return row
end

-- "Stormwind", or "Ironforge (Gnomeregan Exiles)" where the trainers are
-- guests in someone else's city.
local function PlaceName(place)
    return place.faction and ("%s (%s)"):format(place.city, place.faction) or place.city
end

local function PriceAt(place, fullPrice)
    return math.floor(fullPrice * (1 - place.discount) + 0.5)
end

local function ShowOnMap(place)
    if place.spot then
        ns.MapMarks.ShowPoint(place.mapID, place.spot.x, place.spot.y)
    else
        ns.MapMarks.ShowZone(place.mapID)
        ns.Print(
            "That's %s, not the trainer's door. Goldwise marks the trainer "
                .. "once you've visited one there, or straight away with Questie installed.",
            place.city
        )
    end
end

-- The menu behind a training line's Where button: each city's trainers and
-- what they'd charge. Picking one opens the map there.
local function PickTrainingPlace(row, button)
    local places = ns.Training.Places()

    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle("Where to train")

        for _, place in ipairs(places) do
            local label = ("%s: %s"):format(PlaceName(place), ns.Money(PriceAt(place, row.amount)))
            if place.discount > 0 then
                label = label .. (", %d%% off"):format(Percent(place.discount))
            end

            local choice = root:CreateButton(label, function()
                ShowOnMap(place)
            end)
            -- Somewhere we can't put on a map is still worth listing for
            -- its price.
            choice:SetEnabled(place.mapID ~= nil)
        end
    end)
end

-- The hover card for a line of training: what the same skills cost from
-- each city's trainers, given what the player's reputation there earns.
local function ShowTrainingPlaces(row)
    local places = ns.Training.Places()
    if #places == 0 then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:AddLine("Where to train", unpack(Theme.COIN))

    for _, place in ipairs(places) do
        local standing = place.standing
        if place.shortBy then
            standing = ("%s, %s short of %s"):format(
                standing,
                FormatLargeNumber(place.shortBy),
                place.discountStanding
            )
        end

        local red, green, blue = 1, 1, 1
        if place.discount > 0 then
            red, green, blue = GREEN_FONT_COLOR:GetRGB()
        end

        GameTooltip:AddDoubleLine(
            ("%s: %s"):format(PlaceName(place), standing),
            ns.Money(PriceAt(place, row.amount)),
            1,
            1,
            1,
            red,
            green,
            blue
        )
    end

    local muted = Theme.MUTED
    GameTooltip:AddLine(
        ("%s or better with a trainer's people takes %d%% off."):format(
            places[1].discountStanding,
            Percent(ns.Training.REPUTATION_DISCOUNT)
        ),
        muted[1],
        muted[2],
        muted[3],
        true
    )
    GameTooltip:AddLine("Press Where to find them on the map.", muted[1], muted[2], muted[3])
    GameTooltip:Show()
end

-- Each entry is { when, what, amount, showMore, pickPlace }. amount is in
-- copper, or nil if unknown. showMore puts up a tooltip for the line, and
-- pickPlace answers its Where button; both only where there's something
-- worth having. The goal isn't one of them here: it has its own bar.
local function UpcomingCosts(level)
    local costs = {}

    local durability = ns.Purse.Durability()
    if durability then
        local repair, exact = ns.Purse.RepairCost()
        local what = ("Your gear is at %d%%."):format(math.floor(durability))
        if not repair then
            what = what .. " Visit any repairer once and Goldwise will learn the cost."
        elseif not exact then
            what = what .. " An estimate, from your last repair bill."
        end
        table.insert(costs, { when = "Repairs", what = what, amount = repair })
    end

    local training = ns.Training.Outstanding(level)
    if not ns.Training.HasPrices() then
        table.insert(costs, {
            when = "Training",
            what = "Open your class trainer once and Goldwise will learn the prices.",
        })
    end

    -- Amounts are the full price. If the player's reputation somewhere
    -- earns a discount, say where; pointing at the line lists every city.
    local places = ns.Training.Places()
    local cheapest = places[1]
    local discountNote = ""
    if cheapest and cheapest.discount > 0 then
        discountNote = (" %d%% off in %s."):format(Percent(cheapest.discount), cheapest.city)
    end
    local showMore = #places > 0 and ShowTrainingPlaces or nil
    local pickPlace = #places > 0 and PickTrainingPlace or nil

    for index, entry in ipairs(training) do
        if index > LEVELS_SHOWN then
            break
        end

        local skills = entry.skills == 1 and "1 skill" or (entry.skills .. " skills")
        if entry.level <= level then
            table.insert(costs, {
                when = "Training now",
                what = skills .. " waiting at your trainer." .. discountNote,
                amount = entry.cost,
                showMore = showMore,
                pickPlace = pickPlace,
            })
        else
            local away = entry.level - level
            table.insert(costs, {
                when = "Level " .. entry.level,
                what = ("%s to train, %d %s away."):format(
                    skills,
                    away,
                    away == 1 and "level" or "levels"
                ),
                amount = entry.cost,
                showMore = showMore,
                pickPlace = pickPlace,
            })
        end
    end

    return costs
end

-- The verdict under the list: can they cover what's next? The goal's bar
-- speaks for the goal.
local function Verdict(money, income, spending, costs)
    -- "Next" is the repairs, if we can put a price on them, plus the first
    -- thing after them with a price.
    local due, name, repairs = 0, nil, false
    for _, cost in ipairs(costs) do
        if cost.amount then
            due = due + cost.amount
            if cost.when == "Repairs" then
                repairs = cost.amount > 0
            else
                name = cost.when
                break
            end
        end
    end

    local loud = ns.settings.auditorMode
    local net = income - spending
    local lines = {}

    if name then
        local label = name == "Training now" and "the training waiting for you"
            or (name:lower() .. " training")
        -- Only speak for the repairs when their cost is in the sum.
        if repairs then
            label = "repairs and " .. label
        end

        if money >= due then
            table.insert(
                lines,
                ("You can cover %s, with about %s to spare."):format(
                    label,
                    Theme.Coins(money - due)
                )
            )
        elseif net > 0 then
            local short = "You're about %s short for %s. "
                .. "At your recent pace that's about %d days of play."
            table.insert(
                lines,
                short:format(Theme.Coins(due - money), label, math.ceil((due - money) / net))
            )
        else
            table.insert(
                lines,
                ("You're about %s short for %s."):format(Theme.Coins(due - money), label)
            )
        end
    end

    if spending > income and spending > 0 then
        table.insert(
            lines,
            loud and "You are spending MORE than you make. That is not a budget."
                or "Lately you've been spending more than you make."
        )
    end

    return table.concat(lines, "\n")
end

-- The tab ---------------------------------------------------------------------

--- Creates the Money tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh()
function MoneyTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    -- "What you did" or "What you traded", as it was last left.
    local view = ns.settings.moneyView == TRADED and TRADED or DID

    -- Who and when ------------------------------------------------------------

    local scope = CreateFrame("Frame", nil, tab)
    scope:SetPoint("TOPLEFT", 8, -6)
    scope:SetPoint("TOPRIGHT", -8, -6)
    scope:SetHeight(30)

    local scopeWash = scope:CreateTexture(nil, "BACKGROUND")
    scopeWash:SetAllPoints()
    scopeWash:SetColorTexture(0, 0, 0, Theme.CHART_WASH)

    local whoLabel = scope:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    whoLabel:SetPoint("LEFT", 10, 0)
    whoLabel:SetText("WHO")

    local whose = Theme.CreateMoneyScopeButton(scope)
    whose:SetPoint("LEFT", whoLabel, "RIGHT", 8, 0)

    local overLabel = scope:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    overLabel:SetPoint("LEFT", whose, "RIGHT", 18, 0)
    overLabel:SetText("OVER")

    -- One button for each period, the chosen one lit.
    local periodButtons = {}
    for index, period in ipairs(PERIODS) do
        local button = CreateFrame("Button", nil, scope, "UIPanelButtonTemplate")
        button:SetSize(96, 20)
        button:SetText(period.label)
        if index == 1 then
            button:SetPoint("LEFT", overLabel, "RIGHT", 8, 0)
        else
            button:SetPoint("LEFT", periodButtons[index - 1], "RIGHT", 2, 0)
        end
        button:SetScript("OnClick", function()
            ns.settings.moneyPeriod = period.key
            ns.Publish("COURSE_CHANGED")
        end)
        if not period.days then
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText("This session")
                GameTooltip:AddLine(
                    "Since you logged in on this character, or since you last started "
                        .. "the session again from the session tracker.",
                    1,
                    1,
                    1,
                    true
                )
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
        end
        periodButtons[index] = button
    end

    local played = Muted(scope:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    played:SetPoint("RIGHT", -10, 0)

    -- The page, which scrolls when it's taller than the window ----------------

    -- The template brings its own scroll bar.
    local scroll = CreateFrame("ScrollFrame", nil, tab, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", scope, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local page = CreateFrame("Frame", nil, scroll)
    page:SetSize(PAGE_WIDTH, 1)
    scroll:SetScrollChild(page)

    local making = CreateFrame("Frame", nil, page)
    making:SetPoint("TOPLEFT")
    making:SetWidth(PAGE_WIDTH)

    local worth = CreateFrame("Frame", nil, page)
    worth:SetPoint("TOPLEFT", making, "BOTTOMLEFT", 0, -SECTION_GAP)
    worth:SetWidth(PAGE_WIDTH)
    AddRule(worth)

    local afford = CreateFrame("Frame", nil, page)
    afford:SetPoint("TOPLEFT", worth, "BOTTOMLEFT", 0, -SECTION_GAP)
    afford:SetWidth(PAGE_WIDTH)
    AddRule(afford)

    -- 1. Are you making money? ------------------------------------------------

    AddHeading(making, "Are you making money?", 6)

    local headline = making:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    Place(headline, making, 2, 32)

    local because = making:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    because:SetWidth(PAGE_WIDTH - 4)
    because:SetJustifyH("LEFT")

    local cameIn = CreateFlowList(making, "Came in", Theme.INCOME)
    local wentOut = CreateFlowList(making, "Went out", Theme.SPENDING)

    local chartCaption = making:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    local chart = ns.Chart.CreateCashFlow(making, PAGE_WIDTH, CHART_HEIGHT)

    local function DrawChart(period, scopeWhose, session)
        local hours, count, heading = period.hours, period.count, period.heading
        if not period.days then
            -- The last day an hour a bar for someone who isn't being
            -- played, and otherwise the session from where it began.
            hours, count = 1, 24
            if session then
                hours, count = SessionBars(session.seconds)
            end
            heading = hours == 1 and "THIS SESSION, AN HOUR A BAR"
                or ("THIS SESSION, %d HOURS A BAR"):format(hours)
        end

        local byHour = hours < 24
        local function Label(stretch)
            return ns.Chart.Label(ns.Purse.StartOf(stretch, hours), byHour)
        end

        chartCaption:SetText(("CASH FLOW FOR %s, %s"):format(Theme.MoneyOwner():upper(), heading))
        local bars, first, last = ns.Purse.Flow(hours, count, scopeWhose)
        local emptyText = scopeWhose ~= true and Theme.MoneyEmptyText() or nil
        chart:SetBars(bars, first, last, Label(first), Label(last), emptyText)
    end

    -- Fills the first section and lays it out.
    local function RefreshMaking(period, scopeWhose, session)
        local inList, outList, totalIn, totalOut = Flows(period, scopeWhose, session)

        if not inList then
            headline:SetText("-")
            headline:SetTextColor(unpack(Theme.MUTED))
            because:SetText(
                ("%s isn't being played, so there's no session to show. "):format(
                    Theme.MoneyOwner()
                ) .. "Pick 7 days or 30 days to see what they made."
            )
            inList, outList = {}, {}
        elseif totalIn + totalOut == 0 then
            headline:SetText(Theme.Coins(0))
            headline:SetTextColor(unpack(Theme.MUTED))
            local empty = period.days and scopeWhose ~= true and Theme.MoneyEmptyText()
            because:SetText(empty or NO_FLOW:format(period.over))
        else
            local net = totalIn - totalOut
            local text, color = Theme.SignedCoins(net)
            headline:SetText(net > 0 and ("+" .. text) or text)
            headline:SetTextColor(unpack(color))
            because:SetText(FlowSentence(net, inList, outList))
        end

        local y = 32 + 30
        Place(because, making, 2, y)
        y = y + Height(because) + 14

        Place(cameIn, making, 0, y)
        Place(wentOut, making, COLUMN_WIDTH + COLUMN_GAP, y)
        y = y + math.max(cameIn:SetEntries(inList), wentOut:SetEntries(outList)) + 14

        Place(chartCaption, making, 2, y)
        Place(chart, making, 0, y + 14)
        DrawChart(period, scopeWhose, session)
        making:SetHeight(y + 14 + CHART_HEIGHT)
    end

    -- 2. What's worth your time? ----------------------------------------------

    AddHeading(worth, "What's worth your time?", SECTION_GAP)

    -- The box both views fill, with the game's own top tabs to pick one.
    local box = CreateFrame("Frame", nil, worth)
    box:SetWidth(PAGE_WIDTH)

    local boxWash = box:CreateTexture(nil, "BACKGROUND")
    boxWash:SetAllPoints()
    boxWash:SetColorTexture(0, 0, 0, Theme.CHART_WASH)

    -- The template adds each tab to its parent's Tabs, so these are the
    -- box's own, apart from the window's along the bottom.
    for index, label in ipairs(VIEW_LABELS) do
        local viewTab = CreateFrame("Button", nil, box, "PanelTopTabButtonTemplate")
        viewTab:SetID(index)
        viewTab:SetText(label)
        PanelTemplates_TabResize(viewTab, 0)
        viewTab:SetScript("OnClick", function(self)
            view = self:GetID()
            ns.settings.moneyView = view
            -- The window takes its footer from the tab, so it has to be
            -- the one to redraw.
            ns.Publish("COURSE_CHANGED")
        end)
        if index == 1 then
            viewTab:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 12, 0)
        end
    end
    PanelTemplates_SetNumTabs(box, #VIEW_LABELS)
    PanelTemplates_SetTab(box, view)

    local header = CreateFrame("Frame", nil, box)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(TABLE_HEADER_HEIGHT)

    local headerName = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    headerName:SetPoint("LEFT", 10, 0)
    local headerCells = {}
    for index = 1, 4 do
        local cell = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        cell:SetJustifyH("RIGHT")
        headerCells[index] = cell
    end
    local headerVerdict = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    headerVerdict:SetJustifyH("LEFT")
    headerVerdict:SetText("VERDICT")

    local tableRows = {}

    local boxEmpty = Muted(box:CreateFontString(nil, "ARTWORK", "GameFontHighlight"))
    boxEmpty:SetPoint("TOP", 0, -20)
    boxEmpty:SetWidth(PAGE_WIDTH - 80)

    local worthNote = Muted(worth:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    worthNote:SetWidth(PAGE_WIDTH - 4)
    worthNote:SetJustifyH("LEFT")

    -- The latest sales and purchases, under What you traded.
    local tradesCaption = worth:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tradesCaption:SetText("LATEST SALES AND PURCHASES")

    local trades = CreateFrame("Frame", nil, worth, "WowScrollBoxList")
    trades:SetSize(PAGE_WIDTH - 20, TRADE_ROWS_SHOWN * TRADE_ROW_HEIGHT)

    local tradesBar = CreateFrame("EventFrame", nil, worth, "MinimalScrollBar")
    tradesBar:SetPoint("TOPLEFT", trades, "TOPRIGHT", 6, 0)
    tradesBar:SetPoint("BOTTOMLEFT", trades, "BOTTOMRIGHT", 6, 0)

    local tradesView = CreateScrollBoxListLinearView()
    tradesView:SetElementExtent(TRADE_ROW_HEIGHT)
    tradesView:SetElementInitializer("Button", function(row, entry)
        if not row.created then
            CreateTradeRowWidgets(row)
        end
        FillTradeRow(row, entry)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(trades, tradesBar, tradesView)

    local tradesEmpty = Muted(worth:CreateFontString(nil, "ARTWORK", "GameFontHighlight"))
    tradesEmpty:SetPoint("TOP", trades, "TOP", 0, -30)
    tradesEmpty:SetWidth(PAGE_WIDTH - 80)

    -- The rows for the chosen view, and what to say under them.
    local function TableContents(sinceTime, scopeWhose, period, session)
        if not period.days and not session then
            return nil,
                ("%s isn't being played, so there's no session to show."):format(Theme.MoneyOwner())
        end

        if view == DID then
            if not (ns.Activity and ns.Activity.Summary) then
                return nil,
                    "Goldwise can't keep track of what you do yet. Restart the game "
                        .. "after updating it, and it starts with your next kill, herb or quest."
            end
            local activities = ns.Activity.Summary(sinceTime, scopeWhose) or {}
            -- Activities have been kept for each character from the start,
            -- so there's no older record under the account to point to.
            if #activities == 0 then
                return nil, NO_ACTIVITY:format(period.over)
            end
            return activities
        end

        if not ns.Trade.Items then
            return nil,
                "Goldwise can't add up what you traded yet. Restart the game after "
                    .. "updating it."
        end
        local items = ns.Trade.Items(sinceTime, scopeWhose) or {}
        -- Items have been added up from this version on, for everyone at
        -- once, so here too there's nothing older under the account.
        if #items == 0 then
            return nil, NO_ITEMS:format(period.over)
        end
        SortByStake(items)
        return items
    end

    -- Everything the activities brought in, an hour, across all of them.
    local function OverallRate(activities)
        local seconds, earned = 0, 0
        for _, activity in ipairs(activities) do
            seconds = seconds + (activity.seconds or 0)
            earned = earned + (activity.earned or 0)
        end
        return seconds > 0 and earned / seconds * 3600 or 0
    end

    local function RefreshWorth(period, scopeWhose, session)
        PanelTemplates_SetTab(box, view)

        -- The header names the columns of the view on show.
        local nameRight = PlaceCells(header, headerCells, headerVerdict, view)
        headerName:SetText(VIEW_LABELS[view]:upper())
        for index, column in ipairs(COLUMNS[view]) do
            headerCells[index]:SetText(column.title:upper())
        end

        local sinceTime = SinceTime(period, session)
        local entries, emptyText = TableContents(sinceTime, scopeWhose, period, session)
        entries = entries or {}

        local overallRate = view == DID and OverallRate(entries) or 0
        local shown = math.min(#entries, MOST_ROWS)
        for index = 1, shown do
            local row = tableRows[index] or CreateTableRow(box)
            tableRows[index] = row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(TABLE_HEADER_HEIGHT + (index - 1) * TABLE_ROW_HEIGHT))
            row:SetPoint("RIGHT")
            row.Stripe:SetShown(index % 2 == 0)
            PlaceCells(row, row.Cells, row.Verdict, view)
            if view == DID then
                FillActivity(row, entries[index], overallRate, nameRight)
            else
                FillItem(row, entries[index], nameRight)
            end
            row:Show()
        end
        for index = shown + 1, #tableRows do
            tableRows[index]:Hide()
        end

        header:SetShown(shown > 0)
        boxEmpty:SetShown(shown == 0)
        boxEmpty:SetText(emptyText or "")

        local boxHeight = shown > 0 and (TABLE_HEADER_HEIGHT + shown * TABLE_ROW_HEIGHT + 4)
            or (Height(boxEmpty) + 40)
        box:SetHeight(boxHeight)

        -- Room above the box for the heading and the tabs that sit on it.
        local y = SECTION_GAP + 50
        Place(box, worth, 0, y)
        y = y + boxHeight + 8

        local note = view == DID and HOW_ACTIVITY_COUNTS:format((Theme.SignedCoins(overallRate)))
            or HOW_TRADE_COUNTS
        local more = #entries - shown
        if more > 0 then
            -- Said the way each view is ordered: by time, or by what's at
            -- stake (see AtStake).
            local less = view == DID and "less time spent on it"
                or "less made, lost or still to sell"
            if more == 1 then
                note = ("%s One more, with %s, is left out."):format(note, less)
            else
                note = ("%s %d more, each with %s, are left out."):format(note, more, less)
            end
        end
        worthNote:SetText(note)
        worthNote:SetShown(shown > 0)
        if shown > 0 then
            Place(worthNote, worth, 2, y)
            y = y + Height(worthNote) + 6
        end

        -- The latest trades, under the totals they make up.
        local listing = view == TRADED
        tradesCaption:SetShown(listing)
        trades:SetShown(listing)
        tradesBar:SetShown(listing)
        tradesEmpty:SetShown(false)
        if listing then
            y = y + 10
            Place(tradesCaption, worth, 2, y)
            Place(trades, worth, 0, y + 16)

            -- With nothing on the list, say how to fill it, unless the
            -- account has trades this character doesn't: those could be
            -- from before each character's were kept apart.
            local recent = ns.Trade.Recent(scopeWhose)
            local noTrades = NO_TRADE
            if #recent == 0 and scopeWhose ~= true and #ns.Trade.Recent(true) > 0 then
                noTrades = Theme.MoneyEmptyText() or NO_TRADE
            end
            tradesEmpty:SetText(noTrades)
            tradesEmpty:SetShown(#recent == 0)
            trades:SetDataProvider(
                CreateDataProvider(recent),
                ScrollBoxConstants.RetainScrollPosition
            )
            y = y + 16 + TRADE_ROWS_SHOWN * TRADE_ROW_HEIGHT
        end

        worth:SetHeight(y + 6)
    end

    -- 3. Can you afford what's next? ------------------------------------------

    AddHeading(afford, "Can you afford what's next?", SECTION_GAP)

    local have = Theme.CreateTile(afford, "In your purse")
    Place(have, afford, 0, SECTION_GAP + 28)

    -- The goal, beside what's in the purse.
    local GOAL_LEFT = have:GetWidth() + 16
    local goalLabel = afford:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    Place(goalLabel, afford, GOAL_LEFT, SECTION_GAP + 36)
    goalLabel:SetJustifyH("LEFT")

    local goalEta = Muted(afford:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    goalEta:SetPoint("TOPRIGHT", afford, "TOPRIGHT", -4, -(SECTION_GAP + 38))
    goalEta:SetJustifyH("RIGHT")

    local goalBar = CreateFrame("StatusBar", nil, afford)
    Place(goalBar, afford, GOAL_LEFT, SECTION_GAP + 58)
    goalBar:SetPoint("RIGHT", afford, "RIGHT", -4, 0)
    goalBar:SetHeight(12)
    goalBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    goalBar:SetStatusBarColor(unpack(Theme.COIN))
    goalBar:SetMinMaxValues(0, 1)

    local goalTrack = goalBar:CreateTexture(nil, "BACKGROUND")
    goalTrack:SetAllPoints()
    goalTrack:SetColorTexture(0, 0, 0, 0.5)

    local goalNote = Muted(afford:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    goalNote:SetPoint("TOPLEFT", goalBar, "BOTTOMLEFT", 0, -5)

    local comingCaption = afford:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    comingCaption:SetText("COMING UP")

    local comingRows = {}

    -- The verdict sits under the last line of the list, and is placed
    -- there on each refresh. Pinned to the bottom and justified upward,
    -- the words would move and the game's coin icons stay behind.
    local verdict = afford:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    verdict:SetWidth(PAGE_WIDTH - 4)
    verdict:SetJustifyH("LEFT")
    verdict:SetSpacing(4)

    -- What's in the purse, with the other figure underneath, so whichever
    -- is chosen both can be seen.
    local function RefreshPurse(scopeWhose)
        local accountWide = scopeWhose == true
        local own, everyone = GetMoney(), ns.Characters.TotalMoney()
        local money = accountWide and everyone or ns.Characters.MoneyOf(scopeWhose)
        local playing = UnitName("player") or "this one"

        have.Figure:SetText(Theme.Coins(money))
        if Theme.MoneyIsSomeoneElse() then
            have.Note:SetText(
                ("%s had this when last played; %s on %s"):format(
                    Theme.MoneyOwner(),
                    ns.Money(own),
                    playing
                )
            )
        elseif accountWide then
            have.Note:SetText(("across your characters, %s on %s"):format(ns.Money(own), playing))
        elseif everyone > own then
            have.Note:SetText(
                ("on %s, %s across your characters"):format(playing, ns.Money(everyone))
            )
        else
            have.Note:SetText(("on %s"):format(playing))
        end
        return money
    end

    -- The goal as a bar, and how many days of play it is at the rate the
    -- first section is about: the same whose, over the same days, or the
    -- last week for a session, which is too short to make a day's rate of.
    local function RefreshGoal(period, scopeWhose, money)
        local goal = ns.settings.goalCopper
        local hasGoal = goal and goal > 0
        goalBar:SetShown(hasGoal)
        goalEta:SetShown(hasGoal)
        goalNote:SetShown(hasGoal)

        if not hasGoal then
            goalLabel:SetText("Saving for something?")
            goalEta:SetText("")
            goalNote:SetShown(true)
            goalNote:ClearAllPoints()
            goalNote:SetPoint("TOPLEFT", goalLabel, "BOTTOMLEFT", 0, -8)
            goalNote:SetText("Type /gw goal 50 to track a 50 gold target here.")
            return
        end

        goalNote:ClearAllPoints()
        goalNote:SetPoint("TOPLEFT", goalBar, "BOTTOMLEFT", 0, -5)

        local whoseGoal = scopeWhose == true and " across your characters" or ""
        goalLabel:SetText(("Saving toward %s%s"):format(Theme.Coins(goal), whoseGoal))
        goalBar:SetValue(math.min(1, money / goal))
        goalNote:SetText(
            ("%d%% of the way, %s to go"):format(
                math.min(100, Percent(money / goal)),
                Theme.Coins(math.max(0, goal - money))
            )
        )

        local income, spending = ns.Purse.Averages(period.days or VERDICT_DAYS, scopeWhose)
        local net = income - spending
        if money >= goal then
            goalEta:SetText("You've reached it.")
        elseif net > 0 then
            local days = math.ceil((goal - money) / net)
            goalEta:SetText(
                ("About %d %s of play at this rate"):format(days, days == 1 and "day" or "days")
            )
        else
            goalEta:SetText("Not getting any closer at this rate")
        end
    end

    local function RefreshAfford(period, scopeWhose)
        local money = RefreshPurse(scopeWhose)
        RefreshGoal(period, scopeWhose, money)

        local y = SECTION_GAP + 28 + have:GetHeight() + 18
        Place(comingCaption, afford, 2, y)
        y = y + 14

        local costs = UpcomingCosts(UnitLevel("player"))
        for index, cost in ipairs(costs) do
            local row = comingRows[index] or CreateComingRow(afford)
            comingRows[index] = row
            Place(row, afford, 0, y + (index - 1) * COMING_ROW_HEIGHT)
            row.When:SetText(cost.when)
            row.What:SetText(cost.what)
            row.Amount:SetText(cost.amount and Theme.Coins(cost.amount) or "")

            row.amount = cost.amount
            row.showMore = cost.showMore
            row:EnableMouse(cost.showMore ~= nil)

            row.pickPlace = cost.pickPlace
            row.Where:SetShown(cost.pickPlace ~= nil)
            row:Show()
        end
        for index = #costs + 1, #comingRows do
            comingRows[index]:Hide()
        end
        y = y + #costs * COMING_ROW_HEIGHT + 12

        -- The costs are this character's own, so the verdict is too,
        -- whichever money the tab is showing: an alt's gold can't pay for
        -- training here until it's been sent over.
        local income, spending = ns.Purse.Averages(VERDICT_DAYS)
        verdict:SetText(Verdict(GetMoney(), income, spending, costs))
        Place(verdict, afford, 2, y)
        y = y + Height(verdict)

        afford:SetHeight(y + 12)
    end

    --- Brings every figure on the tab up to date.
    ---@return string footer  a line about what's on show, for the window
    function tab:Refresh()
        whose:Update()
        local period = ChosenPeriod()
        local scopeWhose = Theme.MoneyWhose()
        local session = SessionFor(scopeWhose)

        for index, button in ipairs(periodButtons) do
            if PERIODS[index] == period then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
        end

        -- How long a session has run is known; how long anyone played over
        -- days isn't, so that's left unsaid.
        played:SetShown(not period.days and session ~= nil)
        if session then
            played:SetText(PlayedText(session.seconds))
        end

        RefreshMaking(period, scopeWhose, session)
        RefreshWorth(period, scopeWhose, session)
        RefreshAfford(period, scopeWhose)

        -- The scroll range comes from the page's height, which has to be
        -- set by hand.
        page:SetHeight(
            making:GetHeight() + worth:GetHeight() + afford:GetHeight() + 2 * SECTION_GAP
        )
        return FOOTERS[view]
    end

    return tab
end
