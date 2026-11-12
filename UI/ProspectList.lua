local _, ns = ...

-- The Prospects tab: what the player could go and gather for gold at their
-- level, dearest first, with the zones to do it in.

local ProspectList = {}
ns.ProspectList = ProspectList

local Theme = ns.Theme

local ROW_HEIGHT = 44

-- Columns are placed from the right edge, in pixels.
local MAP_RIGHT = 10
local ZONES_RIGHT = 84
local ZONES_WIDTH = 210
local PRICE_RIGHT = 306
local NAME_RIGHT = 410

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

    row.How = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.How:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -4)
    row.How:SetPoint("RIGHT", row, "RIGHT", -NAME_RIGHT, 0)
    row.How:SetJustifyH("LEFT")
    row.How:SetWordWrap(false)
    row.How:SetTextColor(unpack(Theme.MUTED))

    row.Price = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PRICE_RIGHT, -8)
    row.Price:SetJustifyH("RIGHT")

    row.Listed = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Listed:SetPoint("TOPRIGHT", row.Price, "BOTTOMRIGHT", 0, -4)
    row.Listed:SetJustifyH("RIGHT")
    row.Listed:SetTextColor(unpack(Theme.MUTED))

    row.Zones = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Zones:SetPoint("RIGHT", row, "RIGHT", -ZONES_RIGHT, 0)
    row.Zones:SetWidth(ZONES_WIDTH)
    row.Zones:SetJustifyH("LEFT")
    row.Zones:SetMaxLines(2)

    row.Map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Map:SetSize(64, 22)
    row.Map:SetPoint("RIGHT", row, "RIGHT", -MAP_RIGHT, 0)
    row.Map:SetText("Map")
    row.Map:SetScript("OnClick", function(self)
        local data = self:GetParent():GetElementData()
        if data.mapIDs[1] then
            ns.MapMarks.ShowZone(data.mapIDs[1])
        end
    end)

    row:SetScript("OnClick", function(self)
        onSelect(self:GetElementData())
    end)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self:GetElementData().itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function FillRow(row, data)
    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.Icon:SetTexture(data.icon)
    row.Name:SetText(
        ("%s  |cffb9aa8c%s|r"):format(Theme.ItemName(data.name, data.quality), data.kind)
    )
    row.How:SetText(data.how)
    row.Price:SetText(Theme.Coins(data.price))
    row.Listed:SetText(Theme.Listed(data.listed))

    local zoneNames = {}
    for index, mapID in ipairs(data.mapIDs) do
        zoneNames[index] = ns.MapMarks.ZoneName(mapID)
    end
    row.Zones:SetText(table.concat(zoneNames, ", "))
    row.Map:SetShown(#data.mapIDs > 0)
end

-- Gathering the facts ----------------------------------------------------------------

-- Fills in what only the game can tell us: the item's name in the
-- player's language, its icon and quality, and how many they carry.
local function Complete(prospect)
    local itemID = prospect.itemID

    prospect.name = C_Item.GetItemNameByID(itemID) or prospect.name
    prospect.icon = C_Item.GetItemIconByID(itemID)
    prospect.quality = C_Item.GetItemQualityByID(itemID)
    prospect.count = ns.Bags.Counts()[itemID] or 0

    -- The item page expects a verdict to print under the chart. For a
    -- prospect, that's how you come by it.
    prospect.advice = { verb = ns.Advice.UNKNOWN, reason = prospect.how }
    return prospect
end

-- The list ---------------------------------------------------------------------------

--- Creates the prospects list. It starts hidden and fills its parent.
---@param parent table            frame to fill
---@param onSelect fun(row: table) called when the player clicks a row
---@return table list             with :Refresh()
function ProspectList.Create(parent, onSelect)
    local list = CreateFrame("Frame", nil, parent)
    list:SetAllPoints()
    list:Hide()

    local heading = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Prospects")

    local about = list:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))

    -- What the player has said they want to do. Nil is the plain ranked
    -- list of what's worth gathering. A zone is somewhere they've decided
    -- to go, and the tab shows a plan for the trip. RESALE is buying from
    -- vendors to sell at auction, which is laid out as a plan too.
    -- MATERIALS is every trade good on the market, by kind.
    -- CRAFTING is what's worth making from what the player holds.
    local RESALE = {}
    local MATERIALS = {}
    local CRAFTING = {}
    local destination

    -- The button that chooses between them, and the plan it can show.
    local course = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    course:SetSize(210, 20)
    course:SetPoint("TOPRIGHT", -24, -6)

    local plan = ns.TripPlan.Create(list)
    plan:SetPoint("TOPLEFT", 6, -32)
    plan:SetPoint("BOTTOMRIGHT", -6, 6)

    local function GoTo(zone)
        destination = zone
        -- The window redraws the tab and takes its footer from what the
        -- tab says about itself, so tell it, don't just redraw here.
        ns.Publish("COURSE_CHANGED")
    end

    -- The materials list can be narrowed: to one kind, which then gets
    -- the page to itself, and to what a character of this level could
    -- come by. The level limit starts on, because a list topped by things
    -- from zones the player can't survive in isn't much of a guide.
    local materialKind
    local materialsNearLevel = true

    local narrow = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    narrow:SetSize(150, 20)
    narrow:SetPoint("RIGHT", course, "LEFT", -6, 0)
    narrow:Hide()

    narrow:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            local function IsShowing(kindName)
                return materialKind == kindName
            end
            local function Show(kindName)
                materialKind = kindName
                ns.Publish("COURSE_CHANGED")
            end

            root:CreateTitle("Show...")
            root:CreateRadio("The best of every kind", IsShowing, Show, nil)
            for _, kind in ipairs(ns.Materials.Kinds()) do
                root:CreateRadio(
                    ("%s (%d)"):format(kind.name, kind.count),
                    IsShowing,
                    Show,
                    kind.name
                )
            end

            root:CreateDivider()
            root:CreateCheckbox("Only what's within reach of my level", function()
                return materialsNearLevel
            end, function()
                materialsNearLevel = not materialsNearLevel
                ns.Publish("COURSE_CHANGED")
            end)
        end)
    end)

    course:SetScript("OnClick", function(self)
        local level = UnitLevel("player")
        local zones = ns.Prospects.Zones(UnitFactionGroup("player"))
        local hereID = C_Map.GetBestMapForUnit("player")

        local function ZoneLabel(zone)
            return ("%s (%d to %d)"):format(
                ns.MapMarks.ZoneName(zone.mapID),
                zone.minLevel,
                zone.maxLevel
            )
        end

        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("I want to...")
            root:CreateButton("Make gold gathering", function()
                GoTo(nil)
            end)
            root:CreateButton("Turn what I have into more", function()
                GoTo(CRAFTING)
            end)
            root:CreateButton("See what every material is worth", function()
                GoTo(MATERIALS)
            end)
            root:CreateButton("Buy from vendors, sell at auction", function()
                GoTo(RESALE)
            end)

            for _, zone in ipairs(zones) do
                if zone.mapID == hereID then
                    root:CreateButton("Make the most of where I am", function()
                        GoTo(zone)
                    end)
                end
            end

            -- Zones a player of this level would actually go to, then
            -- everywhere else for those who know their own mind.
            local near = root:CreateButton("Go to a zone near my level")
            local anywhere = root:CreateButton("Go to any zone")
            -- Every zone there is makes a long list. Let it scroll.
            anywhere:SetScrollMode(400)
            for _, zone in ipairs(zones) do
                local suits = zone.minLevel <= level + 2 and zone.maxLevel >= level - 4
                if suits then
                    near:CreateButton(ZoneLabel(zone), function()
                        GoTo(zone)
                    end)
                end
                anywhere:CreateButton(ZoneLabel(zone), function()
                    GoTo(zone)
                end)
            end
        end)
    end)

    local empty = list:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("CENTER")
    empty:SetWidth(520)
    empty:SetTextColor(unpack(Theme.MUTED))

    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -32)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row, onSelect)
        end
        FillRow(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    --- Rebuilds the tab for what the player has chosen to do.
    ---@return string footer  a line about what's on show, for the window
    function list:Refresh()
        scrollBox:SetShown(destination == nil)
        scrollBar:SetShown(destination == nil)
        plan:SetShown(destination ~= nil)
        narrow:SetShown(destination == MATERIALS)

        if destination == CRAFTING then
            course:SetText("Making things to sell")
            about:SetText("What's worth making, against selling the ingredients as they are")
            empty:Hide()

            plan:SetPlan(ns.Conversions.Plan())
            return "After the auction house's cut on both sides. "
                .. "Each line assumes its ingredients go to that alone."
        elseif destination == MATERIALS then
            course:SetText("What materials are worth")
            empty:Hide()

            -- A kind picked before the last read of the auction house may
            -- have nothing listed any more.
            local stillThere = false
            for _, kind in ipairs(ns.Materials.Kinds()) do
                stillThere = stillThere or kind.name == materialKind
            end
            if not stillThere then
                materialKind = nil
            end

            narrow:SetText(materialKind or "Every kind")
            -- Kept short: it shares the line with two buttons.
            about:SetText(
                materialsNearLevel and "Within reach of your level, dearest first"
                    or "Dearest first"
            )

            local sections, loading = ns.Materials.Plan(materialKind, materialsNearLevel)
            if loading then
                -- The game is asked about each material in turn, and
                -- answers in its own time.
                loading.label = ("Looking up: %s"):format(loading.kind)
            end
            plan:SetPlan(sections, loading)

            return "From the last full read of the auction house. "
                .. "Click anything for its price history."
        elseif destination == RESALE then
            course:SetText("Buying to sell")
            about:SetText("Recipes a vendor sells for less than they fetch at auction")
            empty:Hide()

            plan:SetPlan(ns.Resale.Plan())
            return "Profit is after the auction house's cut. Prices move, "
                .. "and someone else may list first."
        elseif destination then
            local zoneName = ns.MapMarks.ZoneName(destination.mapID)
            course:SetText("Going to " .. zoneName)
            about:SetText("What to do before you leave, and while you're there")
            empty:Hide()

            plan:SetPlan(ns.Trip.Plan(destination))
            return "A plan, not a promise: what's found where is a guide, and prices move."
        end

        course:SetText("I want to...")
        about:SetText("What you could gather at your level, by what each sells for today")

        local marketKey = ns.Market.Current()

        local profile = {
            level = UnitLevel("player"),
            faction = UnitFactionGroup("player"),
            skills = {
                skinning = ns.Professions.Skill("skinning"),
                mining = ns.Professions.Skill("mining"),
                herbalism = ns.Professions.Skill("herbalism"),
            },
        }

        local prospects = ns.Prospects.For(profile, function(itemID)
            return ns.Ledger.Price(marketKey, itemID)
        end)

        for _, prospect in ipairs(prospects) do
            Complete(prospect)
            -- Follow these properly, so they have long history and price
            -- depth like anything the player carries.
            ns.Ledger.Track(marketKey, prospect.itemID)
        end

        if #prospects == 0 then
            if ns.Ledger.LastScan(marketKey) then
                empty:SetText("Nothing gatherable at your level is listed right now.")
            else
                empty:SetText("Prospects need prices. Visit an auction house first.")
            end
        end
        empty:SetShown(#prospects == 0)

        scrollBox:SetDataProvider(
            CreateDataProvider(prospects),
            ScrollBoxConstants.RetainScrollPosition
        )
        return "Ranked by what each one sells for, not by gold per hour. "
            .. "Level ranges are a guide."
    end

    return list
end
