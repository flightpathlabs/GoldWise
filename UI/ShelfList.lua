local _, ns = ...

-- The list of what the player holds: one row per item, with its price, a
-- two-week trend line, and what Goldwise would do with it.
--
-- For now there is one shelf, "Assets". The list is built so that further
-- shelves can be added as more rows without changing how rows are drawn.

local ShelfList = {}
ns.ShelfList = ShelfList

local Theme = ns.Theme

local ROW_HEIGHT = 44

-- Columns are placed from the right edge, in pixels. The verdict column is
-- wide enough for "about 1,234g 56s 78c".
local VERDICT_RIGHT = 12
local TREND_RIGHT = 148
local PRICE_RIGHT = 234
local NAME_RIGHT = 346

-- Rows --------------------------------------------------------------------------

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

    row:SetScript("OnClick", function(self)
        onSelect(self:GetElementData())
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
        name = ("%s  |cffb9aa8cx%d|r"):format(name, data.count)
    end
    -- Things another character holds say whose they are.
    if data.owner then
        name = ("%s  |cffb9aa8con %s|r"):format(name, data.owner)
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

-- Gathering the facts ----------------------------------------------------------------

-- Items whose details we've asked the client to load this session.
local requested = {}

--- Whether the list asked the client to load this item's details, and so
--- has something to gain from redrawing now that they've arrived.
---@param itemID number
---@return boolean
function ShelfList.IsWaitingFor(itemID)
    return requested[itemID] == true
end

---@param holding table       one entry from Bags.Holdings or Characters.Others
---@param marketKey string
---@param owner string|nil    the character holding it, if not the current one
local function DescribeHolding(holding, marketKey, owner)
    local itemID = holding.itemID
    local price, listed, seenAt, source = ns.Ledger.Price(marketKey, itemID)

    local history = ns.Ledger.History(marketKey, itemID, ns.Stats.USUAL_DAYS)
    local againstUsual = ns.Stats.AgainstUsual(history)

    local trend = {}
    for index, day in ipairs(history) do
        trend[index] = day.last
    end

    -- The eleventh value is what a vendor pays. It's missing until the
    -- client has the item cached. That's nearly always true for the
    -- player's own bags, but not for another character's, so ask for it;
    -- the window redraws when the answer arrives.
    local vendorPrice = select(11, C_Item.GetItemInfo(itemID))
    if vendorPrice == nil and not requested[itemID] then
        -- Once per session is enough. If the client can't load an item,
        -- asking again on every redraw would never end.
        requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end

    return {
        itemID = itemID,
        owner = owner,
        name = holding.name or ("Item " .. itemID),
        icon = holding.icon,
        quality = holding.quality,
        link = holding.link,
        count = holding.count,
        price = price,
        listed = listed,
        seenAt = seenAt,
        source = source,
        trend = trend,
        againstUsual = againstUsual,
        advice = ns.Advice.ForHolding({
            count = holding.count,
            price = price,
            vendorPrice = vendorPrice,
            againstUsual = againstUsual,
            cut = ns.Market.Cut(marketKey),
            auditor = ns.settings.auditorMode,
        }),
    }
end

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

    --- Rebuilds the rows from what the player holds and the current prices.
    ---@return number total  what selling everything marked Sell should bring in
    function list:Refresh()
        local marketKey = ns.Market.Current()
        local everyone = ns.settings.allCharacters
        local rows = {}
        local total = 0

        local function Add(holding, owner)
            local row = DescribeHolding(holding, marketKey, owner)
            table.insert(rows, row)

            if row.advice.verb == ns.Advice.SELL then
                total = total + (row.advice.proceeds or 0)
            end
        end

        for _, holding in ipairs(ns.Bags.Holdings()) do
            Add(holding)
        end

        if everyone then
            -- Matched on home market, not the open auction house: at a
            -- neutral house nobody's home would match, and the list would
            -- quietly lose every other character.
            for _, character in ipairs(ns.Characters.Others(ns.Market.Home())) do
                for _, holding in ipairs(character.holdings) do
                    Add(holding, character.name)
                end
            end
        end
        table.sort(rows, ByProceeds)

        if everyone then
            about:SetText("Sellable things on all your characters, as of their last login")
            scope:SetText("This character")
        else
            about:SetText("Sellable things in your bags")
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
