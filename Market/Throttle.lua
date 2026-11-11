local _, ns = ...

-- The auction house only accepts one request at a time and silently drops
-- anything sent while it's busy. Everything Goldwise asks of it goes
-- through this queue.

local Throttle = {}
ns.Throttle = Throttle

local queue = {}

--- Runs request as soon as the auction house will accept it.
---
--- By the time a queued request's turn comes, whatever asked for it may
--- have given up. So each request decides for itself whether it's still
--- wanted, and returns true only if it really sent something.
---@param request fun(): boolean|nil
function Throttle.WhenReady(request)
    if C_AuctionHouse.IsThrottledMessageSystemReady() then
        request()
    else
        table.insert(queue, request)
    end
end

--- Forgets everything waiting. Called when the auction house closes.
function Throttle.Clear()
    table.wipe(queue)
end

ns.OnEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    -- Send one request per signal, because sending makes the auction house
    -- busy again. A request that's no longer wanted sends nothing, so keep
    -- going past it. Otherwise everything behind it would wait for a
    -- signal that never comes.
    while queue[1] do
        local request = table.remove(queue, 1)
        if request() then
            break
        end
    end
end)

ns.Subscribe("AUCTION_HOUSE_CLOSED", Throttle.Clear)
