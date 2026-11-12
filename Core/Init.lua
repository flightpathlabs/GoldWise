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

-- A gain smaller than this isn't worth walking anywhere for.
ns.SMALL_CHANGE = 100

-- A vendor usually asks four times what they'd pay for the same thing.
-- Used to put a price on ingredients nobody auctions because a vendor
-- sells them.
ns.VENDOR_MARKUP = 4

-- Fewer listed than this and a price is one or two sellers' opinion.
ns.THIN_MARKET = 5

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
---@return string  e.g. "1g 4s", "81c", "2s 30c", "-3s"
function ns.Money(copper)
    copper = math.floor(copper + 0.5)

    -- A loss is the same sum with a minus sign in front.
    if copper < 0 then
        return "-" .. ns.Money(-copper)
    end

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
        return ("%d minutes ago"):format(math.floor(seconds / 60))
    elseif seconds < 2 * 3600 then
        return "an hour ago"
    elseif seconds < ns.SECONDS_PER_DAY then
        return ("%d hours ago"):format(math.floor(seconds / 3600))
    elseif seconds < 2 * ns.SECONDS_PER_DAY then
        return "yesterday"
    end
    return ("%d days ago"):format(math.floor(seconds / ns.SECONDS_PER_DAY))
end

-- How far the player's clock is from UTC, and when that was last worked
-- out. It moves twice a year at most, so it's looked at again every few
-- minutes and no more often.
local CLOCK_CHECK = 300
local clockOffset, clockCheckedAt

--- How many seconds the player's own clock runs ahead of UTC, in whole
--- hours. Negative west of Greenwich: -28,800 on the American west coast.
---
--- The game counts time in UTC, where a new day starts in the middle of
--- an American afternoon and of an Australian morning. Anything Goldwise
--- files by day uses this to file it by the player's day instead.
---@return number seconds
function ns.ClockOffset()
    local uptime = GetTime()
    if not clockOffset or uptime - clockCheckedAt > CLOCK_CHECK then
        local now = time()

        -- The same moment as UTC would write it, read back as though it
        -- were local. The gap between that and now is the offset. Summer
        -- time has to be carried across, or it's an hour out for half the
        -- year.
        local elsewhere = date("!*t", now)
        elsewhere.isdst = date("*t", now).isdst

        -- Taken to the nearest hour. Some of what's filed by day is kept
        -- by the hour underneath, and a zone on the half hour (India,
        -- central Australia) would have those two disagree about where
        -- midnight falls. There a day starts half an hour off the clock's.
        clockOffset = math.floor((now - time(elsewhere)) / 3600 + 0.5) * 3600
        clockCheckedAt = uptime
    end
    return clockOffset
end

--- Prints a line to chat with the addon's name in front.
--- Used for slash-command replies only. Goldwise doesn't narrate in chat.
function ns.Print(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    print("|cffe0b23cGoldwise|r: " .. text)
end
