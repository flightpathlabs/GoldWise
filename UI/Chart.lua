local _, ns = ...

-- Charts, drawn with the client's own lines and textures.
--
-- Three kinds: a sparkline small enough to sit in a list row, a price
-- chart on a parchment background with labelled axes, and a cash flow
-- chart of money in and out by day. All are meant to look like something
-- inked into a ledger: dark strokes on a light page, nothing glossy.

local Chart = {}
ns.Chart = Chart

local Theme = ns.Theme

-- Line pooling ---------------------------------------------------------------

-- Lines can't be destroyed, only hidden, so each chart keeps the ones it
-- has made and reuses them on the next draw.

local function ReleaseLines(chart)
    for _, line in ipairs(chart.lines) do
        line:Hide()
    end
    chart.linesUsed = 0
end

local function DrawLine(chart, x1, y1, x2, y2, thickness, color, alpha)
    chart.linesUsed = chart.linesUsed + 1

    local line = chart.lines[chart.linesUsed]
    if not line then
        line = chart:CreateLine(nil, "ARTWORK")
        chart.lines[chart.linesUsed] = line
    end

    line:SetThickness(thickness)
    line:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    line:SetStartPoint("BOTTOMLEFT", chart, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", chart, x2, y2)
    line:Show()
end

-- Joins a list of { x, y } points with straight segments.
local function DrawPath(chart, points, thickness, color)
    for index = 2, #points do
        local from, to = points[index - 1], points[index]
        DrawLine(chart, from[1], from[2], to[1], to[2], thickness, color)
    end
end

-- Sparkline --------------------------------------------------------------------

--- Creates a small unlabelled trend line.
---@param parent table  frame
---@param width number
---@param height number
---@return table sparkline  with :SetValues(values, color)
function Chart.CreateSparkline(parent, width, height)
    local sparkline = CreateFrame("Frame", nil, parent)
    sparkline:SetSize(width, height)
    sparkline.lines = {}
    sparkline.linesUsed = 0

    --- Draws the given numbers left to right. Fewer than two draws nothing.
    function sparkline:SetValues(values, color)
        ReleaseLines(self)
        if #values < 2 then
            return
        end

        local low, high = math.huge, -math.huge
        for _, value in ipairs(values) do
            low = math.min(low, value)
            high = math.max(high, value)
        end

        -- A price that never moved is a flat line through the middle.
        local span = high - low
        local step = width / (#values - 1)
        local points = {}
        for index, value in ipairs(values) do
            local level = span > 0 and (value - low) / span or 0.5
            -- Keep a pixel clear top and bottom so the stroke isn't clipped.
            points[index] = { (index - 1) * step, 1 + level * (height - 2) }
        end

        DrawPath(self, points, 1.5, color)
    end

    return sparkline
end

-- Full chart ---------------------------------------------------------------------

-- Space around the plotted area for labels. The left margin has to hold a
-- price as wide as "12g 34s 56c".
local MARGIN_LEFT = 72
local MARGIN_RIGHT = 14
local MARGIN_TOP = 14
local MARGIN_BOTTOM = 22

local function CreateLabel(chart, justify)
    local label = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetTextColor(unpack(Theme.FADED_INK))
    -- The stock fonts carry a dark shadow, which smears on a light page.
    label:SetShadowOffset(0, 0)
    label:SetJustifyH(justify)
    return label
end

local function DayLabel(day)
    -- Days are counted in UTC, so format in UTC too (the "!"). Otherwise
    -- anyone west of Greenwich sees every label a day early.
    return date("!%d %b", day * ns.SECONDS_PER_DAY)
end

--- Creates a price chart on a parchment background.
---@param parent table  frame
---@param width number
---@param height number
---@return table chart  with :SetHistory(history, usual)
function Chart.Create(parent, width, height)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(width, height)
    chart.lines = {}
    chart.linesUsed = 0

    local page = chart:CreateTexture(nil, "BACKGROUND")
    page:SetAllPoints()
    page:SetColorTexture(unpack(Theme.PARCHMENT))

    local plotWidth = width - MARGIN_LEFT - MARGIN_RIGHT
    local plotHeight = height - MARGIN_TOP - MARGIN_BOTTOM

    local highLabel = CreateLabel(chart, "RIGHT")
    highLabel:SetPoint("TOPRIGHT", chart, "TOPLEFT", MARGIN_LEFT - 6, -MARGIN_TOP + 5)

    local lowLabel = CreateLabel(chart, "RIGHT")
    lowLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", MARGIN_LEFT - 6, MARGIN_BOTTOM - 5)

    local firstDayLabel = CreateLabel(chart, "LEFT")
    firstDayLabel:SetPoint("BOTTOMLEFT", MARGIN_LEFT, 5)

    local lastDayLabel = CreateLabel(chart, "RIGHT")
    lastDayLabel:SetPoint("BOTTOMRIGHT", -MARGIN_RIGHT, 5)

    local usualLabel = CreateLabel(chart, "LEFT")
    usualLabel:SetTextColor(unpack(Theme.RUST))

    local emptyLabel = CreateLabel(chart, "CENTER")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:SetWidth(width - 60)

    -- Marks the newest price.
    local dot = chart:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    dot:SetColorTexture(unpack(Theme.OXBLOOD))

    local function ShowEmpty(message)
        highLabel:SetText("")
        lowLabel:SetText("")
        firstDayLabel:SetText("")
        lastDayLabel:SetText("")
        usualLabel:Hide()
        dot:Hide()
        emptyLabel:SetText(message)
        emptyLabel:Show()
    end

    --- Draws a price history.
    ---@param history table       from Ledger.History, oldest first
    ---@param usual number|nil    from Stats.UsualPrice, drawn as a level line
    function chart:SetHistory(history, usual)
        ReleaseLines(self)

        if #history == 0 then
            ShowEmpty("No prices recorded yet. Visit an auction house to start the ledger.")
            return
        elseif #history == 1 then
            ShowEmpty("One day of prices so far. The line starts tomorrow.")
            return
        end
        emptyLabel:Hide()

        local low, high = ns.Stats.Range(history)
        if usual then
            low, high = math.min(low, usual), math.max(high, usual)
        end

        -- Leave some air above and below, and cope with a price that
        -- never changed.
        local padding = math.max((high - low) * 0.1, 1)
        low, high = math.max(low - padding, 0), high + padding

        local firstDay, lastDay = history[1].day, history[#history].day
        local function Place(day, price)
            local x = MARGIN_LEFT + (day - firstDay) / (lastDay - firstDay) * plotWidth
            local y = MARGIN_BOTTOM + (price - low) / (high - low) * plotHeight
            return x, y
        end

        -- Frame the plot with a baseline and a faint top rule.
        local left, right = MARGIN_LEFT, MARGIN_LEFT + plotWidth
        local bottom, top = MARGIN_BOTTOM, MARGIN_BOTTOM + plotHeight
        DrawLine(self, left, bottom, right, bottom, 1, Theme.FADED_INK)
        DrawLine(self, left, top, right, top, 1, Theme.FADED_INK, 0.3)

        if usual then
            local _, y = Place(firstDay, usual)
            DrawLine(self, left, y, right, y, 1, Theme.RUST, 0.8)
            usualLabel:ClearAllPoints()
            usualLabel:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", left + 4, y + 2)
            usualLabel:SetText("usual " .. ns.Money(usual))
            usualLabel:Show()
        else
            usualLabel:Hide()
        end

        local points = {}
        for index, day in ipairs(history) do
            points[index] = { Place(day.day, day.last) }
        end
        DrawPath(self, points, 2, Theme.INK)

        local newest = points[#points]
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", self, "BOTTOMLEFT", newest[1], newest[2])
        dot:Show()

        highLabel:SetText(ns.Money(high))
        lowLabel:SetText(ns.Money(low))
        firstDayLabel:SetText(DayLabel(firstDay))
        lastDayLabel:SetText(DayLabel(lastDay))
    end

    return chart
end

-- Cash flow ----------------------------------------------------------------------

-- Ink for money coming in and money going out. They differ in lightness
-- as well as hue, and sit on opposite sides of a line, so nothing depends
-- on telling red from green.
local INCOME_INK = { 0.22, 0.42, 0.18 }
local SPENDING_INK = Theme.OXBLOOD

-- Space left between one day's bar and the next.
local BAR_GAP = 4

-- Bars can't be destroyed any more than lines can, so they're pooled the
-- same way.
local function ReleaseBars(chart)
    for _, bar in ipairs(chart.bars) do
        bar:Hide()
    end
    chart.barsUsed = 0
end

local function DrawBar(chart, x, y, width, height, color)
    chart.barsUsed = chart.barsUsed + 1

    local bar = chart.bars[chart.barsUsed]
    if not bar then
        bar = chart:CreateTexture(nil, "ARTWORK")
        chart.bars[chart.barsUsed] = bar
    end

    bar:SetColorTexture(color[1], color[2], color[3], 0.9)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", x, y)
    bar:SetSize(width, height)
    bar:Show()
end

--- Creates a chart of money in and out, a bar a day: income above a line
--- across the middle, spending below it.
---@param parent table  frame
---@param width number
---@param height number
---@return table chart  with :SetDays(days, firstDay, lastDay)
function Chart.CreateCashFlow(parent, width, height)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(width, height)
    chart.lines, chart.linesUsed = {}, 0
    chart.bars, chart.barsUsed = {}, 0

    local page = chart:CreateTexture(nil, "BACKGROUND")
    page:SetAllPoints()
    page:SetColorTexture(unpack(Theme.PARCHMENT))

    local plotWidth = width - MARGIN_LEFT - MARGIN_RIGHT
    local plotHeight = height - MARGIN_TOP - MARGIN_BOTTOM

    -- The line that income rises from and spending hangs below.
    local middle = MARGIN_BOTTOM + plotHeight / 2
    local reach = plotHeight / 2 - 1

    local incomeLabel = CreateLabel(chart, "RIGHT")
    incomeLabel:SetPoint("TOPRIGHT", chart, "TOPLEFT", MARGIN_LEFT - 6, -MARGIN_TOP + 5)
    incomeLabel:SetTextColor(unpack(INCOME_INK))

    local spendingLabel = CreateLabel(chart, "RIGHT")
    spendingLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", MARGIN_LEFT - 6, MARGIN_BOTTOM - 5)
    spendingLabel:SetTextColor(unpack(SPENDING_INK))

    local firstDayLabel = CreateLabel(chart, "LEFT")
    firstDayLabel:SetPoint("BOTTOMLEFT", MARGIN_LEFT, 5)

    local lastDayLabel = CreateLabel(chart, "RIGHT")
    lastDayLabel:SetPoint("BOTTOMRIGHT", -MARGIN_RIGHT, 5)

    -- Which side is which, for the first time anyone looks at it.
    -- Centred under the plot, which sits right of centre on the page.
    local key = CreateLabel(chart, "CENTER")
    key:SetPoint("BOTTOM", MARGIN_LEFT + plotWidth / 2 - width / 2, 5)
    key:SetText("coming in above the line, going out below")

    local emptyLabel = CreateLabel(chart, "CENTER")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:SetWidth(width - 60)

    --- Draws the days given.
    ---@param days table      list of { day, income, spending }, in copper
    ---@param firstDay number the first day the chart covers
    ---@param lastDay number  the last, normally today
    function chart:SetDays(days, firstDay, lastDay)
        ReleaseLines(self)
        ReleaseBars(self)

        -- Both sides are drawn to one scale, so a tall bar means the same
        -- money whichever way it points.
        local peak = 0
        for _, day in ipairs(days) do
            peak = math.max(peak, day.income, day.spending)
        end

        if peak == 0 then
            incomeLabel:SetText("")
            spendingLabel:SetText("")
            firstDayLabel:SetText("")
            lastDayLabel:SetText("")
            key:Hide()
            emptyLabel:SetText(
                "Nothing earned or spent on record yet. It starts with your next coin."
            )
            emptyLabel:Show()
            return
        end
        emptyLabel:Hide()
        key:Show()

        local slot = plotWidth / (lastDay - firstDay + 1)
        local barWidth = math.max(slot - BAR_GAP, 2)

        for _, day in ipairs(days) do
            local x = MARGIN_LEFT + (day.day - firstDay) * slot + (slot - barWidth) / 2

            -- Anything at all gets at least a sliver, so a small day isn't
            -- mistaken for a day not played.
            if day.income > 0 then
                local rise = math.max(day.income / peak * reach, 1)
                DrawBar(self, x, middle, barWidth, rise, INCOME_INK)
            end
            if day.spending > 0 then
                local drop = math.max(day.spending / peak * reach, 1)
                DrawBar(self, x, middle - drop, barWidth, drop, SPENDING_INK)
            end
        end

        DrawLine(self, MARGIN_LEFT, middle, MARGIN_LEFT + plotWidth, middle, 1, Theme.FADED_INK)

        incomeLabel:SetText(ns.Money(peak))
        spendingLabel:SetText(ns.Money(peak))
        firstDayLabel:SetText(DayLabel(firstDay))
        lastDayLabel:SetText(DayLabel(lastDay))
    end

    return chart
end
