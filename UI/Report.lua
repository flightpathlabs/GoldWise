local addonName, ns = ...

-- "Report a problem": a window with everything a bug report needs, ready
-- to copy.
--
-- The game can't open a web page or send anything anywhere, so the best
-- an addon can do is make the report easy to carry: gather the facts
-- that would otherwise take three messages back and forth to collect,
-- put them in a box, and say where to paste them.
--
-- What's gathered is about the addon and its surroundings, not the
-- player: no character names, no realm, no gold. It's shown in full
-- before anything is copied, so there are no surprises in it.

-- Where reports go.
local ISSUES_URL = "https://github.com/flightpathlabs/GoldWise/issues/new/choose"

local WIDTH, HEIGHT = 640, 480

-- Lines of the diagnostic log included. The newest are the useful ones.
local LOG_LINES = 80

-- Other addons whose presence changes what Goldwise does or shows.
local COMPANIONS = {
    "Auctionator",
    "TradeSkillMaster",
    "ForeverProfessions",
    "Bagnon",
    "BagBrother",
    "Questie",
    "WhatsTraining",
    "OpenMap",
    "Details",
}

-- Gathering the facts -----------------------------------------------------------------

local function Count(list)
    local count = 0
    for _ in pairs(list or {}) do
        count = count + 1
    end
    return count
end

-- Settings the player has changed, since the defaults are known.
local function ChangedSettings()
    local changed = {}
    for key, default in pairs(ns.DEFAULT_SETTINGS) do
        local value = ns.settings[key]
        if value ~= default then
            table.insert(changed, ("%s=%s"):format(key, tostring(value)))
        end
    end
    table.sort(changed)
    return #changed > 0 and table.concat(changed, ", ") or "none"
end

local function LoadedCompanions()
    local loaded = {}
    for _, name in ipairs(COMPANIONS) do
        if C_AddOns.IsAddOnLoaded(name) then
            local version = C_AddOns.GetAddOnMetadata(name, "Version")
            table.insert(loaded, version and ("%s %s"):format(name, version) or name)
        end
    end
    return #loaded > 0 and table.concat(loaded, ", ") or "none of the ones Goldwise works with"
end

local function Professions()
    local parts = {}
    for _, profession in ipairs(ns.Directory.PROFESSIONS) do
        local skill = ns.Professions.SkillByName(profession.name)
        if skill then
            table.insert(parts, ("%s %d"):format(profession.name, skill))
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- What Goldwise has learned so far, as counts. Enough to tell an empty
-- install from a well-used one.
local function DataSummary()
    local home = ns.Market.Home()
    local market = ns.MarketData(home)
    local lastScan = ns.Ledger.LastScan(home)
    local _, bankSeenAt = ns.Bank.Holdings()

    return table.concat({
        ("markets %d"):format(Count(ns.db.markets)),
        ("items followed %d"):format(Count(market.tracked)),
        ("days of prices %d"):format(ns.Ledger.DaysRecorded(home)),
        "last read " .. (lastScan and ns.Ago(GetServerTime() - lastScan) or "never"),
        "bank " .. (bankSeenAt and "seen" or "never opened"),
        ("recipes known %d"):format(#ns.Crafts.Known()),
        ("characters %d"):format(Count(ns.db.characters)),
    }, ", ")
end

local function ReportText()
    local version, build, _, interface = GetBuildInfo()
    local _, class = UnitClass("player")

    local lines = {
        "Goldwise " .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"),
        ("Game: %s (build %s, interface %s), %s"):format(
            version,
            build,
            tostring(interface),
            GetLocale()
        ),
        ("Character: level %d %s, %s"):format(UnitLevel("player"), class or "?", ns.Market.Home()),
        "Professions: " .. Professions(),
        "Settings changed: " .. ChangedSettings(),
        "Other addons: " .. LoadedCompanions(),
        "Learned so far: " .. DataSummary(),
        "",
    }

    local errors = ns.db.errors or {}
    if #errors == 0 then
        table.insert(lines, "Errors: none recorded")
    else
        table.insert(lines, "Errors, newest last:")
        for _, known in ipairs(errors) do
            table.insert(
                lines,
                ("  [%s, x%d, v%s] %s"):format(
                    known.at,
                    known.count,
                    tostring(known.version),
                    known.message
                )
            )
            for stackLine in (known.stack or ""):gmatch("[^\n]+") do
                table.insert(lines, "      " .. stackLine)
            end
        end
    end

    table.insert(lines, "")
    table.insert(lines, "Diagnostic log, newest last:")
    local log = ns.db.log or {}
    for index = math.max(1, #log - LOG_LINES + 1), #log do
        table.insert(lines, "  " .. log[index])
    end

    return table.concat(lines, "\n")
end

-- The window ------------------------------------------------------------------------------

local window

local function Create()
    local frame = CreateFrame("Frame", "GoldwiseReport", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetTitle("Report a problem")
    frame:SetPortraitTextureRaw(ns.Theme.PORTRAIT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    table.insert(UISpecialFrames, frame:GetName())

    local steps = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    steps:SetPoint("TOPLEFT", 66, -32)
    steps:SetPoint("RIGHT", -16, 0)
    steps:SetJustifyH("LEFT")
    steps:SetText("Press Ctrl+C to copy the report below, then paste it into a new report at:")

    -- The address, in a box of its own so it can be copied too.
    local address = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    address:SetSize(WIDTH - 110, 20)
    address:SetPoint("TOPLEFT", 72, -52)
    address:SetAutoFocus(false)
    address:SetText(ISSUES_URL)
    address:SetCursorPosition(0)
    -- It's there to be copied, not edited. Put back whatever is typed.
    address:SetScript("OnTextChanged", function(self, byPlayer)
        if byPlayer then
            self:SetText(ISSUES_URL)
            self:HighlightText()
        end
    end)
    address:SetScript("OnEditFocusGained", address.HighlightText)
    address:SetScript("OnEscapePressed", address.ClearFocus)

    local scroll = CreateFrame("ScrollFrame", nil, frame.Inset, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local report = CreateFrame("EditBox", nil, scroll)
    report:SetMultiLine(true)
    report:SetAutoFocus(false)
    report:SetFontObject("GameFontHighlightSmall")
    report:SetWidth(WIDTH - 60)
    report:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    scroll:SetScrollChild(report)
    frame.Report = report

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", 14, 10)
    note:SetTextColor(unpack(ns.Theme.MUTED))
    note:SetText("No character names, realm or gold are included. Read it before you send it.")

    local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAll:SetSize(110, 22)
    selectAll:SetPoint("BOTTOMRIGHT", -8, 4)
    selectAll:SetText("Select all")
    selectAll:SetScript("OnClick", function()
        report:SetFocus()
        report:HighlightText()
    end)

    return frame
end

--- Opens the report window with a fresh report, selected and ready to copy.
function ns.ShowReport()
    window = window or Create()

    local text = ReportText()
    window.Report:SetText(text)
    -- Typing in the box would spoil the report. Put it back if they do.
    window.Report:SetScript("OnTextChanged", function(self, byPlayer)
        if byPlayer then
            self:SetText(text)
            self:HighlightText()
        end
    end)

    window:Show()
    window.Report:SetFocus()
    window.Report:HighlightText()
end
