local _, ns = ...

-- Goldwise's page in the game's own Options window.
--
-- Everything works without a visit here. These are for people who want to
-- change how it behaves.

-- Ties one key of the saved settings to the Options window, so a change
-- made there goes straight into it and the rest of Goldwise hears.
local function RegisterSetting(category, key, varType, label)
    local variable = "Goldwise_" .. key
    local setting = Settings.RegisterAddOnSetting(
        category,
        variable,
        key,
        ns.settings,
        varType,
        label,
        ns.DEFAULT_SETTINGS[key]
    )
    Settings.SetOnValueChangedCallback(variable, function()
        ns.Publish("SETTINGS_CHANGED")
    end)
    return setting
end

-- Adds a tick box bound to one key of the saved settings.
local function AddCheckbox(category, key, label, tooltip)
    local setting = RegisterSetting(category, key, Settings.VarType.Boolean, label)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- Adds a dropdown bound to one numeric key of the saved settings.
-- `choices` is a list of { value, label }.
local function AddDropdown(category, key, label, tooltip, choices)
    local setting = RegisterSetting(category, key, Settings.VarType.Number, label)
    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(choices) do
            container:Add(choice[1], choice[2])
        end
        return container:GetData()
    end, tooltip)
end

-- Past this many, the dismissed recipes' tooltip sums up the rest.
local MAX_NAMES_LISTED = 12

-- What the dismissed-recipes button says when the mouse is on it: the
-- recipes themselves, so the player can see what they'd be bringing back.
local function IgnoredRecipesTooltip()
    local names = ns.Recipes.IgnoredNames()
    if #names == 0 then
        return "None yet. Click the X beside a recipe on the recipe card and Goldwise "
            .. "won't mention it again."
    end

    local listed = {}
    for index = 1, math.min(#names, MAX_NAMES_LISTED) do
        listed[index] = names[index]
    end
    if #names > MAX_NAMES_LISTED then
        table.insert(listed, ("and %d more"):format(#names - MAX_NAMES_LISTED))
    end
    return ("Goldwise no longer mentions these:\n%s\n\nThey're still on the Recipes tab."):format(
        table.concat(listed, "\n")
    )
end

-- Our page, once it exists. Kept so it can be opened directly.
local category

--- Opens the game's Options window on Goldwise's page.
function ns.OpenOptions()
    -- The Options window is one of the panels the game won't let addons
    -- open during combat.
    if InCombatLockdown() then
        ns.Print("Options can't be opened in combat. Try again in a moment.")
        return
    end

    if category then
        Settings.OpenToCategory(category:GetID())
    end
end

-- Registered at login rather than when the addon loads, so the Options
-- window has finished setting itself up.
ns.OnEvent("PLAYER_LOGIN", function()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Goldwise")

    AddCheckbox(
        category,
        "minimapButton",
        "Show the minimap button",
        "Left-click it to open Goldwise, right-click for these options. "
            .. "You can also type /gw."
    )

    AddCheckbox(
        category,
        "cityPrompt",
        "Tell me when an auction house is worth a visit",
        "Once per visit, when you arrive somewhere with an auction house and your prices "
            .. "are a day old or your bags hold something worth listing."
    )

    AddCheckbox(
        category,
        "recipePrompt",
        "Tell me when a vendor nearby sells a recipe I can use",
        "Once per zone each session, for recipes you haven't learned in the professions "
            .. "you have, when your skill is high enough or nearly so. The X beside a "
            .. "recipe on that card stops it being mentioned again."
    )

    -- The recipes waved away with the X on the recipe card, and a way to
    -- have them back.
    layout:AddInitializer(
        CreateSettingsButtonInitializer("Recipes you've dismissed", "Bring them back", function()
            -- The tooltip lists what's being brought back. Once it has
            -- been, the list is out of date.
            SettingsTooltip:Hide()
            local count = ns.Recipes.ClearIgnored()
            if count == 0 then
                ns.Print("You haven't dismissed any recipes.")
            else
                ns.Print(
                    "%d %s can be mentioned again.",
                    count,
                    count == 1 and "recipe" or "recipes"
                )
            end
        end, IgnoredRecipesTooltip, true)
    )

    -- Where those cards come up. A sample is put out to drag, with the
    -- options out of the way so the screen can be seen.
    layout:AddInitializer(
        CreateSettingsButtonInitializer("Where cards appear", "Move them", function()
            HideUIPanel(SettingsPanel)
            ns.Toast.ShowSample()
        end, function()
            return "Puts out a card to drag where you'd like Goldwise's suggestions to "
                .. "appear. You can also drag any card that comes up."
        end, true)
    )

    AddCheckbox(
        category,
        "sessionTracker",
        "Show the session tracker",
        "A small panel to keep on screen: what this session has earned or lost, and what "
            .. "your bags are worth at the prices Goldwise would sell them for. The Session "
            .. "button on the Goldwise window and /gw session do the same."
    )

    AddCheckbox(
        category,
        "vendorCheck",
        "Check my bags when I open a merchant",
        "A short note if you're carrying things that would fetch a good deal more at auction."
    )

    AddCheckbox(
        category,
        "markSellable",
        "Mark items worth auctioning in my bags and bank",
        "A gold rim and a coin on anything Goldwise would tell you to sell at the auction "
            .. "house. Works in the default bags and bank and in bag addons such as Bagnon."
    )

    AddCheckbox(
        category,
        "promptSound",
        "Play a sound with those prompts",
        "Off unless you turn it on. Goldwise is otherwise silent."
    )

    AddCheckbox(
        category,
        "autoScan",
        "Read prices when the auction house opens",
        "Takes about fifteen seconds and steps aside if you start searching. "
            .. "Skipped if prices were read in the last quarter of an hour."
    )

    AddCheckbox(
        category,
        "scanPanel",
        "Show what's being read at the auction house",
        "A small panel on top of the auction house window: how far the reading has got, "
            .. "what it found, and what your bags would sell for. Click it to open Goldwise."
    )

    AddCheckbox(
        category,
        "deepScan",
        "Read every auction when possible",
        "A fuller read that shows how many are listed at each price. "
            .. "The game allows it once every 15 minutes; otherwise the quick read is used."
    )

    AddDropdown(
        category,
        "historyDays",
        "Keep price history for",
        "How far back Goldwise remembers what your own game has read at the auction "
            .. "house, for the items you carry or follow. Longer makes for longer charts "
            .. "and a larger saved file. Shortening it takes effect the next time you log in.",
        {
            { 30, "30 days" },
            { 90, "90 days" },
            { 180, "6 months" },
            { 365, "1 year" },
        }
    )

    AddCheckbox(
        category,
        "sharePrices",
        "Share prices with other Goldwise players",
        "Whoever visited the auction house last keeps everyone's prices fresh, over a "
            .. "hidden chat channel. Only prices are exchanged, and only a few messages at a time."
    )

    AddCheckbox(
        category,
        "tooltipPrice",
        "Show auction prices on item tooltips",
        "The lowest price and how many are listed, on a line marked Goldwise. Left "
            .. "off when another addon, such as Auctionator, is already showing a "
            .. "price for that item."
    )

    AddCheckbox(
        category,
        "tooltipVerdict",
        "Show the verdict on things in your bags",
        "Sell, Hold, Vendor or Keep, on the same line: what the Assets tab says "
            .. "about it, where you're looking."
    )

    AddCheckbox(
        category,
        "tooltipChart",
        "Show a price chart under item tooltips",
        "A small two-week trend, marked Goldwise. Appears once an item has two days "
            .. "of history."
    )

    AddCheckbox(
        category,
        "tooltipHeld",
        "Show how many your other characters hold",
        "Counts their bags as of their last login. Left to Bagnon or Profession Atlas "
            .. "when one of them is already listing it."
    )

    AddCheckbox(
        category,
        "tooltipTree",
        "Show how to open an item's crafting tree",
        "One line, only on things you can make or make something from."
    )

    AddCheckbox(
        category,
        "auditorMode",
        "Auditor mode",
        "The goblin delivers the same advice at full volume. The facts don't change."
    )

    Settings.RegisterAddOnCategory(category)

    -- The click and the keys have a page of their own beneath this one.
    ns.Shortcuts.Register(category)
end)
