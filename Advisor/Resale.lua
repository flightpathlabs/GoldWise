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

-- One deal as a step: what to buy and where, then the three figures that
-- make the case for it, side by side: what the vendor asks, what it's
-- listed for at auction, and what's left over once it's sold.
local function Step(deal, sayWhere)
    local parts = {}

    if sayWhere then
        table.insert(parts, "In " .. ns.Recipes.ZonesText(deal.vendors))
    end

    -- The two things that turn a good price into a bad buy.
    if (deal.listed or 0) > 0 then
        table.insert(parts, FormatLargeNumber(deal.listed) .. " listed at auction")
    end
    if deal.stock then
        table.insert(parts, ("%d in stock when last seen"):format(deal.stock))
    end

    local detail = ""
    if #parts > 0 then
        detail = table.concat(parts, ". ") .. "."
    end

    local spot = ns.Recipes.VendorSpot(deal)
    return {
        itemID = deal.item,
        title = ns.ItemName(deal.item) or "Recipe",
        detail = detail,
        figures = {
            -- A price we've seen is a fact; one we've worked out is a guess.
            { amount = deal.cost, caption = deal.costIsSeen and "vendor" or "vendor, about" },
            { amount = deal.price, caption = "auction" },
            { amount = deal.profit, caption = "profit" },
        },
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
