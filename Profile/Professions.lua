local _, ns = ...

-- Which professions the player has, and how skilled they are.

local Professions = {}
ns.Professions = Professions

-- Forever reports its own skill-line numbers for a character's professions
-- rather than the long-standing ones, so other addons on this client tell
-- them apart by name, and so do we. The rest of Goldwise knows each by its
-- English name.
local GATHERING = {
    ["Skinning"] = "skinning",
    ["Mining"] = "mining",
    ["Herbalism"] = "herbalism",
}

-- The long-standing numbers. The game still answers to these with each
-- profession's name in the player's own language, which is how a name on
-- a German or French client is matched to the English one.
local SKILL_LINES = {
    [129] = "First Aid",
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [171] = "Alchemy",
    [182] = "Herbalism",
    [185] = "Cooking",
    [186] = "Mining",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting",
    [356] = "Fishing",
    [393] = "Skinning",
}

-- [the game's name for a profession] = its English name. Filled in the
-- first time the game has names to give.
local englishFor

-- [key] = skill level, bonus included, for the gathering professions the
-- player has.
local skills = {}

-- [English name] = skill level, for every profession they have.
local byName = {}

-- The English name of a profession, given the game's. A name the game
-- can't place is handed back as it came, which on an English client is
-- right anyway.
local function EnglishName(name)
    if not englishFor then
        local found = {}
        local ask = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName

        for skillLine, english in pairs(SKILL_LINES) do
            local ok, theirs = pcall(ask, skillLine)
            if ok and type(theirs) == "string" and theirs ~= "" then
                found[theirs] = english
            end
        end

        -- Nothing at all means the game wasn't ready to say. Ask again
        -- next time rather than settle for an empty list.
        if next(found) == nil then
            return name
        end
        englishFor = found
    end

    return englishFor[name] or name
end

local function Read(...)
    table.wipe(skills)
    table.wipe(byName)

    -- GetProfessions returns one index per slot and nil for empty slots,
    -- so walk by count rather than stopping at the first gap.
    for slot = 1, select("#", ...) do
        local index = select(slot, ...)
        if index then
            -- The eighth value is the bonus from gear and racial traits,
            -- which counts toward what the player can gather.
            local name, _, skill, _, _, _, _, bonus = GetProfessionInfo(index)
            if name then
                name = EnglishName(name)
                byName[name] = skill or 0

                local key = GATHERING[name]
                if key then
                    skills[key] = (skill or 0) + (bonus or 0)
                end
            end
        end
    end
end

local function Refresh()
    Read(GetProfessions())
    ns.Publish("PROFILE_CHANGED")
end

--- The player's skill in a gathering profession.
---@param key string  "skinning", "mining" or "herbalism"
---@return number|nil skill  nil if they don't have it
function Professions.Skill(key)
    return skills[key]
end

--- The player's skill in any profession, by its English name.
---@param name string  "Blacksmithing", "First Aid" and so on
---@return number|nil skill  nil if they don't have it
function Professions.SkillByName(name)
    return byName[name]
end

ns.OnEvent("PLAYER_LOGIN", Refresh)
ns.OnEvent("SKILL_LINES_CHANGED", Refresh)
ns.OnEvent("PLAYER_LEVEL_UP", function()
    -- Level isn't stored here, but everything that cares about the profile
    -- cares about level too. Wait a frame: while this event is being
    -- handled the game can still report the old level.
    C_Timer.After(0, function()
        ns.Publish("PROFILE_CHANGED")
    end)
end)
