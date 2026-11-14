local _, ns = ...

-- What creatures drop, learned from the player's own looting.
--
-- Goldwise ships no loot tables. The ones that exist are other people's
-- work under licences we can't take on, and Forever has changed enough
-- that they'd be a guess anyway. So every corpse the player loots is a
-- sample of its kind: what was on it, how many, and the coin. A handful
-- of kills is enough for Advisor\MobValue to say what a creature is worth.
--
-- A corpse can be opened more than once. The first time is the kill.
-- Skinning it, or taking a herb or ore from it, is counted apart: it needs
-- a profession the player may not have. That's told by the spell the
-- player cast just before the window opened, and failing that, by the
-- corpse having been emptied already. Any other second opening is only
-- the player coming back for what they left, and teaches us nothing new
-- beyond the coin.
--
-- Only solo play is recorded. In a group, the loot rules decide who gets
-- what, others may have half emptied a corpse first, and the coin is a
-- share. None of that says what the creature drops.

local Drops = {}
ns.Drops = Drops

-- Kinds of creature kept. A player levelling from one to sixty meets a
-- few hundred, so this only bites after a long while, and then it's the
-- ones not killed for longest that go.
local MOST_KINDS = 2000

-- One kill says little, and a creature killed once a month ago isn't
-- being farmed. Such records are let go after this many days.
local STALE_DAYS = 30

-- How long a corpse is remembered as looted, in seconds. Looted corpses
-- fade in a few minutes; a skinnable one waits a little longer.
local CORPSE_MEMORY = 300

-- Coin can land a moment after the loot window shuts. Purse.lua waits
-- a second for it; this waits a little longer than that.
local LATE_COIN = 2

-- A gathering spell marks the loot window that opens within this many
-- seconds of it as the gathering's.
local GATHER_WINDOW = 3

-- Seconds after a kill before asking whether the corpse has anything on
-- it, so the client has heard from the server.
local LOOT_CHECK_DELAY = 1

-- How a corpse is being opened this time.
local KILL = "kill"
local SKIN = "skin"
local AGAIN = "again"

-- What the player's last spell opened: a corpse, for its hide, herb or
-- ore, or something in the world, such as a herb, a vein or a chest.
local FROM_CORPSE = "corpse"
local FROM_OBJECT = "object"

-- The spells that gather from a corpse on this build. In its SpellEffect
-- table they're the ones with the Skinning effect (95), whose value says
-- what's taken: 0 a hide, 1 a herb, 2 ore, 3 parts from a machine.
local CORPSE_SPELLS = {
    [8613] = true, -- Skinning, each rank
    [8617] = true,
    [8618] = true,
    [10768] = true,
    [1235236] = true, -- Herb Gathering
    [1235230] = true, -- Mining
    [1235244] = true, -- Engineering
}

-- For a rank or a later spell the list above doesn't know, its name is
-- matched instead, as the game gives it in the player's own language.
-- Skinning and Herb Gathering are names only corpses answer to.
local CORPSE_NAMES_FROM = { 8613, 1235236 }

-- Spells that open something in the world rather than a corpse: a herb
-- (Herbalism), a vein (Mining) and a locked chest (Opening). Mining from
-- a corpse shares its name with mining a vein, which is why the spells
-- above are matched by number first.
local OBJECT_NAMES_FROM = { 2366, 2575, 3365 }

-- The slot types, as the client numbers them.
local SLOT = Enum.LootSlotType or { None = 0, Item = 1, Money = 2, Currency = 3 }

-- Units a corpse being looted is likely to be, when the client won't say
-- which creature the loot came from: the one the interact key is on, the
-- one under the mouse, the one targeted.
local CORPSE_UNITS = { "softinteract", "mouseover", "target" }

-- Saved drops: [npcID] = { name, level, type, kills, skins, copper, seen,
-- items, skinned }. kills counts corpses looted and kills seen to leave
-- nothing; skins counts corpses skinned or gathered from; copper is the
-- coin from all the kills together. items and skinned are [itemID] =
-- { times, quantity }: how many corpses it was found on and how many
-- there were altogether. skinned is left out until the creature is first
-- skinned. seen is the server time of the last kill, for deciding what to
-- let go. name, level and type (as UnitCreatureType gives it) are as last
-- seen, and missing when the corpse was never targeted or under the mouse.
local function Book()
    if type(ns.db.drops) ~= "table" then
        ns.db.drops = {}
    end
    return ns.db.drops
end

-- In restricted content some unit answers come back as values an addon
-- may hold but not read. They're as good as nothing to us.
local function Readable(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

local function InGroup()
    return IsInGroup and IsInGroup() or false
end

--- The creature ID inside a creature's GUID, or nil for anything else:
--- players, pets, objects, items.
---@param guid string|nil  e.g. "Creature-0-4372-0-17-299-000045C2A3"
---@return number|nil npcID
function Drops.NpcID(guid)
    guid = Readable(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local npcID = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return npcID and tonumber(npcID)
end

--- What's on record for one kind of creature. For reading only.
---@param npcID number
---@return table|nil drops  as laid out above Book
function Drops.Get(npcID)
    local drops = ns.db and type(ns.db.drops) == "table" and ns.db.drops[npcID]
    return type(drops) == "table" and drops or nil
end

--- Every kind of creature on record, by npcID. For reading only.
---@return table
function Drops.All()
    return ns.db and Book() or {}
end

-- The record for a kind of creature, made on first use.
local function Entry(npcID)
    local book = Book()
    local entry = book[npcID]
    if type(entry) ~= "table" then
        entry = { kills = 0, skins = 0, copper = 0 }
        book[npcID] = entry
    end
    if type(entry.items) ~= "table" then
        entry.items = {}
    end
    if entry.skinned ~= nil and type(entry.skinned) ~= "table" then
        entry.skinned = nil
    end
    return entry
end

local function AddKill(entry)
    entry.kills = (entry.kills or 0) + 1
    entry.seen = GetServerTime()
end

-- Corpses --------------------------------------------------------------------

-- Corpses looted lately, by GUID: { how, left }, where how is KILL or SKIN
-- and left is true when the last opening left something behind. Kept in
-- two halves that take turns, so old ones fall away without anything
-- having to go through them: a corpse is remembered for between one and
-- two spans of CORPSE_MEMORY.
local corpses, olderCorpses, corpsesSince = {}, {}, 0

local function Corpse(guid)
    return corpses[guid] or olderCorpses[guid]
end

local function Remember(guid, corpse)
    local now = GetTime()
    if now - corpsesSince > CORPSE_MEMORY then
        olderCorpses, corpses, corpsesSince = corpses, {}, now
    end
    corpses[guid] = corpse
end

-- The unit a GUID belongs to, if the player has it in view.
local function UnitOf(guid)
    if UnitTokenFromGUID then
        local ok, unit = pcall(UnitTokenFromGUID, guid)
        unit = ok and Readable(unit)
        if unit then
            return unit
        end
    end
    for _, unit in ipairs(CORPSE_UNITS) do
        if Readable(UnitGUID(unit)) == guid then
            return unit
        end
    end
end

-- Whether the client says a corpse has loot on it: true, false, or nil
-- when it won't say.
local function HasLoot(guid)
    if not CanLootUnit then
        return nil
    end
    local ok, hasLoot = pcall(CanLootUnit, guid)
    if not ok then
        return nil
    end
    hasLoot = Readable(hasLoot)
    if type(hasLoot) ~= "boolean" then
        return nil
    end
    return hasLoot
end

-- The corpse the player is most likely looting, when the client won't
-- say which: a dead creature within reach, under the interact key, the
-- mouse or targeted. Anything doubtful gives nil, and the loot goes
-- unrecorded, which costs one sample. Putting a chest or a herb down to
-- a corpse would spoil the creature's record for good.
local function CorpseInView(from)
    -- A spell that opens a herb, a vein or a chest was just cast.
    if from == FROM_OBJECT then
        return nil
    end

    -- The interact key is on something in the world with loot, so that
    -- may well be what's open.
    if
        from ~= FROM_CORPSE
        and UnitIsGameObject
        and UnitIsGameObject("softinteract")
        and UnitHasLootInteraction
        and UnitHasLootInteraction("softinteract")
    then
        return nil
    end

    local found
    for _, unit in ipairs(CORPSE_UNITS) do
        local guid = UnitExists(unit) and UnitIsDead(unit) and Readable(UnitGUID(unit))
        if
            guid
            and guid ~= found
            and Drops.NpcID(guid)
            and (not UnitIsInInteractRange or UnitIsInInteractRange(unit))
            -- A gathering is from a corpse already emptied, which the
            -- client may not count as having loot. The spell is enough.
            and (from == FROM_CORPSE or HasLoot(guid))
        then
            -- Two corpses it could be, and no telling which.
            if found then
                return nil
            end
            found = guid
        end
    end
    return found
end

-- Notes what a creature is called, its level and its type.
local function Describe(entry, unit)
    local name = Readable(UnitName(unit))
    if name then
        entry.name = name
    end

    -- Skull-level creatures report -1, which is no use for comparing.
    local level = Readable(UnitLevel(unit))
    if level and level > 0 then
        entry.level = level
    end

    local creatureType = Readable(UnitCreatureType(unit))
    if creatureType then
        entry.type = creatureType
    end
end

-- Gathering spells -------------------------------------------------------------

-- What the player's last spell opened, and when it was cast.
local lastCastFrom, lastCastAt

-- [name] = true for the names in CORPSE_NAMES_FROM and OBJECT_NAMES_FROM,
-- in the game's language. Made when first needed.
local corpseNames, objectNames

local function SpellNames(spellIDs)
    local names = {}
    for _, spellID in ipairs(spellIDs) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            names[name] = true
        end
    end
    return names
end

local function CastFrom(spellID)
    if CORPSE_SPELLS[spellID] then
        return FROM_CORPSE
    end

    if not objectNames or next(objectNames) == nil then
        objectNames = SpellNames(OBJECT_NAMES_FROM)
        corpseNames = SpellNames(CORPSE_NAMES_FROM)
        -- A translation could give a corpse's spell and a world one the
        -- same name. Such a name can't say which was cast.
        for name in pairs(objectNames) do
            corpseNames[name] = nil
        end
    end

    local name = Readable(C_Spell.GetSpellName(spellID))
    if not name then
        return nil
    elseif corpseNames[name] then
        return FROM_CORPSE
    elseif objectNames[name] then
        return FROM_OBJECT
    end
end

-- Only the player's own casts, which come in plain even where others'
-- don't. A frame of its own, since the shared one in Events.lua would
-- hear every caster in sight.
local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, spellID)
    spellID = Readable(spellID)
    local from = spellID and CastFrom(spellID)
    if from then
        lastCastFrom, lastCastAt = from, GetTime()
    end
end)

-- What the loot window opening now was opened by, if a spell. Each cast
-- marks one window only.
local function TakeCast()
    local from = lastCastAt and GetTime() - lastCastAt <= GATHER_WINDOW and lastCastFrom or nil
    lastCastFrom, lastCastAt = nil, nil
    return from
end

-- Reading the window -----------------------------------------------------------

-- Packs a function's answers into a list that keeps any nils in place.
local function Pack(...)
    return { n = select("#", ...), ... }
end

-- Which creatures a slot came from, as guid, quantity, guid, quantity.
-- Since area loot, one window can hold several corpses, and the client
-- says which slot came from which. Without that, the whole window is put
-- down to the corpse in view.
local function Sources(slot, quantity, fallback)
    if type(GetLootSourceInfo) == "function" then
        local sources = Pack(GetLootSourceInfo(slot))
        if sources.n > 0 and sources[1] then
            return sources
        end
    end
    if fallback then
        return { n = 2, fallback, quantity }
    end
end

local function SlotType(slot, currencyID, isCoin)
    if GetLootSlotType then
        return GetLootSlotType(slot)
    elseif isCoin then
        return SLOT.Money
    elseif currencyID then
        return SLOT.Currency
    end
    return SLOT.Item
end

-- What the window holds, read the moment it's ready: { from, found,
-- coinSlots, unplaced }. found has { slot, money, itemID, quantity,
-- sources } for each slot whose source is known; coinSlots is [slot] =
-- true for each slot of coin, wherever it came from; unplaced is true
-- when some slot's source couldn't be told. Nothing is put on record
-- yet, since the window may turn out to be a bag being opened.
local function Gather()
    local from = TakeCast()
    local fallback = CorpseInView(from)
    local loot = { from = from, found = {}, coinSlots = {}, unplaced = false }

    for slot = 1, GetNumLootItems() do
        local _, _, quantity, currencyID, _, _, isQuestItem, _, _, isCoin = GetLootSlotInfo(slot)
        local slotType = SlotType(slot, currencyID, isCoin)
        local money = slotType == SLOT.Money
        if money then
            loot.coinSlots[slot] = true
        end

        -- Quest items only drop for someone on the quest, so they'd
        -- muddle the odds for everyone else, and currencies aren't
        -- anything Goldwise puts a price on. Their slots are still
        -- followed, so we know whether they were left behind.
        local itemID
        if slotType == SLOT.Item and not isQuestItem then
            local link = GetLootSlotLink(slot)
            itemID = link and tonumber(link:match("item:(%d+)"))
        end

        local sources = Sources(slot, quantity, fallback)
        if sources then
            table.insert(loot.found, {
                slot = slot,
                money = money,
                itemID = itemID,
                quantity = quantity,
                sources = sources,
            })
        else
            loot.unplaced = true
        end
    end
    return loot
end

-- The window open now, once put on record: { sources, slots, coin,
-- coinSlots, coinDue, coinTaken, closedAt }. sources is [guid] = source,
-- or false for one that isn't a creature's corpse; slots is [slot] = the
-- GUIDs it came from; coin is [source] = its share of the coin, by the
-- client's figures. coinDue is how many payments of coin are still to
-- come for it, one for each slot of coin, and coinTaken says whether any
-- of those slots was taken before it closed.
local window

-- Windows that may still be paid coin, oldest first: the open one, and
-- those closed in the last LATE_COIN seconds.
local owing = {}

-- What Gather found, until the window opens properly.
local gathered

-- Slots emptied since the window opened. Kept apart from window: a fast
-- looting addon can empty them before the window has properly opened.
local cleared = {}

-- Whether this loot has been put on record, so a second LOOT_OPENED
-- doesn't count it twice.
local committed = false

-- Creatures whose records changed while the window was read.
local changed = {}

-- Kills waiting to be asked whether they left anything: [guid] = { npcID,
-- about }, where about is the creature as it was described when it died.
local pendingKills = {}

-- Starts on one corpse in the window: decides what this opening is and
-- puts down a kill or a skin. Returns false for anything that isn't the
-- corpse of a creature.
local function Open(guid, from)
    local npcID = Drops.NpcID(guid)
    if not npcID then
        return false
    end

    -- The client says a creature, but the spell just cast opens herbs,
    -- veins and chests. One of them is wrong, and there's no knowing
    -- which.
    if from == FROM_OBJECT then
        return false
    end

    -- Picking a pocket opens the same window on a creature that's still
    -- alive. That isn't what it drops.
    local unit = UnitOf(guid)
    if unit and not UnitIsDead(unit) then
        return false
    end

    pendingKills[guid] = nil

    local corpse = Corpse(guid)
    local how
    if from == FROM_CORPSE then
        -- Skinned, or a herb or ore taken from it, whatever is or isn't
        -- remembered: a corpse it died out of sight of, another player's
        -- kill, or one from before a long break.
        how = SKIN
        corpse = corpse or {}
        corpse.how = SKIN
    elseif not corpse then
        how = KILL
        corpse = { how = KILL }
    elseif corpse.left or corpse.how == SKIN then
        how = AGAIN
    else
        -- Emptied before, so opening it again can only be a gathering,
        -- even if its spell wasn't one we know.
        how = SKIN
        corpse.how = SKIN
    end

    -- Taken to be emptied this time, until the window closes and says
    -- otherwise.
    corpse.left = false
    Remember(guid, corpse)

    local entry = Entry(npcID)
    if how == KILL then
        AddKill(entry)
    elseif how == SKIN then
        entry.skins = (entry.skins or 0) + 1
        -- A creature only ever skinned has no kill to date it, and
        -- undated records are let go as stale on the way out.
        entry.seen = GetServerTime()
    end
    if how ~= AGAIN then
        if unit then
            Describe(entry, unit)
        end
        changed[npcID] = true
    end

    return { npcID = npcID, how = how, stage = corpse.how, entry = entry, counted = {} }
end

-- Puts down one slot's worth from one corpse.
local function Count(source, found, quantity)
    -- Coin belongs to the kill, even when it's picked up on a second visit.
    if found.money then
        if source.stage == KILL then
            window.coin[source] = (window.coin[source] or 0) + (tonumber(quantity) or 0)
        end
        return
    end

    if not found.itemID or source.how == AGAIN then
        return
    end

    local entry = source.entry
    local list = entry.items
    if source.how == SKIN then
        -- Made only for creatures that are skinned, which most aren't.
        entry.skinned = entry.skinned or {}
        list = entry.skinned
    end
    local tally = list[found.itemID]
    if not tally then
        tally = { 0, 0 }
        list[found.itemID] = tally
    end

    -- The same thing can fill two slots from one corpse. That's still one
    -- corpse it was found on.
    if not source.counted[found.itemID] then
        source.counted[found.itemID] = true
        tally[1] = tally[1] + 1
    end
    tally[2] = tally[2] + math.max(tonumber(quantity) or 1, 1)
end

-- Shares coin that reached the purse among the corpses in a window. What
-- the client says each corpse held only decides the shares: what landed
-- is the figure kept.
local function Credit(paid, copper)
    local total, count = 0, 0
    for _, weight in pairs(paid.coin) do
        total = total + weight
        count = count + 1
    end
    if count == 0 then
        return
    end

    for source, weight in pairs(paid.coin) do
        local share = total > 0 and copper * weight / total or copper / count
        source.entry.copper = (source.entry.copper or 0) + math.floor(share + 0.5)
        ns.Publish("DROPS_CHANGED", source.npcID)
    end
end

-- Whether a window can be paid the coin landing now.
local function Owed(owed, now)
    if owed.coinDue <= 0 then
        return false
    end
    if not owed.closedAt then
        return true
    end
    -- After it shuts, only if its coin was taken: otherwise the coin is
    -- still lying on the corpse, and what's landing is someone else's.
    return owed.coinTaken and now - owed.closedAt <= LATE_COIN
end

-- Lets go of windows with nothing more to come.
local function Tidy(now)
    for index = #owing, 1, -1 do
        if not Owed(owing[index], now) then
            table.remove(owing, index)
        end
    end
end

-- Puts what Gather found on record. A window that isn't a creature's,
-- or isn't to be recorded, is still followed, so its coin isn't put
-- down to a corpse.
local function Commit(loot, ignore)
    local now = GetTime()

    -- A window never seen to close can't still be open.
    if window and not window.closedAt then
        window.closedAt = now
    end

    local coinDue = 0
    for _ in pairs(loot.coinSlots) do
        coinDue = coinDue + 1
    end
    window = {
        sources = {},
        slots = {},
        coin = {},
        coinSlots = loot.coinSlots,
        coinDue = coinDue,
        coinTaken = false,
    }
    Tidy(now)
    table.insert(owing, window)

    if ignore then
        ns.Log("drops: window not recorded (%s)", ignore)
        return
    end

    -- Some of this window could be a kill waiting to hear whether it left
    -- anything. Better none of them counted than one counted as empty.
    if loot.unplaced and not loot.from then
        wipe(pendingKills)
    end

    for _, slotFound in ipairs(loot.found) do
        local guids = {}
        local sources = slotFound.sources
        for index = 1, sources.n, 2 do
            local guid, quantity = Readable(sources[index]), sources[index + 1]
            if guid then
                local source = window.sources[guid]
                if source == nil then
                    source = Open(guid, loot.from)
                    window.sources[guid] = source
                end
                if source then
                    table.insert(guids, guid)
                    Count(source, slotFound, quantity)
                end
            end
        end
        window.slots[slotFound.slot] = guids
    end

    -- One line per window, so a report can say why a kill went unrecorded.
    local hows = {}
    for _, source in pairs(window.sources) do
        table.insert(hows, source and (source.how .. " " .. source.npcID) or "not a creature")
    end
    ns.Log(
        "drops: %d slots, %s%s%s",
        #loot.found,
        #hows > 0 and table.concat(hows, ", ") or "no source",
        loot.unplaced and ", some unplaced" or "",
        loot.from and (", by a " .. loot.from .. " spell") or ""
    )

    for npcID in pairs(changed) do
        ns.Publish("DROPS_CHANGED", npcID)
    end
    wipe(changed)
end

-- LOOT_READY comes first, sometimes twice, and is when fast looting
-- addons take everything. So the slots are read then. LOOT_OPENED says
-- whether the window is a bag or a box being opened, so only then is
-- anything put on record.
ns.OnEvent("LOOT_READY", function()
    if committed or gathered or not ns.db then
        return
    end
    gathered = Gather()
end)

ns.OnEvent("LOOT_OPENED", function(_, isFromItem)
    if committed or not ns.db then
        return
    end
    committed = true

    local loot = gathered or Gather()
    gathered = nil

    -- A fish, or a bag or box opened from the bags, isn't a creature's
    -- drop. Nor is anything looted in a group put down, as above.
    local ignore = isFromItem and "opened from the bags"
        or (IsFishingLoot and IsFishingLoot()) and "fishing"
        or InGroup() and "in a group"
        or nil
    Commit(loot, ignore)
end)

-- Without this event there's no telling a corpse left half looted from
-- one emptied, and every second opening is taken to be a skinning.
local followsSlots = ns.OnEvent("LOOT_SLOT_CLEARED", function(slot)
    cleared[slot] = true
end)

ns.OnEvent("LOOT_CLOSED", function()
    if window and not window.closedAt then
        if followsSlots then
            -- A corpse with something still on it can't be skinned yet,
            -- so opening it again will only be to fetch what was left.
            for slot, guids in pairs(window.slots) do
                if not cleared[slot] then
                    for _, guid in ipairs(guids) do
                        local corpse = Corpse(guid)
                        if corpse then
                            corpse.left = true
                        end
                    end
                end
            end

            for slot in pairs(window.coinSlots) do
                if cleared[slot] then
                    window.coinTaken = true
                end
            end
        end
        window.closedAt = GetTime()
    end
    window = nil

    committed = false
    gathered = nil
    wipe(cleared)
end)

-- Kills with nothing on them. A corpse with no loot never opens a window,
-- so counting kills only at the loot would leave out every empty one and
-- make a creature look richer than it is. Beasts carry no coin and often
-- nothing else.
--
-- So a moment after a kill the player or their pet lands, the client is
-- asked whether the corpse has loot. If not, it's an empty kill. If it
-- has, the kill is counted when it's looted, and not at all if it never
-- is: a kill walked away from says nothing about what it dropped.
--
-- Only for a creature in view that was the player's to loot.
local function CheckKill(guid, kill)
    if pendingKills[guid] ~= kill then
        return
    end
    pendingKills[guid] = nil

    -- Looted already, or the player has since joined a group.
    if Corpse(guid) or not ns.db or InGroup() then
        return
    end
    local hasLoot = HasLoot(guid)
    if hasLoot ~= false then
        ns.Log(
            "drops: kill %d, %s",
            kill.npcID,
            hasLoot and "waiting to be looted" or "can't tell if it has loot"
        )
        return
    end
    ns.Log("drops: kill %d, nothing on it", kill.npcID)

    -- Remembered as emptied, so skinning it later counts as a skin.
    Remember(guid, { how = KILL, left = false })

    local entry = Entry(kill.npcID)
    AddKill(entry)
    for key, value in pairs(kill.about) do
        entry[key] = value
    end
    ns.Publish("DROPS_CHANGED", kill.npcID)
end

ns.OnEvent("PARTY_KILL", function(attackerGUID, targetGUID)
    if not ns.db or InGroup() then
        return
    end

    attackerGUID, targetGUID = Readable(attackerGUID), Readable(targetGUID)
    if
        not attackerGUID or (attackerGUID ~= UnitGUID("player") and attackerGUID ~= UnitGUID("pet"))
    then
        return
    end

    local npcID = Drops.NpcID(targetGUID)
    local unit = npcID and not Corpse(targetGUID) and UnitOf(targetGUID)
    if not unit or UnitIsTapDenied(unit) then
        ns.Log("drops: a kill out of view or not yours")
        return
    end

    -- Described now, while it's still in view.
    local kill = { npcID = npcID, about = {} }
    Describe(kill.about, unit)
    pendingKills[targetGUID] = kill
    C_Timer.After(LOOT_CHECK_DELAY, function()
        CheckKill(targetGUID, kill)
    end)
end)

-- The coin itself. Purse.lua files whatever lands while a loot window is
-- open, or just after, as loot. Coin taken from one corpse can land after
-- the next window has opened, when looting quickly. So each window is
-- paid once for each slot of coin it had, oldest first, and one closed
-- is paid only if its coin was taken: what lands then is the late coin
-- of the last corpse, not the first of the next.
ns.Subscribe("MONEY_MOVED", function(delta, category)
    if category ~= "loot" or delta <= 0 then
        return
    end

    Tidy(GetTime())
    local paid = owing[1]
    if paid then
        paid.coinDue = paid.coinDue - 1
        Credit(paid, delta)
    end
end)

-- Keeping it small ---------------------------------------------------------------

local function Prune()
    local book = Book()
    local now = GetServerTime()
    local kinds = {}

    for npcID, entry in pairs(book) do
        if type(entry) ~= "table" then
            book[npcID] = nil
        elseif
            (entry.kills or 0) + (entry.skins or 0) <= 1
            and now - (entry.seen or 0) > STALE_DAYS * ns.SECONDS_PER_DAY
        then
            book[npcID] = nil
        else
            table.insert(kinds, npcID)
        end
    end

    if #kinds > MOST_KINDS then
        table.sort(kinds, function(a, b)
            return (book[a].seen or 0) > (book[b].seen or 0)
        end)
        for index = MOST_KINDS + 1, #kinds do
            book[kinds[index]] = nil
        end
    end
end

-- Corpses looted lately outlast a /reload, or a corpse looted before it
-- and opened again after would be counted as a second kill. They're kept
-- in ns.db.dropsCorpses as { at, corpses }, at being the server time they
-- were saved, and taken back only if that was moments ago.
local function RestoreCorpses()
    local saved = ns.db.dropsCorpses
    ns.db.dropsCorpses = nil
    if
        type(saved) ~= "table"
        or type(saved.corpses) ~= "table"
        or type(saved.at) ~= "number"
        or GetServerTime() - saved.at > CORPSE_MEMORY
    then
        return
    end

    for guid, corpse in pairs(saved.corpses) do
        if type(guid) == "string" and type(corpse) == "table" then
            corpses[guid] = corpse
        end
    end
    corpsesSince = GetTime()
end

local function SaveCorpses()
    local kept = {}
    for _, half in ipairs({ olderCorpses, corpses }) do
        for guid, corpse in pairs(half) do
            kept[guid] = corpse
        end
    end
    ns.db.dropsCorpses = next(kept) and { at = GetServerTime(), corpses = kept } or nil
end

-- Once as the saved data loads and once on the way out, so what's saved
-- is in trim. Never in the middle of a fight.
ns.Subscribe("DATABASE_READY", function()
    Prune()
    RestoreCorpses()
end)

ns.OnEvent("PLAYER_LOGOUT", function()
    if ns.db then
        Prune()
        SaveCorpses()
    end
end)
