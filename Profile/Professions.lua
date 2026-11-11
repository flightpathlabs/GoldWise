local _, ns = ...

-- Which gathering professions the player has, and how skilled they are.

local Professions = {}
ns.Professions = Professions

-- Forever reports its own skill-line numbers for professions rather than
-- the long-standing ones, so other addons on this client identify them by
-- name, and so do we. These are the English names: on another language's
-- client this finds nothing, and the Prospects tab falls back to showing
-- only what anyone can farm. Fixing that properly is on the list.
local GATHERING = {
    ["Skinning"] = "skinning",
    ["Mining"] = "mining",
    ["Herbalism"] = "herbalism",
}

-- [key] = skill level, for the gathering professions the player has.
local skills = {}

local function Read(...)
    table.wipe(skills)

    -- GetProfessions returns one index per slot and nil for empty slots,
    -- so walk by count rather than stopping at the first gap.
    for slot = 1, select("#", ...) do
        local index = select(slot, ...)
        if index then
            -- The eighth value is the bonus from gear and racial traits,
            -- which counts toward what the player can gather.
            local name, _, skill, _, _, _, _, bonus = GetProfessionInfo(index)
            local key = name and GATHERING[name]
            if key then
                skills[key] = (skill or 0) + (bonus or 0)
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
