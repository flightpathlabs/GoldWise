local _, ns = ...

-- Two small message buses.
--
-- Game events come from the client. Messages are how Goldwise's own parts
-- tell each other that something changed, so the scanner can announce a
-- finished scan without knowing that a window exists to redraw.

local frame = CreateFrame("Frame")
local eventHandlers = {}
local messageHandlers = {}

--- Calls handler whenever the client fires a game event.
--- Several handlers can share one event; they run in the order they were added.
---@param event string
---@param handler fun(...)
---@return boolean registered  false if this client has no such event
function ns.OnEvent(event, handler)
    if not eventHandlers[event] then
        -- RegisterEvent throws on names the client doesn't know, and Forever
        -- lacks a few events that retail has. Better to carry on without
        -- one feature than to stop the whole file loading.
        if not pcall(frame.RegisterEvent, frame, event) then
            return false
        end
        eventHandlers[event] = {}
    end

    table.insert(eventHandlers[event], handler)
    return true
end

-- Runs every handler even if one of them fails. The failure still reaches
-- the game's error display; it just doesn't take the handlers queued
-- behind it down as well. Without this, one bad login handler would stop
-- the options page, registered later in the same event, from existing.
local function Dispatch(handlers, ...)
    for _, handler in ipairs(handlers) do
        xpcall(handler, geterrorhandler(), ...)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(eventHandlers[event], ...)
end)

--- Calls handler whenever another part of Goldwise publishes a message.
---@param message string
---@param handler fun(...)
function ns.Subscribe(message, handler)
    messageHandlers[message] = messageHandlers[message] or {}
    table.insert(messageHandlers[message], handler)
end

--- Tells everyone subscribed to a message that it happened.
---@param message string
function ns.Publish(message, ...)
    local handlers = messageHandlers[message]
    if handlers then
        Dispatch(handlers, ...)
    end
end

-- Messages in use, so there's one place to look them up:
--
--   DATABASE_READY                  saved data is loaded and safe to read
--   AUCTION_HOUSE_OPENED            market key for the house we're standing at
--   AUCTION_HOUSE_CLOSED
--   SCAN_STARTED
--   SCAN_PROGRESS    done, total    how far a scan has got; total is nil
--                                   when the scan can't know it in advance
--   SCAN_FINISHED    items, seconds
--   SCAN_STOPPED     reason         gave up; reason is fit to show the player
--   PRICES_CHANGED   marketKey      the ledger has new prices
--   BAGS_CHANGED                    what the player carries has changed
--   PROFILE_CHANGED                 the player's level or professions changed
--   PURSE_CHANGED                   money, gear wear or known costs changed
--   SETTINGS_CHANGED                the player changed an option
--
-- PRICES_CHANGED also fires when another player shares prices with us.
