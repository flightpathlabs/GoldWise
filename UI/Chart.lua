local _, ns = ...

-- Charts, drawn with the client's own lines and textures.
--
-- Four kinds: a sparkline small enough to sit in a list row, a price
-- chart with labelled axes, a chart of lines around a zero for sums that
-- can be losses, and a cash flow chart of money in and out by day. They
-- are drawn to belong on the game's dark panels: a dark wash behind, thin
-- light strokes on it, nothing glossy. Theme.lua has the colours.

local Chart = {}
ns.Chart = Chart

local Theme = ns.Theme

-- Line pooling ----------------------------------------------------------------

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

-- Sparkline -------------------------------------------------------------------

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

-- Full chart ------------------------------------------------------------------

-- Space around the plotted area for labels. The left margin has to hold a
-- price as wide as "12g 34s 56c".
local MARGIN_LEFT = 72
local MARGIN_RIGHT = 14
local MARGIN_TOP = 14
local MARGIN_BOTTOM = 22

-- The frame every labelled chart starts from: its pool of lines, and the
-- wash behind it.
local function CreateChartFrame(parent, width, height)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(width, height)
    chart.lines = {}
    chart.linesUsed = 0

    local page = chart:CreateTexture(nil, "BACKGROUND")
    page:SetAllPoints()
    page:SetColorTexture(0, 0, 0, Theme.CHART_WASH)

    return chart
end

local function CreateLabel(chart, justify)
    local label = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetTextColor(unpack(Theme.MUTED))
    label:SetJustifyH(justify)
    return label
end

local function DayLabel(day)
    -- A day's number already has the player's time zone worked into it
    -- (see Ledger.Today), so it's written out as it stands (the "!").
    -- Letting the clock shift it a second time would put every label a
    -- day out for half the world.
    return date("!%d %b", day * ns.SECONDS_PER_DAY)
end

-- The same for a moment partway through a day, where the hour matters.
local function HourLabel(day)
    return date("!%d %b, %H:%M", day * ns.SECONDS_PER_DAY)
end

--- How a chart writes a moment under one of its ends.
---@param day number         days as Ledger.Today counts them; 12.5 is
---        noon on day 12
---@param withHour boolean|nil  true where the time of day matters
---@return string  "14 Nov", or "14 Nov, 18:00"
function Chart.Label(day, withHour)
    return withHour and HourLabel(day) or DayLabel(day)
end

--- Creates a price chart with labelled axes.
---@param parent table  frame
---@param width number
---@param height number
---@return table chart  with :SetHistory(history, usual)
function Chart.Create(parent, width, height)
    local chart = CreateChartFrame(parent, width, height)

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
    usualLabel:SetTextColor(unpack(Theme.CHART_USUAL))

    local emptyLabel = CreateLabel(chart, "CENTER")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:SetWidth(width - 60)

    -- Marks the newest price.
    local dot = chart:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    dot:SetColorTexture(unpack(Theme.CHART_NEWEST))

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
    ---@param history table       from Ledger.History or Ledger.Readings,
    ---        oldest first. A day needn't be a whole number: 12.5 is noon
    ---        on day 12, and is drawn halfway along it.
    ---@param usual number|nil    from Stats.UsualPrice, drawn as a level line
    ---@param byReading boolean|nil  true when the history is of single
    ---        readings, where the hour belongs in the labels
    function chart:SetHistory(history, usual, byReading)
        ReleaseLines(self)

        if #history == 0 then
            ShowEmpty(
                byReading
                        and "No readings in this stretch. Each visit to an auction house adds one."
                    or "No prices recorded yet. Visit an auction house to start the ledger."
            )
            return
        elseif #history == 1 or history[#history].day <= history[1].day then
            ShowEmpty(
                byReading and "One reading in this stretch so far. The line starts with the next."
                    or "One day of prices so far. The line starts tomorrow."
            )
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
        DrawLine(self, left, bottom, right, bottom, 1, Theme.MUTED, 0.6)
        DrawLine(self, left, top, right, top, 1, Theme.MUTED, 0.2)

        if usual then
            local _, y = Place(firstDay, usual)
            DrawLine(self, left, y, right, y, 1, Theme.CHART_USUAL, 0.8)
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
        DrawPath(self, points, 2, Theme.CHART_LINE)

        local newest = points[#points]
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", self, "BOTTOMLEFT", newest[1], newest[2])
        dot:Show()

        highLabel:SetText(ns.Money(high))
        lowLabel:SetText(ns.Money(low))
        firstDayLabel:SetText(Chart.Label(firstDay, byReading))
        lastDayLabel:SetText(Chart.Label(lastDay, byReading))
    end

    return chart
end

-- Lines over days -------------------------------------------------------------

-- How many lines one chart can carry. Past two or three, nobody can tell
-- them apart.
local MOST_SERIES = 3

--- Creates a chart of one or more lines across a run of days, for sums
--- that can fall below nothing. A level line marks zero.
---@param parent table  frame
---@param width number
---@param height number
---@return table chart  with :SetSeries(series, firstDay, lastDay, emptyText,
---        look)
function Chart.CreateLines(parent, width, height)
    local chart = CreateChartFrame(parent, width, height)

    local plotWidth = width - MARGIN_LEFT - MARGIN_RIGHT
    local plotHeight = height - MARGIN_TOP - MARGIN_BOTTOM

    local highLabel = CreateLabel(chart, "RIGHT")
    highLabel:SetPoint("TOPRIGHT", chart, "TOPLEFT", MARGIN_LEFT - 6, -MARGIN_TOP + 5)

    local lowLabel = CreateLabel(chart, "RIGHT")
    lowLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", MARGIN_LEFT - 6, MARGIN_BOTTOM - 5)

    local zeroLabel = CreateLabel(chart, "RIGHT")
    zeroLabel:SetText("0")

    local firstDayLabel = CreateLabel(chart, "LEFT")
    firstDayLabel:SetPoint("BOTTOMLEFT", MARGIN_LEFT, 5)

    local lastDayLabel = CreateLabel(chart, "RIGHT")
    lastDayLabel:SetPoint("BOTTOMRIGHT", -MARGIN_RIGHT, 5)

    -- Which line is which, written in each line's own colour along the
    -- bottom edge, between the dates.
    local keys = {}
    for index = 1, MOST_SERIES do
        keys[index] = CreateLabel(chart, "LEFT")
        if index == 1 then
            keys[index]:SetPoint("BOTTOMLEFT", MARGIN_LEFT + 80, 5)
        else
            keys[index]:SetPoint("LEFT", keys[index - 1], "RIGHT", 18, 0)
        end
    end

    local emptyLabel = CreateLabel(chart, "CENTER")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:SetWidth(width - 60)

    --- Draws the lines given.
    ---@param series table       list of { label, color, values }, where
    ---        values has one number for each day from firstDay to lastDay
    ---@param firstDay number
    ---@param lastDay number
    ---@param emptyText string   what to say when every value is nothing
    ---@param look table|nil     for a chart that isn't of days around a
    ---        zero: firstLabel and lastLabel to write under its ends, and
    ---        fitted = true to draw it as tall as its own highs and lows
    ---        allow, where measuring from nothing would flatten it
    function chart:SetSeries(series, firstDay, lastDay, emptyText, look)
        ReleaseLines(self)
        look = look or {}

        local low, high, any = 0, 0, false
        if look.fitted then
            low, high = math.huge, -math.huge
        end
        for _, line in ipairs(series) do
            for _, value in ipairs(line.values) do
                low, high = math.min(low, value), math.max(high, value)
                any = any or value ~= 0
            end
        end

        -- With nothing to plot there's nothing for a key to explain.
        local drawable = any and lastDay > firstDay
        for index, key in ipairs(keys) do
            local line = drawable and series[index] or nil
            key:SetShown(line ~= nil)
            if line then
                key:SetText(line.label)
                key:SetTextColor(unpack(line.color))
            end
        end

        if not drawable then
            highLabel:SetText("")
            lowLabel:SetText("")
            zeroLabel:Hide()
            firstDayLabel:SetText("")
            lastDayLabel:SetText("")
            emptyLabel:SetText(emptyText)
            emptyLabel:Show()
            return
        end
        emptyLabel:Hide()

        -- A little air above and below, so no line runs along the edge.
        local padding = (high - low) * 0.08
        if look.fitted then
            -- A figure that never moved still needs a chart with some
            -- height to it, and a purse can't hold less than nothing.
            padding = math.max(padding, 1)
            low, high = math.max(low - padding, 0), high + padding
        else
            low, high = low - (low < 0 and padding or 0), high + (high > 0 and padding or 0)
        end

        local function Place(day, value)
            local x = MARGIN_LEFT + (day - firstDay) / (lastDay - firstDay) * plotWidth
            local y = MARGIN_BOTTOM + (value - low) / (high - low) * plotHeight
            return x, y
        end

        local left, right = MARGIN_LEFT, MARGIN_LEFT + plotWidth
        local bottom, top = MARGIN_BOTTOM, MARGIN_BOTTOM + plotHeight
        DrawLine(self, left, bottom, right, bottom, 1, Theme.MUTED, 0.2)
        DrawLine(self, left, top, right, top, 1, Theme.MUTED, 0.2)

        -- The line everything is measured from, where it's on the chart
        -- at all.
        local _, zero = Place(firstDay, 0)
        if low <= 0 then
            DrawLine(self, left, zero, right, zero, 1, Theme.MUTED, 0.6)
        end

        -- Drawn last first, so the first line given lies on top.
        for index = #series, 1, -1 do
            local line = series[index]
            local points = {}
            for offset, value in ipairs(line.values) do
                points[offset] = { Place(firstDay + offset - 1, value) }
            end
            DrawPath(self, points, 2, line.color)
        end

        highLabel:SetText(high > 0 and ns.Money(high) or "")
        lowLabel:SetText((low < 0 or look.fitted) and ns.Money(low) or "")

        -- Zero is only worth marking where it isn't the top or bottom of
        -- the chart, and where it wouldn't sit on top of their labels.
        local clear = low < 0 and zero - bottom > 14 and top - zero > 14
        zeroLabel:SetShown(clear)
        if clear then
            zeroLabel:ClearAllPoints()
            zeroLabel:SetPoint("RIGHT", self, "BOTTOMLEFT", MARGIN_LEFT - 6, zero)
        end

        firstDayLabel:SetText(look.firstLabel or DayLabel(firstDay))
        lastDayLabel:SetText(look.lastLabel or DayLabel(lastDay))
    end

    return chart
end

-- Cash flow -------------------------------------------------------------------

-- Money coming in and money going out are drawn in Theme.INCOME and
-- Theme.SPENDING. They differ in lightness as well as hue, and sit on
-- opposite sides of a line, so nothing depends on telling red from green.

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

--- Creates a chart of money in and out, a bar for each stretch of time:
--- income above a line across the middle, spending below it.
---@param parent table  frame
---@param width number
---@param height number
---@return table chart  with :SetBars(bars, first, last, firstLabel, lastLabel,
---        emptyText)
function Chart.CreateCashFlow(parent, width, height)
    local chart = CreateChartFrame(parent, width, height)
    chart.bars, chart.barsUsed = {}, 0

    local plotWidth = width - MARGIN_LEFT - MARGIN_RIGHT
    local plotHeight = height - MARGIN_TOP - MARGIN_BOTTOM

    -- The line that income rises from and spending hangs below.
    local middle = MARGIN_BOTTOM + plotHeight / 2
    local reach = plotHeight / 2 - 1

    local incomeLabel = CreateLabel(chart, "RIGHT")
    incomeLabel:SetPoint("TOPRIGHT", chart, "TOPLEFT", MARGIN_LEFT - 6, -MARGIN_TOP + 5)
    incomeLabel:SetTextColor(unpack(Theme.INCOME))

    local spendingLabel = CreateLabel(chart, "RIGHT")
    spendingLabel:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", MARGIN_LEFT - 6, MARGIN_BOTTOM - 5)
    spendingLabel:SetTextColor(unpack(Theme.SPENDING))

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

    --- Draws the bars given. What a bar stands for (a day, six hours) is
    --- the caller's business: here they're numbered places along the
    --- chart.
    ---@param bars table      list of { at, income, spending }, in copper
    ---@param first number    the first place the chart covers
    ---@param last number     the last, normally now
    ---@param firstLabel string  what to write under the left-hand end
    ---@param lastLabel string   and under the right
    ---@param emptyText string|nil  what to say when there are no bars, if
    ---        not the usual
    function chart:SetBars(bars, first, last, firstLabel, lastLabel, emptyText)
        ReleaseLines(self)
        ReleaseBars(self)

        -- Both sides are drawn to one scale, so a tall bar means the same
        -- money whichever way it points.
        local peak = 0
        for _, bar in ipairs(bars) do
            peak = math.max(peak, bar.income, bar.spending)
        end

        if peak == 0 then
            incomeLabel:SetText("")
            spendingLabel:SetText("")
            firstDayLabel:SetText("")
            lastDayLabel:SetText("")
            key:Hide()
            emptyLabel:SetText(
                emptyText or "Nothing earned or spent on record yet. It starts with your next coin."
            )
            emptyLabel:Show()
            return
        end
        emptyLabel:Hide()
        key:Show()

        local slot = plotWidth / (last - first + 1)
        local barWidth = math.max(slot - BAR_GAP, 2)

        for _, bar in ipairs(bars) do
            local x = MARGIN_LEFT + (bar.at - first) * slot + (slot - barWidth) / 2

            -- Anything at all gets at least a sliver, so a quiet stretch
            -- isn't mistaken for one not played.
            if bar.income > 0 then
                local rise = math.max(bar.income / peak * reach, 1)
                DrawBar(self, x, middle, barWidth, rise, Theme.INCOME)
            end
            if bar.spending > 0 then
                local drop = math.max(bar.spending / peak * reach, 1)
                DrawBar(self, x, middle - drop, barWidth, drop, Theme.SPENDING)
            end
        end

        DrawLine(self, MARGIN_LEFT, middle, MARGIN_LEFT + plotWidth, middle, 1, Theme.MUTED, 0.6)

        incomeLabel:SetText(ns.Money(peak))
        spendingLabel:SetText(ns.Money(peak))
        firstDayLabel:SetText(firstLabel)
        lastDayLabel:SetText(lastLabel)
    end

    return chart
end
