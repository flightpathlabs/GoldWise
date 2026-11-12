local _, ns = ...

-- A small card for the few times Goldwise speaks up unasked: a title, a
-- sentence or two, the items it's talking about, and one or two buttons.
--
-- There is only ever one. A new one replaces whatever was showing, and it
-- puts itself away after a while if ignored. It never takes focus, never
-- appears in combat, and makes no sound unless the player asked for one.

local Toast = {}
ns.Toast = Toast

local Theme = ns.Theme

local WIDTH = 360
local PADDING = 14

-- Each item on a card gets a row this tall: its icon, with its name and a
-- line about it alongside.
local ROW_HEIGHT = 38
local ICON_SIZE = 32

-- More items than this and the card stops being something to take in at
-- a glance. The caller says where the rest can be found.
Toast.MAX_ITEMS = 4

-- Seconds before an ignored card puts itself away.
local LINGER = 25

local card

-- Counts up with every card shown, so an old card's timer can tell it has
-- been replaced and leave the new one alone.
local shown = 0

-- Building ------------------------------------------------------------------------

local function ShowItemTooltip(row)
    if row.link or row.itemID then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if row.link then
            GameTooltip:SetHyperlink(row.link)
        else
            GameTooltip:SetItemByID(row.itemID)
        end
        GameTooltip:Show()
    end
end

local function CreateItemRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 2 * PADDING, ROW_HEIGHT)

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.Icon:SetPoint("LEFT")

    -- How many, in the corner of the icon, the way a bag shows it.
    row.Count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.Count:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", -1, 2)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 10, -2)
    row.Name:SetPoint("RIGHT")
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -4)
    row.Detail:SetPoint("RIGHT")
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)

    row:SetScript("OnEnter", ShowItemTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

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

    frame.Rows = {}
    for index = 1, Toast.MAX_ITEMS do
        frame.Rows[index] = CreateItemRow(frame)
    end

    frame.Primary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Primary:SetSize(120, 22)
    frame.Primary:SetPoint("BOTTOMLEFT", PADDING, PADDING - 2)

    frame.Secondary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Secondary:SetSize(120, 22)
    frame.Secondary:SetPoint("LEFT", frame.Primary, "RIGHT", 8, 0)

    return frame
end

-- Filling in ------------------------------------------------------------------------

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

local function FillItemRow(row, item)
    row.itemID = item.itemID
    row.link = item.link

    row.Icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.Count:SetText(item.count and item.count > 1 and item.count or "")
    row.Name:SetText(Theme.ItemName(item.name, item.quality))
    row.Detail:SetText(item.detail or "")
end

--- Shows a card.
---@param options table with:
---   title      one line
---   body       a sentence or two, optional; "\n" starts a new line
---   items      up to Toast.MAX_ITEMS of { itemID, link, icon, name,
---              quality, count, detail }, shown as rows with their icons;
---              detail is the line under the name. Optional.
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

    -- Everything is stacked downward from the title, keeping count of how
    -- far down we've got.
    local height = PADDING + card.Title:GetStringHeight()

    card.Body:SetShown(options.body ~= nil)
    if options.body then
        card.Body:SetText(options.body)
        height = height + 6 + card.Body:GetStringHeight()
    end

    local items = options.items or {}
    if #items > 0 then
        height = height + 10
    end
    for index, row in ipairs(card.Rows) do
        local item = items[index]
        row:SetShown(item ~= nil)
        if item then
            FillItemRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PADDING, -height)
            height = height + ROW_HEIGHT
        end
    end

    WireButton(card.Primary, options.primary)
    WireButton(card.Secondary, options.secondary)

    card:SetHeight(height + 14 + 22 + PADDING)
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

--- Whether a card is up at the moment.
---@return boolean
function Toast.IsShowing()
    return card ~= nil and card:IsShown()
end

--- Puts the card away, if one is showing.
function Toast.Hide()
    if card then
        card:Hide()
    end
end

-- A card about selling has no business hanging around once a fight starts.
ns.OnEvent("PLAYER_REGEN_DISABLED", Toast.Hide)
