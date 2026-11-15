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

-- The X on a row that can be dismissed, and the pin on one with a place
-- to show on the map.
local DISMISS_SIZE = 16
local PIN_SIZE = 20

-- A heading over a group of rows, and the room it takes.
local HEADING_HEIGHT = 18

-- More items than this and the card stops being something to take in at
-- a glance. The caller says where the rest can be found.
Toast.MAX_ITEMS = 4

-- Seconds before an ignored card puts itself away, for those who'd like
-- cards to, and to look again when it's due to go but the mouse is on it.
-- Otherwise a card stays until it's closed.
local LINGER = 25
local LINGER_MORE = 3

local card

-- Counts up with every card shown, so an old card's timer can tell it has
-- been replaced and leave the new one alone.
local shown = 0

-- Building --------------------------------------------------------------------

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

    -- A map pin, for a row with somewhere to show: the vendor who sells
    -- it, say. Each row has its own, since each can be somewhere else.
    row.Pin = CreateFrame("Button", nil, row)
    row.Pin:SetSize(PIN_SIZE, PIN_SIZE)

    row.Pin.Icon = row.Pin:CreateTexture(nil, "ARTWORK")
    row.Pin.Icon:SetAtlas("Waypoint-MapPin-Untracked")
    row.Pin.Icon:SetAllPoints()
    row.Pin.Icon:SetAlpha(0.8)

    row.Pin:SetScript("OnEnter", function(button)
        button.Icon:SetAlpha(1)
        if row.mapTip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.mapTip[1])
            for index = 2, #row.mapTip do
                GameTooltip:AddLine(row.mapTip[index], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    row.Pin:SetScript("OnLeave", function(button)
        button.Icon:SetAlpha(0.8)
        GameTooltip_Hide()
    end)
    row.Pin:SetScript("OnClick", function()
        GameTooltip_Hide()
        if row.onMap then
            row.onMap()
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
    frame.Headings = {}
    for index = 1, Toast.MAX_ITEMS do
        frame.Rows[index] = CreateItemRow(frame)
        local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        heading:SetJustifyH("LEFT")
        heading:SetWidth(textWidth)
        heading:SetTextColor(unpack(Theme.COIN))
        frame.Headings[index] = heading
    end

    frame.Primary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Primary:SetSize(120, 22)
    frame.Primary:SetPoint("BOTTOMLEFT", PADDING, PADDING - 2)

    frame.Secondary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Secondary:SetSize(120, 22)
    frame.Secondary:SetPoint("LEFT", frame.Primary, "RIGHT", 8, 0)

    -- A quiet way out, in grey at the bottom right: "Don't show again".
    frame.Quiet = CreateFrame("Button", nil, frame)
    frame.Quiet:SetPoint("BOTTOMRIGHT", -PADDING, PADDING + 3)
    frame.Quiet.Text = frame.Quiet:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.Quiet.Text:SetPoint("RIGHT")
    frame.Quiet:SetScript("OnEnter", function(self)
        self.Text:SetTextColor(1, 1, 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip[1])
            for index = 2, #self.tip do
                GameTooltip:AddLine(self.tip[index], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    frame.Quiet:SetScript("OnLeave", function(self)
        self.Text:SetTextColor(0.5, 0.5, 0.5)
        GameTooltip_Hide()
    end)

    return frame
end

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

-- Filling in ------------------------------------------------------------------

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
    row.onMap = item.onMap
    row.mapTip = item.mapTip

    row.Icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.Count:SetText(item.count and item.count > 1 and item.count or "")
    row.Name:SetText(Theme.ItemName(item.name, item.quality))
    row.Detail:SetText(item.detail or "")

    -- The X sits at the right edge and the pin before it, each only when
    -- the row has one. The text runs up to whichever comes first.
    local dismissable = item.onDismiss ~= nil
    row.Dismiss:SetShown(dismissable)
    row.Dismiss.Icon:SetAlpha(0.5)
    local edge, edgePoint, offset = row, "RIGHT", 0
    if dismissable then
        edge, edgePoint, offset = row.Dismiss, "LEFT", -4
    end

    local pinned = item.onMap ~= nil
    row.Pin:SetShown(pinned)
    if pinned then
        row.Pin:ClearAllPoints()
        row.Pin:SetPoint("RIGHT", edge, edgePoint, offset, 0)
        edge, edgePoint, offset = row.Pin, "LEFT", -4
    end
    row.Name:SetPoint("RIGHT", edge, edgePoint, offset, 0)
    row.Detail:SetPoint("RIGHT", edge, edgePoint, offset, 0)
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
        local heading = card.Headings[index]
        heading:SetShown(item ~= nil and item.heading ~= nil)
        if item and item.heading then
            -- A little air above every heading but the first.
            if index > 1 then
                height = height + 4
            end
            heading:SetText(item.heading)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", PADDING, -height)
            height = height + HEADING_HEIGHT
        end

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

    local quiet = options.quiet
    card.Quiet:SetShown(quiet ~= nil)
    if quiet then
        card.Quiet.Text:SetText(quiet.label)
        card.Quiet.Text:SetTextColor(0.5, 0.5, 0.5)
        card.Quiet:SetSize(card.Quiet.Text:GetStringWidth(), 16)
        card.Quiet.tip = quiet.tip
        card.Quiet:SetScript("OnClick", function()
            GameTooltip_Hide()
            card:Hide()
            if quiet.onClick then
                quiet.onClick()
            end
        end)
    end

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
---              dismissTip ({ title, line, ... }) is the X's tooltip. A
---              row with onMap gets a map pin that calls it, with mapTip
---              as its tooltip in the same shape. A row with heading
---              starts a section, with that heading over it. Optional.
---   primary    { label, onClick, keepOpen } for the main button; the card
---              closes when it's clicked unless keepOpen is set
---   secondary  the same for the other button, optional
---   quiet      { label, onClick, tip } for a small grey link at the
---              bottom right, such as "Don't show again"; the card closes
---              when it's clicked. Optional.
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
    if ns.settings.cardsPutAway then
        PutAwayLater(shown, LINGER)
    end
    return shown
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
    -- It's not one of the cards that put themselves away. Counting it
    -- stops the timer of the card it replaces, and it's given none.
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
