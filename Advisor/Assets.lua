local _, ns = ...

-- Everything Goldwise knows about one thing the player holds: its price,
-- its recent trend and the verdict on it.
--
-- The Assets list, the prompts and the merchant check all need the same
-- answer, so it's worked out once, here. Advice.lua holds the rules; this
-- gathers the facts those rules are fed.

local Assets = {}
ns.Assets = Assets

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
    if vendorPrice == nil then
        ns.LoadItem(itemID)
    end

    -- Something the player uses isn't for sale, whatever it would fetch.
    -- The price and the chart are still worth showing; the advice isn't.
    local advice
    local kept, why = ns.Keep.IsKept(itemID)
    if kept then
        advice = ns.Advice.ForKept(why == ns.Keep.TOOL, ns.settings.auditorMode)
    else
        advice = ns.Advice.ForHolding({
            count = holding.count,
            price = price,
            vendorPrice = vendorPrice,
            againstUsual = againstUsual,
            cut = ns.Market.Cut(marketKey),
            deposit = ns.Deposit.Estimate((vendorPrice or 0) * holding.count, marketKey),
            auditor = ns.settings.auditorMode,
        })
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
        advice = advice,
    }
end

--- What holdings would be listed for at today's auction prices, before
--- the auction house takes its cut. This is a measure of what someone
--- has, not advice: it counts things better vendored or held along with
--- the rest. Things with no price yet count for nothing, and so does
--- anything the player has said they're keeping.
---@param marketKey string
---@param ... table  lists of holdings, as from Bags.Holdings
---@return number copper
function Assets.Worth(marketKey, ...)
    local worth = 0

    for index = 1, select("#", ...) do
        local holdings = select(index, ...)
        for _, holding in ipairs(holdings) do
            if not ns.Keep.IsKept(holding.itemID) then
                local price = ns.Ledger.Price(marketKey, holding.itemID)
                worth = worth + (price or 0) * holding.count
            end
        end
    end
    return worth
end

--- What this character's things, and everything on the account, would be
--- listed for. This character is their bags and bank. The account adds
--- the bank everyone shares and every other character on the same market,
--- as of their last login.
---@param marketKey string
---@return number mine        copper
---@return number everything  copper, mine included
function Assets.WorthOfEverything(marketKey)
    -- The banks answer with what's in them and when they were last
    -- seen. Only the first is wanted here.
    local banked = ns.Bank.Holdings()
    local shared = ns.Bank.AccountHoldings()

    local mine = Assets.Worth(marketKey, ns.Bags.Holdings(), banked)
    local everything = mine + Assets.Worth(marketKey, shared)

    for _, character in ipairs(ns.Characters.Others(ns.Market.Home())) do
        local theirBank = ns.Bank.Holdings(character.key)
        everything = everything + Assets.Worth(marketKey, character.holdings, theirBank)
    end
    return mine, everything
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
