local _, ns = ...

-- A mark on items in the player's bags and bank that are worth taking to
-- the auction house: a gold rim and a coin in the corner.
--
-- It's meant to be seen. Sorting through a full bank for the handful of
-- things worth selling is exactly the chore Goldwise exists to take away,
-- so the answer is drawn on the items themselves. It can be switched off.
--
-- Every item button in the game, Blizzard's own and other addons' alike,
-- goes through one function to draw its quality border. We listen in on
-- that, which is how this works in the default bags, the bank and bag
-- addons such as Bagnon without knowing anything about any of them.

local Theme = ns.Theme

-- The rim is drawn larger than the button, as the game's own button
-- borders are, so its glow sits around the icon rather than over it.
local RIM_SCALE = 1.7

-- Our textures, by the button they belong to. Kept here rather than on
-- the buttons, which aren't ours to add things to. Weak, so a button that
-- goes away takes its mark with it.
local marks = setmetatable({}, { __mode = "k" })

-- Whether a stack is worth auctioning: ["itemID:count"] = true or false.
-- Thrown away whenever prices change.
local verdicts = {}

-- What a button holds ----------------------------------------------------------------

-- Returns the item ID, stack size and whether it's soulbound for a bag or
-- bank button, or nothing for any other kind of button (a merchant's
-- wares, loot, a quest reward) and for an empty slot.
local function Contents(button)
    -- Bagnon and its relatives keep what they know about the slot here.
    -- This also covers a bank they're showing from memory.
    local info = button.info
    if type(info) == "table" then
        return info.itemID, info.stackCount, info.isBound
    end

    -- Blizzard's buttons know which bag and slot they stand for.
    local bag, slot
    if button.GetBankTabID and button.GetContainerSlotID then
        bag, slot = button:GetBankTabID(), button:GetContainerSlotID()
    elseif button.GetBagID and button.GetID then
        bag, slot = button:GetBagID(), button:GetID()
    end

    if type(bag) == "number" and type(slot) == "number" then
        info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.itemID, info.stackCount, info.isBound
        end
    end
end

local function WorthAuctioning(itemID, count)
    local key = itemID .. ":" .. count
    if verdicts[key] == nil then
        -- What a vendor pays is part of the decision, and it isn't known
        -- until the client has the item's details. Until then, say
        -- nothing and don't remember having said it.
        if select(11, C_Item.GetItemInfo(itemID)) == nil then
            return false
        end

        local asset = ns.Assets.Describe({ itemID = itemID, count = count }, ns.Market.Home())
        verdicts[key] = asset.advice.verb == ns.Advice.SELL
    end
    return verdicts[key]
end

-- Drawing ------------------------------------------------------------------------------

local function CreateMark(button)
    local mark = {}

    mark.Rim = button:CreateTexture(nil, "OVERLAY", nil, 6)
    mark.Rim:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    mark.Rim:SetBlendMode("ADD")
    mark.Rim:SetVertexColor(unpack(Theme.COIN))
    mark.Rim:SetPoint("CENTER")
    mark.Rim:SetSize(button:GetWidth() * RIM_SCALE, button:GetHeight() * RIM_SCALE)

    mark.Coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
    mark.Coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    mark.Coin:SetSize(14, 14)
    mark.Coin:SetPoint("TOPLEFT", 1, -1)

    return mark
end

local function SetMarked(button, marked)
    local mark = marks[button]
    if not mark then
        if not marked then
            return
        end
        mark = CreateMark(button)
        marks[button] = mark
    end

    mark.Rim:SetShown(marked)
    mark.Coin:SetShown(marked)
end

local function Update(button)
    local marked = false
    if ns.settings and ns.settings.markSellable then
        local itemID, count, isBound = Contents(button)
        -- A soulbound item can't be sold to anyone, whatever it's worth.
        if itemID and not isBound then
            marked = WorthAuctioning(itemID, count or 1)
        end
    end
    SetMarked(button, marked)
end

-- Keeping up ----------------------------------------------------------------------------

-- Called for every item button whenever what it shows may have changed.
hooksecurefunc("SetItemButtonQuality", function(button)
    -- Another addon's button is another addon's business. If it's built
    -- in some way we didn't foresee, leave it alone rather than break it.
    pcall(Update, button)
end)

-- New prices, or a change of mind in the options, can alter the answer
-- for buttons that are sitting there unchanged.
local function UpdateAll()
    verdicts = {}
    for button in pairs(marks) do
        if button:IsVisible() then
            pcall(Update, button)
        else
            SetMarked(button, false)
        end
    end
end

ns.Subscribe("PRICES_CHANGED", UpdateAll)
ns.Subscribe("SETTINGS_CHANGED", UpdateAll)
