local _, ns = ...

-- A small card for the few times Goldwise speaks up unasked: a title, a
-- sentence or two, and one or two buttons.
--
-- There is only ever one. A new one replaces whatever was showing, and it
-- puts itself away after a while if ignored. It never takes focus, never
-- appears in combat, and makes no sound unless the player asked for one.

local Toast = {}
ns.Toast = Toast

local Theme = ns.Theme

local WIDTH = 360
local PADDING = 14

-- Seconds before an ignored card puts itself away.
local LINGER = 25

local card

-- Counts up with every card shown, so an old card's timer can tell it has
-- been replaced and leave the new one alone.
local shown = 0

local function Create()
    local frame = CreateFrame("Frame", nil, UIParent, "TooltipBorderedFrameTemplate")
    frame:SetSize(WIDTH, 1)
    frame:SetPoint("TOP", 0, -150)
    -- High enough to be seen, low enough to sit under real dialogs.
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- The text is given its width outright. The card's height is worked
    -- out from how the text wraps, and text that takes its width from
    -- anchors hasn't wrapped yet the first time we ask.
    local textWidth = WIDTH - 2 * PADDING

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
    frame.Title:SetPoint("TOPLEFT", PADDING, -PADDING)
    frame.Title:SetWidth(textWidth)
    frame.Title:SetJustifyH("LEFT")

    frame.Body = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Body:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -6)
    frame.Body:SetWidth(textWidth)
    frame.Body:SetJustifyH("LEFT")
    frame.Body:SetSpacing(3)

    frame.Primary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Primary:SetSize(120, 22)
    frame.Primary:SetPoint("BOTTOMLEFT", PADDING, PADDING - 2)

    frame.Secondary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Secondary:SetSize(120, 22)
    frame.Secondary:SetPoint("LEFT", frame.Primary, "RIGHT", 8, 0)

    return frame
end

local function WireButton(button, definition)
    button:SetShown(definition ~= nil)
    if not definition then
        return
    end

    button:SetText(definition.label)
    button:SetScript("OnClick", function()
        card:Hide()
        if definition.onClick then
            definition.onClick()
        end
    end)
end

--- Shows a card.
---@param options table with:
---   title      one line
---   body       a sentence or two; "\n" starts a new line
---   primary    { label, onClick } for the main button
---   secondary  { label, onClick } for the other button, optional
function Toast.Show(options)
    -- Nothing we have to say is worth a pop-up in the middle of a fight.
    if InCombatLockdown() then
        return
    end

    card = card or Create()
    card.Title:SetText(options.title)
    card.Title:SetTextColor(unpack(Theme.COIN))
    card.Body:SetText(options.body)

    WireButton(card.Primary, options.primary)
    WireButton(card.Secondary, options.secondary)

    -- Tall enough for however many lines the body wrapped to.
    card:SetHeight(
        PADDING + card.Title:GetStringHeight() + 6 + card.Body:GetStringHeight() + 14 + 22 + PADDING
    )
    card:Show()

    if ns.settings.promptSound then
        PlaySound(SOUNDKIT.MAP_PING)
    end

    shown = shown + 1
    local thisOne = shown
    C_Timer.After(LINGER, function()
        if shown == thisOne then
            card:Hide()
        end
    end)
end

--- Puts the card away, if one is showing.
function Toast.Hide()
    if card then
        card:Hide()
    end
end

-- A card about selling has no business hanging around once a fight starts.
ns.OnEvent("PLAYER_REGEN_DISABLED", Toast.Hide)
