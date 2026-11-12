local _, ns = ...

-- A small panel that sits on top of the auction house window and says
-- what Goldwise is doing there: reading prices, how far it's got, and
-- what it found. Without it the reading happens out of sight, and the
-- player has no way to tell it worked short of opening our window.
--
-- It rests on the window's top edge, to the left. Other addons that do
-- the same tend to take the right-hand end, so the two don't collide.
-- Clicking it opens Goldwise.

local Theme = ns.Theme

local WIDTH, HEIGHT = 300, 60

-- How far in from the window's left edge, to clear its round portrait.
local LEFT_OFFSET = 62

-- Seconds each kind of message stays up once there's nothing more to say.
local LINGER_ON_ARRIVAL = 6
local LINGER_ON_RESULT = 12

local panel

-- Counts up with every message, so an old message's timer can tell it has
-- been replaced and leave the new one alone.
local shown = 0

local function Create()
    local frame = CreateFrame("Button", nil, AuctionHouseFrame, "TooltipBorderedFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "TOPLEFT", LEFT_OFFSET, 0)
    frame:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 5)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 12, 0)
    icon:SetTexture(Theme.ICON)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
    title:SetText("Goldwise")
    title:SetTextColor(unpack(Theme.COIN))

    frame.Status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    frame.Status:SetWidth(WIDTH - 12 - 32 - 10 - 12)
    frame.Status:SetJustifyH("LEFT")
    frame.Status:SetWordWrap(false)

    -- Only the fuller read knows how much there is to get through, so the
    -- bar only appears for that one.
    frame.Bar = CreateFrame("StatusBar", nil, frame)
    frame.Bar:SetHeight(6)
    frame.Bar:SetPoint("TOPLEFT", frame.Status, "BOTTOMLEFT", 0, -5)
    frame.Bar:SetPoint("RIGHT", -12, 0)
    frame.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.Bar:SetStatusBarColor(unpack(Theme.COIN))
    frame.Bar:SetMinMaxValues(0, 1)

    local trough = frame.Bar:CreateTexture(nil, "BACKGROUND")
    trough:SetAllPoints()
    trough:SetColorTexture(0, 0, 0, 0.5)

    frame:SetScript("OnClick", function()
        ns.ShowWindow()
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Click to open Goldwise.", 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    return frame
end

local function Hide()
    if panel then
        panel:Hide()
    end
end

-- Shows a message. `fraction` fills the bar, from 0 to 1, or hides it when
-- nil. `linger` puts the panel away after that many seconds; without it
-- the message stays until the next one.
local function Say(text, fraction, linger)
    -- The window belongs to Blizzard's auction house addon, which loads
    -- the first time the player visits one.
    if not ns.settings.scanPanel or not AuctionHouseFrame then
        Hide()
        return
    end

    panel = panel or Create()
    panel.Status:SetText(text)
    panel.Bar:SetShown(fraction ~= nil)
    panel.Bar:SetValue(fraction or 0)
    panel:Show()

    shown = shown + 1
    local thisOne = shown
    if linger then
        C_Timer.After(linger, function()
            if shown == thisOne then
                Hide()
            end
        end)
    end
end

-- What to say and when ---------------------------------------------------------------

-- Progress is progress whoever reports it. If another addon has its own
-- panel up counting through the same auctions, ours keeps quiet until
-- there's something only Goldwise can say: what was found, and what the
-- player's bags are worth.
local function Report(text, fraction, linger)
    if ns.Companions.ShowsScanProgress() then
        Hide()
    else
        Say(text, fraction, linger)
    end
end

-- On arrival, before any reading starts: how fresh the prices already are.
-- If Goldwise decides they're fresh enough to skip reading, this is all
-- the player sees, and it tells them why nothing else happened.
ns.Subscribe("AUCTION_HOUSE_OPENED", function(marketKey)
    local lastScan = ns.Ledger.LastScan(marketKey)
    if lastScan then
        Report("Prices read " .. ns.Ago(GetServerTime() - lastScan) .. ".", nil, LINGER_ON_ARRIVAL)
    else
        Report("No prices read here yet.", nil, LINGER_ON_ARRIVAL)
    end
end)

ns.Subscribe("SCAN_STARTED", function()
    Report("Reading prices...")
end)

ns.Subscribe("SCAN_PROGRESS", function(done, total)
    if total and total > 0 then
        Report(
            ("Reading every auction: %s of %s"):format(
                FormatLargeNumber(done),
                FormatLargeNumber(total)
            ),
            done / total
        )
    else
        Report(("Reading prices: %s items so far"):format(FormatLargeNumber(done)))
    end
end)

-- The result, and the one thing it means for the player right now.
ns.Subscribe("SCAN_FINISHED", function(items, _, borrowed)
    local text = ("%s prices read."):format(FormatLargeNumber(items or 0))
    if borrowed then
        -- Another addon did the asking and we read its answer. Worth
        -- saying, or the player may wonder why ours never seemed to run.
        text = ("%s prices read, alongside another addon."):format(FormatLargeNumber(items or 0))
    end

    local _, sellable = ns.Assets.InBags(ns.Market.Current())
    if sellable > 0 then
        text = text .. (" Your bags: about %s to sell."):format(Theme.Coins(sellable))
    end

    Say(text, nil, LINGER_ON_RESULT)
end)

ns.Subscribe("SCAN_STOPPED", function(reason)
    Report(reason or "Stopped reading prices.", nil, LINGER_ON_RESULT)
end)

ns.Subscribe("AUCTION_HOUSE_CLOSED", Hide)

ns.Subscribe("SETTINGS_CHANGED", function()
    if not ns.settings.scanPanel then
        Hide()
    end
end)
