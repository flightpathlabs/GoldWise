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

--- Whether another addon is putting an auction price on item tooltips.
---@return boolean
function Companions.ShowsTooltipPrices()
    for _, name in ipairs(PRICE_ADDONS) do
        if IsLoaded(name) then
            return true
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

--- Whether another addon has its own progress display on the auction house
--- window while prices are being read.
---@return boolean
function Companions.ShowsScanProgress()
    -- Profession Atlas puts up its "Atlas AH Scan" panel on every visit,
    -- except when Auctionator is installed: then it reads no prices of
    -- its own and shows none.
    return IsLoaded("ForeverProfessions") and not IsLoaded("Auctionator")
end
