local _, ns = ...

-- The Places tab: the nearest trainer for the player's class and for each
-- profession, and the nearest of the services everyone needs, each with a
-- button that puts it on the map.

local PlacesTab = {}
ns.PlacesTab = PlacesTab

local Theme = ns.Theme
local Directory = ns.Directory

local ROW_HEIGHT = 30

-- Seconds between refreshes while the tab is open, so the distances keep
-- up with a player on the move.
local REFRESH_EVERY = 2

-- Columns are placed from the edges, in pixels.
local LABEL_WIDTH = 170
local WHERE_WIDTH = 200
local MAP_RIGHT = 10
local WHERE_RIGHT = 84

-- Rows --------------------------------------------------------------------------

local function CreateRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    -- A row is either a section heading...
    row.Heading = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.Heading:SetPoint("BOTTOMLEFT", 8, 6)

    -- ...or a place: what it is, who runs it, where, and a way there.
    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Label:SetPoint("LEFT", 8, 0)
    row.Label:SetWidth(LABEL_WIDTH)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetWordWrap(false)

    row.Map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Map:SetSize(64, 22)
    row.Map:SetPoint("RIGHT", -MAP_RIGHT, 0)
    row.Map:SetText("Map")
    row.Map:SetScript("OnClick", function(self)
        local spot = self:GetParent():GetElementData().spot
        if spot then
            ns.MapMarks.ShowPoint(spot.mapID, spot.x, spot.y)
        end
    end)

    row.Where = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Where:SetPoint("RIGHT", -WHERE_RIGHT, 0)
    row.Where:SetWidth(WHERE_WIDTH)
    row.Where:SetJustifyH("RIGHT")
    row.Where:SetWordWrap(false)
    row.Where:SetTextColor(unpack(Theme.MUTED))

    row.Who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Who:SetPoint("LEFT", row.Label, "RIGHT", 8, 0)
    row.Who:SetPoint("RIGHT", row.Where, "LEFT", -10, 0)
    row.Who:SetJustifyH("LEFT")
    row.Who:SetWordWrap(false)
end

-- "Bengus Deepforge, Expert Blacksmith", or as much of that as we know.
local function WhoText(spot)
    if spot.name and spot.title and spot.title ~= "" then
        return ("%s, %s"):format(spot.name, spot.title)
    end
    return spot.name or spot.title or ""
end

-- "Ironforge, 420 yd". Distances are rounded: nobody paces them out.
local function WhereText(spot, yards)
    local zone = ns.MapMarks.ZoneName(spot.mapID)
    if not yards then
        return zone
    elseif yards < 20 then
        return zone .. ", right here"
    end
    return ("%s, %s yd"):format(zone, FormatLargeNumber(math.floor(yards / 10 + 0.5) * 10))
end

local function FillRow(row, data)
    local isHeading = data.heading ~= nil

    row.Stripe:SetShown(not isHeading and row:GetOrderIndex() % 2 == 0)
    row.Heading:SetShown(isHeading)
    row.Label:SetShown(not isHeading)
    row.Who:SetShown(not isHeading)
    row.Where:SetShown(not isHeading)
    row.Map:SetShown(not isHeading and data.spot ~= nil)

    if isHeading then
        row.Heading:SetText(data.heading:upper())
        return
    end

    row.Label:SetText(data.label)
    if data.spot then
        row.Who:SetText(WhoText(data.spot))
        row.Who:SetTextColor(1, 1, 1)
        row.Where:SetText(WhereText(data.spot, data.yards))
    else
        row.Who:SetText("Not found yet")
        row.Who:SetTextColor(unpack(Theme.MUTED))
        row.Where:SetText("")
    end
end

-- Gathering the rows ---------------------------------------------------------------

local function Place(label, kind)
    local spot, yards = Directory.Nearest(kind)
    return { label = label, spot = spot, yards = yards }
end

local function Rows()
    local rows = {}
    local className, class = UnitClass("player")

    -- The player's own trainers come first: their class, then whichever
    -- professions they've taken up.
    table.insert(rows, { heading = "Your trainers" })
    table.insert(rows, Place(className or "Class", Directory.ClassTrainerKind()))

    local others = {}
    for _, profession in ipairs(Directory.PROFESSIONS) do
        local skill = ns.Professions.SkillByName(profession.name)
        local kind = Directory.ProfessionKind(profession)
        if skill then
            table.insert(rows, Place(("%s (%d)"):format(profession.name, skill), kind))
        else
            table.insert(others, Place(profession.name, kind))
        end
    end

    table.insert(rows, { heading = "Close by" })
    table.insert(rows, Place("Auction house", Directory.AUCTION))
    table.insert(rows, Place("Repairs", Directory.REPAIR))
    table.insert(rows, Place("Bank", Directory.BANK))
    table.insert(rows, Place("Flight master", Directory.FLIGHT))
    table.insert(rows, Place("Innkeeper", Directory.INN))
    if class == "HUNTER" then
        table.insert(rows, Place("Stable master", Directory.STABLE))
    end

    if #others > 0 then
        table.insert(rows, { heading = "Other professions" })
        for _, row in ipairs(others) do
            table.insert(rows, row)
        end
    end

    return rows
end

-- The tab ------------------------------------------------------------------------------

--- Creates the Places tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh()
function PlacesTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    local heading = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Places")

    local about = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))
    about:SetText("The nearest of each to where you're standing")

    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -32)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", function(row, data)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    --- Rebuilds the list for where the player is now.
    function tab:Refresh()
        scrollBox:SetDataProvider(
            CreateDataProvider(Rows()),
            ScrollBoxConstants.RetainScrollPosition
        )
    end

    -- Nothing announces that the player has walked a few yards, so while
    -- the tab is open it simply looks again every so often.
    local sinceRefresh = 0
    tab:SetScript("OnUpdate", function(self, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= REFRESH_EVERY then
            sinceRefresh = 0
            self:Refresh()
        end
    end)

    return tab
end
