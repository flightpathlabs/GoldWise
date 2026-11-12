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
--
-- Most of these are things the player has never held, so the client has
-- to fetch each one before it can say what it's called, and it does that
-- slowly. The list is therefore laid out in order as far as the names
-- have come, and says how far that is; it never shows a row it can't
-- name yet.

local Materials = {}
ns.Materials = Materials

-- Items shown per kind when every kind is on show: the top of each list
-- is where the money is. A kind with the page to itself gets more.
local PER_KIND = 6
local ONE_KIND = 30

-- Kinds shown together. The rest are small or odd, and can still be
-- picked on their own.
local MOST_KINDS = 12

-- A material counts as within reach when its level is no more than this
-- far above the player's. The game gives every material a level that
-- follows where it's found: copper is 10, mithril 40, runecloth 50.
local LEVEL_HEADROOM = 5

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
        if class == Enum.ItemClass.Tradegoods and kindName and listed >= ns.THIN_MARKET then
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

-- Whether a material is one the player could come by at their level.
local function WithinReach(itemID, ceiling)
    if not ceiling then
        return true
    end

    local _, _, _, level = C_Item.GetItemInfo(itemID)
    -- No level to go on is no reason to hide it.
    return not level or level <= ceiling
end

-- Goes down one kind, dearest first, choosing what to show. Returns the
-- chosen items with their names, and whether that's the whole of it.
--
-- It stops choosing at the first item the client hasn't fetched yet, so
-- that rows only ever arrive at the bottom of the list, in order. It
-- carries on past that point just far enough to ask for the names it's
-- going to need next.
local function Choose(kind, most, ceiling)
    -- With a level to keep to, some of what's asked for will turn out to
    -- be out of reach. Ask for twice as many, or a list of things too
    -- high for the player would be fetched six at a time.
    local reach = ceiling and most * 2 or most

    local chosen = {}
    local settled = true
    local candidates = 0

    for _, item in ipairs(kind.items) do
        local name, coming = ns.ItemName(item.itemID)
        if coming then
            settled = false
            candidates = candidates + 1
        elseif name and WithinReach(item.itemID, ceiling) then
            candidates = candidates + 1
            if settled then
                table.insert(chosen, { item = item, name = name })
            end
        end

        if #chosen == most or candidates == reach then
            break
        end
    end

    return chosen, settled
end

--- The kinds of material on the market, biggest first, for a menu.
---@return table kinds  list of { name, count }
function Materials.Kinds()
    local kinds = {}
    for index, kind in ipairs(Kinds(ns.Market.Home())) do
        kinds[index] = { name = kind.name, count = #kind.items }
    end
    return kinds
end

--- Lays out what the market's materials are worth.
---@param only string|nil     the name of one kind to show on its own; nil
---        shows the top of every kind
---@param nearLevel boolean   true to leave out what's beyond the player's
---        level
---@return table sections     list of { heading, steps, numbered }, shaped
---        like Trip.Plan's
---@return table|nil loading  { kind, fraction } while names are still
---        being fetched: the kind being waited on and how far through the
---        list we are, from 0 to 1. Nil once it's all here.
function Materials.Plan(only, nearLevel)
    local every = Kinds(ns.Market.Home())
    local ceiling = nearLevel and (UnitLevel("player") + LEVEL_HEADROOM) or nil

    -- Which kinds are on show, and how deep into each.
    local kinds, most = {}, PER_KIND
    for index, kind in ipairs(every) do
        if kind.name == only then
            kinds, most = { kind }, ONE_KIND
            break
        elseif index <= MOST_KINDS then
            table.insert(kinds, kind)
        end
    end

    local sections = {}
    local loading

    for index, kind in ipairs(kinds) do
        -- Every kind is gone through, even those below the one being
        -- waited on, so that their names are asked for in the meantime.
        local chosen, settled = Choose(kind, most, ceiling)

        if not loading then
            local steps = {}
            for _, choice in ipairs(chosen) do
                local item = choice.item
                -- What the player already has says whether it's theirs
                -- to sell.
                local held = ns.Bank.Held(item.itemID)

                local detail = FormatLargeNumber(item.listed) .. " listed"
                if held > 0 then
                    detail = ("%s. You have %d"):format(detail, held)
                end

                table.insert(steps, {
                    itemID = item.itemID,
                    title = choice.name,
                    detail = detail .. ".",
                    amount = item.price,
                    amountAfter = "each",
                })
            end

            if #steps > 0 then
                table.insert(sections, { heading = kind.name, steps = steps, numbered = false })
            end

            if not settled then
                local expected = math.min(most, #kind.items)
                loading = {
                    kind = kind.name,
                    fraction = (index - 1 + #chosen / expected) / #kinds,
                }
            end
        end
    end

    if #sections == 0 and not loading then
        local heading, note
        if #every == 0 then
            heading = "Nothing to show yet"
            note = {
                title = "This needs auction prices",
                detail = "Visit an auction house and let Goldwise read it. "
                    .. "Every material on sale will be listed here.",
            }
        elseif nearLevel then
            heading = "Nothing within reach"
            note = {
                title = "Everything on sale here is beyond your level",
                detail = "Untick the level limit in the menu above to see it anyway.",
            }
        else
            heading = "Nothing to show"
            note = {
                title = "The game wouldn't say what these are",
                detail = "It was asked about each of them and didn't answer. "
                    .. "Come back to this page in a moment.",
            }
        end
        table.insert(sections, { heading = heading, numbered = false, steps = { note } })
    end

    return sections, loading
end
