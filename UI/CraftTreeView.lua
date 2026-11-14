local _, ns = ...

-- The page for one item's crafting tree: what it's made from, step by
-- step, and what it goes into, with what each costs to buy or to make.
-- Advisor\CraftTree does the sums; this only draws them.
--
-- Every row is an item, and clicking one makes it the subject of the
-- page, so the player can walk up and down a chain of recipes. Back
-- retraces their steps before it leaves. Right-clicking one opens the
-- usual item menu instead.
--
-- The recipes are every character's, and where it isn't only the one
-- being played who knows a recipe, the page says who does.

local CraftTreeView = {}
ns.CraftTreeView = CraftTreeView

local Theme = ns.Theme

local ROW_HEIGHT = 36

-- Each step down the tree is set in by this much.
local INDENT = 22

-- Three columns of figures, placed from the right edge.
local FIGURES = 3
local FIGURE_WIDTH = 108
local FIGURES_RIGHT = 10

-- What stands over the figures in each part of the page.
local MADE_FROM_CAPTIONS = { "auction, each", "to buy", "to make" }
local GOES_INTO_CAPTIONS = { "auction, each", "materials", "profit" }

-- Words -----------------------------------------------------------------------

-- How many of something a step takes, as words. A recipe that makes
-- two at a time leaves the step above wanting half a batch, and so half
-- of each ingredient. The figures beside it are for that half, so the
-- count has to say so too.
local function HowMany(quantity)
    -- A recipe that makes a great many at a time can leave a step
    -- wanting next to nothing of an ingredient.
    if quantity < 0.05 then
        return "under 0.1"
    end

    -- To one place, and no ".0" on a whole number.
    local text = ("%.1f"):format(quantity)
    return (text:gsub("%.0$", ""))
end

-- Who knows a recipe, to start a sentence with: "You", "Torin", "You and
-- Torin", "You, Torin and 2 more". The character being played comes
-- first, as Crafts lists them.
local function Who(recipe)
    local names = {}
    for index, character in ipairs(recipe.knownBy) do
        names[index] = (index == 1 and recipe.mine) and "You" or character.name
    end

    if #names > 3 then
        return ("%s, %s and %d more"):format(names[1], names[2], #names - 2)
    elseif #names == 3 then
        return ("%s, %s and %s"):format(names[1], names[2], names[3])
    elseif #names == 2 then
        return ("%s and %s"):format(names[1], names[2])
    end
    return names[1]
end

-- Whether a recipe is worth saying who knows. When it's only the
-- character being played, as it mostly is, saying so on every row is
-- noise.
local function SayWho(recipe)
    return not recipe.mine or #recipe.knownBy > 1
end

-- A profit in green; a loss in red, with a minus sign.
local function ProfitText(amount)
    return Theme.Tint(Theme.SignedCoins(amount))
end

-- Rows ------------------------------------------------------------------------

-- One ingredient: how many, what they cost bought and made, and which of
-- those is the better deal. Where it can be made, the note starts with
-- who can make it.
local function PartRow(part)
    local makeable = part.recipe ~= nil
    local who = makeable and Who(part.recipe)
    local buy = part.buy and Theme.Coins(part.buy) or ""
    local make = part.make and Theme.Coins(part.make) or ""
    local note

    if makeable and part.buy and part.make then
        if part.make < part.buy then
            make = Theme.Tint(make, Theme.INCOME)
            note = ("%s can make this, and save %s."):format(who, ns.Money(part.buy - part.make))
        else
            buy = Theme.Tint(buy, Theme.INCOME)
            note = who .. " can make this, but it's cheaper bought."
        end
    elseif makeable and part.make then
        note = who .. " can make this. None are for sale."
    elseif makeable then
        note = who .. " can make this, but something in it has no price yet."
    elseif part.fromVendor then
        buy = "about " .. buy
        note = "From a vendor. The price is a guess."
    elseif part.price then
        note = Theme.Listed(part.listed) .. "."
    else
        note = "No price yet."
    end

    return {
        itemID = part.itemID,
        depth = part.depth,
        title = ("%s %s"):format(HowMany(part.quantity), ns.ItemLabel(part.itemID)),
        note = note,
        figures = { part.price and Theme.Coins(part.price) or "", buy, make },
    }
end

-- An ingredient, then everything that goes into it, set in beneath.
local function AddParts(rows, parts)
    for _, part in ipairs(parts) do
        table.insert(rows, PartRow(part))
        if part.parts then
            AddParts(rows, part.parts)
        end
    end
end

-- One thing the item goes into: what it sells for, what its materials
-- come to, and what's left.
local function IntoRow(product)
    local notes = {}
    if SayWho(product.recipe) then
        table.insert(notes, Who(product.recipe) .. " can make it.")
    end
    if product.makes > 1 then
        table.insert(notes, ("Makes %d."):format(product.makes))
    end
    if not product.price then
        table.insert(notes, "No auction price yet.")
    elseif not product.cost then
        table.insert(notes, "Something in it has no price yet.")
    end
    if product.onward > 0 then
        table.insert(notes, ("Goes on into %d more."):format(product.onward))
    end

    return {
        itemID = product.itemID,
        depth = 1,
        title = ns.ItemLabel(product.itemID) .. "  " .. Theme.Aside(product.recipe.profession),
        note = table.concat(notes, " "),
        figures = {
            product.price and Theme.Coins(product.price) or "",
            product.cost and Theme.Coins(product.cost) or "",
            product.profit and ProfitText(product.profit) or "",
        },
    }
end

local function Rows(tree)
    local rows = {}

    if tree.root.parts then
        local heading = "Made from"
        if tree.root.quantity > 1 then
            heading = ("To make %d"):format(tree.root.quantity)
        end
        table.insert(rows, { heading = heading, captions = MADE_FROM_CAPTIONS })
        AddParts(rows, tree.root.parts)
    end

    if #tree.into > 0 then
        table.insert(rows, { heading = "Goes into", captions = GOES_INTO_CAPTIONS })
        for _, product in ipairs(tree.into) do
            table.insert(rows, IntoRow(product))
        end
        if tree.intoMore > 0 then
            table.insert(rows, {
                depth = 1,
                title = ("And %d more"):format(tree.intoMore),
                note = "The ones above are the most profitable.",
                figures = {},
            })
        end
    end

    return rows
end

-- The sentences at the top: whether buying the materials, making it and
-- selling it pays, and whether making the parts as well does any better.
local function Summary(tree)
    local root = tree.root

    -- Nothing to show. This is also where the shortcut lands on an item
    -- nobody can do anything with, and where it lands before any recipes
    -- have been read at all, so it says how to fill the page.
    if not root.recipe and #tree.into == 0 then
        return "None of your characters knows a recipe that makes or uses this yet.",
            "If one does, open that profession's window on them once and Goldwise will learn it."
    end

    if not root.recipe then
        return "None of your characters knows a recipe that makes this.",
            "Below is what they can make with it, and what each would earn."
    end

    local forHowMany = root.quantity > 1 and ("For %d: "):format(root.quantity) or ""

    if not tree.materials and not root.make then
        return forHowMany .. "Some of its materials have no price yet.",
            "Visit an auction house and let Goldwise read it."
    end

    -- Buying every ingredient outright is the plain case. Where that
    -- can't be priced, the cheapest way of making it is all there is.
    local outlay = tree.materials or root.make
    local first
    if tree.sells then
        local profit = tree.sells - outlay
        first = ("%sBuy the materials for %s, make it and sell it: %s %s after the cut."):format(
            forHowMany,
            Theme.Coins(outlay),
            profit >= 0 and "a profit of" or "a loss of",
            Theme.Tint(
                Theme.Coins(math.abs(profit)),
                profit >= 0 and Theme.INCOME or Theme.SPENDING
            )
        )
    else
        local unsold = "%sThe materials cost %s. It has no auction price yet, "
            .. "so there's no telling what it would earn."
        first = unsold:format(forHowMany, Theme.Coins(outlay))
    end

    local second = {}

    -- The price below which making it to sell loses money, whatever the
    -- market does. It's a sum, not a forecast, so it can always be said.
    local cheapest = math.min(outlay, root.make or outlay)
    table.insert(
        second,
        ("It has to fetch more than %s each to cover what goes into it."):format(
            Theme.Coins(cheapest / root.quantity / (1 - tree.cut))
        )
    )
    if root.make and root.make < outlay then
        local line = ("Making the parts you can make brings the cost down to %s"):format(
            Theme.Coins(root.make)
        )
        if tree.sells then
            line = ("%s, which leaves %s"):format(line, ProfitText(tree.sells - root.make))
        end
        table.insert(second, line .. ".")
    end
    if root.buy and root.make then
        if root.buy < root.make then
            table.insert(
                second,
                ("For your own use it's cheaper bought: %s."):format(Theme.Coins(root.buy))
            )
        else
            table.insert(
                second,
                ("For your own use, making it saves %s."):format(Theme.Coins(root.buy - root.make))
            )
        end
    end
    return first, table.concat(second, " ")
end

-- Drawing a row ---------------------------------------------------------------

local function CreateRowWidgets(row, onPick, onHistory)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    row.Heading = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.Heading:SetPoint("BOTTOMLEFT", 8, 6)

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(26, 26)

    row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Title:SetJustifyH("LEFT")
    row.Title:SetWordWrap(false)

    row.Note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Note:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
    row.Note:SetJustifyH("LEFT")
    row.Note:SetWordWrap(false)
    row.Note:SetTextColor(unpack(Theme.MUTED))

    -- Counted from the right. A heading's captions sit in the same
    -- columns as the figures under them.
    row.Figures, row.Captions = {}, {}
    for index = 1, FIGURES do
        local right = -(FIGURES_RIGHT + (index - 1) * FIGURE_WIDTH)

        local figure = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        figure:SetPoint("RIGHT", right, 0)
        figure:SetWidth(FIGURE_WIDTH)
        figure:SetJustifyH("RIGHT")
        figure:SetWordWrap(false)
        row.Figures[index] = figure

        local caption = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        caption:SetPoint("BOTTOMRIGHT", right, 6)
        caption:SetJustifyH("RIGHT")
        row.Captions[index] = caption
    end

    row:SetScript("OnEnter", function(self)
        local itemID = self:GetElementData().itemID
        if itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    -- Left-click follows the chain to that item; right-click has the
    -- same menu as an item anywhere else in Goldwise.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
        local itemID = self:GetElementData().itemID
        if not itemID then
            return
        elseif mouseButton == "RightButton" then
            -- Through the tree's own way to an item's page, so Back comes here.
            ns.ItemMenu.Open(self, itemID, nil, nil, function()
                onHistory(itemID)
            end)
        else
            onPick(itemID)
        end
    end)
end

local function FillRow(row, data)
    local isHeading = data.heading ~= nil

    row.Stripe:SetShown(not isHeading and row:GetOrderIndex() % 2 == 0)
    row.Heading:SetShown(isHeading)
    row.Icon:SetShown(not isHeading and data.itemID ~= nil)
    row.Title:SetShown(not isHeading)
    row.Note:SetShown(not isHeading)
    -- Only rows with an item behind them should light up when pointed at.
    row:EnableMouse(not isHeading and data.itemID ~= nil)

    -- Given left to right, placed from the right.
    for index = 1, FIGURES do
        local given = FIGURES - index + 1
        row.Captions[index]:SetText(isHeading and data.captions and data.captions[given] or "")
        row.Figures[index]:SetText(not isHeading and data.figures[given] or "")
    end

    if isHeading then
        row.Heading:SetText(data.heading:upper())
        return
    end

    local indent = 8 + (data.depth - 1) * INDENT
    local namesRight = -(FIGURES_RIGHT + FIGURES * FIGURE_WIDTH + 10)

    row.Icon:ClearAllPoints()
    row.Icon:SetPoint("LEFT", indent, 0)
    row.Icon:SetTexture(data.itemID and C_Item.GetItemIconByID(data.itemID))

    row.Title:ClearAllPoints()
    row.Title:SetPoint("TOPLEFT", indent + 34, -5)
    row.Title:SetPoint("RIGHT", row, "RIGHT", namesRight, 0)
    row.Note:SetPoint("RIGHT", row, "RIGHT", namesRight, 0)

    local title = data.title
    if data.itemID then
        title = Theme.ItemName(title, C_Item.GetItemQualityByID(data.itemID))
    end
    row.Title:SetText(title)
    row.Note:SetText(data.note or "")
end

-- The page --------------------------------------------------------------------

--- Creates the crafting tree page. It starts hidden and fills its parent.
---@param parent table            frame to fill
---@param onBack fun()            called when the player backs out of the page
---@param onHistory fun(itemID: number)  called for an item's price history
---@return table view             with :ShowItem(itemID) and :Refresh()
function CraftTreeView.Create(parent, onBack, onHistory)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    -- The item the page is about, and the ones the player came through
    -- to reach it, oldest first.
    local subject
    local trail = {}

    local back = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    back:SetSize(70, 22)
    back:SetPoint("TOPLEFT", 12, -12)
    back:SetText("Back")

    local history = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    history:SetSize(110, 22)
    history:SetPoint("TOPRIGHT", -14, -12)
    history:SetText("Price history")
    history:SetScript("OnClick", function()
        onHistory(subject)
    end)

    local icon = view:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", back, "TOPRIGHT", 14, 4)

    local name = view:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)

    local facts = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    facts:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    facts:SetTextColor(unpack(Theme.MUTED))

    local verdict = view:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
    verdict:SetPoint("TOPLEFT", 14, -62)
    verdict:SetPoint("RIGHT", -16, 0)
    verdict:SetJustifyH("LEFT")
    verdict:SetWordWrap(false)

    local notes = view:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    notes:SetPoint("TOPLEFT", verdict, "BOTTOMLEFT", 0, -6)
    notes:SetPoint("RIGHT", -16, 0)
    notes:SetJustifyH("LEFT")
    notes:SetJustifyV("TOP")
    -- Up to three short sentences, which is more than one line holds.
    notes:SetWordWrap(true)
    notes:SetMaxLines(2)
    notes:SetTextColor(unpack(Theme.MUTED))

    local scrollBox = CreateFrame("Frame", nil, view, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -118)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, view, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local function Draw(keepPlace)
        local tree = ns.CraftTree.For(subject)
        local root = tree.root

        icon:SetTexture(C_Item.GetItemIconByID(subject))
        name:SetText(Theme.ItemName(ns.ItemLabel(subject), C_Item.GetItemQualityByID(subject)))

        -- After the price: how many the player has, and who can make it
        -- if that's anyone besides the character being played.
        local held = ns.Bank.Held(subject)
        local more = held > 0 and (" You have %d."):format(held) or ""
        if root.recipe and SayWho(root.recipe) then
            more = ("%s %s can make it."):format(more, Who(root.recipe))
        end
        if root.price then
            facts:SetText(
                ("%s each at auction, %s.%s"):format(
                    Theme.Coins(root.price),
                    Theme.Listed(root.listed),
                    more
                )
            )
        else
            facts:SetText("No auction price yet." .. more)
        end

        local first, second = Summary(tree)
        verdict:SetText(first)
        notes:SetText(second)

        scrollBox:SetDataProvider(
            CreateDataProvider(Rows(tree)),
            keepPlace and ScrollBoxConstants.RetainScrollPosition
                or ScrollBoxConstants.DiscardScrollPosition
        )
    end

    -- A row was clicked: that item becomes the subject, and the one it
    -- was reached from is remembered for Back.
    local function Pick(itemID)
        if itemID ~= subject then
            table.insert(trail, subject)
            subject = itemID
            Draw(false)
        end
    end

    back:SetScript("OnClick", function()
        if #trail > 0 then
            subject = table.remove(trail)
            Draw(false)
        else
            onBack()
        end
    end)

    local list = CreateScrollBoxListLinearView()
    list:SetElementExtent(ROW_HEIGHT)
    list:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row, Pick, onHistory)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, list)

    --- Shows the tree for an item, starting afresh: Back from here
    --- leaves the page. Only when it's asked for the item already on show
    --- does it keep the way the player came.
    ---@param itemID number
    function view:ShowItem(itemID)
        if itemID ~= subject or not self:IsShown() then
            subject = itemID
            table.wipe(trail)
        end
        Draw(false)
        self:Show()
    end

    --- Redraws the tree on show, for new prices or names that have arrived.
    function view:Refresh()
        if subject then
            Draw(true)
        end
    end

    return view
end
