local _, ns = ...

-- Things the player uses rather than sells.
--
-- A price on something doesn't make it for sale. A fishing pole is worth
-- a few silver at auction and a good deal more to someone who fishes, and
-- advice to sell it is advice nobody wants. So some things are kept: left
-- out of the totals, never marked for sale, never mentioned in a prompt.
--
-- There are two layers. The player's own say comes first and is saved for
-- the whole account. Where they haven't said, the tools of a trade are
-- kept and everything else is fair game.

local Keep = {}
ns.Keep = Keep

-- Why something is kept.
Keep.CHOSEN = "chosen" -- the player said so
Keep.TOOL = "tool" -- it's a tool of a trade, and they haven't said otherwise

-- Tools a profession needs in the bags to work, by item ID. Fishing poles
-- aren't listed: there are many, and the game can tell us what one is.
local TOOLS = {
    [2901] = true, -- Mining Pick
    [7005] = true, -- Skinning Knife
    [5956] = true, -- Blacksmith Hammer
    [6219] = true, -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [6218] = true, -- Runed Copper Rod
    [6339] = true, -- Runed Silver Rod
    [11130] = true, -- Runed Golden Rod
    [11145] = true, -- Runed Truesilver Rod
    [16207] = true, -- Runed Arcanite Rod
    [9149] = true, -- Philosopher's Stone
    [4471] = true, -- Flint and Tinder
}

-- The game files fishing poles as a kind of weapon.
local FISHING_POLE = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20

local function IsTool(itemID)
    if TOOLS[itemID] then
        return true
    end

    -- The twelfth and thirteenth values are the item's class and subclass.
    -- Missing until the client has the item loaded, which for something in
    -- the player's bags it has.
    local _, _, _, _, _, _, _, _, _, _, _, class, subclass = C_Item.GetItemInfo(itemID)
    return class == Enum.ItemClass.Weapon and subclass == FISHING_POLE
end

-- The player's choices: [itemID] = true to keep, false to sell.
local function Choices()
    if type(ns.db.keep) ~= "table" then
        ns.db.keep = {}
    end
    return ns.db.keep
end

--- Whether an item is being kept, and why.
---@param itemID number
---@return boolean kept
---@return string|nil why  Keep.CHOSEN or Keep.TOOL
function Keep.IsKept(itemID)
    local choice = Choices()[itemID]
    if choice == true then
        return true, Keep.CHOSEN
    elseif choice == false then
        return false
    end

    if IsTool(itemID) then
        return true, Keep.TOOL
    end
    return false
end

--- Switches an item between kept and for sale.
---@param itemID number
function Keep.Toggle(itemID)
    local keep = not Keep.IsKept(itemID)

    -- Only a choice that differs from what we'd assume needs remembering.
    if keep == IsTool(itemID) then
        Choices()[itemID] = nil
    else
        Choices()[itemID] = keep
    end

    -- Everything that shows a verdict has one fewer, or one more, to show.
    ns.Publish("SETTINGS_CHANGED")
end
