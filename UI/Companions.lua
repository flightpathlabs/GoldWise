local _, ns = ...

-- Knowing what the player's other addons already show, so Goldwise doesn't
-- say it a second time.
--
-- The rule: if another addon is putting something on screen, we leave that
-- thing to it and keep to what only Goldwise adds. If the player switches
-- the other addon's version off, ours comes back by itself. Nobody should
-- have to visit two options pages to stop seeing double.
--
-- So these answer "is it being shown right now?", not just "is that addon
-- installed?", wherever the other addon lets us tell.

local Companions = {}
ns.Companions = Companions

local function IsLoaded(name)
    return C_AddOns.IsAddOnLoaded(name)
end

-- Profession Atlas has one switch for everything it adds to item tooltips:
-- its auction price and its list of which characters hold the item. It
-- keeps the switch in its saved settings, which is the only place to read
-- it. If those ever change shape, assume it's showing.
local function AtlasTooltipsOn()
    if not IsLoaded("ForeverProfessions") then
        return false
    end

    local saved = ForeverProfessionsDB
    local settings = type(saved) == "table" and saved.settings
    if type(settings) == "table" then
        -- Unset means off, as it does to Profession Atlas itself.
        return settings.tooltips == true
    end
    return true
end

-- Addons that put an auction price on item tooltips whenever they run.
local PRICE_ADDONS = {
    "Auctionator",
    "TradeSkillMaster",
    "Auc-Advanced", -- Auctioneer
}

-- Whether Auctionator has a price of its own for an item. It offers other
-- addons a way to ask. If that way isn't there, or doesn't answer, take
-- it that it has one: saying nothing is better than saying it twice.
local function AuctionatorKnows(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then
        return true
    end

    local ok, price = pcall(api.GetAuctionPriceByItemID, ns.name, itemID)
    return not ok or price ~= nil
end

--- Auctionator's last price for an item, and how many days ago it saw it,
--- asked through the interface Auctionator publishes for other addons.
--- Nothing else of Auctionator's is read.
---@param itemID number
---@return number|nil price  copper; nil when it has none, or isn't there
---@return number|nil age    whole days: 0 is today
function Companions.AuctionatorPrice(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(api) ~= "table" then
        return nil
    end
    local askPrice, askAge = api.GetAuctionPriceByItemID, api.GetAuctionAgeByItemID
    if type(askPrice) ~= "function" or type(askAge) ~= "function" then
        return nil
    end

    -- Either can fail outright on an item Auctionator has never met, or
    -- after an update changes what they expect.
    local gotPrice, price = pcall(askPrice, ns.name, itemID)
    local gotAge, age = pcall(askAge, ns.name, itemID)
    local usable = gotPrice
        and gotAge
        and type(price) == "number"
        and price > 0
        and type(age) == "number"
        and age >= 0
    if usable then
        return price, math.floor(age)
    end
end

--- Whether another addon is putting an auction price on item tooltips.
---@param itemID number|nil  the item in question. An addon that's there
---        but has no price for this one isn't showing one, and where it
---        can be asked, it is.
---@return boolean
function Companions.ShowsTooltipPrices(itemID)
    for _, name in ipairs(PRICE_ADDONS) do
        if IsLoaded(name) then
            if name ~= "Auctionator" or not itemID or AuctionatorKnows(itemID) then
                return true
            end
        end
    end
    return AtlasTooltipsOn()
end

--- Whether another addon is listing, on item tooltips, which of the
--- player's characters hold the item.
---@return boolean
function Companions.ShowsHoldings()
    -- Bagnon lists bags, bank and mail for every character.
    return IsLoaded("Bagnon") or AtlasTooltipsOn()
end

-- Addons that read every auction with the game's full read, which the
-- whole account can use only once in fifteen minutes.
local FULL_READ_ADDONS = {
    "Auctionator",
    "TradeSkillMaster",
    "Auc-Advanced",
    "ForeverProfessions",
}

--- Whether another addon makes full reads of the auction house, and so
--- has a claim on the cooldown they share with ours.
---@return boolean
function Companions.MakesFullReads()
    for _, name in ipairs(FULL_READ_ADDONS) do
        if IsLoaded(name) then
            return true
        end
    end
    return false
end

--- Whether another addon reads the whole market by itself each time the
--- auction house opens. Its read is ours to share, so ours can wait.
---@return boolean
function Companions.ReadsOnOpening()
    -- Auctionator does unless the player has switched that off, and
    -- Profession Atlas does whenever Auctionator isn't there to do it.
    -- If neither turns out to read this time, all we've lost is a couple
    -- of seconds before our own.
    return IsLoaded("Auctionator") or IsLoaded("ForeverProfessions")
end

--- Whether another addon has its own progress display on the auction house
--- window while prices are being read.
---@return boolean
function Companions.ShowsScanProgress()
    -- Profession Atlas puts up its "Atlas AH Scan" panel on every visit,
    -- except when Auctionator is installed: then it reads no prices of
    -- its own and shows none.
    return IsLoaded("ForeverProfessions") and not IsLoaded("Auctionator")
end
