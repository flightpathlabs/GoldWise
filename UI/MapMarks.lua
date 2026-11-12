local _, ns = ...

-- Pointing the player at a place.
--
-- For now this uses only what the game provides: its world map and its
-- single waypoint pin. That works for everyone. Where a map addon offers
-- more (several pins, routes), it can be plugged in here without the rest
-- of Goldwise knowing the difference.

local MapMarks = {}
ns.MapMarks = MapMarks

--- The name of a zone, in the player's language.
---@param mapID number
---@return string
function MapMarks.ZoneName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. mapID)
end

--- Opens the world map on a zone and drops the game's waypoint pin at a
--- spot in it.
---@param mapID number
---@param x number  0 to 1, left to right
---@param y number  0 to 1, top to bottom
function MapMarks.ShowPoint(mapID, x, y)
    -- The world map is one of the panels the game won't let addons open
    -- during combat.
    if InCombatLockdown() then
        ns.Print("The map can't be opened in combat. Try again in a moment.")
        return
    end

    if C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end

    OpenWorldMap(mapID)
end

--- Opens the world map on a zone, with the waypoint in the middle of it.
---
--- For when we know the zone but not a spot within it. It's a "head this
--- way", not an X on the treasure.
---@param mapID number
function MapMarks.ShowZone(mapID)
    MapMarks.ShowPoint(mapID, 0.5, 0.5)
end
