local _, ns = ...

-- Price charts, drawn with the client's line primitives.
--
-- Two kinds: a sparkline small enough to sit in a list row, and a full
-- chart on a parchment background with labelled axes. Both are meant to
-- look like something inked into a ledger: thin dark lines, no fills.

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
