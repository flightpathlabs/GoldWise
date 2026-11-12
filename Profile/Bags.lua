local _, ns = ...

-- What the player is carrying that could be sold.
--
-- This is the first of the four shelves ("Assets"). The others need recipe
-- and gathering data and come later.

local Bags = {}
ns.Bags = Bags

-- Bag updates arrive in bursts: looting one corpse can fire a dozen. Wait
-- for things to settle before counting.
local SETTLE_DELAY = 0.5

-- [itemID] = { itemID, name, icon, quality, link, count }
local holdings = {}

-- [itemID] = how many, for everything in the bags whether sellable or not.
-- This is what "how many do I have" questions are answered from.
local counts = {}

local rescanPending = false

--- Whether something in a bag or bank slot belongs on the list of things
--- that could be sold. Soulbound things can't be, and grey items are
--- vendor fodder that other addons already handle well.
---@param item table  ContainerItemInfo, from C_Container.GetContainerItemInfo
---@return boolean
function Bags.IsWorthListing(item)
    -- Quality is missing until the client has loaded the item. Give it the
    -- benefit of the doubt, or things vanish from the list at login.
    local quality = item.quality or Enum.ItemQuality.Common
    return not item.isBound and quality >= Enum.ItemQuality.Common
end

-- Anything the player carries deserves proper price history, so it has a
-- chart by the time they wonder about it.
local function TrackHoldings(marketKey)
    for itemID in pairs(holdings) do
        ns.Ledger.Track(marketKey, itemID)
    end
end

local function Rescan()
    rescanPending = false
    table.wipe(holdings)
    table.wipe(counts)

    -- Backpack, the four bags, and the reagent bag where the client has one.
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item then
                counts[item.itemID] = (counts[item.itemID] or 0) + item.stackCount
            end

            if item and Bags.IsWorthListing(item) then
                local holding = holdings[item.itemID]
                if holding then
                    holding.count = holding.count + item.stackCount
                else
                    holdings[item.itemID] = {
                        itemID = item.itemID,
                        name = item.itemName,
                        icon = item.iconFileID,
                        quality = item.quality,
                        link = item.hyperlink,
                        count = item.stackCount,
                    }
                end
            end
        end
    end

    TrackHoldings(ns.Market.Home())
    if ns.Market.IsOpen() then
        TrackHoldings(ns.Market.Current())
    end

    ns.Publish("BAGS_CHANGED")
end

local function RescanSoon()
    if rescanPending then
        return
    end
    rescanPending = true
    C_Timer.After(SETTLE_DELAY, Rescan)
end

--- How many of each item are in the player's bags, sellable or not.
---@return table counts  [itemID] = count. Treat it as read-only.
function Bags.Counts()
    return counts
end

--- The sellable items in the player's bags.
---@return table holdings  list of { itemID, name, icon, quality, link, count }, unordered
function Bags.Holdings()
    local list = {}
    for _, holding in pairs(holdings) do
        table.insert(list, holding)
    end
    return list
end

-- A neutral auction house is a different market from home, with its own
-- history to keep.
ns.Subscribe("AUCTION_HOUSE_OPENED", TrackHoldings)

ns.OnEvent("PLAYER_LOGIN", RescanSoon)
ns.OnEvent("BAG_UPDATE_DELAYED", RescanSoon)
