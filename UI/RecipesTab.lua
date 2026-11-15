local _, ns = ...

-- The Recipes tab, in two columns.
--
--   * On the left, recipes to get: what vendors sell that the player
--     hasn't learned, for the professions they have. The ones they can
--     use now come first, closest to their skill first, since those are
--     the ones that still teach them something. Then what's coming up,
--     nearest first, and last what a reputation is holding back.
--
--   * On the right, potential sales: vendor recipes that have fetched a
--     good deal more at auction than the vendor asks, whoever can use
--     them. The same list as Prospects' "Buy from vendors, sell at
--     auction": what's sold where the player is standing first, then the
--     rest, each by most profit. A button swaps it for the player's own
--     resales: what each recipe they bought to sell really cost, what it
--     really sold for, and the profit (Profile\Resales.lua).
--
-- Each row has a pin that puts its vendor on the map.

local RecipesTab = {}
ns.RecipesTab = RecipesTab

local Theme = ns.Theme

-- Three lines beside the icon: the name, the detail and where it's sold.
local ROW_HEIGHT = 48

-- What a reputation holding a recipe back is written in.
local LOCKED_COLOR = { 1, 0.5, 0.25 }
local PIN_SIZE = 22

-- Room between the two columns, and under the headings.
local GUTTER = 16
local LIST_TOP = 52

-- What a row says ---------------------------------------------------------------

-- "Here, in Westfall", or the first couple of zones it's sold in.
local function WhereText(entry)
    if entry.here then
        return ("Here, in %s"):format(entry.here.zone), true
    end
    return ns.Recipes.ZonesText(entry.vendors), false
end

-- For a recipe to get: "Alchemy 60", and how the player stands against it,
-- then what else stands in the way.
local function LearnDetail(recipe)
    local parts = {}
    local skill = ("%s %d"):format(recipe.profession, recipe.needed)
    if recipe.ready then
        skill = GREEN_FONT_COLOR:WrapTextInColorCode(skill)
    else
        skill = ("%s (at %d)"):format(skill, recipe.skill)
    end
    table.insert(parts, skill)
    if recipe.favor then
        table.insert(parts, ("%d Merchant's Favor"):format(recipe.favor))
    end
    -- A reputation holding it back goes on the line below, in place of
    -- where it's sold: it's the longer, and the more important.
    return table.concat(parts, ", ")
end

-- For a potential sale: what it should leave once sold, and what the
-- vendor asks, which is a guess until their wares have been seen.
local function SaleDetail(deal)
    return ("+%s at auction, costs %s%s"):format(
        Theme.Coins(deal.profit),
        deal.costIsSeen and "" or "about ",
        Theme.Coins(deal.cost)
    )
end

-- For one of the player's own resales: what it cost and, once sold, what
-- it fetched and what was left over.
local function LotDetail(lot)
    local paid = ("Paid %s"):format(Theme.Coins(lot.paid or 0))
    if lot.state == ns.Resales.SOLD then
        local profit, color = Theme.SignedCoins(lot.profit or 0)
        local text = ("%s, sold for %s: "):format(paid, Theme.Coins(lot.received or 0))
        return text .. CreateColor(unpack(color)):WrapTextInColorCode(profit)
    end
    local lost = ""
    if (lot.lost or 0) > 0 then
        lost = (", %s in lost deposits"):format(Theme.Coins(lot.lost))
    end
    if lot.state == ns.Resales.LISTED then
        return paid .. ", up for auction" .. lost
    end
    return paid .. ", not listed yet" .. lost
end

-- When it was bought, listed or sold, and by whom if not this character.
local function LotWhen(lot)
    local now = GetServerTime()
    local text
    if lot.state == ns.Resales.SOLD then
        text = "Sold " .. ns.Ago(now - (lot.soldAt or now))
    elseif lot.state == ns.Resales.LISTED then
        text = "Listed " .. ns.Ago(now - (lot.listedAt or now))
    else
        text = "Bought " .. ns.Ago(now - (lot.boughtAt or now))
    end
    if lot.who and lot.who ~= ns.Characters.CurrentKey() then
        text = ("%s, by %s"):format(text, lot.who:match("^[^-]+") or lot.who)
    end
    return text
end

local function ShowOnMap(entry)
    local spot = ns.Recipes.VendorSpot(entry)
    if spot then
        ns.MapMarks.ShowPoint(spot.mapID, spot.x, spot.y)
        return
    end

    local vendor = entry.here or entry.vendors[1]
    ns.Print(
        "It's sold in %s. Goldwise can put the vendor on your map when Questie is installed.",
        vendor and vendor.zone or "a zone it can't name"
    )
end

-- The order of recipes to get: usable now and closest to the player's
-- skill first, then coming up and nearest first, then held back by a
-- reputation. Ties go to the one sold where the player is standing.
local function ByCloseness(a, b)
    local function Group(recipe)
        if recipe.locked then
            return 3
        end
        return recipe.ready and 1 or 2
    end
    local groupA, groupB = Group(a), Group(b)
    if groupA ~= groupB then
        return groupA < groupB
    end

    local gapA, gapB = math.abs(a.skill - a.needed), math.abs(b.skill - b.needed)
    if gapA ~= gapB then
        return gapA < gapB
    end
    if (a.here ~= nil) ~= (b.here ~= nil) then
        return a.here ~= nil
    end
    return a.item < b.item
end

-- The order of potential sales: sold where the player is standing first,
-- then the rest, each most profitable first.
local function ByNearAndProfit(a, b)
    if (a.here ~= nil) ~= (b.here ~= nil) then
        return a.here ~= nil
    end
    if a.profit ~= b.profit then
        return a.profit > b.profit
    end
    return a.item < b.item
end

-- Rows ------------------------------------------------------------------------

local function CreateRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(32, 32)
    row.Icon:SetPoint("LEFT", 6, 0)

    -- The vendor on the map, as on the town card.
    row.Pin = CreateFrame("Button", nil, row)
    row.Pin:SetSize(PIN_SIZE, PIN_SIZE)
    row.Pin:SetPoint("RIGHT", -6, 0)
    row.Pin.Icon = row.Pin:CreateTexture(nil, "ARTWORK")
    row.Pin.Icon:SetAtlas("Waypoint-MapPin-Untracked")
    row.Pin.Icon:SetAllPoints()
    row.Pin.Icon:SetAlpha(0.8)
    row.Pin:SetScript("OnClick", function(self)
        ShowOnMap(self:GetParent():GetElementData())
    end)
    row.Pin:SetScript("OnEnter", function(self)
        self.Icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show the vendor on the map")
        GameTooltip:Show()
    end)
    row.Pin:SetScript("OnLeave", function(self)
        self.Icon:SetAlpha(0.8)
        GameTooltip_Hide()
    end)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -1)
    row.Name:SetPoint("RIGHT", row.Pin, "LEFT", -6, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -3)
    row.Detail:SetPoint("RIGHT", row.Pin, "LEFT", -6, 0)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)

    row.Where = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Where:SetPoint("TOPLEFT", row.Detail, "BOTTOMLEFT", 0, -2)
    row.Where:SetPoint("RIGHT", row.Pin, "LEFT", -6, 0)
    row.Where:SetJustifyH("LEFT")
    row.Where:SetWordWrap(false)

    -- Clicking a recipe opens its price history. Right-clicking gives the
    -- menu every item has.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
        local item = self:GetElementData().item
        if mouseButton == "RightButton" then
            ns.ItemMenu.Open(self, item)
        else
            ns.ShowItemHistory(item)
        end
    end)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self:GetElementData().item)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

-- Fills a row from a recipe to get or a potential sale; detailFor says
-- which.
local function FillRow(row, entry, detailFor)
    -- Recipe items the player has never seen aren't known to the client
    -- until it has fetched them. Recipes.Name asks, and the window redraws
    -- this tab when the answer arrives.
    local name = ns.Recipes.Name(entry.item, entry.spell)

    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.Icon:SetTexture(C_Item.GetItemIconByID(entry.item) or "Interface\\Icons\\INV_Scroll_03")
    row.Name:SetText(Theme.ItemName(name, C_Item.GetItemQualityByID(entry.item)))

    -- One of the player's own resales: no vendor to show, and its story
    -- in place of where it's sold.
    if entry.state then
        row.Pin:Hide()
        row.Detail:SetText(LotDetail(entry))
        row.Where:SetText(LotWhen(entry))
        row.Where:SetTextColor(unpack(Theme.MUTED))
        return
    end

    row.Pin:Show()
    row.Detail:SetText(detailFor(entry))

    if entry.locked then
        row.Where:SetText(entry.locked)
        row.Where:SetTextColor(unpack(LOCKED_COLOR))
    else
        local where, isHere = WhereText(entry)
        row.Where:SetText(where)
        row.Where:SetTextColor(unpack(isHere and Theme.COIN or Theme.MUTED))
    end
end

-- One column: a heading, a line under it, and a scrolling list.
local function CreateColumn(tab, title, about, detailFor)
    local column = CreateFrame("Frame", nil, tab)

    column.Heading = column:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    column.Heading:SetPoint("TOPLEFT", 6, -10)
    column.Heading:SetText(title)

    column.About = column:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    column.About:SetPoint("TOPLEFT", column.Heading, "BOTTOMLEFT", 0, -4)
    column.About:SetPoint("RIGHT", -6, 0)
    column.About:SetJustifyH("LEFT")
    column.About:SetWordWrap(false)
    column.About:SetTextColor(unpack(Theme.MUTED))
    column.About:SetText(about)

    column.Empty = column:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    column.Empty:SetPoint("TOPLEFT", 12, -LIST_TOP - 20)
    column.Empty:SetPoint("RIGHT", -12, 0)
    column.Empty:SetJustifyH("LEFT")
    column.Empty:SetTextColor(unpack(Theme.MUTED))

    local scrollBox = CreateFrame("Frame", nil, column, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, -LIST_TOP)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 6)

    local scrollBar = CreateFrame("EventFrame", nil, column, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, entry)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, entry, detailFor)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    function column:Fill(entries, emptyText)
        self.Empty:SetText(emptyText or "")
        self.Empty:SetShown(#entries == 0)
        scrollBox:SetDataProvider(
            CreateDataProvider(entries),
            ScrollBoxConstants.RetainScrollPosition
        )
    end

    return column
end

-- The tab ---------------------------------------------------------------------

--- Creates the Recipes tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh()
function RecipesTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    local toGet = CreateColumn(
        tab,
        "Recipes to get",
        "For your professions, closest to your skill first",
        LearnDetail
    )
    toGet:SetPoint("TOPLEFT", 6, 0)
    toGet:SetPoint("BOTTOMRIGHT", tab, "BOTTOM", -GUTTER / 2, 0)

    local toSell = CreateColumn(
        tab,
        "Potential sales",
        "Sold near you first, then by most profit at auction",
        SaleDetail
    )
    toSell:SetPoint("TOPLEFT", tab, "TOP", GUTTER / 2, 0)
    toSell:SetPoint("BOTTOMRIGHT", -6, 0)

    -- The right column shows either what could be resold or what the
    -- player has resold. This swaps between them.
    local showingYours = false
    local swap = CreateFrame("Button", nil, toSell, "UIPanelButtonTemplate")
    swap:SetSize(120, 20)
    swap:SetPoint("TOPRIGHT", -4, -6)
    swap:SetScript("OnClick", function()
        showingYours = not showingYours
        tab:Refresh()
    end)

    -- A faint line between the two.
    local rule = tab:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.08)
    rule:SetWidth(1)
    rule:SetPoint("TOP", 0, -10)
    rule:SetPoint("BOTTOM", 0, 6)

    --- Rebuilds both lists for the player's professions, skill and zone.
    function tab:Refresh()
        local recipes = ns.Recipes.Unlearned()
        table.sort(recipes, ByCloseness)

        local emptyLeft
        if #recipes == 0 then
            local hasProfession = false
            for profession in pairs(ns.RecipeData) do
                hasProfession = hasProfession or ns.Professions.SkillByName(profession) ~= nil
            end
            emptyLeft = hasProfession
                    and "You've learned everything vendors sell for your professions."
                or "Take up a crafting profession and the recipes its vendors sell are listed here."
        end
        toGet:Fill(recipes, emptyLeft)

        swap:SetText(showingYours and "Potential sales" or "Your resales")
        if showingYours then
            local lots, totals = ns.Resales.All()
            toSell.Heading:SetText("Your resales")
            -- A loss is shown as one, in red.
            local profit, color = Theme.SignedCoins(totals.profit)
            local about = ("%d sold, %s profit"):format(
                totals.sold,
                CreateColor(unpack(color)):WrapTextInColorCode(profit)
            )
            if totals.held > 0 then
                about = ("%s; %d still to sell"):format(about, totals.held)
            end
            toSell.About:SetText(about)
            toSell:Fill(
                lots,
                "Buy a recipe from a vendor to sell at auction, and how it goes is kept here: "
                    .. "what you paid, what it sold for, and the profit."
            )
            return
        end
        toSell.Heading:SetText("Potential sales")
        toSell.About:SetText("Sold near you first, then by most profit at auction")

        local deals, unpriced = ns.Recipes.Resale(ns.Market.Home())
        table.sort(deals, ByNearAndProfit)
        local emptyRight
        if #deals == 0 and not ns.Ledger.LastScan(ns.Market.Home()) then
            emptyRight = "This needs auction prices. Visit an auction house first."
        elseif #deals == 0 then
            emptyRight = unpriced > 0
                    and "Still finding out what vendors ask for some recipes. A moment..."
                or "No vendor recipe has fetched enough more at auction lately. "
                    .. "How much counts is in Goldwise's options."
        end
        toSell:Fill(deals, emptyRight)
    end

    -- Things that change the lists while they're on screen: moving to
    -- another zone, and learning something.
    local function RefreshIfShown()
        if tab:IsVisible() then
            tab:Refresh()
        end
    end
    ns.OnEvent("ZONE_CHANGED_NEW_AREA", RefreshIfShown)
    ns.OnEvent("NEW_RECIPE_LEARNED", RefreshIfShown)
    ns.Subscribe("RESALES_CHANGED", RefreshIfShown)

    return tab
end
