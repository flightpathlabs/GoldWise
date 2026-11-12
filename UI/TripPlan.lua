local _, ns = ...

-- The plan for a trip to a zone, as a list of steps under headings. It
-- shares the Prospects tab with the ranked list and is shown in its place
-- when the player has picked somewhere to go. Advisor\Trip works out what
-- the steps are; this only draws them.

local TripPlan = {}
ns.TripPlan = TripPlan

local Theme = ns.Theme

local ROW_HEIGHT = 40

-- Columns are placed from the edges, in pixels.
local NUMBER_WIDTH = 24
local ACTION_RIGHT = 10
local AMOUNT_RIGHT = 84
local AMOUNT_WIDTH = 190

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

    row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Title:SetPoint("TOPLEFT", row.Number, "TOPRIGHT", 4, 7)
    row.Title:SetPoint("RIGHT", row.Amount, "LEFT", -10, 0)
    row.Title:SetJustifyH("LEFT")
    row.Title:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
    row.Detail:SetPoint("RIGHT", row.Amount, "LEFT", -10, 0)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)
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

    row.Stripe:SetShown(not isHeading and row:GetOrderIndex() % 2 == 0)
    row.Heading:SetShown(isHeading)
    row.Number:SetShown(not isHeading)
    row.Title:SetShown(not isHeading)
    row.Detail:SetShown(not isHeading)
    row.Amount:SetShown(not isHeading)
    row.Action:SetShown(not isHeading and data.action ~= nil)
    -- Only rows with something behind them should light up when pointed at.
    row:EnableMouse(not isHeading and data.itemID ~= nil)

    if isHeading then
        row.Heading:SetText(data.heading:upper())
        return
    end

    row.Number:SetText(data.number and (data.number .. ".") or "")

    -- An item's name in its quality colour, where the step is about one.
    local title = data.title
    if data.itemID then
        title = Theme.ItemName(title, C_Item.GetItemQualityByID(data.itemID))
    end
    row.Title:SetText(title)
    row.Detail:SetText(data.detail or "")

    if data.amount then
        row.Amount:SetText(("%s %s"):format(data.amountLabel or "", Theme.Coins(data.amount)))
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

    --- Shows a plan.
    ---@param sections table  from Trip.Plan
    function frame:SetPlan(sections)
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
