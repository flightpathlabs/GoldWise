local _, ns = ...

-- What each of the player's characters was carrying when last seen.
--
-- The price ledger is already shared by every character on the account,
-- because saved data is account-wide. This adds the other half: a note of
-- each character's sellable items and gold, taken whenever they're played,
-- so the list can show everything the account holds and who has it.
--
-- A character's record is only as fresh as their last login, and anything
-- built on it says so.

local Characters = {}
ns.Characters = Characters

local function Roster()
    if type(ns.db.characters) ~= "table" then
        ns.db.characters = {}
    end
    return ns.db.characters
end

--- The key the current character's records are kept under.
---
--- Names are unique across a region on Forever, but the realm string also
--- carries the ruleset, and the same name could exist on two of those.
---@return string
function Characters.CurrentKey()
    return ("%s-%s"):format(UnitName("player") or "?", ns.RealmName())
end

--- Whether this is the only character Goldwise has ever seen on the
--- account. If so, everything the account has on record is theirs.
---@return boolean
function Characters.IsOnlyOne()
    local current = Characters.CurrentKey()
    for key in pairs(Roster()) do
        if key ~= current then
            return false
        end
    end
    return true
end

local function Remember()
    local holdings = {}
    for _, holding in ipairs(ns.Bags.Holdings()) do
        holdings[holding.itemID] = {
            name = holding.name,
            icon = holding.icon,
            quality = holding.quality,
            link = holding.link,
            count = holding.count,
        }
    end

    Roster()[Characters.CurrentKey()] = {
        name = UnitName("player"),
        -- Which auction house this character sells at. Only characters who
        -- share a market belong in the same list.
        market = ns.Market.Home(),
        money = GetMoney(),
        holdings = holdings,
        -- Everything in their bags, bound or not, for "who has how many".
        counts = CopyTable(ns.Bags.Counts()),
        seenAt = GetServerTime(),
    }
end

--- All the gold on the account: this character's, as it stands now, plus
--- every other character's as of their last login.
---@return number copper
function Characters.TotalMoney()
    local current = Characters.CurrentKey()
    local total = GetMoney()

    for key, record in pairs(Roster()) do
        if key ~= current then
            total = total + (record.money or 0)
        end
    end
    return total
end

--- Every character Goldwise has seen on the account, this one included,
--- in order of name.
---@return table characters  list of { key, name, realm, money }, where
---        money is this character's now and the others' as of their last
---        login
function Characters.All()
    local current = Characters.CurrentKey()
    local characters = {}

    for key, record in pairs(Roster()) do
        local name = record.name or key:match("^[^-]+") or key
        table.insert(characters, {
            key = key,
            name = name,
            realm = key:sub(#name + 2),
            money = key == current and GetMoney() or record.money,
        })
    end

    table.sort(characters, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.realm < b.realm
    end)
    return characters
end

--- How much gold a character has: the one being played as it stands now,
--- any other as of their last login.
---@param key string|nil  their key; nothing for the one being played
---@return number copper
function Characters.MoneyOf(key)
    if not key or key == Characters.CurrentKey() then
        return GetMoney()
    end
    local record = Roster()[key]
    return record and record.money or 0
end

--- Which of the player's other characters carry an item, most first.
--- Counts bags only, as they stood at each character's last login.
---@param itemID number
---@return table holders  list of { name, count }
function Characters.HoldersOf(itemID)
    local current = Characters.CurrentKey()
    local holders = {}

    for key, record in pairs(Roster()) do
        local count = key ~= current and record.counts and record.counts[itemID]
        if count and count > 0 then
            table.insert(holders, { name = record.name, count = count })
        end
    end

    table.sort(holders, function(a, b)
        return a.count > b.count
    end)
    return holders
end

--- The player's other characters whose home market is the given one.
---@param marketKey string  normally Market.Home(), not the open auction
---        house: a neutral house is nobody's home
---@return table others  list of { key, name, money, seenAt, holdings },
---        where holdings is a list shaped like Bags.Holdings() and key is
---        what their other records, such as their bank, are filed under
function Characters.Others(marketKey)
    local current = Characters.CurrentKey()
    local others = {}

    for key, record in pairs(Roster()) do
        if key ~= current and record.market == marketKey then
            local holdings = {}
            for itemID, holding in pairs(record.holdings or {}) do
                table.insert(holdings, {
                    itemID = itemID,
                    name = holding.name,
                    icon = holding.icon,
                    quality = holding.quality,
                    link = holding.link,
                    count = holding.count,
                })
            end

            table.insert(others, {
                key = key,
                name = record.name,
                money = record.money,
                seenAt = record.seenAt,
                holdings = holdings,
            })
        end
    end

    return others
end

-- Keep building price history for what the other characters hold, so their
-- items have charts too by the time the player logs over to sell them.
local function TrackEveryonesHoldings()
    for _, record in pairs(Roster()) do
        for itemID in pairs(record.holdings or {}) do
            ns.Ledger.Track(record.market, itemID)
        end
    end
end

ns.Subscribe("BAGS_CHANGED", Remember)

-- Gold can change without anything in the bags doing so.
ns.OnEvent("PLAYER_MONEY", function()
    local record = Roster()[Characters.CurrentKey()]
    if record then
        record.money = GetMoney()
    end
end)

-- Records under a blank realm ------------------------------------------------

-- Before ns.RealmName kept the last name seen, a login where the game gave
-- the realm as blank filed everything under "Bjorn-", and the character
-- menus listed Bjorn twice. Once the realm is known again, each such
-- record is folded into its proper one.

-- Tables kept per character, as found under ns.db.
local KEPT_PER_CHARACTER = {
    { "characters" },
    { "sessions" },
    { "banks" },
    { "listings" },
    { "crafts" },
    { "unlearned" },
    { "worth", "characters" },
    { "purse", "characters" },
    { "trade", "characters" },
}

-- Running totals: the two records are added together. Everything else is
-- a snapshot, and the newer of the two stands, with what only the older
-- one knew filled in, except for a session, which is one whole.
local ADDED_UP = { purse = true, trade = true }
local WHOLE = { sessions = true }

-- Adds one book of totals into another, hour by hour and day by day. A
-- character's coin at the end of an hour is a reading, not a sum, and
-- where a book starts is the earlier of the two.
local function AddUp(into, from)
    for key, value in pairs(from) do
        local mine = into[key]
        if mine == nil then
            into[key] = value
        elseif key == "coin" and type(value) == "number" and type(mine) == "number" then
            into[key] = math.max(mine, value)
        elseif key == "hoursFrom" and type(value) == "number" and type(mine) == "number" then
            into[key] = math.min(mine, value)
        elseif type(value) == "number" and type(mine) == "number" then
            into[key] = mine + value
        elseif type(value) == "table" and type(mine) == "table" then
            if key == "recent" then
                -- The latest trades: both lists, newest first, as long
                -- as the list is kept.
                for _, entry in ipairs(value) do
                    table.insert(mine, entry)
                end
                table.sort(mine, function(a, b)
                    return (a.at or 0) > (b.at or 0)
                end)
            else
                AddUp(mine, value)
            end
        end
    end
end

-- Fills in what one snapshot lacks from another, without overwriting.
local function FillIn(into, from)
    for key, value in pairs(from) do
        if into[key] == nil then
            into[key] = value
        elseif type(value) == "table" and type(into[key]) == "table" then
            FillIn(into[key], value)
        end
    end
end

local function SeenAt(record)
    return type(record) == "table" and (record.seenAt or record.startedAt) or nil
end

local function FoldBlankRealms()
    local realm = ns.RealmName()
    if realm == "" then
        return
    end

    local home = ns.Market.Home()
    for _, path in ipairs(KEPT_PER_CHARACTER) do
        local tableOf = ns.db
        for _, step in ipairs(path) do
            tableOf = type(tableOf) == "table" and tableOf[step] or nil
        end

        if type(tableOf) == "table" then
            local blanks = {}
            for key in pairs(tableOf) do
                if type(key) == "string" and key:match("^[^-]+%-$") then
                    table.insert(blanks, key)
                end
            end

            for _, blank in ipairs(blanks) do
                local proper = blank .. realm
                local stray, kept = tableOf[blank], tableOf[proper]
                tableOf[blank] = nil

                if type(kept) ~= "table" then
                    tableOf[proper] = stray
                elseif type(stray) == "table" then
                    if ADDED_UP[path[1]] then
                        AddUp(kept, stray)
                    elseif (SeenAt(stray) or 0) > (SeenAt(kept) or 0) then
                        if not WHOLE[path[1]] then
                            FillIn(stray, kept)
                        end
                        tableOf[proper] = stray
                    elseif not WHOLE[path[1]] then
                        FillIn(kept, stray)
                    end
                end
            end
        end
    end

    -- Recipes bought to resell say who bought and who listed them.
    for _, lot in ipairs(type(ns.db.resales) == "table" and ns.db.resales or {}) do
        if type(lot) == "table" then
            for _, field in ipairs({ "who", "lister" }) do
                local key = lot[field]
                if type(key) == "string" and key:match("^[^-]+%-$") then
                    lot[field] = key .. realm
                end
            end
        end
    end

    -- A character first seen while the realm was blank was put down at
    -- a market of unknown ruleset. Theirs is this one.
    for _, record in pairs(Roster()) do
        if type(record.market) == "string" and record.market:find("-Unknown-", 1, true) then
            record.market = home
        end
    end
    -- And their listings there are a stale copy, read again at the next
    -- visit to the auction house.
    for _, listed in pairs(type(ns.db.listings) == "table" and ns.db.listings or {}) do
        if type(listed) == "table" and type(listed.markets) == "table" then
            for marketKey in pairs(listed.markets) do
                if marketKey:find("-Unknown-", 1, true) then
                    listed.markets[marketKey] = nil
                end
            end
        end
    end
end

ns.OnEvent("PLAYER_LOGIN", function()
    FoldBlankRealms()
    TrackEveryonesHoldings()
end)
