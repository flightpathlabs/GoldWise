local _, ns = ...

-- Item names, kept between sessions so the Items tab can find things.
--
-- The client only knows an item's name once it has loaded the item, and
-- it forgets them all when the game closes. Searching by name needs them
-- to hand, so every name Goldwise comes across is written down here: from
-- the player's bags, from items the client loads for any reason, and from
-- auction house scans.
--
-- Saved as ns.db.itemNames[itemID] = { name, day }, where day is the
-- last day the name was seen, counted as Ledger.Today counts them. A plain
-- list rather than named fields, as the ledger's day records are: there
-- can be fifteen thousand of these in the saved file. The day is all the
-- pruning needs, and changing it once a day costs nothing, where a time
-- to the second would be rewritten on every sighting.
--
-- Names are never sent anywhere. They're the client's own, and only this
-- player's game reads them back.

local Names = {}
ns.Names = Names

local NAME, DAY = 1, 2

-- Names worked through per frame after a scan. Each is two quick
-- questions to the client, so a whole market takes a dozen frames.
local BATCH_SIZE = 1000

-- What a search returns at most, unless the caller asks for fewer. Past a
-- couple of hundred, nobody scrolls; they type another letter.
local DEFAULT_LIMIT = 200

-- Lower-case names for searching, [itemID] = name. Made the first time
-- anything searches, and kept up to date as names come in after that.
local lowered

-- Today, and when it was last worked out. A scan can note thousands of
-- names in one go, and the day doesn't need asking about for each.
local today, todayCheckedAt

local function Today()
    local now = GetTime()
    if not today or now - todayCheckedAt > 60 then
        today, todayCheckedAt = ns.Ledger.Today(), now
    end
    return today
end

-- The saved names, or nil before the saved data has loaded.
local function Saved()
    return ns.db and ns.db.itemNames
end

--- Writes down an item's name, or notes that it's been seen again.
--- Cheap enough to call for every item in a scan.
---@param itemID number
---@param name string|nil  nothing happens without one
function Names.Note(itemID, name)
    local saved = Saved()
    if not saved or not itemID or not name or name == "" then
        return
    end

    local entry = saved[itemID]
    if not entry then
        saved[itemID] = { name, Today() }
    else
        entry[DAY] = Today()
        if entry[NAME] == name then
            return
        end
        entry[NAME] = name
    end

    if lowered then
        lowered[itemID] = name:lower()
    end
end

--- Writes down an item's name if the client already has it. Never asks
--- the client to fetch anything.
---@param itemID number
function Names.NoteKnown(itemID)
    if C_Item.IsItemDataCachedByID(itemID) then
        Names.Note(itemID, C_Item.GetItemNameByID(itemID))
    end
end

-- Items waiting to be looked at, a few frames' worth at a time. A list
-- read from the front, because emptying a table with next() from the
-- start each time gets slower with every item taken out.
local queue, queued, nextInQueue = {}, {}, 1
local working = false

local function WorkThroughQueue()
    local last = math.min(nextInQueue + BATCH_SIZE - 1, #queue)
    for index = nextInQueue, last do
        local itemID = queue[index]
        queued[itemID] = nil
        Names.NoteKnown(itemID)
    end
    nextInQueue = last + 1

    if nextInQueue > #queue then
        queue, nextInQueue = {}, 1
        working = false
    else
        C_Timer.After(0, WorkThroughQueue)
    end
end

local function Enqueue(itemID)
    if itemID and not queued[itemID] then
        queued[itemID] = true
        queue[#queue + 1] = itemID
    end
end

local function StartWork()
    if not working and #queue >= nextInQueue then
        working = true
        C_Timer.After(0, WorkThroughQueue)
    end
end

--- Takes the names of the items in a page of browse results, for those
--- the client has already loaded. Browse results carry only item keys,
--- and asking for the names of the rest would have the client fetch
--- thousands of items it has no other use for. The work is spread over
--- the next few frames, so a scan isn't held up by it.
---@param rows table  BrowseResultInfo[], from C_AuctionHouse.GetBrowseResults
function Names.NoteBrowseRows(rows)
    for _, row in ipairs(rows) do
        Enqueue(row.itemKey and row.itemKey.itemID)
    end
    StartWork()
end

--- An item's name as last written down, whether or not the client has it
--- this session.
---@param itemID number
---@return string|nil
function Names.Get(itemID)
    local saved = Saved()
    local entry = saved and saved[itemID]
    return entry and entry[NAME]
end

-- Searching -------------------------------------------------------------------

local function Index()
    if not lowered then
        lowered = {}
        for itemID, entry in pairs(Saved() or {}) do
            if type(entry) == "table" and type(entry[NAME]) == "string" then
                lowered[itemID] = entry[NAME]:lower()
            end
        end
    end
    return lowered
end

-- How well a name matches, best first: the name starts with the text, a
-- word in it does ("cloth" in "Linen Cloth"), or the text is somewhere
-- inside. Things in the player's bags come before all of those.
local STARTS, WORD, INSIDE = 1, 2, 3
local IN_BAGS = 0
local OTHERWISE = 3

-- What can come before a word.
local WORD_BREAK = "[%s%-%(\"'/:]"

local function ByName(a, b)
    if a.lower ~= b.lower then
        return a.lower < b.lower
    end
    return a.itemID < b.itemID
end

--- Finds items by name.
---
--- Over fifteen thousand names this is one plain-text search through each,
--- and a sort of only as many matches as are going to be returned.
---@param text string  part of a name, in any case
---@param limit number|nil  most to return; 200 if not given
---@return table matches  list of { itemID, name, inBags }, best first
---@return number total   how many matched in all, which can be more than
---        were returned
function Names.Search(text, limit)
    limit = limit or DEFAULT_LIMIT
    text = strtrim(text or ""):lower()
    if text == "" then
        return {}, 0
    end

    local saved = Saved() or {}
    local inBags = ns.Bags.Counts()

    -- One list per kind of match, so only the lists that fill the limit
    -- need sorting. A two-letter search can match thousands.
    local buckets = {}
    for rank = IN_BAGS + STARTS, OTHERWISE + INSIDE do
        buckets[rank] = {}
    end

    local total = 0
    for itemID, name in pairs(Index()) do
        local at = name:find(text, 1, true)
        if at then
            local rank = INSIDE
            if at == 1 then
                rank = STARTS
            elseif name:sub(at - 1, at - 1):find(WORD_BREAK) then
                rank = WORD
            end

            local held = inBags[itemID] ~= nil
            local bucket = buckets[(held and IN_BAGS or OTHERWISE) + rank]
            bucket[#bucket + 1] = { itemID = itemID, lower = name, inBags = held }
            total = total + 1
        end
    end

    local matches = {}
    for rank = IN_BAGS + STARTS, OTHERWISE + INSIDE do
        local bucket = buckets[rank]
        if #matches >= limit then
            break
        end

        table.sort(bucket, ByName)
        for _, match in ipairs(bucket) do
            if #matches >= limit then
                break
            end
            local entry = saved[match.itemID]
            matches[#matches + 1] = {
                itemID = match.itemID,
                name = entry and entry[NAME] or match.lower,
                inBags = match.inBags,
            }
        end
    end
    return matches, total
end

-- Where names come from -------------------------------------------------------

-- Everything in the bags is loaded by the client, so its name is there to
-- be had. The sellable things come with theirs; the rest are asked for.
ns.Subscribe("BAGS_CHANGED", function()
    for _, holding in ipairs(ns.Bags.Holdings()) do
        Names.Note(holding.itemID, holding.name)
    end
    for itemID in pairs(ns.Bags.Counts()) do
        if not ns.Bags.Holding(itemID) then
            Names.NoteKnown(itemID)
        end
    end
end)

-- After a full read of the market, every item on it is worth a look. A
-- deep scan doesn't pass through Names.NoteBrowseRows, and the client
-- loads a good many of the items as it goes.
ns.Subscribe("SCAN_FINISHED", function()
    if not ns.Market.IsOpen() then
        return
    end
    for itemID in pairs(ns.Ledger.AllPrices(ns.Market.Current())) do
        Enqueue(itemID)
    end
    StartWork()
end)

-- Housekeeping ----------------------------------------------------------------

ns.Subscribe("DATABASE_READY", function()
    if type(ns.db.itemNames) ~= "table" then
        ns.db.itemNames = {}
    end
end)

-- Once per login, as the ledger does, names not seen for as long as price
-- history is kept are let go. An item still followed on any market keeps
-- its name: its history can be opened, and should be findable. Anything
-- let go is written down again the next time it turns up.
ns.OnEvent("PLAYER_LOGIN", function()
    local saved = Saved()
    if not saved then
        return
    end

    local followed = {}
    for _, market in pairs(ns.db.markets) do
        for itemID in pairs(market.tracked or {}) do
            followed[itemID] = true
        end
    end

    local oldest = ns.Ledger.Today() - ns.settings.historyDays
    for itemID, entry in pairs(saved) do
        local broken = type(entry) ~= "table" or type(entry[NAME]) ~= "string"
        if broken or ((entry[DAY] or 0) <= oldest and not followed[itemID]) then
            saved[itemID] = nil
        end
    end
    lowered = nil
end)
