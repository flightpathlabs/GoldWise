local _, ns = ...

-- Prices on item tooltips.
--
-- Two things, each with its own switches in the options:
--
--   * One line, under Goldwise's name, giving the verdict on something
--     the player carries and its auction price. Tooltips are crowded, so
--     one line is all it takes, and the price is left off when another
--     addon is already showing one for that item.
--
--   * A small price chart tucked under the tooltip, once the item has
--     enough history to draw. It hangs outside the tooltip rather than
--     adding to it, so it can't disturb what other addons put there.
--
-- Everything put on a tooltip says it's from Goldwise. A tooltip can
-- carry lines from half a dozen addons, and nobody should have to guess
-- which are whose.

local Theme = ns.Theme

-- The name our lines go under.
local OURS = "Goldwise"

-- Days of history an item needs before the chart is worth showing. Two
-- make a line.
local MIN_DAYS_FOR_CHART = 2

local CHART_WIDTH, CHART_HEIGHT = 220, 66
local PADDING = 8

-- Extra height for the line crediting the feed, when the chart needs one.
local CREDIT_HEIGHT = 13

-- Short enough for a tooltip. The full name is on the item's own page.
local FEED_CREDIT = "Blizzard API"

-- Looking up -------------------------------------------------------------------

-- A tooltip is rebuilt several times a second while the mouse rests on an
-- item, so remember the answer for the last item asked about.
local cache = {}

local function Lookup(itemID)
    local marketKey = ns.Market.Current()
    if cache.itemID ~= itemID or cache.marketKey ~= marketKey then
        cache.itemID = itemID
        cache.marketKey = marketKey
        cache.price, cache.listed, cache.seenAt, cache.source = ns.Ledger.Price(marketKey, itemID)
        cache.history = ns.Ledger.History(marketKey, itemID, ns.Stats.USUAL_DAYS)

        -- Whether any day on the chart is one the feed supplied.
        cache.chartUsesFeed = false
        for _, day in ipairs(cache.history) do
            cache.chartUsesFeed = cache.chartUsesFeed or day.fromFeed == true
        end

        -- The verdict, for something in the player's own bags that could
        -- be sold. It's the same one the Assets list gives, from the same
        -- place, so the two can't disagree.
        local holding = ns.Bags.Holding(itemID)
        local asset = holding and ns.Assets.Describe(holding, marketKey)
        cache.verb = asset and asset.advice.verb or nil
    end
    return cache
end

local function ForgetLookup()
    cache.itemID = nil
end

-- The price, what's carried and what's being kept all change the answer.
ns.Subscribe("PRICES_CHANGED", ForgetLookup)
ns.Subscribe("BAGS_CHANGED", ForgetLookup)
ns.Subscribe("SETTINGS_CHANGED", ForgetLookup)

-- The item the player last pointed at, so a key press or "/gw history"
-- can open its full price history. Kept after the tooltip goes, since the
-- mouse has usually wandered by the time a command is typed.
local pointedAt = {}

--- The item the player last had a tooltip up for.
---@return number|nil itemID
---@return string|nil link
function ns.PointedAtItem()
    return pointedAt.itemID, pointedAt.link
end

-- The chart under the tooltip -------------------------------------------------------

local panel

local function CreatePanel()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(CHART_WIDTH, CHART_HEIGHT)
    frame:SetFrameStrata("TOOLTIP")
    frame:Hide()

    -- Dark, like the tooltip it hangs under, with a hairline edge so it
    -- reads as a panel of its own. It floats over the game world, so
    -- unlike the charts in the window it has to be solid.
    local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetAllPoints()
    edge:SetColorTexture(Theme.MUTED[1], Theme.MUTED[2], Theme.MUTED[3], 0.45)

    local page = frame:CreateTexture(nil, "BACKGROUND")
    page:SetPoint("TOPLEFT", 1, -1)
    page:SetPoint("BOTTOMRIGHT", -1, 1)
    page:SetColorTexture(unpack(Theme.CHART_FLOATING))

    frame.Caption = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Caption:SetPoint("TOPLEFT", PADDING, -6)
    frame.Caption:SetTextColor(unpack(Theme.MUTED))

    -- Hung from the top, so the credit line can be added underneath
    -- without moving it.
    frame.Trend = ns.Chart.CreateSparkline(frame, CHART_WIDTH - 2 * PADDING, CHART_HEIGHT - 30)
    frame.Trend:SetPoint("TOPLEFT", PADDING, -23)

    frame.Credit = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Credit:SetPoint("BOTTOMLEFT", PADDING, 6)
    frame.Credit:SetTextColor(unpack(Theme.MUTED))
    frame.Credit:SetText("Includes prices from the " .. FEED_CREDIT)

    return frame
end

-- Counts up each time the chart is asked for or sent away, so a step
-- that was put off by a frame can tell whether it has been overtaken.
local generation = 0

local function ShowChart(tooltip, history, usesFeed)
    -- A tooltip with no owner is being filled but won't be shown, so it
    -- would never tell us to take the chart away again.
    if not tooltip:GetOwner() then
        return
    end

    panel = panel or CreatePanel()

    local values = {}
    for index, day in ipairs(history) do
        values[index] = day.last
    end

    local low, high = ns.Stats.Range(history)
    panel.Caption:SetText(
        ("%s, %d days: %s to %s"):format(OURS, #history, ns.Money(low), ns.Money(high))
    )
    panel.Trend:SetValues(values, Theme.CHART_LINE)

    -- Blizzard's terms ask that its data is credited where it's shown.
    local height = CHART_HEIGHT + (usesFeed and CREDIT_HEIGHT or 0)
    panel.Credit:SetShown(usesFeed)
    panel:SetHeight(height)

    -- We're called while the tooltip is still being built, before it has
    -- its final size and place. Wait a frame for that to settle, then put
    -- the chart below it if there's room and above it if there isn't.
    generation = generation + 1
    local thisOne = generation
    C_Timer.After(0, function()
        -- Overtaken by a newer request, or by the tooltip going away.
        if generation ~= thisOne or not tooltip:IsShown() then
            return
        end

        panel:ClearAllPoints()
        if (tooltip:GetBottom() or 0) > height + 8 then
            panel:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)
        else
            panel:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", 0, 2)
        end
        panel:Show()
    end)
end

-- The tooltip has gone, and the chart goes with it at once.
local function HideChart()
    generation = generation + 1
    if panel then
        panel:Hide()
    end
end

-- The tooltip has been emptied. That happens when it's about to show
-- something else, but also several times a second while it rests on one
-- item and the game rebuilds it. Hiding the chart on the spot would make
-- it blink on every rebuild, so wait a frame. If the chart has been asked
-- for again by then, as it will have been for the same item, leave it be.
local function HideChartSoon()
    generation = generation + 1
    local thisOne = generation
    C_Timer.After(0, function()
        if generation == thisOne and panel then
            panel:Hide()
        end
    end)
end

GameTooltip:HookScript("OnHide", HideChart)
GameTooltip:HookScript("OnTooltipCleared", HideChartSoon)

-- Who holds it ------------------------------------------------------------------------

-- Names listed before the rest are summed up as "and N more".
local MAX_HOLDERS_NAMED = 3

-- "55: 12 here, Alia 40, Brom 3", or nil when no other character has any.
-- With nobody else holding it there's nothing the bag itself doesn't show.
local function HeldText(itemID)
    local holders = ns.Characters.HoldersOf(itemID)
    if #holders == 0 then
        return nil
    end

    local here = ns.Bags.Counts()[itemID] or 0
    local total = here
    local parts = {}

    if here > 0 then
        table.insert(parts, here .. " here")
    end

    for index, holder in ipairs(holders) do
        total = total + holder.count
        if index <= MAX_HOLDERS_NAMED then
            table.insert(parts, ("%s %d"):format(holder.name, holder.count))
        end
    end

    if #holders > MAX_HOLDERS_NAMED then
        table.insert(parts, ("and %d more"):format(#holders - MAX_HOLDERS_NAMED))
    end

    return ("%d: %s"):format(total, table.concat(parts, ", "))
end

-- The price line ----------------------------------------------------------------------

-- A price or a list of holders that another addon is already showing would
-- only be clutter coming from us as well. Companions.lua knows who shows
-- what. The chart is ours alone, so it's never held back.

local function OnItemTooltip(tooltip, data)
    -- Saved data loads a moment after the first tooltips can appear.
    local settings = ns.settings
    if not settings then
        return
    end

    -- Comparison tooltips and other addons' private tooltips also come
    -- through here. Stick to the two the player actually reads.
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
        return
    end

    -- In restricted content the client can hand over an ID we aren't
    -- allowed to look at. Nothing to do with one of those.
    local itemID = data and data.id
    if not itemID or (issecretvalue and issecretvalue(itemID)) then
        return
    end

    -- The link says which exact item it is (its suffix or level, for
    -- gear). The ID alone will do if the tooltip won't say.
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    pointedAt.itemID, pointedAt.link = itemID, link

    local coin = Theme.COIN
    local found = Lookup(itemID)

    -- Our line: the verdict, the price, or both. The verdict is only for
    -- what the player carries and only once there's a price to judge by;
    -- "no price" is said by the line not being there.
    local verdict = settings.tooltipVerdict and found.verb
    if verdict == ns.Advice.UNKNOWN then
        verdict = nil
    end

    local showPrice = found.price
        and settings.tooltipPrice
        and not ns.Companions.ShowsTooltipPrices(itemID)

    if verdict or showPrice then
        local parts = {}
        if verdict then
            table.insert(parts, Theme.Tint(Theme.VERB_LABELS[verdict], Theme.VERB_COLORS[verdict]))
        end
        if showPrice then
            table.insert(
                parts,
                ("%s  (%s)"):format(Theme.Coins(found.price), Theme.Listed(found.listed))
            )
        end

        local fromFeed = showPrice and found.source == ns.Ledger.FEED
        tooltip:AddDoubleLine(
            fromFeed and ("%s (%s)"):format(OURS, FEED_CREDIT) or OURS,
            table.concat(parts, "  "),
            coin[1],
            coin[2],
            coin[3],
            1,
            1,
            1
        )
    end

    if settings.tooltipHeld and not ns.Companions.ShowsHoldings() then
        local text = HeldText(itemID)
        if text then
            tooltip:AddDoubleLine(OURS .. ", held", text, coin[1], coin[2], coin[3], 1, 1, 1)
        end
    end

    -- One quiet line on things the player can make, or make something
    -- from: there's nothing else to say the tree is there.
    local treeClick = settings.tooltipTree and ns.Shortcuts.TreeClickHint()
    if treeClick and ns.CraftTree.Has(itemID) then
        local muted = Theme.MUTED
        tooltip:AddLine(
            ("%s: %s for its crafting tree"):format(OURS, treeClick),
            muted[1],
            muted[2],
            muted[3]
        )
    end

    if settings.tooltipChart and tooltip == GameTooltip then
        if #found.history >= MIN_DAYS_FOR_CHART then
            ShowChart(tooltip, found.history, found.chartUsesFeed)
        end
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
