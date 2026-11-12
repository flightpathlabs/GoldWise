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
-- Four rules that matter:
--
--   * We only pass on what our own game read at the auction house. Never
--     prices from the feed: those come from Blizzard's API, and its terms
--     don't allow handing them to third parties.
--   * What we hear is hearsay. It's used for "what is this worth now" when
--     we have nothing fresher, it's labelled as coming from another
--     player, and it never goes into the price history.
--   * Anyone can type anything into a chat channel, so nothing heard is
--     trusted further than it has to be. Messages from anywhere but our
--     channel are ignored, as are markets we've never dealt in and prices
--     that are absurd or wildly out of line with what we know.
--   * We stay well inside the game's limits on addon chatter, and go
--     silent altogether if the channel gets busy.

local Network = {}
ns.Network = Network

local PREFIX = "Goldwise"
-- Each market has a channel of its own. Prices on one are no use on
-- another, and a channel shared by every faction and ruleset would carry
-- several times the chatter to players who can use none of it.
local CHANNEL_PREFIX = "Goldwise"

-- The channel for the player's home market: "GoldwiseUSPvEAlliance".
-- Channel names take letters and digits only.
local function Channel()
    return CHANNEL_PREFIX .. ns.Market.Home():gsub("%W", "")
end

-- First character of every message. Bumped if the format changes, so old
-- and new versions ignore each other instead of misreading.
local VERSION = "1"

-- The game refuses addon messages longer than this.
local MAX_MESSAGE_BYTES = 255

-- How recent a scan must be to be worth sharing, or to make asking
-- unnecessary.
local FRESH = 2 * 3600

-- How long hearsay is kept.
local HEARSAY_LIFETIME = 24 * 3600

-- Pacing. All in seconds.
local JOIN_DELAY = 15 -- after login, before joining: channels need to settle
local ASK_COOLDOWN = 10 * 60
local ANSWER_COOLDOWN = 5

-- Sizes. A question of this many items fits in one message.
local MAX_ASK_ITEMS = 30
local MAX_REPLIES = 3

-- If we hear more than this many Goldwise messages in a minute, the
-- channel is busy enough without us.
local BUSY_MESSAGES_PER_MINUTE = 40

-- A heard price this many times above or below what we already believe is
-- ignored as a mistake or a prank.
local MAX_DISAGREEMENT = 10

-- Nothing costs more than this (100,000 gold each), and no item is listed
-- in greater numbers. Anything beyond is somebody having fun.
local MAX_PRICE = 1e9
local MAX_QUANTITY = 1e7

-- GetTime() counts from when the computer started, so these begin far
-- enough back that the first question isn't mistaken for a repeat.
local lastAsked = -ASK_COOLDOWN
local lastAnswered = -ANSWER_COOLDOWN

-- Times of recently heard messages, for judging how busy the channel is.
local heardTimes = {}

-- Answers we mean to send unless someone beats us to it, keyed by the
-- question: [marketKey|itemList] = { marketKey, wanted = { [itemID] = true } }.
local pendingAnswers = {}

-- Set if the channel turns us away, so we don't keep knocking.
local turnedAway = false

-- Sending -------------------------------------------------------------------------

local function ChannelNumber()
    local number = GetChannelName(Channel())
    return type(number) == "number" and number > 0 and number or nil
end

local function ForgetOldMessages()
    local cutoff = GetTime() - 60
    while heardTimes[1] and heardTimes[1] < cutoff do
        table.remove(heardTimes, 1)
    end
end

local function ChannelIsBusy()
    ForgetOldMessages()
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

-- A market key off the wire could be anything. Only ones this account has
-- actually dealt in are worth our attention, or a place in the saved file.
local function IsKnownMarket(marketKey)
    return ns.db.markets[marketKey] ~= nil
end

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

local function Believable(marketKey, itemID, price, quantity)
    if price <= 0 or price > MAX_PRICE or quantity > MAX_QUANTITY then
        return false
    end

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

        if wanted and newer and Believable(marketKey, itemID, price, quantity) then
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
    local found = {}

    for itemID in itemList:gmatch("%d+") do
        -- Our own readings only. See the note at the top about the feed.
        local price, quantity, seenAt = ns.Ledger.LocalPrice(marketKey, tonumber(itemID))
        if price and seenAt and now - seenAt <= FRESH then
            table.insert(found, ("%s:%d:%d"):format(itemID, price, quantity or 0))
        end
    end

    local header = ("P|%s|%d|"):format(marketKey, ns.Ledger.LastScan(marketKey) or now)
    local room = MAX_MESSAGE_BYTES - #VERSION - #header

    -- Fill each message with as many prices as will fit, since dear items
    -- take more characters to write down than cheap ones.
    local first, sent = 1, 0
    while first <= #found and sent < MAX_REPLIES do
        local last, bytes = first, #found[first]
        while found[last + 1] and bytes + 1 + #found[last + 1] <= room do
            last = last + 1
            bytes = bytes + 1 + #found[last]
        end

        if not Send(header .. table.concat(found, ",", first, last)) then
            break
        end
        sent = sent + 1
        first = last + 1
    end

    if sent > 0 then
        lastAnswered = GetTime()
        ns.Log("network: answered with %d of %d items", first - 1, #found)
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
    local question = marketKey .. "|" .. itemList
    if pendingAnswers[question] then
        return
    end

    local wanted = {}
    for itemID in itemList:gmatch("%d+") do
        wanted[itemID] = true
    end
    if not next(wanted) then
        return
    end
    pendingAnswers[question] = { marketKey = marketKey, wanted = wanted }

    C_Timer.After(1 + math.random() * 4, function()
        if pendingAnswers[question] then
            pendingAnswers[question] = nil
            Answer(marketKey, itemList)
        end
    end)
end

-- Someone has answered with these prices. Any question of ours they cover
-- has been dealt with.
local function StandDown(marketKey, entries)
    for question, pending in pairs(pendingAnswers) do
        if pending.marketKey == marketKey then
            for itemID in entries:gmatch("(%d+):%d+:%d+") do
                if pending.wanted[itemID] then
                    pendingAnswers[question] = nil
                    break
                end
            end
        end
    end
end

-- Listening ---------------------------------------------------------------------------

local function IsOurs(sender)
    -- The sender arrives as "Name" or "Name-Realm" depending on the client.
    return sender and sender:match("^[^-]+") == UnitName("player")
end

-- The same prefix can be whispered, or sent to a party or guild, by anyone
-- who cares to. We only ever talk on our own channel, so only listen there.
local function IsFromOurChannel(kind, localID, name)
    return kind == "CHANNEL" and (localID == ChannelNumber() or name == Channel())
end

ns.OnEvent("CHAT_MSG_ADDON", function(prefix, text, kind, sender, _, _, localID, channelName)
    if prefix ~= PREFIX or not ns.settings.sharePrices or IsOurs(sender) then
        return
    end
    if not IsFromOurChannel(kind, localID, channelName) then
        return
    end

    ForgetOldMessages()
    table.insert(heardTimes, GetTime())

    if text:sub(1, 1) ~= VERSION then
        return
    end

    local messageType, marketKey, rest = text:match("^.(%a)|([^|]+)|?(.*)$")
    if not messageType then
        return
    end

    if messageType == "A" then
        -- Someone has just scanned this market. If it's ours and we're in
        -- need, this is the moment to ask. A short random wait keeps a
        -- crowd from all asking in the same second.
        if marketKey == ns.Market.Home() then
            C_Timer.After(3 + math.random() * 12, Ask)
        end
    elseif not IsKnownMarket(marketKey) then
        return
    elseif messageType == "Q" then
        ConsiderAnswering(marketKey, rest)
    elseif messageType == "P" then
        local scannedAt, entries = rest:match("^(%d+)|(.*)$")
        if scannedAt then
            StandDown(marketKey, entries)
            Remember(marketKey, tonumber(scannedAt), entries)
        end
    end
end)

-- Joining and leaving ------------------------------------------------------------------

-- Keeps the channel out of every chat window. It carries addon messages
-- only, so there would never be anything to read there.
local function HideChannel()
    for window = 1, NUM_CHAT_WINDOWS or 10 do
        pcall(RemoveChatWindowChannel, window, Channel())
    end
end

-- What the sharing setting was when we last acted on it. Other settings
-- changing is no reason to rejoin a channel the player has left by hand.
local wasSharing

local function UpdateMembership()
    if ns.settings.sharePrices == wasSharing then
        return
    end
    wasSharing = ns.settings.sharePrices

    if ns.settings.sharePrices then
        if not ChannelNumber() and not turnedAway then
            JoinTemporaryChannel(Channel())
            -- The join is confirmed by a notice (below), which is the
            -- proper moment to hide the channel. This is for the day the
            -- notice doesn't come.
            C_Timer.After(2, HideChannel)
        end
    elseif ChannelNumber() then
        LeaveChannelByName(Channel())
    end
end

-- The game tells us how joining went. The ninth value is the channel's name.
ns.OnEvent("CHAT_MSG_CHANNEL_NOTICE", function(notice, _, _, _, _, _, _, _, channelName)
    if type(channelName) ~= "string" or channelName:lower() ~= Channel():lower() then
        return
    end

    if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
        HideChannel()
    elseif notice == "WRONG_PASSWORD" or notice == "BANNED" then
        -- Somebody has locked the channel or thrown us out. Asking again
        -- would only put a password prompt in front of the player each
        -- time, so sharing is off until the next login.
        turnedAway = true
        ns.Log("network: turned away from the channel (%s)", notice)
    end
end)

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
