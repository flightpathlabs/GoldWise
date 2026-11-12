local _, ns = ...

-- What's in the bank.
--
-- The game only lets an addon read the bank while it's open, so what's in
-- it is remembered from the player's last visit. That makes it a little
-- stale by nature, and anything built on it says when it was last seen.
--
-- A character's own bank is kept under that character. The bank the whole
-- account shares is kept once, since everybody's view of it is the same.

local Bank = {}
ns.Bank = Bank

-- The key the shared bank is filed under, alongside the characters'.
local ACCOUNT = "account"

-- Bank updates arrive in bursts, as bag updates do.
local SETTLE_DELAY = 0.5

local isOpen = false
local scanPending = false

-- Saved contents: [key] = { holdings, counts, seenAt }, where holdings is
-- [itemID] = { name, icon, quality, link, count } for what could be sold
-- and counts is [itemID] = how many, for everything.
local function Vaults()
    if type(ns.db.banks) ~= "table" then
        ns.db.banks = {}
    end
    return ns.db.banks
end

-- Reading --------------------------------------------------------------------------------

-- Goes through every tab the player has bought in one kind of bank.
local function ReadTabs(bankType)
    local holdings, counts = {}, {}

    for _, bag in ipairs(C_Bank.FetchPurchasedBankTabIDs(bankType) or {}) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item then
                counts[item.itemID] = (counts[item.itemID] or 0) + item.stackCount

                if ns.Bags.IsWorthListing(item) then
                    local holding = holdings[item.itemID]
                    if holding then
                        holding.count = holding.count + item.stackCount
                    else
                        holdings[item.itemID] = {
                            name = item.itemName,
                            icon = item.iconFileID,
                            quality = item.quality,
                            link = item.hyperlink,
                            count = item.stackCount,
                        }
                    end
                end
            end
        end
    end

    return { holdings = holdings, counts = counts, seenAt = GetServerTime() }
end

local function Scan()
    scanPending = false
    -- The bank may have closed while we waited for it to settle, and a
    -- closed bank reads as an empty one.
    if not isOpen then
        return
    end

    local vaults = Vaults()
    vaults[ns.Characters.CurrentKey()] = ReadTabs(Enum.BankType.Character)
    vaults[ACCOUNT] = ReadTabs(Enum.BankType.Account)

    -- Follow what's banked as closely as what's carried, so it has price
    -- history by the time the player wonders what it's worth.
    local home = ns.Market.Home()
    for _, vault in pairs({ vaults[ns.Characters.CurrentKey()], vaults[ACCOUNT] }) do
        for itemID in pairs(vault.holdings) do
            ns.Ledger.Track(home, itemID)
        end
    end

    ns.Publish("BAGS_CHANGED")
end

local function ScanSoon()
    if isOpen and not scanPending then
        scanPending = true
        C_Timer.After(SETTLE_DELAY, Scan)
    end
end

-- Reading it back --------------------------------------------------------------------

-- A vault's sellable contents as a list shaped like Bags.Holdings().
local function HoldingsOf(vault)
    local list = {}
    for itemID, holding in pairs(vault and vault.holdings or {}) do
        table.insert(list, {
            itemID = itemID,
            name = holding.name,
            icon = holding.icon,
            quality = holding.quality,
            link = holding.link,
            count = holding.count,
        })
    end
    return list, vault and vault.seenAt
end

--- The sellable things in a character's bank, as of their last visit.
---@param characterKey string|nil  from Characters.CurrentKey; the current
---        character if left out
---@return table holdings      list shaped like Bags.Holdings()
---@return number|nil seenAt   when the bank was last open; nil if never
function Bank.Holdings(characterKey)
    return HoldingsOf(Vaults()[characterKey or ns.Characters.CurrentKey()])
end

--- The sellable things in the bank the whole account shares.
---@return table holdings
---@return number|nil seenAt
function Bank.AccountHoldings()
    return HoldingsOf(Vaults()[ACCOUNT])
end

--- How many of an item the current character has banked, counting their
--- own bank and the shared one.
---@param itemID number
---@return number
function Bank.Count(itemID)
    local vaults = Vaults()
    local own = vaults[ns.Characters.CurrentKey()]
    local shared = vaults[ACCOUNT]
    return (own and own.counts[itemID] or 0) + (shared and shared.counts[itemID] or 0)
end

ns.OnEvent("BANKFRAME_OPENED", function()
    isOpen = true
    ScanSoon()
end)

ns.OnEvent("BANKFRAME_CLOSED", function()
    isOpen = false
end)

-- Moving things in and out while it's open.
ns.OnEvent("PLAYERBANKSLOTS_CHANGED", ScanSoon)
ns.OnEvent("BAG_UPDATE_DELAYED", ScanSoon)
