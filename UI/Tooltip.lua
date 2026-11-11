local _, ns = ...

-- Prices on item tooltips.
--
-- Two things, each with its own switch in the options:
--
--   * One line giving the auction price. Tooltips are crowded, so one line
--     is all we take, and if Auctionator is installed we leave pricing to
--     it rather than say the same thing twice.
--
--   * A small price chart tucked under the tooltip, once the item has
--     enough history to draw. It hangs outside the tooltip rather than
--     adding to it, so it can't disturb what other addons put there.

local Theme = ns.Theme

-- Days of history an item needs before the chart is worth showing.
local MIN_DAYS_FOR_CHART = 3

local CHART_WIDTH, CHART_HEIGHT = 220, 66
local PADDING = 8

-- Looking up -------------------------------------------------------------------

-- A tooltip is rebuilt several times a second while the mouse rests on an
-- item, so remember the answer for the last item asked about.
local cache = {}

local function Lookup(itemID)
    local marketKey = ns.Market.Current()
    if cache.itemID ~= itemID or cache.marketKey ~= marketKey then
        cache.itemID = itemID
        cache.marketKey = marketKey
        cache.price, cache.listed = ns.Ledger.Price(marketKey, itemID)
        cache.history = ns.Ledger.History(marketKey, itemID, ns.Stats.USUAL_DAYS)
    end
    return cache
end

ns.Subscribe("PRICES_CHANGED", function()
    cache.itemID = nil
end)

-- The chart under the tooltip -------------------------------------------------------

local panel

local function CreatePanel()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(CHART_WIDTH, CHART_HEIGHT)
    frame:SetFrameStrata("TOOLTIP")
    frame:Hide()

    local page = frame:CreateTexture(nil, "BACKGROUND")
    page:SetAllPoints()
    page:SetColorTexture(unpack(Theme.PARCHMENT))

    frame.Caption = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Caption:SetPoint("TOPLEFT", PADDING, -6)
    frame.Caption:SetTextColor(unpack(Theme.FADED_INK))
    -- The stock fonts carry a dark shadow, which smears on a light page.
    frame.Caption:SetShadowOffset(0, 0)

    frame.Trend = ns.Chart.CreateSparkline(frame, CHART_WIDTH - 2 * PADDING, CHART_HEIGHT - 30)
    frame.Trend:SetPoint("BOTTOMLEFT", PADDING, 7)

    return frame
end

local function ShowChart(tooltip, history)
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
    panel.Caption:SetText(("%d days: %s to %s"):format(#history, ns.Money(low), ns.Money(high)))
    panel.Trend:SetValues(values, Theme.INK)

    -- We're called while the tooltip is still being built, before it has
    -- its final size and place. Wait a frame for that to settle, then put
    -- the chart below it if there's room and above it if there isn't.
    C_Timer.After(0, function()
        if not tooltip:IsShown() then
            return
        end

        panel:ClearAllPoints()
        if (tooltip:GetBottom() or 0) > CHART_HEIGHT + 8 then
            panel:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)
        else
            panel:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", 0, 2)
        end
        panel:Show()
    end)
end

local function HideChart()
    if panel then
        panel:Hide()
    end
end

-- Whenever the tooltip empties or goes away, the chart goes with it. If the
-- next thing shown is an item with history, it comes straight back.
GameTooltip:HookScript("OnHide", HideChart)
GameTooltip:HookScript("OnTooltipCleared", HideChart)

-- Who holds it ------------------------------------------------------------------------

-- Names listed before the rest are summed up as "and N more".
local MAX_HOLDERS_NAMED = 3

-- "55: 12 here, Buffy 40, Bjorn 3", or nil when no other character has any.
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

    local coin = Theme.COIN
    local found = Lookup(itemID)

    if found.price and settings.tooltipPrice and not C_AddOns.IsAddOnLoaded("Auctionator") then
        tooltip:AddDoubleLine(
            "Auction",
            ("%s  (%s)"):format(Theme.Coins(found.price), Theme.Listed(found.listed)),
            coin[1],
            coin[2],
            coin[3],
            1,
            1,
            1
        )
    end

    -- Bagnon already lists who holds what, bank and mail included, so
    -- leave this to it when it's there.
    if settings.tooltipHeld and not C_AddOns.IsAddOnLoaded("Bagnon") then
        local text = HeldText(itemID)
        if text then
            tooltip:AddDoubleLine("Held", text, coin[1], coin[2], coin[3], 1, 1, 1)
        end
    end

    if settings.tooltipChart and tooltip == GameTooltip then
        if #found.history >= MIN_DAYS_FOR_CHART then
            ShowChart(tooltip, found.history)
        end
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
