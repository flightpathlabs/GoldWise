local _, ns = ...

-- The Goldwise window: a status line, a tab for each list, and the page
-- for a single item. Built on Blizzard's own panel template, so it picks
-- up the game's frame art, close button and title bar for free.

local Theme = ns.Theme

local WIDTH, HEIGHT = 780, 520

-- The tabs along the bottom edge, in order. Each names the page it shows
-- (a field on the window) and how to bring that page up to date. Whatever
-- refresh returns goes in the footer.
local TABS = {
    {
        label = "Assets",
        page = "List",
        refresh = function(page)
            local total = page:Refresh()
            local parts = {}
            if total > 0 then
                table.insert(
                    parts,
                    ("About %s from what's marked Sell."):format(Theme.Coins(total))
                )
            end

            -- In the first few days there are prices but nothing to judge
            -- them against. Say so, and say that it passes, so a list of
            -- cautious verdicts doesn't look like all there is.
            local days = ns.Ledger.DaysRecorded(ns.Market.Current())
            local needed = ns.Stats.DAYS_FOR_USUAL
            if days > 0 and days < needed then
                local early = "Day %d of your price history. "
                    .. "Trends and sharper advice come after day %d."
                table.insert(parts, early:format(days, needed))
            end
            return table.concat(parts, " ")
        end,
    },
    {
        label = "Prospects",
        page = "Prospects",
        refresh = function(page)
            page:Refresh()
            return "Ranked by what each one sells for, not by gold per hour. "
                .. "Level ranges are a guide."
        end,
    },
    {
        label = "Purse",
        page = "Purse",
        refresh = function(page)
            page:Refresh()
            return "Amounts are full price. Point at a training line to see where "
                .. "your reputation makes it cheaper."
        end,
    },
    {
        label = "Places",
        page = "Places",
        refresh = function(page)
            page:Refresh()
            if ns.Directory.HasQuestie() then
                return "Nearest in a straight line. The road there may be longer."
            end
            return "Goldwise learns places as you visit them. "
                .. "With Questie installed it knows them from the start."
        end,
    },
    {
        label = "Recipes",
        page = "Recipes",
        refresh = function(page)
            page:Refresh()
            return "Click a recipe for its price history. "
                .. "The list of who sells what comes from What's Training?."
        end,
    },
    {
        label = "About",
        page = "About",
        refresh = function() end,
    },
}

local window
local currentTab = 1

-- How far the scan in progress has got, or nil when idle. The deep scan
-- knows how much there is to do; the ordinary one doesn't.
local scanProgress, scanTotal

-- Why the last scan gave up, if it did. Shown until the next one starts.
local stopReason

-- What we know about how fresh the prices are.
local function PriceAgeText()
    local marketKey = ns.Market.Current()
    local lastScan = ns.Ledger.LastScan(marketKey)

    -- The feed may cover this market too. Wherever its prices can appear,
    -- say where they come from, as Blizzard's terms ask.
    local feedUpdated = ns.Feed.UpdatedAt(marketKey)

    if lastScan then
        local text = ("%s. Prices read %s."):format(
            ns.Market.Label(marketKey),
            ns.Ago(GetServerTime() - lastScan)
        )
        if feedUpdated then
            text = text .. " Gaps filled from " .. ns.Feed.SOURCE .. "."
        end
        return text
    end

    -- Nothing of the player's own yet.
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

    -- Only the tab on show is rebuilt. The others catch up when the
    -- player switches to them. While an item's page covers the tab, the
    -- footer still belongs to the tab underneath.
    local tab = TABS[currentTab]
    window.Footer:SetText(tab.refresh(window[tab.page]) or "")
end

local function HidePages()
    for _, tab in ipairs(TABS) do
        window[tab.page]:Hide()
    end
end

local function ShowTab(index)
    currentTab = index
    PanelTemplates_SetTab(window, index)

    window.Detail:Hide()
    HidePages()
    window[TABS[index].page]:Show()
    Refresh()
end

-- Back from an item's page to whichever list it was opened from.
local function ShowCurrentTab()
    ShowTab(currentTab)
end

local function ShowDetail(row)
    HidePages()
    window.Detail:ShowItem(row)
end

local function CreateTabs(frame)
    for index, definition in ipairs(TABS) do
        -- The template adds each tab to frame.Tabs for us.
        local tab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(definition.label)
        PanelTemplates_TabResize(tab, 0)
        tab:SetScript("OnClick", function(self)
            ShowTab(self:GetID())
        end)

        -- Only the first needs placing. SetNumTabs chains the rest to it.
        if index == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        end
    end

    PanelTemplates_SetNumTabs(frame, #TABS)
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
    frame.Purse = ns.PurseTab.Create(frame.Inset)
    frame.Places = ns.PlacesTab.Create(frame.Inset)
    frame.Recipes = ns.RecipesTab.Create(frame.Inset)
    frame.About = ns.AboutTab.Create(frame.Inset)
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

--- Opens the window, and leaves it be if it's open already.
function ns.ShowWindow()
    if not window then
        window = CreateWindow()
    end
    window:Show()
end

--- Opens the window on a particular tab.
---@param page string  the tab's page, as named in TABS: "Recipes", say
function ns.ShowWindowTab(page)
    ns.ShowWindow()
    for index, tab in ipairs(TABS) do
        if tab.page == page then
            ShowTab(index)
            return
        end
    end
end

--- Opens the window on one item's price history, whether or not the
--- player is carrying any.
---@param itemID number
---@param link string|nil  the item's link, if there is one to hand
function ns.ShowItemHistory(itemID, link)
    local marketKey = ns.Market.Current()
    local name, itemLink, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link or itemID)
    local count = ns.Bags.Counts()[itemID] or 0

    -- Asking about an item is a sign of interest in it. Follow it from
    -- here on, so the history is longer the next time they look.
    ns.Ledger.Track(marketKey, itemID)

    local row = ns.Assets.Describe({
        itemID = itemID,
        name = name,
        icon = icon or C_Item.GetItemIconByID(itemID),
        quality = quality,
        link = itemLink or link,
        count = count,
    }, marketKey)

    -- A verdict is advice on what to do with a holding. With nothing
    -- held, there's none to give.
    if count == 0 then
        row.advice = { verb = ns.Advice.UNKNOWN, reason = "You aren't carrying any of these." }
    end

    ns.ShowWindow()
    ShowDetail(row)
end

-- Opens the history of whatever the player last pointed at.
local function ShowPointedAtItem()
    local itemID, link = ns.PointedAtItem()
    if itemID then
        ns.ShowItemHistory(itemID, link)
    else
        ns.Print("Point at an item first, then try again.")
    end
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

-- Money and durability change constantly, and only one tab cares.
ns.Subscribe("PURSE_CHANGED", function()
    if TABS[currentTab].page == "Purse" then
        Refresh()
    end
end)

-- Likewise a newly learned place. It also names a trainer on the Purse
-- tab's map menu, but that's built fresh each time it's opened.
ns.Subscribe("PLACES_CHANGED", function()
    if TABS[currentTab].page == "Places" then
        Refresh()
    end
end)

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
    if not ns.Assets.IsWaitingFor(itemID) then
        return
    end

    redrawQueued = true
    C_Timer.After(0.5, function()
        redrawQueued = false
        Refresh()
    end)
end)

-- Ways in -----------------------------------------------------------------------------

-- More gold than this isn't a goal, it's a typo (or "inf", which Lua will
-- happily read as a number).
local MAX_GOAL_GOLD = 1e7

-- "/gw goal 50" sets a savings target of 50 gold; "/gw goal off" clears it.
local function SetGoal(amount)
    local gold = tonumber(amount)
    if gold and gold > 0 and gold <= MAX_GOAL_GOLD then
        ns.settings.goalCopper = math.floor(gold * ns.COPPER_PER_GOLD)
        ns.Print("Saving toward %s. The Purse tab tracks it.", ns.Money(ns.settings.goalCopper))
    elseif amount == "off" or amount == "0" then
        ns.settings.goalCopper = nil
        ns.Print("Savings goal cleared.")
    else
        ns.Print("Give an amount in gold, like /gw goal 50, or /gw goal off to clear it.")
        return
    end
    ns.Publish("SETTINGS_CHANGED")
end

SLASH_GOLDWISE1 = "/goldwise"
SLASH_GOLDWISE2 = "/gw"
SlashCmdList.GOLDWISE = function(message)
    message = strtrim(message or "")

    -- An item shift-clicked into the command: "/gw [Light Leather]".
    local linkedItem = message:match("|Hitem:(%d+)")
    if linkedItem then
        ns.ShowItemHistory(tonumber(linkedItem), message:match("|c.-|h|r"))
        return
    end

    local command, argument = message:lower():match("^(%S*)%s*(.-)$")
    if command == "goal" then
        SetGoal(argument)
    elseif command == "history" then
        ShowPointedAtItem()
    else
        ns.ToggleWindow()
    end
end

-- The key binding, declared in Bindings.xml. The game finds the function
-- and these labels by name, so they have to be global.
BINDING_NAME_GOLDWISE_HISTORY = "Price history for the item under the mouse"

function Goldwise_ShowHoveredItemHistory()
    ShowPointedAtItem()
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
