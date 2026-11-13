local _, ns = ...

-- A small panel to keep on screen while playing: what this session has
-- brought in or cost, and what's in the bags at the prices Goldwise would
-- sell it for. The figures are worked out in Profile\Session.lua.
--
-- It's off until the player asks for it, from the button on the Goldwise
-- window's title bar or with /gw session. Drag it anywhere; right-click
-- for the rest.

local Theme = ns.Theme

local WIDTH = 220
local PADDING = 10
local LINE_HEIGHT = 16
local PIN_SIZE = 18

-- How often the clock on it moves on, in seconds.
local TICK = 5

-- Before this long, an hourly rate is mostly noise.
local RATE_AFTER_SECONDS = 10 * 60

-- The places the pin's tooltip names, nearest first within each.
local NEARBY = {
    { label = "Auction house", kind = "AUCTION" },
    { label = "Repairs", kind = "REPAIR" },
    { label = "Bank", kind = "BANK" },
    { label = "Flight master", kind = "FLIGHT" },
    { label = "Innkeeper", kind = "INN" },
}

local tracker

local function Duration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if hours > 0 then
        return ("%dh %02dm"):format(hours, minutes)
    end
    return ("%dm"):format(minutes)
end

local function Distance(spot, yards)
    if yards then
        return ("%d yd"):format(yards)
    end
    local map = spot.mapID and C_Map.GetMapInfo(spot.mapID)
    return map and map.name or ""
end

-- Building -----------------------------------------------------------------------------

-- A line of the panel: what it is on the left, the figure on the right.
local function CreateLine(parent, index, label, font)
    local top = -(PADDING + 20 + (index - 1) * LINE_HEIGHT)

    local line = {}
    line.Label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
    line.Label:SetPoint("TOPLEFT", PADDING, top)
    line.Label:SetText(label)

    line.Figure = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    line.Figure:SetPoint("TOPRIGHT", -PADDING, top)
    line.Figure:SetJustifyH("RIGHT")
    return line
end

local function SetSigned(line, copper)
    if not copper then
        line.Figure:SetText("-")
        line.Figure:SetTextColor(1, 1, 1)
        return
    end
    -- Rounded first, so a fraction of a copper isn't shown as a gain of none.
    copper = math.floor(copper + 0.5)
    local text, color = Theme.SignedCoins(copper)
    if copper > 0 then
        text = "+" .. text
    end
    line.Figure:SetText(text)
    line.Figure:SetTextColor(unpack(color))
end

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ns.settings.sessionTrackerPoint = { point, relativePoint, x, y }
end

local function PlacePanel(frame)
    frame:ClearAllPoints()
    local saved = ns.settings.sessionTrackerPoint
    if type(saved) == "table" and saved[1] then
        frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
    end
end

-- The pin in the corner, to the Places tab, naming what's nearest.
local function CreatePlacesPin(frame)
    local pin = CreateFrame("Button", nil, frame)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetPoint("TOPRIGHT", -PADDING + 4, -PADDING + 4)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("Waypoint-MapPin-Untracked")
    icon:SetAllPoints()

    local glow = pin:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAtlas("Waypoint-MapPin-Untracked")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.5)
    glow:SetAllPoints()

    pin:SetScript("OnClick", function()
        ns.ShowWindowTab("Places")
    end)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Places near you")
        for _, place in ipairs(NEARBY) do
            local spot, yards = ns.Directory.Nearest(ns.Directory[place.kind])
            if spot then
                GameTooltip:AddDoubleLine(place.label, Distance(spot, yards), 1, 1, 1, 1, 1, 1)
            else
                local muted = Theme.MUTED
                GameTooltip:AddDoubleLine(
                    place.label,
                    "not found yet",
                    1,
                    1,
                    1,
                    muted[1],
                    muted[2],
                    muted[3]
                )
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "Click for trainers and the rest on the Places tab.",
            0.6,
            0.6,
            0.6,
            true
        )
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", GameTooltip_Hide)
end

local function ShowDetails(frame)
    local summary = ns.Session.Summary()
    if not summary then
        return
    end

    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:SetText("This session")
    GameTooltip:AddDoubleLine("Coin in", Theme.Coins(summary.earned), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Coin out", Theme.Coins(summary.spent), 1, 1, 1, 1, 1, 1)
    if summary.bags then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Bags at auction", Theme.Coins(summary.auction), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Bags to vendors", Theme.Coins(summary.vendor), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(
            "Each thing is counted the way Goldwise would sell it: at auction, "
                .. "less the cut, if it says sell or hold, and at a vendor's price if it "
                .. "says vendor. What you keep isn't counted.",
            0.6,
            0.6,
            0.6,
            true
        )
        if summary.unpriced > 0 then
            GameTooltip:AddLine(
                (
                    "%d %s no auction price yet, so %s counted at what a vendor pays, "
                    .. "if anything."
                ):format(
                    summary.unpriced,
                    summary.unpriced == 1 and "thing has" or "things have",
                    summary.unpriced == 1 and "it's" or "they're"
                ),
                0.6,
                0.6,
                0.6,
                true
            )
        end
        GameTooltip:AddLine(
            "Change in bags compares what you carry now with what you started with, "
                .. "both at today's prices. Listing something takes it out of your bags "
                .. "before its coin arrives, so the session dips until the sale's letter "
                .. "is collected. Putting things in the bank or posting them to another "
                .. "character counts as them leaving.",
            0.6,
            0.6,
            0.6,
            true
        )
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Drag to move it. Right-click for more.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function OpenMenu(frame)
    MenuUtil.CreateContextMenu(frame, function(_, root)
        root:CreateTitle("Session tracker")
        root:CreateButton("Start a new session", function()
            ns.Session.Restart()
        end)
        root:CreateCheckbox("Lock in place", function()
            return ns.settings.sessionTrackerLocked
        end, function()
            ns.settings.sessionTrackerLocked = not ns.settings.sessionTrackerLocked
        end)
        root:CreateButton("Open Goldwise", function()
            ns.ShowWindow()
        end)
        root:CreateButton("Hide", function()
            ns.ToggleSessionTracker(false)
        end)
    end)
end

local function Create()
    local frame =
        CreateFrame("Frame", "GoldwiseSessionTracker", UIParent, "TooltipBackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    PlacePanel(frame)

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Title:SetPoint("TOPLEFT", PADDING, -PADDING)
    frame.Title:SetText("Session")

    frame.Clock = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.Clock:SetPoint("LEFT", frame.Title, "RIGHT", 6, 0)

    CreatePlacesPin(frame)

    frame.Coin = CreateLine(frame, 1, "Coin")
    frame.Goods = CreateLine(frame, 2, "Change in bags")
    frame.Overall = CreateLine(frame, 3, "Altogether", "GameFontNormal")
    frame.Overall.Figure:SetFontObject("GameFontHighlight")
    frame.Rate = CreateLine(frame, 4, "An hour")
    frame.Bags = CreateLine(frame, 5.5, "Bags worth")
    frame.Auction = CreateLine(frame, 6.5, "   at auction", "GameFontDisableSmall")
    frame.Vendor = CreateLine(frame, 7.5, "   to vendors", "GameFontDisableSmall")

    frame:SetSize(WIDTH, PADDING * 2 + 20 + 7.5 * LINE_HEIGHT)

    frame:SetScript("OnDragStart", function(self)
        if not ns.settings.sessionTrackerLocked then
            GameTooltip_Hide()
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            OpenMenu(self)
        end
    end)
    frame:SetScript("OnEnter", ShowDetails)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    frame:SetScript("OnShow", function(self)
        ns.Session.SetWatched(true)
        self:Refresh()
        self.ticker = C_Timer.NewTicker(TICK, function()
            self:Refresh()
        end)
    end)
    frame:SetScript("OnHide", function(self)
        ns.Session.SetWatched(false)
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
    end)

    function frame:Refresh()
        local summary = ns.Session.Summary()
        if not summary then
            return
        end

        self.Clock:SetText(Duration(summary.seconds))
        SetSigned(self.Coin, summary.coin)
        SetSigned(self.Goods, summary.goods)
        SetSigned(self.Overall, summary.overall or summary.coin)

        if summary.seconds >= RATE_AFTER_SECONDS then
            SetSigned(self.Rate, (summary.overall or summary.coin) / summary.seconds * 3600)
        else
            self.Rate.Figure:SetText("after 10 minutes")
            self.Rate.Figure:SetTextColor(unpack(Theme.MUTED))
        end

        if summary.bags then
            self.Bags.Figure:SetText(Theme.Coins(summary.bags))
            self.Auction.Figure:SetText(Theme.Coins(summary.auction))
            self.Vendor.Figure:SetText(Theme.Coins(summary.vendor))
        else
            self.Bags.Figure:SetText("-")
            self.Auction.Figure:SetText("-")
            self.Vendor.Figure:SetText("-")
        end
    end

    ns.Subscribe("SESSION_CHANGED", function()
        if frame:IsShown() then
            frame:Refresh()
        end
    end)

    frame:Hide()
    return frame
end

--- Shows or hides the session tracker, and remembers which.
---@param show boolean|nil  nil to switch it to the other
function ns.ToggleSessionTracker(show)
    if show == nil then
        show = not ns.settings.sessionTracker
    end
    ns.settings.sessionTracker = show

    tracker = tracker or Create()
    tracker:SetShown(show)
    ns.Publish("SESSION_TRACKER_TOGGLED", show)
end

--- Whether the session tracker is on.
---@return boolean
function ns.SessionTrackerShown()
    return ns.settings.sessionTracker == true
end

ns.OnEvent("PLAYER_LOGIN", function()
    if ns.settings.sessionTracker then
        ns.ToggleSessionTracker(true)
    end
end)

-- The options page has a box for it too, which sets the setting directly.
ns.Subscribe("SETTINGS_CHANGED", function()
    local wanted = ns.settings.sessionTracker == true
    if wanted ~= (tracker ~= nil and tracker:IsShown()) then
        ns.ToggleSessionTracker(wanted)
    end
end)
