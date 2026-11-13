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

-- The cash flow chart: how far down the tab it sits, and its height.
local CHART_TOP = 124
local CHART_HEIGHT = 90

-- What the chart can cover, in the order the menu lists them: how long a
-- stretch each bar stands for, and how many of them. A month is as far
-- back as the purse remembers, and about thirty bars is as many as stay
-- readable, so the shorter the stretch, the shorter the time on show.
local SPANS = {
    { label = "30 days, a day at a time", heading = "LAST 30 DAYS", hours = 24, count = 30 },
    { label = "2 weeks, 12 hours at a time", heading = "LAST 2 WEEKS", hours = 12, count = 28 },
    { label = "A week, 6 hours at a time", heading = "LAST WEEK", hours = 6, count = 28 },
    { label = "A day, an hour at a time", heading = "LAST 24 HOURS", hours = 1, count = 24 },
}

-- How far down the tab the "Coming up" list starts.
local ROWS_TOP = CHART_TOP + CHART_HEIGHT + 32

-- Building blocks ---------------------------------------------------------------

-- One line of the "Coming up" list: when, what, how much.
local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 12, -(ROWS_TOP + (index - 1) * ROW_HEIGHT))
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
        local what = ("Your gear is at %d%%."):format(math.floor(durability))
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

    local have = Theme.CreateTile(tab, "In your purse")
    have:SetPoint("TOPLEFT", 12, -34)
    local comingIn = Theme.CreateTile(tab, "Coming in")
    comingIn:SetPoint("LEFT", have, "RIGHT", 13, 0)
    local goingOut = Theme.CreateTile(tab, "Going out")
    goingOut:SetPoint("LEFT", comingIn, "RIGHT", 13, 0)

    local flowHeading = tab:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    flowHeading:SetPoint("TOPLEFT", 14, -(CHART_TOP - 14))

    -- Two charts in the one place: bars of what came in and went out, or
    -- a line of what was held. Only one shows at a time.
    local flow = ns.Chart.CreateCashFlow(tab, 746, CHART_HEIGHT)
    flow:SetPoint("TOPLEFT", 12, -CHART_TOP)

    local held = ns.Chart.CreateLines(tab, 746, CHART_HEIGHT)
    held:SetPoint("TOPLEFT", 12, -CHART_TOP)

    -- What the chart shows and over how long, chosen from one menu and
    -- remembered.
    local pick = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    pick:SetSize(210, 20)
    pick:SetPoint("TOPRIGHT", -24, -6)

    -- Whose money the whole tab is about, beside it.
    local whose = Theme.CreateMoneyScopeButton(tab)
    whose:SetPoint("RIGHT", pick, "LEFT", -6, 0)
    pick:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Show...")
            root:CreateRadio("Coming in and going out", function()
                return not ns.settings.purseCoin
            end, function()
                ns.settings.purseCoin = false
                tab:Refresh()
            end)
            root:CreateRadio("Coin held, as a line", function()
                return ns.settings.purseCoin
            end, function()
                ns.settings.purseCoin = true
                tab:Refresh()
            end)

            root:CreateDivider()
            root:CreateTitle("Over...")
            for index, span in ipairs(SPANS) do
                root:CreateRadio(span.label, function()
                    return ns.settings.purseSpan == index
                end, function()
                    ns.settings.purseSpan = index
                    tab:Refresh()
                end)
            end
        end)
    end)

    -- Draws whichever chart is chosen, over the stretch that's chosen.
    local function DrawChart()
        local span = SPANS[ns.settings.purseSpan] or SPANS[1]
        local byHour = span.hours < 24
        local function Label(stretch)
            return ns.Chart.Label(ns.Purse.StartOf(stretch, span.hours), byHour)
        end

        pick:SetText(span.label)
        flow:SetShown(not ns.settings.purseCoin)
        held:SetShown(ns.settings.purseCoin)

        local accountWide = ns.settings.moneyAccountWide
        local owner = Theme.MoneyOwner():upper()

        if ns.settings.purseCoin then
            local coin, first, last = ns.Purse.Coin(span.hours, span.count, accountWide)
            first = first or last

            flowHeading:SetText(
                (accountWide and "COIN ACROSS %s, %s" or "COIN ON %s, %s"):format(
                    owner,
                    span.heading
                )
            )
            held:SetSeries(
                -- One line, named in the heading, needs no key.
                { { label = "", color = Theme.COIN, values = coin } },
                first,
                last,
                #coin == 1 and "One figure on record so far. The line starts as you play on."
                    or "Nothing on record yet. Goldwise notes what you hold as you play.",
                { fitted = true, firstLabel = Label(first), lastLabel = Label(last) }
            )
        else
            local bars, first, last = ns.Purse.Flow(span.hours, span.count, accountWide)

            flowHeading:SetText(("CASH FLOW FOR %s, %s"):format(owner, span.heading))
            flow:SetBars(bars, first, last, Label(first), Label(last))
        end
    end

    local upcoming = tab:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    upcoming:SetPoint("TOPLEFT", 14, -(ROWS_TOP - 22))
    upcoming:SetText("COMING UP")

    local rows = {}
    for index = 1, ROW_COUNT do
        rows[index] = CreateRow(tab, index)
    end

    -- The verdict sits under the last line of the list, and is placed
    -- there on each refresh. It used to be pinned to the bottom of the tab
    -- and justified upward, which the game's coin icons don't follow: the
    -- words moved and the coins stayed behind, a line too high.
    local verdict = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    verdict:SetPoint("RIGHT", -14, 0)
    verdict:SetJustifyH("LEFT")
    verdict:SetSpacing(4)

    --- Brings every figure on the tab up to date.
    function tab:Refresh()
        whose:Update()
        local accountWide = ns.settings.moneyAccountWide
        local level = UnitLevel("player")
        local income, spending, activeDays, biggest = ns.Purse.Averages(AVERAGE_DAYS, accountWide)

        -- The other figure goes underneath, so whichever is chosen, both
        -- can be seen.
        local own, everyone = GetMoney(), ns.Characters.TotalMoney()
        local money = accountWide and everyone or own
        have.Figure:SetText(Theme.Coins(money))
        if accountWide then
            have.Note:SetText(
                ("across your characters, %s on %s"):format(
                    ns.Money(own),
                    UnitName("player") or "this one"
                )
            )
        elseif everyone > own then
            have.Note:SetText(
                ("on %s, %s across your characters"):format(
                    UnitName("player") or "this character",
                    ns.Money(everyone)
                )
            )
        else
            have.Note:SetText(("on %s"):format(UnitName("player") or "this character"))
        end

        if activeDays == 0 then
            comingIn.Figure:SetText("-")
            comingIn.Note:SetText(
                accountWide and "Nothing recorded yet" or "Nothing for this character yet"
            )
            goingOut.Figure:SetText("-")
            goingOut.Note:SetText(
                accountWide and "Nothing recorded yet" or "Nothing for this character yet"
            )
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

        DrawChart()

        local costs = UpcomingCosts(level)
        local shown = 0
        for index, row in ipairs(rows) do
            local cost = costs[index]
            row:SetShown(cost ~= nil)
            if cost then
                shown = shown + 1
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

        verdict:SetPoint("TOPLEFT", 14, -(ROWS_TOP + shown * ROW_HEIGHT + 16))
        -- The costs are this character's own, so the verdict is too, whichever
        -- money the tab is showing: an alt's gold can't pay for training here
        -- until it's been sent over.
        local ownIncome, ownSpending = income, spending
        if accountWide then
            ownIncome, ownSpending = ns.Purse.Averages(AVERAGE_DAYS, false)
        end
        verdict:SetText(Verdict(own, ownIncome, ownSpending, costs))
    end

    return tab
end
