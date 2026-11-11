local _, ns = ...

-- The page for one item: its price over the last month, and what that
-- means in a sentence or two.

local ItemDetail = {}
ns.ItemDetail = ItemDetail

local Theme = ns.Theme

local HISTORY_DAYS = 30
local CHART_WIDTH = 740
local CHART_HEIGHT = 250

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

    local icon = detail:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", back, "TOPRIGHT", 14, 4)

    local name = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)

    local facts = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    facts:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    facts:SetTextColor(unpack(Theme.MUTED))

    local chart = ns.Chart.Create(detail, CHART_WIDTH, CHART_HEIGHT)
    chart:SetPoint("TOPLEFT", 14, -62)

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
        local history = ns.Ledger.History(marketKey, row.itemID, HISTORY_DAYS)

        -- The chart shows a month, but "usual" is worked out over the same
        -- shorter window the list used, so the line drawn here agrees
        -- with the sentence beneath it.
        local usual =
            ns.Stats.UsualPrice(ns.Ledger.History(marketKey, row.itemID, ns.Stats.USUAL_DAYS))

        icon:SetTexture(row.icon)
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

        chart:SetHistory(history, usual)
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

        if row.seenAt then
            table.insert(lines, "Price read " .. ns.Ago(GetServerTime() - row.seenAt) .. ".")
        end

        -- Credit the feed wherever any of what's shown came from it: the
        -- current price, or days on the chart the player wasn't there for.
        local usesFeed = row.fromFeed
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
