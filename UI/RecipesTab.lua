local _, ns = ...

-- The Recipes tab: what vendors sell that the player hasn't learned, for
-- the professions they have, and where to buy it.

local RecipesTab = {}
ns.RecipesTab = RecipesTab

local Theme = ns.Theme

local ROW_HEIGHT = 44

-- Zones named per recipe before the rest are counted.
local ZONES_NAMED = 2

-- Columns are placed from the right edge, in pixels.
local MAP_RIGHT = 10
local WHERE_RIGHT = 84
local WHERE_WIDTH = 230

-- What a row says ---------------------------------------------------------------------

-- "Alchemy 60", and how the player stands against it.
local function SkillText(recipe)
    local text = ("%s %d"):format(recipe.profession, recipe.needed)
    if recipe.ready then
        return GREEN_FONT_COLOR:WrapTextInColorCode(text)
    end
    return ("%s (you're at %d)"):format(text, recipe.skill)
end

-- What else there is to know: what it costs in favor, what's stopping the
-- player buying it, and what it would sell for if they bought it to sell.
local function ExtrasText(recipe)
    local extras = {}
    if recipe.locked then
        table.insert(extras, recipe.locked)
    end
    if recipe.favor then
        table.insert(extras, ("%d Merchant's Favor"):format(recipe.favor))
    end

    if not recipe.bound then
        local price = ns.Ledger.Price(ns.Market.Current(), recipe.item)
        if price then
            table.insert(extras, ("%s at auction"):format(Theme.Coins(price)))
        end
    end
    return table.concat(extras, ", ")
end

-- "Here, in Westfall", or the first couple of zones it's sold in.
local function WhereText(recipe)
    if recipe.here then
        return ("Here, in %s"):format(recipe.here.zone), true
    end

    local zones, seen = {}, {}
    for _, vendor in ipairs(recipe.vendors) do
        if vendor.zone and not seen[vendor.zone] then
            seen[vendor.zone] = true
            table.insert(zones, vendor.zone)
        end
    end

    local text = table.concat(zones, ", ", 1, math.min(ZONES_NAMED, #zones))
    if #zones > ZONES_NAMED then
        text = ("%s and %d more"):format(text, #zones - ZONES_NAMED)
    end
    return text, false
end

local function ShowOnMap(recipe)
    local spot = ns.Recipes.VendorSpot(recipe)
    if spot then
        ns.MapMarks.ShowPoint(spot.mapID, spot.x, spot.y)
        return
    end

    local vendor = recipe.here or recipe.vendors[1]
    ns.Print(
        "It's sold in %s. Goldwise can put the vendor on your map when Questie is installed.",
        vendor.zone or "a zone it can't name"
    )
end

-- Rows --------------------------------------------------------------------------

local function CreateRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(32, 32)
    row.Icon:SetPoint("LEFT", 6, 0)

    row.Map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Map:SetSize(64, 22)
    row.Map:SetPoint("RIGHT", -MAP_RIGHT, 0)
    row.Map:SetText("Map")
    row.Map:SetScript("OnClick", function(self)
        ShowOnMap(self:GetParent():GetElementData())
    end)

    row.Where = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Where:SetPoint("RIGHT", -WHERE_RIGHT, 0)
    row.Where:SetWidth(WHERE_WIDTH)
    row.Where:SetJustifyH("RIGHT")
    row.Where:SetMaxLines(2)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -2)
    row.Name:SetPoint("RIGHT", row.Where, "LEFT", -10, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -4)
    row.Detail:SetPoint("RIGHT", row.Where, "LEFT", -10, 0)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)
    row.Detail:SetTextColor(unpack(Theme.MUTED))

    -- Clicking a recipe opens its price history: handy for the ones worth
    -- buying to sell on.
    row:SetScript("OnClick", function(self)
        ns.ShowItemHistory(self:GetElementData().item)
    end)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self:GetElementData().item)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

-- Returns false if the game hasn't yet told us the recipe's name.
local function FillRow(row, recipe)
    local name = C_Item.GetItemNameByID(recipe.item)

    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.Icon:SetTexture(C_Item.GetItemIconByID(recipe.item) or "Interface\\Icons\\INV_Scroll_03")
    row.Name:SetText(Theme.ItemName(name or "Recipe", C_Item.GetItemQualityByID(recipe.item)))

    local extras = ExtrasText(recipe)
    row.Detail:SetText(SkillText(recipe) .. (extras ~= "" and ("   " .. extras) or ""))

    local where, isHere = WhereText(recipe)
    row.Where:SetText(where)
    if isHere then
        row.Where:SetTextColor(unpack(Theme.COIN))
    else
        row.Where:SetTextColor(unpack(Theme.MUTED))
    end

    return name ~= nil
end

-- The tab ------------------------------------------------------------------------------

--- Creates the Recipes tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh()
function RecipesTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    local heading = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Recipes")

    local about = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))
    about:SetText("What vendors sell that you haven't learned, for the professions you have")

    local empty = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("CENTER")
    empty:SetWidth(520)
    empty:SetTextColor(unpack(Theme.MUTED))

    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -32)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    -- Recipe items the player has never seen aren't known to the client
    -- until it has fetched them, so a row may have to go without its name
    -- at first. Each is asked for once: if the client can't load an item,
    -- asking again on every redraw would never end.
    local requested = {}
    local awaitingNames = false

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, recipe)
        if not row.created then
            CreateRowWidgets(row)
        end
        if not FillRow(row, recipe) and not requested[recipe.item] then
            requested[recipe.item] = true
            awaitingNames = true
            C_Item.RequestLoadItemDataByID(recipe.item)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    --- Rebuilds the list for the player's professions, skill and zone.
    function tab:Refresh()
        local recipes = ns.Recipes.Unlearned()

        if #recipes == 0 then
            local hasProfession = false
            for profession in pairs(ns.RecipeData) do
                hasProfession = hasProfession or ns.Professions.SkillByName(profession) ~= nil
            end
            if hasProfession then
                empty:SetText("You've learned everything vendors sell for your professions.")
            else
                empty:SetText(
                    "Take up a crafting profession and the recipes its vendors sell "
                        .. "are listed here."
                )
            end
        end
        empty:SetShown(#recipes == 0)

        scrollBox:SetDataProvider(
            CreateDataProvider(recipes),
            ScrollBoxConstants.RetainScrollPosition
        )
    end

    -- Things that change the list while it's on screen: moving to another
    -- zone, and learning something.
    local function RefreshIfShown()
        if tab:IsVisible() then
            tab:Refresh()
        end
    end
    ns.OnEvent("ZONE_CHANGED_NEW_AREA", RefreshIfShown)
    ns.OnEvent("NEW_RECIPE_LEARNED", RefreshIfShown)

    -- Names arriving. The event fires for every item anything in the game
    -- loads, so only act when we're waiting, and gather a burst into one
    -- redraw.
    local redrawQueued = false
    ns.OnEvent("GET_ITEM_INFO_RECEIVED", function()
        if not awaitingNames or redrawQueued or not tab:IsVisible() then
            return
        end
        redrawQueued = true
        C_Timer.After(0.5, function()
            redrawQueued = false
            awaitingNames = false
            RefreshIfShown()
        end)
    end)

    return tab
end
