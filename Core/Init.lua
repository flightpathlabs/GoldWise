local addonName, ns = ...

-- Goldwise
--
-- Everything hangs off the private table the client hands every file in an
-- addon (ns). Nothing here is global except the saved-variables table, the
-- slash command and the addon-list click handler, which the client needs
-- to find by name.

ns.name = addonName

ns.COPPER_PER_SILVER = 100
ns.COPPER_PER_GOLD = 10000
ns.SECONDS_PER_DAY = 86400

-- Measured on Forever with the probe: listing anything costs at least this
-- much, whatever the stack size or duration.
ns.MIN_DEPOSIT = 100

-- The auction house's share of a sale. The client doesn't expose it, so
-- these are the Classic figures until a real sale tells us otherwise. The
-- goblin-run neutral houses have always taken more.
ns.AUCTION_CUT = 0.05
ns.NEUTRAL_AUCTION_CUT = 0.15

-- What trainers charge, by class. Filled in by the files in Data\Training.
ns.TrainingData = {}

-- Which vendors sell which recipes, by the profession's name in English.
-- Filled in by the files in Data\Recipes.
ns.RecipeData = {}

--- Formats copper as plain text, leaving out the parts that are zero.
---@param copper number
---@return string  e.g. "1g 4s", "81c", "2s 30c"
function ns.Money(copper)
    copper = math.floor(copper + 0.5)

    local gold = math.floor(copper / ns.COPPER_PER_GOLD)
    local silver = math.floor(copper / ns.COPPER_PER_SILVER) % 100
    local bronze = copper % 100

    local parts = {}
    if gold > 0 then
        table.insert(parts, gold .. "g")
    end
    if silver > 0 then
        table.insert(parts, silver .. "s")
    end
    if bronze > 0 or #parts == 0 then
        table.insert(parts, bronze .. "c")
    end
    return table.concat(parts, " ")
end

--- Describes how long ago something happened, the way a person would.
---@param seconds number
---@return string  e.g. "just now", "20 minutes ago", "3 days ago"
function ns.Ago(seconds)
    if seconds < 90 then
        return "just now"
    elseif seconds < 3600 then
        return ("%d minutes ago"):format(seconds / 60)
    elseif seconds < 2 * 3600 then
        return "an hour ago"
    elseif seconds < ns.SECONDS_PER_DAY then
        return ("%d hours ago"):format(seconds / 3600)
    elseif seconds < 2 * ns.SECONDS_PER_DAY then
        return "yesterday"
    end
    return ("%d days ago"):format(seconds / ns.SECONDS_PER_DAY)
end

--- Prints a line to chat with the addon's name in front.
--- Used for slash-command replies only. Goldwise doesn't narrate in chat.
function ns.Print(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    print("|cffe0b23cGoldwise|r: " .. text)
end
