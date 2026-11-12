local _, ns = ...

-- "/gw check": asks the game a few questions and prints the answers.
--
-- Some of what Goldwise might do next depends on what this client will
-- tell an addon, and that can't be read off from Blizzard's interface code
-- alone. The next thing on the list is working out what the player could
-- make from what they're carrying, and what it would sell for. That needs
-- each recipe's ingredients, and the open question is whether the game
-- hands those over without the profession window being open.
--
-- This doesn't change anything. It's here to be run once and reported.

-- Recipes looked at per profession. Enough to see a pattern.
local SAMPLES = 2

local function Say(text, ...)
    ns.Print(text, ...)
    ns.Log("check: " .. text, ...)
end

-- Describes what the game says about one recipe.
local function DescribeRecipe(spellID)
    local known = C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)

    local gotSchematic, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
    if not gotSchematic then
        return ("recipe %d: asking for its ingredients failed (%s)"):format(
            spellID,
            tostring(schematic)
        )
    elseif type(schematic) ~= "table" then
        return ("recipe %d (%s): no ingredients given"):format(
            spellID,
            known and "known" or "not known"
        )
    end

    local slots = schematic.reagentSlotSchematics or {}
    local first = slots[1]
    local firstReagent = first and first.reagents and first.reagents[1]

    return ("recipe %d (%s): makes item %s x%s, %d ingredients, first is item %s x%s"):format(
        spellID,
        known and "known" or "not known",
        tostring(schematic.outputItemID),
        tostring(schematic.quantityMin),
        #slots,
        tostring(firstReagent and firstReagent.itemID),
        tostring(first and first.quantityRequired)
    )
end

--- Runs the check and prints what it finds.
function ns.RunCheck()
    Say("Checking what the game will say about recipes...")

    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
        Say("This client has no way to ask for a recipe's ingredients.")
        return
    end

    local gotAll, all = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    local listed = gotAll and type(all) == "table" and #all or "none (the game wouldn't say)"
    Say("Recipes listed with no profession window open: %s", listed)

    local professions = 0
    for profession, recipes in pairs(ns.RecipeData) do
        local skill = ns.Professions.SkillByName(profession)
        if skill then
            professions = professions + 1
            Say("%s (skill %d):", profession, skill)
            for index = 1, math.min(SAMPLES, #recipes) do
                -- The second entry of each recipe is the spell it teaches.
                Say("  %s", DescribeRecipe(recipes[index][2]))
            end
        end
    end

    if professions == 0 then
        Say("You have no crafting profession on this character, so there was nothing to ask.")
    end
    Say("Done. Send these lines back and Goldwise can be taught the next step.")
end
