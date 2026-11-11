local _, ns = ...

-- Players keeping each other's prices fresh.
--
-- Whoever was at the auction house most recently knows what things cost
-- right now. Goldwise players share that over a hidden chat channel, so
-- someone who logs in out in the wilds can still be told what the leather
-- in their bags is worth, without a trip to town.
--
-- It is deliberately a quiet protocol. Nobody broadcasts a whole market.
-- A player announces that they've scanned (one message), anyone who needs
-- prices asks for the handful of items they carry (one message), and one
-- player who has them answers (a few messages). Everyone on the channel
-- hears the answer, so one question helps many.
--
-- Three rules that matter:
--
--   * We only pass on what our own game read at the auction house. Never
--     prices from the feed: those come from Blizzard's API, and its terms
--     don't allow handing them to third parties.
--   * What we hear is hearsay. It's used for "what is this worth now" when
--     we have nothing fresher, it's labelled as coming from another
--     player, and it never goes into the price history.
--   * We stay well inside the game's limits on addon chatter, and go
--     silent altogether if the channel gets busy.

local Network = {}
ns.Network = Network

local PREFIX = "Goldwise"
local CHANNEL = "GoldwiseNet"

-- First character of every message. Bumped if the format changes, so old
-- and new versions ignore each other instead of misreading.
local VERSION = "1"

-- How recent a scan must be to be worth sharing, or to make asking
-- unnecessary.
local FRESH = 2 * 3600

-- How long hearsay is kept.
local HEARSAY_LIFETIME = 24 * 3600

-- Pacing. All in seconds.
local JOIN_DELAY = 15 -- after login, before joining: channels need to settle
local ASK_COOLDOWN = 10 * 60
local ANSWER_COOLDOWN = 5

-- Sizes, chosen to keep each message under the 255-byte limit.
local MAX_ASK_ITEMS = 30
local ITEMS_PER_REPLY = 12
local MAX_REPLIES = 3

-- If we hear more than this many Goldwise messages in a minute, the
-- channel is busy enough without us.
local BUSY_MESSAGES_PER_MINUTE = 40

-- A heard price this many times above or below what we already believe is
-- ignored as a mistake or a prank.
local MAX_DISAGREEMENT = 10

local lastAsked = 0
local lastAnswered = 0

-- Times of recently heard messages, for judging how busy the channel is.
local heardTimes = {}

-- Answers we mean to send unless someone beats us to it: [firstItemID] = true.
local pendingAnswers = {}

-- Sending -------------------------------------------------------------------------

local function ChannelNumber()
    local number = GetChannelName(CHANNEL)
    return type(number) == "number" and number > 0 and number or nil
end

local function ChannelIsBusy()
    local cutoff = GetTime() - 60
    while heardTimes[1] and heardTimes[1] < cutoff do
        table.remove(heardTimes, 1)
    end
    return #heardTimes > BUSY_MESSAGES_PER_MINUTE
end

-- Whether this is a moment we're allowed, and it's polite, to speak.
local function MaySpeak()
    return ns.settings.sharePrices
        and not InCombatLockdown()
        and not IsInInstance()
        and not C_ChatInfo.InChatMessagingLockdown()
        and not ChannelIsBusy()
end

local function Send(text)
    local number = ChannelNumber()
    if not number or not MaySpeak() then
        return false
    end

    -- The target is the channel's number, passed as text.
    local result = C_ChatInfo.SendAddonMessage(PREFIX, VERSION .. text, "CHANNEL", tostring(number))
    if result ~= Enum.SendAddonMessageResult.Success then
        ns.Log("network: send refused (%s)", tostring(result))
        return false
    end
    return true
end

-- Hearsay ---------------------------------------------------------------------------

local function Hearsay(marketKey)
    local market = ns.MarketData(marketKey)
    if type(market.heard) ~= "table" then
        market.heard = {}
    end
    return market.heard
end

--- What another player told us an item costs, if it's recent enough.
---@param marketKey string
---@param itemID number
---@return number|nil price
---@return number|nil quantity
---@return number|nil scannedAt  when that player's game read it
function Network.Price(marketKey, itemID)
    local entry = Hearsay(marketKey)[itemID]
    if entry and GetServerTime() - entry[3] <= HEARSAY_LIFETIME then
        return entry[1], entry[2], entry[3]
    end
end

local function Believable(marketKey, itemID, price)
    -- Compare with our own readings or the feed, whichever we have.
    local known = ns.Ledger.LocalPrice(marketKey, itemID) or ns.Feed.Price(marketKey, itemID)
    if not known then
        return true
    end
    return price <= known * MAX_DISAGREEMENT and price * MAX_DISAGREEMENT >= known
end

local function Remember(marketKey, scannedAt, entries)
    local now = GetServerTime()
    -- A scan from the future or the distant past is no use to anyone.
    if scannedAt > now + 300 or now - scannedAt > FRESH then
        return
    end

    local heard = Hearsay(marketKey)
    local market = ns.MarketData(marketKey)
    local learned = false

    for itemID, price, quantity in entries:gmatch("(%d+):(%d+):(%d+)") do
        itemID, price, quantity = tonumber(itemID), tonumber(price), tonumber(quantity)

        -- Only for things we follow. Otherwise a busy channel would fill
        -- the saved file with items the player will never look at.
        local wanted = market.tracked[itemID] ~= nil
        local newer = not heard[itemID] or heard[itemID][3] < scannedAt

        if wanted and newer and price > 0 and Believable(marketKey, itemID, price) then
            heard[itemID] = { price, quantity, scannedAt }
            learned = true
        end
    end

    if learned then
        ns.Publish("PRICES_CHANGED", marketKey)
    end
end

-- Asking -----------------------------------------------------------------------------

-- The items in the player's bags that we have no fresh price for.
local function Wanted(marketKey)
    local now = GetServerTime()
    local wanted = {}

    for _, holding in ipairs(ns.Bags.Holdings()) do
        local _, _, seenAt = ns.Ledger.LocalPrice(marketKey, holding.itemID)
        local _, _, heardAt = Network.Price(marketKey, holding.itemID)
        local newest = math.max(seenAt or 0, heardAt or 0)

        if now - newest > FRESH then
            table.insert(wanted, holding.itemID)
            if #wanted == MAX_ASK_ITEMS then
                break
            end
        end
    end
    return wanted
end

local function Ask()
    if GetTime() - lastAsked < ASK_COOLDOWN then
        return
    end

    local marketKey = ns.Market.Home()
    local wanted = Wanted(marketKey)
    if #wanted == 0 then
        return
    end

    if Send(("Q|%s|%s"):format(marketKey, table.concat(wanted, ","))) then
        lastAsked = GetTime()
        ns.Log("network: asked about %d items", #wanted)
    end
end

-- Answering ------------------------------------------------------------------------

local function Answer(marketKey, itemList)
    local now = GetServerTime()
    local scannedAt = ns.Ledger.LastScan(marketKey)
    local found = {}

    for itemID in itemList:gmatch("%d+") do
        -- Our own readings only. See the note at the top about the feed.
        local price, quantity, seenAt = ns.Ledger.LocalPrice(marketKey, tonumber(itemID))
        if price and seenAt and now - seenAt <= FRESH then
            table.insert(found, ("%s:%d:%d"):format(itemID, price, quantity or 0))
        end
    end

    local sent = 0
    for first = 1, #found, ITEMS_PER_REPLY do
        if sent == MAX_REPLIES then
            break
        end

        local last = math.min(first + ITEMS_PER_REPLY - 1, #found)
        local entries = table.concat(found, ",", first, last)
        if not Send(("P|%s|%d|%s"):format(marketKey, scannedAt, entries)) then
            break
        end
        sent = sent + 1
    end

    if sent > 0 then
        lastAnswered = GetTime()
        ns.Log(
            "network: answered with %d of %d items",
            math.min(#found, sent * ITEMS_PER_REPLY),
            #found
        )
    end
end

local function ConsiderAnswering(marketKey, itemList)
    local scannedAt = ns.Ledger.LastScan(marketKey)
    local haveFreshScan = scannedAt and GetServerTime() - scannedAt <= FRESH
    if not haveFreshScan or GetTime() - lastAnswered < ANSWER_COOLDOWN then
        return
    end

    -- Several players may be able to answer. Each waits a random moment,
    -- and stands down if it hears someone else answer first.
    local firstItem = itemList:match("%d+")
    if not firstItem or pendingAnswers[firstItem] then
        return
    end
    pendingAnswers[firstItem] = true

    C_Timer.After(1 + math.random() * 4, function()
        if pendingAnswers[firstItem] then
            pendingAnswers[firstItem] = nil
            Answer(marketKey, itemList)
        end
    end)
end

-- Listening ---------------------------------------------------------------------------

local function IsOurs(sender)
    -- The sender arrives as "Name" or "Name-Realm" depending on the client.
    return sender and sender:match("^[^-]+") == UnitName("player")
end

ns.OnEvent("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if prefix ~= PREFIX or not ns.settings.sharePrices or IsOurs(sender) then
        return
    end
    table.insert(heardTimes, GetTime())

    if text:sub(1, 1) ~= VERSION then
        return
    end

    local kind, marketKey, rest = text:match("^.(%a)|([^|]+)|?(.*)$")
    if not kind then
        return
    end

    if kind == "A" then
        -- Someone has just scanned this market. If it's ours and we're in
        -- need, this is the moment to ask. A short random wait keeps a
        -- crowd from all asking in the same second.
        if marketKey == ns.Market.Home() then
            C_Timer.After(3 + math.random() * 12, Ask)
        end
    elseif kind == "Q" then
        ConsiderAnswering(marketKey, rest)
    elseif kind == "P" then
        local scannedAt, entries = rest:match("^(%d+)|(.*)$")
        if scannedAt then
            -- Someone answered. If we were about to answer the same
            -- question, there's no need now.
            local firstItem = entries:match("%d+")
            if firstItem then
                pendingAnswers[firstItem] = nil
            end
            Remember(marketKey, tonumber(scannedAt), entries)
        end
    end
end)

-- Joining and leaving ------------------------------------------------------------------

-- Keeps the channel out of every chat window. It carries addon messages
-- only, so there would never be anything to read there.
local function HideChannel()
    for window = 1, NUM_CHAT_WINDOWS or 10 do
        pcall(RemoveChatWindowChannel, window, CHANNEL)
    end
end

local function UpdateMembership()
    if ns.settings.sharePrices then
        if not ChannelNumber() then
            JoinTemporaryChannel(CHANNEL)
            C_Timer.After(2, HideChannel)
        end
    elseif ChannelNumber() then
        LeaveChannelByName(CHANNEL)
    end
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

ns.OnEvent("PLAYER_LOGIN", function()
    -- Forget hearsay that has gone stale while we were away.
    local now = GetServerTime()
    for _, market in pairs(ns.db.markets) do
        for itemID, entry in pairs(market.heard or {}) do
            if now - entry[3] > HEARSAY_LIFETIME then
                market.heard[itemID] = nil
            end
        end
    end

    C_Timer.After(JOIN_DELAY, function()
        UpdateMembership()
        -- Then, a little later and not on the same second as everyone
        -- else who logged in at the top of the hour, see who can help.
        C_Timer.After(15 + math.random() * 30, Ask)
    end)
end)

ns.Subscribe("SETTINGS_CHANGED", UpdateMembership)

-- Having just scanned, we're the one with fresh prices. Say so.
ns.Subscribe("SCAN_FINISHED", function()
    Send(("A|%s|%d"):format(ns.Market.Current(), GetServerTime()))
end)
