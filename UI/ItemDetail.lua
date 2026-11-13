local _, ns = ...

-- The page for one item: its price for as far back as history is kept,
-- and what that means in a sentence or two.

local ItemDetail = {}
ns.ItemDetail = ItemDetail

local Theme = ns.Theme

local CHART_WIDTH = 740
local CHART_HEIGHT = 250

-- The crafting tree button, and the room an item's name has beside it
-- before it would run under the buttons at the top right.
local TREE_BUTTON_WIDTH = 110
local NAME_WIDTH = 300

-- A stack this size or bigger is worth a word when it's more than the
-- whole market has on offer.
local SIZEABLE_STACK = 5

-- What the chart can draw, in the order the menu lists them. By day is
-- the long view: one point a day for as long as history is kept. The
-- others plot every separate reading, which is where a price that swings
-- between morning and evening shows itself.
local VIEWS = {
    { label = "A point a day" },
    { label = "Every reading, last week", readingDays = 7 },
    { label = "Every reading, last 2 days", readingDays = 2 },
}

--- Creates the detail page. It starts hidden and fills its parent.
---@param parent table        frame to fill
---@param onBack fun()        called when the player presses Back
---@return table detail       with :ShowItem(row)
function ItemDetail.Create(parent, onBack)
    local detail = CreateFrame("Frame", nil, parent)
    detail:SetAllPoints()
    detail:Hide()

    local back = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    back:SetSize(70, 22)
    back:SetPoint("TOPLEFT", 12, -12)
    back:SetText("Back")
    back:SetScript("OnClick", onBack)

    -- The item on show.
    local shown

    -- The chart's view, in the corner, where it stays put. The crafting
    -- tree button comes and goes, so it's the one that sits beside.
    local pick = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    pick:SetSize(180, 22)
    pick:SetPoint("TOPRIGHT", -14, -12)

    -- Only there for an item that's part of something the player can
    -- make. For anything else the tree would have nothing in it.
    local tree = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    tree:SetSize(TREE_BUTTON_WIDTH, 22)
    tree:SetPoint("RIGHT", pick, "LEFT", -8, 0)
    tree:SetText("Crafting tree")
    tree:SetScript("OnClick", function()
        ns.ShowCraftTree(shown)
    end)

    local icon = detail:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", back, "TOPRIGHT", 14, 4)

    -- A long name stops short of the buttons. Its width is set outright
    -- each time an item is shown: pinning its right-hand edge to a button
    -- would drag it down to the button's height as well.
    local name = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    local facts = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    facts:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    facts:SetTextColor(unpack(Theme.MUTED))

    local chart = ns.Chart.Create(detail, CHART_WIDTH, CHART_HEIGHT)
    chart:SetPoint("TOPLEFT", 14, -62)

    -- Draws the chart for the item on show, the way the player last chose.
    local function DrawChart()
        local marketKey = ns.Market.Current()
        local view = VIEWS[ns.settings.historyView] or VIEWS[1]
        pick:SetText(view.label)

        -- "Usual" is worked out over the same shorter window the list
        -- used, so the line drawn here agrees with the sentence beneath
        -- it, whichever view is on show.
        local usual = ns.Stats.UsualPrice(ns.Ledger.History(marketKey, shown, ns.Stats.USUAL_DAYS))

        if view.readingDays then
            chart:SetHistory(ns.Ledger.Readings(marketKey, shown, view.readingDays), usual, true)
        else
            chart:SetHistory(ns.Ledger.History(marketKey, shown, ns.settings.historyDays), usual)
        end
    end

    pick:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Chart...")
            for index, view in ipairs(VIEWS) do
                root:CreateRadio(view.label, function()
                    return ns.settings.historyView == index
                end, function()
                    ns.settings.historyView = index
                    DrawChart()
                end)
            end
        end)
    end)

    local verdict = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
    verdict:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 2, -14)
    verdict:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    verdict:SetJustifyH("LEFT")

    local notes = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    notes:SetPoint("TOPLEFT", verdict, "BOTTOMLEFT", 0, -8)
    notes:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    notes:SetJustifyH("LEFT")
    notes:SetSpacing(4)

    --- Fills the page for one row of the shelf list and shows it.
    ---@param row table  as built by ShelfList
    function detail:ShowItem(row)
        local marketKey = ns.Market.Current()
        local history = ns.Ledger.History(marketKey, row.itemID, ns.settings.historyDays)

        shown = row.itemID
        tree:SetShown(ns.CraftTree.Has(row.itemID))

        icon:SetTexture(row.icon)
        name:SetWidth(tree:IsShown() and NAME_WIDTH or NAME_WIDTH + TREE_BUTTON_WIDTH + 8)
        name:SetText(Theme.ItemName(row.name, row.quality))

        local holder = row.owner and (row.owner .. " has") or "You have"
        if row.price then
            facts:SetText(
                ("%s each, %s. %s %d."):format(
                    Theme.Coins(row.price),
                    Theme.Listed(row.listed),
                    holder,
                    row.count
                )
            )
        else
            facts:SetText(("%s %d."):format(holder, row.count))
        end

        DrawChart()
        verdict:SetText(row.advice.reason)

        local lines = {}
        if row.advice.proceeds and row.advice.verb == ns.Advice.SELL then
            table.insert(
                lines,
                ("Selling all %d should bring in about %s after the auction house's cut."):format(
                    row.count,
                    Theme.Coins(row.advice.proceeds)
                )
            )
        end

        -- How far the price can be trusted, and what selling a lot at
        -- once would do to it. Both come from how many are listed.
        local listed = row.listed or 0
        if row.price and listed > 0 and listed < ns.THIN_MARKET then
            table.insert(
                lines,
                ("Only %d listed, so that price is one or two sellers' opinion."):format(listed)
            )
        elseif row.price and listed > 0 and row.count >= SIZEABLE_STACK and row.count > listed then
            table.insert(
                lines,
                ("You have more of these than are listed altogether (%d against %d). "):format(
                    row.count,
                    listed
                ) .. "Put up all at once, they'd likely push the price down."
            )
        end

        -- What they paid, if they bought it at auction, against what it
        -- would clear today.
        local paid, paidAt = ns.Trade.LastPaid(row.itemID)
        if paid then
            local line = ("You last paid %s each for these at auction, %s."):format(
                Theme.Coins(paid),
                ns.Ago(GetServerTime() - paidAt)
            )
            if row.price then
                local clears = row.price * (1 - ns.Market.Cut(marketKey)) - paid
                line = line
                    .. (
                        clears >= 0 and " Sold today, each would clear about %s over that."
                        or " Sold today, each would come in about %s under that."
                    ):format(Theme.Coins(math.abs(clears)))
            end
            table.insert(lines, line)
        end

        local low, high = ns.Stats.Range(history)
        if low and #history > 1 then
            table.insert(
                lines,
                ("Over the last %d days of records it has ranged from %s to %s."):format(
                    #history,
                    Theme.Coins(low),
                    Theme.Coins(high)
                )
            )
        end

        -- From the last deep scan, if there's been one: how much is stacked
        -- up at each of the lowest prices.
        local depth = ns.Ledger.Depth(marketKey, row.itemID)
        if depth and #depth.levels > 0 then
            local levels = {}
            for index, level in ipairs(depth.levels) do
                levels[index] = ("%s at %s"):format(FormatLargeNumber(level[2]), ns.Money(level[1]))
            end

            -- If prices have been read again since by the quicker scan,
            -- say how old this picture is, so it can't seem to contradict
            -- the price above.
            local label = "Cheapest listings"
            if depth.at < (row.seenAt or 0) then
                label = label .. " " .. ns.Ago(GetServerTime() - depth.at)
            end

            local line = label .. ": " .. table.concat(levels, ", ") .. "."
            if depth.higher > 0 then
                line = line .. (" %s more above that."):format(FormatLargeNumber(depth.higher))
            end
            table.insert(lines, line)
        end

        if row.source == ns.Ledger.AUCTIONATOR then
            -- Auctionator only says which day, so that's all this says.
            local days = ns.Ledger.Today() - ns.Ledger.DayOf(row.seenAt)
            local when = days == 0 and "today" or days == 1 and "yesterday" or (days .. " days ago")
            local credit = "Price from Auctionator, which last saw it %s. "
                .. "Goldwise hasn't read it itself yet."
            table.insert(lines, credit:format(when))
        elseif row.seenAt then
            local age = ns.Ago(GetServerTime() - row.seenAt)
            if row.source == ns.Ledger.PLAYERS then
                table.insert(lines, "Price shared by another Goldwise player, read " .. age .. ".")
            else
                table.insert(lines, "Price read " .. age .. ".")
            end
        end

        -- A day on the chart that only Auctionator saw is worth a word, so
        -- the point isn't taken for one of Goldwise's own.
        if row.source ~= ns.Ledger.AUCTIONATOR then
            for _, day in ipairs(history) do
                if day.fromAuctionator then
                    table.insert(lines, "One day on the chart is Auctionator's price.")
                    break
                end
            end
        end

        -- Credit the feed wherever any of what's shown came from it: the
        -- current price, or days on the chart the player wasn't there for.
        local usesFeed = row.source == ns.Ledger.FEED
        for _, day in ipairs(history) do
            usesFeed = usesFeed or day.fromFeed
        end
        if usesFeed then
            table.insert(lines, "Includes prices from " .. ns.Feed.SOURCE .. ".")
        end

        notes:SetText(table.concat(lines, "\n"))
        self:Show()
    end

    return detail
end
