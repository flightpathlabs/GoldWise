local _, ns = ...

-- What the player knows how to make, and what goes into it.
--
-- The game shows a recipe's ingredients in the profession window and
-- nowhere else an addon can count on. So this is learned the way the
-- bank is: whenever the player has a profession window open, we read
-- every recipe they know, what it makes and what it takes, and remember
-- it for that character.
--
-- That's the raw material for the sums in Advisor\Conversions: whether a
-- stack of ore is worth more as ore or as bars.

local Crafts = {}
ns.Crafts = Crafts

-- The window fills in over a few updates. Wait for it to settle.
local SETTLE_DELAY = 0.5

local readPending = false

-- How many recipes the last read of each profession found.
local readCounts = {}

-- Saved recipes: [character] = { [profession] = { [recipeID] = recipe } },
-- where a recipe is { item, makes, needs }: the item made, how many each
-- time, and the ingredients as a flat list of item, count, item, count.
local function Books()
    if type(ns.db.crafts) ~= "table" then
        ns.db.crafts = {}
    end
    return ns.db.crafts
end

-- Reading the window ----------------------------------------------------------

-- Whether the window is showing the player's own recipes. It's also used
-- for a profession someone has linked in chat, a guild's, and a
-- crafter NPC's, and none of those are things this character can make.
local function IsOurOwn()
    local ui = C_TradeSkillUI
    return not (ui.IsTradeSkillLinked and ui.IsTradeSkillLinked())
        and not (ui.IsTradeSkillGuild and ui.IsTradeSkillGuild())
        and not (ui.IsNPCCrafting and ui.IsNPCCrafting())
end

-- The ingredients a recipe always needs, as item, count, item, count.
-- Returns nil if any of them is something we can't put a price on.
local function Ingredients(schematic)
    local needs = {}

    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        -- Optional and finishing extras don't count: only what the recipe
        -- can't be made without.
        local basic = slot.reagentType == Enum.CraftingReagentType.Basic
        if basic and slot.required ~= false and (slot.quantityRequired or 0) > 0 then
            local reagent = slot.reagents and slot.reagents[1]
            if not reagent or not reagent.itemID then
                -- Paid for in a currency, say.
                return nil
            end
            table.insert(needs, reagent.itemID)
            table.insert(needs, slot.quantityRequired)
        end
    end

    return #needs > 0 and needs or nil
end

local function Read()
    readPending = false
    if not IsOurOwn() then
        return
    end

    local profession = C_TradeSkillUI.GetBaseProfessionInfo()
    local name = profession and profession.professionName
    local list = C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs
    if not name or name == "" or not list then
        return
    end

    local recipes, count = {}, 0
    for _, recipeID in ipairs(list() or {}) do
        -- Each recipe is read under protection. One the game chokes on
        -- shouldn't cost the player all the others.
        local ok, schematic = pcall(function()
            local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
            return info and info.learned and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        end)
        schematic = ok and schematic or nil
        local needs = schematic and schematic.outputItemID and Ingredients(schematic)

        if needs then
            -- A recipe that makes a variable number is counted at its
            -- least, so the sums never promise more than it delivers.
            recipes[recipeID] = {
                item = schematic.outputItemID,
                makes = math.max(schematic.quantityMin or 1, 1),
                needs = needs,
            }
            count = count + 1
        end
    end

    -- An empty read is the window not being ready, not the player having
    -- forgotten everything. Keep what we had.
    if count == 0 then
        return
    end

    local books = Books()
    local character = ns.Characters.CurrentKey()
    books[character] = books[character] or {}
    books[character][name] = recipes

    -- The window updates after every craft. Only a change in what the
    -- player knows is worth a line in the log.
    if readCounts[name] ~= count then
        readCounts[name] = count
        ns.Log("crafts: read %d %s recipes", count, name)
    end
    ns.Publish("CRAFTS_CHANGED")
end

local function ReadSoon()
    if not readPending then
        readPending = true
        C_Timer.After(SETTLE_DELAY, Read)
    end
end

-- Reading it back -------------------------------------------------------------

--- Everything the current character is known to be able to make.
---@return table recipes  list of { profession, item, makes, needs }, where
---        needs is a list of { itemID, count }
function Crafts.Known()
    local known = {}

    for profession, recipes in pairs(Books()[ns.Characters.CurrentKey()] or {}) do
        for _, recipe in pairs(recipes) do
            local needs = {}
            for index = 1, #recipe.needs, 2 do
                table.insert(
                    needs,
                    { itemID = recipe.needs[index], count = recipe.needs[index + 1] }
                )
            end

            table.insert(known, {
                profession = profession,
                item = recipe.item,
                makes = recipe.makes,
                needs = needs,
            })
        end
    end
    return known
end

ns.OnEvent("TRADE_SKILL_SHOW", ReadSoon)
ns.OnEvent("TRADE_SKILL_LIST_UPDATE", ReadSoon)
ns.OnEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", ReadSoon)
ns.OnEvent("NEW_RECIPE_LEARNED", ReadSoon)
