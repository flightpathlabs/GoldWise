local addonName, ns = ...

-- Saved data.
--
-- One account-wide table, GoldwiseDB, laid out like this:
--
--   schema     version of this layout, for migrations
--   settings   the player's options
--   markets    price data, one entry per auction house market (see Ledger)
--   places     where auction houses are, learned by visiting them
--   feedHouses which house in the price feed serves each market (see Feed)
--   characters what each character held when last played (see Characters)
--   log        the last couple of hundred diagnostic lines
--
-- Forever's beta builds had a bug where saved data was written but not read
-- back. It's fixed in the build we developed on, but the lesson stands:
-- never assume the table is there, and never replace what did load with
-- defaults. We only ever fill in what's missing.

local SCHEMA = 1

local DEFAULT_SETTINGS = {
    -- Scan when the auction house opens, unless we scanned recently.
    autoScan = true,

    -- "Recently", in seconds.
    scanInterval = 15 * 60,

    -- Use the deep scan (every individual auction) when its fifteen-minute
    -- cooldown allows, falling back to the ordinary one.
    deepScan = true,

    -- Days of history to keep for items the player holds or follows.
    historyDays = 180,

    -- Days of whole-market snapshots to keep. These are large, so not many.
    marketDays = 10,

    -- Whether the goblin delivers advice at full volume.
    auditorMode = false,

    -- The button on the minimap's rim, and where on the rim it sits, in
    -- degrees anticlockwise from three o'clock.
    minimapButton = true,
    minimapAngle = 215,

    -- An auction price line on item tooltips. Left to Auctionator when
    -- that's installed, whatever this says.
    tooltipPrice = true,

    -- A small price chart under item tooltips, for items with history.
    tooltipChart = true,

    -- A tooltip line saying how many of an item the player's other
    -- characters carry. Left to Bagnon when that's installed.
    tooltipHeld = true,

    -- Whether the list shows every character's holdings or just this one's.
    allCharacters = true,
}

-- The options page needs these too, for its "Defaults" button.
ns.DEFAULT_SETTINGS = DEFAULT_SETTINGS

-- Copies defaults into target wherever target has no value of its own.
local function FillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
end

-- Returns db[key] if it's a table, otherwise puts a fresh one there.
local function EnsureTable(db, key)
    if type(db[key]) ~= "table" then
        db[key] = {}
    end
    return db[key]
end

ns.OnEvent("ADDON_LOADED", function(name)
    if name ~= addonName then
        return
    end

    if type(GoldwiseDB) ~= "table" then
        GoldwiseDB = {}
    end

    local db = GoldwiseDB
    db.schema = db.schema or SCHEMA

    FillDefaults(EnsureTable(db, "settings"), DEFAULT_SETTINGS)
    EnsureTable(db, "markets")
    EnsureTable(db, "places")

    ns.db = db
    ns.settings = db.settings

    ns.Publish("DATABASE_READY")
end)

-- Diagnostics ------------------------------------------------------------------

-- A short running log, kept in the saved data. When a scan misbehaves on
-- someone's machine, this is what tells us what happened without asking
-- them to reproduce it.
local LOG_LIMIT = 200

--- Adds a line to the diagnostic log. Arguments are as for string.format.
function ns.Log(text, ...)
    -- Things can happen before the saved data has loaded. Rare, and not
    -- worth holding on to.
    if not ns.db then
        return
    end

    if select("#", ...) > 0 then
        text = text:format(...)
    end

    local log = EnsureTable(ns.db, "log")
    table.insert(log, date("%m-%d %H:%M:%S ") .. text)
    while #log > LOG_LIMIT do
        table.remove(log, 1)
    end
end

--- Returns the saved data for one market, creating it on first use.
---@param marketKey string  from ns.Market
---@return table market  { tracked = {}, daily = {}, lastScan = number|nil }
function ns.MarketData(marketKey)
    local market = EnsureTable(ns.db.markets, marketKey)
    EnsureTable(market, "tracked")
    EnsureTable(market, "daily")
    return market
end
