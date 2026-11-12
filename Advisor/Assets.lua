local _, ns = ...

-- Everything Goldwise knows about one thing the player holds: its price,
-- its recent trend and the verdict on it.
--
-- The Assets list, the prompts and the merchant check all need the same
-- answer, so it's worked out once, here. Advice.lua holds the rules; this
-- gathers the facts those rules are fed.

local Assets = {}
ns.Assets = Assets

-- Items whose details we've asked the client to load this session.
local requested = {}

--- Whether we asked the client to load this item's details, and so have
--- something to gain from redrawing now that they've arrived.
---@param itemID number
---@return boolean
function Assets.IsWaitingFor(itemID)
    return requested[itemID] == true
end

--- Assesses one holding.
---@param holding table       one entry from Bags.Holdings or Characters.Others
---@param marketKey string
---@param owner string|nil    the character holding it, if not the current one
---@return table asset  { itemID, owner, name, icon, quality, link, count,
---        price, listed, seenAt, source, trend, againstUsual, advice }
function Assets.Describe(holding, marketKey, owner)
    local itemID = holding.itemID
    local price, listed, seenAt, source = ns.Ledger.Price(marketKey, itemID)

    local history = ns.Ledger.History(marketKey, itemID, ns.Stats.USUAL_DAYS)
    local againstUsual = ns.Stats.AgainstUsual(history, price)

    local trend = {}
    for index, day in ipairs(history) do
        trend[index] = day.last
    end

    -- The eleventh value is what a vendor pays. It's missing until the
    -- client has the item cached. That's nearly always true for the
    -- player's own bags, but not for another character's, so ask for it;
    -- the window redraws when the answer arrives.
    local vendorPrice = select(11, C_Item.GetItemInfo(itemID))
    if vendorPrice == nil and not requested[itemID] then
        -- Once per session is enough. If the client can't load an item,
        -- asking again on every redraw would never end.
        requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end

    return {
        itemID = itemID,
        owner = owner,
        name = holding.name or ("Item " .. itemID),
        icon = holding.icon,
        quality = holding.quality,
        link = holding.link,
        count = holding.count,
        price = price,
        listed = listed,
        seenAt = seenAt,
        source = source,
        trend = trend,
        againstUsual = againstUsual,
        advice = ns.Advice.ForHolding({
            count = holding.count,
            price = price,
            vendorPrice = vendorPrice,
            againstUsual = againstUsual,
            cut = ns.Market.Cut(marketKey),
            auditor = ns.settings.auditorMode,
        }),
    }
end

--- Assesses everything sellable in the player's own bags.
---@param marketKey string
---@return table assets   list of assets, as from Describe, unordered
---@return number total   what selling everything marked Sell should bring in
function Assets.InBags(marketKey)
    local assets = {}
    local total = 0

    for _, holding in ipairs(ns.Bags.Holdings()) do
        local asset = Assets.Describe(holding, marketKey)
        table.insert(assets, asset)

        if asset.advice.verb == ns.Advice.SELL then
            total = total + (asset.advice.proceeds or 0)
        end
    end
    return assets, total
end
