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

-- The X on a row that can be dismissed.
local DISMISS_SIZE = 16

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

-- Where the card goes. The player can drag it anywhere; it's kept by its
-- top edge, so a taller card grows downward from where they put it.
local function PlaceCard(frame)
    frame:ClearAllPoints()
    local saved = ns.settings.toastPoint
    if type(saved) == "table" and saved.x and saved.top then
        frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", saved.x, saved.top)
    else
        frame:SetPoint("TOP", 0, -150)
    end
end

local function SavePlace(frame)
    local left, top, width = frame:GetLeft(), frame:GetTop(), frame:GetWidth()
    if left and top then
        ns.settings.toastPoint = { x = left + width / 2, top = top }
    end
end

-- Dragging works from anywhere on the card that isn't a button: the
-- rows pass a drag on to it.
local function StartDrag()
    card.dragging = true
    GameTooltip_Hide()
    card:StartMoving()
end

local function StopDrag()
    card:StopMovingOrSizing()
    card.dragging = false
    SavePlace(card)
    PlaceCard(card)
end
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
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", StartDrag)
    row:SetScript("OnDragStop", StopDrag)

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.Icon:SetPoint("LEFT")

    -- How many, in the corner of the icon, the way a bag shows it.
    row.Count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.Count:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", -1, 2)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 10, -2)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -4)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)

    -- The small circled X the game puts in its search boxes, for a row the
    -- player can wave away. Faint until the mouse finds it.
    row.Dismiss = CreateFrame("Button", nil, row)
    row.Dismiss:SetSize(DISMISS_SIZE, DISMISS_SIZE)
    row.Dismiss:SetPoint("RIGHT")

    row.Dismiss.Icon = row.Dismiss:CreateTexture(nil, "ARTWORK")
    row.Dismiss.Icon:SetAtlas("common-search-clearbutton")
    row.Dismiss.Icon:SetSize(DISMISS_SIZE - 4, DISMISS_SIZE - 4)
    row.Dismiss.Icon:SetPoint("CENTER")
    row.Dismiss.Icon:SetAlpha(0.5)

    row.Dismiss:SetScript("OnEnter", function(button)
        button.Icon:SetAlpha(1)
        if row.dismissTip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.dismissTip[1])
            for index = 2, #row.dismissTip do
                GameTooltip:AddLine(row.dismissTip[index], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    row.Dismiss:SetScript("OnLeave", function(button)
        button.Icon:SetAlpha(0.5)
        GameTooltip_Hide()
    end)
    row.Dismiss:SetScript("OnClick", function()
        GameTooltip_Hide()
        if row.onDismiss then
            row.onDismiss()
        end
    end)

    row:SetScript("OnEnter", ShowItemTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

local function Create()
    local frame = CreateFrame("Frame", nil, UIParent, "TooltipBorderedFrameTemplate")
    frame:SetSize(WIDTH, 1)
    PlaceCard(frame)
    -- High enough to be seen, low enough to sit under real dialogs.
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
    -- A card can be put away mid-drag, when a fight starts. Let go of it
    -- properly, or it would be thought to be held for good.
    frame:SetScript("OnHide", function(self)
        if self.dragging then
            StopDrag()
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle("Goldwise's cards")
                root:CreateButton("Put it back where it was", function()
                    Toast.ResetPlace()
                end)
                root:CreateButton("Close", function()
                    self:Hide()
                end)
            end)
        end
    end)

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

-- Seconds to look again when a card is due to go but the mouse is on it.
local LINGER_MORE = 3

-- Puts a card away after a while, unless it's been replaced. Not while
-- the player is pointing at it or dragging it, though: that's someone
-- reading it, or putting it where they want it.
local function PutAwayLater(which, seconds)
    C_Timer.After(seconds, function()
        if shown ~= which or not card:IsShown() then
            return
        end
        if card.dragging or card:IsMouseOver() then
            PutAwayLater(which, LINGER_MORE)
            return
        end
        card:Hide()
    end)
end

-- Filling in ------------------------------------------------------------------------

local function WireButton(button, definition)
    button:SetShown(definition ~= nil)
    if not definition then
        return
    end

    button:SetText(definition.label)
    button:SetScript("OnClick", function()
        if not definition.keepOpen then
            card:Hide()
        end
        if definition.onClick then
            definition.onClick()
        end
    end)
end

local function FillItemRow(row, item)
    row.itemID = item.itemID
    row.link = item.link
    row.onDismiss = item.onDismiss
    row.dismissTip = item.dismissTip

    row.Icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.Count:SetText(item.count and item.count > 1 and item.count or "")
    row.Name:SetText(Theme.ItemName(item.name, item.quality))
    row.Detail:SetText(item.detail or "")

    -- The text runs up to the X when there is one, and to the edge when
    -- there isn't.
    local dismissable = item.onDismiss ~= nil
    row.Dismiss:SetShown(dismissable)
    row.Dismiss.Icon:SetAlpha(0.5)
    local edge, offset = row, 0
    if dismissable then
        edge, offset = row.Dismiss, -4
    end
    row.Name:SetPoint("RIGHT", edge, dismissable and "LEFT" or "RIGHT", offset, 0)
    row.Detail:SetPoint("RIGHT", edge, dismissable and "LEFT" or "RIGHT", offset, 0)
end

-- Puts what a card says into it, and sizes it to fit.
local function Fill(options)
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
end

--- Shows a card.
---@param options table with:
---   title      one line
---   body       a sentence or two, optional; "\n" starts a new line
---   items      up to Toast.MAX_ITEMS of { itemID, link, icon, name,
---              quality, count, detail, onDismiss, dismissTip }, shown as
---              rows with their icons; detail is the line under the name.
---              A row with onDismiss gets a small X that calls it, and
---              dismissTip ({ title, line, ... }) is the X's tooltip.
---              Optional.
---   primary    { label, onClick, keepOpen } for the main button; the card
---              closes when it's clicked unless keepOpen is set
---   secondary  { label, onClick } for the other button, optional
---@return number|nil card  for Toast.Update; nil if nothing was shown
function Toast.Show(options)
    -- Nothing we have to say is worth a pop-up in the middle of a fight.
    if InCombatLockdown() then
        return nil
    end

    card = card or Create()
    Fill(options)
    card:Show()

    if ns.settings.promptSound then
        PlaySound(SOUNDKIT.MAP_PING)
    end

    shown = shown + 1
    local thisOne = shown
    PutAwayLater(thisOne, LINGER)
    return thisOne
end

--- Shows a card that's only there to be moved, for the options page:
--- it stays until it's closed, and says where the others will go.
function Toast.ShowSample()
    if InCombatLockdown() then
        return
    end
    card = card or Create()
    Fill({
        title = "Goldwise's cards go here",
        body = "Drag this card to wherever you'd like Goldwise to put its "
            .. "suggestions, like a recipe for sale nearby. Right-click it to put "
            .. "it back where it started.",
        primary = { label = "Done" },
        secondary = {
            label = "Put it back",
            -- So the player sees where it went.
            keepOpen = true,
            onClick = function()
                Toast.ResetPlace()
            end,
        },
    })
    -- It's not one of the cards that put themselves away.
    shown = shown + 1
    card:Show()
end

--- Puts the card back where it first appeared, at the top of the screen.
function Toast.ResetPlace()
    ns.settings.toastPoint = nil
    if card then
        PlaceCard(card)
    end
end

--- Redraws a card that's still up with new contents, as when one of its
--- rows has been dismissed or a name has arrived. Quietly, and without
--- giving it any longer to linger. Does nothing if that card has gone or
--- been replaced.
---@param which number  what Toast.Show returned
---@param options table  as for Toast.Show
function Toast.Update(which, options)
    if which == shown and Toast.IsShowing() then
        Fill(options)
    end
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
