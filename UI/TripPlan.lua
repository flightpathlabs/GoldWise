local _, ns = ...

-- The plan for a trip to a zone, as a list of steps under headings. It
-- shares the Prospects tab with the ranked list and is shown in its place
-- when the player has picked somewhere to go. Advisor\Trip works out what
-- the steps are; this only draws them.

local TripPlan = {}
ns.TripPlan = TripPlan

local Theme = ns.Theme

local ROW_HEIGHT = 46

-- Columns are placed from the edges, in pixels.
local NUMBER_WIDTH = 24
local ACTION_RIGHT = 10
local AMOUNT_RIGHT = 84
local AMOUNT_WIDTH = 170

-- A step can show a few figures side by side in place of the one amount,
-- each with a word under it saying what it is.
local MOST_FIGURES = 3
local FIGURE_WIDTH = 96

-- The strip along the bottom that says how far a slow list has got.
local LOADING_HEIGHT = 24
local LOADING_LABEL_WIDTH = 230

-- Rows --------------------------------------------------------------------------

local function CreateRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    -- A row is either a heading...
    row.Heading = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.Heading:SetPoint("BOTTOMLEFT", 8, 8)

    -- ...or a step: its number, what to do, why, what it's worth, and a
    -- button where there's somewhere to go.
    row.Number = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Number:SetPoint("LEFT", 8, 0)
    row.Number:SetWidth(NUMBER_WIDTH)
    row.Number:SetJustifyH("LEFT")
    row.Number:SetTextColor(unpack(Theme.MUTED))

    row.Action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Action:SetSize(64, 22)
    row.Action:SetPoint("RIGHT", -ACTION_RIGHT, 0)
    row.Action:SetScript("OnClick", function(self)
        local action = self:GetParent():GetElementData().action
        if action then
            action.onClick()
        end
    end)

    row.Amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Amount:SetPoint("RIGHT", -AMOUNT_RIGHT, 0)
    row.Amount:SetWidth(AMOUNT_WIDTH)
    row.Amount:SetJustifyH("RIGHT")
    row.Amount:SetWordWrap(false)

    -- Counted from the right, so the last figure given sits where the
    -- single amount would.
    row.Figures = {}
    for index = 1, MOST_FIGURES do
        local value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        value:SetPoint("TOPRIGHT", -(AMOUNT_RIGHT + (index - 1) * FIGURE_WIDTH), -8)
        value:SetWidth(FIGURE_WIDTH)
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)

        local caption = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        caption:SetPoint("TOPRIGHT", value, "BOTTOMRIGHT", 0, -4)
        caption:SetTextColor(unpack(Theme.MUTED))

        row.Figures[index] = { Value = value, Caption = caption }
    end

    row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Title:SetPoint("TOPLEFT", row.Number, "TOPRIGHT", 4, 7)
    row.Title:SetPoint("RIGHT", row.Amount, "LEFT", -10, 0)
    row.Title:SetJustifyH("LEFT")
    row.Title:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
    row.Detail:SetPoint("RIGHT", row.Amount, "LEFT", -10, 0)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetJustifyV("TOP")
    row.Detail:SetMaxLines(2)
    row.Detail:SetTextColor(unpack(Theme.MUTED))

    -- A step about an item shows the item when pointed at, and opens its
    -- price history when clicked.
    row:SetScript("OnEnter", function(self)
        local itemID = self:GetElementData().itemID
        if itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        local itemID = self:GetElementData().itemID
        if itemID then
            ns.ShowItemHistory(itemID)
        end
    end)
end

local function FillRow(row, data)
    local isHeading = data.heading ~= nil
    local figures = not isHeading and data.figures or nil

    row.Stripe:SetShown(not isHeading and row:GetOrderIndex() % 2 == 0)
    row.Heading:SetShown(isHeading)
    row.Number:SetShown(not isHeading)
    row.Title:SetShown(not isHeading)
    row.Detail:SetShown(not isHeading)
    row.Amount:SetShown(not isHeading and figures == nil)
    row.Action:SetShown(not isHeading and data.action ~= nil)
    -- Only rows with something behind them should light up when pointed at.
    row:EnableMouse(not isHeading and data.itemID ~= nil)

    -- Figures are given left to right and placed from the right.
    for index, figure in ipairs(row.Figures) do
        local given = figures and figures[#figures - index + 1]
        figure.Value:SetShown(given ~= nil)
        figure.Caption:SetShown(given ~= nil)
        if given then
            figure.Value:SetText(Theme.Coins(given.amount))
            figure.Caption:SetText(given.caption)
        end
    end

    if isHeading then
        row.Heading:SetText(data.heading:upper())
        return
    end

    row.Number:SetText(data.number and (data.number .. ".") or "")

    -- A step with no figure and no button has the row to itself, and its
    -- words can run the full width.
    local fullWidth = data.amount == nil and data.action == nil and figures == nil
    for _, text in ipairs({ row.Title, row.Detail }) do
        text:ClearAllPoints()
    end
    row.Title:SetPoint("TOPLEFT", row.Number, "TOPRIGHT", 4, 7)
    row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
    if fullWidth then
        row.Title:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.Detail:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    elseif figures then
        local taken = AMOUNT_RIGHT + #figures * FIGURE_WIDTH + 10
        row.Title:SetPoint("RIGHT", row, "RIGHT", -taken, 0)
        row.Detail:SetPoint("RIGHT", row, "RIGHT", -taken, 0)
    else
        row.Title:SetPoint("RIGHT", row.Amount, "LEFT", -10, 0)
        row.Detail:SetPoint("RIGHT", row.Amount, "LEFT", -10, 0)
    end

    -- An item's name in its quality colour, where the step is about one.
    local title = data.title
    if data.itemID then
        title = Theme.ItemName(title, C_Item.GetItemQualityByID(data.itemID))
    end
    row.Title:SetText(title)
    row.Detail:SetText(data.detail or "")

    if data.amount then
        -- A word before the figure ("profit 2g") or after it ("2g each"),
        -- whichever reads naturally.
        local text = Theme.Coins(data.amount)
        if data.amountLabel then
            text = data.amountLabel .. " " .. text
        end
        if data.amountAfter then
            text = text .. " " .. data.amountAfter
        end
        row.Amount:SetText(text)
    else
        row.Amount:SetText("")
    end

    if data.action then
        row.Action:SetText(data.action.label)
    end
end

-- The view ----------------------------------------------------------------------------

--- Creates the plan view. It starts hidden.
---@param parent table  frame to sit in; the caller places it
---@return table view   with :SetPlan(sections)
function TripPlan.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()

    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT")
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Some plans can't be laid out all at once, because the game has to
    -- be asked about each thing in them. While one is filling in, this
    -- says what it's waiting on and how far it has got.
    local loadingLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    loadingLabel:SetPoint("BOTTOMLEFT", 8, 6)
    loadingLabel:SetWidth(LOADING_LABEL_WIDTH)
    loadingLabel:SetJustifyH("LEFT")
    loadingLabel:SetWordWrap(false)
    loadingLabel:SetTextColor(unpack(Theme.MUTED))

    local loadingBar = CreateFrame("StatusBar", nil, frame)
    loadingBar:SetHeight(6)
    loadingBar:SetPoint("LEFT", loadingLabel, "RIGHT", 10, 0)
    loadingBar:SetPoint("RIGHT", scrollBox, "RIGHT", -6, 0)
    loadingBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    loadingBar:SetStatusBarColor(unpack(Theme.COIN))
    loadingBar:SetMinMaxValues(0, 1)

    local trough = loadingBar:CreateTexture(nil, "BACKGROUND")
    trough:SetAllPoints()
    trough:SetColorTexture(0, 0, 0, 0.5)

    --- Shows a plan.
    ---@param sections table      from Trip.Plan
    ---@param loading table|nil   { label, fraction } for a plan that's
    ---        still filling in: what to say, and how far along it is from
    ---        0 to 1
    function frame:SetPlan(sections, loading)
        -- The list gives up its bottom edge to the strip while it's there.
        scrollBox:SetPoint("BOTTOMRIGHT", -16, loading and LOADING_HEIGHT or 0)
        loadingLabel:SetShown(loading ~= nil)
        loadingBar:SetShown(loading ~= nil)
        if loading then
            loadingLabel:SetText(loading.label)
            loadingBar:SetValue(loading.fraction)
        end

        -- Flattened into one list of rows, a heading and then its steps.
        -- Things to do are numbered straight through, so the plan reads
        -- as one sequence from top to bottom.
        local rows = {}
        local number = 0

        for _, section in ipairs(sections) do
            table.insert(rows, { heading = section.heading })
            for _, step in ipairs(section.steps) do
                if section.numbered then
                    number = number + 1
                    step.number = number
                end
                table.insert(rows, step)
            end
        end

        scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    end

    return frame
end
