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
local RESET_SIZE = 14
local FOLD_SIZE = 16

-- Folded to its title line: the padding above and below, and a line of
-- text between.
local FOLDED_HEIGHT = 2 * PADDING + 14

-- How often the clock on it moves on, in seconds.
local TICK = 5

-- Before this long, an hourly rate is mostly noise.
local RATE_AFTER_SECONDS = 10 * 60

-- The places the pin's tooltip names, the nearest of each kind.
local NEARBY = {
    { label = "Auction house", kind = "AUCTION" },
    { label = "Repairs", kind = "REPAIR" },
    { label = "Bank", kind = "BANK" },
    { label = "Flight master", kind = "FLIGHT" },
    { label = "Innkeeper", kind = "INN" },
}

-- The breakdown's names for each kind of coin, by Purse.lua's categories.
-- Anything not here is shown as "Other".
local INCOME_LABELS = {
    loot = "Looted",
    quest = "Quest rewards",
    vendor = "Sold to vendors",
    auction = "Auction sales",
    mail = "Mail",
    other = "Other",
}

local SPENDING_LABELS = {
    repair = "Repairs",
    vendor = "Bought from vendors",
    training = "Training",
    auction = "Auction house",
    mail = "Postage",
    travel = "Flights",
    quest = "Quests",
    other = "Other",
}

-- Where the breakdown's switch sits, and where its lines start when open.
local BREAKDOWN_SWITCH = 8.75
local BREAKDOWN_START = 10

local tracker

-- When the panel was last let go of after a drag. The lines are buttons,
-- and letting go over one mustn't count as clicking it.
local droppedAt = 0
local DROP_GRACE = 0.3

local function JustDropped()
    return GetTime() - droppedAt < DROP_GRACE
end

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
    -- Too far off to measure, or measured from somewhere it can't be: the
    -- zone it's in will have to do.
    local map = spot.mapID and C_Map.GetMapInfo(spot.mapID)
    return map and map.name or ""
end

-- Building --------------------------------------------------------------------

-- How far down the panel a line sits. Lines are counted from 1, under
-- the title; halves leave a gap.
local function TopOf(index)
    return -(PADDING + 20 + (index - 1) * LINE_HEIGHT)
end

-- A line of the panel: what it is on the left, the figure on the right.
local function CreateLine(parent, index, label, font)
    local top = TopOf(index)

    local line = {}
    line.Label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
    line.Label:SetPoint("TOPLEFT", PADDING, top)
    line.Label:SetText(label)

    line.Figure = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    line.Figure:SetPoint("TOPRIGHT", -PADDING, top)
    line.Figure:SetJustifyH("RIGHT")
    return line
end

-- Moves a line to another place down the panel, for the breakdown, whose
-- lines come and go.
local function MoveLine(line, index)
    local top = TopOf(index)
    line.Label:ClearAllPoints()
    line.Label:SetPoint("TOPLEFT", PADDING, top)
    line.Figure:ClearAllPoints()
    line.Figure:SetPoint("TOPRIGHT", -PADDING, top)
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

-- The folded total has a narrow space to fit in, so once it's into gold
-- the copper is left off.
local function Rounded(copper)
    if math.abs(copper) >= 10000 then
        return math.floor(copper / 100 + 0.5) * 100
    end
    return copper
end

-- Kept by its top-left corner, so the panel grows downward from where
-- it was put when the breakdown opens.
local function SavePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        ns.settings.sessionTrackerPoint = { "TOPLEFT", "BOTTOMLEFT", left, top }
    end
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
                GameTooltip:AddDoubleLine(
                    place.label,
                    "not found yet",
                    1,
                    1,
                    1,
                    unpack(Theme.MUTED)
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
    return pin
end

-- The arrow beside the pin, to start the session again from now: before a
-- run, say, to see what that run alone brings in.
local function CreateResetButton(frame, beside)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(RESET_SIZE, RESET_SIZE)
    button:SetPoint("RIGHT", beside, "LEFT", -6, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("common-icon-undo")
    icon:SetAllPoints()

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAtlas("common-icon-undo")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.5)
    glow:SetAllPoints()

    button:SetScript("OnClick", function()
        ns.Session.Restart()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Start again")
        GameTooltip:AddLine(
            "Sets the session back to nothing from now, with your bags as they are. "
                .. "Handy before a run, to see what that run alone brings in.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- The button beside the reset arrow that folds the panel down to its
-- title line, with the session's total in it, and opens it out again.
local function CreateFoldButton(frame, beside)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(FOLD_SIZE, FOLD_SIZE)
    button:SetPoint("RIGHT", beside, "LEFT", -4, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.5)
    glow:SetAllPoints()

    function button:Update()
        local atlas = ns.settings.sessionTrackerFolded and "ui-questtrackerbutton-secondary-expand"
            or "ui-questtrackerbutton-secondary-collapse"
        icon:SetAtlas(atlas)
        glow:SetAtlas(atlas)
    end

    button:SetScript("OnClick", function()
        ns.settings.sessionTrackerFolded = not ns.settings.sessionTrackerFolded
        GameTooltip_Hide()
        frame:Refresh()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.settings.sessionTrackerFolded and "Open out" or "Fold to one line")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button:Update()
    return button
end

-- The panel's tooltip: the figures in full. opens is where a click on
-- the line being pointed at goes, if it's one of those.
local function ShowDetails(frame, opens)
    local summary = ns.Session.Summary()
    if not summary then
        return
    end

    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:SetText(("This session, %s"):format(Duration(summary.seconds)))
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
    if opens then
        GameTooltip:AddLine(("Click to open %s."):format(opens), 1, 0.82, 0, true)
    end
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

-- Where a click on a line of the panel goes. The session is this
-- character's, so these open on this character's figures.
local function OpenPurse()
    Theme.ShowOwnMoney()
    ns.ShowWindowTab("Purse")
end

local function OpenAssets()
    if ns.settings.allCharacters then
        ns.settings.allCharacters = false
        ns.Publish("SETTINGS_CHANGED")
    end
    ns.ShowWindowTab("List")
end

-- Lays a button over a line of the panel that calls onClick on a left
-- click. A drag still moves the panel, and a right-click still brings up
-- its menu. The panel's drag handlers are looked up at the time, as
-- they're set after the lines are made.
local function CoverLine(frame, line, onClick)
    -- On the body with the line, so it folds away with it.
    local button = CreateFrame("Button", nil, line.Label:GetParent())
    button:SetPoint("TOPLEFT", line.Label, "TOPLEFT", -4, 2)
    button:SetPoint("RIGHT", frame, "RIGHT", -PADDING + 4, 0)
    button:SetHeight(LINE_HEIGHT)

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0, 0.12)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        frame:GetScript("OnDragStart")(frame)
    end)
    button:SetScript("OnDragStop", function()
        frame:GetScript("OnDragStop")(frame)
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if JustDropped() then
            return
        end
        if mouseButton == "RightButton" then
            OpenMenu(frame)
        else
            onClick()
        end
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- Makes a line open where its figure comes from when clicked.
local function MakeClickable(frame, line, opens, open)
    local button = CoverLine(frame, line, open)
    button:SetScript("OnEnter", function()
        ShowDetails(frame, opens)
    end)
end

-- The breakdown ---------------------------------------------------------------

-- Makes the "Coin in and out" line open and close the breakdown under it.
local function CreateBreakdownSwitch(frame, line)
    local button = CoverLine(frame, line, function()
        ns.settings.sessionTrackerExpanded = not ns.settings.sessionTrackerExpanded
        frame:Refresh()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Coin in and out")
        GameTooltip:AddLine(
            ns.settings.sessionTrackerExpanded and "Click to fold the breakdown away."
                or "Click to see where this session's coin came from and went: loot, "
                    .. "quest rewards, vendors, the auction house, repairs and the rest.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

-- The breakdown's nth line, made the first time it's wanted.
local function BreakdownLine(frame, n)
    local line = frame.breakdown[n]
    if not line then
        line = CreateLine(frame.Body, BREAKDOWN_START, "", "GameFontHighlightSmall")
        frame.breakdown[n] = line
    end
    line.Label:Show()
    line.Figure:Show()
    return line
end

-- Fills one side of the breakdown: a heading with the side's total, then
-- a line for each kind of coin, the biggest first. Kinds without a name
-- of their own are put together as "Other".
---@return number index  the place down the panel after its last line
---@return number used   how many of the breakdown's lines are now in use
local function FillSide(frame, heading, amounts, labels, total, color, index, used)
    MoveLine(heading, index)
    heading.Label:Show()
    heading.Figure:Show()
    heading.Figure:SetText(Theme.Coins(total))
    heading.Figure:SetTextColor(unpack(color))
    index = index + 1

    local byLabel, order = {}, {}
    for category, amount in pairs(amounts) do
        if amount > 0 then
            local label = labels[category] or "Other"
            if not byLabel[label] then
                byLabel[label] = 0
                table.insert(order, label)
            end
            byLabel[label] = byLabel[label] + amount
        end
    end
    table.sort(order, function(a, b)
        return byLabel[a] > byLabel[b]
    end)

    if #order == 0 then
        used = used + 1
        local line = BreakdownLine(frame, used)
        MoveLine(line, index)
        line.Label:SetText("Nothing yet")
        line.Label:SetTextColor(unpack(Theme.MUTED))
        line.Figure:SetText("")
        return index + 1, used
    end

    for _, label in ipairs(order) do
        used = used + 1
        local line = BreakdownLine(frame, used)
        MoveLine(line, index)
        line.Label:SetText("   " .. label)
        line.Label:SetTextColor(1, 1, 1)
        line.Figure:SetText(Theme.Coins(byLabel[label]))
        line.Figure:SetTextColor(unpack(color))
        index = index + 1
    end
    return index, used
end

-- Shows the breakdown or folds it away, and sizes the panel to fit.
local function DrawBreakdown(frame, summary)
    local open = ns.settings.sessionTrackerExpanded
    frame.Switch.Figure:SetText(
        open and "|A:common-icon-minus:12:12|a" or "|A:common-icon-plus:12:12|a"
    )

    local last, used = BREAKDOWN_SWITCH, 0
    if open then
        local index
        index, used = FillSide(
            frame,
            frame.InHeading,
            summary.income or {},
            INCOME_LABELS,
            summary.earned,
            Theme.INCOME,
            BREAKDOWN_START,
            used
        )
        index, used = FillSide(
            frame,
            frame.OutHeading,
            summary.spending or {},
            SPENDING_LABELS,
            summary.spent,
            Theme.SPENDING,
            index + 0.5,
            used
        )
        last = index - 1
    else
        for _, heading in ipairs({ frame.InHeading, frame.OutHeading }) do
            heading.Label:Hide()
            heading.Figure:Hide()
        end
    end

    for n = used + 1, #frame.breakdown do
        frame.breakdown[n].Label:Hide()
        frame.breakdown[n].Figure:Hide()
    end

    -- Down to the bottom of the last line, and the padding under it.
    frame:SetHeight(-TopOf(last) + 12 + PADDING)
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

    frame.Fold = CreateFoldButton(frame, CreateResetButton(frame, CreatePlacesPin(frame)))

    -- Folded, the title line carries the session's total in place of the
    -- clock, between the title and the buttons.
    frame.Total = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Total:SetPoint("LEFT", frame.Title, "RIGHT", 8, 0)
    frame.Total:SetPoint("RIGHT", frame.Fold, "LEFT", -6, 0)
    frame.Total:SetJustifyH("LEFT")
    frame.Total:SetWordWrap(false)

    -- Everything under the title line, so folding can put it all away at once.
    frame.Body = CreateFrame("Frame", nil, frame)
    frame.Body:SetAllPoints()

    local body = frame.Body
    frame.Coin = CreateLine(body, 1, "Coin")
    frame.Goods = CreateLine(body, 2, "Change in bags")
    frame.Overall = CreateLine(body, 3, "Altogether", "GameFontNormal")
    frame.Overall.Figure:SetFontObject("GameFontHighlight")
    frame.Rate = CreateLine(body, 4, "An hour")
    frame.Bags = CreateLine(body, 5.5, "Bags worth")
    frame.Auction = CreateLine(body, 6.5, "   at auction", "GameFontDisableSmall")
    frame.Vendor = CreateLine(body, 7.5, "   to vendors", "GameFontDisableSmall")

    -- Each line opens where its figure comes from.
    for _, line in ipairs({ frame.Coin, frame.Overall, frame.Rate }) do
        MakeClickable(frame, line, "your purse", OpenPurse)
    end
    for _, line in ipairs({ frame.Goods, frame.Bags, frame.Auction, frame.Vendor }) do
        MakeClickable(frame, line, "this character's assets", OpenAssets)
    end

    -- The switch for the breakdown, and its two headings. The lines under
    -- them are made as they're needed.
    frame.Switch = CreateLine(body, BREAKDOWN_SWITCH, "Coin in and out")
    CreateBreakdownSwitch(frame, frame.Switch)
    frame.InHeading = CreateLine(body, BREAKDOWN_START, "COIN IN", "GameFontDisableSmall")
    frame.OutHeading = CreateLine(body, BREAKDOWN_START, "COIN OUT", "GameFontDisableSmall")
    frame.breakdown = {}

    frame:SetWidth(WIDTH)

    frame:SetScript("OnDragStart", function(self)
        if not ns.settings.sessionTrackerLocked then
            GameTooltip_Hide()
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        droppedAt = GetTime()
        SavePosition(self)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            OpenMenu(self)
        end
    end)
    -- Not ShowDetails itself: OnEnter's own second argument would be
    -- taken for where a click goes.
    frame:SetScript("OnEnter", function(self)
        ShowDetails(self)
    end)
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

        -- Until the bags have been valued, coin is all there is to go on.
        local overall = summary.overall or summary.coin

        local folded = ns.settings.sessionTrackerFolded
        self.Fold:Update()
        self.Body:SetShown(not folded)
        self.Clock:SetShown(not folded)
        self.Total:SetShown(folded)
        if folded then
            SetSigned({ Figure = self.Total }, Rounded(overall))
            self:SetHeight(FOLDED_HEIGHT)
            return
        end

        self.Clock:SetText(Duration(summary.seconds))
        SetSigned(self.Coin, summary.coin)
        SetSigned(self.Goods, summary.goods)
        SetSigned(self.Overall, overall)

        if summary.seconds >= RATE_AFTER_SECONDS then
            SetSigned(self.Rate, overall / summary.seconds * 3600)
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

        DrawBreakdown(self, summary)
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
