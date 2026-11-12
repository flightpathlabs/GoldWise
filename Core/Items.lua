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

-- The client doesn't always answer. It gets this many seconds of silence
-- before it's asked again, and this many askings before we stop waiting:
-- a list that waits for ever on one item is worse than a list without it.
--
-- Silence, not time. Ask for a hundred items and the client works through
-- them in its own time, which can be a good deal longer than this. While
-- answers are still coming, the ones that haven't are only further back
-- in the queue.
local PATIENCE = 5
local MOST_ASKS = 2

-- Items we've asked for and not yet heard back about, each with when it
-- was last asked for and how many times.
local awaited = {}

-- Items the client couldn't give us. Not asked for again: asking on
-- every redraw would never end.
local unavailable = {}

-- When the client last gave us any item we were waiting on.
local lastArrival = 0

local announcePending = false
local watching = false

local function Announce()
    if announcePending then
        return
    end
    announcePending = true
    C_Timer.After(SETTLE_DELAY, function()
        announcePending = false
        ns.Publish("ITEM_NAMES_LOADED")
    end)
end

-- Looks in on what's still awaited, and keeps looking for as long as
-- anything is.
local Watch

local function KeepWatch()
    if not watching then
        watching = true
        C_Timer.After(PATIENCE, Watch)
    end
end

function Watch()
    watching = false

    local now = GetTime()
    local changed, waiting = false, false

    for itemID, wait in pairs(awaited) do
        if C_Item.GetItemNameByID(itemID) then
            -- It arrived without the event that should have said so.
            awaited[itemID] = nil
            lastArrival = now
            changed = true
        elseif now - math.max(wait.since, lastArrival) < PATIENCE then
            waiting = true
        elseif wait.asks < MOST_ASKS then
            wait.asks = wait.asks + 1
            wait.since = now
            C_Item.RequestLoadItemDataByID(itemID)
            waiting = true
        else
            awaited[itemID] = nil
            unavailable[itemID] = true
            changed = true
        end
    end

    -- A list holding a place for something that isn't coming needs to
    -- hear that as much as it needs to hear about an arrival.
    if changed then
        Announce()
    end
    if waiting then
        KeepWatch()
    end
end

--- An item's name, if the client has it yet. If it hasn't, the item is
--- asked for, and ITEM_NAMES_LOADED is published once it's here or once
--- it's clear that it isn't coming.
---@param itemID number
---@return string|nil name
---@return boolean coming  true while there's no name but one is on its
---        way; false with no name means the client has none to give
function ns.ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if name then
        return name, false
    end
    if unavailable[itemID] then
        return nil, false
    end

    if not awaited[itemID] then
        awaited[itemID] = { since = GetTime(), asks = 1 }
        C_Item.RequestLoadItemDataByID(itemID)
        KeepWatch()
    end
    return nil, true
end

--- An item's name for a sentence that can't wait for one: the name if
--- the client has it, and "item 1234" until it does. Asks for the name,
--- as ns.ItemName does, so whatever shows it gets told to redraw.
---@param itemID number
---@return string
function ns.ItemLabel(itemID)
    return ns.ItemName(itemID) or ("item " .. itemID)
end

local function OnItemLoaded(itemID, success)
    -- Given up on, and here after all. Whatever was drawn without it
    -- will want to know.
    if unavailable[itemID] and success and C_Item.GetItemNameByID(itemID) then
        unavailable[itemID] = nil
        Announce()
        return
    end

    -- This fires for every item anything in the game loads. Only the
    -- ones we asked for are ours to act on.
    if not awaited[itemID] then
        return
    end
    awaited[itemID] = nil
    lastArrival = GetTime()

    -- Told it loaded, and still nameless: there's no name coming.
    if not success or not C_Item.GetItemNameByID(itemID) then
        unavailable[itemID] = true
    end
    Announce()
end

-- The client has two ways of saying an item has arrived, and which one it
-- uses depends on how the item came to be loaded. Either will do.
ns.OnEvent("GET_ITEM_INFO_RECEIVED", OnItemLoaded)
ns.OnEvent("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
