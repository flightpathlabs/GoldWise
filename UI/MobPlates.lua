local _, ns = ...

-- What an enemy is worth a kill, where the player is looking at it.
--
-- Two places, each with its own switch in the options:
--
--   * A few lines on the enemy's tooltip: about how much a kill brings
--     in, then the drops that make it so. On unless turned off.
--
--   * A small coin and a figure over its nameplate, so a field of boars
--     can be weighed up at a glance. Off unless turned on: nameplates are
--     busy enough already.
--
-- The figures come from MobValue, which works them out from what the
-- player has looted. Nothing here does any sums of its own.
--
-- Nameplates belong to the game, or to whichever nameplate addon has
-- restyled them. We never touch anything on them. The coin is a small
-- frame of our own, hung from the plate itself rather than from the
-- health bar or name inside it, which Plater and the rest replace or
-- move. It only ever follows the plate around.

local Theme = ns.Theme

-- The name our tooltip lines go under, as on item tooltips.
local OURS = "Goldwise"

-- How many drops the tooltip lists, and how many skins. The rest are
-- in the kill's value all the same.
local MAX_DROPS = 4
local MAX_SKINS = 2

-- Prices and drop tables tend to change in bursts (a scan, a run of
-- loot). One redraw of the plates for each burst is plenty.
local REFRESH_DELAY = 0.5

local COIN_SIZE = 10

local function CanSeeSecret(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Whether a unit is one we have anything to say about: a creature the
-- player could fight. Other players and their pets aren't looted.
local function IsQuarry(unit)
    if not UnitExists(unit) then
        return false
    end
    -- In restricted content the game can keep a unit's identity from us.
    -- MobValue can't tell what it is either, then.
    if not CanSeeSecret(UnitGUID(unit)) then
        return false
    end
    return UnitCanAttack("player", unit)
        and not UnitIsPlayer(unit)
        and not UnitPlayerControlled(unit)
end

local function Estimate(unit)
    -- The two halves of this feature are written side by side, and either
    -- can arrive first.
    if not ns.MobValue then
        return nil
    end
    local estimate = ns.MobValue.ForUnit(unit)
    if estimate and estimate.value and estimate.value > 0 then
        return estimate
    end
end

-- Whether to hedge: a guess from similar creatures, or too few of this
-- one's own kills to go on.
local function IsRough(estimate)
    return estimate.guess or not ns.MobValue.Confident(estimate)
end

-- Money, rounded --------------------------------------------------------------

-- An estimate written to the copper claims more than it knows. These
-- keep two figures at most, which is about as sure as a few kills get.

-- For a tooltip line: "4c", "3s 40c", "38s", "2g 40s", "12g".
local function Rough(copper)
    copper = math.floor(copper + 0.5)
    if copper < 100 then
        return copper .. "c"
    elseif copper < 1000 then
        return ns.Money(math.floor(copper / 10 + 0.5) * 10)
    elseif copper < 10000 then
        return ns.Money(math.floor(copper / 100 + 0.5) * 100)
    elseif copper < 100000 then
        return ns.Money(math.floor(copper / 1000 + 0.5) * 1000)
    end
    return ns.Money(math.floor(copper / 10000 + 0.5) * 10000)
end

-- For a nameplate, where every letter covers a bit more of the world:
-- one coin only. "4c", "38s", "2.4g", "12g".
local function Short(copper)
    copper = math.floor(copper + 0.5)
    if copper < 100 then
        return copper .. "c"
    end

    local silver = math.floor(copper / 100 + 0.5)
    if silver < 100 then
        return silver .. "s"
    end

    local gold = copper / 10000
    if gold < 10 then
        -- "2.4g", but "2g" rather than "2.0g".
        return (("%.1f"):format(gold):gsub("%.0$", "")) .. "g"
    end
    return math.floor(gold + 0.5) .. "g"
end

-- "42%", or "<1%" for the rare drop that would otherwise read as never.
local function Percent(chance)
    local percent = math.floor(chance * 100 + 0.5)
    if percent < 1 then
        return "<1%"
    end
    return percent .. "%"
end

-- The tooltip ------------------------------------------------------------------

-- One drop's row: its name on the left, its chance and worth on the
-- right. Nil when the item has no name and none is coming.
local function DropRow(drop, prefix)
    local name, coming = ns.ItemName(drop.itemID)
    if name then
        name = Theme.ItemName(name, C_Item.GetItemQualityByID(drop.itemID))
    elseif coming then
        -- It's being fetched, and will be there next time the tooltip is
        -- built. Holding its place keeps the best drops in order.
        name = Theme.Aside("one moment...")
    else
        return nil
    end

    local parts = { Percent(drop.chance) }
    -- Quantity is an average, so it can be a fraction. Only worth saying
    -- when it's more than one at a time.
    if drop.quantity and drop.quantity >= 1.05 then
        local quantity = ("%.1f"):format(drop.quantity):gsub("%.0$", "")
        table.insert(parts, "x" .. quantity)
    end
    if drop.each and drop.each > 0 then
        table.insert(parts, Rough(drop.each) .. " each")
    end

    return "  " .. (prefix or "") .. name, table.concat(parts, "  ")
end

local function AddRow(tooltip, left, right)
    local muted = Theme.MUTED
    tooltip:AddDoubleLine(left, right, muted[1], muted[2], muted[3], muted[1], muted[2], muted[3])
end

local function KillsText(kills)
    return kills == 1 and "1 kill" or (FormatLargeNumber(kills) .. " kills")
end

local function OnUnitTooltip(tooltip, data)
    -- Saved data loads a moment after the first tooltips can appear.
    local settings = ns.settings
    if not settings or not settings.mobValueTooltip then
        return
    end

    -- Unit tooltips are the game's own, on GameTooltip. Other addons'
    -- private tooltips come through here too, and aren't ours to add to.
    if tooltip ~= GameTooltip then
        return
    end

    local guid = data and data.guid
    if not CanSeeSecret(guid) then
        return
    end
    local unit = UnitTokenFromGUID(guid)
    if not CanSeeSecret(unit) or not IsQuarry(unit) then
        return
    end

    -- Rebuilt several times a second while the mouse rests here, but
    -- MobValue keeps its answers, so asking again is cheap.
    local estimate = Estimate(unit)
    if not estimate then
        return
    end

    local coin = Theme.COIN
    local rough = IsRough(estimate)

    -- "~38s a kill" is written as the nameplate writes it.
    local headline = (rough and "~%s a kill" or "About %s a kill"):format(Rough(estimate.value))
    tooltip:AddDoubleLine(OURS, headline, coin[1], coin[2], coin[3], 1, 1, 1)

    -- Where the figure comes from, so a guess isn't taken for a promise.
    -- The kills are always this creature's own, even in a guess.
    local kills = estimate.kills or 0
    local source
    if estimate.guess then
        source = "A guess from similar creatures"
        if kills > 0 then
            source = ("%s and your %s"):format(source, KillsText(kills))
        end
    elseif rough then
        source = ("From %s, so only a rough idea"):format(KillsText(kills))
    else
        source = ("From %s"):format(KillsText(kills))
    end
    tooltip:AddLine(source, unpack(Theme.MUTED))

    local shown = 0
    for _, drop in ipairs(estimate.drops or {}) do
        if shown >= MAX_DROPS then
            break
        end
        local left, right = DropRow(drop)
        if left then
            AddRow(tooltip, left, right)
            shown = shown + 1
        end
    end

    if (estimate.copper or 0) > 0 then
        AddRow(tooltip, "  Coin", Rough(estimate.copper))
    end

    shown = 0
    for _, skin in ipairs(estimate.skinned or {}) do
        if shown >= MAX_SKINS then
            break
        end
        local left, right = DropRow(skin, "Skinned: ")
        if left then
            AddRow(tooltip, left, right)
            shown = shown + 1
        end
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)

-- The nameplate coin -----------------------------------------------------------

-- Every unit with a nameplate up, whether or not it's showing a coin. Kept
-- even with the coins switched off, so turning them on can fill in the
-- plates already on screen.
local plated = {}

-- The coin showing over each unit's plate.
local coins = {}

-- Coins taken off plates, ready for the next one. Plates come and go by
-- the dozen in a busy area; making a frame each time would add up.
local spare = {}

local function CreateCoin()
    -- Parented to nothing for now. It goes onto a plate when it's used.
    local frame = CreateFrame("Frame")
    frame:SetSize(COIN_SIZE, COIN_SIZE)
    frame:Hide()

    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetAtlas("coin-gold")
    frame.Icon:SetSize(COIN_SIZE, COIN_SIZE)
    frame.Icon:SetPoint("LEFT")

    -- Small, with a shadow: it has to read against grass and snow alike
    -- without growing big enough to cover the name below it.
    frame.Text = frame:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Small")
    frame.Text:SetPoint("LEFT", frame.Icon, "RIGHT", 2, 0)

    return frame
end

local function ReleaseCoin(unit)
    local frame = coins[unit]
    if not frame then
        return
    end
    coins[unit] = nil
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    frame.plate = nil
    table.insert(spare, frame)
end

local function AcquireCoin(unit, plate)
    local frame = coins[unit]
    if not frame then
        frame = table.remove(spare) or CreateCoin()
        coins[unit] = frame
    end

    if frame.plate ~= plate then
        -- On the plate itself, which every nameplate addon keeps: it's
        -- what the game moves about the screen. Being its child, the coin
        -- fades and scales with it. Just clear of its top edge, above
        -- where most styles put the name.
        frame:SetParent(plate)
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", plate, "TOP", 0, 2)
        frame.plate = plate
    end
    return frame
end

local function UpdatePlate(unit)
    if not (ns.settings and ns.settings.mobValuePlates) then
        ReleaseCoin(unit)
        return
    end

    -- Without asking for them, forbidden plates (those in some instances,
    -- whose frames addons may not touch) aren't handed over at all. The
    -- check is there in case one ever is.
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) or not IsQuarry(unit) then
        ReleaseCoin(unit)
        return
    end

    local estimate = Estimate(unit)
    if not estimate then
        ReleaseCoin(unit)
        return
    end

    local frame = AcquireCoin(unit, plate)
    local rough = IsRough(estimate)
    frame.Text:SetText((rough and "~" or "") .. Short(estimate.value))
    -- Gold for a figure from the creature's own kills, quieter for one
    -- that's only a guess.
    frame.Text:SetTextColor(unpack(rough and Theme.MUTED or Theme.COIN))
    frame:SetWidth(COIN_SIZE + 2 + frame.Text:GetStringWidth())
    frame:Show()
end

local function UpdateAllPlates()
    for unit in pairs(plated) do
        UpdatePlate(unit)
    end
    -- And take down any coin left over a plate that has gone.
    for unit in pairs(coins) do
        if not plated[unit] then
            ReleaseCoin(unit)
        end
    end
end

local refreshPending = false

local function UpdateAllPlatesSoon()
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        UpdateAllPlates()
    end)
end

ns.OnEvent("NAME_PLATE_UNIT_ADDED", function(unit)
    plated[unit] = true
    UpdatePlate(unit)
end)

ns.OnEvent("NAME_PLATE_UNIT_REMOVED", function(unit)
    plated[unit] = nil
    ReleaseCoin(unit)
end)

-- After a reload the plates already on screen may not be announced
-- again, and after a loading screen the old ones may not have been seen
-- off. So start afresh from the plate units there are now; the first
-- forty cover any crowd worth pricing.
ns.OnEvent("PLAYER_ENTERING_WORLD", function()
    wipe(plated)
    for index = 1, 40 do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            plated[unit] = true
        end
    end
    UpdateAllPlates()
end)

-- New prices, a new kill looted, a vendor price that was missing: the
-- figures move. MobValue hears these first (it loads before us) and has
-- let go of its old answers by the time the plates ask again. Tooltips
-- need nothing, being built afresh each time.
ns.Subscribe("PRICES_CHANGED", UpdateAllPlatesSoon)
ns.Subscribe("DROPS_CHANGED", UpdateAllPlatesSoon)
ns.Subscribe("ITEM_NAMES_LOADED", UpdateAllPlatesSoon)

-- Switching the coins on or off shows at once.
ns.Subscribe("SETTINGS_CHANGED", UpdateAllPlates)
