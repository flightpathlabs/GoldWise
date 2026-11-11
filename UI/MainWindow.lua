local _, ns = ...

-- The Goldwise window: a status line, a tab for each list, and the page
-- for a single item. Built on Blizzard's own panel template, so it picks
-- up the game's frame art, close button and title bar for free.

local Theme = ns.Theme

local WIDTH, HEIGHT = 780, 520

-- The tabs along the bottom edge, in order.
local ASSETS, PROSPECTS = 1, 2
local TAB_LABELS = { "Assets", "Prospects" }

local window
local currentTab = ASSETS

-- How far the scan in progress has got, or nil when idle. The deep scan
-- knows how much there is to do; the ordinary one doesn't.
local scanProgress, scanTotal

-- Why the last scan gave up, if it did. Shown until the next one starts.
local stopReason

-- What we know about how fresh the prices are.
local function PriceAgeText()
    local marketKey = ns.Market.Current()
    local lastScan = ns.Ledger.LastScan(marketKey)

    if lastScan then
        return ("%s. Prices read %s."):format(
            ns.Market.Label(marketKey),
            ns.Ago(GetServerTime() - lastScan)
        )
    end

    -- Nothing of the player's own yet, but the feed may cover this market.
    -- Say where those prices come from, as Blizzard's terms ask.
    local feedUpdated = ns.Feed.UpdatedAt(marketKey)
    if feedUpdated then
        return ("Prices from %s, updated %s. Visit an auction house for live ones."):format(
            ns.Feed.SOURCE,
            ns.Ago(GetServerTime() - feedUpdated)
        )
    elseif ns.Market.IsOpen() then
        return "No prices yet. Press Read prices to fetch them."
    end
    return "No prices yet. Open an auction house and Goldwise will read it."
end

local function StatusText()
    if ns.Scanner.IsScanning() then
        if scanProgress and scanTotal then
            return ("Reading every auction: %s of %s..."):format(
                FormatLargeNumber(scanProgress),
                FormatLargeNumber(scanTotal)
            )
        elseif scanProgress then
            return ("Reading the auction house: %s items so far..."):format(
                FormatLargeNumber(scanProgress)
            )
        end
        return "Reading the auction house..."
    end

    if stopReason then
        return stopReason .. " " .. PriceAgeText()
    end
    return PriceAgeText()
end

local function RefreshStatus()
    if window and window:IsShown() then
        window.Status:SetText(StatusText())
    end
end

local function Refresh()
    if not window or not window:IsShown() then
        return
    end

    window.Status:SetText(StatusText())
    window.ScanButton:SetEnabled(ns.Market.IsOpen() and not ns.Scanner.IsScanning())

    -- Only the tab on show is rebuilt. The other catches up when the
    -- player switches to it.
    if currentTab == PROSPECTS then
        window.Prospects:Refresh()
        window.Footer:SetText(
            "Ranked by what each one sells for, not by gold per hour. Level ranges are a guide."
        )
        return
    end

    local total = window.List:Refresh()
    if total > 0 then
        window.Footer:SetText(
            "Selling what's marked Sell should bring in about " .. Theme.Coins(total) .. "."
        )
    else
        window.Footer:SetText("")
    end
end

local function ShowTab(tab)
    currentTab = tab
    PanelTemplates_SetTab(window, tab)

    window.Detail:Hide()
    window.List:SetShown(tab == ASSETS)
    window.Prospects:SetShown(tab == PROSPECTS)
    Refresh()
end

-- Back from an item's page to whichever list it was opened from.
local function ShowCurrentTab()
    ShowTab(currentTab)
end

local function ShowDetail(row)
    window.List:Hide()
    window.Prospects:Hide()
    window.Detail:ShowItem(row)
end

local function CreateTabs(frame)
    for index, label in ipairs(TAB_LABELS) do
        -- The template adds each tab to frame.Tabs for us.
        local tab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(label)
        PanelTemplates_TabResize(tab, 0)
        tab:SetScript("OnClick", function(self)
            ShowTab(self:GetID())
        end)

        -- Only the first needs placing. SetNumTabs chains the rest to it.
        if index == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        end
    end

    PanelTemplates_SetNumTabs(frame, #TAB_LABELS)
    PanelTemplates_SetTab(frame, currentTab)
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "GoldwiseWindow", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetTitle("Goldwise")
    frame:SetPortraitTextureRaw(Theme.PORTRAIT)
    frame:Hide()

    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    -- The tabs hang below the frame's own edge. Count them as part of it,
    -- or the window can be dragged until they're off the screen.
    frame:SetClampRectInsets(0, 0, 0, -30)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Lets Escape close the window like any other panel. Going through
    -- ShowUIPanel instead would refuse to open it in combat.
    table.insert(UISpecialFrames, frame:GetName())

    -- The strip between the title bar and the inset, clear of the portrait.
    frame.Status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Status:SetPoint("TOPLEFT", 66, -34)
    frame.Status:SetPoint("RIGHT", -16, 0)
    frame.Status:SetJustifyH("LEFT")
    frame.Status:SetWordWrap(false)

    -- The bar along the bottom edge.
    frame.ScanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.ScanButton:SetSize(110, 22)
    frame.ScanButton:SetPoint("BOTTOMRIGHT", -8, 4)
    frame.ScanButton:SetText("Read prices")
    frame.ScanButton:SetScript("OnClick", function()
        ns.Scanner.ReadPrices()
    end)

    frame.Footer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Footer:SetPoint("BOTTOMLEFT", 14, 10)
    frame.Footer:SetPoint("RIGHT", frame.ScanButton, "LEFT", -10, 0)
    frame.Footer:SetJustifyH("LEFT")
    frame.Footer:SetWordWrap(false)

    frame.List = ns.ShelfList.Create(frame.Inset, ShowDetail)
    frame.Prospects = ns.ProspectList.Create(frame.Inset, ShowDetail)
    frame.Detail = ns.ItemDetail.Create(frame.Inset, ShowCurrentTab)
    CreateTabs(frame)

    frame:SetScript("OnShow", Refresh)
    return frame
end

--- Opens the window, or closes it if it's already open.
function ns.ToggleWindow()
    if not window then
        window = CreateWindow()
    end
    window:SetShown(not window:IsShown())
end

-- Keeping it current -----------------------------------------------------------------

ns.Subscribe("SCAN_STARTED", function()
    scanProgress, scanTotal = nil, nil
    stopReason = nil
    Refresh()
end)

-- Only the status line changes mid-scan. Redrawing the whole list for
-- every page would be wasted work.
ns.Subscribe("SCAN_PROGRESS", function(done, total)
    scanProgress, scanTotal = done, total
    RefreshStatus()
end)

-- The new prices have already redrawn the list by the time this arrives
-- (see PRICES_CHANGED below), so there's only the status left to update.
ns.Subscribe("SCAN_FINISHED", function()
    stopReason = nil
    RefreshStatus()
end)

ns.Subscribe("SCAN_STOPPED", function(reason)
    stopReason = reason
    Refresh()
end)

ns.Subscribe("AUCTION_HOUSE_OPENED", function()
    stopReason = nil
    Refresh()
end)

for _, message in ipairs({
    "PRICES_CHANGED",
    "BAGS_CHANGED",
    "PROFILE_CHANGED",
    "SETTINGS_CHANGED",
    "AUCTION_HOUSE_CLOSED",
}) do
    ns.Subscribe(message, Refresh)
end

-- Item details the client had to fetch (a vendor price for something on
-- another character, say) arrive a moment after they're asked for. The
-- event fires for every item anything in the game loads, so only listen
-- while the window is open, and gather a burst into one redraw.
local redrawQueued = false

ns.OnEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
    if redrawQueued or not window or not window:IsShown() then
        return
    end

    -- A deep scan makes the client load thousands of items. Only the ones
    -- the list is actually waiting on are a reason to redraw.
    if not ns.ShelfList.IsWaitingFor(itemID) then
        return
    end

    redrawQueued = true
    C_Timer.After(0.5, function()
        redrawQueued = false
        Refresh()
    end)
end)

-- Ways in -----------------------------------------------------------------------------

SLASH_GOLDWISE1 = "/goldwise"
SLASH_GOLDWISE2 = "/gw"
SlashCmdList.GOLDWISE = function()
    ns.ToggleWindow()
end

-- Named in the TOC file. The client calls it when the player picks Goldwise
-- from the addon list by the minimap. Right-click goes to the options, the
-- same as on the minimap button.
function Goldwise_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenOptions()
    else
        ns.ToggleWindow()
    end
end
