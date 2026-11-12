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
Theme.PARCHMENT = { 0.91, 0.85, 0.72 }
Theme.INK = { 0.17, 0.13, 0.09 }
Theme.FADED_INK = { 0.35, 0.27, 0.19 }
Theme.RUST = { 0.54, 0.29, 0.11 }
Theme.OXBLOOD = { 0.54, 0.10, 0.08 }
Theme.MUTED = { 0.79, 0.73, 0.61 }

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
    if not quantity or quantity == 0 then
        return "none listed"
    end
    return FormatLargeNumber(quantity) .. " listed"
end

--- Money with the game's own coin icons.
---@param copper number
---@return string
function Theme.Coins(copper)
    return GetMoneyString(math.floor(copper + 0.5), true)
end
