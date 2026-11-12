local _, ns = ...

-- The Assets tab: what the player holds, one row per item, with its
-- price, a two-week trend line, and what Goldwise would do with it. Under
-- the list is what it all comes to at auction.

local ShelfList = {}
ns.ShelfList = ShelfList

local Theme = ns.Theme

local ROW_HEIGHT = 44

-- Room under the list for the line that adds it all up.
local WORTH_HEIGHT = 30

-- Columns are placed from the right edge, in pixels. The verdict column is
-- wide enough for "about 1,234g 56s 78c".
local VERDICT_RIGHT = 12
local TREND_RIGHT = 148
local PRICE_RIGHT = 234
local NAME_RIGHT = 346

-- Rows --------------------------------------------------------------------------

-- The menu behind a right-click: keep the item or sell it, and a way to
-- its page for anyone who went looking for that here.
local function ShowKeepMenu(row, data, onSelect)
    local kept = ns.Keep.IsKept(data.itemID)

    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(data.name)
        root:CreateButton(
            kept and "Suggest selling this again" or "Keep this, don't suggest selling",
            function()
                ns.Keep.Toggle(data.itemID)
            end
        )
        root:CreateButton("Price history", function()
            onSelect(data)
        end)
        if ns.CraftTree.Has(data.itemID) then
            root:CreateButton("Crafting tree", function()
                ns.ShowCraftTree(data.itemID)
            end)
        end
    end)
end

local function CreateRowWidgets(row, onSelect)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(32, 32)
    row.Icon:SetPoint("LEFT", 6, 0)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -2)
    row.Name:SetPoint("RIGHT", row, "RIGHT", -NAME_RIGHT, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Reason = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Reason:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -4)
    row.Reason:SetPoint("RIGHT", row, "RIGHT", -NAME_RIGHT, 0)
    row.Reason:SetJustifyH("LEFT")
    row.Reason:SetWordWrap(false)
    row.Reason:SetTextColor(unpack(Theme.MUTED))

    row.Price = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PRICE_RIGHT, -8)
    row.Price:SetJustifyH("RIGHT")

    row.Listed = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Listed:SetPoint("TOPRIGHT", row.Price, "BOTTOMRIGHT", 0, -4)
    row.Listed:SetJustifyH("RIGHT")
    row.Listed:SetTextColor(unpack(Theme.MUTED))

    row.Trend = ns.Chart.CreateSparkline(row, 72, 22)
    row.Trend:SetPoint("RIGHT", row, "RIGHT", -TREND_RIGHT, 0)

    row.Verb = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Verb:SetPoint("TOPRIGHT", row, "TOPRIGHT", -VERDICT_RIGHT, -8)
    row.Verb:SetJustifyH("RIGHT")

    row.Proceeds = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Proceeds:SetPoint("TOPRIGHT", row.Verb, "BOTTOMRIGHT", 0, -4)
    row.Proceeds:SetJustifyH("RIGHT")
    row.Proceeds:SetTextColor(unpack(Theme.MUTED))

    -- Left-click for the item's page; right-click to say whether it's for
    -- sale at all.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
        local data = self:GetElementData()
        if mouseButton == "RightButton" then
            ShowKeepMenu(self, data, onSelect)
        else
            onSelect(data)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local data = self:GetElementData()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The link keeps suffixes and enchants that the bare ID would lose.
        if data.link then
            GameTooltip:SetHyperlink(data.link)
        else
            GameTooltip:SetItemByID(data.itemID)
        end

        local muted = Theme.MUTED
        GameTooltip:AddLine(
            ns.Keep.IsKept(data.itemID) and "Right-click to put this up for sale again."
                or "Right-click to keep this: Goldwise won't suggest selling it.",
            muted[1],
            muted[2],
            muted[3]
        )
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function TrendColor(againstUsual)
    if againstUsual and againstUsual >= 0.1 then
        return Theme.VERB_COLORS.sell
    elseif againstUsual and againstUsual <= -0.1 then
        return Theme.VERB_COLORS.hold
    end
    return Theme.MUTED
end

local function FillRow(row, data)
    local advice = data.advice

    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.Icon:SetTexture(data.icon)
    -- A count of one is the normal case and doesn't need saying.
    local name = Theme.ItemName(data.name, data.quality)
    if data.count > 1 then
        name = name .. "  " .. Theme.Aside("x" .. data.count)
    end
    -- Where they are, if they aren't all to hand.
    if (data.inBank or 0) > 0 and not data.owner then
        local where = data.inBank == data.count and "in your bank"
            or (data.inBank .. " in your bank")
        name = name .. "  " .. Theme.Aside(where)
    end
    -- Things another character holds say whose they are.
    if data.owner then
        name = name .. "  " .. Theme.Aside("on " .. data.owner)
    end
    row.Name:SetText(name)
    row.Reason:SetText(advice.reason)

    if data.price then
        row.Price:SetText(Theme.Coins(data.price))
        row.Listed:SetText(Theme.Listed(data.listed))
    else
        row.Price:SetText("")
        row.Listed:SetText("")
    end

    row.Trend:SetValues(data.trend, TrendColor(data.againstUsual))

    row.Verb:SetText(Theme.VERB_LABELS[advice.verb])
    row.Verb:SetTextColor(unpack(Theme.VERB_COLORS[advice.verb]))

    -- Under the verdict, the money it would bring in.
    if advice.verb == ns.Advice.SELL and advice.proceeds then
        row.Proceeds:SetText("about " .. Theme.Coins(advice.proceeds))
    elseif advice.verb == ns.Advice.VENDOR and (advice.fromVendor or 0) > 0 then
        row.Proceeds:SetText("pays " .. Theme.Coins(advice.fromVendor))
    else
        row.Proceeds:SetText("")
    end
end

-- Ordering -----------------------------------------------------------------------------

-- Most valuable first; things we can't price yet go to the bottom.
local function ByProceeds(a, b)
    local left, right = a.advice.proceeds or -1, b.advice.proceeds or -1
    if left ~= right then
        return left > right
    end
    return a.name < b.name
end

-- The list ---------------------------------------------------------------------------

--- Creates the shelf list. It fills its parent.
---@param parent table            frame to fill
---@param onSelect fun(row: table) called when the player clicks a row
---@return table list             with :Refresh()
function ShelfList.Create(parent, onSelect)
    local list = CreateFrame("Frame", nil, parent)
    list:SetAllPoints()

    local heading = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Assets")

    local about = list:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))

    -- Switches between this character's bags and everyone's.
    local scope = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    scope:SetSize(130, 20)
    scope:SetPoint("TOPRIGHT", -24, -6)
    scope:SetScript("OnClick", function()
        ns.settings.allCharacters = not ns.settings.allCharacters
        ns.Publish("SETTINGS_CHANGED")
    end)

    local empty = list:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("CENTER")
    empty:SetTextColor(unpack(Theme.MUTED))

    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -32)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    -- Rows are plain buttons rather than an XML template, so the list can't
    -- work out their height for itself.
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row, onSelect)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Under the list: what it all comes to at auction, for this character
    -- and for the account. Always both, whichever the list is showing.
    local worth = list:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    worth:SetPoint("BOTTOMLEFT", 12, 8)
    worth:SetPoint("RIGHT", scrollBox, "RIGHT", -6, 0)
    worth:SetJustifyH("LEFT")
    worth:SetWordWrap(false)

    local function ShowWorth(marketKey)
        local mine, everything = ns.Assets.WorthOfEverything(marketKey)

        local text
        if everything > mine then
            text = ("Worth at auction: %s on this character  %s"):format(
                Theme.Coins(mine),
                Theme.Aside(("(%s in total)"):format(Theme.Coins(everything)))
            )
        elseif mine > 0 then
            text = ("Worth at auction: %s"):format(Theme.Coins(mine))
        end

        -- The list gives up its bottom edge to the line while there's
        -- something to say.
        worth:SetText(text or "")
        worth:SetShown(text ~= nil)
        scrollBox:SetPoint("BOTTOMRIGHT", -22, text and WORTH_HEIGHT or 6)
    end

    --- Rebuilds the rows from what the player holds and the current prices.
    ---@return number total  what selling everything marked Sell should bring in
    function list:Refresh()
        local marketKey = ns.Market.Current()
        local everyone = ns.settings.allCharacters
        local rows = {}
        local total = 0

        -- One row per item for each owner, however it's split between
        -- their bags and their bank. The row says how many are banked.
        local function AddAll(carried, banked, owner)
            local byItem, order = {}, {}

            local function Merge(holding, inBank)
                local merged = byItem[holding.itemID]
                if not merged then
                    merged = {
                        itemID = holding.itemID,
                        name = holding.name,
                        icon = holding.icon,
                        quality = holding.quality,
                        link = holding.link,
                        count = 0,
                        inBank = 0,
                    }
                    byItem[holding.itemID] = merged
                    table.insert(order, merged)
                end
                merged.count = merged.count + holding.count
                if inBank then
                    merged.inBank = merged.inBank + holding.count
                end
            end

            for _, holding in ipairs(carried) do
                Merge(holding, false)
            end
            for _, holding in ipairs(banked) do
                Merge(holding, true)
            end

            for _, holding in ipairs(order) do
                local row = ns.Assets.Describe(holding, marketKey, owner)
                row.inBank = holding.inBank
                table.insert(rows, row)

                if row.advice.verb == ns.Advice.SELL then
                    total = total + (row.advice.proceeds or 0)
                end
            end
        end

        local banked, bankSeenAt = ns.Bank.Holdings()
        AddAll(ns.Bags.Holdings(), banked)
        ShowWorth(marketKey)

        -- The bank every character shares is this character's to sell
        -- from as much as anyone's.
        AddAll({}, ns.Bank.AccountHoldings(), "the account bank")

        if everyone then
            -- Matched on home market, not the open auction house: at a
            -- neutral house nobody's home would match, and the list would
            -- quietly lose every other character.
            for _, character in ipairs(ns.Characters.Others(ns.Market.Home())) do
                AddAll(character.holdings, ns.Bank.Holdings(character.key), character.name)
            end
        end
        table.sort(rows, ByProceeds)

        if everyone then
            about:SetText("Sellable things on all your characters, as of their last login")
            scope:SetText("This character")
        elseif bankSeenAt then
            about:SetText(
                "Sellable things in your bags and bank (bank as of "
                    .. ns.Ago(GetServerTime() - bankSeenAt)
                    .. ")"
            )
            scope:SetText("All characters")
        else
            -- The bank can only be read while it's open, and it hasn't
            -- been since Goldwise was installed.
            about:SetText("Sellable things in your bags. Open your bank once to add what's in it.")
            scope:SetText("All characters")
        end

        empty:SetText(
            everyone and "None of your characters has anything to sell right now."
                or "Nothing in your bags to sell right now."
        )
        empty:SetShown(#rows == 0)
        scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
        return total
    end

    return list
end
