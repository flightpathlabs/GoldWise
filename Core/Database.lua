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

local SCHEMA = 2

local DEFAULT_SETTINGS = {
    -- Scan when the auction house opens, unless we scanned recently.
    autoScan = true,

    -- "Recently", in seconds.
    scanInterval = 15 * 60,

    -- Use the deep scan (every individual auction) when its fifteen-minute
    -- cooldown allows, falling back to the ordinary one.
    deepScan = true,

    -- Days of history to keep for items the player holds or follows. This
    -- is what the player's own game has read, so how long it's kept is up
    -- to them. (The feed is another matter: Blizzard's terms hold that to
    -- thirty days, and the collector sees to it.)
    historyDays = 90,

    -- Days of whole-market snapshots to keep. These are large, so not many.
    marketDays = 10,

    -- Whether the goblin delivers advice at full volume.
    auditorMode = false,

    -- The button on the minimap's rim, and where on the rim it sits, in
    -- degrees anticlockwise from three o'clock.
    minimapButton = true,
    minimapAngle = 215,

    -- The small panel on top of the auction house window that says what
    -- Goldwise is reading and what it found.
    scanPanel = true,

    -- A gold rim and coin on items in bags and the bank that are worth
    -- taking to the auction house.
    markSellable = true,

    -- The two unprompted cards, and whether they make a sound.
    cityPrompt = true,
    recipePrompt = true,
    vendorCheck = true,
    promptSound = false,

    -- An auction price line on item tooltips. Skipped when another addon
    -- already shows one, whatever this says.
    tooltipPrice = true,

    -- A small price chart under item tooltips, for items with history.
    tooltipChart = true,

    -- A tooltip line saying how many of an item the player's other
    -- characters carry. Left to Bagnon when that's installed.
    tooltipHeld = true,

    -- Trade prices with other Goldwise players over a hidden chat channel.
    sharePrices = true,

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
    local settings = EnsureTable(db, "settings")

    -- Schema 2 brought the default history length down from 180 days to
    -- 90. Before then there was no way to choose it, so anyone holding the
    -- old figure simply moves to the new one.
    if (db.schema or SCHEMA) < 2 and settings.historyDays == 180 then
        settings.historyDays = nil
    end
    db.schema = SCHEMA

    FillDefaults(settings, DEFAULT_SETTINGS)
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

-- Errors of our own, kept for bug reports. The same error tends to repeat,
-- so each is kept once with a count.
local ERROR_LIMIT = 20

-- Whether the player has been told this session that something went wrong.
local errorMentioned = false

-- The last error noted and when, to tell a repeat from an echo.
local lastNoted, lastNotedAt = nil, 0

--- Notes an error raised by one of Goldwise's own handlers.
---@param message string  the error text
---@param stack string    where it happened
function ns.NoteError(message, stack)
    if not ns.db then
        return
    end

    local errors = EnsureTable(ns.db, "errors")
    message = tostring(message)

    -- One failure can reach us twice, by the two routes below. Count it once.
    local now = GetTime()
    if message == lastNoted and now - lastNotedAt < 1 then
        return
    end
    lastNoted, lastNotedAt = message, now

    for _, known in ipairs(errors) do
        if known.message == message then
            known.count = known.count + 1
            known.at = date("%m-%d %H:%M:%S")
            return
        end
    end

    table.insert(errors, {
        message = message,
        stack = stack,
        count = 1,
        at = date("%m-%d %H:%M:%S"),
        version = C_AddOns.GetAddOnMetadata(addonName, "Version"),
    })
    while #errors > ERROR_LIMIT do
        table.remove(errors, 1)
    end

    -- Once a session is enough. The game shows the error itself to
    -- anyone who has asked to see them; this is for everyone else.
    if not errorMentioned then
        errorMentioned = true
        ns.Print("Something went wrong inside Goldwise. Type /gw report to send in the details.")
    end
end

-- Errors in our event handlers are noted where they're caught (see
-- Events.lua). That leaves the ones raised from a button click or a timer,
-- which go straight to the game's error handler. So we stand in front of
-- it: anything that names Goldwise is noted, and everything, ours or not,
-- is passed on exactly as it came. Done at login, once the other addons
-- that take an interest in errors have put their own handlers in place.
ns.OnEvent("PLAYER_LOGIN", function()
    local passOn = geterrorhandler()

    seterrorhandler(function(message, ...)
        if type(message) == "string" and message:find(addonName, 1, true) then
            pcall(ns.NoteError, message, debugstack(2, 12, 0))
        end
        return passOn(message, ...)
    end)
end)

--- Returns the saved data for one market, creating it on first use.
---@param marketKey string  from ns.Market
---@return table market  { tracked = {}, daily = {}, lastScan = number|nil }
function ns.MarketData(marketKey)
    local market = EnsureTable(ns.db.markets, marketKey)
    EnsureTable(market, "tracked")
    EnsureTable(market, "daily")
    return market
end
