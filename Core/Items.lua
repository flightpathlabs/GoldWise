local _, ns = ...

-- Item names, for things the player may never have seen.
--
-- The client only knows an item's name once it has fetched the item, and
-- for most of what's on the auction house it hasn't. Asking for a name
-- that isn't there yet returns nothing and starts the fetch; the answer
-- comes a moment later. So anything that lists items it didn't get from
-- the player's bags asks here, shows what it gets, and is told to redraw
-- when the missing names arrive.

-- Names come back in a rush when a list of unseen items is first shown.
-- Gather them into one redraw.
local SETTLE_DELAY = 0.4

-- Items we've asked for and not yet heard back about.
local awaited = {}

-- Items the client couldn't give us. Asked for once: asking again on
-- every redraw would never end.
local unavailable = {}

local announcePending = false

--- An item's name, if the client has it yet. If it hasn't, the item is
--- asked for, and ITEM_NAMES_LOADED is published once it's here.
---@param itemID number
---@return string|nil name
function ns.ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if name then
        return name
    end

    if not awaited[itemID] and not unavailable[itemID] then
        awaited[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return nil
end

ns.OnEvent("GET_ITEM_INFO_RECEIVED", function(itemID, success)
    -- This fires for every item anything in the game loads. Only the
    -- ones we asked for are ours to act on.
    if not awaited[itemID] then
        return
    end
    awaited[itemID] = nil

    -- Told it loaded, and still nameless: there's no name coming.
    if not success or not C_Item.GetItemNameByID(itemID) then
        unavailable[itemID] = true
        return
    end

    if not announcePending then
        announcePending = true
        C_Timer.After(SETTLE_DELAY, function()
            announcePending = false
            ns.Publish("ITEM_NAMES_LOADED")
        end)
    end
end)
