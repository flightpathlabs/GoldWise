local _, ns = ...

-- Colours and small display helpers shared by every part of the interface.
--
-- Wherever the game has its own answer (item quality colours, coin icons,
-- fonts, frame art) we use that. These are only for the things it doesn't
-- cover.

local Theme = {}
ns.Theme = Theme

-- Each colour is { red, green, blue } from 0 to 1, ready for unpack().
Theme.COIN = { 0.88, 0.70, 0.24 }
Theme.MUTED = { 0.79, 0.73, 0.61 }

-- Charts. They sit on the game's dark panels, so they're drawn the way
-- the panels are: a dark wash for a background and light strokes on it,
-- with gold for the line that matters.
--
-- The wash is black at CHART_WASH opacity, the same as the tiles on the
-- Purse tab, so a chart reads as part of the panel it's on. The one under
-- a tooltip floats over the game world with nothing behind it, and gets
-- a solid colour instead.
Theme.CHART_WASH = 0.35
Theme.CHART_FLOATING = { 0.05, 0.05, 0.06 }
Theme.CHART_LINE = Theme.COIN
Theme.CHART_USUAL = { 0.62, 0.74, 0.88 } -- the level a price usually sits at
Theme.CHART_NEWEST = { 1.00, 0.95, 0.80 } -- the dot on the latest price
Theme.INCOME = { 0.49, 0.84, 0.42 }
Theme.SPENDING = { 0.86, 0.38, 0.30 }

-- One colour per verdict. They differ in brightness as well as hue, and
-- every one is shown next to its word, so nothing depends on telling red
-- from green.
Theme.VERB_COLORS = {
    sell = { 0.49, 0.84, 0.42 },
    hold = { 0.90, 0.78, 0.42 },
    vendor = { 0.82, 0.76, 0.64 },
    keep = { 0.62, 0.74, 0.88 },
    unknown = { 0.60, 0.60, 0.60 },
}

Theme.VERB_LABELS = {
    sell = "Sell",
    hold = "Hold",
    vendor = "Vendor",
    keep = "Keep",
    unknown = "No price",
}

Theme.PORTRAIT = "Interface\\AddOns\\Goldwise\\Media\\portrait"
Theme.ICON = "Interface\\AddOns\\Goldwise\\Media\\icon"

-- The whole picture: the goblin mid-audit, and the adventurer on the
-- receiving end of it.
Theme.SCENE = "Interface\\AddOns\\Goldwise\\Media\\scene"

--- Wraps an item's name in its quality colour, the way the game does.
---@param name string
---@param quality number|nil  Enum.ItemQuality
---@return string
function Theme.ItemName(name, quality)
    local colors = quality and ColorManager.GetColorDataForItemQuality(quality)
    if colors then
        return colors.color:WrapTextInColorCode(name)
    end
    return name
end

--- How many of something are for sale, in words.
---@param quantity number|nil
---@return string  e.g. "8,853 listed", "none listed"
function Theme.Listed(quantity)
    -- A price from somewhere that doesn't say how many were up.
    if quantity == nil then
        return "listings not counted"
    elseif quantity == 0 then
        return "none listed"
    end
    return FormatLargeNumber(quantity) .. " listed"
end

--- Wraps text in a colour.
---@param text string
---@param color table  { red, green, blue }, each from 0 to 1
---@return string
function Theme.Tint(text, color)
    -- Colours are kept as fractions and written as whole numbers.
    local function Channel(index)
        return math.floor(color[index] * 255 + 0.5)
    end
    return ("|cff%02x%02x%02x%s|r"):format(Channel(1), Channel(2), Channel(3), text)
end

--- Sets a few words apart from the name they follow: a count, where the
--- thing is, whose it is. Quieter than Theme.MUTED, which is for whole
--- lines.
---@param text string
---@return string
function Theme.Aside(text)
    return "|cffb9aa8c" .. text .. "|r"
end

--- A sum that can be below nothing, with the colour of the side it's on:
--- what came in, or what went out.
---@param copper number
---@return string text  with the game's coin icons, and a minus sign for
---        a loss
---@return table color  Theme.INCOME or Theme.SPENDING
function Theme.SignedCoins(copper)
    -- Rounded first, so a fraction of a copper under nothing isn't
    -- written as a loss of none.
    copper = math.floor(copper + 0.5)
    if copper < 0 then
        return "-" .. Theme.Coins(-copper), Theme.SPENDING
    end
    return Theme.Coins(copper), Theme.INCOME
end

--- Creates one of the boxes the money tabs put across the top: a label,
--- a figure and a footnote.
---@param parent table  frame
---@param label string  what the figure is, shown small and in capitals
---@return table tile   with .Figure and .Note, both font strings
function Theme.CreateTile(parent, label)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(240, 66)

    local background = tile:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.35)

    local caption = tile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    caption:SetPoint("TOPLEFT", 10, -8)
    caption:SetText(label:upper())

    tile.Figure = tile:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    tile.Figure:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -5)

    tile.Note = tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tile.Note:SetPoint("TOPLEFT", tile.Figure, "BOTTOMLEFT", 0, -4)
    tile.Note:SetPoint("RIGHT", -8, 0)
    tile.Note:SetJustifyH("LEFT")
    tile.Note:SetWordWrap(false)
    tile.Note:SetTextColor(unpack(Theme.MUTED))

    return tile
end

--- Whose money the Purse and Profit tabs are showing, in words for a
--- heading: "Alia" or "your characters".
---@return string
function Theme.MoneyOwner()
    if ns.settings.moneyAccountWide then
        return "your characters"
    end
    return UnitName("player") or "this character"
end

--- Creates the button the money tabs share for choosing whose money they
--- show: this character's, which is where they start, or the whole
--- account's. The choice is one setting, so switching on one tab switches
--- both.
---@param parent table  frame
---@return table button  with :Update(), to bring its text up to date
function Theme.CreateMoneyScopeButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(140, 20)

    local function Choose(accountWide)
        ns.settings.moneyAccountWide = accountWide
        ns.Publish("SETTINGS_CHANGED")
    end

    button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Whose money...")
            root:CreateRadio(("%s only"):format(UnitName("player") or "This character"), function()
                return not ns.settings.moneyAccountWide
            end, function()
                Choose(false)
            end)
            root:CreateRadio("Whole account", function()
                return ns.settings.moneyAccountWide
            end, function()
                Choose(true)
            end)
        end)
    end)

    function button:Update()
        if ns.settings.moneyAccountWide then
            self:SetText("Whole account")
        else
            self:SetText(("%s only"):format(UnitName("player") or "This character"))
        end
    end

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Whose money")
        GameTooltip:AddLine(
            "This character on their own, or every character on the account added "
                .. "together. Each character's own figures start from when this "
                .. "version of Goldwise first ran; the account's go back further.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button:Update()
    return button
end

--- Money with the game's own coin icons.
---@param copper number
---@return string
function Theme.Coins(copper)
    return GetMoneyString(math.floor(copper + 0.5), true)
end
