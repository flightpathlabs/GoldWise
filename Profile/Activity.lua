local _, ns = ...

-- What the player spends their time doing, and what it brings in.
--
-- Play is cut into stretches of five minutes. The time in a stretch is
-- shared among the things the player did in it, by how many times they
-- did each: killing one kind of creature in one zone, gathering herbs,
-- ore or hides, fishing, or handing in quests. Only time close to
-- something being done counts, up to a minute and a half after the last
-- of it, and none spent away from the keyboard, dead, on a flight, or at
-- a vendor, the auction house, the mailbox or the bank: that's selling,
-- not earning.
--
-- What came in goes to whatever brought it in. The coin and things from
-- a loot window go to the creature, the gathering or the fishing behind
-- it; a quest's coin and reward go to questing. Things are valued as they
-- arrive, the way Goldwise would have them sold. Coin from sales and the
-- post isn't earning in this sense, and nor is anything bought, posted,
-- brought out of the bank, taken off, or found inside something opened
-- from the bags, which was counted already as the thing it came in.
--
-- Totals are kept by day for thirty days, once for the account and once
-- for each character, so the Money tab can say what pays. The last two
-- days are kept stretch by stretch as well, so a session or the last few
-- hours can be added up from when they began rather than from midnight.

local Activity = {}
ns.Activity = Activity

local STRETCH_SECONDS = 5 * 60

local KEEP_DAYS = 30

-- How long stretches are kept one by one.
local KEEP_EXACT = 48 * 60 * 60

-- Time goes on counting for this long after the player last did
-- something. Running from one kill or herb to the next is part of the
-- work; standing about after a single kill isn't.
local IDLE_GRACE = 90

-- Loot lands in the bags a moment after the window that gave it, and
-- Bags.lua waits half a second more before saying so. Things arriving
-- this long after the window closed are still taken to be from it.
local LATE_ITEMS = 3

-- New things are valued together this long after the first of them
-- arrives, rather than each time the bags change.
local VALUE_DELAY = 2

-- A gathering spell, or one that takes an item apart, marks the loot
-- window opening within this many seconds of it as its own.
local CAST_WINDOW = 3

-- How often to look at whether the player is on a flight or dead, in
-- case the game's word on it was missed.
local STATE_CHECK = 5

-- Which activity leads a stretch when two had as many events. A creature
-- skinned is a creature killed first, so the kill comes first.
local KIND_ORDER = { kill = 1, gather = 2, fish = 3, quest = 4 }

-- How each kind of gathering reads.
local GATHER_LABELS = { herbalism = "Herbalism", mining = "Mining", skinning = "Skinning" }

-- The gathering spells Profile\Drops.lua knows from corpses, with the
-- ones that open a herb or a vein in the world beside them.
local GATHER_SPELLS = {
    [2366] = "herbalism", -- a herb in the world
    [1235236] = "herbalism", -- a herb from a corpse
    [2575] = "mining", -- a vein
    [1235230] = "mining", -- ore from a corpse
    [8613] = "skinning", -- each rank
    [8617] = "skinning",
    [8618] = "skinning",
    [10768] = "skinning",
}

-- For ranks the list above doesn't know, the names of these are matched
-- instead, in the game's own language.
local GATHER_NAMES_FROM = { 2366, 1235236, 2575, 8613 }

-- Spells whose loot comes out of something from the bags: Disenchant,
-- and Prospecting and Milling should the client have them.
local TAKING_APART = { [13262] = true, [31252] = true, [51005] = true }

-- Units a corpse being looted is likely to be when the client won't say
-- which creature the loot came from, as in Drops.lua.
local CORPSE_UNITS = { "softinteract", "mouseover", "target" }

-- Windows whose time isn't spent earning. Any this client lacks are
-- skipped.
local SELLING_WINDOWS = {
    "Merchant",
    "Auctioneer",
    "MailInfo",
    "Banker",
    "CharacterBanker",
    "AccountBanker",
    "GuildBanker",
}

-- Windows things can come into the bags through without having been
-- earned: bought, posted, traded or taken out of a bank.
local INCOMING_WINDOWS = {
    "Merchant",
    "Auctioneer",
    "MailInfo",
    "Banker",
    "CharacterBanker",
    "AccountBanker",
    "GuildBanker",
    "TradePartner",
}

-- Maps of caves and the like, which belong to the zone they're in.
local MICRO_MAP = Enum.UIMapType and Enum.UIMapType.Micro or 5

-- The saved record, ns.db.activity:
--
--   days        the account's: [day] = { [key] = { seconds, earned } }
--   characters  each character's, by character key, laid out as days
--   names       [key] = { label, where }, as last seen
--   latest      each character's last two days, by character key: a list
--               of { at, span, key, seconds, earned }, one for each
--               activity in each stretch, oldest first. at is the server
--               time the stretch began and span how long it ran.
--   latestFrom  the server time stretches began to be kept one by one
--
-- Days are counted as Ledger.Today counts them, seconds are time spent
-- and earned is copper. A key says what the activity was and where:
-- "kill:<npcID>:<zone>", "gather:<herbalism|mining|skinning>:<zone>",
-- "fish:<zone>" or "quest:<zone>", where the zone is its map ID, or its
-- name when the game gives no map.
local function Book()
    if type(ns.db.activity) ~= "table" then
        ns.db.activity = {}
    end
    local book = ns.db.activity
    for _, part in ipairs({ "days", "characters", "names", "latest" }) do
        if type(book[part]) ~= "table" then
            book[part] = {}
        end
    end
    return book
end

local function OwnDays()
    local characters = Book().characters
    local key = ns.Characters.CurrentKey()
    if type(characters[key]) ~= "table" then
        characters[key] = {}
    end
    return characters[key]
end

local function OwnLatest()
    local latest = Book().latest
    local key = ns.Characters.CurrentKey()
    if type(latest[key]) ~= "table" then
        latest[key] = {}
    end
    return latest[key]
end

-- The days to read back. whose is as for Trade.Flow; reading another
-- character's never makes them a record.
local function DaysFor(whose)
    local book = Book()
    if whose == true then
        return book.days
    end
    if not whose or whose == ns.Characters.CurrentKey() then
        return OwnDays()
    end
    local theirs = book.characters[whose]
    return type(theirs) == "table" and theirs or {}
end

-- The stretches to read back, as a list of lists: everyone's for the
-- account, which has none of its own.
local function LatestFor(whose)
    local latest = Book().latest
    local lists = {}
    if whose == true then
        for _, list in pairs(latest) do
            if type(list) == "table" then
                table.insert(lists, list)
            end
        end
    else
        local list = latest[whose or ns.Characters.CurrentKey()]
        table.insert(lists, type(list) == "table" and list or {})
    end
    return lists
end

local function KindOf(key)
    return key:match("^(%a+)")
end

-- In restricted content some answers come back as values an addon may
-- hold but not read.
local function Readable(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

-- Where the player is ----------------------------------------------------------

-- [uiMapID] = { key, name } for the zone that map is part of, worked out
-- once a session.
local zones = {}

local function ZoneOf(mapID)
    local zone = zones[mapID]
    if zone then
        return zone
    end

    local info = C_Map.GetMapInfo(mapID)
    local steps = 0
    while info and info.mapType == MICRO_MAP and info.parentMapID and steps < 5 do
        info = C_Map.GetMapInfo(info.parentMapID)
        steps = steps + 1
    end
    zone = info and { info.mapID, info.name } or { mapID, Readable(GetRealZoneText()) }
    zones[mapID] = zone
    return zone
end

-- The zone the player is in: something to put in a key, and its name.
local function Here()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID then
        local zone = ZoneOf(mapID)
        return zone[1], zone[2]
    end
    local name = Readable(GetRealZoneText())
    if type(name) == "string" and name ~= "" then
        return name, name
    end
    return "?", nil
end

-- The stretch under way ------------------------------------------------------------

-- { startedAt, counts, about, earned, loose, active }. startedAt is the
-- server time it began. counts is [key] = events and about is [key] =
-- { label, where }. earned is [key] = copper brought in by that
-- activity, and loose is copper that came in from something we couldn't
-- tell, shared out like the time when the stretch closes. active is how
-- many seconds of it count.
local stretch

-- When the player last did something, by GetTime, and what it was. Time
-- is counted on from countedTo, up to IDLE_GRACE past lastDoneAt.
local lastDoneAt, lastKey
local countedTo

-- What stops time counting: being away, on a flight, dead or a ghost, or
-- having a selling window open.
local away, onTaxi, dead = false, false, false
local sellingOpen = {}

local function Paused()
    return away or onTaxi or dead or next(sellingOpen) ~= nil
end

-- Counts the time since it was last counted, as things stood until now.
-- Called before anything that changes them, so each moment is judged by
-- what held at the time.
local function Accrue()
    local now = GetTime()
    if stretch and countedTo and lastDoneAt and not Paused() then
        local to = math.min(now, lastDoneAt + IDLE_GRACE)
        if to > countedTo then
            stretch.active = stretch.active + to - countedTo
        end
    end
    countedTo = now
end

local function Begin()
    stretch = {
        startedAt = GetServerTime(),
        counts = {},
        about = {},
        earned = {},
        loose = 0,
        active = 0,
    }
end

-- Keeps what's known of an activity in this stretch. A creature's name
-- can be missing one time and known the next, so what's known is kept.
local function Know(key, label, where)
    if not stretch then
        return
    end
    local about = stretch.about[key] or {}
    about[1] = label or about[1]
    about[2] = where or about[2]
    stretch.about[key] = about
end

-- Puts one event down to an activity in this stretch.
local function Note(key, label, where)
    if not stretch then
        return
    end
    Accrue()
    stretch.counts[key] = (stretch.counts[key] or 0) + 1
    lastDoneAt, lastKey = GetTime(), key
    Know(key, label, where)
end

-- How many events the stretch has had, all told.
local function EventCount()
    local total = 0
    for _, count in pairs(stretch.counts) do
        total = total + count
    end
    return total
end

-- The activity with the most events in this stretch, if any.
local function Leader()
    local best, bestCount
    for key, count in pairs(stretch.counts) do
        local better = not best or count > bestCount
        if not better and count == bestCount then
            local kind, bestKind = KIND_ORDER[KindOf(key)] or 9, KIND_ORDER[KindOf(best)] or 9
            better = kind < bestKind or (kind == bestKind and key < best)
        end
        if better then
            best, bestCount = key, count
        end
    end
    return best
end

-- Puts copper down to what brought it in. shares is [key] = weight, and
-- the copper is split by weight; with no shares it's loose.
local function Credit(shares, copper)
    if not stretch or copper <= 0 then
        return
    end
    local total = 0
    for _, weight in pairs(shares or {}) do
        total = total + weight
    end
    if total <= 0 then
        stretch.loose = stretch.loose + copper
        return
    end
    for key, weight in pairs(shares) do
        stretch.earned[key] = (stretch.earned[key] or 0) + copper * weight / total
    end
end

-- Something with a creature's name, from the unit it's on if the player
-- has it in view, or from what Drops has on record.
local function CreatureName(guid, npcID)
    local unit
    if UnitTokenFromGUID then
        local ok, token = pcall(UnitTokenFromGUID, guid)
        unit = ok and Readable(token)
    end
    local name = unit and Readable(UnitName(unit))
    if type(name) == "string" and name ~= "" then
        return name
    end
    local drops = ns.Drops.Get(npcID)
    return drops and drops.name
end

local function KillKey(npcID, zone)
    return ("kill:%d:%s"):format(npcID, zone)
end

-- Things that came in --------------------------------------------------------------

-- What was in the bags at the last look, as [itemID] = count.
local lastCounts

-- What's come in from loot and quests and is still to be valued, by what
-- brought it in: [shares] = { [itemID] = count }, with shares as for
-- Credit. What came from nothing we could tell is kept under LOOSE.
local LOOSE = {}
local unvalued = {}
local valuePending = false

-- The windows things are earned through: a loot window on something in
-- the world, and a quest's reward page. earnedUntil is how long after the
-- last of them closed things arriving still count, and earningFor what
-- they're put down to: lootShares or questShares, whichever opened last.
local lootOpen, questOpen = false, false
local earnedUntil = 0
local lootShares, questShares
local earningFor

-- A loot window on something from the bags: a box, a clam, or something
-- being taken apart. What it holds was counted already as the thing
-- itself, so neither its coin nor what comes into the bags from it is
-- earned, until LATE_ITEMS after it closes.
local itemLootOpen = false
local lootFromItem = false
local unearnedUntil = 0

-- The windows things can come in through unearned that are open now, and
-- whether any has been since the last look.
local incomingOpen = {}
local incomingSinceLook = false

local function Earning()
    return lootOpen or questOpen or GetTime() <= earnedUntil
end

local function Unearned()
    return itemLootOpen or GetTime() <= unearnedUntil
end

local function ValueNew()
    valuePending = false
    if not next(unvalued) then
        return
    end
    local batches = unvalued
    unvalued = {}
    if not stretch then
        return
    end

    local home = ns.Market.Home()
    for shares, counts in pairs(batches) do
        local holdings = {}
        for itemID, count in pairs(counts) do
            table.insert(holdings, { itemID = itemID, count = count })
        end
        local auction, vendor = ns.Assets.SaleValue(holdings, home)
        Credit(shares, auction + vendor)
    end
end

local function ValueSoon()
    if valuePending then
        return
    end
    valuePending = true
    C_Timer.After(VALUE_DELAY, ValueNew)
end

-- The bags are compared with how they were at the last look. Only what
-- went up counts, and only while something was being earned with nothing
-- open that could have brought it in otherwise.
ns.Subscribe("BAGS_CHANGED", function()
    local counts = ns.Bags.Counts()
    if lastCounts and stretch and Earning() and not incomingSinceLook and not Unearned() then
        local batch
        for itemID, count in pairs(counts) do
            local more = count - (lastCounts[itemID] or 0)
            if more > 0 then
                local shares = earningFor or LOOSE
                batch = batch or unvalued[shares] or {}
                unvalued[shares] = batch
                batch[itemID] = (batch[itemID] or 0) + more
            end
        end
        if batch then
            ValueSoon()
        end
    end

    lastCounts = CopyTable(counts)
    incomingSinceLook = next(incomingOpen) ~= nil or Unearned()
end)

-- The quest being handed in, as something to put its coin and reward to.
local function QuestShares()
    local zone, where = Here()
    local key = "quest:" .. zone
    Know(key, "Questing", where)
    return { [key] = 1 }
end

ns.Subscribe("MONEY_MOVED", function(delta, category)
    if not stretch or delta <= 0 then
        return
    end
    if category == "quest" then
        Credit(questShares or QuestShares(), delta)
    elseif category == "loot" and not lootFromItem then
        Credit(lootShares, delta)
    end
end)

-- Closing a stretch ----------------------------------------------------------------

local function AddTo(days, day, key, seconds, earned)
    local record = days[day]
    if type(record) ~= "table" then
        record = {}
        days[day] = record
    end
    local totals = record[key]
    if type(totals) ~= "table" then
        totals = { 0, 0 }
        record[key] = totals
    end
    totals[1] = (totals[1] or 0) + seconds
    totals[2] = (totals[2] or 0) + earned
end

-- Lets go of stretches more than two days gone.
local function TrimLatest(list)
    local oldest = GetServerTime() - KEEP_EXACT
    local kept = 0
    for index = 1, #list do
        local entry = list[index]
        if type(entry) == "table" and (entry[1] or 0) + (entry[2] or 0) >= oldest then
            kept = kept + 1
            list[kept] = entry
        end
    end
    for index = #list, kept + 1, -1 do
        list[index] = nil
    end
end

-- The day last trimmed, so it's done once a day and no more.
local lastTrimmed

-- Lets go of days past keeping, stretches past two days, and names
-- nothing refers to any more.
local function Trim()
    local book = Book()
    lastTrimmed = ns.Ledger.Today()
    local oldest = lastTrimmed - KEEP_DAYS + 1
    local inUse = {}

    -- Kept from when this was first loaded, so that an older period than
    -- that is never added up from stretches that aren't all there.
    book.latestFrom = book.latestFrom or GetServerTime()

    local function TrimDays(days)
        for day, record in pairs(days) do
            if type(day) ~= "number" or day < oldest or type(record) ~= "table" then
                days[day] = nil
            else
                for key in pairs(record) do
                    inUse[key] = true
                end
            end
        end
    end

    TrimDays(book.days)
    for key, days in pairs(book.characters) do
        if type(days) == "table" then
            TrimDays(days)
        end
        if type(days) ~= "table" or next(days) == nil then
            book.characters[key] = nil
        end
    end
    for key, list in pairs(book.latest) do
        if type(list) == "table" then
            TrimLatest(list)
        end
        if type(list) ~= "table" or #list == 0 then
            book.latest[key] = nil
        end
    end
    for key in pairs(book.names) do
        if not inUse[key] then
            book.names[key] = nil
        end
    end
end

-- Puts the stretch on record: its time shared among what was done in it,
-- and what came in to whatever brought it. Unless the player is on their
-- way out, the next one starts.
local function Close(leaving)
    if not stretch or not ns.db then
        return
    end

    -- What's come in and not yet been valued belongs to this stretch.
    ValueNew()
    Accrue()

    local shares, events = stretch.counts, EventCount()
    if events == 0 and lastKey and stretch.active > 0 then
        -- Only the last moments after something done in the stretch
        -- before. They're that thing's.
        shares, events = { [lastKey] = 1 }, 1
    end

    -- [key] = { seconds, earned }, before rounding.
    local filed = {}
    for key, count in pairs(shares) do
        local share = count / events
        filed[key] = { stretch.active * share, stretch.loose * share }
    end
    for key, copper in pairs(stretch.earned) do
        filed[key] = filed[key] or { 0, 0 }
        filed[key][2] = filed[key][2] + copper
    end

    local day = ns.Ledger.DayOf(stretch.startedAt)
    local span = math.max(0, GetServerTime() - stretch.startedAt)
    local names = Book().names
    local latest = OwnLatest()
    local lead, leadSeconds = nil, -1
    for key, figures in pairs(filed) do
        local seconds = math.floor(figures[1] + 0.5)
        local earned = math.floor(figures[2] + 0.5)
        if seconds > 0 or earned > 0 then
            AddTo(Book().days, day, key, seconds, earned)
            AddTo(OwnDays(), day, key, seconds, earned)
            table.insert(latest, { stretch.startedAt, span, key, seconds, earned })

            local about = stretch.about[key] or {}
            local known = type(names[key]) == "table" and names[key] or {}
            names[key] = { about[1] or known[1], about[2] or known[2] }

            if seconds > leadSeconds or (seconds == leadSeconds and key < lead) then
                lead, leadSeconds = key, seconds
            end
        end
    end

    if lead then
        TrimLatest(latest)
        if ns.Ledger.Today() ~= lastTrimmed then
            Trim()
        end
    end

    if leaving then
        stretch = nil
        return
    end
    Begin()
    ns.Publish("ACTIVITY_CHANGED", lead)
end

-- Events ---------------------------------------------------------------------------

ns.OnEvent("PARTY_KILL", function(attackerGUID, targetGUID)
    -- The player's kills and their pet's. A group's other members' kills
    -- are theirs, as Drops.lua has it.
    attackerGUID, targetGUID = Readable(attackerGUID), Readable(targetGUID)
    if
        not attackerGUID or (attackerGUID ~= UnitGUID("player") and attackerGUID ~= UnitGUID("pet"))
    then
        return
    end
    local npcID = ns.Drops.NpcID(targetGUID)
    if not npcID then
        return
    end
    local zone, where = Here()
    Note(KillKey(npcID, zone), CreatureName(targetGUID, npcID), where)
end)

-- [name] = kind of gathering, for the names in GATHER_NAMES_FROM. Made
-- when first needed, and again if the game hadn't the names to hand.
local gatherNames

local function GatherKind(spellID)
    if GATHER_SPELLS[spellID] then
        return GATHER_SPELLS[spellID]
    end
    if not gatherNames or next(gatherNames) == nil then
        gatherNames = {}
        for _, known in ipairs(GATHER_NAMES_FROM) do
            local name = C_Spell.GetSpellName(known)
            if name then
                gatherNames[name] = GATHER_SPELLS[known]
            end
        end
    end
    local name = Readable(C_Spell.GetSpellName(spellID))
    return name and gatherNames[name]
end

-- The last gathering cast, { key, at }, and when something was last
-- taken apart. Each marks the one loot window that opens just after.
local lastGather
local takenApartAt

-- The player's own casts only. A frame of its own, as in Drops.lua, since
-- the shared one would hear everyone in sight casting.
local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, spellID)
    spellID = Readable(spellID)
    if not spellID then
        return
    end
    if TAKING_APART[spellID] then
        takenApartAt = GetTime()
        return
    end
    local kind = GatherKind(spellID)
    if kind then
        local zone, where = Here()
        local key = ("gather:%s:%s"):format(kind, zone)
        Note(key, GATHER_LABELS[kind], where)
        lastGather = { key = key, at = GetTime() }
    end
end)

-- Packs a function's answers into a list that keeps any nils in place.
local function Pack(...)
    return { n = select("#", ...), ... }
end

-- Whether the loot window opening now is on something from the bags
-- though the game didn't say so: something just taken apart, or loot the
-- client says came from an item.
local function OpenedFromBags()
    if takenApartAt and GetTime() - takenApartAt <= CAST_WINDOW then
        takenApartAt = nil
        return true
    end
    if type(GetLootSourceInfo) == "function" and GetNumLootItems() > 0 then
        local guid = Readable((GetLootSourceInfo(1)))
        return type(guid) == "string" and guid:find("^Item%-") ~= nil
    end
    return false
end

-- What the loot window opening now is from, as shares for Credit: the
-- fishing, the gathering cast just before it, or the creatures the client
-- says its slots came from, by how many slots each. Failing all of those,
-- the corpse in view. Empty if there's no telling.
local function LootShares()
    local zone, where = Here()
    if IsFishingLoot and IsFishingLoot() then
        local key = "fish:" .. zone
        Note(key, "Fishing", where)
        return { [key] = 1 }
    end

    local gather = lastGather
    lastGather = nil
    if gather and GetTime() - gather.at <= CAST_WINDOW then
        return { [gather.key] = 1 }
    end

    local shares = {}
    if type(GetLootSourceInfo) == "function" then
        for slot = 1, GetNumLootItems() do
            local sources = Pack(GetLootSourceInfo(slot))
            for index = 1, sources.n, 2 do
                local guid = Readable(sources[index])
                local npcID = ns.Drops.NpcID(guid)
                if npcID then
                    local key = KillKey(npcID, zone)
                    Know(key, CreatureName(guid, npcID), where)
                    shares[key] = (shares[key] or 0) + 1
                end
            end
        end
    end
    if next(shares) then
        return shares
    end

    for _, unit in ipairs(CORPSE_UNITS) do
        local guid = Readable(UnitGUID(unit))
        local npcID = guid and ns.Drops.NpcID(guid)
        if npcID and Readable(UnitIsDead(unit)) then
            local key = KillKey(npcID, zone)
            Know(key, CreatureName(guid, npcID), where)
            return { [key] = 1 }
        end
    end
    return shares
end

ns.OnEvent("LOOT_OPENED", function(_, isFromItem)
    -- The event can come twice for one window.
    if lootOpen or itemLootOpen then
        return
    end

    lootFromItem = isFromItem and true or OpenedFromBags()
    if lootFromItem then
        -- Whatever was still being earned from the window before is cut
        -- off here, so this one's contents can't pass for it.
        itemLootOpen = true
        earnedUntil = 0
        incomingSinceLook = true
        return
    end

    lootOpen = true
    lootShares = LootShares()
    earningFor = lootShares
end)

ns.OnEvent("LOOT_CLOSED", function()
    if lootOpen then
        lootOpen = false
        earnedUntil = GetTime() + LATE_ITEMS
    elseif itemLootOpen then
        itemLootOpen = false
        unearnedUntil = GetTime() + LATE_ITEMS
    end
end)

ns.OnEvent("QUEST_COMPLETE", function()
    questOpen = true
    questShares = QuestShares()
    earningFor = questShares
end)

ns.OnEvent("QUEST_FINISHED", function()
    if questOpen then
        questOpen = false
        earnedUntil = GetTime() + LATE_ITEMS
    end
end)

ns.OnEvent("QUEST_TURNED_IN", function()
    local zone, where = Here()
    Note("quest:" .. zone, "Questing", where)
end)

-- Gear taken off lands in the bags, and isn't anything new.
ns.OnEvent("PLAYER_EQUIPMENT_CHANGED", function()
    incomingSinceLook = true
    unearnedUntil = math.max(unearnedUntil, GetTime() + LATE_ITEMS)
end)

local function CheckState()
    Accrue()
    away = Readable(UnitIsAFK("player")) == true
    onTaxi = Readable(UnitOnTaxi("player")) == true
    dead = Readable(UnitIsDeadOrGhost("player")) == true
end

ns.OnEvent("PLAYER_FLAGS_CHANGED", function(unit)
    if unit == "player" then
        CheckState()
    end
end)

-- A flight takes control away and gives it back; dying and coming back
-- each have their word.
for _, event in ipairs({
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED",
}) do
    ns.OnEvent(event, CheckState)
end

-- [interaction type] = true, for each list of window names above.
local function WindowSet(names)
    local set = {}
    for _, name in ipairs(names) do
        local window = Enum.PlayerInteractionType[name]
        if window then
            set[window] = true
        end
    end
    return set
end

local SELLING = WindowSet(SELLING_WINDOWS)
local INCOMING = WindowSet(INCOMING_WINDOWS)

local function WindowShown(window, selling, incoming)
    if incoming then
        incomingOpen[window] = true
        incomingSinceLook = true
    end
    if selling and not sellingOpen[window] then
        Accrue()
        sellingOpen[window] = true
    end
end

local function WindowHidden(window)
    incomingOpen[window] = nil
    if sellingOpen[window] then
        Accrue()
        sellingOpen[window] = nil
    end
end

ns.OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(window)
    WindowShown(window, SELLING[window], INCOMING[window])
end)

ns.OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", WindowHidden)

-- The bank's own word, as Bank.lua listens for, in case the client's
-- bank doesn't go through the interaction manager.
ns.OnEvent("BANKFRAME_OPENED", function()
    WindowShown("bank", true, true)
end)

ns.OnEvent("BANKFRAME_CLOSED", function()
    WindowHidden("bank")
end)

ns.Subscribe("DATABASE_READY", Trim)

ns.OnEvent("PLAYER_LOGIN", function()
    Begin()
    countedTo = GetTime()
    CheckState()
    C_Timer.NewTicker(STATE_CHECK, CheckState)
    C_Timer.NewTicker(STRETCH_SECONDS, function()
        Close(false)
    end)
end)

-- A stretch cut short by logging out or reloading still counts for what
-- there was of it.
ns.OnEvent("PLAYER_LOGOUT", function()
    Close(true)
end)

-- Reading it back ------------------------------------------------------------------

local function Entry(key, label, where, seconds, earned)
    return {
        key = key,
        label = label,
        where = where,
        kind = KindOf(key),
        seconds = seconds,
        earned = earned,
        perHour = seconds > 0 and math.floor(earned * 3600 / seconds + 0.5) or 0,
    }
end

-- A kill's label, for a creature whose name wasn't known when it was put
-- on record.
local function KillLabel(key)
    local npcID = tonumber(key:match("^kill:(%d+):"))
    local drops = npcID and ns.Drops.Get(npcID)
    return drops and drops.name or "Unknown creature"
end

-- Whether a period can be added up stretch by stretch: it began within
-- the last two days, and since stretches were kept that way.
local function Exact(sinceTime)
    local from = Book().latestFrom
    return sinceTime ~= nil
        and from ~= nil
        and sinceTime >= from
        and GetServerTime() - sinceTime <= KEEP_EXACT
end

-- [key] = { seconds, earned } from the stretches since a moment. One that
-- was under way at that moment counts for the part of it after.
local function LatestTotals(whose, sinceTime)
    local totals = {}
    for _, list in ipairs(LatestFor(whose)) do
        for _, entry in ipairs(list) do
            local at, span, key = entry[1] or 0, entry[2] or 0, entry[3]
            local part = 1
            if at < sinceTime then
                part = span > 0 and math.max(0, (at + span - sinceTime) / span) or 0
            end
            if key and part > 0 then
                local total = totals[key] or { 0, 0 }
                total[1] = total[1] + (entry[4] or 0) * part
                total[2] = total[2] + (entry[5] or 0) * part
                totals[key] = total
            end
        end
    end
    return totals
end

-- [key] = { seconds, earned } from the whole days since a moment.
local function DayTotals(whose, sinceTime)
    local firstDay = sinceTime and ns.Ledger.DayOf(sinceTime) or -math.huge
    local totals = {}
    for day, record in pairs(DaysFor(whose)) do
        if type(day) == "number" and day >= firstDay and type(record) == "table" then
            for key, figures in pairs(record) do
                local total = totals[key] or { 0, 0 }
                total[1] = total[1] + (figures[1] or 0)
                total[2] = total[2] + (figures[2] or 0)
                totals[key] = total
            end
        end
    end
    return totals
end

--- Time spent and earned on each activity since a moment.
---
--- A moment in the last two days is counted from to the second, stretch
--- by stretch. Further back, it's kept by day, so the first day counted
--- is the whole of the day sinceTime falls on. Either way the stretch
--- under way isn't included until it closes (see Activity.Current).
---@param sinceTime number|nil  server time; nil for everything kept
---@param whose boolean|string|nil  true for the whole account, a
---        character's key for theirs, nothing for the one being played
---@return table activities  list of { key, label, where, kind, seconds,
---        earned, perHour }, most time first. kind is "kill", "gather",
---        "fish" or "quest"; label is what was done ("Young Panther",
---        "Herbalism") and where the zone's name, nil if never known.
---        earned and perHour are copper. seconds can be 0 for something
---        that brought coin in without taking any time, such as loot
---        from a creature killed by someone else.
function Activity.Summary(sinceTime, whose)
    if not ns.db then
        return {}
    end
    local names = Book().names
    local totals = Exact(sinceTime) and LatestTotals(whose, sinceTime)
        or DayTotals(whose, sinceTime)

    local list = {}
    for key, total in pairs(totals) do
        local seconds = math.floor(total[1] + 0.5)
        local earned = math.floor(total[2] + 0.5)
        if seconds > 0 or earned > 0 then
            local name = type(names[key]) == "table" and names[key] or {}
            local label = name[1]
            if not label and KindOf(key) == "kill" then
                label = KillLabel(key)
            end
            table.insert(list, Entry(key, label, name[2], seconds, earned))
        end
    end

    table.sort(list, function(a, b)
        if a.seconds ~= b.seconds then
            return a.seconds > b.seconds
        end
        if a.earned ~= b.earned then
            return a.earned > b.earned
        end
        return a.key < b.key
    end)
    return list
end

--- What the stretch under way is going to, so far.
---@return table|nil activity  as an entry of Activity.Summary, for the
---        activity with the most events in the stretch so far and its
---        share of it, or nil when nothing's been done in it yet. earned
---        leaves out things that came in in the last moment or two,
---        which are still being valued.
function Activity.Current()
    if not stretch then
        return nil
    end
    local key = Leader()
    if not key then
        return nil
    end
    Accrue()
    local share = stretch.counts[key] / EventCount()
    local about = stretch.about[key] or {}
    local label = about[1] or (KindOf(key) == "kill" and KillLabel(key) or nil)
    local earned = (stretch.earned[key] or 0) + stretch.loose * share
    return Entry(key, label, about[2], math.floor(stretch.active * share), math.floor(earned))
end
