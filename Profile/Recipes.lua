local _, ns = ...

-- Recipes the player could still buy from a vendor, for the professions
-- they have.
--
-- Which vendors sell which recipes isn't something the game will say. The
-- list in Data\Recipes is the one What's Training? keeps, brought in with
-- its author's licence. What's worked out here is the part that depends on
-- the player: which of those recipes they haven't learned, which they're
-- skilled enough for, and whether one is on sale where they're standing.

local Recipes = {}
ns.Recipes = Recipes

-- How far short of a recipe's skill the player can be and still be told,
-- unasked, that it's for sale nearby. Close enough to be worth buying
-- ahead; not so far that it's noise.
local WITHIN_REACH = 25

local function IsLearned(spellID)
    return C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)
end

-- Whether the player's reputation is good enough to be sold a recipe.
-- `standing` is pairs of faction and standing, any one of which will do
-- (there's usually one pair for each side). Returns false and a few words
-- on what's missing when it isn't.
local function MeetsStanding(standing)
    if not standing then
        return true
    end

    local missing
    for index = 1, #standing, 2 do
        local faction = C_Reputation.GetFactionDataByID(standing[index])
        -- The other side's faction is one this character will never meet.
        if faction then
            local needed = standing[index + 1]
            if faction.reaction >= needed then
                return true
            end
            missing = ("Needs %s with %s"):format(
                _G["FACTION_STANDING_LABEL" .. needed] or "better standing",
                faction.name
            )
        end
    end
    return false, missing or "Needs a reputation you haven't begun"
end

--- Every vendor recipe the player hasn't learned, for the professions they
--- have. Recipes on sale in the zone they're in come first, then the ones
--- they can use now, then the rest by skill.
---@return table recipes  list of:
---   item        the recipe's item ID
---   spell       the spell it teaches
---   profession  the profession's name
---   needed      skill it takes to learn
---   skill       the player's skill
---   ready       true if they're skilled enough now
---   bound       true if it binds when bought
---   favor       its price in Merchant's Favor, if it isn't sold for coin
---   locked      what reputation is missing, if they can't be sold it yet
---   vendors     { npc, area, zone } for each vendor who'll deal with them
---   here        the vendor in the zone they're standing in, if there is one
function Recipes.Unlearned()
    local side = UnitFactionGroup("player")
    local zoneHere = GetRealZoneText()
    local list = {}

    for profession, recipes in pairs(ns.RecipeData) do
        local skill = ns.Professions.SkillByName(profession)

        for _, recipe in ipairs(skill and recipes or {}) do
            local item, spell, needed = recipe[1], recipe[2], recipe[3]

            if not IsLearned(spell) then
                local vendors, here = {}, nil
                for _, vendor in ipairs(recipe.vendors) do
                    if not vendor[3] or vendor[3] == side then
                        local entry = {
                            npc = vendor[1],
                            area = vendor[2],
                            zone = C_Map.GetAreaInfo(vendor[2]),
                        }
                        table.insert(vendors, entry)
                        if entry.zone and entry.zone == zoneHere then
                            here = here or entry
                        end
                    end
                end

                if #vendors > 0 then
                    local allowed, missing = MeetsStanding(recipe.standing)
                    table.insert(list, {
                        item = item,
                        spell = spell,
                        profession = profession,
                        needed = needed,
                        skill = skill,
                        ready = skill >= needed,
                        bound = recipe.bound == true,
                        favor = recipe.favor,
                        locked = not allowed and missing or nil,
                        vendors = vendors,
                        here = here,
                    })
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if (a.here ~= nil) ~= (b.here ~= nil) then
            return a.here ~= nil
        end

        local usableA = a.ready and not a.locked
        local usableB = b.ready and not b.locked
        if usableA ~= usableB then
            return usableA
        elseif a.needed ~= b.needed then
            return a.needed < b.needed
        end
        return a.item < b.item
    end)
    return list
end

--- The recipes worth mentioning unasked: on sale in the zone the player is
--- in, within reach of their skill, and not held back by reputation.
---@return table recipes  as from Recipes.Unlearned
function Recipes.ForSaleHere()
    local forSale = {}
    for _, recipe in ipairs(Recipes.Unlearned()) do
        local withinReach = recipe.needed <= recipe.skill + WITHIN_REACH
        if recipe.here and withinReach and not recipe.locked then
            table.insert(forSale, recipe)
        end
    end
    return forSale
end

--- A spot on the map for one of a recipe's vendors, where one can be
--- placed. That takes Questie; without it we know the zone and no more.
---@param recipe table  one entry from Recipes.Unlearned
---@return table|nil spot    { mapID, x, y, name }
---@return table|nil vendor  the vendor it belongs to
function Recipes.VendorSpot(recipe)
    -- The one in this zone first, if there is one.
    if recipe.here then
        local spot = ns.Directory.FindNPC(recipe.here.npc)
        if spot then
            return spot, recipe.here
        end
    end

    for _, vendor in ipairs(recipe.vendors) do
        local spot = ns.Directory.FindNPC(vendor.npc)
        if spot then
            return spot, vendor
        end
    end
end
