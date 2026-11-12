local _, ns = ...

-- What materials are worth: every trade good on the market, sorted into
-- kinds, dearest first.
--
-- The gathering list knows where a few dozen things come from. This goes
-- the other way. It knows nothing about where anything comes from, and
-- instead reads the whole market: cloth, leather, ore, herbs, meat, fish,
-- gems, elemental bits, enchanting dust, everything the game files as a
-- trade good. It's the answer to "what's actually worth picking up?",
-- drawn from what's really for sale and not from anyone's list.

local Materials = {}
ns.Materials = Materials

-- Items shown per kind. The top of each list is where the money is.
local PER_KIND = 6

-- Kinds shown. The rest are small or odd.
local MOST_KINDS = 12

-- Fewer than this many listed and the price is one seller's opinion.
local FEWEST_LISTED = 5

-- The work is going through thirteen thousand prices, and it only needs
-- redoing when they change: kept by market, with the scan it came from.
local cache = {}

-- Sorts the market's trade goods into kinds. Returns a list of
-- { name, worth, items }, biggest market first, where items is a list of
-- { itemID, price, listed }, dearest first.
local function Kinds(marketKey)
    local lastScan = ns.Ledger.LastScan(marketKey) or 0
    local cached = cache[marketKey]
    if cached and cached.lastScan == lastScan then
        return cached.kinds
    end

    local byName = {}
    for itemID, entry in pairs(ns.Ledger.AllPrices(marketKey)) do
        local price, listed = entry[1], entry[2]

        -- The sixth and third values are the item's class and the name of
        -- its kind within it. This is known for every item without the
        -- client having to fetch anything.
        local _, _, kindName, _, _, class = C_Item.GetItemInfoInstant(itemID)
        if class == Enum.ItemClass.Tradegoods and kindName and listed >= FEWEST_LISTED then
            local kind = byName[kindName]
            if not kind then
                kind = { name = kindName, worth = 0, items = {} }
                byName[kindName] = kind
            end
            kind.worth = kind.worth + price * listed
            table.insert(kind.items, { itemID = itemID, price = price, listed = listed })
        end
    end

    local kinds = {}
    for _, kind in pairs(byName) do
        table.sort(kind.items, function(a, b)
            if a.price ~= b.price then
                return a.price > b.price
            end
            return a.itemID < b.itemID
        end)
        table.insert(kinds, kind)
    end

    -- The kinds with the most coin tied up in them first: that's where
    -- the buyers are.
    table.sort(kinds, function(a, b)
        if a.worth ~= b.worth then
            return a.worth > b.worth
        end
        return a.name < b.name
    end)

    cache[marketKey] = { lastScan = lastScan, kinds = kinds }
    return kinds
end

--- Lays out what the market's materials are worth.
---@return table sections  list of { heading, steps, numbered }, shaped
---        like Trip.Plan's
function Materials.Plan()
    local marketKey = ns.Market.Home()
    local kinds = Kinds(marketKey)
    local sections = {}

    for index = 1, math.min(MOST_KINDS, #kinds) do
        local kind = kinds[index]
        local steps = {}

        for position = 1, math.min(PER_KIND, #kind.items) do
            local item = kind.items[position]
            local name = C_Item.GetItemNameByID(item.itemID)
            if not name then
                C_Item.RequestLoadItemDataByID(item.itemID)
            end

            -- What the player already has says whether it's theirs to sell.
            local held = (ns.Bags.Counts()[item.itemID] or 0) + ns.Bank.Count(item.itemID)
            local detail = FormatLargeNumber(item.listed) .. " listed"
            if held > 0 then
                detail = ("%s. You have %d"):format(detail, held)
            end

            table.insert(steps, {
                itemID = item.itemID,
                title = name or ("Item " .. item.itemID),
                detail = detail .. ".",
                amount = item.price,
                amountLabel = "each",
            })
        end

        table.insert(sections, { heading = kind.name, steps = steps, numbered = false })
    end

    if #sections == 0 then
        table.insert(sections, {
            heading = "Nothing to show yet",
            numbered = false,
            steps = {
                {
                    title = "This needs auction prices",
                    detail = "Visit an auction house and let Goldwise read it. "
                        .. "Every material on sale will be listed here.",
                },
            },
        })
    end
    return sections
end
