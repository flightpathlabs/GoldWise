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

-- How far down the header runs: two lines of instruction and the address.
local HEADER_HEIGHT = 92

local window

local function Create()
    local frame = CreateFrame("Frame", "GoldwiseReport", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetTitle("Goldwise: report a problem")
    -- No portrait: the header is all words, and they need the room.
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    table.insert(UISpecialFrames, frame:GetName())

    -- The panel the report sits in, below the header and above the buttons.
    frame.Inset:ClearAllPoints()
    frame.Inset:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT)
    frame.Inset:SetPoint("BOTTOMRIGHT", -8, 32)

    local first = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    first:SetPoint("TOPLEFT", 16, -30)
    first:SetText("1. Press Select all below, then Ctrl+C to copy the report.")

    local second = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -8)
    second:SetText("2. Paste it into a new report at this address:")

    -- The address, in a box of its own so it can be copied too.
    local address = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    address:SetSize(WIDTH - 48, 20)
    address:SetPoint("TOPLEFT", second, "BOTTOMLEFT", 6, -6)
    address:SetAutoFocus(false)
    address:SetText(ISSUES_URL)
    address:SetCursorPosition(0)
    -- It's there to be copied, not edited. Put back whatever is typed.
    address:HookScript("OnTextChanged", function(self, byPlayer)
        if byPlayer then
            self:SetText(ISSUES_URL)
            self:HighlightText()
        end
    end)

    -- Blizzard's own scrolling text box. It keeps the cursor in view and
    -- takes the keyboard when clicked, which a bare edit box doesn't.
    local scroll = CreateFrame("ScrollFrame", nil, frame.Inset, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    -- It's built for typing a short note, and counts the letters left.
    scroll.CharCount:Hide()

    local report = scroll.EditBox
    report:SetMaxLetters(0)
    report:SetFontObject("GameFontHighlightSmall")
    report:SetWidth(WIDTH - 16 - 10 - 28 - 18)
    report:SetAutoFocus(false)
    -- The report isn't for editing either.
    report:HookScript("OnTextChanged", function(self, byPlayer)
        if byPlayer and frame.text then
            self:SetText(frame.text)
        end
    end)
    report:HookScript("OnEscapePressed", function()
        frame:Hide()
    end)
    frame.Report = report

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("BOTTOMLEFT", 14, 11)
    note:SetTextColor(unpack(ns.Theme.MUTED))
    note:SetText("No character names, realm or gold are included. Read it before you send it.")

    local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAll:SetSize(110, 22)
    selectAll:SetPoint("BOTTOMRIGHT", -8, 5)
    selectAll:SetText("Select all")
    selectAll:SetScript("OnClick", function()
        report:SetFocus()
        report:HighlightText()
    end)

    return frame
end

--- Opens the report window with a fresh report.
function ns.ShowReport()
    window = window or Create()

    window.text = ReportText()
    window.Report:SetText(window.text)
    window.Report:SetCursorPosition(0)
    window.Report:ClearFocus()
    window:Show()
end
