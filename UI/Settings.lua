local _, ns = ...

-- Goldwise's page in the game's own Options window.
--
-- Everything works without a visit here. These are for people who want to
-- change how it behaves.

-- Adds a tick box bound to one key of the saved settings.
local function AddCheckbox(category, key, label, tooltip)
    local setting = Settings.RegisterAddOnSetting(
        category,
        "Goldwise_" .. key,
        key,
        ns.settings,
        Settings.VarType.Boolean,
        label,
        ns.DEFAULT_SETTINGS[key]
    )
    Settings.CreateCheckbox(category, setting, tooltip)

    Settings.SetOnValueChangedCallback("Goldwise_" .. key, function()
        ns.Publish("SETTINGS_CHANGED")
    end)
end

-- Adds a dropdown bound to one numeric key of the saved settings.
-- `choices` is a list of { value, label }.
local function AddDropdown(category, key, label, tooltip, choices)
    local setting = Settings.RegisterAddOnSetting(
        category,
        "Goldwise_" .. key,
        key,
        ns.settings,
        Settings.VarType.Number,
        label,
        ns.DEFAULT_SETTINGS[key]
    )

    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(choices) do
            container:Add(choice[1], choice[2])
        end
        return container:GetData()
    end, tooltip)

    Settings.SetOnValueChangedCallback("Goldwise_" .. key, function()
        ns.Publish("SETTINGS_CHANGED")
    end)
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
    category = Settings.RegisterVerticalLayoutCategory("Goldwise")

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
        "vendorCheck",
        "Check my bags when I open a merchant",
        "A short note if you're carrying things that would fetch a good deal more at auction."
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
        "One line with the lowest price and how many are listed. Skipped when "
            .. "another addon, such as Auctionator, already shows a price there."
    )

    AddCheckbox(
        category,
        "tooltipChart",
        "Show a price chart under item tooltips",
        "A small two-week trend. Appears once an item has a few days of history."
    )

    AddCheckbox(
        category,
        "tooltipHeld",
        "Show how many your other characters hold",
        "Counts their bags as of their last login. Left to Bagnon if you have that installed."
    )

    AddCheckbox(
        category,
        "auditorMode",
        "Auditor mode",
        "The goblin delivers the same advice at full volume. The facts don't change."
    )

    Settings.RegisterAddOnCategory(category)
end)
