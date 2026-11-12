local _, ns = ...

-- The Purse tab: what the player has, what comes in and goes out, what's
-- going to cost them soon, and whether they can cover it.

local PurseTab = {}
ns.PurseTab = PurseTab

local Theme = ns.Theme

-- Days of income and spending the averages are taken over.
local AVERAGE_DAYS = 7

-- Upcoming training levels listed before we stop.
local LEVELS_SHOWN = 3

local ROW_COUNT = 7
local ROW_HEIGHT = 30

-- Building blocks ---------------------------------------------------------------

-- One of the three boxes across the top: a label, a figure, a footnote.
local function CreateTile(parent, label)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(240, 66)

    local background = tile:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.35)

    local caption = tile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    caption:SetPoint("TOPLEFT", 10, -8)
    caption:SetText(label:upper())

    tile.Figure = tile:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    tile.Figure:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -5)

    tile.Note = tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tile.Note:SetPoint("TOPLEFT", tile.Figure, "BOTTOMLEFT", 0, -4)
    tile.Note:SetPoint("RIGHT", -8, 0)
    tile.Note:SetJustifyH("LEFT")
    tile.Note:SetWordWrap(false)
    tile.Note:SetTextColor(unpack(Theme.MUTED))

    return tile
end

-- One line of the "Coming up" list: when, what, how much.
local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 12, -150 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", -12, 0)

    row.When = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.When:SetPoint("LEFT", 4, 0)
    row.When:SetWidth(120)
    row.When:SetJustifyH("LEFT")

    -- A button at the far end, for the lines that can point at a map. The
    -- amounts keep clear of it on every line, so they stay in a column.
    row.Where = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Where:SetSize(64, 22)
    row.Where:SetPoint("RIGHT", -4, 0)
    row.Where:SetText("Where")
    row.Where:Hide()
    row.Where:SetScript("OnClick", function(self)
        local line = self:GetParent()
        if line.pickPlace then
            line.pickPlace(line, self)
        end
    end)

    row.Amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Amount:SetPoint("RIGHT", row.Where, "LEFT", -10, 0)
    row.Amount:SetJustifyH("RIGHT")

    row.What = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.What:SetPoint("LEFT", row.When, "RIGHT", 8, 0)
    row.What:SetPoint("RIGHT", row.Amount, "LEFT", -12, 0)
    row.What:SetJustifyH("LEFT")
    row.What:SetWordWrap(false)

    local rule = row:CreateTexture(nil, "BACKGROUND")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetColorTexture(1, 1, 1, 0.08)

    -- Some lines have more to say when pointed at. Those light up, so the
    -- player can tell which.
    row.Glow = row:CreateTexture(nil, "BACKGROUND")
    row.Glow:SetAllPoints()
    row.Glow:SetColorTexture(1, 1, 1, 0.05)
    row.Glow:Hide()

    row:SetScript("OnEnter", function(self)
        if self.showMore then
            self.Glow:Show()
            self.showMore(self)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.Glow:Hide()
        GameTooltip:Hide()
    end)

    return row
end

-- Where to train -----------------------------------------------------------------------

local function Percent(fraction)
    return math.floor(fraction * 100 + 0.5)
end

-- "Stormwind", or "Ironforge (Gnomeregan Exiles)" where the trainers are
-- guests in someone else's city.
local function PlaceName(place)
    return place.faction and ("%s (%s)"):format(place.city, place.faction) or place.city
end

local function PriceAt(place, fullPrice)
    return math.floor(fullPrice * (1 - place.discount) + 0.5)
end

local function ShowOnMap(place)
    if place.spot then
        ns.MapMarks.ShowPoint(place.mapID, place.spot.x, place.spot.y)
    else
        ns.MapMarks.ShowZone(place.mapID)
        ns.Print(
            "That's %s, not the trainer's door. Goldwise marks the trainer "
                .. "once you've visited one there, or straight away with Questie installed.",
            place.city
        )
    end
end

-- The menu behind a training line's Where button: each city's trainers and
-- what they'd charge. Picking one opens the map there.
local function PickTrainingPlace(row, button)
    local places = ns.Training.Places()

    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle("Where to train")

        for _, place in ipairs(places) do
            local label = ("%s: %s"):format(PlaceName(place), ns.Money(PriceAt(place, row.amount)))
            if place.discount > 0 then
                label = label .. (", %d%% off"):format(Percent(place.discount))
            end

            local choice = root:CreateButton(label, function()
                ShowOnMap(place)
            end)
            -- Somewhere we can't put on a map is still worth listing for
            -- its price.
            choice:SetEnabled(place.mapID ~= nil)
        end
    end)
end

-- The hover card for a line of training: what the same skills cost from
-- each city's trainers, given what the player's reputation there earns.
local function ShowTrainingPlaces(row)
    local places = ns.Training.Places()
    if #places == 0 then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:AddLine("Where to train", unpack(Theme.COIN))

    for _, place in ipairs(places) do
        local standing = place.standing
        if place.shortBy then
            standing = ("%s, %s short of %s"):format(
                standing,
                FormatLargeNumber(place.shortBy),
                place.discountStanding
            )
        end

        local red, green, blue = 1, 1, 1
        if place.discount > 0 then
            red, green, blue = GREEN_FONT_COLOR:GetRGB()
        end

        GameTooltip:AddDoubleLine(
            ("%s: %s"):format(PlaceName(place), standing),
            ns.Money(PriceAt(place, row.amount)),
            1,
            1,
            1,
            red,
            green,
            blue
        )
    end

    local muted = Theme.MUTED
    GameTooltip:AddLine(
        ("%s or better with a trainer's people takes %d%% off."):format(
            places[1].discountStanding,
            Percent(ns.Training.REPUTATION_DISCOUNT)
        ),
        muted[1],
        muted[2],
        muted[3],
        true
    )
    GameTooltip:AddLine("Press Where to find them on the map.", muted[1], muted[2], muted[3])
    GameTooltip:Show()
end

-- What's coming up -------------------------------------------------------------------

-- Each entry is { when, what, amount, showMore, pickPlace }. amount is in
-- copper, or nil if unknown. showMore puts up a tooltip for the line, and
-- pickPlace answers its Where button; both only where there's something
-- worth having.
local function UpcomingCosts(level)
    local costs = {}

    local durability = ns.Purse.Durability()
    if durability then
        local repair, exact = ns.Purse.RepairCost()
        local what = ("Your gear is at %d%%."):format(durability)
        if not repair then
            what = what .. " Visit any repairer once and Goldwise will learn the cost."
        elseif not exact then
            what = what .. " An estimate, from your last repair bill."
        end
        table.insert(costs, { when = "Repairs", what = what, amount = repair })
    end

    local training = ns.Training.Outstanding(level)
    if not ns.Training.HasPrices() then
        table.insert(costs, {
            when = "Training",
            what = "Open your class trainer once and Goldwise will learn the prices.",
        })
    end

    -- Amounts are the full price. If the player's reputation somewhere
    -- earns a discount, say where; pointing at the line lists every city.
    local places = ns.Training.Places()
    local cheapest = places[1]
    local discountNote = ""
    if cheapest and cheapest.discount > 0 then
        discountNote = (" %d%% off in %s."):format(Percent(cheapest.discount), cheapest.city)
    end
    local showMore = #places > 0 and ShowTrainingPlaces or nil
    local pickPlace = #places > 0 and PickTrainingPlace or nil

    for index, entry in ipairs(training) do
        if index > LEVELS_SHOWN then
            break
        end

        local skills = entry.skills == 1 and "1 skill" or (entry.skills .. " skills")
        if entry.level <= level then
            table.insert(costs, {
                when = "Training now",
                what = skills .. " waiting at your trainer." .. discountNote,
                amount = entry.cost,
                showMore = showMore,
                pickPlace = pickPlace,
            })
        else
            local away = entry.level - level
            table.insert(costs, {
                when = "Level " .. entry.level,
                what = ("%s to train, %d %s away."):format(
                    skills,
                    away,
                    away == 1 and "level" or "levels"
                ),
                amount = entry.cost,
                showMore = showMore,
                pickPlace = pickPlace,
            })
        end
    end

    local goal = ns.settings.goalCopper
    if goal and goal > 0 then
        table.insert(
            costs,
            { when = "Your goal", what = "What you're saving toward.", amount = goal }
        )
    end

    return costs
end

-- The sentence at the bottom: can they cover what's next?
local function Verdict(money, income, spending, costs)
    -- "Next" is the repairs, if we can put a price on them, plus the first
    -- thing with a price that isn't the long-term goal.
    local due, name, repairs = 0, nil, false
    for _, cost in ipairs(costs) do
        if cost.amount and cost.when ~= "Your goal" then
            due = due + cost.amount
            if cost.when == "Repairs" then
                repairs = cost.amount > 0
            else
                name = cost.when
                break
            end
        end
    end

    local loud = ns.settings.auditorMode
    local net = income - spending
    local lines = {}

    if name then
        local label = name == "Training now" and "the training waiting for you"
            or (name:lower() .. " training")
        -- Only speak for the repairs when their cost is in the sum.
        if repairs then
            label = "repairs and " .. label
        end

        if money >= due then
            table.insert(
                lines,
                ("You can cover %s, with about %s to spare."):format(
                    label,
                    Theme.Coins(money - due)
                )
            )
        elseif net > 0 then
            local short = "You're about %s short for %s. "
                .. "At your recent pace that's about %d days of play."
            table.insert(
                lines,
                short:format(Theme.Coins(due - money), label, math.ceil((due - money) / net))
            )
        else
            table.insert(
                lines,
                ("You're about %s short for %s."):format(Theme.Coins(due - money), label)
            )
        end
    end

    if spending > income and spending > 0 then
        table.insert(
            lines,
            loud and "You are spending MORE than you make. That is not a budget."
                or "Lately you've been spending more than you make."
        )
    end

    local goal = ns.settings.goalCopper
    if goal and goal > 0 then
        if money >= goal then
            table.insert(lines, "You've reached your goal.")
        elseif net > 0 then
            table.insert(
                lines,
                ("Your goal is about %d days of play away."):format(math.ceil((goal - money) / net))
            )
        end
    else
        table.insert(lines, "Saving for something? Type /gw goal 50 to track a 50 gold target.")
    end

    return table.concat(lines, "\n")
end

-- The tab ------------------------------------------------------------------------------

--- Creates the Purse tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh()
function PurseTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    local heading = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Purse")

    local about = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))
    about:SetText("What's coming, and whether you can afford it")

    local have = CreateTile(tab, "In your purse")
    have:SetPoint("TOPLEFT", 12, -34)
    local comingIn = CreateTile(tab, "Coming in")
    comingIn:SetPoint("LEFT", have, "RIGHT", 13, 0)
    local goingOut = CreateTile(tab, "Going out")
    goingOut:SetPoint("LEFT", comingIn, "RIGHT", 13, 0)

    local upcoming = tab:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    upcoming:SetPoint("TOPLEFT", 14, -128)
    upcoming:SetText("COMING UP")

    local rows = {}
    for index = 1, ROW_COUNT do
        rows[index] = CreateRow(tab, index)
    end

    local verdict = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    verdict:SetPoint("BOTTOMLEFT", 14, 12)
    verdict:SetPoint("RIGHT", -14, 0)
    verdict:SetJustifyH("LEFT")
    verdict:SetJustifyV("BOTTOM")
    verdict:SetSpacing(4)

    --- Brings every figure on the tab up to date.
    function tab:Refresh()
        local money = GetMoney()
        local level = UnitLevel("player")
        local income, spending, activeDays, biggest = ns.Purse.Averages(AVERAGE_DAYS)

        have.Figure:SetText(Theme.Coins(money))
        local everyone = ns.Characters.TotalMoney()
        if everyone > money then
            have.Note:SetText(Theme.Coins(everyone) .. " across your characters")
        else
            have.Note:SetText("on this character")
        end

        if activeDays == 0 then
            comingIn.Figure:SetText("-")
            comingIn.Note:SetText("Nothing recorded yet")
            goingOut.Figure:SetText("-")
            goingOut.Note:SetText("Nothing recorded yet")
        else
            local span = activeDays == 1 and "from one day of play so far"
                or ("over your last %d days played"):format(activeDays)
            comingIn.Figure:SetText(Theme.Coins(income) .. " a day")
            comingIn.Note:SetText(span)
            goingOut.Figure:SetText(Theme.Coins(spending) .. " a day")
            goingOut.Note:SetText(
                biggest and ("mostly " .. ns.Purse.SPENDING_LABELS[biggest]) or span
            )
        end

        local costs = UpcomingCosts(level)
        for index, row in ipairs(rows) do
            local cost = costs[index]
            row:SetShown(cost ~= nil)
            if cost then
                row.When:SetText(cost.when)
                row.What:SetText(cost.what)
                row.Amount:SetText(cost.amount and Theme.Coins(cost.amount) or "")

                row.amount = cost.amount
                row.showMore = cost.showMore
                row:EnableMouse(cost.showMore ~= nil)

                row.pickPlace = cost.pickPlace
                row.Where:SetShown(cost.pickPlace ~= nil)
            end
        end

        verdict:SetText(Verdict(money, income, spending, costs))
    end

    return tab
end
