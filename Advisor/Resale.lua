local _, ns = ...

-- Buy from a vendor, sell at the auction house: the plan for it.
--
-- Recipes.Resale finds what's worth buying. This lays it out in the same
-- shape as a trip plan, so the Prospects tab can show either: what's on
-- sale where the player is standing first, then the rest by profit.

local Resale = {}
ns.Resale = Resale

-- How many deals each part of the plan lists. Past the first handful, the
-- profits are small and the walking isn't.
local MOST_HERE = 8
local MOST_ELSEWHERE = 12

-- Zones named per deal before the rest are counted.
local ZONES_NAMED = 2

local function WhereText(deal)
    local zones, seen = {}, {}
    for _, vendor in ipairs(deal.vendors) do
        if vendor.zone and not seen[vendor.zone] then
            seen[vendor.zone] = true
            table.insert(zones, vendor.zone)
        end
    end

    local text = table.concat(zones, ", ", 1, math.min(ZONES_NAMED, #zones))
    if #zones > ZONES_NAMED then
        text = ("%s and %d more"):format(text, #zones - ZONES_NAMED)
    end
    return text
end

-- One deal as a step: what to buy, what it costs and where, and what's
-- left over once it's sold.
local function Step(deal, sayWhere)
    local parts = {}

    -- A price we've seen is a fact; one we've worked out is "about".
    table.insert(
        parts,
        (deal.costIsSeen and "Costs %s" or "Costs about %s"):format(ns.Money(deal.cost))
    )
    if sayWhere then
        table.insert(parts, "in " .. WhereText(deal))
    end
    local detail = table.concat(parts, " ") .. (". Sells for %s"):format(ns.Money(deal.price))

    -- The two things that turn a good price into a bad buy.
    if (deal.listed or 0) > 0 then
        detail = ("%s, %s listed"):format(detail, FormatLargeNumber(deal.listed))
    end
    if deal.stock then
        detail = ("%s. %d in stock when last seen"):format(detail, deal.stock)
    end

    local spot = ns.Recipes.VendorSpot(deal)
    return {
        itemID = deal.item,
        title = ns.ItemName(deal.item) or "Recipe",
        detail = detail .. ".",
        amount = deal.profit,
        amountLabel = "profit",
        action = spot and {
            label = "Map",
            onClick = function()
                ns.MapMarks.ShowPoint(spot.mapID, spot.x, spot.y)
            end,
        } or nil,
    }
end

--- Lays out what's worth buying from vendors to sell at auction.
---@return table sections  list of { heading, steps, numbered }, shaped
---        like Trip.Plan's
function Resale.Plan()
    local deals, unpriced = ns.Recipes.Resale(ns.Market.Home())

    local here, elsewhere = {}, {}
    for _, deal in ipairs(deals) do
        if deal.here and #here < MOST_HERE then
            table.insert(here, Step(deal, false))
        elseif not deal.here and #elsewhere < MOST_ELSEWHERE then
            table.insert(elsewhere, Step(deal, true))
        end
    end

    local sections = {}
    if #here > 0 then
        table.insert(sections, {
            heading = "On sale where you are",
            steps = here,
            numbered = true,
        })
    end
    if #elsewhere > 0 then
        table.insert(sections, {
            heading = #here > 0 and "Worth a trip" or "Worth buying to sell",
            steps = elsewhere,
            numbered = true,
        })
    end

    -- Say why the list is empty or short, where we know.
    local notes = {}
    if #deals == 0 then
        local reason = ns.Ledger.LastScan(ns.Market.Home())
                and "Nothing vendors sell is fetching enough at auction to be worth it right now."
            or "This needs auction prices. Visit an auction house first."
        table.insert(notes, { title = "Nothing to buy just now", detail = reason })
    end
    if unpriced > 0 then
        table.insert(notes, {
            title = "Still working some out",
            detail = (
                "%d more are waiting on the game for what vendors charge. "
                .. "Look again in a moment."
            ):format(unpriced),
        })
    end
    if #notes > 0 then
        table.insert(sections, { heading = "Worth knowing", steps = notes, numbered = false })
    end

    return sections
end
