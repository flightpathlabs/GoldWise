local _, ns = ...

-- A strip on the bank window, while it's open, saying what's in it would
-- fetch: at auction and to vendors, counted the way Goldwise would sell
-- each thing, and how many things are worth listing.
--
-- Bag addons replace the bank window with their own, so the strip looks
-- for whichever bank window is showing rather than assuming Blizzard's.
-- It won't find one whose frames are named some other way, and then waits
-- at the top of the screen, out of the way.

local BankValue = {}
ns.BankValue = BankValue

local Theme = ns.Theme

local PADDING = 8
local HEIGHT = 22

-- Long enough for the bank to have been read (ProfileBank.lua waits half
-- a second for it to settle), and for a bag addon's window to appear.
local FIND_DELAY = 0.6

-- A frame smaller than this is a piece of a window, not the window.
local MIN_WINDOW_AREA = 40000

-- Bank windows that aren't the player's own bank.
local NOT_THIS_BANK = { "guild", "void", "reagent" }

local SEPARATOR = "   |cff7d7260·|r   "

local strip
local open = false

-- Whether the strip found a window to sit on, rather than the top of the
-- screen.
local onWindow = false

-- How big a frame is, if it's a bank window on screen; nil if not. Other
-- addons' frames can be ones this addon isn't allowed to look at, or
-- answer with values it can't use, so this is only ever asked through
-- pcall, and any complaint means "not this one".
local function WindowArea(frame)
    if frame == strip or frame:IsForbidden() or not frame:IsVisible() then
        return nil
    end
    local name = frame:GetName()
    if not name then
        return nil
    end
    name = name:lower()
    if not name:find("bank") then
        return nil
    end
    for _, word in ipairs(NOT_THIS_BANK) do
        if name:find(word) then
            return nil
        end
    end
    local area = (frame:GetWidth() or 0) * (frame:GetHeight() or 0)
    if area < MIN_WINDOW_AREA then
        return nil
    end
    return area
end

-- The bank window on screen: Blizzard's, or a bag addon's that has "bank"
-- in its name. Of those, the largest, which is the window rather than a
-- piece of one. Blizzard's counts only if it can be seen; a bag addon may
-- leave it open but invisible.
local function FindBankWindow()
    local ok, shown = pcall(function()
        return BankFrame and BankFrame:IsVisible() and BankFrame:GetEffectiveAlpha() > 0
    end)
    if ok and shown then
        return BankFrame
    end

    local best, bestArea
    local frame = EnumerateFrames()
    while frame do
        local fine, area = pcall(WindowArea, frame)
        if fine and area and (not bestArea or area > bestArea) then
            best, bestArea = frame, area
        end
        frame = EnumerateFrames(frame)
    end
    return best
end

local function Place()
    strip:ClearAllPoints()
    local window = FindBankWindow()
    onWindow = window ~= nil
    if window then
        strip:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, 2)
    else
        strip:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
end

-- What each bank would fetch, kept until what's in it changes or prices
-- or settings do. The bags change far more often than the bank, and each
-- change would otherwise mean assessing everything in both banks. Keyed
-- by bank: { contents, auction, vendor, listable }.
local valued = {}

-- A short summary of what's in a bank, which changes when anything in it
-- does. Far cheaper than valuing it.
local function Fingerprint(holdings)
    local kinds, total = 0, 0
    for _, holding in ipairs(holdings) do
        kinds = kinds + 1
        total = total + holding.itemID * holding.count
    end
    return kinds .. ":" .. total
end

-- What one bank would fetch, as "Your bank: 12g at auction, 3g to
-- vendors", and how many kinds of thing in it are worth listing. Nothing
-- for a bank with nothing in it to sell.
local function Line(label, holdings)
    if #holdings == 0 then
        return nil, 0
    end
    local contents = Fingerprint(holdings)
    local known = valued[label]
    if not known or known.contents ~= contents then
        local auction, vendor, _, listable = ns.Assets.SaleValue(holdings, ns.Market.Home())
        known = { contents = contents, auction = auction, vendor = vendor, listable = listable }
        valued[label] = known
    end
    local text = ("%s: %s at auction, %s to vendors"):format(
        label,
        Theme.Coins(known.auction),
        Theme.Coins(known.vendor)
    )
    return text, known.listable
end

local function Fill()
    -- The banks also say when they were last seen; only what's in them
    -- is wanted here.
    local own, ownListable = Line("Your bank", (ns.Bank.Holdings()))
    local shared, sharedListable = Line("Account bank", (ns.Bank.AccountHoldings()))

    local parts = {}
    table.insert(parts, own or "Nothing in your bank to sell")
    if shared then
        table.insert(parts, shared)
    end
    local listable = ownListable + sharedListable
    if listable > 0 then
        table.insert(parts, ("%d worth listing"):format(listable))
    end

    strip.Text:SetText(table.concat(parts, SEPARATOR))
    strip:SetWidth(strip.Label:GetStringWidth() + strip.Text:GetStringWidth() + 3 * PADDING)
end

local function Create()
    local frame = CreateFrame("Button", "GoldwiseBankValue", UIParent, "TooltipBackdropTemplate")
    frame:SetHeight(HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    frame.Label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.Label:SetPoint("LEFT", PADDING, 0)
    frame.Label:SetText("Goldwise")
    frame.Label:SetTextColor(unpack(Theme.COIN))

    frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Text:SetPoint("LEFT", frame.Label, "RIGHT", PADDING, 0)
    frame.Text:SetWordWrap(false)

    frame:SetScript("OnClick", function()
        ns.ShowWindowTab("List")
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("What your bank would fetch")
        GameTooltip:AddLine(
            "Each thing is counted the way Goldwise would sell it: at auction, less "
                .. "the cut, if it says sell or hold, and at a vendor's price if it says "
                .. "vendor or has no auction price yet. What you keep isn't counted. "
                .. "Click for Assets, where each thing in your bank has its own line.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    frame:Hide()
    return frame
end

local function ShowStrip()
    if not open or not ns.settings.bankValue then
        return
    end
    strip = strip or Create()
    Place()
    Fill()
    strip:Show()
end

ns.OnEvent("BANKFRAME_OPENED", function()
    open = true
    C_Timer.After(FIND_DELAY, ShowStrip)
end)

ns.OnEvent("BANKFRAME_CLOSED", function()
    open = false
    if strip then
        strip:Hide()
    end
end)

-- The bank is read again as things move in and out of it, and prices can
-- arrive while it's open. A bag addon's window that took its time to
-- appear is looked for again too.
local function Refresh()
    if strip and strip:IsShown() then
        if not onWindow then
            Place()
        end
        Fill()
    end
end
ns.Subscribe("BAGS_CHANGED", Refresh)

ns.Subscribe("PRICES_CHANGED", function()
    wipe(valued)
    Refresh()
end)

-- Marking something as kept, or switching to auditor mode, changes what
-- it would be sold for.
ns.Subscribe("SETTINGS_CHANGED", function()
    wipe(valued)
    if not ns.settings.bankValue then
        if strip then
            strip:Hide()
        end
    elseif strip and strip:IsShown() then
        Fill()
    else
        ShowStrip()
    end
end)
