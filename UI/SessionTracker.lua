local _, ns = ...

-- A small panel to keep on screen while playing: what this session has
-- brought in or cost, and what's in the bags at the prices Goldwise would
-- sell it for. The figures are worked out in Profile\Session.lua.
--
-- The total is coin alone: what was actually made. What the bags would
-- fetch is kept to a section of its own and called that, so a purchase
-- that sells for more at auction doesn't look like a gain. The cog on the
-- panel switches its sections on and off.
--
-- It's off until the player asks for it, from the button on the Goldwise
-- window's title bar or with /gw session. Drag it anywhere; right-click
-- for the rest.

local Theme = ns.Theme

local WIDTH = 240
local PADDING = 10
local PIN_SIZE = 18
local RESET_SIZE = 14
local FOLD_SIZE = 16
local OPTIONS_SIZE = 14

-- Where the body starts, under the title line.
local BODY_TOP = PADDING + 20
local ROW_HEIGHT = 16
-- A rule between sections, with the space around it.
local RULE_SPACE = 9
-- Room on the right of a bag line for how much it has changed.
local ASIDE_WIDTH = 80

-- Folded to its title line: the padding above and below, and a line of
-- text between.
local FOLDED_HEIGHT = 2 * PADDING + 14

-- How often the clock on it moves on, in seconds.
local TICK = 5

-- Before this long, an hourly rate is mostly noise, so the tooltip leaves
-- it out.
local RATE_AFTER_SECONDS = 10 * 60

-- The places the pin's tooltip names, the nearest of each kind.
local NEARBY = {
    { label = "Auction house", kind = "AUCTION" },
    { label = "Repairs", kind = "REPAIR" },
    { label = "Bank", kind = "BANK" },
    { label = "Flight master", kind = "FLIGHT" },
    { label = "Innkeeper", kind = "INN" },
}

-- The names for each kind of coin, by Purse.lua's categories. Anything not
-- here is shown as "Other".
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

local tracker

-- When the panel was last let go of after a drag. Most lines are buttons,
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

-- Money that can go either way, with a plus in front of a gain and the
-- colour of its side.
local function Signed(copper)
    -- Rounded first, so a fraction of a copper isn't shown as a gain of none.
    copper = math.floor(copper + 0.5)
    local text, color = Theme.SignedCoins(copper)
    if copper > 0 then
        text = "+" .. text
    end
    return text, color
end

-- Most figures have a narrow space to fit in, so once they're into gold
-- the copper is left off.
local function Rounded(copper)
    if math.abs(copper) >= 10000 then
        return math.floor(copper / 100 + 0.5) * 100
    end
    return copper
end

-- The figure the panel leads with, and what to call it: coin alone, unless
-- the player has asked for the bags' gains to be counted in.
local function Headline(summary)
    if ns.settings.sessionTrackerCountBags and summary.overall then
        return summary.overall, "Made, with bag gains"
    end
    return summary.coin, "Made this session"
end

-- Building --------------------------------------------------------------------

-- Kept by its top-left corner, so the panel grows downward from where it
-- was put as its sections come and go.
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

-- The cog at the left of the buttons: a quick menu of what the panel
-- shows.
local function CreateOptionsButton(frame, beside)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(OPTIONS_SIZE, OPTIONS_SIZE)
    button:SetPoint("RIGHT", beside, "LEFT", -4, 0)

    local cog = button:CreateTexture(nil, "ARTWORK")
    cog:SetAtlas("questlog-icon-setting")
    cog:SetAllPoints()

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAtlas("questlog-icon-setting")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)
    glow:SetAllPoints()

    local function Switch(key)
        return function()
            return ns.settings[key]
        end, function()
            ns.settings[key] = not ns.settings[key]
            frame:Refresh()
        end
    end

    button:SetScript("OnClick", function(self)
        GameTooltip_Hide()
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Show on the panel")
            root:CreateCheckbox("Coin in and out", Switch("sessionTrackerCoin"))
            root:CreateCheckbox("Your bags, if sold", Switch("sessionTrackerBags"))
            root:CreateDivider()
            root:CreateCheckbox("Count bag gains in the total", Switch("sessionTrackerCountBags"))
        end)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("What it shows")
        GameTooltip:AddLine(
            "Switch the panel's sections on and off, and choose whether your bags "
                .. "count towards the total.",
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

-- The panel's tooltip: the figures in full. opens is where a click on the
-- line being pointed at goes, if it's one of those.
local function ShowDetails(frame, opens)
    local summary = ns.Session.Summary()
    if not summary then
        return
    end

    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:SetText(("This session, %s"):format(Duration(summary.seconds)))
    GameTooltip:AddDoubleLine("Coin in", Theme.Coins(summary.earned), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Coin out", Theme.Coins(summary.spent), 1, 1, 1, 1, 1, 1)
    if summary.seconds >= RATE_AFTER_SECONDS then
        -- Kept to the tooltip and said in so many words: on the panel it
        -- read as a total.
        local headline = Headline(summary)
        local text, color = Theme.SignedCoins(headline / summary.seconds * 3600)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(
            "Per hour, at this pace",
            text,
            1,
            1,
            1,
            color[1],
            color[2],
            color[3]
        )
    end
    if summary.bags then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "Your bags are counted the way Goldwise would sell each thing: at "
                .. "auction, less the cut, if it says sell or hold, and at a vendor's "
                .. "price if it says vendor. What you keep isn't counted. None of it is "
                .. "in the total unless you ask for it with the cog.",
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
            "The figure beside each compares what you carry now with what you "
                .. "started with, both at today's prices. Putting things in the bank or "
                .. "posting them to another character counts as them leaving.",
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

-- Laying out the body ---------------------------------------------------------

-- The body is drawn top to bottom on every refresh, since what's in it
-- depends on the session and on which sections are switched on. Its rows
-- and rules are made the first time they're wanted and kept.

-- Each kind of row's fonts and label colour.
local KINDS = {
    total = { label = "GameFontNormal", figure = "GameFontHighlight", color = { 1, 0.82, 0 } },
    heading = {
        label = "GameFontNormalSmall",
        figure = "GameFontHighlightSmall",
        color = { 1, 0.82, 0 },
    },
    item = {
        label = "GameFontHighlightSmall",
        figure = "GameFontHighlightSmall",
        color = { 1, 1, 1 },
    },
    note = {
        label = "GameFontHighlightSmall",
        figure = "GameFontHighlightSmall",
        color = Theme.MUTED,
    },
}

local function NewRow(frame)
    local body = frame.Body
    local row = {}

    row.Label = body:CreateFontString(nil, "ARTWORK")
    row.Label:SetJustifyH("LEFT")
    row.Figure = body:CreateFontString(nil, "ARTWORK")
    row.Figure:SetJustifyH("RIGHT")
    row.Aside = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Aside:SetJustifyH("RIGHT")
    row.Aside:SetWidth(ASIDE_WIDTH)
    row.Aside:SetWordWrap(false)

    -- A button over the row for the lines that open somewhere. A drag
    -- still moves the panel and a right-click still brings up its menu;
    -- the panel's drag handlers are looked up at the time, as they're set
    -- after the body is made.
    local cover = CreateFrame("Button", nil, body)
    cover:SetPoint("TOPLEFT", row.Label, "TOPLEFT", -4, 2)
    cover:SetPoint("RIGHT", frame, "RIGHT", -PADDING + 4, 0)
    cover:SetHeight(ROW_HEIGHT)

    local glow = cover:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0, 0.12)

    cover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cover:RegisterForDrag("LeftButton")
    cover:SetScript("OnDragStart", function()
        frame:GetScript("OnDragStart")(frame)
    end)
    cover:SetScript("OnDragStop", function()
        frame:GetScript("OnDragStop")(frame)
    end)
    cover:SetScript("OnClick", function(self, mouseButton)
        if JustDropped() then
            return
        end
        if mouseButton == "RightButton" then
            OpenMenu(frame)
        elseif self.open then
            self.open()
        end
    end)
    cover:SetScript("OnEnter", function(self)
        ShowDetails(frame, self.opens)
    end)
    cover:SetScript("OnLeave", GameTooltip_Hide)
    row.Cover = cover

    return row
end

-- Puts a row at the next place down. spec is { kind, label, figure, color,
-- aside, asideColor, opens, open }: figure and aside are text, opens says
-- where a click goes, for the tooltip, and open goes there.
local function AddRow(layout, spec)
    local frame = layout.frame
    layout.rows = layout.rows + 1
    local row = frame.rows[layout.rows]
    if not row then
        row = NewRow(frame)
        frame.rows[layout.rows] = row
    end

    local kind = KINDS[spec.kind]
    local top = -layout.y
    row.Label:SetFontObject(kind.label)
    row.Label:SetTextColor(unpack(kind.color))
    row.Label:SetText(spec.kind == "item" and ("   " .. spec.label) or spec.label)
    row.Label:ClearAllPoints()
    row.Label:SetPoint("TOPLEFT", PADDING, top)

    row.Figure:SetFontObject(kind.figure)
    row.Figure:SetText(spec.figure or "")
    row.Figure:SetTextColor(unpack(spec.color or { 1, 1, 1 }))
    row.Figure:ClearAllPoints()
    if spec.aside then
        row.Aside:ClearAllPoints()
        row.Aside:SetPoint("TOPRIGHT", -PADDING, top)
        row.Aside:SetText(spec.aside)
        row.Aside:SetTextColor(unpack(spec.asideColor or Theme.MUTED))
        row.Figure:SetPoint("TOPRIGHT", -(PADDING + ASIDE_WIDTH + 4), top)
    else
        row.Figure:SetPoint("TOPRIGHT", -PADDING, top)
    end

    row.Label:Show()
    row.Figure:Show()
    row.Aside:SetShown(spec.aside ~= nil)
    row.Cover.open, row.Cover.opens = spec.open, spec.opens
    row.Cover:SetShown(spec.open ~= nil)

    layout.y = layout.y + ROW_HEIGHT
end

-- A faint line between sections.
local function AddRule(layout)
    local frame = layout.frame
    layout.rules = layout.rules + 1
    local rule = frame.ruleLines[layout.rules]
    if not rule then
        rule = frame.Body:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.12)
        rule:SetHeight(1)
        frame.ruleLines[layout.rules] = rule
    end

    local top = -(layout.y + math.floor(RULE_SPACE / 2) - 2)
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", PADDING, top)
    rule:SetPoint("TOPRIGHT", -PADDING, top)
    rule:Show()

    layout.y = layout.y + RULE_SPACE
end

-- Puts away whatever this refresh didn't use, and sizes the panel to fit.
local function FinishLayout(layout)
    local frame = layout.frame
    for n = layout.rows + 1, #frame.rows do
        local row = frame.rows[n]
        row.Label:Hide()
        row.Figure:Hide()
        row.Aside:Hide()
        row.Cover:Hide()
    end
    for n = layout.rules + 1, #frame.ruleLines do
        frame.ruleLines[n]:Hide()
    end
    -- The last row's text sits in the top of its slot.
    frame:SetHeight(layout.y + PADDING - 2)
end

-- One side of the coin: a heading with its total, then a line for each kind,
-- the biggest first. Kinds without a name of their own are put together as
-- "Other".
local function AddSide(layout, heading, amounts, labels, total, sign, color)
    AddRow(layout, {
        kind = "heading",
        label = heading,
        figure = Signed(sign * total),
        color = color,
        opens = "your purse",
        open = OpenPurse,
    })

    local byLabel, order = {}, {}
    for category, amount in pairs(amounts or {}) do
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
        AddRow(layout, { kind = "note", label = "   Nothing yet" })
        return
    end
    for _, label in ipairs(order) do
        AddRow(layout, {
            kind = "item",
            label = label,
            figure = Theme.Coins(byLabel[label]),
            color = color,
            opens = "your purse",
            open = OpenPurse,
        })
    end
end

-- What the bags would fetch each way, and how far that has moved since the
-- session began.
local function AddBags(layout, summary)
    AddRow(layout, { kind = "heading", label = "YOUR BAGS, IF SOLD" })
    if not summary.bags then
        AddRow(layout, { kind = "note", label = "   Valuing what you carry..." })
        return
    end

    for _, way in ipairs({
        { label = "At auction", worth = summary.auction, change = summary.auctionChange },
        { label = "To vendors", worth = summary.vendor, change = summary.vendorChange },
    }) do
        local change = Rounded(way.change)
        local aside, asideColor = "", nil
        if math.floor(change + 0.5) ~= 0 then
            aside, asideColor = Signed(change)
        end
        AddRow(layout, {
            kind = "item",
            label = way.label,
            figure = Theme.Coins(Rounded(way.worth)),
            aside = aside,
            asideColor = asideColor,
            opens = "this character's assets",
            open = OpenAssets,
        })
    end
end

local function Create()
    local frame =
        CreateFrame("Frame", "GoldwiseSessionTracker", UIParent, "TooltipBackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetWidth(WIDTH)
    PlacePanel(frame)

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Title:SetPoint("TOPLEFT", PADDING, -PADDING)
    frame.Title:SetText("Session")

    frame.Clock = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.Clock:SetPoint("LEFT", frame.Title, "RIGHT", 6, 0)

    -- From the right: the pin, the reset arrow, the fold button and the cog.
    frame.Fold = CreateFoldButton(frame, CreateResetButton(frame, CreatePlacesPin(frame)))
    frame.Options = CreateOptionsButton(frame, frame.Fold)

    -- Folded, the title line carries the session's total in place of the
    -- clock, between the title and the buttons.
    frame.Total = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Total:SetPoint("LEFT", frame.Title, "RIGHT", 8, 0)
    frame.Total:SetPoint("RIGHT", frame.Options, "LEFT", -6, 0)
    frame.Total:SetJustifyH("LEFT")
    frame.Total:SetWordWrap(false)

    -- Everything under the title line, so folding can put it all away at
    -- once.
    frame.Body = CreateFrame("Frame", nil, frame)
    frame.Body:SetAllPoints()
    frame.rows, frame.ruleLines = {}, {}

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
    -- Not ShowDetails itself: OnEnter's own second argument would be taken
    -- for where a click goes.
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

        local headline, headlineLabel = Headline(summary)

        local folded = ns.settings.sessionTrackerFolded
        self.Fold:Update()
        self.Body:SetShown(not folded)
        self.Clock:SetShown(not folded)
        self.Total:SetShown(folded)
        if folded then
            local text, color = Signed(Rounded(headline))
            self.Total:SetText(text)
            self.Total:SetTextColor(unpack(color))
            self:SetHeight(FOLDED_HEIGHT)
            return
        end

        self.Clock:SetText(Duration(summary.seconds))

        local layout = { frame = self, y = BODY_TOP, rows = 0, rules = 0 }
        -- Rounded like the folded line, so a big figure stays clear of its label.
        local text, color = Signed(Rounded(headline))
        AddRow(layout, {
            kind = "total",
            label = headlineLabel,
            figure = text,
            color = color,
            opens = "your purse",
            open = OpenPurse,
        })
        if ns.settings.sessionTrackerCoin then
            AddRule(layout)
            AddSide(
                layout,
                "COIN IN",
                summary.income,
                INCOME_LABELS,
                summary.earned,
                1,
                Theme.INCOME
            )
            AddSide(
                layout,
                "COIN OUT",
                summary.spending,
                SPENDING_LABELS,
                summary.spent,
                -1,
                Theme.SPENDING
            )
        end
        if ns.settings.sessionTrackerBags then
            AddRule(layout)
            AddBags(layout, summary)
        end
        FinishLayout(layout)
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
